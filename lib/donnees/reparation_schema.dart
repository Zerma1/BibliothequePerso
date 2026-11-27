/// Réparation du numéro de version d'une base dont le schéma réel est plus
/// récent que la version enregistrée (`PRAGMA user_version`).
///
/// Cas d'origine (incident 0.2.4) : une ancienne version de l'application
/// (0.1.0, schéma 6) ouvre une base au schéma 13. Sans `onDowngrade`,
/// sqflite écrit quand même `user_version = 6` ; la version suivante rejoue
/// alors les migrations 7 à 13 sur des tables déjà présentes et l'ouverture
/// échoue (« table titres_sources already exists »).
///
/// Principe : avant les migrations, le niveau **réel** du schéma est déduit
/// de marqueurs (une table, une colonne ou une liste système propre à chaque
/// migration). S'il dépasse la version enregistrée, les éléments des
/// migrations 1 à ce niveau sont vérifiés un par un et seuls ceux qui
/// manquent sont recréés (tables, colonnes, index, déclencheurs, listes
/// système), puis les migrations reprennent à partir du niveau réel.
///
/// Les instructions ci-dessous sont des **copies** de celles de
/// `migrations.dart` (qui ne doivent jamais être modifiées) : à chaque
/// nouvelle migration, ajouter son marqueur dans [detecterNiveauSchema] et
/// ses éléments dans [_elementsParMigration].
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/journal.dart';

/// Message de l'erreur levée quand la base vient d'une version plus récente
/// de l'application que celle qui l'ouvre ([niveau] : schéma de la base).
String messageBasePlusRecente(int niveau) =>
    "Cette base a été créée par une version plus récente de l'application "
    '(schéma $niveau) : installez la dernière version.';

/// Niveau réel du schéma de la base, déduit des marqueurs de chaque
/// migration, du plus récent au plus ancien. 0 si la base est vide.
///
/// Marqueurs (un élément créé par la migration et par aucune autre) :
/// 14 table `tickets`, 13 `chapitres.origine`, 12 `titres.description_perso`, 11 liste système
/// « Terminés », 10 `titres.champs_manuels`, 9 table
/// `categories_equivalences`, 8 `titres_sources.lien_seul`, 7 table
/// `titres_sources`, 6 `chapitres.url_externe`, 5 `chapitres.est_garde`,
/// 4 `chapitres.nom_archive`, 3 table `parametres`, 2 table
/// `telechargements`, 1 une des tables `sources`, `titres` ou `listes`.
Future<int> detecterNiveauSchema(DatabaseExecutor executeur) async {
  if (await _tableExiste(executeur, 'tickets')) return 14;
  if (await _colonneExiste(executeur, 'chapitres', 'origine')) return 13;
  if (await _colonneExiste(executeur, 'titres', 'description_perso')) {
    return 12;
  }
  if (await _tableExiste(executeur, 'listes')) {
    final termines = await executeur.query(
      'listes',
      columns: <String>['id'],
      where: 'nom = ? AND est_systeme = ?',
      whereArgs: <Object?>['Terminés', 1],
      limit: 1,
    );
    if (termines.isNotEmpty) return 11;
  }
  if (await _colonneExiste(executeur, 'titres', 'champs_manuels')) return 10;
  if (await _tableExiste(executeur, 'categories_equivalences')) return 9;
  if (await _colonneExiste(executeur, 'titres_sources', 'lien_seul')) return 8;
  if (await _tableExiste(executeur, 'titres_sources')) return 7;
  if (await _colonneExiste(executeur, 'chapitres', 'url_externe')) return 6;
  if (await _colonneExiste(executeur, 'chapitres', 'est_garde')) return 5;
  if (await _colonneExiste(executeur, 'chapitres', 'nom_archive')) return 4;
  if (await _tableExiste(executeur, 'parametres')) return 3;
  if (await _tableExiste(executeur, 'telechargements')) return 2;
  for (final table in const <String>['sources', 'titres', 'listes']) {
    if (await _tableExiste(executeur, table)) return 1;
  }
  return 0;
}

