/// Modèle `EquivalenceCategorie` : rattachement d'une catégorie à sa
/// catégorie de référence (table `categories_equivalences`, migration 9).
library;

import 'outils_modeles.dart';

/// Une catégorie ([idCategorie]) considérée comme de même sens que sa
/// catégorie de référence ([idReference]) : « survival » → « survie ».
///
/// Un seul niveau : une référence n'est jamais elle-même rattachée (voir
/// `DepotEquivalencesCategories`).
class EquivalenceCategorie {
  /// Crée un rattachement.
  const EquivalenceCategorie({
    required this.idCategorie,
    required this.idReference,
  });

  static const String _entite = 'EquivalenceCategorie';

  /// Catégorie rattachée (unique dans la table : au plus une référence).
  final int idCategorie;

  /// Catégorie de référence du groupe.
  final int idReference;

  /// Convertit le rattachement en ligne de la table
  /// `categories_equivalences`.
  Map<String, Object?> versMap() {
    return <String, Object?>{
      'id_categorie': idCategorie,
      'id_reference': idReference,
    };
  }

  /// Construit un rattachement depuis une ligne SQLite.
  ///
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  factory EquivalenceCategorie.depuisMap(Map<String, Object?> map) {
    return EquivalenceCategorie(
      idCategorie: map.lireEntier('id_categorie', _entite),
      idReference: map.lireEntier('id_reference', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  EquivalenceCategorie copierAvec({int? idCategorie, int? idReference}) {
    return EquivalenceCategorie(
      idCategorie: idCategorie ?? this.idCategorie,
      idReference: idReference ?? this.idReference,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EquivalenceCategorie &&
            other.idCategorie == idCategorie &&
            other.idReference == idReference;
  }

  @override
  int get hashCode => Object.hash(idCategorie, idReference);

  @override
  String toString() =>
      'EquivalenceCategorie(idCategorie: $idCategorie, '
      'idReference: $idReference)';
}
