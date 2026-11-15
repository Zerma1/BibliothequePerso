import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotParametres depot;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotParametres(base);
  });

  tearDown(() async {
    await base.close();
  });

  test('une base neuve ne contient aucun réglage', () async {
    expect(await depot.chargerTout(), isEmpty);
    expect(await depot.chargerTexte('absent'), isNull);
    expect(await depot.chargerEntier('absent'), isNull);
  });

  test('un texte enregistré est relu puis remplacé', () async {
    await depot.enregistrerTexte('dossier', r'D:\Mangas « été »');
    expect(await depot.chargerTexte('dossier'), r'D:\Mangas « été »');
    await depot.enregistrerTexte('dossier', '');
    expect(await depot.chargerTexte('dossier'), '');
    expect(await depot.chargerTout(), <String, String>{'dossier': ''});
  });

  test('un entier enregistré est relu, y compris négatif', () async {
    await depot.enregistrerEntier('intervalle', 60);
    expect(await depot.chargerEntier('intervalle'), 60);
    expect(await depot.chargerTexte('intervalle'), '60');
    await depot.enregistrerEntier('intervalle', -3);
    expect(await depot.chargerEntier('intervalle'), -3);
  });

  test('un entier illisible est lu comme null', () async {
    await depot.enregistrerTexte('intervalle', 'une heure');
    expect(await depot.chargerEntier('intervalle'), isNull);
    await depot.enregistrerTexte('intervalle', '1.5');
    expect(await depot.chargerEntier('intervalle'), isNull);
  });

  test('supprimer retire le réglage', () async {
    await depot.enregistrerTexte('theme', 'sombre');
    expect(await depot.supprimer('theme'), isTrue);
    expect(await depot.chargerTexte('theme'), isNull);
    expect(await depot.supprimer('theme'), isFalse);
  });

  test('chargerTout renvoie tous les réglages triés par clé', () async {
    await depot.enregistrerTexte('b', '2');
    await depot.enregistrerEntier('a', 1);
    expect(await depot.chargerTout(), <String, String>{'a': '1', 'b': '2'});
    expect((await depot.chargerTout()).keys.toList(), <String>['a', 'b']);
  });

  test(
    'une clé contenant des caractères SQL est traitée littéralement',
    () async {
      const cle = "x'; DROP TABLE parametres; --";
      await depot.enregistrerTexte(cle, 'valeur');
      expect(await depot.chargerTexte(cle), 'valeur');
      expect(await depot.chargerTout(), hasLength(1));
    },
  );
}