/// Répare une base dont la version enregistrée ([ancienneVersion]) est plus
/// basse que son schéma réel, et renvoie la version à partir de laquelle
/// les migrations doivent reprendre.
///
/// - Niveau réel ≤ [ancienneVersion] : rien n'est fait, renvoie
///   [ancienneVersion] (cas normal).
/// - Niveau réel > [versionDemandee] : la base vient d'une version plus
///   récente de l'application ; lève [ErreurBaseDeDonnees] sans rien
///   modifier.
/// - Sinon : recrée seulement les éléments manquants des migrations 1 à ce
///   niveau (idempotent, données conservées), écrit ce niveau dans
///   `user_version`, journalise un avertissement et renvoie ce niveau.
///
/// À appeler dans la transaction d'ouverture (`onCreate`/`onUpgrade`) : une
/// erreur annule toute la réparation.
Future<int> reparerVersionSchema(
  DatabaseExecutor executeur,
  int ancienneVersion,
  int versionDemandee,
) async {
  final niveau = await detecterNiveauSchema(executeur);
  if (niveau <= ancienneVersion) {
    return ancienneVersion;
  }
  if (niveau > versionDemandee) {
    throw ErreurBaseDeDonnees(messageBasePlusRecente(niveau));
  }

  final recrees = <String>[];
  final elements = _elementsParMigration();
  for (var version = 1; version <= niveau; version++) {
    for (final element in elements[version - 1]) {
      if (await element.assurer(executeur)) {
        recrees.add('${element.description} (migration $version)');
      }
    }
  }

  // PRAGMA n'accepte pas de paramètre « ? » : la valeur est un entier calculé
  // ici (jamais une donnée extérieure), comme dans `setVersion` de sqflite.
  // sqflite écrit ensuite la version finale à la fin de l'ouverture.
  await executeur.execute('PRAGMA user_version = $niveau');

  Journal.actuel.avertissement(
    CategorieJournal.base,
    'Version du schéma réparée : enregistrée $ancienneVersion, réelle '
    '$niveau (base ouverte par une version plus ancienne de '
    "l'application). Éléments recréés : "
    '${recrees.isEmpty ? 'aucun' : recrees.join(', ')}.',
  );
  return niveau;
}

/// `true` si la table [table] existe.
Future<bool> _tableExiste(DatabaseExecutor executeur, String table) async =>
    _objetExiste(executeur, 'table', table);

/// `true` si l'objet SQLite [nom] de type [type] (`table`, `index`,
/// `trigger`) existe.
Future<bool> _objetExiste(
  DatabaseExecutor executeur,
  String type,
  String nom,
) async {
  final lignes = await executeur.rawQuery(
    'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
    <Object?>[type, nom],
  );
  return lignes.isNotEmpty;
}

/// `true` si la colonne [colonne] de [table] existe (faux si la table
/// n'existe pas).
Future<bool> _colonneExiste(
  DatabaseExecutor executeur,
  String table,
  String colonne,
) async {
  // pragma_table_info accepte le nom de table en paramètre (SQLite 3.16+),
  // ce qui évite de l'écrire dans le SQL.
  final lignes = await executeur.rawQuery(
    'SELECT 1 FROM pragma_table_info(?) WHERE name = ? LIMIT 1',
    <Object?>[table, colonne],
  );
  return lignes.isNotEmpty;
}

/// Un élément du schéma créé par une migration, recréé seulement s'il
/// manque.
class _Element {
  const _Element(this.description, this.assurer);

  /// Description pour le journal (`table titres_sources`…).
  final String description;

  /// Crée l'élément s'il manque ; renvoie `true` s'il a été créé.
  final Future<bool> Function(DatabaseExecutor executeur) assurer;
}

/// Table, index ou déclencheur [nom] (de [type]) créé par [sql] s'il manque.
_Element _objet(String type, String nom, String sql) =>
    _Element('$type $nom', (executeur) async {
      if (await _objetExiste(executeur, type, nom)) return false;
      await executeur.execute(sql);
      return true;
    });

/// Table [nom] créée par [sql] si elle manque ; [apresCreation] remplit
/// ensuite ses données d'origine (migration 7).
_Element _table(
  String nom,
  String sql, {
  Future<void> Function(DatabaseExecutor executeur)? apresCreation,
}) => _Element('table $nom', (executeur) async {
  if (await _tableExiste(executeur, nom)) return false;
  await executeur.execute(sql);
  if (apresCreation != null) await apresCreation(executeur);
  return true;
});

/// Colonne [colonne] de [table] ajoutée par [sql] si elle manque ;
/// [apresAjout] remplit ensuite les lignes existantes (migration 7).
_Element _colonne(
  String table,
  String colonne,
  String sql, {
  Future<void> Function(DatabaseExecutor executeur)? apresAjout,
}) => _Element('colonne $table.$colonne', (executeur) async {
  if (await _colonneExiste(executeur, table, colonne)) return false;
  await executeur.execute(sql);
  if (apresAjout != null) await apresAjout(executeur);
  return true;
});

