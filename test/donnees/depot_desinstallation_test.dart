/// Opérations de la désinstallation partielle :
/// `DepotTitres.supprimerTousLesTitres`,
/// `DepotSources.supprimerSourcesInutilisees` et
/// `DepotChapitres.marquerTousNonTelecharges`.
library;

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
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

  Future<int> compter(String table) async => Sqflite.firstIntValue(
    await base.rawQuery('SELECT COUNT(*) FROM $table'),
  )!;

  /// Insère un chapitre du titre [idTitre] et renvoie son identifiant.
  Future<int> insererChapitre(
    int idTitre,
    String url, {
    bool lu = false,
    String? nomArchive,
    bool garde = false,
    int? dateSuppression,
  }) => base.insert('chapitres', <String, Object?>{
    'id_titre': idTitre,
    'url_chapitre': url,
    'nom': url,
    'numero': 1.0,
    'est_lu': lu ? 1 : 0,
    'est_telecharge': nomArchive == null ? 0 : 1,
    'nom_archive': nomArchive,
    'est_garde': garde ? 1 : 0,
    'date_suppression_prevue': dateSuppression,
  });

  /// Insère une ligne de file pour le chapitre [idChapitre].
  Future<void> insererTelechargement(int idChapitre, String statut) =>
      base.insert('telechargements', <String, Object?>{
        'id_chapitre': idChapitre,
        'statut': statut,
        'date_ajout': 1,
        'date_maj': 1,
      });

  /// Bibliothèque complète : 2 sources, 2 titres (dont un avec un site
  /// secondaire), chapitres, file, listes, catégories.
  Future<({int source1, int source2, int titre1, int titre2})> remplir() async {
    final source1 = (await DepotSources(base).enregistrerSource(sourceMangaDex))
        .id!;
    final source2 = (await DepotSources(base).enregistrerSource(
      const Source(
        nom: 'Autre',
        urlBase: 'https://autre.exemple',
        typeSource: TypeSource.generique,
      ),
    )).id!;
    final titre1 = (await DepotTitres(base).enregistrerTitre(
      titreReference(source1),
      categories: categoriesReference,
    )).id!;
    final titre2 = (await DepotTitres(base).enregistrerTitre(
      titreReference(source2)
          .copierAvec(urlTitre: 'https://autre.exemple/t/2', nom: 'Deuxième'),
      categories: const <String>['Action'],
    )).id!;
    await DepotTitresSources(base)
        .ajouterSourceSecondaire(titre1, source2, 'https://autre.exemple/t/1');
    final c1 = await insererChapitre(
      titre1,
      'https://mangadex.org/c/1',
      lu: true,
      nomArchive: 'manga/A/ch1.en.zip',
      garde: true,
    );
    final c2 = await insererChapitre(
      titre1,
      'https://mangadex.org/c/2',
      nomArchive: 'manga/A/ch2.en.zip',
      dateSuppression: 123,
    );
    await insererChapitre(titre2, 'https://autre.exemple/c/1', lu: true);
    await insererTelechargement(c1, 'termine');
    await insererTelechargement(c2, 'en_attente');
    final listes = DepotListes(base);
    final perso = await listes.creerListe('Ma liste');
    final favoris = (await listes.chargerListes()).first;
    await listes.ajouterTitre(perso.id!, titre1);
    await listes.ajouterTitre(favoris.id!, titre2);
    return (source1: source1, source2: source2, titre1: titre1, titre2: titre2);
  }

  group('supprimerTousLesTitres', () {
    test('supprime les titres et tout ce qui en dépend, garde les listes, '
        'les sources et les catégories', () async {
      await remplir();
      final listesAvant = await compter('listes');
      final categoriesAvant = await compter('categories');

      expect(await DepotTitres(base).supprimerTousLesTitres(), 2);

      for (final table in <String>[
        'titres',
        'chapitres',
        'telechargements',
        'titres_alternatifs',
        'titres_listes',
        'titres_categories',
        'titres_sources',
      ]) {
        expect(await compter(table), 0, reason: table);
      }
      expect(await compter('listes'), listesAvant);
      expect(await compter('sources'), 2);
      expect(await compter('categories'), categoriesAvant);
      expect(await DepotCategories(base).chargerCategories(), isNotEmpty);
    });

    test('base sans titre : renvoie 0', () async {
      expect(await DepotTitres(base).supprimerTousLesTitres(), 0);
    });
  });

  group('supprimerSourcesInutilisees', () {
    test('garde les sources encore utilisées par un titre (principal ou '
        'secondaire), ne touche aucun titre', () async {
      final ids = await remplir();
      final inutile = (await DepotSources(base).enregistrerSource(
        const Source(
          nom: 'Inutile',
          urlBase: 'https://inutile.exemple',
          typeSource: TypeSource.madara,
        ),
      )).id!;

      final resultat = await DepotSources(base).supprimerSourcesInutilisees();

      expect(resultat.supprimees, 1);
      expect(resultat.gardees, 2);
      expect(await DepotSources(base).chargerSource(inutile), isNull);
      expect(await DepotSources(base).chargerSource(ids.source1), isNotNull);
      expect(await DepotSources(base).chargerSource(ids.source2), isNotNull);
      expect(await compter('titres'), 2);
      expect(await compter('titres_sources'), 3);
      expect(await compter('chapitres'), 3);
    });

    test('garde une source dont seuls des chapitres viennent encore', () async {
      final ids = await remplir();
      // Le titre 1 ne garde que son site principal ; ses chapitres
      // viennent maintenant du site 2 (chapitres lus gardés après le
      // retrait d'un site).
      await base.delete(
        'titres_sources',
        where: 'id_titre = ? AND id_source = ?',
        whereArgs: <Object?>[ids.titre1, ids.source2],
      );
      await base.delete(
        'titres',
        where: 'id = ?',
        whereArgs: <Object?>[ids.titre2],
      );
      await base.update(
        'chapitres',
        <String, Object?>{'id_source': ids.source2},
        where: 'id_titre = ?',
        whereArgs: <Object?>[ids.titre1],
      );

      final resultat = await DepotSources(base).supprimerSourcesInutilisees();

      expect(resultat.supprimees, 0);
      expect(resultat.gardees, 2);
    });

    test('après supprimerTousLesTitres, toutes les sources partent', () async {
      await remplir();
      await DepotTitres(base).supprimerTousLesTitres();

      final resultat = await DepotSources(base).supprimerSourcesInutilisees();

      expect(resultat, (supprimees: 2, gardees: 0));
      expect(await compter('sources'), 0);
    });
  });

  group('marquerTousNonTelecharges', () {
    test("remet tous les chapitres à « non téléchargé » sans toucher à "
        "l'état lu, et vide la file", () async {
      await remplir();

      final resultat = await DepotChapitres(base).marquerTousNonTelecharges();

      expect(resultat, (chapitres: 2, telechargements: 2));
      final lignes = await base.query('chapitres', orderBy: 'id');
      expect(lignes, hasLength(3));
      for (final ligne in lignes) {
        expect(ligne['est_telecharge'], 0);
        expect(ligne['nom_archive'], isNull);
        expect(ligne['date_suppression_prevue'], isNull);
        expect(ligne['est_garde'], 0);
      }
      expect(lignes.map((ligne) => ligne['est_lu']), <Object?>[1, 0, 1]);
      expect(await compter('telechargements'), 0);
      expect(await DepotChapitres(base).chargerChapitresTelecharges(), isEmpty);
    });

    test('viderFile: false garde la file', () async {
      await remplir();

      final resultat = await DepotChapitres(base)
          .marquerTousNonTelecharges(viderFile: false);

      expect(resultat, (chapitres: 2, telechargements: 0));
      expect(await compter('telechargements'), 2);
    });

    test('second appel : rien à changer', () async {
      await remplir();
      await DepotChapitres(base).marquerTousNonTelecharges();

      expect(await DepotChapitres(base).marquerTousNonTelecharges(), (
        chapitres: 0,
        telechargements: 0,
      ));
    });
  });
}
