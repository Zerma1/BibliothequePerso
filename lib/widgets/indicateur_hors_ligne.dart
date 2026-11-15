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
    final couleur = couleurHorsLigne(etat.statut, couleurs);
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
      iconeHorsLigne(etat.statut),
      color: couleur,
      semanticLabel: Textes.libelleStatutHorsLigne(etat.statut),
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
    return Wrap(
      spacing: espacementMoyen,
      runSpacing: espacementPetit / 2,
      children: <Widget>[
        for (final statut in StatutHorsLigne.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                iconeHorsLigne(statut),
                size: theme.textTheme.bodyMedium?.fontSize,
                color: couleurHorsLigne(statut, theme.colorScheme),
              ),
              const SizedBox(width: espacementPetit / 2),
              Text(
                Textes.libelleStatutHorsLigne(statut),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }
}
