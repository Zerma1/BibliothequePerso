/// Accès des widgets aux images de couverture.
library;

import 'dart:typed_data';

import '../modeles/titre.dart';
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

  /// Couverture affichée de [titre] en vignette (512 px pour MangaDex) :
  /// celle enregistrée sur l'appareil (lisible hors-ligne), sinon
  /// téléchargée puis enregistrée. Pour la grille, les cartes et l'onglet
  /// Mises à jour. `null` si aucune n'est disponible ; ne lève jamais.
  Future<Uint8List?> chargerCouverture(Titre titre) =>
      _service.chargerCouverture(titre);

  /// Couverture de [titre] en pleine taille, pour la fiche d'un titre (la
  /// vignette en cas d'échec). `null` si aucune image n'est disponible ; ne
  /// lève jamais.
  Future<Uint8List?> chargerCouvertureOriginale(Titre titre) =>
      _service.chargerCouvertureOriginale(titre);

  /// Vignette de l'image à [urlCouverture] (miniatures du choix de la
  /// couverture), mise en cache par le service pour la session.
  ///
  /// [referer] est l'URL de base du site du titre, si elle est connue. Lève
  /// l'erreur du service en cas d'échec : le widget affiche alors un espace
  /// réservé.
  Future<Uint8List> recupererVignette(
    String urlCouverture, {
    String? referer,
  }) => _service.recupererVignette(urlCouverture, referer: referer);
}
