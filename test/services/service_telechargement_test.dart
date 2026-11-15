// Tests de bout en bout du téléchargement : base en mémoire, archives dans un
// dossier temporaire, réponses MangaDex enregistrées (aucun appel réseau).
import 'dart:convert';
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
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

const String _uuidChapitre = 'ef4aae9e-eea8-4931-8435-9f907870f4d8';

void main() {
  late Database base;
  late Directory dossier;
  late DepotChapitres depotChapitres;
  late DepotListes depotListes;
  late DepotTelechargements depotTelechargements;
  late ServiceParametres parametres;
  late ServiceTelechargement service;
  late List<http.Request> requetes;
  late int nombre403Restants;
  late int nombreImages;
  late Titre titre;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('telechargements_test');
    requetes = <http.Request>[];
    nombre403Restants = 0;
    final atHome = lireExemple('exemples_json/at_home_serveur.json');
    nombreImages =
        (((jsonDecode(atHome) as Map<String, Object?>)['chapter']!
                    as Map<String, Object?>)['data']!
                as List<Object?>)
            .length;
    final client = creerClientTest((http.Request requete) async {
      requetes.add(requete);
      final url = requete.url;
      if (url.host == 'api.mangadex.network') {
        return http.Response('', 200);
      }
      if (url.path.startsWith('/at-home/server/')) {
        return reponseJson(atHome);
      }
      if (url.host.endsWith('.mangadex.network')) {
        if (nombre403Restants > 0) {
          nombre403Restants--;
          return http.Response('expiré', 403);
        }
        return http.Response.bytes(<int>[1, 2, 3, 4], 200);
      }
      return http.Response('introuvable', 404);
    }, HorlogeFactice());

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
    );

    final source = await depotSources.enregistrerSource(
      const Source(
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
        langueParDefaut: 'fr,en',
      ),
    );
    titre = await depotTitres.enregistrerTitre(
      Titre(
        idSource: source.id,
        urlTitre: urlTitreReference,
        nom: 'Shinigami ni Sodaterareta',
      ),
    );
    // 30 chapitres : tous pointent vers le même chapitre MangaDex réel
    // enregistré (seul le numéro change).
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (var n = 1; n <= 30; n++)
        Chapitre(
          idTitre: titre.id,
          urlChapitre: 'https://mangadex.org/chapter/$_uuidChapitre?n=$n',
          nom: 'Chapitre $n',
          numero: n.toDouble(),
          langue: 'fr',
        ),
    ]);
  });

  tearDown(() async {
    await service.fermer();
    await base.close();
    await dossier.delete(recursive: true);
  });

  Future<Chapitre> chapitre(int numero) async {
    final chapitres = await depotChapitres.chargerChapitres(titre.id!);
    return chapitres.firstWhere((c) => c.numero == numero);
  }

  Future<int> idListe(String nom) async =>
      (await depotListes.chargerListeParNom(nom))!.id!;

  test(
    'télécharge un chapitre, le lit dans l\'archive et le signale',
    () async {
      final premier = await chapitre(1);
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();

      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.termine);
      expect(ligne.nombrePagesFaites, nombreImages);
      expect((await chapitre(1)).estTelecharge, isTrue);

      expect(await service.compterPages(premier.id!), nombreImages);
      expect(await service.lirePage(premier.id!, 0), <int>[1, 2, 3, 4]);

      final signalements = requetes
          .where((r) => r.url.host == 'api.mangadex.network')
          .toList();
      expect(signalements, hasLength(nombreImages));
      final corps = jsonDecode(signalements.first.body) as Map<String, Object?>;
      expect(corps['success'], isTrue);
      expect(corps['bytes'], 4);
    },
  );

  test('renouvelle l\'adresse des images après un 403 (expiration)', () async {
    nombre403Restants = 1;
    final premier = await chapitre(1);
    await service.telechargerChapitre(premier.id!);
    await service.lancerTraitement();

    final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
    expect(ligne!.statut, StatutTelechargement.termine);
    final appelsAtHome = requetes
        .where((r) => r.url.path.startsWith('/at-home/server/'))
        .length;
    expect(appelsAtHome, 2);
    final echecsSignales = requetes
        .where((r) => r.url.host == 'api.mangadex.network')
        .map((r) => jsonDecode(r.body) as Map<String, Object?>)
        .where((corps) => corps['success'] == false);
    expect(echecsSignales, hasLength(1));
  });

  test('un échec répété met le téléchargement en échec sans archive', () async {
    nombre403Restants = 99;
    final premier = await chapitre(1);
    await service.telechargerChapitre(premier.id!);
    await service.lancerTraitement();

    final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
    expect(ligne!.statut, StatutTelechargement.echec);
    expect(ligne.messageErreur, isNotEmpty);
    expect((await chapitre(1)).estTelecharge, isFalse);
    final archives = dossier
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.zip'));
    expect(archives, isEmpty);
  });

  group('règles de conservation', () {
    test('un titre suivi télécharge les 10 premiers chapitres', () async {
      await depotListes.ajouterTitre(await idListe(nomListeSuivis), titre.id!);
      await service.appliquerRegles(titre.id!);
      await service.lancerTraitement();

      final chapitres = await depotChapitres.chargerChapitres(titre.id!);
      final telecharges =
          chapitres
              .where((c) => c.estTelecharge)
              .map((c) => c.numero.toInt())
              .toList()
            ..sort();
      expect(telecharges, <int>[for (var n = 1; n <= 10; n++) n]);
    });

    test('la vague avance avec la lecture et supprime les anciens', () async {
      await parametres.enregistrerReglagesTelechargement(
        const ReglagesTelechargement(
          suivisInitial: 4,
          suivisAvant: 2,
          suivisApres: 2,
        ),
      );
      await depotListes.ajouterTitre(await idListe(nomListeSuivis), titre.id!);
      await service.appliquerRegles(titre.id!);
      await service.lancerTraitement();

      for (var n = 1; n <= 4; n++) {
        await depotChapitres.marquerLu((await chapitre(n)).id!);
      }
      await service.appliquerRegles(titre.id!);
      await service.lancerTraitement();

      final chapitres = await depotChapitres.chargerChapitres(titre.id!);
      final telecharges =
          chapitres
              .where((c) => c.estTelecharge)
              .map((c) => c.numero.toInt())
              .toList()
            ..sort();
      // Dernier lu = 4 : on garde 3 et 4, on télécharge 5 et 6.
      expect(telecharges, <int>[3, 4, 5, 6]);
      final archives = dossier
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'));
      expect(archives, hasLength(4));
    });

    test('un titre ni favori ni suivi n\'est pas téléchargé', () async {
      await service.appliquerReglesATous();
      await service.lancerTraitement();
      expect(await depotTelechargements.chargerFile(), isEmpty);
    });
  });

  test('reprend au démarrage un téléchargement interrompu', () async {
    final premier = await chapitre(1);
    final ligne = await depotTelechargements.ajouterEnFile(premier.id!);
    await depotTelechargements.enregistrerStatut(
      ligne.id!,
      StatutTelechargement.enCours,
    );
    await service.demarrer();
    await service.lancerTraitement();

    expect(
      (await depotTelechargements.chargerParChapitre(premier.id!))!.statut,
      StatutTelechargement.termine,
    );
  });
}
