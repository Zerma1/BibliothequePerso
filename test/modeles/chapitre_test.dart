import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final chapitre = Chapitre(
    id: 5,
    idTitre: 7,
    urlChapitre: 'https://mangadex.org/chapter/abc',
    nom: 'Chapitre 10.5',
    numero: 10.5,
    langue: 'fr',
    datePublication: DateTime.utc(2026, 1, 2),
    estLu: true,
    dateDetection: DateTime.utc(2026, 1, 3),
  );

  test('versMap puis depuisMap redonne le même chapitre', () {
    final map = chapitre.versMap();
    expect(map['est_lu'], 1);
    expect(map['est_telecharge'], 0);
    expect(Chapitre.depuisMap(map), chapitre);
  });

  test('un numéro entier renvoyé par SQLite est converti en double', () {
    final map = chapitre.versMap()..['numero'] = 3;
    expect(Chapitre.depuisMap(map).numero, 3.0);
  });

  test('les dates sont relues en UTC', () {
    final local = chapitre.copierAvec(datePublication: DateTime(2026, 5, 1));
    final relu = Chapitre.depuisMap(local.versMap());
    expect(relu.datePublication!.isUtc, isTrue);
    expect(
      relu.datePublication!.isAtSameMomentAs(local.datePublication!),
      isTrue,
    );
  });

  test('copierAvec, == et hashCode sont cohérents', () {
    final telecharge = chapitre.copierAvec(estTelecharge: true);
    expect(telecharge.estTelecharge, isTrue);
    expect(telecharge, isNot(chapitre));
    expect(chapitre.copierAvec(), chapitre);
    expect(chapitre.copierAvec().hashCode, chapitre.hashCode);
  });

  test('nomArchive et dateSuppressionPrevue : aller-retour et effacement', () {
    final telecharge = chapitre.copierAvec(
      estTelecharge: true,
      nomArchive: 'manga/One Punch Man/ch10.5.fr.2.zip',
      dateSuppressionPrevue: DateTime.utc(2026, 11, 17, 9),
    );
    final map = telecharge.versMap();
    expect(map['nom_archive'], 'manga/One Punch Man/ch10.5.fr.2.zip');
    expect(
      map['date_suppression_prevue'],
      DateTime.utc(2026, 11, 17, 9).millisecondsSinceEpoch,
    );
    final relu = Chapitre.depuisMap(map);
    expect(relu, telecharge);
    expect(relu.dateSuppressionPrevue!.isUtc, isTrue);
    expect(relu, isNot(chapitre));

    // Valeurs absentes en base (NULL) : null.
    expect(chapitre.versMap()['nom_archive'], isNull);
    expect(chapitre.versMap()['date_suppression_prevue'], isNull);

    // copierAvec sans argument garde les valeurs ; effacer… les remet à null.
    expect(telecharge.copierAvec(), telecharge);
    final efface = telecharge.copierAvec(
      effacerNomArchive: true,
      effacerDateSuppressionPrevue: true,
    );
    expect(efface.nomArchive, isNull);
    expect(efface.dateSuppressionPrevue, isNull);
    expect(efface.estTelecharge, isTrue);
    // L'indicateur l'emporte sur la valeur donnée.
    expect(
      telecharge
          .copierAvec(nomArchive: 'x', effacerNomArchive: true)
          .nomArchive,
      isNull,
    );
    // Les deux indicateurs sont indépendants.
    final sansSuppression = telecharge.copierAvec(
      effacerDateSuppressionPrevue: true,
    );
    expect(sansSuppression.nomArchive, telecharge.nomArchive);
    expect(sansSuppression.dateSuppressionPrevue, isNull);
  });

  test('un nom_archive mal typé lève une ErreurBaseDeDonnees', () {
    final map = chapitre.versMap()..['nom_archive'] = 12;
    expect(() => Chapitre.depuisMap(map), throwsA(isA<ErreurBaseDeDonnees>()));
  });

  test('un numéro sous forme de texte lève une ErreurBaseDeDonnees', () {
    final map = chapitre.versMap()..['numero'] = '10';
    expect(() => Chapitre.depuisMap(map), throwsA(isA<ErreurBaseDeDonnees>()));
  });

  test('un chapitre sans idTitre (construit par un adaptateur) fait '
      'l\'aller-retour', () {
    const sansTitre = Chapitre(urlChapitre: 'u', nom: 'Chapitre 1', numero: 1);
    expect(sansTitre.idTitre, isNull);
    expect(sansTitre.versMap()['id_titre'], isNull);
    expect(Chapitre.depuisMap(sansTitre.versMap()), sansTitre);
    expect(sansTitre.copierAvec(idTitre: 4).idTitre, 4);
  });

  test('toString mentionne le numéro', () {
    expect(chapitre.toString(), contains('10.5'));
  });
}
