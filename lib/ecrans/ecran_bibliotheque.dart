/// Écran Bibliothèque : grille des titres, filtres et ajout d'un titre.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_bibliotheque.dart';
import '../etat/etat_mises_a_jour.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/titre.dart';
import '../widgets/bouton_recherche_mises_a_jour.dart';
import '../widgets/carte_titre.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/dialogue_ajout_titre.dart';
import '../widgets/dialogues_listes.dart';
import '../widgets/messages.dart';
import '../widgets/panneau_filtres.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';
import 'ecran_gestion_listes.dart';
import 'ecran_titre.dart';

/// Grille des couvertures de la bibliothèque, avec recherche et filtres par
/// liste et par catégorie.
class EcranBibliotheque extends StatefulWidget {
  /// Crée l'écran.
  const EcranBibliotheque({super.key});

  @override
  State<EcranBibliotheque> createState() => _EtatEcranBibliotheque();
}

class _EtatEcranBibliotheque extends State<EcranBibliotheque> {
  // Initialisé avec la recherche de l'état : si l'écran est reconstruit, le
  // champ affiche toujours le filtre réellement appliqué.
  late final TextEditingController _recherche = TextEditingController(
    text: context.read<EtatBibliotheque>().recherche,
  );

  /// Gardé pour se désabonner dans [dispose], où `context.read` n'est plus
  /// sûr.
  late final EtatMisesAJour _misesAJour;

  @override
  void initState() {
    super.initState();
    // L'écran reste monté (IndexedStack, routes empilées par-dessus) : il
    // reçoit aussi les fins de vérifications automatiques.
    _misesAJour = context.read<EtatMisesAJour>();
    _misesAJour.finVerification.addListener(_surFinVerification);
  }

  @override
  void dispose() {
    _misesAJour.finVerification.removeListener(_surFinVerification);
    _recherche.dispose();
    super.dispose();
  }

  /// Fin d'une recherche de nouveaux chapitres : recharge la grille (badges
  /// des non-lus) s'il y a des nouveautés, et affiche le bilan.
  void _surFinVerification() {
    final fin = _misesAJour.finVerification.value;
    if (fin == null || !mounted) {
      return;
    }
    if (fin.aDesNouveautes) {
      context.read<EtatBibliotheque>().charger();
    }
    // Une vérification automatique sans nouveauté reste silencieuse : un
    // message toutes les six heures pour dire « rien » serait du bruit.
    if (!fin.estManuelle && !fin.aDesNouveautes) {
      return;
    }
    final erreur = fin.erreur;
    afficherMessage(
      context,
      erreur != null
          ? Textes.messageErreur(erreur)
          : Textes.bilanMisesAJour(
              nombreChapitres: fin.nombreNouveauxChapitres,
              nombreTitres: fin.nombreTitresAvecNouveautes,
              nombreSitesEnEchec: fin.nombreSitesEnEchec,
              nombreAutresEchecs: fin.nombreAutresEchecs,
            ),
    );
  }

  Future<void> _ajouterTitre() async {
    final issue = await afficherDialogueAjoutTitre(context);
    if (issue == null || !mounted) return;
    afficherMessage(context, issue.message);
    final idTitre = issue.idTitreAOuvrir;
    if (idTitre != null) await _ouvrirFiche(idTitre);
  }

  Future<void> _ouvrirTitre(Titre titre) async {
    final idTitre = titre.id;
    if (idTitre == null) {
      return;
    }
    await _ouvrirFiche(idTitre);
  }

