/// État de la fiche d'un titre : informations, listes, catégories et
/// chapitres.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../modeles/categorie.dart';
import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/telechargement.dart';
import '../modeles/titre.dart';
import '../services/service_bibliotheque.dart';
import '../services/service_telechargement.dart';
import 'description_erreur.dart';
import 'etat_lecteur.dart';
import 'outils_chapitres.dart';

/// Fiche d'un titre et actions sur ses chapitres et ses listes.
class EtatTitre extends EtatNotifiant {
  /// Crée l'état du titre [idTitre] ; appeler [charger] pour lire la base.
  ///
  /// Sans [serviceTelechargement], la fiche n'affiche pas l'état hors-ligne
  /// des chapitres (tests de l'étape 3).
  EtatTitre(
    this._service,
    this.idTitre, {
    ServiceTelechargement? serviceTelechargement,
  }) : _serviceTelechargement = serviceTelechargement {
    // La file change à chaque page téléchargée : la fiche suit la
    // progression de ses chapitres sans que le client ne recharge.
    _abonnement = serviceTelechargement?.changements.listen(
      (_) => unawaited(_relireTelechargements()),
    );
  }

  final ServiceBibliotheque _service;
  final ServiceTelechargement? _serviceTelechargement;
  StreamSubscription<void>? _abonnement;

  /// Identifiant du titre affiché.
  final int idTitre;

  /// Lignes de la file de téléchargement des chapitres de ce titre.
  Map<int, Telechargement> _telechargements = const <int, Telechargement>{};

  /// Versions regroupées par numéro, du plus récent au plus ancien.
  List<GroupeChapitres> _groupes = const <GroupeChapitres>[];

  Titre? _titre;
  Source? _source;
  List<Categorie> _categories = const <Categorie>[];
  List<ListeLecture> _listes = const <ListeLecture>[];
  Set<int> _idsListesDuTitre = const <int>{};
  List<Chapitre> _chapitres = const <Chapitre>[];
  bool _estEnChargement = false;
  bool _estEnActualisation = false;
  DescriptionErreur? _erreur;

  /// Titre chargé, ou `null` avant le chargement ou en cas d'erreur.
  Titre? get titre => _titre;

  /// Site d'où vient le titre, si connu.
  Source? get source => _source;

  /// Catégories du titre.
  List<Categorie> get categories => _categories;

  /// Toutes les listes, pour les puces cochables.
  List<ListeLecture> get listes => _listes;

  /// Identifiants des listes qui contiennent le titre.
  Set<int> get idsListesDuTitre => _idsListesDuTitre;

  /// Chapitres triés par numéro décroissant (le plus récent en haut).
  List<Chapitre> get chapitres => _chapitres;

  /// `true` pendant le chargement initial.
  bool get estEnChargement => _estEnChargement;

