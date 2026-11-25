/// Export des rapports d'erreur (tâche IN4 de l'étape 6) : quand l'ajout
/// d'un site ou d'un titre échoue, le client peut enregistrer un rapport
/// sans données personnelles et l'envoyer pour faire diagnostiquer le site.
library;

import '../services/service_rapports_erreur.dart';
import 'description_erreur.dart';

/// Accès des widgets à `ServiceRapportsErreur`.
///
/// Ce n'est pas un ChangeNotifier : chaque bouton suit son propre export.
/// La classe existe pour que les widgets ne dépendent pas directement du
/// service (sens des dépendances, PLAYBOOK.md section 4).
class EtatRapportsErreur {
  /// Crée l'accès au service des rapports.
  const EtatRapportsErreur(this._service);

  final ServiceRapportsErreur _service;

  /// Dossier où les rapports sont écrits (affiché au client).
  String get dossierRapports => _service.dossierRapports;

  /// Écrit le rapport de [erreur] et renvoie le chemin du fichier.
  ///
  /// [action] décrit ce que faisait le client (texte de `Textes`, recopié
  /// dans le rapport). L'erreur d'origine ([DescriptionErreur.cause]) est
  /// utilisée si elle est connue, sinon son message.
  Future<ResultatAction<String>> exporter(
    DescriptionErreur erreur, {
    required String action,
  }) async {
    try {
      final chemin = await _service.exporterRapport(
        erreur.cause ?? erreur.detail,
        action: action,
      );
      return ResultatAction<String>.reussite(chemin);
    } catch (exception, pile) {
      return ResultatAction<String>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }
}
