/// Erreur levée par `StockageTelechargements` (fichiers hors-ligne).
library;

/// Erreur de lecture ou d'écriture d'une archive de chapitre sur le disque.
///
/// Exemples : archive absente ou abîmée, page introuvable, disque plein,
/// chapitre déjà en cours d'écriture.
class ErreurStockage implements Exception {
  /// Crée une erreur avec un [message] lisible, le [chemin] concerné et, si
  /// elle existe, sa [cause].
  const ErreurStockage(this.message, {this.chemin, this.cause});

  /// Description claire du problème, en français.
  final String message;

  /// Chemin du fichier concerné, s'il est connu.
  final String? chemin;

  /// Erreur d'origine (`FileSystemException`, `ArchiveException`…), si elle
  /// existe.
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('ErreurStockage : $message');
    if (chemin != null) {
      buffer.write(' [$chemin]');
    }
    if (cause != null) {
      buffer.write(' (cause : $cause)');
    }
    return buffer.toString();
  }
}
