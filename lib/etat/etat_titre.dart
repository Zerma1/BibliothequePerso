/// État de la fiche d'un titre : informations, listes, catégories et
/// chapitres.
library;

import '../modeles/categorie.dart';
import '../modeles/chapitre.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../services/service_bibliotheque.dart';
import 'description_erreur.dart';

/// Fiche d'un titre et actions sur ses chapitres et ses listes.
class EtatTitre extends EtatNotifiant {
  /// Crée l'état du titre [idTitre] ; appeler [charger] pour lire la base.
  EtatTitre(this._service, this.idTitre);

  final ServiceBibliotheque _service;

  /// Identifiant du titre affiché.
  final int idTitre;

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
          existant.id == idChapitre ? existant.copierAvec(estLu: estLu) : existant,
      ];
      _mettreAJourNonLus();
      notifier();
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
      notifier();
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
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
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

    // Le dépôt trie par numéro croissant ; la fiche montre le plus récent en
    // haut. À numéro égal (plusieurs langues), le plus récemment enregistré
    // passe d'abord.
    final tries = List<Chapitre>.of(chapitres)
      ..sort((a, b) {
        final parNumero = b.numero.compareTo(a.numero);
        return parNumero != 0 ? parNumero : (b.id ?? 0).compareTo(a.id ?? 0);
      });

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
    );
  }

  void _appliquer(_DonneesTitre donnees) {
    _titre = donnees.titre;
    _source = donnees.source;
    _categories = donnees.categories;
    _listes = donnees.listes;
    _idsListesDuTitre = donnees.idsListesDuTitre;
    _chapitres = donnees.chapitres;
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
});

/// Signal interne : le titre n'existe plus en base.
class _TitreIntrouvable implements Exception {
  const _TitreIntrouvable();
}
