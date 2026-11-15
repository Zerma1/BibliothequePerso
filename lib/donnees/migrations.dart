/// Migrations versionnées du schéma SQLite (PLAYBOOK.md section 5).
///
/// Règles :
/// - la migration N fait passer la base de la version N-1 à la version N ;
/// - une migration livrée n'est **jamais** modifiée : toute évolution du schéma
///   ajoute une nouvelle fonction à la fin de [migrations] ;
/// - [versionSchema] est déduite de la longueur de la liste, ce qui évite
///   d'oublier de l'incrémenter.
library;

import 'package:sqflite/sqflite.dart';

/// Une migration : reçoit l'exécuteur de la transaction d'ouverture.
///
/// `sqflite` exécute déjà `onCreate` et `onUpgrade` dans une transaction : une
/// migration qui échoue est donc entièrement annulée.
typedef Migration = Future<void> Function(DatabaseExecutor executeur);

/// Liste ordonnée des migrations : l'élément d'indice `i` est la migration
/// `i + 1`.
const List<Migration> migrations = <Migration>[_migration1, _migration2];

/// Version actuelle du schéma (nombre de migrations).
int get versionSchema => migrations.length;

/// Applique les migrations de [ancienneVersion] (exclue) à [nouvelleVersion]
/// (incluse).
///
/// Utilisée par `onCreate` (ancienne version 0) et par `onUpgrade`.
Future<void> appliquerMigrations(
  DatabaseExecutor executeur,
  int ancienneVersion,
  int nouvelleVersion,
) async {
  for (
    var version = ancienneVersion + 1;
    version <= nouvelleVersion;
    version++
  ) {
    await migrations[version - 1](executeur);
  }
}

