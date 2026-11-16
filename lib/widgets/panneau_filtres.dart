/// Panneaux de filtre de la bibliothèque : catégories (pensé pour des
/// centaines de tags) et niveau de contenu (tâche IN2 de l'étape 6).
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_bibliotheque.dart';
import '../modeles/constantes.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'pastille_categorie.dart';
import 'textes.dart';

/// Ouvre [contenu] en feuille du bas sur téléphone (le pouce l'atteint et
/// la grille reste devinée derrière), en dialogue centré sur grand écran
/// (une feuille étirée sur toute la largeur serait peu lisible).
Future<void> _ouvrirPanneau(BuildContext context, Widget contenu) {
  final taille = MediaQuery.sizeOf(context);
  if (taille.width < largeurMinNavigationLaterale) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: taille.height * fractionHauteurPanneau,
      ),
      builder: (_) => contenu,
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: largeurMaxFormulaire,
          maxHeight: taille.height * fractionHauteurPanneau,
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: espacementMoyen),
          child: contenu,
        ),
      ),
    ),
  );
}

/// Ouvre le panneau des catégories de la bibliothèque.
Future<void> afficherPanneauCategories(BuildContext context) =>
    _ouvrirPanneau(context, const PanneauCategories());

/// Ouvre le panneau des niveaux de contenu de la bibliothèque.
Future<void> afficherPanneauNiveaux(BuildContext context) =>
    _ouvrirPanneau(context, const PanneauNiveauxContenu());

/// Choix des catégories de la bibliothèque (demande du client) : toutes les
/// catégories, avec recherche et défilement, regroupées par initiale ;
/// chaque catégorie a trois états (neutre, incluse, exclue). Le choix est un
/// brouillon appliqué par « Appliquer » : la bibliothèque n'est relue qu'une
/// fois.
///
/// Filtre appliqué : les titres qui ont toutes les catégories incluses et
/// aucune des catégories exclues.
class PanneauCategories extends StatefulWidget {
  /// Crée le panneau (lit `EtatBibliotheque`).
  const PanneauCategories({super.key});

  @override
  State<PanneauCategories> createState() => _EtatPanneauCategories();
}

class _EtatPanneauCategories extends State<PanneauCategories> {
  final TextEditingController _recherche = TextEditingController();

  /// Brouillon : catégories incluses et exclues, initialisées avec le
  /// filtre en cours.
  late final Set<int> _incluses = <int>{
    ...context.read<EtatBibliotheque>().idsCategoriesChoisies,
  };
  late final Set<int> _exclues = <int>{
    ...context.read<EtatBibliotheque>().idsCategoriesExclues,
  };

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  EtatFiltreCategorie _etat(int id) {
    if (_incluses.contains(id)) return EtatFiltreCategorie.incluse;
    if (_exclues.contains(id)) return EtatFiltreCategorie.exclue;
    return EtatFiltreCategorie.neutre;
  }

  /// Un appui fait passer la catégorie de neutre à incluse, puis exclue,
  /// puis de nouveau neutre.
  void _basculer(int id) {
    setState(() {
      switch (_etat(id)) {
        case EtatFiltreCategorie.neutre:
          _incluses.add(id);
        case EtatFiltreCategorie.incluse:
          _incluses.remove(id);
          _exclues.add(id);
        case EtatFiltreCategorie.exclue:
          _exclues.remove(id);
      }
    });
  }

  Future<void> _appliquer(EtatBibliotheque etat) async {
    Navigator.of(context).pop();
    await etat.appliquerFiltreCategories(
      incluses: Set<int>.of(_incluses),
      exclues: Set<int>.of(_exclues),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatBibliotheque>();
    final theme = Theme.of(context);
    final groupes = etat.grouperCategories(_recherche.text);
    final enRecherche = _recherche.text.trim().isNotEmpty;
    final aUnChoix = _incluses.isNotEmpty || _exclues.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: espacementMoyen),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(Textes.filtrerParCategories, style: theme.textTheme.titleLarge),
          const SizedBox(height: espacementPetit / 2),
          Text(Textes.aideTroisEtats, style: theme.textTheme.bodySmall),
          const SizedBox(height: espacementPetit),
          TextField(
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: Textes.rechercherCategorie,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: enRecherche
                  ? IconButton(
                      tooltip: Textes.annuler,
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_recherche.clear),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: espacementPetit),
          // Seule la liste défile : la recherche et les boutons restent
          // visibles même avec des centaines de catégories.
          Flexible(
            child: _ListeCategories(
              etat: etat,
              groupes: groupes,
              etatDe: _etat,
              surAppui: _basculer,
            ),
          ),
          const SizedBox(height: espacementPetit),
          Text(
            Textes.resumeFiltreCategories(_incluses.length, _exclues.length),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: espacementPetit),
          // Boutons qui passent à la ligne sur un écran étroit.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: espacementPetit,
            runSpacing: espacementPetit,
            children: <Widget>[
              TextButton(
                onPressed: aUnChoix
                    ? () => setState(() {
                        _incluses.clear();
                        _exclues.clear();
                      })
                    : null,
                child: const Text(Textes.effacerCategories),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(Textes.annuler),
              ),
              FilledButton(
                onPressed: () => _appliquer(etat),
                child: const Text(Textes.appliquer),
              ),
            ],
          ),
          const SizedBox(height: espacementMoyen),
        ],
      ),
    );
  }
}