  Future<void> _ouvrirFiche(int idTitre) async {
    final etat = context.read<EtatBibliotheque>();
    await EcranTitre.ouvrir(context, idTitre);
    // Au retour, les compteurs de non-lus et les listes ont pu changer.
    await etat.charger();
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatBibliotheque>();
    return Scaffold(
      appBar: AppBar(
        title: const Text(Textes.ongletBibliotheque),
        actions: <Widget>[
          const BoutonRechercheMisesAJour(),
          IconButton(
            tooltip: Textes.actualiser,
            icon: const Icon(Icons.refresh),
            onPressed: etat.estEnChargement ? null : etat.charger,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ajouterTitre,
        icon: const Icon(Icons.add),
        label: const Text(Textes.boutonAjouterTitre),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              espacementMoyen,
              espacementPetit,
              espacementMoyen,
              0,
            ),
            child: TextField(
              controller: _recherche,
              onChanged: etat.modifierRecherche,
              decoration: InputDecoration(
                hintText: Textes.champRecherche,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: etat.recherche.isEmpty
                    ? null
                    : IconButton(
                        tooltip: Textes.annuler,
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _recherche.clear();
                          etat.modifierRecherche('', immediat: true);
                        },
                      ),
              ),
            ),
          ),
          _BarreFiltres(etat: etat),
          // Barre fine plutôt qu'un indicateur plein écran quand des titres
          // sont déjà affichés : la grille ne clignote pas à chaque frappe.
          if (etat.estEnChargement && etat.estCharge)
            const LinearProgressIndicator()
          else
            const SizedBox(height: hauteurBarreProgression),
          Expanded(child: _contenu(etat)),
        ],
      ),
    );
  }

  Widget _contenu(EtatBibliotheque etat) {
    final erreur = etat.erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    }
    if (!etat.estCharge) {
      return const VueChargement();
    }
    if (etat.titres.isEmpty) {
      if (etat.aUnFiltre) {
        return const VueVide(
          message: Textes.aucunResultat,
          icone: Icons.search_off,
        );
      }
      // Pas de second bouton « Ajouter un titre » au centre : le bouton
      // flottant, toujours au même endroit, suffit (retour du client).
      return const VueVide(
        message: Textes.bibliothequeVide,
        icone: Icons.collections_bookmark_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: etat.charger,
      // Grille à largeur de carte maximale : le nombre de colonnes suit la
      // largeur de la fenêtre (2 sur téléphone, 6 ou plus sur grand écran)
      // sans seuil codé en dur.
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          espacementMoyen,
          espacementPetit,
          espacementMoyen,
          margeBasBoutonFlottant,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: largeurMaxCarteTitre,
          childAspectRatio: rapportCarteTitre,
          crossAxisSpacing: espacementPetit,
          mainAxisSpacing: espacementPetit,
        ),
        itemCount: etat.titres.length,
        itemBuilder: (context, index) {
          final titre = etat.titres[index];
          return CarteTitre(
            key: ValueKey<int?>(titre.id),
            titre: titre,
            surAppui: () => _ouvrirTitre(titre),
          );
        },
      ),
    );
  }
}

/// Filtres de la bibliothèque : une ligne de puces pour les listes (peu
/// nombreuses), puis la ligne des catégories, réduite à « Toutes les
/// catégories » et un entonnoir (retour du client : la rangée de toutes les
/// catégories débordait), suivie du filtre de niveau de contenu.
class _BarreFiltres extends StatelessWidget {
  const _BarreFiltres({required this.etat});

  final EtatBibliotheque etat;

