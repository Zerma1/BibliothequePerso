/// Modèle `Categorie` : un genre ou un tag repris des sites.
library;

import 'outils_modeles.dart';

/// Une catégorie (genre) partagée entre les sources.
///
/// Le nom est normalisé (minuscules, sans espaces autour) pour que deux sites
/// qui affichent « Action » et « action  » partagent la même catégorie.
class Categorie {
  /// Crée une catégorie. Le [nom] doit déjà être normalisé : utiliser
  /// [normaliserNom] sur un nom venant d'un site.
  const Categorie({this.id, required this.nom});

  static const String _entite = 'Categorie';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Nom normalisé (unique en base).
  final String nom;

  /// Normalise un nom de catégorie : espaces retirés autour, minuscules.
  ///
  /// LIMITE : `toLowerCase()` de Dart ne dépend pas de la langue (pas de règle
  /// turque, par exemple), ce qui convient aux genres affichés par les sites.
  static String normaliserNom(String nomBrut) => nomBrut.trim().toLowerCase();

  /// Convertit la catégorie en ligne de la table `categories`.
  Map<String, Object?> versMap() {
    return <String, Object?>{if (id != null) 'id': id, 'nom': nom};
  }

  /// Construit une catégorie depuis une ligne SQLite.
  ///
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  factory Categorie.depuisMap(Map<String, Object?> map) {
    return Categorie(
      id: map.lireEntierOptionnel('id', _entite),
      nom: map.lireTexte('nom', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  Categorie copierAvec({int? id, String? nom}) {
    return Categorie(id: id ?? this.id, nom: nom ?? this.nom);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Categorie && other.id == id && other.nom == nom;
  }

  @override
  int get hashCode => Object.hash(id, nom);

  @override
  String toString() => 'Categorie(id: $id, nom: $nom)';
}
