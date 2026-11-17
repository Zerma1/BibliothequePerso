/// Adaptateur des sites construits avec le thème WordPress
/// **MangaThemesia** (« MangaReader » de Themesia), tâche W2.
///
/// Structure relevée le 2026-11-17 sur le site de démonstration officiel du
/// thème, `https://mangareader.themesia.com`, pages enregistrées dans
/// `test/sources/exemples_html/mangathemesia_*.html` :
/// - fiche d'un titre : `https://<site>/manga/<nom>/` (segment réglable :
///   `comics`, `series`, `komik`…), HTML complet : informations
///   (`.main-info`), genres, résumé et **toute** la liste des chapitres
///   (`#chapterlist`) dans la même page ;
/// - chapitre : `https://<site>/<nom>-chapter-<n>/` ; les adresses des
///   images sont en clair dans l'appel `ts_reader.run({…})` d'un script de
///   la page (objet JSON : `sources[].images`), et en double dans le
///   `<noscript>` de `#readerarea` ;
/// - recherche : `https://<site>/?s=<texte>` (formulaire du thème), page de
///   résultats HTML (`.listupd .bs`).
///
/// Aucune protection n'est contournée (PLAYBOOK.md section 10) : un
/// chapitre marqué protégé par le lecteur (`"protected": true`), ou dont les
/// images ne sont pas en clair (script encodé, chargement par un autre
/// script), lève une [ErreurSource] ; il se lit alors sur le site.
library;

import 'dart:convert';

import 'package:html/dom.dart' show Document, Element;
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
import 'outils_sources.dart';
import 'outils_wordpress.dart';
import 'source_site.dart';

/// Lecture d'un site MangaThemesia : recherche, fiche, chapitres et images.
///
/// Toute [ErreurSource] levée par ses méthodes publiques porte
/// `typeDetecte == TypeSource.mangaThemesia` et, quand une page a été
/// reçue, son début nettoyé (`extraitReponse`) pour le rapport d'erreur.
class SourceMangaThemesia implements SourceSite {
  /// Crée l'adaptateur du site [urlBase] (`https://site.exemple`).
  ///
  /// [languesPreferees] (« fr,en ») ne sert qu'à défaut de langue déclarée
  /// par la page (voir `OutilsWordPress.langueDepuisPage`). [maintenant]
  /// remplace l'horloge dans les tests.
  SourceMangaThemesia(
    this._client, {
    required this.urlBase,
    this.languesPreferees = '',
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? DateTime.now;

  final ClientHttpPoli _client;
  final DateTime Function() _maintenant;

  /// Adresse du site (`Source.urlBase`), base de la recherche.
  final String urlBase;

  /// Langues du client (« fr,en »), repli de la langue des chapitres.
  final String languesPreferees;

  /// Dernière fiche téléchargée (adresse, HTML, date) : la fiche et les
  /// chapitres viennent de la même page.
  ({String url, String html, DateTime date})? _dernierePage;

  /// Appel du lecteur du thème dans un script de la page de chapitre.
  static const String _appelLecteur = 'ts_reader.run(';

  // ---------------------------------------------------------------------
  // Adresses
  // ---------------------------------------------------------------------

  /// Valide l'adresse d'une fiche et la renvoie sans fragment. Lève une
  /// [ErreurSource] sinon.
  static Uri validerUrlTitre(String urlTitre) {
    return OutilsWordPress.validerUrlPage(
      urlTitre,
      TypeSource.mangaThemesia,
      'https://<site>/manga/<nom>/ attendu',
    );
  }

  // ---------------------------------------------------------------------
  // SourceSite
  // ---------------------------------------------------------------------

  /// Recherche [requete] avec le formulaire du thème (`/?s=<texte>`, une
  /// requête). Une requête vide renvoie une liste vide sans requête.
  ///
  /// LIMITE : seule la première page de résultats est lue.
  @override
  Future<List<Titre>> rechercher(String requete) {
    return OutilsWordPress.avecType(TypeSource.mangaThemesia, () async {
      final texte = requete.trim();
      if (texte.isEmpty) {
        return const <Titre>[];
      }
      final uri = Uri.parse(urlBase)
          .resolve('/')
          .replace(queryParameters: <String, String>{'s': texte});
      final html = await _client.recupererTexte(uri);
      return OutilsWordPress.avecExtrait(
        html,
        () => analyserRecherche(html, uri),
      );
    });
  }

  /// Récupère la fiche d'un titre depuis sa page (une requête, ou aucune si
  /// la même page vient d'être lue).
  @override
  Future<FicheTitre> recupererFiche(String urlTitre) {
    return OutilsWordPress.avecType(TypeSource.mangaThemesia, () async {
      final uri = validerUrlTitre(urlTitre);
      final html = await _recupererPage(uri);
      return OutilsWordPress.avecExtrait(html, () => analyserFiche(html, uri));
    });
  }

  /// Récupère tous les chapitres listés dans la fiche (même page que
  /// [recupererFiche]), du plus ancien au plus récent.
  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) {
    return OutilsWordPress.avecType(TypeSource.mangaThemesia, () async {
      final uri = validerUrlTitre(urlTitre);
      final html = await _recupererPage(uri);
      return OutilsWordPress.avecExtrait(
        html,
        () => analyserChapitres(
          html,
          uri,
          languesPreferees: languesPreferees,
          maintenant: _maintenant(),
        ).reversed.toList(),
      );
    });
  }

  /// Récupère les adresses des images du chapitre [urlChapitre].
  ///
  /// Les images sont demandées avec le `Referer` du site
  /// (`ContenuChapitre.urlReferer`), comme le fait le navigateur d'un
  /// lecteur.
  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) {
    return OutilsWordPress.avecType(TypeSource.mangaThemesia, () async {
      final uri = OutilsWordPress.validerUrlPage(
        urlChapitre,
        TypeSource.mangaThemesia,
        'https://<site>/<nom>-chapter-<n>/ attendu',
      );
      final html = await _client.recupererTexte(uri);
      return OutilsWordPress.avecExtrait(
        html,
        () => analyserContenu(html, uri),
      );
    });
  }

