// Tests de l'import d'un export (U1) depuis la section « Sauvegarde et
// export » de EcranParametres, avec de faux services (aucun fichier lu).
import 'dart:async';

import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_export.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_import.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceExport export;
  late FauxServiceImport importation;

  const cheminRecent = 'C:/exports/bibliotheque_2026-11-17.json';
  const cheminAncien = r'C:\exports\bibliotheque_2026-11-01.json';

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    export = FauxServiceExport();
    importation = FauxServiceImport();
  });

  Future<void> afficher(
    WidgetTester tester, {
    bool avecImport = true,
    List<String> exports = const <String>[cheminRecent, cheminAncien],
  }) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        export: export,
        importation: avecImport ? importation : null,
        listerExports: () async => exports,
      ),
    );
    await tester.pump();
    await tester.pump();
    await basculerSection(tester, Textes.sectionSauvegardeExport);
  }

  Future<void> ouvrirDialogue(WidgetTester tester) async {
    await tester.tap(find.text(Textes.importerUnExport));
    await tester.pumpAndSettle();
  }

  Finder boutonImporter() => find.widgetWithText(FilledButton, Textes.importer);

  testWidgets('sans service d\'import, pas de bouton « Importer »', (
    tester,
  ) async {
    await afficher(tester, avecImport: false);
    expect(find.text(Textes.exporterTitresEtSites), findsOneWidget);
    expect(find.text(Textes.importerUnExport), findsNothing);
  });

  testWidgets('choisir un export trouvé, importer, voir le bilan et les '
      'erreurs ; les écrans sont relus', (tester) async {
    importation.resultat = const ResultatImport(
      versionFormat: 1,
      titresAjoutes: 3,
      titresIgnores: 1,
      erreurs: <ErreurLigneImport>[
        ErreurLigneImport(
          partie: PartieImport.titre,
          numero: 4,
          nom: 'Titre cassé',
          message: 'adresse invalide',
        ),
      ],
    );
    await afficher(tester);
    await ouvrirDialogue(tester);

    // Liste des exports : nom du fichier, chemin complet en sous-titre.
    expect(find.text('bibliotheque_2026-11-17.json'), findsOneWidget);
    expect(find.text('bibliotheque_2026-11-01.json'), findsOneWidget);
    expect(find.text(cheminAncien), findsOneWidget);
    // Rien de choisi : « Importer » inactif.
    expect(tester.widget<FilledButton>(boutonImporter()).onPressed, isNull);

    await tester.tap(find.text('bibliotheque_2026-11-01.json'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      cheminAncien,
    );
    final lectures = bibliotheque.nombreLecturesParutions;
    await tester.tap(boutonImporter());
    await tester.pumpAndSettle();

    expect(importation.chemins, <String>[cheminAncien]);
    expect(find.text(Textes.importTermine), findsOneWidget);
    expect(find.text(importation.resultat.resume), findsOneWidget);
    expect(find.text(Textes.erreursImport(1)), findsOneWidget);
    expect(
      find.text('• Titre n°4 « Titre cassé » : adresse invalide'),
      findsOneWidget,
    );
    // Mises à jour (et bibliothèque, sites, réglages) relues.
    expect(bibliotheque.nombreLecturesParutions, greaterThan(lectures));

    await tester.tap(find.text(Textes.fermer));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('aucun export trouvé : chemin collé ; un fichier refusé '
      'laisse la boîte ouverte avec le message', (tester) async {
    importation.erreur = const ErreurService(
      "Ce fichier n'est pas un export de la bibliothèque.",
    );
    await afficher(tester, exports: const <String>[]);
    await ouvrirDialogue(tester);
    expect(find.text(Textes.aucunExportTrouve), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  D:/autre.json  ');
    await tester.pump();
    await tester.tap(boutonImporter());
    await tester.pumpAndSettle();

    expect(importation.chemins, <String>['D:/autre.json']);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining("n'est pas un export"), findsOneWidget);
    expect(find.text(Textes.importTermine), findsNothing);

    // Annuler ferme la boîte sans rien importer d'autre.
    await tester.tap(find.text(Textes.annuler));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(importation.chemins, hasLength(1));
  });

  testWidgets('pendant l\'import, les boutons sont inactifs', (tester) async {
    final retenue = Completer<void>();
    importation.retenue = retenue;
    await afficher(tester);
    await ouvrirDialogue(tester);
    await tester.tap(find.text('bibliotheque_2026-11-17.json'));
    await tester.pump();
    await tester.tap(boutonImporter());
    await tester.pump();

    expect(find.text(Textes.importEnCours), findsOneWidget);
    expect(tester.widget<FilledButton>(boutonImporter()).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, Textes.annuler))
          .onPressed,
      isNull,
    );

    retenue.complete();
    await tester.pumpAndSettle();
    expect(find.text(Textes.importTermine), findsOneWidget);
  });

  group('EtatExport : import', () {
    test('propose le dernier export de la session et tolère un dossier '
        'illisible', () async {
      final etat = EtatExport(
        export,
        serviceImport: importation,
        listerExports: () async => throw const ErreurService('illisible'),
      );
      addTearDown(etat.dispose);
      expect(await etat.chargerExportsDisponibles(), isEmpty);

      await etat.exporter();
      expect(await etat.chargerExportsDisponibles(), <String>[
        'C:/exports/export.json',
      ]);
    });

    test('chemin vide ou sans service : refus sans appel', () async {
      final etat = EtatExport(export, serviceImport: importation);
      addTearDown(etat.dispose);
      expect((await etat.importer('   ')).estReussi, isFalse);
      expect(importation.chemins, isEmpty);

      final sansImport = EtatExport(export);
      addTearDown(sansImport.dispose);
      expect(sansImport.peutImporter, isFalse);
      expect((await sansImport.importer('C:/a.json')).estReussi, isFalse);
    });
  });
}
