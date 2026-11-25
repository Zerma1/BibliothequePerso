/// Section « Catégories regroupées » des Paramètres : groupes de catégories
/// de même sens, regroupement à la main et suggestions à confirmer.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_bibliotheque.dart';
import '../etat/etat_categories.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'pastille_categorie.dart';
import 'section_pliable.dart';
import 'textes.dart';
import 'vues_etat.dart';

/// Section pliable des catégories regroupées : liste des groupes (retrait
/// d'une catégorie, groupe défait), bouton « Regrouper des catégories » et
/// suggestions (« Regrouper » / « Ignorer »).
///
/// Absente si la bibliothèque n'a pas de service de catégories (tests,
/// ancien assemblage). L'état ([EtatCategories]) est celui de la
/// bibliothèque : chaque modification relit la grille et ses filtres.
class SectionCategoriesRegroupees extends StatelessWidget {
  /// Crée la section (lit `EtatBibliotheque`).
  const SectionCategoriesRegroupees({super.key});

  @override
  Widget build(BuildContext context) {
    final EtatCategories? etat;
    try {
      etat = context.read<EtatBibliotheque>().etatCategories;
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (etat == null) return const SizedBox.shrink();
    return ChangeNotifierProvider<EtatCategories>.value(
      value: etat,
      child: const _Section(),
    );
  }
}

class _Section extends StatefulWidget {
  const _Section();

  @override
  State<_Section> createState() => _EtatSection();
}

class _EtatSection extends State<_Section> {
  @override
  void initState() {
    super.initState();
    // Relu à chaque ouverture des Paramètres : de nouveaux titres ont pu
    // apporter des catégories (et donc des suggestions). Après l'image :
    // notifier pendant la construction est interdit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<EtatCategories>().charger();
    });
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatCategories>();
    return SectionPliable(
      identifiant: 'parametres.categories',
      titre: Textes.sectionCategoriesRegroupees,
      icone: Icons.category_outlined,
      resume: etat.estCharge
          ? Textes.resumeCategoriesRegroupees(
              etat.groupes.length,
              etat.suggestions.length,
            )
          : null,
      enfants: <Widget>[_contenu(context, etat)],
    );
  }

  Widget _contenu(BuildContext context, EtatCategories etat) {
    final erreur = etat.erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    }
    if (!etat.estCharge) {
      return const Padding(
        padding: EdgeInsets.all(espacementGrand),
        child: VueChargement(),
      );
    }
    final theme = Theme.of(context);
    final occupe = etat.estEnModification;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          Textes.explicationCategoriesRegroupees,
          style: theme.textTheme.bodyMedium,
        ),
        // Barre fine plutôt qu'un indicateur plein écran : la liste reste
        // lisible pendant l'enregistrement.
        if (occupe) ...<Widget>[
          const SizedBox(height: espacementPetit),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: espacementMoyen),
        Text(Textes.intertitreGroupes, style: theme.textTheme.titleSmall),
        const SizedBox(height: espacementPetit),
        if (etat.groupes.isEmpty)
          const Text(Textes.aucunGroupe)
        else
          for (final groupe in etat.groupes)
            _TuileGroupe(etat: etat, groupe: groupe),
        const SizedBox(height: espacementPetit),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: occupe ? null : () => _regrouperALaMain(context, etat),
            icon: const Icon(Icons.merge_type),
            label: const Text(Textes.regrouperDesCategories),
          ),
        ),
        const SizedBox(height: espacementGrand),
        Text(Textes.intertitreSuggestions, style: theme.textTheme.titleSmall),
        const SizedBox(height: espacementPetit / 2),
        Text(Textes.explicationSuggestions, style: theme.textTheme.bodySmall),
        const SizedBox(height: espacementPetit),
        if (etat.suggestions.isEmpty)
          const Text(Textes.aucuneSuggestion)
        else
          for (final suggestion in etat.suggestions)
            _CarteSuggestion(etat: etat, suggestion: suggestion),
      ],
    );
  }

  Future<void> _regrouperALaMain(
    BuildContext context,
    EtatCategories etat,
  ) async {
    if (etat.categories.length < 2) {
      afficherMessage(context, Textes.pasAssezDeCategories);
      return;
    }
    final choix = await showDialog<_ChoixRegroupement>(
      context: context,
      builder: (_) => _DialogueRegroupement(etat: etat),
    );
    if (choix == null || !context.mounted) return;
    final resultat = await etat.regrouper(
      choix.reference.id!,
      choix.idsARattacher,
    );
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.categoriesRegroupees(
          PastilleCategorie.afficher(choix.reference.nom),
          choix.idsARattacher.length,
        ),
      );
    }
  }
}