  // ---------------------------------------------------------------------
  // Analyse du HTML (sans réseau, publique pour les tests)
  // ---------------------------------------------------------------------

  /// Résultats de la page de recherche [html] (adresse [uriRecherche]).
  ///
  /// Lève une [ErreurSource] si la page n'a pas de bloc de résultats
  /// (`.listupd`) ; une recherche sans résultat (« Not Found ») donne une
  /// liste vide.
  static List<Titre> analyserRecherche(String html, Uri uriRecherche) {
    final document = parse(html);
    final liste = document.querySelector('.listupd');
    if (liste == null) {
      throw ErreurSource(
        uriRecherche.toString(),
        "La page reçue n'est pas une page de recherche MangaThemesia "
        '(pas de .listupd : structure inattendue ou page anti-robot)',
      );
    }
    final titres = <Titre>[];
    final urlsVues = <String>{};
    // Un résultat = `.bs` ; son lien unique `.bsx > a` porte le nom dans
    // `title`, répété dans `.tt`.
    for (final bloc in liste.querySelectorAll('.bs')) {
      final lien =
          bloc.querySelector('.bsx a[href]') ?? bloc.querySelector('a[href]');
      final href = lien?.attributes['href']?.trim() ?? '';
      if (lien == null || href.isEmpty) {
        continue;
      }
      final Uri adresse;
      try {
        adresse = validerUrlTitre(uriRecherche.resolve(href).toString());
      } on ErreurSource {
        continue;
      }
      var nom = OutilsWordPress.nettoyer(bloc.querySelector('.tt')?.text ?? '');
      if (nom.isEmpty) {
        nom = OutilsWordPress.nettoyer(lien.attributes['title'] ?? '');
      }
      if (nom.isEmpty || !urlsVues.add(adresse.toString())) {
        continue;
      }
      // Vignette : `img.ts-post-image` ; l'image visible est une image
      // d'attente `data:` avec l'adresse dans `data-src`, et une copie avec
      // `src` est dans <noscript>. `adresseImage` lit les deux formes.
      String? couverture;
      for (final image in bloc.querySelectorAll('img')) {
        couverture = OutilsWordPress.adresseImage(image, uriRecherche);
        if (couverture != null) {
          break;
        }
      }
      // Le type est la classe du span `.type` (« type Manga »).
      final type = bloc.querySelector('.type')?.className;
      titres.add(
        Titre(
          urlTitre: adresse.toString(),
          nom: nom,
          typeTitre: OutilsWordPress.typeDepuisTexte(type),
          urlCouverture: couverture,
        ),
      );
    }
    return titres;
  }

