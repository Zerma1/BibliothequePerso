/// Adaptateur **générique** (tâches W3 et T2) : sites qui n'ont pas de thème
/// connu, lus soit par des sélecteurs CSS réglés par le client
/// (`Source.configurationSelecteurs`), soit, sans réglage, par des
/// heuristiques pour les sites « à liens explicites ».
///
/// Site de référence : https://ruri-dragon.online (relevé le 2026-11-17,
/// pages allégées dans `test/sources/exemples_html/generique_ruri_*.html`) :
/// un site dédié à une seule œuvre dont l'accueil liste tous les chapitres
/// (`/comic/ruri-dragon-chapter-<n>/`) et dont chaque page de chapitre
/// contient les images en clair (`.images-container img`).
///
/// Heuristiques sans réglage :
/// - liens de chapitres : liens du même site dont l'adresse (ou le texte)
///   contient « chapter », « chapitre », « episode », « ch » ou « ep » suivi
///   d'un numéro ; on garde le plus grand groupe d'adresses de même forme ;
/// - fiche : `h1`, `og:title` ou `<title>` ; couverture `og:image` ou image
///   marquée « cover » / « thumb » ; résumé ; auteur, statut, type d'après
///   leur libellé (« Author: ») ; genres ;
/// - contenu : le plus grand groupe d'images d'un même conteneur ;
/// - adresse d'un chapitre collée : on remonte à la page qui liste les
///   chapitres (lien « tous les chapitres », fil d'Ariane, accueil du site).
///
/// Aucune protection n'est contournée (PLAYBOOK.md section 10) : défi
/// anti-robot, script brouillé ou images dessinées dans un canvas lèvent une
/// [ErreurSource].
library;

import 'dart:convert';

import 'package:html/dom.dart' show Document, Element, Node, Text;
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
import 'outils_wordpress.dart';
import 'protection_anti_robot.dart';
import 'source_site.dart';

/// Réglages d'un site générique, lus dans le JSON de
/// `Source.configurationSelecteurs`.
///
/// Chaque réglage est facultatif : un réglage absent ou vide laisse place à
/// l'heuristique correspondante. Les sélecteurs sont des sélecteurs CSS
/// appliqués à toute la page (ceux pris en charge par `package:html`).
class ConfigurationGenerique {
  /// Crée des réglages ; tous les champs sont facultatifs.
  const ConfigurationGenerique({
    this.selecteurTitre,
    this.selecteurCouverture,
    this.selecteurResume,
    this.selecteurAuteur,
    this.selecteurCategories,
    this.selecteurLiensChapitres,
    this.selecteurImagesChapitre,
    this.selecteurLienListeChapitres,
    this.motifNumeroChapitre,
  });

  /// Réglages vides : heuristiques seulement.
  static const ConfigurationGenerique vide = ConfigurationGenerique();

  /// Noms des clés JSON reconnues (même nom que les champs).
  static const List<String> cles = <String>[
    'selecteurTitre',
    'selecteurCouverture',
    'selecteurResume',
    'selecteurAuteur',
    'selecteurCategories',
    'selecteurLiensChapitres',
    'selecteurImagesChapitre',
    'selecteurLienListeChapitres',
    'motifNumeroChapitre',
  ];

  /// Élément dont le texte est le nom du titre (fiche).
  final String? selecteurTitre;

  /// Image de couverture (`img`, ou élément portant `content`, `href` ou
  /// `src`).
  final String? selecteurCouverture;

  /// Bloc du résumé.
  final String? selecteurResume;

  /// Élément(s) portant le nom de l'auteur (textes joints par des virgules).
  final String? selecteurAuteur;

  /// Éléments dont chacun est une catégorie (genre, tag).
  final String? selecteurCategories;

  /// Liens (ou blocs contenant un lien) vers les chapitres.
  final String? selecteurLiensChapitres;

  /// Images (ou blocs contenant une image) d'une page de chapitre, dans
  /// l'ordre de lecture.
  final String? selecteurImagesChapitre;

  /// Lien, sur une page de chapitre, vers la page qui liste les chapitres.
  final String? selecteurLienListeChapitres;

  /// Expression régulière qui trouve le numéro d'un chapitre dans son
  /// adresse puis dans son texte ; le premier groupe (ou, à défaut, tout le
  /// texte reconnu) est le numéro. Si [selecteurLiensChapitres] est absent,
  /// elle sert aussi à reconnaître les liens de chapitres par leur adresse.
  final String? motifNumeroChapitre;

  /// `true` si aucun réglage n'est renseigné.
  bool get estVide =>
      selecteurTitre == null &&
      selecteurCouverture == null &&
      selecteurResume == null &&
      selecteurAuteur == null &&
      selecteurCategories == null &&
      selecteurLiensChapitres == null &&
      selecteurImagesChapitre == null &&
      selecteurLienListeChapitres == null &&
      motifNumeroChapitre == null;

  /// Lit les réglages dans [json] (`null` ou vide : [vide]).
  ///
  /// Les valeurs vides sont ignorées, les clés inconnues aussi. Lève une
  /// [ErreurSource] (adresse [url], type générique) si le JSON est illisible,
  /// si une valeur n'est pas un texte ou si [motifNumeroChapitre] n'est pas
  /// une expression régulière valide.
  factory ConfigurationGenerique.depuisJson(String? json, {String url = ''}) {
    final texte = json?.trim() ?? '';
    if (texte.isEmpty) {
      return vide;
    }
    final Object? valeur;
    try {
      valeur = jsonDecode(texte);
    } on FormatException catch (erreur) {
      throw ErreurSource(
        url,
        'Réglages du site générique illisibles (JSON invalide)',
        cause: erreur,
        typeDetecte: TypeSource.generique,
      );
    }
    if (valeur is! Map<String, Object?>) {
      throw ErreurSource(
        url,
        'Réglages du site générique illisibles (objet JSON attendu)',
        typeDetecte: TypeSource.generique,
      );
    }
    final Map<String, Object?> carte = valeur;
    String? lire(String cle) {
      final brut = carte[cle];
      if (brut == null) {
        return null;
      }
      if (brut is! String) {
        throw ErreurSource(
          url,
          'Réglage « $cle » du site générique : texte attendu',
          typeDetecte: TypeSource.generique,
        );
      }
      final propre = brut.trim();
      return propre.isEmpty ? null : propre;
    }

    final motif = lire('motifNumeroChapitre');
    if (motif != null) {
      try {
        RegExp(motif);
      } on FormatException catch (erreur) {
        throw ErreurSource(
          url,
          'Réglage « motifNumeroChapitre » du site générique : expression '
          'régulière invalide',
          cause: erreur,
          typeDetecte: TypeSource.generique,
        );
      }
    }
    return ConfigurationGenerique(
      selecteurTitre: lire('selecteurTitre'),
      selecteurCouverture: lire('selecteurCouverture'),
      selecteurResume: lire('selecteurResume'),
      selecteurAuteur: lire('selecteurAuteur'),
      selecteurCategories: lire('selecteurCategories'),
      selecteurLiensChapitres: lire('selecteurLiensChapitres'),
      selecteurImagesChapitre: lire('selecteurImagesChapitre'),
      selecteurLienListeChapitres: lire('selecteurLienListeChapitres'),
      motifNumeroChapitre: motif,
    );
  }
}

