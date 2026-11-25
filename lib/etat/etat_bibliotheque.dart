/// État de l'écran Bibliothèque : titres filtrés (liste, catégories, niveau
/// de contenu, recherche), listes, catégories et ajout d'un titre par URL.
library;

import 'dart:async';

import '../modeles/constantes.dart';
import '../modeles/journal.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../services/classement_listes.dart';
import '../services/service_bibliotheque.dart';
import '../services/service_categories.dart';
import '../services/service_parametres.dart';
import '../services/service_sources_par_defaut.dart';
import '../services/service_telechargement.dart';
import 'constantes_etat.dart';
import 'description_erreur.dart';
import 'etat_categories.dart';
import 'etat_titre.dart';

/// État d'une catégorie dans le filtre de la bibliothèque (trois états,
/// demande du client) : sans effet, exigée, ou interdite.
enum EtatFiltreCategorie {
  /// Sans effet sur le filtre.
  neutre,

  /// Le titre doit avoir cette catégorie.
  incluse,

  /// Le titre ne doit pas avoir cette catégorie.
  exclue,
}

/// Catégories qui commencent par la même [initiale] (panneau des
/// catégories).
typedef CategoriesParInitiale = ({String initiale, List<Categorie> categories});

/// Titres de la bibliothèque, filtrés par liste, par catégories, par niveau
/// de contenu et par recherche.
class EtatBibliotheque extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire la base.
  ///
  /// [serviceTelechargement] est transmis aux fiches des titres (état
  /// hors-ligne des chapitres, lecteur). [serviceParametres] fournit le
  /// filtre de niveau de contenu choisi par le client ; sans lui, tous les
  /// titres sont affichés.
  ///
  /// [serviceCategories] apporte les catégories regroupées : un groupe de
  /// même sens (« survie », « survival ») n'est qu'une entrée du panneau des
  /// filtres, le filtre se fait en une seule lecture, et la fiche d'un titre
  /// n'affiche pas de doublon. Sans lui (anciens tests), chaque catégorie
  /// est une entrée et le filtre lit la base une fois par catégorie.
  EtatBibliotheque(
    this._service, {
    this._serviceTelechargement,
    this._serviceParametres,
    this._serviceCategories,
  });

  final ServiceBibliotheque _service;
  final ServiceTelechargement? _serviceTelechargement;
  final ServiceParametres? _serviceParametres;
  final ServiceCategories? _serviceCategories;

  /// État de la gestion des groupes (Paramètres), créé à la demande et
  /// gardé pour la session (suggestions ignorées).
  EtatCategories? _etatCategories;

  List<Titre> _titres = const <Titre>[];
  List<ListeLecture> _listes = const <ListeLecture>[];
  List<Categorie> _categories = const <Categorie>[];

  /// Autres noms des groupes, par identifiant de référence (« survival »
  /// sous « survie »).
  Map<int, List<String>> _autresNoms = const <int, List<String>>{};
  int? _idListe;
  Set<int> _idsCategories = const <int>{};
  Set<int> _idsExclues = const <int>{};
  List<String>? _niveauxContenu;
  String _recherche = '';
  bool _estEnChargement = false;
  bool _estCharge = false;
  bool _estEnAjout = false;
  DescriptionErreur? _erreur;

  /// Numéro du dernier chargement lancé : une réponse plus ancienne (le
  /// client tape vite dans la recherche) est ignorée.
  int _numeroChargement = 0;

  /// Minuterie de la recherche en cours de frappe.
  Timer? _minuterieRecherche;

  /// Promesse rendue aux appels de [modifierRecherche] en attente.
  Completer<void>? _rechercheEnAttente;

  /// Titres qui correspondent aux filtres.
  List<Titre> get titres => _titres;

  /// Toutes les listes, dans l'ordre choisi par le client (système d'abord
  /// tant qu'il ne l'a pas changé : Favoris, Suivis, Planifié, En attente,
  /// Terminés).
  List<ListeLecture> get listes => _listes;

  /// Catégories proposées dans le filtre : avec les catégories regroupées,
  /// une seule entrée par groupe (sa référence) ; sinon toutes.
  List<Categorie> get categories => _categories;

  /// `true` si les catégories regroupées sont disponibles (section des
  /// Paramètres, filtres par groupe).
  bool get gereCategoriesRegroupees => _serviceCategories != null;

  /// Autres noms du groupe dont [idCategorie] est la référence (vide si ce
  /// n'est pas une référence), triés.
  List<String> autresNoms(int idCategorie) =>
      _autresNoms[idCategorie] ?? const <String>[];

  /// État de la gestion des catégories regroupées, partagé pour la session
  /// (créé au premier appel), ou `null` sans service de catégories. Chaque
  /// modification relit la bibliothèque et ses filtres.
  EtatCategories? get etatCategories {
    final service = _serviceCategories;
    if (service == null || estLibere) return null;
    return _etatCategories ??= EtatCategories(
      service,
      surModification: charger,
    );
  }

  /// Liste choisie comme filtre, ou `null` pour toutes.
  int? get idListeChoisie => _idListe;

  /// Catégories incluses : un titre affiché les a toutes (vide : aucune
  /// exigence).
  Set<int> get idsCategoriesChoisies => _idsCategories;

  /// Catégories exclues : un titre affiché n'en a aucune.
  Set<int> get idsCategoriesExclues => _idsExclues;

  /// Catégorie incluse si une seule l'est (et aucune exclue), sinon `null`.
  int? get idCategorieChoisie =>
      _idsCategories.length == 1 && _idsExclues.isEmpty
      ? _idsCategories.single
      : null;

  /// Nombre de catégories incluses ou exclues (badge de l'entonnoir).
  int get nombreFiltresCategories => _idsCategories.length + _idsExclues.length;

  /// État de [idCategorie] dans le filtre.
  EtatFiltreCategorie etatCategorie(int idCategorie) {
    if (_idsCategories.contains(idCategorie)) {
      return EtatFiltreCategorie.incluse;
    }
    if (_idsExclues.contains(idCategorie)) return EtatFiltreCategorie.exclue;
    return EtatFiltreCategorie.neutre;
  }

  /// Niveaux de contenu affichés (`null` : pas de filtre, faute de réglage).
  List<String>? get niveauxContenuChoisis => _niveauxContenu;

  /// `true` si le filtre de niveau de contenu est disponible (réglage
  /// branché).
  bool get gereNiveauxContenu => _serviceParametres != null;

  /// `true` si le filtre de niveau de contenu vaut la valeur par défaut
  /// (tout sauf `pornographic`).
  bool get estNiveauxParDefaut {
    final choisis = _niveauxContenu;
    return choisis == null ||
        (choisis.length == niveauxContenuParDefaut.length &&
            choisis.every(niveauxContenuParDefaut.contains));
  }

  /// Texte de recherche courant.
  String get recherche => _recherche;

  /// `true` pendant un chargement.
  bool get estEnChargement => _estEnChargement;

  /// `true` une fois qu'un chargement a abouti.
  bool get estCharge => _estCharge;

  /// `true` pendant l'ajout d'un titre.
  bool get estEnAjout => _estEnAjout;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` si un filtre (liste, catégories, niveau de contenu modifié) ou
  /// une recherche est actif.
  bool get aUnFiltre =>
      _idListe != null ||
      _idsCategories.isNotEmpty ||
      _idsExclues.isNotEmpty ||
      !estNiveauxParDefaut ||
      _recherche.trim().isNotEmpty;

  /// `true` si le chargement a abouti sans aucun titre à afficher.
  bool get estVide => _estCharge && _erreur == null && _titres.isEmpty;

  /// Listes cochées par défaut lors de l'ajout d'un titre : Suivis
  /// seulement (retour X3 du client sur la 0.2.1-test : Favoris reste
  /// proposée, mais décochée).
  Set<int> get idsListesParDefaut => <int>{
    for (final liste in _listes)
      if (liste.id != null && liste.nom == nomListeSuivis) liste.id!,
  };

  /// `true` si [liste] est tenue automatiquement par l'application (« En
  /// attente ») : le client ne peut pas y ranger un titre à la main.
  bool estListeAutomatique(ListeLecture liste) =>
      ClassementListes.listesAutomatiques.contains(liste.nom);

  /// `true` si [liste] peut être renommée et supprimée par le client (liste
  /// personnelle) ; les listes système (Favoris, Suivis, Planifié, En
  /// attente, Terminés) ne le peuvent pas.
  bool estListeModifiable(ListeLecture liste) =>
      liste.id != null && !liste.estSysteme;

  // ------------------------------------------- Listes personnelles (X4)

  /// Crée une liste personnelle nommée [nom], puis relit la bibliothèque.
  /// Le service nettoie le nom et refuse un nom vide, trop long ou déjà
  /// pris.
  Future<ResultatAction<ListeLecture>> creerListe(String nom) =>
      _modifierListes(() => _service.creerListe(nom));

  /// Renomme la liste personnelle [idListe], puis relit la bibliothèque.
  Future<ResultatAction<ListeLecture>> renommerListe(int idListe, String nom) =>
      _modifierListes(() => _service.renommerListe(idListe, nom));

  /// Supprime la liste personnelle [idListe] (ses titres restent dans la
  /// bibliothèque), puis relit la bibliothèque. Un filtre posé sur cette
  /// liste est abandonné au rechargement.
  Future<ResultatAction<bool>> supprimerListe(int idListe) =>
      _modifierListes(() async {
        await _service.supprimerListe(idListe);
        return true;
      });

  /// Enregistre l'ordre d'affichage des listes ([idsDansLOrdre] : de la
  /// première à la dernière).
  ///
  /// L'ordre est appliqué tout de suite à l'écran (glisser-déposer sans
  /// saut), puis enregistré ; en cas d'échec, la bibliothèque est relue et
  /// l'ancien ordre revient.
  Future<ResultatAction<bool>> reordonnerListes(List<int> idsDansLOrdre) async {
    final parId = <int, ListeLecture>{
      for (final liste in _listes)
        if (liste.id != null) liste.id!: liste,
    };
    _listes = <ListeLecture>[
      for (final id in idsDansLOrdre) ?parId[id],
      for (final liste in _listes)
        if (!idsDansLOrdre.contains(liste.id)) liste,
    ];
    notifier();
    try {
      _listes = await _service.reordonnerListes(idsDansLOrdre);
      notifier();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      await charger();
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Déroulement commun aux changements de listes : action du service puis
  /// relecture de la bibliothèque (puces, filtre).
  Future<ResultatAction<T>> _modifierListes<T>(
    Future<T> Function() action,
  ) async {
    try {
      final resultat = await action();
      await charger();
      return ResultatAction<T>.reussite(resultat);
    } catch (erreur, pile) {
      return ResultatAction<T>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  // ------------------------------------------ Recherche sur MangaDex (X6)

  /// Cherche [requete] sur MangaDex (onglet « Rechercher » du dialogue
  /// d'ajout). Les résultats ne sont pas enregistrés : le client en choisit
  /// un, qui est ensuite ajouté par son adresse ([ajouterTitre]).
  ///
  /// Le site MangaDex configuré est utilisé s'il existe, sinon la source
  /// MangaDex par défaut (non enregistrée) : une recherche ne crée rien.
  Future<ResultatAction<List<Titre>>> rechercherSurMangaDex(
    String requete,
  ) async {
    final texte = requete.trim();
    if (texte.isEmpty) {
      return const ResultatAction<List<Titre>>.reussite(<Titre>[]);
    }
    try {
      final sources = await _service.chargerSources();
      final source =
          sources
              .where((source) => source.typeSource == TypeSource.mangaDex)
              .firstOrNull ??
          sourcesParDefaut
              .firstWhere((defaut) => defaut.typeSource == TypeSource.mangaDex)
              .versSource();
      return ResultatAction<List<Titre>>.reussite(
        await _service.rechercherSurSource(source, texte),
      );
    } catch (erreur, pile) {
      return ResultatAction<List<Titre>>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
  }

  /// Catégories qui contiennent [filtre] (sans tenir compte de la casse ni
  /// des accents), regroupées par initiale (« A », « B »… ; « # » pour un
  /// chiffre ou un symbole) et triées : le panneau des catégories reste
  /// lisible même avec des centaines de tags.
  ///
  /// Une référence de groupe est aussi trouvée par ses autres noms :
  /// chercher « survival » montre « survie ».
  List<CategoriesParInitiale> grouperCategories(String filtre) {
    final recherche = sansAccents(filtre.trim().toLowerCase());
    bool correspond(String nom) =>
        sansAccents(nom.toLowerCase()).contains(recherche);
    final retenues =
        _categories
            .where(
              (categorie) =>
                  correspond(categorie.nom) ||
                  (categorie.id != null &&
                      autresNoms(categorie.id!).any(correspond)),
            )
            .toList()
          ..sort(
            (a, b) =>
                sansAccents(a.nom.toLowerCase())
                    .compareTo(sansAccents(b.nom.toLowerCase())),
          );
    final groupes = <String, List<Categorie>>{};
    for (final categorie in retenues) {
      final premiere = sansAccents(categorie.nom.trim().toUpperCase());
      final initiale = premiere.isEmpty ? '#' : premiere[0];
      final cle = RegExp('[A-Z]').hasMatch(initiale) ? initiale : '#';
      groupes.putIfAbsent(cle, () => <Categorie>[]).add(categorie);
    }
    final cles = groupes.keys.toList()
      ..sort((a, b) {
        // « # » en dernier : les tags alphabétiques sont les plus cherchés.
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return <CategoriesParInitiale>[
      for (final cle in cles) (initiale: cle, categories: groupes[cle]!),
    ];
  }

  /// Catégories qui comptent dans le filtre (incluses ou exclues), dans
  /// l'ordre alphabétique.
  List<Categorie> get categoriesFiltrees =>
      _categories
          .where(
            (categorie) =>
                _idsCategories.contains(categorie.id) ||
                _idsExclues.contains(categorie.id),
          )
          .toList()
        ..sort((a, b) => a.nom.compareTo(b.nom));

  /// [texte] sans les accents courants (é → e, ç → c…), pour la recherche
  /// et le tri des catégories.
  static String sansAccents(String texte) {
    const avec = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸ';
    const sans = 'aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUYY';
    final tampon = StringBuffer();
    for (final rune in texte.runes) {
      final caractere = String.fromCharCode(rune);
      final index = avec.indexOf(caractere);
      tampon.write(index < 0 ? caractere : sans[index]);
    }
    return tampon.toString();
  }

  /// Charge les listes, les catégories, le filtre de niveau de contenu et
  /// les titres filtrés.
  Future<void> charger() async {
    final numero = ++_numeroChargement;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final listes = await _service.chargerListes();
      final serviceCategories = _serviceCategories;
      final List<Categorie> categories;
      // Catégorie rattachée → sa référence : un filtre posé sur une
      // catégorie qui vient d'être regroupée suit son groupe.
      final versReference = <int, int>{};
      final autresNoms = <int, List<String>>{};
      if (serviceCategories == null) {
        categories = await _service.chargerCategories();
      } else {
        categories = await serviceCategories.chargerCategoriesEffectives();
        for (final groupe in await serviceCategories.chargerGroupes()) {
          final idReference = groupe.reference.id;
          if (idReference == null) continue;
          autresNoms[idReference] = <String>[
            for (final categorie in groupe.rattachees) categorie.nom,
          ]..sort();
          for (final categorie in groupe.rattachees) {
            final id = categorie.id;
            if (id != null) versReference[id] = idReference;
          }
        }
      }
      final niveaux = await _serviceParametres?.chargerNiveauxContenu();
      // Un filtre qui désigne une liste ou une catégorie disparue est
      // abandonné, sinon la grille resterait vide sans raison visible.
      final idListe = listes.any((liste) => liste.id == _idListe)
          ? _idListe
          : null;
      final idsConnus = <int>{
        for (final categorie in categories)
          if (categorie.id != null) categorie.id!,
      };
      Set<int> connues(Set<int> ids) =>
          <int>{for (final id in ids) versReference[id] ?? id}
              .where(idsConnus.contains)
              .toSet();
      final exclues = connues(_idsExclues);
      // Deux catégories regroupées, l'une incluse et l'autre exclue : comme
      // dans le panneau, l'exclusion l'emporte.
      final incluses = connues(_idsCategories).difference(exclues);
      final titres = await _chargerTitresFiltres(
        idListe: idListe,
        incluses: incluses,
        exclues: exclues,
        niveaux: niveaux,
      );
      if (numero != _numeroChargement) {
        return;
      }
      _listes = listes;
      _categories = categories;
      _autresNoms = autresNoms;
      _niveauxContenu = niveaux;
      _idListe = idListe;
      _idsCategories = incluses;
      _idsExclues = exclues;
      _titres = titres;
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

  /// Titres filtrés : toutes les catégories [incluses] et aucune des
  /// [exclues] (demande du client).
  ///
  /// Avec le service des catégories, une seule lecture fait tout (chaque
  /// filtre porte sur le groupe de la catégorie). Sans lui (repli des
  /// anciens tests), le service de la bibliothèque ne filtre que sur une
  /// catégorie à la fois : une lecture par catégorie, puis l'intersection
  /// des incluses moins l'union des exclues, dans l'ordre de la lecture
  /// sans filtre de catégorie.
  Future<List<Titre>> _chargerTitresFiltres({
    required int? idListe,
    required Set<int> incluses,
    required Set<int> exclues,
    required List<String>? niveaux,
  }) async {
    final texte = _recherche.trim();
    final serviceCategories = _serviceCategories;
    if (serviceCategories != null) {
      return serviceCategories.chargerTitresFiltres(
        recherche: texte.isEmpty ? null : texte,
        idListe: idListe,
        idsCategoriesIncluses: incluses,
        idsCategoriesExclues: exclues,
        niveauxContenu: niveaux,
      );
    }
    Future<List<Titre>> lire(int? idCategorie) => _service.chargerTitres(
      recherche: texte.isEmpty ? null : texte,
      idListe: idListe,
      idCategorie: idCategorie,
      niveauxContenu: niveaux,
    );
    if (exclues.isEmpty && incluses.length <= 1) {
      return lire(incluses.firstOrNull);
    }
    Set<int> ids(List<Titre> titres) => <int>{
      for (final titre in titres)
        if (titre.id != null) titre.id!,
    };
    final tous = await lire(null);
    var retenus = ids(tous);
    for (final idCategorie in incluses) {
      retenus = retenus.intersection(ids(await lire(idCategorie)));
    }
    for (final idCategorie in exclues) {
      retenus = retenus.difference(ids(await lire(idCategorie)));
    }
    return <Titre>[
      for (final titre in tous)
        if (retenus.contains(titre.id)) titre,
    ];
  }

  /// Filtre par liste ([idListe] `null` = toutes).
  Future<void> choisirListe(int? idListe) {
    _idListe = idListe;
    return charger();
  }

  /// Filtre sur une seule catégorie incluse ([idCategorie] `null` = toutes).
  Future<void> choisirCategorie(int? idCategorie) => appliquerFiltreCategories(
    incluses: idCategorie == null ? <int>{} : <int>{idCategorie},
    exclues: <int>{},
  );

  /// Applique le filtre choisi dans le panneau : titres qui ont toutes les
  /// [incluses] et aucune des [exclues]. Une catégorie présente dans les
  /// deux est considérée comme exclue.
  Future<void> appliquerFiltreCategories({
    required Set<int> incluses,
    required Set<int> exclues,
  }) {
    _idsExclues = Set<int>.unmodifiable(exclues);
    _idsCategories = Set<int>.unmodifiable(incluses.difference(exclues));
    return charger();
  }

  /// « Toutes » : retire tout filtre de catégorie.
  Future<void> effacerFiltreCategories() =>
      appliquerFiltreCategories(incluses: <int>{}, exclues: <int>{});

  /// Enregistre les niveaux de contenu affichés (réglage gardé d'une
  /// session à l'autre, qui sert aussi aux recherches sur MangaDex) puis
  /// recharge la bibliothèque.
  Future<ResultatAction<bool>> modifierNiveauxContenu(
    Set<String> niveaux,
  ) async {
    final parametres = _serviceParametres;
    if (parametres == null) {
      return const ResultatAction<bool>.reussite(false);
    }
    try {
      await parametres.enregistrerNiveauxContenu(niveaux);
      await charger();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Remet le filtre de niveau de contenu à sa valeur par défaut.
  Future<ResultatAction<bool>> reinitialiserNiveauxContenu() async {
    final parametres = _serviceParametres;
    if (parametres == null) {
      return const ResultatAction<bool>.reussite(false);
    }
    try {
      await parametres.reinitialiserNiveauxContenu();
      await charger();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Change le texte de recherche (nom ou titre alternatif).
  ///
  /// Le chargement part [delaiAvantRecherche] après la dernière frappe, sauf
  /// si [immediat] vaut `true` (bouton « effacer »). Le Future se termine
  /// une fois la bibliothèque rechargée.
  Future<void> modifierRecherche(String texte, {bool immediat = false}) {
    if (texte == _recherche && _minuterieRecherche == null) {
      return Future<void>.value();
    }
    _recherche = texte;
    // Notification immédiate : le champ (bouton « effacer ») suit la saisie
    // même avant le rechargement.
    notifier();
    _minuterieRecherche?.cancel();
    _minuterieRecherche = null;
    final attente = _rechercheEnAttente ??= Completer<void>();
    if (immediat) {
      _lancerRecherche(attente);
    } else {
      _minuterieRecherche = Timer(
        delaiAvantRecherche,
        () => _lancerRecherche(attente),
      );
    }
    return attente.future;
  }

  Future<void> _lancerRecherche(Completer<void> attente) async {
    _minuterieRecherche = null;
    _rechercheEnAttente = null;
    await charger();
    if (!attente.isCompleted) {
      attente.complete();
    }
  }

  /// Ajoute le titre situé à [url] et le range dans [idsListes].
  ///
  /// Recharge la bibliothèque dans tous les cas : même en cas d'échec, un
  /// site (MangaDex) ou un titre a pu être enregistré avant l'erreur.
  Future<ResultatAction<ResultatAjoutTitre>> ajouterTitre(
    String url,
    Set<int> idsListes,
  ) async {
    if (url.trim().isEmpty) {
      return const ResultatAction<ResultatAjoutTitre>.echec(
        DescriptionErreur(NatureErreur.adresseVide),
      );
    }
    _estEnAjout = true;
    notifier();
    ResultatAction<ResultatAjoutTitre> resultat;
    try {
      final ajout = await _service.ajouterTitreDepuisUrl(
        url.trim(),
        idsListes: idsListes.toList(),
      );
      resultat = ResultatAction<ResultatAjoutTitre>.reussite(ajout);
      // E11 : sans cet appel, un titre ajouté en Favoris / Suivis n'avait
      // aucun chapitre en file avant le redémarrage suivant.
      await _appliquerRegles(ajout.titre.id);
    } catch (erreur, pile) {
      resultat = ResultatAction<ResultatAjoutTitre>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
    _estEnAjout = false;
    await charger();
    return resultat;
  }

  /// Demande au service d'appliquer les règles de téléchargement au titre
  /// [idTitre] (le service ne fait rien hors de Favoris et Suivis).
  ///
  /// Une erreur ici ne fait pas échouer l'ajout, déjà enregistré : elle est
  /// journalisée, et les règles seront réappliquées plus tard (démarrage,
  /// mises à jour, réglages).
  Future<void> _appliquerRegles(int? idTitre) async {
    final service = _serviceTelechargement;
    if (service == null || idTitre == null) return;
    try {
      await service.appliquerRegles(idTitre);
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Règles de téléchargement non appliquées au titre n°$idTitre',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  /// Supprime un titre, ses chapitres et leurs archives hors-ligne, puis
  /// recharge la bibliothèque.
  Future<ResultatAction<bool>> supprimerTitre(int idTitre) async {
    try {
      final telechargement = _serviceTelechargement;
      if (telechargement != null) {
        // Le service des téléchargements efface aussi les fichiers `.zip` ;
        // `ServiceBibliotheque.supprimerTitre` les laisserait sur le disque.
        await telechargement.supprimerTitre(idTitre);
      } else {
        await _service.supprimerTitre(idTitre);
      }
      await charger();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Crée l'état de la fiche d'un titre (l'écran n'a pas accès au service).
  EtatTitre creerEtatTitre(int idTitre) => EtatTitre(
    _service,
    idTitre,
    serviceTelechargement: _serviceTelechargement,
    serviceCategories: _serviceCategories,
  );

  @override
  void dispose() {
    _etatCategories?.dispose();
    _etatCategories = null;
    _minuterieRecherche?.cancel();
    // Personne ne doit rester bloqué sur une recherche qui n'aura pas lieu.
    final attente = _rechercheEnAttente;
    if (attente != null && !attente.isCompleted) {
      attente.complete();
    }
    super.dispose();
  }
}
