/// Carte d'un titre dans la grille de la bibliothèque.
library;

import 'package:material_ui/material_ui.dart';

import '../modeles/titre.dart';
import 'constantes_interface.dart';
import 'image_couverture.dart';
import 'textes.dart';

/// Couverture et nom d'un titre, avec le nombre de chapitres non lus en
/// badge.
///
/// La couverture vient de l'appareil quand elle y est enregistrée (lisible
/// hors-ligne), sinon du site (voir [ImageCouverture]).
class CarteTitre extends StatelessWidget {
  /// Crée la carte de [titre] ; [surAppui] ouvre sa fiche.
  const CarteTitre({super.key, required this.titre, this.surAppui});

  /// Titre affiché.
  final Titre titre;

  /// Action à l'appui sur la carte.
  final VoidCallback? surAppui;

  @override
  Widget build(BuildContext context) {
    final nonLus = titre.nombreChapitresNonLus;
    return Card(
      // Découpe l'image aux coins arrondis de la carte.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: surAppui,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // La couverture prend toute la hauteur restante : la grille fixe
            // le rapport de la carte, le nom garde sa hauteur naturelle.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ImageCouverture(titre: titre),
                  if (nonLus > 0)
                    Positioned(
                      top: espacementPetit,
                      right: espacementPetit,
                      child: Semantics(
                        label: Textes.chapitresNonLus(nonLus),
                        child: Badge.count(count: nonLus),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(espacementPetit),
              child: Text(
                titre.nom,
                maxLines: lignesMaxNomCarte,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
