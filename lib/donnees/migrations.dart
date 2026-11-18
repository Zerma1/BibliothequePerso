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
  _migration6,
  _migration7,
  _migration8,
  _migration9,
  _migration10,
  _migration11,
  _migration12,
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
  //
  // Le booléen indique s'il faut renommer une liste du client de même nom
  // au lieu de la fusionner (voir plus bas).
  const listesSysteme = <(String, int, bool)>[
    ('Planifié', 2, false),
    ('En attente', 3, true),
  ];
  for (final (nom, ordre, renommerCollision) in listesSysteme) {
    // Le client a pu créer lui-même une liste de ce nom (nom UNIQUE COLLATE
    // NOCASE) : une insertion échouerait et bloquerait l'ouverture de la
    // base.
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
    } else if (renommerCollision) {
      // « En attente » est remplie et vidée automatiquement par le
      // classement : fusionnée, la liste du client perdrait ses titres en
      // silence. Elle est donc renommée « En attente (perso) » (puis
      // « En attente (perso 2) », « (perso 3) »... si ce nom est déjà
      // pris), garde son identifiant, ses titres et sa position, et la
      // liste système est créée à côté, vide.
      final nouveauNom = await _nomLibre(executeur, '$nom (perso)');
      await executeur.update(
        'listes',
        <String, Object?>{'nom': nouveauNom},
        where: 'id = ?',
        whereArgs: <Object?>[existantes.first['id']],
      );
      await executeur.insert('listes', <String, Object?>{
        'nom': nom,
        'est_systeme': 1,
        'ordre': ordre,
      });
    } else {
      // « Planifié » n'est jamais vidée automatiquement : la liste du
      // client devient la liste système, avec ses titres.
      await executeur.update(
        'listes',
        <String, Object?>{'nom': nom, 'est_systeme': 1, 'ordre': ordre},
        where: 'id = ?',
        whereArgs: <Object?>[existantes.first['id']],
      );
    }
  }
}

/// Renvoie [base] s'il n'est porté par aucune liste (comparaison insensible
/// à la casse, comme la contrainte UNIQUE COLLATE NOCASE de `listes.nom`),
/// sinon le premier nom libre parmi « base sans la parenthèse finale + 2) »,
/// « ... 3) », etc. Ex. : « En attente (perso) » → « En attente (perso 2) ».
///
/// Utilisée par les migrations 5 et 11 : NE PLUS MODIFIER après livraison.
Future<String> _nomLibre(DatabaseExecutor executeur, String base) async {
  Future<bool> estPris(String nom) async => (await executeur.query(
    'listes',
    columns: <String>['id'],
    where: 'nom = ? COLLATE NOCASE',
    whereArgs: <Object?>[nom],
    limit: 1,
  )).isNotEmpty;

  if (!await estPris(base)) {
    return base;
  }
  final racine = base.endsWith(')') ? base.substring(0, base.length - 1) : base;
  for (var numero = 2; ; numero++) {
    final candidat = base.endsWith(')')
        ? '$racine $numero)'
        : '$racine $numero';
    if (!await estPris(candidat)) {
      return candidat;
    }
  }
}

/// Migration 6 (tâche R4) : lien externe des chapitres non hébergés par le
/// site source (ex. MangaDex qui renvoie vers le site de l'éditeur).
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration6(DatabaseExecutor executeur) async {
  // url_externe : URL du chapitre chez l'éditeur, NULL = chapitre hébergé
  // par le site source. ADD COLUMN sans DEFAULT : les lignes existantes
  // reçoivent NULL, c'est-à-dire « hébergé », ce qui était le cas de tous
  // les chapitres enregistrés jusqu'ici. Pas de NOT NULL ni de CHECK : la
  // valeur vient du site et n'a pas de format garanti. Pas d'UNIQUE : un
  // éditeur peut renvoyer plusieurs chapitres vers la même page. Pas
  // d'index : la colonne n'est jamais un critère de recherche (elle est lue
  // avec le chapitre, et la mise à jour par enregistrerChapitres passe par
  // l'index UNIQUE de url_chapitre).
  await executeur.execute('ALTER TABLE chapitres ADD COLUMN url_externe TEXT');
}