/// Un groupe : la référence, ses catégories rattachées (chacune avec une
/// croix pour la retirer) et un bouton pour défaire le groupe.
class _TuileGroupe extends StatelessWidget {
  const _TuileGroupe({required this.etat, required this.groupe});

  final EtatCategories etat;
  final GroupeCategories groupe;

  Future<void> _detacher(BuildContext context, Categorie categorie) async {
    final resultat = await etat.detacher(categorie);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.categorieDetachee(
          PastilleCategorie.afficher(categorie.nom),
        ),
      );
    }
  }

  Future<void> _defaire(BuildContext context) async {
    final nom = PastilleCategorie.afficher(groupe.reference.nom);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.defaireGroupe),
        content: Text(Textes.confirmationDefaireGroupe(nom)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.defaire),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.dissoudre(groupe);
    if (context.mounted) {
      afficherResultat(context, resultat, succes: Textes.groupeDefait(nom));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occupe = etat.estEnModification;
    return Card.filled(
      margin: const EdgeInsets.only(bottom: espacementPetit),
      child: Padding(
        padding: const EdgeInsets.all(espacementPetit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: PastilleCategorie.afficher(
                            groupe.reference.nom,
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                        TextSpan(
                          text: '  ${Textes.referenceDuGroupe}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: Textes.defaireGroupe,
                  icon: const Icon(Icons.link_off),
                  onPressed: occupe ? null : () => _defaire(context),
                ),
              ],
            ),
            // Une puce par catégorie rattachée : la croix la retire du
            // groupe, sans toucher aux autres.
            Wrap(
              spacing: espacementPetit,
              runSpacing: espacementPetit / 2,
              children: <Widget>[
                for (final categorie in groupe.rattachees)
                  InputChip(
                    label: Text(PastilleCategorie.afficher(categorie.nom)),
                    visualDensity: VisualDensity.compact,
                    deleteButtonTooltipMessage: Textes.detacherCategorie(
                      PastilleCategorie.afficher(categorie.nom),
                    ),
                    onDeleted: occupe
                        ? null
                        : () => _detacher(context, categorie),
                    isEnabled: !occupe,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Une suggestion : « Rattacher survival, supervivencia à « survie » », avec
/// « Ignorer » et « Regrouper ». Rien n'est appliqué sans appui du client.
class _CarteSuggestion extends StatelessWidget {
  const _CarteSuggestion({required this.etat, required this.suggestion});

  final EtatCategories etat;
  final SuggestionRegroupement suggestion;

  Future<void> _appliquer(BuildContext context) async {
    final reference = PastilleCategorie.afficher(suggestion.reference.nom);
    final resultat = await etat.appliquerSuggestion(suggestion);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.categoriesRegroupees(
          reference,
          suggestion.aRattacher.length,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final occupe = etat.estEnModification;
    final autres = suggestion.aRattacher
        .map((categorie) => PastilleCategorie.afficher(categorie.nom))
        .join(', ');
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: espacementPetit),
      child: Padding(
        padding: const EdgeInsets.all(espacementPetit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              Textes.suggestion(
                PastilleCategorie.afficher(suggestion.reference.nom),
                autres,
              ),
            ),
            // Boutons à droite, qui passent à la ligne sur un écran étroit.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: espacementPetit,
              children: <Widget>[
                TextButton(
                  onPressed: occupe
                      ? null
                      : () => etat.ignorerSuggestion(suggestion),
                  child: const Text(Textes.ignorer),
                ),
                FilledButton.tonal(
                  onPressed: occupe ? null : () => _appliquer(context),
                  child: const Text(Textes.regrouper),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix fait dans le dialogue de regroupement.
typedef _ChoixRegroupement = ({Categorie reference, Set<int> idsARattacher});

/// Dialogue en deux étapes : choix de la référence, puis des catégories à
/// lui rattacher. Recherche sans accents à chaque étape.
class _DialogueRegroupement extends StatefulWidget {
  const _DialogueRegroupement({required this.etat});

  final EtatCategories etat;

  @override
  State<_DialogueRegroupement> createState() => _EtatDialogueRegroupement();
}

class _EtatDialogueRegroupement extends State<_DialogueRegroupement> {
  final TextEditingController _recherche = TextEditingController();
  Categorie? _reference;
  final Set<int> _choisies = <int>{};

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _choisirReference(Categorie? categorie) {
    setState(() {
      _reference = categorie;
      _choisies.clear();
      // Nouvelle étape, nouvelle recherche : le filtre de l'étape 1 ne
      // doit pas cacher les catégories à rattacher.
      _recherche.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = _reference;
    final hauteur = MediaQuery.sizeOf(context).height;
    final texte = _recherche.text;
    final candidates = reference == null
        ? widget.etat.referencesPossibles(texte)
        : widget.etat.rattachablesA(reference.id!, texte);
    return AlertDialog(
      title: const Text(Textes.regrouperDesCategories),
      content: ConstrainedBox(
        // Hauteur plafonnée à une part de l'écran : seule la liste défile,
        // la consigne et la recherche restent visibles.
        constraints: BoxConstraints(
          maxWidth: largeurMaxFormulaire,
          maxHeight: hauteur * fractionHauteurPanneau,
        ),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                reference == null
                    ? Textes.choisirReference
                    : Textes.choisirARattacher(
                        PastilleCategorie.afficher(reference.nom),
                      ),
                style: theme.textTheme.bodyMedium,
              ),
              if (reference != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _choisirReference(null),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text(Textes.changerReference),
                  ),
                ),
              const SizedBox(height: espacementPetit),
              TextField(
                controller: _recherche,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: Textes.rechercherCategorie,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: texte.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: Textes.annuler,
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(_recherche.clear),
                        ),
                ),
              ),
              const SizedBox(height: espacementPetit),
              Flexible(
                child: candidates.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(espacementMoyen),
                        child: Text(
                          Textes.aucuneCategorieTrouvee,
                          textAlign: TextAlign.center,
                        ),
                      )
                    // Construite à la demande : des centaines de tags
                    // restent fluides.
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) => reference == null
                            ? _ligneReference(candidates[index])
                            : _ligneARattacher(candidates[index], reference),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        if (reference != null)
          FilledButton(
            onPressed: _choisies.isEmpty
                ? null
                : () => Navigator.of(context).pop<_ChoixRegroupement>((
                    reference: reference,
                    idsARattacher: Set<int>.of(_choisies),
                  )),
            child: Text(Textes.regrouperNombre(_choisies.length)),
          ),
      ],
    );
  }

  Widget _ligneReference(Categorie categorie) {
    final groupe = widget.etat.groupeDe(categorie.id!);
    final rattachees = groupe?.rattachees ?? const <Categorie>[];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(PastilleCategorie.afficher(categorie.nom)),
      // Une référence existante rappelle ce qu'elle regroupe déjà : le
      // client complète le groupe plutôt que d'en créer un doublon.
      subtitle: rattachees.isEmpty
          ? null
          : Text(
              Textes.rattacheesAuGroupe(
                rattachees
                    .map((autre) => PastilleCategorie.afficher(autre.nom))
                    .join(', '),
              ),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _choisirReference(categorie),
    );
  }

  Widget _ligneARattacher(Categorie categorie, Categorie reference) {
    final id = categorie.id!;
    final groupe = widget.etat.groupeDe(id);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(PastilleCategorie.afficher(categorie.nom)),
      // Une catégorie déjà regroupée ailleurs changera de groupe : on le dit.
      subtitle: groupe == null
          ? null
          : Text(
              Textes.dansLeGroupe(
                PastilleCategorie.afficher(groupe.reference.nom),
              ),
            ),
      value: _choisies.contains(id),
      onChanged: (coche) => setState(() {
        if (coche ?? false) {
          _choisies.add(id);
        } else {
          _choisies.remove(id);
        }
      }),
    );
  }
}
