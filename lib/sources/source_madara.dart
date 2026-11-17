/// Adaptateur des sites construits avec le thème WordPress **Madara**
/// (extension « WP Manga » de MangaBooth), tâche W2.
///
/// Structure relevée le 2026-11-17 sur le site de démonstration officiel du
/// thème, `https://live.mangabooth.com` (Madara 2.x, WP Manga 2.4), pages
/// enregistrées dans `test/sources/exemples_html/madara_*.html` :
/// - fiche d'un titre : `https://<site>/manga/<nom>/` (le segment `manga`
///   est réglable : `series`, `webtoon`, `comic`… selon les sites) ;
/// - liste des chapitres : absente de la fiche (`#manga-chapters-holder`
///   vide), chargée par le script du thème `wp-manga/assets/js/script.js` :
///   `POST <fiche>ajax/chapters/?t=<page>` sans corps, réponse HTML ;
///   variante des versions plus anciennes : `POST /wp-admin/admin-ajax.php`
///   avec `action=manga_get_chapters&manga=<data-id>` ; certains sites
///   affichent encore la liste directement dans la fiche ;
/// - chapitre : `https://<site>/manga/<nom>/<volume>/<chapitre>/`, images en
///   clair dans `.reading-content img` (adresse dans `data-src`) ; le
///   paramètre `style=list` (sélecteur « List style » du lecteur) demande
///   toutes les images sur une seule page ;
/// - recherche : `https://<site>/?s=<texte>&post_type=wp-manga` (formulaire
///   de recherche du thème), page de résultats HTML.
///
/// Aucune protection n'est contournée (PLAYBOOK.md section 10) : un
/// chapitre réservé (premium, connexion) est listé avec `urlExterne`, et une
/// page sans image en clair lève une [ErreurSource].
library;

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
import 'outils_wordpress.dart';
import 'source_site.dart';

/// Lecture d'un site Madara : recherche, fiche, chapitres et images.
///
/// Toute [ErreurSource] levée par ses méthodes publiques porte
/// `typeDetecte == TypeSource.madara` et, quand une page a été reçue, son
/// début nettoyé (`extraitReponse`) pour le rapport d'erreur.
class SourceMadara implements SourceSite {
  /// Crée l'adaptateur du site [urlBase] (`https://site.exemple`).
  ///
  /// [languesPreferees] (« fr,en ») ne sert qu'à défaut de langue déclarée
  /// par la page (voir `OutilsWordPress.langueDepuisPage`). [maintenant]
  /// remplace l'horloge dans les tests (dates relatives, page gardée en
  /// mémoire) ; [nombreMaxPages] borne les pages de la liste des chapitres.
  SourceMadara(
    this._client, {
    required this.urlBase,
    this.languesPreferees = '',
    DateTime Function()? maintenant,
    this.nombreMaxPages = nombreMaxPagesChapitresMadara,
  }) : _maintenant = maintenant ?? DateTime.now;

  final ClientHttpPoli _client;
  final DateTime Function() _maintenant;

  /// Adresse du site (`Source.urlBase`), base de la recherche.
  final String urlBase;

  /// Langues du client (« fr,en »), repli de la langue des chapitres.
  final String languesPreferees;

  /// Nombre maximal de pages de la liste des chapitres lues pour un titre.
  final int nombreMaxPages;

  /// Dernière fiche téléchargée (adresse, HTML, date) : la fiche et les
  /// chapitres viennent de la même page.
  ({String url, String html, DateTime date})? _dernierePage;

  // ---------------------------------------------------------------------
  // Adresses
  // ---------------------------------------------------------------------

