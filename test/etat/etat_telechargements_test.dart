// Tests de EtatTelechargements avec de faux services (aucune base, aucun
// réseau).
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceTelechargement service;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    service = FauxServiceTelechargement(bibliotheque);
    bibliotheque.ajouterTitreDeTest(
      'Titre A',
      chapitres: const <Chapitre>[
        Chapitre(id: 10, urlChapitre: 'https://a/10', nom: 'Dix', numero: 10),
        Chapitre(id: 11, urlChapitre: 'https://a/11', nom: '', numero: 11),
      ],
    );
    bibliotheque.ajouterTitreDeTest(
      'Titre B',
      chapitres: const <Chapitre>[
        Chapitre(id: 20, urlChapitre: 'https://b/20', nom: 'Vingt', numero: 1),
      ],
    );
  });

  test('file vide : état vide après chargement', () async {
    final etat = EtatTelechargements(service, bibliotheque);
    addTearDown(etat.dispose);
    expect(etat.estCharge, isFalse);
    await etat.charger();

    expect(etat.estVide, isTrue);
    expect(etat.nombreActifs, 0);
  });

  test('associe chaque ligne à son chapitre et à son titre', () async {
    service
      ..modifierLigne(20, StatutTelechargement.enCours, faites: 2, total: 8)
      ..modifierLigne(10, StatutTelechargement.enAttente)
      ..modifierLigne(
        11,
        StatutTelechargement.echec,
        messageErreur: 'HTTP 404',
      );
    final etat = EtatTelechargements(service, bibliotheque);
    addTearDown(etat.dispose);
    await etat.charger();

    expect(etat.elements.map((e) => e.idChapitre), <int>[20, 10, 11]);
    expect(etat.elements[0].titre!.nom, 'Titre B');
    expect(etat.elements[0].chapitre!.nom, 'Vingt');
    expect(etat.elements[0].telechargement.progression, 0.25);
    expect(etat.elements[2].telechargement.messageErreur, 'HTTP 404');
    expect(etat.nombreActifs, 2);
    expect(etat.nombreEchecs, 1);
  });

  test('suit les changements de la file en direct', () async {
    final etat = EtatTelechargements(service, bibliotheque);
    addTearDown(etat.dispose);
    await etat.charger();
    var notifications = 0;
    etat.addListener(() => notifications++);

    service.modifierLigne(
      10,
      StatutTelechargement.enCours,
      faites: 1,
      total: 4,
    );
    await pumpEventQueue();
    expect(etat.elements.single.telechargement.nombrePagesFaites, 1);

    service.modifierLigne(
      10,
      StatutTelechargement.enCours,
      faites: 4,
      total: 4,
    );
    await pumpEventQueue();
    expect(etat.elements.single.telechargement.progression, 1);
    expect(notifications, greaterThan(0));
  });

  test('un chapitre disparu est affiché sans planter', () async {
    service.modifierLigne(999, StatutTelechargement.enAttente);
    final etat = EtatTelechargements(service, bibliotheque);
    addTearDown(etat.dispose);
    await etat.charger();

    expect(etat.elements.single.chapitre, isNull);
    expect(etat.elements.single.titre, isNull);
  });

  test('réessayer, supprimer, vider les terminés', () async {
    service
      ..modifierLigne(10, StatutTelechargement.echec, messageErreur: 'panne')
      ..modifierLigne(11, StatutTelechargement.termine)
      ..modifierLigne(20, StatutTelechargement.enAttente);
    final etat = EtatTelechargements(service, bibliotheque);
    addTearDown(etat.dispose);
    await etat.charger();

    expect((await etat.reessayer(10)).estReussi, isTrue);
    expect(
      etat.elements.firstWhere((e) => e.idChapitre == 10).statut,
      StatutTelechargement.enAttente,
    );

    expect((await etat.supprimer(20)).estReussi, isTrue);
    expect(etat.elements.map((e) => e.idChapitre), isNot(contains(20)));

    final vidage = await etat.viderTermines();
    expect(vidage.donnee, 1);
    expect(etat.elements.map((e) => e.idChapitre), <int>[10]);
  });

  test('une erreur de lecture est exposée', () async {
    service.erreurFile = const ErreurService('File illisible.');
    final etat = EtatTelechargements(service, bibliotheque);
    addTearDown(etat.dispose);
    await etat.charger();

    expect(etat.erreur!.nature, NatureErreur.refus);
    expect(etat.estCharge, isFalse);
  });

  test('se désabonne au dispose', () async {
    final etat = EtatTelechargements(service, bibliotheque);
    await etat.charger();
    etat.dispose();
    // Un changement après dispose ne doit rien lever.
    service.modifierLigne(10, StatutTelechargement.enAttente);
    await pumpEventQueue();
    expect(etat.estLibere, isTrue);
  });
}
