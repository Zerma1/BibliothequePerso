/// Regroupement des catégories de même sens (« Survival » / « Survie »,
/// « Comedy » / « Comédie ») : gestion des groupes, catégories effectives
/// pour les filtres et la fiche, et suggestions de regroupement.
///
/// Les sites ne sont jamais concernés : les catégories qu'ils donnent restent
/// enregistrées telles quelles, le regroupement n'agit qu'à la lecture
/// (PLAYBOOK.md, idées pour des versions futures).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'package:sqflite/sqflite.dart'
    show Database, DatabaseException, DatabaseExecutor;

import '../donnees/depot_categories.dart';
import '../donnees/depot_equivalences_categories.dart';
import '../donnees/depot_titres.dart';
import '../donnees/gestionnaire_transactions.dart';
import '../modeles/categorie.dart';
import '../modeles/equivalence_categorie.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/groupe_categories.dart';
import '../modeles/titre.dart';
import 'erreur_service.dart';

/// Dictionnaire intégré des genres et tags courants (MangaDex et sites
/// français), de l'anglais vers le **libellé français** qui sert de
/// référence proposée. Les clés sont comparées après
/// [ServiceCategories.cleDeComparaison] (sans accents, sans majuscules,
/// tirets et espaces confondus) : « Sci-Fi », « sci fi » et « SciFi »
/// donnent donc la même entrée.
///
/// Il ne sert qu'à **proposer** des regroupements : rien n'est appliqué sans
/// la confirmation du client. Les libellés français eux-mêmes sont reconnus
/// (« comédie », « comedie » → « comédie »).
const Map<String, String> traductionsCategories = <String, String>{
  'action': 'action',
  'adventure': 'aventure',
  'comedy': 'comédie',
  'drama': 'drame',
  'fantasy': 'fantastique',
  'horror': 'horreur',
  'mystery': 'mystère',
  'romance': 'romance',
  'sci-fi': 'science-fiction',
  'scifi': 'science-fiction',
  'science fiction': 'science-fiction',
  'slice of life': 'tranche de vie',
  'sports': 'sport',
  'sport': 'sport',
  'supernatural': 'surnaturel',
  'survival': 'survie',
  'psychological': 'psychologique',
  'historical': 'historique',
  'history': 'historique',
  'tragedy': 'tragédie',
  'military': 'militaire',
  'magic': 'magie',
  'school life': 'vie scolaire',
  'martial arts': 'arts martiaux',
  'thriller': 'thriller',
  'crime': 'crime',
  'philosophical': 'philosophique',
  'medical': 'médical',
  'music': 'musique',
  'cooking': 'cuisine',
  'superhero': 'super-héros',
  'post-apocalyptic': 'post-apocalyptique',
  'reincarnation': 'réincarnation',
  'time travel': 'voyage dans le temps',
  'monsters': 'monstres',
  'demons': 'démons',
  'ghosts': 'fantômes',
  'aliens': 'extraterrestres',
  'animals': 'animaux',
  'video games': 'jeux vidéo',
  'police': 'police',
  'delinquents': 'délinquants',
  'office workers': 'employés de bureau',
  'adaptation': 'adaptation',
  'anthology': 'anthologie',
  'award winning': 'primé',
  'gore': 'gore',
  'harem': 'harem',
  'isekai': 'isekai',
  'mecha': 'mecha',
  'vampires': 'vampires',
  'zombies': 'zombies',
};

/// Un regroupement proposé par [ServiceCategories.suggererRegroupements] :
/// une catégorie de référence et les catégories de même sens à lui
/// rattacher. Jamais appliqué sans la confirmation du client
/// ([ServiceCategories.appliquerSuggestion]).
class SuggestionRegroupement {
  /// Crée la suggestion. La liste [aRattacher] est copiée dans une liste non
  /// modifiable.
  SuggestionRegroupement({
    required this.reference,
    required List<Categorie> aRattacher,
    this.libelleFrancais,
  }) : aRattacher = List<Categorie>.unmodifiable(aRattacher);

  /// Catégorie de référence proposée : celle qui porte le libellé français
  /// s'il existe parmi les catégories, sinon une référence de groupe déjà
  /// existante, sinon la première par nom.
  final Categorie reference;

  /// Catégories à rattacher à [reference], triées par nom (jamais vide).
  final List<Categorie> aRattacher;

  /// Libellé français du dictionnaire intégré ([traductionsCategories]), ou
  /// `null` si les catégories se ressemblent sans y figurer (« comédie » et
  /// « comedie »).
  final String? libelleFrancais;

