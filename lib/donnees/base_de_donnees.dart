/// Initialisation et ouverture de la base SQLite, identiques sur Windows, Linux
/// et Android.
library;

import 'dart:io' show Platform;

import 'package:path/path.dart' as chemins;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../modeles/constantes.dart';
import 'migrations.dart';

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
/// Avec le chemin par défaut, `WidgetsFlutterBinding.ensureInitialized()` doit
/// avoir été appelé (exigence de `path_provider`).
Future<Database> ouvrirBaseDeDonnees({
  String? chemin,
  DatabaseFactory? fabrique,
  bool? annulerTransactionOuverte,
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
      version: versionSchema,
      // Les clés étrangères sont désactivées par défaut dans SQLite et ce
      // réglage n'est pas mémorisé dans le fichier : il faut le refaire à
      // chaque ouverture, avant toute migration (sinon pas de CASCADE).
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => appliquerMigrations(db, 0, version),
      onUpgrade: (db, ancienne, nouvelle) =>
          appliquerMigrations(db, ancienne, nouvelle),
      // Une base en mémoire ne doit pas être partagée entre deux ouvertures
      // (chaque test repart d'une base vide).
      singleInstance: !estEnMemoire,
      rollbackActiveTransactionOnOpen: annulerTransactionOuverte,
    ),
  );
}

/// Chemin par défaut du fichier SQLite.
///
/// - Android : dossier standard des bases (`getDatabasesPath()` de sqflite).
/// - Windows et Linux : dossier de support de l'application
///   (`getApplicationSupportDirectory()`), car le dossier par défaut de
///   `sqflite_common_ffi` dépend du dossier courant du processus.
Future<String> cheminParDefautBaseDeDonnees() async {
  if (Platform.isAndroid) {
    return chemins.join(await getDatabasesPath(), nomFichierBaseDeDonnees);
  }
  final dossier = await getApplicationSupportDirectory();
  // SQLite crée le fichier mais pas les dossiers parents.
  await dossier.create(recursive: true);
  return chemins.join(dossier.path, nomFichierBaseDeDonnees);
}