/// Lien de chapitre repéré dans une page (usage interne).
class _LienChapitre {
  _LienChapitre(this.adresse, this.numero, this.cleGroupe, this.rang);

  final Uri adresse;
  final double numero;
  final String cleGroupe;
  final int rang;

  /// Nom retenu et sa qualité : 2 = texte du lien qui contient « Chapter
  /// 12 » ; 1 = attribut `aria-label` / `title` ; 0 = nom fabriqué.
  String nom = '';
  int qualiteNom = -1;

  /// Morceaux de texte de tous les liens vers ce chapitre (nom, date…).
  final List<String> segments = <String>[];
}

/// Lecture d'un site générique : fiche, chapitres et images.
///
/// Toute [ErreurSource] levée par ses méthodes publiques porte
/// `typeDetecte == TypeSource.generique` et, quand une page a été reçue, son
/// début nettoyé (`extraitReponse`).
class SourceGenerique implements SourceSite {
  /// Crée l'adaptateur du site [urlBase] avec ses [configuration] (vides par
  /// défaut : heuristiques).
  ///
  /// [languesPreferees] (« fr,en ») ne sert qu'à défaut de langue déclarée
  /// par la page (`<html lang>`). [maintenant] remplace l'horloge dans les
  /// tests.
  SourceGenerique(
    this._client, {
    required this.urlBase,
    this.configuration = ConfigurationGenerique.vide,
    this.languesPreferees = '',
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? DateTime.now;

  final ClientHttpPoli _client;
  final DateTime Function() _maintenant;

  /// Adresse du site (`Source.urlBase`) : son accueil est essayé quand une
  /// adresse de chapitre est collée (site dédié à une seule œuvre).
  final String urlBase;

  /// Réglages du site (sélecteurs CSS, motif du numéro).
  final ConfigurationGenerique configuration;

  /// Langues du client (« fr,en »), repli de la langue des chapitres.
  final String languesPreferees;

  /// Pages récemment téléchargées (adresse → HTML, date).
  final Map<String, ({String html, DateTime date})> _pages =
      <String, ({String html, DateTime date})>{};

  /// Adresses de chapitre déjà résolues vers la page qui liste les chapitres.
  final Map<String, ({Uri url, DateTime date})> _resolutions =
      <String, ({Uri url, DateTime date})>{};

  // Mot-clé d'un chapitre suivi de son numéro dans une ADRESSE :
  // « chapter-12 », « chapitre_3 », « episode/7 », « ch-10-5 » (10.5).
  // Le regard arrière (pas de lettre avant) écarte « watch-2 » ou
  // « sleep-1 » ; le regard avant écarte « chapter-12abc ».
  static final RegExp _motifAdresse = RegExp(
    r'(?<![a-z])(?:chapters?|chapitres?|chap|ch|episodes?|épisodes?|ep)'
    r'[-_./]?(\d+)(?:[-_.](\d+))?(?![a-z\d])',
    caseSensitive: false,
  );

  // Même mot-clé dans un TEXTE : « Chapter 12 », « Chapitre 10,5 »,
  // « Ep. 3 », « Épisode 4 ».
  static final RegExp _motifTexte = RegExp(
    r'(?<![a-z])(?:chapters?|chapitres?|chap|ch|episodes?|épisodes?|ep)'
    r'\.?\s*(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  );

  // Texte d'un lien vers la page qui liste tous les chapitres.
  static final RegExp _motifLienListe = RegExp(
    r'(tous les chapitres|liste des chapitres|all chapters|chapter list|'
    r'chapters list|chapter index|manga info|series info|'
    r'back to (the )?(manga|series|comic)|retour (au|à la) (manga|série|fiche))',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------
  // SourceSite
  // ---------------------------------------------------------------------

  /// Un site générique n'a pas de moteur de recherche connu : une requête
  /// non vide lève une [ErreurSource] qui invite à coller l'adresse du
  /// titre (une liste vide ferait croire à « aucun résultat »).
  @override
  Future<List<Titre>> rechercher(String requete) async {
    if (requete.trim().isEmpty) {
      return const <Titre>[];
    }
    throw ErreurSource(
      urlBase,
      "La recherche n'est pas disponible pour ce site (site générique) : "
      "collez l'adresse de la page du titre, celle qui liste les chapitres",
      typeDetecte: TypeSource.generique,
    );
  }

  /// Récupère la fiche du titre de [urlTitre] (adresse du titre, de
  /// l'accueil d'un site dédié à une œuvre, ou d'un de ses chapitres).
  ///
  /// La fiche porte l'adresse de la page qui liste les chapitres
  /// (`Titre.urlTitre`), même si [urlTitre] était celle d'un chapitre.
  @override
  Future<FicheTitre> recupererFiche(String urlTitre) {
    return OutilsWordPress.avecType(TypeSource.generique, () async {
      final page = await _recupererPageTitre(urlTitre);
      return OutilsWordPress.avecExtrait(
        page.html,
        () => analyserFiche(page.html, page.url, configuration: configuration),
      );
    });
  }

  /// Récupère les chapitres de [urlTitre] (même page que [recupererFiche]),
  /// du plus ancien au plus récent.
  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) {
    return OutilsWordPress.avecType(TypeSource.generique, () async {
      final page = await _recupererPageTitre(urlTitre);
      return OutilsWordPress.avecExtrait(page.html, () {
        final chapitres = analyserChapitres(
          page.html,
          page.url,
          configuration: configuration,
          languesPreferees: languesPreferees,
          maintenant: _maintenant(),
        );
        if (chapitres.isEmpty) {
          throw ErreurSource(page.url.toString(), _messageSansChapitre);
        }
        return chapitres;
      });
    });
  }

  /// Récupère les adresses des images du chapitre [urlChapitre].
  ///
  /// Les images sont demandées avec le `Referer` de la racine du site
  /// (`ContenuChapitre.urlReferer`), comme le fait le navigateur d'un
  /// lecteur, même si elles sont hébergées ailleurs.
  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) {
    return OutilsWordPress.avecType(TypeSource.generique, () async {
      final uri = validerUrl(urlChapitre);
      final html = await _recupererPage(uri);
      return OutilsWordPress.avecExtrait(
        html,
        () => analyserContenu(html, uri, configuration: configuration),
      );
    });
  }

  // ---------------------------------------------------------------------
  // Adresses
  // ---------------------------------------------------------------------

  /// Valide une adresse de page (`http`/`https` et un hôte) et la renvoie
  /// sans fragment ; lève une [ErreurSource] sinon. Le chemin peut être vide
  /// (accueil d'un site dédié à une œuvre).
  static Uri validerUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return uri.removeFragment();
    }
    throw ErreurSource(
      url,
      'Adresse invalide : http:// ou https:// et un nom de domaine attendus',
      typeDetecte: TypeSource.generique,
    );
  }

