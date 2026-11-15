/// Adaptateur MangaDex : lecture via l'API publique officielle
/// `https://api.mangadex.org` (PLAYBOOK.md section 6, « Cas particulier :
/// MangaDex »).
///
/// Sources consultées le 2026-11-15 (aucun point d'accès écrit de mémoire) :
/// - spécification OpenAPI 5.13.1 : https://api.mangadex.org/docs/static/api.yaml
/// - limites : https://api.mangadex.org/docs/2-limitations/
/// - codes de langue : https://api.mangadex.org/docs/3-enumerations/
/// - pagination : https://api.mangadex.org/docs/01-concepts/pagination/
/// - couvertures : https://api.mangadex.org/docs/03-manga/covers/
/// - images : https://api.mangadex.org/docs/04-chapter/retrieving-chapter/
/// - chapitres : https://api.mangadex.org/docs/04-chapter/feed/
///
/// Règles d'usage retenues (docs/2-limitations) :
/// - User-Agent obligatoire et non usurpé → [userAgentApplication] ;
/// - environ 5 requêtes/s par IP au total → la règle « 1 s par domaine » de
///   `ClientHttpPoli` est plus stricte ;
/// - `GET /at-home/server/{id}` : 40 requêtes/minute →
///   [delaiMinimalAtHomeMangaDex] ;
/// - HTTP 429 puis bannissement temporaire (403) si l'on insiste → les
///   nouvelles tentatives sont limitées et respectent `X-RateLimit-Retry-After` ;
/// - `offset + limit > 10 000` est refusé → [plafondOffsetMangaDex].
library;

import '../modeles/chapitre.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/titre.dart';
import '../modeles/titre_alternatif.dart';
import 'client_http_poli.dart';
import 'constantes_sources.dart';
import 'erreur_source.dart';
import 'lecture_json.dart';
import 'source_site.dart';

/// Lecture de MangaDex par son API JSON (le HTML du site est construit en
/// JavaScript et ne contient pas les données).
class SourceMangaDex implements SourceSite {
  /// Crée l'adaptateur.
  ///
  /// - [languesChapitres] : codes de langue MangaDex (`en`, `fr`, `pt-br`…)
  ///   pour filtrer les chapitres ; vide = toutes les langues.
  /// - [languesPreferees] : ordre de préférence pour choisir le résumé.
  /// - [qualiteReduite] : `true` pour les images compressées (`data-saver`).
  /// - [taillePageChapitres] : taille d'une page du flux de chapitres
  ///   (maximum 500 d'après api.yaml) ; modifiable pour les tests.
  SourceMangaDex(
    this._client, {
    List<String> languesChapitres = const <String>[],
    List<String> languesPreferees = const <String>['fr', 'en'],
    this.qualiteReduite = false,
    this.taillePageChapitres = taillePageMaxFluxMangaDex,
  }) : languesChapitres = List<String>.unmodifiable(languesChapitres),
       languesPreferees = List<String>.unmodifiable(languesPreferees);

  final ClientHttpPoli _client;

  /// Langues de chapitres demandées à l'API (vide = toutes).
  final List<String> languesChapitres;

  /// Langues préférées pour le résumé, dans l'ordre.
  final List<String> languesPreferees;

  /// `true` pour les images `data-saver` plutôt que `data`.
  final bool qualiteReduite;

  /// Nombre de chapitres demandés par page du flux.
  final int taillePageChapitres;

  static final RegExp _motifUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  /// Toutes les valeurs de `contentRating[]` (api.yaml, énumération
  /// safe/suggestive/erotica/pornographic). Sans ce paramètre, l'API applique
  /// le défaut `[safe, suggestive, erotica]` et un titre que le client suit
  /// déjà pourrait renvoyer un flux vide sans erreur.
  static const List<String> _toutesClassifications = <String>[
    'safe',
    'suggestive',
    'erotica',
    'pornographic',
  ];

  // ---------------------------------------------------------------------
  // Extraction des identifiants
  // ---------------------------------------------------------------------

  /// Indique si [hote] est le site MangaDex (`mangadex.org` ou
  /// `www.mangadex.org`).
  static bool estHoteMangaDex(String hote) {
    final h = hote.toLowerCase();
    return h == domaineMangaDex || h == 'www.$domaineMangaDex';
  }

