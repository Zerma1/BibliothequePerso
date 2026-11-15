// Tests de l'assemblage des services (lib/main.dart) et de la tâche de fond
// Android, sur une base SQLite en mémoire et sans réseau.
import 'dart:io';

import 'package:bibliotheque_perso/main.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
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

  test('construireServices assemble des services utilisables', () async {
    final services = await construireServices(
      chemin: inMemoryDatabasePath,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
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
  });

  test('fermer ferme la base', () async {
    final services = await construireServices(
      chemin: inMemoryDatabasePath,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
    );
    await services.fermer();
    expect(services.base.isOpen, isFalse);
  });

  test('la tâche de fond réussit sur une base valide', () async {
    final reussi = await executerTacheDeFond(
      chemin: inMemoryDatabasePath,
      fabrique: databaseFactoryFfi,
      client: creerClient(),
    );
    expect(reussi, isTrue);
  });

  test(
    "la tâche de fond ne ferme pas la base partagée avec l'application",
    () async {
      // Sur Android, la connexion native est commune au processus : si la tâche
      // de fond fermait la base, l'application ouverte ne pourrait plus lire.
      final dossier = await Directory.systemTemp.createTemp(
        'bibliotheque_test',
      );
      final chemin = chemins.join(dossier.path, 'base.db');
      final services = await construireServices(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
        client: creerClient(),
      );
      addTearDown(() async {
        await services.fermer();
        await dossier.delete(recursive: true);
      });

      final reussi = await executerTacheDeFond(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
        client: creerClient(),
      );

      expect(reussi, isTrue);
      expect(services.base.isOpen, isTrue);
      expect(await services.serviceBibliotheque.chargerListes(), isNotEmpty);
    },
  );

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
    );
    expect(reussi, isFalse);
  });
}
