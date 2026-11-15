// Test minimal de démarrage : vérifie que l'application se construit sans erreur
// et affiche son titre.

import 'package:flutter_test/flutter_test.dart';

import 'package:bibliotheque_perso/main.dart';

void main() {
  testWidgets("l'application démarre et affiche le titre", (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BibliothequePersoApp());

    expect(find.text('Bibliothèque perso'), findsOneWidget);
  });
}
