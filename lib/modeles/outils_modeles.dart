/// Outils communs aux modèles : lecture contrôlée des `Map` SQLite et
/// comparaison de listes.
///
/// Ces fonctions évitent tout `dynamic` implicite (PLAYBOOK.md section 9) :
/// chaque valeur est vérifiée avant d'être convertie, et une donnée invalide
/// lève une [ErreurBaseDeDonnees] qui indique l'entité et la colonne fautives.
library;

import 'constantes.dart';
import 'erreur_base_de_donnees.dart';

/// Lecture typée et vérifiée des colonnes d'une ligne SQLite.
///
/// Le paramètre `entite` (par exemple `'Titre'`) sert uniquement à rendre le
/// message d'erreur lisible.
extension LectureMap on Map<String, Object?> {
  /// Lit un entier obligatoire.
  int lireEntier(String cle, String entite) {
    final valeur = this[cle];
    if (valeur is int) {
      return valeur;
    }
    throw _erreurType(cle, entite, 'un entier', valeur);
  }

  /// Lit un entier qui peut être absent ou `NULL`.
  int? lireEntierOptionnel(String cle, String entite) {
    final valeur = this[cle];
    if (valeur == null || valeur is int) {
      return valeur as int?;
    }
    throw _erreurType(cle, entite, 'un entier ou NULL', valeur);
  }

  /// Lit un texte obligatoire.
  String lireTexte(String cle, String entite) {
    final valeur = this[cle];
    if (valeur is String) {
      return valeur;
    }
    throw _erreurType(cle, entite, 'un texte', valeur);
  }

  /// Lit un texte qui peut être absent ou `NULL`.
  String? lireTexteOptionnel(String cle, String entite) {
    final valeur = this[cle];
    if (valeur == null || valeur is String) {
      return valeur as String?;
    }
    throw _erreurType(cle, entite, 'un texte ou NULL', valeur);
  }

  /// Lit un nombre réel obligatoire.
  ///
  /// SQLite peut renvoyer un `int` pour une colonne `REAL` dont la valeur est
  /// entière : on accepte donc tout `num`.
  double lireDouble(String cle, String entite) {
    final valeur = this[cle];
    if (valeur is num) {
      return valeur.toDouble();
    }
    throw _erreurType(cle, entite, 'un nombre', valeur);
  }

  /// Lit un booléen stocké en `INTEGER` 0 ou 1 (SQLite n'a pas de type booléen).
  ///
  /// Un `bool` Dart est aussi accepté, pour les `Map` construites à la main.
  bool lireBooleen(String cle, String entite) {
    final valeur = this[cle];
    if (valeur is bool) {
      return valeur;
    }
    if (valeur == valeurSqlVrai) {
      return true;
    }
    if (valeur == valeurSqlFaux) {
      return false;
    }
    throw _erreurType(cle, entite, '0 ou 1', valeur);
  }

  /// Lit une date stockée en millisecondes depuis l'époque Unix (UTC).
  ///
  /// La date renvoyée est toujours en UTC.
  DateTime? lireDateOptionnelle(String cle, String entite) {
    final millisecondes = lireEntierOptionnel(cle, entite);
    if (millisecondes == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millisecondes, isUtc: true);
  }

  /// Lit une valeur d'énumération stockée sous son nom (`Enum.name`).
  T lireEnum<T extends Enum>(String cle, String entite, List<T> valeurs) {
    final nom = lireTexte(cle, entite);
    for (final valeur in valeurs) {
      if (valeur.name == nom) {
        return valeur;
      }
    }
    throw ErreurBaseDeDonnees(
      'Donnée invalide pour $entite : la colonne « $cle » contient « $nom », '
      'qui ne fait pas partie des valeurs autorisées '
      '(${valeurs.map((v) => v.name).join(', ')}).',
    );
  }

  ErreurBaseDeDonnees _erreurType(
    String cle,
    String entite,
    String attendu,
    Object? recu,
  ) {
    final description = recu == null
        ? 'NULL ou absente'
        : '${recu.runtimeType} ($recu)';
    return ErreurBaseDeDonnees(
      'Donnée invalide pour $entite : la colonne « $cle » doit être $attendu, '
      'reçu $description.',
    );
  }
}

/// Convertit une date en millisecondes UTC pour SQLite (`NULL` si absente).
///
/// On stocke un entier plutôt qu'un texte ISO 8601 : c'est compact, triable
/// directement et indépendant du fuseau horaire.
int? dateVersMillisecondes(DateTime? date) =>
    date?.toUtc().millisecondsSinceEpoch;

/// Convertit un booléen Dart en entier SQLite (0 ou 1).
int booleenVersEntier(bool valeur) => valeur ? valeurSqlVrai : valeurSqlFaux;

/// Indique si deux listes contiennent les mêmes éléments dans le même ordre.
///
/// Écrit à la main pour que `modeles/` ne dépende que de `dart:core`.
bool listesEgales<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
