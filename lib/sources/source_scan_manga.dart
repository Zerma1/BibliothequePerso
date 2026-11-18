/// Adaptateur Scan-Manga (`https://www.scan-manga.com`, tâche R8).
///
/// Structure relevée le 2026-11-16 sur deux pages réelles enregistrées dans
/// `test/sources/exemples_html/` (Potion-danomi de Ikinobimasu!, Murim
/// Login) :
/// - page d'un titre : `https://www.scan-manga.com/<numéro>/<Nom>.html` (ou
///   `<numéro>-<numéro>/<Nom>.html`), HTML lisible servi en 200 ;
/// - chapitres : liens
///   `https://www.scan-manga.com/lecture-en-ligne/<Nom>-Chapitre-<n>-FR_<id>.html`.
///
/// Les pages de chapitre cachent leurs images derrière un script brouillé :
/// **aucune page de chapitre n'est lue ni téléchargée** (PLAYBOOK.md
/// section 10). Chaque chapitre est rendu avec `urlExterne` = sa page de
/// lecture (« Lire sur Scan-Manga »).
library;

import 'package:html/dom.dart' show Document, Element, Text;
import 'package:html/parser.dart' show parse;

import '../modeles/chapitre.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../modeles/titre_alternatif.dart';
import 'client_http_poli.dart';
import 'constantes_sources.dart';
import 'erreur_source.dart';
import 'journal_sources.dart';
import 'outils_sources.dart';
import 'rapport_erreur_source.dart';
import 'source_site.dart';

/// Lecture de Scan-Manga : fiche et liste des chapitres depuis la page HTML
/// d'un titre ; chapitres lisibles uniquement sur le site.
///
/// Toute [ErreurSource] levée par ses méthodes publiques porte
/// `typeDetecte == TypeSource.scanManga` et, quand une page a été reçue, son
/// début nettoyé (`extraitReponse`) pour le rapport d'erreur.
class SourceScanManga implements SourceSite {
  /// Crée l'adaptateur. [maintenant] remplace l'horloge dans les tests (durée
  /// de vie de la page gardée en mémoire, [dureeCachePageScanManga]).
  SourceScanManga(this._client, {DateTime Function()? maintenant})
    : _maintenant = maintenant ?? DateTime.now;

  final ClientHttpPoli _client;
  final DateTime Function() _maintenant;

  /// Dernière page de titre téléchargée (adresse, HTML, date) : la fiche et
  /// les chapitres viennent de la même page.
  ({String url, String html, DateTime date})? _dernierePage;

  /// Chemin d'une page de lecture :
  /// `/lecture-en-ligne/<Nom>-Chapitre-<n>-<LANGUE>_<id>.html`. Le suffixe de
  /// langue (`FR`, `VUS`…) est capturé.
  static final RegExp _motifCheminChapitre = RegExp(
    r'^/lecture-en-ligne/.+-([A-Za-z]{2,4})_\d+\.html$',
  );

  /// Premier segment du chemin d'une page de titre : `6678` ou `7676-38512`.
  static final RegExp _motifIdentifiantTitre = RegExp(r'^\d+(-\d+)?$');

  /// Correspondance entre le suffixe d'une URL de chapitre et la langue
  /// (code ISO 639-1). `VUS` (« version US ») désigne l'anglais.
  static const Map<String, String> _languesSuffixes = <String, String>{
    'FR': 'fr',
    'VF': 'fr',
    'VUS': 'en',
    'US': 'en',
    'EN': 'en',
  };

  // ---------------------------------------------------------------------
  // Adresses
  // ---------------------------------------------------------------------

  /// Indique si [hote] est Scan-Manga (`scan-manga.com` ou
  /// `www.scan-manga.com`), sans requête réseau.
  static bool estHoteScanManga(String hote) {
    final h = hote.trim().toLowerCase();
    return h == domaineScanManga || h == 'www.$domaineScanManga';
  }