  /// Construit la fiche à partir du [html] de la page [urlTitre].
  ///
  /// Lève une [ErreurSource] si la page n'est pas une fiche MangaThemesia
  /// ou si le nom manque.
  static FicheTitre analyserFiche(String html, Uri urlTitre) {
    final document = parse(html);
    _verifierFiche(document, urlTitre);

    // Nom : `h1.entry-title` (itemprop="name") ; repli : og:title puis la
    // balise <title> (« Nom – Site »).
    var nom = OutilsWordPress.nettoyer(
      document.querySelector('h1.entry-title')?.text ?? '',
    );
    if (nom.isEmpty) {
      nom =
          OutilsWordPress.meta(document, 'meta[property="og:title"]') ??
          OutilsWordPress.nomDepuisTitrePage(document);
    }
    if (nom.isEmpty) {
      throw ErreurSource(
        urlTitre.toString(),
        'Fiche MangaThemesia sans nom de titre (structure inattendue)',
      );
    }

    // Titres alternatifs : `span.alternative` sous le h1 (noms séparés par
    // des virgules) ; variante des gabarits plus anciens : ligne
    // « Alternative » de `.wd-full` (`<b>` libellé + `<span>` valeur) ou
    // `.seriestualt`.
    final alternatifs = <TitreAlternatif>[];
    final texteAlternatifs =
        document.querySelector('.alternative, .seriestualt')?.text ??
        _valeurInfo(
          document,
          RegExp(r'^(alternative|alternatif|other)', caseSensitive: false),
        ) ??
        '';
    for (final alt in OutilsWordPress.separerNoms(texteAlternatifs)) {
      if (alt != nom && !alternatifs.any((a) => a.nom == alt)) {
        alternatifs.add(TitreAlternatif(nom: alt));
      }
    }

    // Couverture : l'image de `.thumb` (`itemprop="image"`) ; repli :
    // og:image.
    String? urlCouverture;
    final image = document.querySelector('.thumb img, .thumbook img');
    if (image != null) {
      urlCouverture = OutilsWordPress.adresseImage(image, urlTitre);
    }
    final ogImage = OutilsWordPress.meta(document, 'meta[property="og:image"]');
    if (urlCouverture == null && ogImage != null) {
      urlCouverture = urlTitre.resolve(ogImage).toString();
    }

    // Résumé : `[itemprop="description"]` (`.entry-content-single`),
    // paragraphes séparés par des sauts de ligne.
    final blocResume = document.querySelector(
      '.entry-content[itemprop="description"], [itemprop="description"], '
      '.entry-content-single',
    );
    final resume = blocResume == null
        ? ''
        : OutilsWordPress.texteParagraphes(blocResume);

    // Auteurs : lignes « Author » puis « Artist » du bloc d'informations.
    final auteurs = <String>[];
    for (final libelle in <RegExp>[
      RegExp(r'^(author|auteur|autor|penulis)', caseSensitive: false),
      RegExp(r'^(artist|artiste|ilustrador)', caseSensitive: false),
    ]) {
      for (final auteur in OutilsWordPress.separerNoms(
        _valeurInfo(document, libelle) ?? '',
      )) {
        if (!auteurs.contains(auteur)) {
          auteurs.add(auteur);
        }
      }
    }

    // Genres : liens de `.mgen` (variante : `.seriestugenre`).
    final categories = <String>[];
    for (final lien in document.querySelectorAll('.mgen a, .seriestugenre a')) {
      final genre = OutilsWordPress.nettoyer(lien.text);
      if (genre.isNotEmpty &&
          !categories.any((c) => c.toLowerCase() == genre.toLowerCase())) {
        categories.add(genre);
      }
    }

    final statut = _valeurInfo(
      document,
      RegExp(r'^(status|statut|estado)', caseSensitive: false),
    );
    // Type : ligne « Type » (Manga, Manhwa, Manhua, Novel, Comic).
    final type = OutilsWordPress.typeDepuisTexte(
      _valeurInfo(document, RegExp(r'^(type|tipe|tipo)', caseSensitive: false)),
    );

    return FicheTitre(
      titre: Titre(
        urlTitre: urlTitre.toString(),
        nom: nom,
        typeTitre: type,
        urlCouverture: urlCouverture,
        resume: resume.isEmpty ? null : resume,
        auteur: auteurs.isEmpty ? null : auteurs.join(', '),
        statut: statut,
        titresAlternatifs: alternatifs,
      ),
      categories: categories,
    );
  }