/// Migration 7 (étape 8, tâche M1) : plusieurs sites pour un même titre.
///
/// - Table `titres_sources` : tous les sites d'un titre, dont le principal,
///   remplie avec le site actuel (`titres.id_source`, `titres.url_titre`) de
///   chaque titre existant.
/// - Colonne `chapitres.id_source` : site d'origine de chaque chapitre,
///   remplie avec la source principale de son titre.
///
/// Compatibilité : `titres.id_source` et `titres.url_titre` restent le site
/// principal. Ils deviennent **redondants** avec la ligne
/// `est_principale = 1` de `titres_sources`, gardés pour ne casser aucun
/// appel existant (`DepotTitres`, filtre par source, contrôle RESTRICT de
/// suppression d'une source). Des déclencheurs SQL maintiennent les deux en
/// accord, quel que soit le chemin d'écriture.
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration7(DatabaseExecutor executeur) async {
  const creationTitresSources = <String>[
    // id_titre ON DELETE CASCADE : les sites d'un titre supprimé n'ont plus
    // de sens. id_source ON DELETE RESTRICT, comme titres.id_source :
    // supprimer un site ne doit pas effacer en silence une partie de la
    // bibliothèque.
    // url_titre UNIQUE (tous titres confondus) : une même adresse ne peut
    // désigner qu'un seul titre, sinon les chapitres d'un site seraient
    // enregistrés sous deux titres ; l'index créé sert aussi à retrouver un
    // titre par l'URL de n'importe lequel de ses sites.
    // UNIQUE (id_titre, id_source) : un site n'est lié qu'une fois à un
    // titre ; l'index créé (id_titre en tête) sert au chargement des sites
    // d'un titre.
    // est_principale : booléen 0/1 (CHECK) ; l'unicité du principal est
    // assurée par l'index partiel ci-dessous.
    // date_ajout : millisecondes UTC, NOT NULL (remplie par la migration,
    // les déclencheurs et le dépôt) ; sert à l'ordre d'affichage.
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
    // Index UNIQUE partiel : au plus un site principal par titre. Seules
    // les lignes principales sont indexées (une par titre).
    'CREATE UNIQUE INDEX index_titres_sources_principale '
        'ON titres_sources (id_titre) WHERE est_principale = 1',
    // Index sur la clé étrangère id_source : SQLite n'en crée pas, et il
    // sert au contrôle RESTRICT et au comptage des titres d'une source avant
    // sa suppression (DepotSources.supprimerSource).
    'CREATE INDEX index_titres_sources_id_source '
        'ON titres_sources (id_source)',
  ];
  const suite = <String>[
    // id_source des chapitres : NULL autorisé (ADD COLUMN ne peut pas
    // ajouter NOT NULL sans valeur par défaut) ; NULL signifie « site
    // principal du titre ». Les lignes existantes sont remplies plus bas et
    // les nouvelles par le déclencheur declencheur_chapitres_source. ON
    // DELETE RESTRICT (même raison que plus haut). La clé étrangère est
    // permise par ADD COLUMN car la valeur par défaut est NULL.
    'ALTER TABLE chapitres ADD COLUMN id_source INTEGER '
        'REFERENCES sources (id) ON DELETE RESTRICT',
    // Remplissage : la source principale actuelle du titre, seule source
    // connue jusqu'ici. Aucune valeur extérieure : pas de paramètre.
    'UPDATE chapitres SET id_source = '
        '(SELECT t.id_source FROM titres t WHERE t.id = chapitres.id_titre) '
        'WHERE id_source IS NULL',
    // Index composite (id_titre, id_source) : couvre le chargement des
    // chapitres d'un titre filtrés par site et la suppression des chapitres
    // d'un site retiré. LIMITE : il ne sert pas au contrôle RESTRICT d'une
    // suppression de source (id_source n'est pas en tête), opération rare
    // qui parcourt alors la table.
    'CREATE INDEX index_chapitres_titre_source '
        'ON chapitres (id_titre, id_source)',
    // Déclencheur : tout titre inséré reçoit sa ligne principale dans
    // titres_sources (DepotTitres.enregistrerTitre et les insertions
    // directes restent ainsi valables sans modification). Une URL déjà
    // utilisée comme site secondaire d'un autre titre fait échouer
    // l'insertion (contrainte UNIQUE), donc toute la transaction.
    // Date : secondes UTC de SQLite × 1000 (strftime('%s') existe sur
    // toutes les versions de SQLite, contrairement à unixepoch()).
    '''
    CREATE TRIGGER declencheur_titres_source_insertion
    AFTER INSERT ON titres
    BEGIN
      INSERT INTO titres_sources
        (id_titre, id_source, url_titre, est_principale, date_ajout)
      VALUES (NEW.id, NEW.id_source, NEW.url_titre, 1,
        CAST(strftime('%s', 'now') AS INTEGER) * 1000);
    END
    ''',
    // Déclencheur : si le site principal change dans titres (mise à jour du
    // titre ou DepotTitresSources.definirSourcePrincipale), la ligne
    // principale de titres_sources suit. La clause WHEN évite toute
    // écriture quand rien ne change (cas normal d'une actualisation).
    '''
    CREATE TRIGGER declencheur_titres_source_modification
    AFTER UPDATE OF id_source, url_titre ON titres
    WHEN OLD.id_source IS NOT NEW.id_source
      OR OLD.url_titre IS NOT NEW.url_titre
    BEGIN
      UPDATE titres_sources
      SET id_source = NEW.id_source, url_titre = NEW.url_titre
      WHERE id_titre = NEW.id AND est_principale = 1;
    END
    ''',
    // Déclencheur : un chapitre inséré sans source (appels antérieurs à
    // l'étape 8) reçoit la source principale de son titre. La colonne n'est
    // donc jamais NULL en pratique, et le filtre par site peut utiliser
    // l'index sans traiter NULL à part.
    '''
    CREATE TRIGGER declencheur_chapitres_source
    AFTER INSERT ON chapitres
    WHEN NEW.id_source IS NULL
    BEGIN
      UPDATE chapitres
      SET id_source = (SELECT t.id_source FROM titres t
                       WHERE t.id = NEW.id_titre)
      WHERE id = NEW.id;
    END
    ''',
  ];

  for (final instruction in creationTitresSources) {
    await executeur.execute(instruction);
  }
  // Une ligne principale par titre existant, avant la création des
  // déclencheurs. titres.url_titre étant déjà UNIQUE, les contraintes de la
  // nouvelle table ne peuvent pas échouer.
  await executeur.rawInsert(
    'INSERT INTO titres_sources '
    '(id_titre, id_source, url_titre, est_principale, date_ajout) '
    'SELECT id, id_source, url_titre, ?, ? FROM titres',
    <Object?>[1, DateTime.now().toUtc().millisecondsSinceEpoch],
  );
  for (final instruction in suite) {
    await executeur.execute(instruction);
  }
}

