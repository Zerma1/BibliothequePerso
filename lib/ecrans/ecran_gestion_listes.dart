/// Écran « Gérer les listes » (tâche X4) : ordre des listes par
/// glisser-déposer, création, renommage et suppression des listes
/// personnelles.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_bibliotheque.dart';
import '../modeles/liste_lecture.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/dialogues_listes.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';

/// Actions du menu d'une liste.
enum _ActionListe { renommer, supprimer }

/// Toutes les listes, dans l'ordre des puces de la bibliothèque : chacune
/// se déplace par sa poignée ; les listes personnelles se renomment et se
/// suppriment depuis leur menu.
class EcranGestionListes extends StatelessWidget {
  /// Crée l'écran.
  const EcranGestionListes({super.key});

  /// Ouvre l'écran par-dessus l'écran courant.
  static Future<void> ouvrir(BuildContext context) => Navigator.of(context)
      .push<void>(
        MaterialPageRoute<void>(builder: (_) => const EcranGestionListes()),
      );

  Future<void> _deplacer(
    BuildContext context,
    EtatBibliotheque etat,
    int ancienIndex,
    int nouvelIndex,
  ) async {
    final ids = <int>[for (final liste in etat.listes) ?liste.id];
    // `onReorderItem` donne l'index d'arrivée une fois l'élément retiré.
    final id = ids.removeAt(ancienIndex);
    ids.insert(nouvelIndex, id);
    final resultat = await etat.reordonnerListes(ids);
    if (context.mounted) afficherResultat(context, resultat);
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatBibliotheque>();
    return Scaffold(
      appBar: AppBar(title: const Text(Textes.gererListes)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => creerListeAvecDialogue(context, etat),
        icon: const Icon(Icons.playlist_add),
        label: const Text(Textes.nouvelleListe),
      ),
      // Colonne centrée de largeur plafonnée : sur grand écran, une liste
      // étirée sur toute la largeur éloignerait la poignée du nom.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: _contenu(context, etat),
        ),
      ),
    );
  }

  Widget _contenu(BuildContext context, EtatBibliotheque etat) {
    final erreur = etat.erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    }
    if (!etat.estCharge) return const VueChargement();
    final listes = etat.listes;
    if (listes.isEmpty) {
      return const VueVide(
        message: Textes.aucuneListe,
        icone: Icons.playlist_remove,
      );
    }
    return ReorderableListView.builder(
      // Poignées explicites à gauche : le geste est le même à la souris et
      // au doigt, et le menu de la liste garde sa place à droite.
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.all(espacementMoyen),
        child: Text(
          Textes.aideGestionListes,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      padding: const EdgeInsets.only(bottom: margeBasBoutonFlottant),
      itemCount: listes.length,
      onReorderItem: (ancien, nouveau) =>
          _deplacer(context, etat, ancien, nouveau),
      itemBuilder: (context, index) {
        final liste = listes[index];
        return _LigneListe(
          key: ValueKey<int?>(liste.id),
          etat: etat,
          liste: liste,
          index: index,
        );
      },
    );
  }
}

/// Une liste : poignée, nom, mention « liste de l'application », menu.
class _LigneListe extends StatelessWidget {
  const _LigneListe({
    super.key,
    required this.etat,
    required this.liste,
    required this.index,
  });

  final EtatBibliotheque etat;
  final ListeLecture liste;
  final int index;

  @override
  Widget build(BuildContext context) {
    final modifiable = etat.estListeModifiable(liste);
    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        // Info-bulle au survol seulement : au doigt, l'appui long de
        // l'info-bulle gênerait le glisser.
        child: const Tooltip(
          message: Textes.deplacerListe,
          triggerMode: TooltipTriggerMode.manual,
          child: Icon(Icons.drag_handle),
        ),
      ),
      title: Text(liste.nom),
      subtitle: modifiable ? null : const Text(Textes.listeSysteme),
      // Menu présent même pour une liste système, avec ses actions
      // grisées : le client voit pourquoi il ne peut pas la renommer.
      trailing: PopupMenuButton<_ActionListe>(
        tooltip: Textes.actionsListe,
        onSelected: (action) {
          switch (action) {
            case _ActionListe.renommer:
              renommerListeAvecDialogue(context, etat, liste);
            case _ActionListe.supprimer:
              supprimerListeAvecConfirmation(context, etat, liste);
          }
        },
        itemBuilder: (_) => <PopupMenuEntry<_ActionListe>>[
          PopupMenuItem<_ActionListe>(
            value: _ActionListe.renommer,
            enabled: modifiable,
            child: const Text(Textes.renommerListe),
          ),
          PopupMenuItem<_ActionListe>(
            value: _ActionListe.supprimer,
            enabled: modifiable,
            child: const Text(Textes.supprimerListe),
          ),
        ],
      ),
    );
  }
}