  /// Indique si [adresse] est celle d'un chapitre : son chemin contient
  /// « chapter-12 », « chapitre-3 », « episode-7 »… (ou correspond à
  /// [ConfigurationGenerique.motifNumeroChapitre] s'il est réglé).
  static bool estAdresseChapitre(
    Uri adresse, {
    ConfigurationGenerique configuration = ConfigurationGenerique.vide,
  }) {
    final chemin = _cheminDecode(adresse);
    final motif = configuration.motifNumeroChapitre;
    if (motif != null && RegExp(motif, caseSensitive: false).hasMatch(chemin)) {
      return true;
    }
    return _motifAdresse.hasMatch(chemin);
  }

  // ---------------------------------------------------------------------
  // Analyse du HTML (sans réseau, publique pour les tests et le diagnostic)
  // ---------------------------------------------------------------------

  /// Chapitres listés dans la page [html] (adresse [urlPage]), du plus
  /// ancien au plus récent (numéro croissant). Liste vide si aucun lien de
  /// chapitre n'est trouvé.
  ///
  /// Langue : `lang` de la page, à défaut la première de [languesPreferees].
  /// Lève une [ErreurSource] si la page est un défi anti-robot ou si un
  /// réglage est invalide.
  static List<Chapitre> analyserChapitres(
    String html,
    Uri urlPage, {
    ConfigurationGenerique configuration = ConfigurationGenerique.vide,
    String languesPreferees = '',
    DateTime? maintenant,
  }) {
    _verifierPasDeDefi(html, urlPage);
    final document = parse(html);
    final langue = OutilsWordPress.langueDepuisPage(document, languesPreferees);
    final heure = maintenant ?? DateTime.now();
    final liens = _liensChapitres(document, urlPage, configuration);
    final chapitres = <({Chapitre chapitre, int rang})>[];
    for (final lien in liens) {
      DateTime? date;
      for (final segment in lien.segments) {
        if (segment == lien.nom) {
          continue;
        }
        date = OutilsWordPress.convertirDate(segment, heure);
        if (date != null) {
          break;
        }
      }
      chapitres.add((
        chapitre: Chapitre(
          urlChapitre: lien.adresse.toString(),
          nom: lien.nom,
          numero: lien.numero,
          langue: langue,
          datePublication: date,
        ),
        rang: lien.rang,
      ));
    }
    // Ordre de lecture : numéro croissant ; à numéro égal, ordre de la page.
    chapitres.sort((a, b) {
      final parNumero = a.chapitre.numero.compareTo(b.chapitre.numero);
      return parNumero != 0 ? parNumero : a.rang.compareTo(b.rang);
    });
    return <Chapitre>[for (final c in chapitres) c.chapitre];
  }

  /// Fiche du titre à partir du [html] de la page [urlPage] qui liste ses
  /// chapitres.
  ///
  /// Lève une [ErreurSource] si la page est un défi anti-robot, si elle ne
  /// contient aucun lien de chapitre (ce n'est alors pas une page de titre
  /// lisible) ou si aucun nom n'est trouvé.
  static FicheTitre analyserFiche(
    String html,
    Uri urlPage, {
    ConfigurationGenerique configuration = ConfigurationGenerique.vide,
  }) {
    _verifierPasDeDefi(html, urlPage);
    final document = parse(html);
    if (_liensChapitres(document, urlPage, configuration).isEmpty) {
      throw ErreurSource(urlPage.toString(), _messageSansChapitre);
    }

    // Nom : réglage, sinon le premier h1 non vide (le nom de l'œuvre sur la
    // page qui la présente), puis og:title et <title> (« Nom – Site »).
    var nom = '';
    final selecteurTitre = configuration.selecteurTitre;
    if (selecteurTitre != null) {
      nom = OutilsWordPress.nettoyer(
        _selectionner(
          document,
          selecteurTitre,
          'selecteurTitre',
          urlPage,
        ).map((e) => e.text).join(' '),
      );
    }
    if (nom.isEmpty) {
      for (final h1 in document.querySelectorAll('h1')) {
        nom = OutilsWordPress.nettoyer(h1.text);
        if (nom.isNotEmpty) {
          break;
        }
      }
    }
    if (nom.isEmpty) {
      nom =
          OutilsWordPress.meta(document, 'meta[property="og:title"]') ??
          OutilsWordPress.nomDepuisTitrePage(document);
    }
    if (nom.isEmpty) {
      throw ErreurSource(
        urlPage.toString(),
        'Page de titre sans nom (ni h1, ni og:title, ni <title>) : réglez '
        '« selecteurTitre »',
      );
    }

    return FicheTitre(
      titre: Titre(
        urlTitre: _adresseCanonique(document, urlPage, configuration),
        nom: nom,
        typeTitre: OutilsWordPress.typeDepuisTexte(
          _valeurLibelle(
            document,
            RegExp(r'type|tipo|tipe|format', caseSensitive: false),
          ),
        ),
        urlCouverture: _couverture(document, urlPage, configuration),
        resume: _resume(document, urlPage, configuration),
        auteur: _auteur(document, urlPage, configuration),
        statut: _valeurLibelle(
          document,
          RegExp(r'status|statut|estado', caseSensitive: false),
        ),
      ),
      categories: _categories(document, urlPage, configuration),
    );
  }