/// Migration 8 (tâche T4) : sites en « lien seul ».
///
/// Colonne `titres_sources.lien_seul` : site que l'application ne sait pas
/// lire (protection anti-robot, adaptateur incapable), gardé seulement pour
/// être ouvert dans le navigateur ; aucun chapitre n'y est lu. Le site
/// principal n'est jamais un lien seul (garanti par deux déclencheurs, en
/// plus des contrôles de `DepotTitresSources`).
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration8(DatabaseExecutor executeur) async {
  const instructions = <String>[
    // Booléen 0/1 (CHECK), NOT NULL DEFAULT 0 : les liens existants, tous
    // lisibles jusqu'ici, deviennent des sites normaux. ADD COLUMN accepte
    // NOT NULL grâce à la valeur par défaut. Pas d'index : la colonne est
    // lue avec les sites d'un titre (index UNIQUE (id_titre, id_source)),
    // jamais cherchée seule.
    'ALTER TABLE titres_sources ADD COLUMN lien_seul INTEGER NOT NULL '
        'DEFAULT 0 CHECK (lien_seul IN (0, 1))',
    // Déclencheurs : une ligne à la fois principale et lien seul est
    // refusée, quel que soit le chemin d'écriture. Un CHECK de table
    // (est_principale = 0 OR lien_seul = 0) aurait demandé de recréer la
    // table, ce que ADD COLUMN ne permet pas. Le texte d'erreur sert
    // seulement au diagnostic : le dépôt vérifie avant d'écrire et donne un
    // message clair.
    '''
    CREATE TRIGGER declencheur_titres_sources_lien_seul_insertion
    BEFORE INSERT ON titres_sources
    WHEN NEW.est_principale = 1 AND NEW.lien_seul = 1
    BEGIN
      SELECT RAISE(ABORT, 'site principal en lien seul interdit');
    END
    ''',
    '''
    CREATE TRIGGER declencheur_titres_sources_lien_seul_modification
    BEFORE UPDATE OF est_principale, lien_seul ON titres_sources
    WHEN NEW.est_principale = 1 AND NEW.lien_seul = 1
    BEGIN
      SELECT RAISE(ABORT, 'site principal en lien seul interdit');
    END
    ''',
  ];
  for (final instruction in instructions) {
    await executeur.execute(instruction);
  }
}

