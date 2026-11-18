/// Formulaire « Modifier la fiche » d'un titre (tâche X6) : nom, titres
/// alternatifs, résumé, auteur, statut, catégories et niveau de contenu.
/// Les champs modifiés sont protégés de l'actualisation depuis le site.
library;

import 'package:material_ui/material_ui.dart';

import '../etat/etat_titre.dart';
import '../modeles/titre.dart';
import '../modeles/titre_alternatif.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';

/// Une ligne de titre alternatif en cours de saisie.
class _LigneAlternatif {
  _LigneAlternatif(String nom, String langue)
    : nom = TextEditingController(text: nom),
      langue = TextEditingController(text: langue);

  final TextEditingController nom;
  final TextEditingController langue;

  void dispose() {
    nom.dispose();
    langue.dispose();
  }
}

/// Formulaire de modification de la fiche du titre de [etat].
///
/// Brouillon local : rien n'est écrit avant « Enregistrer », et seuls les
/// champs réellement changés sont envoyés (un champ inchangé n'est pas
/// protégé pour rien). « Rendre au site » agit tout de suite.
class EcranModificationTitre extends StatefulWidget {
  /// Crée le formulaire.
  const EcranModificationTitre({super.key, required this.etat});

  /// État de la fiche (le formulaire est ouvert au-dessus d'elle).
  final EtatTitre etat;

  /// Ouvre le formulaire ; affiche le résultat de l'enregistrement.
  static Future<void> ouvrir(BuildContext context, EtatTitre etat) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        // Plein écran : beaucoup de champs, et un clavier sur téléphone.
        fullscreenDialog: true,
        builder: (_) => EcranModificationTitre(etat: etat),
      ),
    );
    if (message != null && context.mounted) afficherMessage(context, message);
  }

  @override
  State<EcranModificationTitre> createState() => _EtatEcranModificationTitre();
}

