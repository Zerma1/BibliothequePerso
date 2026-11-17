// ServiceExport (tâche R7) : fichiers JSON et Markdown de la bibliothèque.
// Base en mémoire et dossier temporaire ; aucun appel réseau.
import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_export.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as chemins;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

void main() {
  late Database base;
  late Directory dossier;
  late DepotSources depotSources;
  late DepotTitres depotTitres;
  late DepotChapitres depotChapitres;
  late DepotListes depotListes;
  late ServiceParametres parametres;
  late ServiceExport service;

  final dateExport = DateTime(2026, 11, 16, 14, 30);

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('bibliotheque_export');
    depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    depotListes = DepotListes(base);
    parametres = ServiceParametres(DepotParametres(base));
    service = ServiceExport(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotChapitres: depotChapitres,
      depotListes: depotListes,
      depotCategories: DepotCategories(base),
      dossierExports: ServiceExport.cheminDossierExports(dossier.path),
      serviceParametres: parametres,
      versionApplication: '0.1.0',
      horloge: () => dateExport,
      depotTitresSources: DepotTitresSources(base),
    );
  });

  tearDown(() async {
    await base.close();
    if (await dossier.exists()) await dossier.delete(recursive: true);
  });

  /// Remplit la base : MangaDex (actif) et un site désactivé, deux titres
  /// (l'un favori et dans une liste du client, l'autre sans liste).
  Future<void> remplir() async {
    final mangaDex = await depotSources.enregistrerSource(
      const Source(
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
        langueParDefaut: 'fr,en',
      ),
    );
    final autre = await depotSources.enregistrerSource(
      const Source(
        nom: "L'Étagère",
        urlBase: 'https://etagere.example',
        typeSource: TypeSource.madara,
        estActive: false,
      ),
    );
    final premier = await depotTitres.enregistrerTitre(
      Titre(
        idSource: mangaDex.id,
        urlTitre: urlTitreReference,
        nom: "Death's Daughter — l'épée d'ébène",
        typeTitre: TypeTitre.manga,
        urlCouverture: 'https://uploads.mangadex.org/covers/exemple.jpg',
        auteur: 'Exemple',
        statut: 'En cours',
        niveauContenu: niveauContenuSuggestif,
        titresAlternatifs: const <TitreAlternatif>[
          TitreAlternatif(nom: '死神に育てられた少女', langue: 'ja'),
        ],
      ),
      categories: <String>['Action', 'Comédie'],
    );
    await depotTitres.enregistrerLanguesPreferees(premier.id!, 'fr,en');
    await depotTitres.enregistrerCouvertureChoisie(
      premier.id!,
      r'C:\Users\bapti\Pictures\ma couverture.png',
    );
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (final numero in <double>[1, 2, 12.5, 13])
        Chapitre(
          idTitre: premier.id,
          urlChapitre: 'https://mangadex.org/chapter/c$numero',
          nom: 'Chapitre $numero',
          numero: numero,
          langue: 'fr',
          datePublication: DateTime.utc(2026, 1, numero.toInt()),
        ),
    ]);
    for (final chapitre in await depotChapitres.chargerChapitres(premier.id!)) {
      if (chapitre.numero <= 12.5) await depotChapitres.marquerLu(chapitre.id!);
    }
    final favoris = await depotListes.chargerListeParNom(nomListeFavoris);
    await depotListes.ajouterTitre(favoris!.id!, premier.id!);
    final perso = await depotListes.creerListe('À relire [été]');
    await depotListes.ajouterTitre(perso.id!, premier.id!);

    await depotTitres.enregistrerTitre(
      Titre(
        idSource: autre.id,
        urlTitre: 'https://etagere.example/livre/un (tome 1)',
        nom: 'Un *livre*',
        typeTitre: TypeTitre.livre,
      ),
    );
    await parametres.enregistrerLangues(<String>['fr', 'ja']);
  }

  Map<String, Object?> lireJson(String chemin) =>
      jsonDecode(File(chemin).readAsStringSync(encoding: utf8))
          as Map<String, Object?>;

  group('exporter', () {
    test('écrit les deux fichiers datés dans le dossier exports', () async {
      await remplir();
      final resultat = await service.exporter();
      final attendu = chemins.join(
        dossier.path,
        'exports',
        'bibliotheque_perso-export-2026-11-16_1430',
      );
      expect(resultat.cheminJson, '$attendu.json');
      expect(resultat.cheminMarkdown, '$attendu.md');
      expect(File(resultat.cheminJson).existsSync(), isTrue);
      expect(File(resultat.cheminMarkdown).existsSync(), isTrue);
      expect(resultat.nombreTitres, 2);
      expect(resultat.nombreSites, 2);
      // Aucun fichier partiel ne reste.
      final restes = Directory(chemins.join(dossier.path, 'exports'))
          .listSync()
          .where((entite) => entite.path.endsWith('.part'));
      expect(restes, isEmpty);
    });

    test('deux exports dans la même minute ne s\'écrasent pas', () async {
      final premier = await service.exporter();
      final second = await service.exporter();
      expect(second.cheminJson, isNot(premier.cheminJson));
      expect(second.cheminJson, endsWith('_1430_2.json'));
      expect(second.cheminMarkdown, endsWith('_1430_2.md'));
    });

    test('un double appel simultané partage le même export', () async {
      final a = service.exporter();
      final b = service.exporter();
      expect(identical(a, b), isTrue);
      await a;
      final fichiers = Directory(chemins.join(dossier.path, 'exports'))
          .listSync();
      expect(fichiers, hasLength(2));
    });

    test('la date donnée fixe le nom des fichiers', () async {
      final resultat = await service.exporter(date: DateTime(2027, 1, 2, 3, 4));
      expect(
        chemins.basename(resultat.cheminJson),
        'bibliotheque_perso-export-2027-01-02_0304.json',
      );
    });

    test("un dossier impossible à créer lève une ErreurService", () async {
      // Un fichier occupe la place du dossier « exports ».
      File(chemins.join(dossier.path, 'exports')).writeAsStringSync('x');
      await expectLater(service.exporter(), throwsA(isA<ErreurService>()));
    });
  });

  group('listerExportsJson', () {
    test('dossier absent : liste vide, sans erreur', () async {
      expect(await service.listerExportsJson(), isEmpty);
    });

    test('ne garde que les .json, le plus récent d\'abord', () async {
      final exports = Directory(
        ServiceExport.cheminDossierExports(dossier.path),
      )..createSync(recursive: true);
      File creer(String nom, DateTime date) =>
          File(chemins.join(exports.path, nom))
            ..writeAsStringSync('{}')
            ..setLastModifiedSync(date);
      final ancien = creer('ancien.json', DateTime(2026, 1, 1));
      final recent = creer('recent.JSON', DateTime(2026, 11, 1));
      final moyen = creer('moyen.json', DateTime(2026, 6, 1));
      creer('notes.md', DateTime(2026, 12, 1));
      creer('export.json.part', DateTime(2026, 12, 1));
      Directory(chemins.join(exports.path, 'dossier.json')).createSync();

      expect(await service.listerExportsJson(), <String>[
        recent.path,
        moyen.path,
        ancien.path,
      ]);
    });
  });

  group('contenu JSON', () {
    test('contient la version de format, les réglages et les listes', () async {
      await remplir();
      final json = lireJson((await service.exporter()).cheminJson);
      expect(json['format'], 'bibliotheque_perso-export');
      // Format 3 : regroupements de catégories (après le format 2 :
      // sélecteurs CSS des sites et résumé des titres).
      expect(json['version'], 3);
      expect(json['dateExport'], dateExport.toUtc().toIso8601String());
      expect(json['versionApplication'], '0.1.0');
      final reglages = json['reglages']! as Map<String, Object?>;
      expect(reglages['langues'], <String>['fr', 'ja']);
      final listes = (json['listes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(listes.map((l) => l['nom']), <String>[
        nomListeFavoris,
        nomListeSuivis,
        nomListePlanifie,
        nomListeEnAttente,
        'À relire [été]',
      ]);
      expect(listes.first['systeme'], isTrue);
      expect(listes.last['systeme'], isFalse);
      expect(listes.first['ordre'], ordreListeFavoris);
    });

    test('décrit chaque site', () async {
      await remplir();
      final json = lireJson((await service.exporter()).cheminJson);
      final sources = (json['sources']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(sources, hasLength(2));
      final mangaDex = sources.firstWhere((s) => s['nom'] == 'MangaDex');
      expect(mangaDex, <String, Object?>{
        'nom': 'MangaDex',
        'urlBase': 'https://mangadex.org',
        'type': 'mangaDex',
        'langues': <String>['fr', 'en'],
        'active': true,
        'configurationSelecteurs': null,
      });
      final autre = sources.firstWhere((s) => s['nom'] == "L'Étagère");
      expect(autre['active'], isFalse);
      expect(autre['langues'], isEmpty);
    });

    test('décrit chaque titre avec tous ses champs', () async {
      await remplir();
      final json = lireJson((await service.exporter()).cheminJson);
      final titres = (json['titres']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(titres, hasLength(2));
      final premier = titres.firstWhere((t) => t['url'] == urlTitreReference);
      expect(premier['nom'], "Death's Daughter — l'épée d'ébène");
      expect(premier['titresAlternatifs'], <Object?>[
        <String, Object?>{'nom': '死神に育てられた少女', 'langue': 'ja'},
      ]);
      expect(premier['type'], 'manga');
      expect(premier['source'], 'MangaDex');
      expect(premier['urlSource'], 'https://mangadex.org');
      expect(premier['listes'], <String>[nomListeFavoris, 'À relire [été]']);
      expect(premier['categories'], containsAll(<String>['action', 'comédie']));
      expect(premier['langues'], <String>['fr', 'en']);
      expect(premier['niveauContenu'], niveauContenuSuggestif);
      expect(
        premier['urlCouverture'],
        'https://uploads.mangadex.org/covers/exemple.jpg',
      );
      expect(premier['auteur'], 'Exemple');
      expect(premier['statut'], 'En cours');
      expect(premier['nombreChapitres'], 4);
      final dernier = premier['dernierChapitreLu']! as Map<String, Object?>;
      expect(dernier['numero'], 12.5);
      expect(dernier['langue'], 'fr');
      expect(dernier['datePublication'], '2026-01-12T00:00:00.000Z');

      final second = titres.firstWhere((t) => t['nom'] == 'Un *livre*');
      expect(second['listes'], isEmpty);
      expect(second['dernierChapitreLu'], isNull);
      expect(second['nombreChapitres'], 0);
      expect(second['langues'], isEmpty);
      expect(second['couvertureChoisie'], isNull);
    });

    test('liste tous les sites de chaque titre, le principal en tête '
        '(étape 8)', () async {
      await remplir();
      final premierTitre = (await depotTitres.chargerTitreParUrl(
        urlTitreReference,
      ))!;
      final etagere = (await depotSources.chargerSourceParUrl(
        'https://etagere.example',
      ))!;
      await DepotTitresSources(base).ajouterSourceSecondaire(
        premierTitre.id!,
        etagere.id!,
        'https://etagere.example/manga/death',
      );
      // Tâche T4 : un site enregistré comme simple lien.
      final protege = await depotSources.enregistrerSource(
        const Source(
          nom: 'Protégé',
          urlBase: 'https://protege.example',
          typeSource: TypeSource.generique,
        ),
      );
      await DepotTitresSources(base).ajouterSourceSecondaire(
        premierTitre.id!,
        protege.id!,
        'https://protege.example/oeuvre/death',
        lienSeul: true,
      );

      final resultat = await service.exporter();
      final titres = (lireJson(resultat.cheminJson)['titres']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final premier = titres.firstWhere((t) => t['url'] == urlTitreReference);
      expect(premier['sites'], <Object?>[
        <String, Object?>{
          'url': urlTitreReference,
          'source': 'MangaDex',
          'urlSource': 'https://mangadex.org',
          'principal': true,
          'lienSeul': false,
        },
        <String, Object?>{
          'url': 'https://etagere.example/manga/death',
          'source': "L'Étagère",
          'urlSource': 'https://etagere.example',
          'principal': false,
          'lienSeul': false,
        },
        <String, Object?>{
          'url': 'https://protege.example/oeuvre/death',
          'source': 'Protégé',
          'urlSource': 'https://protege.example',
          'principal': false,
          'lienSeul': true,
        },
      ]);
      final second = titres.firstWhere((t) => t['nom'] == 'Un *livre*');
      expect(second['sites'], hasLength(1));

      final markdown = File(resultat.cheminMarkdown)
          .readAsStringSync(encoding: utf8);
      expect(
        markdown,
        contains(
          "autres sites : [L'Étagère](https://etagere.example/manga/death), "
          '[Protégé](https://protege.example/oeuvre/death) (lien seul)',
        ),
      );
    });

    test('est encodé en UTF-8 avec accents et apostrophes lisibles', () async {
      await remplir();
      final chemin = (await service.exporter()).cheminJson;
      final octets = File(chemin).readAsBytesSync();
      // Pas de BOM, et le texte se décode en UTF-8 strict.
      expect(octets.take(3), isNot(<int>[0xEF, 0xBB, 0xBF]));
      final texte = utf8.decode(octets);
      // Accents et apostrophes écrits tels quels, sans échappement \u.
      expect(texte, contains("Death's Daughter — l'épée d'ébène"));
      expect(texte, contains("L'Étagère"));
      expect(texte, contains('死神に育てられた少女'));
      expect(texte, isNot(contains(r'\u')));
    });

    test("ne contient aucun chemin de l'appareil", () async {
      await remplir();
      final resultat = await service.exporter();
      final json = lireJson(resultat.cheminJson);
      final premier = (json['titres']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((t) => t['url'] == urlTitreReference);
      expect(premier['couvertureChoisie'], 'ma couverture.png');
      for (final chemin in <String>[
        resultat.cheminJson,
        resultat.cheminMarkdown,
      ]) {
        final texte = File(chemin).readAsStringSync();
        expect(texte, isNot(contains('bapti')));
        expect(texte, isNot(contains('Users')));
        expect(texte, isNot(contains(dossier.path)));
      }
    });

    test('base vide : listes système seules, aucun titre ni site', () async {
      final resultat = await service.exporter();
      expect(resultat.nombreTitres, 0);
      expect(resultat.nombreSites, 0);
      final json = lireJson(resultat.cheminJson);
      expect(json['titres'], isEmpty);
      expect(json['sources'], isEmpty);
      expect(json['listes'], hasLength(4));
      expect(
        (json['reglages']! as Map<String, Object?>)['langues'],
        ServiceParametres.languesParDefaut,
      );
      final markdown = File(resultat.cheminMarkdown).readAsStringSync();
      expect(markdown, contains('0 titre, 0 site'));
      expect(markdown, contains('## Favoris'));
      expect(markdown, contains('_Aucun titre._'));
      expect(markdown, contains('_Aucun site configuré._'));
      expect(markdown, isNot(contains('## Sans liste')));
    });
  });

  group('contenu Markdown', () {
    test(
      'une section par liste, dans l\'ordre, puis Sans liste et Sites',
      () async {
        await remplir();
        final markdown = File((await service.exporter()).cheminMarkdown)
            .readAsStringSync(encoding: utf8);
        final sections = RegExp(
          r'^## (.+)$',
          multiLine: true,
        ).allMatches(markdown).map((m) => m[1]).toList();
        expect(sections, <String>[
          'Favoris',
          'Suivis',
          'Planifié',
          'En attente',
          r'À relire \[été\]',
          'Sans liste',
          'Sites',
        ]);
        expect(markdown, startsWith('# Bibliothèque perso — export'));
        expect(
          markdown,
          contains('Export du 16/11/2026 à 14:30 : 2 titres, 2 sites.'),
        );
      },
    );

    test(
      'chaque titre est un lien avec son site, ses catégories et sa lecture',
      () async {
        await remplir();
        final markdown = File((await service.exporter()).cheminMarkdown)
            .readAsStringSync(encoding: utf8);
        final ligne = markdown
            .split('\n')
            .firstWhere((l) => l.contains(urlTitreReference));
        expect(
          ligne,
          startsWith(
            "- [Death's Daughter — l'épée d'ébène]($urlTitreReference) — "
            'MangaDex · catégories : ',
          ),
        );
        expect(ligne, contains('action'));
        expect(ligne, contains('comédie'));
        expect(ligne, endsWith('dernier chapitre lu : 12.5 (fr)'));
        // Le titre est listé dans ses deux listes.
        expect(
          RegExp(RegExp.escape(urlTitreReference)).allMatches(markdown),
          hasLength(2),
        );
      },
    );

    test('échappe la mise en forme et protège les adresses', () async {
      await remplir();
      final markdown = File((await service.exporter()).cheminMarkdown)
          .readAsStringSync(encoding: utf8);
      expect(
        markdown,
        contains(
          r'- [Un \*livre\*](https://etagere.example/livre/un%20%28tome%201%29)'
          " — L'Étagère · aucun chapitre lu",
        ),
      );
      expect(
        markdown,
        contains("- [L'Étagère](https://etagere.example) — madara · désactivé"),
      );
      expect(
        markdown,
        contains(
          '- [MangaDex](https://mangadex.org) — mangaDex · langues : fr, en',
        ),
      );
    });
  });

  group('fonctions pures', () {
    test('couvertureExportee garde les adresses et réduit les chemins', () {
      expect(ServiceExport.couvertureExportee(null), isNull);
      expect(ServiceExport.couvertureExportee('  '), isNull);
      expect(
        ServiceExport.couvertureExportee('https://site.example/c.jpg'),
        'https://site.example/c.jpg',
      );
      expect(
        ServiceExport.couvertureExportee(r'C:\Users\moi\Images\c.png'),
        'c.png',
      );
      expect(
        ServiceExport.couvertureExportee('/home/moi/images/c.webp'),
        'c.webp',
      );
      expect(
        ServiceExport.couvertureExportee('file:///C:/Users/moi/c.jpg'),
        'c.jpg',
      );
    });

    test('dernierChapitreLu prend le plus grand numéro lu', () {
      Chapitre chapitre(double numero, {bool lu = true, DateTime? date}) =>
          Chapitre(
            urlChapitre: 'u$numero$date',
            nom: 'c',
            numero: numero,
            estLu: lu,
            datePublication: date,
          );
      expect(ServiceExport.dernierChapitreLu(<Chapitre>[]), isNull);
      expect(
        ServiceExport.dernierChapitreLu(<Chapitre>[chapitre(3, lu: false)]),
        isNull,
      );
      expect(
        ServiceExport.dernierChapitreLu(<Chapitre>[
          chapitre(2),
          chapitre(10, lu: false),
          chapitre(5),
        ])!.numero,
        5,
      );
      final recent = chapitre(5, date: DateTime.utc(2026, 2));
      expect(
        ServiceExport.dernierChapitreLu(<Chapitre>[
          chapitre(5, date: DateTime.utc(2026)),
          recent,
        ]),
        same(recent),
      );
    });

    test('horodatageFichier complète les zéros', () {
      expect(
        ServiceExport.horodatageFichier(DateTime(2026, 3, 4, 5, 6)),
        '2026-03-04_0506',
      );
    });
  });
}
