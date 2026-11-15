/// Écran racine : navigation entre la bibliothèque, les sources, les
/// téléchargements et les paramètres.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_telechargements.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/textes.dart';
import 'ecran_bibliotheque.dart';
import 'ecran_parametres.dart';
import 'ecran_sources.dart';
import 'ecran_telechargements.dart';

/// Écran racine avec la navigation principale.
///
/// Sous [largeurMinNavigationLaterale], une barre de navigation en bas (pouce
/// sur téléphone) ; au-delà, un `NavigationRail` sur le côté, qui laisse
/// toute la hauteur au contenu (PLAYBOOK.md section 8). Le numéro de version
/// est rappelé en petit sous le rail ou au-dessus de la barre.
class EcranAccueil extends StatefulWidget {
  /// Crée l'écran.
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EtatEcranAccueil();
}

class _EtatEcranAccueil extends State<EcranAccueil> {
  int _indexOnglet = 0;

  /// Index de l'onglet Téléchargements (badge du nombre en cours).
  static const int _indexTelechargements = 2;

  static const List<_Onglet> _onglets = <_Onglet>[
    _Onglet(
      Textes.ongletBibliotheque,
      Icons.collections_bookmark_outlined,
      Icons.collections_bookmark,
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

  void _choisirOnglet(int index) => setState(() => _indexOnglet = index);

  /// Icône d'un onglet ; celle des téléchargements porte un badge avec le
  /// nombre de chapitres en attente ou en cours.
  Widget _icone(int index, IconData icone, int nombreActifs) {
    if (index != _indexTelechargements || nombreActifs == 0) {
      return Icon(icone);
    }
    return Semantics(
      label: Textes.telechargementsActifs(nombreActifs),
      child: Badge.count(count: nombreActifs, child: Icon(icone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreActifs = context.select<EtatTelechargements, int>(
      (etat) => etat.nombreActifs,
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
          body: Row(
            children: <Widget>[
              if (estLarge) ...<Widget>[
                NavigationRail(
                  selectedIndex: _indexOnglet,
                  onDestinationSelected: _choisirOnglet,
                  labelType: NavigationRailLabelType.all,
                  trailing: Padding(
                    padding: const EdgeInsets.only(top: espacementMoyen),
                    child: version,
                  ),
                  destinations: <NavigationRailDestination>[
                    for (var i = 0; i < _onglets.length; i++)
                      NavigationRailDestination(
                        icon: _icone(i, _onglets[i].icone, nombreActifs),
                        selectedIcon: _icone(
                          i,
                          _onglets[i].iconeChoisie,
                          nombreActifs,
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
                    EcranSources(),
                    EcranTelechargements(),
                    EcranParametres(),
                  ],
                ),
              ),
            ],
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
                            icon: _icone(i, _onglets[i].icone, nombreActifs),
                            selectedIcon: _icone(
                              i,
                              _onglets[i].iconeChoisie,
                              nombreActifs,
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
