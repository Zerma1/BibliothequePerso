// Tests de la section « Dossier des chapitres » des paramètres et de son
// dialogue de changement de dossier.
import 'dart:async';

import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_dossier_chapitres.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/section_dossier_chapitres.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';
import 'outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceDossierChapitres service;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    service = FauxServiceDossierChapitres();
  });

  Future<void> afficher(
    WidgetTester tester, {
    bool avecService = true,
    bool deplier = true,
  }) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        dossierChapitres: avecService ? service : null,
      ),
    );
    await tester.pump();
    await tester.pump();
    if (deplier && avecService) {
      await basculerSection(tester, Textes.sectionDossierChapitres);
    }
  }

  /// Bouton « Changer de dossier » de la section.
  Finder boutonChanger() => find.ancestor(
    of: find.text(Textes.changerDeDossier),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  Future<void> ouvrirDialogue(WidgetTester tester) async {
    await tester.ensureVisible(boutonChanger());
    await tester.tap(boutonChanger());
    await tester.pumpAndSettle();
  }

  testWidgets('sans service, la section est masquée', (tester) async {
    await afficher(tester, avecService: false);

    expect(find.text(Textes.sectionDossierChapitres), findsNothing);
  });

  testWidgets('affiche le dossier actuel, son origine et le bouton', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text(Textes.sectionDossierChapitres), findsOneWidget);
    expect(
      find.widgetWithText(SelectableText, r'C:\appli\telechargements'),
      findsOneWidget,
    );
    expect(find.text(Textes.dossierParDefautApplication), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(boutonChanger()).enabled, isTrue);
  });

  testWidgets('changement avec déplacement : progression, boîte non '
      'fermable, puis résultat et redémarrage', (tester) async {
    final retenue = Completer<void>();
    service
      ..retenueDeplacement = retenue
      ..nombreFichiers = 4;
    await afficher(tester);
    await ouvrirDialogue(tester);

    // Case cochée par défaut, avec son explication.
    final caseDeplacer = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(caseDeplacer.value, isTrue);
    expect(find.text(Textes.explicationDeplacerCoche), findsOneWidget);

    await tester.enterText(find.byType(TextField), r'\\nas\partage\Mangas');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
    await tester.pump();
    await tester.pump();

    expect(find.text(Textes.deplacementEnCours), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(Textes.progressionDeplacement(1, 4)), findsOneWidget);
    // Aucun bouton pour fermer pendant le déplacement, et le retour est
    // bloqué.
    expect(find.text(Textes.annuler), findsNothing);
    final navigateur = tester.state<NavigatorState>(find.byType(Navigator));
    await navigateur.maybePop();
    await tester.pump();
    expect(find.text(Textes.deplacementEnCours), findsOneWidget);

    retenue.complete();
    await tester.pumpAndSettle();

    expect(find.text(Textes.dossierChange), findsOneWidget);
    expect(
      find.textContaining(r'\\nas\partage\Mangas', findRichText: true),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(Textes.redemarrerPourNouveauDossier),
      ),
      findsOneWidget,
    );
    expect(service.demandes.single, (
      dossier: r'\\nas\partage\Mangas',
      deplacer: true,
    ));

    await tester.tap(find.text(Textes.fermer));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text(Textes.dossierAuProchainDemarrage(r'\\nas\partage\Mangas')),
      findsOneWidget,
    );
    // Un seul changement par session.
    expect(tester.widget<ButtonStyleButton>(boutonChanger()).enabled, isFalse);
  });

  testWidgets('case décochée : explication du retéléchargement et pas de '
      'déplacement', (tester) async {
    await afficher(tester);
    await ouvrirDialogue(tester);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(find.text(Textes.explicationDeplacerDecoche), findsOneWidget);

    await tester.enterText(find.byType(TextField), r'D:\Mangas');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
    await tester.pumpAndSettle();

    expect(service.demandes.single, (dossier: r'D:\Mangas', deplacer: false));
    expect(find.text(Textes.dossierChange), findsOneWidget);
  });

  testWidgets('un refus reste dans la boîte avec le message du service', (
    tester,
  ) async {
    service.erreurChangement = const ErreurService(
      "Le dossier n'a pas pu être créé.",
    );
    await afficher(tester);
    await ouvrirDialogue(tester);
    await tester.enterText(find.byType(TextField), r'Q:\absent');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
    await tester.pumpAndSettle();

    expect(find.text("Le dossier n'a pas pu être créé."), findsOneWidget);
    expect(find.widgetWithText(FilledButton, Textes.reessayer), findsOneWidget);
    expect(find.text(Textes.dossierChange), findsNothing);
  });

  testWidgets('refus « chapitre en cours » : « Annuler » reprend la file', (
    tester,
  ) async {
    service.chapitreEnCours = true;
    await afficher(tester);
    await ouvrirDialogue(tester);
    await tester.enterText(find.byType(TextField), r'Z:\Mangas');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Un chapitre est en cours de téléchargement'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(Textes.filePauseeParChangement),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text(Textes.annuler));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(service.nombreReprises, 1);
    expect(service.estFileEnPause, isFalse);
  });

  testWidgets('« Revenir au dossier par défaut » seulement pour un dossier '
      'choisi', (tester) async {
    await afficher(tester);
    await ouvrirDialogue(tester);
    final bouton = find.ancestor(
      of: find.text(Textes.revenirDossierParDefaut),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(bouton).enabled, isFalse);
    expect(
      find.text(Textes.cheminDossierParDefaut(r'C:\appli\telechargements')),
      findsOneWidget,
    );
    await tester.tap(find.text(Textes.annuler));
    await tester.pumpAndSettle();
    // Aucune pause à lever : la file n'est pas touchée.
    expect(service.nombreReprises, 0);
  });

  testWidgets('« Revenir au dossier par défaut » demande le dossier par '
      'défaut', (tester) async {
    service
      ..estDossierPersonnalise = true
      ..dossierActuel = r'Z:\Mangas'
      ..dossierChoisi = r'Z:\Mangas';
    await afficher(tester);
    expect(find.text(Textes.dossierChoisiParVous), findsOneWidget);
    await ouvrirDialogue(tester);

    await tester.tap(find.text(Textes.revenirDossierParDefaut));
    await tester.pumpAndSettle();

    expect(service.demandes.single, (dossier: null, deplacer: true));
    expect(find.text(Textes.dossierChange), findsOneWidget);
  });

  testWidgets('déplacement inachevé : « Terminer » reprend vers le même '
      'dossier', (tester) async {
    service.deplacementInacheve = r'Z:\Mangas';
    await afficher(tester);

    expect(find.text(Textes.deplacementInacheve(r'Z:\Mangas')), findsOneWidget);
    // Changer pour un autre dossier reste possible (après avertissement).
    expect(tester.widget<ButtonStyleButton>(boutonChanger()).enabled, isTrue);

    await tester.tap(find.text(Textes.terminerDeplacement));
    await tester.pumpAndSettle();

    expect(service.demandes.single, (dossier: r'Z:\Mangas', deplacer: true));
    expect(find.text(Textes.dossierChange), findsOneWidget);
  });

  testWidgets('déplacement inachevé : « Abandonner » après confirmation', (
    tester,
  ) async {
    service.deplacementInacheve = r'Z:\Mangas';
    await afficher(tester);

    await tester.tap(find.text(Textes.abandonner));
    await tester.pumpAndSettle();
    expect(find.text(Textes.confirmationAbandonDeplacement), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, Textes.abandonner),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.nombreAbandons, 1);
    expect(find.text(Textes.deplacementAbandonne), findsOneWidget);
    expect(find.text(Textes.deplacementInacheve(r'Z:\Mangas')), findsNothing);
  });

  testWidgets('bilan : les fichiers en conflit sont listés (liste '
      'courte)', (tester) async {
    service.cheminsEnConflit = <String>[
      for (var i = 1; i <= 7; i++) 'manga/Titre/ch$i.fr.zip',
    ];
    await afficher(tester);
    await ouvrirDialogue(tester);
    await tester.enterText(find.byType(TextField), r'Z:\Mangas');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
    await tester.pumpAndSettle();

    expect(find.text(Textes.dossierChange), findsOneWidget);
    expect(find.text(Textes.fichiersEnConflit(7)), findsOneWidget);
    expect(
      find.text(Textes.fichierEnConflit('manga/Titre/ch1.fr.zip')),
      findsOneWidget,
    );
    expect(
      find.text(Textes.fichierEnConflit('manga/Titre/ch5.fr.zip')),
      findsOneWidget,
    );
    // Au-delà de la limite, seul le nombre restant est indiqué.
    expect(
      find.text(Textes.fichierEnConflit('manga/Titre/ch6.fr.zip')),
      findsNothing,
    );
    expect(find.text(Textes.autresFichiersEnConflit(2)), findsOneWidget);
  });

  testWidgets('bilan sans conflit : pas de liste', (tester) async {
    await afficher(tester);
    await ouvrirDialogue(tester);
    await tester.enterText(find.byType(TextField), r'Z:\Mangas');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
    await tester.pumpAndSettle();

    expect(find.text(Textes.dossierChange), findsOneWidget);
    expect(find.textContaining("restés dans l'ancien dossier"), findsNothing);
  });

  testWidgets('de bout en bout : déplacement inachevé, « Changer de dossier » '
      'actif, avertissement puis changement', (tester) async {
    service.deplacementInacheve = r'Y:\Ancien';
    await afficher(tester);

    expect(find.text(Textes.deplacementInacheve(r'Y:\Ancien')), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(boutonChanger()).enabled, isTrue);

    await ouvrirDialogue(tester);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.enterText(find.byType(TextField), r'Z:\Mangas');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
    await tester.pumpAndSettle();

    expect(find.text(Textes.avantChangementDossier), findsOneWidget);
    expect(find.textContaining(r'Y:\Ancien'), findsWidgets);
    expect(service.demandes, isEmpty);

    await tester.tap(find.text(Textes.changerQuandMeme));
    await tester.pumpAndSettle();

    expect(service.demandes.single, (dossier: r'Z:\Mangas', deplacer: false));
    expect(find.text(Textes.dossierChange), findsOneWidget);
    await tester.tap(find.text(Textes.fermer));
    await tester.pumpAndSettle();

    // Après un changement réussi, le bouton est désactivé pour la session.
    expect(tester.widget<ButtonStyleButton>(boutonChanger()).enabled, isFalse);
  });

  group('avertissement avant changement', () {
    late EtatDossierChapitres etat;

    // Dialogue affiché seul : cas de l'avertissement testés en détail.
    Future<void> afficherDialogue(WidgetTester tester) async {
      etat = EtatDossierChapitres(service);
      addTearDown(etat.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DialogueChangementDossier(etat: etat)),
        ),
      );
    }

    Future<void> demanderSansDeplacement(WidgetTester tester) async {
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.enterText(find.byType(TextField), r'Z:\Mangas');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
      await tester.pumpAndSettle();
    }

    testWidgets('déplacement inachevé abandonné : confirmation avec le texte '
        'du service', (tester) async {
      service.deplacementInacheve = r'Y:\Ancien';
      await afficherDialogue(tester);
      await demanderSansDeplacement(tester);

      expect(find.text(Textes.avantChangementDossier), findsOneWidget);
      expect(find.textContaining(r'Y:\Ancien'), findsOneWidget);
      expect(service.demandes, isEmpty);

      // « Annuler » : rien n'est changé, la saisie reste ouverte.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text(Textes.avantChangementDossier),
            matching: find.byType(AlertDialog),
          ),
          matching: find.text(Textes.annuler),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(Textes.avantChangementDossier), findsNothing);
      expect(service.demandes, isEmpty);
      expect(find.widgetWithText(FilledButton, Textes.changer), findsOneWidget);

      // « Changer quand même » : le changement a lieu.
      await tester.tap(find.widgetWithText(FilledButton, Textes.changer));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.changerQuandMeme));
      await tester.pumpAndSettle();

      expect(service.demandes.single, (dossier: r'Z:\Mangas', deplacer: false));
      expect(find.text(Textes.dossierChange), findsOneWidget);
    });

    testWidgets('sans avertissement, aucune confirmation', (tester) async {
      await afficherDialogue(tester);
      await demanderSansDeplacement(tester);

      expect(find.text(Textes.avantChangementDossier), findsNothing);
      expect(service.demandes.single, (dossier: r'Z:\Mangas', deplacer: false));
    });

    testWidgets('erreur de lecture : message dans la boîte, rien de '
        'changé', (tester) async {
      service.erreurLecture = const ErreurService('Lecture impossible.');
      await afficherDialogue(tester);
      await demanderSansDeplacement(tester);

      expect(find.text('Lecture impossible.'), findsOneWidget);
      expect(find.text(Textes.avantChangementDossier), findsNothing);
      expect(service.demandes, isEmpty);
    });
  });

  testWidgets('dialogue utilisable sur un téléphone étroit', (tester) async {
    // Étroit mais haut : toutes les sections sont construites d'emblée.
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        dossierChapitres: service,
      ),
    );
    await tester.pump();
    await tester.pump();
    await basculerSection(tester, Textes.sectionDossierChapitres);
    await ouvrirDialogue(tester);

    expect(find.byType(DialogueChangementDossier), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
