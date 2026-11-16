/// Écran affiché quand l'application ne peut pas démarrer (base illisible).
library;

import 'package:material_ui/material_ui.dart';

import '../widgets/constantes_interface.dart';
import '../widgets/textes.dart';

/// Explique au client que la base n'a pas pu être ouverte, au lieu de
/// laisser l'application planter sur un écran blanc.
class EcranErreurDemarrage extends StatelessWidget {
  /// Crée l'écran avec le [detail] technique de l'erreur.
  const EcranErreurDemarrage({
    super.key,
    required this.detail,
    this.surReessayer,
  });

  /// Texte technique de l'erreur (utile pour un signalement).
  final String detail;

  /// Relance le démarrage ; sans action, le bouton est masqué.
  final VoidCallback? surReessayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(Textes.titreApplication)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(espacementGrand),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.storage_outlined,
                  size: tailleIconeEtat,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: espacementMoyen),
                Text(
                  Textes.erreurDemarrageTitre,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: espacementMoyen),
                const Text(
                  Textes.erreurDemarrageExplication,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: espacementMoyen),
                SelectableText(
                  Textes.detailTechnique(detail),
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                if (surReessayer != null) ...<Widget>[
                  const SizedBox(height: espacementGrand),
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
      ),
    );
  }
}
