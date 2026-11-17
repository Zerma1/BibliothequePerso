// Tests de la navigation responsive de EcranAccueil.
import 'package:bibliotheque_perso/ecrans/ecran_accueil.dart';
import 'package:bibliotheque_perso/ecrans/ecran_erreur_demarrage.dart';
import 'package:bibliotheque_perso/etat/constantes_etat.dart';
import 'package:bibliotheque_perso/main.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/widgets/carte_titre.dart';
import 'package:bibliotheque_perso/widgets/constantes_interface.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

void main() {
  Future<void> afficher(WidgetTester tester, double largeur) async {
    tester.view.physicalSize = Size(largeur, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(const EcranAccueil(), bibliotheque: FauxServiceBibliotheque()),
    );
    await tester.pump();
  }

  testWidgets('barre de navigation en bas sous 600 px', (tester) async {
    await afficher(tester, 400);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('NavigationRail au-delà de 600 px', (tester) async {
    await afficher(tester, 1000);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('passe de la bibliothèque aux sources', (tester) async {
    await afficher(tester, 400);
    expect(find.text(Textes.bibliothequeVide), findsOneWidget);

    await tester.tap(find.byIcon(Icons.public_outlined));
    await tester.pumpAndSettle();

    expect(find.text(Textes.sourcesVide), findsOneWidget);
  });

  testWidgets('la recherche survit au passage de 400 à 1000 px', (
    tester,
  ) async {
    final service = FauxServiceBibliotheque()
      ..ajouterTitreDeTest('Shinigami')
      ..ajouterTitreDeTest('Solo Leveling');
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(const EcranAccueil(), bibliotheque: service),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'solo');
    await tester.pump(delaiAvantRecherche);
    await tester.pump();
    expect(find.byType(CarteTitre), findsOneWidget);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.widgetWithText(TextField, 'solo'), findsOneWidget);
    expect(find.byType(CarteTitre), findsOneWidget);
    expect(find.text('Solo Leveling'), findsOneWidget);
  });

  testWidgets(
    'après un ajout de titre, l\'onglet Sources montre MangaDex ajouté '
    'automatiquement (même en cas d\'échec)',
    (tester) async {
      final service = FauxServiceBibliotheque();
      service
        ..erreurAjout = const ErreurSource('https://api.mangadex.org', 'Panne')
        ..avantAjout = () => service.sources.add(
          const Source(
            id: 1,
            nom: 'MangaDex',
            urlBase: 'https://mangadex.org',
            typeSource: TypeSource.mangaDex,
          ),
        );
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        envelopper(const EcranAccueil(), bibliotheque: service),
      );
      await tester.pump();

      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterTitre),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champUrlTitre),
        'https://mangadex.org/title/abc',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.annuler));
      await tester.pumpAndSettle();

      await tester.tap(find.text(Textes.ongletSources));
      await tester.pumpAndSettle();
      expect(find.text('MangaDex'), findsOneWidget);
    },
  );

  testWidgets('onglets Téléchargements et Paramètres, badge et version', (
    tester,
  ) async {
    final bibliotheque = FauxServiceBibliotheque()
      ..ajouterTitreDeTest(
        'Titre',
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
        ],
      );
    final telechargement = FauxServiceTelechargement(bibliotheque)
      ..modifierLigne(1, StatutTelechargement.enAttente);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranAccueil(),
        bibliotheque: bibliotheque,
        telechargement: telechargement,
      ),
    );
    await tester.pump();
    await tester.pump();

    // Version en petit tout en bas du rail (retour 0.2.0-test), sous la
    // dernière destination.
    final version = find.text(Textes.versionCourte(versionApplication));
    expect(version, findsOneWidget);
    expect(
      tester.getBottomLeft(version).dy,
      greaterThan(tester.getSize(find.byType(NavigationRail)).height - 60),
    );
    expect(
      tester.getTopLeft(version).dy,
      greaterThan(
        tester
            .getBottomLeft(
              find.descendant(
                of: find.byType(NavigationRail),
                matching: find.text(Textes.ongletParametres),
              ),
            )
            .dy,
      ),
    );
    // Badge : un chapitre en attente.
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.descendant(
          of: find.byType(Badge),
          matching: find.text('1'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text(Textes.ongletTelechargements));
    await tester.pumpAndSettle();
    expect(find.text('En attente'), findsOneWidget);

    await tester.tap(find.text(Textes.ongletParametres).first);
    await tester.pumpAndSettle();
    // Section de l'écran Paramètres, repliée au départ.
    expect(find.text(Textes.sectionMisesAJour), findsOneWidget);
    expect(find.text(Textes.heuresEnAttente), findsNothing);
    await tester.tap(find.text(Textes.sectionMisesAJour));
    await tester.pumpAndSettle();
    expect(find.text(Textes.heuresEnAttente), findsOneWidget);
  });

  testWidgets('écran d\'erreur de démarrage lisible', (tester) async {
    var essais = 0;
    await tester.pumpWidget(
      BibliothequePersoApp(
        accueil: EcranErreurDemarrage(
          detail: 'database is locked',
          surReessayer: () => essais++,
        ),
      ),
    );

    expect(find.text(Textes.erreurDemarrageTitre), findsOneWidget);
    expect(find.textContaining('database is locked'), findsOneWidget);
    await tester.tap(find.text(Textes.reessayer));
    expect(essais, 1);
  });
}
