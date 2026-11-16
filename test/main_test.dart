// Tests de l'assemblage des services (lib/main.dart) et de la tâche de fond
// Android, sur une base SQLite en mémoire, des archives dans un dossier
// temporaire et sans réseau.
import 'dart:io';

import 'package:bibliotheque_perso/main.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/services/planification_mises_a_jour.dart';
import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as chemins;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sources/outils_tests_sources.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  // Client sans réseau : toute requête reçoit une 404 et est comptée.
  late List<Uri> requetes;
  ClientHttpPoli creerClient() {
    requetes = <Uri>[];
    return creerClientTest((http.Request requete) async {
      requetes.add(requete.url);
      return http.Response('', 404);
    }, HorlogeFactice());
  }

  // Dossier des archives hors-ligne : path_provider n'existe pas en test.
  late Directory dossierArchives;
  setUp(() async {
    dossierArchives = await Directory.systemTemp.createTemp('archives_test');
  });
  tearDown(() => dossierArchives.delete(recursive: true));

  test('construireServices assemble des services utilisables', () async {
    final services = await construireServices(
      chemin: inMemoryDatabasePath,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
      dossierTelechargements: dossierArchives.path,
    );
    addTearDown(services.fermer);

    // Les migrations ont créé les listes système.
    final listes = await services.serviceBibliotheque.chargerListes();
    expect(
      listes.map((liste) => liste.nom),
      containsAll(<String>[nomListeFavoris, nomListeSuivis]),
    );
    expect(await services.serviceBibliotheque.chargerSources(), isEmpty);

    // Aucun titre suivi : rapport vide, aucune requête réseau.
    final rapport = await services.serviceMisesAJour.verifierTitresSuivis();
    expect(rapport.resultats, isEmpty);
    expect(requetes, isEmpty);

    // Le service de téléchargement est branché : file vide, démarrage sans
    // erreur ni réseau.
    await services.serviceTelechargement.demarrer();
    await services.serviceTelechargement.lancerTraitement();
    expect(await services.serviceTelechargement.chargerFile(), isEmpty);
    expect(requetes, isEmpty);

    // Les réglages sont lus avec leurs valeurs par défaut.
    final planification = await services.serviceParametres
        .chargerPlanification();
    expect(
      planification.verificationsParJour,
      PlanificationMisesAJour.parDefautParJour,
    );
  });

  test('fermer ferme la base', () async {
    final services = await construireServices(
      chemin: inMemoryDatabasePath,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
      dossierTelechargements: dossierArchives.path,
    );
    await services.fermer();
    expect(services.base.isOpen, isFalse);
  });

  test('la tâche de fond réussit sur une base valide', () async {
    final reussi = await executerTacheDeFond(
      chemin: inMemoryDatabasePath,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
      dossierTelechargements: dossierArchives.path,
    );
    expect(reussi, isTrue);
  });

  test("la tâche de fond ne ferme pas la base partagée avec l'application, "
      "et ne vérifie que si une échéance est passée", () async {
    // Sur Android, la connexion native est commune au processus : si la tâche
    // de fond fermait la base, l'application ouverte ne pourrait plus lire.
    final dossier = await Directory.systemTemp.createTemp('bibliotheque_test');
    final chemin = chemins.join(dossier.path, 'base.db');
    final services = await construireServices(
      chemin: chemin,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
      dossierTelechargements: dossierArchives.path,
    );
    addTearDown(() async {
      await services.fermer();
      await dossier.delete(recursive: true);
    });
    expect(
      await services.serviceParametres.chargerDerniereVerification(),
      isNull,
    );

    // Première exécution : jamais vérifié, donc en retard → vérification.
    final reussi = await executerTacheDeFond(
      chemin: chemin,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
      dossierTelechargements: dossierArchives.path,
    );

    expect(reussi, isTrue);
    expect(services.base.isOpen, isTrue);
    expect(await services.serviceBibliotheque.chargerListes(), isNotEmpty);
    final premiere = await services.serviceParametres
        .chargerDerniereVerification();
    expect(premiere, isNotNull);

    // Seconde exécution juste après : aucune échéance passée depuis, la
    // date de dernière vérification ne change pas.
    await executerTacheDeFond(
      chemin: chemin,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
      dossierTelechargements: dossierArchives.path,
    );
    expect(
      await services.serviceParametres.chargerDerniereVerification(),
      premiere,
    );
  });

  test('la tâche de fond échoue si la base ne s\'ouvre pas', () async {
    // Le « dossier » parent est un fichier : ni sqflite ni SQLite ne
    // peuvent y créer la base, l'ouverture échoue.
    final dossier = await Directory.systemTemp.createTemp('bibliotheque_test');
    addTearDown(() => dossier.delete(recursive: true));
    final fichier = File(chemins.join(dossier.path, 'fichier'));
    await fichier.writeAsString('pas un dossier');
    final cheminImpossible = chemins.join(fichier.path, 'base.db');
    final reussi = await executerTacheDeFond(
      chemin: cheminImpossible,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
      dossierTelechargements: dossierArchives.path,
    );
    expect(reussi, isFalse);
  });

  test(
    'fréquence de la tâche Android : écart entre échéances, 1 h minimum',
    () {
      expect(
        frequenceTacheAndroid(PlanificationMisesAJour(2)),
        const Duration(hours: 12),
      );
      expect(
        frequenceTacheAndroid(PlanificationMisesAJour(24)),
        const Duration(hours: 1),
      );
      expect(
        frequenceTacheAndroid(PlanificationMisesAJour(5)),
        greaterThan(frequenceMinimaleTacheAndroid),
      );
    },
  );
}
