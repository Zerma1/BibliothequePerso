/// Lecture typée et vérifiée de réponses JSON (`dart:convert`).
///
/// Ces fonctions évitent tout `dynamic` implicite (PLAYBOOK.md section 9) :
/// chaque valeur est vérifiée avant usage, et une structure inattendue lève
/// une [ErreurSource] qui cite l'URL et le chemin JSON fautif.
library;

import 'dart:convert';

import 'erreur_source.dart';

/// Décode [texte] en objet JSON (`Map`) ou lève une [ErreurSource] pour [url].
Map<String, Object?> decoderObjetJson(String texte, String url) {
  final Object? valeur;
  try {
    valeur = jsonDecode(texte);
  } on FormatException catch (erreur) {
    throw ErreurSource(url, 'JSON invalide', cause: erreur);
  }
  if (valeur is Map<String, Object?>) {
    return valeur;
  }
  throw ErreurSource(url, 'JSON inattendu : un objet était attendu');
}

/// Accès vérifiés aux champs d'un objet JSON.
///
/// [url] sert uniquement à construire une [ErreurSource] lisible.
extension LectureJson on Map<String, Object?> {
  /// Lit un objet obligatoire.
  Map<String, Object?> lireObjet(String cle, String url) {
    final valeur = this[cle];
    if (valeur is Map<String, Object?>) {
      return valeur;
    }
    throw _erreur(cle, 'un objet', valeur, url);
  }

  /// Lit un objet qui peut être absent ou `null`.
  Map<String, Object?>? lireObjetOptionnel(String cle, String url) {
    final valeur = this[cle];
    if (valeur == null) {
      return null;
    }
    if (valeur is Map<String, Object?>) {
      return valeur;
    }
    throw _erreur(cle, 'un objet ou null', valeur, url);
  }

  /// Lit une liste d'objets obligatoire.
  List<Map<String, Object?>> lireListeObjets(String cle, String url) {
    final valeur = this[cle];
    if (valeur is List<Object?>) {
      final resultat = <Map<String, Object?>>[];
      for (final element in valeur) {
        if (element is! Map<String, Object?>) {
          throw _erreur(cle, 'une liste d\'objets', valeur, url);
        }
        resultat.add(element);
      }
      return resultat;
    }
    throw _erreur(cle, 'une liste', valeur, url);
  }

  /// Lit une liste de textes obligatoire.
  List<String> lireListeTextes(String cle, String url) {
    final valeur = this[cle];
    if (valeur is List<Object?>) {
      final resultat = <String>[];
      for (final element in valeur) {
        if (element is! String) {
          throw _erreur(cle, 'une liste de textes', valeur, url);
        }
        resultat.add(element);
      }
      return resultat;
    }
    throw _erreur(cle, 'une liste', valeur, url);
  }

  /// Lit un texte obligatoire.
  String lireTexte(String cle, String url) {
    final valeur = this[cle];
    if (valeur is String) {
      return valeur;
    }
    throw _erreur(cle, 'un texte', valeur, url);
  }

  /// Lit un texte qui peut être absent ou `null`.
  String? lireTexteOptionnel(String cle, String url) {
    final valeur = this[cle];
    if (valeur == null || valeur is String) {
      return valeur as String?;
    }
    throw _erreur(cle, 'un texte ou null', valeur, url);
  }

  /// Lit un entier obligatoire.
  int lireEntier(String cle, String url) {
    final valeur = this[cle];
    if (valeur is int) {
      return valeur;
    }
    throw _erreur(cle, 'un entier', valeur, url);
  }

  /// Lit un dictionnaire « langue → texte » (`LocalizedString` de MangaDex).
  ///
  /// Les valeurs qui ne sont pas des textes sont ignorées. L'API renvoie
  /// parfois une liste vide `[]` à la place d'un objet vide : on la traite
  /// comme un dictionnaire vide.
  Map<String, String> lireTextesLocalises(String cle, String url) {
    final valeur = this[cle];
    if (valeur == null || (valeur is List<Object?> && valeur.isEmpty)) {
      return const <String, String>{};
    }
    if (valeur is Map<String, Object?>) {
      return <String, String>{
        for (final entree in valeur.entries)
          if (entree.value is String) entree.key: entree.value! as String,
      };
    }
    throw _erreur(cle, 'un objet « langue → texte »', valeur, url);
  }

  ErreurSource _erreur(String cle, String attendu, Object? recu, String url) {
    final description = recu == null ? 'null ou absent' : '${recu.runtimeType}';
    return ErreurSource(
      url,
      'Structure JSON inattendue : « $cle » doit être $attendu, '
      'reçu $description',
    );
  }
}
