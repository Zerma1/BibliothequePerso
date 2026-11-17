// Dossier des chapitres choisi par le client (disque, lecteur réseau, NAS) :
// dossier injoignable jamais pris pour des archives perdues, file qui attend
// son retour, changement de dossier avec déplacement des archives.
// Base en mémoire, dossiers temporaires (un NAS « éteint » est un dossier
// renommé), réponses MangaDex enregistrées : aucun appel réseau.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/erreur_stockage.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/dossier_chapitres.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/services/verrou_telechargement.dart';
import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

const String _uuidChapitre = 'ef4aae9e-eea8-4931-8435-9f907870f4d8';

void main() {
  late Database base;
  late Directory temporaire;
  late DepotChapitres depotChapitres;
  late DepotListes depotListes;
  late DepotTelechargements depotTelechargements;
  late DepotParametres depotParametres;
  late DepotSources depotSources;
  late DepotTitres depotTitres;
  late ServiceParametres parametres;
  late ClientHttpPoli client;
  late List<http.Request> requetes;
  late int nombreImagesDemandees;
  late Titre titre;
  late String dossierParDefaut;
  // Action lancée une fois, à la première demande du contenu d'un chapitre
  // (avant l'ouverture de l'archive).
  Future<void> Function()? avantContenu;
  // Action lancée une fois, à la première demande d'image.
  Future<void> Function()? avantImage;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    temporaire = await Directory.systemTemp.createTemp('dossier_chapitres');
    dossierParDefaut = p.join(temporaire.path, 'defaut');
    requetes = <http.Request>[];
    nombreImagesDemandees = 0;
    avantContenu = null;
    avantImage = null;
    final atHome = lireExemple('exemples_json/at_home_serveur.json');
    final flux =
        lireJsonExemple('manga_flux_page1.json')['data']! as List<Object?>;
    final reponseChapitre = jsonEncode(<String, Object?>{
      'result': 'ok',
      'response': 'entity',
      'data': flux.firstWhere(
        (d) => (d! as Map<String, Object?>)['id'] == _uuidChapitre,
      ),
    });
    client = creerClientTest((http.Request requete) async {
      requetes.add(requete);
      final url = requete.url;
      if (url.host == 'api.mangadex.network') {
        return http.Response('', 200);
      }
      if (url.host == 'api.mangadex.org' && url.path.startsWith('/chapter/')) {
        final action = avantContenu;
        if (action != null) {
          avantContenu = null;
          await action();
        }
        return reponseJson(reponseChapitre);
      }
      if (url.path.startsWith('/at-home/server/')) {
        return reponseJson(atHome);
      }
      if (url.host.endsWith('.mangadex.network') ||
          url.host == 'uploads.mangadex.org') {
        nombreImagesDemandees++;
        final action = avantImage;
        if (action != null) {
          avantImage = null;
          await action();
        }
        return http.Response.bytes(
          <int>[1, 2, 3, 4],
          200,
          headers: <String, String>{'content-type': 'image/jpeg'},
        );
      }
      return http.Response('introuvable', 404);
    }, HorlogeFactice());

    depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    depotListes = DepotListes(base);
    depotTelechargements = DepotTelechargements(base);
    depotParametres = DepotParametres(base);
    parametres = ServiceParametres(depotParametres);

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
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (var n = 1; n <= 3; n++)
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
    await base.close();
    try {
      await temporaire.delete(recursive: true);
    } on FileSystemException {
      // Fichier encore ouvert par le système : le dossier temporaire sera
      // nettoyé plus tard, sans conséquence sur les tests.
    }
  });

  Future<Chapitre> chapitre(int numero, {Titre? deTitre}) async {
    final chapitres = await depotChapitres.chargerChapitres(
      (deTitre ?? titre).id!,
    );
    return chapitres.firstWhere((c) => c.numero == numero);
  }

  ServiceTelechargement creerService(
    StockageTelechargements stockage, {
    String identifiant = 'application',
  }) {
    final service = ServiceTelechargement(
      depotTelechargements: depotTelechargements,
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotListes: depotListes,
      depotSources: depotSources,
      stockage: stockage,
      fabriqueSources: FabriqueSources(client),
      client: client,
      serviceParametres: parametres,
      identifiantVerrou: identifiant,
      depotParametres: depotParametres,
    );
    addTearDown(service.fermer);
    return service;
  }

  ServiceDossierChapitres creerDossiers(ServiceTelechargement service) =>
      ServiceDossierChapitres(
        serviceTelechargement: service,
        depotParametres: depotParametres,
        cheminDossierParDefaut: () async => dossierParDefaut,
      );

  /// Dossier « NAS » accepté par la validation (fichier repère écrit).
  Future<String> preparerNas([String nom = 'nas']) =>
      StockageTelechargements.validerDossier(p.join(temporaire.path, nom));

  /// NAS éteint : le dossier disparaît (renommé).
  Future<void> eteindre(String nas) => Directory(nas).rename('$nas.eteint');

  /// NAS rallumé : le dossier revient avec son contenu.
  Future<void> rallumer(String nas) => Directory('$nas.eteint').rename(nas);

  /// Écrit l'archive d'un chapitre (une page) sans réseau et l'enregistre
  /// en base, comme à la fin d'un téléchargement.
  Future<String> ecrireArchive(
    StockageTelechargements stockage,
    Chapitre chapitreAEcrire, {
    Titre? deTitre,
  }) async {
    final ecriture = await stockage.ouvrirEcriture(
      deTitre ?? titre,
      chapitreAEcrire,
    );
    await ecriture.ajouterPage(<int>[1, 2, 3, 4], extension: 'jpg');
    await ecriture.finaliser();
    await depotChapitres.enregistrerArchive(
      chapitreAEcrire.id!,
      ecriture.nomArchive,
    );
    return ecriture.nomArchive;
  }

  String cheminArchive(String racine, String nomArchive) =>
      p.joinAll(<String>[racine, ...nomArchive.split('/')]);

  group('dossier inaccessible ≠ archive manquante', () {
    test('un NAS éteint au démarrage ne fait passer aucun chapitre en « non '
        'téléchargé » et le bandeau le signale', () async {
      final nas = await preparerNas();
      final stockage = StockageTelechargements.personnalise(nas);
      final nomArchive = await ecrireArchive(stockage, await chapitre(1));
      final service = creerService(stockage);
      final dossiers = creerDossiers(service);
      await eteindre(nas);

      expect(await service.reparerArchivesManquantes(), 0);
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isTrue);
      expect(relu.nomArchive, nomArchive);
      expect(dossiers.accesDossier.estAccessible, isFalse);
      expect(dossiers.accesDossier.message, contains('inaccessible'));
      expect(dossiers.accesDossier.message, contains('ne sont pas perdus'));

      // Le NAS revient : le bandeau disparaît.
      await rallumer(nas);
      expect((await dossiers.verifierAccesDossier()).estAccessible, isTrue);
      expect(dossiers.accesDossier.message, isNull);
      // Le retour du NAS relance la file (vide ici) : on attend sa fin.
      await service.lancerTraitement();
    });

    test('un point de montage vide (sans fichier repère) est traité comme un '
        'NAS éteint', () async {
      final nas = await preparerNas();
      final stockage = StockageTelechargements.personnalise(nas);
      await ecrireArchive(stockage, await chapitre(1));
      final service = creerService(stockage);
      // Partage démonté : il ne reste qu'un dossier vide sur le disque local.
      await Directory(nas).delete(recursive: true);
      await Directory(nas).create();

      expect(await service.reparerArchivesManquantes(), 0);
      expect((await chapitre(1)).estTelecharge, isTrue);
    });

    test('avec le NAS joignable, une archive effacée à la main est bien '
        'réparée', () async {
      final nas = await preparerNas();
      final stockage = StockageTelechargements.personnalise(nas);
      final nomArchive = await ecrireArchive(stockage, await chapitre(1));
      await File(cheminArchive(nas, nomArchive)).delete();
      final service = creerService(stockage);

      expect(await service.reparerArchivesManquantes(), 1);
      expect((await chapitre(1)).estTelecharge, isFalse);
    });

    test('un déplacement inachevé suspend le contrôle des archives', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final nomArchive = await ecrireArchive(stockage, await chapitre(1));
      await File(cheminArchive(ancien, nomArchive)).delete();
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
        p.join(temporaire.path, 'nas'),
      );
      final service = creerService(stockage);

      expect(await service.reparerArchivesManquantes(), 0);
      expect((await chapitre(1)).estTelecharge, isTrue);
    });

    test(
      'les suppressions prévues échues attendent le retour du NAS',
      () async {
        final nas = await preparerNas();
        final stockage = StockageTelechargements.personnalise(nas);
        final premier = await chapitre(1);
        await ecrireArchive(stockage, premier);
        await depotChapitres.planifierSuppression(
          premier.id!,
          DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        );
        final service = creerService(stockage);
        await eteindre(nas);

        expect(await service.supprimerArchivesEchues(), 0);
        final relu = await chapitre(1);
        expect(relu.estTelecharge, isTrue);
        expect(relu.dateSuppressionPrevue, isNotNull);
      },
    );
  });

  group('file de téléchargement et NAS', () {
    test('NAS éteint : la file attend sans requête ni échec, puis reprend '
        'dès son retour', () async {
      final nas = await preparerNas();
      final service = creerService(StockageTelechargements.personnalise(nas));
      final dossiers = creerDossiers(service);
      await eteindre(nas);
      final premier = await chapitre(1);

      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();

      expect(requetes, isEmpty);
      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.enAttente);
      expect(ligne.messageErreur, isNull);
      expect(dossiers.accesDossier.estAccessible, isFalse);

      // Retour du NAS : la vérification relance la file d'elle-même.
      await rallumer(nas);
      await dossiers.verifierAccesDossier();
      await service.lancerTraitement();

      final finie = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(finie!.statut, StatutTelechargement.termine);
      expect((await chapitre(1)).estTelecharge, isTrue);
      expect(await service.compterPages(premier.id!), greaterThan(0));
    });

    test("NAS perdu au début d'un chapitre : le chapitre retourne en attente "
        "sans compter d'échec, puis se télécharge au retour du NAS", () async {
      final nas = await preparerNas();
      final service = creerService(StockageTelechargements.personnalise(nas));
      final dossiers = creerDossiers(service);
      final premier = await chapitre(1);
      // Le NAS s'éteint juste après le contrôle d'avant chapitre, pendant
      // la demande du contenu au site.
      avantContenu = () => eteindre(nas);

      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();

      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.enAttente);
      expect(ligne.messageErreur, isNull);
      expect(nombreImagesDemandees, 0);
      expect((await chapitre(1)).estTelecharge, isFalse);
      expect(dossiers.accesDossier.estAccessible, isFalse);

      await rallumer(nas);
      await dossiers.verifierAccesDossier();
      await service.lancerTraitement();
      final finie = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(finie!.statut, StatutTelechargement.termine);
    });
  });

  group('changement du dossier des chapitres', () {
    test('déplace les archives, enregistre le réglage et ne change de '
        'dossier qu\'au prochain démarrage', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final premier = await chapitre(1);
      final nomArchive = await ecrireArchive(stockage, premier);
      final service = creerService(stockage);
      final dossiers = creerDossiers(service);
      final nouveau = p.join(temporaire.path, 'nas');
      final progression = <(int, int)>[];

      final resultat = await dossiers.changerDossierChapitres(
        nouveau,
        surProgression: (faits, total) => progression.add((faits, total)),
      );

      expect(resultat.archivesDeplacees, isTrue);
      expect(resultat.bilan!.nombreFichiers, 1);
      expect(resultat.redemarrageNecessaire, isTrue);
      expect(resultat.dossierChoisi, p.normalize(nouveau));
      expect(resultat.message, contains('Redémarrez'));
      expect(progression, <(int, int)>[(0, 1), (1, 1)]);
      expect(await File(cheminArchive(nouveau, nomArchive)).exists(), isTrue);
      expect(await File(cheminArchive(ancien, nomArchive)).exists(), isFalse);
      expect(await dossiers.chargerDossierChoisi(), p.normalize(nouveau));
      expect(await dossiers.chargerDeplacementInacheve(), isNull);
      expect(dossiers.redemarrageNecessaire, isTrue);
      expect(dossiers.estFileEnPause, isTrue);

      // D'ici le redémarrage : lecture refusée avec un message clair, file en
      // pause, aucun chapitre remis à « non téléchargé ».
      await expectLater(
        service.lirePage(premier.id!, 0),
        throwsA(isA<ErreurService>()),
      );
      final deuxieme = await chapitre(2);
      await service.telechargerChapitre(deuxieme.id!);
      await service.lancerTraitement();
      expect(requetes, isEmpty);
      expect(
        (await depotTelechargements.chargerParChapitre(deuxieme.id!))!.statut,
        StatutTelechargement.enAttente,
      );
      expect(await service.reparerArchivesManquantes(), 0);
      expect((await chapitre(1)).estTelecharge, isTrue);
      await expectLater(
        dossiers.changerDossierChapitres(p.join(temporaire.path, 'autre')),
        throwsA(isA<ErreurService>()),
      );

      // Prochain démarrage : le stockage suit le réglage.
      final apres = await ServiceDossierChapitres.creerStockage(
        depotParametres,
      );
      expect(apres.estPersonnalise, isTrue);
      expect(apres.dossierRacine, p.normalize(nouveau));
      final redemarre = creerService(apres, identifiant: 'redemarre');
      expect(await redemarre.reparerArchivesManquantes(), 0);
      expect(await redemarre.lirePage(premier.id!, 0), <int>[1, 2, 3, 4]);
    });

    test('sans déplacement, seul le réglage change et les archives restent '
        'lisibles jusqu\'au redémarrage', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final premier = await chapitre(1);
      final nomArchive = await ecrireArchive(stockage, premier);
      final service = creerService(stockage);
      final dossiers = creerDossiers(service);
      final nouveau = p.join(temporaire.path, 'nas');

      final resultat = await dossiers.changerDossierChapitres(
        nouveau,
        deplacerArchives: false,
      );

      expect(resultat.archivesDeplacees, isFalse);
      expect(resultat.message, contains("l'ancien dossier"));
      expect(await File(cheminArchive(ancien, nomArchive)).exists(), isTrue);
      expect(await dossiers.chargerDossierChoisi(), p.normalize(nouveau));
      expect(dossiers.estFileEnPause, isTrue);
      expect(await service.lirePage(premier.id!, 0), <int>[1, 2, 3, 4]);
    });

    test('revenir au dossier par défaut y déplace les archives et efface le '
        'réglage', () async {
      final nas = await preparerNas();
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDossierChapitres,
        nas,
      );
      final stockage = StockageTelechargements.personnalise(nas);
      final nomArchive = await ecrireArchive(stockage, await chapitre(1));
      final dossiers = creerDossiers(creerService(stockage));

      final resultat = await dossiers.changerDossierChapitres(null);

      expect(resultat.dossierChoisi, isNull);
      expect(resultat.cheminDossier, p.normalize(dossierParDefaut));
      expect(await dossiers.chargerDossierChoisi(), isNull);
      expect(
        await File(cheminArchive(dossierParDefaut, nomArchive)).exists(),
        isTrue,
      );
    });

    test(
      'un chemin refusé ne change rien et ne met pas la file en pause',
      () async {
        final dossiers = creerDossiers(
          creerService(StockageTelechargements(p.join(temporaire.path, 'a'))),
        );

        await expectLater(
          dossiers.changerDossierChapitres(p.join('relatif', 'dossier')),
          throwsA(isA<ErreurService>()),
        );
        expect(dossiers.estFileEnPause, isFalse);
        expect(dossiers.redemarrageNecessaire, isFalse);
        expect(await dossiers.chargerDossierChoisi(), isNull);
      },
    );

    test('choisir le dossier déjà utilisé est refusé', () async {
      final actuel = p.join(temporaire.path, 'actuel');
      final dossiers = creerDossiers(
        creerService(StockageTelechargements(actuel)),
      );

      await expectLater(
        dossiers.changerDossierChapitres(actuel),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('déjà'),
          ),
        ),
      );
    });

    test('un chapitre en cours de téléchargement fait refuser le '
        'déplacement ; la file s\'arrête après lui et la demande suivante '
        'aboutit', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final service = creerService(StockageTelechargements(ancien));
      final dossiers = creerDossiers(service);
      final atteint = Completer<void>();
      final libere = Completer<void>();
      avantImage = () async {
        atteint.complete();
        await libere.future;
      };
      final premier = await chapitre(1);
      final deuxieme = await chapitre(2);
      await service.telechargerChapitre(premier.id!);
      await service.telechargerChapitre(deuxieme.id!);
      await atteint.future;

      await expectLater(
        dossiers.changerDossierChapitres(p.join(temporaire.path, 'nas')),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('en cours de téléchargement'),
          ),
        ),
      );
      expect(dossiers.estFileEnPause, isTrue);

      libere.complete();
      await service.lancerTraitement();
      expect((await chapitre(1)).estTelecharge, isTrue);
      // Pause : le chapitre suivant n'a pas été commencé.
      expect(
        (await depotTelechargements.chargerParChapitre(deuxieme.id!))!.statut,
        StatutTelechargement.enAttente,
      );

      final resultat = await dossiers.changerDossierChapitres(
        p.join(temporaire.path, 'nas'),
      );
      expect(resultat.bilan!.nombreFichiers, 1);
    });

    test('renoncer après un refus relance la file', () async {
      final service = creerService(
        StockageTelechargements(p.join(temporaire.path, 'ancien')),
      );
      final dossiers = creerDossiers(service);
      final atteint = Completer<void>();
      final libere = Completer<void>();
      avantImage = () async {
        atteint.complete();
        await libere.future;
      };
      final deuxieme = await chapitre(2);
      await service.telechargerChapitre((await chapitre(1)).id!);
      await service.telechargerChapitre(deuxieme.id!);
      await atteint.future;
      await expectLater(
        dossiers.changerDossierChapitres(p.join(temporaire.path, 'nas')),
        throwsA(isA<ErreurService>()),
      );
      libere.complete();
      await service.lancerTraitement();

      dossiers.reprendreFile();
      expect(dossiers.estFileEnPause, isFalse);
      await service.lancerTraitement();
      expect((await chapitre(2)).estTelecharge, isTrue);
    });

    test('la file tenue par la tâche de fond fait refuser le déplacement, '
        'sans laisser la file en pause', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final nomArchive = await ecrireArchive(stockage, await chapitre(1));
      final dossiers = creerDossiers(creerService(stockage));
      await parametres.enregistrerVerrouTelechargement(
        VerrouTelechargement(
          proprietaire: 'tache-de-fond',
          expiration: DateTime.now().toUtc().add(const Duration(days: 3)),
        ),
      );

      await expectLater(
        dossiers.changerDossierChapitres(p.join(temporaire.path, 'nas')),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('arrière-plan'),
          ),
        ),
      );
      expect(dossiers.estFileEnPause, isFalse);
      expect(await File(cheminArchive(ancien, nomArchive)).exists(), isTrue);
      expect(await dossiers.chargerDeplacementInacheve(), isNull);
      expect(await dossiers.chargerDossierChoisi(), isNull);
    });

    test('une copie interrompue est signalée comme inachevée, suspend le '
        'contrôle des archives, puis se reprend', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      // Deux titres de types différents : « autre/… » est déplacé avant
      // « manga/… » (ordre alphabétique), qui échoue.
      await ecrireArchive(stockage, await chapitre(1));
      final titreManga = await depotTitres.enregistrerTitre(
        Titre(
          idSource: titre.idSource,
          urlTitre: 'https://mangadex.org/title/autre',
          nom: 'Autre titre',
          typeTitre: TypeTitre.manga,
        ),
      );
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: titreManga.id,
          urlChapitre: 'https://mangadex.org/chapter/autre-1',
          nom: 'Chapitre 1',
          numero: 1,
          langue: 'fr',
        ),
      ]);
      await ecrireArchive(
        stockage,
        await chapitre(1, deTitre: titreManga),
        deTitre: titreManga,
      );
      final service = creerService(stockage);
      final dossiers = creerDossiers(service);
      final nouveau = await preparerNas();
      // Un fichier « manga » empêche de créer le dossier du même nom.
      final bloquant = File(p.join(nouveau, 'manga'));
      await bloquant.writeAsString('bloque');

      await expectLater(
        dossiers.changerDossierChapitres(nouveau),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('relancez'),
          ),
        ),
      );
      expect(await dossiers.chargerDeplacementInacheve(), nouveau);
      expect(await dossiers.chargerDossierChoisi(), isNull);
      expect(dossiers.estFileEnPause, isFalse);
      // L'archive déjà déplacée n'est plus dans l'ancien dossier, mais le
      // chapitre n'est pas pris pour perdu.
      expect(await service.reparerArchivesManquantes(), 0);
      expect((await chapitre(1)).estTelecharge, isTrue);

      await bloquant.delete();
      final resultat = await dossiers.changerDossierChapitres(nouveau);
      expect(resultat.bilan!.nombreFichiers, 1);
      expect(await dossiers.chargerDeplacementInacheve(), isNull);
      expect(await dossiers.chargerDossierChoisi(), nouveau);
    });

    test('deux demandes simultanées : la seconde est refusée', () async {
      final dossiers = creerDossiers(
        creerService(StockageTelechargements(p.join(temporaire.path, 'a'))),
      );
      final premiere = dossiers.changerDossierChapitres(
        p.join(temporaire.path, 'b'),
      );
      await expectLater(
        dossiers.changerDossierChapitres(p.join(temporaire.path, 'c')),
        throwsA(isA<ErreurService>()),
      );
      await premiere;
    });
  });

  group('messages pour l\'interface', () {
    test('un dossier accessible n\'affiche aucun bandeau', () {
      const acces = AccesDossierChapitres.accessible(
        '/mnt/nas',
        estPersonnalise: true,
      );
      expect(acces.message, isNull);
    });

    test('le bandeau explique la cause selon la nature du problème', () {
      const reseau = AccesDossierChapitres.inaccessible(
        r'\\nas\mangas',
        estPersonnalise: true,
        nature: NatureErreurStockage.reseauIndisponible,
      );
      expect(reseau.message, contains('partage réseau ne répond pas'));
      expect(reseau.message, contains(r'\\nas\mangas'));
      const absent = AccesDossierChapitres.inaccessible(
        'Z:/Mangas',
        estPersonnalise: true,
      );
      expect(absent.message, contains('NAS éteint'));
    });

    test('le résultat d\'un changement rappelle de redémarrer, avec ou sans '
        'déplacement', () {
      const sans = ResultatChangementDossier(
        dossierChoisi: '/mnt/nas',
        cheminDossier: '/mnt/nas',
      );
      expect(sans.archivesDeplacees, isFalse);
      expect(sans.message, contains("Redémarrez l'application"));
      const avec = ResultatChangementDossier(
        dossierChoisi: null,
        cheminDossier: '/home/moi/Documents/bibliotheque_perso',
        bilan: BilanDeplacement(
          nombreFichiers: 3,
          nombreCopies: 3,
          nombreDejaPresents: 0,
          octetsCopies: 12,
        ),
      );
      expect(avec.archivesDeplacees, isTrue);
      expect(avec.message, contains('3 fichier(s)'));
    });
  });
}
