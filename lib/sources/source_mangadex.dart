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
/// Ajouts de l'étape 6, vérifiés le 2026-11-16 dans la même spécification
/// (api.yaml 5.13.1, téléchargée hors du projet) :
/// - `MangaAttributes.contentRating` : « type: string, enum: safe,
///   suggestive, erotica, pornographic » → `Titre.niveauContenu` ;
/// - `GET /manga` (operationId `get-search-manga`), paramètre
///   `contentRating[]` : « type: array, default: [safe, suggestive,
///   erotica] », même énumération → filtre de [rechercher] ;
///   docs/03-manga/search : « Pornographic titles are hidden by default » ;
/// - `GET /cover` (operationId `get-cover`, réponse `CoverList`) : paramètres
///   `manga[]` (« Manga ids (limited to 100 per request) »), `limit`
///   (« default: 10, maximum: 100 »), `offset`, `order[volume]` (asc/desc) ;
///   `CoverAttributes` : `volume` (nullable), `fileName`, `locale`
///   (nullable) → [recupererCouvertures] ;
///   docs/03-manga/covers : « All covers for a manga : Using the GET /cover
///   endpoint », miniatures `…/:cover-filename.{256, 512}.jpg`.
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

import 'package:flutter/foundation.dart';

import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../modeles/titre_alternatif.dart';
import 'client_http_poli.dart';
import 'constantes_sources.dart';
import 'couverture_site.dart';
import 'erreur_source.dart';
import 'journal_sources.dart';
import 'lecture_json.dart';
import 'outils_sources.dart';
import 'rapport_erreur_source.dart';
import 'sites_externes.dart' as sites_externes;
import 'source_site.dart';

/// Lecture de MangaDex par son API JSON (le HTML du site est construit en
/// JavaScript et ne contient pas les données).
///
/// Toute [ErreurSource] levée par ses méthodes publiques porte
/// `typeDetecte == TypeSource.mangaDex` et, quand une réponse a été reçue,
/// son début nettoyé (`extraitReponse`) pour le rapport d'erreur.
class SourceMangaDex implements SourceSite, SourceAvecCouvertures {
  /// Crée l'adaptateur.
  ///
  /// - [languesChapitres] : codes de langue MangaDex (`en`, `fr`, `pt-br`…)
  ///   pour filtrer les chapitres ; vide = toutes les langues.
  /// - [languesPreferees] : ordre de préférence pour choisir le résumé.
  /// - [qualiteReduite] : `true` pour les images compressées (`data-saver`).
  /// - [taillePageChapitres] : taille d'une page du flux de chapitres
  ///   (maximum 500 d'après api.yaml) ; modifiable pour les tests.
  /// - [niveauxContenuRecherche] : niveaux de contenu (`contentRating`)
  ///   acceptés par [rechercher], parmi `niveauxContenu`
  ///   (lib/modeles/constantes.dart). `null` = défaut de l'API (tout sauf
  ///   `pornographic`) ; liste vide = aucun résultat possible. Un niveau
  ///   inconnu de l'API lève une [ArgumentError] (erreur de programmation,
  ///   pas d'échec du site).
  SourceMangaDex(
    this._client, {
    List<String> languesChapitres = const <String>[],
    List<String> languesPreferees = const <String>['fr', 'en'],
    this.qualiteReduite = false,
    this.taillePageChapitres = taillePageMaxFluxMangaDex,
    List<String>? niveauxContenuRecherche,
  }) : languesChapitres = List<String>.unmodifiable(languesChapitres),
       languesPreferees = List<String>.unmodifiable(languesPreferees),
       niveauxContenuRecherche = niveauxContenuRecherche == null
           ? null
           : List<String>.unmodifiable(
               _validerNiveaux(niveauxContenuRecherche),
             );

  final ClientHttpPoli _client;

  /// Langues de chapitres demandées à l'API (vide = toutes).
  final List<String> languesChapitres;

  /// Langues préférées pour le résumé, dans l'ordre.
  final List<String> languesPreferees;

  /// `true` pour les images `data-saver` plutôt que `data`.
  final bool qualiteReduite;

  /// Nombre de chapitres demandés par page du flux.
  final int taillePageChapitres;

  /// Niveaux de contenu acceptés par [rechercher] (`null` = défaut de l'API,
  /// qui masque les titres `pornographic`).
  final List<String>? niveauxContenuRecherche;

