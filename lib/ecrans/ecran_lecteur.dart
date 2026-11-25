/// Écran Lecteur : pages d'un chapitre téléchargé en défilement vertical
/// continu (style webtoon), ou texte d'un chapitre de roman.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_lecteur.dart';
import '../etat/outils_chapitres.dart';
import '../modeles/chapitre.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/indicateur_hors_ligne.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';
import 'ecran_navigateur.dart';

/// Lecteur d'un chapitre : pages lues directement dans l'archive `.zip`,
/// chargées au fur et à mesure du défilement, zoom, position « page X / N »
/// et passage au chapitre précédent ou suivant.
///
/// Lit un [EtatLecteur] fourni au-dessus de lui : utiliser
/// [EcranLecteur.ouvrir].
class EcranLecteur extends StatelessWidget {
  /// Crée l'écran.
  const EcranLecteur({super.key});

  /// Ouvre le lecteur avec [etat] (créé par la fiche du titre, qui a accès
  /// aux services). L'état est libéré à la fermeture.
  static Future<void> ouvrir(BuildContext context, EtatLecteur etat) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<EtatLecteur>(
          create: (_) => etat..charger(),
          child: const EcranLecteur(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatLecteur>();
    final chapitre = etat.chapitre;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              chapitre == null
                  ? ''
                  : Textes.nomChapitre(chapitre.nom, chapitre.numero),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (etat.titre != null)
              Text(
                etat.titre!.nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: _contenu(context, etat),
      bottomNavigationBar: chapitre == null ? null : _BarreLecteur(etat: etat),
    );
  }

  Widget _contenu(BuildContext context, EtatLecteur etat) {
    final erreur = etat.erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.reessayer,
      );
    }
    final chapitre = etat.chapitre;
    switch (etat.nature) {
      case NatureContenu.chargement:
        return const VueChargement();
      case NatureContenu.nonTelecharge:
        return _VueNonTelecharge(etat: etat);
      case NatureContenu.externe:
        return _VueExterne(etat: etat);
      case NatureContenu.texte:
        // Clé par chapitre : un nouveau chapitre repart en haut de page.
        return _VueTexte(key: ValueKey<int?>(chapitre?.id), etat: etat);
      case NatureContenu.images:
        return _VueImages(key: ValueKey<int?>(chapitre?.id), etat: etat);
    }
  }
}

/// Barre du bas : chapitre précédent, position, chapitre suivant.
class _BarreLecteur extends StatelessWidget {
  const _BarreLecteur({required this.etat});

  final EtatLecteur etat;

  @override
  Widget build(BuildContext context) {
    final precedent = etat.chapitrePrecedent;
    final suivant = etat.chapitreSuivant;
    final position = etat.nature == NatureContenu.images
        ? Textes.pageSurTotal(etat.pageCourante + 1, etat.nombrePages)
        : '';
    return BottomAppBar(
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: Textes.chapitrePrecedent,
            icon: const Icon(Icons.skip_previous),
            onPressed: precedent == null ? null : etat.allerAuPrecedent,
          ),
          Expanded(
            child: Text(
              position,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: Textes.chapitreSuivant,
            icon: const Icon(Icons.skip_next),
            onPressed: suivant == null ? null : etat.allerAuSuivant,
          ),
        ],
      ),
    );
  }
}

/// Chapitre pas encore sur l'appareil : téléchargement, progression, ou
/// ouverture sur le site.
class _VueNonTelecharge extends StatelessWidget {
  const _VueNonTelecharge({required this.etat});

  final EtatLecteur etat;

