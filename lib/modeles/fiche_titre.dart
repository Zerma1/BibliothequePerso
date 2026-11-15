/// Modèle `FicheTitre` : métadonnées complètes d'un titre telles que lues sur
/// un site (PLAYBOOK.md section 6, `SourceSite.recupererFiche`).
library;

import 'outils_modeles.dart';
import 'titre.dart';

/// Fiche d'un titre renvoyée par un adaptateur de site : le [titre] et les
/// noms de ses [categories].
///
/// Les catégories sont des noms bruts (« Action », « Gore »…) tels
/// qu'affichés par le site : la normalisation (`Categorie.normaliserNom`) et
/// l'enregistrement en base sont faits par le service, pas par l'adaptateur.
class FicheTitre {
  /// Crée une fiche. La liste [categories] est copiée dans une liste non
  /// modifiable pour garantir l'immuabilité de l'objet.
  FicheTitre({required this.titre, List<String> categories = const <String>[]})
    : categories = List<String>.unmodifiable(categories);

  /// Titre lu sur le site (`id` et `idSource` à `null` : le service les
  /// complète).
  final Titre titre;

  /// Noms des catégories (genres, tags) dans l'ordre du site, non normalisés.
  final List<String> categories;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FicheTitre &&
            other.titre == titre &&
            listesEgales(other.categories, categories);
  }

  @override
  int get hashCode => Object.hash(titre, Object.hashAll(categories));

  @override
  String toString() =>
      'FicheTitre(titre: ${titre.nom}, categories: ${categories.join(', ')})';
}
