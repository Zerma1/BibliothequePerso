/// Image de couverture chargée par le service (jamais par `Image.network`).
library;

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_couvertures.dart';

/// Couverture d'un titre, avec un espace réservé pendant le chargement et en
/// cas d'erreur.
///
/// Les octets passent par `ServiceBibliotheque.recupererCouverture`, donc par
/// `ClientHttpPoli` : délai par domaine et User-Agent respectés
/// (PLAYBOOK.md section 6). `Image.network` contournerait ces règles.
class ImageCouverture extends StatefulWidget {
  /// Crée l'image pour [urlCouverture] (`null` : espace réservé seul).
  const ImageCouverture({
    super.key,
    required this.urlCouverture,
    this.referer,
  });

  /// Adresse de l'image, si le titre en a une.
  final String? urlCouverture;

  /// URL de base du site du titre, envoyée en `Referer` (beaucoup de sites
  /// refusent leurs images sans elle) ; `null` si la source est inconnue.
  final String? referer;

  @override
  State<ImageCouverture> createState() => _EtatImageCouverture();
}

class _EtatImageCouverture extends State<ImageCouverture> {
  Future<Uint8List>? _octets;

  @override
  void initState() {
    super.initState();
    _demanderOctets();
  }

  @override
  void didUpdateWidget(ImageCouverture ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.urlCouverture != widget.urlCouverture ||
        ancien.referer != widget.referer) {
      _demanderOctets();
    }
  }

  // Le Future est créé une seule fois par URL (et non dans build) : sinon
  // chaque reconstruction de la grille relancerait le chargement.
  void _demanderOctets() {
    final url = widget.urlCouverture;
    _octets = (url == null || url.isEmpty)
        ? null
        : context.read<EtatCouvertures>().recupererCouverture(
            url,
            referer: widget.referer,
          );
  }

  @override
  Widget build(BuildContext context) {
    final octets = _octets;
    if (octets == null) {
      return const _EspaceReserve(icone: Icons.menu_book_outlined);
    }
    return FutureBuilder<Uint8List>(
      future: octets,
      builder: (context, instantane) {
        final donnees = instantane.data;
        if (instantane.hasError) {
          return const _EspaceReserve(icone: Icons.broken_image_outlined);
        }
        if (donnees == null) {
          return const _EspaceReserve(icone: Icons.menu_book_outlined);
        }
        return Image.memory(
          donnees,
          fit: BoxFit.cover,
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
