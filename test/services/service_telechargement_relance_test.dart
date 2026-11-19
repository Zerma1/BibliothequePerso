// File de téléchargement : une demande de traitement arrivée pendant la fin
// d'un traitement (file vue vide, verrou en cours de libération) n'est pas
// perdue. Base en mémoire, dossier temporaire ; le chapitre mis en file est
// externe, la file le retire donc sans aucune requête.
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Paramètres dont la libération du verrou de la file lance [avantLiberation]
/// (une fois) : c'est la toute fin d'un traitement.
class _ParametresAvecCrochet extends ServiceParametres {
  _ParametresAvecCrochet(super.depot);

  Future<void> Function()? avantLiberation;
  int liberations = 0;

  @override
  Future<void> supprimerVerrouTelechargement() async {
    liberations++;
    final action = avantLiberation;
    avantLiberation = null;
    if (action != null) await action();
    return super.supprimerVerrouTelechargement();
  }
}

void main() {
  late Database base;
  late Directory dossier;
  late DepotChapitres depotChapitres;
  late DepotTelechargements depotTelechargements;
  late _ParametresAvecCrochet parametres;
  late ServiceTelechargement service;
  late int requetes;
  late Chapitre externe;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('relance_file_test');
    requetes = 0;
    final client = creerClientTest((requete) async {
      requetes++;
      return http.Response('introuvable', 404);
    }, HorlogeFactice());
    final depotSources = DepotSources(base);
    final depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    depotTelechargements = DepotTelechargements(base);
    final depotParametres = DepotParametres(base);
    parametres = _ParametresAvecCrochet(depotParametres);
    service = ServiceTelechargement(
      depotTelechargements: depotTelechargements,
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotListes: DepotListes(base),
      depotSources: depotSources,
      stockage: StockageTelechargements(dossier.path),
      fabriqueSources: FabriqueSources(client),
      client: client,
      serviceParametres: parametres,
      depotParametres: depotParametres,
    );

    final source = await depotSources.enregistrerSource(
      const Source(
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
        langueParDefaut: 'fr',
      ),
    );
    final titre = await depotTitres.enregistrerTitre(
      Titre(
        idSource: source.id,
        urlTitre: 'https://mangadex.org/title/abc',
        nom: 'Titre',
      ),
    );
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      Chapitre(
        idTitre: titre.id,
        urlChapitre: 'https://mangadex.org/chapter/externe',
        nom: 'Chapitre 1',
        numero: 1,
        langue: 'fr',
        urlExterne: 'https://editeur.example/lire/1',
      ),
    ]);
    externe = (await depotChapitres.chargerChapitres(titre.id!)).single;
  });

  tearDown(() async {
    await service.fermer();
    await base.close();
    await dossier.delete(recursive: true);
  });

  test(
    'un chapitre mis en file pendant la fin du traitement est traité dans la '
    'foulée',
    () async {
      parametres.avantLiberation = () async {
        // File déjà vue vide : sans relance, ce chapitre attendrait la
        // prochaine action du client.
        await depotTelechargements.ajouterEnFile(externe.id!);
        final partage = service.lancerTraitement();
        expect(partage, isNotNull);
      };

      await service.lancerTraitement();

      // Second passage fait dans le même traitement : la ligne du chapitre
      // externe a été retirée sans requête.
      expect(
        await depotTelechargements.chargerParChapitre(externe.id!),
        isNull,
      );
      expect(parametres.liberations, 2);
      expect(service.estEnCours, isFalse);
      expect(requetes, 0);
    },
  );

  test('sans nouvelle demande, un seul passage est fait', () async {
    await depotTelechargements.ajouterEnFile(externe.id!);

    await service.lancerTraitement();

    expect(await depotTelechargements.chargerParChapitre(externe.id!), isNull);
    expect(parametres.liberations, 1);
    expect(service.estEnCours, isFalse);
  });
}
