/// Vues communes des trois cas que chaque écran doit montrer : chargement,
/// erreur et liste vide.
library;

import 'package:material_ui/material_ui.dart';

import 'constantes_interface.dart';
import 'textes.dart';

/// Indicateur de chargement centré.
class VueChargement extends StatelessWidget {
  /// Crée la vue.
  const VueChargement({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// Message d'erreur centré avec un bouton « Réessayer ».
class VueErreur extends StatelessWidget {
  /// Crée la vue avec le [message] à afficher.
  const VueErreur({super.key, required this.message, this.surReessayer});

  /// Texte de l'erreur, en français.
  final String message;

  /// Action du bouton « Réessayer » ; sans action, le bouton est masqué.
  final VoidCallback? surReessayer;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    // Défilement possible : un long message ne doit pas déborder sur un petit
    // écran ou en mode paysage.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(espacementGrand),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: tailleIconeEtat,
                color: couleurs.error,
              ),
              const SizedBox(height: espacementMoyen),
              Text(message, textAlign: TextAlign.center),
              if (surReessayer != null) ...<Widget>[
                const SizedBox(height: espacementMoyen),
                FilledButton.icon(
                  onPressed: surReessayer,
                  icon: const Icon(Icons.refresh),
                  label: const Text(Textes.reessayer),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Message d'aide centré quand il n'y a rien à afficher.
class VueVide extends StatelessWidget {
  /// Crée la vue avec son [message] et son [icone].
  const VueVide({
    super.key,
    required this.message,
    this.icone = Icons.inbox_outlined,
    this.action,
  });

  /// Texte d'aide, en français.
  final String message;

  /// Icône d'illustration.
  final IconData icone;

  /// Bouton facultatif sous le message (par exemple « Ajouter »).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(espacementGrand),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icone, size: tailleIconeEtat, color: couleurs.outline),
              const SizedBox(height: espacementMoyen),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...<Widget>[
                const SizedBox(height: espacementMoyen),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
