/// Choix d'un fichier d'export dans l'explorateur de fichiers du système
/// (bouton « Parcourir… » du dialogue d'import).
library;

import 'package:file_picker/file_picker.dart';

import 'textes.dart';

/// Ouvre l'explorateur de fichiers pour choisir un export JSON ; renvoie le
/// chemin du fichier choisi, ou `null` si le client annule.
/// [dossierInitial] : dossier ouvert en premier (s'il est pris en charge).
typedef ChoisirFichierExport = Future<String?> Function({
  String? dossierInitial,
});

/// Sélecteur de fichier utilisé par le dialogue d'import. L'application
/// utilise [SelecteurFichierExport.systeme] ; un test en fournit un faux
/// (via `Provider<SelecteurFichierExport>`) pour ne jamais ouvrir de vraie
/// fenêtre.
class SelecteurFichierExport {
  /// Crée un sélecteur qui appelle [choisir].
  const SelecteurFichierExport(this.choisir);

  /// Sélecteur réel : explorateur de fichiers du système (`file_picker`).
  static const SelecteurFichierExport systeme = SelecteurFichierExport(
    choisirFichierExportSysteme,
  );

  /// Ouvre le choix du fichier.
  final ChoisirFichierExport choisir;
}

/// Extension des exports complets (`ServiceExport` écrit un `.json` et un
/// `.md` ; seul le `.json` se réimporte).
const String _extensionExport = 'json';

/// Explorateur de fichiers du système (Windows, Linux, Android), filtré sur
/// les fichiers `.json`. Renvoie `null` si le client annule.
Future<String?> choisirFichierExportSysteme({String? dossierInitial}) async {
  // LIMITE : `initialDirectory` n'est pris en compte que sous Windows,
  // Linux et macOS (documentation de file_picker 11.0.3) ; sous Android,
  // l'explorateur s'ouvre là où le système le décide. Sous Android, le
  // filtre passe par le type MIME (application/json) : un gestionnaire de
  // fichiers qui ne reconnaît pas ce type peut griser un export valide.
  // Sous Android, le chemin renvoyé est celui d'une copie en cache du
  // fichier choisi, ce qui suffit pour le lire.
  final resultat = await FilePicker.pickFiles(
    dialogTitle: Textes.titreChoixFichierImport,
    initialDirectory: dossierInitial,
    type: FileType.custom,
    allowedExtensions: const <String>[_extensionExport],
    // Sous Windows, la fenêtre reste devant l'application tant qu'elle est
    // ouverte (comme une boîte de dialogue).
    lockParentWindow: true,
  );
  if (resultat == null || resultat.files.isEmpty) return null;
  return resultat.files.first.path;
}