  /// Contenu de la page de chapitre [html] (adresse [urlChapitre]).
  ///
  /// Images : celles du réglage `selecteurImagesChapitre`, sinon le plus
  /// grand groupe d'images d'un même conteneur (la zone de lecture), lues
  /// dans `src`, `data-src`, `data-lazy-src`… Le `Referer` est la racine du
  /// site.
  ///
  /// Lève une [ErreurSource] si la page est un défi anti-robot, si les
  /// images sont cachées (script brouillé, canvas) ou introuvables.
  static ContenuChapitre analyserContenu(
    String html,
    Uri urlChapitre, {
    ConfigurationGenerique configuration = ConfigurationGenerique.vide,
  }) {
    _verifierPasDeDefi(html, urlChapitre);
    final document = parse(html);
    final images = imagesChapitre(document, urlChapitre, configuration);
    if (images.isEmpty) {
      throw ErreurSource(
        urlChapitre.toString(),
        raisonSansImage(document) ??
            'Aucune image de chapitre trouvée dans la page (images chargées '
                'par un script ou zone de lecture non reconnue) : réglez '
                '« selecteurImagesChapitre » ou lisez le chapitre sur le site',
      );
    }
    return ContenuChapitre.images(
      images,
      urlReferer: OutilsWordPress.racineSite(urlChapitre),
    );
  }

  /// Pages candidates, dans l'ordre d'essai, pour remonter de la page de
  /// chapitre [html] (adresse [urlChapitre]) à la page qui liste les
  /// chapitres.
  ///
  /// Ordre : lien du réglage `selecteurLienListeChapitres` ; lien « tous les
  /// chapitres » ; élément du fil d'Ariane dont le texte figure dans le nom
  /// du chapitre (« Ruri Dragon » dans « Ruri Dragon, Chapter 1 ») ; accueil
  /// du site [urlBase] (site dédié à une seule œuvre) ; autres éléments du
  /// fil d'Ariane, du plus proche au plus lointain. Les adresses de chapitre
  /// et les autres sites sont écartés.
  static List<Uri> candidatsPageListe(
    String html,
    Uri urlChapitre, {
    ConfigurationGenerique configuration = ConfigurationGenerique.vide,
    String? urlBase,
  }) {
    final document = parse(html);
    final candidats = <Uri>[];
    final cles = <String>{_cleAdresse(urlChapitre)};
    void ajouter(String? href, {bool memeSiteSeulement = true}) {
      final lien = href?.trim() ?? '';
      if (lien.isEmpty || lien.startsWith('#')) {
        return;
      }
      final Uri adresse;
      try {
        adresse = urlChapitre.resolve(lien).removeFragment();
      } on FormatException {
        return;
      }
      if ((adresse.scheme != 'http' && adresse.scheme != 'https') ||
          (memeSiteSeulement && !_memeSite(adresse, urlChapitre)) ||
          estAdresseChapitre(adresse, configuration: configuration)) {
        return;
      }
      if (cles.add(_cleAdresse(adresse))) {
        candidats.add(adresse);
      }
    }

    final selecteur = configuration.selecteurLienListeChapitres;
    if (selecteur != null) {
      for (final element in _selectionner(
        document,
        selecteur,
        'selecteurLienListeChapitres',
        urlChapitre,
      )) {
        final lien = element.localName == 'a'
            ? element
            : element.querySelector('a[href]');
        ajouter(lien?.attributes['href'], memeSiteSeulement: false);
      }
    }

    // Lien explicite vers la liste : texte « All chapters », « Tous les
    // chapitres », « Back to manga »… (ou son title / aria-label).
    for (final lien in document.querySelectorAll('a[href]')) {
      final texte =
          '${lien.text} ${lien.attributes['title'] ?? ''} '
          '${lien.attributes['aria-label'] ?? ''}';
      if (_motifLienListe.hasMatch(texte)) {
        ajouter(lien.attributes['href']);
      }
    }

    // Fil d'Ariane : classes et attributs usuels (« breadcrumb(s) »,
    // schema.org BreadcrumbList, `nav[aria-label=breadcrumb]`). Le sélecteur
    // `[class*="readcrumb"]` couvre « breadcrumb » et « Breadcrumb ».
    final ariane = document
        .querySelectorAll(
          '[class*="readcrumb"] a[href], [id*="readcrumb"] a[href], '
          '[itemtype*="BreadcrumbList"] a[href], '
          'nav[aria-label*="readcrumb"] a[href]',
        )
        .reversed
        .toList();
    final nomChapitre = OutilsWordPress.nettoyer(
      '${document.querySelector('h1')?.text ?? ''} '
      '${document.querySelector('title')?.text ?? ''}',
    ).toLowerCase();
    final autres = <Element>[];
    for (final lien in ariane) {
      final texte = OutilsWordPress.nettoyer(lien.text).toLowerCase();
      if (texte.length >= 3 && nomChapitre.contains(texte)) {
        ajouter(lien.attributes['href']);
      } else {
        autres.add(lien);
      }
    }

    // Accueil : un site dédié à une seule œuvre y liste tous ses chapitres.
    final base = urlBase == null ? null : Uri.tryParse(urlBase.trim());
    if (base != null && base.host.isNotEmpty && _memeSite(base, urlChapitre)) {
      ajouter(base.resolve('/').toString());
    } else {
      ajouter(OutilsWordPress.racineSite(urlChapitre));
    }
    for (final lien in autres) {
      ajouter(lien.attributes['href']);
    }
    return candidats;
  }

  /// Adresses absolues des images de la zone de lecture de [document]
  /// (vide si aucune) : réglage `selecteurImagesChapitre`, sinon le plus
  /// grand groupe d'images d'un même conteneur, s'il en compte au moins
  /// [nombreMinImagesChapitreGenerique].
  static List<String> imagesChapitre(
    Document document,
    Uri urlChapitre, [
    ConfigurationGenerique configuration = ConfigurationGenerique.vide,
  ]) {
    final selecteur = configuration.selecteurImagesChapitre;
    if (selecteur != null) {
      final urls = <String>[];
      for (final element in _selectionner(
        document,
        selecteur,
        'selecteurImagesChapitre',
        urlChapitre,
      )) {
        final images = element.localName == 'img'
            ? <Element>[element]
            : element.querySelectorAll('img');
        for (final image in images) {
          final adresse = OutilsWordPress.adresseImage(image, urlChapitre);
          if (adresse != null && !urls.contains(adresse)) {
            urls.add(adresse);
          }
        }
      }
      return urls;
    }

    // Chaque image est rattachée au conteneur de son « bloc » : on remonte
    // tant que le parent ne contient qu'elle (`<p><img></p>`,
    // `<figure><img></figure>`, `<div class="page"><img></div>`). Les pages
    // d'un chapitre partagent ainsi le même conteneur (ruri-dragon.online :
    // `.images-container > p > img`), alors qu'un logo, une bannière ou un
    // bouton de dons restent seuls dans le leur.
    final groupes = <Element, List<String>>{};
    for (final image in document.querySelectorAll('img')) {
      final adresse = OutilsWordPress.adresseImage(image, urlChapitre);
      if (adresse == null) {
        continue;
      }
      var bloc = image;
      var parent = bloc.parent;
      while (parent != null &&
          parent.localName != 'body' &&
          parent.querySelectorAll('img').length == 1) {
        bloc = parent;
        parent = bloc.parent;
      }
      if (parent == null) {
        continue;
      }
      final urls = groupes.putIfAbsent(parent, () => <String>[]);
      if (!urls.contains(adresse)) {
        urls.add(adresse);
      }
    }
    var meilleur = const <String>[];
    for (final urls in groupes.values) {
      if (urls.length > meilleur.length) {
        meilleur = urls;
      }
    }
    return meilleur.length >= nombreMinImagesChapitreGenerique
        ? meilleur
        : const <String>[];
  }

