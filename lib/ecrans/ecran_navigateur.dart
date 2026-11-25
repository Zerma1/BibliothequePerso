/// Écran Navigateur : navigateur intégré (tâche N3) pour lire un chapitre sur
/// son site sans quitter l'application, avec suivi de lecture et
/// « Enregistrer ce chapitre ».
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_navigateur.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vue_web.dart';
import '../widgets/vues_etat.dart';

/// Navigateur intégré : barre d'adresse et de navigation, vue web, et en bas
/// le repère du chapitre affiché (« Chapitre 12 de … (non lu) ») avec
/// « Enregistrer ce chapitre ».
///
/// Lit un [EtatNavigateur] fourni au-dessus de lui : utiliser
/// [EcranNavigateur.ouvrir]. [constructeurVueWeb] permet aux tests de
/// remplacer la vraie vue web par un faux.
class EcranNavigateur extends StatefulWidget {
  /// Crée l'écran.
  const EcranNavigateur({
    super.key,
    this.constructeurVueWeb = construireVueWeb,
  });

  /// Construit la vue web (la vraie par défaut).
  final ConstructeurVueWeb constructeurVueWeb;

  /// `true` si le navigateur intégré peut s'ouvrir ici : Windows ou Android,
  /// et état fourni par l'application.
  static bool estDisponible(BuildContext context) =>
      estNavigateurIntegrePossible &&
      context.read<FabriqueEtatNavigateur?>() != null;

  /// Ouvre [adresse] dans le navigateur intégré (depuis la fiche du titre
  /// [idTitre] si connue) ; ailleurs (Linux, ou état absent), dans le
  /// navigateur du système. Se termine à la fermeture de l'écran.
  static Future<void> ouvrir(
    BuildContext context,
    String adresse, {
    int? idTitre,
  }) async {
    final fabrique = estNavigateurIntegrePossible
        ? context.read<FabriqueEtatNavigateur?>()
        : null;
    if (fabrique == null) {
      await ouvrirLienExterne(context, adresse);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<EtatNavigateur>(
          create: (_) => fabrique.creer(adresse: adresse, idTitre: idTitre),
          child: const EcranNavigateur(),
        ),
      ),
    );
  }

  @override
  State<EcranNavigateur> createState() => _EtatEcranNavigateur();
}

class _EtatEcranNavigateur extends State<EcranNavigateur> {
  final TextEditingController _champAdresse = TextEditingController();
  final FocusNode _focusAdresse = FocusNode();
  ControleurVueWeb? _controleur;
  late final EtatNavigateur _etat;

  /// Vue web construite une seule fois : la reconstruire à chaque
  /// notification de l'état recréerait la page.
  late final Widget _vueWeb;

  @override
  void initState() {
    super.initState();
    _etat = context.read<EtatNavigateur>();
    _champAdresse.text = _etat.adresse;
    _etat.addListener(_synchroniserAdresse);
    _vueWeb = widget.constructeurVueWeb(
      ParametresVueWeb(
        adresseInitiale: _etat.adresseInitiale,
        surCreation: (controleur) {
          _controleur = controleur;
          // Les boutons qui dépendent du contrôleur deviennent actifs.
          if (mounted) setState(() {});
        },
        surDebutChargement: _etat.signalerDebutChargement,
        surAdresse: _surAdresse,
        surFinChargement: (adresse) {
          _etat.signalerProgression(100);
          _surAdresse(adresse);
        },
        surTitre: _etat.signalerTitrePage,
        surProgression: _etat.signalerProgression,
        surErreur: _etat.signalerErreurChargement,
      ),
    );
  }

  @override
  void dispose() {
    _etat.removeListener(_synchroniserAdresse);
    _champAdresse.dispose();
    _focusAdresse.dispose();
    super.dispose();
  }

  /// Recopie l'adresse affichée dans le champ, sauf pendant que le client
  /// y tape une autre adresse.
  void _synchroniserAdresse() {
    if (_focusAdresse.hasFocus) return;
    if (_champAdresse.text != _etat.adresse) {
      _champAdresse.text = _etat.adresse;
    }
  }

