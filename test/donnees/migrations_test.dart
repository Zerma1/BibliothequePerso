import 'package:bibliotheque_perso/donnees/migrations.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;

  setUp(() async {
    base = await ouvrirBaseDeTest();
  });

  tearDown(() async {
    await base.close();
  });

  test('la version du schéma est 1 et correspond à la base ouverte', () async {
    expect(versionSchema, 1);
    expect(await base.getVersion(), versionSchema);
  });

  test('la migration 1 crée toutes les tables du playbook', () async {
    final lignes = await base.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    final tables = lignes.map((ligne) => ligne['name']).toSet();
    expect(
      tables,
      containsAll(<String>[
        'sources',
        'titres',
        'chapitres',
        'titres_alternatifs',
        'listes',
        'titres_listes',
        'categories',
        'titres_categories',
      ]),
    );
  });

  test('les clés étrangères sont actives à l\'ouverture', () async {
    final lignes = await base.rawQuery('PRAGMA foreign_keys');
    expect(lignes.first.values.first, 1);
  });

  test('la migration 1 crée Favoris et Suivis en listes système', () async {
    final lignes = await base.query('listes', orderBy: 'ordre');
    expect(lignes, hasLength(2));
    // La migration écrit ces valeurs en dur : ce test garantit qu'elles
    // restent alignées avec les constantes utilisées par le reste du code.
    expect(lignes[0]['nom'], nomListeFavoris);
    expect(lignes[0]['est_systeme'], 1);
    expect(lignes[0]['ordre'], ordreListeFavoris);
    expect(lignes[1]['nom'], nomListeSuivis);
    expect(lignes[1]['est_systeme'], 1);
    expect(lignes[1]['ordre'], ordreListeSuivis);
  });

  test('un titre ne peut pas référencer une source inexistante', () async {
    await expectLater(
      base.insert('titres', <String, Object?>{
        'id_source': 999,
        'url_titre': 'https://exemple.org/titre',
        'nom': 'Orphelin',
        'type_titre': 'manga',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
