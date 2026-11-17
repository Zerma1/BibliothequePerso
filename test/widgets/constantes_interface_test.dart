// Le numéro de version affiché doit suivre celui de pubspec.yaml.
import 'dart:io';

import 'package:bibliotheque_perso/widgets/constantes_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// `X.Y.Z` découpé en trois entiers.
List<int> _decouper(String version) =>
    version.split('.').map(int.parse).toList();

/// Compare deux versions `X.Y.Z` : négatif, zéro ou positif.
int _comparer(String a, String b) {
  final gauche = _decouper(a);
  final droite = _decouper(b);
  for (var i = 0; i < 3; i++) {
    final ecart = gauche[i] - droite[i];
    if (ecart != 0) return ecart;
  }
  return 0;
}

void main() {
  test('versionApplication est au format X.Y.Z et égale ou supérieure à la '
      'version de pubspec.yaml (sans le numéro de build)', () {
    // Tâche T7 : la version affichée passe à la suivante pendant le
    // développement ; pubspec.yaml n'est modifié qu'à la publication. Elle
    // ne doit donc jamais être en retard sur pubspec.yaml.
    // `flutter test` s'exécute à la racine du projet.
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final ligne = pubspec.firstWhere(
      (ligne) => ligne.startsWith('version:'),
      orElse: () => fail('Aucune ligne « version: » dans pubspec.yaml'),
    );
    final version = ligne.substring('version:'.length).trim().split('+').first;

    final format = RegExp(r'^\d+\.\d+\.\d+$');
    expect(format.hasMatch(version), isTrue);
    expect(format.hasMatch(versionApplication), isTrue);
    expect(
      _comparer(versionApplication, version),
      greaterThanOrEqualTo(0),
      reason:
          'versionApplication ($versionApplication) en retard sur '
          'pubspec.yaml ($version)',
    );
  });

  test('la comparaison des versions suit les nombres, pas le texte', () {
    expect(_comparer('0.10.0', '0.9.0'), greaterThan(0));
    expect(_comparer('0.2.0', '0.2.0'), 0);
    expect(_comparer('0.1.9', '0.2.0'), lessThan(0));
  });
}
