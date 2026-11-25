// Tests de EtatMisesAJour avec un faux ServiceMisesAJour (aucune base, aucun
// réseau). Les tests de minuterie utilisent testWidgets : le temps y est
// simulé et `tester.pump(durée)` fait avancer les Timer sans attendre.
import 'dart:async';

import 'package:bibliotheque_perso/etat/constantes_etat.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_mises_a_jour.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_mises_a_jour.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

/// Titre de test rattaché au site [idSource].
Titre _titre(String nom, int idSource) => Titre(
  id: nom.hashCode,
  idSource: idSource,
  urlTitre: 'https://site$idSource.test/$nom',
  nom: nom,
);

void main() {
  late FauxServiceMisesAJour service;

  setUp(() => service = FauxServiceMisesAJour());

  test('sans option, demarrer ne lance rien', () async {
    final etat = EtatMisesAJour(service)..demarrer();
    addTearDown(etat.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(service.nombreAppels, 0);
    expect(etat.estEnCours, isFalse);
    expect(etat.dernierRapport, isNull);
  });

  test('vérifie au démarrage et publie le bilan (automatique)', () async {
    service.resultats = <ResultatVerificationTitre>[
      ResultatVerificationTitre(
        titre: _titre('A', 1),
        nombreNouveauxChapitres: 2,
      ),
    ];
    service.retenue = Completer<void>();
    final etat = EtatMisesAJour(service, planifier: true);
    addTearDown(etat.dispose);
    final etats = <bool>[];
    etat.addListener(() => etats.add(etat.estEnCours));

    etat.demarrer();
    // La vérification démarre au tour suivant de la boucle d'événements.
    expect(etat.estEnCours, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(service.nombreAppels, 1);

    service.retenue!.complete();
    await Future<void>.delayed(Duration.zero);

    // La programmation du minuteur notifie aussi (prochaine échéance) : on
    // vérifie le début et la fin de la vérification.
    expect(etats.first, isTrue);
    expect(etats.last, isFalse);
    expect(etat.estEnCours, isFalse);
    expect(etat.erreur, isNull);
    expect(etat.dernierRapport!.nombreNouveauxChapitres, 2);
    expect(etat.dateDerniereVerification, DateTime.utc(2026, 11, 15, 12));
    final fin = etat.finVerification.value!;
    expect(fin.estManuelle, isFalse);
    expect(fin.aDesNouveautes, isTrue);
    expect(fin.nombreTitresAvecNouveautes, 1);

    // Un second appel à demarrer ne relance rien.
    etat.demarrer();
    await Future<void>.delayed(Duration.zero);
    expect(service.nombreAppels, 1);
  });

  test('un clic pendant une vérification automatique ne la relance pas et '
      'rend le bilan « manuel »', () async {
    service.retenue = Completer<void>();
    final etat = EtatMisesAJour(service, planifier: true)..demarrer();
    addTearDown(etat.dispose);

    final clic = etat.verifierMaintenant();
    service.retenue!.complete();
    await clic;

    expect(service.nombreAppels, 1);
    expect(etat.finVerification.value!.estManuelle, isTrue);

    // Le clic suivant relance bien une vérification.
    await etat.verifierMaintenant();
    expect(service.nombreAppels, 2);
  });

  test(
    'une panne générale est exposée sans perdre le dernier rapport',
    () async {
      final etat = EtatMisesAJour(service);
      addTearDown(etat.dispose);
      await etat.verifierMaintenant();
      final premierRapport = etat.dernierRapport;
      expect(premierRapport, isNotNull);

      service.erreur = const ErreurSource('https://site.test', 'Panne');
      await etat.verifierMaintenant();

      expect(etat.erreur!.nature, NatureErreur.site);
      expect(etat.dernierRapport, same(premierRapport));
      final fin = etat.finVerification.value!;
      expect(fin.erreur, isNotNull);
      expect(fin.rapport, isNull);
      expect(fin.aDesNouveautes, isFalse);

      // L'erreur disparaît à la vérification suivante réussie.
      service.erreur = null;
      await etat.verifierMaintenant();
      expect(etat.erreur, isNull);
    },
  );

  test('compte les sites en échec une seule fois chacun', () async {
    service.resultats = <ResultatVerificationTitre>[
      ResultatVerificationTitre(
        titre: _titre('A', 1),
        nombreNouveauxChapitres: 3,
      ),
      ResultatVerificationTitre(
        titre: _titre('B', 1),
        nombreNouveauxChapitres: 1,
      ),
      ResultatVerificationTitre(
        titre: _titre('C', 2),
        erreur: const ErreurSource('https://site2.test', 'panne'),
      ),
      ResultatVerificationTitre(
        titre: _titre('D', 2),
        erreur: const ErreurSource('https://site2.test', 'panne'),
      ),
      ResultatVerificationTitre(
        titre: _titre('E', 3),
        erreur: const ErreurSource('https://site3.test', 'panne'),
      ),
      // Erreur qui ne vient pas d'un site : comptée à part.
      ResultatVerificationTitre(titre: _titre('F', 4), erreur: 'base occupée'),
    ];
    final etat = EtatMisesAJour(service);
    addTearDown(etat.dispose);
    await etat.verifierMaintenant();

    final fin = etat.finVerification.value!;
    expect(fin.nombreNouveauxChapitres, 4);
    expect(fin.nombreTitresAvecNouveautes, 2);
    expect(fin.nombreSitesEnEchec, 2);
    expect(fin.nombreAutresEchecs, 1);
  });

  test('aucune notification après dispose', () async {
    service.retenue = Completer<void>();
    final etat = EtatMisesAJour(service, planifier: true)..demarrer();
    var notifications = 0;
    etat.addListener(() => notifications++);

    etat.dispose();
    service.retenue!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 0);
    expect(etat.dernierRapport, isNull);
    // Une demande après dispose ne touche plus au service.
    await etat.verifierMaintenant();
    expect(service.nombreAppels, 1);
  });

  testWidgets(
    'minuteur jusqu\'à la prochaine échéance, reprogrammé, annulé au dispose',
    (tester) async {
      var heure = DateTime.utc(2026, 11, 15, 11);
      // Rien n'est dû au démarrage : la vérification de 00:00 a déjà eu lieu.
      service.echeancePassee = false;
      final etat = EtatMisesAJour(
        service,
        planifier: true,
        maintenant: () => heure,
      )..demarrer();
      await tester.pump();

      expect(service.nombreControlesEcheance, 1);
      expect(service.nombreAppels, 0);
      expect(etat.finVerification.value, isNull);
      // 2 par jour par défaut : 00:00 et 12:00 UTC.
      expect(etat.prochaineEcheance, DateTime.utc(2026, 11, 15, 12));

      service.echeancePassee = true;
      // L'heure simulée n'avance pas toute seule : elle reste avant
      // l'échéance pendant que le temps passe, puis l'atteint.
      await tester.pump(const Duration(minutes: 59));
      expect(service.nombreControlesEcheance, 1);
      heure = DateTime.utc(2026, 11, 15, 12);
      await tester.pump(const Duration(minutes: 1));
      expect(service.nombreControlesEcheance, 2);
      expect(service.nombreAppels, 1);
      expect(etat.finVerification.value!.estManuelle, isFalse);
      expect(etat.prochaineEcheance, DateTime.utc(2026, 11, 16));

      await tester.pump(const Duration(hours: 11, minutes: 59));
      expect(service.nombreControlesEcheance, 2);
      heure = DateTime.utc(2026, 11, 16);
      await tester.pump(const Duration(minutes: 1));
      expect(service.nombreControlesEcheance, 3);

      etat.dispose();
      await tester.pump(const Duration(days: 2));
      // Aucune vérification après dispose ; testWidgets échouerait aussi si
      // un Timer restait en attente.
      expect(service.nombreControlesEcheance, 3);
    },
  );

  testWidgets(
    "veille : l'échéance passée pendant la veille est rattrapée par le "
    "contrôle régulier, sans attendre le minuteur",
    (tester) async {
      var heure = DateTime.utc(2026, 11, 15, 11);
      service.echeancePassee = false;
      final etat = EtatMisesAJour(
        service,
        planifier: true,
        maintenant: () => heure,
      )..demarrer();
      addTearDown(etat.dispose);
      await tester.pump();
      expect(service.nombreControlesEcheance, 1);

      // Contrôle avant l'échéance : la base n'est pas sollicitée.
      await tester.pump(intervalleControleEcheance);
      expect(service.nombreControlesEcheance, 1);

      // L'ordinateur dort de 11:15 à 14:00 : l'horloge réelle avance, pas
      // le minuteur (qui attendrait encore 45 min).
      service.echeancePassee = true;
      heure = DateTime.utc(2026, 11, 15, 14);
      await tester.pump(intervalleControleEcheance);
      expect(service.nombreControlesEcheance, 2);
      expect(service.nombreAppels, 1);
      expect(etat.prochaineEcheance, DateTime.utc(2026, 11, 16));
    },
  );

  testWidgets('controlerEcheance (retour au premier plan) ne fait rien '
      'avant l\'échéance et vérifie après', (tester) async {
    var heure = DateTime.utc(2026, 11, 15, 11);
    service.echeancePassee = false;
    final etat = EtatMisesAJour(
      service,
      planifier: true,
      maintenant: () => heure,
    )..demarrer();
    addTearDown(etat.dispose);
    await tester.pump();

    etat.controlerEcheance();
    await tester.pump();
    expect(service.nombreControlesEcheance, 1);

    heure = DateTime.utc(2026, 11, 15, 13);
    etat.controlerEcheance();
    await tester.pump();
    expect(service.nombreControlesEcheance, 2);
  });

  test('controlerEcheance est sans effet sans planification', () async {
    final etat = EtatMisesAJour(service)..demarrer();
    addTearDown(etat.dispose);
    etat.controlerEcheance();
    await Future<void>.delayed(Duration.zero);
    expect(service.nombreControlesEcheance, 0);
  });

  testWidgets('replanifier recale le minuteur sur le nouveau réglage', (
    tester,
  ) async {
    final heure = DateTime.utc(2026, 11, 15, 1);
    final parametres = FauxServiceParametres();
    final planificationsRecues = <int>[];
    service
      ..echeancePassee = false
      // Le service calcule la prochaine échéance à partir des réglages.
      ..parametres = parametres;
    final etat = EtatMisesAJour(
      service,
      planifier: true,
      serviceParametres: parametres,
      maintenant: () => heure,
      surChangementPlanification: (planification) async =>
          planificationsRecues.add(planification.verificationsParJour),
    )..demarrer();
    await tester.pump();
    expect(etat.prochaineEcheance, DateTime.utc(2026, 11, 15, 12));

    parametres.verificationsParJour = 24;
    await etat.replanifier();
    expect(etat.prochaineEcheance, DateTime.utc(2026, 11, 15, 2));
    expect(planificationsRecues, <int>[24]);

    // L'ancien minuteur (12:00) est annulé : seul celui de 02:00 compte.
    await tester.pump(const Duration(hours: 1));
    expect(service.nombreControlesEcheance, 2);

    etat.dispose();
  });

  test('sans planification (Android), aucun contrôle automatique ; '
      'replanifier prévient seulement la tâche de fond', () async {
    final recues = <int>[];
    final etat = EtatMisesAJour(
      service,
      surChangementPlanification: (planification) async =>
          recues.add(planification.verificationsParJour),
    )..demarrer();
    addTearDown(etat.dispose);
    await etat.replanifier();

    expect(service.nombreControlesEcheance, 0);
    expect(etat.prochaineEcheance, isNull);
    expect(recues, <int>[2]);
  });

  test(
    'un clic pendant un contrôle sans échéance due vérifie quand même',
    () async {
      service.echeancePassee = false;
      final etat = EtatMisesAJour(service, planifier: true)..demarrer();
      addTearDown(etat.dispose);
      await etat.verifierMaintenant();

      expect(service.nombreAppels, 1);
      expect(etat.finVerification.value!.estManuelle, isTrue);
    },
  );

  test(
    'après chaque vérification, les règles de téléchargement sont appliquées',
    () async {
      service.resultats = <ResultatVerificationTitre>[
        ResultatVerificationTitre(
          titre: _titre('A', 1),
          nombreNouveauxChapitres: 1,
        ),
      ];
      final telechargement = FauxServiceTelechargement(
        FauxServiceBibliotheque(),
      );
      final etat = EtatMisesAJour(
        service,
        serviceTelechargement: telechargement,
      );
      addTearDown(etat.dispose);
      await etat.verifierMaintenant();
      expect(telechargement.nombreAppelsReglesATous, 1);

      // Sans nouveauté aussi (demande du client) : les règles sont
      // réappliquées, pour retenter les chapitres en échec.
      service.resultats = <ResultatVerificationTitre>[];
      await etat.verifierMaintenant();
      expect(telechargement.nombreAppelsReglesATous, 2);
    },
  );
}