  /// Raison connue pour laquelle les images d'une page de chapitre ne sont
  /// pas lisibles, ou `null` : images cachées derrière un script brouillé
  /// (`eval` + `atob`, « packer » `function(p,a,c,k,e`), ou dessinées dans
  /// un `canvas` (souvent chiffrées). Aucune n'est décodée (PLAYBOOK.md
  /// section 10).
  static String? raisonSansImage(Document document) {
    for (final script in document.querySelectorAll('script')) {
      final texte = script.text;
      if (texte.contains('eval(') &&
          (texte.contains('atob(') ||
              texte.contains('function(p,a,c,k,e') ||
              texte.contains('fromCharCode'))) {
        return 'Les images du chapitre sont cachées derrière un script '
            "brouillé : l'application ne le décode pas (à lire sur le site)";
      }
    }
    if (document.querySelector('canvas') != null) {
      return 'Les pages du chapitre sont dessinées par un script (canvas), '
          "probablement chiffrées : l'application ne les lit pas (à lire "
          'sur le site)';
    }
    return null;
  }

  /// Nombre de liens de chapitres retenus dans [document] (diagnostic).
  static int compterLiensChapitres(
    Document document,
    Uri urlPage, [
    ConfigurationGenerique configuration = ConfigurationGenerique.vide,
  ]) => _liensChapitres(document, urlPage, configuration).length;

  /// Message d'une page sans lien de chapitre.
  static const String _messageSansChapitre =
      'Aucun lien de chapitre trouvé sur cette page : les liens doivent '
      'mener au même site et contenir « chapter », « chapitre », '
      '« episode », « ch » ou « ep » suivi du numéro (dans leur adresse ou '
      'leur texte). Sinon, réglez « selecteurLiensChapitres »';

  // ---------------------------------------------------------------------
  // Outils privés : chapitres
  // ---------------------------------------------------------------------

  /// Liens de chapitres de [document], sans doublon, dans l'ordre de la
  /// page.
  static List<_LienChapitre> _liensChapitres(
    Document document,
    Uri urlPage,
    ConfigurationGenerique configuration,
  ) {
    final motifRegle = configuration.motifNumeroChapitre == null
        ? null
        : RegExp(configuration.motifNumeroChapitre!, caseSensitive: false);
    final selecteur = configuration.selecteurLiensChapitres;
    final List<Element> elements;
    if (selecteur != null) {
      elements = <Element>[
        for (final element in _selectionner(
          document,
          selecteur,
          'selecteurLiensChapitres',
          urlPage,
        ))
          if (element.localName == 'a')
            element
          else if (element.querySelector('a[href]') case final Element lien)
            lien,
      ];
    } else {
      elements = document.querySelectorAll('a[href]');
    }

    // Liens regroupés par « forme » d'adresse (le numéro remplacé par
    // `{n}`) : les chapitres d'une œuvre partagent la même forme
    // (`/comic/ruri-dragon-chapter-{n}/`), alors qu'un lien isolé (menu,
    // autre œuvre en barre latérale) forme un petit groupe à part.
    final groupes = <String, Map<String, _LienChapitre>>{};
    var rang = 0;
    for (final element in elements) {
      final href = element.attributes['href']?.trim() ?? '';
      if (href.isEmpty ||
          href.startsWith('#') ||
          href.toLowerCase().startsWith('javascript:') ||
          href.toLowerCase().startsWith('mailto:')) {
        continue;
      }
      final Uri adresse;
      try {
        adresse = urlPage.resolve(href).removeFragment();
      } on FormatException {
        continue;
      }
      if (adresse.scheme != 'http' && adresse.scheme != 'https') {
        continue;
      }
      // Sans réglage, seuls les liens du même site comptent : un lien vers
      // un autre site n'est pas un chapitre lisible ici.
      if (selecteur == null && !_memeSite(adresse, urlPage)) {
        continue;
      }
      final segments = _segmentsTexte(element);
      final analyse = _analyserLien(
        adresse,
        segments,
        element,
        motifRegle,
        accepterSansNumero: selecteur != null,
      );
      if (analyse == null) {
        continue;
      }
      final cleGroupe = selecteur != null ? 'reglage' : analyse.cleGroupe;
      final groupe = groupes.putIfAbsent(
        cleGroupe,
        () => <String, _LienChapitre>{},
      );
      final cle = _cleAdresse(adresse);
      final lien = groupe.putIfAbsent(
        cle,
        () => _LienChapitre(adresse, analyse.numero, cleGroupe, rang++),
      );
      // Plusieurs liens vers le même chapitre (« Premier chapitre », liste,
      // « Suivant ») : on garde le meilleur nom, et les morceaux de texte de
      // tous ces liens (la date n'est souvent que dans la liste).
      if (analyse.qualiteNom > lien.qualiteNom) {
        lien
          ..nom = analyse.nom
          ..qualiteNom = analyse.qualiteNom;
      }
      lien.segments.addAll(segments);
    }
    var meilleur = const <_LienChapitre>[];
    for (final groupe in groupes.values) {
      if (groupe.length > meilleur.length) {
        meilleur = groupe.values.toList();
      }
    }
    return meilleur;
  }

