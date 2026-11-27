/// Jauge à crans des Paramètres : libellé, valeur lisible, curseur et
/// boutons − / + pour l'ajustement fin.
library;

import 'package:material_ui/material_ui.dart';

import 'constantes_interface.dart';
import 'textes.dart';

/// Réglage numérique présenté en jauge (préférence du client : un geste
/// plutôt qu'une saisie).
///
/// Le curseur se déplace de cran en cran dans [crans] (valeurs croissantes,
/// pas forcément régulières) ; pendant le glissement, [surApercu] reçoit la
/// valeur visée et rien n'est enregistré ; au lâcher, [surChoix] la reçoit.
/// Les boutons − / + appellent directement [surChoix] avec la valeur
/// voisine : de 1 en 1 ([pasBoutons]), ou de cran en cran si [pasBoutons]
/// est `null` (durées). Une [valeur] hors des crans (réglée de 1 en 1) place
/// le curseur sur le cran le plus proche, sans changer la valeur.
///
/// Sans logique métier : les bornes viennent de l'état, l'enregistrement
/// aussi.
class JaugeReglage extends StatelessWidget {
  /// Crée la jauge.
  const JaugeReglage({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.crans,
    required this.formater,
    required this.surApercu,
    required this.surChoix,
    this.pasBoutons = 1,
    this.explication,
    this.estActive = true,
  });

  /// Nom du réglage, à gauche de la valeur.
  final String libelle;

  /// Valeur affichée.
  final int valeur;

  /// Valeurs atteignables par le curseur, croissantes ; la première et la
  /// dernière sont les bornes du réglage.
  final List<int> crans;

  /// Valeur lisible (« 6 h », « 12 », « 2 jours »).
  final String Function(int valeur) formater;

  /// Valeur visée pendant le glissement (aucun enregistrement).
  final ValueChanged<int> surApercu;

  /// Valeur choisie (lâcher du curseur ou appui sur − / +).
  final ValueChanged<int> surChoix;

  /// Pas des boutons − / + ; `null` : cran précédent ou suivant.
  final int? pasBoutons;

  /// Phrase courte sous la jauge, ou `null`.
  final String? explication;

  /// `false` pendant un enregistrement : jauge et boutons inactifs.
  final bool estActive;

  /// Index du cran le plus proche de [valeur] (le plus bas en cas
  /// d'égalité).
  int get _indexCran {
    var meilleur = 0;
    for (var index = 1; index < crans.length; index++) {
      if ((crans[index] - valeur).abs() < (crans[meilleur] - valeur).abs()) {
        meilleur = index;
      }
    }
    return meilleur;
  }

  int? _voisine(int sens) {
    final minimum = crans.first;
    final maximum = crans.last;
    final pas = pasBoutons;
    if (pas != null) {
      final cible = valeur + sens * pas;
      if (cible < minimum || cible > maximum) return null;
      return cible;
    }
    // De cran en cran : premier cran strictement au-delà de la valeur, dans
    // le sens demandé (une valeur hors des crans rejoint le cran voisin).
    if (sens > 0) {
      for (final cran in crans) {
        if (cran > valeur) return cran;
      }
    } else {
      for (final cran in crans.reversed) {
        if (cran < valeur) return cran;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moins = _voisine(-1);
    final plus = _voisine(1);
    // Une seule valeur possible (par exemple « En attente » quand les
    // recherches ont lieu toutes les heures) : pas de curseur, il ne
    // pourrait pas bouger.
    final avecCurseur = crans.length > 1;
    final index = _indexCran;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Libellé à gauche (passe à la ligne si besoin), valeur bien visible
        // à droite : le client lit le réglage sans viser le curseur.
        Row(
          children: <Widget>[
            Expanded(child: Text(libelle, style: theme.textTheme.titleSmall)),
            const SizedBox(width: espacementPetit),
            Text(formater(valeur), style: theme.textTheme.titleMedium),
          ],
        ),
        Row(
          children: <Widget>[
            IconButton(
              tooltip: Textes.diminuer,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: estActive && moins != null
                  ? () => surChoix(moins)
                  : null,
            ),
            // Le curseur prend toute la largeur restante : plus il est long,
            // plus les crans sont faciles à viser.
            Expanded(
              child: avecCurseur
                  ? Slider(
                      value: index.toDouble(),
                      max: (crans.length - 1).toDouble(),
                      divisions: crans.length - 1,
                      label: formater(crans[index]),
                      semanticFormatterCallback: (position) =>
                          formater(crans[position.round()]),
                      onChanged: estActive
                          ? (position) => surApercu(crans[position.round()])
                          : null,
                      onChangeEnd: estActive
                          ? (position) => surChoix(crans[position.round()])
                          : null,
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(
              tooltip: Textes.augmenter,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: estActive && plus != null
                  ? () => surChoix(plus)
                  : null,
            ),
          ],
        ),
        if (explication != null)
          Text(explication!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Crans de 1 en 1 de [minimum] à [maximum] (jauges courtes : recherches par
/// jour, heures « En attente », téléchargements simultanés).
List<int> cransReguliers(int minimum, int maximum) => <int>[
  for (var valeur = minimum; valeur <= maximum; valeur++) valeur,
];

/// Crans d'une limite de téléchargement entre [minimum] et [maximum] :
/// ceux de [cransLimitesTelechargement] compris entre les deux, bornes
/// incluses.
List<int> cransLimite(int minimum, int maximum) => <int>{
  minimum,
  for (final cran in cransLimitesTelechargement)
    if (cran > minimum && cran < maximum) cran,
  maximum,
}.toList();
