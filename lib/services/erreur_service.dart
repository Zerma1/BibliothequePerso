/// Erreur métier levée par la couche `services/`.
///
/// Les erreurs techniques ([ErreurSource], [ErreurBaseDeDonnees]) sont
/// laissées telles quelles ; cette classe sert aux refus métier, par exemple
/// une URL de titre qui ne correspond à aucun site configuré.
library;

/// Refus ou impossibilité métier, avec un message lisible par le client.
class ErreurService implements Exception {
  /// Crée une erreur avec un [message] en français destiné à l'interface.
  const ErreurService(this.message, {this.cause});

  /// Explication affichable telle quelle.
  final String message;

  /// Erreur d'origine éventuelle.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'ErreurService : $message'
      : 'ErreurService : $message ($cause)';
}