  /// Chapitres listés dans la fiche [html], dans l'ordre du site (du plus
  /// récent au plus ancien).
  ///
  /// Langue : `lang` de la page, à défaut la première de [languesPreferees].
  ///
  /// Lève une [ErreurSource] si la page n'est pas une fiche MangaThemesia ;
  /// une fiche sans chapitre donne une liste vide.
  static List<Chapitre> analyserChapitres(
    String html,
    Uri urlTitre, {
    String languesPreferees = '',
    DateTime? maintenant,
  }) {
    final document = parse(html);
    _verifierFiche(document, urlTitre);
    final langue = OutilsWordPress.langueDepuisPage(document, languesPreferees);
    final heure = maintenant ?? DateTime.now();
    final chapitres = <Chapitre>[];
    final urlsVues = <String>{};
    // `#chapterlist li` : un li par chapitre (`data-num` = numéro). Le
    // lien de lecture est celui de `.eph-num` ; le lien `.dload` d'un même
    // li mène à un téléchargement externe et n'est pas lu.
    for (final ligne in document.querySelectorAll('#chapterlist li')) {
      final lien =
          ligne.querySelector('.eph-num a[href]') ??
          ligne.querySelector('a[href]');
      final href = lien?.attributes['href']?.trim() ?? '';
      if (lien == null || href.isEmpty || href.startsWith('#')) {
        continue;
      }
      final Uri adresse;
      try {
        adresse = urlTitre.resolve(href).removeFragment();
      } on FormatException {
        continue;
      }
      final url = adresse.toString();
      if (!urlsVues.add(url)) {
        continue;
      }
      // Nom : `.chapternum` (« Chapter 4.5 ») ; repli : texte du lien.
      var nom = OutilsWordPress.nettoyer(
        lien.querySelector('.chapternum')?.text ?? '',
      );
      if (nom.isEmpty) {
        nom = OutilsWordPress.nettoyer(lien.text);
      }
      // Numéro : `data-num` du li (« 4.5 ») ; repli : nom puis adresse.
      final dataNum = ligne.attributes['data-num']?.trim() ?? '';
      final numero = RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(dataNum)
          ? OutilsSources.convertirNumero(dataNum)
          : OutilsWordPress.numeroChapitre(nom, adresse);
      final texteDate = lien.querySelector('.chapterdate')?.text ?? '';
      chapitres.add(
        Chapitre(
          urlChapitre: url,
          nom: nom.isEmpty ? url : nom,
          numero: numero,
          langue: langue,
          datePublication: OutilsWordPress.convertirDate(texteDate, heure),
        ),
      );
    }
    return chapitres;
  }

  /// Contenu de la page de chapitre [html] (adresse [urlChapitre]).
  ///
  /// Source principale : l'objet JSON passé à `ts_reader.run(…)` dans un
  /// script **en clair** de la page — images du serveur `defaultSource`, ou
  /// du premier serveur. Repli : les `img` de `#readerarea` (copie
  /// `<noscript>` du thème, ou images directement dans la page).
  ///
  /// Lève une [ErreurSource] si le lecteur marque le chapitre protégé
  /// (`protected` à `true`, `1`, `"1"` ou `!0`, cherché dans le texte brut
  /// du script avant tout décodage ou repli) ou si aucune image n'est en
  /// clair.
  ///
  /// LIMITE : des sites minifient leurs scripts dans un attribut
  /// `src="data:text/javascript;base64,…"` ; ce script n'est pas décodé :
  /// seul le repli `#readerarea img` est alors lu.
  static ContenuChapitre analyserContenu(String html, Uri urlChapitre) {
    final document = parse(html);
    final referer = OutilsWordPress.racineSite(urlChapitre);
    // PLAYBOOK §10 : la marque de protection est cherchée dans le texte brut
    // du script AVANT tout décodage JSON et tout repli `#readerarea img` /
    // `<noscript>` : un objet écrit en JavaScript non strict (clés sans
    // guillemets, `!0`) échoue au décodage, et le repli lirait alors les
    // images d'un chapitre protégé.
    if (_lecteurMarqueProtege(document)) {
      throw _erreurProtege(urlChapitre);
    }
    final lecteur = _objetLecteur(document, urlChapitre);
    if (lecteur != null) {
      if (_valeurProtegee(lecteur['protected'])) {
        throw _erreurProtege(urlChapitre);
      }
      final images = _imagesLecteur(lecteur, urlChapitre);
      if (images.isNotEmpty) {
        return ContenuChapitre.images(images, urlReferer: referer);
      }
    }

    final zone = document.querySelector('#readerarea');
    if (zone == null && lecteur == null) {
      throw ErreurSource(
        urlChapitre.toString(),
        "La page reçue n'est pas un chapitre MangaThemesia (ni "
        '#readerarea ni ts_reader : structure inattendue ou page '
        'anti-robot)',
      );
    }
    final urls = <String>[];
    for (final image in zone?.querySelectorAll('img') ?? const <Element>[]) {
      final adresse = OutilsWordPress.adresseImage(image, urlChapitre);
      if (adresse != null) {
        urls.add(adresse);
      }
    }
    if (urls.isEmpty) {
      // <noscript> peut être lu comme du texte brut selon l'analyseur : on
      // relit alors son contenu comme un fragment HTML.
      for (final bloc
          in zone?.querySelectorAll('noscript') ?? const <Element>[]) {
        for (final image in parse(bloc.text).querySelectorAll('img')) {
          final adresse = OutilsWordPress.adresseImage(image, urlChapitre);
          if (adresse != null) {
            urls.add(adresse);
          }
        }
      }
    }
    if (urls.isEmpty) {
      throw ErreurSource(
        urlChapitre.toString(),
        'Aucune image en clair dans ce chapitre MangaThemesia (images '
        'chargées par un script ou chapitre réservé) : à lire sur le site',
      );
    }
    return ContenuChapitre.images(urls, urlReferer: referer);
  }