  @override
  Widget build(BuildContext context) {
    final horsLigne = etat.etatHorsLigne;
    final chapitre = etat.chapitre;
    final enTelechargement =
        horsLigne.statut == StatutHorsLigne.enFile ||
        horsLigne.statut == StatutHorsLigne.enCours;
    return VueVide(
      message: enTelechargement
          ? Textes.lecteurEnTelechargement(horsLigne)
          : Textes.lecteurNonTelecharge,
      icone: iconeHorsLigne(horsLigne.statut),
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: espacementPetit,
        runSpacing: espacementPetit,
        children: <Widget>[
          if (enTelechargement)
            IndicateurHorsLigne(etat: horsLigne)
          else
            FilledButton.icon(
              onPressed: () async {
                final resultat = await etat.telechargerChapitre();
                if (context.mounted) {
                  afficherResultat(
                    context,
                    resultat,
                    succes: Textes.telechargementAjoute,
                  );
                }
              },
              icon: const Icon(Icons.download),
              label: Text(
                horsLigne.statut == StatutHorsLigne.echec
                    ? Textes.reessayerTelechargement
                    : Textes.telecharger,
              ),
            ),
          // « Lire en ligne » : navigateur intégré (Windows, Android) ; au
          // retour, le chapitre a peut-être été enregistré depuis la page.
          if (chapitre != null && EcranNavigateur.estDisponible(context))
            OutlinedButton.icon(
              onPressed: () async {
                await EcranNavigateur.ouvrir(
                  context,
                  chapitre.urlChapitre,
                  idTitre: etat.idTitre,
                );
                await etat.charger();
              },
              icon: const Icon(Icons.public),
              label: const Text(Textes.lireEnLigne),
            ),
          if (chapitre != null)
            OutlinedButton.icon(
              onPressed: () => ouvrirLienExterne(context, chapitre.urlChapitre),
              icon: const Icon(Icons.open_in_new),
              label: const Text(Textes.ouvrirSurLeSite),
            ),
        ],
      ),
    );
  }
}

/// Chapitre publié sur un site externe : rien à lire ici, seulement le lien
/// vers le site de l'éditeur (PLAYBOOK.md section 10).
class _VueExterne extends StatelessWidget {
  const _VueExterne({required this.etat});

  final EtatLecteur etat;

  @override
  Widget build(BuildContext context) {
    final chapitre = etat.chapitre;
    final site = chapitre == null ? null : etat.nomSiteExterneDe(chapitre);
    if (chapitre == null || site == null) return const VueChargement();
    return VueVide(
      message: Textes.lecteurChapitreExterne(site),
      icone: iconeLienExterne,
      action: _BoutonLireSurSite(
        chapitre: chapitre,
        site: site,
        idTitre: etat.idTitre,
      ),
    );
  }
}

/// Bouton « Lire sur `site` » d'un chapitre externe : ouvre la page dans le
/// navigateur intégré (Windows, Android), sinon dans le navigateur du
/// système.
class _BoutonLireSurSite extends StatelessWidget {
  const _BoutonLireSurSite({
    required this.chapitre,
    required this.site,
    required this.idTitre,
  });

  final Chapitre chapitre;
  final String site;
  final int idTitre;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => EcranNavigateur.ouvrir(
        context,
        chapitre.urlExterne!,
        idTitre: idTitre,
      ),
      icon: const Icon(iconeLienExterne),
      label: Text(
        '${Textes.lireSur(site)} : '
        '${Textes.nomChapitre(chapitre.nom, chapitre.numero)}',
      ),
    );
  }
}

/// Pages en défilement vertical continu, construites seulement quand elles
/// approchent de l'écran.
class _VueImages extends StatefulWidget {
  const _VueImages({super.key, required this.etat});

  final EtatLecteur etat;

  @override
  State<_VueImages> createState() => _EtatVueImages();
}

class _EtatVueImages extends State<_VueImages> {
  final TransformationController _zoom = TransformationController();

  /// Clés des pages actuellement construites : servent à savoir laquelle
  /// est au milieu de l'écran (position « page X / N »).
  final Map<int, GlobalKey> _clesPages = <int, GlobalKey>{};

  /// Proportion (hauteur / largeur) de chaque page déjà décodée, gardée
  /// pour tout le chapitre. En remontant, une page reconstruite (et parfois
  /// relue dans l'archive, l'état oubliant les octets des pages éloignées)
  /// réserve d'emblée sa hauteur réelle au lieu de la hauteur provisoire :
  /// sinon elle grandissait au-dessus de l'écran une fois décodée et tout
  /// le contenu visible était repoussé vers le bas (sauts signalés par le
  /// client sur la 0.2.0-test).
  final Map<int, double> _proportionsPages = <int, double>{};

