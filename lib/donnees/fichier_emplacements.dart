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

import 'constantes_donnees.dart';
import 'dossier_base_de_donnees.dart';

/// Chemin par défaut de [nomFichierEmplacements] : dans le dossier de la base
/// de données **effectivement utilisé** ([preparerDossierBaseDeDonnees], le
/// même que `cheminParDefautBaseDeDonnees`), soit sous Windows
/// `%APPDATA%\bibliotheque_perso\emplacements.json` par défaut, ou le
/// dossier choisi à l'installation (`dossierBase`). Si l'ancien dossier n'a
/// pas pu être déplacé, le fichier reste à côté de la base, dans l'ancien
/// dossier.
///
/// Renvoie `null` sous Android : aucun désinstalleur ne lit ce fichier
/// (Android efface lui-même les données privées de l'application).
///
/// Peut lever l'erreur de [preparerDossierBaseDeDonnees] (dans les tests
/// notamment, où elle lève une `StateError`).
Future<String?> cheminParDefautFichierEmplacements() async {
  if (Platform.isAndroid) return null;
  return chemins.join(
    await preparerDossierBaseDeDonnees(),
    nomFichierEmplacements,
  );
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
