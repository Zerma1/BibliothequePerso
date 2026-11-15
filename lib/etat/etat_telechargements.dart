/// État de l'écran Téléchargements : file de téléchargement hors-ligne avec
/// sa progression, et actions du client (réessayer, supprimer, vider).
library;

import 'dart:async';

import '../modeles/chapitre.dart';
import '../modeles/telechargement.dart';
import '../modeles/titre.dart';
import '../services/service_bibliotheque.dart';
import '../services/service_telechargement.dart';
import 'description_erreur.dart';

/// Une ligne de la file, avec le chapitre et le titre à afficher.
class ElementTelechargement {
  /// Crée l'élément.
  const ElementTelechargement({
    required this.telechargement,
    this.chapitre,
    this.titre,
  });

  /// Ligne de la file (statut, progression, erreur).
  final Telechargement telechargement;

  /// Chapitre concerné, `null` s'il n'a pas pu être retrouvé.
  final Chapitre? chapitre;

  /// Titre du chapitre, `null` s'il n'a pas pu être retrouvé.
  final Titre? titre;

  /// Identifiant du chapitre.
  int get idChapitre => telechargement.idChapitre;

  /// Statut du téléchargement.
  StatutTelechargement get statut => telechargement.statut;
}

/// File de téléchargement, mise à jour en direct par
/// `ServiceTelechargement.changements`.
class EtatTelechargements extends EtatNotifiant {
  /// Crée l'état et s'abonne aux changements de la file ; appeler [charger]
  /// pour la première lecture.
  EtatTelechargements(this._service, this._serviceBibliotheque) {
    _abonnement = _service.changements.listen((_) => _demanderRechargement());
  }

  final ServiceTelechargement _service;
  final ServiceBibliotheque _serviceBibliotheque;
  late final StreamSubscription<void> _abonnement;

  List<ElementTelechargement> _elements = const <ElementTelechargement>[];
  bool _estEnChargement = false;
  bool _estCharge = false;
  DescriptionErreur? _erreur;

  /// Chapitres et titres déjà retrouvés : la file est relue à chaque page
  /// téléchargée, inutile de relire les titres à chaque fois.
  final Map<int, Chapitre> _chapitres = <int, Chapitre>{};
  final Map<int, Titre> _titres = <int, Titre>{};

  /// Chapitres introuvables (supprimés entre-temps) : on ne les recherche
  /// plus jusqu'au prochain [charger] demandé par le client.
  final Set<int> _idsIntrouvables = <int>{};

  /// Rechargement en cours, et nouveau rechargement demandé pendant celui-ci.
  Future<void>? _rechargement;
  bool _rechargementRedemande = false;

  /// Lignes de la file, dans l'ordre d'ajout.
  List<ElementTelechargement> get elements => _elements;

  /// `true` pendant le chargement demandé par le client.
  bool get estEnChargement => _estEnChargement;

