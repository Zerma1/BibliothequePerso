/// Dialogue « Choisir la couverture » d'un titre (tâche IN3 de l'étape 6).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_titre.dart';
import 'constantes_interface.dart';
import 'image_couverture.dart';
import 'textes.dart';

/// Ouvre le choix de la couverture du titre de [etat].
///
/// Renvoie le message à afficher après un changement, ou `null` si le
/// client a fermé sans rien changer.
Future<String?> afficherDialogueCouverture(
  BuildContext context,
  EtatTitre etat,
) {
  return showDialog<String>(
    context: context,
    builder: (_) => DialogueCouverture(etat: etat),
  );
}

/// Choix de la couverture : une des couvertures proposées par le site
/// (MangaDex : une par volume), une image de l'appareil, ou retour à la
/// couverture du site.
///
/// L'état est passé en paramètre : le dialogue est une autre route, hors du
/// fournisseur de la fiche.
class DialogueCouverture extends StatefulWidget {
  /// Crée le dialogue pour le titre de [etat].
  const DialogueCouverture({super.key, required this.etat});

  /// État de la fiche du titre.
  final EtatTitre etat;

  @override
  State<DialogueCouverture> createState() => _EtatDialogueCouverture();
}

class _EtatDialogueCouverture extends State<DialogueCouverture> {
  final TextEditingController _chemin = TextEditingController();

  /// Lecture réseau des couvertures du site, lancée une fois à l'ouverture
  /// (et non à chaque reconstruction).
  late Future<ResultatAction<List<CouvertureProposee>>> _couvertures = widget
      .etat
      .recupererCouverturesDuSite();

  String? _messageErreur;

  @override
  void dispose() {
    _chemin.dispose();
    super.dispose();
  }

  Future<void> _appliquer(Future<ResultatAction<bool>> action) async {
    setState(() => _messageErreur = null);
    final resultat = await action;
    if (!mounted) return;
    final erreur = resultat.erreur;
    if (erreur != null) {
      // L'erreur reste dans le dialogue : le client peut choisir une autre
      // image sans tout recommencer.
      setState(() => _messageErreur = Textes.messageErreur(erreur));
      return;
    }
    Navigator.of(context).pop(Textes.couvertureChangee);
  }

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.sizeOf(context);
    return ListenableBuilder(
      listenable: widget.etat,
      builder: (context, _) {
        final etat = widget.etat;
        final occupe = etat.estEnChangementCouverture;
        final theme = Theme.of(context);
        final messageErreur = _messageErreur;
        return AlertDialog(
          title: const Text(Textes.choisirCouverture),
          // Largeur et hauteur bornées : la grille des couvertures défile
          // dans le dialogue sans le faire déborder de l'écran.
          // Largeur fixée (et non seulement bornée) : AlertDialog mesure la
          // largeur « naturelle » de son contenu, ce qu'une grille construite
          // à la demande ne sait pas faire.
          content: SizedBox(
            width: math.min(
              largeurMaxFormulaire,
              taille.width * fractionLargeurDialogue,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: taille.height * fractionHauteurPanneau,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (occupe) ...<Widget>[
                      const LinearProgressIndicator(),
                      const SizedBox(height: espacementPetit),
                    ],
                    if (messageErreur != null) ...<Widget>[
                      Text(
                        messageErreur,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: espacementPetit),
                    ],
                    Text(
                      Textes.couverturesDuSite,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: espacementPetit),
                    _couverturesDuSite(etat, occupe),
                    const SizedBox(height: espacementGrand),
                    Text(
                      Textes.imageDeLAppareil,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: espacementPetit),
                    // LIMITE : sans paquet de sélection de fichiers (à valider
                    // par le client), le chemin est saisi ou collé à la main.
                    TextField(
                      controller: _chemin,
                      enabled: !occupe,
                      decoration: const InputDecoration(
                        labelText: Textes.champCheminImage,
                        helperText: Textes.aideCheminImage,
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: occupe
                          ? null
                          : (_) => _appliquer(
                              etat.choisirCouvertureLocale(_chemin.text),
                            ),
                    ),
                    const SizedBox(height: espacementPetit),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: OutlinedButton.icon(
                        onPressed: occupe
                            ? null
                            : () => _appliquer(
                                etat.choisirCouvertureLocale(_chemin.text),
                              ),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text(Textes.utiliserImage),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: <Widget>[
            if (etat.aCouvertureChoisie)
              TextButton(
                onPressed: occupe
                    ? null
                    : () => _appliquer(etat.retablirCouvertureDuSite()),
                child: const Text(Textes.revenirCouvertureSite),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(Textes.fermer),
            ),
          ],
        );
      },
    );
  }

  /// Grille des couvertures du site, avec les trois cas : chargement,
  /// erreur (« Réessayer ») et aucune couverture.
  Widget _couverturesDuSite(EtatTitre etat, bool occupe) {
    return FutureBuilder<ResultatAction<List<CouvertureProposee>>>(
      future: _couvertures,
      builder: (context, instantane) {
        final resultat = instantane.data;
        if (resultat == null) {
          return const Padding(
            padding: EdgeInsets.all(espacementMoyen),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final erreur = resultat.erreur;
        if (erreur != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(Textes.messageErreur(erreur)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _couvertures = etat.recupererCouverturesDuSite(),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text(Textes.reessayer),
                ),
              ),
            ],
          );
        }
        final couvertures = resultat.donnee ?? const <CouvertureProposee>[];
        if (couvertures.isEmpty) {
          return const Text(Textes.aucuneCouvertureSite);
        }
        final actuelle = etat.titre?.couvertureAffichee;
        // Grille à largeur de miniature maximale : le nombre de colonnes
        // suit la largeur du dialogue (2 sur téléphone, 4 sur ordinateur).
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: largeurMaxMiniatureCouverture,
            childAspectRatio: rapportCarteTitre,
            crossAxisSpacing: espacementPetit,
            mainAxisSpacing: espacementPetit,
          ),
          itemCount: couvertures.length,
          itemBuilder: (context, index) => _MiniatureCouverture(
            couverture: couvertures[index],
            referer: etat.source?.urlBase,
            estActuelle: couvertures[index].url == actuelle,
            surChoix: occupe
                ? null
                : () => _appliquer(
                    etat.choisirCouverture(couvertures[index].url),
                  ),
          ),
        );
      },
    );
  }
}

/// Une couverture proposée : image, volume et langue ; encadrée si c'est la
/// couverture actuelle.
class _MiniatureCouverture extends StatelessWidget {
  const _MiniatureCouverture({
    required this.couverture,
    required this.referer,
    required this.estActuelle,
    required this.surChoix,
  });

  final CouvertureProposee couverture;
  final String? referer;
  final bool estActuelle;
  final VoidCallback? surChoix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final legende = Textes.legendeCouverture(
      couverture.volume,
      couverture.langue,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      // Bordure de la couleur principale : la couverture actuelle se repère
      // sans lire les légendes.
      shape: estActuelle
          ? RoundedRectangleBorder(
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(espacementPetit),
            )
          : null,
      child: InkWell(
        onTap: surChoix,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ImageCouverture.adresse(
                url: couverture.urlAffichee,
                referer: referer,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(espacementPetit / 2),
              child: Text(
                estActuelle
                    ? '$legende · ${Textes.couvertureActuelle}'
                    : legende,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
