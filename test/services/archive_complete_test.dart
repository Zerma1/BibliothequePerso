// « Archive complète » (retour X7 de la 0.2.1-test) : règle pure de la
// politique, réglage, et application par le service de téléchargement
// (base en mémoire, dossier temporaire, aucun appel réseau réel).
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/extension_image.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/services/verrou_telechargement.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Chapitre de test (identifiant = numéro × 10 + rang de version).
Chapitre _chapitre(
  int id,
  double numero, {
  String langue = 'fr',
  bool lu = false,
  bool telecharge = false,
  String? urlExterne,
  int? idSource,
}) => Chapitre(
  id: id,
  idTitre: 1,
  urlChapitre: 'https://exemple.test/ch/$id',
  nom: 'Chapitre $numero',
  numero: numero,
  langue: langue,
  estLu: lu,
  estTelecharge: telecharge,
  urlExterne: urlExterne,
  idSource: idSource,
);

void main() {
  group('politique en archive complète', () {
    const politique = PolitiqueTelechargement(
      languesPreferees: <String>['fr', 'en'],
      archiveComplete: true,
      idSourcePrincipale: 1,
      idsSourcesLiees: <int>{1},
    );

    test('veut tous les numéros, même pour un titre ni favori ni suivi', () {
      final chapitres = <Chapitre>[
        for (var n = 1; n <= 40; n++)
          _chapitre(n, n.toDouble(), lu: n <= 30, telecharge: n <= 5),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: false,
        estSuivi: false,
      );
      expect(plan.idsVoulus, hasLength(40));
      expect(plan.idsATelecharger, <int>[for (var n = 6; n <= 40; n++) n]);
      expect(plan.idsASupprimer, isEmpty);
    });

    test(
      "une version par numéro, la langue préférée, jamais d'autre langue",
      () {
        final plan = politique.calculer(
          <Chapitre>[
            _chapitre(11, 1, langue: 'en'),
            _chapitre(12, 1, langue: 'fr'),
            _chapitre(21, 2, langue: 'ru'),
            _chapitre(31, 3, langue: 'ja'),
            _chapitre(32, 3, langue: 'en'),
          ],
          estFavori: true,
          estSuivi: false,
        );
        expect(plan.idsVoulus, <int>{12, 32});
        expect(plan.idsATelecharger, <int>[12, 32]);
      },
    );

    test('jamais les chapitres externes ni ceux d’un site retiré', () {
      final plan = politique.calculer(
        <Chapitre>[
          _chapitre(1, 1, urlExterne: 'https://mangaplus.example/1'),
          _chapitre(2, 2, idSource: 9),
          _chapitre(3, 3, idSource: 1),
        ],
        estFavori: false,
        estSuivi: true,
      );
      expect(plan.idsATelecharger, <int>[3]);
    });

    test(
      'aucune suppression : autre langue, site retiré et lus anciens gardés',
      () {
        final plan = politique.calculer(
          <Chapitre>[
            for (var n = 1; n <= 30; n++)
              _chapitre(n, n.toDouble(), lu: true, telecharge: true),
            _chapitre(100, 31, langue: 'ru', telecharge: true),
            _chapitre(101, 32, idSource: 9, telecharge: true),
          ],
          estFavori: false,
          estSuivi: true,
        );
        expect(plan.idsASupprimer, isEmpty);
        expect(plan.idsATelecharger, isEmpty);
      },
    );

    test('un numéro lu déjà archivé dans une langue choisie n’est pas '
        'retéléchargé dans la préférée', () {
      final plan = politique.calculer(
        <Chapitre>[
          _chapitre(11, 1, langue: 'en', lu: true, telecharge: true),
          _chapitre(12, 1, langue: 'fr'),
        ],
        estFavori: false,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{11});
      expect(plan.idsATelecharger, isEmpty);
    });

    test('désactivée, les règles ordinaires reprennent (rien pour un titre '
        'sans liste)', () {
      const ordinaire = PolitiqueTelechargement(
        languesPreferees: <String>['fr'],
      );
      final plan = ordinaire.calculer(
        <Chapitre>[_chapitre(1, 1)],
        estFavori: false,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, isEmpty);
    });
  });

  group('extension des images', () {
    test('les octets passent avant l’adresse', () {
      final webp = <int>[...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits];
      expect(extensionImage(webp, 'https://exemple.test/page.jpg'), 'webp');
      expect(extensionImage(<int>[0xFF, 0xD8, 0xFF, 0], null), 'jpg');
    });

    test("à défaut, l'extension de l'adresse, puis jpg", () {
      expect(extensionImage(<int>[1, 2, 3], 'https://e.test/a.png?x=1'), 'png');
      expect(extensionImage(<int>[1, 2, 3], 'https://e.test/image'), 'jpg');
      expect(extensionImage(<int>[], null), 'jpg');
    });
  });

  group('réglage', () {
    late Database base;
    late ServiceParametres parametres;
    late DepotParametres depot;

    setUp(() async {
      base = await ouvrirBaseDeTest();
      depot = DepotParametres(base);
      parametres = ServiceParametres(depot);
    });

    tearDown(() => base.close());

    test('désactivée par défaut, puis activée et désactivée', () async {
      expect(await parametres.chargerArchiveComplete(), isFalse);
      await parametres.enregistrerArchiveComplete(true);
      expect(await parametres.chargerArchiveComplete(), isTrue);
      await parametres.enregistrerArchiveComplete(false);
      expect(await parametres.chargerArchiveComplete(), isFalse);
    });

    test('une valeur illisible vaut la valeur par défaut', () async {
      await depot.enregistrerEntier(ServiceParametres.cleArchiveComplete, 7);
      expect(await parametres.chargerArchiveComplete(), isFalse);
    });
  });

  group('service de téléchargement en archive complète', () {
    late Database base;
    late Directory dossier;
    late DepotChapitres depotChapitres;
    late DepotTelechargements depotTelechargements;
    late DepotListes depotListes;
    late ServiceParametres parametres;
    late ServiceTelechargement service;
    late Titre sansListe;
    late Titre suivi;

    setUp(() async {
      base = await ouvrirBaseDeTest();
      dossier = await Directory.systemTemp.createTemp('archive_complete');
      // Aucun site ne répond : seule la mise en file est observée, sans
      // aucun appel réseau réel.
      final client = creerClientTest(
        (http.Request requete) async => http.Response('introuvable', 404),
        HorlogeFactice(),
      );
      final depotSources = DepotSources(base);
      final depotTitres = DepotTitres(base);
      depotChapitres = DepotChapitres(base);
      depotListes = DepotListes(base);
      depotTelechargements = DepotTelechargements(base);
      parametres = ServiceParametres(DepotParametres(base));
      service = ServiceTelechargement(
        depotTelechargements: depotTelechargements,
        depotChapitres: depotChapitres,
        depotTitres: depotTitres,
        depotListes: depotListes,
        depotSources: depotSources,
        stockage: StockageTelechargements(dossier.path),
        fabriqueSources: FabriqueSources(client),
        client: client,
        serviceParametres: parametres,
        identifiantVerrou: 'application',
      );
      final source = await depotSources.enregistrerSource(
        const Source(
          nom: 'Exemple',
          urlBase: 'https://exemple.test',
          typeSource: TypeSource.generique,
        ),
      );
      Future<Titre> titre(String nom) => depotTitres.enregistrerTitre(
        Titre(
          idSource: source.id,
          urlTitre: 'https://exemple.test/$nom',
          nom: nom,
        ),
      );
      sansListe = await titre('sans-liste');
      suivi = await titre('suivi');
      await depotListes.ajouterTitre(
        (await depotListes.chargerListeParNom(nomListeSuivis))!.id!,
        suivi.id!,
      );
      for (final t in <Titre>[sansListe, suivi]) {
        await depotChapitres.enregistrerChapitres(<Chapitre>[
          for (var n = 1; n <= 20; n++)
            Chapitre(
              idTitre: t.id,
              urlChapitre: 'https://exemple.test/${t.nom}/chapitre-$n',
              nom: 'Chapitre $n',
              numero: n.toDouble(),
              langue: 'fr',
            ),
        ]);
      }
    });

    tearDown(() async {
      await service.lancerTraitement();
      await service.fermer();
      await base.close();
      await dossier.delete(recursive: true);
    });

    Future<Set<int>> chapitresEnFile(Titre titre) async {
      final ids = <int>{
        for (final c in await depotChapitres.chargerChapitres(titre.id!)) c.id!,
      };
      return <int>{
        for (final ligne in await depotTelechargements.chargerFile())
          if (ids.contains(ligne.idChapitre)) ligne.idChapitre,
      };
    }

    test('désactivée : seul le titre suivi a des chapitres en file', () async {
      await service.appliquerReglesATous();
      expect(await chapitresEnFile(sansListe), isEmpty);
      expect(await chapitresEnFile(suivi), hasLength(10));
    });

    test(
      'activée : tous les chapitres de tous les titres sont mis en file',
      () async {
        await parametres.enregistrerArchiveComplete(true);
        await service.appliquerReglesATous();
        expect(await chapitresEnFile(sansListe), hasLength(20));
        expect(await chapitresEnFile(suivi), hasLength(20));
      },
    );

    test('activée : une suppression prévue est annulée', () async {
      final chapitre = (await depotChapitres.chargerChapitres(suivi.id!)).last;
      await depotChapitres.enregistrerArchive(chapitre.id!, 'suivi/ch20.zip');
      await depotChapitres.planifierSuppression(
        chapitre.id!,
        DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      await parametres.enregistrerArchiveComplete(true);
      await service.appliquerReglesATous();
      final relu = await depotChapitres.chargerChapitre(chapitre.id!);
      expect(relu!.dateSuppressionPrevue, isNull);
      expect(relu.estTelecharge, isTrue);
    });

    test('juste désactivée : la file perd les téléchargements automatiques '
        'qui ne sont plus voulus', () async {
      // Verrou tenu par la tâche de fond : la file n'est pas traitée, les
      // téléchargements restent « en attente » pendant tout le test.
      await parametres.enregistrerVerrouTelechargement(
        VerrouTelechargement(
          proprietaire: 'tache-de-fond',
          expiration: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      await parametres.enregistrerArchiveComplete(true);
      await service.appliquerReglesATous();
      expect(await chapitresEnFile(sansListe), hasLength(20));
      // Demande manuelle de la session : elle doit rester en file.
      final manuel = (await depotChapitres.chargerChapitres(sansListe.id!))
          .first;
      await service.telechargerChapitre(manuel.id!);

      await parametres.enregistrerArchiveComplete(false);
      await service.appliquerReglesATous();
      expect(await chapitresEnFile(sansListe), <int>{manuel.id!});
      expect(await chapitresEnFile(suivi), hasLength(10));
    });

    test(
      'désactivée : le même chapitre loin de la lecture est à supprimer',
      () async {
        final chapitre = (await depotChapitres.chargerChapitres(suivi.id!))
            .last;
        await depotChapitres.enregistrerArchive(chapitre.id!, 'suivi/ch20.zip');
        await service.appliquerReglesATous();
        final relu = await depotChapitres.chargerChapitre(chapitre.id!);
        expect(relu!.dateSuppressionPrevue, isNotNull);
      },
    );
  });
}