  /// `true` pendant la relecture du site.
  bool get estEnActualisation => _estEnActualisation;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` si les données viennent de MangaDex, qui doit être crédité
  /// (PLAYBOOK.md section 6, règles d'usage).
  bool get estMangaDex => _source?.typeSource == TypeSource.mangaDex;

  /// Nombre de chapitres non lus.
  int get nombreNonLus =>
      _chapitres.where((chapitre) => !chapitre.estLu).length;

  /// `true` si les téléchargements sont disponibles (service branché).
  bool get gereTelechargements => _serviceTelechargement != null;

  /// Chapitres regroupés par numéro (une ligne par numéro, la version
  /// téléchargée par le service en premier), du plus récent au plus ancien.
  List<GroupeChapitres> get groupes => _groupes;

  /// Nombre de numéros distincts.
  int get nombreNumeros => _groupes.length;

  /// Nombre de numéros dont aucune version n'est lue.
  int get nombreNumerosNonLus =>
      _groupes.where((groupe) => !groupe.estLu).length;

  /// État hors-ligne d'un chapitre (téléchargé, en file, en cours…).
  EtatHorsLigne etatHorsLigne(Chapitre chapitre) {
    final id = chapitre.id;
    return EtatHorsLigne.depuis(
      chapitre,
      id == null ? null : _telechargements[id],
    );
  }

  /// Numéro de la dernière lecture de la base : une réponse plus ancienne
  /// (chargement relancé, actualisation terminée entre-temps) est ignorée.
  int _numeroLecture = 0;

  /// Charge la fiche complète depuis la base.
  Future<void> charger() async {
    final numero = ++_numeroLecture;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final donnees = await _lireBase();
      if (numero != _numeroLecture) {
        return;
      }
      _appliquer(donnees);
    } on _TitreIntrouvable {
      if (numero != _numeroLecture) {
        return;
      }
      _signalerIntrouvable();
    } catch (erreur, pile) {
      if (numero != _numeroLecture) {
        return;
      }
      _erreur = DescriptionErreur.depuis(erreur, pile);
    }
    _estEnChargement = false;
    notifier();
  }

  /// Relit la fiche et les chapitres sur le site, et renvoie le nombre de
  /// nouveaux chapitres.
  Future<ResultatAction<int>> actualiser() async {
    final titre = _titre;
    if (titre == null) {
      return const ResultatAction<int>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    _estEnActualisation = true;
    notifier();
    try {
      final resultat = await _service.actualiserTitre(titre);
      // Nouvelle génération : un chargement plus ancien encore en cours ne
      // doit pas écraser les données relues après l'actualisation.
      final numero = ++_numeroLecture;
      final donnees = await _lireBase();
      if (numero == _numeroLecture) {
        _appliquer(donnees);
      }
      return ResultatAction<int>.reussite(resultat.nombreNouveauxChapitres);
    } on _TitreIntrouvable {
      // Sans erreur définie, l'écran attendrait un titre qui ne viendra
      // jamais (chargement infini).
      _signalerIntrouvable();
      return const ResultatAction<int>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    } catch (erreur, pile) {
      return ResultatAction<int>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnActualisation = false;
      notifier();
    }
  }

  /// Marque [chapitre] lu (ou non lu si [estLu] vaut `false`).
  Future<ResultatAction<bool>> marquerLu(
    Chapitre chapitre, {
    bool estLu = true,
  }) async {
    final idChapitre = chapitre.id;
    if (idChapitre == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await _service.marquerLu(idChapitre, estLu: estLu);
      // Mise à jour locale plutôt qu'un rechargement complet : la liste ne
      // saute pas et l'action reste instantanée sur un long titre.
      _chapitres = <Chapitre>[
        for (final existant in _chapitres)
          existant.id == idChapitre
              ? existant.copierAvec(estLu: estLu)
              : existant,
      ];
      _mettreAJourNonLus();
      _regrouper();
      notifier();
      // La lecture fait avancer la fenêtre des titres suivis (et change les
      // lus gardés des favoris) : le service met la file à jour.
      await _appliquerRegles();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Marque toutes les versions du [groupe] lues (ou non lues) : pour le
  /// client, un numéro est lu ou ne l'est pas, quelle que soit la langue.
  Future<ResultatAction<bool>> marquerGroupeLu(
    GroupeChapitres groupe, {
    bool estLu = true,
  }) async {
    try {
      final ids = <int>{
        for (final chapitre in groupe.versions)
          if (chapitre.id != null && chapitre.estLu != estLu) chapitre.id!,
      };
      for (final id in ids) {
        await _service.marquerLu(id, estLu: estLu);
      }
      _chapitres = <Chapitre>[
        for (final existant in _chapitres)
          ids.contains(existant.id)
              ? existant.copierAvec(estLu: estLu)
              : existant,
      ];
      _mettreAJourNonLus();
      _regrouper();
      notifier();
      await _appliquerRegles();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Marque tous les chapitres lus (ou non lus si [estLu] vaut `false`).
  Future<ResultatAction<bool>> marquerTousLus({bool estLu = true}) async {
    try {
      await _service.marquerTousLus(idTitre, estLu: estLu);
      _chapitres = <Chapitre>[
        for (final existant in _chapitres) existant.copierAvec(estLu: estLu),
      ];
      _mettreAJourNonLus();
      _regrouper();
      notifier();
      await _appliquerRegles();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Ajoute le titre à la liste [idListe].
  Future<ResultatAction<bool>> ajouterALaListe(int idListe) async {
    try {
      await _service.ajouterTitreALaListe(idListe, idTitre);
      _idsListesDuTitre = <int>{..._idsListesDuTitre, idListe};
      notifier();
      await _appliquerReglesSiSysteme(idListe);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Retire le titre de la liste [idListe] (le titre reste dans la
  /// bibliothèque).
  Future<ResultatAction<bool>> retirerDeLaListe(int idListe) async {
    try {
      await _service.retirerTitreDeLaListe(idListe, idTitre);
      _idsListesDuTitre = <int>{
        for (final id in _idsListesDuTitre)
          if (id != idListe) id,
      };
      notifier();
      await _appliquerReglesSiSysteme(idListe);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  // ------------------------------------------------------- Téléchargements

  /// Ajoute [chapitre] à la file de téléchargement (ou relance un échec).
  Future<ResultatAction<bool>> telecharger(Chapitre chapitre) async {
    final service = _serviceTelechargement;
    final id = chapitre.id;
    if (service == null || id == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await service.telechargerChapitre(id);
      await _relireTelechargements();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Supprime l'archive de [chapitre] (ou le retire de la file).
  ///
  /// LIMITE : pour un titre favori ou suivi, les règles automatiques peuvent
  /// le télécharger de nouveau plus tard s'il fait encore partie des
  /// chapitres voulus.
  Future<ResultatAction<bool>> supprimerTelechargement(
    Chapitre chapitre,
  ) async {
    final service = _serviceTelechargement;
    final id = chapitre.id;
    if (service == null || id == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await service.supprimerTelechargement(id);
      await _relireTelechargements(relireChapitres: true);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Crée l'état du lecteur ouvert sur [chapitre], ou `null` si les
  /// téléchargements ne sont pas disponibles.
  EtatLecteur? creerEtatLecteur(Chapitre chapitre) {
    final service = _serviceTelechargement;
    final id = chapitre.id;
    if (service == null || id == null) return null;
    return EtatLecteur(
      serviceBibliotheque: _service,
      serviceTelechargement: service,
      idTitre: idTitre,
      idChapitre: id,
    );
  }

  /// Applique les règles de conservation si [idListe] est Favoris ou Suivis
  /// (les seules listes qui déclenchent des téléchargements).
  Future<void> _appliquerReglesSiSysteme(int idListe) async {
    final liste = _listes.where((liste) => liste.id == idListe).firstOrNull;
    if (liste == null ||
        liste.nom == nomListeFavoris ||
        liste.nom == nomListeSuivis) {
      await _appliquerRegles();
    }
  }

  /// Demande au service d'appliquer les règles de conservation à ce titre.
  ///
  /// Une erreur ici n'annule pas l'action du client (déjà enregistrée) : elle
  /// est seulement journalisée, les règles seront réappliquées plus tard.
  Future<void> _appliquerRegles() async {
    final service = _serviceTelechargement;
    if (service == null) return;
    try {
      await service.appliquerRegles(idTitre);
    } catch (erreur, pile) {
      debugPrint('Règles de téléchargement non appliquées : $erreur\n$pile');
    }
    await _relireTelechargements(relireChapitres: true);
  }

  /// Relit la file pour les chapitres de ce titre ; relit aussi les
  /// chapitres si un téléchargement s'est terminé ou a été retiré (le
  /// marqueur « téléchargé » a changé en base).
  Future<void> _relireTelechargements({bool relireChapitres = false}) async {
    final service = _serviceTelechargement;
    if (service == null || estLibere) return;
    try {
      final idsChapitres = <int>{
        for (final chapitre in _chapitres)
          if (chapitre.id != null) chapitre.id!,
      };
      final file = await service.chargerFile();
      final nouveaux = <int, Telechargement>{
        for (final telechargement in file)
          if (idsChapitres.contains(telechargement.idChapitre))
            telechargement.idChapitre: telechargement,
      };
      final anciens = _telechargements;
      final statutsChanges =
          anciens.length != nouveaux.length ||
          nouveaux.entries.any(
            (entree) => anciens[entree.key]?.statut != entree.value.statut,
          );
      _telechargements = nouveaux;
      if ((relireChapitres || statutsChanges) && _titre != null) {
        final chapitres = await _service.chargerChapitres(idTitre);
        _chapitres = _trier(chapitres);
        _mettreAJourNonLus();
        _regrouper();
      }
      notifier();
    } catch (erreur, pile) {
      // Un échec de lecture de la file ne doit pas masquer la fiche.
      debugPrint('File de téléchargement illisible : $erreur\n$pile');
    }
  }

  /// Lit toutes les données du titre sans modifier l'état ; lève une erreur
  /// en cas d'échec. L'appelant décide d'appliquer ou non le résultat.
  Future<_DonneesTitre> _lireBase() async {
    final titre = await _service.chargerTitre(idTitre);
    if (titre == null) {
      throw const _TitreIntrouvable();
    }
    final idSource = titre.idSource;
    final source = idSource == null
        ? null
        : await _service.chargerSource(idSource);
    final categories = await _service.chargerCategoriesDuTitre(idTitre);
    final listes = await _service.chargerListes();
    final listesDuTitre = await _service.chargerListesDuTitre(idTitre);
    final chapitres = await _service.chargerChapitres(idTitre);
    final tries = _trier(chapitres);
    final service = _serviceTelechargement;
    final idsChapitres = <int>{
      for (final chapitre in tries)
        if (chapitre.id != null) chapitre.id!,
    };
    final telechargements = service == null
        ? const <int, Telechargement>{}
        : <int, Telechargement>{
            for (final telechargement in await service.chargerFile())
              if (idsChapitres.contains(telechargement.idChapitre))
                telechargement.idChapitre: telechargement,
          };

    return (
      titre: titre,
      source: source,
      categories: categories,
      listes: listes,
      idsListesDuTitre: <int>{
        for (final liste in listesDuTitre)
          if (liste.id != null) liste.id!,
      },
      chapitres: tries,
      telechargements: telechargements,
    );
  }

  /// Le dépôt trie par numéro croissant ; la fiche montre le plus récent en
  /// haut. À numéro égal (plusieurs langues), le plus récemment enregistré
  /// passe d'abord.
  static List<Chapitre> _trier(List<Chapitre> chapitres) {
    return List<Chapitre>.of(chapitres)..sort((a, b) {
      final parNumero = b.numero.compareTo(a.numero);
      return parNumero != 0 ? parNumero : (b.id ?? 0).compareTo(a.id ?? 0);
    });
  }

  void _appliquer(_DonneesTitre donnees) {
    _titre = donnees.titre;
    _source = donnees.source;
    _categories = donnees.categories;
    _listes = donnees.listes;
    _idsListesDuTitre = donnees.idsListesDuTitre;
    _chapitres = donnees.chapitres;
    _telechargements = donnees.telechargements;
    _regrouper();
  }

  /// Une ligne par numéro, la plus récente en haut.
  void _regrouper() {
    _groupes = regrouperParNumero(
      _chapitres,
      languesPreferees(_source),
    ).reversed.toList();
  }

  @override
  void dispose() {
    unawaited(_abonnement?.cancel());
    super.dispose();
  }

  void _signalerIntrouvable() {
    _titre = null;
    _erreur = const DescriptionErreur(NatureErreur.introuvable);
  }

  void _mettreAJourNonLus() {
    final titre = _titre;
    if (titre != null) {
      _titre = titre.copierAvec(nombreChapitresNonLus: nombreNonLus);
    }
  }
}

/// Données d'un titre lues en une fois dans la base.
typedef _DonneesTitre = ({
  Titre titre,
  Source? source,
  List<Categorie> categories,
  List<ListeLecture> listes,
  Set<int> idsListesDuTitre,
  List<Chapitre> chapitres,
  Map<int, Telechargement> telechargements,
});

/// Signal interne : le titre n'existe plus en base.
class _TitreIntrouvable implements Exception {
  const _TitreIntrouvable();
}