  @override
  Widget build(BuildContext context) {
    final nombreFiltres = etat.nombreFiltresCategories;
    final couleurs = Theme.of(context).colorScheme;
    // Défilement horizontal pour les listes : sur téléphone, les puces
    // dépassent vite la largeur ; une ligne qui défile garde la grille
    // visible.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LignePuces(
          puces: <Widget>[
            FilterChip(
              label: const Text(Textes.toutesLesListes),
              selected: etat.idListeChoisie == null,
              onSelected: (_) => etat.choisirListe(null),
            ),
            for (final liste in etat.listes)
              etat.estListeAutomatique(liste)
                  // La liste automatique s'explique d'elle-même au survol
                  // ou à l'appui long (info-bulle) : elle n'a pas de menu,
                  // dont l'appui long entrerait en conflit avec l'info-bulle.
                  ? FilterChip(
                      label: Text(liste.nom),
                      tooltip: Textes.listeAutomatique,
                      avatar: const Icon(Icons.hourglass_empty),
                      selected: etat.idListeChoisie == liste.id,
                      onSelected: (choisie) =>
                          etat.choisirListe(choisie ? liste.id : null),
                    )
                  // Appui long (téléphone) ou clic droit (ordinateur) :
                  // menu de la liste (renommer, supprimer, gérer).
                  : GestureDetector(
                      onLongPressStart: (details) => _afficherMenuListe(
                        context,
                        etat,
                        liste,
                        details.globalPosition,
                      ),
                      onSecondaryTapUp: (details) => _afficherMenuListe(
                        context,
                        etat,
                        liste,
                        details.globalPosition,
                      ),
                      child: FilterChip(
                        label: Text(liste.nom),
                        selected: etat.idListeChoisie == liste.id,
                        onSelected: (choisie) =>
                            etat.choisirListe(choisie ? liste.id : null),
                      ),
                    ),
            // Création et gestion au bout de la ligne des listes : le
            // client les trouve là où il voit ses listes.
            IconButton(
              tooltip: Textes.nouvelleListe,
              icon: const Icon(Icons.add),
              onPressed: () => creerListeAvecDialogue(context, etat),
            ),
            IconButton(
              tooltip: Textes.gererListes,
              icon: const Icon(Icons.edit_note),
              onPressed: () => EcranGestionListes.ouvrir(context),
            ),
          ],
        ),
        _LignePuces(
          puces: <Widget>[
            FilterChip(
              label: const Text(Textes.toutesLesCategories),
              selected: nombreFiltres == 0,
              onSelected: (_) => etat.effacerFiltreCategories(),
            ),
            // Entonnoir : ouvre la fenêtre de toutes les catégories ; le
            // badge rappelle combien sont incluses ou exclues.
            IconButton(
              tooltip: nombreFiltres == 0
                  ? Textes.filtrerParCategories
                  : Textes.filtreCategoriesActif(nombreFiltres),
              isSelected: nombreFiltres > 0,
              icon: const Icon(Icons.filter_alt_outlined),
              selectedIcon: Badge.count(
                count: nombreFiltres,
                child: Icon(Icons.filter_alt, color: couleurs.primary),
              ),
              onPressed: () => afficherPanneauCategories(context),
            ),
            if (etat.gereNiveauxContenu)
              FilterChip(
                avatar: const Icon(Icons.shield_outlined),
                label: const Text(Textes.boutonContenu),
                // Mis en avant seulement s'il diffère du réglage par
                // défaut : le client voit qu'un filtre inhabituel est actif.
                selected: !etat.estNiveauxParDefaut,
                showCheckmark: false,
                onSelected: (_) => afficherPanneauNiveaux(context),
              ),
          ],
        ),
      ],
    );
  }
}

/// Actions du menu d'une puce de liste.
enum _ActionPuceListe { renommer, supprimer, gerer }

/// Menu d'une liste, ouvert à [position] (appui long ou clic droit sur sa
/// puce). Pour une liste système, « Renommer » et « Supprimer » sont grisés
/// et une ligne explique pourquoi.
Future<void> _afficherMenuListe(
  BuildContext context,
  EtatBibliotheque etat,
  ListeLecture liste,
  Offset position,
) async {
  final modifiable = etat.estListeModifiable(liste);
  final cadre = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final action = await showMenu<_ActionPuceListe>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & cadre.size,
    ),
    items: <PopupMenuEntry<_ActionPuceListe>>[
      PopupMenuItem<_ActionPuceListe>(
        value: _ActionPuceListe.renommer,
        enabled: modifiable,
        child: const Text(Textes.renommerListe),
      ),
      PopupMenuItem<_ActionPuceListe>(
        value: _ActionPuceListe.supprimer,
        enabled: modifiable,
        child: const Text(Textes.supprimerListe),
      ),
      if (!modifiable)
        const PopupMenuItem<_ActionPuceListe>(
          enabled: false,
          child: Text(Textes.listeSysteme),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<_ActionPuceListe>(
        value: _ActionPuceListe.gerer,
        child: Text(Textes.gererListes),
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _ActionPuceListe.renommer:
      await renommerListeAvecDialogue(context, etat, liste);
    case _ActionPuceListe.supprimer:
      await supprimerListeAvecConfirmation(context, etat, liste);
    case _ActionPuceListe.gerer:
      await EcranGestionListes.ouvrir(context);
  }
}

/// Ligne de puces qui défile horizontalement.
class _LignePuces extends StatelessWidget {
  const _LignePuces({required this.puces});

  final List<Widget> puces;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: espacementMoyen,
        vertical: espacementPetit / 2,
      ),
      child: Row(
        children: <Widget>[
          for (final puce in puces)
            Padding(
              padding: const EdgeInsets.only(right: espacementPetit),
              child: puce,
            ),
        ],
      ),
    );
  }
}
