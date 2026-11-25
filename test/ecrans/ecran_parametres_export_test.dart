// Tests de la section « Sauvegarde et export » de EcranParametres (R7).
import 'dart:async';

import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceExport export;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    export = FauxServiceExport();
  });

  Future<void> afficher(WidgetTester tester, {bool avecExport = true}) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        export: avecExport ? export : null,
      ),
    );
    await tester.pump();
    await tester.pump();
    await deplierParametres(tester);
  }

  testWidgets('sans service d\'export, la section est masquée', (tester) async {
    await afficher(tester, avecExport: false);

    expect(find.text(Textes.sectionSauvegardeExport), findsNothing);
    expect(find.text(Textes.sectionAPropos), findsOneWidget);
  });

  testWidgets('l\'export affiche les nombres et les deux chemins '
      'sélectionnables', (tester) async {
    await afficher(tester);
    expect(find.text(Textes.sectionSauvegardeExport), findsOneWidget);

    await tester.tap(find.text(Textes.exporterTitresEtSites));
    await tester.pumpAndSettle();

    expect(export.nombreExports, 1);
    expect(find.text(Textes.exportEnregistre), findsOneWidget);
    expect(find.text(Textes.resumeExport(12, 2)), findsOneWidget);
    expect(
      find.widgetWithText(SelectableText, 'C:/exports/export.json'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(SelectableText, 'C:/exports/export.md'),
      findsOneWidget,
    );
    expect(find.text(Textes.ouvrirDossier), findsOneWidget);

    await tester.tap(find.text(Textes.fermer));
    await tester.pumpAndSettle();
    expect(find.text(Textes.exportEnregistre), findsNothing);
  });

  testWidgets('le bouton est désactivé pendant l\'export', (tester) async {
    final retenue = Completer<void>();
    export.retenue = retenue;
    await afficher(tester);

    await tester.tap(find.text(Textes.exporterTitresEtSites));
    await tester.pump();
    await tester.tap(find.text(Textes.exporterTitresEtSites));
    await tester.pump();
    expect(export.nombreExports, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    retenue.complete();
    await tester.pumpAndSettle();
    expect(find.text(Textes.exportEnregistre), findsOneWidget);
  });

  testWidgets('une ErreurService est affichée en message', (tester) async {
    export.erreur = const ErreurService("L'export n'a pas pu être enregistré.");
    await afficher(tester);

    await tester.tap(find.text(Textes.exporterTitresEtSites));
    await tester.pumpAndSettle();

    expect(find.text(Textes.exportEnregistre), findsNothing);
    expect(
      find.textContaining("L'export n'a pas pu être enregistré."),
      findsOneWidget,
    );
  });

  testWidgets('une ErreurBaseDeDonnees est affichée en message', (
    tester,
  ) async {
    export.erreur = const ErreurBaseDeDonnees('Base illisible.');
    await afficher(tester);

    await tester.tap(find.text(Textes.exporterTitresEtSites));
    await tester.pumpAndSettle();

    expect(find.text(Textes.exportEnregistre), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
