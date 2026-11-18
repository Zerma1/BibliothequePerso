/// Section repliable réutilisable : en-tête (icône, titre, résumé) et contenu
/// affiché à la demande.
library;

import 'package:material_ui/material_ui.dart';

import 'constantes_interface.dart';

/// Carte repliable : un en-tête toujours visible (icône, [titre] et
/// [resume] facultatif), et [enfants] affichés quand le client la déplie.
///
/// L'état plié ou déplié est mémorisé pendant la session grâce à
/// [identifiant] (`PageStorageKey`) : quitter l'écran ou faire défiler la
/// liste ne le perd pas. Au premier affichage, la section est dépliée si
/// [estDeplieeAuDepart] vaut `true`.
class SectionPliable extends StatelessWidget {
  /// Crée la section.
  const SectionPliable({
    super.key,
    required this.identifiant,
    required this.titre,
    required this.enfants,
    this.icone,
    this.resume,
    this.estDeplieeAuDepart = false,
  });

  /// Identifiant unique dans l'écran (mémorisation du pliage).
  final String identifiant;

  /// Titre de l'en-tête.
  final String titre;

  /// Résumé affiché sous le titre (utile section repliée), ou `null`.
  final String? resume;

  /// Icône de l'en-tête, ou `null`.
  final IconData? icone;

  /// `true` si la section est dépliée au premier affichage.
  final bool estDeplieeAuDepart;

  /// Contenu de la section.
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resume = this.resume;
    // Carte à bord fin plutôt qu'une simple ligne : chaque thème forme un
    // bloc distinct, repérable d'un coup d'œil quand tout est replié.
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: espacementMoyen),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>(identifiant),
        initiallyExpanded: estDeplieeAuDepart,
        // La carte dessine déjà le cadre : pas de trait supplémentaire
        // quand la section est dépliée.
        shape: const Border(),
        collapsedShape: const Border(),
        leading: icone == null ? null : Icon(icone),
        title: Text(titre, style: theme.textTheme.titleMedium),
        subtitle: resume == null
            ? null
            : Text(resume, maxLines: 2, overflow: TextOverflow.ellipsis),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        childrenPadding: const EdgeInsets.fromLTRB(
          espacementMoyen,
          0,
          espacementMoyen,
          espacementMoyen,
        ),
        // Chaque enfant reçoit sa propre clé de mémorisation : sans elle, une
        // zone qui défile dans la section (VueErreur, liste) partagerait
        // l'identifiant de l'ExpansionTile et relirait son booléen « déplié »
        // comme une position de défilement (plantage « bool is not a
        // subtype of double? »).
        children: <Widget>[
          for (final (index, enfant) in enfants.indexed)
            KeyedSubtree(
              key: PageStorageKey<String>('$identifiant.$index'),
              child: enfant,
            ),
        ],
      ),
    );
  }
}
