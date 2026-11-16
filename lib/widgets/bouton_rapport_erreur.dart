/// Bouton « Exporter le rapport d'erreur » (tâche IN4 de l'étape 6).
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_rapports_erreur.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'textes.dart';

/// Bouton affiché sous le message d'un ajout de site ou de titre échoué :
/// il enregistre un rapport d'erreur (sans données personnelles) puis
/// indique au client où le trouver.
///
/// Rien n'est affiché si l'erreur n'a rien à diagnostiquer
/// ([DescriptionErreur.estRapportable] faux, par exemple une adresse vide)
/// ou si l'application n'a pas de service de rapports.
class BoutonRapportErreur extends StatefulWidget {
  /// Crée le bouton pour [erreur] ; [action] décrit ce que faisait le client
  /// (texte de `Textes`, recopié dans le rapport).
  const BoutonRapportErreur({
    super.key,
    required this.erreur,
    required this.action,
  });

  /// Erreur à rapporter.
  final DescriptionErreur erreur;

  /// Action en cours au moment de l'erreur (« Ajout d'un site »…).
  final String action;

  @override
  State<BoutonRapportErreur> createState() => _EtatBoutonRapportErreur();
}

class _EtatBoutonRapportErreur extends State<BoutonRapportErreur> {
  bool _estEnCours = false;

  EtatRapportsErreur? _etat(BuildContext context) {
    try {
      return context.read<EtatRapportsErreur>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _exporter(EtatRapportsErreur etat) async {
    setState(() => _estEnCours = true);
    final resultat = await etat.exporter(widget.erreur, action: widget.action);
    if (!mounted) return;
    setState(() => _estEnCours = false);
    final chemin = resultat.donnee;
    if (chemin == null) {
      afficherResultat(context, resultat);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.rapportEnregistre),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(Textes.explicationRapport),
                const SizedBox(height: espacementPetit),
                // Sélectionnable : le client peut copier le chemin pour
                // joindre le fichier à un message.
                SelectableText(chemin),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => ouvrirLienExterne(
              contexteDialogue,
              Uri.directory(etat.dossierRapports).toString(),
            ),
            child: const Text(Textes.ouvrirDossier),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(),
            child: const Text(Textes.fermer),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = _etat(context);
    if (etat == null || !widget.erreur.estRapportable) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: _estEnCours ? null : () => _exporter(etat),
        icon: _estEnCours
            ? SizedBox.square(
                dimension: IconTheme.of(context).size,
                child: const CircularProgressIndicator(
                  strokeWidth: epaisseurIndicateurBouton,
                ),
              )
            : const Icon(Icons.bug_report_outlined),
        label: const Text(Textes.exporterRapport),
      ),
    );
  }
}
