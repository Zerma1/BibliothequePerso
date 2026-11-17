/// Erreur métier levée par la couche `services/`.
///
/// Les erreurs techniques ([ErreurSource], [ErreurBaseDeDonnees]) sont
/// laissées telles quelles ; cette classe sert aux refus métier, par exemple
/// une URL de titre qui ne correspond à aucun site configuré.
library;

/// Refus ou impossibilité métier, avec un message lisible par le client.
class ErreurService implements Exception {
  /// Crée une erreur avec un [message] en français destiné à l'interface.
  const ErreurService(
    this.message, {
    this.cause,
    this.ajoutLienSeulPossible = false,
  });

  /// Explication affichable telle quelle.
  final String message;

  /// Erreur d'origine éventuelle.
  final Object? cause;

  /// `true` si le refus vient de ce que l'application ne sait pas lire le
  /// site (site non configuré, réglages illisibles) : l'interface peut alors
  /// proposer « Ajouter quand même comme simple lien » (tâche T4). Voir
  /// `ServiceBibliotheque.peutAjouterCommeLienSeul`.
  final bool ajoutLienSeulPossible;

  @override
  String toString() => cause == null
      ? 'ErreurService : $message'
      : 'ErreurService : $message ($cause)';
}
