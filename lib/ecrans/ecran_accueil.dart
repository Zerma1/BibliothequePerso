/// Écran racine : navigation entre la bibliothèque et les sources.
library;

import 'package:material_ui/material_ui.dart';

import '../widgets/constantes_interface.dart';
import '../widgets/textes.dart';
import 'ecran_bibliotheque.dart';
import 'ecran_sources.dart';

/// Écran racine avec la navigation principale.
///
/// Sous [largeurMinNavigationLaterale], une barre de navigation en bas (pouce
/// sur téléphone) ; au-delà, un `NavigationRail` sur le côté, qui laisse
/// toute la hauteur au contenu (PLAYBOOK.md section 8).
class EcranAccueil extends StatefulWidget {
  /// Crée l'écran.
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EtatEcranAccueil();
}

class _EtatEcranAccueil extends State<EcranAccueil> {
  int _indexOnglet = 0;

  static const List<_Onglet> _onglets = <_Onglet>[
    _Onglet(
      Textes.ongletBibliotheque,
      Icons.collections_bookmark_outlined,
      Icons.collections_bookmark,
    ),
    _Onglet(Textes.ongletSources, Icons.public_outlined, Icons.public),
  ];

  /// Clé globale du contenu : au passage du seuil de largeur, les onglets
  /// gardent leur état (recherche saisie, défilement) au lieu d'être
  /// recréés.
  final GlobalKey _cleContenu = GlobalKey(debugLabel: 'contenuAccueil');

  void _choisirOnglet(int index) => setState(() => _indexOnglet = index);

  @override
  Widget build(BuildContext context) {
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
                  destinations: <NavigationRailDestination>[
                    for (final onglet in _onglets)
                      NavigationRailDestination(
                        icon: Icon(onglet.icone),
                        selectedIcon: Icon(onglet.iconeChoisie),
                        label: Text(onglet.libelle),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
              ],
              Expanded(
                child: IndexedStack(
                  key: _cleContenu,
                  index: _indexOnglet,
                  children: const <Widget>[EcranBibliotheque(), EcranSources()],
                ),
              ),
            ],
          ),
          bottomNavigationBar: estLarge
              ? null
              : NavigationBar(
                  selectedIndex: _indexOnglet,
                  onDestinationSelected: _choisirOnglet,
                  destinations: <Widget>[
                    for (final onglet in _onglets)
                      NavigationDestination(
                        icon: Icon(onglet.icone),
                        selectedIcon: Icon(onglet.iconeChoisie),
                        label: onglet.libelle,
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