  /// Toutes les catégories concernées : la référence puis les autres.
  List<Categorie> get toutes => <Categorie>[reference, ...aRattacher];

  @override
  String toString() =>
      'SuggestionRegroupement(reference: ${reference.nom}, '
      'aRattacher: ${aRattacher.map((c) => c.nom).join(', ')})';
}

/// Point d'entrée de l'interface pour les catégories : groupes de
/// catégories de même sens, catégories effectives (panneau des filtres,
/// fiche d'un titre) et suggestions de regroupement.
///
/// Les filtres de la bibliothèque suivent les groupes d'eux-mêmes
/// (`ServiceBibliotheque.chargerTitres`, `idsCategoriesIncluses` /
/// `idsCategoriesExclues`).
///
/// Toutes les erreurs de la base sont rendues comme des [ErreurService] au
/// message lisible : l'interface n'a jamais à attraper une erreur technique.
class ServiceCategories {
  /// Crée le service.
  ///
  /// [gestionnaireTransactions] rend [regrouperCategories] (et donc
  /// [appliquerSuggestion]) « tout ou rien » : à fournir dans l'application.
  ServiceCategories({
    required DepotCategories depotCategories,
    required DepotEquivalencesCategories depotEquivalences,
    required DepotTitres depotTitres,
    GestionnaireTransactions? gestionnaireTransactions,
  }) : _depotCategories = depotCategories,
       _depotEquivalences = depotEquivalences,
       _depotTitres = depotTitres,
       _gestionnaireTransactions = gestionnaireTransactions;

  /// Crée le service sur une base déjà ouverte, avec ses dépôts et un
  /// gestionnaire de transactions (assemblage de l'application).
  factory ServiceCategories.surBase(Database base) => ServiceCategories(
    depotCategories: DepotCategories(base),
    depotEquivalences: DepotEquivalencesCategories(base),
    depotTitres: DepotTitres(base),
    gestionnaireTransactions: GestionnaireTransactions(base),
  );

  final DepotCategories _depotCategories;
  final DepotEquivalencesCategories _depotEquivalences;
  final DepotTitres _depotTitres;
  final GestionnaireTransactions? _gestionnaireTransactions;

  // ---------------------------------------------------------------- Titres

  /// Titres de la bibliothèque avec tous les filtres du panneau, en **un
  /// seul** appel au dépôt (tous les filtres se cumulent dans la même
  /// requête), triés par nom.
  ///
  /// - [recherche], [idListe], [niveauxContenu], [inclureNiveauInconnu] :
  ///   comme `ServiceBibliotheque.chargerTitres` ;
  /// - [idsCategoriesIncluses] : titres qui ont **toutes** ces catégories ;
  /// - [idsCategoriesExclues] : titres qui n'en ont **aucune**.
  ///
  /// Chaque filtre de catégorie porte sur le **groupe** de la catégorie :
  /// inclure « survie » trouve aussi les titres classés « survival », et
  /// exclure « survival » écarte aussi ceux classés « survie ». Une
  /// catégorie à la fois incluse et exclue ne donne aucun titre (choix
  /// contradictoire du client, laissé tel quel plutôt que deviné).
  ///
  /// Placée ici plutôt que dans `ServiceBibliotheque` : une nouvelle méthode
  /// de ce dernier casserait sa doublure `FauxServiceBibliotheque` (tests de
  /// l'interface), qui l'implémente en entier.
  Future<List<Titre>> chargerTitresFiltres({
    String? recherche,
    int? idListe,
    Set<int> idsCategoriesIncluses = const <int>{},
    Set<int> idsCategoriesExclues = const <int>{},
    List<String>? niveauxContenu,
    bool inclureNiveauInconnu = true,
  }) => _lire(
    () => _depotTitres.chargerTitres(
      recherche: recherche,
      idListe: idListe,
      idsCategoriesIncluses: idsCategoriesIncluses,
      idsCategoriesExclues: idsCategoriesExclues,
      niveauxContenu: niveauxContenu,
      inclureNiveauInconnu: inclureNiveauInconnu,
    ),
    "La bibliothèque n'a pas pu être lue.",
  );

  // ---------------------------------------------------------------- Lecture

  /// Toutes les catégories connues (rattachées comprises), triées par nom :
  /// pour l'écran de gestion des groupes.
  Future<List<Categorie>> chargerCategories() =>
      _lire(_depotCategories.chargerCategories);