  /// `true` une fois qu'un chargement a abouti.
  bool get estCharge => _estCharge;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` si le chargement a abouti et que la file est vide.
  bool get estVide => _estCharge && _erreur == null && _elements.isEmpty;

  /// Nombre de téléchargements en attente ou en cours (badge de l'onglet).
  int get nombreActifs => _elements
      .where(
        (element) =>
            element.statut == StatutTelechargement.enAttente ||
            element.statut == StatutTelechargement.enCours,
      )
      .length;

  /// Nombre de téléchargements terminés (bouton « Vider les terminés »).
  int get nombreTermines => _elements
      .where((element) => element.statut == StatutTelechargement.termine)
      .length;

  /// Nombre de téléchargements en échec.
  int get nombreEchecs => _elements
      .where((element) => element.statut == StatutTelechargement.echec)
      .length;

  /// Ligne de file d'un chapitre, ou `null` s'il n'y est pas.
  Telechargement? telechargementDuChapitre(int idChapitre) {
    for (final element in _elements) {
      if (element.idChapitre == idChapitre) return element.telechargement;
    }
    return null;
  }

  /// Lit la file (demandé par le client : indicateur et erreur visibles).
  Future<void> charger() async {
    _estEnChargement = true;
    _erreur = null;
    _idsIntrouvables.clear();
    notifier();
    await _demanderRechargement();
    _estEnChargement = false;
    notifier();
  }

  /// Relit la file. Les demandes qui arrivent pendant une lecture sont
  /// regroupées en une seule relecture à la fin : pendant un téléchargement,
  /// le service prévient à chaque page.
  Future<void> _demanderRechargement() {
    final enCours = _rechargement;
    if (enCours != null) {
      _rechargementRedemande = true;
      return enCours;
    }
    final nouveau = _recharger().whenComplete(() => _rechargement = null);
    _rechargement = nouveau;
    return nouveau;
  }

  Future<void> _recharger() async {
    do {
      _rechargementRedemande = false;
      if (estLibere) return;
      try {
        final file = await _service.chargerFile();
        await _retrouverChapitres(file.map((t) => t.idChapitre));
        _elements = <ElementTelechargement>[
          for (final telechargement in file)
            ElementTelechargement(
              telechargement: telechargement,
              chapitre: _chapitres[telechargement.idChapitre],
              titre: _titres[_chapitres[telechargement.idChapitre]?.idTitre],
            ),
        ];
        _estCharge = true;
        _erreur = null;
      } catch (erreur, pile) {
        _erreur = DescriptionErreur.depuis(erreur, pile);
      }
      notifier();
    } while (_rechargementRedemande);
  }

  /// Retrouve le chapitre et le titre de chaque identifiant inconnu.
  // LIMITE : le service ne fournit pas de lecture d'un chapitre par son
  // identifiant (`ServiceBibliotheque.chargerChapitre` manque) : on relit les
  // chapitres des titres jusqu'à les avoir tous trouvés. C'est fait une seule
  // fois par chapitre grâce au cache.
  Future<void> _retrouverChapitres(Iterable<int> idsChapitres) async {
    final manquants = idsChapitres
        .where(
          (id) => !_chapitres.containsKey(id) && !_idsIntrouvables.contains(id),
        )
        .toSet();
    if (manquants.isEmpty) return;
    final titres = await _serviceBibliotheque.chargerTitres();
    for (final titre in titres) {
      final idTitre = titre.id;
      if (idTitre == null) continue;
      _titres[idTitre] = titre;
      final chapitres = await _serviceBibliotheque.chargerChapitres(idTitre);
      for (final chapitre in chapitres) {
        final id = chapitre.id;
        if (id != null &&
            (manquants.contains(id) || _chapitres.containsKey(id))) {
          _chapitres[id] = chapitre;
        }
      }
      manquants.removeWhere(_chapitres.containsKey);
      if (manquants.isEmpty) return;
    }
    _idsIntrouvables.addAll(manquants);
  }

  /// Relance un téléchargement en échec.
  Future<ResultatAction<bool>> reessayer(int idChapitre) =>
      _executer(() => _service.telechargerChapitre(idChapitre));

  /// Retire un chapitre de la file et supprime son archive s'il en a une.
  Future<ResultatAction<bool>> supprimer(int idChapitre) =>
      _executer(() => _service.supprimerTelechargement(idChapitre));

  /// Retire de la file les téléchargements terminés (les archives restent).
  Future<ResultatAction<int>> viderTermines() async {
    try {
      final nombre = await _service.viderTermines();
      await _demanderRechargement();
      return ResultatAction<int>.reussite(nombre);
    } catch (erreur, pile) {
      return ResultatAction<int>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Relance tous les téléchargements en échec.
  Future<ResultatAction<bool>> reessayerEchecs() => _executer(() async {
    for (final element in List<ElementTelechargement>.of(_elements)) {
      if (element.statut == StatutTelechargement.echec) {
        await _service.telechargerChapitre(element.idChapitre);
      }
    }
  });

  Future<ResultatAction<bool>> _executer(Future<void> Function() action) async {
    try {
      await action();
      await _demanderRechargement();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  @override
  void dispose() {
    unawaited(_abonnement.cancel());
    super.dispose();
  }
}
