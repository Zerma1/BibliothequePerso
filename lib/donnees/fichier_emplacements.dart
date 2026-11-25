/// Fichier `emplacements.json` : indique au désinstalleur Windows
/// (`installateur/*.iss`) le dossier des chapitres téléchargés, qu'il ne
/// peut pas lire dans la base SQLite.
///
/// ```
/// <dossier de la base>/emplacements.json
///     {"dossierChapitres": "<chemin absolu du dossier des chapitres>"}
/// ```
///
/// Stockage pur : aucune décision ici (quand écrire, quoi faire d'un échec),
/// c'est `ServiceDossierChapitres` qui s'en charge.
library;

import 'dart:convert' show jsonEncode, utf8;
import 'dart:io';

import 'package:path/path.dart' as chemins;
import 'package:path_provider/path_provider.dart';

import 'constantes_donnees.dart';

/// Chemin par défaut de [nomFichierEmplacements] : dans le dossier de la base
/// de données (`getApplicationSupportDirectory()`, comme
/// `cheminParDefautBaseDeDonnees`), soit sous Windows
/// `%APPDATA%\io.github.zerma1\bibliotheque_perso\emplacements.json`.
///
/// Renvoie `null` sous Android : la base y est dans un autre dossier
/// (`getDatabasesPath()`) et aucun désinstalleur ne lit ce fichier (Android
/// efface lui-même les données privées de l'application).
///
/// Peut lever l'erreur de `path_provider` (par exemple dans les tests, où le
/// greffon n'est pas enregistré).
Future<String?> cheminParDefautFichierEmplacements() async {
  if (Platform.isAndroid) return null;
  final dossier = await getApplicationSupportDirectory();
  return chemins.join(dossier.path, nomFichierEmplacements);
}

/// Contenu de [nomFichierEmplacements] pour [dossierChapitres] (chemin
/// rendu absolu et normalisé).
///
/// `jsonEncode` : le désinstalleur lit la clé avec les échappements JSON
/// standards (`\\` pour chaque antislash d'un chemin Windows, `\"`…).
String contenuFichierEmplacements(String dossierChapitres) {
  return jsonEncode(<String, String>{
    cleDossierChapitresEmplacements: chemins.normalize(
      chemins.absolute(dossierChapitres.trim()),
    ),
  });
}

/// Écrit [nomFichierEmplacements] au chemin [cheminFichier] pour le dossier
/// des chapitres [dossierChapitres] (contenu : [contenuFichierEmplacements]).
///
/// UTF-8 **sans BOM** (le désinstalleur ne l'attend pas). Écriture sûre : le
/// contenu va d'abord dans un fichier temporaire
/// (`…`[suffixeFichierTemporaireEmplacements]), qui remplace ensuite l'ancien
/// fichier par renommage. Une coupure pendant l'écriture laisse donc
/// l'ancien fichier entier, jamais un JSON tronqué. Le dossier parent est
/// créé au besoin.
///
/// Lève la [FileSystemException] d'écriture ; le fichier temporaire est
/// alors effacé si possible.
Future<void> ecrireFichierEmplacements(
  String cheminFichier,
  String dossierChapitres,
) async {
  final fichier = File(cheminFichier);
  await fichier.parent.create(recursive: true);
  final temporaire = File(
    '$cheminFichier$suffixeFichierTemporaireEmplacements',
  );
  try {
    // Octets écrits à la main : `utf8.encode` n'ajoute jamais de BOM.
    await temporaire.writeAsBytes(
      utf8.encode(contenuFichierEmplacements(dossierChapitres)),
      flush: true,
    );
    // Sous Windows, `rename` remplace un fichier existant (MoveFileEx avec
    // remplacement), comme sous Linux.
    await temporaire.rename(fichier.path);
  } catch (_) {
    try {
      if (await temporaire.exists()) await temporaire.delete();
    } on FileSystemException {
      // Fichier temporaire resté : il sera remplacé à la prochaine écriture.
    }
    rethrow;
  }
}
