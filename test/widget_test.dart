// Test de démarrage : l'application complète se construit avec de faux
// services (ni base ni réseau) et affiche la bibliothèque vide.

import 'package:bibliotheque_perso/main.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'etat/outils_tests_etat.dart';

void main() {
  testWidgets("l'application démarre sur la bibliothèque", (
    WidgetTester tester,
  ) async {
    final bibliotheque = FauxServiceBibliotheque();
    await tester.pumpWidget(
      construireApplication(
        serviceBibliotheque: bibliotheque,
        serviceAjoutSite: FauxServiceAjoutSite(bibliotheque),
      ),
    );
    await tester.pump();

    expect(find.text(Textes.ongletBibliotheque), findsWidgets);
    expect(find.text(Textes.bibliothequeVide), findsOneWidget);
  });
}