  /// Groupes existants (références avec leurs catégories rattachées), triés
  /// par nom de référence.
  Future<List<GroupeCategories>> chargerGroupes() =>
      _lire(_depotEquivalences.chargerGroupes);

  /// Catégories à proposer dans le panneau des filtres : références de
  /// groupes et catégories sans groupe (une catégorie rattachée est
  /// représentée par sa référence), triées par nom.
  Future<List<Categorie>> chargerCategoriesEffectives() =>
      _lire(_depotEquivalences.chargerCategoriesEffectives);

  /// Catégories d'un titre ramenées à leur référence, sans doublon, triées
  /// par nom : pour la fiche (« survival » et « survie » n'affichent que
  /// « survie »).
  Future<List<Categorie>> chargerCategoriesEffectivesDuTitre(int idTitre) =>
      _lire(
        () => _depotEquivalences.chargerCategoriesEffectivesDuTitre(idTitre),
      );

  /// Catégorie effective de [idCategorie] (sa référence si elle est
  /// rattachée, elle-même sinon), ou `null` si elle n'existe pas.
  Future<Categorie?> chargerCategorieEffective(int idCategorie) =>
      _lire(() => _depotEquivalences.chargerCategorieEffective(idCategorie));

  // ---------------------------------------------------------------- Groupes

  /// Rattache [idCategorie] au groupe de [idReference] (qui devient la
  /// référence du groupe si elle n'en avait pas encore). Une catégorie déjà
  /// rattachée ailleurs change de groupe.
  ///
  /// Lève une [ErreurService] au message lisible si le rattachement est
  /// impossible : même catégorie, catégorie inconnue, [idReference] déjà
  /// rattachée à une autre (il faut choisir sa référence), ou [idCategorie]
  /// référence d'un autre groupe (il faut d'abord le dissoudre).
  Future<void> rattacherCategorie(int idCategorie, int idReference) => _ecrire(
    () => _depotEquivalences.rattacherCategorie(idCategorie, idReference),
    'Le regroupement des catégories a échoué.',
  );

  /// Rattache toutes les [idsCategories] à [idReference] en une fois (choix
  /// de plusieurs catégories dans l'interface, suggestion confirmée).
  /// [idReference] elle-même est ignorée si elle figure dans la liste.
  ///
  /// Avec un gestionnaire de transactions, c'est « tout ou rien » : si un
  /// rattachement est refusé, aucun n'est gardé. Lève une [ErreurService]
  /// (message du premier refus) si un rattachement est impossible.
  ///
  /// LIMITE : sans gestionnaire de transactions (tests, anciens
  /// assemblages), les rattachements réussis avant un refus restent
  /// enregistrés ; relancer après correction termine le travail (un
  /// rattachement déjà fait ne change rien).
  Future<void> regrouperCategories(
    int idReference,
    Iterable<int> idsCategories,
  ) {
    final ids = <int>{
      for (final id in idsCategories)
        if (id != idReference) id,
    };
    if (ids.isEmpty) return Future<void>.value();
    Future<void> tout(DatabaseExecutor? executeur) async {
      for (final id in ids) {
        await _depotEquivalences.rattacherCategorie(
          id,
          idReference,
          executeur: executeur,
        );
      }
    }

    final gestionnaire = _gestionnaireTransactions;
    return _ecrire(
      () => gestionnaire == null
          ? tout(null)
          : gestionnaire.executerEnTransaction<void>(tout),
      'Le regroupement des catégories a échoué : rien n\'a été modifié.',
    );
  }

  /// Applique une suggestion confirmée par le client : rattache
  /// `suggestion.aRattacher` à `suggestion.reference` (voir
  /// [regrouperCategories]).
  Future<void> appliquerSuggestion(SuggestionRegroupement suggestion) {
    final idReference = suggestion.reference.id;
    if (idReference == null) {
      return Future<void>.error(
        const ErreurService('Cette suggestion ne désigne aucune catégorie.'),
      );
    }
    return regrouperCategories(idReference, <int>[
      for (final categorie in suggestion.aRattacher) ?categorie.id,
    ]);
  }

  /// Détache [idCategorie] de son groupe : elle redevient indépendante.
  /// Renvoie `false` si elle n'était rattachée à rien.
  Future<bool> detacherCategorie(int idCategorie) => _ecrire(
    () => _depotEquivalences.detacherCategorie(idCategorie),
    "La catégorie n'a pas pu être retirée de son groupe.",
  );