/// Migration 1 : schéma initial et listes système « Favoris » et « Suivis ».
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration1(DatabaseExecutor executeur) async {
  // Chaque instruction est exécutée séparément : sqflite sur Android n'exécute
  // que la première instruction d'une chaîne qui en contient plusieurs.
  const instructions = <String>[
    // Booléens en INTEGER 0/1 (SQLite n'a pas de type booléen) ; le CHECK
    // empêche toute autre valeur que depuisMap() refuserait ensuite.
    // url_base UNIQUE : un même site ne peut pas être ajouté deux fois.
    '''
    CREATE TABLE sources (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nom TEXT NOT NULL,
      url_base TEXT NOT NULL UNIQUE,
      type_source TEXT NOT NULL,
      langue_par_defaut TEXT NOT NULL DEFAULT '',
      configuration_selecteurs TEXT,
      est_active INTEGER NOT NULL DEFAULT 1 CHECK (est_active IN (0, 1))
    )
    ''',
    // id_source en ON DELETE RESTRICT (et non CASCADE) : supprimer un site ne
    // doit pas effacer silencieusement toute une partie de la bibliothèque.
    // Le service qui supprime une source doit d'abord supprimer ses titres.
    // url_titre UNIQUE : clé naturelle utilisée pour éviter les doublons.
    // Les dates sont en millisecondes UTC (INTEGER) : compactes et triables.
    '''
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
    ''',
    // Index sur la clé étrangère : SQLite n'en crée pas automatiquement, et il
    // sert au contrôle RESTRICT et au chargement des titres d'une source.
    'CREATE INDEX index_titres_id_source ON titres (id_source)',
    // ON DELETE CASCADE : les chapitres n'ont pas de sens sans leur titre.
    // url_chapitre UNIQUE : permet l'insertion sans doublon (INSERT OR IGNORE)
    // lors de chaque recherche de mises à jour.
    '''
    CREATE TABLE chapitres (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
      url_chapitre TEXT NOT NULL UNIQUE,
      nom TEXT NOT NULL,
      numero REAL NOT NULL,
      langue TEXT NOT NULL DEFAULT '',
      date_publication INTEGER,
      est_lu INTEGER NOT NULL DEFAULT 0 CHECK (est_lu IN (0, 1)),
      est_telecharge INTEGER NOT NULL DEFAULT 0 CHECK (est_telecharge IN (0, 1)),
      date_detection INTEGER
    )
    ''',
    // Index composite (id_titre, est_lu) : couvre à la fois le chargement des
    // chapitres d'un titre et le comptage des non-lus, calculé pour chaque
    // titre affiché dans la bibliothèque.
    'CREATE INDEX index_chapitres_titre_lu ON chapitres (id_titre, est_lu)',
    // UNIQUE(id_titre, nom) : un même nom alternatif n'est pas répété pour un
    // titre ; l'index qu'il crée sert aussi à charger les noms d'un titre.
    '''
    CREATE TABLE titres_alternatifs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
      nom TEXT NOT NULL,
      langue TEXT NOT NULL DEFAULT '',
      UNIQUE (id_titre, nom)
    )
    ''',
    // nom UNIQUE COLLATE NOCASE : « favoris » ne peut pas coexister avec
    // « Favoris » (LIMITE : NOCASE ne replie que les lettres ASCII).
    '''
    CREATE TABLE listes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nom TEXT NOT NULL UNIQUE COLLATE NOCASE,
      est_systeme INTEGER NOT NULL DEFAULT 0 CHECK (est_systeme IN (0, 1)),
      ordre INTEGER NOT NULL DEFAULT 0
    )
    ''',
    // Clé primaire composite : un titre n'apparaît qu'une fois par liste.
    // CASCADE des deux côtés : supprimer un titre ou une liste nettoie la
    // relation sans toucher à l'autre entité.
    '''
    CREATE TABLE titres_listes (
      id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
      id_liste INTEGER NOT NULL REFERENCES listes (id) ON DELETE CASCADE,
      PRIMARY KEY (id_titre, id_liste)
    )
    ''',
    // La clé primaire commence par id_titre : cet index couvre l'autre sens,
    // utilisé par le filtre « titres d'une liste ».
    'CREATE INDEX index_titres_listes_id_liste ON titres_listes (id_liste)',
    // nom UNIQUE : les noms sont normalisés (minuscules, trim) par le dépôt,
    // donc deux sites qui donnent le même genre partagent la même ligne.
    '''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nom TEXT NOT NULL UNIQUE
    )
    ''',
    '''
    CREATE TABLE titres_categories (
      id_titre INTEGER NOT NULL REFERENCES titres (id) ON DELETE CASCADE,
      id_categorie INTEGER NOT NULL REFERENCES categories (id) ON DELETE CASCADE,
      PRIMARY KEY (id_titre, id_categorie)
    )
    ''',
    // Même raison que index_titres_listes_id_liste : filtre par catégorie.
    'CREATE INDEX index_titres_categories_id_categorie '
        'ON titres_categories (id_categorie)',
  ];

  for (final instruction in instructions) {
    await executeur.execute(instruction);
  }

  // Listes système : insertion paramétrée, comme toute écriture de valeur.
  // Valeurs écrites en dur, volontairement (exception à la règle « pas de
  // valeur magique ») : une migration livrée doit produire exactement le même
  // résultat pour toujours. Si l'on utilisait `nomListeFavoris` ou
  // `ordreListeSuivis`, modifier une de ces constantes changerait en silence
  // le contenu de cette migration ; un renommage passe par une nouvelle
  // migration. Les constantes de constantes.dart doivent rester égales à ces
  // valeurs (vérifié par migrations_test.dart).
  await executeur.insert('listes', <String, Object?>{
    'nom': 'Favoris',
    'est_systeme': 1,
    'ordre': 0,
  });
  await executeur.insert('listes', <String, Object?>{
    'nom': 'Suivis',
    'est_systeme': 1,
    'ordre': 1,
  });
}

/// Migration 2 : file de téléchargement hors-ligne (étape 5).
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration2(DatabaseExecutor executeur) async {
  const instructions = <String>[
    // id_chapitre UNIQUE : un chapitre n'apparaît qu'une fois dans la file
    // (ajout sans doublon par INSERT OR IGNORE) ; l'index créé par UNIQUE sert
    // aussi à retrouver le téléchargement d'un chapitre.
    // ON DELETE CASCADE : un chapitre supprimé n'a plus rien à télécharger.
    // statut : valeurs écrites en dur (même raison que les listes système de
    // la migration 1) et vérifiées par CHECK, pour qu'une faute de frappe dans
    // une requête échoue tout de suite au lieu de bloquer la file.
    // Compteurs de pages ≥ 0 (CHECK) ; dates en millisecondes UTC, NOT NULL
    // car date_ajout ordonne la file.
    '''
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
    ''',
    // Index composite (statut, date_ajout) : couvre « prochain en attente »
    // (filtre sur statut puis plus ancien d'abord) sans tri en mémoire, la
    // remise en attente des en_cours au démarrage et le filtre par statut de
    // l'écran des téléchargements.
    'CREATE INDEX index_telechargements_statut '
        'ON telechargements (statut, date_ajout)',
  ];

  for (final instruction in instructions) {
    await executeur.execute(instruction);
  }
}
