// Tests de widgets du bloc « Ma description » de la fiche d'un titre, avec de
// faux services (aucune base, aucun réseau).
import 'package:bibliotheque_perso/ecrans/ecran_titre.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/bloc_description_perso.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';

void main() {
  late FauxServiceBibliotheque service;

  setUp(() => service = FauxServiceBibliotheque());

  Future<void> afficherFiche(WidgetTester tester, {String? description}) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    service.ajouterTitreDeTest('Shinigami', idSource: 1);
    if (description != null) {
      service.titres[0] = service.titres[0].copierAvec(
        descriptionPerso: description,
      );
    }
    await tester.pumpWidget(
      envelopper(
        ChangeNotifierProvider<EtatTitre>(
          create: (_) => EtatTitre(service, 1)..charger(),
          child: const EcranTitre(),
        ),
        bibliotheque: service,
      ),
    );
    await tester.pump();
  }

  Finder dansBloc(String texte) => find.descendant(
    of: find.byType(BlocDescriptionPerso),
    matching: find.text(texte),
  );

  Finder champ() => find.widgetWithText(TextField, Textes.champDescription);

  testWidgets('la fiche ne propose plus « Modifier la fiche » ; « Ajouter '
      'une description » quand elle est vide', (tester) async {
    await afficherFiche(tester);

    expect(find.byType(BlocDescriptionPerso), findsOneWidget);
    expect(find.text(Textes.maDescription), findsOneWidget);
    expect(dansBloc(Textes.ajouterDescription), findsOneWidget);
    expect(dansBloc(Textes.modifierDescription), findsNothing);
    expect(dansBloc(Textes.effacerDescription), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('ajouter : saisie multi-lignes avec compteur, enregistrement '
      'puis affichage', (tester) async {
    await afficherFiche(tester);

    await tester.tap(dansBloc(Textes.ajouterDescription));
    await tester.pumpAndSettle();
    final saisie = tester.widget<TextField>(champ());
    expect(saisie.maxLength, EtatTitre.longueurMaxDescription);
    expect(saisie.maxLines, greaterThan(1));
    expect(find.text('0/${EtatTitre.longueurMaxDescription}'), findsOneWidget);

    await tester.enterText(champ(), 'Ligne 1\nLigne 2');
    await tester.pump();
    expect(find.text('15/${EtatTitre.longueurMaxDescription}'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, Textes.enregistrer));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(service.titres.single.descriptionPerso, 'Ligne 1\nLigne 2');
    expect(find.text('Ligne 1\nLigne 2'), findsOneWidget);
    expect(find.text(Textes.descriptionEnregistree), findsOneWidget);
    expect(dansBloc(Textes.modifierDescription), findsOneWidget);
    expect(dansBloc(Textes.effacerDescription), findsOneWidget);
    expect(dansBloc(Textes.ajouterDescription), findsNothing);
  });

  testWidgets('modifier : le dialogue reprend le texte ; annuler ne change '
      'rien', (tester) async {
    await afficherFiche(tester, description: 'Ancien texte');

    await tester.tap(dansBloc(Textes.modifierDescription));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(champ()).controller!.text, 'Ancien texte');
    await tester.enterText(champ(), 'Autre chose');
    await tester.tap(find.widgetWithText(TextButton, Textes.annuler));
    await tester.pumpAndSettle();

    expect(service.titres.single.descriptionPerso, 'Ancien texte');
    expect(find.text('Ancien texte'), findsOneWidget);
  });

  testWidgets('effacer demande confirmation', (tester) async {
    await afficherFiche(tester, description: 'À effacer');

    await tester.tap(dansBloc(Textes.effacerDescription));
    await tester.pumpAndSettle();
    expect(find.text(Textes.titreEffacerDescription), findsOneWidget);
    // Annuler : la description reste.
    await tester.tap(find.widgetWithText(TextButton, Textes.annuler));
    await tester.pumpAndSettle();
    expect(service.titres.single.descriptionPerso, 'À effacer');

    await tester.tap(dansBloc(Textes.effacerDescription));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, Textes.effacerDescription),
    );
    await tester.pumpAndSettle();

    expect(service.titres.single.descriptionPerso, isNull);
    expect(find.text(Textes.descriptionEffacee), findsOneWidget);
    expect(dansBloc(Textes.ajouterDescription), findsOneWidget);
  });

  testWidgets('refus du service : message dans le dialogue, texte gardé', (
    tester,
  ) async {
    await afficherFiche(tester);
    service.erreurDescription = const ErreurService(
      'La description est trop longue (5000 caractères au plus).',
    );

    await tester.tap(dansBloc(Textes.ajouterDescription));
    await tester.pumpAndSettle();
    await tester.enterText(champ(), 'Mon texte');
    await tester.tap(find.widgetWithText(FilledButton, Textes.enregistrer));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('trop longue'), findsOneWidget);
    expect(tester.widget<TextField>(champ()).controller!.text, 'Mon texte');
    expect(service.titres.single.descriptionPerso, isNull);
  });

  testWidgets('échec de l\'effacement : erreur affichée', (tester) async {
    await afficherFiche(tester, description: 'Gardée');
    service.erreurDescription = const ErreurService("Ce titre n'existe plus.");

    await tester.tap(dansBloc(Textes.effacerDescription));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, Textes.effacerDescription),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Ce titre n'existe plus."), findsOneWidget);
    expect(service.titres.single.descriptionPerso, 'Gardée');
  });
}
