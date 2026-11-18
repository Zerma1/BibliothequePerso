// Tests de la section « Catégories regroupées » de EcranParametres et de
// l'affichage des groupes dans le panneau des catégories.
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_bibliotheque.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/panneau_filtres.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceCategories categories;

  // Catégories : 1 survival, 2 action, 3 survie, 4 comédie, 5 comedy.
  setUp(() {
    bibliotheque = FauxServiceBibliotheque()
      ..ajouterTitreDeTest(
        'Alpha',
        nomsCategories: <String>['survival', 'action'],
      )
      ..ajouterTitreDeTest('Beta', nomsCategories: <String>['survie'])
      ..ajouterTitreDeTest(
        'Gamma',
        nomsCategories: <String>['comédie', 'comedy'],
      );
    categories = FauxServiceCategories(bibliotheque);
  });

  Future<void> afficher(WidgetTester tester, {bool avecService = true}) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        categories: avecService ? categories : null,
      ),
    );
    await tester.pumpAndSettle();
    if (avecService) {
      await basculerSection(tester, Textes.sectionCategoriesRegroupees);
    }
  }

  testWidgets('sans service de catégories, la section est masquée', (
    tester,
  ) async {
    await afficher(tester, avecService: false);

    expect(find.text(Textes.sectionCategoriesRegroupees), findsNothing);
    expect(find.text(Textes.sectionSites), findsOneWidget);
  });

  testWidgets('le résumé et les suggestions s\'affichent, rien n\'est '
      'appliqué sans appui', (tester) async {
    await afficher(tester);

    expect(find.text(Textes.resumeCategoriesRegroupees(0, 2)), findsOneWidget);
    expect(find.text(Textes.aucunGroupe), findsOneWidget);
    expect(find.text(Textes.suggestion('Survie', 'Survival')), findsOneWidget);
    expect(find.text(Textes.suggestion('Comédie', 'Comedy')), findsOneWidget);
    expect(categories.journal, isEmpty);
  });

  testWidgets('« Regrouper » applique la suggestion et relit la '
      'bibliothèque', (tester) async {
    await afficher(tester);

    final carte = find
        .ancestor(
          of: find.text(Textes.suggestion('Survie', 'Survival')),
          matching: find.byType(Card),
        )
        .first; // la carte de la suggestion, pas celle de la section
    await tester.tap(
      find.descendant(of: carte, matching: find.text(Textes.regrouper)),
    );
    await tester.pumpAndSettle();

    expect(categories.equivalences, <int, int>{1: 3});
    expect(find.text(Textes.categoriesRegroupees('Survie', 1)), findsOneWidget);
    expect(find.text(Textes.suggestion('Survie', 'Survival')), findsNothing);
    // Le groupe est listé : la référence et sa catégorie rattachée.
    expect(find.widgetWithText(InputChip, 'Survival'), findsOneWidget);
    final etat = tester
        .element(find.byType(EcranParametres))
        .read<EtatBibliotheque>();
    expect(etat.autresNoms(3), <String>['survival']);
    expect(etat.categories.map((c) => c.nom), isNot(contains('survival')));
  });

  testWidgets('« Ignorer » masque la suggestion sans écrire', (tester) async {
    await afficher(tester);

    final carte = find
        .ancestor(
          of: find.text(Textes.suggestion('Comédie', 'Comedy')),
          matching: find.byType(Card),
        )
        .first; // la carte de la suggestion, pas celle de la section
    await tester.tap(
      find.descendant(of: carte, matching: find.text(Textes.ignorer)),
    );
    await tester.pumpAndSettle();

    expect(find.text(Textes.suggestion('Comédie', 'Comedy')), findsNothing);
    expect(categories.journal, isEmpty);
  });

  testWidgets('retire une catégorie puis défait un groupe', (tester) async {
    categories
      ..regrouperDeTest(3, <int>[1])
      ..regrouperDeTest(4, <int>[5]);
    await afficher(tester);
    expect(find.text(Textes.resumeCategoriesRegroupees(2, 0)), findsOneWidget);

    await tester.tap(
      find.byTooltip(Textes.detacherCategorie('Comedy')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(categories.equivalences, <int, int>{1: 3});
    expect(find.text(Textes.categorieDetachee('Comedy')), findsOneWidget);

    await tester.tap(find.byTooltip(Textes.defaireGroupe));
    await tester.pumpAndSettle();
    expect(
      find.text(Textes.confirmationDefaireGroupe('Survie')),
      findsOneWidget,
    );
    await tester.tap(find.text(Textes.defaire));
    await tester.pumpAndSettle();

    expect(categories.equivalences, isEmpty);
    expect(find.text(Textes.groupeDefait('Survie')), findsOneWidget);
    expect(find.text(Textes.aucunGroupe), findsOneWidget);
  });

  testWidgets('regroupement à la main : référence, recherche sans accents, '
      'catégories cochées', (tester) async {
    await afficher(tester);

    await tester.tap(find.text(Textes.regrouperDesCategories));
    await tester.pumpAndSettle();
    expect(find.text(Textes.choisirReference), findsOneWidget);

    final dialogue = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialogue, matching: find.byType(TextField)),
      'COMEDIE',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialogue, matching: find.byType(ListTile)),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: dialogue, matching: find.text('Comédie')),
    );
    await tester.pumpAndSettle();

    expect(find.text(Textes.choisirARattacher('Comédie')), findsOneWidget);
    await tester.tap(
      find.descendant(of: dialogue, matching: find.text('Comedy')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.regrouperNombre(1)));
    await tester.pumpAndSettle();

    expect(categories.equivalences, <int, int>{5: 4});
    expect(
      find.text(Textes.categoriesRegroupees('Comédie', 1)),
      findsOneWidget,
    );
  });

  testWidgets('une ErreurService du regroupement est affichée', (tester) async {
    await afficher(tester);
    categories.erreurEcriture = const ErreurService(
      "Le regroupement des catégories a échoué : rien n'a été modifié.",
    );

    final carte = find
        .ancestor(
          of: find.text(Textes.suggestion('Survie', 'Survival')),
          matching: find.byType(Card),
        )
        .first; // la carte de la suggestion, pas celle de la section
    await tester.tap(
      find.descendant(of: carte, matching: find.text(Textes.regrouper)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Le regroupement des catégories a échoué : rien n'a été "
        'modifié.',
      ),
      findsOneWidget,
    );
    expect(categories.equivalences, isEmpty);
  });

  testWidgets('une erreur de lecture propose « Réessayer »', (tester) async {
    categories.erreurLecture = const ErreurService(
      "Les catégories n'ont pas pu être lues.",
    );
    await afficher(tester);

    expect(find.text(Textes.reessayer), findsWidgets);
    categories.erreurLecture = null;
    await tester.tap(find.text(Textes.reessayer).last);
    await tester.pumpAndSettle();
    expect(find.text(Textes.aucunGroupe), findsOneWidget);
  });

  testWidgets('panneau des filtres : une puce par groupe, autres noms '
      'dessous', (tester) async {
    categories.regrouperDeTest(3, <int>[1]);
    await tester.pumpWidget(
      envelopper(
        const Scaffold(body: PanneauCategories()),
        bibliotheque: bibliotheque,
        categories: categories,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Survie'), findsOneWidget);
    expect(find.text('Survival'), findsOneWidget);
    expect(find.byType(PuceCategorieTroisEtats), findsNWidgets(4));

    await tester.enterText(find.byType(TextField), 'survival');
    await tester.pumpAndSettle();
    expect(find.byType(PuceCategorieTroisEtats), findsOneWidget);
    expect(find.text('Survie'), findsOneWidget);
  });
}