  @override
  void initState() {
    super.initState();
    // Un chapitre court peut tenir entièrement à l'écran : on vérifie la
    // position une première fois après l'affichage.
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculerPage(null));
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  GlobalKey _cle(int index) =>
      _clesPages.putIfAbsent(index, () => GlobalKey(debugLabel: 'page$index'));

  /// Repère la page qui occupe le milieu de l'écran et la signale à l'état
  /// (qui marque le chapitre lu à la dernière page).
  void _calculerPage(ScrollMetrics? metriques) {
    if (!mounted) return;
    final reference = context.findRenderObject();
    if (reference is! RenderBox || !reference.hasSize) return;
    final etat = widget.etat;
    // Bas de la liste atteint : la dernière page est forcément vue.
    final finAtteinte = metriques != null && metriques.extentAfter <= 0;
    if (finAtteinte) {
      etat.signalerPageVisible(etat.nombrePages - 1);
      return;
    }
    final milieu = reference.size.height / 2;
    for (final entree in _clesPages.entries) {
      final boite = entree.value.currentContext?.findRenderObject();
      if (boite is! RenderBox || !boite.attached || !boite.hasSize) continue;
      final haut = boite.localToGlobal(Offset.zero, ancestor: reference).dy;
      if (haut <= milieu && haut + boite.size.height > milieu) {
        etat.signalerPageVisible(entree.key);
        return;
      }
    }
  }

