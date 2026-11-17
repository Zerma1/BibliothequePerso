import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:bibliotheque_perso/sources/source_madara.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

/// Pages réelles du site de démonstration du thème Madara
/// (live.mangabooth.com), enregistrées le 2026-11-17 et allégées. Aucun appel
/// réseau dans les tests.
const String urlBase = 'https://live.mangabooth.com';
const String urlTitre = 'https://live.mangabooth.com/manga/hajime-boyfriend/';
const String urlChapitre1 =
    'https://live.mangabooth.com/manga/hajime-boyfriend/volume-1/chapter-1/';

final String htmlAccueil = lireExemple('exemples_html/madara_accueil.html');
final String htmlFiche = lireExemple('exemples_html/madara_fiche.html');
final String htmlChapitres = lireExemple(
  'exemples_html/madara_chapitres_ajax.html',
);
final String htmlChapitre = lireExemple('exemples_html/madara_chapitre.html');
final String htmlRecherche = lireExemple('exemples_html/madara_recherche.html');

/// Réponse HTML UTF-8, comme le site.
http.Response reponseHtml(String corps, {int statut = 200}) {
  return http.Response(
    corps,
    statut,
    headers: <String, String>{'content-type': 'text/html; charset=UTF-8'},
  );
}

/// Adaptateur branché sur [gestionnaire] (aucun réseau).
SourceMadara creerSource(
  Future<http.Response> Function(http.Request requete) gestionnaire, {
  HorlogeFactice? horloge,
  String languesPreferees = '',
}) {
  final h = horloge ?? HorlogeFactice();
  return SourceMadara(
    creerClientTest(gestionnaire, h),
    urlBase: urlBase,
    languesPreferees: languesPreferees,
    maintenant: h.lire,
  );
}