  /// Valide l'adresse d'une fiche et renvoie sa forme canonique : sans
  /// paramètres ni fragment, terminée par « / » (le script du thème construit
  /// `<fiche>ajax/chapters/` à partir de cette forme). Lève une
  /// [ErreurSource] sinon.
  static Uri validerUrlTitre(String urlTitre) {
    final uri = OutilsWordPress.validerUrlPage(
      urlTitre,
      TypeSource.madara,
      'https://<site>/manga/<nom>/ attendu',
    );
    final chemin = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: chemin,
    );
  }

  /// Adresse de la page [urlChapitre] en mode « liste » (`style=list`) : le
  /// lecteur du thème y affiche toutes les images du chapitre, au lieu d'une
  /// image par page en mode « paged ». Les autres paramètres sont gardés.
  static Uri adresseLectureEnListe(Uri urlChapitre) {
    return urlChapitre.replace(
      queryParameters: <String, String>{
        ...urlChapitre.queryParameters,
        'style': 'list',
      },
    );
  }

  // ---------------------------------------------------------------------
  // SourceSite
  // ---------------------------------------------------------------------

  /// Recherche [requete] avec le formulaire du thème
  /// (`/?s=<texte>&post_type=wp-manga`, une requête). Une requête vide
  /// renvoie une liste vide sans requête.
  ///
  /// LIMITE : seule la première page de résultats est lue.
  @override
  Future<List<Titre>> rechercher(String requete) {
    return OutilsWordPress.avecType(TypeSource.madara, () async {
      final texte = requete.trim();
      if (texte.isEmpty) {
        return const <Titre>[];
      }
      final base = Uri.parse(urlBase);
      final uri = base
          .resolve('/')
          .replace(
            queryParameters: <String, String>{
              's': texte,
              'post_type': 'wp-manga',
            },
          );
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
    return OutilsWordPress.avecType(TypeSource.madara, () async {
      final uri = validerUrlTitre(urlTitre);
      final html = await _recupererPage(uri);
      return OutilsWordPress.avecExtrait(html, () => analyserFiche(html, uri));
    });
  }

  /// Récupère tous les chapitres du titre, du plus ancien au plus récent.
  ///
  /// La liste est lue dans la fiche si elle y figure ; sinon elle est
  /// demandée comme le fait le script du thème :
  /// `POST <fiche>ajax/chapters/?t=<page>` (pages suivantes tant que la
  /// pagination en propose), puis, si
  /// ce point d'accès n'existe pas (404, 400, 405), l'ancien appel
  /// `admin-ajax.php` (`action=manga_get_chapters`).
  ///
  /// LIMITE : au-delà de [nombreMaxPages] pages, les chapitres suivants ne
  /// sont pas listés.
  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) {
    return OutilsWordPress.avecType(TypeSource.madara, () async {
      final uri = validerUrlTitre(urlTitre);
      final html = await _recupererPage(uri);
      final document = OutilsWordPress.avecExtrait(html, () {
        final document = parse(html);
        _verifierFiche(document, uri);
        return document;
      });
      final langue = OutilsWordPress.langueDepuisPage(
        document,
        languesPreferees,
      );
      final maintenant = _maintenant();

      // Liste présente dans la fiche (anciennes versions, ou réglage « pas de
      // chargement AJAX » du thème).
      if (document.querySelector('li.wp-manga-chapter') != null) {
        return analyserChapitres(
          html,
          uri,
          langue: langue,
          maintenant: maintenant,
        ).reversed.toList();
      }
      final conteneur = document.querySelector('#manga-chapters-holder');
      if (conteneur == null) {
        throw ErreurSource(
          uri.toString(),
          'Fiche Madara sans liste de chapitres (ni dans la page, ni '
          '#manga-chapters-holder)',
        );
      }

      final chapitres = <Chapitre>[];
      final urlsVues = <String>{};
      try {
        for (var page = 1; page <= nombreMaxPages; page++) {
          final adresse = uri
              .resolve('ajax/chapters/')
              .replace(queryParameters: <String, String>{'t': '$page'});
          final reponse = await _client.envoyerFormulaire(
            adresse,
            referer: uri.toString(),
            // Requête de lecture : la renvoyer après une coupure est sans
            // risque.
            nouvellesTentatives: nombreMaxNouvellesTentatives,
          );
          final dePage = OutilsWordPress.avecExtrait(reponse, () {
            // Les pages suivantes ne sont demandées que si la page 1 en
            // annonçait : seule la page 1 peut être une réponse étrangère.
            if (page == 1) {
              verifierReponseChapitres(reponse, adresse);
            }
            return analyserChapitres(
              reponse,
              uri,
              langue: langue,
              maintenant: maintenant,
            );
          });
          final avant = chapitres.length;
          chapitres.addAll(dePage.where((c) => urlsVues.add(c.urlChapitre)));
          // Garde-fou : une page sans chapitre nouveau arrête la lecture.
          if (chapitres.length == avant || !aPageSuivante(reponse, page)) {
            break;
          }
        }
      } on ErreurSource catch (erreur) {
        final code = erreur.codeStatut;
        // Seul un échec dès la première page signale un site sans ce point
        // d'accès ; un échec plus loin est une vraie erreur.
        if (chapitres.isNotEmpty ||
            !codesHttpSansAjaxChapitresMadara.contains(code)) {
          rethrow;
        }
        // Ancien point d'accès du thème (Madara 1.x) : identifiant du titre
        // dans `data-id` du conteneur.
        final idTitre = conteneur.attributes['data-id']?.trim() ?? '';
        if (idTitre.isEmpty) {
          rethrow;
        }
        final adresseAncienne = uri.resolve('/wp-admin/admin-ajax.php');
        final reponse = await _client.envoyerFormulaire(
          adresseAncienne,
          champs: <String, String>{
            'action': 'manga_get_chapters',
            'manga': idTitre,
          },
          referer: uri.toString(),
          nouvellesTentatives: nombreMaxNouvellesTentatives,
        );
        chapitres
          ..clear()
          ..addAll(
            OutilsWordPress.avecExtrait(reponse, () {
              // Une réponse en 200 qui n'est pas une liste du thème (page
              // de cache, anti-robot) donnerait sinon une liste vide
              // silencieuse.
              verifierReponseChapitres(reponse, adresseAncienne);
              return analyserChapitres(
                reponse,
                uri,
                langue: langue,
                maintenant: maintenant,
              );
            }),
          );
      }
      return chapitres.reversed.toList();
    });
  }

  /// Récupère les adresses des images du chapitre [urlChapitre] (page lue en
  /// mode liste, voir [adresseLectureEnListe]), ou son texte pour un roman.
  ///
  /// Les images sont demandées avec le `Referer` du site
  /// (`ContenuChapitre.urlReferer`), comme le fait le navigateur d'un
  /// lecteur : beaucoup de sites Madara refusent les images sans lui.
  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) {
    return OutilsWordPress.avecType(TypeSource.madara, () async {
      final uri = OutilsWordPress.validerUrlPage(
        urlChapitre,
        TypeSource.madara,
        'https://<site>/manga/<nom>/<chapitre>/ attendu',
      );
      final html = await _client.recupererTexte(adresseLectureEnListe(uri));
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
  /// Lève une [ErreurSource] si la page n'est pas une page de résultats du
  /// thème ; une recherche sans résultat donne une liste vide.
  static List<Titre> analyserRecherche(String html, Uri uriRecherche) {
    final document = parse(html);
    // `.c-tabs-item__content` : un bloc par résultat (gabarit
    // `search.php` du thème). Variante des pages d'archive :
    // `.page-item-detail`.
    final blocs = document.querySelectorAll(
      '.c-tabs-item__content, .page-item-detail',
    );
    // Une page sans résultat garde la classe `search` sur <body> et le
    // conteneur `.search-wrap` ; leur absence signale une autre page
    // (anti-robot, erreur, site qui n'est pas un Madara).
    final estPageRecherche =
        (document.body?.className.contains('search') ?? false) ||
        document.querySelector('.search-wrap, .c-tabs-item') != null;
    if (blocs.isEmpty && !estPageRecherche) {
      throw ErreurSource(
        uriRecherche.toString(),
        "La page reçue n'est pas une page de recherche Madara (structure "
        'inattendue ou page anti-robot)',
      );
    }
    final titres = <Titre>[];
    final urlsVues = <String>{};
    for (final bloc in blocs) {
      // Le lien du nom est dans `.post-title` (h3/h4) ; repli : lien de la
      // vignette, qui porte le nom dans `title`.
      final lien =
          bloc.querySelector('.post-title a[href]') ??
          bloc.querySelector('a[href][title]');
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
      final nom = OutilsWordPress.nettoyer(
        lien.text.trim().isEmpty ? (lien.attributes['title'] ?? '') : lien.text,
      );
      if (nom.isEmpty || !urlsVues.add(adresse.toString())) {
        continue;
      }
      final image = bloc.querySelector('.tab-thumb img, .item-thumb img, img');
      titres.add(
        Titre(
          urlTitre: adresse.toString(),
          nom: nom,
          urlCouverture: image == null
              ? null
              : OutilsWordPress.adresseImage(image, uriRecherche),
          auteur: _auteursRecherche(bloc),
          statut: _texteValeur(
            bloc,
            RegExp(r'^(status|statut)', caseSensitive: false),
          ),
        ),
      );
    }
    return titres;
  }

  /// Construit la fiche à partir du [html] de la page [urlTitre].
  ///
  /// Lève une [ErreurSource] si la page n'est pas une fiche Madara ou si le
  /// nom manque.
  static FicheTitre analyserFiche(String html, Uri urlTitre) {
    final document = parse(html);
    _verifierFiche(document, urlTitre);
    // Les lignes « libellé / valeur » sont cherchées dans le bandeau de la
    // fiche (`.profile-manga`, ou `.tab-summary` selon les gabarits) : les
    // widgets latéraux réutilisent `.post-content_item` pour d'autres titres.
    final racine =
        document.querySelector('.profile-manga') ??
        document.querySelector('.tab-summary') ??
        document.documentElement!;

    // Nom : le h1 de `.post-title` (variante récente : `#manga-title h1`).
    // Le thème y ajoute des badges (`<span class="manga-title-badges">HOT`)
    // : seul le texte propre du h1 est gardé.
    final enTete = document.querySelector(
      '.post-title h1, #manga-title h1, .post-title h3',
    );
    var nom = enTete == null
        ? ''
        : OutilsWordPress.nettoyer(OutilsWordPress.texteDirect(enTete));
    if (nom.isEmpty && enTete != null) {
      nom = OutilsWordPress.nettoyer(enTete.text);
    }
    if (nom.isEmpty) {
      nom =
          OutilsWordPress.meta(document, 'meta[property="og:title"]') ??
          OutilsWordPress.nomDepuisTitrePage(document);
    }
    if (nom.isEmpty) {
      throw ErreurSource(
        urlTitre.toString(),
        'Fiche Madara sans nom de titre (structure inattendue)',
      );
    }

    // Titres alternatifs : ligne « Alternative » de la fiche (libellé
    // traduit selon les sites : « Alternatif », « Autre(s) nom(s) »…),
    // noms séparés par des virgules ou des points-virgules.
    final alternatifs = <TitreAlternatif>[];
    final ligneAlternatifs = _texteValeur(
      racine,
      RegExp(
        r'^(alternative|alternatif|autres? noms?|other names?)',
        caseSensitive: false,
      ),
    );
    for (final alt in OutilsWordPress.separerNoms(ligneAlternatifs ?? '')) {
      if (alt != nom && !alternatifs.any((a) => a.nom == alt)) {
        alternatifs.add(TitreAlternatif(nom: alt));
      }
    }

    // Couverture : l'image de `.summary_image` (chargée en différé :
    // `data-src`, l'attribut `src` n'est qu'une image d'attente « dflazy »).
    // Repli : og:image (même image, en plus grand).
    String? urlCouverture;
    final image = document.querySelector('.summary_image img');
    if (image != null) {
      urlCouverture = OutilsWordPress.adresseImage(image, urlTitre);
    }
    final ogImage = OutilsWordPress.meta(document, 'meta[property="og:image"]');
    if (urlCouverture == null && ogImage != null) {
      urlCouverture = urlTitre.resolve(ogImage).toString();
    }

    // Résumé : `.summary__content` (bloc « Summary » sous la fiche) ;
    // variantes : `.description-summary` sans ce sous-bloc, ou
    // `.manga-excerpt` des gabarits plus anciens.
    final blocResume = document.querySelector(
      '.description-summary .summary__content, .summary__content, '
      '.description-summary, .manga-excerpt',
    );
    final resume = blocResume == null
        ? ''
        : OutilsWordPress.texteParagraphes(blocResume);

    // Auteurs : liens des lignes « Author(s) » puis « Artist(s) ». On passe
    // par le libellé de la ligne et non par `.author-content` seul : le
    // thème réutilise cette classe pour « Translator Team » (équipe de
    // traduction, pas un auteur).
    final auteurs = <String>[];
    for (final libelle in <RegExp>[
      RegExp(r'^(author|auteur|autor)', caseSensitive: false),
      RegExp(r'^(artist|artiste)', caseSensitive: false),
    ]) {
      final valeur = _valeur(racine, libelle);
      if (valeur == null) {
        continue;
      }
      final liens = valeur.querySelectorAll('a');
      final noms = liens.isEmpty
          ? OutilsWordPress.separerNoms(valeur.text)
          : liens.map((a) => OutilsWordPress.nettoyer(a.text));
      for (final auteur in noms) {
        if (auteur.isNotEmpty && !auteurs.contains(auteur)) {
          auteurs.add(auteur);
        }
      }
    }
    if (auteurs.isEmpty) {
      // Gabarit sans libellé reconnu : `.author-content` de la fiche.
      for (final lien in document.querySelectorAll('.author-content a')) {
        final auteur = OutilsWordPress.nettoyer(lien.text);
        if (auteur.isNotEmpty && !auteurs.contains(auteur)) {
          auteurs.add(auteur);
        }
      }
    }

    // Genres : liens de `.genres-content` (taxonomie `manga-genre`).
    final categories = <String>[];
    for (final lien in document.querySelectorAll('.genres-content a')) {
      final genre = OutilsWordPress.nettoyer(lien.text);
      if (genre.isNotEmpty &&
          !categories.any((c) => c.toLowerCase() == genre.toLowerCase())) {
        categories.add(genre);
      }
    }

    // Statut : ligne « Status » (dans `.post-status`), texte du site.
    final statut = _texteValeur(
      racine,
      RegExp(r'^(status|statut|état|estado)', caseSensitive: false),
    );

    // Type : ligne « Type » (Manga, Manhwa, Manhua… ; le site de
    // démonstration y met des genres), puis les genres eux-mêmes, que des
    // sites utilisent pour le type (« Manhwa »).
    var type = OutilsWordPress.typeDepuisTexte(
      _texteValeur(racine, RegExp(r'^type', caseSensitive: false)),
    );
    if (type == TypeTitre.autre) {
      type = OutilsWordPress.typeDepuisTexte(categories.join(' '));
    }

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

  /// Chapitres listés dans [html] (fiche ou réponse de `ajax/chapters/`),
  /// dans l'ordre du site (du plus récent au plus ancien), en [langue].
  ///
  /// Un chapitre réservé (classe `premium` / `vip` ou icône de cadenas,
  /// achat de pièces ou connexion) est rendu avec `urlExterne` : il se lit
  /// sur le site et n'est jamais téléchargé.
  ///
  /// LIMITE : la forme exacte des chapitres réservés n'a pas pu être
  /// vérifiée sur une page réelle (le site de démonstration n'en a pas).
  static List<Chapitre> analyserChapitres(
    String html,
    Uri urlTitre, {
    String langue = '',
    DateTime? maintenant,
  }) {
    final document = parse(html);
    final heure = maintenant ?? DateTime.now();
    final chapitres = <Chapitre>[];
    final urlsVues = <String>{};
    // `li.wp-manga-chapter` : un li par chapitre, dans la fiche ou dans la
    // réponse de `ajax/chapters/` (volumes en sous-listes imbriquées).
    for (final ligne in document.querySelectorAll('li.wp-manga-chapter')) {
      // Le premier lien du li mène au chapitre ; un second lien éventuel
      // (`.c-new-tag` dans la date) pointe vers la même page.
      final lien = ligne.querySelector('a[href]');
      final href = lien?.attributes['href']?.trim() ?? '';
      if (lien == null || href.isEmpty || href.startsWith('javascript')) {
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
      var nom = OutilsWordPress.nettoyer(OutilsWordPress.texteDirect(lien));
      if (nom.isEmpty) {
        nom = OutilsWordPress.nettoyer(lien.text);
      }

      // Date : `.chapter-release-date i` (date absolue) ; les chapitres
      // récents ont à la place un lien `.c-new-tag` dont `title` vaut
      // « 2 days ago ».
      final blocDate = ligne.querySelector('.chapter-release-date');
      final texteDate =
          blocDate?.querySelector('a[title]')?.attributes['title'] ??
          blocDate?.querySelector('i')?.text ??
          blocDate?.text ??
          '';
      final classes = ligne.className.toLowerCase();
      final estReserve =
          classes.contains('premium') ||
          classes.contains('vip') ||
          ligne.querySelector('.fa-lock, .ion-md-lock, .ion-ios-lock') != null;

      chapitres.add(
        Chapitre(
          urlChapitre: url,
          nom: nom.isEmpty ? url : nom,
          numero: OutilsWordPress.numeroChapitre(nom, adresse),
          langue: langue,
          datePublication: OutilsWordPress.convertirDate(texteDate, heure),
          urlExterne: estReserve ? url : null,
        ),
      );
    }
    return chapitres;
  }

  /// Lève une [ErreurSource] (adresse [adresse]) si la réponse [html] d'une
  /// demande de liste de chapitres n'est pas une liste du thème : ni
  /// `li.wp-manga-chapter`, ni conteneur de liste connu.
  ///
  /// Un site peut servir en 200 une page étrangère (anti-robot, page de
  /// cache, accueil après redirection) : sans ce contrôle, la liste serait
  /// vide sans erreur.
  ///
  /// LIMITE : le message « aucun chapitre » du thème (`.no-chapter`) n'a pas
  /// pu être vu sur une page réelle ; un titre réellement sans chapitre dont
  /// la réponse n'a aucun des conteneurs reconnus lève donc une erreur.
  static void verifierReponseChapitres(String html, Uri adresse) {
    final document = parse(html);
    // `li.wp-manga-chapter` : un chapitre. `.page-content-listing` et
    // `.listing-chapters_wrap` enveloppent la réponse de `ajax/chapters/`
    // (réponse réelle enregistrée), `.version-chap` est la liste elle-même,
    // `.no-chapter` le message d'un titre sans chapitre.
    if (document.querySelector(
          'li.wp-manga-chapter, .page-content-listing, '
          '.listing-chapters_wrap, .version-chap, .no-chapter',
        ) !=
        null) {
      return;
    }
    throw ErreurSource(
      adresse.toString(),
      "La réponse reçue n'est pas une liste de chapitres Madara (ni "
      'li.wp-manga-chapter ni conteneur de liste du thème : page anti-robot '
      'ou structure inattendue)',
    );
  }

  /// Indique si la réponse [html] de la page [numeroPage] de
  /// `ajax/chapters/` propose une page suivante : liens
  /// `.listing-chapters_wrap .pagination .page a[data-page]` du thème.
  static bool aPageSuivante(String html, int numeroPage) {
    final document = parse(html);
    for (final lien in document.querySelectorAll(
      '.pagination a[data-page], .pagination [data-page]',
    )) {
      if (int.tryParse(lien.attributes['data-page'] ?? '') == numeroPage + 1) {
        return true;
      }
    }
    return false;
  }

  /// Contenu de la page de chapitre [html] (adresse [urlChapitre]).
  ///
  /// Images : `.reading-content img` dans l'ordre (classe
  /// `wp-manga-chapter-img`, adresse dans `data-src` précédée d'une espace
  /// sur le site de démonstration). Roman (chapitre « texte » de WP Manga) :
  /// le bloc `.reading-content .text-left` (ou `.text-right`).
  ///
  /// Lève une [ErreurSource] si la page n'a ni image ni texte en clair
  /// (chapitre réservé, images chargées par un script) : aucun contournement
  /// n'est tenté.
  static ContenuChapitre analyserContenu(String html, Uri urlChapitre) {
    final document = parse(html);
    final lecture = document.querySelector('.reading-content');
    if (lecture == null) {
      throw ErreurSource(
        urlChapitre.toString(),
        "La page reçue n'est pas un chapitre Madara (pas de "
        '.reading-content : structure inattendue, page anti-robot ou '
        'chapitre réservé)',
      );
    }
    final urls = <String>[];
    for (final image in lecture.querySelectorAll('img')) {
      final adresse = OutilsWordPress.adresseImage(image, urlChapitre);
      if (adresse != null) {
        urls.add(adresse);
      }
    }
    if (urls.isNotEmpty) {
      return ContenuChapitre.images(
        urls,
        urlReferer: OutilsWordPress.racineSite(urlChapitre),
      );
    }
    // Chapitre texte : WP Manga place le texte dans `.text-left` (ou
    // `.text-right` pour les langues écrites de droite à gauche).
    final texte = lecture.querySelector('.text-left, .text-right');
    if (texte != null && OutilsWordPress.nettoyer(texte.text).isNotEmpty) {
      return ContenuChapitre.texte(texte.innerHtml.trim());
    }
    throw ErreurSource(
      urlChapitre.toString(),
      'Aucune image ni aucun texte en clair dans ce chapitre Madara '
      '(chapitre réservé ou images chargées par un script) : à lire sur le '
      'site',
    );
  }

  // ---------------------------------------------------------------------
  // Outils privés
  // ---------------------------------------------------------------------

  /// Lève une [ErreurSource] si [document] n'est pas une fiche Madara : le
  /// bloc `.post-title` et l'un des blocs de la fiche (`.summary_content`,
  /// `.tab-summary`, `#manga-chapters-holder`) sont présents sur toutes les
  /// fiches et absents des pages d'erreur ou anti-robot.
  static void _verifierFiche(Document document, Uri urlTitre) {
    final aTitre = document.querySelector('.post-title, #manga-title') != null;
    final aFiche =
        document.querySelector(
          '.summary_content, .tab-summary, #manga-chapters-holder, '
          'li.wp-manga-chapter',
        ) !=
        null;
    if (!aTitre || !aFiche) {
      throw ErreurSource(
        urlTitre.toString(),
        "La page reçue n'est pas une fiche de titre Madara (structure "
        'inattendue, page anti-robot ou titre retiré)',
      );
    }
  }

  /// Valeur (`.summary-content`) de la ligne `.post-content_item` de
  /// [racine] dont le libellé (`.summary-heading`) correspond à [libelle],
  /// ou `null`.
  static Element? _valeur(Element racine, RegExp libelle) {
    for (final ligne in racine.querySelectorAll('.post-content_item')) {
      final titre = OutilsWordPress.nettoyer(
        ligne.querySelector('.summary-heading')?.text ?? '',
      );
      if (titre.isNotEmpty && libelle.hasMatch(titre)) {
        return ligne.querySelector('.summary-content');
      }
    }
    return null;
  }

  /// Texte nettoyé de [_valeur], ou `null` s'il est absent ou vide.
  static String? _texteValeur(Element racine, RegExp libelle) {
    final valeur = _valeur(racine, libelle);
    final texte = valeur == null ? '' : OutilsWordPress.nettoyer(valeur.text);
    return texte.isEmpty ? null : texte;
  }

  /// Auteurs d'un résultat de recherche (lignes `mg_author` puis
  /// `mg_artists`), séparés par des virgules ; `null` si aucun.
  static String? _auteursRecherche(Element bloc) {
    final auteurs = <String>[];
    for (final lien in bloc.querySelectorAll(
      '.mg_author .summary-content a, .mg_artists .summary-content a',
    )) {
      final auteur = OutilsWordPress.nettoyer(lien.text);
      if (auteur.isNotEmpty && !auteurs.contains(auteur)) {
        auteurs.add(auteur);
      }
    }
    return auteurs.isEmpty ? null : auteurs.join(', ');
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
