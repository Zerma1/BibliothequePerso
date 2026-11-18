// Tests de EtatJournal (section « Journal » des paramètres).
import 'dart:async';

import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_journal.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  late FauxServiceJournal service;

  setUp(() {
    service = FauxServiceJournal();
  });

  test(
    'charger lit les fichiers (le plus récent d\'abord) et le réglage',
    () async {
      service.detaille = true;
      final etat = EtatJournal(
        service,
        mesurerTaille: (chemin) async => chemin.length * 100,
      );
      expect(etat.estCharge, isFalse);

      await etat.charger();

      expect(etat.estCharge, isTrue);
      expect(etat.estEnChargement, isFalse);
      expect(etat.erreur, isNull);
      expect(etat.journalDetaille, isTrue);
      expect(etat.fichiers.map((l) => l.jour), <DateTime>[
        DateTime(2026, 11, 18),
        DateTime(2026, 11, 17),
      ]);
      expect(etat.fichiers.first.nom, 'journal-2026-11-18.log');
      expect(
        etat.fichiers.first.taille,
        'C:/journaux/journal-2026-11-18.log'.length * 100,
      );
      expect(etat.dossierJournaux, 'C:/journaux');
    },
  );

  test(
    'sans mesure de taille, ou si elle échoue, la taille est absente',
    () async {
      final sansMesure = EtatJournal(service);
      await sansMesure.charger();
      expect(sansMesure.fichiers.every((l) => l.taille == null), isTrue);

      final enPanne = EtatJournal(
        service,
        mesurerTaille: (_) async => throw StateError('fichier effacé'),
      );
      await enPanne.charger();
      expect(enPanne.fichiers, hasLength(2));
      expect(enPanne.fichiers.every((l) => l.taille == null), isTrue);
    },
  );

  test('aucun fichier : liste vide, état chargé', () async {
    service.fichiers = [];
    final etat = EtatJournal(service);
    await etat.charger();
    expect(etat.estCharge, isTrue);
    expect(etat.fichiers, isEmpty);
  });

  test('exporter renvoie le chemin et relit la liste', () async {
    final etat = EtatJournal(service);
    await etat.charger();
    final listesAvant = service.nombreListes;

    final resultat = await etat.exporter(jours: EtatJournal.joursExportSemaine);

    expect(resultat.estReussi, isTrue);
    expect(resultat.donnee, 'C:/rapports/journal_export_1.log');
    expect(service.joursExportes, <int>[7]);
    expect(service.nombreListes, listesAvant + 1);
    expect(etat.estEnExport, isFalse);
  });

  test('par défaut, exporter copie le journal du jour', () async {
    final etat = EtatJournal(service);
    await etat.exporter();
    expect(service.joursExportes, <int>[EtatJournal.joursExportJour]);
    expect(EtatJournal.joursExportJour, 1);
  });

  test('un journal vide (ErreurService) devient un refus lisible', () async {
    service.erreurExport = const ErreurService('Le journal est vide.');
    final etat = EtatJournal(service);

    final resultat = await etat.exporter();

    expect(resultat.estReussi, isFalse);
    expect(resultat.erreur!.nature, NatureErreur.refus);
    expect(resultat.erreur!.detail, 'Le journal est vide.');
    expect(etat.estEnExport, isFalse);
  });

  test('pendant un export, les boutons savent lequel est en cours et un '
      'second export est refusé', () async {
    final retenue = Completer<void>();
    service.retenue = retenue;
    final etat = EtatJournal(service);

    final premier = etat.exporter(jours: 7);
    expect(etat.estEnExport, isTrue);
    expect(etat.joursEnExport, 7);
    final second = await etat.exporter();
    expect(second.estReussi, isFalse);
    expect(service.joursExportes, <int>[7]);

    retenue.complete();
    expect((await premier).estReussi, isTrue);
    expect(etat.joursEnExport, isNull);
  });

  test('modifierJournalDetaille enregistre le réglage', () async {
    final etat = EtatJournal(service);
    await etat.charger();
    var notifications = 0;
    etat.addListener(() => notifications++);

    final resultat = await etat.modifierJournalDetaille(true);

    expect(resultat.estReussi, isTrue);
    expect(service.detaille, isTrue);
    expect(etat.journalDetaille, isTrue);
    expect(etat.estEnEnregistrementReglage, isFalse);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('un réglage non enregistré renvoie l\'erreur mais l\'interrupteur '
      'garde la valeur demandée (appliquée pour la session)', () async {
    service.erreurReglage = const ErreurService(
      "Le réglage du journal n'a pas pu être enregistré.",
    );
    final etat = EtatJournal(service);
    await etat.charger();

    final resultat = await etat.modifierJournalDetaille(true);

    expect(resultat.estReussi, isFalse);
    expect(resultat.erreur!.nature, NatureErreur.refus);
    expect(etat.journalDetaille, isTrue);
  });

  test('après dispose, un chargement en cours ne notifie plus', () async {
    final etat = EtatJournal(service);
    final chargement = etat.charger();
    etat.dispose();
    await chargement;
    expect(etat.estLibere, isTrue);
  });
}
