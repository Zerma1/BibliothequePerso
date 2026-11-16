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
const List<Migration> migrations = <Migration>[
  _migration1,
  _migration2,
  _migration3,
  _migration4,
  _migration5,
];

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

/// Migration 3 : réglages de l'application (écran Paramètres).
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration3(DatabaseExecutor executeur) async {
  // Table clé-valeur : la clé est la clé primaire (un réglage = une ligne,
  // et son index sert à toute lecture). Toutes les valeurs sont stockées en
  // texte, converties par DepotParametres ; NOT NULL car un réglage absent
  // est représenté par l'absence de ligne, pas par NULL. Pas de ligne
  // initiale : les valeurs par défaut sont définies par la couche services.
  await executeur.execute('''
    CREATE TABLE parametres (
      cle TEXT NOT NULL PRIMARY KEY,
      valeur TEXT NOT NULL
    )
    ''');
}

/// Migration 4 : chemin enregistré de l'archive hors-ligne, suppression
/// automatique planifiée des chapitres téléchargés et langues favorites
/// propres à chaque titre.
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration4(DatabaseExecutor executeur) async {
  const instructions = <String>[
    // nom_archive : chemin RELATIF au dossier racine des téléchargements
    // (séparateur « / »), NULL si le chapitre n'est pas téléchargé ou l'a été
    // avant cette migration (le chemin est alors recalculé). Relatif pour que
    // la base reste valable si le client déplace le dossier racine.
    // ADD COLUMN sans DEFAULT : les lignes existantes reçoivent NULL, ce qui
    // est exactement « chemin non enregistré ».
    'ALTER TABLE chapitres ADD COLUMN nom_archive TEXT',
    // date_suppression_prevue : millisecondes UTC, NULL = aucune suppression
    // prévue (comme les autres dates du schéma).
    'ALTER TABLE chapitres ADD COLUMN date_suppression_prevue INTEGER',
    // Index UNIQUE : deux chapitres ne peuvent jamais désigner la même
    // archive (sinon supprimer l'un effacerait le fichier de l'autre).
    // SQLite considère les NULL comme distincts : les chapitres non
    // téléchargés ne sont pas concernés. L'index sert aussi à retrouver le
    // chapitre d'une archive.
    // LIMITE : comparaison binaire (sensible à la casse), comme les noms
    // calculés ; Windows ignore la casse des fichiers, mais la couche
    // StockageTelechargements choisit un nom libre sur le disque lui-même.
    'CREATE UNIQUE INDEX index_chapitres_nom_archive '
        'ON chapitres (nom_archive)',
    // Index partiel : seules les quelques lignes avec une suppression prévue
    // sont indexées (la grande majorité des chapitres a NULL). Il couvre la
    // recherche des suppressions échues (date_suppression_prevue <= ?), faite
    // à chaque démarrage et à chaque passage de la tâche de fond, sans
    // parcourir toute la table. Index partiels : SQLite 3.8.0+, disponible
    // sur tous les Android visés.
    'CREATE INDEX index_chapitres_suppression_prevue '
        'ON chapitres (date_suppression_prevue) '
        'WHERE date_suppression_prevue IS NOT NULL',
    // langues_preferees : codes de langue séparés par des virgules, par ordre
    // de préférence (« fr,en »). NULL = réglage général. Une simple colonne
    // texte plutôt qu'une table : la liste est courte, toujours lue en
    // entier avec le titre, et jamais filtrée en SQL. Pas d'index : aucune
    // recherche ne porte sur cette colonne.
    'ALTER TABLE titres ADD COLUMN langues_preferees TEXT',
  ];

  for (final instruction in instructions) {
    await executeur.execute(instruction);
  }
}

/// Migration 5 (étape 6) : bouton « Garder » en base, niveau de contenu et
/// couverture choisie des titres, listes système « Planifié » et « En
/// attente ».
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration5(DatabaseExecutor executeur) async {
  const instructions = <String>[
    // est_garde : choix « Garder » du client, auparavant mémorisé dans
    // `parametres` (course possible entre isolats). Une colonne rend le
    // choix atomique avec le reste de la ligne. NOT NULL DEFAULT 0 : les
    // lignes existantes deviennent « non gardé » ; la reprise des
    // identifiants déjà gardés est faite par la couche services
    // (DepotChapitres.marquerGardes). CHECK : booléen 0/1 comme les autres.
    'ALTER TABLE chapitres ADD COLUMN est_garde INTEGER NOT NULL DEFAULT 0 '
        'CHECK (est_garde IN (0, 1))',
    // Index partiel : seuls les chapitres gardés (une poignée) sont indexés.
    // Il sert à charger la liste des gardés sans parcourir la table, et ne
    // coûte rien aux écritures des autres chapitres.
    'CREATE INDEX index_chapitres_gardes ON chapitres (id) '
        'WHERE est_garde = 1',
    // niveau_contenu : valeur MangaDex (`safe`, `suggestive`, `erotica`,
    // `pornographic`), NULL si le site ne la donne pas. Pas de CHECK : une
    // valeur ajoutée un jour par MangaDex ne doit pas bloquer l'enregistrement
    // du titre. Pas d'index : le filtre de la bibliothèque porte sur toute la
    // table des titres (quelques centaines de lignes) et sur peu de valeurs
    // distinctes, un index n'apporterait rien.
    'ALTER TABLE titres ADD COLUMN niveau_contenu TEXT',
    // couverture_choisie : URL d'une autre couverture du site ou chemin d'une
    // image de l'appareil, NULL = couverture du site. Jamais filtrée en SQL :
    // pas d'index.
    'ALTER TABLE titres ADD COLUMN couverture_choisie TEXT',
  ];

  for (final instruction in instructions) {
    await executeur.execute(instruction);
  }

  // Les listes du client occupaient les positions 2 et suivantes : elles
  // sont décalées de deux pour laisser les positions 2 et 3 aux nouvelles
  // listes système (qui restent ainsi groupées avec Favoris et Suivis).
  await executeur.rawUpdate(
    'UPDATE listes SET ordre = ordre + ? WHERE est_systeme = ? AND ordre >= ?',
    <Object?>[2, 0, 2],
  );

  // Valeurs écrites en dur, pour la même raison que dans la migration 1 :
  // une migration livrée doit toujours produire le même résultat. Les
  // constantes nomListePlanifie, nomListeEnAttente, ordreListePlanifie et
  // ordreListeEnAttente doivent rester égales (vérifié par migrations_test).
  const listesSysteme = <(String, int)>[('Planifié', 2), ('En attente', 3)];
  for (final (nom, ordre) in listesSysteme) {
    // Le client a pu créer lui-même une liste de ce nom (nom UNIQUE COLLATE
    // NOCASE) : une insertion échouerait et bloquerait l'ouverture de la
    // base. Sa liste devient alors la liste système, avec ses titres.
    final existantes = await executeur.query(
      'listes',
      columns: <String>['id'],
      where: 'nom = ? COLLATE NOCASE',
      whereArgs: <Object?>[nom],
      limit: 1,
    );
    if (existantes.isEmpty) {
      await executeur.insert('listes', <String, Object?>{
        'nom': nom,
        'est_systeme': 1,
        'ordre': ordre,
      });
    } else {
      await executeur.update(
        'listes',
        <String, Object?>{'nom': nom, 'est_systeme': 1, 'ordre': ordre},
        where: 'id = ?',
        whereArgs: <Object?>[existantes.first['id']],
      );
    }
  }
}
