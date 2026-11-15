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
  const ErreurSource(this.url, this.message, {this.cause, this.codeStatut});

  /// URL dont la lecture a échoué (ou URL saisie invalide).
  final String url;

  /// Description claire du problème, en français.
  final String message;

  /// Erreur d'origine (exception réseau, `FormatException`…), si elle existe.
  final Object? cause;

  /// Code de statut HTTP reçu, si l'échec vient d'une réponse HTTP.
  final int? codeStatut;

  @override
  String toString() {
    final statut = codeStatut == null ? '' : ' [HTTP $codeStatut]';
    final suite = cause == null ? '' : ' (cause : $cause)';
    return 'ErreurSource$statut : $message — $url$suite';
  }
}