  /// Analyse un lien : numéro, forme de l'adresse et nom ; `null` si ce
  /// n'est pas un lien de chapitre.
  static ({double numero, String cleGroupe, String nom, int qualiteNom})?
  _analyserLien(
    Uri adresse,
    List<String> segments,
    Element element,
    RegExp? motifRegle, {
    required bool accepterSansNumero,
  }) {
    final chemin = _cheminDecode(adresse);

    // Nom : morceau du texte qui contient « Chapter 12 » (ou le motif
    // réglé) ; sinon `aria-label` / `title` ; sinon un nom fabriqué.
    final motifNom = motifRegle ?? _motifTexte;
    String? nom;
    var qualite = 0;
    double? numeroTexte;
    for (final segment in segments) {
      final m = motifNom.firstMatch(segment);
      if (m != null) {
        nom = segment;
        qualite = 2;
        numeroTexte = OutilsSources.convertirNumero(m.group(1) ?? m.group(0));
        break;
      }
    }
    if (nom == null) {
      for (final attribut in <String>['aria-label', 'title']) {
        final valeur = OutilsWordPress.nettoyer(
          element.attributes[attribut] ?? '',
        );
        final m = motifNom.firstMatch(valeur);
        if (m != null) {
          nom = valeur;
          qualite = 1;
          numeroTexte = OutilsSources.convertirNumero(m.group(1) ?? m.group(0));
          break;
        }
      }
    }

    // Numéro : d'abord l'adresse (« chapter-49-2 » → 49.2, plus précis que
    // le texte « Chapter 49 »), puis le texte.
    double? numero;
    String? cleGroupe;
    if (motifRegle != null) {
      final m = _dernier(motifRegle.allMatches(chemin));
      if (m != null) {
        numero = OutilsSources.convertirNumero(m.group(1) ?? m.group(0));
        cleGroupe = chemin.replaceRange(m.start, m.end, '{n}');
      }
    } else {
      final m = _dernier(_motifAdresse.allMatches(chemin));
      if (m != null) {
        final decimale = m.group(2);
        numero = OutilsSources.convertirNumero(
          decimale == null ? m.group(1) : '${m.group(1)}.$decimale',
        );
        cleGroupe = chemin.replaceRange(m.start, m.end, '{n}');
      }
    }
    if (numero == null && numeroTexte != null) {
      numero = numeroTexte;
      cleGroupe = 'texte:${chemin.replaceAll(RegExp(r'\d+'), '{n}')}';
    }
    if (numero == null) {
      if (!accepterSansNumero) {
        return null;
      }
      numero = 0;
      cleGroupe = 'reglage';
    }
    if (nom == null) {
      final texte = OutilsWordPress.nettoyer(segments.join(' '));
      nom = accepterSansNumero && texte.isNotEmpty
          ? texte
          : 'Chapitre ${_formaterNumero(numero)}';
    }
    return (
      numero: numero,
      cleGroupe: cleGroupe!,
      nom: nom,
      qualiteNom: qualite,
    );
  }

  /// Morceaux de texte de [element] (nœuds texte nettoyés, scripts exclus) :
  /// « First Chapter », « Chapter 1 », « May 14, 2026 »…
  static List<String> _segmentsTexte(Element element) {
    final segments = <String>[];
    void parcourir(Node noeud) {
      for (final enfant in noeud.nodes) {
        if (enfant is Text) {
          final texte = OutilsWordPress.nettoyer(enfant.text);
          if (texte.isNotEmpty) {
            segments.add(texte);
          }
        } else if (enfant is Element &&
            enfant.localName != 'script' &&
            enfant.localName != 'style') {
          parcourir(enfant);
        }
      }
    }

    parcourir(element);
    return segments;
  }

  static RegExpMatch? _dernier(Iterable<RegExpMatch> correspondances) {
    RegExpMatch? dernier;
    for (final m in correspondances) {
      dernier = m;
    }
    return dernier;
  }

  /// « 1 » pour 1.0, « 49.2 » pour 49.2.
  static String _formaterNumero(double numero) =>
      numero == numero.truncateToDouble()
      ? numero.toInt().toString()
      : numero.toString();

  // ---------------------------------------------------------------------
  // Outils privés : fiche
  // ---------------------------------------------------------------------

  /// Adresse retenue pour le titre : `link[rel=canonical]` s'il désigne une
  /// page du même site qui n'est pas un chapitre (adresse sans redirection,
  /// avec la barre finale du site), sinon [urlPage].
  static String _adresseCanonique(
    Document document,
    Uri urlPage,
    ConfigurationGenerique configuration,
  ) {
    final href =
        document
            .querySelector('link[rel="canonical"]')
            ?.attributes['href']
            ?.trim() ??
        '';
    if (href.isNotEmpty) {
      try {
        final canonique = urlPage.resolve(href).removeFragment();
        if ((canonique.scheme == 'http' || canonique.scheme == 'https') &&
            _memeSite(canonique, urlPage) &&
            !estAdresseChapitre(canonique, configuration: configuration)) {
          return canonique.toString();
        }
      } on FormatException {
        // Adresse canonique mal écrite : on garde celle de la page.
      }
    }
    return urlPage.toString();
  }

  /// Couverture : réglage, sinon `og:image` / `twitter:image`, sinon la
  /// première image dont la classe, l'identifiant ou le texte alternatif
  /// parle de couverture (« cover », « thumb », « poster »).
  static String? _couverture(
    Document document,
    Uri urlPage,
    ConfigurationGenerique configuration,
  ) {
    final selecteur = configuration.selecteurCouverture;
    if (selecteur != null) {
      for (final element in _selectionner(
        document,
        selecteur,
        'selecteurCouverture',
        urlPage,
      )) {
        final image = element.localName == 'img'
            ? element
            : element.querySelector('img');
        if (image != null) {
          final adresse = OutilsWordPress.adresseImage(image, urlPage);
          if (adresse != null) {
            return adresse;
          }
        }
        for (final attribut in <String>['content', 'href', 'src']) {
          final valeur = element.attributes[attribut]?.trim() ?? '';
          if (valeur.isNotEmpty && !valeur.startsWith('data:')) {
            return urlPage.resolve(valeur).toString();
          }
        }
      }
    }
    final meta =
        OutilsWordPress.meta(document, 'meta[property="og:image"]') ??
        OutilsWordPress.meta(document, 'meta[name="twitter:image"]');
    if (meta != null) {
      return urlPage.resolve(meta).toString();
    }
    // ruri-dragon.online n'a pas d'og:image : sa couverture est
    // `img.manga-thumb` (alt « Ruri Dragon Cover Image »).
    final indices = RegExp(r'cover|thumb|poster|couverture');
    for (final image in document.querySelectorAll('img')) {
      final description =
          '${image.className} ${image.id} ${image.attributes['alt'] ?? ''}'
              .toLowerCase();
      if (indices.hasMatch(description)) {
        final adresse = OutilsWordPress.adresseImage(image, urlPage);
        if (adresse != null) {
          return adresse;
        }
      }
    }
    return null;
  }

