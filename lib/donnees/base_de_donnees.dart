/// Initialisation et ouverture de la base SQLite, identiques sur Windows, Linux
/// et Android.
library;

import 'dart:io' show Platform;

import 'package:path/path.dart' as chemins;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import 'dossier_base_de_donnees.dart';
import 'migrations.dart';
import 'reparation_schema.dart';

/// Vrai une fois [initialiserFabriqueBaseDeDonnees] exécutée.
bool _fabriqueInitialisee = false;

/// Configure la fabrique SQLite globale selon la plateforme. **Seul endroit
/// du projet** qui le fait.
///
/// - Windows et Linux : `sqfliteFfiInit()` puis `databaseFactory =
///   databaseFactoryFfi` (le plugin `sqflite` ne gère pas ces plateformes).
/// - Android : rien à faire, le plugin `sqflite` enregistre sa fabrique.
///
/// Les appels suivants ne font rien : `sqflite` déconseille de remplacer la
/// fabrique globale plusieurs fois.
void initialiserFabriqueBaseDeDonnees() {
  if (_fabriqueInitialisee) {
    return;
  }
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  _fabriqueInitialisee = true;
}

/// Ouvre la base, active les clés étrangères et applique les migrations.
///
/// - [chemin] : chemin du fichier SQLite. Par défaut, le dossier de données
///   de l'application ([cheminParDefautBaseDeDonnees]). Les tests passent
///   `inMemoryDatabasePath` pour une base en mémoire, recréée à chaque fois.
/// - [fabrique] : fabrique SQLite à utiliser. Si elle est absente,
///   [initialiserFabriqueBaseDeDonnees] est appelée et la fabrique globale
///   est utilisée. Les tests passent `databaseFactoryFfi` pour ne pas
///   modifier l'état global.
/// - [annulerTransactionOuverte] : `false` depuis un isolat secondaire (tâche
///   de fond Android). Sur Android, la connexion native est partagée par tout
///   le processus : l'ouvrir depuis un autre isolat avec la valeur par défaut
///   annulerait en mode debug une transaction en cours de l'application
///   (documentation sqflite, « Isolates and hot restart »). `null` garde la
///   valeur par défaut de sqflite.
///
/// - [versionDemandee] : version du schéma voulue, [versionSchema] par
///   défaut. Réservé aux tests (simuler une version plus ancienne de
///   l'application).
///
/// Lève [ErreurBaseDeDonnees] si la base vient d'une version plus récente
/// de l'application (schéma plus haut que la version demandée) ; la base
/// n'est alors pas modifiée.
///
/// Avec le chemin par défaut, `WidgetsFlutterBinding.ensureInitialized()` doit
/// avoir été appelé (exigence de `path_provider`).
Future<Database> ouvrirBaseDeDonnees({
  String? chemin,
  DatabaseFactory? fabrique,
  bool? annulerTransactionOuverte,
  int? versionDemandee,
}) async {
  if (fabrique == null) {
    initialiserFabriqueBaseDeDonnees();
  }
  final fabriqueUtilisee = fabrique ?? databaseFactory;
  final cheminUtilise = chemin ?? await cheminParDefautBaseDeDonnees();
  final estEnMemoire = cheminUtilise == inMemoryDatabasePath;

  return fabriqueUtilisee.openDatabase(
    cheminUtilise,
    options: OpenDatabaseOptions(
      version: versionDemandee ?? versionSchema,
      // Les clés étrangères sont désactivées par défaut dans SQLite et ce
      // réglage n'est pas mémorisé dans le fichier : il faut le refaire à
      // chaque ouverture, avant toute migration (sinon pas de CASCADE).
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      // user_version 0 : base neuve, ou base dont la version a été perdue
      // (tables déjà présentes) ; la réparation distingue les deux cas.
      onCreate: (db, version) => migrerAvecReparation(db, 0, version),
      onUpgrade: migrerAvecReparation,
      // Sans onDowngrade, sqflite écrirait quand même la version plus basse
      // dans user_version : une version plus récente rejouerait ensuite des
      // migrations déjà faites (incident 0.2.4, « table titres_sources
      // already exists »). L'erreur annule la transaction d'ouverture : la
      // base et sa version restent intactes.
      onDowngrade: (db, ancienne, nouvelle) =>
          throw ErreurBaseDeDonnees(messageBasePlusRecente(ancienne)),
      // Une base en mémoire ne doit pas être partagée entre deux ouvertures
      // (chaque test repart d'une base vide).
      singleInstance: !estEnMemoire,
      rollbackActiveTransactionOnOpen: annulerTransactionOuverte,
    ),
  );
}

/// Répare si besoin la version enregistrée ([reparerVersionSchema]) puis
/// applique les migrations de la version réelle à [nouvelle].
///
/// Utilisée par `onCreate` ([ancienne] = 0) et `onUpgrade`, dans la
/// transaction d'ouverture.
Future<void> migrerAvecReparation(
  DatabaseExecutor executeur,
  int ancienne,
  int nouvelle,
) async {
  final depart = await reparerVersionSchema(executeur, ancienne, nouvelle);
  await appliquerMigrations(executeur, depart, nouvelle);
}

/// Chemin par défaut du fichier SQLite, dans le dossier donné par
/// [preparerDossierBaseDeDonnees] (créé au besoin) :
///
/// - Android : dossier standard des bases (`getDatabasesPath()` de sqflite).
/// - Linux : dossier de support de l'application
///   (`getApplicationSupportDirectory()`), car le dossier par défaut de
///   `sqflite_common_ffi` dépend du dossier courant du processus.
/// - Windows : dossier choisi à l'installation (`dossierBase` de
///   `installation.json`), sinon `%APPDATA%\bibliotheque_perso` ; l'ancien
///   dossier `%APPDATA%\io.github.zerma1\bibliotheque_perso` est déplacé au
///   premier appel ([migrerAncienDossierBase]).
Future<String> cheminParDefautBaseDeDonnees() async {
  return chemins.join(
    await preparerDossierBaseDeDonnees(),
    nomFichierBaseDeDonnees,
  );
}
