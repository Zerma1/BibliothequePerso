/// Adaptateur WEBTOON (`https://www.webtoons.com`, tâche W1).
///
/// Structure relevée le 2026-11-17 sur des pages réelles enregistrées dans
/// `test/sources/exemples_html/` (La Petite Frappe du Duc de Pacotille en
/// français, pages 1 et 2 de Tower of God en anglais) :
/// - page d'un titre (liste des épisodes) :
///   `https://www.webtoons.com/<langue>/<genre>/<nom>/list?title_no=<n>`,
///   HTML lisible servi en 200 (fiche, résumé, auteurs, genre, épisodes) ;
/// - liste paginée par `&page=<n>` (une dizaine d'épisodes par page, du plus
///   récent au plus ancien) ; le robots.txt du site interdit
///   `list?title_no=*&page=1` (doublon de la première page) : la première
///   page est donc toujours demandée sans paramètre `page` ;
/// - épisodes : liens
///   `https://www.webtoons.com/<langue>/<genre>/<nom>/<épisode>/viewer?title_no=<n>&episode_no=<m>`.
///
/// Les pages d'épisode listent leurs images, mais le serveur d'images
/// (`webtoon-phinf.pstatic.net`) répond 403 sans en-tête `Referer` du site,
/// et le lecteur bloque copie et clic droit : **aucune page d'épisode n'est
/// lue ni téléchargée** (PLAYBOOK.md section 10). Chaque épisode est rendu
/// avec `urlExterne` = sa page de lecture (« Lire sur WEBTOON »).
library;

import 'package:html/dom.dart' show Document, Element, Text;
import 'package:html/parser.dart' show parse;

import '../modeles/chapitre.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import 'client_http_poli.dart';
import 'constantes_sources.dart';
import 'erreur_source.dart';
import 'outils_sources.dart';
import 'rapport_erreur_source.dart';
import 'source_site.dart';

/// Lecture de WEBTOON : fiche et liste des épisodes depuis les pages HTML de
/// la liste d'un titre ; épisodes lisibles uniquement sur le site.
///
/// Toute [ErreurSource] levée par ses méthodes publiques porte
/// `typeDetecte == TypeSource.webtoons` et, quand une page a été reçue, son
/// début nettoyé (`extraitReponse`) pour le rapport d'erreur.
class SourceWebtoons implements SourceSite {
  /// Crée l'adaptateur. [maintenant] remplace l'horloge dans les tests (durée
  /// de vie de la page gardée en mémoire, [dureeCachePageWebtoons]) ;
  /// [nombreMaxPages] borne le nombre de pages de la liste lues par titre.
  SourceWebtoons(
    this._client, {
    DateTime Function()? maintenant,
    this.nombreMaxPages = nombreMaxPagesListeWebtoons,
  }) : _maintenant = maintenant ?? DateTime.now;

  final ClientHttpPoli _client;
  final DateTime Function() _maintenant;

  /// Nombre maximal de pages de la liste des épisodes lues pour un titre.
  final int nombreMaxPages;

  /// Dernière première page de liste téléchargée (adresse, HTML, date) : la
  /// fiche et le début des épisodes viennent de la même page.
  ({String url, String html, DateTime date})? _dernierePage;

  /// Premier segment du chemin : code de langue du site (`fr`, `en`,
  /// `zh-hant`…).
  static final RegExp _motifLangue = RegExp(r'^[a-z]{2}(-[a-z]+)?$');

  // ---------------------------------------------------------------------
  // Adresses
  // ---------------------------------------------------------------------

  /// Indique si [hote] est WEBTOON (`webtoons.com`, `www.webtoons.com` ou
  /// `m.webtoons.com`), sans requête réseau.
  static bool estHoteWebtoons(String hote) {
    final h = hote.trim().toLowerCase();
    return h == domaineWebtoons ||
        h == 'www.$domaineWebtoons' ||
        h == 'm.$domaineWebtoons';
  }