/// Migration 9 : regroupement des catégories de même sens (« survival » /
/// « survie »), PLAYBOOK.md section « idées futures ».
///
/// Table `categories_equivalences` : chaque ligne rattache une catégorie à
/// sa **catégorie de référence**. Un groupe = une référence et les
/// catégories qui lui sont rattachées. Les catégories et `titres_categories`
/// ne changent pas : les adaptateurs de sites continuent d'enregistrer les
/// noms qu'ils lisent, le regroupement n'intervient qu'à la lecture.
///
/// Un seul niveau : une référence n'est jamais elle-même rattachée, et une
/// catégorie rattachée n'est jamais la référence d'une autre (pas de
/// chaîne, donc pas de cycle). Garanti par deux déclencheurs, en plus des
/// contrôles de `DepotEquivalencesCategories`.
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration9(DatabaseExecutor executeur) async {
  const instructions = <String>[
    // id_categorie UNIQUE : une catégorie a au plus une référence ; l'index
    // créé sert à retrouver la référence d'une catégorie (lecture des
    // catégories effectives et filtre de la bibliothèque). Ce n'est pas la
    // clé primaire INTEGER : elle deviendrait un alias du rowid, et une
    // insertion avec NULL recevrait un identifiant automatique au lieu
    // d'échouer.
    // ON DELETE CASCADE des deux côtés : supprimer une catégorie retire son
    // rattachement, et supprimer une référence défait son groupe (les
    // catégories rattachées redeviennent indépendantes, rien d'autre n'est
    // effacé).
    // CHECK (id_categorie <> id_reference) : une catégorie ne peut pas être
    // sa propre référence (cycle de longueur 1).
    '''
    CREATE TABLE categories_equivalences (
      id_categorie INTEGER NOT NULL UNIQUE
        REFERENCES categories (id) ON DELETE CASCADE,
      id_reference INTEGER NOT NULL
        REFERENCES categories (id) ON DELETE CASCADE,
      CHECK (id_categorie <> id_reference)
    )
    ''',
    // Index sur la clé étrangère id_reference : SQLite n'en crée pas. Il
    // sert à la cascade quand une référence est supprimée, au chargement
    // des catégories d'un groupe et aux contrôles des déclencheurs.
    'CREATE INDEX index_categories_equivalences_id_reference '
        'ON categories_equivalences (id_reference)',
    // Déclencheurs : refusent toute chaîne (A → B → C), quel que soit le
    // chemin d'écriture. Une contrainte CHECK ne peut pas lire d'autres
    // lignes, d'où les déclencheurs. Le texte d'erreur sert seulement au
    // diagnostic : le dépôt vérifie avant d'écrire et donne un message
    // clair. Sans chaîne et sans boucle sur soi-même (CHECK), aucun cycle
    // n'est possible.
    '''
    CREATE TRIGGER declencheur_categories_equivalences_insertion
    BEFORE INSERT ON categories_equivalences
    WHEN EXISTS (SELECT 1 FROM categories_equivalences
                 WHERE id_categorie = NEW.id_reference)
      OR EXISTS (SELECT 1 FROM categories_equivalences
                 WHERE id_reference = NEW.id_categorie)
    BEGIN
      SELECT RAISE(ABORT, 'chaine de categories equivalentes interdite');
    END
    ''',
    // Mise à jour : même contrôle, en ignorant la ligne modifiée elle-même
    // (id_categorie est UNIQUE, il identifie la ligne).
    '''
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
    ''',
  ];
  for (final instruction in instructions) {
    await executeur.execute(instruction);
  }
}

