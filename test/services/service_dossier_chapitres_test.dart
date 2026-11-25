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
  // `emplacements.json` dans le dossier temporaire : jamais le vrai %APPDATA%.
  late String cheminEmplacements;
  // Action lancée une fois, à la première demande du contenu d'un chapitre
  // (avant l'ouverture de l'archive).
  Future<void> Function()? avantContenu;
  // Action lancée une fois, à la première demande d'image.
  Future<void> Function()? avantImage;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    temporaire = await Directory.systemTemp.createTemp('dossier_chapitres');
    dossierParDefaut = p.join(temporaire.path, 'defaut');
    cheminEmplacements = p.join(temporaire.path, 'appli', 'emplacements.json');
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
    bool avecParametres = true,
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
      depotParametres: avecParametres ? depotParametres : null,
    );
    addTearDown(service.fermer);
    return service;
  }

  ServiceDossierChapitres creerDossiers(ServiceTelechargement service) =>
      ServiceDossierChapitres(
        serviceTelechargement: service,
        depotParametres: depotParametres,
        cheminDossierParDefaut: () async => dossierParDefaut,
        cheminFichierEmplacements: () async => cheminEmplacements,
      );

  /// Stockage du démarrage ([ServiceDossierChapitres.creerStockage]), avec
  /// `emplacements.json` écrit dans le dossier temporaire.
  Future<StockageTelechargements> demarrerStockage() =>
      ServiceDossierChapitres.creerStockage(
        depotParametres,
        cheminFichierEmplacements: () async => cheminEmplacements,
      );

  /// Dossier lu dans `emplacements.json`, comme le désinstalleur, ou `null`
  /// si le fichier n'existe pas.
  Future<String?> lireEmplacements() async {
    final fichier = File(cheminEmplacements);
    if (!await fichier.exists()) return null;
    final donnees = jsonDecode(
      utf8.decode(await fichier.readAsBytes()),
    ) as Map<String, Object?>;
    return donnees['dossierChapitres'] as String?;
  }

  /// Dossier « NAS » accepté par la validation (fichier repère écrit).
  Future<String> preparerNas([String nom = 'nas']) =>
      StockageTelechargements.validerDossier(p.join(temporaire.path, nom));

  /// Stockage sur le NAS, comme au démarrage : le réglage pointe dessus.
  Future<StockageTelechargements> stockageNas(String nas) async {
    await depotParametres.enregistrerTexte(
      ServiceParametres.cleDossierChapitres,
      nas,
    );
    return StockageTelechargements.personnalise(nas);
  }

  /// Ajoute [nombre] chapitres au titre (numéros 101, 102…) et renvoie-les.
  Future<List<Chapitre>> ajouterChapitres(int nombre) async {
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (var n = 1; n <= nombre; n++)
        Chapitre(
          idTitre: titre.id,
          urlChapitre: 'https://mangadex.org/chapter/supplement-$n',
          nom: 'Chapitre ${100 + n}',
          numero: (100 + n).toDouble(),
          langue: 'fr',
        ),
    ]);
    final tous = await depotChapitres.chargerChapitres(titre.id!);
    return tous.where((c) => c.numero > 100).toList();
  }

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
      final service = creerService(await stockageNas(nas));
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
      final service = creerService(await stockageNas(nas));
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
      final apres = await demarrerStockage();
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
      // Un chapitre à la fois : le second ne doit pas être commencé avant
      // la pause (le cas de plusieurs chapitres en cours est testé dans
      // service_telechargement_parallele_test.dart).
      await parametres.enregistrerTelechargementsSimultanes(1);
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

  group('aucune suppression pendant un déplacement', () {
    test('les suppressions échues attendent tant qu\'un déplacement est '
        'inachevé', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final premier = await chapitre(1);
      final nomArchive = await ecrireArchive(stockage, premier);
      await depotChapitres.planifierSuppression(
        premier.id!,
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
        p.join(temporaire.path, 'nas'),
      );
      final service = creerService(stockage);

      expect(await service.supprimerArchivesEchues(), 0);
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isTrue);
      expect(relu.dateSuppressionPrevue, isNotNull);
      expect(await File(cheminArchive(ancien, nomArchive)).exists(), isTrue);
    });

    test('une suppression manuelle est refusée avec un message clair '
        'pendant un déplacement inachevé ; retirer de la file un chapitre '
        'sans archive reste possible', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final premier = await chapitre(1);
      final nomArchive = await ecrireArchive(stockage, premier);
      final deuxieme = await chapitre(2);
      await depotTelechargements.ajouterEnFile(deuxieme.id!);
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
        p.join(temporaire.path, 'nas'),
      );
      final service = creerService(stockage);

      await expectLater(
        service.supprimerTelechargement(premier.id!),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('en cours de déplacement'),
          ),
        ),
      );
      await expectLater(
        service.supprimerTitre(titre.id!),
        throwsA(isA<ErreurService>()),
      );
      expect((await chapitre(1)).estTelecharge, isTrue);
      expect(await File(cheminArchive(ancien, nomArchive)).exists(), isTrue);

      await service.supprimerTelechargement(deuxieme.id!);
      expect(
        await depotTelechargements.chargerParChapitre(deuxieme.id!),
        isNull,
      );
    });

    test("supprimer toutes les suppressions prévues est refusé avec un "
        "message clair pendant un déplacement inachevé", () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final premier = await chapitre(1);
      final nomArchive = await ecrireArchive(stockage, premier);
      await depotChapitres.planifierSuppression(
        premier.id!,
        DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
        p.join(temporaire.path, 'nas'),
      );
      final service = creerService(stockage);

      await expectLater(
        service.supprimerToutesSuppressionsPrevues(),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('en cours de déplacement'),
          ),
        ),
      );
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isTrue);
      expect(relu.dateSuppressionPrevue, isNotNull);
      expect(await File(cheminArchive(ancien, nomArchive)).exists(), isTrue);
    });

    test("supprimer toutes les suppressions prévues, NAS éteint, ne touche "
        "à rien et l'explique", () async {
      final nas = await preparerNas();
      final stockage = await stockageNas(nas);
      final premier = await chapitre(1);
      final nomArchive = await ecrireArchive(stockage, premier);
      await depotChapitres.planifierSuppression(
        premier.id!,
        DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      final service = creerService(stockage);
      await eteindre(nas);

      await expectLater(
        service.supprimerToutesSuppressionsPrevues(),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            allOf(
              contains("Aucun chapitre n'a été supprimé"),
              contains('inaccessible'),
            ),
          ),
        ),
      );
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isTrue);
      expect(relu.nomArchive, nomArchive);
      expect(relu.dateSuppressionPrevue, isNotNull);

      // Le NAS revient : la suppression se fait.
      await rallumer(nas);
      expect(await service.supprimerToutesSuppressionsPrevues(), 1);
      expect(await File(cheminArchive(nas, nomArchive)).exists(), isFalse);
      expect((await chapitre(1)).estTelecharge, isFalse);
      // Le retour du NAS relance la file (vide ici) : on attend sa fin.
      await service.lancerTraitement();
    });

    test('pendant le changement de dossier lui-même, aucune archive n\'est '
        'supprimée (même sans repère lisible par ce service)', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final premier = await chapitre(1);
      final nomArchive = await ecrireArchive(stockage, premier);
      await depotChapitres.planifierSuppression(
        premier.id!,
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      // Sans dépôt des paramètres : seul le changement en cours (en
      // mémoire) peut protéger l'archive.
      final service = creerService(stockage, avecParametres: false);
      final dossiers = creerDossiers(service);
      final nouveau = p.join(temporaire.path, 'nas');
      final pendant = <Future<Object?>>[];

      await dossiers.changerDossierChapitres(
        nouveau,
        surProgression: (faits, total) {
          if (faits != 0) return;
          pendant
            ..add(
              service
                  .supprimerTelechargement(premier.id!)
                  .then<Object?>((_) => null, onError: (Object e) => e),
            )
            ..add(service.supprimerArchivesEchues());
        },
      );
      final issues = await Future.wait(pendant);

      expect(issues[0], isA<ErreurService>());
      expect(issues[1], 0);
      expect((await chapitre(1)).estTelecharge, isTrue);
      expect(await File(cheminArchive(nouveau, nomArchive)).exists(), isTrue);
    });
  });

  group('file de téléchargement et changement de dossier', () {
    test('une file lancée avant un changement de dossier (tâche de fond) '
        's\'arrête sans échec dès que le réglage ne correspond plus', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final service = creerService(StockageTelechargements(ancien));
      final premier = await chapitre(1);
      await depotTelechargements.ajouterEnFile(premier.id!);
      // L'application a changé le dossier depuis la création de ce service.
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDossierChapitres,
        await preparerNas(),
      );

      await service.lancerTraitement();

      expect(requetes, isEmpty);
      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.enAttente);
      expect(ligne.messageErreur, isNull);
      expect((await chapitre(1)).estTelecharge, isFalse);
    });

    test('retour au dossier par défaut : une file sur le NAS s\'arrête sans '
        'échec', () async {
      final nas = await preparerNas();
      final service = creerService(StockageTelechargements.personnalise(nas));
      final premier = await chapitre(1);
      await depotTelechargements.ajouterEnFile(premier.id!);

      await service.lancerTraitement();

      expect(requetes, isEmpty);
      expect(
        (await depotTelechargements.chargerParChapitre(premier.id!))!.statut,
        StatutTelechargement.enAttente,
      );
    });

    test('un déplacement inachevé arrête la file ; l\'abandonner la '
        'relance', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final service = creerService(StockageTelechargements(ancien));
      final dossiers = creerDossiers(service);
      final premier = await chapitre(1);
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
        p.join(temporaire.path, 'nas'),
      );

      await service.telechargerChapitre(premier.id!);
      await service.lancerTraitement();
      expect(requetes, isEmpty);
      final ligne = await depotTelechargements.chargerParChapitre(premier.id!);
      expect(ligne!.statut, StatutTelechargement.enAttente);
      expect(ligne.messageErreur, isNull);

      await dossiers.abandonnerDeplacementInacheve();
      await service.lancerTraitement();
      expect((await chapitre(1)).estTelecharge, isTrue);
    });
  });

  group('contrôle des archives sur un partage réseau', () {
    test('une archive vue absente une seule fois (partage instable) n\'est '
        'pas remise à « non téléchargé »', () async {
      final nas = await preparerNas();
      final stockage = _StockageInstable(nas);
      final nomArchive = await ecrireArchive(stockage, await chapitre(1));
      final service = creerService(stockage);

      expect(await service.reparerArchivesManquantes(), 0);
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isTrue);
      expect(relu.nomArchive, nomArchive);
      expect(stockage.appels, 2);
    });

    test('plus de 20 archives manquantes d\'affilée sur le NAS arrêtent le '
        'contrôle sans rien remettre à zéro', () async {
      final nas = await preparerNas();
      final stockage = StockageTelechargements.personnalise(nas);
      final supplements = await ajouterChapitres(21);
      for (final supplement in supplements) {
        final nom = await ecrireArchive(stockage, supplement);
        await File(cheminArchive(nas, nom)).delete();
      }
      final service = creerService(stockage);

      expect(await service.reparerArchivesManquantes(), 0);
      for (final supplement in supplements) {
        final relu = await depotChapitres.chargerChapitre(supplement.id!);
        expect(relu!.estTelecharge, isTrue);
      }
    });

    test('des archives manquantes suivies d\'une archive présente sont '
        'bien réparées sur le NAS', () async {
      final nas = await preparerNas();
      final stockage = StockageTelechargements.personnalise(nas);
      final premier = await chapitre(1);
      final deuxieme = await chapitre(2);
      final troisieme = await chapitre(3);
      for (final perdu in <Chapitre>[premier, deuxieme]) {
        final nom = await ecrireArchive(stockage, perdu);
        await File(cheminArchive(nas, nom)).delete();
      }
      await ecrireArchive(stockage, troisieme);
      final service = creerService(stockage);

      expect(await service.reparerArchivesManquantes(), 2);
      expect((await chapitre(1)).estTelecharge, isFalse);
      expect((await chapitre(2)).estTelecharge, isFalse);
      expect((await chapitre(3)).estTelecharge, isTrue);
    });

    test('dans le dossier par défaut, la limite d\'affilée ne s\'applique '
        'pas', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final supplements = await ajouterChapitres(21);
      for (final supplement in supplements) {
        final nom = await ecrireArchive(stockage, supplement);
        await File(cheminArchive(ancien, nom)).delete();
      }
      final service = creerService(stockage);

      expect(await service.reparerArchivesManquantes(), 21);
    });
  });

  group('changement sans déplacement après un déplacement inachevé', () {
    test('l\'avertissement prévient que les chapitres déjà copiés seront '
        'retéléchargés, seulement quand c\'est le cas', () async {
      final service = creerService(
        StockageTelechargements(p.join(temporaire.path, 'ancien')),
      );
      final dossiers = creerDossiers(service);
      final inacheve = p.join(temporaire.path, 'nas');
      final autre = p.join(temporaire.path, 'autre');

      expect(
        await dossiers.avertissementAvantChangement(
          autre,
          deplacerArchives: false,
        ),
        isNull,
      );
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
        inacheve,
      );
      final texte = await dossiers.avertissementAvantChangement(
        autre,
        deplacerArchives: false,
      );
      expect(texte, contains(inacheve));
      expect(texte, contains('ne seront pas utilisés'));
      expect(texte, contains('retéléchargés'));
      expect(
        await dossiers.avertissementAvantChangement(
          autre,
          deplacerArchives: true,
        ),
        isNull,
      );
      expect(
        await dossiers.avertissementAvantChangement(
          inacheve,
          deplacerArchives: false,
        ),
        isNull,
      );

      final resultat = await dossiers.changerDossierChapitres(
        autre,
        deplacerArchives: false,
      );
      expect(resultat.avertissement, texte);
      expect(resultat.message, contains('ne seront pas utilisés'));
      expect(await dossiers.chargerDeplacementInacheve(), isNull);
    });
  });

  group('conflits au déplacement', () {
    test('un fichier différent déjà présent dans le nouveau dossier est '
        'laissé dans l\'ancien et signalé dans le message', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final nomArchive = await ecrireArchive(stockage, await chapitre(1));
      final nouveau = await preparerNas();
      final occupe = File(cheminArchive(nouveau, nomArchive));
      await occupe.parent.create(recursive: true);
      await occupe.writeAsString('autre bibliothèque');
      final dossiers = creerDossiers(creerService(stockage));

      final resultat = await dossiers.changerDossierChapitres(nouveau);

      expect(resultat.cheminsEnConflit, <String>[nomArchive]);
      expect(resultat.message, contains("restés dans l'ancien dossier"));
      expect(resultat.message, contains(nomArchive));
      expect(await File(cheminArchive(ancien, nomArchive)).exists(), isTrue);
      expect(await occupe.readAsString(), 'autre bibliothèque');
    });

    test('les chapitres en conflit sont remis à « non téléchargé » puis '
        'retéléchargés sous un nom libre, sans toucher au fichier '
        'étranger', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      final premier = await chapitre(1);
      final nomConflit = await ecrireArchive(stockage, premier);
      final nomSain = await ecrireArchive(stockage, await chapitre(2));
      final nouveau = await preparerNas();
      final occupe = File(cheminArchive(nouveau, nomConflit));
      await occupe.parent.create(recursive: true);
      await occupe.writeAsString('autre bibliothèque');
      final dossiers = creerDossiers(creerService(stockage));

      final resultat = await dossiers.changerDossierChapitres(nouveau);

      expect(resultat.message, contains('seront retéléchargés'));
      final relu = await chapitre(1);
      expect(relu.estTelecharge, isFalse);
      expect(relu.nomArchive, isNull);
      // Le chapitre sans conflit garde son archive, déplacée.
      expect((await chapitre(2)).nomArchive, nomSain);
      expect(await File(cheminArchive(nouveau, nomSain)).exists(), isTrue);
      // L'original reste dans l'ancien dossier.
      expect(await File(cheminArchive(ancien, nomConflit)).exists(), isTrue);

      // Prochain démarrage : le retéléchargement choisit un nom libre.
      final apres = await demarrerStockage();
      final redemarre = creerService(apres, identifiant: 'redemarre');
      await redemarre.telechargerChapitre(premier.id!);
      await redemarre.lancerTraitement();
      final retelecharge = await chapitre(1);
      expect(retelecharge.estTelecharge, isTrue);
      expect(retelecharge.nomArchive, isNot(nomConflit));
      expect(await occupe.readAsString(), 'autre bibliothèque');
      expect(await redemarre.compterPages(premier.id!), greaterThan(0));
    });

    test('au-delà de 5 conflits, le message n\'en cite que 5', () {
      final conflits = <String>[
        for (var n = 1; n <= 7; n++) 'manga/Titre/ch$n.fr.zip',
      ];
      final resultat = ResultatChangementDossier(
        dossierChoisi: '/mnt/nas',
        cheminDossier: '/mnt/nas',
        bilan: BilanDeplacement(
          nombreFichiers: 7,
          nombreCopies: 0,
          nombreDejaPresents: 0,
          octetsCopies: 0,
          cheminsEnConflit: conflits,
        ),
      );
      expect(resultat.message, contains('7 fichier(s) ne sont pas déplacés'));
      expect(resultat.message, contains('ch5.fr.zip'));
      expect(resultat.message, isNot(contains('ch6.fr.zip')));
      expect(resultat.message, contains('et 2 autre(s)'));
    });
  });

  group("dossier choisi dans l'installateur Windows", () {
    Future<void> appliquer(String? chemin) =>
        ServiceDossierChapitres.appliquerDossierInstallation(
          depotParametres,
          chemin,
          depotChapitres: depotChapitres,
          cheminDossierParDefaut: () async => dossierParDefaut,
        );

    Future<String?> enAttente() => depotParametres.chargerTexte(
      ServiceDossierChapitres.cleDossierInstallationEnAttente,
    );

    /// Un chapitre téléchargé dans le dossier par défaut, comme chez un
    /// client qui utilisait déjà l'application avant l'installateur.
    Future<String> telechargerDansDefaut() async => ecrireArchive(
      StockageTelechargements(dossierParDefaut),
      await chapitre(1),
    );

    Future<String?> reglage() =>
        depotParametres.chargerTexte(ServiceParametres.cleDossierChapitres);

    Future<String?> repere() => depotParametres.chargerTexte(
      ServiceDossierChapitres.cleDossierInstallationApplique,
    );

    test("un dossier valide est enregistré avec son repère et sert au "
        "démarrage", () async {
      final nas = p.join(temporaire.path, 'bibliotheque');

      await appliquer(nas);

      expect(await reglage(), p.normalize(nas));
      expect(await repere(), p.normalize(nas));
      final stockage = await demarrerStockage();
      expect(stockage.estPersonnalise, isTrue);
      expect(stockage.dossierRacine, p.normalize(nas));
    });

    test('sans fichier installation.json (chemin null ou vide), rien '
        "n'est enregistré", () async {
      await appliquer(null);
      await appliquer('   ');

      expect(await reglage(), isNull);
      expect(await repere(), isNull);
    });

    test('un dossier déjà réglé par le client est gardé', () async {
      final choisi = await preparerNas('choisi');
      await depotParametres.enregistrerTexte(
        ServiceParametres.cleDossierChapitres,
        choisi,
      );

      await appliquer(p.join(temporaire.path, 'bibliotheque'));

      expect(await reglage(), choisi);
      expect(await repere(), isNull);
    });

    test('le dossier par défaut (autre casse, séparateur final) ne devient '
        'pas un dossier personnalisé', () async {
      await appliquer('${dossierParDefaut.toUpperCase()}${p.separator}');

      expect(await reglage(), isNull);
      expect(await repere(), isNull);
    });

    test('après un retour au dossier par défaut, le dossier de '
        "l'installateur n'est pas réappliqué au démarrage suivant", () async {
      final nas = p.join(temporaire.path, 'bibliotheque');
      await appliquer(nas);
      // « Revenir au dossier par défaut » efface le réglage.
      await depotParametres.supprimer(ServiceParametres.cleDossierChapitres);

      await appliquer('$nas${p.separator}');

      expect(await reglage(), isNull);
      expect(await repere(), p.normalize(nas));
    });

    test('un dossier refusé (NAS éteint) ne laisse rien, pas même le '
        'repère, et est réessayé au démarrage suivant', () async {
      final nas = p.join(temporaire.path, 'nas');
      // Un fichier à la place du dossier : la validation le refuse.
      await File(nas).writeAsString('pas un dossier');

      await appliquer(nas);
      expect(await reglage(), isNull);
      expect(await repere(), isNull);

      await File(nas).delete();
      await appliquer(nas);
      expect(await reglage(), p.normalize(nas));
      expect(await repere(), p.normalize(nas));
    });

    test('aucun chapitre téléchargé : le dossier est appliqué et rien ne '
        'reste en attente', () async {
      final nas = p.join(temporaire.path, 'bibliotheque');

      await appliquer(nas);

      expect(await reglage(), p.normalize(nas));
      expect(await enAttente(), isNull);
    });

    test('des chapitres déjà téléchargés : rien n\'est appliqué, le dossier '
        'est mis en attente pour le proposer au client', () async {
      final nomArchive = await telechargerDansDefaut();
      final nas = p.join(temporaire.path, 'bibliotheque');

      await appliquer(nas);

      expect(await reglage(), isNull);
      expect(await repere(), isNull);
      expect(await enAttente(), p.normalize(nas));
      // Le démarrage reste sur le dossier par défaut (aucun réglage) : le
      // chapitre est toujours téléchargé et son archive lisible.
      final service = creerService(StockageTelechargements(dossierParDefaut));
      expect(await service.reparerArchivesManquantes(), 0);
      expect((await chapitre(1)).estTelecharge, isTrue);
      expect(
        await File(cheminArchive(dossierParDefaut, nomArchive)).exists(),
        isTrue,
      );
      final dossiers = creerDossiers(service);
      expect(
        await dossiers.chargerDossierInstallationEnAttente(),
        p.normalize(nas),
      );

      // Démarrage suivant sans réponse du client : toujours en attente.
      await appliquer(nas);
      expect(await reglage(), isNull);
      expect(await enAttente(), p.normalize(nas));
    });

    test('sans dépôt des chapitres pour vérifier, le dossier est mis en '
        'attente par prudence', () async {
      final nas = p.join(temporaire.path, 'bibliotheque');

      await ServiceDossierChapitres.appliquerDossierInstallation(
        depotParametres,
        nas,
        cheminDossierParDefaut: () async => dossierParDefaut,
      );

      expect(await reglage(), isNull);
      expect(await enAttente(), p.normalize(nas));
    });

    test('le client refuse : la proposition est effacée et le dossier '
        'n\'est plus jamais appliqué ni proposé', () async {
      await telechargerDansDefaut();
      final nas = p.join(temporaire.path, 'bibliotheque');
      await appliquer(nas);
      final dossiers = creerDossiers(
        creerService(StockageTelechargements(dossierParDefaut)),
      );

      await dossiers.ignorerDossierInstallationEnAttente();

      expect(await dossiers.chargerDossierInstallationEnAttente(), isNull);
      expect(await enAttente(), isNull);
      expect(await repere(), p.normalize(nas));
      // Même si les chapitres sont supprimés ensuite, le dossier refusé
      // n'est pas appliqué au démarrage suivant.
      await depotChapitres.marquerTelecharge(
        (await chapitre(1)).id!,
        estTelecharge: false,
      );
      await appliquer(nas);
      expect(await reglage(), isNull);
      expect(await enAttente(), isNull);
    });

    test('le client accepte : les chapitres sont déplacés, le dossier est '
        'réglé et la proposition est close', () async {
      final nomArchive = await telechargerDansDefaut();
      final nas = p.join(temporaire.path, 'bibliotheque');
      await appliquer(nas);
      final dossiers = creerDossiers(
        creerService(StockageTelechargements(dossierParDefaut)),
      );
      final propose = await dossiers.chargerDossierInstallationEnAttente();

      final resultat = await dossiers.changerDossierChapitres(
        propose,
        deplacerArchives: true,
      );

      expect(resultat.archivesDeplacees, isTrue);
      expect(await reglage(), p.normalize(nas));
      expect(await repere(), p.normalize(nas));
      expect(await enAttente(), isNull);
      expect(await dossiers.chargerDossierInstallationEnAttente(), isNull);
      expect(await File(cheminArchive(nas, nomArchive)).exists(), isTrue);
      // Prochain démarrage : le dossier réglé l'emporte, rien n'est reproposé.
      await appliquer(nas);
      expect(await reglage(), p.normalize(nas));
      expect(await enAttente(), isNull);
    });

    test('un changement de dossier qui échoue garde la proposition en '
        'attente', () async {
      await telechargerDansDefaut();
      final nas = p.join(temporaire.path, 'bibliotheque');
      await appliquer(nas);
      final dossiers = creerDossiers(
        creerService(StockageTelechargements(dossierParDefaut)),
      );

      await expectLater(
        dossiers.changerDossierChapitres(p.join('relatif', 'dossier')),
        throwsA(isA<ErreurService>()),
      );

      expect(
        await dossiers.chargerDossierInstallationEnAttente(),
        p.normalize(nas),
      );
    });

    test('une base illisible ne fait pas échouer le démarrage', () async {
      await expectLater(
        ServiceDossierChapitres.appliquerDossierInstallation(
          _DepotParametresEnPanne(),
          p.join(temporaire.path, 'bibliotheque'),
          cheminDossierParDefaut: () async => dossierParDefaut,
        ),
        completes,
      );
    });
  });

  group('fichier emplacements.json pour le désinstalleur', () {
    test('le démarrage écrit le dossier choisi, en JSON UTF-8 sans BOM, sans '
        'laisser de fichier temporaire', () async {
      final nas = await preparerNas();
      await stockageNas(nas);

      final stockage = await demarrerStockage();

      expect(stockage.dossierRacine, p.normalize(nas));
      final octets = await File(cheminEmplacements).readAsBytes();
      expect(octets.take(3), isNot(<int>[0xEF, 0xBB, 0xBF]));
      expect(
        utf8.decode(octets),
        jsonEncode(<String, String>{'dossierChapitres': p.normalize(nas)}),
      );
      expect(await lireEmplacements(), p.normalize(nas));
      expect(await File('$cheminEmplacements.tmp').exists(), isFalse);
    });

    test('un NAS éteint au démarrage est quand même noté comme dossier des '
        'chapitres', () async {
      final nas = await preparerNas();
      await stockageNas(nas);
      await eteindre(nas);

      await demarrerStockage();

      expect(await lireEmplacements(), p.normalize(nas));
    });

    test('un chemin avec accents, espaces et antislashs est relu tel quel '
        'après décodage JSON', () async {
      final dossier = p.join(temporaire.path, 'Bibliothèque perso', r'a\b');

      await ServiceDossierChapitres.ecrireEmplacements(
        dossier,
        cheminFichierEmplacements: () async => cheminEmplacements,
      );

      expect(await lireEmplacements(), p.normalize(dossier));
    });

    test("l'ancien fichier est remplacé à chaque écriture", () async {
      await ServiceDossierChapitres.ecrireEmplacements(
        p.join(temporaire.path, 'premier'),
        cheminFichierEmplacements: () async => cheminEmplacements,
      );
      await ServiceDossierChapitres.ecrireEmplacements(
        p.join(temporaire.path, 'second'),
        cheminFichierEmplacements: () async => cheminEmplacements,
      );

      expect(await lireEmplacements(), p.join(temporaire.path, 'second'));
    });

    test("un fichier impossible à écrire n'empêche ni le démarrage ni le "
        'changement de dossier', () async {
      // Le dossier parent prévu est un fichier : création impossible.
      final bloquant = File(p.join(temporaire.path, 'appli'));
      await bloquant.writeAsString('pas un dossier');
      final nas = await preparerNas();
      await stockageNas(nas);

      final stockage = await demarrerStockage();
      expect(stockage.dossierRacine, p.normalize(nas));
      await expectLater(
        ServiceDossierChapitres.ecrireEmplacements(
          nas,
          cheminFichierEmplacements: () async =>
              throw StateError('path_provider absent'),
        ),
        completes,
      );

      final dossiers = creerDossiers(creerService(stockage));
      final resultat = await dossiers.changerDossierChapitres(
        null,
        deplacerArchives: false,
      );
      expect(resultat.dossierChoisi, isNull);
      expect(await dossiers.chargerDossierChoisi(), isNull);
      expect(await bloquant.readAsString(), 'pas un dossier');
    });

    test("sans chemin (Android), aucun fichier n'est écrit", () async {
      await ServiceDossierChapitres.ecrireEmplacements(
        p.join(temporaire.path, 'chapitres'),
        cheminFichierEmplacements: () async => null,
      );

      expect(await Directory(p.dirname(cheminEmplacements)).exists(), isFalse);
    });

    test('un changement réussi note le nouveau dossier, avec ou sans '
        'déplacement des archives', () async {
      final ancien = p.join(temporaire.path, 'ancien');
      final stockage = StockageTelechargements(ancien);
      await ecrireArchive(stockage, await chapitre(1));
      final nouveau = p.join(temporaire.path, 'nouveau');

      final dossiers = creerDossiers(creerService(stockage));
      await dossiers.changerDossierChapitres(nouveau);

      expect(await lireEmplacements(), p.normalize(nouveau));

      // Sans déplacement (nouvelle session) : même règle.
      final autre = p.join(temporaire.path, 'autre');
      final suivants = creerDossiers(
        creerService(StockageTelechargements(ancien), identifiant: 'suivant'),
      );
      await suivants.changerDossierChapitres(autre, deplacerArchives: false);

      expect(await lireEmplacements(), p.normalize(autre));
    });

    test(
      'le retour au dossier par défaut note le dossier par défaut',
      () async {
        final nas = await preparerNas();
        final dossiers = creerDossiers(creerService(await stockageNas(nas)));

        await dossiers.changerDossierChapitres(null, deplacerArchives: false);

        expect(await lireEmplacements(), p.normalize(dossierParDefaut));
      },
    );

    test("un changement refusé ne modifie pas le fichier", () async {
      final nas = await preparerNas();
      final stockage = await stockageNas(nas);
      await demarrerStockage();
      final dossiers = creerDossiers(creerService(stockage));

      await expectLater(
        dossiers.changerDossierChapitres(p.join('relatif', 'dossier')),
        throwsA(isA<ErreurService>()),
      );

      expect(await lireEmplacements(), p.normalize(nas));
    });

    test("le dossier de l'installateur appliqué au premier démarrage est "
        'celui noté dans le fichier', () async {
      final nas = p.join(temporaire.path, 'bibliotheque');
      await ServiceDossierChapitres.appliquerDossierInstallation(
        depotParametres,
        nas,
        depotChapitres: depotChapitres,
        cheminDossierParDefaut: () async => dossierParDefaut,
      );

      await demarrerStockage();

      expect(await lireEmplacements(), p.normalize(nas));
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

/// Dépôt des paramètres dont toute lecture échoue (base illisible).
class _DepotParametresEnPanne implements DepotParametres {
  // Toute méthode (chargerTexte, enregistrerTexte…) renvoie une erreur.
  @override
  Object? noSuchMethod(Invocation invocation) =>
      Future<String?>.error(StateError('base illisible'));
}

/// Partage réseau instable : chaque archive est vue absente au premier
/// contrôle, puis présente au second.
class _StockageInstable extends StockageTelechargements {
  _StockageInstable(super.dossierRacine) : super.personnalise();

  /// Nombre d'appels à [estTelecharge].
  int appels = 0;

  @override
  Future<bool> estTelecharge(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    appels++;
    if (appels.isOdd) return false;
    return super.estTelecharge(titre, chapitre, nomSource: nomSource);
  }
}