  /// UUID de chapitre → `externalUrl` (`null` = hébergé sur MangaDex), pour
  /// les chapitres déjà lus dans un flux par cette instance.
  final Map<String, String?> _urlsExternesConnues = <String, String?>{};

  static final RegExp _motifUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  /// Vérifie que chaque niveau fait partie de l'énumération `contentRating`
  /// de api.yaml (`niveauxContenu` reprend ces quatre valeurs) et retire les
  /// doublons. Lève une [ArgumentError] sinon.
  static List<String> _validerNiveaux(List<String> niveaux) {
    final resultat = <String>[];
    for (final niveau in niveaux) {
      if (!niveauxContenu.contains(niveau)) {
        throw ArgumentError.value(
          niveau,
          'niveauxContenuRecherche',
          'niveau de contenu MangaDex inconnu (attendu : '
              '${niveauxContenu.join(', ')})',
        );
      }
      if (!resultat.contains(niveau)) {
        resultat.add(niveau);
      }
    }
    return resultat;
  }

  // ---------------------------------------------------------------------
  // Extraction des identifiants
  // ---------------------------------------------------------------------

  /// Indique si [hote] est le site public MangaDex (`mangadex.org` ou
  /// `www.mangadex.org`) : sert à reconnaître une URL de titre ou de
  /// chapitre. Pour choisir le User-Agent d'une requête, utiliser
  /// [estServeurMangaDex], qui couvre aussi les sous-domaines.
  static bool estHoteMangaDex(String hote) {
    final h = hote.toLowerCase();
    return h == domaineMangaDex || h == 'www.$domaineMangaDex';
  }