/// Liste système [nom] insérée si aucune liste de ce nom n'existe. Une liste
/// déjà présente n'est jamais modifiée (données du client).
_Element _listeSysteme(String nom, int ordre) =>
    _Element('liste système $nom', (executeur) async {
      final existantes = await executeur.query(
        'listes',
        columns: <String>['id'],
        where: 'nom = ? COLLATE NOCASE',
        whereArgs: <Object?>[nom],
        limit: 1,
      );
      if (existantes.isNotEmpty) return false;
      await executeur.insert('listes', <String, Object?>{
        'nom': nom,
        'est_systeme': 1,
        'ordre': ordre,
      });
      return true;
    });

/// Éléments de chaque migration (indice `i` = migration `i + 1`), dans
/// l'ordre de création : une table recréée reçoit ensuite les colonnes des
/// migrations suivantes. Copies des instructions de `migrations.dart` (voir
/// les commentaires de ce fichier pour le choix des contraintes et index).
List<List<_Element>> _elementsParMigration() => <List<_Element>>[
  // Migration 1.
  <_Element>[
    _table('sources', '''
      CREATE TABLE sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        url_base TEXT NOT NULL UNIQUE,
        type_source TEXT NOT NULL,
        langue_par_defaut TEXT NOT NULL DEFAULT '',
        configuration_selecteurs TEXT,
        est_active INTEGER NOT NULL DEFAULT 1 CHECK (est_active IN (0, 1))
      )
      '''),
    _table('titres', '''
      CREATE TABLE titres (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_source INTEGER NOT NULL REFERENCES sources (id) ON DELETE RESTRICT,
        url_titre TEXT NOT NULL UNIQUE,
        nom TEXT NOT NULL,
        type_titre TEXT NOT NULL,
        url_couverture TEXT,
        resume TEXT,
        auteur TEXT,
        statut TEXT,
        date_derniere_verification INTEGER
      )
      '''),
    _objet(
      'index',
      'index_titres_id_source',
      'CREATE INDEX index_titres_id_source ON titres (id_source)',
    ),
    _table('chapitres', '''
      CREATE TABLE chapitres (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
        url_chapitre TEXT NOT NULL UNIQUE,
        nom TEXT NOT NULL,
        numero REAL NOT NULL,
        langue TEXT NOT NULL DEFAULT '',
        date_publication INTEGER,
        est_lu INTEGER NOT NULL DEFAULT 0 CHECK (est_lu IN (0, 1)),
        est_telecharge INTEGER NOT NULL DEFAULT 0
          CHECK (est_telecharge IN (0, 1)),
        date_detection INTEGER
      )
      '''),
    _objet(
      'index',
      'index_chapitres_titre_lu',
      'CREATE INDEX index_chapitres_titre_lu ON chapitres (id_titre, est_lu)',
    ),
    _table('titres_alternatifs', '''
      CREATE TABLE titres_alternatifs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
        nom TEXT NOT NULL,
        langue TEXT NOT NULL DEFAULT '',
        UNIQUE (id_titre, nom)
      )
      '''),
    _table('listes', '''
      CREATE TABLE listes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL UNIQUE COLLATE NOCASE,
        est_systeme INTEGER NOT NULL DEFAULT 0 CHECK (est_systeme IN (0, 1)),
        ordre INTEGER NOT NULL DEFAULT 0
      )
      '''),
    _table('titres_listes', '''
      CREATE TABLE titres_listes (
        id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
        id_liste INTEGER NOT NULL REFERENCES listes (id) ON DELETE CASCADE,
        PRIMARY KEY (id_titre, id_liste)
      )
      '''),
    _objet(
      'index',
      'index_titres_listes_id_liste',
      'CREATE INDEX index_titres_listes_id_liste ON titres_listes (id_liste)',
    ),
    _table('categories', '''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL UNIQUE
      )
      '''),
    _table('titres_categories', '''
      CREATE TABLE titres_categories (
        id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
        id_categorie INTEGER NOT NULL
          REFERENCES categories (id) ON DELETE CASCADE,
        PRIMARY KEY (id_titre, id_categorie)
      )
      '''),
    _objet(
      'index',
      'index_titres_categories_id_categorie',
      'CREATE INDEX index_titres_categories_id_categorie '
          'ON titres_categories (id_categorie)',
    ),
    _listeSysteme('Favoris', 0),
    _listeSysteme('Suivis', 1),
  ],
  // Migration 2.
  <_Element>[
    _table('telechargements', '''
      CREATE TABLE telechargements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_chapitre INTEGER NOT NULL UNIQUE
          REFERENCES chapitres (id) ON DELETE CASCADE,
        statut TEXT NOT NULL DEFAULT 'en_attente'
          CHECK (statut IN ('en_attente', 'en_cours', 'termine', 'echec')),
        nombre_pages_total INTEGER NOT NULL DEFAULT 0
          CHECK (nombre_pages_total >= 0),
        nombre_pages_faites INTEGER NOT NULL DEFAULT 0
          CHECK (nombre_pages_faites >= 0),
        message_erreur TEXT,
        date_ajout INTEGER NOT NULL,
        date_maj INTEGER NOT NULL
      )
      '''),
    _objet(
      'index',
      'index_telechargements_statut',
      'CREATE INDEX index_telechargements_statut '
          'ON telechargements (statut, date_ajout)',
    ),
  ],
  // Migration 3.
  <_Element>[
    _table('parametres', '''
      CREATE TABLE parametres (
        cle TEXT NOT NULL PRIMARY KEY,
        valeur TEXT NOT NULL
      )
      '''),
  ],
  // Migration 4.
  <_Element>[
    _colonne(
      'chapitres',
      'nom_archive',
      'ALTER TABLE chapitres ADD COLUMN nom_archive TEXT',
    ),
    _colonne(
      'chapitres',
      'date_suppression_prevue',
      'ALTER TABLE chapitres ADD COLUMN date_suppression_prevue INTEGER',
    ),
    _objet(
      'index',
      'index_chapitres_nom_archive',
      'CREATE UNIQUE INDEX index_chapitres_nom_archive '
          'ON chapitres (nom_archive)',
    ),
    _objet(
      'index',
      'index_chapitres_suppression_prevue',
      'CREATE INDEX index_chapitres_suppression_prevue '
          'ON chapitres (date_suppression_prevue) '
          'WHERE date_suppression_prevue IS NOT NULL',
    ),
    _colonne(
      'titres',
      'langues_preferees',
      'ALTER TABLE titres ADD COLUMN langues_preferees TEXT',
    ),
  ],
  // Migration 5.
  <_Element>[
    _colonne(
      'chapitres',
      'est_garde',
      'ALTER TABLE chapitres ADD COLUMN est_garde INTEGER NOT NULL DEFAULT 0 '
          'CHECK (est_garde IN (0, 1))',
    ),
    _objet(
      'index',
      'index_chapitres_gardes',
      'CREATE INDEX index_chapitres_gardes ON chapitres (id) '
          'WHERE est_garde = 1',
    ),
    _colonne(
      'titres',
      'niveau_contenu',
      'ALTER TABLE titres ADD COLUMN niveau_contenu TEXT',
    ),
    _colonne(
      'titres',
      'couverture_choisie',
      'ALTER TABLE titres ADD COLUMN couverture_choisie TEXT',
    ),
    _listeSysteme('Planifié', 2),
    _listeSysteme('En attente', 3),
  ],
  // Migration 6.
  <_Element>[
    _colonne(
      'chapitres',
      'url_externe',
      'ALTER TABLE chapitres ADD COLUMN url_externe TEXT',
    ),
  ],
  // Migration 7.
  <_Element>[
    _table(
      'titres_sources',
      '''
      CREATE TABLE titres_sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
        id_source INTEGER NOT NULL REFERENCES sources (id) ON DELETE RESTRICT,
        url_titre TEXT NOT NULL UNIQUE,
        est_principale INTEGER NOT NULL DEFAULT 0
          CHECK (est_principale IN (0, 1)),
        date_ajout INTEGER NOT NULL,
        UNIQUE (id_titre, id_source)
      )
      ''',
      // Table recréée : une ligne principale par titre, comme la
      // migration 7 (titres.url_titre est UNIQUE : rien ne peut échouer).
      apresCreation: (executeur) => executeur.rawInsert(
        'INSERT INTO titres_sources '
        '(id_titre, id_source, url_titre, est_principale, date_ajout) '
        'SELECT id, id_source, url_titre, ?, ? FROM titres',
        <Object?>[1, DateTime.now().toUtc().millisecondsSinceEpoch],
      ),
    ),
    _objet(
      'index',
      'index_titres_sources_principale',
      'CREATE UNIQUE INDEX index_titres_sources_principale '
          'ON titres_sources (id_titre) WHERE est_principale = 1',
    ),
    _objet(
      'index',
      'index_titres_sources_id_source',
      'CREATE INDEX index_titres_sources_id_source '
          'ON titres_sources (id_source)',
    ),
    _colonne(
      'chapitres',
      'id_source',
      'ALTER TABLE chapitres ADD COLUMN id_source INTEGER '
          'REFERENCES sources (id) ON DELETE RESTRICT',
      // Colonne recréée : remplie avec la source principale du titre, comme
      // la migration 7.
      apresAjout: (executeur) => executeur.execute(
        'UPDATE chapitres SET id_source = '
        '(SELECT t.id_source FROM titres t WHERE t.id = chapitres.id_titre) '
        'WHERE id_source IS NULL',
      ),
    ),
    _objet(
      'index',
      'index_chapitres_titre_source',
      'CREATE INDEX index_chapitres_titre_source '
          'ON chapitres (id_titre, id_source)',
    ),
    _objet('trigger', 'declencheur_titres_source_insertion', '''
      CREATE TRIGGER declencheur_titres_source_insertion
      AFTER INSERT ON titres
      BEGIN
        INSERT INTO titres_sources
          (id_titre, id_source, url_titre, est_principale, date_ajout)
        VALUES (NEW.id, NEW.id_source, NEW.url_titre, 1,
          CAST(strftime('%s', 'now') AS INTEGER) * 1000);
      END
      '''),
    _objet('trigger', 'declencheur_titres_source_modification', '''
      CREATE TRIGGER declencheur_titres_source_modification
      AFTER UPDATE OF id_source, url_titre ON titres
      WHEN OLD.id_source IS NOT NEW.id_source
        OR OLD.url_titre IS NOT NEW.url_titre
      BEGIN
        UPDATE titres_sources
        SET id_source = NEW.id_source, url_titre = NEW.url_titre
        WHERE id_titre = NEW.id AND est_principale = 1;
      END
      '''),
    _objet('trigger', 'declencheur_chapitres_source', '''
      CREATE TRIGGER declencheur_chapitres_source
      AFTER INSERT ON chapitres
      WHEN NEW.id_source IS NULL
      BEGIN
        UPDATE chapitres
        SET id_source = (SELECT t.id_source FROM titres t
                         WHERE t.id = NEW.id_titre)
        WHERE id = NEW.id;
      END
      '''),
  ],
  // Migration 8.
  <_Element>[
    _colonne(
      'titres_sources',
      'lien_seul',
      'ALTER TABLE titres_sources ADD COLUMN lien_seul INTEGER NOT NULL '
          'DEFAULT 0 CHECK (lien_seul IN (0, 1))',
    ),
    _objet('trigger', 'declencheur_titres_sources_lien_seul_insertion', '''
      CREATE TRIGGER declencheur_titres_sources_lien_seul_insertion
      BEFORE INSERT ON titres_sources
      WHEN NEW.est_principale = 1 AND NEW.lien_seul = 1
      BEGIN
        SELECT RAISE(ABORT, 'site principal en lien seul interdit');
      END
      '''),
    _objet('trigger', 'declencheur_titres_sources_lien_seul_modification', '''
      CREATE TRIGGER declencheur_titres_sources_lien_seul_modification
      BEFORE UPDATE OF est_principale, lien_seul ON titres_sources
      WHEN NEW.est_principale = 1 AND NEW.lien_seul = 1
      BEGIN
        SELECT RAISE(ABORT, 'site principal en lien seul interdit');
      END
      '''),
  ],
  // Migration 9.
  <_Element>[
    _table('categories_equivalences', '''
      CREATE TABLE categories_equivalences (
        id_categorie INTEGER NOT NULL UNIQUE
          REFERENCES categories (id) ON DELETE CASCADE,
        id_reference INTEGER NOT NULL
          REFERENCES categories (id) ON DELETE CASCADE,
        CHECK (id_categorie <> id_reference)
      )
      '''),
    _objet(
      'index',
      'index_categories_equivalences_id_reference',
      'CREATE INDEX index_categories_equivalences_id_reference '
          'ON categories_equivalences (id_reference)',
    ),
    _objet('trigger', 'declencheur_categories_equivalences_insertion', '''
      CREATE TRIGGER declencheur_categories_equivalences_insertion
      BEFORE INSERT ON categories_equivalences
      WHEN EXISTS (SELECT 1 FROM categories_equivalences
                   WHERE id_categorie = NEW.id_reference)
        OR EXISTS (SELECT 1 FROM categories_equivalences
                   WHERE id_reference = NEW.id_categorie)
      BEGIN
        SELECT RAISE(ABORT, 'chaine de categories equivalentes interdite');
      END
      '''),
    _objet('trigger', 'declencheur_categories_equivalences_modification', '''
      CREATE TRIGGER declencheur_categories_equivalences_modification
      BEFORE UPDATE OF id_categorie, id_reference ON categories_equivalences
      WHEN EXISTS (SELECT 1 FROM categories_equivalences
                   WHERE id_categorie = NEW.id_reference
                     AND id_categorie <> OLD.id_categorie)
        OR EXISTS (SELECT 1 FROM categories_equivalences
                   WHERE id_reference = NEW.id_categorie
                     AND id_categorie <> OLD.id_categorie)
      BEGIN
        SELECT RAISE(ABORT, 'chaine de categories equivalentes interdite');
      END
      '''),
  ],
  // Migration 10.
  <_Element>[
    _colonne(
      'titres',
      'champs_manuels',
      "ALTER TABLE titres ADD COLUMN champs_manuels TEXT NOT NULL DEFAULT '[]'",
    ),
  ],
  // Migration 11 : la liste est ajoutée sans décaler les autres (les
  // positions choisies par le client ne sont pas touchées).
  <_Element>[_listeSysteme('Terminés', 4)],
  // Migration 12.
  <_Element>[
    _colonne(
      'titres',
      'description_perso',
      'ALTER TABLE titres ADD COLUMN description_perso TEXT',
    ),
  ],
  // Migration 13.
  <_Element>[
    _colonne(
      'chapitres',
      'origine',
      "ALTER TABLE chapitres ADD COLUMN origine TEXT NOT NULL DEFAULT 'site' "
          "CHECK (origine IN ('site', 'web'))",
    ),
    _objet('trigger', 'declencheur_chapitres_lien_seul_insertion', '''
      CREATE TRIGGER declencheur_chapitres_lien_seul_insertion
      BEFORE INSERT ON chapitres
      WHEN NEW.origine = 'site'
        AND EXISTS (SELECT 1 FROM titres_sources ts
                    WHERE ts.id_titre = NEW.id_titre
                      AND ts.id_source = NEW.id_source
                      AND ts.lien_seul = 1)
      BEGIN
        SELECT RAISE(ABORT, 'chapitre du site refuse sur un lien seul');
      END
      '''),
    _objet('trigger', 'declencheur_chapitres_lien_seul_modification', '''
      CREATE TRIGGER declencheur_chapitres_lien_seul_modification
      BEFORE UPDATE OF origine, id_titre, id_source ON chapitres
      WHEN NEW.origine = 'site'
        AND (NEW.origine IS NOT OLD.origine
          OR NEW.id_titre IS NOT OLD.id_titre
          OR NEW.id_source IS NOT OLD.id_source)
        AND EXISTS (SELECT 1 FROM titres_sources ts
                    WHERE ts.id_titre = NEW.id_titre
                      AND ts.id_source = NEW.id_source
                      AND ts.lien_seul = 1)
      BEGIN
        SELECT RAISE(ABORT, 'chapitre du site refuse sur un lien seul');
      END
      '''),
  ],
  // Migration 14.
  <_Element>[
    _table('tickets', '''
      CREATE TABLE tickets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repere TEXT NOT NULL UNIQUE,
        titre TEXT NOT NULL,
        type_ticket TEXT NOT NULL
          CHECK (type_ticket IN ('bug', 'suggestion', 'question')),
        date_creation INTEGER NOT NULL,
        numero INTEGER UNIQUE CHECK (numero IS NULL OR numero > 0),
        etat TEXT CHECK (etat IS NULL OR etat IN ('ouvert', 'ferme')),
        raison_fermeture TEXT CHECK (raison_fermeture IS NULL
          OR raison_fermeture IN ('termine', 'non_retenu')),
        etiquettes TEXT NOT NULL DEFAULT '[]',
        nombre_commentaires INTEGER
          CHECK (nombre_commentaires IS NULL OR nombre_commentaires >= 0),
        date_maj_github INTEGER,
        date_dernier_releve INTEGER,
        date_consultation INTEGER
      )
      '''),
  ],
];
