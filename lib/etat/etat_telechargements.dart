/// État de l'écran Téléchargements : file de téléchargement hors-ligne avec
/// sa progression, et actions du client (réessayer, supprimer, vider).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../modeles/chapitre.dart';
import '../modeles/telechargement.dart';
import '../modeles/titre.dart';
import '../services/service_bibliotheque.dart';
import '../services/service_telechargement.dart';
import 'constantes_etat.dart';
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
  ///
  /// Avec [controlerEcheances] (par défaut), les suppressions prévues dont
  /// le délai de 24 heures est passé sont faites toutes les
  /// [intervalleControleEcheance] ; l'écran d'accueil appelle aussi
  /// [controlerSuppressionsEchues] au retour au premier plan.
  EtatTelechargements(
    this._service,
    this._serviceBibliotheque, {
    bool controlerEcheances = true,
  }) {
    _abonnement = _service.changements.listen((_) => _demanderRechargement());
    if (controlerEcheances) {
      // Le service ne fait ces suppressions qu'au démarrage, à l'application
      // des règles et en fin de file : une application laissée ouverte
      // plusieurs jours sans nouveau chapitre ne les ferait jamais. Un
      // `Timer` ne compte pas la veille : le retour au premier plan complète.
      _controleRegulier = Timer.periodic(
        intervalleControleEcheance,
        (_) => unawaited(controlerSuppressionsEchues()),
      );
    }
  }

  final ServiceTelechargement _service;
  Timer? _controleRegulier;

  /// Contrôle en cours : deux déclenchements rapprochés (minuteur et retour
  /// au premier plan) n'en font qu'un.
  Future<int>? _controleEnCours;

  /// Supprime les archives dont la suppression prévue est échue et renvoie
  /// leur nombre (0 en cas d'erreur, journalisée : ce contrôle automatique
  /// sera refait au suivant).
  Future<int> controlerSuppressionsEchues() {
    if (estLibere) return Future<int>.value(0);
    final enCours = _controleEnCours;
    if (enCours != null) return enCours;
    final nouveau = _controler().whenComplete(() => _controleEnCours = null);
    _controleEnCours = nouveau;
    return nouveau;
  }

  Future<int> _controler() async {
    try {
      // Le service prévient par `changements` s'il a supprimé quelque
      // chose : la file et les fiches ouvertes se relisent d'elles-mêmes.
      return await _service.supprimerArchivesEchues();
    } catch (erreur, pile) {
      debugPrint('Suppressions prévues non faites : $erreur\n$pile');
      return 0;
    }
  }

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

  /// Retrouve le chapitre et le titre de chaque identifiant inconnu (une
  /// seule lecture par chapitre et par titre grâce au cache).
  Future<void> _retrouverChapitres(Iterable<int> idsChapitres) async {
    final manquants = idsChapitres
        .where(
          (id) => !_chapitres.containsKey(id) && !_idsIntrouvables.contains(id),
        )
        .toSet();
    for (final id in manquants) {
      final chapitre = await _serviceBibliotheque.chargerChapitre(id);
      if (chapitre == null) {
        _idsIntrouvables.add(id);
        continue;
      }
      _chapitres[id] = chapitre;
      final idTitre = chapitre.idTitre;
      if (idTitre != null && !_titres.containsKey(idTitre)) {
        final titre = await _serviceBibliotheque.chargerTitre(idTitre);
        if (titre != null) _titres[idTitre] = titre;
      }
    }
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
    _controleRegulier?.cancel();
    _controleRegulier = null;
    unawaited(_abonnement.cancel());
    super.dispose();
  }
}
