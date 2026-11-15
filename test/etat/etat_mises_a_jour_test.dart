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

  test('intervalle bureau : 6 heures', () {
    expect(intervalleMisesAJourBureau, const Duration(hours: 6));
  });

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
    final etat = EtatMisesAJour(service, verifierAuDemarrage: true);
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

    expect(etats, <bool>[true, false]);
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
    final etat = EtatMisesAJour(service, verifierAuDemarrage: true)..demarrer();
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
    final etat = EtatMisesAJour(service, verifierAuDemarrage: true)..demarrer();
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

  testWidgets('minuterie périodique puis annulation au dispose', (
    tester,
  ) async {
    const intervalle = Duration(hours: 1);
    final etat = EtatMisesAJour(service, intervalle: intervalle)..demarrer();

    await tester.pump(intervalle - const Duration(minutes: 1));
    expect(service.nombreAppels, 0);

    await tester.pump(const Duration(minutes: 1));
    expect(service.nombreAppels, 1);
    expect(etat.dernierRapport, isNotNull);
    expect(etat.finVerification.value!.estManuelle, isFalse);

    await tester.pump(intervalle);
    expect(service.nombreAppels, 2);

    etat.dispose();
    await tester.pump(intervalle * 3);
    // Aucune vérification après dispose ; testWidgets échouerait aussi si
    // un Timer restait en attente.
    expect(service.nombreAppels, 2);
  });

  testWidgets('vérification au démarrage et minuterie combinées', (
    tester,
  ) async {
    final etat = EtatMisesAJour(
      service,
      verifierAuDemarrage: true,
      intervalle: intervalleMisesAJourBureau,
    )..demarrer();
    await tester.pump();
    expect(service.nombreAppels, 1);

    await tester.pump(intervalleMisesAJourBureau);
    expect(service.nombreAppels, 2);

    etat.dispose();
  });
}