  /// Dissout le groupe de la référence [idReference] : toutes ses
  /// catégories redeviennent indépendantes. Renvoie le nombre de catégories
  /// détachées (0 si ce n'était pas une référence).
  Future<int> dissoudreGroupe(int idReference) => _ecrire(
    () => _depotEquivalences.dissoudreGroupe(idReference),
    "Le groupe n'a pas pu être dissous.",
  );

  // ------------------------------------------------------------ Suggestions

  /// Regroupements possibles parmi les catégories existantes, d'après le
  /// dictionnaire intégré ([traductionsCategories]) et une comparaison sans
  /// accents ni majuscules. Base seulement (aucun réseau), **aucune
  /// écriture** : le client confirme chaque suggestion
  /// ([appliquerSuggestion]).
  Future<List<SuggestionRegroupement>> suggererRegroupements() async {
    final categories = await chargerCategories();
    final equivalences = await _lire(_depotEquivalences.chargerEquivalences);
    return calculerSuggestions(categories, equivalences);
  }

  /// Calcul des suggestions (fonction pure, voir [suggererRegroupements]).
  ///
  /// Les catégories sont réparties par sens ([cleDeSens]) ; un sens partagé
  /// par plusieurs catégories qui ne sont pas encore dans le même groupe
  /// donne une suggestion. Les choix déjà faits par le client sont
  /// respectés :
  /// - une catégorie déjà rattachée (au groupe proposé ou à un autre) n'est
  ///   jamais reproposée ;
  /// - une référence de groupe n'est jamais proposée au rattachement (il
  ///   faudrait dissoudre son groupe) ; s'il y en a une parmi les catégories
  ///   de même sens, elle devient la référence proposée, son groupe étant
  ///   alors complété.
  ///
  /// Référence proposée, dans l'ordre : la catégorie qui porte le libellé
  /// français du dictionnaire (« survie » pour « survival »), sinon une
  /// référence de groupe existante, sinon la première par nom. Suggestions
  /// triées par nom de référence.
  static List<SuggestionRegroupement> calculerSuggestions(
    List<Categorie> categories,
    List<EquivalenceCategorie> equivalences,
  ) {
    final rattachees = <int>{
      for (final equivalence in equivalences) equivalence.idCategorie,
    };
    final references = <int>{
      for (final equivalence in equivalences) equivalence.idReference,
    };
    final parSens = <String, List<Categorie>>{};
    for (final categorie in categories) {
      final id = categorie.id;
      if (id == null || rattachees.contains(id)) continue;
      final sens = cleDeSens(categorie.nom);
      if (sens.isEmpty) continue;
      (parSens[sens] ??= <Categorie>[]).add(categorie);
    }

    final suggestions = <SuggestionRegroupement>[];
    for (final MapEntry(key: sens, value: membres) in parSens.entries) {
      if (membres.length < 2) continue;
      membres.sort(_comparerParNom);
      final libelle = libelleFrancais(sens);
      final cleLibelle = libelle == null ? null : cleDeComparaison(libelle);
      final referencesExistantes = membres
          .where((categorie) => references.contains(categorie.id))
          .toList();
      // Le libellé écrit exactement (accents compris) d'abord : entre
      // « comédie » et « comedie », c'est « comédie » qui représente le
      // groupe. Puis une écriture approchée (« science fiction »).
      Categorie? portantLeLibelle(List<Categorie> parmi) {
        if (libelle == null) return null;
        final exact = Categorie.normaliserNom(libelle);
        for (final categorie in parmi) {
          if (categorie.nom == exact) return categorie;
        }
        for (final categorie in parmi) {
          if (cleDeComparaison(categorie.nom) == cleLibelle) return categorie;
        }
        return null;
      }

      // Une référence existante ne peut pas être rattachée : s'il y en a,
      // la référence proposée est forcément l'une d'elles.
      final reference = referencesExistantes.isEmpty
          ? portantLeLibelle(membres) ?? membres.first
          : portantLeLibelle(referencesExistantes) ??
                referencesExistantes.first;
      final aRattacher = <Categorie>[
        for (final categorie in membres)
          if (categorie.id != reference.id &&
              !references.contains(categorie.id))
            categorie,
      ];
      if (aRattacher.isEmpty) continue;
      suggestions.add(
        SuggestionRegroupement(
          reference: reference,
          aRattacher: aRattacher,
          libelleFrancais: libelle,
        ),
      );
    }
    suggestions.sort((a, b) => _comparerParNom(a.reference, b.reference));
    return suggestions;
  }

