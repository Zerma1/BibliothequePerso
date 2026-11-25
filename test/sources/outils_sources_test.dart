import 'package:bibliotheque_perso/sources/outils_sources.dart';
import 'package:bibliotheque_perso/sources/source_mangadex.dart';
import 'package:bibliotheque_perso/sources/source_webtoons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convertirNumero : même résultat que SourceMangaDex', () {
    for (final texte in <String?>[null, '', '10.5', '12a', '10,5', '1e3']) {
      expect(
        OutilsSources.convertirNumero(texte),
        SourceMangaDex.convertirNumero(texte),
        reason: texte,
      );
    }
    expect(OutilsSources.convertirNumero('Chapitre 7,5'), 7.5);
  });

  test('convertirDateAvecMois : même résultat que SourceWebtoons', () {
    for (final texte in <String>['13 nov. 2026', 'Dec 22, 2024', 'x']) {
      expect(
        OutilsSources.convertirDateAvecMois(texte),
        SourceWebtoons.convertirDate(texte),
        reason: texte,
      );
    }
    expect(
      OutilsSources.convertirDateAvecMois('1 janvier 2020'),
      DateTime.utc(2020),
    );
  });

  test('dateValide : refuse les jours absents du mois', () {
    expect(OutilsSources.dateValide(2025, 2, 31), isNull);
    expect(OutilsSources.dateValide(2025, 2, 29), isNull);
    expect(OutilsSources.dateValide(2024, 2, 29), DateTime.utc(2024, 2, 29));
    expect(OutilsSources.dateValide(2024, 13, 1), isNull);
    expect(OutilsSources.dateValide(2024, 6, 0), isNull);
    expect(OutilsSources.dateValide(2024, 6, 30), DateTime.utc(2024, 6, 30));
  });
}
