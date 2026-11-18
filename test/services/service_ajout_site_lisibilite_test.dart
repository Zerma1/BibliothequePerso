// ServiceAjoutSite : refus d'une page générique illisible à l'ajout (retour
// C2 de la 0.2.1-test, faux positif Wikipédia) et changement de type d'un
// site (X5). Base en mémoire, pages HTML simulées par un MockClient.
import 'dart:convert';

import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/lisibilite_site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Accueil d'un site sans marqueur Madara ni MangaThemesia : générique.
const String _accueil =
    '<html><head><title>Accueil</title></head><body><h1>Bienvenue</h1>'
    '<p>Un site de lecture.</p></body></html>';

/// Article d'encyclopédie : beaucoup de texte et de liens, aucun chapitre.
final String _article =
    '<html><head><title>One Piece — Wikipédia</title></head><body>'
    '<h1>One Piece</h1>'
    '${List<String>.generate(30, (i) => '<p>Paragraphe $i sur le manga, '
        'son auteur et sa publication.</p><a href="/wiki/Page_$i">Page $i</a>').join()}'
    '</body></html>';

/// Page d'un titre lisible : liens explicites vers ses chapitres.
const String _pageTitre =
    '<html><head><title>Mon œuvre</title></head><body><h1>Mon œuvre</h1>'
    '<ul>'
    '<li><a href="/comic/mon-oeuvre-chapter-1/">Chapter 1</a></li>'
    '<li><a href="/comic/mon-oeuvre-chapter-2/">Chapter 2</a></li>'
    '<li><a href="/comic/mon-oeuvre-chapter-3/">Chapter 3</a></li>'
    '</ul></body></html>';

http.Response _html(String corps) => http.Response.bytes(
  utf8.encode(corps),
  200,
  headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
);

