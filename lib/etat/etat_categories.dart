/// État de la section « Catégories regroupées » des Paramètres : groupes de
/// catégories de même sens (« survival » / « survie »), regroupement à la
/// main et suggestions à confirmer.
library;

import '../modeles/categorie.dart';
import '../modeles/groupe_categories.dart';
import '../services/service_categories.dart';
import 'description_erreur.dart';

// L'interface affiche les groupes et les suggestions sans importer les
// services ni les modèles.
export '../modeles/categorie.dart' show Categorie;
export '../modeles/groupe_categories.dart' show GroupeCategories;
export '../services/service_categories.dart' show SuggestionRegroupement;

/// Groupes de catégories, catégories connues et suggestions de
/// regroupement. Rien n'est regroupé sans une action du client : les
/// suggestions ne sont appliquées qu'avec [appliquerSuggestion].
class EtatCategories extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire la base.
  ///
  /// [surModification] est appelé après chaque modification (réussie ou
  /// non : un regroupement partiel a pu être enregistré) pour relire la
  /// bibliothèque et ses filtres.
  EtatCategories(this._service, {this._surModification});

  final ServiceCategories _service;
  final Future<void> Function()? _surModification;

  List<Categorie> _categories = const <Categorie>[];
  List<GroupeCategories> _groupes = const <GroupeCategories>[];
  List<SuggestionRegroupement> _suggestions = const <SuggestionRegroupement>[];

  /// Suggestions écartées par « Ignorer » (clé : identifiants triés), pour
  /// la durée de la session.
  // LIMITE : non enregistré en base ; une suggestion ignorée revient au
  // prochain lancement de l'application.
  final Set<String> _suggestionsIgnorees = <String>{};

  bool _estEnChargement = false;
  bool _estCharge = false;
  bool _estEnModification = false;
  DescriptionErreur? _erreur;

  /// Numéro du dernier chargement : une réponse plus ancienne est ignorée.
  int _numeroChargement = 0;

  /// Toutes les catégories connues (rattachées comprises), triées par nom.
  List<Categorie> get categories => _categories;

  /// Groupes existants, triés par nom de référence.
  List<GroupeCategories> get groupes => _groupes;

  /// Suggestions de regroupement non ignorées.
  List<SuggestionRegroupement> get suggestions => <SuggestionRegroupement>[
    for (final suggestion in _suggestions)
      if (!_suggestionsIgnorees.contains(_cle(suggestion))) suggestion,
  ];

  /// `true` pendant un chargement.
  bool get estEnChargement => _estEnChargement;

  /// `true` une fois qu'un chargement a abouti.
  bool get estCharge => _estCharge;

  /// `true` pendant une modification (boutons désactivés).
  bool get estEnModification => _estEnModification;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// Identifiants des catégories rattachées à une référence.
  Set<int> get _idsRattachees => <int>{
    for (final groupe in _groupes)
      for (final categorie in groupe.rattachees) ?categorie.id,
  };

  /// Identifiants des références de groupe.
  Set<int> get _idsReferences => <int>{
    for (final groupe in _groupes) ?groupe.reference.id,
  };

  /// Groupe qui contient [idCategorie] (comme référence ou rattachée), ou
  /// `null`.
  GroupeCategories? groupeDe(int idCategorie) {
    for (final groupe in _groupes) {
      if (groupe.toutes.any((categorie) => categorie.id == idCategorie)) {
        return groupe;
      }
    }
    return null;
  }

  /// Catégories qui peuvent devenir référence : toutes sauf celles déjà
  /// rattachées à une autre (le service le refuserait), filtrées par
  /// [recherche] (sans accents ni majuscules).
  List<Categorie> referencesPossibles(String recherche) => filtrer(
    _categories.where((categorie) => !_idsRattachees.contains(categorie.id)),
    recherche,
  );

  /// Catégories rattachables à [idReference] : toutes sauf la référence
  /// elle-même, celles déjà dans son groupe et les références d'autres
  /// groupes (il faudrait d'abord les défaire), filtrées par [recherche].
  /// Une catégorie rattachée ailleurs reste proposée : elle changera de
  /// groupe.
  List<Categorie> rattachablesA(int idReference, String recherche) {
    final dejaDansLeGroupe = <int>{
      for (final groupe in _groupes)
        if (groupe.reference.id == idReference)
          for (final categorie in groupe.rattachees) ?categorie.id,
    };
    final references = _idsReferences;
    return filtrer(
      _categories.where(
        (categorie) =>
            categorie.id != null &&
            categorie.id != idReference &&
            !dejaDansLeGroupe.contains(categorie.id) &&
            !references.contains(categorie.id),
      ),
      recherche,
    );
  }

  /// [categories] dont le nom contient [recherche], sans tenir compte des
  /// accents, des majuscules ni des tirets (« comedie » trouve « comédie »,
  /// « sci fi » trouve « sci-fi »).
  static List<Categorie> filtrer(
    Iterable<Categorie> categories,
    String recherche,
  ) {
    final cle = ServiceCategories.cleDeComparaison(recherche);
    return <Categorie>[
      for (final categorie in categories)
        if (cle.isEmpty ||
            ServiceCategories.cleDeComparaison(categorie.nom).contains(cle))
          categorie,
    ];
  }

  /// Lit les catégories, les groupes et les suggestions.
  Future<void> charger() async {
    final numero = ++_numeroChargement;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final categories = await _service.chargerCategories();
      final groupes = await _service.chargerGroupes();
      final suggestions = await _service.suggererRegroupements();
      if (numero != _numeroChargement) return;
      _categories = categories;
      _groupes = groupes;
      _suggestions = suggestions;
      _estCharge = true;
    } catch (erreur, pile) {
      if (numero == _numeroChargement) {
        _erreur = DescriptionErreur.depuis(erreur, pile);
      }
    }
    if (numero == _numeroChargement) {
      _estEnChargement = false;
      notifier();
    }
  }

  /// Rattache [idsCategories] à [idReference] (tout ou rien).
  Future<ResultatAction<bool>> regrouper(
    int idReference,
    Set<int> idsCategories,
  ) => _modifier(() async {
    await _service.regrouperCategories(idReference, idsCategories);
    return true;
  });

  /// Applique une suggestion confirmée par le client.
  Future<ResultatAction<bool>> appliquerSuggestion(
    SuggestionRegroupement suggestion,
  ) => _modifier(() async {
    await _service.appliquerSuggestion(suggestion);
    return true;
  });

  /// Écarte [suggestion] pour la session (aucune écriture en base).
  void ignorerSuggestion(SuggestionRegroupement suggestion) {
    _suggestionsIgnorees.add(_cle(suggestion));
    notifier();
  }

  /// Retire [categorie] de son groupe ; renvoie `false` si elle n'était
  /// rattachée à rien.
  Future<ResultatAction<bool>> detacher(Categorie categorie) {
    final id = categorie.id;
    if (id == null) {
      return Future<ResultatAction<bool>>.value(
        const ResultatAction<bool>.reussite(false),
      );
    }
    return _modifier(() => _service.detacherCategorie(id));
  }

  /// Défait le groupe de [groupe] : toutes ses catégories redeviennent
  /// indépendantes. Renvoie le nombre de catégories détachées.
  Future<ResultatAction<int>> dissoudre(GroupeCategories groupe) {
    final id = groupe.reference.id;
    if (id == null) {
      return Future<ResultatAction<int>>.value(
        const ResultatAction<int>.reussite(0),
      );
    }
    return _modifier(() => _service.dissoudreGroupe(id));
  }

  /// Exécute une modification, puis relit les groupes et la bibliothèque
  /// dans tous les cas (sans transaction, un regroupement refusé en cours de
  /// route a pu garder ses premiers rattachements).
  Future<ResultatAction<T>> _modifier<T>(Future<T> Function() action) async {
    _estEnModification = true;
    notifier();
    ResultatAction<T> resultat;
    try {
      resultat = ResultatAction<T>.reussite(await action());
    } catch (erreur, pile) {
      resultat = ResultatAction<T>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
    await charger();
    try {
      await _surModification?.call();
    } catch (_) {
      // La bibliothèque affiche elle-même son erreur de chargement.
    }
    _estEnModification = false;
    notifier();
    return resultat;
  }

  /// Clé d'une suggestion : identifiants de ses catégories, triés. Une
  /// suggestion qui change (nouvelle catégorie de même sens) revient donc
  /// même après « Ignorer ».
  static String _cle(SuggestionRegroupement suggestion) {
    final ids = <int>[
      for (final categorie in suggestion.toutes) categorie.id ?? -1,
    ]..sort();
    return ids.join(',');
  }
}
