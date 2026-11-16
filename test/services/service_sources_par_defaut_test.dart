// Sources par défaut (R9) : ajout au démarrage sans réseau, sans toucher aux
// sources du client ni recréer une source supprimée (base en mémoire).
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_sources_par_defaut.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotSources depotSources;
  late ServiceParametres parametres;
  late ServiceSourcesParDefaut service;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depotSources = DepotSources(base);
    parametres = ServiceParametres(DepotParametres(base));
    service = ServiceSourcesParDefaut(
      depotSources: depotSources,
      serviceParametres: parametres,
    );
  });

  tearDown(() => base.close());

  Future<Source?> parUrl(String url) => depotSources.chargerSourceParUrl(url);

  test('au premier lancement, MangaDex et Scan-Manga sont ajoutés', () async {
    final resultat = await service.assurerSourcesParDefaut();

    expect(resultat.erreurs, isEmpty);
    expect(resultat.ajoutees, hasLength(2));
    final mangaDex = await parUrl(urlBaseMangaDex);
    expect(mangaDex?.nom, nomMangaDex);
    expect(mangaDex?.typeSource, TypeSource.mangaDex);
    final scanManga = await parUrl(urlBaseScanManga);
    expect(scanManga?.nom, nomScanManga);
    expect(scanManga?.typeSource, TypeSource.scanManga);
    expect(scanManga?.langueParDefaut, 'fr');
    expect(await parametres.chargerSourcesParDefautProposees(), <String>{
      'mangadex',
      'scan-manga',
    });
  });

  test('un second appel ne crée aucun doublon', () async {
    await service.assurerSourcesParDefaut();
    final resultat = await service.assurerSourcesParDefaut();

    expect(resultat.ajoutees, isEmpty);
    expect(resultat.erreurs, isEmpty);
    expect(await depotSources.chargerSources(), hasLength(2));
  });

  test(
    'une source existante avec ou sans www est laissée telle quelle',
    () async {
      // Le client a configuré MangaDex avec www, un autre nom, ses langues
      // et l'a désactivé ; Scan-Manga sans www.
      final mangaDexClient = await depotSources.enregistrerSource(
        const Source(
          nom: 'Mon MangaDex',
          urlBase: 'https://www.mangadex.org',
          typeSource: TypeSource.mangaDex,
          langueParDefaut: 'en',
          estActive: false,
        ),
      );
      final scanMangaClient = await depotSources.enregistrerSource(
        const Source(
          nom: 'SM',
          urlBase: 'https://scan-manga.com',
          typeSource: TypeSource.generique,
          langueParDefaut: 'fr,en',
        ),
      );

      final resultat = await service.assurerSourcesParDefaut();

      expect(resultat.ajoutees, isEmpty);
      expect(resultat.erreurs, isEmpty);
      expect(await depotSources.chargerSources(), hasLength(2));
      expect(
        await depotSources.chargerSource(mangaDexClient.id!),
        mangaDexClient,
      );
      expect(
        await depotSources.chargerSource(scanMangaClient.id!),
        scanMangaClient,
      );
      // Marquées comme proposées : une suppression ultérieure sera respectée.
      expect(await parametres.chargerSourcesParDefautProposees(), <String>{
        'mangadex',
        'scan-manga',
      });
    },
  );

  test(
    "une source par défaut supprimée par le client n'est pas recréée",
    () async {
      await service.assurerSourcesParDefaut();
      final mangaDex = await parUrl(urlBaseMangaDex);
      await depotSources.supprimerSource(mangaDex!.id!);

      final resultat = await service.assurerSourcesParDefaut();

      expect(resultat.ajoutees, isEmpty);
      expect(await parUrl(urlBaseMangaDex), isNull);
      expect(await parUrl(urlBaseScanManga), isNotNull);
    },
  );

  test(
    'une nouvelle source par défaut est ajoutée aux anciens lancements',
    () async {
      // Un ancien lancement n'avait proposé que MangaDex.
      await parametres.enregistrerSourcesParDefautProposees(<String>[
        'mangadex',
      ]);

      final resultat = await service.assurerSourcesParDefaut();

      expect(resultat.ajoutees.map((s) => s.urlBase), <String>[
        urlBaseScanManga,
      ]);
      expect(await parUrl(urlBaseMangaDex), isNull);
    },
  );

  test(
    "une erreur de base est rendue dans le résultat sans être levée",
    () async {
      await base.close();

      final resultat = await service.assurerSourcesParDefaut();

      expect(resultat.ajoutees, isEmpty);
      expect(resultat.erreurs, isNotEmpty);
      // Rouverte pour le tearDown.
      base = await ouvrirBaseDeTest();
    },
  );

  group('plan pur', () {
    test(
      "ignore les sources aux URL illisibles et compare l'hôte sans www",
      () {
        final plan = PlanSourcesParDefaut.calculer(
          defauts: sourcesParDefaut,
          existantes: const <Source>[
            Source(
              nom: 'x',
              urlBase: 'pas une url',
              typeSource: TypeSource.generique,
            ),
            Source(
              nom: 'y',
              urlBase: 'http://WWW.Scan-Manga.com',
              typeSource: TypeSource.generique,
            ),
          ],
          dejaProposees: const <String>{},
        );

        expect(plan.aAjouter.map((d) => d.identifiant), <String>['mangadex']);
        expect(plan.dejaPresentes.map((d) => d.identifiant), <String>[
          'scan-manga',
        ]);
      },
    );
  });
}