  /// Indique si [hote] est un serveur MangaDex, quel qu'il soit : le site
  /// (`mangadex.org`), ses sous-domaines (`api.`, `uploads.`…) et les nœuds
  /// MangaDex@Home (`*.mangadex.network`). Tous exigent un User-Agent honnête
  /// ([userAgentApplication], docs/2-limitations) ; avec un User-Agent de
  /// navigateur, `uploads.mangadex.org` redirige vers une page anti-robot
  /// HTML (journal des erreurs, E10).
  ///
  /// Différence avec [estHoteMangaDex] : celle-ci ne reconnaît que le site
  /// public (URLs de titres et de chapitres).
  static bool estServeurMangaDex(String hote) {
    var h = hote.trim().toLowerCase();
    // Point final d'un nom de domaine absolu (« mangadex.org. ») toléré.
    if (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    return h == domaineMangaDex ||
        h.endsWith('.$domaineMangaDex') ||
        h == 'mangadex.network' ||
        h.endsWith('.mangadex.network');
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
  /// réseau, de même qu'une liste [niveauxContenuRecherche] vide (aucun
  /// niveau accepté).
  ///
  /// Filtre de niveau de contenu : paramètre `contentRating[]` de
  /// `GET /manga` (api.yaml : « type: array, default: [safe, suggestive,
  /// erotica] »). Envoyé seulement si [niveauxContenuRecherche] est
  /// renseigné ; sinon le défaut de l'API s'applique (docs/03-manga/search :
  /// « Pornographic titles are hidden by default »).
  @override
  Future<List<Titre>> rechercher(String requete) {
    return JournalSources.operation(
      'MangaDex',
      'recherche',
      requete,
      () => _avecTypeSite(() async {
        final texte = requete.trim();
        final niveaux = niveauxContenuRecherche;
        if (texte.isEmpty || (niveaux != null && niveaux.isEmpty)) {
          return const <Titre>[];
        }
        final uri = Uri.https(domaineApiMangaDex, '/manga', <String, Object>{
          'title': texte,
          'limit': '$taillePageRechercheMangaDex',
          // Reference expansion (docs/01-concepts/reference-expansion) : évite
          // une requête par titre pour la couverture et l'auteur.
          'includes[]': <String>['cover_art', 'author', 'artist'],
          'contentRating[]': ?niveaux,
        });
        return _lireJson(
          uri,
          (json, url) => <Titre>[
            for (final manga in json.lireListeObjets('data', url))
              _construireTitre(manga, url),
          ],
        );
      }),
    );
  }

  /// Fiche d'un titre : `GET /manga/{id}?includes[]=cover_art&includes[]=author
  /// &includes[]=artist` (api.yaml, operationId `get-manga-id` ; paramètre
  /// `includes[]` = `ReferenceExpansionManga`).
  ///
  /// Le niveau de contenu (`MangaAttributes.contentRating`) est rangé dans
  /// `Titre.niveauContenu`.
  @override
  Future<FicheTitre> recupererFiche(String urlTitre) {
    return JournalSources.operation(
      'MangaDex',
      'fiche',
      urlTitre,
      () => _avecTypeSite(() async {
        final id = extraireIdTitre(urlTitre);
        final uri = Uri.https(
          domaineApiMangaDex,
          '/manga/$id',
          <String, Object>{
            'includes[]': <String>['cover_art', 'author', 'artist'],
          },
        );
        return _lireJson(uri, (json, url) {
          final manga = json.lireObjet('data', url);
          final attributs = manga.lireObjet('attributes', url);

          // Catégories = tags du titre (MangaAttributes.tags →
          // Tag.attributes.name, un LocalizedString). Les tags MangaDex ont un
          // nom anglais ; on prend sinon le premier nom disponible.
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
        });
      }),
    );
  }

  /// Toutes les couvertures d'un titre (une par volume en général) :
  /// `GET /cover?manga[]={id}&order[volume]=asc&limit=100&offset=…`
  /// (api.yaml, operationId `get-cover`, réponse `CoverList` ;
  /// docs/03-manga/covers : « All covers for a manga : Using the GET /cover
  /// endpoint »), parcouru page par page avec `limit`/`offset`/`total`.
  ///
  /// Chaque couverture donne :
  /// - [CouvertureSite.url] : `https://uploads.mangadex.org/covers/:manga-id/
  ///   :cover-filename` (docs/03-manga/covers) ;
  /// - [CouvertureSite.urlMiniature] : la miniature de 512 px,
  ///   `…/:cover-filename.512.jpg` (« the full cover filename is still
  ///   expected. Including the original extension ») ;
  /// - [CouvertureSite.volume] et [CouvertureSite.langue] :
  ///   `CoverAttributes.volume` et `CoverAttributes.locale` (nullables).
  ///
  /// L'ordre est celui de l'API (`order[volume]=asc`). LIMITE : `volume` est
  /// un texte ; la doc ne dit pas si le tri est numérique. La réponse réelle
  /// enregistrée le 2026-11-16 range bien « 10 » après « 9 ».
  @override
  Future<List<CouvertureSite>> recupererCouvertures(String urlTitre) {
    return _avecTypeSite(() async {
      final id = extraireIdTitre(urlTitre);
      final couvertures = <CouvertureSite>[];
      final urlsVues = <String>{};
      var offset = 0;
      while (true) {
        final uri = Uri.https(domaineApiMangaDex, '/cover', <String, Object>{
          'manga[]': <String>[id],
          'limit': '$taillePageCouverturesMangaDex',
          'offset': '$offset',
          'order[volume]': 'asc',
        });
        final page = await _lireJson(uri, (json, url) {
          final donnees = json.lireListeObjets('data', url);
          return (
            nombre: donnees.length,
            total: json.lireEntier('total', url),
            couvertures: <CouvertureSite>[
              for (final couverture in donnees)
                ?_construireCouverture(id, couverture, url),
            ],
          );
        });
        // Une couverture ajoutée pendant la lecture décale les offsets : on
        // ne garde qu'une fois la même image.
        for (final couverture in page.couvertures) {
          if (urlsVues.add(couverture.url)) {
            couvertures.add(couverture);
          }
        }
        offset += page.nombre;
        // Même règle d'arrêt que le flux de chapitres : page vide, total
        // atteint, ou plafond de pagination de l'API (docs/2-limitations).
        if (page.nombre == 0 ||
            offset >= page.total ||
            offset + taillePageCouverturesMangaDex > plafondOffsetMangaDex) {
          break;
        }
      }
      return couvertures;
    });
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
  /// - `contentRating[]` : toutes les classifications (énumération
  ///   `contentRating` de api.yaml) ;
  /// - `includeFuturePublishAt=0` : on ne signale pas un chapitre qui ne
  ///   peut pas encore être lu ;
  /// - `translatedLanguage[]` si [languesChapitres] n'est pas vide.
  ///
  /// Chapitres hébergés sur un site externe (tâche R4) : api.yaml 5.13.1,
  /// `feedParameters`, déclare `includeExternalUrl` avec le schéma
  /// `triStateFilter` (« type: integer, enum: [0, 1] ») sans en décrire le
  /// sens ; `ChapterAttributes.externalUrl` : « type: string, pattern:
  /// ^https?://, maxLength: 512, nullable: true, description: Denotes a
  /// chapter that links to an external source ». Sens vérifié sur l'API le
  /// 2026-11-16 : `includeExternalUrl=1` ne renvoie QUE les chapitres
  /// externes (titre de référence : total 0 au lieu de 217), `0` les exclut,
  /// paramètre absent = les deux (Ruri Dragon : 324 = 280 externes + 44).
  /// Le paramètre n'est donc plus envoyé, et chaque chapitre externe reçoit
  /// `Chapitre.urlExterne`.
  ///
  /// `includeEmptyPages` n'est plus envoyé non plus : un chapitre externe a
  /// souvent `pages = 0` (Ruri Dragon, VIZ et MANGA Plus) et serait exclu.
  /// Les chapitres sans page ET sans `externalUrl` (illisibles) sont retirés
  /// ici, comme le faisait `includeEmptyPages=0`.
  ///
  /// Lève une [ErreurSource] si le flux dépasse le plafond de 10 000
  /// résultats de l'API (il faut alors filtrer par langue).
  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) {
    return JournalSources.operation(
      'MangaDex',
      'chapitres',
      urlTitre,
      () => _avecTypeSite(() async {
        final id = extraireIdTitre(urlTitre);
        final chapitres = <Chapitre>[];
        // Un chapitre ajouté ou retiré pendant la lecture des pages décale les
        // offsets : la même entrée peut revenir sur deux pages. On ne la garde
        // qu'une fois (l'UUID est unique, comme `url_chapitre` en base).
        final idsVus = <String>{};
        // Chapitres sans page ni lien externe, comptés pour le journal.
        var illisibles = 0;
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
              // Tous les niveaux (énumération `contentRating` de api.yaml).
              // Sans ce paramètre, l'API applique le défaut [safe, suggestive,
              // erotica] et un titre que le client suit déjà pourrait renvoyer
              // un flux vide sans erreur.
              'contentRating[]': niveauxContenu,
              // Ni `includeExternalUrl` ni `includeEmptyPages` : voir la
              // documentation de la méthode (chapitres externes, R4).
              'includeFuturePublishAt': '0',
              if (languesChapitres.isNotEmpty)
                'translatedLanguage[]': languesChapitres,
            },
          );
          final page = await _lireJson(uri, (json, url) {
            final donnees = json.lireListeObjets('data', url);
            final total = json.lireEntier('total', url);
            // Dès la première page, `total` dit si l'on atteindra le plafond :
            // inutile de lire 20 pages pour échouer ensuite.
            if (total > plafondOffsetMangaDex) {
              throw ErreurSource(
                urlTitre,
                "Trop de chapitres ($total) : l'API MangaDex refuse de dépasser "
                '$plafondOffsetMangaDex résultats. Choisir une langue de '
                'chapitres pour cette source.',
              );
            }
            return (
              total: total,
              nombre: donnees.length,
              chapitres: <(String, Chapitre?)>[
                for (final chapitre in donnees)
                  (
                    chapitre.lireTexte('id', url),
                    _construireChapitre(chapitre, url),
                  ),
              ],
            );
          });
          for (final (idChapitre, chapitre) in page.chapitres) {
            if (chapitre == null) {
              // Chapitre vide et non externe : illisible, ignoré.
              illisibles++;
              continue;
            }
            // Mémorisé pour que [recupererContenu] reconnaisse un chapitre
            // externe sans requête supplémentaire.
            _urlsExternesConnues[idChapitre] = chapitre.urlExterne;
            if (idsVus.add(idChapitre)) {
              chapitres.add(chapitre);
            }
          }
          offset += page.nombre;
          // Page vide : l'API a fini (docs/01-concepts/pagination : un offset
          // au delà du total renvoie une collection vide). On s'arrête aussi
          // pour ne jamais boucler indéfiniment si `total` est incohérent.
          if (page.nombre == 0 ||
              offset >= page.total ||
              offset >= plafondOffsetMangaDex) {
            break;
          }
        }
        if (illisibles > 0) {
          JournalSources.avertir(
            'MangaDex',
            '$illisibles chapitre${illisibles > 1 ? 's' : ''} sans page '
                'ignoré${illisibles > 1 ? 's' : ''} ($urlTitre)',
          );
        }
        return chapitres;
      }),
    );
  }

  /// URLs des images d'un chapitre : `GET /at-home/server/{chapterId}`
  /// (api.yaml, operationId `get-at-home-server-chapterId`), puis
  /// `<baseUrl>/<data|data-saver>/<chapter.hash>/<fichier>`
  /// (docs/04-chapter/retrieving-chapter).
  ///
  /// LIMITE : `baseUrl` n'est garanti que 15 minutes (« We guarantee 15
  /// minutes ») ; passé ce délai, le serveur d'images répond 403
  /// (`ErreurSource.codeStatut == 403`) et il faut rappeler cette méthode.
  /// Signalement : la doc demande de signaler chaque image chargée depuis un
  /// serveur MangaDex@Home ; le téléchargement (service) s'en charge avec
  /// `SignalementMangaDex` (signalement_mangadex.dart), qui reconnaît ces
  /// images avec `SignalementMangaDex.estServeurMangaDexAtHome`.
  /// Qualité : [qualiteReduite] choisit les images `data-saver`.
  ///
  /// Chapitre externe (`ChapterAttributes.externalUrl` renseigné, tâche R4) :
  /// lève une [ErreurSource] « chapitre hébergé sur un site externe » sans
  /// appeler `/at-home` (PLAYBOOK.md section 10 : ces pages ne sont jamais
  /// lues ni téléchargées). Si le chapitre n'a pas été vu par
  /// [recupererChapitres] avec cette instance, une requête
  /// `GET /chapter/{id}` (api.yaml, operationId `get-chapter-id`, réponse
  /// `ChapterResponse`) vérifie d'abord `externalUrl`.
  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) {
    return JournalSources.operation(
      'MangaDex',
      'chapitre',
      urlChapitre,
      () => _avecTypeSite(() async {
        final id = extraireIdChapitre(urlChapitre);
        final String? urlExterne;
        if (_urlsExternesConnues.containsKey(id)) {
          urlExterne = _urlsExternesConnues[id];
        } else {
          urlExterne = await _lireJson(
            Uri.https(domaineApiMangaDex, '/chapter/$id'),
            (json, url) => _lireUrlExterne(
              json.lireObjet('data', url).lireObjet('attributes', url),
              id,
            ),
          );
          _urlsExternesConnues[id] = urlExterne;
        }
        if (urlExterne != null) {
          throw ErreurSource(
            urlChapitre,
            'Chapitre hébergé sur un site externe '
            '(${nomSiteExterne(urlExterne)} : $urlExterne) : aucune page à '
            'récupérer sur MangaDex',
          );
        }
        final uri = Uri.https(domaineApiMangaDex, '/at-home/server/$id');
        return _lireJson(
          uri,
          limite: const LimiteRequetes(
            '$domaineApiMangaDex/at-home/server',
            delaiMinimalAtHomeMangaDex,
          ),
          (json, url) {
            // La doc insiste : « Do NOT assume any format [...] Just use it
            // as-is ». On concatène donc baseUrl tel quel au lieu d'utiliser
            // Uri.resolve (qui supprimerait le dernier segment d'un baseUrl
            // sans « / » final).
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
            // Pas de Referer : la doc MangaDex n'en exige pas pour les images
            // et interdit seulement les en-têtes d'authentification.
            return ContenuChapitre.images(<String>[
              for (final fichier in fichiers)
                '$baseUrl/$qualite/$hash/$fichier',
            ]);
          },
        );
      }),
    );
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
      niveauContenu: niveauContenuDepuisApi(
        attributs.lireTexteOptionnel('contentRating', url),
      ),
    );
  }

  /// Valeur de `MangaAttributes.contentRating` (api.yaml : « type: string,
  /// enum: safe, suggestive, erotica, pornographic ») gardée telle quelle si
  /// elle fait partie de l'énumération (`niveauxContenu`), sinon `null`.
  ///
  /// LIMITE : une valeur ajoutée plus tard par MangaDex sera ignorée (titre
  /// sans niveau connu) plutôt que de faire échouer la fiche ; la casse et les
  /// espaces sont tolérés.
  static String? niveauContenuDepuisApi(String? valeur) {
    final niveau = valeur?.trim().toLowerCase();
    return niveau != null && niveauxContenu.contains(niveau) ? niveau : null;
  }

  /// Construit une [CouvertureSite] depuis un objet `Cover` de l'API
  /// (api.yaml, schémas `Cover` et `CoverAttributes`), ou `null` si
  /// `fileName` est vide (aucune image à proposer).
  CouvertureSite? _construireCouverture(
    String idTitre,
    Map<String, Object?> couverture,
    String url,
  ) {
    final attributs = couverture.lireObjet('attributes', url);
    final fichier = attributs.lireTexte('fileName', url).trim();
    if (fichier.isEmpty) {
      return null;
    }
    // docs/03-manga/covers : https://uploads.mangadex.org/covers/:manga-id/
    // :cover-filename, et la miniature :cover-filename.{256, 512}.jpg (nom
    // complet, extension d'origine comprise).
    final urlImage =
        'https://$domaineCouverturesMangaDex/covers/$idTitre/$fichier';
    final volume = attributs.lireTexteOptionnel('volume', url)?.trim();
    final langue = attributs.lireTexteOptionnel('locale', url)?.trim();
    return CouvertureSite(
      url: urlImage,
      urlMiniature: '$urlImage.$largeurMiniatureCouvertureMangaDex.jpg',
      volume: volume == null || volume.isEmpty ? null : volume,
      langue: langue == null || langue.isEmpty ? null : langue,
    );
  }

  /// Longueur maximale d'`externalUrl` (api.yaml, `ChapterAttributes` :
  /// « maxLength: 512 »).
  static const int longueurMaxUrlExterne = 512;

  /// Lit `ChapterAttributes.externalUrl` (api.yaml : « type: string,
  /// pattern: ^https?://, maxLength: 512, nullable: true ») du chapitre
  /// [idChapitre] : renvoie l'URL si elle est valide, `null` si l'attribut
  /// est absent, nul ou vide.
  ///
  /// Valeur présente mais invalide (pas un texte, schéma autre que http(s),
  /// sans hôte, plus de [longueurMaxUrlExterne] caractères, mal formée) :
  /// choix retenu, le chapitre reste **externe** avec l'URL MangaDex du
  /// chapitre comme lien (`urlChapitreDepuisId`). Pourquoi pas une
  /// [ErreurSource] : une seule entrée abîmée faisait échouer tout le flux et
  /// bloquait les mises à jour du titre. Pourquoi pas ignorer le chapitre :
  /// il disparaîtrait sans explication alors que MangaDex le déclare externe ;
  /// ainsi l'utilisateur peut au moins l'ouvrir sur mangadex.org, et le
  /// chapitre n'est jamais téléchargé ([recupererContenu] refuse les
  /// chapitres externes). L'anomalie est journalisée avec `debugPrint`, sans
  /// la valeur reçue (elle peut contenir des jetons ou données personnelles).
  static String? _lireUrlExterne(
    Map<String, Object?> attributs,
    String idChapitre,
  ) {
    final brute = attributs['externalUrl'];
    if (brute == null) {
      return null;
    }
    final String? raison;
    final valeur = brute is String ? brute.trim() : null;
    if (brute is! String) {
      raison = "type ${brute.runtimeType} au lieu d'un texte";
    } else if (valeur!.isEmpty) {
      return null;
    } else if (valeur.length > longueurMaxUrlExterne) {
      raison = '${valeur.length} caractères (max $longueurMaxUrlExterne)';
    } else {
      final uri = Uri.tryParse(valeur);
      if (uri == null) {
        raison = 'URL mal formée';
      } else if (uri.scheme != 'http' && uri.scheme != 'https') {
        raison = 'schéma non http(s)';
      } else if (uri.host.isEmpty) {
        raison = 'hôte absent';
      } else {
        raison = null;
      }
    }
    if (raison == null) {
      return valeur;
    }
    debugPrint(
      'SourceMangaDex : externalUrl invalide pour le chapitre $idChapitre '
      '($raison) ; lien remplacé par la page MangaDex du chapitre.',
    );
    return urlChapitreDepuisId(idChapitre);
  }

  /// Nom lisible du site d'un chapitre externe, pour le bouton
  /// « Lire sur `site` » : « MANGA Plus » pour `mangaplus.shueisha.co.jp`,
  /// « VIZ » pour `viz.com` (deux éditeurs vus dans le flux réel de Ruri
  /// Dragon), « Scan-Manga » pour `scan-manga.com`, sinon le nom de domaine
  /// en minuscules sans `www.`. Renvoie le texte reçu tel quel s'il ne
  /// contient pas d'hôte.
  ///
  /// Gardée pour les appelants existants ; la table des noms est commune à
  /// tous les adaptateurs (`sites_externes.dart`).
  static String nomSiteExterne(String urlExterne) =>
      sites_externes.nomSiteExterne(urlExterne);

  /// Construit un [Chapitre] depuis un objet `Chapter` de l'API (api.yaml,
  /// schéma `ChapterAttributes`), ou `null` si le chapitre n'a aucune page
  /// (`pages`, « Count of readable images ») et pas d'`externalUrl` : il ne
  /// peut être lu nulle part (rôle de l'ancien `includeEmptyPages=0`).
  ///
  /// Un chapitre externe garde son URL MangaDex dans `urlChapitre` (clé
  /// unique en base) et reçoit son lien dans `Chapitre.urlExterne`.
  Chapitre? _construireChapitre(Map<String, Object?> chapitre, String url) {
    final id = chapitre.lireTexte('id', url);
    final attributs = chapitre.lireObjet('attributes', url);
    final urlExterne = _lireUrlExterne(attributs, id);
    final pages = attributs['pages'];
    if (urlExterne == null && pages is int && pages <= 0) {
      return null;
    }
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
      urlExterne: urlExterne,
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
  /// en notation scientifique ou non fini donne 0. Voir
  /// `OutilsSources.convertirNumero`, partagé avec les autres adaptateurs.
  static double convertirNumero(String? texte) =>
      OutilsSources.convertirNumero(texte);

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

  /// Découpe une préférence de langues `Source.langueParDefaut` (codes ISO
  /// 639-1 séparés par des virgules, par ordre de préférence, ex. « fr,en »).
  ///
  /// Les espaces sont ignorés, les codes vides aussi, la casse est ramenée
  /// en minuscules et les doublons sont retirés (le premier gardé fixe
  /// l'ordre). « fr, en ,,FR » → `[fr, en]` ; « » → `[]`.
  static List<String> languesIsoDepuisPreference(String preference) {
    final codes = <String>[];
    for (final morceau in preference.split(',')) {
      final code = morceau.trim().toLowerCase();
      if (code.isNotEmpty && !codes.contains(code)) {
        codes.add(code);
      }
    }
    return codes;
  }

  /// Codes `translatedLanguage[]` à demander pour une préférence de langues
  /// (voir [languesIsoDepuisPreference]) : chaque code passe par
  /// [languesApiDepuisIso], puis les résultats sont fusionnés dans l'ordre,
  /// sans doublon.
  ///
  /// « fr,en » → `[fr, en]` ; « pt,en » → `[pt, pt-br, en]` ; valeur vide →
  /// liste vide (toutes les langues).
  static List<String> languesDepuisPreference(String preference) {
    final langues = <String>[];
    for (final iso in languesIsoDepuisPreference(preference)) {
      for (final code in languesApiDepuisIso(iso)) {
        if (!langues.contains(code)) {
          langues.add(code);
        }
      }
    }
    return langues;
  }

  /// Exécute [action] et complète toute [ErreurSource] levée avec le type de
  /// site MangaDex (rapport d'erreur, tâche SO2), sans perdre la pile
  /// d'appels d'origine.
  Future<T> _avecTypeSite<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ErreurSource catch (erreur, pile) {
      Error.throwWithStackTrace(
        erreur.avecContexte(typeDetecte: TypeSource.mangaDex),
        pile,
      );
    }
  }

  /// Récupère [uri] en JSON, vérifie le champ `result` (api.yaml : `result`
  /// vaut `ok` ou `error`, avec `errors[].detail`), puis applique
  /// [convertir].
  ///
  /// Toute [ErreurSource] levée après réception (JSON invalide, `result`
  /// en erreur, structure inattendue dans [convertir]) reçoit le début
  /// nettoyé de la réponse (`extraitReponse`) pour le rapport d'erreur.
  Future<T> _lireJson<T>(
    Uri uri,
    T Function(Map<String, Object?> json, String url) convertir, {
    LimiteRequetes? limite,
  }) async {
    final url = uri.toString();
    final texte = await _client.recupererTexte(
      uri,
      userAgent: userAgentApplication,
      enTetes: const <String, String>{'Accept': 'application/json'},
      limite: limite,
    );
    try {
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
      return convertir(json, url);
    } on ErreurSource catch (erreur, pile) {
      Error.throwWithStackTrace(
        erreur.avecContexte(extraitReponse: extraireDebutReponse(texte)),
        pile,
      );
    }
  }
}
