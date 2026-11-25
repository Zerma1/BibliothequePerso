/// Export des titres et des sites (tâche R7) et réimport d'un export (U1) :
/// section « Sauvegarde et export » des paramètres.
library;

import '../services/service_export.dart';
import '../services/service_import.dart';
import 'description_erreur.dart';

// Les écrans n'importent que les états (PLAYBOOK.md section 4) : le
// résultat d'un import leur est fourni par cet état.
export '../services/service_import.dart' show ErreurLigneImport, ResultatImport;

/// État de l'export et de l'import de la bibliothèque : opération en cours,
/// dernier résultat ou dernière erreur.
class EtatExport extends EtatNotifiant {
  /// Crée l'état sur [_service].
  ///
  /// [serviceImport] : sans lui, le bouton « Importer un export » est masqué.
  /// [listerExports] : liste les fichiers JSON du dossier des exports (le
  /// plus récent d'abord) ; sans elle, seul le dernier export de la session
  /// est proposé, et le client peut coller un autre chemin.
  EtatExport(this._service, {this._serviceImport, this._listerExports});

  final ServiceExport _service;
  final ServiceImport? _serviceImport;
  final Future<List<String>> Function()? _listerExports;

  bool _estEnCours = false;
  bool _estEnImport = false;
  ResultatExport? _dernierResultat;
  DescriptionErreur? _erreur;

  /// `true` pendant l'écriture des fichiers (bouton désactivé).
  bool get estEnCours => _estEnCours;

  /// `true` pendant un import (boutons désactivés).
  bool get estEnImport => _estEnImport;

  /// `true` si l'application sait importer un export.
  bool get peutImporter => _serviceImport != null;

  /// Résultat du dernier export réussi de cette session, ou `null`.
  ResultatExport? get dernierResultat => _dernierResultat;

  /// Erreur du dernier export ou import, ou `null` s'il a réussi.
  DescriptionErreur? get erreur => _erreur;

  /// Dossier où les exports sont écrits (bouton « Ouvrir le dossier »).
  String get dossierExports => _service.dossierExports;

  /// Exporte les titres et les sites. Une `ErreurService` (fichier non
  /// écrit) ou une `ErreurBaseDeDonnees` devient un message lisible.
  ///
  /// Un second appel pendant l'export (double clic) reçoit le même résultat :
  /// le service n'écrit qu'une paire de fichiers.
  Future<ResultatAction<ResultatExport>> exporter() async {
    _estEnCours = true;
    _erreur = null;
    notifier();
    try {
      final resultat = await _service.exporter();
      _dernierResultat = resultat;
      return ResultatAction<ResultatExport>.reussite(resultat);
    } catch (exception, pile) {
      final description = DescriptionErreur.depuis(exception, pile);
      _erreur = description;
      return ResultatAction<ResultatExport>.echec(description);
    } finally {
      _estEnCours = false;
      notifier();
    }
  }

  /// Fichiers JSON proposés à l'import : ceux du dossier des exports (si
  /// l'application sait les lister) et le dernier export de la session,
  /// sans doublon. Une erreur de lecture du dossier donne une liste vide :
  /// le client peut toujours coller un chemin.
  Future<List<String>> chargerExportsDisponibles() async {
    final chemins = <String>[];
    final lister = _listerExports;
    if (lister != null) {
      try {
        chemins.addAll(await lister());
      } catch (_) {
        // Dossier absent ou illisible : rien à proposer.
      }
    }
    final dernier = _dernierResultat?.cheminJson;
    if (dernier != null && !chemins.contains(dernier)) {
      chemins.insert(0, dernier);
    }
    return chemins;
  }

  /// Importe le fichier [chemin] (fusion sans doublon, voir
  /// `ServiceImport`). Un fichier refusé (`ErreurService`) devient un
  /// message lisible ; les lignes en erreur sont dans le résultat.
  Future<ResultatAction<ResultatImport>> importer(String chemin) async {
    final service = _serviceImport;
    final nettoye = chemin.trim();
    if (service == null || nettoye.isEmpty) {
      return const ResultatAction<ResultatImport>.echec(
        DescriptionErreur(NatureErreur.refus, detail: 'Aucun fichier choisi.'),
      );
    }
    _estEnImport = true;
    _erreur = null;
    notifier();
    try {
      final resultat = await service.importerFichier(nettoye);
      return ResultatAction<ResultatImport>.reussite(resultat);
    } catch (exception, pile) {
      final description = DescriptionErreur.depuis(exception, pile);
      _erreur = description;
      return ResultatAction<ResultatImport>.echec(description);
    } finally {
      _estEnImport = false;
      notifier();
    }
  }
}
