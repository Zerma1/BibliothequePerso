/// État de l'écran Bibliothèque : titres filtrés, listes, catégories et ajout
/// d'un titre par URL.
library;

import 'dart:async';

import '../modeles/categorie.dart';
import '../modeles/constantes.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/titre.dart';
import '../services/service_bibliotheque.dart';
import 'constantes_etat.dart';
import 'description_erreur.dart';
import 'etat_titre.dart';

/// Titres de la bibliothèque, filtrés par liste, par catégorie et par
/// recherche.
class EtatBibliotheque extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire la base.
  EtatBibliotheque(this._service);

  final ServiceBibliotheque _service;

  List<Titre> _titres = const <Titre>[];
  List<ListeLecture> _listes = const <ListeLecture>[];
  List<Categorie> _categories = const <Categorie>[];
  Map<int, String> _urlsBaseSources = const <int, String>{};
  int? _idListe;
  int? _idCategorie;
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

  /// Toutes les listes (Favoris et Suivis d'abord).
  List<ListeLecture> get listes => _listes;

  /// Toutes les catégories connues.
  List<Categorie> get categories => _categories;

  /// Liste choisie comme filtre, ou `null` pour toutes.
  int? get idListeChoisie => _idListe;

  /// Catégorie choisie comme filtre, ou `null` pour toutes.
  int? get idCategorieChoisie => _idCategorie;

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

  /// `true` si un filtre ou une recherche est actif.
  bool get aUnFiltre =>
      _idListe != null || _idCategorie != null || _recherche.trim().isNotEmpty;

  /// `true` si le chargement a abouti sans aucun titre à afficher.
  bool get estVide => _estCharge && _erreur == null && _titres.isEmpty;

  /// Listes cochées par défaut lors de l'ajout d'un titre : Favoris et Suivis.
  Set<int> get idsListesParDefaut => <int>{
    for (final liste in _listes)
      if (liste.id != null &&
          (liste.nom == nomListeFavoris || liste.nom == nomListeSuivis))
        liste.id!,
  };

  /// Referer à envoyer pour la couverture de [titre] : l'URL de base de son
  /// site, que beaucoup de sites exigent pour servir leurs images. `null` si
  /// la source est inconnue.
  String? refererPour(Titre titre) {
    final idSource = titre.idSource;
    return idSource == null ? null : _urlsBaseSources[idSource];
  }

  /// Charge les listes, les catégories, les sites et les titres filtrés.
  Future<void> charger() async {
    final numero = ++_numeroChargement;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final listes = await _service.chargerListes();
      final categories = await _service.chargerCategories();
      final sources = await _service.chargerSources();
      // Un filtre qui désigne une liste ou une catégorie disparue est
      // abandonné, sinon la grille resterait vide sans raison visible.
      final idListe = listes.any((liste) => liste.id == _idListe)
          ? _idListe
          : null;
      final idCategorie =
          categories.any((categorie) => categorie.id == _idCategorie)
          ? _idCategorie
          : null;
      final recherche = _recherche.trim();
      final titres = await _service.chargerTitres(
        recherche: recherche.isEmpty ? null : recherche,
        idListe: idListe,
        idCategorie: idCategorie,
      );
      if (numero != _numeroChargement) {
        return;
      }
      _listes = listes;
      _categories = categories;
      _urlsBaseSources = <int, String>{
        for (final source in sources)
          if (source.id != null) source.id!: source.urlBase,
      };
      _idListe = idListe;
      _idCategorie = idCategorie;
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

  /// Filtre par liste ([idListe] `null` = toutes).
  Future<void> choisirListe(int? idListe) {
    _idListe = idListe;
    return charger();
  }

  /// Filtre par catégorie ([idCategorie] `null` = toutes).
  Future<void> choisirCategorie(int? idCategorie) {
    _idCategorie = idCategorie;
    return charger();
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
      resultat = ResultatAction<ResultatAjoutTitre>.reussite(
        await _service.ajouterTitreDepuisUrl(
          url.trim(),
          idsListes: idsListes.toList(),
        ),
      );
    } catch (erreur, pile) {
      resultat = ResultatAction<ResultatAjoutTitre>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
    _estEnAjout = false;
    await charger();
    return resultat;
  }

  /// Supprime un titre et ses chapitres, puis recharge la bibliothèque.
  Future<ResultatAction<bool>> supprimerTitre(int idTitre) async {
    try {
      await _service.supprimerTitre(idTitre);
      await charger();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Crée l'état de la fiche d'un titre (l'écran n'a pas accès au service).
  EtatTitre creerEtatTitre(int idTitre) => EtatTitre(_service, idTitre);

  @override
  void dispose() {
    _minuterieRecherche?.cancel();
    // Personne ne doit rester bloqué sur une recherche qui n'aura pas lieu.
    final attente = _rechercheEnAttente;
    if (attente != null && !attente.isCompleted) {
      attente.complete();
    }
    super.dispose();
  }
}