/// Toutes les catégories par initiale.
class _ListeCategories extends StatelessWidget {
  const _ListeCategories({
    required this.etat,
    required this.groupes,
    required this.etatDe,
    required this.surAppui,
  });

  final EtatBibliotheque etat;
  final List<GroupeCategories> groupes;
  final EtatFiltreCategorie Function(int idCategorie) etatDe;
  final void Function(int idCategorie) surAppui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (etat.categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(espacementMoyen),
        child: Text(Textes.aucuneCategorieConnue, textAlign: TextAlign.center),
      );
    }
    if (groupes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(espacementMoyen),
        child: Text(Textes.aucuneCategorieTrouvee, textAlign: TextAlign.center),
      );
    }
    final styleIntertitre = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.primary,
    );
    // ListView construit à la demande : seuls les groupes visibles sont
    // créés, même avec des centaines de catégories.
    return ListView.builder(
      shrinkWrap: true,
      itemCount: groupes.length,
      itemBuilder: (context, index) {
        final groupe = groupes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: espacementPetit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(groupe.initiale, style: styleIntertitre),
              const SizedBox(height: espacementPetit / 2),
              Wrap(
                spacing: espacementPetit,
                runSpacing: espacementPetit / 2,
                children: <Widget>[
                  for (final categorie in groupe.categories)
                    if (categorie.id != null)
                      PuceCategorieTroisEtats(
                        nom: categorie.nom,
                        etat: etatDe(categorie.id!),
                        surAppui: () => surAppui(categorie.id!),
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

/// Puce d'une catégorie à trois états : neutre (contour), incluse (pleine,
/// « + ») ou exclue (rouge, « − », barrée).
class PuceCategorieTroisEtats extends StatelessWidget {
  /// Crée la puce de la catégorie [nom] dans l'[etat] donné.
  const PuceCategorieTroisEtats({
    super.key,
    required this.nom,
    required this.etat,
    required this.surAppui,
  });

  /// Nom de la catégorie, tel qu'enregistré (minuscules).
  final String nom;

  /// État dans le filtre.
  final EtatFiltreCategorie etat;

  /// Passe à l'état suivant.
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final libelle = PastilleCategorie.afficher(nom);
    final estExclue = etat == EtatFiltreCategorie.exclue;
    return Tooltip(
      message: Textes.etatFiltreCategorie(etat),
      child: FilterChip(
        // L'état est aussi dit par l'icône et la couleur, pas seulement par
        // la couleur (lisible pour un daltonien).
        avatar: switch (etat) {
          EtatFiltreCategorie.neutre => null,
          EtatFiltreCategorie.incluse => Icon(
            Icons.add_circle,
            color: couleurs.primary,
          ),
          EtatFiltreCategorie.exclue => Icon(
            Icons.remove_circle,
            color: couleurs.error,
          ),
        },
        label: Text(
          libelle,
          style: estExclue
              ? TextStyle(
                  color: couleurs.error,
                  decoration: TextDecoration.lineThrough,
                )
              : null,
        ),
        selected: etat == EtatFiltreCategorie.incluse,
        showCheckmark: false,
        side: estExclue ? BorderSide(color: couleurs.error) : null,
        onSelected: (_) => surAppui(),
      ),
    );
  }
}

/// Choix des niveaux de contenu affichés (MangaDex : tous publics,
/// suggestif, érotique, pornographique). Réglage enregistré, qui sert aussi
/// aux recherches sur MangaDex.
class PanneauNiveauxContenu extends StatelessWidget {
  /// Crée le panneau (lit `EtatBibliotheque`).
  const PanneauNiveauxContenu({super.key});

  Future<void> _basculer(
    BuildContext context,
    EtatBibliotheque etat,
    String niveau,
    bool coche,
  ) async {
    final choisis = <String>{...?etat.niveauxContenuChoisis};
    if (coche) {
      choisis.add(niveau);
    } else {
      choisis.remove(niveau);
    }
    final resultat = await etat.modifierNiveauxContenu(choisis);
    if (context.mounted) afficherResultat(context, resultat);
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatBibliotheque>();
    final theme = Theme.of(context);
    final choisis = etat.niveauxContenuChoisis ?? niveauxContenuParDefaut;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: espacementMoyen),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(Textes.niveauxContenu, style: theme.textTheme.titleLarge),
            const SizedBox(height: espacementPetit),
            Text(
              Textes.explicationNiveauxContenu,
              style: theme.textTheme.bodySmall,
            ),
            for (final niveau in niveauxContenu)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(Textes.libelleNiveauContenu(niveau)),
                value: choisis.contains(niveau),
                onChanged: etat.estEnChargement
                    ? null
                    : (coche) =>
                          _basculer(context, etat, niveau, coche ?? false),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: espacementPetit,
              runSpacing: espacementPetit,
              children: <Widget>[
                TextButton(
                  onPressed: etat.estNiveauxParDefaut
                      ? null
                      : () async {
                          final resultat = await etat
                              .reinitialiserNiveauxContenu();
                          if (context.mounted) {
                            afficherResultat(context, resultat);
                          }
                        },
                  child: const Text(Textes.niveauxParDefaut),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(Textes.afficherTitres(etat.titres.length)),
                ),
              ],
            ),
            const SizedBox(height: espacementMoyen),
          ],
        ),
      ),
    );
  }
}