  /// Clé de comparaison d'un nom : minuscules, accents retirés, tirets,
  /// soulignés, apostrophes, points et barres remplacés par des espaces,
  /// espaces multiples réduits. « Science-Fiction » → « science fiction »,
  /// « Comédie » → « comedie ». Les caractères non latins (japonais…) sont
  /// gardés tels quels. Fonction pure.
  static String cleDeComparaison(String nom) {
    final tampon = StringBuffer();
    for (final rune in nom.toLowerCase().runes) {
      final caractere = String.fromCharCode(rune);
      tampon.write(_sansAccent[caractere] ?? caractere);
    }
    return tampon
        .toString()
        .replaceAll(_separateurs, ' ')
        .replaceAll(_espaces, ' ')
        .trim();
  }

  /// Clé de **sens** d'un nom : la clé de comparaison de son libellé
  /// français s'il figure au dictionnaire, sinon sa propre clé de
  /// comparaison. « Survival » et « survie » ont la même clé de sens.
  /// Fonction pure.
  static String cleDeSens(String nom) {
    final libelle = libelleFrancais(cleDeComparaison(nom));
    return libelle == null ? cleDeComparaison(nom) : cleDeComparaison(libelle);
  }

  /// Libellé français du dictionnaire pour un nom (ou une clé de
  /// comparaison), anglais ou déjà français ; `null` s'il n'y figure pas.
  /// « Sci-Fi » → « science-fiction », « comedie » → « comédie ».
  /// Fonction pure.
  static String? libelleFrancais(String nom) =>
      _dictionnaireParCle[cleDeComparaison(nom)];

  /// Dictionnaire indexé par clé de comparaison : les clés anglaises et les
  /// libellés français eux-mêmes. Construit une fois, à la première
  /// utilisation.
  static final Map<String, String> _dictionnaireParCle = () {
    final parCle = <String, String>{};
    for (final MapEntry(key: anglais, value: francais)
        in traductionsCategories.entries) {
      parCle[cleDeComparaison(anglais)] = francais;
    }
    // Les libellés français se reconnaissent aussi (« comedie » sans
    // accent, « Tranche-de-vie ») ; une clé anglaise identique garde sa
    // traduction (« romance » → « romance »).
    for (final francais in traductionsCategories.values) {
      parCle.putIfAbsent(cleDeComparaison(francais), () => francais);
    }
    return parCle;
  }();

  /// Séparateurs confondus avec une espace : « sci-fi », « sci_fi »,
  /// « girls' love », « sci/fi », « sci.fi ».
  static final RegExp _separateurs = RegExp(r"[-_'’./]");

  static final RegExp _espaces = RegExp(r'\s+');

  /// Lettres accentuées courantes (français, espagnol, portugais, allemand)
  /// et leur forme sans accent.
  static const Map<String, String> _sansAccent = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
    'ß': 'ss',
  };

  static int _comparerParNom(Categorie a, Categorie b) {
    final parNom = a.nom.compareTo(b.nom);
    return parNom != 0 ? parNom : (a.id ?? 0).compareTo(b.id ?? 0);
  }

  // ------------------------------------------------------------- Erreurs

  /// Lecture : une erreur de base (modèle illisible ou base indisponible)
  /// devient une [ErreurService] lisible.
  static Future<T> _lire<T>(
    Future<T> Function() lecture, [
    String message = "Les catégories n'ont pas pu être lues.",
  ]) async {
    try {
      return await lecture();
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService(message, cause: erreur);
    } on DatabaseException catch (erreur) {
      throw ErreurService(message, cause: erreur);
    }
  }

  /// Écriture : un refus du dépôt (message déjà en français, par exemple
  /// « « survival » est la référence d'autres catégories : détachez-les
  /// d'abord. ») est rendu tel quel ; toute autre erreur reçoit le message
  /// générique [messageEchec].
  static Future<T> _ecrire<T>(
    Future<T> Function() ecriture,
    String messageEchec,
  ) async {
    try {
      return await ecriture();
    } on ErreurService {
      rethrow;
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService(erreur.message, cause: erreur);
    } on Exception catch (erreur) {
      // DatabaseException brute (base verrouillée, disque plein…) : jamais
      // jusqu'à l'interface.
      throw ErreurService(messageEchec, cause: erreur);
    }
  }
}
