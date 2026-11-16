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

  test('la version du schéma est 5 et correspond à la base ouverte', () async {
    expect(versionSchema, 5);
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
    // + Planifié et En attente (migration 5).
    expect(lignes, hasLength(4));
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
          expect(await version2.query('listes'), hasLength(4));
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
          expect(await version3.query('listes'), hasLength(4));
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
          expect(await version4.query('listes'), hasLength(4));

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
        expect(await version5.getVersion(), 5);
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
            ('Lus en 2026', 0),
          ],
        );
        // La liste du client devenue « Planifié » garde son identifiant et
        // ses titres ; l'autre liste du client passe après les listes
        // système.
        final planifie = listes[2];
        expect(planifie['id'], idPlanifieClient);
        expect(planifie['ordre'], ordreListePlanifie);
        expect(listes[4]['ordre'], 4);
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
}
