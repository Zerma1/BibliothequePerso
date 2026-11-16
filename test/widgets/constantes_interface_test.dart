// Le numéro de version affiché doit suivre celui de pubspec.yaml.
import 'dart:io';

import 'package:bibliotheque_perso/widgets/constantes_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'versionApplication = version de pubspec.yaml sans le numéro de build',
    () {
      // `flutter test` s'exécute à la racine du projet.
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      final ligne = pubspec.firstWhere(
        (ligne) => ligne.startsWith('version:'),
        orElse: () => fail('Aucune ligne « version: » dans pubspec.yaml'),
      );
      final version = ligne
          .substring('version:'.length)
          .trim()
          .split('+')
          .first;

      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version), isTrue);
      expect(versionApplication, version);
    },
  );
}