  /// Extrait l'UUID d'un titre depuis
  /// `https://mangadex.org/title/<uuid>/<nom-lisible>` (le nom lisible est
  /// facultatif). Lève une [ErreurSource] si l'URL ne correspond pas.
  static String extraireIdTitre(String urlTitre) =>
      _extraireUuid(urlTitre, 'title');

  /// Extrait l'UUID d'un chapitre depuis `https://mangadex.org/chapter/<uuid>`.
  /// Lève une [ErreurSource] si l'URL ne correspond pas.
  static String extraireIdChapitre(String urlChapitre) =>
      _extraireUuid(urlChapitre, 'chapter');

  static String _extraireUuid(String url, String segmentAttendu) {
    final uri = Uri.tryParse(url.trim());
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        estHoteMangaDex(uri.host)) {
      final segments = uri.pathSegments;
      if (segments.length >= 2 &&
          segments[0] == segmentAttendu &&
          _motifUuid.hasMatch(segments[1])) {
        return segments[1].toLowerCase();
      }
    }
    throw ErreurSource(
      url,
      'URL MangaDex invalide : https://$domaineMangaDex/$segmentAttendu/<uuid> '
      'attendu',
    );
  }

  /// URL publique d'un titre, rangée dans `Titre.urlTitre`.
  ///
  /// LIMITE : l'API ne fournit pas le « nom lisible » qui suit l'UUID dans les
  /// URLs du site ; l'URL sans ce suffixe reste valide pour
  /// [extraireIdTitre].
  static String urlTitreDepuisId(String id) =>
      'https://$domaineMangaDex/title/$id';

  /// URL publique d'un chapitre, rangée dans `Chapitre.urlChapitre`.
  static String urlChapitreDepuisId(String id) =>
      'https://$domaineMangaDex/chapter/$id';

  // ---------------------------------------------------------------------
  // SourceSite
  // ---------------------------------------------------------------------

  /// Recherche par titre : `GET /manga?title=…` (api.yaml, operationId
  /// `get-search-manga` ; docs/03-manga/search).
  ///
  /// Une requête vide ou faite d'espaces renvoie une liste vide sans appel
  /// réseau. La classification par défaut de l'API s'applique (les titres
  /// pornographiques sont masqués, comme sur le site).
  @override
  Future<List<Titre>> rechercher(String requete) async {
    final texte = requete.trim();
    if (texte.isEmpty) {
      return const <Titre>[];
    }
    final uri = Uri.https(domaineApiMangaDex, '/manga', <String, Object>{
      'title': texte,
      'limit': '$taillePageRechercheMangaDex',
      // Reference expansion (docs/01-concepts/reference-expansion) : évite
      // une requête par titre pour la couverture et l'auteur.
      'includes[]': <String>['cover_art', 'author', 'artist'],
    });
    final json = await _recupererJson(uri);
    final url = uri.toString();
    return <Titre>[
      for (final manga in json.lireListeObjets('data', url))
        _construireTitre(manga, url),
    ];
  }

  /// Fiche d'un titre : `GET /manga/{id}?includes[]=cover_art&includes[]=author
  /// &includes[]=artist` (api.yaml, operationId `get-manga-id` ; paramètre
  /// `includes[]` = `ReferenceExpansionManga`).
  @override
  Future<FicheTitre> recupererFiche(String urlTitre) async {
    final id = extraireIdTitre(urlTitre);
    final uri = Uri.https(domaineApiMangaDex, '/manga/$id', <String, Object>{
      'includes[]': <String>['cover_art', 'author', 'artist'],
    });
    final json = await _recupererJson(uri);
    final url = uri.toString();
    final manga = json.lireObjet('data', url);
    final attributs = manga.lireObjet('attributes', url);

    // Catégories = tags du titre (MangaAttributes.tags → Tag.attributes.name,
    // un LocalizedString). Les tags MangaDex ont un nom anglais ; on prend
    // sinon le premier nom disponible.
    final categories = <String>[];
    for (final tag in attributs.lireListeObjets('tags', url)) {
      final noms = tag
          .lireObjet('attributes', url)
          .lireTextesLocalises('name', url);
      final nom = noms['en'] ?? (noms.isEmpty ? null : noms.values.first);
      if (nom != null && nom.trim().isNotEmpty) {
        categories.add(nom.trim());
      }
    }
    return FicheTitre(
      titre: _construireTitre(manga, url),
      categories: categories,
    );
  }

  /// Tous les chapitres d'un titre : `GET /manga/{id}/feed` (api.yaml,
  /// operationId `get-manga-id-feed`, paramètres `feedParameters`),
  /// parcouru page par page avec `limit`/`offset`/`total`
  /// (docs/01-concepts/pagination).
  ///
  /// Paramètres envoyés :
  /// - `order[chapter]=asc` puis `order[createdAt]=asc` : tri par numéro,
  ///   départagé par date de création. LIMITE : la doc ne garantit pas que
  ///   ce tri soit total ni stable entre deux requêtes (ajouts pendant la
  ///   lecture) ; les doublons éventuels sont donc retirés par UUID ;
  /// - `contentRating[]` : toutes les classifications (voir
  ///   [_toutesClassifications]) ;
  /// - `includeExternalUrl=0` : un chapitre hébergé ailleurs n'a pas de pages
  ///   sur MangaDex et ne pourrait pas être téléchargé ;
  /// - `includeFuturePublishAt=0` et `includeEmptyPages=0` : on ne signale
  ///   pas un chapitre qui ne peut pas encore être lu ;
  /// - `translatedLanguage[]` si [languesChapitres] n'est pas vide.
  ///
  /// Lève une [ErreurSource] si le flux dépasse le plafond de 10 000
  /// résultats de l'API (il faut alors filtrer par langue).
  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) async {
    final id = extraireIdTitre(urlTitre);
    final chapitres = <Chapitre>[];
    // Un chapitre ajouté ou retiré pendant la lecture des pages décale les
    // offsets : la même entrée peut revenir sur deux pages. On ne la garde
    // qu'une fois (l'UUID est unique, comme `url_chapitre` en base).
    final idsVus = <String>{};
    var offset = 0;
    while (true) {
      final restantAvantPlafond = plafondOffsetMangaDex - offset;
      final limit = taillePageChapitres < restantAvantPlafond
          ? taillePageChapitres
          : restantAvantPlafond;
      final uri = Uri.https(
        domaineApiMangaDex,
        '/manga/$id/feed',
        <String, Object>{
          'limit': '$limit',
          'offset': '$offset',
          'order[chapter]': 'asc',
          // Départage des chapitres de même numéro (plusieurs langues ou
          // groupes) : api.yaml, feedParameters.order accepte `createdAt`.
          'order[createdAt]': 'asc',
          'contentRating[]': _toutesClassifications,
          'includeExternalUrl': '0',
          'includeFuturePublishAt': '0',
          'includeEmptyPages': '0',
          if (languesChapitres.isNotEmpty)
            'translatedLanguage[]': languesChapitres,
        },
      );
      final url = uri.toString();
      final json = await _recupererJson(uri);
      final donnees = json.lireListeObjets('data', url);
      final total = json.lireEntier('total', url);
      // Dès la première page, `total` dit si l'on atteindra le plafond : inutile
      // de lire 20 pages pour échouer ensuite.
      if (total > plafondOffsetMangaDex) {
        throw ErreurSource(
          urlTitre,
          'Trop de chapitres ($total) : l\'API MangaDex refuse de dépasser '
          '$plafondOffsetMangaDex résultats. Choisir une langue de chapitres '
          'pour cette source.',
        );
      }
      for (final chapitre in donnees) {
        if (idsVus.add(chapitre.lireTexte('id', url))) {
          chapitres.add(_construireChapitre(chapitre, url));
        }
      }
      offset += donnees.length;
      // Page vide : l'API a fini (docs/01-concepts/pagination : un offset au
      // delà du total renvoie une collection vide). On s'arrête aussi pour ne
      // jamais boucler indéfiniment si `total` est incohérent.
      if (donnees.isEmpty ||
          offset >= total ||
          offset >= plafondOffsetMangaDex) {
        break;
      }
    }
    return chapitres;
  }

  /// URLs des images d'un chapitre : `GET /at-home/server/{chapterId}`
  /// (api.yaml, operationId `get-at-home-server-chapterId`), puis
  /// `<baseUrl>/<data|data-saver>/<chapter.hash>/<fichier>`
  /// (docs/04-chapter/retrieving-chapter).
  ///
  /// LIMITE : `baseUrl` n'est garanti que 15 minutes (« We guarantee 15
  /// minutes ») ; passé ce délai, il faut rappeler cette méthode.
  /// LIMITE : la doc demande de signaler chaque image chargée depuis un
  /// serveur MangaDex@Home à `POST https://api.mangadex.network/report` ; ce
  /// signalement relève du téléchargement (service), pas de cet adaptateur.
  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) async {
    final id = extraireIdChapitre(urlChapitre);
    final uri = Uri.https(domaineApiMangaDex, '/at-home/server/$id');
    final json = await _recupererJson(
      uri,
      limite: const LimiteRequetes(
        '$domaineApiMangaDex/at-home/server',
        delaiMinimalAtHomeMangaDex,
      ),
    );
    final url = uri.toString();
    // La doc insiste : « Do NOT assume any format [...] Just use it as-is ».
    // On concatène donc baseUrl tel quel au lieu d'utiliser Uri.resolve (qui
    // supprimerait le dernier segment d'un baseUrl sans « / » final).
    final baseUrl = json.lireTexte('baseUrl', url);
    final chapitre = json.lireObjet('chapter', url);
    final hash = chapitre.lireTexte('hash', url);
    final qualite = qualiteReduite ? 'data-saver' : 'data';
    final fichiers = chapitre.lireListeTextes(
      qualiteReduite ? 'dataSaver' : 'data',
      url,
    );
    if (fichiers.isEmpty) {
      throw ErreurSource(
        urlChapitre,
        'Aucune page disponible sur MangaDex pour ce chapitre '
        '(chapitre externe ou retiré)',
      );
    }
    // Pas de Referer : la doc MangaDex n'en exige pas pour les images et
    // interdit seulement les en-têtes d'authentification.
    return ContenuChapitre.images(<String>[
      for (final fichier in fichiers) '$baseUrl/$qualite/$hash/$fichier',
    ]);
  }

  // ---------------------------------------------------------------------
  // Conversion JSON → modèles
  // ---------------------------------------------------------------------

  /// Convertit un code de langue MangaDex en code ISO 639-1 (ou vide).
  ///
  /// docs/3-enumerations : les codes sont ISO 639-1, parfois suivis d'une
  /// région (`pt-br`, `es-la`, `zh-hk`) ; le suffixe `-ro` désigne une
  /// romanisation (`ja-ro`), qui n'a pas de code ISO 639-1.
  /// Choix : région → on garde la langue (`pt-br` → `pt`) ; romanisation ou
  /// code inconnu → langue vide (`TitreAlternatif.langue` l'autorise).
  static String convertirCodeLangue(String code) {
    final c = code.trim().toLowerCase();
    if (RegExp(r'^[a-z]{2}$').hasMatch(c)) {
      return c;
    }
    if (RegExp(r'^[a-z]{2}-ro$').hasMatch(c)) {
      return '';
    }
    if (RegExp(r'^[a-z]{2}-[a-z]{2}$').hasMatch(c)) {
      return c.substring(0, 2);
    }
    return '';
  }

  /// Déduit le type du titre de sa langue d'origine (`originalLanguage`).
  ///
  /// LIMITE : la doc MangaDex ne définit pas de champ « type » (manga, manhwa,
  /// manhua) ; la correspondance ja → manga, ko → manhwa, zh/zh-hk → manhua
  /// est une convention d'usage, pas une règle de l'API. Autre langue → autre.
  static TypeTitre typeDepuisLangueOriginale(String? langue) {
    switch (langue?.toLowerCase()) {
      case 'ja':
        return TypeTitre.manga;
      case 'ko':
        return TypeTitre.manhwa;
      case 'zh':
      case 'zh-hk':
        return TypeTitre.manhua;
      default:
        return TypeTitre.autre;
    }
  }

  /// Construit un [Titre] depuis un objet `Manga` de l'API (api.yaml,
  /// schémas `Manga`, `MangaAttributes`, `Relationship`).
  Titre _construireTitre(Map<String, Object?> manga, String url) {
    final id = manga.lireTexte('id', url);
    final attributs = manga.lireObjet('attributes', url);

    // Titre principal : `title` est un LocalizedString qui contient en
    // pratique une seule entrée (ici `ja-ro`) ; on prend la première.
    final titres = attributs.lireTextesLocalises('title', url);
    final nom = titres.isEmpty ? '' : titres.values.first.trim();
    if (nom.isEmpty) {
      throw ErreurSource(url, 'Titre MangaDex sans nom (id $id)');
    }

    // altTitles : liste de LocalizedString, une entrée par objet en pratique
    // mais on les parcourt toutes. Les doublons (même nom) sont ignorés :
    // la table titres_alternatifs impose UNIQUE(id_titre, nom).
    final alternatifs = <TitreAlternatif>[];
    final nomsVus = <String>{nom};
    for (final objet in attributs.lireListeObjets('altTitles', url)) {
      for (final entree in objet.entries) {
        final valeur = entree.value;
        if (valeur is! String) {
          continue;
        }
        final alt = valeur.trim();
        if (alt.isEmpty || !nomsVus.add(alt)) {
          continue;
        }
        alternatifs.add(
          TitreAlternatif(nom: alt, langue: convertirCodeLangue(entree.key)),
        );
      }
    }

    final description = attributs.lireTextesLocalises('description', url);
    String? resume;
    for (final langue in languesPreferees) {
      final texte = description[langue]?.trim();
      if (texte != null && texte.isNotEmpty) {
        resume = texte;
        break;
      }
    }
    if (resume == null && description.isNotEmpty) {
      final texte = description.values.first.trim();
      resume = texte.isEmpty ? null : texte;
    }

    // Relations développées par `includes[]` : author, artist, cover_art
    // (docs/3-enumerations, « Relationship types »). Sans développement,
    // `attributes` est absent : on ignore alors la relation.
    final auteurs = <String>[];
    final artistes = <String>[];
    String? urlCouverture;
    for (final relation in manga.lireListeObjets('relationships', url)) {
      final type = relation.lireTexte('type', url);
      final attributsRelation = relation.lireObjetOptionnel('attributes', url);
      if (attributsRelation == null) {
        continue;
      }
      switch (type) {
        case 'author':
          final n = attributsRelation.lireTexteOptionnel('name', url)?.trim();
          if (n != null && n.isNotEmpty && !auteurs.contains(n)) {
            auteurs.add(n);
          }
        case 'artist':
          final n = attributsRelation.lireTexteOptionnel('name', url)?.trim();
          if (n != null && n.isNotEmpty && !artistes.contains(n)) {
            artistes.add(n);
          }
        case 'cover_art':
          // docs/03-manga/covers : https://uploads.mangadex.org/covers/
          // :manga-id/:cover-filename (CoverAttributes.fileName).
          final fichier = attributsRelation.lireTexteOptionnel('fileName', url);
          if (fichier != null && fichier.isNotEmpty) {
            urlCouverture =
                'https://$domaineCouverturesMangaDex/covers/$id/$fichier';
          }
      }
    }
    // Le modèle n'a qu'un champ « auteur » : on y met les auteurs (scénario),
    // ou à défaut les artistes (dessin).
    final createurs = auteurs.isNotEmpty ? auteurs : artistes;

    return Titre(
      urlTitre: urlTitreDepuisId(id),
      nom: nom,
      typeTitre: typeDepuisLangueOriginale(
        attributs.lireTexteOptionnel('originalLanguage', url),
      ),
      urlCouverture: urlCouverture,
      resume: resume,
      auteur: createurs.isEmpty ? null : createurs.join(', '),
      // Valeur brute de l'API (ongoing, completed, hiatus, cancelled —
      // docs/3-enumerations « Manga status ») : le modèle garde le statut
      // « tel quel » ; la traduction relève de l'interface.
      statut: attributs.lireTexteOptionnel('status', url),
      titresAlternatifs: alternatifs,
    );
  }

  /// Construit un [Chapitre] depuis un objet `Chapter` de l'API (api.yaml,
  /// schéma `ChapterAttributes`).
  Chapitre _construireChapitre(Map<String, Object?> chapitre, String url) {
    final id = chapitre.lireTexte('id', url);
    final attributs = chapitre.lireObjet('attributes', url);
    // `chapter` est un texte nullable (maxLength 8) : null pour un oneshot.
    final numeroTexte = attributs.lireTexteOptionnel('chapter', url)?.trim();
    final titre = attributs.lireTexteOptionnel('title', url)?.trim() ?? '';
    final String nom;
    if (numeroTexte == null || numeroTexte.isEmpty) {
      nom = titre.isEmpty ? 'Oneshot' : titre;
    } else {
      nom = titre.isEmpty
          ? 'Chapitre $numeroTexte'
          : 'Chapitre $numeroTexte : $titre';
    }
    final publication = attributs.lireTexteOptionnel('publishAt', url);
    return Chapitre(
      urlChapitre: urlChapitreDepuisId(id),
      nom: nom,
      numero: convertirNumero(numeroTexte),
      langue: convertirCodeLangue(
        attributs.lireTexteOptionnel('translatedLanguage', url) ?? '',
      ),
      // docs/01-concepts/timestamps : dates RFC 3339, en UTC si non précisé.
      datePublication: publication == null
          ? null
          : DateTime.tryParse(publication)?.toUtc(),
    );
  }

  /// Convertit le numéro de chapitre MangaDex (texte) en double.
  ///
  /// `null` ou vide (oneshot) → 0. LIMITE : le format exact du champ n'est pas
  /// documenté (seulement « maxLength: 8 ») ; on lit le premier nombre trouvé
  /// (« 10.5 », « 12a » → 12) et 0 si aucun.
  ///
  /// `double.tryParse` accepte aussi « NaN », « Infinity » et « 1e3 », qui ne
  /// sont pas des numéros de chapitre : seule la forme décimale simple
  /// (chiffres, éventuellement « . » ou « , » puis chiffres) est lue. Un texte
  /// en notation scientifique ou non fini donne 0.
  static double convertirNumero(String? texte) {
    if (texte == null) {
      return 0;
    }
    final t = texte.trim();
    // Notation scientifique (« 1e3 », « 2.5E-1 ») : refusée plutôt que lue
    // comme « 1 » ou « 1000 ».
    if (RegExp(r'\d[eE][+-]?\d').hasMatch(t)) {
      return 0;
    }
    final correspondance = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(t);
    if (correspondance == null) {
      return 0;
    }
    final valeur = double.parse(correspondance.group(0)!.replaceAll(',', '.'));
    return valeur.isFinite ? valeur : 0;
  }

  /// Variantes régionales des langues de chapitres (`translatedLanguage`)
  /// listées par docs/3-enumerations : `zh-hk`, `pt-br`, `es-la`.
  ///
  /// Les romanisations (`ja-ro`, `ko-ro`, `zh-ro`) ne sont pas ajoutées : la
  /// doc les décrit pour les titres, et ce ne sont pas des traductions dans la
  /// langue demandée.
  static const Map<String, List<String>> _variantesRegionales =
      <String, List<String>>{
        'pt': <String>['pt', 'pt-br'],
        'es': <String>['es', 'es-la'],
        'zh': <String>['zh', 'zh-hk'],
      };

  /// Codes `translatedLanguage[]` à demander pour une langue ISO 639-1
  /// (`pt` → `pt`, `pt-br`). Une langue sans variante donne `[langue]` ; une
  /// langue vide donne une liste vide (toutes les langues).
  static List<String> languesApiDepuisIso(String langue) {
    final l = langue.trim().toLowerCase();
    if (l.isEmpty) {
      return const <String>[];
    }
    return _variantesRegionales[l] ?? <String>[l];
  }

  /// Récupère [uri] en JSON et vérifie le champ `result` (api.yaml :
  /// `result` vaut `ok` ou `error`, avec `errors[].detail`).
  Future<Map<String, Object?>> _recupererJson(
    Uri uri, {
    LimiteRequetes? limite,
  }) async {
    final url = uri.toString();
    final texte = await _client.recupererTexte(
      uri,
      userAgent: userAgentApplication,
      enTetes: const <String, String>{'Accept': 'application/json'},
      limite: limite,
    );
    final json = decoderObjetJson(texte, url);
    final resultat = json.lireTexteOptionnel('result', url);
    if (resultat != 'ok') {
      final details = <String>[];
      final erreurs = json['errors'];
      if (erreurs is List<Object?>) {
        for (final erreur in erreurs) {
          if (erreur is Map<String, Object?>) {
            final detail = erreur['detail'] ?? erreur['title'];
            if (detail is String) {
              details.add(detail);
            }
          }
        }
      }
      throw ErreurSource(
        url,
        'Réponse MangaDex en erreur (result : $resultat)'
        '${details.isEmpty ? '' : ' : ${details.join(' ; ')}'}',
      );
    }
    return json;
  }
}