/// Migration 10 : champs d'un titre modifiés à la main par le client,
/// protégés contre l'actualisation depuis le site.
///
/// Colonne `titres.champs_manuels` : tableau JSON des noms des champs
/// verrouillés (`["nom","resume"]`, valeurs de `ChampTitre`).
///
/// Une colonne JSON plutôt qu'une colonne booléenne par champ : un champ
/// verrouillable ajouté plus tard ne demande pas de migration, et la ligne
/// reste lisible d'un coup avec le titre (aucune requête de plus au
/// chargement). Plutôt qu'une table à part : le verrou n'est jamais cherché
/// seul (jamais de « tous les titres dont le résumé est manuel »), il est
/// toujours lu avec son titre ; il disparaît avec lui sans cascade.
///
/// NOT NULL DEFAULT '[]' : les titres existants n'ont aucun champ manuel, et
/// ADD COLUMN accepte NOT NULL grâce à la valeur par défaut. Pas de CHECK
/// sur le contenu (SQLite sans JSON1 garanti sur tous les Android) : le
/// modèle ignore un nom inconnu et le dépôt est le seul à écrire. Pas
/// d'index : la colonne n'est jamais un critère de recherche.
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration10(DatabaseExecutor executeur) async {
  await executeur.execute(
    "ALTER TABLE titres ADD COLUMN champs_manuels TEXT NOT NULL DEFAULT '[]'",
  );
}

/// Migration 11 : liste système « Terminés » (titres que le client a fini
/// de lire), placée juste après « En attente ».
///
/// Aucune table ni colonne : une ligne de `listes` (`est_systeme = 1`), donc
/// protégée par `DepotListes` comme les autres listes système.
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration11(DatabaseExecutor executeur) async {
  // Valeurs écrites en dur, pour la même raison que dans les migrations 1
  // et 5 : une migration livrée doit toujours produire le même résultat. Les
  // constantes nomListeTermines et ordreListeTermines doivent rester égales
  // (vérifié par migrations_test).
  const nom = 'Terminés';
  const ordre = 4;

  // Les listes en position 4 et au-delà sont décalées d'un cran pour laisser
  // la position 4 à « Terminés ». Contrairement à la migration 5, les listes
  // système sont décalées aussi : le client peut les déplacer avec
  // DepotListes.enregistrerOrdre, et décaler toutes les lignes
  // garde exactement l'ordre relatif qu'il a choisi.
  await executeur.rawUpdate(
    'UPDATE listes SET ordre = ordre + ? WHERE ordre >= ?',
    <Object?>[1, ordre],
  );

  // Le client a pu créer lui-même une liste « Terminés » (nom UNIQUE COLLATE
  // NOCASE) : une insertion échouerait et bloquerait l'ouverture de la base.
  // Comme pour « En attente » (migration 5), sa liste n'est pas fusionnée
  // avec la liste système (dont le sens est fixé par l'application, et que
  // la couche services peut remplir elle-même) : elle est renommée « Terminés (perso) » (ou
  // « (perso 2) »… si ce nom est pris) et garde son identifiant, ses titres
  // et sa position ; la liste système est créée à côté, vide.
  final existantes = await executeur.query(
    'listes',
    columns: <String>['id'],
    where: 'nom = ? COLLATE NOCASE',
    whereArgs: <Object?>[nom],
    limit: 1,
  );
  if (existantes.isNotEmpty) {
    final nouveauNom = await _nomLibre(executeur, '$nom (perso)');
    await executeur.update(
      'listes',
      <String, Object?>{'nom': nouveauNom},
      where: 'id = ?',
      whereArgs: <Object?>[existantes.first['id']],
    );
  }
  await executeur.insert('listes', <String, Object?>{
    'nom': nom,
    'est_systeme': 1,
    'ordre': ordre,
  });
}

/// Migration 12 : description personnelle d'un titre, écrite par le client,
/// distincte du résumé du site (`titres.resume`).
///
/// Colonne `titres.description_perso` : texte libre, NULL par défaut (les
/// titres existants n'en ont pas ; ADD COLUMN sans valeur par défaut remplit
/// NULL). NULL plutôt qu'un texte vide pour « aucune description » : le dépôt
/// remplace un texte vide par NULL, une seule représentation de l'absence.
/// Une colonne de `titres` plutôt qu'une table à part : au plus une
/// description par titre, toujours lue avec lui, supprimée avec lui. Pas
/// d'index : la colonne n'est jamais un critère de recherche.
///
/// NE PLUS MODIFIER après livraison.
Future<void> _migration12(DatabaseExecutor executeur) async {
  await executeur.execute(
    'ALTER TABLE titres ADD COLUMN description_perso TEXT',
  );
}
