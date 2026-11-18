/// Modèle `GroupeCategories` : une catégorie de référence et les catégories
/// de même sens qui lui sont rattachées.
library;

import 'categorie.dart';
import 'outils_modeles.dart';

/// Groupe de catégories de même sens : « survie » (référence) et
/// « survival », « supervivencia » (rattachées).
///
/// Lu par `DepotEquivalencesCategories.chargerGroupes` : ce n'est pas une
/// ligne de table, d'où l'absence de `versMap` / `depuisMap`.
class GroupeCategories {
  /// Crée un groupe. La liste [rattachees] est copiée dans une liste non
  /// modifiable pour garantir l'immuabilité de l'objet.
  GroupeCategories({
    required this.reference,
    List<Categorie> rattachees = const <Categorie>[],
  }) : rattachees = List<Categorie>.unmodifiable(rattachees);

  /// Catégorie de référence (celle qui représente le groupe dans les
  /// filtres).
  final Categorie reference;

  /// Catégories rattachées à [reference], triées par nom (sans la
  /// référence elle-même).
  final List<Categorie> rattachees;

  /// Toutes les catégories du groupe : la référence puis les rattachées.
  List<Categorie> get toutes => <Categorie>[reference, ...rattachees];

  /// Renvoie une copie avec les champs donnés remplacés.
  GroupeCategories copierAvec({
    Categorie? reference,
    List<Categorie>? rattachees,
  }) {
    return GroupeCategories(
      reference: reference ?? this.reference,
      rattachees: rattachees ?? this.rattachees,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GroupeCategories &&
            other.reference == reference &&
            listesEgales(other.rattachees, rattachees);
  }

  @override
  int get hashCode => Object.hash(reference, Object.hashAll(rattachees));

  @override
  String toString() =>
      'GroupeCategories(reference: ${reference.nom}, '
      'rattachees: ${rattachees.map((c) => c.nom).join(', ')})';
}
