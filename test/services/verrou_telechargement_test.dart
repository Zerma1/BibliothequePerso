// Règles pures du verrou de la file de téléchargement (aucune base).
import 'package:bibliotheque_perso/services/verrou_telechargement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final expiration = DateTime.utc(2026, 11, 15, 12);
  final verrou = VerrouTelechargement(
    proprietaire: 'application',
    expiration: expiration,
  );

  test('se relit tel quel depuis son texte', () {
    final relu = VerrouTelechargement.depuisTexte(verrou.versTexte());
    expect(relu!.proprietaire, 'application');
    expect(relu.expiration, expiration);
  });

  test('un texte illisible est traité comme un verrou libre', () {
    expect(VerrouTelechargement.depuisTexte(null), isNull);
    expect(VerrouTelechargement.depuisTexte(''), isNull);
    expect(VerrouTelechargement.depuisTexte('sans-date'), isNull);
    expect(VerrouTelechargement.depuisTexte('|2026-11-15T12:00:00Z'), isNull);
    expect(VerrouTelechargement.depuisTexte('a|pas une date'), isNull);
  });

  test('reste à son propriétaire, même expiré', () {
    expect(
      verrou.estLibrePour(
        'application',
        expiration.add(const Duration(hours: 1)),
      ),
      isTrue,
    );
    expect(
      verrou.estLibrePour(
        'application',
        expiration.subtract(const Duration(hours: 1)),
      ),
      isTrue,
    );
  });

  test("est refusé à un autre avant l'expiration et repris après", () {
    final avant = expiration.subtract(const Duration(seconds: 1));
    expect(verrou.estLibrePour('tache-de-fond', avant), isFalse);
    expect(verrou.estLibrePour('tache-de-fond', expiration), isTrue);
  });
}
