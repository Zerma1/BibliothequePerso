import 'dart:io';

import 'package:bibliotheque_perso/donnees/base_de_donnees.dart';
import 'package:bibliotheque_perso/donnees/migrations.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  test('la version du schéma est 15 et correspond à la base ouverte', () async {
    expect(versionSchema, 15);
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
    // + Planifié et En attente (migration 5), Terminés (migration 11).
    expect(lignes, hasLength(5));
    // La migration écrit ces valeurs en dur : ce test garantit qu'elles
    // restent alignées avec les constantes utilisées par le reste du code.
    expect(lignes[0]['nom'], nomListeFavoris);
    expect(lignes[0]['est_systeme'], 1);
    expect(lignes[0]['ordre'], ordreListeFavoris);
    expect(lignes[1]['nom'], nomListeSuivis);
    expect(lignes[1]['est_systeme'], 1);
    expect(lignes[1]['ordre'], ordreListeSuivis);
  });

  test('la migration 2 crée la table telechargements et son index', () async {
    final tables = await base.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>['telechargements'],
    );
    expect(tables, hasLength(1));
    final index = await base.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
      <Object?>['index_telechargements_statut'],
    );
    expect(index, hasLength(1));
  });

  test(
    'la migration 1 → 2 conserve les données d\'une base existante',
    () async {
      // Une base en mémoire disparaît à la fermeture : pour tester une vraie
      // mise à niveau (onUpgrade), il faut un fichier, ici dans un dossier
      // temporaire supprimé à la fin.
      final dossier = await Directory.systemTemp.createTemp('migration_test_');
      final chemin = p.join(dossier.path, 'version1.db');
      try {
        final version1 = await databaseFactoryFfi.openDatabase(
          chemin,
          options: OpenDatabaseOptions(
            version: 1,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            // Uniquement la migration 1, comme une installation d'avant
            // l'étape 5.
            onCreate: (db, version) => appliquerMigrations(db, 0, 1),
          ),
        );
        final idSource = await version1.insert('sources', <String, Object?>{
          'nom': 'MangaDex',
          'url_base': 'https://mangadex.org',
          'type_source': 'mangaDex',
        });
        final idTitre = await version1.insert('titres', <String, Object?>{
          'id_source': idSource,
          'url_titre': 'https://mangadex.org/title/abc',
          'nom': 'Titre existant',
          'type_titre': 'manga',
        });
        final idChapitre = await version1.insert('chapitres', <String, Object?>{
          'id_titre': idTitre,
          'url_chapitre': 'https://mangadex.org/chapter/1',
          'nom': 'Chapitre 1',
          'numero': 1.0,
          'langue': 'en',
          'est_lu': 1,
        });
        expect(await version1.getVersion(), 1);
        await version1.close();

        // Réouverture avec le code actuel : onUpgrade applique la migration 2.
        final version2 = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        try {
          // Toutes les migrations suivantes sont appliquées.
          expect(await version2.getVersion(), versionSchema);
          final chapitres = await version2.query('chapitres');
          expect(chapitres.single['nom'], 'Chapitre 1');
          expect(chapitres.single['est_lu'], 1);
          expect(
            (await version2.query('titres')).single['nom'],
            'Titre existant',
          );
          expect(await version2.query('listes'), hasLength(5));
          expect(await version2.query('telechargements'), isEmpty);

          // La nouvelle table est utilisable avec les données existantes.
          await version2.insert('telechargements', <String, Object?>{
            'id_chapitre': idChapitre,
            'date_ajout': 0,
            'date_maj': 0,
          });
          final ligne = (await version2.query('telechargements')).single;
          expect(ligne['statut'], 'en_attente');
          expect(ligne['nombre_pages_faites'], 0);
        } finally {
          await version2.close();
        }
      } finally {
        await dossier.delete(recursive: true);
      }
    },
  );

  test(
    'la migration 2 → 3 conserve les données et ajoute parametres',
    () async {
      final dossier = await Directory.systemTemp.createTemp('migration3_test_');
      final chemin = p.join(dossier.path, 'version2.db');
      try {
        final version2 = await databaseFactoryFfi.openDatabase(
          chemin,
          options: OpenDatabaseOptions(
            version: 2,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            // Migrations 1 et 2 seulement : installation d'avant l'écran
            // Paramètres.
            onCreate: (db, version) => appliquerMigrations(db, 0, 2),
          ),
        );
        final idSource = await version2.insert('sources', <String, Object?>{
          'nom': 'MangaDex',
          'url_base': 'https://mangadex.org',
          'type_source': 'mangaDex',
        });
        final idTitre = await version2.insert('titres', <String, Object?>{
          'id_source': idSource,
          'url_titre': 'https://mangadex.org/title/abc',
          'nom': 'Titre existant',
          'type_titre': 'manga',
        });
        final idChapitre = await version2.insert('chapitres', <String, Object?>{
          'id_titre': idTitre,
          'url_chapitre': 'https://mangadex.org/chapter/1',
          'nom': 'Chapitre 1',
          'numero': 1.0,
        });
        await version2.insert('telechargements', <String, Object?>{
          'id_chapitre': idChapitre,
          'statut': 'echec',
          'message_erreur': 'Erreur 403',
          'date_ajout': 1,
          'date_maj': 2,
        });
        expect(await version2.getVersion(), 2);
        await version2.close();

        final version3 = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        try {
          // Toutes les migrations suivantes sont appliquées.
          expect(await version3.getVersion(), versionSchema);
          expect(
            (await version3.query('titres')).single['nom'],
            'Titre existant',
          );
          final telechargement = (await version3.query('telechargements'))
              .single;
          expect(telechargement['statut'], 'echec');
          expect(telechargement['message_erreur'], 'Erreur 403');
          expect(await version3.query('listes'), hasLength(5));
          // La nouvelle table est vide (pas de valeur par défaut en base) et
          // utilisable.
          expect(await version3.query('parametres'), isEmpty);
          await version3.insert('parametres', <String, Object?>{
            'cle': 'cle_test',
            'valeur': '1',
          });
          expect((await version3.query('parametres')).single['valeur'], '1');
        } finally {
          await version3.close();
        }
      } finally {
        await dossier.delete(recursive: true);
      }
    },
  );

  test(
    "la migration 3 → 4 conserve les données et ajoute les nouvelles colonnes",
    () async {
      final dossier = await Directory.systemTemp.createTemp('migration4_test_');
      final chemin = p.join(dossier.path, 'version3.db');
      try {
        final version3 = await databaseFactoryFfi.openDatabase(
          chemin,
          options: OpenDatabaseOptions(
            version: 3,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, version) => appliquerMigrations(db, 0, 3),
          ),
        );
        final idSource = await version3.insert('sources', <String, Object?>{
          'nom': 'MangaDex',
          'url_base': 'https://mangadex.org',
          'type_source': 'mangaDex',
        });
        final idTitre = await version3.insert('titres', <String, Object?>{
          'id_source': idSource,
          'url_titre': 'https://mangadex.org/title/abc',
          'nom': 'Titre existant',
          'type_titre': 'manga',
        });
        final idChapitre = await version3.insert('chapitres', <String, Object?>{
          'id_titre': idTitre,
          'url_chapitre': 'https://mangadex.org/chapter/1',
          'nom': 'Chapitre 1',
          'numero': 1.0,
          'langue': 'en',
          'est_lu': 1,
          'est_telecharge': 1,
        });
        await version3.insert('telechargements', <String, Object?>{
          'id_chapitre': idChapitre,
          'statut': 'termine',
          'date_ajout': 1,
          'date_maj': 2,
        });
        await version3.insert('parametres', <String, Object?>{
          'cle': 'langue',
          'valeur': 'fr',
        });
        await version3.close();

        final version4 = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        try {
          expect(await version4.getVersion(), versionSchema);
          final chapitre = (await version4.query('chapitres')).single;
          expect(chapitre['nom'], 'Chapitre 1');
          expect(chapitre['est_lu'], 1);
          expect(chapitre['est_telecharge'], 1);
          // Les lignes existantes reçoivent NULL : chemin non enregistré
          // (repli sur le calcul) et aucune suppression prévue.
          expect(chapitre.containsKey('nom_archive'), isTrue);
          expect(chapitre['nom_archive'], isNull);
          expect(chapitre['date_suppression_prevue'], isNull);
          final titre = (await version4.query('titres')).single;
          expect(titre['nom'], 'Titre existant');
          expect(titre.containsKey('langues_preferees'), isTrue);
          expect(titre['langues_preferees'], isNull);
          expect(
            (await version4.query('telechargements')).single['statut'],
            'termine',
          );
          expect((await version4.query('parametres')).single['valeur'], 'fr');
          expect(await version4.query('listes'), hasLength(5));

          final index = await version4.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            'AND name IN (?, ?)',
            <Object?>[
              'index_chapitres_nom_archive',
              'index_chapitres_suppression_prevue',
            ],
          );
          expect(index, hasLength(2));
        } finally {
          await version4.close();
        }
      } finally {
        await dossier.delete(recursive: true);
      }
    },
  );

  test(
    'la migration 5 crée Planifié et En attente en listes système',
    () async {
      final lignes = await base.query('listes', orderBy: 'ordre');
      // Valeurs écrites en dur dans la migration : alignées sur les constantes.
      expect(lignes[2]['nom'], nomListePlanifie);
      expect(lignes[2]['est_systeme'], 1);
      expect(lignes[2]['ordre'], ordreListePlanifie);
      expect(lignes[3]['nom'], nomListeEnAttente);
      expect(lignes[3]['est_systeme'], 1);
      expect(lignes[3]['ordre'], ordreListeEnAttente);
    },
  );

  test('la migration 4 → 5 conserve les données, ajoute les colonnes et les '
      'listes système', () async {
    final dossier = await Directory.systemTemp.createTemp('migration5_test_');
    final chemin = p.join(dossier.path, 'version4.db');
    try {
      final version4 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => appliquerMigrations(db, 0, 4),
        ),
      );
      final idSource = await version4.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      final idTitre = await version4.insert('titres', <String, Object?>{
        'id_source': idSource,
        'url_titre': 'https://mangadex.org/title/abc',
        'nom': 'Titre existant',
        'type_titre': 'manga',
        'langues_preferees': 'fr,en',
      });
      await version4.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
        'langue': 'fr',
        'est_lu': 1,
        'est_telecharge': 1,
        'nom_archive': 'manga/Titre existant/ch1.fr.zip',
        'date_suppression_prevue': 1000,
      });
      // Listes du client existantes : « Lus en 2026 » (position 2) et une
      // liste nommée comme une nouvelle liste système, avec un titre.
      await version4.insert('listes', <String, Object?>{
        'nom': 'Lus en 2026',
        'ordre': 2,
      });
      final idPlanifieClient = await version4.insert(
        'listes',
        <String, Object?>{'nom': 'planifié', 'ordre': 3},
      );
      await version4.insert('titres_listes', <String, Object?>{
        'id_titre': idTitre,
        'id_liste': idPlanifieClient,
      });
      await version4.insert('parametres', <String, Object?>{
        'cle': 'telechargement.gardes',
        'valeur': '1',
      });
      await version4.close();

      final version5 = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      try {
        // Toutes les migrations suivantes sont appliquées.
        expect(await version5.getVersion(), versionSchema);
        final chapitre = (await version5.query('chapitres')).single;
        expect(chapitre['nom'], 'Chapitre 1');
        expect(chapitre['est_lu'], 1);
        expect(chapitre['est_telecharge'], 1);
        expect(chapitre['nom_archive'], 'manga/Titre existant/ch1.fr.zip');
        expect(chapitre['date_suppression_prevue'], 1000);
        // Valeur par défaut : non gardé (la reprise est faite par les
        // services, qui lisent toujours `parametres`).
        expect(chapitre['est_garde'], 0);
        expect((await version5.query('parametres')).single['valeur'], '1');

        final titre = (await version5.query('titres')).single;
        expect(titre['nom'], 'Titre existant');
        expect(titre['langues_preferees'], 'fr,en');
        expect(titre.containsKey('niveau_contenu'), isTrue);
        expect(titre['niveau_contenu'], isNull);
        expect(titre.containsKey('couverture_choisie'), isTrue);
        expect(titre['couverture_choisie'], isNull);

        final listes = await version5.query('listes', orderBy: 'ordre, nom');
        expect(
          listes.map((liste) => (liste['nom'], liste['est_systeme'])),
          <(String, int)>[
            (nomListeFavoris, 1),
            (nomListeSuivis, 1),
            (nomListePlanifie, 1),
            (nomListeEnAttente, 1),
            (nomListeTermines, 1),
            ('Lus en 2026', 0),
          ],
        );
        // La liste du client devenue « Planifié » garde son identifiant et
        // ses titres ; l'autre liste du client passe après les listes
        // système (position 4 après la migration 5, 5 après la migration
        // 11).
        final planifie = listes[2];
        expect(planifie['id'], idPlanifieClient);
        expect(planifie['ordre'], ordreListePlanifie);
        expect(listes[5]['ordre'], 5);
        expect(
          await version5.query(
            'titres_listes',
            where: 'id_liste = ?',
            whereArgs: <Object?>[idPlanifieClient],
          ),
          hasLength(1),
        );

        final index = await version5.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
          <Object?>['index_chapitres_gardes'],
        );
        expect(index, hasLength(1));

        // CHECK : est_garde n'accepte que 0 ou 1.
        await expectLater(
          version5.update('chapitres', <String, Object?>{'est_garde': 2}),
          throwsA(isA<DatabaseException>()),
        );
      } finally {
        await version5.close();
      }
    } finally {
      await dossier.delete(recursive: true);
    }
  });

  /// Crée une base fichier en schéma v4 avec un titre, puis appelle
  /// [preparer] pour y ajouter les listes du client, et l'ouvre avec le code
  /// actuel. Renvoie la base mise à niveau (à fermer par l'appelant) et le
  /// dossier temporaire (à supprimer).
  Future<(Database, Directory)> monterDepuisV4(
    Future<void> Function(Database base, int idTitre) preparer,
  ) async {
    final dossier = await Directory.systemTemp.createTemp('migration5b_test_');
    final chemin = p.join(dossier.path, 'version4.db');
    final version4 = await databaseFactoryFfi.openDatabase(
      chemin,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => appliquerMigrations(db, 0, 4),
      ),
    );
    final idSource = await version4.insert('sources', <String, Object?>{
      'nom': 'MangaDex',
      'url_base': 'https://mangadex.org',
      'type_source': 'mangaDex',
    });
    final idTitre = await version4.insert('titres', <String, Object?>{
      'id_source': idSource,
      'url_titre': 'https://mangadex.org/title/abc',
      'nom': 'Titre existant',
      'type_titre': 'manga',
    });
    await preparer(version4, idTitre);
    await version4.close();
    final misANiveau = await ouvrirBaseDeDonnees(
      chemin: chemin,
      fabrique: databaseFactoryFfi,
    );
    return (misANiveau, dossier);
  }

  test("la migration 4 → 5 renomme la liste « en attente » du client en "
      "« En attente (perso) » avec ses titres", () async {
    late int idListeClient;
    final (version5, dossier) = await monterDepuisV4((base, idTitre) async {
      idListeClient = await base.insert('listes', <String, Object?>{
        'nom': 'en attente',
        'ordre': 2,
      });
      await base.insert('titres_listes', <String, Object?>{
        'id_titre': idTitre,
        'id_liste': idListeClient,
      });
    });
    try {
      expect(await version5.getVersion(), versionSchema);
      // La liste système est créée, vide.
      final systeme = (await version5.query(
        'listes',
        where: 'nom = ?',
        whereArgs: <Object?>[nomListeEnAttente],
      )).single;
      expect(systeme['est_systeme'], 1);
      expect(systeme['ordre'], ordreListeEnAttente);
      expect(systeme['id'], isNot(idListeClient));
      expect(
        await version5.query(
          'titres_listes',
          where: 'id_liste = ?',
          whereArgs: <Object?>[systeme['id']],
        ),
        isEmpty,
      );
      // La liste du client est renommée et garde ses titres.
      final perso = (await version5.query(
        'listes',
        where: 'id = ?',
        whereArgs: <Object?>[idListeClient],
      )).single;
      expect(perso['nom'], 'En attente (perso)');
      expect(perso['est_systeme'], 0);
      expect(
        await version5.query(
          'titres_listes',
          where: 'id_liste = ?',
          whereArgs: <Object?>[idListeClient],
        ),
        hasLength(1),
      );
      expect(await version5.query('listes'), hasLength(6));
    } finally {
      await version5.close();
      await dossier.delete(recursive: true);
    }
  });

  test("la migration 4 → 5 numérote le nouveau nom si « En attente (perso) » "
      'existe déjà', () async {
    late int idListeClient;
    final (version5, dossier) = await monterDepuisV4((base, idTitre) async {
      idListeClient = await base.insert('listes', <String, Object?>{
        'nom': 'EN ATTENTE',
        'ordre': 2,
      });
      await base.insert('listes', <String, Object?>{
        'nom': 'en attente (perso)',
        'ordre': 3,
      });
    });
    try {
      final perso = (await version5.query(
        'listes',
        where: 'id = ?',
        whereArgs: <Object?>[idListeClient],
      )).single;
      expect(perso['nom'], 'En attente (perso 2)');
      final noms = (await version5.query('listes'))
          .map((liste) => liste['nom'])
          .toSet();
      expect(
        noms,
        containsAll(<String>[
          nomListeEnAttente,
          'en attente (perso)',
          'En attente (perso 2)',
        ]),
      );
    } finally {
      await version5.close();
      await dossier.delete(recursive: true);
    }
  });

  test('la migration 5 → 6 conserve les données et ajoute url_externe '
      '(NULL = chapitre hébergé)', () async {
    final dossier = await Directory.systemTemp.createTemp('migration6_test_');
    final chemin = p.join(dossier.path, 'version5.db');
    try {
      final version5 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 5,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => appliquerMigrations(db, 0, 5),
        ),
      );
      final idSource = await version5.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      final idTitre = await version5.insert('titres', <String, Object?>{
        'id_source': idSource,
        'url_titre': 'https://mangadex.org/title/ruri',
        'nom': 'Ruri Dragon',
        'type_titre': 'manga',
        'niveau_contenu': 'safe',
        'couverture_choisie': 'https://exemple.org/vol2.jpg',
      });
      final idChapitre = await version5.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
        'langue': 'fr',
        'est_lu': 1,
        'est_telecharge': 1,
        'nom_archive': 'manga/Ruri Dragon/ch1.fr.zip',
        'date_suppression_prevue': 1000,
        'est_garde': 1,
      });
      await version5.insert('telechargements', <String, Object?>{
        'id_chapitre': idChapitre,
        'statut': 'termine',
        'date_ajout': 1,
        'date_maj': 2,
      });
      await version5.insert('listes', <String, Object?>{
        'nom': 'Lus en 2026',
        'ordre': 4,
      });
      expect(await version5.getVersion(), 5);
      await version5.close();

      final version6 = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      try {
        expect(await version6.getVersion(), versionSchema);
        final chapitre = (await version6.query('chapitres')).single;
        expect(chapitre['nom'], 'Chapitre 1');
        expect(chapitre['est_lu'], 1);
        expect(chapitre['est_telecharge'], 1);
        expect(chapitre['nom_archive'], 'manga/Ruri Dragon/ch1.fr.zip');
        expect(chapitre['date_suppression_prevue'], 1000);
        expect(chapitre['est_garde'], 1);
        // Les lignes existantes reçoivent NULL : chapitre hébergé.
        expect(chapitre.containsKey('url_externe'), isTrue);
        expect(chapitre['url_externe'], isNull);

        final titre = (await version6.query('titres')).single;
        expect(titre['niveau_contenu'], 'safe');
        expect(titre['couverture_choisie'], 'https://exemple.org/vol2.jpg');
        expect(
          (await version6.query('telechargements')).single['statut'],
          'termine',
        );
        expect(await version6.query('listes'), hasLength(6));

        // La colonne est utilisable et accepte NULL.
        await version6.update(
          'chapitres',
          <String, Object?>{'url_externe': 'https://editeur.example/ch1'},
          where: 'id = ?',
          whereArgs: <Object?>[idChapitre],
        );
        expect(
          (await version6.query('chapitres')).single['url_externe'],
          'https://editeur.example/ch1',
        );
      } finally {
        await version6.close();
      }
    } finally {
      await dossier.delete(recursive: true);
    }
  });

  test('la migration 6 → 7 ne perd rien et remplit titres_sources et '
      'chapitres.id_source', () async {
    final dossier = await Directory.systemTemp.createTemp('migration7_test_');
    final chemin = p.join(dossier.path, 'version6.db');
    try {
      final version6 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 6,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => appliquerMigrations(db, 0, 6),
        ),
      );
      final idMangaDex = await version6.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      final idScanManga = await version6.insert('sources', <String, Object?>{
        'nom': 'Scan-Manga',
        'url_base': 'https://www.scan-manga.com',
        'type_source': 'scanManga',
      });
      final idRuri = await version6.insert('titres', <String, Object?>{
        'id_source': idMangaDex,
        'url_titre': 'https://mangadex.org/title/ruri',
        'nom': 'Ruri Dragon',
        'type_titre': 'manga',
        'langues_preferees': 'fr,en',
        'niveau_contenu': 'safe',
        'couverture_choisie': 'https://exemple.org/vol2.jpg',
      });
      final idSolo = await version6.insert('titres', <String, Object?>{
        'id_source': idScanManga,
        'url_titre': 'https://www.scan-manga.com/solo',
        'nom': 'Solo Leveling',
        'type_titre': 'manhwa',
      });
      await version6.insert('titres_alternatifs', <String, Object?>{
        'id_titre': idRuri,
        'nom': 'Ruri Doragon',
        'langue': 'ja',
      });
      final idCategorie = await version6.insert('categories', <String, Object?>{
        'nom': 'comédie',
      });
      await version6.insert('titres_categories', <String, Object?>{
        'id_titre': idRuri,
        'id_categorie': idCategorie,
      });
      // Chapitre lu et téléchargé, gardé, avec suppression prévue.
      final idLu = await version6.insert('chapitres', <String, Object?>{
        'id_titre': idRuri,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
        'langue': 'fr',
        'est_lu': 1,
        'est_telecharge': 1,
        'nom_archive': 'manga/Ruri Dragon/ch1.fr.zip',
        'date_suppression_prevue': 1000,
        'est_garde': 1,
        'date_detection': 5,
      });
      // Chapitre externe non lu.
      await version6.insert('chapitres', <String, Object?>{
        'id_titre': idRuri,
        'url_chapitre': 'https://mangadex.org/chapter/2',
        'nom': 'Chapitre 2',
        'numero': 2.0,
        'url_externe': 'https://editeur.example/ruri/2',
      });
      final idSoloCh = await version6.insert('chapitres', <String, Object?>{
        'id_titre': idSolo,
        'url_chapitre': 'https://www.scan-manga.com/solo/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
      });
      await version6.insert('telechargements', <String, Object?>{
        'id_chapitre': idLu,
        'statut': 'termine',
        'nombre_pages_total': 12,
        'nombre_pages_faites': 12,
        'date_ajout': 1,
        'date_maj': 2,
      });
      await version6.insert('telechargements', <String, Object?>{
        'id_chapitre': idSoloCh,
        'statut': 'en_attente',
        'date_ajout': 3,
        'date_maj': 3,
      });
      final idListeClient = await version6.insert('listes', <String, Object?>{
        'nom': 'Lus en 2026',
        'ordre': 4,
      });
      final favoris = (await version6.query(
        'listes',
        where: 'nom = ?',
        whereArgs: <Object?>[nomListeFavoris],
      )).single;
      await version6.insert('titres_listes', <String, Object?>{
        'id_titre': idRuri,
        'id_liste': favoris['id'],
      });
      await version6.insert('titres_listes', <String, Object?>{
        'id_titre': idSolo,
        'id_liste': idListeClient,
      });
      await version6.insert('parametres', <String, Object?>{
        'cle': 'langue',
        'valeur': 'fr',
      });

      // Instantané de toutes les tables existantes avant la mise à niveau.
      const tables = <String>[
        'sources',
        'titres',
        'titres_alternatifs',
        'categories',
        'titres_categories',
        'chapitres',
        'telechargements',
        'listes',
        'titres_listes',
        'parametres',
      ];
      final avant = <String, List<Map<String, Object?>>>{
        for (final table in tables)
          table: await version6.query(table, orderBy: 'rowid'),
      };
      expect(await version6.getVersion(), 6);
      await version6.close();

      final avantMigration = DateTime.now().toUtc().millisecondsSinceEpoch;
      final version7 = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      try {
        expect(await version7.getVersion(), versionSchema);

        // Rien de perdu : chaque ligne de chaque table est identique, à la
        // nouvelle colonne chapitres.id_source près.
        for (final table in tables) {
          final apres = sansMigrationsRecentes(
            table,
            await version7.query(table, orderBy: 'rowid'),
          );
          // + titres.champs_manuels, ajoutée plus tard par la migration 10.
          final comparables = sansColonnes(apres, switch (table) {
            'chapitres' => const <String>{'id_source'},
            'titres' => const <String>{'champs_manuels'},
            _ => const <String>{},
          });
          expect(comparables, avant[table], reason: 'table $table');
        }

        // chapitres.id_source = source principale du titre.
        final chapitres = await version7.query('chapitres', orderBy: 'id');
        expect(
          chapitres.map((c) => (c['id_titre'], c['id_source'])),
          <(Object?, Object?)>[
            (idRuri, idMangaDex),
            (idRuri, idMangaDex),
            (idSolo, idScanManga),
          ],
        );

        // Une ligne principale par titre, copiée de titres.
        final liens = await version7.query('titres_sources', orderBy: 'id');
        expect(
          liens.map(
            (l) => (
              l['id_titre'],
              l['id_source'],
              l['url_titre'],
              l['est_principale'],
            ),
          ),
          <(Object?, Object?, Object?, Object?)>[
            (idRuri, idMangaDex, 'https://mangadex.org/title/ruri', 1),
            (idSolo, idScanManga, 'https://www.scan-manga.com/solo', 1),
          ],
        );
        for (final lien in liens) {
          expect(lien['date_ajout'], greaterThanOrEqualTo(avantMigration));
        }

        // Index et déclencheurs créés.
        final objets = await version7.rawQuery(
          "SELECT name FROM sqlite_master WHERE type IN ('index', 'trigger') "
          'AND name IN (?, ?, ?, ?, ?, ?)',
          <Object?>[
            'index_titres_sources_principale',
            'index_titres_sources_id_source',
            'index_chapitres_titre_source',
            'declencheur_titres_source_insertion',
            'declencheur_titres_source_modification',
            'declencheur_chapitres_source',
          ],
        );
        expect(objets, hasLength(6));

        // Clés étrangères cohérentes après le remplissage.
        expect(await version7.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await version7.close();
      }
    } finally {
      await dossier.delete(recursive: true);
    }
  });

  group('migration 7 : contraintes et déclencheurs', () {
    late int idMangaDex;
    late int idScanManga;
    late int idTitre;

    setUp(() async {
      idMangaDex = await base.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      idScanManga = await base.insert('sources', <String, Object?>{
        'nom': 'Scan-Manga',
        'url_base': 'https://www.scan-manga.com',
        'type_source': 'scanManga',
      });
      idTitre = await base.insert('titres', <String, Object?>{
        'id_source': idMangaDex,
        'url_titre': 'https://mangadex.org/title/abc',
        'nom': 'Titre',
        'type_titre': 'manga',
      });
    });

    Map<String, Object?> lien(
      int idSource,
      String url, {
      int? titre,
      int principale = 0,
    }) => <String, Object?>{
      'id_titre': titre ?? idTitre,
      'id_source': idSource,
      'url_titre': url,
      'est_principale': principale,
      'date_ajout': 0,
    };

    test('un titre inséré reçoit sa ligne principale', () async {
      final ligne = (await base.query('titres_sources')).single;
      expect(ligne['id_titre'], idTitre);
      expect(ligne['id_source'], idMangaDex);
      expect(ligne['url_titre'], 'https://mangadex.org/title/abc');
      expect(ligne['est_principale'], 1);
      expect(ligne['date_ajout'], isA<int>());
    });

    test('changer le site principal dans titres met à jour la ligne '
        'principale', () async {
      await base.update(
        'titres',
        <String, Object?>{
          'id_source': idScanManga,
          'url_titre': 'https://www.scan-manga.com/abc',
        },
        where: 'id = ?',
        whereArgs: <Object?>[idTitre],
      );
      final ligne = (await base.query('titres_sources')).single;
      expect(ligne['id_source'], idScanManga);
      expect(ligne['url_titre'], 'https://www.scan-manga.com/abc');
      expect(ligne['est_principale'], 1);
    });

    test('un chapitre inséré sans source reçoit celle du titre', () async {
      await base.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
      });
      await base.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'id_source': idScanManga,
        'url_chapitre': 'https://www.scan-manga.com/abc/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
      });
      final sources = (await base.query(
        'chapitres',
        orderBy: 'id',
      )).map((c) => c['id_source']);
      expect(sources, <Object?>[idMangaDex, idScanManga]);
    });

    test('url_titre est unique, tous titres confondus', () async {
      await expectLater(
        base.insert(
          'titres_sources',
          lien(idScanManga, 'https://mangadex.org/title/abc'),
        ),
        throwsA(isA<DatabaseException>()),
      );
      // Un nouveau titre ne peut pas reprendre l'adresse secondaire d'un
      // autre titre (le déclencheur échoue, l'insertion est annulée).
      await base.insert(
        'titres_sources',
        lien(idScanManga, 'https://www.scan-manga.com/abc'),
      );
      await expectLater(
        base.insert('titres', <String, Object?>{
          'id_source': idScanManga,
          'url_titre': 'https://www.scan-manga.com/abc',
          'nom': 'Doublon',
          'type_titre': 'manga',
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(await base.query('titres'), hasLength(1));
    });

    test('un site n\'est lié qu\'une fois à un titre', () async {
      await expectLater(
        base.insert(
          'titres_sources',
          lien(idMangaDex, 'https://mangadex.org/title/autre'),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('un seul site principal par titre', () async {
      await expectLater(
        base.insert(
          'titres_sources',
          lien(idScanManga, 'https://www.scan-manga.com/abc', principale: 1),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('est_principale n\'accepte que 0 ou 1', () async {
      await expectLater(
        base.insert(
          'titres_sources',
          lien(idScanManga, 'https://www.scan-manga.com/abc', principale: 2),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('source inexistante refusée, source liée non supprimable, titre '
        'supprimé en cascade', () async {
      await expectLater(
        base.insert('titres_sources', lien(999, 'https://exemple.org/abc')),
        throwsA(isA<DatabaseException>()),
      );
      await base.insert(
        'titres_sources',
        lien(idScanManga, 'https://www.scan-manga.com/abc'),
      );
      await expectLater(
        base.delete(
          'sources',
          where: 'id = ?',
          whereArgs: <Object?>[idScanManga],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await base.delete(
        'titres',
        where: 'id = ?',
        whereArgs: <Object?>[idTitre],
      );
      expect(await base.query('titres_sources'), isEmpty);
    });
  });

  test('la migration 7 → 8 ne perd rien et ajoute lien_seul à 0', () async {
    final dossier = await Directory.systemTemp.createTemp('migration8_test_');
    final chemin = p.join(dossier.path, 'version7.db');
    try {
      final version7 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 7,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => appliquerMigrations(db, 0, 7),
        ),
      );
      final idMangaDex = await version7.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      final idScanManga = await version7.insert('sources', <String, Object?>{
        'nom': 'Scan-Manga',
        'url_base': 'https://www.scan-manga.com',
        'type_source': 'scanManga',
      });
      final idRuri = await version7.insert('titres', <String, Object?>{
        'id_source': idMangaDex,
        'url_titre': 'https://mangadex.org/title/ruri',
        'nom': 'Ruri Dragon',
        'type_titre': 'manga',
      });
      await version7.insert('titres_sources', <String, Object?>{
        'id_titre': idRuri,
        'id_source': idScanManga,
        'url_titre': 'https://www.scan-manga.com/ruri',
        'est_principale': 0,
        'date_ajout': 42,
      });
      await version7.insert('chapitres', <String, Object?>{
        'id_titre': idRuri,
        'id_source': idScanManga,
        'url_chapitre': 'https://www.scan-manga.com/ruri/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
        'est_lu': 1,
      });
      final favoris = (await version7.query(
        'listes',
        where: 'nom = ?',
        whereArgs: <Object?>[nomListeFavoris],
      )).single;
      await version7.insert('titres_listes', <String, Object?>{
        'id_titre': idRuri,
        'id_liste': favoris['id'],
      });

      const tables = <String>[
        'sources',
        'titres',
        'titres_sources',
        'chapitres',
        'listes',
        'titres_listes',
      ];
      final avant = <String, List<Map<String, Object?>>>{
        for (final table in tables)
          table: await version7.query(table, orderBy: 'rowid'),
      };
      expect(await version7.getVersion(), 7);
      await version7.close();

      final version8 = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      try {
        expect(await version8.getVersion(), versionSchema);

        // Rien de perdu, à la nouvelle colonne lien_seul près, qui vaut 0
        // pour tous les liens existants.
        for (final table in tables) {
          final apres = sansMigrationsRecentes(
            table,
            await version8.query(table, orderBy: 'rowid'),
          );
          // + titres.champs_manuels, ajoutée plus tard par la migration 10.
          final comparables = sansColonnes(apres, switch (table) {
            'titres_sources' => const <String>{'lien_seul'},
            'titres' => const <String>{'champs_manuels'},
            _ => const <String>{},
          });
          expect(comparables, avant[table], reason: 'table $table');
        }
        final liens = await version8.query('titres_sources', orderBy: 'id');
        expect(liens.map((l) => l['lien_seul']), <Object?>[0, 0]);

        // Déclencheurs créés.
        final objets = await version8.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' "
          'AND name IN (?, ?)',
          <Object?>[
            'declencheur_titres_sources_lien_seul_insertion',
            'declencheur_titres_sources_lien_seul_modification',
          ],
        );
        expect(objets, hasLength(2));

        // La colonne est utilisable sur un site secondaire.
        await version8.update(
          'titres_sources',
          <String, Object?>{'lien_seul': 1},
          where: 'id_source = ?',
          whereArgs: <Object?>[idScanManga],
        );
        expect(
          (await version8.query(
            'titres_sources',
            where: 'id_source = ?',
            whereArgs: <Object?>[idScanManga],
          )).single['lien_seul'],
          1,
        );
        expect(await version8.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await version8.close();
      }
    } finally {
      await dossier.delete(recursive: true);
    }
  });

  group('migration 8 : lien seul', () {
    late int idMangaDex;
    late int idScanManga;
    late int idTitre;

    setUp(() async {
      idMangaDex = await base.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      idScanManga = await base.insert('sources', <String, Object?>{
        'nom': 'Scan-Manga',
        'url_base': 'https://www.scan-manga.com',
        'type_source': 'scanManga',
      });
      idTitre = await base.insert('titres', <String, Object?>{
        'id_source': idMangaDex,
        'url_titre': 'https://mangadex.org/title/abc',
        'nom': 'Titre',
        'type_titre': 'manga',
      });
    });

    test('lien_seul vaut 0 par défaut et n\'accepte que 0 ou 1', () async {
      expect((await base.query('titres_sources')).single['lien_seul'], 0);
      await expectLater(
        base.insert('titres_sources', <String, Object?>{
          'id_titre': idTitre,
          'id_source': idScanManga,
          'url_titre': 'https://www.scan-manga.com/abc',
          'lien_seul': 2,
          'date_ajout': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('le site principal ne peut pas être un lien seul', () async {
      // Mise à jour directe de la ligne principale : refusée.
      await expectLater(
        base.update(
          'titres_sources',
          <String, Object?>{'lien_seul': 1},
          where: 'id_titre = ? AND est_principale = ?',
          whereArgs: <Object?>[idTitre, 1],
        ),
        throwsA(isA<DatabaseException>()),
      );
      // Un lien seul promu principal : refusé.
      await base.insert('titres_sources', <String, Object?>{
        'id_titre': idTitre,
        'id_source': idScanManga,
        'url_titre': 'https://www.scan-manga.com/abc',
        'lien_seul': 1,
        'date_ajout': 0,
      });
      await base.update(
        'titres_sources',
        <String, Object?>{'est_principale': 0},
        where: 'id_titre = ? AND est_principale = ?',
        whereArgs: <Object?>[idTitre, 1],
      );
      await expectLater(
        base.update(
          'titres_sources',
          <String, Object?>{'est_principale': 1},
          where: 'id_source = ?',
          whereArgs: <Object?>[idScanManga],
        ),
        throwsA(isA<DatabaseException>()),
      );
      // Insertion directe d'une ligne principale en lien seul : refusée.
      final idAutre = await base.insert('sources', <String, Object?>{
        'nom': 'Autre',
        'url_base': 'https://autre.example',
        'type_source': 'generique',
      });
      await expectLater(
        base.insert('titres_sources', <String, Object?>{
          'id_titre': idTitre,
          'id_source': idAutre,
          'url_titre': 'https://autre.example/abc',
          'est_principale': 1,
          'lien_seul': 1,
          'date_ajout': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  test('la migration 8 → 9 ne perd rien et ajoute les équivalences', () async {
    final dossier = await Directory.systemTemp.createTemp('migration9_test_');
    final chemin = p.join(dossier.path, 'version8.db');
    try {
      final version8 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 8,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => appliquerMigrations(db, 0, 8),
        ),
      );
      final idSource = await version8.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      final idTitre = await version8.insert('titres', <String, Object?>{
        'id_source': idSource,
        'url_titre': 'https://mangadex.org/title/ruri',
        'nom': 'Ruri Dragon',
        'type_titre': 'manga',
      });
      final idSurvival = await version8.insert('categories', <String, Object?>{
        'nom': 'survival',
      });
      final idSurvie = await version8.insert('categories', <String, Object?>{
        'nom': 'survie',
      });
      await version8.insert('titres_categories', <String, Object?>{
        'id_titre': idTitre,
        'id_categorie': idSurvival,
      });
      await version8.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
      });

      const tables = <String>[
        'sources',
        'titres',
        'titres_sources',
        'chapitres',
        'listes',
        'categories',
        'titres_categories',
      ];
      final avant = <String, List<Map<String, Object?>>>{
        for (final table in tables)
          table: await version8.query(table, orderBy: 'rowid'),
      };
      expect(await version8.getVersion(), 8);
      await version8.close();

      final version9 = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      try {
        expect(await version9.getVersion(), versionSchema);
        for (final table in tables) {
          // titres.champs_manuels : ajoutée plus tard par la migration 10.
          expect(
            sansColonnes(
              sansMigrationsRecentes(
                table,
                await version9.query(table, orderBy: 'rowid'),
              ),
              const <String>{'champs_manuels'},
            ),
            avant[table],
            reason: 'table $table',
          );
        }
        // Table vide, index et déclencheurs créés.
        expect(await version9.query('categories_equivalences'), isEmpty);
        final objets = await version9.rawQuery(
          'SELECT name FROM sqlite_master WHERE name IN (?, ?, ?)',
          <Object?>[
            'index_categories_equivalences_id_reference',
            'declencheur_categories_equivalences_insertion',
            'declencheur_categories_equivalences_modification',
          ],
        );
        expect(objets, hasLength(3));

        // La table est utilisable sur les catégories existantes.
        await version9.insert('categories_equivalences', <String, Object?>{
          'id_categorie': idSurvival,
          'id_reference': idSurvie,
        });
        expect(await version9.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await version9.close();
      }
    } finally {
      await dossier.delete(recursive: true);
    }
  });

  group('migration 9 : équivalences de catégories', () {
    late int idSurvie;
    late int idSurvival;
    late int idSupervivencia;

    Future<int> categorie(String nom) =>
        base.insert('categories', <String, Object?>{'nom': nom});
    Future<int> rattacher(int idCategorie, int idReference) =>
        base.insert('categories_equivalences', <String, Object?>{
          'id_categorie': idCategorie,
          'id_reference': idReference,
        });

    setUp(() async {
      idSurvie = await categorie('survie');
      idSurvival = await categorie('survival');
      idSupervivencia = await categorie('supervivencia');
    });

    test('une catégorie ne peut pas être sa propre référence', () async {
      await expectLater(
        rattacher(idSurvie, idSurvie),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('une catégorie n\'a qu\'une seule référence', () async {
      await rattacher(idSurvival, idSurvie);
      await expectLater(
        rattacher(idSurvival, idSupervivencia),
        throwsA(isA<DatabaseException>()),
      );
    });

    test(
      'les chaînes et les cycles sont refusés par les déclencheurs',
      () async {
        await rattacher(idSurvival, idSurvie);
        // Référence elle-même rattachée : survival → survie déjà présent.
        await expectLater(
          rattacher(idSupervivencia, idSurvival),
          throwsA(isA<DatabaseException>()),
        );
        // Une référence ne peut pas être rattachée (cycle survie → survival).
        await expectLater(
          rattacher(idSurvie, idSurvival),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          rattacher(idSurvie, idSupervivencia),
          throwsA(isA<DatabaseException>()),
        );
        // Même contrôle par une mise à jour.
        await rattacher(idSupervivencia, idSurvie);
        await expectLater(
          base.update(
            'categories_equivalences',
            <String, Object?>{'id_reference': idSurvival},
            where: 'id_categorie = ?',
            whereArgs: <Object?>[idSupervivencia],
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(await base.query('categories_equivalences'), hasLength(2));
      },
    );

    test('supprimer une catégorie retire ses rattachements', () async {
      await rattacher(idSurvival, idSurvie);
      await rattacher(idSupervivencia, idSurvie);
      await base.delete(
        'categories',
        where: 'id = ?',
        whereArgs: <Object?>[idSurvival],
      );
      expect(await base.query('categories_equivalences'), hasLength(1));
      await base.delete(
        'categories',
        where: 'id = ?',
        whereArgs: <Object?>[idSurvie],
      );
      expect(await base.query('categories_equivalences'), isEmpty);
      // La catégorie rattachée reste, indépendante.
      expect(
        await base.query(
          'categories',
          where: 'id = ?',
          whereArgs: <Object?>[idSupervivencia],
        ),
        hasLength(1),
      );
    });
  });

  test('nom_archive est unique, mais plusieurs NULL sont permis', () async {
    final idSource = await base.insert('sources', <String, Object?>{
      'nom': 'MangaDex',
      'url_base': 'https://mangadex.org',
      'type_source': 'mangaDex',
    });
    final idTitre = await base.insert('titres', <String, Object?>{
      'id_source': idSource,
      'url_titre': 'https://mangadex.org/title/abc',
      'nom': 'Titre',
      'type_titre': 'manga',
    });
    Map<String, Object?> chapitre(int n, String? nomArchive) =>
        <String, Object?>{
          'id_titre': idTitre,
          'url_chapitre': 'https://mangadex.org/chapter/$n',
          'nom': 'Chapitre $n',
          'numero': n.toDouble(),
          'nom_archive': nomArchive,
        };
    await base.insert('chapitres', chapitre(1, null));
    await base.insert('chapitres', chapitre(2, null));
    await base.insert('chapitres', chapitre(3, 'manga/Titre/ch3.zip'));
    await expectLater(
      base.insert('chapitres', chapitre(4, 'manga/Titre/ch3.zip')),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('parametres : la clé est unique et la valeur obligatoire', () async {
    await base.insert('parametres', <String, Object?>{
      'cle': 'a',
      'valeur': 'x',
    });
    await expectLater(
      base.insert('parametres', <String, Object?>{'cle': 'a', 'valeur': 'y'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      base.insert('parametres', <String, Object?>{'cle': 'b', 'valeur': null}),
      throwsA(isA<DatabaseException>()),
    );
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

  test(
    'la migration 9 → 10 ne perd rien et ajoute champs_manuels vide',
    () async {
      final dossier = await Directory.systemTemp.createTemp(
        'migration10_test_',
      );
      final chemin = p.join(dossier.path, 'version9.db');
      try {
        final version9 = await databaseFactoryFfi.openDatabase(
          chemin,
          options: OpenDatabaseOptions(
            version: 9,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, version) => appliquerMigrations(db, 0, 9),
          ),
        );
        final idSource = await version9.insert('sources', <String, Object?>{
          'nom': 'MangaDex',
          'url_base': 'https://mangadex.org',
          'type_source': 'mangaDex',
        });
        final idTitre = await version9.insert('titres', <String, Object?>{
          'id_source': idSource,
          'url_titre': 'https://mangadex.org/title/ruri',
          'nom': 'Ruri Dragon',
          'type_titre': 'manga',
          'resume': 'Une lycéenne à cornes.',
        });
        await version9.insert('titres_alternatifs', <String, Object?>{
          'id_titre': idTitre,
          'nom': 'ルリドラゴン',
          'langue': 'ja',
        });
        final idCategorie = await version9.insert(
          'categories',
          <String, Object?>{'nom': 'comedy'},
        );
        await version9.insert('titres_categories', <String, Object?>{
          'id_titre': idTitre,
          'id_categorie': idCategorie,
        });
        await version9.insert('chapitres', <String, Object?>{
          'id_titre': idTitre,
          'url_chapitre': 'https://mangadex.org/chapter/1',
          'nom': 'Chapitre 1',
          'numero': 1.0,
        });

        const tables = <String>[
          'sources',
          'titres',
          'titres_sources',
          'titres_alternatifs',
          'chapitres',
          'listes',
          'categories',
          'titres_categories',
        ];
        final avant = <String, List<Map<String, Object?>>>{
          for (final table in tables)
            table: await version9.query(table, orderBy: 'rowid'),
        };
        expect(await version9.getVersion(), 9);
        await version9.close();

        final version10 = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        try {
          expect(await version10.getVersion(), versionSchema);
          for (final table in tables) {
            final apres = sansMigrationsRecentes(
              table,
              await version10.query(table, orderBy: 'rowid'),
            );
            expect(
              table == 'titres'
                  ? sansColonnes(apres, const <String>{'champs_manuels'})
                  : apres,
              avant[table],
              reason: 'table $table',
            );
          }
          // Les titres existants n'ont aucun champ manuel.
          final titres = await version10.query('titres');
          expect(titres.single['champs_manuels'], '[]');
          // Colonne NOT NULL : un NULL explicite est refusé.
          await expectLater(
            version10.update('titres', <String, Object?>{
              'champs_manuels': null,
            }),
            throwsA(isA<DatabaseException>()),
          );
        } finally {
          await version10.close();
        }
      } finally {
        await dossier.delete(recursive: true);
      }
    },
  );

  test('la migration 11 crée Terminés en liste système, après En '
      'attente', () async {
    final lignes = await base.query('listes', orderBy: 'ordre');
    // Valeurs écrites en dur dans la migration : alignées sur les constantes.
    expect(lignes[4]['nom'], nomListeTermines);
    expect(lignes[4]['est_systeme'], 1);
    expect(lignes[4]['ordre'], ordreListeTermines);
    expect(lignes.map((ligne) => ligne['nom']), nomsListesSysteme);
    expect(ordreDerniereListeSysteme, ordreListeTermines);
  });

  group('migration 10 → 11', () {
    /// Crée une base fichier en schéma v10 avec un titre, appelle
    /// [preparer] pour y ajouter des listes, l'ouvre avec le code actuel et
    /// passe la base mise à niveau à [verifier].
    Future<void> monterDepuisV10(
      Future<void> Function(Database base, int idTitre) preparer,
      Future<void> Function(Database base, int idTitre) verifier,
    ) async {
      final dossier = await Directory.systemTemp.createTemp(
        'migration11_test_',
      );
      final chemin = p.join(dossier.path, 'version10.db');
      try {
        final version10 = await databaseFactoryFfi.openDatabase(
          chemin,
          options: OpenDatabaseOptions(
            version: 10,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, version) => appliquerMigrations(db, 0, 10),
          ),
        );
        final idSource = await version10.insert('sources', <String, Object?>{
          'nom': 'MangaDex',
          'url_base': 'https://mangadex.org',
          'type_source': 'mangaDex',
        });
        final idTitre = await version10.insert('titres', <String, Object?>{
          'id_source': idSource,
          'url_titre': 'https://mangadex.org/title/ruri',
          'nom': 'Ruri Dragon',
          'type_titre': 'manga',
        });
        await version10.insert('chapitres', <String, Object?>{
          'id_titre': idTitre,
          'url_chapitre': 'https://mangadex.org/chapter/1',
          'nom': 'Chapitre 1',
          'numero': 1.0,
          'est_lu': 1,
        });
        await preparer(version10, idTitre);
        expect(await version10.getVersion(), 10);
        await version10.close();

        final version11 = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        try {
          expect(await version11.getVersion(), versionSchema);
          await verifier(version11, idTitre);
          expect(await version11.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          await version11.close();
        }
      } finally {
        await dossier.delete(recursive: true);
      }
    }

    Future<Map<String, Object?>> listeParId(Database base, int id) async =>
        (await base.query(
          'listes',
          where: 'id = ?',
          whereArgs: <Object?>[id],
        )).single;

    Future<int> nombreTitres(Database base, Object? idListe) async =>
        (await base.query(
          'titres_listes',
          where: 'id_liste = ?',
          whereArgs: <Object?>[idListe],
        )).length;

    test('sans liste « Terminés » : ajoutée en position 4, les listes du '
        'client décalées, rien d\'autre ne change', () async {
      late int idLus;
      late int idPlusTard;
      late Map<String, List<Map<String, Object?>>> avant;
      const tables = <String>[
        'sources',
        'titres',
        'titres_sources',
        'chapitres',
        'titres_listes',
      ];
      await monterDepuisV10(
        (base, idTitre) async {
          idLus = await base.insert('listes', <String, Object?>{
            'nom': 'Lus en 2026',
            'ordre': 4,
          });
          idPlusTard = await base.insert('listes', <String, Object?>{
            'nom': 'Plus tard',
            'ordre': 5,
          });
          await base.insert('titres_listes', <String, Object?>{
            'id_titre': idTitre,
            'id_liste': idLus,
          });
          avant = <String, List<Map<String, Object?>>>{
            for (final table in <String>[...tables, 'listes'])
              table: await base.query(table, orderBy: 'rowid'),
          };
        },
        (base, idTitre) async {
          for (final table in tables) {
            expect(
              sansMigrationsRecentes(
                table,
                await base.query(table, orderBy: 'rowid'),
              ),
              avant[table],
              reason: 'table $table',
            );
          }
          expect(
            sansMigrationsRecentes(
              'listes',
              await base.query('listes', orderBy: 'rowid'),
            ),
            avant['listes'],
          );
          final listes = await base.query('listes', orderBy: 'ordre');
          expect(
            listes.map((l) => (l['nom'], l['est_systeme'], l['ordre'])),
            <(Object?, Object?, Object?)>[
              (nomListeFavoris, 1, 0),
              (nomListeSuivis, 1, 1),
              (nomListePlanifie, 1, 2),
              (nomListeEnAttente, 1, 3),
              (nomListeTermines, 1, ordreListeTermines),
              ('Lus en 2026', 0, 5),
              ('Plus tard', 0, 6),
            ],
          );
          expect(await nombreTitres(base, listes[4]['id']), 0);
          expect(await nombreTitres(base, idLus), 1);
          expect((await listeParId(base, idPlusTard))['ordre'], 6);
        },
      );
    });

    test('un ordre choisi par le client est conservé', () async {
      // Ordre personnalisé (DepotListes.enregistrerOrdre) : « En attente »
      // déplacée tout à la fin, après une liste du client.
      await monterDepuisV10(
        (base, idTitre) async {
          await base.update(
            'listes',
            <String, Object?>{'ordre': 5},
            where: 'nom = ?',
            whereArgs: <Object?>[nomListeEnAttente],
          );
          await base.insert('listes', <String, Object?>{
            'nom': 'Lus en 2026',
            'ordre': 3,
          });
          await base.insert('listes', <String, Object?>{
            'nom': 'Plus tard',
            'ordre': 4,
          });
        },
        (base, idTitre) async {
          final listes = await base.query('listes', orderBy: 'ordre');
          expect(
            listes.map((l) => (l['nom'], l['ordre'])),
            <(Object?, Object?)>[
              (nomListeFavoris, 0),
              (nomListeSuivis, 1),
              (nomListePlanifie, 2),
              ('Lus en 2026', 3),
              (nomListeTermines, 4),
              ('Plus tard', 5),
              (nomListeEnAttente, 6),
            ],
          );
        },
      );
    });

    test('une liste « terminés » du client est renommée « Terminés (perso) » '
        'avec ses titres', () async {
      late int idClient;
      await monterDepuisV10(
        (base, idTitre) async {
          idClient = await base.insert('listes', <String, Object?>{
            'nom': 'terminés',
            'ordre': 4,
          });
          await base.insert('titres_listes', <String, Object?>{
            'id_titre': idTitre,
            'id_liste': idClient,
          });
        },
        (base, idTitre) async {
          final perso = await listeParId(base, idClient);
          expect(perso['nom'], 'Terminés (perso)');
          expect(perso['est_systeme'], 0);
          expect(perso['ordre'], 5);
          expect(await nombreTitres(base, idClient), 1);
          // La liste système est créée à côté, vide.
          final systeme = (await base.query(
            'listes',
            where: 'nom = ?',
            whereArgs: <Object?>[nomListeTermines],
          )).single;
          expect(systeme['id'], isNot(idClient));
          expect(systeme['est_systeme'], 1);
          expect(systeme['ordre'], ordreListeTermines);
          expect(await nombreTitres(base, systeme['id']), 0);
          expect(await base.query('listes'), hasLength(6));
        },
      );
    });

    test('le nouveau nom est numéroté si « Terminés (perso) » existe '
        'déjà', () async {
      late int idClient;
      await monterDepuisV10(
        (base, idTitre) async {
          idClient = await base.insert('listes', <String, Object?>{
            'nom': 'TERMINéS',
            'ordre': 4,
          });
          await base.insert('listes', <String, Object?>{
            'nom': 'terminés (perso)',
            'ordre': 5,
          });
        },
        (base, idTitre) async {
          expect(
            (await listeParId(base, idClient))['nom'],
            'Terminés (perso 2)',
          );
          final noms = (await base.query('listes'))
              .map((liste) => liste['nom'])
              .toSet();
          expect(
            noms,
            containsAll(<String>[
              nomListeTermines,
              'terminés (perso)',
              'Terminés (perso 2)',
            ]),
          );
        },
      );
    });
  });

  test('la migration 11 → 12 ne perd rien et ajoute description_perso '
      'à NULL', () async {
    final dossier = await Directory.systemTemp.createTemp('migration12_test_');
    final chemin = p.join(dossier.path, 'version11.db');
    try {
      final version11 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 11,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => appliquerMigrations(db, 0, 11),
        ),
      );
      final idSource = await version11.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      final idTitre = await version11.insert('titres', <String, Object?>{
        'id_source': idSource,
        'url_titre': 'https://mangadex.org/title/ruri',
        'nom': 'Ruri Dragon',
        'type_titre': 'manga',
        'resume': 'Une lycéenne à cornes.',
        'champs_manuels': '["nom"]',
      });
      await version11.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
        'est_lu': 1,
      });
      const tables = <String>[
        'sources',
        'titres',
        'titres_sources',
        'chapitres',
        'listes',
      ];
      final avant = <String, List<Map<String, Object?>>>{
        for (final table in tables)
          table: await version11.query(table, orderBy: 'rowid'),
      };
      expect(
        (await version11.rawQuery('PRAGMA table_info(titres)'))
            .map((colonne) => colonne['name']),
        isNot(contains('description_perso')),
      );
      await version11.close();

      final version12 = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      try {
        expect(await version12.getVersion(), versionSchema);
        for (final table in tables) {
          final apres = await version12.query(table, orderBy: 'rowid');
          expect(
            switch (table) {
              'titres' => sansColonnes(apres, const <String>{
                'description_perso',
              }),
              // chapitres.origine : ajoutée plus tard par la migration 13.
              'chapitres' => sansColonnes(apres, const <String>{'origine'}),
              _ => apres,
            },
            avant[table],
            reason: 'table $table',
          );
        }
        // Les titres existants n'ont pas de description personnelle.
        final titre = (await version12.query('titres')).single;
        expect(titre.containsKey('description_perso'), isTrue);
        expect(titre['description_perso'], isNull);
        expect(await version12.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await version12.close();
      }
    } finally {
      await dossier.delete(recursive: true);
    }
  });

  test('la migration 12 → 13 ne perd rien, met origine à « site » et '
      'garde les chapitres déjà présents sur un lien seul', () async {
    final dossier = await Directory.systemTemp.createTemp('migration13_test_');
    final chemin = p.join(dossier.path, 'version12.db');
    try {
      final version12 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 12,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => appliquerMigrations(db, 0, 12),
        ),
      );
      final idMangaDex = await version12.insert('sources', <String, Object?>{
        'nom': 'MangaDex',
        'url_base': 'https://mangadex.org',
        'type_source': 'mangaDex',
      });
      final idComix = await version12.insert('sources', <String, Object?>{
        'nom': 'Comix',
        'url_base': 'https://comix.to',
        'type_source': 'generique',
      });
      final idTitre = await version12.insert('titres', <String, Object?>{
        'id_source': idMangaDex,
        'url_titre': 'https://mangadex.org/title/ruri',
        'nom': 'Ruri Dragon',
        'type_titre': 'manga',
      });
      await version12.insert('titres_sources', <String, Object?>{
        'id_titre': idTitre,
        'id_source': idComix,
        'url_titre': 'https://comix.to/title/ruri',
        'est_principale': 0,
        'date_ajout': 42,
      });
      await version12.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
        'est_lu': 1,
      });
      // Chapitre lu sur Comix, gardé lors de son passage en lien seul.
      final idGarde = await version12.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'id_source': idComix,
        'url_chapitre': 'https://comix.to/title/ruri/chapter-1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
        'est_lu': 1,
      });
      await version12.update(
        'titres_sources',
        <String, Object?>{'lien_seul': 1},
        where: 'id_source = ?',
        whereArgs: <Object?>[idComix],
      );
      const tables = <String>[
        'sources',
        'titres',
        'titres_sources',
        'chapitres',
        'listes',
      ];
      final avant = <String, List<Map<String, Object?>>>{
        for (final table in tables)
          table: await version12.query(table, orderBy: 'rowid'),
      };
      expect(
        (await version12.rawQuery('PRAGMA table_info(chapitres)'))
            .map((colonne) => colonne['name']),
        isNot(contains('origine')),
      );
      await version12.close();

      final version13 = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      try {
        expect(await version13.getVersion(), versionSchema);
        for (final table in tables) {
          final apres = await version13.query(table, orderBy: 'rowid');
          expect(
            table == 'chapitres'
                ? sansColonnes(apres, const <String>{'origine'})
                : apres,
            avant[table],
            reason: 'table $table',
          );
        }
        // Tous les chapitres existants viennent du site.
        expect(
          (await version13.query('chapitres'))
              .map((chapitre) => chapitre['origine']),
          everyElement('site'),
        );
        // Le chapitre site gardé sur le lien seul reste modifiable.
        await version13.update(
          'chapitres',
          <String, Object?>{'est_lu': 0, 'est_garde': 1},
          where: 'id = ?',
          whereArgs: <Object?>[idGarde],
        );
        // Nouveau chapitre site sur le lien seul : refusé ; web : accepté.
        final nouveau = <String, Object?>{
          'id_titre': idTitre,
          'id_source': idComix,
          'url_chapitre': 'https://comix.to/title/ruri/chapter-2',
          'nom': 'Chapitre 2',
          'numero': 2.0,
        };
        await expectLater(
          version13.insert('chapitres', nouveau),
          throwsA(isA<DatabaseException>()),
        );
        await version13.insert('chapitres', <String, Object?>{
          ...nouveau,
          'origine': 'web',
        });
        final declencheurs = await version13.query(
          'sqlite_master',
          columns: <String>['name'],
          where: 'type = ? AND tbl_name = ?',
          whereArgs: <Object?>['trigger', 'chapitres'],
        );
        expect(
          declencheurs.map((ligne) => ligne['name']),
          containsAll(<String>[
            'declencheur_chapitres_source',
            'declencheur_chapitres_lien_seul_insertion',
            'declencheur_chapitres_lien_seul_modification',
          ]),
        );
        expect(await version13.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await version13.close();
      }
    } finally {
      await dossier.delete(recursive: true);
    }
  });

  test(
    'la migration 13 → 14 ne perd rien et crée la table tickets vide',
    () async {
      final dossier = await Directory.systemTemp.createTemp(
        'migration14_test_',
      );
      final chemin = p.join(dossier.path, 'version13.db');
      try {
        final version13 = await databaseFactoryFfi.openDatabase(
          chemin,
          options: OpenDatabaseOptions(
            version: 13,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, version) => appliquerMigrations(db, 0, 13),
          ),
        );
        final idSource = await version13.insert('sources', <String, Object?>{
          'nom': 'MangaDex',
          'url_base': 'https://mangadex.org',
          'type_source': 'mangaDex',
        });
        await version13.insert('titres', <String, Object?>{
          'id_source': idSource,
          'url_titre': 'https://mangadex.org/title/abc',
          'nom': 'Titre',
          'type_titre': 'manga',
        });
        const tables = <String>[
          'sources',
          'titres',
          'titres_sources',
          'listes',
        ];
        final avant = <String, List<Map<String, Object?>>>{
          for (final table in tables)
            table: await version13.query(table, orderBy: 'rowid'),
        };
        await version13.close();

        final version14 = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        try {
          expect(await version14.getVersion(), versionSchema);
          for (final table in tables) {
            expect(
              await version14.query(table, orderBy: 'rowid'),
              avant[table],
              reason: 'table $table',
            );
          }
          expect(await version14.query('tickets'), isEmpty);
          final colonnes = (await version14.rawQuery(
            'PRAGMA table_info(tickets)',
          )).map((colonne) => colonne['name']);
          expect(
            colonnes,
            containsAll(<String>[
              'repere',
              'type_ticket',
              'numero',
              'etat',
              'raison_fermeture',
              'etiquettes',
              'date_consultation',
            ]),
          );
          // Valeur par défaut des étiquettes : tableau JSON vide.
          await version14.insert('tickets', <String, Object?>{
            'repere': 'BP-000000000001',
            'titre': 'Essai',
            'type_ticket': 'bug',
            'date_creation': 0,
          });
          expect((await version14.query('tickets')).single['etiquettes'], '[]');
        } finally {
          await version14.close();
        }
      } finally {
        await dossier.delete(recursive: true);
      }
    },
  );
}

/// Annule, dans les [lignes] de [table] lues après toutes les migrations,
/// l'effet des migrations 11 et 12 : sert à comparer une table avant et
/// après une migration plus ancienne.
///
/// - Migration 11 sur `listes` : ligne « Terminés » ajoutée en position 4,
///   lignes suivantes décalées d'un cran.
/// - Migration 12 sur `titres` : colonne `description_perso` retirée.
/// - Migration 13 sur `chapitres` : colonne `origine` retirée.
///
/// Les autres tables sont renvoyées telles quelles.
List<Map<String, Object?>> sansMigrationsRecentes(
  String table,
  List<Map<String, Object?>> lignes,
) {
  if (table == 'titres') {
    return sansColonnes(lignes, const <String>{'description_perso'});
  }
  if (table == 'chapitres') {
    return sansColonnes(lignes, const <String>{'origine'});
  }
  if (table != 'listes') {
    return lignes;
  }
  return <Map<String, Object?>>[
    for (final ligne in lignes)
      if (!(ligne['nom'] == nomListeTermines && ligne['est_systeme'] == 1))
        <String, Object?>{
          ...ligne,
          if ((ligne['ordre']! as int) > ordreListeTermines)
            'ordre': (ligne['ordre']! as int) - 1,
        },
  ];
}

/// Copie de [lignes] sans les [colonnes] données : sert à comparer une
/// table avant et après une migration qui lui a ajouté des colonnes.
List<Map<String, Object?>> sansColonnes(
  List<Map<String, Object?>> lignes,
  Set<String> colonnes,
) {
  return <Map<String, Object?>>[
    for (final ligne in lignes)
      Map<String, Object?>.of(ligne)
        ..removeWhere((cle, _) => colonnes.contains(cle)),
  ];
}
