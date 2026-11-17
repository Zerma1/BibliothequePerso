/// Bandeaux globaux du dossier des chapitres : dossier inaccessible (NAS
/// éteint, lecteur réseau déconnecté) et redémarrage nécessaire après un
/// changement de dossier.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_dossier_chapitres.dart';
import 'constantes_interface.dart';
import 'textes.dart';

/// Zone qui affiche les bandeaux du dossier des chapitres au-dessus de
/// [child], visibles quel que soit l'onglet choisi.
///
/// Sans [EtatDossierChapitres] (tests), [child] est affiché seul.
class ZoneBandeauxDossierChapitres extends StatelessWidget {
  /// Crée la zone autour de [child].
  const ZoneBandeauxDossierChapitres({super.key, required this.child});

  /// Contenu affiché sous les bandeaux.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatDossierChapitres?>();
    // Présence de l'état fixée au démarrage : ce retour anticipé ne change
    // jamais la structure en cours de route.
    if (etat == null) return child;
    final message = etat.accesDossier.message;
    final inaccessible = !etat.accesDossier.estAccessible;
    final redemarrage = etat.redemarrageNecessaire;
    final visible = inaccessible || redemarrage;
    // Structure identique avec ou sans bandeau (Column > Expanded >
    // MediaQuery) : le contenu garde son état (onglets, défilement) quand un
    // bandeau apparaît ou disparaît.
    return Column(
      children: <Widget>[
        if (visible)
          // Les bandeaux prennent la marge du haut (barre d'état du
          // téléphone) ; le contenu dessous ne la compte plus.
          SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (inaccessible)
                  _Bandeau(
                    icone: Icons.folder_off_outlined,
                    texte: message ?? '',
                    estAlerte: true,
                    action: TextButton.icon(
                      onPressed: etat.estEnVerification
                          ? null
                          : etat.verifierAcces,
                      icon: etat.estEnVerification
                          ? SizedBox.square(
                              dimension: IconTheme.of(context).size,
                              child: const CircularProgressIndicator(
                                strokeWidth: epaisseurIndicateurBouton,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text(Textes.reessayer),
                    ),
                  ),
                if (redemarrage)
                  const _Bandeau(
                    icone: Icons.restart_alt,
                    texte: Textes.bandeauRedemarrage,
                    estAlerte: false,
                  ),
              ],
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: visible,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Un bandeau : icône, texte et action facultative, sur toute la largeur.
class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.icone,
    required this.texte,
    required this.estAlerte,
    this.action,
  });

  final IconData icone;
  final String texte;
  final bool estAlerte;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    // Rouge du thème pour un dossier inaccessible (problème à régler), teinte
    // secondaire pour le redémarrage (simple consigne).
    final fond = estAlerte
        ? couleurs.errorContainer
        : couleurs.secondaryContainer;
    final texteCouleur = estAlerte
        ? couleurs.onErrorContainer
        : couleurs.onSecondaryContainer;
    final action = this.action;
    return Material(
      color: fond,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: espacementMoyen,
          vertical: espacementPetit,
        ),
        // Texte sur toute la largeur et action en dessous, à droite : le
        // message peut être long (chemin du NAS) et doit rester lisible sur
        // un téléphone.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icone, color: texteCouleur),
                const SizedBox(width: espacementPetit),
                // Hauteur du texte plafonnée : le message d'un NAS
                // injoignable est long ; sur un téléphone, il défile au lieu
                // de cacher l'onglet, et le bouton reste visible dessous.
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          MediaQuery.sizeOf(context).height *
                          fractionHauteurMaxBandeau,
                    ),
                    child: SingleChildScrollView(
                      child: Text(texte, style: TextStyle(color: texteCouleur)),
                    ),
                  ),
                ),
              ],
            ),
            if (action != null)
              Align(alignment: Alignment.centerRight, child: action),
          ],
        ),
      ),
    );
  }
}
