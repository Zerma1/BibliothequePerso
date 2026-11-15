/// Puce d'une catégorie (genre ou tag repris des sites).
library;

import 'package:material_ui/material_ui.dart';

/// Puce affichant le nom d'une catégorie.
///
/// Sans [surSelection], c'est une simple étiquette (fiche d'un titre) ; avec
/// [surSelection], c'est une puce de filtre cochable (bibliothèque).
class PastilleCategorie extends StatelessWidget {
  /// Crée la puce pour le [nom] (normalisé) d'une catégorie.
  const PastilleCategorie({
    super.key,
    required this.nom,
    this.estChoisie = false,
    this.surSelection,
  });

  /// Nom de la catégorie, tel qu'enregistré (minuscules).
  final String nom;

  /// `true` si la puce de filtre est cochée.
  final bool estChoisie;

  /// Action quand le client coche ou décoche la puce.
  final ValueChanged<bool>? surSelection;

  /// Nom avec une majuscule initiale : les catégories sont enregistrées en
  /// minuscules pour être partagées entre sites, mais se lisent mieux ainsi.
  static String afficher(String nom) {
    if (nom.isEmpty) {
      return nom;
    }
    return '${nom[0].toUpperCase()}${nom.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final libelle = Text(afficher(nom));
    final action = surSelection;
    if (action == null) {
      return Chip(label: libelle, visualDensity: VisualDensity.compact);
    }
    return FilterChip(label: libelle, selected: estChoisie, onSelected: action);
  }
}
