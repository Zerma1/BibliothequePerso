/// Bandeaux globaux du dossier des chapitres : dossier inaccessible (NAS
/// éteint, lecteur réseau déconnecté), redémarrage nécessaire après un
/// changement de dossier, et proposition du dossier choisi à l'installation.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_dossier_chapitres.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'section_dossier_chapitres.dart' show ouvrirChangementDossier;
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

  /// « Ignorer » le dossier de l'installateur : confirmation (le choix est
  /// définitif), puis refus enregistré par l'état.
  Future<void> _ignorerInstallation(
    BuildContext context,
    EtatDossierChapitres etat,
  ) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.ignorerDossierInstallation),
        // Largeur bornée : le texte cite un chemin, il reste lisible sur
        // grand écran.
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: SingleChildScrollView(
            child: Text(
              Textes.confirmationIgnorerDossierInstallation(etat.dossierActuel),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.ignorer),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.ignorerDossierInstallation();
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.dossierInstallationIgnore,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatDossierChapitres?>();
    // Présence de l'état fixée au démarrage : ce retour anticipé ne change
    // jamais la structure en cours de route.
    if (etat == null) return child;
    final message = etat.accesDossier.message;
    final inaccessible = !etat.accesDossier.estAccessible;
    final redemarrage = etat.redemarrageNecessaire;
    final installation = etat.dossierInstallationEnAttente;
    final occupe = etat.estEnChangement || etat.estEnRefusInstallation;
    final visible = inaccessible || redemarrage || installation != null;
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
                // Proposition et non alerte : rien n'est cassé, le client
                // choisit quand il veut (teinte secondaire, comme le
                // redémarrage).
                if (installation != null)
                  _Bandeau(
                    icone: Icons.drive_file_move_outlined,
                    texte: Textes.bandeauDossierInstallation(
                      installation,
                      etat.dossierActuel,
                    ),
                    estAlerte: false,
                    // Boutons qui passent à la ligne sur un écran étroit.
                    action: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: espacementPetit,
                      runSpacing: espacementPetit,
                      children: <Widget>[
                        TextButton(
                          onPressed: occupe
                              ? null
                              : () => _ignorerInstallation(context, etat),
                          child: const Text(Textes.ignorer),
                        ),
                        FilledButton.tonal(
                          onPressed: occupe
                              ? null
                              : () => ouvrirChangementDossier(
                                  context,
                                  etat,
                                  cheminPropose: installation,
                                ),
                          child: const Text(Textes.deplacerMesChapitres),
                        ),
                      ],
                    ),
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
