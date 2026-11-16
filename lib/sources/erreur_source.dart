/// Erreur levée par la couche `sources/` (lecture des sites).
library;

/// Échec de lecture d'un site : réseau, code HTTP, délai dépassé, réponse
/// illisible ou structure inattendue.
///
/// Elle porte toujours l'[url] concernée et, si elle existe, la [cause]
/// d'origine. Le service l'attrape et l'enregistre : elle ne doit jamais faire
/// planter l'interface (PLAYBOOK.md section 6).
class ErreurSource implements Exception {
  /// Crée une erreur pour [url] avec un [message] lisible en français.
  const ErreurSource(
    this.url,
    this.message, {
    this.cause,
    this.codeStatut,
    this.octetsRecus,
    this.duree,
  });

  /// URL dont la lecture a échoué (ou URL saisie invalide).
  final String url;

  /// Description claire du problème, en français.
  final String message;

  /// Erreur d'origine (exception réseau, `FormatException`…), si elle existe.
  final Object? cause;

  /// Code de statut HTTP reçu, si l'échec vient d'une réponse HTTP.
  final int? codeStatut;

  /// Taille du corps reçu lors de la dernière tentative (0 si aucune réponse :
  /// connexion refusée, délai dépassé…), quand l'échec vient du réseau.
  ///
  /// Sert au signalement MangaDex@Home, qui demande la taille reçue même en
  /// cas d'échec (« On a failure that doesn't result in any response [...]
  /// just put 0 for bytes »).
  final int? octetsRecus;

  /// Durée de la dernière tentative (requête complète), quand l'échec vient
  /// du réseau. Sert aussi au signalement MangaDex@Home.
  final Duration? duree;

  @override
  String toString() {
    final statut = codeStatut == null ? '' : ' [HTTP $codeStatut]';
    final suite = cause == null ? '' : ' (cause : $cause)';
    return 'ErreurSource$statut : $message — $url$suite';
  }
}