void main() {
  test('la page d\'accueil réelle est détectée comme Madara', () {
    expect(
      DetecteurTypeSite.detecterDepuisHtml(htmlAccueil),
      TypeSource.madara,
    );
  });

  test('la fabrique crée un SourceMadara pour une source Madara', () {
    final fabrique = FabriqueSources(
      creerClientTest((r) async => reponseHtml(''), HorlogeFactice()),
    );
    final adaptateur = fabrique.creer(
      const Source(
        nom: 'Démo',
        urlBase: urlBase,
        typeSource: TypeSource.madara,
        langueParDefaut: 'fr,en',
      ),
    );
    expect(adaptateur, isA<SourceMadara>());
    expect((adaptateur as SourceMadara).urlBase, urlBase);
    expect(adaptateur.languesPreferees, 'fr,en');
  });

  group('adresses', () {
    test('forme canonique : sans paramètres, terminée par /', () {
      expect(
        SourceMadara.validerUrlTitre(
          'https://live.mangabooth.com/manga/hajime-boyfriend?x=1#haut',
        ).toString(),
        urlTitre,
      );
      expect(SourceMadara.validerUrlTitre(urlTitre).toString(), urlTitre);
    });

    test('adresse invalide : ErreurSource typée Madara', () {
      for (final url in <String>[
        'ftp://site/manga/x/',
        'https://site.org/',
        'x',
      ]) {
        expect(
          () => SourceMadara.validerUrlTitre(url),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.typeDetecte,
              'typeDetecte',
              TypeSource.madara,
            ),
          ),
          reason: url,
        );
      }
    });

    test('lecture en liste : style=list ajouté, autres paramètres gardés', () {
      expect(
        SourceMadara.adresseLectureEnListe(Uri.parse(urlChapitre1)).toString(),
        '$urlChapitre1?style=list',
      );
      expect(
        SourceMadara.adresseLectureEnListe(
          Uri.parse('$urlChapitre1?host=local&style=paged'),
        ).queryParameters,
        <String, String>{'host': 'local', 'style': 'list'},
      );
    });
  });

  group('fiche (page réelle)', () {
    final fiche = SourceMadara.analyserFiche(htmlFiche, Uri.parse(urlTitre));

    test('nom, couverture, résumé', () {
      expect(fiche.titre.nom, 'Hajime boyfriend');
      expect(fiche.titre.urlTitre, urlTitre);
      // data-src (et non l'image d'attente dflazy.jpg de src).
      expect(
        fiche.titre.urlCouverture,
        'https://live.mangabooth.com/wp-content/uploads/2017/12/'
        'pexels-huynh-van-9334944-193x278.jpg',
      );
      expect(fiche.titre.resume, startsWith('Makunachi is an ordinary high'));
      expect(fiche.titre.resume, contains("doesn’t get to enjoy"));
    });

    test("auteurs et artistes, sans l'équipe de traduction", () {
      expect(fiche.titre.auteur, 'Achitaka, Mijimura, Natakiwa');
      expect(fiche.titre.auteur, isNot(contains('MangaBooth Team')));
    });

    test('genres, statut et type', () {
      expect(fiche.categories, <String>['Action', 'Comedy', 'Shounen']);
      expect(fiche.titre.statut, 'OnGoing');
      // La ligne « Type » de la démo contient des genres : aucun type connu.
      expect(fiche.titre.typeTitre, TypeTitre.autre);
      expect(fiche.titre.titresAlternatifs, isEmpty);
    });

    test('variante : titres alternatifs, badge dans le h1, type Manhwa', () {
      const html = '''
<html lang="fr-FR"><body><div class="profile-manga">
<div class="post-title"><h1><span class="manga-title-badges hot">HOT</span> Mon titre </h1></div>
<div class="tab-summary"><div class="summary_content">
<div class="post-content_item"><div class="summary-heading"><h5>Alternative</h5></div>
<div class="summary-content"> Nom 1, 名前 ; Nom 3 </div></div>
<div class="post-content_item"><div class="summary-heading"><h5>Type</h5></div>
<div class="summary-content"> Manhwa </div></div>
</div></div></div></body></html>''';
      final variante = SourceMadara.analyserFiche(html, Uri.parse(urlTitre));
      expect(variante.titre.nom, 'Mon titre');
      expect(variante.titre.titresAlternatifs.map((a) => a.nom), <String>[
        'Nom 1',
        '名前',
        'Nom 3',
      ]);
      expect(variante.titre.typeTitre, TypeTitre.manhwa);
    });

    test("page qui n'est pas une fiche : ErreurSource", () {
      expect(
        () => SourceMadara.analyserFiche(htmlChapitre, Uri.parse(urlTitre)),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('chapitres', () {
    test('réponse réelle de ajax/chapters : 15 chapitres datés', () {
      final chapitres = SourceMadara.analyserChapitres(
        htmlChapitres,
        Uri.parse(urlTitre),
        langue: 'en',
      );
      expect(chapitres, hasLength(15));
      // Ordre du site : du plus récent au plus ancien.
      expect(chapitres.first.nom, 'Chapter 15');
      expect(chapitres.first.numero, 15);
      expect(chapitres.last.urlChapitre, urlChapitre1);
      expect(chapitres.last.numero, 1);
      expect(chapitres.last.langue, 'en');
      expect(chapitres.last.datePublication, DateTime.utc(2017, 10, 11));
      expect(chapitres.every((c) => c.urlExterne == null), isTrue);
    });

    test(
      'variantes : date relative, chapitre premium, numéro dans l\'adresse',
      () {
        final horloge = HorlogeFactice();
        const html = '''
<ul class="main version-chap">
<li class="wp-manga-chapter premium"><a href="/manga/x/chapter-12-5/">Bonus <i class="fas fa-lock"></i></a>
<span class="chapter-release-date"><a href="/manga/x/chapter-12-5/" title="2 days ago" class="c-new-tag">new</a></span></li>
<li class="wp-manga-chapter"><a href="/manga/x/chapter-12/">Chapitre 12</a>
<span class="chapter-release-date"><i>il y a 3 heures</i></span></li>
</ul>''';
        final chapitres = SourceMadara.analyserChapitres(
          html,
          Uri.parse('https://site.test/manga/x/'),
          maintenant: horloge.maintenant,
        );
        expect(chapitres, hasLength(2));
        expect(chapitres[0].numero, 12.5);
        expect(
          chapitres[0].urlExterne,
          'https://site.test/manga/x/chapter-12-5/',
        );
        expect(
          chapitres[0].datePublication,
          horloge.maintenant.subtract(const Duration(days: 2)),
        );
        expect(chapitres[1].numero, 12);
        expect(chapitres[1].urlExterne, isNull);
        expect(
          chapitres[1].datePublication,
          horloge.maintenant.subtract(const Duration(hours: 3)),
        );
      },
    );

    test('pagination : page suivante annoncée par data-page', () {
      const html =
          '<div class="listing-chapters_wrap"><ul class="pagination">'
          '<li class="page current"><a data-page="1">1</a></li>'
          '<li class="page"><a data-page="2">2</a></li></ul></div>';
      expect(SourceMadara.aPageSuivante(html, 1), isTrue);
      expect(SourceMadara.aPageSuivante(html, 2), isFalse);
      expect(SourceMadara.aPageSuivante(htmlChapitres, 1), isFalse);
    });

    test(
      'recupererChapitres : fiche puis POST ajax/chapters, ordre croissant',
      () async {
        final requetes = <http.Request>[];
        final source = creerSource((requete) async {
          requetes.add(requete);
          if (requete.method == 'POST') {
            return reponseHtml(htmlChapitres);
          }
          return reponseHtml(htmlFiche);
        });
        final fiche = await source.recupererFiche(urlTitre);
        final chapitres = await source.recupererChapitres(urlTitre);
        expect(fiche.titre.nom, 'Hajime boyfriend');
        // La fiche n'est demandée qu'une fois (page gardée en mémoire).
        expect(requetes.map((r) => '${r.method} ${r.url}'), <String>[
          'GET $urlTitre',
          'POST ${urlTitre}ajax/chapters/?t=1',
        ]);
        final post = requetes.last;
        expect(post.headers['X-Requested-With'], 'XMLHttpRequest');
        expect(post.headers['Referer'], urlTitre);
        expect(post.body, isEmpty);
        expect(chapitres, hasLength(15));
        expect(chapitres.first.numero, 1);
        expect(chapitres.last.numero, 15);
        // Langue lue dans <html lang="en-US">, avant les langues du client.
        expect(chapitres.first.langue, 'en');
      },
    );

    test('ancien thème : 404 sur ajax/chapters puis admin-ajax.php', () async {
      final requetes = <http.Request>[];
      final source = creerSource((requete) async {
        requetes.add(requete);
        if (requete.url.path.endsWith('/ajax/chapters/')) {
          return reponseHtml('introuvable', statut: 404);
        }
        if (requete.url.path == '/wp-admin/admin-ajax.php') {
          return reponseHtml(htmlChapitres);
        }
        return reponseHtml(htmlFiche);
      });
      final chapitres = await source.recupererChapitres(urlTitre);
      expect(chapitres, hasLength(15));
      final dernier = requetes.last;
      expect(dernier.method, 'POST');
      expect(dernier.url.toString(), '$urlBase/wp-admin/admin-ajax.php');
      expect(dernier.bodyFields, <String, String>{
        'action': 'manga_get_chapters',
        'manga': '228',
      });
    });

    test(
      'page 1 étrangère servie en 200 : ErreurSource avec extrait, jamais une '
      'liste vide',
      () async {
        final source = creerSource((requete) async {
          if (requete.method == 'POST') {
            return reponseHtml(
              '<html><body><h1>Just a moment...</h1></body></html>',
            );
          }
          return reponseHtml(htmlFiche);
        });
        await expectLater(
          source.recupererChapitres(urlTitre),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.url, 'url', '${urlTitre}ajax/chapters/?t=1')
                .having(
                  (e) => e.message,
                  'message',
                  contains("n'est pas une liste de chapitres Madara"),
                )
                .having(
                  (e) => e.extraitReponse,
                  'extraitReponse',
                  contains('Just a moment'),
                )
                .having((e) => e.typeDetecte, 'typeDetecte', TypeSource.madara),
          ),
        );
      },
    );

    test(
      'conteneur du thème sans chapitre : accepté ; autre page : erreur',
      () {
        for (final html in <String>[
          '<div class="page-content-listing single-page">'
              '<div class="listing-chapters_wrap"></div></div>',
          '<ul class="main version-chap"></ul>',
          '<span class="no-chapter">No chapters</span>',
        ]) {
          SourceMadara.verifierReponseChapitres(html, Uri.parse(urlTitre));
        }
        // Réponse réelle : acceptée.
        SourceMadara.verifierReponseChapitres(
          htmlChapitres,
          Uri.parse(urlTitre),
        );
        expect(
          () => SourceMadara.verifierReponseChapitres(
            '<p>Accueil</p>',
            Uri.parse(urlTitre),
          ),
          throwsA(isA<ErreurSource>()),
        );
      },
    );

    test(
      'erreur serveur sur la liste : ErreurSource, jamais une liste vide',
      () async {
        final source = creerSource((requete) async {
          if (requete.method == 'POST') {
            return reponseHtml('panne', statut: 403);
          }
          return reponseHtml(htmlFiche);
        });
        await expectLater(
          source.recupererChapitres(urlTitre),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.codeStatut, 'codeStatut', 403)
                .having((e) => e.typeDetecte, 'typeDetecte', TypeSource.madara),
          ),
        );
      },
    );
  });

  group('contenu', () {
    test('page réelle : 15 images dans l\'ordre, Referer du site', () {
      final contenu = SourceMadara.analyserContenu(
        htmlChapitre,
        Uri.parse(urlChapitre1),
      );
      expect(contenu.urlsImages, hasLength(15));
      expect(
        contenu.urlsImages.first,
        'https://live.mangabooth.com/wp-content/uploads/WP-manga/data/'
        'manga_59dc2df66dca9/chapter-1/sample-01.jpg',
      );
      expect(contenu.urlsImages.last, endsWith('/sample-15.jpg'));
      expect(contenu.urlReferer, 'https://live.mangabooth.com/');
    });

    test('recupererContenu demande la page en mode liste', () async {
      final urls = <String>[];
      final source = creerSource((requete) async {
        urls.add(requete.url.toString());
        return reponseHtml(htmlChapitre);
      });
      final contenu = await source.recupererContenu(urlChapitre1);
      expect(urls, <String>['$urlChapitre1?style=list']);
      expect(contenu.urlsImages, hasLength(15));
    });

    test('chapitre texte (roman) : contenu HTML de .text-left', () {
      const html =
          '<div class="reading-content"><div class="text-left">'
          '<p>Il était une fois.</p></div></div>';
      final contenu = SourceMadara.analyserContenu(
        html,
        Uri.parse(urlChapitre1),
      );
      expect(contenu.estTexte, isTrue);
      expect(contenu.texteHtml, '<p>Il était une fois.</p>');
    });

    test('ni image ni texte en clair : ErreurSource sans contournement', () {
      for (final html in <String>[
        '<div class="reading-content"><div class="content-blocked">'
            'Connectez-vous</div></div>',
        '<html><body>Vérification anti-robot</body></html>',
      ]) {
        expect(
          () => SourceMadara.analyserContenu(html, Uri.parse(urlChapitre1)),
          throwsA(isA<ErreurSource>()),
        );
      }
    });
  });

  group('recherche', () {
    test('page réelle : résultats avec nom, couverture et auteurs', () {
      final titres = SourceMadara.analyserRecherche(
        htmlRecherche,
        Uri.parse('$urlBase/?s=boyfriend&post_type=wp-manga'),
      );
      expect(titres, hasLength(2));
      expect(titres.first.nom, 'Hajime boyfriend');
      expect(titres.first.urlTitre, urlTitre);
      expect(titres.first.urlCouverture, endsWith('9334944-193x278.jpg'));
      expect(titres.first.auteur, 'Achitaka, Mijimura, Natakiwa');
      expect(titres.first.statut, 'OnGoing');
      expect(titres[1].nom, '6-ji kara 8-ji made');
    });

    test(
      'rechercher : formulaire du thème, requête vide sans réseau',
      () async {
        final urls = <String>[];
        final source = creerSource((requete) async {
          urls.add(requete.url.toString());
          return reponseHtml(htmlRecherche);
        });
        expect(await source.rechercher('  '), isEmpty);
        expect(urls, isEmpty);
        final titres = await source.rechercher('boyfriend');
        expect(titres, hasLength(2));
        expect(urls, <String>['$urlBase/?s=boyfriend&post_type=wp-manga']);
      },
    );

    test('page sans résultat : liste vide ; autre page : ErreurSource', () {
      const vide =
          '<html><body class="search search-no-results">'
          '<div class="search-wrap"></div></body></html>';
      expect(SourceMadara.analyserRecherche(vide, Uri.parse(urlBase)), isEmpty);
      expect(
        () => SourceMadara.analyserRecherche(
          '<html><body>Just a moment...</body></html>',
          Uri.parse(urlBase),
        ),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  test('erreur de fiche : extrait de la page et type Madara', () async {
    final source = creerSource(
      (requete) async =>
          reponseHtml('<html><body>Just a moment...</body></html>'),
    );
    await expectLater(
      source.recupererFiche(urlTitre),
      throwsA(
        isA<ErreurSource>()
            .having((e) => e.typeDetecte, 'typeDetecte', TypeSource.madara)
            .having(
              (e) => e.extraitReponse,
              'extraitReponse',
              contains('Just a moment'),
            ),
      ),
    );
  });
}
