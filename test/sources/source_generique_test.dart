import 'dart:convert';

import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/lisibilite_site.dart';
import 'package:bibliotheque_perso/sources/source_generique.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

/// Réponse HTML UTF-8.
http.Response reponseHtml(String corps, {int statut = 200}) {
  return http.Response.bytes(
    utf8.encode(corps),
    statut,
    headers: <String, String>{'content-type': 'text/html; charset=UTF-8'},
  );
}

void main() {
  final htmlAccueil = lireExemple('exemples_html/generique_ruri_accueil.html');
  final htmlChapitre = lireExemple(
    'exemples_html/generique_ruri_chapitre.html',
  );
  final htmlDefi = lireExemple('exemples_html/defi_anti_robot.html');
  const urlRacine = 'https://ruri-dragon.online';
  const urlChapitre1 =
      'https://ruri-dragon.online/comic/ruri-dragon-chapter-1/';

  group('adresses', () {
    test('reconnaît une adresse de chapitre', () {
      for (final url in <String>[
        urlChapitre1,
        'https://exemple.org/manga/x/chapitre-10-5/',
        'https://exemple.org/serie/episode_7',
        'https://exemple.org/lire/ch-3',
        'https://exemple.org/manga/x/chapter/12/',
      ]) {
        expect(
          SourceGenerique.estAdresseChapitre(Uri.parse(url)),
          isTrue,
          reason: url,
        );
      }
      for (final url in <String>[
        urlRacine,
        'https://exemple.org/comic/',
        'https://exemple.org/watch-2/',
        'https://exemple.org/chroniques-12/',
        'https://exemple.org/chapter-12abc/',
      ]) {
        expect(
          SourceGenerique.estAdresseChapitre(Uri.parse(url)),
          isFalse,
          reason: url,
        );
      }
    });

    test('adresse invalide : ErreurSource', () {
      expect(
        () => SourceGenerique.validerUrl('ftp://exemple.org/'),
        throwsA(isA<ErreurSource>()),
      );
      expect(
        SourceGenerique.validerUrl('https://exemple.org#haut').toString(),
        'https://exemple.org',
      );
    });
  });

  group('ruri-dragon.online : accueil (page qui liste les chapitres)', () {
    test('chapitres : liens explicites, numéros, dates, ordre de lecture', () {
      final chapitres = SourceGenerique.analyserChapitres(
        htmlAccueil,
        Uri.parse(urlRacine),
        maintenant: DateTime.utc(2026, 11, 17),
      );
      expect(chapitres.map((c) => c.numero).toList(), <double>[
        1,
        2,
        3,
        49,
        49.2,
        50,
        51,
        52,
        53,
      ]);
      final premier = chapitres.first;
      expect(premier.urlChapitre, urlChapitre1);
      expect(premier.nom, 'Chapter 1');
      expect(premier.langue, 'en');
      expect(premier.datePublication, DateTime.utc(2026, 5, 14));
      // Le lien « New Chapter » (sans date) et celui de la liste (avec
      // date) mènent au même chapitre : un seul chapitre, avec la date.
      final dernier = chapitres.last;
      expect(dernier.nom, 'Chapter 53');
      expect(dernier.datePublication, DateTime.utc(2026, 11, 15));
      expect(
        chapitres.where((c) => c.urlChapitre.endsWith('chapter-49-2/')),
        hasLength(1),
      );
    });

    test('fiche : nom, couverture, résumé, auteur, statut, type, genres', () {
      final fiche = SourceGenerique.analyserFiche(
        htmlAccueil,
        Uri.parse(urlRacine),
      );
      final titre = fiche.titre;
      expect(titre.nom, 'Ruri Dragon');
      // Adresse canonique de la page (barre finale du site).
      expect(titre.urlTitre, 'https://ruri-dragon.online/');
      expect(
        titre.urlCouverture,
        'https://ruri-dragon.online/wp-content/uploads/2026/05/'
        'ezgif-35cfa96766ee77fd.jpg',
      );
      expect(titre.resume, startsWith('Originally appearing as a one-shot'));
      expect(titre.auteur, 'Shindou Masaoki');
      expect(titre.statut, 'ongoing');
      expect(titre.typeTitre, TypeTitre.manga);
      expect(fiche.categories, <String>['Slice of Life', 'Supernatural']);
    });
  });

  group('ruri-dragon.online : page de chapitre', () {
    test('images de la zone de lecture, Referer = racine du site', () {
      final contenu = SourceGenerique.analyserContenu(
        htmlChapitre,
        Uri.parse(urlChapitre1),
      );
      expect(contenu.urlsImages, hasLength(6));
      // Espaces de l'adresse d'origine encodés par `Uri.resolve`.
      expect(
        contenu.urlsImages.first,
        'https://laiond.com/images/Ruri%20Dragon/'
        'e55wKWnCNSjEl94LOYB2AFlWNykrbH1778794057.jpg',
      );
      expect(
        contenu.urlsImages.last,
        endsWith('CTrvz5AH2jXPnTApvXIShwWtvtBOpl1778794085.jpg'),
      );
      // Le bouton de dons (image seule dans son bloc) est écarté.
      expect(contenu.urlsImages.any((u) => u.contains('ko-fi')), isFalse);
      expect(contenu.urlReferer, 'https://ruri-dragon.online/');
    });

    test('pages candidates pour remonter à la liste : accueil en premier', () {
      final candidats = SourceGenerique.candidatsPageListe(
        htmlChapitre,
        Uri.parse(urlChapitre1),
        urlBase: urlRacine,
      );
      expect(candidats.map((u) => u.toString()).toList(), <String>[
        'https://ruri-dragon.online/',
        'https://ruri-dragon.online/comic/',
      ]);
    });

    test("un lien « All chapters » passe avant le fil d'Ariane", () {
      const html =
          '<html><body><nav class="breadcrumb">'
          '<a href="/">Accueil</a><a href="/serie/x/">Xeno</a></nav>'
          '<h1>Xeno chapitre 4</h1>'
          '<a href="/serie/x/liste/">All chapters</a></body></html>';
      final candidats = SourceGenerique.candidatsPageListe(
        html,
        Uri.parse('https://exemple.org/serie/x/chapitre-4/'),
        urlBase: 'https://exemple.org',
      );
      expect(candidats.map((u) => u.path).toList(), <String>[
        '/serie/x/liste/',
        // Élément du fil d'Ariane dont le texte (« Xeno ») est dans le nom.
        '/serie/x/',
        '/',
      ]);
    });
  });

  group('heuristiques', () {
    test('le plus grand groupe de liens de même forme est retenu', () {
      const html =
          '<html lang="fr"><body>'
          '<aside><a href="/autre/chapitre-90/">Autre 90</a>'
          '<a href="/autre/chapitre-91/">Autre 91</a></aside>'
          '<ul><li><a href="/oeuvre/chapitre-1/">Chapitre 1</a></li>'
          '<li><a href="/oeuvre/chapitre-2/">Chapitre 2</a></li>'
          '<li><a href="/oeuvre/chapitre-3/">Chapitre 3</a></li></ul>'
          '<a href="https://autre-site.org/oeuvre/chapitre-4/">Ailleurs</a>'
          '</body></html>';
      final chapitres = SourceGenerique.analyserChapitres(
        html,
        Uri.parse('https://exemple.org/oeuvre/'),
      );
      expect(chapitres.map((c) => c.urlChapitre).toList(), <String>[
        'https://exemple.org/oeuvre/chapitre-1/',
        'https://exemple.org/oeuvre/chapitre-2/',
        'https://exemple.org/oeuvre/chapitre-3/',
      ]);
      expect(chapitres.first.langue, 'fr');
    });

    test("liens reconnus par leur texte quand l'adresse n'a pas de motif", () {
      const html =
          '<html><body>'
          '<a href="/lire?id=101">Épisode 1</a>'
          '<a href="/lire?id=102">Épisode 2</a>'
          '<a href="/a-propos">À propos</a>'
          '</body></html>';
      final chapitres = SourceGenerique.analyserChapitres(
        html,
        Uri.parse('https://exemple.org/'),
      );
      expect(chapitres.map((c) => c.numero).toList(), <double>[1, 2]);
      expect(chapitres.first.nom, 'Épisode 1');
    });

    test('page sans lien de chapitre : liste vide, fiche refusée', () {
      const html = '<html><body><h1>Blog</h1><a href="/x">X</a></body></html>';
      final url = Uri.parse('https://exemple.org/');
      expect(SourceGenerique.analyserChapitres(html, url), isEmpty);
      expect(
        () => SourceGenerique.analyserFiche(html, url),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('Aucun lien de chapitre'),
          ),
        ),
      );
    });

    test('images en data-src / data-lazy-src', () {
      const html =
          '<html><body><img src="/logo.png">'
          '<div class="lecture">'
          '<img src="data:image/gif;base64,R0" data-src="/p/1.jpg">'
          '<img data-lazy-src="/p/2.jpg">'
          '<img src="/p/3.jpg">'
          '</div></body></html>';
      final contenu = SourceGenerique.analyserContenu(
        html,
        Uri.parse('https://exemple.org/oeuvre/chapitre-1/'),
      );
      expect(contenu.urlsImages, <String>[
        'https://exemple.org/p/1.jpg',
        'https://exemple.org/p/2.jpg',
        'https://exemple.org/p/3.jpg',
      ]);
    });

    test('script brouillé ou canvas : ErreurSource, aucun décodage', () {
      final url = Uri.parse('https://exemple.org/oeuvre/chapitre-1/');
      const brouille =
          '<html><body><div id="lecteur"></div>'
          '<script>eval(atob("ZG9jdW1lbnQud3JpdGUoKQ=="))</script>'
          '</body></html>';
      expect(
        () => SourceGenerique.analyserContenu(brouille, url),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('script brouillé'),
          ),
        ),
      );
      const canvas = '<html><body><canvas id="page"></canvas></body></html>';
      expect(
        () => SourceGenerique.analyserContenu(canvas, url),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('canvas'),
          ),
        ),
      );
    });

    test('page de défi anti-robot : erreur dédiée', () {
      expect(
        () => SourceGenerique.analyserChapitres(
          htmlDefi,
          Uri.parse('https://exemple.org/'),
        ),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.protectionAntiRobot,
            'protection',
            isTrue,
          ),
        ),
      );
    });
  });

  group('réglages (configurationSelecteurs)', () {
    const html =
        '<html><body><h1>Pub</h1><h2 class="nom"> Mon titre </h2>'
        '<div class="cv"><img src="/c.jpg"></div>'
        '<div class="res"><p>Un résumé.</p></div>'
        '<span class="aut">Une Autrice</span>'
        '<ul class="tags"><li>Action</li><li>Drame</li></ul>'
        '<div class="liste"><a href="/lire/aa-7">Lire</a>'
        '<a href="/lire/aa-8">Lire</a></div>'
        '<div class="pages"><img src="/i/1.png"></div>'
        '</body></html>';
    final configuration = ConfigurationGenerique.depuisJson(
      jsonEncode(<String, String>{
        'selecteurTitre': 'h2.nom',
        'selecteurCouverture': '.cv',
        'selecteurResume': '.res',
        'selecteurAuteur': '.aut',
        'selecteurCategories': '.tags li',
        'selecteurLiensChapitres': '.liste a',
        'selecteurImagesChapitre': '.pages img',
        'motifNumeroChapitre': r'aa-(\d+)',
      }),
    );
    final url = Uri.parse('https://exemple.org/oeuvre');

    test('fiche et chapitres lus par les sélecteurs et le motif', () {
      final fiche = SourceGenerique.analyserFiche(
        html,
        url,
        configuration: configuration,
      );
      expect(fiche.titre.nom, 'Mon titre');
      expect(fiche.titre.urlCouverture, 'https://exemple.org/c.jpg');
      expect(fiche.titre.resume, 'Un résumé.');
      expect(fiche.titre.auteur, 'Une Autrice');
      expect(fiche.categories, <String>['Action', 'Drame']);
      final chapitres = SourceGenerique.analyserChapitres(
        html,
        url,
        configuration: configuration,
      );
      expect(chapitres.map((c) => c.numero).toList(), <double>[7, 8]);
      expect(chapitres.first.urlChapitre, 'https://exemple.org/lire/aa-7');
    });

    test('images lues par le sélecteur, même seules', () {
      final contenu = SourceGenerique.analyserContenu(
        html,
        Uri.parse('https://exemple.org/lire/aa-7'),
        configuration: configuration,
      );
      expect(contenu.urlsImages, <String>['https://exemple.org/i/1.png']);
    });

    test('JSON, valeur ou motif invalides : ErreurSource', () {
      for (final json in <String>[
        '{pas du json',
        '[1, 2]',
        '{"selecteurTitre": 3}',
        '{"motifNumeroChapitre": "("}',
      ]) {
        expect(
          () => ConfigurationGenerique.depuisJson(json),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.typeDetecte,
              'type',
              TypeSource.generique,
            ),
          ),
          reason: json,
        );
      }
      expect(ConfigurationGenerique.depuisJson(null).estVide, isTrue);
      expect(ConfigurationGenerique.depuisJson('  ').estVide, isTrue);
    });

    test('sélecteur CSS invalide : ErreurSource claire', () {
      final mauvais = ConfigurationGenerique.depuisJson(
        '{"selecteurLiensChapitres": "a[["}',
      );
      expect(
        () => SourceGenerique.analyserChapitres(
          html,
          url,
          configuration: mauvais,
        ),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('selecteurLiensChapitres'),
          ),
        ),
      );
    });
  });

  group('réseau simulé', () {
    test("adresse d'un chapitre collée : remontée à l'accueil, 2 requêtes au "
        'total pour la fiche et les chapitres', () async {
      final requetes = <http.Request>[];
      final client = creerClientTest((requete) async {
        requetes.add(requete);
        final url = requete.url.toString();
        if (url == urlChapitre1) {
          return reponseHtml(htmlChapitre);
        }
        if (url == 'https://ruri-dragon.online/') {
          return reponseHtml(htmlAccueil);
        }
        return reponseHtml('introuvable', statut: 404);
      }, HorlogeFactice());
      final source = SourceGenerique(client, urlBase: urlRacine);
      final fiche = await source.recupererFiche(urlChapitre1);
      final chapitres = await source.recupererChapitres(urlChapitre1);
      expect(fiche.titre.nom, 'Ruri Dragon');
      expect(fiche.titre.urlTitre, 'https://ruri-dragon.online/');
      expect(chapitres, hasLength(9));
      expect(requetes.map((r) => r.url.toString()).toList(), <String>[
        urlChapitre1,
        'https://ruri-dragon.online/',
      ]);
      for (final requete in requetes) {
        expect(requete.headers['User-Agent'], userAgentApplication);
      }
    });

    test("accueil collé sans barre finale : une seule requête", () async {
      final requetes = <String>[];
      final client = creerClientTest((requete) async {
        requetes.add(requete.url.toString());
        return reponseHtml(htmlAccueil);
      }, HorlogeFactice());
      final source = SourceGenerique(client, urlBase: urlRacine);
      final fiche = await source.recupererFiche(urlRacine);
      final chapitres = await source.recupererChapitres(urlRacine);
      expect(fiche.titre.urlTitre, 'https://ruri-dragon.online/');
      expect(chapitres.last.numero, 53);
      expect(requetes, <String>[urlRacine]);
    });

    test('contenu : images et Referer', () async {
      final client = creerClientTest(
        (requete) async => reponseHtml(htmlChapitre),
        HorlogeFactice(),
      );
      final contenu = await SourceGenerique(
        client,
        urlBase: urlRacine,
      ).recupererContenu(urlChapitre1);
      expect(contenu.urlsImages, hasLength(6));
      expect(contenu.urlReferer, 'https://ruri-dragon.online/');
    });

    test(
      "chapitre dont la liste n'est pas trouvée : ErreurSource explicite",
      () async {
        final client = creerClientTest((requete) async {
          if (requete.url.toString() == urlChapitre1) {
            return reponseHtml(htmlChapitre);
          }
          return reponseHtml('<html><body><h1>Vide</h1></body></html>');
        }, HorlogeFactice());
        final source = SourceGenerique(client, urlBase: urlRacine);
        await expectLater(
          source.recupererFiche(urlChapitre1),
          throwsA(
            isA<ErreurSource>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('page qui liste les chapitres'),
                )
                .having((e) => e.typeDetecte, 'type', TypeSource.generique),
          ),
        );
      },
    );

    test('défi anti-robot (403) : erreur dédiée, aucune autre page', () async {
      var appels = 0;
      final client = creerClientTest((requete) async {
        appels++;
        return reponseHtml(htmlDefi, statut: 403);
      }, HorlogeFactice());
      final source = SourceGenerique(client, urlBase: urlRacine);
      await expectLater(
        source.recupererFiche(urlRacine),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.protectionAntiRobot, 'protection', isTrue)
              .having((e) => e.typeDetecte, 'type', TypeSource.generique),
        ),
      );
      expect(appels, 1);
    });

    test('recherche : vide sans requête, sinon ErreurSource', () async {
      final source = SourceGenerique(
        creerClientTest((requete) async => reponseHtml(''), HorlogeFactice()),
        urlBase: urlRacine,
      );
      expect(await source.rechercher('  '), isEmpty);
      await expectLater(
        source.rechercher('ruri'),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('verifierLisibilite', () {
    test('accueil de ruri-dragon.online : lisible, œuvre unique', () {
      final diagnostic = verifierLisibilite(htmlAccueil, Uri.parse(urlRacine));
      expect(diagnostic.estLisible, isTrue);
      expect(diagnostic.nombreLiensChapitres, 9);
      expect(diagnostic.estOeuvreUnique, isTrue);
      expect(diagnostic.estPageChapitre, isFalse);
    });

    test('chapitre de ruri-dragon.online : lisible, 6 images', () {
      final diagnostic = verifierLisibilite(
        htmlChapitre,
        Uri.parse(urlChapitre1),
      );
      expect(diagnostic.estLisible, isTrue);
      expect(diagnostic.estPageChapitre, isTrue);
      expect(diagnostic.nombreImages, 6);
      expect(diagnostic.remarques.first, contains("celle d'un chapitre"));
    });

    test('défi anti-robot', () {
      final diagnostic = verifierLisibilite(
        htmlDefi,
        Uri.parse('https://www.scan-manga.com/6678/x.html'),
        codeStatut: 403,
      );
      expect(diagnostic.estLisible, isFalse);
      expect(diagnostic.protectionAntiRobot, isTrue);
      expect(
        diagnostic.raisons.single,
        contains('www.scan-manga.com a activé une protection anti-robot'),
      );
    });

    test('page sans chapitre, page de connexion, page en JavaScript', () {
      expect(
        verifierLisibilite(
          '<html><body><h1>Blog</h1><p>${'texte ' * 60}</p>'
          '<a href="/a">A</a><a href="/b">B</a><a href="/c">C</a>'
          '</body></html>',
          Uri.parse('https://exemple.org/'),
        ).raisons.single,
        contains('Aucun lien de chapitre'),
      );
      expect(
        verifierLisibilite(
          '<html><body><form><input type="password"></form></body></html>',
          Uri.parse('https://exemple.org/connexion'),
        ).raisons.first,
        contains('connexion'),
      );
      expect(
        verifierLisibilite(
          '<html><body><div id="root"></div>'
          '<script src="/app.js"></script></body></html>',
          Uri.parse('https://exemple.org/'),
        ).raisons.first,
        contains('JavaScript'),
      );
    });

    test('chapitre au script brouillé', () {
      final diagnostic = verifierLisibilite(
        '<html><body><script>eval(function(p,a,c,k,e,d){})</script>'
        '</body></html>',
        Uri.parse('https://exemple.org/oeuvre/chapter-3/'),
      );
      expect(diagnostic.raisons.single, contains('script brouillé'));
    });

    test('erreur HTTP ordinaire', () {
      final diagnostic = verifierLisibilite(
        'Introuvable',
        Uri.parse('https://exemple.org/x'),
        codeStatut: 404,
      );
      expect(diagnostic.raisons.single, contains('HTTP 404'));
    });
  });

  test('compterLiensChapitres et imagesChapitre (outils du diagnostic)', () {
    expect(
      SourceGenerique.compterLiensChapitres(
        parse(htmlAccueil),
        Uri.parse(urlRacine),
      ),
      9,
    );
    expect(
      SourceGenerique.imagesChapitre(parse(htmlAccueil), Uri.parse(urlRacine)),
      isEmpty,
    );
  });
}
