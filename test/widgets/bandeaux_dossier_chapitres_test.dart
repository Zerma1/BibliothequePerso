// Tests des bandeaux globaux du dossier des chapitres sur l'écran
// d'accueil : dossier inaccessible (avec « Réessayer » et contrôle au retour
// au premier plan) et redémarrage nécessaire.
import 'dart:async';

import 'package:bibliotheque_perso/donnees/erreur_stockage.dart';
import 'package:bibliotheque_perso/ecrans/ecran_accueil.dart';
import 'package:bibliotheque_perso/etat/etat_dossier_chapitres.dart';
import 'package:bibliotheque_perso/widgets/section_dossier_chapitres.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

void main() {
  late FauxServiceDossierChapitres service;

  const inaccessible = AccesDossierChapitres.inaccessible(
    r'\\nas\partage\Mangas',
    estPersonnalise: true,
    nature: NatureErreurStockage.reseauIndisponible,
  );
  const accessible = AccesDossierChapitres.accessible(
    r'\\nas\partage\Mangas',
    estPersonnalise: true,
  );

  setUp(() => service = FauxServiceDossierChapitres());

  Future<void> afficher(
    WidgetTester tester, {
    double largeur = 400,
    bool avecService = true,
  }) async {
    tester.view.physicalSize = Size(largeur, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranAccueil(),
        bibliotheque: FauxServiceBibliotheque(),
        dossierChapitres: avecService ? service : null,
      ),
    );
    await tester.pump();
  }

  testWidgets('aucun bandeau quand le dossier est accessible', (tester) async {
    await afficher(tester);

    expect(find.byIcon(Icons.folder_off_outlined), findsNothing);
    expect(find.text(Textes.bandeauRedemarrage), findsNothing);
  });

  testWidgets('sans service, l\'accueil s\'affiche sans bandeau', (
    tester,
  ) async {
    await afficher(tester, avecService: false);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byIcon(Icons.folder_off_outlined), findsNothing);
  });

  testWidgets('dossier inaccessible : message du service sur tous les '
      'onglets, « Réessayer » relance la vérification', (tester) async {
    service.accesDossier = inaccessible;
    await afficher(tester);

    expect(find.text(inaccessible.message!), findsOneWidget);
    // Autre onglet : le bandeau reste visible.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text(inaccessible.message!), findsOneWidget);

    final retenue = Completer<void>();
    service
      ..retenueVerification = retenue
      ..accesApresVerification = accessible;
    await tester.tap(find.text(Textes.reessayer));
    await tester.pump();
    // Pendant la vérification, le bouton est désactivé.
    final bouton = find.ancestor(
      of: find.text(Textes.reessayer),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(bouton).enabled, isFalse);

    retenue.complete();
    await tester.pumpAndSettle();

    expect(service.nombreVerifications, 1);
    expect(find.text(inaccessible.message!), findsNothing);
  });

  testWidgets('dossier inaccessible en disposition large', (tester) async {
    service.accesDossier = inaccessible;
    await afficher(tester, largeur: 1000);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text(inaccessible.message!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retour au premier plan : l\'accès est vérifié', (tester) async {
    await afficher(tester);
    expect(service.nombreVerifications, 0);
    service.accesApresVerification = inaccessible;

    for (final etat in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(etat);
    }
    await tester.pumpAndSettle();

    expect(service.nombreVerifications, 1);
    expect(find.text(inaccessible.message!), findsOneWidget);
  });

  testWidgets('redémarrage nécessaire : bandeau dédié', (tester) async {
    service.redemarrageNecessaire = true;
    await afficher(tester);

    expect(find.text(Textes.bandeauRedemarrage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.public_outlined));
    await tester.pumpAndSettle();
    expect(find.text(Textes.bandeauRedemarrage), findsOneWidget);
  });

  testWidgets('les deux bandeaux peuvent s\'afficher ensemble', (tester) async {
    service
      ..accesDossier = inaccessible
      ..redemarrageNecessaire = true;
    await afficher(tester);

    expect(find.text(inaccessible.message!), findsOneWidget);
    expect(find.text(Textes.bandeauRedemarrage), findsOneWidget);
  });

  group('dossier choisi à l\'installation', () {
    const nas = r'\\nas\partage\Bibliotheque';
    final texteBandeau = Textes.bandeauDossierInstallation(
      nas,
      r'C:\appli\telechargements',
    );

    testWidgets('aucun bandeau sans proposition', (tester) async {
      await afficher(tester);

      expect(find.text(Textes.deplacerMesChapitres), findsNothing);
    });

    testWidgets('bandeau avec les deux chemins, sur tous les onglets', (
      tester,
    ) async {
      service.dossierInstallationEnAttente = nas;
      await afficher(tester);

      expect(find.text(texteBandeau), findsOneWidget);
      expect(find.text(Textes.deplacerMesChapitres), findsOneWidget);
      expect(find.text(Textes.ignorer), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text(texteBandeau), findsOneWidget);
    });

    testWidgets('disposition large : bandeau sans débordement', (tester) async {
      service.dossierInstallationEnAttente = nas;
      await afficher(tester, largeur: 1000);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text(texteBandeau), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Déplacer mes chapitres » ouvre le dialogue prérempli, '
        'déplacement coché ; la réussite retire le bandeau', (tester) async {
      service.dossierInstallationEnAttente = nas;
      await afficher(tester);

      await tester.tap(find.text(Textes.deplacerMesChapitres));
      await tester.pumpAndSettle();

      // Champ du dialogue (l'accueil a aussi son champ de recherche).
      final champ = tester.widget<TextField>(
        find.descendant(
          of: find.byType(DialogueChangementDossier),
          matching: find.byType(TextField),
        ),
      );
      expect(champ.controller?.text, nas);
      // Chemin modifiable : le client peut corriger le dossier proposé.
      expect(champ.readOnly, isFalse);
      final caseDeplacer = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(caseDeplacer.value, isTrue);

      await tester.tap(find.text(Textes.changer));
      await tester.pumpAndSettle();

      expect(service.demandes.single, (dossier: nas, deplacer: true));
      expect(find.text(Textes.dossierChange), findsOneWidget);
      await tester.tap(find.text(Textes.fermer));
      await tester.pumpAndSettle();

      expect(find.text(texteBandeau), findsNothing);
      expect(find.text(Textes.bandeauRedemarrage), findsOneWidget);
    });

    testWidgets('annuler le dialogue garde la proposition', (tester) async {
      service.dossierInstallationEnAttente = nas;
      await afficher(tester);

      await tester.tap(find.text(Textes.deplacerMesChapitres));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.annuler));
      await tester.pumpAndSettle();

      expect(service.demandes, isEmpty);
      expect(find.text(texteBandeau), findsOneWidget);
    });

    testWidgets('« Ignorer » demande confirmation : annuler ne change rien', (
      tester,
    ) async {
      service.dossierInstallationEnAttente = nas;
      await afficher(tester);

      await tester.tap(find.text(Textes.ignorer));
      await tester.pumpAndSettle();
      expect(find.text(Textes.ignorerDossierInstallation), findsOneWidget);
      await tester.tap(find.text(Textes.annuler));
      await tester.pumpAndSettle();

      expect(service.nombreRefusInstallation, 0);
      expect(find.text(texteBandeau), findsOneWidget);
    });

    testWidgets('« Ignorer » confirmé : refus enregistré, bandeau retiré', (
      tester,
    ) async {
      service.dossierInstallationEnAttente = nas;
      await afficher(tester);

      await tester.tap(find.text(Textes.ignorer));
      await tester.pumpAndSettle();
      // Bouton de confirmation (le dernier « Ignorer », dans le dialogue).
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(Textes.ignorer),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.nombreRefusInstallation, 1);
      expect(find.text(texteBandeau), findsNothing);
      expect(find.text(Textes.dossierInstallationIgnore), findsOneWidget);
    });

    testWidgets('« Ignorer » en échec : message d\'erreur, bandeau gardé', (
      tester,
    ) async {
      service
        ..dossierInstallationEnAttente = nas
        ..erreurIgnorerInstallation = StateError('base verrouillée');
      await afficher(tester);

      await tester.tap(find.text(Textes.ignorer));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(Textes.ignorer),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.nombreRefusInstallation, 1);
      expect(find.text(texteBandeau), findsOneWidget);
      expect(find.text(Textes.dossierInstallationIgnore), findsNothing);
    });
  });
}
