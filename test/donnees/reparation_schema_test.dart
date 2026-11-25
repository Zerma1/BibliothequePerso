/// Tests de la réparation de la version du schéma (incident 0.2.4 : base au
/// schéma 13 marquée 6 par une ancienne version de l'application) et du refus
/// d'ouverture par une version plus ancienne.
library;

import 'dart:io';

import 'package:bibliotheque_perso/donnees/base_de_donnees.dart';
import 'package:bibliotheque_perso/donnees/migrations.dart';
import 'package:bibliotheque_perso/donnees/reparation_schema.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as chemins;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ouvre (ou crée) la base [chemin] directement au schéma [version].
Future<Database> _ouvrirAuSchema(String chemin, int version) =>
    databaseFactoryFfi.openDatabase(
      chemin,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) => appliquerMigrations(db, 0, v),
      ),
    );

/// Écrit [version] dans `user_version` sans rien d'autre, comme l'a fait
/// sqflite dans l'ancienne version de l'application.
Future<void> _marquerVersion(String chemin, int version) async {
  final db = await databaseFactoryFfi.openDatabase(chemin);
  await db.execute('PRAGMA user_version = $version');
  await db.close();
}

/// Version enregistrée dans le fichier [chemin].
Future<int> _lireVersion(String chemin) async {
  final db = await databaseFactoryFfi.openDatabase(chemin);
  final version = await db.getVersion();
  await db.close();
  return version;
}

/// Insère une source, un titre et un chapitre (colonnes présentes dès la
/// migration 1) ; renvoie l'identifiant du titre.
Future<int> _insererDonnees(Database db) async {
  final idSource = await db.insert('sources', <String, Object?>{
    'nom': 'MangaDex',
    'url_base': 'https://mangadex.org',
    'type_source': 'mangaDex',
  });
  final idTitre = await db.insert('titres', <String, Object?>{
    'id_source': idSource,
    'url_titre': 'https://mangadex.org/title/abc',
    'nom': 'Titre conservé',
    'type_titre': 'manga',
  });
  await db.insert('chapitres', <String, Object?>{
    'id_titre': idTitre,
    'url_chapitre': 'https://mangadex.org/chapter/1',
    'nom': 'Chapitre 1',
    'numero': 1.0,
    'est_lu': 1,
  });
  await db.insert('listes', <String, Object?>{'nom': 'Ma liste', 'ordre': 9});
  return idTitre;
}

