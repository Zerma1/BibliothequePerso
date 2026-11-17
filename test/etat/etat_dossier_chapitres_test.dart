// Tests de EtatDossierChapitres : lecture des réglages, accès au dossier,
// changement avec progression, refus « chapitre en cours », déplacement
// inachevé.
import 'dart:async';

import 'package:bibliotheque_perso/donnees/erreur_stockage.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_dossier_chapitres.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  late FauxServiceDossierChapitres service;
  late EtatDossierChapitres etat;

  setUp(() {
    service = FauxServiceDossierChapitres();
    etat = EtatDossierChapitres(service);
  });

  tearDown(() => etat.dispose());

  test('charger lit le dossier choisi, le défaut et le déplacement '
      'inachevé', () async {
    service
      ..dossierChoisi = r'Z:\Mangas'
      ..deplacementInacheve = r'Z:\Mangas';
    await etat.charger();

    expect(etat.estCharge, isTrue);
    expect(etat.erreur, isNull);
    expect(etat.dossierChoisi, r'Z:\Mangas');
    expect(etat.cheminParDefaut, r'C:\appli\telechargements');
    expect(etat.deplacementInacheve, r'Z:\Mangas');
    expect(etat.dossierAuProchainDemarrage, isNull);
  });

  test('une erreur de lecture devient une erreur affichable', () async {
    service.erreurLecture = const ErreurBaseDeDonnees('base verrouillée');
    await etat.charger();

    expect(etat.estCharge, isFalse);
    expect(etat.erreur?.nature, NatureErreur.baseDeDonnees);
  });

  test('les changements du service notifient l\'état', () async {
    var notifications = 0;
    etat.addListener(() => notifications++);
    service.signaler();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);
  });

  test('verifierAcces relit l\'accès et fusionne deux appels '
      'rapprochés', () async {
    final retenue = Completer<void>();
    service
      ..retenueVerification = retenue
      ..accesApresVerification = const AccesDossierChapitres.inaccessible(
        r'\\nas\partage',
        estPersonnalise: true,
        nature: NatureErreurStockage.reseauIndisponible,
      );
    final premier = etat.verifierAcces();
    final second = etat.verifierAcces();
    expect(etat.estEnVerification, isTrue);
    retenue.complete();
    final acces = await premier;
    await second;

    expect(service.nombreVerifications, 1);
    expect(acces.estAccessible, isFalse);
    expect(etat.accesDossier.estAccessible, isFalse);
    expect(etat.accesDossier.message, contains(r'\\nas\partage'));
    expect(etat.estEnVerification, isFalse);
  });

  test('changerDossier expose la progression puis le résultat', () async {
    final retenue = Completer<void>();
    service
      ..retenueDeplacement = retenue
      ..nombreFichiers = 4;
    await etat.charger();
    final changement = etat.changerDossier(r'Z:\Mangas');
    await Future<void>.delayed(Duration.zero);

    expect(etat.estEnChangement, isTrue);
    expect(etat.faits, 1);
    expect(etat.total, 4);
    expect(etat.progression, 0.25);

    retenue.complete();
    final resultat = await changement;
    await Future<void>.delayed(Duration.zero);

    expect(resultat.estReussi, isTrue);
    expect(resultat.donnee?.cheminDossier, r'Z:\Mangas');
    expect(resultat.donnee?.archivesDeplacees, isTrue);
    expect(service.demandes.single, (dossier: r'Z:\Mangas', deplacer: true));
    expect(etat.estEnChangement, isFalse);
    expect(etat.redemarrageNecessaire, isTrue);
    expect(etat.peutReprendreFile, isFalse);
    // Réglages relus : le dossier du prochain démarrage est connu.
    expect(etat.dossierChoisi, r'Z:\Mangas');
    expect(etat.dossierAuProchainDemarrage, r'Z:\Mangas');
  });

  test('sans déplacement, aucune progression n\'est annoncée', () async {
    final resultat = await etat.changerDossier(
      r'D:\Mangas',
      deplacerArchives: false,
    );

    expect(resultat.donnee?.archivesDeplacees, isFalse);
    expect(service.demandes.single.deplacer, isFalse);
    expect(etat.total, 0);
    expect(etat.progression, isNull);
  });

  test('un refus du service garde son message tel quel', () async {
    service.erreurChangement = const ErreurService(
      "C'est déjà le dossier des chapitres.",
    );
    final resultat = await etat.changerDossier(r'C:\appli\telechargements');

    expect(resultat.estReussi, isFalse);
    expect(resultat.erreur?.nature, NatureErreur.refus);
    expect(resultat.erreur?.detail, "C'est déjà le dossier des chapitres.");
    expect(etat.redemarrageNecessaire, isFalse);
  });

  test('refus « chapitre en cours » : la file reste en pause jusqu\'à '
      'reprendreFile', () async {
    service.chapitreEnCours = true;
    final resultat = await etat.changerDossier(r'Z:\Mangas');

    expect(resultat.estReussi, isFalse);
    expect(etat.peutReprendreFile, isTrue);

    etat.reprendreFile();

    expect(service.nombreReprises, 1);
    expect(etat.peutReprendreFile, isFalse);
    expect(etat.estFileEnPause, isFalse);
  });

  test('un second changement pendant le premier est refusé', () async {
    final retenue = Completer<void>();
    service.retenueDeplacement = retenue;
    final premier = etat.changerDossier(r'Z:\Mangas');
    final second = await etat.changerDossier(r'Y:\Mangas');
    retenue.complete();
    await premier;

    expect(second.estReussi, isFalse);
    expect(second.erreur?.nature, NatureErreur.refus);
    expect(service.demandes, hasLength(1));
  });

  group('avertissementAvantChangement', () {
    test('rien à signaler sans déplacement inachevé', () async {
      final resultat = await etat.avertissementAvantChangement(
        r'Z:\Mangas',
        deplacerArchives: false,
      );

      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee, isNull);
    });

    test('signale l\'abandon d\'un déplacement inachevé sans '
        'déplacement', () async {
      service.deplacementInacheve = r'Y:\Ancien';
      final resultat = await etat.avertissementAvantChangement(
        r'Z:\Mangas',
        deplacerArchives: false,
      );

      expect(resultat.donnee, contains(r'Y:\Ancien'));
      // Ne modifie rien.
      expect(service.demandes, isEmpty);
      expect(service.deplacementInacheve, r'Y:\Ancien');
    });

    test('rien à signaler avec déplacement', () async {
      service.deplacementInacheve = r'Y:\Ancien';
      final resultat = await etat.avertissementAvantChangement(
        r'Z:\Mangas',
        deplacerArchives: true,
      );

      expect(resultat.donnee, isNull);
    });

    test('une erreur de lecture devient l\'erreur du résultat', () async {
      service.erreurLecture = const ErreurBaseDeDonnees('base verrouillée');
      final resultat = await etat.avertissementAvantChangement(
        r'Z:\Mangas',
        deplacerArchives: false,
      );

      expect(resultat.estReussi, isFalse);
      expect(resultat.erreur?.nature, NatureErreur.baseDeDonnees);
    });
  });

  test('abandonner le déplacement inachevé l\'oublie', () async {
    service.deplacementInacheve = r'Z:\Mangas';
    await etat.charger();

    final resultat = await etat.abandonnerDeplacementInacheve();

    expect(resultat.estReussi, isTrue);
    expect(service.nombreAbandons, 1);
    expect(etat.deplacementInacheve, isNull);
  });
}
