/// Icône colorée de l'état hors-ligne d'un chapitre (téléchargé, en file,
/// en cours, échec, non téléchargé) et légende de ces icônes.
library;

import 'package:material_ui/material_ui.dart';

import '../etat/outils_chapitres.dart';
import 'constantes_interface.dart';
import 'textes.dart';

/// Icône d'un statut hors-ligne.
IconData iconeHorsLigne(StatutHorsLigne statut) {
  switch (statut) {
    case StatutHorsLigne.telecharge:
      return Icons.download_done;
    case StatutHorsLigne.enFile:
      return Icons.schedule;
    case StatutHorsLigne.enCours:
      return Icons.downloading;
    case StatutHorsLigne.echec:
      return Icons.error_outline;
    case StatutHorsLigne.nonTelecharge:
      return Icons.cloud_outlined;
  }
}

/// Couleur d'un statut hors-ligne, prise dans le thème (lisible en clair
/// comme en sombre).
Color couleurHorsLigne(StatutHorsLigne statut, ColorScheme couleurs) {
  switch (statut) {
    case StatutHorsLigne.telecharge:
      return couleurs.primary;
    case StatutHorsLigne.enFile:
      return couleurs.tertiary;
    case StatutHorsLigne.enCours:
      return couleurs.tertiary;
    case StatutHorsLigne.echec:
      return couleurs.error;
    case StatutHorsLigne.nonTelecharge:
      return couleurs.outline;
  }
}

/// Icône d'une archive dont la suppression automatique est prévue.
const IconData iconeSuppressionPrevue = Icons.auto_delete_outlined;

/// Icône d'une archive en double.
const IconData iconeDoublon = Icons.content_copy;

/// Couleur des suppressions prévues (rouge du thème, décision du client).
Color couleurSuppressionPrevue(ColorScheme couleurs) => couleurs.error;

/// Couleur des doublons (orange, décision du client). Le schéma Material 3
/// n'a pas d'orange : on choisit une nuance lisible sur fond clair ou
/// sombre.
Color couleurDoublon(ColorScheme couleurs) =>
    couleurs.brightness == Brightness.dark
    ? Colors.orange.shade300
    : Colors.orange.shade800;

/// Couleur d'un état complet : rouge pour une suppression prévue, orange
/// pour un doublon, sinon celle du statut.
Color couleurEtatHorsLigne(EtatHorsLigne etat, ColorScheme couleurs) {
  if (etat.aSuppressionPrevue) return couleurSuppressionPrevue(couleurs);
  if (etat.statut == StatutHorsLigne.telecharge && etat.estDoublon) {
    return couleurDoublon(couleurs);
  }
  return couleurHorsLigne(etat.statut, couleurs);
}

/// Icône d'un état complet (suppression prévue et doublon d'abord).
IconData iconeEtatHorsLigne(EtatHorsLigne etat) {
  if (etat.aSuppressionPrevue) return iconeSuppressionPrevue;
  if (etat.statut == StatutHorsLigne.telecharge && etat.estDoublon) {
    return iconeDoublon;
  }
  return iconeHorsLigne(etat.statut);
}

/// Indicateur de l'état hors-ligne d'un chapitre : icône colorée, ou cercle
/// de progression avec le pourcentage pendant le téléchargement.
class IndicateurHorsLigne extends StatelessWidget {
  /// Crée l'indicateur pour [etat].
  const IndicateurHorsLigne({super.key, required this.etat});

  /// État affiché.
  final EtatHorsLigne etat;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final couleur = couleurEtatHorsLigne(etat, couleurs);
    if (etat.statut == StatutHorsLigne.enCours) {
      // Cercle à la taille d'une icône : la ligne ne change pas de hauteur
      // quand le téléchargement commence ; le pourcentage est écrit dessous
      // en petit.
      final taille = IconTheme.of(context).size ?? espacementGrand;
      return Semantics(
        label: Textes.infoBulleHorsLigne(etat),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox.square(
              dimension: taille * 0.8,
              child: CircularProgressIndicator(
                value: etat.progression,
                strokeWidth: epaisseurIndicateurBouton,
                color: couleur,
              ),
            ),
            Text(
              Textes.pourcentage(etat.progression),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: couleur),
            ),
          ],
        ),
      );
    }
    return Icon(
      iconeEtatHorsLigne(etat),
      color: couleur,
      semanticLabel: etat.aSuppressionPrevue
          ? Textes.legendeSuppressionPrevue
          : (etat.estDoublon && etat.statut == StatutHorsLigne.telecharge
                ? Textes.legendeDoublon
                : Textes.libelleStatutHorsLigne(etat.statut)),
    );
  }
}

/// Légende des icônes hors-ligne, en petites étiquettes qui passent à la
/// ligne selon la largeur.
class LegendeHorsLigne extends StatelessWidget {
  /// Crée la légende.
  const LegendeHorsLigne({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget entree(IconData icone, Color couleur, String libelle) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icone, size: theme.textTheme.bodyMedium?.fontSize, color: couleur),
        const SizedBox(width: espacementPetit / 2),
        Text(libelle, style: theme.textTheme.bodySmall),
      ],
    );
    return Wrap(
      spacing: espacementMoyen,
      runSpacing: espacementPetit / 2,
      children: <Widget>[
        for (final statut in StatutHorsLigne.values)
          entree(
            iconeHorsLigne(statut),
            couleurHorsLigne(statut, theme.colorScheme),
            Textes.libelleStatutHorsLigne(statut),
          ),
        // Décisions du client : rouge = supprimé dans 24 h, orange = doublon.
        entree(
          iconeSuppressionPrevue,
          couleurSuppressionPrevue(theme.colorScheme),
          Textes.legendeSuppressionPrevue,
        ),
        entree(
          iconeDoublon,
          couleurDoublon(theme.colorScheme),
          Textes.legendeDoublon,
        ),
      ],
    );
  }
}
