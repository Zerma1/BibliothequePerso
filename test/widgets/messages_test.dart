// Tests de afficherResultat : un refus du service (phrase longue) reste
// affiché plus longtemps et peut être fermé.
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/messages.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const String _messageDeplacement =
    'Les chapitres sont en cours de déplacement vers un autre dossier : '
    'terminez (ou abandonnez) ce déplacement dans les Paramètres avant de '
    'supprimer des chapitres téléchargés.';

void main() {
  Future<void> appuyer(
    WidgetTester tester,
    ResultatAction<bool> resultat,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  afficherResultat(context, resultat, succes: 'Supprimé'),
              child: const Text('Agir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Agir'));
    await tester.pumpAndSettle();
  }

  testWidgets('un refus affiche le message du service, fermable', (
    tester,
  ) async {
    await appuyer(
      tester,
      ResultatAction<bool>.echec(
        DescriptionErreur.depuis(const ErreurService(_messageDeplacement)),
      ),
    );

    expect(find.text(_messageDeplacement), findsOneWidget);
    expect(find.text(Textes.erreurInattendue), findsNothing);
    final barre = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(barre.duration, dureeMessageErreur);
    expect(barre.showCloseIcon, isTrue);

    // Toujours visible après les 4 s d'un message ordinaire.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text(_messageDeplacement), findsOneWidget);
  });

  testWidgets('une réussite garde la barre ordinaire', (tester) async {
    await appuyer(tester, const ResultatAction<bool>.reussite(true));

    final barre = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(find.text('Supprimé'), findsOneWidget);
    expect(barre.showCloseIcon, isNot(isTrue));
  });
}
