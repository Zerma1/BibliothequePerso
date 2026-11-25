// Tests de la tâche R4 sur le modèle : Chapitre.urlExterne et estExterne.
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const heberge = Chapitre(
    id: 1,
    idTitre: 2,
    urlChapitre: 'https://mangadex.org/chapter/1',
    nom: 'Chapitre 1',
    numero: 1,
  );
  final externe = heberge.copierAvec(
    urlExterne: 'https://editeur.example/ruri/1',
  );

  test('par défaut, un chapitre est hébergé', () {
    expect(heberge.urlExterne, isNull);
    expect(heberge.estExterne, isFalse);
    expect(heberge.versMap()['url_externe'], isNull);
  });

  test('estExterne : vrai seulement pour un lien non vide', () {
    expect(externe.estExterne, isTrue);
    expect(heberge.copierAvec(urlExterne: '').estExterne, isFalse);
    expect(heberge.copierAvec(urlExterne: '   ').estExterne, isFalse);
  });

  test('aller-retour versMap / depuisMap', () {
    final map = externe.versMap();
    expect(map['url_externe'], 'https://editeur.example/ruri/1');
    expect(Chapitre.depuisMap(map), externe);
  });

  test('colonne absente (base avant la migration 6) : hébergé', () {
    final map = externe.versMap()..remove('url_externe');
    expect(Chapitre.depuisMap(map).urlExterne, isNull);
  });

  test('type invalide : erreur', () {
    final map = externe.versMap()..['url_externe'] = 12;
    expect(() => Chapitre.depuisMap(map), throwsA(isA<ErreurBaseDeDonnees>()));
  });

  test('copierAvec : effacerUrlExterne remet à null et l\'emporte', () {
    expect(externe.copierAvec().urlExterne, externe.urlExterne);
    expect(externe.copierAvec(nom: 'x').urlExterne, externe.urlExterne);
    expect(externe.copierAvec(effacerUrlExterne: true), heberge);
    expect(
      externe
          .copierAvec(
            urlExterne: 'https://autre.example',
            effacerUrlExterne: true,
          )
          .urlExterne,
      isNull,
    );
  });

  test('== et hashCode tiennent compte du lien externe', () {
    expect(externe, isNot(heberge));
    expect(
      heberge.copierAvec(urlExterne: 'https://editeur.example/ruri/1'),
      externe,
    );
    expect(
      heberge.copierAvec(urlExterne: 'https://editeur.example/ruri/1').hashCode,
      externe.hashCode,
    );
  });
}