  /// Valide l'adresse de la liste d'un titre
  /// (`https://www.webtoons.com/<langue>/<genre>/<nom>/list?title_no=<n>`,
  /// aussi acceptée sur `m.` ou sans `www.`) et renvoie sa forme canonique :
  /// `https://www.webtoons.com/…/list?title_no=<n>`, sans autre paramètre
  /// (`page=` compris). Lève une [ErreurSource] sinon.
  static Uri validerUrlTitre(String urlTitre) {
    final uri = Uri.tryParse(urlTitre.trim());
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        estHoteWebtoons(uri.host)) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final numero = uri.queryParameters['title_no'] ?? '';
      if (segments.length == 4 &&
          _motifLangue.hasMatch(segments[0].toLowerCase()) &&
          segments[3] == 'list' &&
          RegExp(r'^\d+$').hasMatch(numero)) {
        return Uri(
          scheme: 'https',
          host: 'www.$domaineWebtoons',
          pathSegments: segments,
          queryParameters: <String, String>{'title_no': numero},
        );
      }
    }
    throw ErreurSource(
      urlTitre,
      'URL WEBTOON invalide : https://www.$domaineWebtoons/<langue>/<genre>/'
      '<nom>/list?title_no=<numéro> attendu',
      typeDetecte: TypeSource.webtoons,
    );
  }

  /// Adresse de la page [numeroPage] de la liste [urlTitre] (canonique).
  ///
  /// La page 1 n'a pas de paramètre `page` : le robots.txt du site interdit
  /// `list?title_no=*&page=1`.
  static Uri adressePage(Uri urlTitre, int numeroPage) {
    if (numeroPage <= 1) {
      return urlTitre;
    }
    return urlTitre.replace(
      queryParameters: <String, String>{
        ...urlTitre.queryParameters,
        'page': '$numeroPage',
      },
    );
  }

  /// Langue des épisodes d'après le premier segment de l'adresse (`/fr/` →
  /// `fr`, `/en/` → `en`). `zh-hant` (chinois traditionnel) donne `zh` ;
  /// une adresse sans langue reconnue donne une chaîne vide.
  static String langueDepuisAdresse(Uri adresse) {
    final segments = adresse.pathSegments.where((s) => s.isNotEmpty);
    final premier = segments.isEmpty ? '' : segments.first.toLowerCase();
    if (!_motifLangue.hasMatch(premier)) {
      return '';
    }
    return premier.substring(0, 2);
  }

  /// Date d'un épisode telle qu'affichée dans la liste (« 13 nov. 2026 »,
  /// « Dec 22, 2024 »), en UTC à minuit ; `null` si le format est inconnu ou
  /// si la date n'existe pas (31 février). Voir
  /// `OutilsSources.convertirDateAvecMois`.
  ///
  /// LIMITE : seuls les noms de mois français et anglais sont reconnus ; les
  /// listes des autres langues du site n'ont pas de date.
  static DateTime? convertirDate(String texte) =>
      OutilsSources.convertirDateAvecMois(texte);

  // ---------------------------------------------------------------------
  // SourceSite
  // ---------------------------------------------------------------------

  /// Recherche sur WEBTOON : renvoie toujours une liste vide, sans requête.
  ///
  /// LIMITE : le robots.txt du site (relevé le 2026-11-17) interdit
  /// `/*/search` aux robots ; l'application ne l'utilise donc pas. Le client
  /// ajoute un titre par l'adresse de sa liste d'épisodes.
  @override
  Future<List<Titre>> rechercher(String requete) async {
    return const <Titre>[];
  }

  /// Récupère la fiche d'un titre depuis la première page de sa liste (une
  /// requête, ou aucune si la même page vient d'être lue).
  @override
  Future<FicheTitre> recupererFiche(String urlTitre) {
    return _avecTypeSite(() async {
      final uri = validerUrlTitre(urlTitre);
      final html = await _recupererPremierePage(uri);
      return _avecExtrait(html, () => analyserFiche(html, uri));
    });
  }

  /// Récupère tous les épisodes du titre, page après page (1 s entre deux
  /// pages grâce à `ClientHttpPoli`), du plus ancien au plus récent. Aucune
  /// page d'épisode n'est téléchargée.
  ///
  /// LIMITE : au-delà de [nombreMaxPages] pages, les épisodes les plus
  /// anciens ne sont pas listés (la liste commence par les plus récents).
  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) {
    return _avecTypeSite(() async {
      final uri = validerUrlTitre(urlTitre);
      // Ordre du site : du plus récent au plus ancien.
      final episodes = <Chapitre>[];
      final urlsVues = <String>{};
      var html = await _recupererPremierePage(uri);
      for (var page = 1; page <= nombreMaxPages; page++) {
        if (page > 1) {
          html = await _recupererTexte(adressePage(uri, page));
        }
        final courant = html;
        final dePage = _avecExtrait(
          courant,
          () => analyserEpisodes(courant, uri),
        );
        final nouveaux = dePage.where((e) => urlsVues.add(e.urlChapitre));
        final avant = episodes.length;
        episodes.addAll(nouveaux);
        // Garde-fou : une page sans épisode nouveau (paramètre `page` ignoré
        // par le site, page vide) arrête la lecture au lieu de boucler.
        if (page > 1 && episodes.length == avant) {
          break;
        }
        if (!aPageSuivante(courant, uri, page)) {
          break;
        }
      }
      return episodes.reversed.toList();
    });
  }

  /// Lève toujours une [ErreurSource], sans requête : le serveur d'images de
  /// WEBTOON refuse les images demandées hors de son lecteur, que
  /// l'application ne contourne jamais (PLAYBOOK.md section 10). L'épisode
  /// se lit sur le site (`Chapitre.urlExterne`).
  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) async {
    throw ErreurSource(
      urlChapitre,
      'Épisode lisible uniquement sur WEBTOON : ouvrez-le sur le site '
      '(« Lire sur WEBTOON »)',
      typeDetecte: TypeSource.webtoons,
    );
  }

  // ---------------------------------------------------------------------
  // Analyse du HTML (sans réseau, publique pour les tests)
  // ---------------------------------------------------------------------

  /// Construit la fiche à partir du [html] de la page de liste [urlTitre].
  ///
  /// Lève une [ErreurSource] si la page n'a pas la structure d'une liste
  /// WEBTOON (page d'erreur, titre retiré…) ou si le nom manque.
  static FicheTitre analyserFiche(String html, Uri urlTitre) {
    final document = parse(html);
    _verifierPageTitre(document, urlTitre);

    // Le nom est le h1 `.subj` du bandeau du titre (`.detail_header
    // .info`) ; les épisodes ont aussi des `.subj`, mais en span, dans la
    // liste. Repli : og:title, qui porte le même nom.
    var nom = _nettoyer(
      document.querySelector('.detail_header .info .subj')?.text ?? '',
    );
    if (nom.isEmpty) {
      nom = _nettoyer(_meta(document, 'meta[property="og:title"]') ?? '');
    }
    if (nom.isEmpty) {
      throw ErreurSource(
        urlTitre.toString(),
        'Fiche WEBTOON sans nom de titre (structure inattendue)',
      );
    }

    // Couverture : og:image (affiche du titre). L'image `.detail_header
    // .thmb img` est un personnage détouré sur fond transparent, pas une
    // couverture. Repli : twitter:image (vignette carrée).
    String? urlCouverture;
    for (final candidat in <String?>[
      _meta(document, 'meta[property="og:image"]'),
      _meta(document, 'meta[name="twitter:image"]'),
    ]) {
      final lien = candidat?.trim() ?? '';
      if (lien.isNotEmpty) {
        urlCouverture = urlTitre.resolve(lien).toString();
        break;
      }
    }

    // Résumé : le paragraphe `p.summary` du panneau de droite, complet ;
    // la balise meta description y ajoute un texte publicitaire du site.
    // Repli : og:description (même texte, entités HTML décodées).
    var resume = _nettoyer(document.querySelector('p.summary')?.text ?? '');
    if (resume.isEmpty) {
      resume = _nettoyer(
        _meta(document, 'meta[property="og:description"]') ?? '',
      );
    }

    // Auteurs : un h3.title par créateur dans la fenêtre « Info Auteur »
    // (`._authorInnerContent`), liste complète ; le bandeau
    // `.author_area` peut la tronquer par « ... ». Le `>` écarte les titres
    // des « autres œuvres » de la même fenêtre.
    final auteurs = <String>[];
    void ajouterAuteur(String nomAuteur) {
      final propre = _nettoyer(nomAuteur);
      if (propre.isNotEmpty && propre != '...' && !auteurs.contains(propre)) {
        auteurs.add(propre);
      }
    }

    for (final titre in document.querySelectorAll(
      '._authorInnerContent > h3.title',
    )) {
      ajouterAuteur(titre.text);
    }
    if (auteurs.isEmpty) {
      // Repli : texte propre du bandeau (sans le bouton « Info Auteur »),
      // noms séparés par des virgules.
      final bandeau = document.querySelector('.detail_header .author_area');
      if (bandeau != null) {
        _texteDirect(bandeau).split(',').forEach(ajouterAuteur);
        // Certains bandeaux mettent les noms dans des liens.
        for (final lien in bandeau.querySelectorAll('a')) {
          ajouterAuteur(lien.text);
        }
      }
    }
    if (auteurs.isEmpty) {
      // Dernier repli : la meta auteur (« A / B »).
      final meta = _meta(
        document,
        'meta[property="com-linewebtoon:webtoon:author"]',
      );
      meta?.split('/').forEach(ajouterAuteur);
    }

    // Genre : le h2 `.genre` du bandeau (« Romance », « Fantasy ») ; il
    // devient une catégorie.
    final categories = <String>[];
    for (final genre in document.querySelectorAll(
      '.detail_header .info .genre',
    )) {
      final propre = _nettoyer(genre.text);
      if (propre.isNotEmpty &&
          !categories.any((c) => c.toLowerCase() == propre.toLowerCase())) {
        categories.add(propre);
      }
    }

    // Statut : texte propre de `p.day_info` (« Nouvel épisode chaque
    // VENDREDI », « EVERY MONDAY », ou la mention de fin de série), sans le
    // badge « NOUVEAU » / « UP » du span intérieur.
    final jour = document.querySelector('p.day_info');
    final statut = jour == null ? '' : _nettoyer(_texteDirect(jour));

    return FicheTitre(
      titre: Titre(
        urlTitre: urlTitre.toString(),
        nom: nom,
        // WEBTOON publie des créations coréennes, américaines, françaises…
        // sans indiquer le pays d'origine : « manhwa » serait souvent faux.
        typeTitre: TypeTitre.autre,
        urlCouverture: urlCouverture,
        resume: resume.isEmpty ? null : resume,
        auteur: auteurs.isEmpty ? null : auteurs.join(', '),
        statut: statut.isEmpty ? null : statut,
      ),
      categories: categories,
    );
  }

  /// Extrait les épisodes d'une page de la liste [html] du titre [urlTitre],
  /// dans l'ordre du site (du plus récent au plus ancien).
  ///
  /// Chaque épisode a `urlChapitre` = `urlExterne` = sa page de lecture : il
  /// se lit sur WEBTOON et n'est jamais téléchargé. Son numéro est le rang
  /// « #N » affiché par le site (continu d'une saison à l'autre, alors que
  /// « Ep. N » repart de zéro à chaque saison).
  ///
  /// Lève une [ErreurSource] si la page n'est pas une liste WEBTOON. Une page
  /// sans épisode donne une liste vide.
  static List<Chapitre> analyserEpisodes(String html, Uri urlTitre) {
    final document = parse(html);
    _verifierPageTitre(document, urlTitre);
    final langue = langueDepuisAdresse(urlTitre);

    final episodes = <Chapitre>[];
    // Chaque épisode est un `li._episodeItem` de la liste `#_listUl` ; les
    // liens « autres œuvres » de la fenêtre des auteurs pointent aussi vers
    // des listes et sont ainsi écartés.
    for (final ligne in document.querySelectorAll('#_listUl li._episodeItem')) {
      // Le seul lien du li mène au lecteur (`/viewer?…&episode_no=`).
      final lien = ligne.querySelector('a[href]');
      final href = lien?.attributes['href']?.trim() ?? '';
      if (href.isEmpty) {
        continue;
      }
      final Uri adresse;
      try {
        adresse = urlTitre.resolve(href);
      } on FormatException {
        continue;
      }
      final numeroSite = adresse.queryParameters['episode_no'] ?? '';
      if (!estHoteWebtoons(adresse.host) ||
          !adresse.path.endsWith('/viewer') ||
          numeroSite.isEmpty) {
        continue;
      }
      final url = adresse.toString();

      // Nom : `.subj` du lien (« Ep. 2 », « [Season 3] Ep. 226 ») ; repli :
      // texte alternatif de la vignette, qui porte le même nom.
      var nom = _nettoyer(ligne.querySelector('.subj')?.text ?? '');
      if (nom.isEmpty) {
        nom = _nettoyer(ligne.querySelector('img')?.attributes['alt'] ?? '');
      }

      // Numéro : rang « #N » de `.tx` ; replis : `data-episode-no` du li,
      // puis `episode_no` de l'adresse (identifiant du site, croissant).
      final rang = RegExp(r'#\s*(\d+(?:\.\d+)?)')
          .firstMatch(ligne.querySelector('.tx')?.text ?? '');
      final numero = rang != null
          ? OutilsSources.convertirNumero(rang.group(1))
          : OutilsSources.convertirNumero(
              ligne.attributes['data-episode-no'] ?? numeroSite,
            );

      final date = ligne.querySelector('.date');
      episodes.add(
        Chapitre(
          urlChapitre: url,
          nom: nom.isEmpty ? 'Épisode $numeroSite' : nom,
          numero: numero,
          langue: langue,
          datePublication: date == null ? null : convertirDate(date.text),
          urlExterne: url,
        ),
      );
    }
    return episodes;
  }

  /// Indique si la page [numeroPage] de la liste ([html]) propose un lien
  /// vers la page suivante, dans le bloc `.paginate` (lien de numéro
  /// `pg_page` ou flèche `pg_next` vers le bloc de dix pages suivant).
  static bool aPageSuivante(String html, Uri urlTitre, int numeroPage) {
    final document = parse(html);
    for (final lien in document.querySelectorAll('.paginate a[href]')) {
      final href = lien.attributes['href']?.trim() ?? '';
      // La page courante est un lien « # » sans adresse.
      if (href.isEmpty || href == '#') {
        continue;
      }
      final Uri adresse;
      try {
        adresse = urlTitre.resolve(href);
      } on FormatException {
        continue;
      }
      if (int.tryParse(adresse.queryParameters['page'] ?? '') ==
          numeroPage + 1) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Outils privés
  // ---------------------------------------------------------------------

  /// Lève une [ErreurSource] si [document] n'est pas une liste de titre :
  /// le bandeau `.detail_header` et la liste `#_listUl` sont présents sur
  /// toutes les listes et absents des pages d'erreur.
  static void _verifierPageTitre(Document document, Uri urlTitre) {
    if (document.querySelector('.detail_header') == null ||
        document.querySelector('#_listUl') == null) {
      throw ErreurSource(
        urlTitre.toString(),
        "La page reçue n'est pas une liste d'épisodes WEBTOON (structure "
        'inattendue ou titre retiré)',
      );
    }
  }

  /// Attribut `content` de la balise meta [selecteur], ou `null`.
  static String? _meta(Document document, String selecteur) =>
      document.querySelector(selecteur)?.attributes['content'];

  /// Texte propre de [element] : ses nœuds texte directs, sans le texte de
  /// ses éléments enfants (badges, boutons).
  static String _texteDirect(Element element) {
    final tampon = StringBuffer();
    for (final noeud in element.nodes) {
      if (noeud is Text) {
        tampon.write(noeud.text);
      }
    }
    return tampon.toString();
  }

  /// Regroupe les espaces (sauts de ligne compris) et retire ceux des bords.
  static String _nettoyer(String texte) =>
      texte.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Télécharge la première page de la liste [uri], ou réutilise celle lue
  /// il y a moins de [dureeCachePageWebtoons].
  Future<String> _recupererPremierePage(Uri uri) async {
    final url = uri.toString();
    final page = _dernierePage;
    final maintenant = _maintenant();
    if (page != null &&
        page.url == url &&
        maintenant.difference(page.date) < dureeCachePageWebtoons) {
      return page.html;
    }
    final html = await _recupererTexte(uri);
    _dernierePage = (url: url, html: html, date: maintenant);
    return html;
  }

  /// Télécharge une page de liste avec le User-Agent honnête de
  /// l'application : WEBTOON sert ses listes à ce User-Agent (vérifié le
  /// 2026-11-17), il est donc inutile d'usurper un navigateur.
  Future<String> _recupererTexte(Uri uri) =>
      _client.recupererTexte(uri, userAgent: userAgentApplication);

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
  /// site WEBTOON, sans perdre la pile d'appels d'origine.
  Future<T> _avecTypeSite<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ErreurSource catch (erreur, pile) {
      Error.throwWithStackTrace(
        erreur.avecContexte(typeDetecte: TypeSource.webtoons),
        pile,
      );
    }
  }
}