  void _zoomer(double pas) {
    final echelle = (_zoom.value.getMaxScaleOnAxis() + pas).clamp(
      1.0,
      zoomMaxLecteur,
    );
    _zoom.value = Matrix4.diagonal3Values(echelle, echelle, 1);
  }

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    final plateforme = Theme.of(context).platform;
    // Sur ordinateur, la molette doit faire défiler les pages et non zoomer
    // (InteractiveViewer zoome à la molette) : le zoom y passe par les
    // boutons. Sur écran tactile, on pince pour zoomer.
    final estOrdinateur =
        plateforme == TargetPlatform.windows ||
        plateforme == TargetPlatform.linux ||
        plateforme == TargetPlatform.macOS;
    final hauteurProvisoire =
        MediaQuery.sizeOf(context).height * fractionHauteurPageProvisoire;
    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _calculerPage(notification.metrics);
            return false;
          },
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: zoomMaxLecteur,
            scaleEnabled: !estOrdinateur,
            child: ListView.builder(
              // Une page de plus : le pied « fin du chapitre ».
              itemCount: etat.nombrePages + 1,
              itemBuilder: (context, index) {
                if (index == etat.nombrePages) {
                  return _PiedChapitre(etat: etat);
                }
                return Center(
                  // Largeur plafonnée : sur grand écran, une page étirée sur
                  // toute la fenêtre serait trop haute pour être lue.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: largeurMaxLecture,
                    ),
                    child: _PageLecteur(
                      key: _cle(index),
                      etat: etat,
                      index: index,
                      hauteurProvisoire: hauteurProvisoire,
                      proportionConnue: _proportionsPages[index],
                      // Pas de setState : la page décodée a déjà sa taille
                      // réelle ; la valeur ne sert qu'aux prochaines
                      // constructions de cette page.
                      surProportion: (proportion) =>
                          _proportionsPages[index] = proportion,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Boutons de zoom flottants en haut à droite : discrets, et
        // toujours accessibles à la souris.
        Positioned(
          top: espacementPetit,
          right: espacementPetit,
          child: Card(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: Textes.reduire,
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () => _zoomer(-pasZoomLecteur),
                ),
                IconButton(
                  tooltip: Textes.tailleNormale,
                  icon: const Icon(Icons.fit_screen),
                  onPressed: () => _zoom.value = Matrix4.identity(),
                ),
                IconButton(
                  tooltip: Textes.agrandir,
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () => _zoomer(pasZoomLecteur),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Une page : lue dans l'archive au premier affichage.
class _PageLecteur extends StatefulWidget {
  const _PageLecteur({
    super.key,
    required this.etat,
    required this.index,
    required this.hauteurProvisoire,
    required this.proportionConnue,
    required this.surProportion,
  });

  final EtatLecteur etat;
  final int index;

  /// Hauteur réservée tant que la proportion de la page est inconnue.
  final double hauteurProvisoire;

  /// Proportion (hauteur / largeur) de la page si elle a déjà été décodée.
  final double? proportionConnue;

  /// Appelé avec la proportion de la page dès qu'elle est décodée.
  final ValueChanged<double> surProportion;

  @override
  State<_PageLecteur> createState() => _EtatPageLecteur();
}

class _EtatPageLecteur extends State<_PageLecteur> {
  /// Lecture demandée une fois pour toutes tant que la page est construite :
  /// l'état oublie les pages éloignées de la page courante, mais une page
  /// encore à l'écran ne doit pas être relue à chaque notification.
  late Future<Uint8List> _lecture;

  @override
  void initState() {
    super.initState();
    _lecture = widget.etat.page(widget.index);
  }

  @override
  void didUpdateWidget(_PageLecteur ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.index != widget.index || ancien.etat != widget.etat) {
      _lecture = widget.etat.page(widget.index);
    }
  }

  void _relire() {
    widget.etat.relirePage(widget.index);
    setState(() => _lecture = widget.etat.page(widget.index));
  }

  /// Image écoutée pour connaître sa proportion une fois décodée.
  ImageProvider? _imageEcoutee;
  ImageStream? _flux;
  ImageStreamListener? _ecouteur;

  /// Écoute le décodage de [image] (une seule fois par image) pour
  /// transmettre sa proportion au lecteur. Le décodage est celui de
  /// l'`Image` affichée (même clé dans le cache d'images) : rien n'est
  /// décodé deux fois.
  void _ecouterProportion(BuildContext context, ImageProvider image) {
    if (image == _imageEcoutee) return;
    _arreterEcoute();
    _imageEcoutee = image;
    final ecouteur = ImageStreamListener((info, _) {
      final largeur = info.image.width;
      if (largeur > 0) widget.surProportion(info.image.height / largeur);
    }, onError: (_, _) {});
    _ecouteur = ecouteur;
    _flux = image.resolve(createLocalImageConfiguration(context))
      ..addListener(ecouteur);
  }

  void _arreterEcoute() {
    final ecouteur = _ecouteur;
    if (ecouteur != null) _flux?.removeListener(ecouteur);
    _flux = null;
    _ecouteur = null;
    _imageEcoutee = null;
  }

  @override
  void dispose() {
    _arreterEcoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    final index = widget.index;
    final hauteurProvisoire = widget.hauteurProvisoire;
    final proportion = widget.proportionConnue;
    // Largeur réellement affichée (plafonnée par la colonne de lecture) :
    // elle donne la hauteur réservée d'une page dont la proportion est
    // connue, et la taille de décodage de l'image.
    return LayoutBuilder(
      builder: (context, contraintes) {
        final largeur = contraintes.maxWidth;
        final largeurValide = largeur.isFinite && largeur > 0;
        // Hauteur réelle si la page a déjà été affichée, sinon provisoire.
        // Elle ne change donc jamais pour une page déjà vue : en remontant,
        // rien ne grandit au-dessus de l'écran.
        final hauteurReservee = proportion != null && largeurValide
            ? largeur * proportion
            : hauteurProvisoire;
        return FutureBuilder<Uint8List>(
          future: _lecture,
          builder: (context, instantane) {
            if (instantane.hasError) {
              return SizedBox(
                height: proportion == null
                    ? hauteurProvisoire / 2
                    : hauteurReservee,
                child: VueErreur(
                  message: Textes.pageIllisible,
                  surReessayer: _relire,
                ),
              );
            }
            final octets = instantane.data;
            if (octets == null) {
              return SizedBox(
                height: hauteurReservee,
                child: const VueChargement(),
              );
            }
            // Décodage à la largeur affichée en pixels physiques et non à
            // la taille d'origine, souvent bien plus grande : une page de
            // webtoon décodée en entier peut peser des dizaines de Mo.
            final largeurDecodage = largeurValide
                ? (largeur * MediaQuery.devicePixelRatioOf(context)).round()
                : null;
            final image = ResizeImage.resizeIfNeeded(
              largeurDecodage,
              null,
              MemoryImage(octets),
            );
            _ecouterProportion(context, image);
            final vue = Image(
              image: image,
              width: double.infinity,
              fit: BoxFit.fitWidth,
              gaplessPlayback: true,
              semanticLabel: Textes.pageSurTotal(index + 1, etat.nombrePages),
              // Tant que l'image n'est pas décodée, elle n'a pas de hauteur :
              // on garde la hauteur réservée, sinon toutes les pages
              // suivantes entreraient d'un coup dans l'écran (et seraient
              // toutes lues).
              frameBuilder: (context, enfant, image, estSynchrone) =>
                  image == null && !estSynchrone
                  ? SizedBox(height: hauteurReservee, child: enfant)
                  : enfant,
              errorBuilder: (_, _, _) => SizedBox(
                height: hauteurProvisoire / 2,
                child: const Center(child: Text(Textes.pageIllisible)),
              ),
            );
            // Proportion connue : hauteur fixée, identique avant et après
            // le décodage.
            return proportion == null
                ? vue
                : SizedBox(height: hauteurReservee, child: vue);
          },
        );
      },
    );
  }
}

/// Pied du chapitre : fin, chapitre suivant et crédit MangaDex.
class _PiedChapitre extends StatelessWidget {
  const _PiedChapitre({required this.etat});

  final EtatLecteur etat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suivant = etat.chapitreSuivant;
    final externes = etat.chapitresExternesSuivants;
    final premierExterne = externes.firstOrNull;
    final site = premierExterne == null
        ? null
        : etat.nomSiteExterneDe(premierExterne);
    return Padding(
      padding: const EdgeInsets.all(espacementGrand),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(Textes.finDuChapitre, style: theme.textTheme.titleMedium),
          const SizedBox(height: espacementMoyen),
          // Les chapitres publiés chez l'éditeur sont sautés par « Chapitre
          // suivant » : leur lien est proposé ici, juste avant.
          if (premierExterne != null && site != null) ...<Widget>[
            Text(
              Textes.chapitresExternesSuivants(externes.length, site),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: espacementPetit),
            _BoutonLireSurSite(
              chapitre: premierExterne,
              site: site,
              idTitre: etat.idTitre,
            ),
            const SizedBox(height: espacementMoyen),
          ],
          if (suivant == null && premierExterne != null)
            const SizedBox.shrink()
          else if (suivant == null)
            const Text(Textes.dernierChapitre, textAlign: TextAlign.center)
          else
            FilledButton.icon(
              onPressed: etat.allerAuSuivant,
              icon: const Icon(Icons.skip_next),
              label: Text(
                '${Textes.chapitreSuivant} : '
                '${Textes.nomChapitre(suivant.nom, suivant.numero)}',
              ),
            ),
          if (etat.estMangaDex) ...<Widget>[
            const SizedBox(height: espacementMoyen),
            // Crédit exigé par les règles d'usage de MangaDex
            // (PLAYBOOK.md section 6).
            Text(
              Textes.creditMangaDexComplet,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Texte d'un chapitre de roman, en colonne de largeur confortable.
class _VueTexte extends StatefulWidget {
  const _VueTexte({super.key, required this.etat});

  final EtatLecteur etat;

  @override
  State<_VueTexte> createState() => _EtatVueTexte();
}

class _EtatVueTexte extends State<_VueTexte> {
  final ScrollController _defilement = ScrollController();

  @override
  void initState() {
    super.initState();
    // Un texte court tient sans défiler : sa fin est alors déjà visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _defilement.hasClients &&
          _defilement.position.maxScrollExtent <= 0) {
        unawaited(widget.etat.marquerFinLecture());
      }
    });
  }

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texte = widget.etat.texte;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter <= 0) {
          unawaited(widget.etat.marquerFinLecture());
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _defilement,
        padding: const EdgeInsets.all(espacementMoyen),
        child: Center(
          // Lignes de longueur raisonnable : un texte sur toute la largeur
          // d'un écran d'ordinateur se lit mal.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: largeurMaxLecture),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SelectableText(
                  texte.isEmpty ? Textes.texteVide : texte,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: interligneLecture,
                  ),
                ),
                _PiedChapitre(etat: widget.etat),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
