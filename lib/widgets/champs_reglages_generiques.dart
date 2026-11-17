/// Champs repliables des réglages avancés d'un site générique (sélecteurs
/// CSS), communs à l'ajout et à la modification d'un site.
library;

import 'package:material_ui/material_ui.dart';

import '../etat/etat_sources.dart';
import 'constantes_interface.dart';
import 'textes.dart';

/// Section repliable « Réglages avancés (sélecteurs CSS) » : une explication
/// puis un champ par réglage (`EtatSources.clesReglagesGeneriques`).
///
/// Les contrôleurs [controleurs] (un par clé) appartiennent à l'écran
/// parent, qui lit leurs valeurs à l'envoi. Chaque champ est vérifié par le
/// service (`EtatSources.erreurReglageGenerique`) lors de la validation du
/// `Form` englobant ; le message s'affiche sous le champ concerné.
class ChampsReglagesGeneriques extends StatelessWidget {
  /// Crée la section.
  const ChampsReglagesGeneriques({
    super.key,
    required this.controleurs,
    this.estActive = true,
    this.estDeplieeAuDepart = false,
  });

  /// Contrôleur de chaque réglage, par clé.
  final Map<String, TextEditingController> controleurs;

  /// `false` pendant un envoi : champs grisés.
  final bool estActive;

  /// `true` si la section est dépliée au premier affichage (site qui a déjà
  /// des réglages).
  final bool estDeplieeAuDepart;

  @override
  Widget build(BuildContext context) {
    // ExpansionTile simple plutôt que SectionPliable (carte) : la section
    // vit à l'intérieur d'un formulaire, sous les autres champs, sans cadre
    // supplémentaire.
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.tune),
      initiallyExpanded: estDeplieeAuDepart,
      // Champs gardés même repliés : leur validation s'applique toujours à
      // l'envoi.
      maintainState: true,
      title: const Text(Textes.reglagesAvancesSelecteurs),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      childrenPadding: const EdgeInsets.only(bottom: espacementPetit),
      children: <Widget>[
        const Text(Textes.explicationReglagesSelecteurs),
        for (final cle in EtatSources.clesReglagesGeneriques)
          Padding(
            padding: const EdgeInsets.only(top: espacementPetit),
            child: TextFormField(
              key: ValueKey<String>('reglage_$cle'),
              controller: controleurs[cle],
              enabled: estActive,
              decoration: InputDecoration(
                labelText: EtatSources.libelleReglageGenerique(cle),
                helperText: cle,
                // Message du service parfois long (motif cité) : plusieurs
                // lignes plutôt qu'un texte tronqué.
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              validator: (valeur) =>
                  EtatSources.erreurReglageGenerique(cle, valeur ?? ''),
            ),
          ),
      ],
    );
  }
}