/// Noms de toutes les tables, index et déclencheurs (hors objets internes).
Future<Set<String>> _objetsSchema(Database db) async {
  final lignes = await db.rawQuery(
    'SELECT type, name FROM sqlite_master '
    "WHERE name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return lignes.map((l) => '${l['type']} ${l['name']}').toSet();
}

/// Noms et indicateurs système des listes, triés.
Future<List<String>> _listes(Database db) async {
  final lignes = await db.query('listes', orderBy: 'nom');
  return lignes.map((l) => '${l['nom']}:${l['est_systeme']}').toList();
}

void main() {
  sqfliteFfiInit();

  late Directory dossier;
  late String chemin;
  late JournalMemoire journal;
  late Set<String> objetsReference;

  setUpAll(() async {
    final reference = await ouvrirBaseDeDonnees(
      chemin: inMemoryDatabasePath,
      fabrique: databaseFactoryFfi,
    );
    objetsReference = await _objetsSchema(reference);
    await reference.close();
  });

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('reparation_schema_test_');
    chemin = chemins.join(dossier.path, 'base.db');
    journal = JournalMemoire();
    Journal.actuel = journal;
  });

  tearDown(() async {
    Journal.actuel = const JournalSilencieux();
    await dossier.delete(recursive: true);
  });

  Future<Database> ouvrir({int? versionDemandee}) => ouvrirBaseDeDonnees(
    chemin: chemin,
    fabrique: databaseFactoryFfi,
    versionDemandee: versionDemandee,
  );

  List<EntreeJournal> avertissementsBase() => journal.entrees
      .where(
        (e) =>
            e.niveau == NiveauJournal.avertissement &&
            e.categorie == CategorieJournal.base,
      )
      .toList();

  group('detecterNiveauSchema', () {
    for (var niveau = 0; niveau <= versionSchema; niveau++) {
      test('reconnaît une base réellement au schéma $niveau', () async {
        final db = niveau == 0
            ? await databaseFactoryFfi.openDatabase(inMemoryDatabasePath)
            : await databaseFactoryFfi.openDatabase(
                inMemoryDatabasePath,
                options: OpenDatabaseOptions(
                  version: niveau,
                  onCreate: (db, v) => appliquerMigrations(db, 0, v),
                ),
              );
        expect(await detecterNiveauSchema(db), niveau);
        await db.close();
      });
    }
  });

  test('base au schéma 13 marquée 6 : ouverture réussie, données '
      'conservées, version 13', () async {
    final v13 = await ouvrir();
    final idTitre = await _insererDonnees(v13);
    await v13.update(
      'titres',
      <String, Object?>{'description_perso': 'Ma note'},
      where: 'id = ?',
      whereArgs: <Object?>[idTitre],
    );
    final listesAvant = await _listes(v13);
    await v13.close();
    // Reproduction exacte de l'incident.
    await _marquerVersion(chemin, 6);

    final db = await ouvrir();
    expect(await db.getVersion(), versionSchema);
    expect(await _objetsSchema(db), objetsReference);
    expect(await _listes(db), listesAvant);
    final titres = await db.query('titres');
    expect(titres.single['nom'], 'Titre conservé');
    expect(titres.single['description_perso'], 'Ma note');
    final chapitres = await db.query('chapitres');
    expect(chapitres.single['est_lu'], 1);
    expect(chapitres.single['origine'], 'site');
    expect(await db.query('titres_sources'), hasLength(1));
    await db.close();

    final avertissements = avertissementsBase();
    expect(avertissements, hasLength(1));
    expect(avertissements.single.message, contains('enregistrée 6'));
    expect(avertissements.single.message, contains('réelle 13'));
    expect(avertissements.single.message, contains('aucun'));

    // Ouverture suivante : plus rien à réparer.
    journal.entrees.clear();
    final encore = await ouvrir();
    expect(await encore.getVersion(), versionSchema);
    await encore.close();
    expect(avertissementsBase(), isEmpty);
  });

  test('base au schéma 13 marquée 0 (tables présentes) : pas de onCreate '
      'sur les tables existantes, données conservées', () async {
    final v13 = await ouvrir();
    await _insererDonnees(v13);
    await v13.close();
    await _marquerVersion(chemin, 0);

    final db = await ouvrir();
    expect(await db.getVersion(), versionSchema);
    expect(await _objetsSchema(db), objetsReference);
    expect((await db.query('titres')).single['nom'], 'Titre conservé');
    // Listes système non dupliquées.
    expect(
      await db.query('listes', where: 'est_systeme = ?', whereArgs: [1]),
      hasLength(5),
    );
    await db.close();
    expect(avertissementsBase(), hasLength(1));
  });

  test('éléments manquants des migrations sautées recréés, sans toucher '
      'au reste', () async {
    final v13 = await ouvrir();
    await _insererDonnees(v13);
    await v13.execute('DROP TRIGGER declencheur_chapitres_lien_seul_insertion');
    await v13.execute('DROP INDEX index_categories_equivalences_id_reference');
    await v13.delete(
      'listes',
      where: 'nom = ? AND est_systeme = ?',
      whereArgs: <Object?>['Planifié', 1],
    );
    await v13.close();
    await _marquerVersion(chemin, 6);

    final db = await ouvrir();
    expect(await db.getVersion(), versionSchema);
    expect(await _objetsSchema(db), objetsReference);
    final planifie = await db.query(
      'listes',
      where: 'nom = ?',
      whereArgs: <Object?>['Planifié'],
    );
    expect(planifie.single['est_systeme'], 1);
    expect((await db.query('chapitres')).single['nom'], 'Chapitre 1');
    await db.close();

    final message = avertissementsBase().single.message;
    expect(message, contains('declencheur_chapitres_lien_seul_insertion'));
    expect(message, contains('index_categories_equivalences_id_reference'));
    expect(message, contains('Planifié'));
  });

  test('base réellement au schéma 6 : migrations normales, sans '
      'réparation', () async {
    final v6 = await _ouvrirAuSchema(chemin, 6);
    await _insererDonnees(v6);
    await v6.close();

    final db = await ouvrir();
    expect(await db.getVersion(), versionSchema);
    expect(await _objetsSchema(db), objetsReference);
    final ts = await db.query('titres_sources');
    expect(ts.single['est_principale'], 1);
    expect((await db.query('chapitres')).single['id_source'], isNotNull);
    expect(
      await db.query(
        'listes',
        where: 'nom = ? AND est_systeme = ?',
        whereArgs: <Object?>['Terminés', 1],
      ),
      hasLength(1),
    );
    await db.close();
    expect(avertissementsBase(), isEmpty);
  });

  test('base neuve : création normale, sans réparation', () async {
    final db = await ouvrir();
    expect(await db.getVersion(), versionSchema);
    await db.close();
    expect(avertissementsBase(), isEmpty);
  });

  test("version plus ancienne de l'application : erreur claire, base et "
      'version inchangées', () async {
    final v13 = await ouvrir();
    await _insererDonnees(v13);
    await v13.close();

    await expectLater(
      ouvrir(versionDemandee: 6),
      throwsA(
        isA<ErreurBaseDeDonnees>().having(
          (e) => e.message,
          'message',
          "Cette base a été créée par une version plus récente de "
              "l'application (schéma 13) : installez la dernière version.",
        ),
      ),
    );
    expect(await _lireVersion(chemin), versionSchema);

    final db = await ouvrir();
    expect((await db.query('titres')).single['nom'], 'Titre conservé');
    await db.close();
  });

  test('base au schéma 13 marquée 6, ouverte par une version au schéma 10 : '
      'erreur claire, rien de modifié', () async {
    final v13 = await ouvrir();
    await v13.close();
    await _marquerVersion(chemin, 6);

    await expectLater(
      ouvrir(versionDemandee: 10),
      throwsA(
        isA<ErreurBaseDeDonnees>().having(
          (e) => e.message,
          'message',
          contains('schéma 13'),
        ),
      ),
    );
    expect(await _lireVersion(chemin), 6);
  });
}
