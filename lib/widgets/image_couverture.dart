/// Image de couverture chargée par le service (jamais par `Image.network`).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_couvertures.dart';
import '../modeles/titre.dart';

/// Couverture d'un titre, avec un espace réservé pendant le chargement et en
/// cas d'erreur.
///
/// Avec [titre] : la vignette enregistrée sur l'appareil (lisible
/// hors-ligne), sinon téléchargée puis enregistrée par
/// `ServiceBibliotheque.chargerCouverture` ; avec [pleineTaille], la
/// vignette est ensuite remplacée par l'image d'origine
/// (`chargerCouvertureOriginale`). Avec [ImageCouverture.adresse] : la
/// vignette d'une image du site (miniatures du choix de la couverture), par
/// `ServiceBibliotheque.recupererVignette`. Tout passe par `ClientHttpPoli` :
/// délai par domaine et User-Agent respectés (PLAYBOOK.md section 6).
/// `Image.network` contournerait ces règles.
class ImageCouverture extends StatefulWidget {
  /// Couverture affichée de [titre] (celle choisie par le client, sinon
  /// celle du site). [pleineTaille] : fiche d'un titre (vignette, puis
  /// image d'origine).
  const ImageCouverture({
    super.key,
    required Titre this.titre,
    this.pleineTaille = false,
  }) : url = null,
       referer = null;

  /// Vignette de l'image du site à [url] ; [referer] est l'URL de base du
  /// site (beaucoup de sites refusent leurs images sans elle).
  const ImageCouverture.adresse({
    super.key,
    required String this.url,
    this.referer,
  }) : titre = null,
       pleineTaille = false;

  /// `true` pour la fiche d'un titre : l'image d'origine remplace la
  /// vignette dès qu'elle arrive.
  final bool pleineTaille;

  /// Titre dont on affiche la couverture, ou `null` (image par adresse).
  final Titre? titre;

  /// Adresse de l'image, ou `null` (couverture d'un titre).
  final String? url;

  /// URL de base du site, envoyée en `Referer` avec [url].
  final String? referer;

  @override
  State<ImageCouverture> createState() => _EtatImageCouverture();
}

class _EtatImageCouverture extends State<ImageCouverture> {
  /// Octets affichés : la vignette, puis l'image d'origine pour la fiche.
  Future<Uint8List?>? _octets;

  /// Numéro de la demande en cours : une réponse arrivée après un
  /// changement de titre ou de couverture est ignorée.
  int _demande = 0;

  @override
  void initState() {
    super.initState();
    _demanderOctets();
  }

  @override
  void didUpdateWidget(ImageCouverture ancien) {
    super.didUpdateWidget(ancien);
    if (_cle(ancien) != _cle(widget)) {
      _demanderOctets();
    }
  }

  /// Ce qui change l'image affichée : couverture choisie, ou nom et type du
  /// titre (ils déterminent le dossier de l'image sur l'appareil).
  static Object? _cle(ImageCouverture image) {
    final titre = image.titre;
    if (titre == null) return (image.url, image.referer);
    return (
      titre.id,
      titre.couvertureAffichee,
      titre.nom,
      titre.typeTitre,
      image.pleineTaille,
    );
  }

  // Le Future est créé une seule fois par image (et non dans build) : sinon
  // chaque reconstruction de la grille relancerait le chargement.
  void _demanderOctets() {
    final couvertures = context.read<EtatCouvertures>();
    final titre = widget.titre;
    final url = widget.url;
    final demande = ++_demande;
    if (titre != null) {
      final vignette = titre.couvertureAffichee == null
          ? null
          : couvertures.chargerCouverture(titre);
      _octets = vignette;
      if (vignette != null && widget.pleineTaille) {
        // L'original n'est demandé qu'une fois la vignette affichée : la
        // fiche s'ouvre sans attendre une image dix fois plus lourde, et
        // les deux requêtes ne se concurrencent pas.
        unawaited(
          vignette
              .then((_) => couvertures.chargerCouvertureOriginale(titre))
              .then((original) {
                if (!mounted || demande != _demande || original == null) {
                  return;
                }
                // Nouveau Future plutôt qu'un autre widget : le
                // FutureBuilder garde la vignette jusqu'à la réponse et
                // l'Image garde son état (passage sans clignotement).
                setState(() => _octets = Future<Uint8List?>.value(original));
              }),
        );
      }
    } else if (url != null && url.isNotEmpty) {
      _octets = couvertures.recupererVignette(url, referer: widget.referer);
    } else {
      _octets = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final octets = _octets;
    if (octets == null) {
      return const _EspaceReserve(icone: Icons.menu_book_outlined);
    }
    return FutureBuilder<Uint8List?>(
      future: octets,
      builder: (context, instantane) {
        final donnees = instantane.data;
        if (instantane.hasError) {
          return const _EspaceReserve(icone: Icons.broken_image_outlined);
        }
        if (donnees == null) {
          return _EspaceReserve(
            icone: instantane.connectionState == ConnectionState.done
                ? Icons.broken_image_outlined
                : Icons.menu_book_outlined,
          );
        }
        return _image(donnees);
      },
    );
  }

  /// Image décodée à la taille affichée (et non à sa taille réelle) : une
  /// grille de centaines de couvertures reste légère en mémoire.
  Widget _image(Uint8List donnees) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final largeur = contraintes.hasBoundedWidth
            ? (contraintes.maxWidth * ratio).ceil()
            : null;
        return Image.memory(
          donnees,
          fit: BoxFit.cover,
          cacheWidth: largeur == null || largeur <= 0 ? null : largeur,
          // Passage vignette → original sans clignotement.
          gaplessPlayback: true,
          // Octets reçus mais illisibles (page HTML d'erreur…) : espace
          // réservé plutôt qu'une exception.
          errorBuilder: (context, erreur, pile) =>
              const _EspaceReserve(icone: Icons.broken_image_outlined),
        );
      },
    );
  }
}

/// Fond neutre avec une icône, à la taille de la couverture.
class _EspaceReserve extends StatelessWidget {
  const _EspaceReserve({required this.icone});

  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: couleurs.surfaceContainerHighest,
      child: Center(child: Icon(icone, color: couleurs.outline)),
    );
  }
}
