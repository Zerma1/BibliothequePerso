/// Erreur levée par la couche de persistance (modèles et dépôts).
///
/// Elle est définie dans `modeles/` plutôt que dans `donnees/` pour que les
/// méthodes `depuisMap()` puissent la lever sans dépendre de SQLite.
library;

/// Erreur de lecture ou d'écriture de la base de données locale.
///
/// Exemples : une ligne SQLite dont une colonne a un type inattendu, une
/// tentative de suppression d'une liste système, une URL de source en double.
class ErreurBaseDeDonnees implements Exception {
  /// Crée une erreur avec un [message] lisible et, si elle existe, sa [cause].
  const ErreurBaseDeDonnees(this.message, {this.cause});

  /// Description claire du problème, en français.
  final String message;

  /// Erreur d'origine (par exemple une `DatabaseException`), si elle existe.
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'ErreurBaseDeDonnees : $message';
    }
    return 'ErreurBaseDeDonnees : $message (cause : $cause)';
  }
}
