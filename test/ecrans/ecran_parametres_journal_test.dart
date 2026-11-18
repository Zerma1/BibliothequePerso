// Tests de la section « Journal » de EcranParametres.
import 'dart:async';

import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceJournal journal;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    journal = FauxServiceJournal();
  });

  Future<void> afficher(
    WidgetTester tester, {
    bool avecJournal = true,
    double largeur = 900,
  }) async {
    tester.view.physicalSize = Size(largeur, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        journal: avecJournal ? journal : null,
        mesurerTailleJournal: (chemin) async =>
            chemin.endsWith('18.log') ? 2560 : 512,
      ),
    );
    await tester.pump();
    await tester.pump();
    await deplierParametres(tester);
  }

  testWidgets('sans service du journal, la section est masquée', (
    tester,
  ) async {
    await afficher(tester, avecJournal: false);

    expect(find.text(Textes.sectionJournal), findsNothing);
    expect(find.text(Textes.sectionAPropos), findsOneWidget);
  });

  testWidgets('la section montre l\'explication, le dossier sélectionnable '
      'et les fichiers avec leur date et leur taille', (tester) async {
    await afficher(tester);

    expect(find.text(Textes.sectionJournal), findsOneWidget);
    expect(find.text(Textes.explicationJournal), findsOneWidget);
    expect(find.widgetWithText(SelectableText, 'C:/journaux'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, Textes.ouvrirDossier),
      findsOneWidget,
    );
    expect(
      find.text(Textes.ligneFichierJournal(DateTime(2026, 11, 18), 1, 2560)),
      findsOneWidget,
    );
    expect(find.text('18/11/2026 · 2,5 Ko'), findsOneWidget);
    expect(find.text('17/11/2026 · 512 o'), findsOneWidget);
    expect(find.text('journal-2026-11-18.log'), findsOneWidget);
    // Le plus récent en haut.
    expect(
      tester.getTopLeft(find.text('18/11/2026 · 2,5 Ko')).dy,
      lessThan(tester.getTopLeft(find.text('17/11/2026 · 512 o')).dy),
    );
    expect(find.text(Textes.journalDetaille), findsOneWidget);
    expect(find.text(Textes.explicationJournalDetaille), findsOneWidget);
  });

  testWidgets('sans fichier, un message le dit', (tester) async {
    journal.fichiers = [];
    await afficher(tester);

    expect(find.text(Textes.aucunFichierJournal), findsOneWidget);
  });

  testWidgets('« Exporter le journal du jour » affiche le chemin du fichier', (
    tester,
  ) async {
    await afficher(tester);

    await tester.ensureVisible(find.text(Textes.exporterJournalDuJour));
    await tester.tap(find.text(Textes.exporterJournalDuJour));
    await tester.pumpAndSettle();

    expect(journal.joursExportes, <int>[1]);
    expect(find.text(Textes.journalExporte), findsOneWidget);
    expect(
      find.widgetWithText(SelectableText, 'C:/rapports/journal_export_1.log'),
      findsOneWidget,
    );

    await tester.tap(find.text(Textes.fermer));
    await tester.pumpAndSettle();
    expect(find.text(Textes.journalExporte), findsNothing);
  });

  testWidgets('« Exporter les 7 derniers jours » demande 7 jours', (
    tester,
  ) async {
    await afficher(tester);

    await tester.ensureVisible(find.text(Textes.exporterJournalSemaine));
    await tester.tap(find.text(Textes.exporterJournalSemaine));
    await tester.pumpAndSettle();

    expect(journal.joursExportes, <int>[7]);
    expect(find.text(Textes.journalExporte), findsOneWidget);
  });

  testWidgets('les boutons sont désactivés pendant l\'export', (tester) async {
    final retenue = Completer<void>();
    journal.retenue = retenue;
    await afficher(tester);

    await tester.ensureVisible(find.text(Textes.exporterJournalDuJour));
    await tester.tap(find.text(Textes.exporterJournalDuJour));
    await tester.pump();
    await tester.tap(find.text(Textes.exporterJournalSemaine));
    await tester.pump();

    expect(journal.joursExportes, <int>[1]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    retenue.complete();
    await tester.pumpAndSettle();
    expect(find.text(Textes.journalExporte), findsOneWidget);
  });

  testWidgets('un journal vide est signalé par un message', (tester) async {
    journal.erreurExport = const ErreurService(
      "Le journal est vide : rien n'a encore été noté pour ces jours.",
    );
    await afficher(tester);

    await tester.ensureVisible(find.text(Textes.exporterJournalDuJour));
    await tester.tap(find.text(Textes.exporterJournalDuJour));
    await tester.pumpAndSettle();

    expect(find.text(Textes.journalExporte), findsNothing);
    expect(find.textContaining('Le journal est vide'), findsOneWidget);
  });

  testWidgets('l\'interrupteur active le journal détaillé', (tester) async {
    await afficher(tester);
    final interrupteur = find.widgetWithText(
      SwitchListTile,
      Textes.journalDetaille,
    );
    expect(tester.widget<SwitchListTile>(interrupteur).value, isFalse);

    await tester.ensureVisible(interrupteur);
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();

    expect(journal.detaille, isTrue);
    expect(tester.widget<SwitchListTile>(interrupteur).value, isTrue);
    expect(find.text(Textes.journalDetailleModifie(true)), findsOneWidget);
    // Le résumé de la section rappelle de le désactiver.
    expect(find.text(Textes.resumeJournal(detaille: true)), findsOneWidget);
  });

  testWidgets('écran étroit : la section tient sans débordement', (
    tester,
  ) async {
    await afficher(tester, largeur: 360);

    expect(find.text(Textes.exporterJournalSemaine), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
