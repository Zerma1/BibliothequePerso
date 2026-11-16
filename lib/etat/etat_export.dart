/// Export des titres et des sites (tâche R7) : section « Sauvegarde et
/// export » des paramètres.
library;

import '../services/service_export.dart';
import 'description_erreur.dart';

/// État de l'export de la bibliothèque : export en cours, dernier résultat
/// ou dernière erreur.
class EtatExport extends EtatNotifiant {
  /// Crée l'état sur [_service].
  EtatExport(this._service);

  final ServiceExport _service;

  bool _estEnCours = false;
  ResultatExport? _dernierResultat;
  DescriptionErreur? _erreur;

  /// `true` pendant l'écriture des fichiers (bouton désactivé).
  bool get estEnCours => _estEnCours;

  /// Résultat du dernier export réussi de cette session, ou `null`.
  ResultatExport? get dernierResultat => _dernierResultat;

  /// Erreur du dernier export, ou `null` s'il a réussi.
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
}
