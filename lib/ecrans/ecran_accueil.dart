/// Écran racine : navigation entre la bibliothèque, les sources, les
/// téléchargements et les paramètres.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_dossier_chapitres.dart';
import '../etat/etat_mises_a_jour.dart';
import '../etat/etat_parutions.dart';
import '../etat/etat_telechargements.dart';
import '../etat/journal_interface.dart';
import '../widgets/bandeaux_dossier_chapitres.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/textes.dart';
import 'ecran_bibliotheque.dart';
import 'ecran_mises_a_jour.dart';
import 'ecran_parametres.dart';
import 'ecran_sources.dart';
import 'ecran_telechargements.dart';

/// Écran racine avec la navigation principale.
///
/// Sous [largeurMinNavigationLaterale], une barre de navigation en bas (pouce
/// sur téléphone) ; au-delà, un `NavigationRail` sur le côté, qui laisse
/// toute la hauteur au contenu (PLAYBOOK.md section 8). Le numéro de version
/// est rappelé en petit tout en bas : au pied du rail, ou juste au-dessus de
/// la barre du bas.
class EcranAccueil extends StatefulWidget {
  /// Crée l'écran.
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EtatEcranAccueil();
}

class _EtatEcranAccueil extends State<EcranAccueil> {
  int _indexOnglet = 0;

  /// Index de l'onglet Mises à jour (badge des titres avec un chapitre non
  /// lu).
  static const int _indexMisesAJour = 1;

  /// Index de l'onglet Téléchargements (badge du nombre en cours).
  static const int _indexTelechargements = 3;

  static const List<_Onglet> _onglets = <_Onglet>[
    _Onglet(
      Textes.ongletBibliotheque,
      Icons.collections_bookmark_outlined,
      Icons.collections_bookmark,
    ),
    // Juste après la bibliothèque : c'est l'écran que le client consulte
    // le plus souvent après elle (retour du 2026-11-15).
    _Onglet(
      Textes.ongletMisesAJour,
      Icons.new_releases_outlined,
      Icons.new_releases,
    ),
    _Onglet(Textes.ongletSources, Icons.public_outlined, Icons.public),
    _Onglet(
      Textes.ongletTelechargements,
      Icons.download_for_offline_outlined,
      Icons.download_for_offline,
    ),
    _Onglet(Textes.ongletParametres, Icons.settings_outlined, Icons.settings),
  ];

  /// Clé globale du contenu : au passage du seuil de largeur, les onglets
  /// gardent leur état (recherche saisie, défilement) au lieu d'être
  /// recréés.
  final GlobalKey _cleContenu = GlobalKey(debugLabel: 'contenuAccueil');

  /// Retour de l'application au premier plan (réveil de l'ordinateur,
  /// fenêtre réactivée, application Android rouverte) : une échéance de
  /// recherche des nouveaux chapitres ou de suppression prévue a pu passer
  /// pendant la veille, que les minuteurs n'ont pas comptée.
  late final AppLifecycleListener _cycleDeVie;

  @override
  void initState() {
    super.initState();
    _cycleDeVie = AppLifecycleListener(
      onResume: () {
        if (!mounted) return;
        context.read<EtatMisesAJour>().controlerEcheance();
        context.read<EtatTelechargements>().controlerSuppressionsEchues();
        // Le NAS a pu être rallumé (ou éteint) pendant la veille : le
        // bandeau suit tout de suite. Absent dans les tests sans service.
        context.read<EtatDossierChapitres?>()?.verifierAcces();
      },
    );
  }

  @override
  void dispose() {
    _cycleDeVie.dispose();
    super.dispose();
  }

  void _choisirOnglet(int index) {
    if (index == _indexMisesAJour && index != _indexOnglet) {
      // Des chapitres ont pu être lus depuis la bibliothèque : la liste et
      // ses badges « Nouveau » sont relus (base seulement, sans réseau).
      context.read<EtatParutions>().charger();
    }
    if (index != _indexOnglet) {
      // Le journal garde le fil de la navigation : utile pour relire un
      // retour de test (« l'erreur est arrivée en ouvrant tel onglet »).
      noterActionInterface('Onglet « ${_onglets[index].libelle} » ouvert');
    }
    setState(() => _indexOnglet = index);
  }