  // ---------------------------------------------------------------------
  // Outils privés
  // ---------------------------------------------------------------------

  /// Lève une [ErreurSource] si [document] n'est pas une fiche
  /// MangaThemesia : le bloc d'informations (`.main-info`, ou `.bigcontent`
  /// / `.infox` des gabarits plus anciens) ou la liste `#chapterlist` sont
  /// présents sur toutes les fiches.
  static void _verifierFiche(Document document, Uri urlTitre) {
    if (document.querySelector(
          '.main-info, .bigcontent, .infox, #chapterlist',
        ) ==
        null) {
      throw ErreurSource(
        urlTitre.toString(),
        "La page reçue n'est pas une fiche de titre MangaThemesia "
        '(structure inattendue, page anti-robot ou titre retiré)',
      );
    }
  }

  /// Valeur de la ligne d'informations [libelle], ou `null`.
  ///
  /// Trois gabarits connus : `.tsinfo .imptdt` (« Status <i>Ongoing</i> » :
  /// libellé en texte propre, valeur dans `i` ou `a`, gabarit du site de
  /// démonstration) ; `.infotable tr` (deux cellules) ; `.fmed` (`<b>`
  /// libellé, `<span>` valeur).
  static String? _valeurInfo(Document document, RegExp libelle) {
    String? propre(String? texte) {
      final t = OutilsWordPress.nettoyer(texte ?? '');
      return t.isEmpty || t == '-' ? null : t;
    }

    for (final ligne in document.querySelectorAll('.tsinfo .imptdt')) {
      final titre = OutilsWordPress.nettoyer(
        OutilsWordPress.texteDirect(ligne),
      );
      if (libelle.hasMatch(titre)) {
        final valeur = ligne.querySelector('i, a');
        return propre(valeur?.text);
      }
    }
    for (final ligne in document.querySelectorAll('.infotable tr')) {
      final cellules = ligne.querySelectorAll('td');
      if (cellules.length >= 2 &&
          libelle.hasMatch(OutilsWordPress.nettoyer(cellules[0].text))) {
        return propre(cellules[1].text);
      }
    }
    for (final ligne in document.querySelectorAll('.fmed, .wd-full')) {
      final titre = ligne.querySelector('b');
      if (titre != null &&
          libelle.hasMatch(OutilsWordPress.nettoyer(titre.text))) {
        return propre(ligne.querySelector('span')?.text);
      }
    }
    return null;
  }

  /// Marque de protection dans le texte d'un script : clé `protected` (avec
  /// ou sans guillemets) valant `true`, `1`, `"1"`, `'1'` ou `!0` (forme
  /// minifiée de `true`). Le regard arrière écarte `unprotected` ou
  /// `is_protected` ; le regard avant écarte `10` ou `true_value`.
  static final RegExp _motifProtege = RegExp(
    r'''(?<![\w$])["']?protected["']?\s*:\s*(?:true|1|"1"|'1'|!0)(?![\w$])''',
  );

