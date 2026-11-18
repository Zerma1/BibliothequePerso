// Tests des chapitres marqués lus en lot (tâche X10) : base en mémoire, aucun
// appel réseau (le client simulé répond 404 à tout).
import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

void main() {
  late Database base;
  late ServiceBibliotheque service;
  late DepotTitres depotTitres;
  late DepotChapitres depotChapitres;
  late int idSource;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    final client = creerClientTest(
      (http.Request requete) async => http.Response('', 404),
      HorlogeFactice(),
    );
    final depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    service = ServiceBibliotheque(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotChapitres: depotChapitres,
      depotListes: DepotListes(base),
      depotCategories: DepotCategories(base),
      fabriqueSources: FabriqueSources(client),
      serviceAjoutSite: ServiceAjoutSite(
        depotSources,
        DetecteurTypeSite(client),
      ),
      client: client,
    );
    idSource = (await depotSources.enregistrerSource(
      const Source(
        nom: 'a.test',
        urlBase: 'https://a.test',
        typeSource: TypeSource.mangaDex,
      ),
    )).id!;
  });

  tearDown(() => base.close());

  /// Crée un titre et ses chapitres [numeros] (en français), et renvoie
  /// l'identifiant du titre.
  Future<int> creerTitre(String nom, List<double> numeros) async {
    final titre = await depotTitres.enregistrerTitre(
      Titre(idSource: idSource, urlTitre: 'https://a.test/$nom', nom: nom),
    );
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (final numero in numeros)
        Chapitre(
          idTitre: titre.id,
          urlChapitre: 'https://a.test/$nom/$numero',
          nom: 'Chapitre $numero',
          numero: numero,
          langue: 'fr',
        ),
    ]);
    return titre.id!;
  }

  Future<Map<double, bool>> etatsLecture(int idTitre) async => <double, bool>{
    for (final chapitre in await depotChapitres.chargerChapitres(idTitre))
      chapitre.numero: chapitre.estLu,
  };

  Future<List<int>> idsDe(int idTitre, Iterable<double> numeros) async => <int>[
    for (final chapitre in await depotChapitres.chargerChapitres(idTitre))
      if (numeros.contains(chapitre.numero)) chapitre.id!,
  ];

  group('marquerChapitresLus', () {
    test('marque les chapitres choisis et renvoie le nombre modifié', () async {
      final idTitre = await creerTitre('un', <double>[1, 2, 3, 4]);

      final nombre = await service.marquerChapitresLus(
        idTitre,
        await idsDe(idTitre, <double>[1, 3]),
      );

      expect(nombre, 2);
      expect(await etatsLecture(idTitre), <double, bool>{
        1: true,
        2: false,
        3: true,
        4: false,
      });
    });

    test('ne compte pas les chapitres déjà dans cet état', () async {
      final idTitre = await creerTitre('un', <double>[1, 2, 3]);
      await service.marquerChapitresLus(
        idTitre,
        await idsDe(idTitre, <double>[1]),
      );

      final nombre = await service.marquerChapitresLus(
        idTitre,
        await idsDe(idTitre, <double>[1, 2]),
      );

      expect(nombre, 1);
    });

    test('remet des chapitres en non lus', () async {
      final idTitre = await creerTitre('un', <double>[1, 2]);
      await service.marquerTousLus(idTitre);

      final nombre = await service.marquerChapitresLus(
        idTitre,
        await idsDe(idTitre, <double>[2]),
        lu: false,
      );

      expect(nombre, 1);
      expect(await etatsLecture(idTitre), <double, bool>{1: true, 2: false});
    });

    test("ignore les chapitres d'un autre titre", () async {
      final idTitre = await creerTitre('un', <double>[1]);
      final idAutre = await creerTitre('autre', <double>[1, 2]);

      final nombre = await service.marquerChapitresLus(idTitre, <int>[
        ...await idsDe(idTitre, <double>[1]),
        ...await idsDe(idAutre, <double>[1, 2]),
      ]);

      expect(nombre, 1);
      expect(await etatsLecture(idAutre), <double, bool>{1: false, 2: false});
    });

    test('une sélection vide ne modifie rien', () async {
      final idTitre = await creerTitre('un', <double>[1]);

      expect(await service.marquerChapitresLus(idTitre, <int>[]), 0);
    });
  });

  group('marquerLusJusqua', () {
    test("marque lus les chapitres jusqu'au numéro donné compris", () async {
      final idTitre = await creerTitre('un', <double>[1, 2, 2.5, 3, 4]);

      final nombre = await service.marquerLusJusqua(idTitre, 3);

      expect(nombre, 4);
      expect(await etatsLecture(idTitre), <double, bool>{
        1: true,
        2: true,
        2.5: true,
        3: true,
        4: false,
      });
    });

    test("remet en non lus jusqu'au numéro sans toucher la suite", () async {
      final idTitre = await creerTitre('un', <double>[1, 2, 3]);
      await service.marquerTousLus(idTitre);

      final nombre = await service.marquerLusJusqua(idTitre, 2, lu: false);

      expect(nombre, 2);
      expect(await etatsLecture(idTitre), <double, bool>{
        1: false,
        2: false,
        3: true,
      });
    });

    test("ne touche pas les chapitres d'un autre titre", () async {
      final idTitre = await creerTitre('un', <double>[1]);
      final idAutre = await creerTitre('autre', <double>[1]);

      await service.marquerLusJusqua(idTitre, 10);

      expect(await etatsLecture(idAutre), <double, bool>{1: false});
    });

    test("refuse un numéro qui n'est pas un nombre fini", () async {
      final idTitre = await creerTitre('un', <double>[1]);

      await expectLater(
        service.marquerLusJusqua(idTitre, double.nan),
        throwsA(isA<ErreurService>()),
      );
      expect(await etatsLecture(idTitre), <double, bool>{1: false});
    });
  });
}