  void _surAdresse(String adresse) {
    unawaited(_etat.signalerAdresse(adresse));
    unawaited(_mettreAJourHistorique());
  }

  Future<void> _mettreAJourHistorique() async {
    final controleur = _controleur;
    if (controleur == null) return;
    try {
      final reculer = await controleur.peutReculer();
      final avancer = await controleur.peutAvancer();
      if (!mounted) return;
      _etat.signalerHistorique(peutReculer: reculer, peutAvancer: avancer);
    } catch (_) {
      // Vue web fermée entre-temps : les boutons restent tels quels.
    }
  }

  Future<void> _ouvrirSaisie(String texte) async {
    final adresse = EtatNavigateur.adresseDepuisSaisie(texte);
    if (adresse == null) {
      afficherMessage(
        context,
        Textes.adresseNavigateurInvalide,
        estErreur: true,
      );
      return;
    }
    _focusAdresse.unfocus();
    await _controleur?.charger(adresse);
  }

  Future<void> _enregistrer() async {
    final controleur = _controleur;
    if (controleur == null) return;
    final resultat = await _etat.enregistrerChapitre(controleur);
    if (!mounted) return;
    final refus = resultat.refus;
    final erreur = resultat.erreur;
    if (resultat.estReussi) {
      afficherMessage(context, Textes.chapitreWebEnregistre);
    } else if (refus != null) {
      afficherMessage(
        context,
        Textes.refusEnregistrementWeb(refus),
        estErreur: refus != RefusEnregistrementWeb.annule,
      );
    } else if (erreur != null) {
      afficherMessage(context, Textes.messageErreur(erreur), estErreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatNavigateur>();
    final controleur = _controleur;
    // Barre complète sur grand écran ; sous 600 px, recharger et « navigateur
    // externe » passent dans un menu pour laisser de la place à l'adresse.
    final estLarge =
        MediaQuery.sizeOf(context).width >= largeurMinNavigationLaterale;
    final boutonReculer = IconButton(
      tooltip: Textes.pagePrecedente,
      icon: const Icon(Icons.arrow_back),
      onPressed: controleur != null && etat.peutReculer
          ? () => controleur.reculer()
          : null,
    );
    final boutonAvancer = IconButton(
      tooltip: Textes.pageSuivante,
      icon: const Icon(Icons.arrow_forward),
      onPressed: controleur != null && etat.peutAvancer
          ? () => controleur.avancer()
          : null,
    );
    return PopScope(
      // Geste « retour » d'Android : page précédente du site d'abord ; la
      // croix de la barre ferme toujours le navigateur.
      canPop: !etat.peutReculer,
      onPopInvokedWithResult: (aFerme, _) {
        if (!aFerme) unawaited(_controleur?.reculer());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: Textes.fermerNavigateur,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleSpacing: 0,
          title: TextField(
            controller: _champAdresse,
            focusNode: _focusAdresse,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            maxLines: 1,
            decoration: const InputDecoration(
              hintText: Textes.champAdresse,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: _ouvrirSaisie,
          ),
          actions: <Widget>[
            boutonReculer,
            boutonAvancer,
            if (estLarge) ...<Widget>[
              IconButton(
                tooltip: Textes.rechargerPage,
                icon: const Icon(Icons.refresh),
                onPressed: controleur == null
                    ? null
                    : () => controleur.recharger(),
              ),
              IconButton(
                tooltip: Textes.ouvrirNavigateurExterne,
                icon: const Icon(Icons.open_in_new),
                onPressed: () => ouvrirLienExterne(context, etat.adresse),
              ),
            ] else
              PopupMenuButton<_ActionNavigateur>(
                tooltip: Textes.autresActions,
                onSelected: (action) {
                  switch (action) {
                    case _ActionNavigateur.recharger:
                      unawaited(controleur?.recharger());
                    case _ActionNavigateur.externe:
                      unawaited(ouvrirLienExterne(context, etat.adresse));
                  }
                },
                itemBuilder: (_) => const <PopupMenuEntry<_ActionNavigateur>>[
                  PopupMenuItem<_ActionNavigateur>(
                    value: _ActionNavigateur.recharger,
                    child: ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text(Textes.rechargerPage),
                    ),
                  ),
                  PopupMenuItem<_ActionNavigateur>(
                    value: _ActionNavigateur.externe,
                    child: ListTile(
                      leading: Icon(Icons.open_in_new),
                      title: Text(Textes.ouvrirNavigateurExterne),
                    ),
                  ),
                ],
              ),
          ],
          // Fine barre sous la barre d'adresse pendant le chargement : la
          // page reste visible et utilisable.
          bottom: etat.estEnChargement
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(hauteurBarreProgression),
                  child: LinearProgressIndicator(
                    value: etat.progression <= 0
                        ? null
                        : etat.progression / 100,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: _vueWeb),
            // Erreur de chargement par-dessus la vue web (gardée en dessous :
            // « Réessayer » recharge la même page).
            if (etat.erreurChargement case final description?)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: VueErreur(
                    message: Textes.erreurChargementPage(description),
                    surReessayer: () => _controleur?.recharger(),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _BarreChapitre(
          etat: etat,
          surEnregistrer: controleur == null ? null : _enregistrer,
        ),
      ),
    );
  }
}

/// Actions du menu « ⋮ » sur écran étroit.
enum _ActionNavigateur { recharger, externe }

/// Barre du bas : repère du chapitre affiché et « Enregistrer ce chapitre »,
/// ou progression de l'enregistrement avec « Annuler ».
class _BarreChapitre extends StatelessWidget {
  const _BarreChapitre({required this.etat, required this.surEnregistrer});

  final EtatNavigateur etat;
  final VoidCallback? surEnregistrer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapitre = etat.chapitre;
    final Widget contenu;
    if (etat.estEnEnregistrement) {
      final total = etat.pagesTotal;
      contenu = Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  total == 0
                      ? Textes.rechercheImagesPage
                      : Textes.progressionEnregistrementWeb(
                          etat.pagesFaites,
                          total,
                        ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: espacementPetit / 2),
                LinearProgressIndicator(
                  value: total == 0 ? null : etat.pagesFaites / total,
                ),
              ],
            ),
          ),
          const SizedBox(width: espacementPetit),
          TextButton(
            onPressed: etat.annulerEnregistrement,
            child: const Text(Textes.annuler),
          ),
        ],
      );
    } else {
      final reconnu = etat.chapitreReconnu;
      final String repere;
      if (chapitre != null) {
        repere = Textes.repereChapitreWeb(
          numero: chapitre.numero,
          nomTitre: etat.nomTitreChapitre,
          estLu: chapitre.estLu,
          estTelecharge: chapitre.estTelecharge,
        );
      } else if (reconnu != null) {
        // Chapitre reconnu, en cours d'enregistrement en base.
        repere = Textes.repereChapitreWeb(
          numero: reconnu.numero,
          nomTitre: etat.nomTitreChapitre,
          estLu: false,
        );
      } else {
        repere = Textes.pageNonReconnue;
      }
      // Texte et bouton dans un Wrap : sur téléphone, le bouton passe sous
      // le repère au lieu de l'écraser.
      contenu = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: espacementPetit,
        runSpacing: espacementPetit / 2,
        children: <Widget>[
          // Wrap borne chaque enfant à sa largeur : un long repère passe à
          // la ligne.
          Text(
            repere,
            style: chapitre == null
                ? theme.textTheme.bodySmall
                : theme.textTheme.titleSmall,
          ),
          // Grisé (avec l'explication à côté) quand la page n'est pas un
          // chapitre reconnu : choix le plus simple, pas de saisie du titre
          // et du numéro.
          FilledButton.icon(
            onPressed: etat.peutEnregistrer ? surEnregistrer : null,
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text(Textes.enregistrerCeChapitre),
          ),
        ],
      );
    }
    return SafeArea(
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: espacementMoyen,
            vertical: espacementPetit,
          ),
          child: contenu,
        ),
      ),
    );
  }
}