  /// Indique si un script en clair qui appelle `ts_reader.run(` porte la
  /// marque de protection ([_motifProtege]), sans décoder son objet.
  static bool _lecteurMarqueProtege(Document document) {
    for (final script in document.querySelectorAll('script')) {
      final texte = script.text;
      if (texte.contains(_appelLecteur) && _motifProtege.hasMatch(texte)) {
        return true;
      }
    }
    return false;
  }

  /// Indique si la valeur JSON de `protected` marque un chapitre protégé :
  /// `true`, `1` ou `"1"`.
  static bool _valeurProtegee(Object? valeur) =>
      valeur == true || valeur == 1 || valeur == '1';

  /// Erreur d'un chapitre protégé par le lecteur du site.
  static ErreurSource _erreurProtege(Uri urlChapitre) => ErreurSource(
    urlChapitre.toString(),
    'Chapitre protégé par le site (lecteur MangaThemesia) : à lire sur '
    'le site',
  );

  /// Objet JSON passé à `ts_reader.run(…)` dans un script en clair de la
  /// page, ou `null` s'il n'y en a pas ou s'il est illisible.
  static Map<String, Object?>? _objetLecteur(Document document, Uri url) {
    for (final script in document.querySelectorAll('script')) {
      final texte = script.text;
      final debutAppel = texte.indexOf(_appelLecteur);
      if (debutAppel < 0) {
        continue;
      }
      final debut = texte.indexOf('{', debutAppel);
      final fin = debut < 0 ? -1 : _finObjetJson(texte, debut);
      if (fin < 0) {
        continue;
      }
      try {
        final valeur = jsonDecode(texte.substring(debut, fin + 1));
        if (valeur is Map<String, Object?>) {
          return valeur;
        }
      } on FormatException {
        // Objet écrit en JavaScript et non en JSON strict : on passe au
        // repli `#readerarea img`. La marque de protection a déjà été
        // cherchée dans le texte brut (`_lecteurMarqueProtege`).
        continue;
      }
    }
    return null;
  }

  /// Index de l'accolade qui ferme l'objet JSON ouvert à [debut], en sautant
  /// les chaînes (qui peuvent contenir des accolades) ; -1 si introuvable.
  static int _finObjetJson(String texte, int debut) {
    var profondeur = 0;
    var dansChaine = false;
    for (var i = debut; i < texte.length; i++) {
      final c = texte[i];
      if (dansChaine) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          dansChaine = false;
        }
        continue;
      }
      if (c == '"') {
        dansChaine = true;
      } else if (c == '{') {
        profondeur++;
      } else if (c == '}') {
        profondeur--;
        if (profondeur == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  /// Images du serveur `defaultSource` de l'objet du lecteur (ou du premier
  /// serveur qui en a), adresses absolues.
  static List<String> _imagesLecteur(
    Map<String, Object?> lecteur,
    Uri urlChapitre,
  ) {
    final serveurs = lecteur['sources'];
    if (serveurs is! List<Object?>) {
      return const <String>[];
    }
    final parDefaut = lecteur['defaultSource'];
    List<String>? premieres;
    for (final serveur in serveurs) {
      if (serveur is! Map<String, Object?>) {
        continue;
      }
      final images = serveur['images'];
      if (images is! List<Object?>) {
        continue;
      }
      final urls = <String>[];
      for (final image in images) {
        final lien = image is String ? image.trim() : '';
        if (lien.isEmpty || lien.startsWith('data:')) {
          continue;
        }
        try {
          urls.add(urlChapitre.resolve(lien).toString());
        } on FormatException {
          continue;
        }
      }
      if (urls.isEmpty) {
        continue;
      }
      if (serveur['source'] == parDefaut) {
        return urls;
      }
      premieres ??= urls;
    }
    return premieres ?? const <String>[];
  }

  /// Télécharge la fiche [uri], ou réutilise celle lue il y a moins de
  /// [dureeCachePageWordPress].
  Future<String> _recupererPage(Uri uri) async {
    final url = uri.toString();
    final page = _dernierePage;
    final maintenant = _maintenant();
    if (page != null &&
        page.url == url &&
        maintenant.difference(page.date) < dureeCachePageWordPress) {
      return page.html;
    }
    // User-Agent par défaut de ClientHttpPoli (navigateur courant).
    final html = await _client.recupererTexte(uri);
    _dernierePage = (url: url, html: html, date: maintenant);
    return html;
  }
}