  /// Valide l'adresse d'une page de titre
  /// (`https://www.scan-manga.com/<numéro>/<Nom>.html`) et la renvoie
  /// analysée. Lève une [ErreurSource] sinon.
  static Uri validerUrlTitre(String urlTitre) {
    final uri = Uri.tryParse(urlTitre.trim());
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        estHoteScanManga(uri.host)) {
      final segments = uri.pathSegments;
      if (segments.length == 2 &&
          _motifIdentifiantTitre.hasMatch(segments[0]) &&
          segments[1].toLowerCase().endsWith('.html')) {
        return uri;
      }
    }
    throw ErreurSource(
      urlTitre,
      'URL Scan-Manga invalide : '
      'https://www.$domaineScanManga/<numéro>/<Nom>.html attendu',
      typeDetecte: TypeSource.scanManga,
    );
  }

  /// Langue d'un chapitre d'après le suffixe de son URL (`FR` → `fr`,
  /// `VUS` → `en`). Un autre suffixe de deux lettres est pris comme code
  /// ISO 639-1 ; un suffixe inconnu ou absent donne `fr`, langue du site.
  static String langueDepuisSuffixe(String? suffixe) {
    final s = (suffixe ?? '').trim().toUpperCase();
    final connue = _languesSuffixes[s];
    if (connue != null) {
      return connue;
    }
    if (RegExp(r'^[A-Z]{2}$').hasMatch(s)) {
      return s.toLowerCase();
    }
    return 'fr';
  }

  /// Type du titre d'après le premier mot de sa « Catégorie » sur la fiche
  /// (« Manga Shonen », « Manhwa Seinen »…).
  ///
  /// LIMITE : seules les valeurs manga, manhwa, manhua et novel (→ roman)
  /// sont reconnues ; « Webtoon » ou une autre catégorie donne
  /// [TypeTitre.autre] (le pays d'origine n'est pas indiqué).
  static TypeTitre typeDepuisCategorie(String? categorie) {
    final mots = (categorie ?? '').trim().toLowerCase().split(RegExp(r'\s+'));
    switch (mots.first) {
      case 'manga':
        return TypeTitre.manga;
      case 'manhwa':
        return TypeTitre.manhwa;
      case 'manhua':
        return TypeTitre.manhua;
      case 'novel':
      case 'roman':
        return TypeTitre.roman;
      default:
        return TypeTitre.autre;
    }
  }

  // ---------------------------------------------------------------------
  // SourceSite
  // ---------------------------------------------------------------------

  /// Recherche sur Scan-Manga : renvoie toujours une liste vide.
  ///
  /// LIMITE : la page de recherche du site
  /// (`/scanlation/liste_series.html?q=<texte>`, vérifiée le 2026-11-16) ne
  /// contient aucun résultat dans son HTML : la liste est chargée ensuite par
  /// un script de la page. Sans page de résultats HTML, aucune recherche
  /// n'est faite ; le client ajoute un titre par l'adresse de sa page.
  @override
  Future<List<Titre>> rechercher(String requete) async {
    return const <Titre>[];
  }

  /// Récupère la fiche d'un titre depuis sa page HTML (une requête, ou
  /// aucune si la même page vient d'être lue).
  @override
  Future<FicheTitre> recupererFiche(String urlTitre) {
    return JournalSources.operation(
      'Scan-Manga',
      'fiche',
      urlTitre,
      () => _avecTypeSite(() async {
        final uri = validerUrlTitre(urlTitre);
        final html = await _recupererPage(uri);
        return _avecExtrait(html, () => analyserFiche(html, uri));
      }),
    );
  }

  /// Récupère tous les chapitres listés sur la page du titre. Aucune page de
  /// chapitre n'est téléchargée.
  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) {
    return JournalSources.operation(
      'Scan-Manga',
      'chapitres',
      urlTitre,
      () => _avecTypeSite(() async {
        final uri = validerUrlTitre(urlTitre);
        final html = await _recupererPage(uri);
        return _avecExtrait(html, () => analyserChapitres(html, uri));
      }),
    );
  }

  /// Lève toujours une [ErreurSource], sans requête : les images d'un
  /// chapitre Scan-Manga sont cachées derrière un script brouillé, que
  /// l'application ne décode jamais (PLAYBOOK.md section 10). Le chapitre se
  /// lit sur le site (`Chapitre.urlExterne`).
  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) async {
    JournalSources.avertir(
      'Scan-Manga',
      'chapitre protégé, lisible seulement sur le site '
          '($urlChapitre)',
    );
    throw ErreurSource(
      urlChapitre,
      'Chapitre lisible uniquement sur Scan-Manga : ouvrez-le sur le site '
      '(« Lire sur Scan-Manga »)',
      typeDetecte: TypeSource.scanManga,
    );
  }

  // ---------------------------------------------------------------------
  // Analyse du HTML (sans réseau, publique pour les tests)
  // ---------------------------------------------------------------------

  /// Construit la fiche à partir du [html] de la page [urlTitre].
  ///
  /// Lève une [ErreurSource] si la page n'a pas la structure d'une fiche
  /// Scan-Manga (page d'erreur, page anti-robot…) ou si le nom manque.
  static FicheTitre analyserFiche(String html, Uri urlTitre) {
    final document = parse(html);
    _verifierPageTitre(document, urlTitre);

    // Le nom est le h2 du bandeau du titre (`.h2_titre`), le premier de la
    // page : le fil d'Ariane a aussi un h2 mais hors de `.h2_titre`, et le
    // bandeau « Chapitres disponibles » vient plus bas.
    final enTete = document.querySelector('.h2_titre h2');
    var nom = enTete == null ? '' : _nettoyer(enTete.text);
    if (nom.isEmpty) {
      // Repli : la balise <title> vaut « <Nom> | Scan-Manga ».
      final titrePage = _nettoyer(document.querySelector('title')?.text ?? '');
      final fin = titrePage.lastIndexOf(' | ');
      nom = fin > 0 ? titrePage.substring(0, fin).trim() : titrePage;
    }
    if (nom.isEmpty) {
      throw ErreurSource(
        urlTitre.toString(),
        'Fiche Scan-Manga sans nom de titre (structure inattendue)',
      );
    }

    // Titres alternatifs : éléments `itemprop="… alternativeHeadline"` du
    // bloc `.alt_name`. Le site écrit `<span'` (apostrophe collée au nom de
    // la balise) et ferme par `</span>` : l'analyseur imbrique alors chaque
    // nom dans le précédent. On ne garde donc que le texte propre de chaque
    // élément, sans celui de ses descendants.
    final alternatifs = <TitreAlternatif>[];
    final nomsVus = <String>{nom};
    for (final element in document.querySelectorAll(
      '.alt_name [itemprop*="alternativeHeadline"]',
    )) {
      final alt = _nettoyer(_texteDirect(element))
          .replaceAll(RegExp(r'^,\s*|\s*,$'), '');
      if (alt.isNotEmpty && nomsVus.add(alt)) {
        alternatifs.add(TitreAlternatif(nom: alt));
      }
    }

    // Couverture : l'image `itemprop="image"` de la fiche technique
    // (`.image_manga`) ; `data-original` d'abord, au cas où l'image serait
    // chargée en différé (le site le fait pour les couvertures de volumes).
    // Repli : la balise og:image, qui donne la même image.
    String? urlCouverture;
    final image = document.querySelector('.image_manga img');
    final sourceImage =
        image?.attributes['data-original'] ?? image?.attributes['src'];
    final ogImage = document
        .querySelector('meta[property="og:image"]')
        ?.attributes['content'];
    for (final candidat in <String?>[sourceImage, ogImage]) {
      final lien = candidat?.trim() ?? '';
      if (lien.isNotEmpty) {
        urlCouverture = urlTitre.resolve(lien).toString();
        break;
      }
    }

    // Résumé : le paragraphe `itemprop="description"` du synopsis (la balise
    // og:description est tronquée). Le texte caché (`£` dans un span
    // invisible) est écarté en ne lisant que le texte propre du paragraphe.
    final description = document.querySelector(
      '.texte_synopsis_manga [itemprop="description"]',
    );
    final resume = description == null
        ? ''
        : _texteDirect(description)
              .split('\n')
              .map(_nettoyer)
              .where((ligne) => ligne.isNotEmpty)
              .join('\n');

    // Auteurs : les liens de la ligne `itemprop="author"` (un lien par
    // auteur ou artiste, séparés par <br>).
    final ligneAuteur = document.querySelector(
      '.contenu_texte_fiche_technique [itemprop="author"]',
    );
    final auteurs = <String>[];
    if (ligneAuteur != null) {
      for (final lien in ligneAuteur.querySelectorAll('a')) {
        final auteur = _nettoyer(lien.text);
        if (auteur.isNotEmpty && !auteurs.contains(auteur)) {
          auteurs.add(auteur);
        }
      }
      if (auteurs.isEmpty && _nettoyer(ligneAuteur.text).isNotEmpty) {
        auteurs.add(_nettoyer(ligneAuteur.text));
      }
    }

    // « Catégorie » (`itemprop="genre"`) : « Manga Shonen » = type puis
    // public visé ; le public est gardé comme catégorie.
    final categorieSite = _nettoyer(
      document
              .querySelector(
                '.contenu_texte_fiche_technique [itemprop="genre"]',
              )
              ?.text ??
          '',
    );
    final motsCategorie = categorieSite.isEmpty
        ? const <String>[]
        : categorieSite.split(' ');

    final categories = <String>[];
    void ajouterCategorie(String nomCategorie) {
      final propre = _nettoyer(nomCategorie);
      if (propre.isNotEmpty &&
          !categories.any((c) => c.toLowerCase() == propre.toLowerCase())) {
        categories.add(propre);
      }
    }

    // Genres : ligne « Genres » de la fiche technique, un lien `.infoBulle`
    // par genre, dont le span intérieur est l'info-bulle (description) : on
    // ne garde que le texte propre du lien.
    final ligneGenres = _valeurFicheTechnique(document, 'Genres');
    if (ligneGenres != null) {
      final liens = ligneGenres.querySelectorAll('a.infoBulle');
      if (liens.isNotEmpty) {
        for (final lien in liens) {
          ajouterCategorie(_texteDirect(lien));
        }
      } else {
        ligneGenres.text.split(' - ').forEach(ajouterCategorie);
      }
    }
    if (motsCategorie.length > 1) {
      ajouterCategorie(motsCategorie.sublist(1).join(' '));
    }

    final statut = _valeurFicheTechnique(document, 'Statut');
    final texteStatut = statut == null ? '' : _nettoyer(statut.text);

    return FicheTitre(
      titre: Titre(
        urlTitre: urlTitre.toString(),
        nom: nom,
        typeTitre: typeDepuisCategorie(
          motsCategorie.isEmpty ? null : motsCategorie.first,
        ),
        urlCouverture: urlCouverture,
        resume: resume.isEmpty ? null : resume,
        auteur: auteurs.isEmpty ? null : auteurs.join(', '),
        // Statut tel qu'affiché (« En cours », « En pause », « Terminé ») :
        // le modèle garde le texte du site.
        statut: texteStatut.isEmpty ? null : texteStatut,
        titresAlternatifs: alternatifs,
      ),
      categories: categories,
    );
  }

  /// Extrait la liste des chapitres du [html] de la page [urlTitre], du plus
  /// ancien au plus récent (le site les affiche du plus récent au plus
  /// ancien).
  ///
  /// Chaque chapitre a `urlChapitre` = `urlExterne` = sa page de lecture :
  /// il se lit sur Scan-Manga et n'est jamais téléchargé.
  ///
  /// LIMITE : la page d'un titre n'affiche pas la date de parution des
  /// chapitres : `datePublication` reste `null`.
  ///
  /// Lève une [ErreurSource] si la page n'est pas une fiche Scan-Manga. Une
  /// fiche sans aucun chapitre donne une liste vide.
  static List<Chapitre> analyserChapitres(String html, Uri urlTitre) {
    final document = parse(html);
    _verifierPageTitre(document, urlTitre);

    final chapitres = <Chapitre>[];
    final urlsVues = <String>{};
    // Chaque chapitre est un `li.chapitre` des blocs de volumes ; son nom est
    // dans `.chapitre_nom` (lien « Chapitre N » suivi du titre éventuel).
    // Le second lien du li (« Lire en ligne ») pointe vers la même page.
    for (final ligne in document.querySelectorAll('li.chapitre')) {
      final bloc = ligne.querySelector('.chapitre_nom');
      // Le lien de lecture contient « /lecture-en-ligne/ » ; les liens
      // « publications » du même li mènent aux commentaires.
      final lien =
          bloc?.querySelector('a[href*="/lecture-en-ligne/"]') ??
          ligne.querySelector('a[href*="/lecture-en-ligne/"]');
      final href = lien?.attributes['href']?.trim() ?? '';
      if (lien == null || href.isEmpty) {
        continue;
      }
      final Uri adresse;
      try {
        adresse = urlTitre.resolve(href);
      } on FormatException {
        continue;
      }
      final correspondance = _motifCheminChapitre.firstMatch(adresse.path);
      if (!estHoteScanManga(adresse.host) || correspondance == null) {
        continue;
      }
      final url = adresse.toString();
      if (!urlsVues.add(url)) {
        continue;
      }
      final texteLien = _nettoyer(lien.text);
      final nomComplet = _nettoyer(bloc?.text ?? texteLien);
      chapitres.add(
        Chapitre(
          urlChapitre: url,
          nom: nomComplet.isEmpty ? texteLien : nomComplet,
          numero: _numeroChapitre(texteLien, adresse.path),
          langue: langueDepuisSuffixe(correspondance.group(1)),
          urlExterne: url,
        ),
      );
    }
    return chapitres.reversed.toList();
  }

  // ---------------------------------------------------------------------
  // Outils privés
  // ---------------------------------------------------------------------

  /// Lève une [ErreurSource] si [document] n'est pas une fiche de titre :
  /// le bloc `.fiche_technique` est présent sur toutes les fiches et absent
  /// des pages d'erreur ou anti-robot.
  static void _verifierPageTitre(Document document, Uri urlTitre) {
    if (document.querySelector('.fiche_technique') == null) {
      throw ErreurSource(
        urlTitre.toString(),
        "La page reçue n'est pas une fiche de titre Scan-Manga (structure "
        'inattendue, page anti-robot ou titre retiré)',
      );
    }
  }

  /// Valeur de la ligne [libelle] de la fiche technique, ou `null`.
  ///
  /// La fiche technique est faite de deux listes parallèles : les libellés
  /// (`.contenu_titres_fiche_technique li` : « Auteur/Artiste »,
  /// « Catégorie », « Genres », « Statut »…) et les valeurs
  /// (`.contenu_texte_fiche_technique > ul > li`) dans le même ordre. Seuls
  /// des listes de même longueur sont associées, pour ne jamais lire la
  /// valeur d'une autre ligne.
  static Element? _valeurFicheTechnique(Document document, String libelle) {
    final libelles = document.querySelectorAll(
      '.contenu_titres_fiche_technique li',
    );
    final valeurs = document.querySelectorAll(
      '.contenu_texte_fiche_technique > ul > li',
    );
    if (libelles.length != valeurs.length) {
      return null;
    }
    for (var i = 0; i < libelles.length; i++) {
      if (_nettoyer(libelles[i].text).toLowerCase() == libelle.toLowerCase()) {
        return valeurs[i];
      }
    }
    return null;
  }

  /// Numéro du chapitre : d'abord « Chapitre N » dans le texte du lien, puis
  /// « -Chapitre-N- » dans l'adresse, puis le premier nombre du texte ; 0 si
  /// aucun (oneshot).
  static double _numeroChapitre(String texteLien, String chemin) {
    final dansTexte = RegExp(
      r'chapitre\s*(\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    ).firstMatch(texteLien);
    if (dansTexte != null) {
      return OutilsSources.convertirNumero(dansTexte.group(1));
    }
    final dansChemin = RegExp(
      r'-Chapitre-(\d+(?:\.\d+)?)-',
      caseSensitive: false,
    ).firstMatch(chemin);
    if (dansChemin != null) {
      return OutilsSources.convertirNumero(dansChemin.group(1));
    }
    return OutilsSources.convertirNumero(texteLien);
  }

  /// Texte propre de [element] : ses nœuds texte directs, sans le texte de
  /// ses éléments enfants (info-bulles, spans cachés) ; un `<br>` devient un
  /// saut de ligne.
  static String _texteDirect(Element element) {
    final tampon = StringBuffer();
    for (final noeud in element.nodes) {
      if (noeud is Text) {
        tampon.write(noeud.text);
      } else if (noeud is Element && noeud.localName == 'br') {
        tampon.write('\n');
      }
    }
    return tampon.toString();
  }

  /// Regroupe les espaces (sauts de ligne compris) et retire ceux des bords.
  static String _nettoyer(String texte) =>
      texte.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Télécharge la page du titre [uri], ou réutilise celle lue il y a moins
  /// de [dureeCachePageScanManga].
  Future<String> _recupererPage(Uri uri) async {
    final url = uri.toString();
    final page = _dernierePage;
    final maintenant = _maintenant();
    if (page != null &&
        page.url == url &&
        maintenant.difference(page.date) < dureeCachePageScanManga) {
      return page.html;
    }
    // User-Agent par défaut de ClientHttpPoli (celui, honnête, de
    // l'application). Une page de défi Cloudflare est signalée par
    // ClientHttpPoli (`ErreurSource.protectionAntiRobot`).
    final html = await _client.recupererTexte(uri);
    _dernierePage = (url: url, html: html, date: maintenant);
    return html;
  }

  /// Exécute l'analyse [action] et ajoute à toute [ErreurSource] le début
  /// nettoyé de la page reçue, pour le rapport d'erreur.
  static T _avecExtrait<T>(String html, T Function() action) {
    try {
      return action();
    } on ErreurSource catch (erreur, pile) {
      Error.throwWithStackTrace(
        erreur.avecContexte(extraitReponse: extraireDebutReponse(html)),
        pile,
      );
    }
  }

  /// Exécute [action] et complète toute [ErreurSource] levée avec le type de
  /// site Scan-Manga, sans perdre la pile d'appels d'origine.
  Future<T> _avecTypeSite<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ErreurSource catch (erreur, pile) {
      Error.throwWithStackTrace(
        erreur.avecContexte(typeDetecte: TypeSource.scanManga),
        pile,
      );
    }
  }
}