  /// Icône d'un onglet ; celle des mises à jour porte le nombre de titres
  /// avec un chapitre non lu, celle des téléchargements le nombre de
  /// chapitres en attente ou en cours.
  Widget _icone(int index, IconData icone, int nombreActifs, int nouveautes) {
    if (index == _indexTelechargements && nombreActifs > 0) {
      return Semantics(
        label: Textes.telechargementsActifs(nombreActifs),
        child: Badge.count(count: nombreActifs, child: Icon(icone)),
      );
    }
    if (index == _indexMisesAJour && nouveautes > 0) {
      return Semantics(
        label: Textes.titresAvecNouveaute(nouveautes),
        child: Badge.count(count: nouveautes, child: Icon(icone)),
      );
    }
    return Icon(icone);
  }

  @override
  Widget build(BuildContext context) {
    final nombreActifs = context.select<EtatTelechargements, int>(
      (etat) => etat.nombreActifs,
    );
    final nouveautes = context.select<EtatParutions, int>(
      (etat) => etat.nombreNouveautes,
    );
    final theme = Theme.of(context);
    final version = Text(
      Textes.versionCourte(versionApplication),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
    return LayoutBuilder(
      builder: (context, contraintes) {
        final estLarge = contraintes.maxWidth >= largeurMinNavigationLaterale;
        // Structure identique dans les deux dispositions (Scaffold > Row >
        // Expanded) : seuls le rail et la barre du bas apparaissent ou
        // disparaissent. IndexedStack garde chaque onglet en vie lors d'un
        // changement d'onglet.
        return Scaffold(
          // Bandeaux du dossier des chapitres (NAS inaccessible, redémarrage
          // nécessaire) en haut, sur toute la largeur : visibles quel que
          // soit l'onglet.
          body: ZoneBandeauxDossierChapitres(
            child: Row(
              children: <Widget>[
                if (estLarge) ...<Widget>[
                  NavigationRail(
                    selectedIndex: _indexOnglet,
                    onDestinationSelected: _choisirOnglet,
                    labelType: NavigationRailLabelType.all,
                    // Version épinglée en bas de la colonne (retour du client
                    // sur la 0.2.0-test) : elle ne se confond plus avec les
                    // onglets. Les onglets défilent si la fenêtre est très
                    // basse, la version reste visible.
                    trailingAtBottom: true,
                    scrollable: true,
                    trailing: Padding(
                      padding: const EdgeInsets.only(bottom: espacementMoyen),
                      child: version,
                    ),
                    destinations: <NavigationRailDestination>[
                      for (var i = 0; i < _onglets.length; i++)
                        NavigationRailDestination(
                          icon: _icone(
                            i,
                            _onglets[i].icone,
                            nombreActifs,
                            nouveautes,
                          ),
                          selectedIcon: _icone(
                            i,
                            _onglets[i].iconeChoisie,
                            nombreActifs,
                            nouveautes,
                          ),
                          label: Text(_onglets[i].libelle),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                ],
                Expanded(
                  child: IndexedStack(
                    key: _cleContenu,
                    index: _indexOnglet,
                    children: const <Widget>[
                      EcranBibliotheque(),
                      EcranMisesAJour(),
                      EcranSources(),
                      EcranTelechargements(),
                      EcranParametres(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: estLarge
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Version en petit juste au-dessus de la barre, sur la
                    // même couleur de fond : elle ne prend qu'une ligne.
                    ColoredBox(
                      color: theme.colorScheme.surfaceContainer,
                      child: SizedBox(
                        width: double.infinity,
                        child: Center(child: version),
                      ),
                    ),
                    NavigationBar(
                      selectedIndex: _indexOnglet,
                      onDestinationSelected: _choisirOnglet,
                      destinations: <Widget>[
                        for (var i = 0; i < _onglets.length; i++)
                          NavigationDestination(
                            icon: _icone(
                              i,
                              _onglets[i].icone,
                              nombreActifs,
                              nouveautes,
                            ),
                            selectedIcon: _icone(
                              i,
                              _onglets[i].iconeChoisie,
                              nombreActifs,
                              nouveautes,
                            ),
                            label: _onglets[i].libelle,
                          ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Description d'un onglet de navigation.
class _Onglet {
  const _Onglet(this.libelle, this.icone, this.iconeChoisie);

  final String libelle;
  final IconData icone;
  final IconData iconeChoisie;
}
