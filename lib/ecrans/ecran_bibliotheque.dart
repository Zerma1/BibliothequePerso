/// Écran Bibliothèque : grille des titres, filtres et ajout d'un titre.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_bibliotheque.dart';
import '../modeles/titre.dart';
import '../widgets/carte_titre.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/dialogue_ajout_titre.dart';
import '../widgets/messages.dart';
import '../widgets/pastille_categorie.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';
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

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _ajouterTitre() async {
    final message = await afficherDialogueAjoutTitre(context);
    if (message != null && mounted) {
      afficherMessage(context, message);
    }
  }

  Future<void> _ouvrirTitre(Titre titre) async {
    final idTitre = titre.id;
    if (idTitre == null) {
      return;
    }
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
      return VueVide(
        message: Textes.bibliothequeVide,
        icone: Icons.collections_bookmark_outlined,
        action: FilledButton.icon(
          onPressed: _ajouterTitre,
          icon: const Icon(Icons.add),
          label: const Text(Textes.boutonAjouterTitre),
        ),
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
            referer: etat.refererPour(titre),
            surAppui: () => _ouvrirTitre(titre),
          );
        },
      ),
    );
  }
}

/// Puces de filtre par liste et par catégorie.
class _BarreFiltres extends StatelessWidget {
  const _BarreFiltres({required this.etat});

  final EtatBibliotheque etat;

  @override
  Widget build(BuildContext context) {
    // Défilement horizontal : le nombre de listes et surtout de catégories
    // (une dizaine par titre MangaDex) dépasse vite la largeur d'un
    // téléphone ; une ligne qui défile garde la grille visible.
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
              FilterChip(
                label: Text(liste.nom),
                selected: etat.idListeChoisie == liste.id,
                onSelected: (choisie) =>
                    etat.choisirListe(choisie ? liste.id : null),
              ),
          ],
        ),
        if (etat.categories.isNotEmpty)
          _LignePuces(
            puces: <Widget>[
              FilterChip(
                label: const Text(Textes.toutesLesCategories),
                selected: etat.idCategorieChoisie == null,
                onSelected: (_) => etat.choisirCategorie(null),
              ),
              for (final categorie in etat.categories)
                PastilleCategorie(
                  nom: categorie.nom,
                  estChoisie: etat.idCategorieChoisie == categorie.id,
                  surSelection: (choisie) =>
                      etat.choisirCategorie(choisie ? categorie.id : null),
                ),
            ],
          ),
      ],
    );
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
