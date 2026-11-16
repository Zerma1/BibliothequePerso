import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotCategories depot;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotCategories(base);
  });

  tearDown(() async {
    await base.close();
  });

  test('aucune catégorie dans une base neuve', () async {
    expect(await depot.chargerCategories(), isEmpty);
  });

  test(
    'le nom est normalisé et une catégorie existante est réutilisée',
    () async {
      final premiere = await depot.enregistrerCategorie('  Action ');
      final seconde = await depot.enregistrerCategorie('ACTION');

      expect(premiere.nom, 'action');
      expect(seconde, premiere);
      expect(await depot.chargerCategories(), hasLength(1));
    },
  );

  test('un nom vide est refusé', () async {
    await expectLater(
      depot.enregistrerCategorie('   '),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
  });

  test('deux titres de sites différents partagent la même catégorie', () async {
    final depotSources = DepotSources(base);
    final depotTitres = DepotTitres(base);
    final idMangaDex = (await depotSources.enregistrerSource(sourceMangaDex))
        .id!;
    final idAutre = (await depotSources.enregistrerSource(
      sourceMangaDex.copierAvec(nom: 'Autre', urlBase: 'https://autre.org'),
    )).id!;

    await depotTitres.enregistrerTitre(
      titreReference(idMangaDex),
      categories: <String>['Fantasy'],
    );
    await depotTitres.enregistrerTitre(
      Titre(idSource: idAutre, urlTitre: 'https://autre.org/t', nom: 'Autre'),
      categories: <String>['fantasy '],
    );

    final categories = await depot.chargerCategories();
    expect(categories, hasLength(1));
    expect(
      await depotTitres.chargerTitres(idCategorie: categories.single.id),
      hasLength(2),
    );
  });

  test('les catégories inutilisées sont supprimées, pas les autres', () async {
    final idSource = (await DepotSources(
      base,
    ).enregistrerSource(sourceMangaDex)).id!;
    await DepotTitres(
      base,
    ).enregistrerTitre(titreReference(idSource), categories: <String>['Gore']);
    await depot.enregistrerCategorie('Romance');

    expect(await depot.supprimerCategoriesInutilisees(), 1);
    expect(
      (await depot.chargerCategories()).map((categorie) => categorie.nom),
      <String>['gore'],
    );
  });
}