  /// Résumé : réglage, sinon le bloc le plus précis dont la classe parle de
  /// description / résumé (`desc`, `summary`, `synopsis`), ou
  /// `[itemprop=description]`, d'au moins [longueurMinResumeGenerique]
  /// caractères ; sinon `og:description` / `meta[name=description]`.
  static String? _resume(
    Document document,
    Uri urlPage,
    ConfigurationGenerique configuration,
  ) {
    final selecteur = configuration.selecteurResume;
    if (selecteur != null) {
      final blocs = _selectionner(
        document,
        selecteur,
        'selecteurResume',
        urlPage,
      );
      final texte = blocs.map(OutilsWordPress.texteParagraphes).join('\n');
      if (texte.trim().isNotEmpty) {
        return texte.trim();
      }
    }
    // Le bloc « le plus précis » : un bloc qui contient lui-même un autre
    // bloc candidat assez long est écarté (ruri-dragon.online :
    // `div.info-desc` contient le nom, les genres et `span.desc`, seul ce
    // dernier est le résumé).
    const selecteurBlocs =
        '[class*="desc"], [class*="summary"], [class*="synopsis"], '
        '[class*="resume"], [itemprop="description"]';
    bool assezLong(Element e) =>
        OutilsWordPress.nettoyer(e.text).length >= longueurMinResumeGenerique;
    for (final bloc in document.querySelectorAll(selecteurBlocs)) {
      if (bloc.localName == 'meta' || !assezLong(bloc)) {
        continue;
      }
      if (bloc.querySelectorAll(selecteurBlocs).any(assezLong)) {
        continue;
      }
      return OutilsWordPress.texteParagraphes(bloc);
    }
    return OutilsWordPress.meta(document, 'meta[property="og:description"]') ??
        OutilsWordPress.meta(document, 'meta[name="description"]');
  }

  /// Auteur(s) : réglage, sinon les lignes « Author: » puis « Artist: ».
  static String? _auteur(
    Document document,
    Uri urlPage,
    ConfigurationGenerique configuration,
  ) {
    final selecteur = configuration.selecteurAuteur;
    final noms = <String>[];
    void ajouter(String? texte) {
      for (final nom in OutilsWordPress.separerNoms(texte ?? '')) {
        if (!noms.contains(nom)) {
          noms.add(nom);
        }
      }
    }

    if (selecteur != null) {
      for (final element in _selectionner(
        document,
        selecteur,
        'selecteurAuteur',
        urlPage,
      )) {
        ajouter(OutilsWordPress.nettoyer(element.text));
      }
    }
    if (noms.isEmpty) {
      ajouter(
        _valeurLibelle(
          document,
          RegExp(
            r'authors?|auteurs?|autor|writer|scénario',
            caseSensitive: false,
          ),
        ),
      );
      ajouter(
        _valeurLibelle(
          document,
          RegExp(
            r'artists?|artistes?|dessin|illustrat\w*',
            caseSensitive: false,
          ),
        ),
      );
    }
    return noms.isEmpty ? null : noms.join(', ');
  }

  /// Catégories : réglage (un élément par catégorie), sinon les éléments
  /// d'un bloc dont la classe contient « genre » (`.genre-list
  /// .genre-list-item` sur ruri-dragon.online, `.genres a` ailleurs).
  static List<String> _categories(
    Document document,
    Uri urlPage,
    ConfigurationGenerique configuration,
  ) {
    final categories = <String>[];
    void ajouter(String texte) {
      final genre = OutilsWordPress.nettoyer(texte);
      // Un genre est court : un texte long est un bloc entier, pas un tag.
      if (genre.isNotEmpty &&
          genre.length <= 40 &&
          !categories.any((c) => c.toLowerCase() == genre.toLowerCase())) {
        categories.add(genre);
      }
    }

    final selecteur = configuration.selecteurCategories;
    if (selecteur != null) {
      for (final element in _selectionner(
        document,
        selecteur,
        'selecteurCategories',
        urlPage,
      )) {
        ajouter(element.text);
      }
      return categories;
    }
    for (final bloc in document.querySelectorAll('[class*="genre"]')) {
      final elements = bloc.querySelectorAll('a, span, li');
      for (final element in elements) {
        // Seuls les éléments « feuilles » portent un nom de genre (un `li`
        // qui contient un `a` le répéterait).
        if (element.querySelector('a, span, li') == null) {
          ajouter(element.text);
        }
      }
      if (categories.isNotEmpty) {
        break;
      }
    }
    return categories;
  }