void main() {
  late Database base;
  late DepotSources depot;
  late ServiceAjoutSite service;
  late List<Uri> requetes;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotSources(base);
    requetes = <Uri>[];
    final client = creerClientTest((http.Request requete) async {
      requetes.add(requete.url);
      final chemin = requete.url.path;
      if (chemin.isEmpty || chemin == '/') return _html(_accueil);
      if (chemin.startsWith('/wiki/')) return _html(_article);
      if (chemin.startsWith('/oeuvre')) return _html(_pageTitre);
      return http.Response('introuvable', 404);
    }, HorlogeFactice());
    service = ServiceAjoutSite(
      depot,
      DetecteurTypeSite(client),
      client: client,
    );
  });

  tearDown(() => base.close());

  group('ajout d’un site générique (C2)', () {
    test(
      'une page sans chapitre est refusée et rien n’est enregistré',
      () async {
        await expectLater(
          service.ajouterSite('https://fr.wikipedia.test/wiki/One_Piece'),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.message, 'message', contains('chapitre'))
                .having((e) => e.typeDetecte, 'type', TypeSource.generique),
          ),
        );
        expect(await depot.chargerSources(), isEmpty);
      },
    );

    test('une page de titre lisible est acceptée', () async {
      final source = await service.ajouterSite(
        'https://oeuvre.test/oeuvre/mon-oeuvre',
      );
      expect(source.typeSource, TypeSource.generique);
      expect(source.urlBase, 'https://oeuvre.test');
      // Accueil (détection) puis page collée : deux requêtes, pas plus.
      expect(requetes, hasLength(2));
    });

    test('la racine seule reste acceptée sans chapitre', () async {
      final source = await service.ajouterSite('https://portail.test/');
      expect(source.typeSource, TypeSource.generique);
      // Accueil (détection) puis page collée, relue pour les refus sûrs.
      expect(requetes, hasLength(2));
    });

    test('un type forcé n’est pas revérifié', () async {
      final source = await service.ajouterSite(
        'https://fr.wikipedia.test/wiki/One_Piece',
        typeForce: TypeSource.generique,
      );
      expect(source.typeSource, TypeSource.generique);
      expect(requetes, isEmpty);
    });

    test('des réglages CSS fournis servent à la vérification', () async {
      final source = await service.ajouterSite(
        'https://fr.wikipedia.test/wiki/One_Piece',
        configurationSelecteurs: '{"selecteurLiensChapitres":"a"}',
      );
      expect(source.typeSource, TypeSource.generique);
    });

    test('sans client HTTP, la vérification n’est pas faite', () async {
      final client = creerClientTest(
        (http.Request requete) async => _html(_accueil),
        HorlogeFactice(),
      );
      final sansClient = ServiceAjoutSite(depot, DetecteurTypeSite(client));
      final source = await sansClient.ajouterSite(
        'https://fr.wikipedia.test/wiki/One_Piece',
      );
      expect(source.typeSource, TypeSource.generique);
    });

    test('estPageAccueil distingue un accueil d’une page précise', () {
      for (final accueil in const <String>[
        'https://a.test',
        'https://a.test/',
        'https://a.test/?p=1',
        'https://a.test/fr/',
        'https://a.test/index.php',
        'https://a.test/home',
        'https://a.test/manga/',
        'https://a.test//fr//',
      ]) {
        expect(
          ServiceAjoutSite.estPageAccueil(Uri.parse(accueil)),
          isTrue,
          reason: accueil,
        );
      }
      for (final precise in const <String>[
        'https://a.test/wiki/Ruri_Dragon',
        'https://a.test/manga/titre/',
        'https://a.test/fr/manga/titre?page=2',
      ]) {
        expect(
          ServiceAjoutSite.estPageAccueil(Uri.parse(precise)),
          isFalse,
          reason: precise,
        );
      }
    });
  });

  group('accueils et refus sûrs (relecture C2)', () {
    late Database baseC2;
    late DepotSources depotC2;
    late ServiceAjoutSite serviceC2;

    /// Page de connexion : un champ de mot de passe, aucun chapitre.
    const connexion =
        '<html><head><title>Connexion</title></head><body><form>'
        '<input type="text" name="nom"><input type="password" name="mdp">'
        '</form></body></html>';

    /// Coquille JavaScript : presque rien dans le HTML reçu.
    const coquille =
        '<html><head><title>Appli</title></head><body><div id="app"></div>'
        '<script src="/app.js"></script></body></html>';

    /// Défi anti-robot servi en code 200.
    const defi =
        '<html><head><title>Just a moment...</title></head><body>'
        '<script src="/cdn-cgi/challenge-platform/h/b/orchestrate.js">'
        '</script></body></html>';

    setUp(() async {
      baseC2 = await ouvrirBaseDeTest();
      depotC2 = DepotSources(baseC2);
      final client = creerClientTest((http.Request requete) async {
        final chemin = requete.url.path;
        // Racine de chaque site : accueil générique ordinaire (détection).
        if (chemin.isEmpty || chemin == '/') {
          return _html(_accueil);
        }
        return switch (requete.url.host) {
          'connexion.test' => _html(connexion),
          'coquille.test' => _html(coquille),
          'robot.test' => _html(defi),
          // Accueils, pages de langue, catalogues : beaucoup de liens et
          // de texte, aucun lien de chapitre.
          _ => _html(_article),
        };
      }, HorlogeFactice());
      serviceC2 = ServiceAjoutSite(
        depotC2,
        DetecteurTypeSite(client),
        client: client,
      );
    });

    tearDown(() => baseC2.close());

    for (final accueil in const <String>[
      'https://un.test/fr/',
      'https://deux.test/index.php',
      'https://trois.test/home',
      'https://quatre.test/?lang=fr',
      'https://cinq.test/manga/',
    ]) {
      test('l’accueil $accueil est accepté sans chapitre', () async {
        final source = await serviceC2.ajouterSite(accueil);
        expect(source.typeSource, TypeSource.generique);
      });
    }

    test('une page Wikipédia reste refusée', () async {
      await expectLater(
        serviceC2.ajouterSite('https://fr.wikipedia.test/wiki/Ruri_Dragon'),
        throwsA(isA<ErreurSource>()),
      );
      expect(await depotC2.chargerSources(), isEmpty);
    });

    test('un accueil qui demande une connexion est refusé', () async {
      await expectLater(
        serviceC2.ajouterSite('https://connexion.test/home'),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('connexion'),
          ),
        ),
      );
      expect(await depotC2.chargerSources(), isEmpty);
    });

    test('un accueil construit en JavaScript est refusé', () async {
      await expectLater(
        serviceC2.ajouterSite('https://coquille.test/fr/'),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('JavaScript'),
          ),
        ),
      );
      expect(await depotC2.chargerSources(), isEmpty);
    });

    test('un accueil protégé par un défi anti-robot est refusé', () async {
      await expectLater(
        serviceC2.ajouterSite('https://robot.test/fr/'),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.protectionAntiRobot,
            'anti-robot',
            isTrue,
          ),
        ),
      );
      expect(await depotC2.chargerSources(), isEmpty);
    });

    test('raisonRefusSur ignore la seule absence de chapitres', () {
      final sansChapitre = verifierLisibilite(
        _article,
        Uri.parse('https://a.test/wiki/X'),
      );
      expect(sansChapitre.estLisible, isFalse);
      expect(ServiceAjoutSite.raisonRefusSur(sansChapitre), isNull);
      final page = verifierLisibilite(connexion, Uri.parse('https://a.test/'));
      expect(ServiceAjoutSite.raisonRefusSur(page), contains('connexion'));
    });
  });

  group('changement de type (X5)', () {
    late Source generique;

    setUp(() async {
      generique = await depot.enregistrerSource(
        const Source(
          nom: 'Générique',
          urlBase: 'https://generique.test',
          typeSource: TypeSource.generique,
          configurationSelecteurs: '{"selecteurTitre":"h1"}',
        ),
      );
    });

    test('passer en Madara efface les réglages du type générique', () async {
      final modifiee = await service.modifierSource(
        generique.copierAvec(typeSource: TypeSource.madara),
      );
      expect(modifiee.typeSource, TypeSource.madara);
      expect(modifiee.configurationSelecteurs, isNull);
      expect(
        (await depot.chargerSource(generique.id!))!.typeSource,
        TypeSource.madara,
      );
    });

    test('revenir au type générique est accepté', () async {
      final madara = await service.modifierSource(
        generique.copierAvec(typeSource: TypeSource.madara),
      );
      final retour = await service.modifierSource(
        madara.copierAvec(typeSource: TypeSource.generique),
      );
      expect(retour.typeSource, TypeSource.generique);
    });

    test('un type réservé à un site officiel est refusé ailleurs', () async {
      await expectLater(
        service.modifierSource(
          generique.copierAvec(typeSource: TypeSource.mangaDex),
        ),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('réservé'),
          ),
        ),
      );
      expect(
        (await depot.chargerSource(generique.id!))!.typeSource,
        TypeSource.generique,
      );
    });

    test('le type d’un site reconnu par son domaine ne change pas', () async {
      final mangaDex = await depot.enregistrerSource(
        const Source(
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
        ),
      );
      await expectLater(
        service.modifierSource(
          mangaDex.copierAvec(typeSource: TypeSource.madara),
        ),
        throwsA(isA<ErreurService>()),
      );
      // Un simple renommage reste possible.
      final renomme = await service.modifierSource(
        mangaDex.copierAvec(nom: 'MD'),
      );
      expect(renomme.nom, 'MD');
    });

    test('un type forcé incohérent est refusé avant toute requête', () async {
      await expectLater(
        service.ajouterSite(
          'https://autre.test',
          typeForce: TypeSource.webtoons,
        ),
        throwsA(isA<ErreurService>()),
      );
      expect(requetes, isEmpty);
    });

    test('erreurTypeSite est une règle pure', () {
      expect(
        ServiceAjoutSite.erreurTypeSite(
          'https://site.test',
          TypeSource.mangaThemesia,
        ),
        isNull,
      );
      expect(
        ServiceAjoutSite.erreurTypeSite(
          'https://www.webtoons.com',
          TypeSource.webtoons,
        ),
        isNull,
      );
      expect(
        ServiceAjoutSite.erreurTypeSite(
          'https://www.webtoons.com',
          TypeSource.generique,
        ),
        isNotNull,
      );
    });
  });
}
