/// Bouton de barre d'app « Rechercher les nouveaux chapitres ».
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_mises_a_jour.dart';
import 'constantes_interface.dart';
import 'textes.dart';

/// Bouton de la barre d'app qui lance la recherche des nouveaux chapitres
/// (onglets Bibliothèque et Mises à jour).
///
/// Widget séparé : seul lui se reconstruit quand la vérification commence ou
/// finit, pas tout l'écran.
class BoutonRechercheMisesAJour extends StatelessWidget {
  /// Crée le bouton.
  const BoutonRechercheMisesAJour({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatMisesAJour>();
    if (etat.estEnCours) {
      // L'indicateur prend la taille d'une icône de la barre d'app : le
      // titre et les autres boutons ne bougent pas pendant la vérification.
      return IconButton(
        tooltip: Textes.rechercheNouveauxChapitresEnCours,
        onPressed: null,
        icon: SizedBox.square(
          dimension: IconTheme.of(context).size,
          child: const CircularProgressIndicator(
            strokeWidth: epaisseurIndicateurBouton,
          ),
        ),
      );
    }
    return IconButton(
      tooltip: Textes.rechercherNouveauxChapitres,
      icon: const Icon(Icons.update),
      onPressed: etat.verifierMaintenant,
    );
  }
}