  /// Valeur d'une ligne d'informations « Libellé : valeur » dont le libellé
  /// correspond à [libelle] (`<p>Author(s): <span>Nom</span></p>`,
  /// `<li><b>Status</b> Ongoing</li>`, `<dt>Type</dt><dd>Manga</dd>`), ou
  /// `null`.
  ///
  /// Le libellé doit être suivi de « : » ou terminer le texte propre de
  /// l'élément : « Type of Issue » (formulaire de signalement) n'est pas
  /// une ligne « Type ».
  static String? _valeurLibelle(Document document, RegExp libelle) {
    final motif = RegExp(
      '^(?:${libelle.pattern})(?:\\s*\\(s\\))?\\s*(?::\\s*(.*))?\$',
      caseSensitive: false,
    );
    for (final element in document.querySelectorAll(
      'p, li, div, span, td, th, dt, b, strong, label',
    )) {
      final direct = OutilsWordPress.nettoyer(
        OutilsWordPress.texteDirect(element),
      );
      final m = motif.firstMatch(direct);
      if (m == null) {
        continue;
      }
      var valeur = OutilsWordPress.nettoyer(m.group(1) ?? '');
      if (valeur.isEmpty) {
        // Valeur dans un enfant (`<span>Nom</span>`) : texte complet de
        // l'élément sans son libellé.
        final complet = OutilsWordPress.nettoyer(element.text);
        valeur = complet.startsWith(direct)
            ? complet.substring(direct.length).trim()
            : '';
      }
      if (valeur.isEmpty) {
        // Valeur dans l'élément suivant (`<dt>Type</dt><dd>Manga</dd>`,
        // `<b>Status</b><span>Ongoing</span>`).
        valeur = OutilsWordPress.nettoyer(
          element.nextElementSibling?.text ?? '',
        );
      }
      if (valeur.isNotEmpty && valeur != '-' && valeur.length <= 200) {
        return valeur;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Outils privés : communs
  // ---------------------------------------------------------------------

  /// Éléments de [document] choisis par le [selecteur] du réglage
  /// [reglage] ; lève une [ErreurSource] claire si le sélecteur est invalide
  /// ou non pris en charge par `package:html`.
  static List<Element> _selectionner(
    Document document,
    String selecteur,
    String reglage,
    Uri url,
  ) {
    try {
      return document.querySelectorAll(selecteur);
    } on FormatException catch (erreur) {
      throw ErreurSource(
        url.toString(),
        'Réglage « $reglage » : sélecteur CSS « $selecteur » invalide',
        cause: erreur,
      );
    } on UnimplementedError catch (erreur) {
      // `package:html` ne gère pas tous les sélecteurs (pseudo-classes
      // avancées) et lève alors une UnimplementedError.
      throw ErreurSource(
        url.toString(),
        'Réglage « $reglage » : sélecteur CSS « $selecteur » non pris en '
        'charge',
        cause: erreur,
      );
    }
  }

  /// Lève l'erreur dédiée si [html] est une page de défi anti-robot.
  static void _verifierPasDeDefi(String html, Uri url) {
    if (estPageDefiAntiRobot(html)) {
      throw erreurProtectionAntiRobot(url);
    }
  }

  /// Hôte sans `www.` en minuscules.
  static String _hote(Uri uri) {
    final hote = uri.host.toLowerCase();
    return hote.startsWith('www.') ? hote.substring(4) : hote;
  }

  /// `true` si [a] et [b] sont sur le même site (`www.` ignoré).
  static bool _memeSite(Uri a, Uri b) => _hote(a) == _hote(b);

  /// Clé de comparaison d'une adresse : hôte sans `www.`, chemin sans barre
  /// finale, paramètres (« /a/ » et « /a » désignent la même page).
  static String _cleAdresse(Uri uri) {
    var chemin = uri.path;
    while (chemin.endsWith('/')) {
      chemin = chemin.substring(0, chemin.length - 1);
    }
    return '${_hote(uri)}$chemin${uri.hasQuery ? '?${uri.query}' : ''}';
  }

  /// Chemin de [uri] décodé (« %C3%A9pisode » → « épisode ») ; le chemin
  /// brut si le décodage échoue.
  static String _cheminDecode(Uri uri) {
    try {
      return Uri.decodeFull(uri.path);
    } on ArgumentError {
      return uri.path;
    }
  }

  // ---------------------------------------------------------------------
  // Réseau
  // ---------------------------------------------------------------------

  /// Télécharge [uri], ou réutilise la page lue il y a moins de
  /// [dureeCachePageGenerique].
  Future<String> _recupererPage(Uri uri) async {
    final cle = uri.toString();
    final maintenant = _maintenant();
    _pages.removeWhere(
      (_, page) => maintenant.difference(page.date) >= dureeCachePageGenerique,
    );
    final page = _pages[cle];
    if (page != null) {
      return page.html;
    }
    // User-Agent par défaut de ClientHttpPoli (honnête, de l'application) ;
    // une page de défi anti-robot y est déjà reconnue.
    final html = await _client.recupererTexte(uri);
    _pages[cle] = (html: html, date: maintenant);
    return html;
  }

  /// Page qui liste les chapitres de [urlTitre] : la page elle-même, ou,
  /// pour une adresse de chapitre, la première page candidate
  /// ([candidatsPageListe], au plus [nombreMaxCandidatsPageListe]) qui
  /// liste ce chapitre (ou des chapitres de même forme d'adresse).
  Future<({Uri url, String html})> _recupererPageTitre(String urlTitre) async {
    final uri = validerUrl(urlTitre);
    if (!estAdresseChapitre(uri, configuration: configuration)) {
      return (url: uri, html: await _recupererPage(uri));
    }
    final maintenant = _maintenant();
    final connue = _resolutions[uri.toString()];
    if (connue != null &&
        maintenant.difference(connue.date) < dureeCachePageGenerique) {
      return (url: connue.url, html: await _recupererPage(connue.url));
    }

    final htmlChapitre = await _recupererPage(uri);
    final candidats = OutilsWordPress.avecExtrait(
      htmlChapitre,
      () => candidatsPageListe(
        htmlChapitre,
        uri,
        configuration: configuration,
        urlBase: urlBase,
      ),
    );
    final cleChapitre = _cleAdresse(uri);
    final formeChapitre = _formeAdresse(uri);
    final essais = <String>[];
    for (final candidat in candidats.take(nombreMaxCandidatsPageListe)) {
      essais.add(candidat.toString());
      final String html;
      try {
        html = await _recupererPage(candidat);
      } on ErreurSource catch (erreur) {
        // Une protection anti-robot vaut pour tout le site : inutile
        // d'essayer d'autres pages.
        if (erreur.protectionAntiRobot) {
          rethrow;
        }
        continue;
      }
      final liens = _liensChapitres(parse(html), candidat, configuration);
      final listeLeChapitre = liens.any(
        (l) =>
            _cleAdresse(l.adresse) == cleChapitre ||
            (formeChapitre != null &&
                _formeAdresse(l.adresse) == formeChapitre),
      );
      if (listeLeChapitre) {
        _resolutions[uri.toString()] = (url: candidat, date: maintenant);
        return (url: candidat, html: html);
      }
    }
    throw ErreurSource(
      uri.toString(),
      "Cette adresse est celle d'un chapitre, et la page qui liste les "
      "chapitres du titre n'a pas été trouvée"
      '${essais.isEmpty ? '' : ' (pages essayées : ${essais.join(', ')})'} : '
      "collez l'adresse de la page du titre, ou réglez "
      '« selecteurLienListeChapitres »',
    );
  }

  /// Forme de l'adresse d'un chapitre (numéro remplacé par `{n}`), ou
  /// `null` si elle ne contient pas de numéro de chapitre reconnu.
  String? _formeAdresse(Uri adresse) {
    final chemin = _cheminDecode(adresse);
    final motif = configuration.motifNumeroChapitre == null
        ? _motifAdresse
        : RegExp(configuration.motifNumeroChapitre!, caseSensitive: false);
    final m = _dernier(motif.allMatches(chemin));
    if (m == null) {
      return null;
    }
    return '${_hote(adresse)}${chemin.replaceRange(m.start, m.end, '{n}')}';
  }
}