class _EtatEcranModificationTitre extends State<EcranModificationTitre> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  late Titre _titre = widget.etat.titre!;
  late final TextEditingController _nom = TextEditingController(
    text: _titre.nom,
  );
  late final TextEditingController _resume = TextEditingController(
    text: _titre.resume ?? '',
  );
  late final TextEditingController _auteur = TextEditingController(
    text: _titre.auteur ?? '',
  );
  late final TextEditingController _statut = TextEditingController(
    text: _titre.statut ?? '',
  );
  final TextEditingController _nouvelleCategorie = TextEditingController();
  late final List<_LigneAlternatif> _alternatifs = <_LigneAlternatif>[
    for (final alternatif in _titre.titresAlternatifs)
      _LigneAlternatif(alternatif.nom, alternatif.langue),
  ];

  /// Catégories telles qu'affichées par la fiche au départ.
  late final List<String> _categoriesInitiales = <String>[
    for (final categorie in widget.etat.categories) categorie.nom,
  ];
  late List<String> _categories = List<String>.of(_categoriesInitiales);
  // Un niveau inconnu de la liste (valeur d'un site) est montré « Inconnu ».
  // L'enregistrement compare au niveau affiché au départ, pas à la valeur
  // brute : sinon un niveau hors liste serait effacé (et protégé) alors que
  // le client n'a pas touché au champ.
  late final String _niveauInitial =
      EtatTitre.niveauxContenuPossibles.contains(_titre.niveauContenu)
      ? _titre.niveauContenu!
      : '';
  late String _niveau = _niveauInitial;

  @override
  void dispose() {
    _nom.dispose();
    _resume.dispose();
    _auteur.dispose();
    _statut.dispose();
    _nouvelleCategorie.dispose();
    for (final ligne in _alternatifs) {
      ligne.dispose();
    }
    super.dispose();
  }

  void _ajouterCategorie() {
    final nom = _nouvelleCategorie.text.trim();
    if (nom.isEmpty) return;
    setState(() {
      if (!_categories.any((c) => c.toLowerCase() == nom.toLowerCase())) {
        _categories = <String>[..._categories, nom];
      }
      _nouvelleCategorie.clear();
    });
  }

  List<TitreAlternatif> get _alternatifsSaisis =>
      _normaliserAlternatifs(<TitreAlternatif>[
        for (final ligne in _alternatifs)
          TitreAlternatif(nom: ligne.nom.text, langue: ligne.langue.text),
      ]);

  /// Même traitement pour la saisie et pour la valeur de départ : espaces
  /// retirés, lignes sans nom ignorées. Sinon une ligne vide venue du site
  /// suffirait à faire croire à une modification.
  static List<TitreAlternatif> _normaliserAlternatifs(
    List<TitreAlternatif> alternatifs,
  ) => <TitreAlternatif>[
    for (final alternatif in alternatifs)
      if (alternatif.nom.trim().isNotEmpty)
        TitreAlternatif(
          nom: alternatif.nom.trim(),
          langue: alternatif.langue.trim(),
        ),
  ];

  static bool _memesAlternatifs(
    List<TitreAlternatif> a,
    List<TitreAlternatif> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].nom.trim() != b[i].nom.trim() ||
          a[i].langue.trim().toLowerCase() !=
              b[i].langue.trim().toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  static bool _memesTextes(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  /// Enregistre les champs changés (et seulement eux).
  Future<void> _enregistrer() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    String? change(String saisie, String? avant) =>
        saisie.trim() == (avant ?? '').trim() ? null : saisie.trim();
    final alternatifs = _alternatifsSaisis;
    final nom = change(_nom.text, _titre.nom);
    final resume = change(_resume.text, _titre.resume);
    final auteur = change(_auteur.text, _titre.auteur);
    final statut = change(_statut.text, _titre.statut);
    final niveau = _niveau == _niveauInitial ? null : _niveau;
    final titresAlternatifs =
        _memesAlternatifs(
          alternatifs,
          _normaliserAlternatifs(_titre.titresAlternatifs),
        )
        ? null
        : alternatifs;
    final categories = _memesTextes(_categories, _categoriesInitiales)
        ? null
        : _categories;
    if (nom == null &&
        resume == null &&
        auteur == null &&
        statut == null &&
        niveau == null &&
        titresAlternatifs == null &&
        categories == null) {
      Navigator.of(context).pop(Textes.aucuneModification);
      return;
    }
    final resultat = await widget.etat.modifierFiche(
      nom: nom,
      titresAlternatifs: titresAlternatifs,
      resume: resume,
      auteur: auteur,
      statut: statut,
      categories: categories,
      niveauContenu: niveau,
    );
    if (!mounted) return;
    if (resultat.estReussi) {
      Navigator.of(context).pop(Textes.ficheModifiee);
    } else {
      afficherResultat(context, resultat);
    }
  }

  /// « Rendre au site » : le champ n'est plus protégé (la valeur du site
  /// revient à la prochaine actualisation ; la saisie reste affichée).
  Future<void> _rendreAuSite(ChampTitre champ) async {
    final resultat = await widget.etat.rendreAuSite(<ChampTitre>{champ});
    if (!mounted) return;
    final relu = widget.etat.titre;
    if (resultat.estReussi && relu != null) setState(() => _titre = relu);
    afficherResultat(context, resultat, succes: Textes.champRenduAuSite);
  }

  /// Repère « modifié à la main » d'un champ, avec « Rendre au site ».
  Widget _repere(ChampTitre champ) {
    if (!_titre.estManuel(champ)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final couleur = theme.colorScheme.tertiary;
    // Discret : une ligne en petit texte sous le champ, pas un bandeau.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: espacementPetit / 2,
      children: <Widget>[
        Icon(
          Icons.edit_note,
          size: theme.textTheme.bodySmall?.fontSize,
          color: couleur,
        ),
        Text(
          Textes.modifieALaMain,
          style: theme.textTheme.bodySmall?.copyWith(color: couleur),
        ),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: widget.etat.estEnModificationFiche
              ? null
              : () => _rendreAuSite(champ),
          child: Text(
            Textes.rendreAuSite,
            semanticsLabel:
                '${Textes.rendreAuSite} : ${Textes.libelleChampTitre(champ)}',
          ),
        ),
      ],
    );
  }

  Widget _champ(
    TextEditingController controleur,
    String libelle,
    ChampTitre champ, {
    int lignes = 1,
    String? Function(String?)? validateur,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: espacementMoyen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextFormField(
            controller: controleur,
            minLines: lignes,
            maxLines: lignes == 1 ? 1 : null,
            decoration: InputDecoration(
              labelText: libelle,
              border: const OutlineInputBorder(),
            ),
            validator: validateur,
          ),
          _repere(champ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Le formulaire suit l'état de la fiche (enregistrement en cours).
    return ListenableBuilder(
      listenable: widget.etat,
      builder: (context, _) => _construire(context),
    );
  }

  Widget _construire(BuildContext context) {
    final theme = Theme.of(context);
    final occupe = widget.etat.estEnModificationFiche;
    return Scaffold(
      appBar: AppBar(
        title: const Text(Textes.modifierFiche),
        actions: <Widget>[
          TextButton(
            onPressed: occupe ? null : _enregistrer,
            child: const Text(Textes.enregistrer),
          ),
        ],
      ),
      body: widget.etat.titre == null
          ? const VueChargement()
          // Colonne centrée de largeur plafonnée, comme les Paramètres : des
          // champs étirés sur un grand écran seraient difficiles à lire.
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: largeurMaxFormulaire,
                ),
                child: Form(
                  key: _formulaire,
                  child: ListView(
                    padding: const EdgeInsets.all(espacementMoyen),
                    children: <Widget>[
                      if (occupe) const LinearProgressIndicator(),
                      Text(
                        Textes.explicationModificationFiche,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: espacementMoyen),
                      _champ(
                        _nom,
                        Textes.champNomTitre,
                        ChampTitre.nom,
                        validateur: (valeur) => (valeur ?? '').trim().isEmpty
                            ? Textes.erreurNomTitreVide
                            : null,
                      ),
                      _sectionAlternatifs(theme),
                      _champ(
                        _resume,
                        Textes.resume,
                        ChampTitre.resume,
                        lignes: 4,
                      ),
                      _champ(_auteur, Textes.auteur, ChampTitre.auteur),
                      _champ(_statut, Textes.statut, ChampTitre.statut),
                      _sectionCategories(theme),
                      _sectionNiveau(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _sectionAlternatifs(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: espacementMoyen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            Textes.sectionTitresAlternatifs,
            style: theme.textTheme.titleSmall,
          ),
          for (final ligne in _alternatifs)
            Padding(
              padding: const EdgeInsets.only(top: espacementPetit),
              // Nom large, langue étroite (un code de deux lettres) : en
              // proportions, pas en pixels.
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: ligne.nom,
                      decoration: const InputDecoration(
                        labelText: Textes.champTitreAlternatif,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: espacementPetit),
                  Expanded(
                    child: TextField(
                      controller: ligne.langue,
                      decoration: const InputDecoration(
                        labelText: Textes.champLangueAlternatif,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: Textes.retirer,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      _alternatifs.remove(ligne);
                      ligne.dispose();
                    }),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _alternatifs.add(_LigneAlternatif('', ''))),
              icon: const Icon(Icons.add),
              label: const Text(Textes.ajouterTitreAlternatif),
            ),
          ),
          _repere(ChampTitre.titresAlternatifs),
        ],
      ),
    );
  }

  Widget _sectionCategories(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: espacementMoyen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(Textes.categories, style: theme.textTheme.titleSmall),
          const SizedBox(height: espacementPetit),
          // Puces qui passent à la ligne : leur nombre varie beaucoup d'un
          // titre à l'autre.
          Wrap(
            spacing: espacementPetit,
            runSpacing: espacementPetit,
            children: <Widget>[
              for (final categorie in _categories)
                InputChip(
                  label: Text(categorie),
                  deleteButtonTooltipMessage: Textes.retirer,
                  onDeleted: () => setState(
                    () => _categories = <String>[
                      for (final autre in _categories)
                        if (autre != categorie) autre,
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: espacementPetit),
          TextField(
            controller: _nouvelleCategorie,
            decoration: InputDecoration(
              labelText: Textes.champAjoutCategorie,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: Textes.ajouter,
                icon: const Icon(Icons.add),
                onPressed: _ajouterCategorie,
              ),
            ),
            onSubmitted: (_) => _ajouterCategorie(),
          ),
          _repere(ChampTitre.categories),
        ],
      ),
    );
  }

  Widget _sectionNiveau() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _niveau,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: Textes.niveauContenu,
            border: OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: '',
              child: Text(Textes.niveauInconnu),
            ),
            for (final niveau in EtatTitre.niveauxContenuPossibles)
              DropdownMenuItem<String>(
                value: niveau,
                child: Text(Textes.libelleNiveauContenu(niveau)),
              ),
          ],
          onChanged: (valeur) => setState(() => _niveau = valeur ?? ''),
        ),
        _repere(ChampTitre.niveauContenu),
      ],
    );
  }
}
