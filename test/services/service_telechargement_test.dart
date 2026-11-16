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
import 'package:bibliotheque_perso/services/verrou_telechargement.dart';
import 'package:bibliotheque_perso/sources/client_http_poli.dart';
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
  late DepotSources depotSources;
  late DepotTitres depotTitres;
  late StockageTelechargements stockage;
  late ClientHttpPoli client;
  // Action lancée une fois, à la première demande d'image (simule ce que
  // fait l'autre isolat pendant un téléchargement).
  Future<void> Function()? avantImage;
  // Serveur d'images renvoyé par /at-home/server (null = celui enregistré,
  // un nœud MangaDex@Home).
  String? baseUrlImages;
  late int nombreImagesDemandees;
  // Avance de l'horloge du service, pour faire passer le délai de 24 h des
  // suppressions prévues sans attendre.
  late Duration decalage;

  setUp(() async {
    decalage = Duration.zero;
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('telechargements_test');
    requetes = <http.Request>[];
    nombre403Restants = 0;
    avantImage = null;
    baseUrlImages = null;
    nombreImagesDemandees = 0;
    final atHome = lireExemple('exemples_json/at_home_serveur.json');
    nombreImages =
        (((jsonDecode(atHome) as Map<String, Object?>)['chapter']!
                    as Map<String, Object?>)['data']!
                as List<Object?>)
            .length;
    client = creerClientTest((http.Request requete) async {
      requetes.add(requete);
      final url = requete.url;
      if (url.host == 'api.mangadex.network') {
        return http.Response('', 200);
      }
      if (url.path.startsWith('/at-home/server/')) {
        final serveur = baseUrlImages;
        if (serveur == null) return reponseJson(atHome);
        final json = jsonDecode(atHome) as Map<String, Object?>;
        return reponseJson(
          jsonEncode(<String, Object?>{...json, 'baseUrl': serveur}),
        );
      }
      if (url.host.endsWith('.mangadex.network') ||
          url.host == 'uploads.mangadex.org') {
        nombreImagesDemandees++;
        final action = avantImage;
        if (action != null) {
          avantImage = null;
          await action();
        }
        if (nombre403Restants > 0) {
          nombre403Restants--;
          return http.Response('expiré', 403);
        }
        return http.Response.bytes(<int>[1, 2, 3, 4], 200);
      }
      return http.Response('introuvable', 404);
    }, HorlogeFactice());

    depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    depotListes = DepotListes(base);
    depotTelechargements = DepotTelechargements(base);
    parametres = ServiceParametres(DepotParametres(base));
    stockage = StockageTelechargements(dossier.path);
    service = ServiceTelechargement(
      depotTelechargements: depotTelechargements,
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotListes: depotListes,
      depotSources: depotSources,
      stockage: stockage,
      fabriqueSources: FabriqueSources(client),
      client: client,
      serviceParametres: parametres,
      identifiantVerrou: 'application',
      horloge: () => DateTime.now().add(decalage),
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

  /// Second service sur la même base (dépôt, stockage ou horloge
  /// remplacés), fermé à la fin du test.
  ServiceTelechargement creerService({
    DepotTelechargements? depot,
    StockageTelechargements? stockageService,
    String identifiant = 'application',
    DateTime Function()? horloge,
  }) {
    final autre = ServiceTelechargement(
      depotTelechargements: depot ?? depotTelechargements,
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotListes: depotListes,
      depotSources: depotSources,
      stockage: stockageService ?? stockage,
      fabriqueSources: FabriqueSources(client),
      client: client,
      serviceParametres: parametres,
      identifiantVerrou: identifiant,
      horloge: horloge ?? () => DateTime.now().add(decalage),
    );
    addTearDown(autre.fermer);
    return autre;
  }

  /// Attend (au plus 2 s) qu'une écriture lancée sans être attendue soit
  /// visible en base.
  Future<void> attendreQue(Future<bool> Function() condition) async {
    for (var essai = 0; essai < 200; essai++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('La condition attendue ne s\'est jamais réalisée.');
  }

  /// Empêche la file de tourner : un autre isolat tient le verrou.
  Future<void> bloquerFile() => parametres.enregistrerVerrouTelechargement(
    VerrouTelechargement(
      proprietaire: 'tache-de-fond',
      expiration: DateTime.now().toUtc().add(const Duration(days: 3)),
    ),
  );

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
      // Dernier lu = 4 : on garde 3 et 4, on télécharge 5 et 6 ; 1 et 2
      // attendent 24 h avant d'être supprimés.
      expect(telecharges, <int>[1, 2, 3, 4, 5, 6]);
      expect((await chapitre(1)).dateSuppressionPrevue, isNotNull);
      expect((await chapitre(3)).dateSuppressionPrevue, isNull);

      decalage = const Duration(hours: 25);
      expect(await service.supprimerArchivesEchues(), 2);
      final restants =
          (await depotChapitres.chargerChapitres(titre.id!))
              .where((c) => c.estTelecharge)
              .map((c) => c.numero.toInt())
              .toList()
            ..sort();
      expect(restants, <int>[3, 4, 5, 6]);
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

  /// Marque le chapitre « en cours » comme si son dernier enregistrement
  /// datait de [il y a] (dépôt avec une horloge dans le passé).
  Future<void> marquerEnCoursDepuis(int idChapitre, Duration ilYA) async {
    final depotAncien = DepotTelechargements(
      base,
      horloge: () => DateTime.now().toUtc().subtract(ilYA),
    );
    final ligne = await depotAncien.ajouterEnFile(idChapitre);
    await depotAncien.enregistrerStatut(
      ligne.id!,
      StatutTelechargement.enCours,
    );
  }

  test('reprend au démarrage un téléchargement interrompu', () async {
    final premier = await chapitre(1);
    await marquerEnCoursDepuis(premier.id!, const Duration(minutes: 10));
    await service.demarrer();
    await service.lancerTraitement();

    expect(
      (await depotTelechargements.chargerParChapitre(premier.id!))!.statut,
      StatutTelechargement.termine,
    );
  });

  test("ne reprend pas un téléchargement en cours récent (celui de l'autre isolat)", () async {
    final premier = await chapitre(1);
    await marquerEnCoursDepuis(premier.id!, const Duration(seconds: 10));
    await service.demarrer();
    await service.lancerTraitement();

    expect(
      (await depotTelechargements.chargerParChapitre(premier.id!))!.statut,
      StatutTelechargement.enCours,
    );
    expect(requetes, isEmpty);
  });

  group('verrou partagé entre isolats', () {
    ServiceTelechargement creerAutreService() => ServiceTelechargement(
      depotTelechargements: depotTelechargements,
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotListes: depotListes,
      depotSources: depotSources,
      stockage: StockageTelechargements(dossier.path),
      fabriqueSources: FabriqueSources(client),
      client: client,
      serviceParametres: parametres,
      identifiantVerrou: 'tache-de-fond',
    );

    Future<void> poserVerrouAutre(DateTime expiration) =>
        parametres.enregistrerVerrouTelechargement(
          VerrouTelechargement(
            proprietaire: 'tache-de-fond',
            expiration: expiration,
          ),
        );

    test('ne traite rien quand un autre isolat tient le verrou', () async {
      await poserVerrouAutre(
        DateTime.now().toUtc().add(const Duration(minutes: 2)),
      );
      final premier = await chapitre(1);
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();

      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.enAttente);
      expect(requetes, isEmpty);
      final verrou = await parametres.chargerVerrouTelechargement();
      expect(verrou!.proprietaire, 'tache-de-fond');
    });

    test(
      "reprend un verrou expiré, nettoie l'interruption et libère le verrou",
      () async {
        await poserVerrouAutre(DateTime.utc(2000));
        // L'autre isolat a été tué en plein téléchargement.
        final premier = await chapitre(1);
        await marquerEnCoursDepuis(premier.id!, const Duration(minutes: 10));
        final partiel = File('${dossier.path}/abandon.zip.part');
        await partiel.writeAsBytes(<int>[0]);
        await partiel.setLastModified(
          DateTime.now().subtract(const Duration(minutes: 10)),
        );
        // Un .zip.part récent peut être l'écriture de l'autre isolat : il
        // n'est pas effacé.
        final recent = File('${dossier.path}/recent.zip.part');
        await recent.writeAsBytes(<int>[0]);

        await service.lancerTraitement();

        expect(
          (await depotTelechargements.chargerParChapitre(premier.id!))!.statut,
          StatutTelechargement.termine,
        );
        expect(await partiel.exists(), isFalse);
        expect(await recent.exists(), isTrue);
        expect(await parametres.chargerVerrouTelechargement(), isNull);
      },
    );

    test(
      "un second service refuse la file tant que le premier la traite",
      () async {
        final autre = creerAutreService();
        addTearDown(autre.fermer);
        final premier = await chapitre(1);
        final verrous = <VerrouTelechargement?>[];
        avantImage = () async {
          // Le premier service télécharge : la tâche de fond essaie à son
          // tour et doit s'abstenir.
          await autre.lancerTraitement();
          verrous.add(await parametres.chargerVerrouTelechargement());
        };
        await service.telechargerChapitre(premier.id!);
        await service.lancerTraitement();

        expect(verrous.single!.proprietaire, 'application');
        expect(
          (await depotTelechargements.chargerParChapitre(premier.id!))!.statut,
          StatutTelechargement.termine,
        );
        final appelsAtHome = requetes
            .where((r) => r.url.path.startsWith('/at-home/server/'))
            .length;
        expect(appelsAtHome, 1);
      },
    );

    test(
      "s'arrête avant le chapitre suivant si un autre isolat a pris le verrou",
      () async {
        final premier = await chapitre(1);
        final second = await chapitre(2);
        avantImage = () => poserVerrouAutre(
          DateTime.now().toUtc().add(const Duration(minutes: 2)),
        );
        await depotTelechargements.ajouterEnFile(premier.id!);
        await depotTelechargements.ajouterEnFile(second.id!);
        await service.lancerTraitement();

        expect(
          (await depotTelechargements.chargerParChapitre(premier.id!))!.statut,
          StatutTelechargement.termine,
        );
        expect(
          (await depotTelechargements.chargerParChapitre(second.id!))!.statut,
          StatutTelechargement.enAttente,
        );
        // Le verrou de l'autre n'est pas effacé en partant.
        final verrou = await parametres.chargerVerrouTelechargement();
        expect(verrou!.proprietaire, 'tache-de-fond');
      },
    );
  });

  group('protection du chapitre en cours de lecture', () {
    Future<List<int>> numerosTelecharges() async {
      final chapitres = await depotChapitres.chargerChapitres(titre.id!);
      return chapitres
          .where((c) => c.estTelecharge)
          .map((c) => c.numero.toInt())
          .toList()
        ..sort();
    }

    test("les règles ne suppriment pas un chapitre ouvert, puis le suppriment une fois libéré", () async {
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

      final idPremier = (await chapitre(1)).id!;
      service.protegerChapitre(idPremier);
      for (var n = 1; n <= 4; n++) {
        await depotChapitres.marquerLu((await chapitre(n)).id!);
      }
      await service.appliquerRegles(titre.id!);
      await service.lancerTraitement();
      decalage = const Duration(hours: 25);
      await service.supprimerArchivesEchues();
      expect(await numerosTelecharges(), <int>[1, 3, 4, 5, 6]);
      expect(await service.compterPages(idPremier), nombreImages);

      service.libererChapitre(idPremier);
      expect(service.estProtege(idPremier), isFalse);
      await service.appliquerRegles(titre.id!);
      await service.lancerTraitement();
      expect(await numerosTelecharges(), <int>[3, 4, 5, 6]);
    });

    test('la protection compte les ouvertures', () {
      service.protegerChapitre(7);
      service.protegerChapitre(7);
      service.libererChapitre(7);
      expect(service.estProtege(7), isTrue);
      service.libererChapitre(7);
      expect(service.estProtege(7), isFalse);
      // Libérer un chapitre non protégé est sans effet.
      service.libererChapitre(7);
      expect(service.estProtege(7), isFalse);
    });
  });

  List<File> archives() => dossier
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.zip') || f.path.endsWith('.zip.part'))
      .toList();

  int appelsAtHome() =>
      requetes.where((r) => r.url.path.startsWith('/at-home/server/')).length;

  test("redemande les adresses après un 403 d'uploads.mangadex.org, sans signalement", () async {
    baseUrlImages = 'https://uploads.mangadex.org';
    nombre403Restants = 1;
    final premier = await chapitre(1);
    await service.telechargerChapitre(premier.id!);
    await service.lancerTraitement();

    final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
    expect(ligne!.statut, StatutTelechargement.termine);
    expect(appelsAtHome(), 2);
    expect(
      requetes.where((r) => r.url.host == 'api.mangadex.network'),
      isEmpty,
    );
  });

  test("annuler un téléchargement en cours l'arrête à la page suivante sans laisser d'archive", () async {
    final premier = await chapitre(1);
    avantImage = () => service.supprimerTelechargement(premier.id!);
    await service.telechargerChapitre(premier.id!);
    await service.lancerTraitement();

    expect(nombreImagesDemandees, 1);
    expect(await depotTelechargements.chargerParChapitre(premier.id!), isNull);
    expect((await chapitre(1)).estTelecharge, isFalse);
    expect(archives(), isEmpty);
  });

  test('supprimer un titre efface ses archives puis le titre', () async {
    final premier = await chapitre(1);
    await service.telechargerChapitre(premier.id!);
    await service.lancerTraitement();
    expect(archives(), isNotEmpty);

    await service.supprimerTitre(titre.id!);

    expect(archives(), isEmpty);
    expect(await depotTitres.chargerTitre(titre.id!), isNull);
  });

  group('règles et file', () {
    Future<void> suivreAvec(ReglagesTelechargement reglages) async {
      await parametres.enregistrerReglagesTelechargement(reglages);
      await depotListes.ajouterTitre(await idListe(nomListeSuivis), titre.id!);
    }

    test("après 3 échecs, les règles ne relancent plus le chapitre ; le client le peut encore", () async {
      nombre403Restants = 1 << 30;
      await suivreAvec(
        const ReglagesTelechargement(
          suivisInitial: 1,
          suivisAvant: 1,
          suivisApres: 1,
        ),
      );
      for (var essai = 0; essai < 5; essai++) {
        await service.appliquerRegles(titre.id!);
        await service.lancerTraitement();
      }
      // Chaque essai demande deux fois les adresses (essai + renouvellement).
      expect(appelsAtHome(), 3 * 2);

      await service.telechargerChapitre((await chapitre(1)).id!);
      await service.lancerTraitement();
      expect(appelsAtHome(), 4 * 2);
    });

    test('retirer un titre de Suivis retire ses téléchargements en attente, sauf les demandes manuelles', () async {
      // La file reste en attente : un autre isolat tient le verrou.
      await parametres.enregistrerVerrouTelechargement(
        VerrouTelechargement(
          proprietaire: 'tache-de-fond',
          expiration: DateTime.now().toUtc().add(const Duration(minutes: 2)),
        ),
      );
      await suivreAvec(const ReglagesTelechargement(suivisInitial: 3));
      await service.appliquerRegles(titre.id!);
      final manuel = await chapitre(20);
      await service.telechargerChapitre(manuel.id!);
      expect(await depotTelechargements.chargerFile(), hasLength(4));

      await depotListes.retirerTitre(await idListe(nomListeSuivis), titre.id!);
      await service.appliquerRegles(titre.id!);

      final file = await depotTelechargements.chargerFile();
      expect(file.map((t) => t.idChapitre), <int>[manuel.id!]);
    });

    test(
      'une archive dans une langue non choisie est supprimée par les règles',
      () async {
        await depotChapitres.enregistrerChapitres(<Chapitre>[
          Chapitre(
            idTitre: titre.id,
            urlChapitre: 'https://mangadex.org/chapter/$_uuidChapitre?ru=1',
            nom: 'Глава 1',
            numero: 1,
            langue: 'ru',
          ),
        ]);
        final russe = (await depotChapitres.chargerChapitres(titre.id!))
            .firstWhere((c) => c.langue == 'ru');
        await service.telechargerChapitre(russe.id!);
        await service.lancerTraitement();
        expect(
          (await depotChapitres.chargerChapitre(russe.id!))!.estTelecharge,
          isTrue,
        );

        await depotListes.ajouterTitre(
          await idListe(nomListeFavoris),
          titre.id!,
        );
        await service.appliquerRegles(titre.id!);
        await service.lancerTraitement();
        // Suppression différée de 24 h, puis faite à l'échéance.
        final planifie = await depotChapitres.chargerChapitre(russe.id!);
        expect(planifie!.estTelecharge, isTrue);
        expect(planifie.dateSuppressionPrevue, isNotNull);
        decalage = const Duration(hours: 25);
        await service.appliquerRegles(titre.id!);

        expect(
          (await depotChapitres.chargerChapitre(russe.id!))!.estTelecharge,
          isFalse,
        );
        final chapitres = await depotChapitres.chargerChapitres(titre.id!);
        expect(
          chapitres.where((c) => c.estTelecharge).map((c) => c.langue).toSet(),
          <String>{'fr'},
        );
      },
    );

    test('chargerDoublons renvoie les chapitres téléchargés de même numéro et langue', () async {
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: titre.id,
          urlChapitre: 'https://mangadex.org/chapter/$_uuidChapitre?autre=1',
          nom: 'Chapitre 1 (autre groupe)',
          numero: 1,
          langue: 'fr',
        ),
      ]);
      final versions = (await depotChapitres.chargerChapitres(titre.id!))
          .where((c) => c.numero == 1)
          .toList();
      for (final version in versions) {
        await depotChapitres.marquerTelecharge(version.id!);
      }

      final doublons = await service.chargerDoublons(titre.id!);
      expect(
        doublons.single.map((c) => c.id).toSet(),
        versions.map((c) => c.id).toSet(),
      );
    });
  });

  group('suppression différée', () {
    // La file ne tourne pas (verrou tenu ailleurs, voir bloquerFile) : seuls
    // les états en base comptent, les chapitres sont marqués téléchargés
    // directement.
    Future<int> preparerChapitre5HorsRegles() async {
      await bloquerFile();
      await parametres.enregistrerReglagesTelechargement(
        const ReglagesTelechargement(suivisInitial: 2),
      );
      await depotListes.ajouterTitre(await idListe(nomListeSuivis), titre.id!);
      final id = (await chapitre(5)).id!;
      await depotChapitres.marquerTelecharge(id);
      await service.appliquerRegles(titre.id!);
      return id;
    }

    test(
      "pose une échéance à 24 h sans la repousser à chaque application",
      () async {
        final id = await preparerChapitre5HorsRegles();
        final premiere = (await depotChapitres.chargerChapitre(id))!
            .dateSuppressionPrevue;
        expect(premiere, isNotNull);
        final attendu = DateTime.now().toUtc().add(const Duration(hours: 24));
        expect(premiere!.difference(attendu).inMinutes.abs(), lessThan(2));

        decalage = const Duration(hours: 1);
        await service.appliquerRegles(titre.id!);
        expect(
          (await depotChapitres.chargerChapitre(id))!.dateSuppressionPrevue,
          premiere,
        );
      },
    );

    test('« Garder » annule la suppression, même après l\'échéance', () async {
      final id = await preparerChapitre5HorsRegles();
      await service.annulerSuppression(id);
      expect(await service.chargerChapitresGardes(), contains(id));

      decalage = const Duration(hours: 25);
      await service.appliquerRegles(titre.id!);
      await service.supprimerArchivesEchues();
      final garde = (await depotChapitres.chargerChapitre(id))!;
      expect(garde.estTelecharge, isTrue);
      expect(garde.dateSuppressionPrevue, isNull);
    });

    test('« Garder » est enregistré dans le chapitre et non plus dans les '
        'paramètres', () async {
      final id = await preparerChapitre5HorsRegles();
      await service.annulerSuppression(id);
      expect((await depotChapitres.chargerChapitre(id))!.estGarde, isTrue);
      expect(await parametres.chargerChapitresGardes(), isEmpty);
    });

    test("les chapitres gardés par l'ancienne version sont repris au "
        'démarrage puis la clé est supprimée', () async {
      await bloquerFile();
      final id = (await chapitre(5)).id!;
      await depotChapitres.marquerTelecharge(id);
      await depotChapitres.planifierSuppression(
        id,
        DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      await parametres.enregistrerChapitresGardes(<int>[id, 999999]);

      await service.demarrer();

      final relu = (await depotChapitres.chargerChapitre(id))!;
      expect(relu.estGarde, isTrue);
      expect(relu.dateSuppressionPrevue, isNull);
      expect(await parametres.chargerChapitresGardes(), isEmpty);
    });

    test("retirer « Garder » prévoit de nouveau la suppression d'un chapitre "
        "qui n'est plus voulu", () async {
      final id = await preparerChapitre5HorsRegles();
      await service.annulerSuppression(id);
      await service.retirerGarde(id);
      final relu = (await depotChapitres.chargerChapitre(id))!;
      expect(relu.estGarde, isFalse);
      expect(relu.dateSuppressionPrevue, isNotNull);
    });

    test("liste les suppressions prévues de tous les titres ou d'un seul", () async {
      final id = await preparerChapitre5HorsRegles();
      expect(
        (await service.chargerSuppressionsPrevues()).map((c) => c.id),
        <int>[id],
      );
      expect(
        await service.chargerSuppressionsPrevues(idTitre: titre.id! + 1),
        isEmpty,
      );
    });

    test('supprimer un chapitre gardé retire aussi le choix « Garder »', () async {
      final id = await preparerChapitre5HorsRegles();
      await service.annulerSuppression(id);
      await service.supprimerMaintenant(id);
      expect((await depotChapitres.chargerChapitre(id))!.estGarde, isFalse);
    });

    test('supprimer un titre efface aussi sa couverture enregistrée', () async {
      await bloquerFile();
      final chemin = await stockage.enregistrerCouverture(
        titre,
        <int>[1, 2, 3],
        'jpg',
      );
      expect(File(chemin).existsSync(), isTrue);
      await service.supprimerTitre(titre.id!);
      expect(File(chemin).existsSync(), isFalse);
      expect(await depotTitres.chargerTitre(titre.id!), isNull);
    });

    test(
      'un chapitre qui redevient voulu perd sa suppression prévue',
      () async {
        final id = await preparerChapitre5HorsRegles();
        await parametres.enregistrerReglagesTelechargement(
          const ReglagesTelechargement(suivisInitial: 10),
        );
        await service.appliquerRegles(titre.id!);
        expect(
          (await depotChapitres.chargerChapitre(id))!.dateSuppressionPrevue,
          isNull,
        );
      },
    );

    test('modifierLanguesTitre prévoit la suppression des autres langues, '
        'puis le retour au réglage général l\'annule', () async {
      await bloquerFile();
      await depotListes.ajouterTitre(await idListe(nomListeFavoris), titre.id!);
      final id = (await chapitre(1)).id!;
      await depotChapitres.marquerTelecharge(id);

      await service.modifierLanguesTitre(titre.id!, <String>['en']);
      expect(
        (await depotTitres.chargerTitre(titre.id!))!.languesPreferees,
        'en',
      );
      expect(
        (await depotChapitres.chargerChapitre(id))!.dateSuppressionPrevue,
        isNotNull,
      );

      await service.modifierLanguesTitre(titre.id!, null);
      expect(
        (await depotTitres.chargerTitre(titre.id!))!.languesPreferees,
        isNull,
      );
      expect(
        (await depotChapitres.chargerChapitre(id))!.dateSuppressionPrevue,
        isNull,
      );
    });

    test("ouvrir un chapitre repousse sa suppression prévue en base, et la "
        "tâche de fond ne l'efface plus à l'ancienne échéance", () async {
      final id = await preparerChapitre5HorsRegles();
      final premiere = (await depotChapitres.chargerChapitre(id))!
          .dateSuppressionPrevue!;

      decalage = const Duration(hours: 20);
      service.protegerChapitre(id);
      await attendreQue(
        () async =>
            (await depotChapitres.chargerChapitre(id))!.dateSuppressionPrevue !=
            premiere,
      );
      final repoussee = (await depotChapitres.chargerChapitre(id))!
          .dateSuppressionPrevue!;
      expect(
        repoussee.difference(premiere).inMinutes,
        closeTo(const Duration(hours: 20).inMinutes, 2),
      );

      // La tâche de fond (autre isolat) ne voit pas la protection en
      // mémoire : 25 h après la première date, elle ne doit rien effacer.
      final tacheDeFond = creerService(
        identifiant: 'tache-de-fond',
        horloge: () => DateTime.now().add(const Duration(hours: 25)),
      );
      expect(await tacheDeFond.supprimerArchivesEchues(), 0);
      expect((await depotChapitres.chargerChapitre(id))!.estTelecharge, isTrue);
    });

    test("ouvrir un chapitre sans suppression prévue n'en pose pas", () async {
      await bloquerFile();
      final id = (await chapitre(1)).id!;
      await depotChapitres.marquerTelecharge(id);
      service.protegerChapitre(id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        (await depotChapitres.chargerChapitre(id))!.dateSuppressionPrevue,
        isNull,
      );
    });

    test("une suppression échue n'est pas faite si les règles veulent de "
        'nouveau le chapitre', () async {
      final id = await preparerChapitre5HorsRegles();
      // Réglage changé dans l'autre isolat : les règles de ce titre n'ont
      // pas encore été réappliquées ici.
      await parametres.enregistrerReglagesTelechargement(
        const ReglagesTelechargement(suivisInitial: 10),
      );
      decalage = const Duration(hours: 25);

      expect(await service.supprimerArchivesEchues(), 0);
      final relu = (await depotChapitres.chargerChapitre(id))!;
      expect(relu.estTelecharge, isTrue);
      expect(relu.dateSuppressionPrevue, isNull);
    });

    test("une suppression échue n'est pas faite si le titre n'est plus ni "
        'favori ni suivi', () async {
      final id = await preparerChapitre5HorsRegles();
      await depotListes.retirerTitre(await idListe(nomListeSuivis), titre.id!);
      decalage = const Duration(hours: 25);

      expect(await service.supprimerArchivesEchues(), 0);
      final relu = (await depotChapitres.chargerChapitre(id))!;
      expect(relu.estTelecharge, isTrue);
      expect(relu.dateSuppressionPrevue, isNull);
    });
  });

  group("nom d'archive enregistré", () {
    test('supprimerMaintenant efface tout de suite archive et nom', () async {
      final premier = await chapitre(1);
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();
      expect((await chapitre(1)).nomArchive, isNotNull);

      await service.supprimerMaintenant(premier.id!);
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isFalse);
      expect(relu.nomArchive, isNull);
      expect(archives(), isEmpty);
    });

    test(
      'deux versions de même numéro et langue ont deux archives distinctes',
      () async {
        await depotChapitres.enregistrerChapitres(<Chapitre>[
          Chapitre(
            idTitre: titre.id,
            urlChapitre: 'https://mangadex.org/chapter/$_uuidChapitre?autre=1',
            nom: 'Chapitre 1 (autre groupe)',
            numero: 1,
            langue: 'fr',
          ),
        ]);
        final versions = (await depotChapitres.chargerChapitres(titre.id!))
            .where((c) => c.numero == 1)
            .toList();
        for (final version in versions) {
          await service.telechargerChapitre(version.id!);
        }
        await service.lancerTraitement();

        final noms = <String?>[
          for (final version in versions)
            (await depotChapitres.chargerChapitre(version.id!))!.nomArchive,
        ];
        expect(noms[0], endsWith('/ch1.fr.zip'));
        expect(noms[1], endsWith('/ch1.fr.2.zip'));
        expect(await service.lirePage(versions[1].id!, 0), <int>[1, 2, 3, 4]);

        // Supprimer le doublon laisse l'autre archive lisible.
        await service.supprimerTelechargement(versions[1].id!);
        expect(await service.compterPages(versions[0].id!), nombreImages);
        expect(archives(), hasLength(1));
      },
    );

    test("au démarrage, un chapitre sans archive sur le disque redevient non téléchargé", () async {
      final premier = await chapitre(1);
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();
      for (final fichier in archives()) {
        await fichier.delete();
      }

      expect(await service.reparerArchivesManquantes(), 1);
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isFalse);
      expect(relu.nomArchive, isNull);
      // La ligne « terminé » est retirée : les règles pourront remettre le
      // chapitre en file.
      expect(
        await depotTelechargements.chargerParChapitre(premier.id!),
        isNull,
      );
    });

    test('au démarrage, un dossier racine absent (support démonté) ne '
        'modifie aucun chapitre', () async {
      final premier = await chapitre(1);
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();
      final nomArchive = (await chapitre(1)).nomArchive;

      final surSupportAbsent = creerService(
        stockageService: StockageTelechargements('${dossier.path}/absent'),
      );
      expect(await surSupportAbsent.reparerArchivesManquantes(), 0);
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isTrue);
      expect(relu.nomArchive, nomArchive);
    });
  });

  group('suppression et fin de téléchargement', () {
    Future<List<Chapitre>> ajouterDeuxOneshots() async {
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        for (final lettre in <String>['A', 'B'])
          Chapitre(
            idTitre: titre.id,
            urlChapitre:
                'https://mangadex.org/chapter/$_uuidChapitre?oneshot=$lettre',
            nom: 'Oneshot $lettre',
            numero: 0,
            langue: 'fr',
          ),
      ]);
      return (await depotChapitres.chargerChapitres(titre.id!))
          .where((c) => c.numero == 0)
          .toList()
        ..sort((a, b) => a.id!.compareTo(b.id!));
    }

    test("annuler un oneshot en file ne touche pas l'archive d'un autre "
        'oneshot', () async {
      final oneshots = await ajouterDeuxOneshots();
      final a = oneshots[0];
      final b = oneshots[1];
      await service.telechargerChapitre(a.id!);
      await service.lancerTraitement();
      final nomA = (await depotChapitres.chargerChapitre(a.id!))!.nomArchive;
      expect(nomA, endsWith('/ch0.fr.zip'));

      // B reste en file (jamais téléchargé) : son nom calculé serait aussi
      // ch0.fr.zip.
      await bloquerFile();
      await service.telechargerChapitre(b.id!);
      await service.supprimerTelechargement(b.id!);

      expect(await depotTelechargements.chargerParChapitre(b.id!), isNull);
      expect(await stockage.existeArchive(nomA!), isTrue);
      expect(await service.compterPages(a.id!), nombreImages);
      expect(
        (await depotChapitres.chargerChapitre(a.id!))!.estTelecharge,
        isTrue,
      );
    });

    test("annuler un chapitre en file (autre groupe, même numéro) ne touche "
        "pas l'archive du chapitre téléchargé", () async {
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: titre.id,
          urlChapitre: 'https://mangadex.org/chapter/$_uuidChapitre?groupe=2',
          nom: 'Chapitre 1 (autre groupe)',
          numero: 1,
          langue: 'fr',
        ),
      ]);
      final premier = await chapitre(1);
      final autreGroupe = (await depotChapitres.chargerChapitres(titre.id!))
          .firstWhere((c) => c.numero == 1 && c.id != premier.id);
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();

      await bloquerFile();
      await service.telechargerChapitre(autreGroupe.id!);
      await service.supprimerTelechargement(autreGroupe.id!);

      expect(await service.compterPages(premier.id!), nombreImages);
    });

    test("supprimerTelechargement retire la ligne de file avant d'effacer "
        "l'archive", () async {
      final premier = await chapitre(1);
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();

      final lignesAuMomentDeLEffacement = <Object?>[];
      final espion = _StockageEspion(dossier.path, (nomArchive) async {
        lignesAuMomentDeLEffacement.add(
          await depotTelechargements.chargerParChapitre(premier.id!),
        );
      });
      await creerService(stockageService: espion)
          .supprimerTelechargement(premier.id!);

      expect(lignesAuMomentDeLEffacement, <Object?>[null]);
      expect(archives(), isEmpty);
      expect((await chapitre(1)).estTelecharge, isFalse);
    });

    test("une archive finie dont le statut ne s'enregistre pas est effacée "
        '(pas de fichier orphelin)', () async {
      final premier = await chapitre(1);
      final serviceFragile = creerService(
        depot: _DepotQuiEchoueAuTermine(base),
      );
      await serviceFragile.telechargerChapitre(premier.id!);
      await serviceFragile.lancerTraitement();

      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.echec);
      expect(archives(), isEmpty);
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isFalse);
      expect(relu.nomArchive, isNull);
    });

    test("un verrou repris par l'autre isolat entre deux pages arrête le "
        'chapitre sans toucher sa ligne de file', () async {
      final premier = await chapitre(1);
      avantImage = () async {
        // Notre verrou a expiré (application en pause) et la tâche de fond
        // l'a repris : le prochain renouvellement est dû et le constate.
        decalage = const Duration(minutes: 2);
        await parametres.enregistrerVerrouTelechargement(
          VerrouTelechargement(
            proprietaire: 'tache-de-fond',
            expiration: DateTime.now().toUtc().add(const Duration(minutes: 10)),
          ),
        );
      };
      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();

      expect(nombreImagesDemandees, 1);
      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.enCours);
      expect(ligne.nombrePagesFaites, 1);
      expect(archives(), isEmpty);
      expect((await chapitre(1)).estTelecharge, isFalse);
      final verrou = await parametres.chargerVerrouTelechargement();
      expect(verrou!.proprietaire, 'tache-de-fond');
    });
  });
}

/// Stockage qui prévient le test juste avant d'effacer une archive.
class _StockageEspion extends StockageTelechargements {
  _StockageEspion(super.dossierRacine, this._avantEffacement);

  final Future<void> Function(String nomArchive) _avantEffacement;

  @override
  Future<bool> supprimerArchive(String nomArchive) async {
    await _avantEffacement(nomArchive);
    return super.supprimerArchive(nomArchive);
  }
}

/// Dépôt dont l'enregistrement du statut « terminé » échoue (base occupée
/// par l'autre isolat, disque plein…), après la finalisation de l'archive.
class _DepotQuiEchoueAuTermine extends DepotTelechargements {
  _DepotQuiEchoueAuTermine(super.base);

  @override
  Future<bool> enregistrerStatut(
    int id,
    StatutTelechargement statut, {
    String? messageErreur,
    String? nomArchive,
  }) {
    if (statut == StatutTelechargement.termine) {
      throw StateError('Base occupée');
    }
    return super.enregistrerStatut(
      id,
      statut,
      messageErreur: messageErreur,
      nomArchive: nomArchive,
    );
  }
}
