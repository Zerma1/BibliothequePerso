// Tests des textes de durée : conservation avant suppression réglable
// (1 h à 30 jours) et compte à rebours des suppressions prévues.
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/widgets/constantes_interface.dart';
import 'package:bibliotheque_perso/widgets/jauge_reglage.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('durée courte des crans de la jauge', () {
    expect(
      <String>[
        for (final delai in EtatParametres.delaisSuppressionProposes)
          Textes.dureeCourte(delai),
      ],
      <String>[
        '1 h',
        '6 h',
        '12 h',
        '24 h',
        '2 jours',
        '3 jours',
        '7 jours',
        '14 jours',
        '30 jours',
      ],
    );
    // Valeur hors des crans (écrite par une version future ou à la main).
    expect(Textes.dureeCourte(const Duration(hours: 30)), '1 j 6 h');
  });

  test('durée en toutes lettres dans les phrases', () {
    expect(Textes.dureeEnToutesLettres(const Duration(hours: 1)), '1 heure');
    expect(Textes.dureeEnToutesLettres(const Duration(hours: 24)), '24 heures');
    expect(Textes.dureeEnToutesLettres(const Duration(days: 2)), '2 jours');
    expect(
      Textes.dureeEnToutesLettres(const Duration(hours: 30)),
      '1 jour et 6 heures',
    );
  });

  test('plus aucun « 24 heures » écrit en dur : la durée réglée est '
      'reprise', () {
    const delai = Duration(days: 7);
    expect(
      Textes.legendeSuppressionPrevue(delai),
      'Suppression prévue (7 jours)',
    );
    expect(Textes.explicationLanguesTitre(delai), contains('dans 7 jours'));
    expect(
      Textes.introReglesTelechargement(delai),
      contains('7 jours plus tard'),
    );
    for (final texte in <String>[
      Textes.confirmationRetraitSite(
        nombreNonLusRetires: 0,
        nombreTelecharges: 1,
        delaiSuppression: delai,
      ),
      Textes.confirmationRetraitSite(
        nombreNonLusRetires: 0,
        nombreTelecharges: 3,
        delaiSuppression: delai,
      ),
      Textes.confirmationPassageLienSeul(
        nombreNonLusRetires: 0,
        nombreTelecharges: 1,
        delaiSuppression: delai,
      ),
      Textes.confirmationPassageLienSeul(
        nombreNonLusRetires: 0,
        nombreTelecharges: 3,
        delaiSuppression: delai,
      ),
    ]) {
      expect(texte, contains('dans 7 jours'));
      expect(texte, isNot(contains('24')));
    }
  });

  test('compte à rebours : minutes, heures jusqu\'à 48 h, puis jours', () {
    expect(Textes.suppressionDans(Duration.zero), 'Suppression imminente');
    expect(
      Textes.suppressionDans(const Duration(minutes: 42)),
      'Supprimé dans 42 min',
    );
    expect(
      Textes.suppressionDans(const Duration(hours: 5, minutes: 3)),
      'Supprimé dans 5 h 03',
    );
    expect(
      Textes.suppressionDans(const Duration(hours: 47, minutes: 59)),
      'Supprimé dans 47 h 59',
    );
    expect(
      Textes.suppressionDans(const Duration(days: 6, hours: 4, minutes: 30)),
      'Supprimé dans 6 j 4 h',
    );
  });

  test('crans des limites : de 0 (ou 1) à la borne du service', () {
    expect(cransLimitesTelechargement.last, EtatParametres.limiteMaximale);
    final avecZero = cransLimite(0, EtatParametres.limiteMaximale);
    expect(avecZero.first, 0);
    expect(avecZero.last, 500);
    final depuisUn = cransLimite(1, EtatParametres.limiteMaximale);
    expect(depuisUn.first, 1);
    expect(depuisUn, isNot(contains(0)));
    // Strictement croissants, sans doublon.
    for (var index = 1; index < avecZero.length; index++) {
      expect(avecZero[index], greaterThan(avecZero[index - 1]));
    }
    expect(cransReguliers(1, 4), <int>[1, 2, 3, 4]);
  });
}
