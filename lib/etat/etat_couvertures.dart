/// Accès des widgets aux images de couverture.
library;

import 'dart:typed_data';

import '../services/service_bibliotheque.dart';

/// Fournit les octets des couvertures aux widgets.
///
/// Ce n'est pas un ChangeNotifier : chaque image gère son propre chargement.
/// La classe existe pour que les widgets ne dépendent pas directement du
/// service (sens des dépendances, PLAYBOOK.md section 4).
class EtatCouvertures {
  /// Crée l'accès aux couvertures.
  const EtatCouvertures(this._service);

  final ServiceBibliotheque _service;

  /// Octets de la couverture à [urlCouverture], mis en cache par le service.
  ///
  /// [referer] est l'URL de base du site du titre, si elle est connue. Lève
  /// l'erreur du service en cas d'échec : le widget affiche alors un espace
  /// réservé.
  Future<Uint8List> recupererCouverture(
    String urlCouverture, {
    String? referer,
  }) => _service.recupererCouverture(urlCouverture, referer: referer);
}
