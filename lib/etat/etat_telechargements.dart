/// État de l'écran Téléchargements : file de téléchargement hors-ligne avec
/// sa progression, et actions du client (réessayer, supprimer, vider).
library;

import 'dart:async';

import '../modeles/chapitre.dart';
import '../modeles/journal.dart';
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

/// Chapitre dont la suppression automatique est prévue, avec son titre.
class ElementSuppressionPrevue {
  /// Crée l'élément.
  const ElementSuppressionPrevue({required this.chapitre, this.titre});

  /// Chapitre concerné (`dateSuppressionPrevue` renseignée).
  final Chapitre chapitre;

  /// Titre du chapitre, `null` s'il n'a pas pu être retrouvé.
  final Titre? titre;

  /// Identifiant du chapitre.
  int get idChapitre => chapitre.id!;

  /// Temps restant avant la suppression à [maintenant] (jamais négatif).
  Duration tempsRestant(DateTime maintenant) {
    final date = chapitre.dateSuppressionPrevue;
    if (date == null) return Duration.zero;
    final reste = date.difference(maintenant);
    return reste.isNegative ? Duration.zero : reste;
  }
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
  ///
  /// [maintenant] permet aux tests de fixer l'heure du compte à rebours.
  EtatTelechargements(
    this._service,
    this._serviceBibliotheque, {
    bool controlerEcheances = true,
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? (() => DateTime.now().toUtc()) {
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
  final DateTime Function() _maintenant;
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
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Suppressions prévues non faites',
        erreur: erreur,
        pile: pile,
      );
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

  /// `true` si le chargement a abouti sans file ni suppression prévue.
  bool get estVide =>
      _estCharge &&
      _erreur == null &&
      _elements.isEmpty &&
      _suppressions.isEmpty;

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
        // Pendant un téléchargement, le service prévient à chaque page : les
        // suppressions prévues ne sont relues que hors traitement ou quand
        // la file a changé de composition (moins de lectures en base).
        final composition = <int>{for (final t in file) t.idChapitre};
        if (!_service.estEnCours ||
            !_suppressionsLues ||
            composition.length != _compositionFile.length ||
            !composition.containsAll(_compositionFile)) {
          await _relireSuppressionsEtGardes();
        }
        _compositionFile = composition;
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

  // ------------------------------------------- Suppressions prévues (IN5)

  List<ElementSuppressionPrevue> _suppressions =
      const <ElementSuppressionPrevue>[];
  Set<int> _idsGardes = const <int>{};
  Set<int> _compositionFile = const <int>{};
  bool _suppressionsLues = false;

  /// Rafraîchit le compte à rebours ; actif seulement s'il y a des
  /// suppressions prévues.
  Timer? _minuterieCompteARebours;

  /// Chapitres dont la suppression automatique est prévue (tous titres), la
  /// plus proche d'abord.
  List<ElementSuppressionPrevue> get suppressionsPrevues => _suppressions;

  /// `true` si [idChapitre] est gardé par le client (repère « gardé »).
  bool estGarde(int idChapitre) => _idsGardes.contains(idChapitre);

  /// Heure actuelle (UTC) pour le compte à rebours.
  DateTime get maintenant => _maintenant();

  Future<void> _relireSuppressionsEtGardes() async {
    final prevues = await _service.chargerSuppressionsPrevues();
    final gardes = await _service.chargerChapitresGardes();
    // Les titres manquants sont lus une fois (cache partagé avec la file).
    for (final chapitre in prevues) {
      final idTitre = chapitre.idTitre;
      if (idTitre != null && !_titres.containsKey(idTitre)) {
        final titre = await _serviceBibliotheque.chargerTitre(idTitre);
        if (titre != null) _titres[idTitre] = titre;
      }
    }
    _suppressions = <ElementSuppressionPrevue>[
      for (final chapitre in prevues)
        if (chapitre.id != null)
          ElementSuppressionPrevue(
            chapitre: chapitre,
            titre: _titres[chapitre.idTitre],
          ),
    ];
    _idsGardes = gardes;
    // Le chapitre a pu changer (gardé, retéléchargé) : le cache de la file
    // est rafraîchi avec la version lue.
    for (final chapitre in prevues) {
      if (chapitre.id != null) _chapitres[chapitre.id!] = chapitre;
    }
    _suppressionsLues = true;
    _mettreAJourCompteARebours();
  }

  void _mettreAJourCompteARebours() {
    if (estLibere) return;
    if (_suppressions.isEmpty) {
      _minuterieCompteARebours?.cancel();
      _minuterieCompteARebours = null;
    } else {
      _minuterieCompteARebours ??= Timer.periodic(
        intervalleCompteARebours,
        (_) => notifier(),
      );
    }
  }

  /// Bouton « Garder » : la suppression prévue est annulée pour de bon.
  Future<ResultatAction<bool>> garder(int idChapitre) =>
      _executer(() => _service.annulerSuppression(idChapitre));

  /// Bouton « Supprimer maintenant » d'une suppression prévue.
  Future<ResultatAction<bool>> supprimerMaintenant(int idChapitre) =>
      _executer(() => _service.supprimerMaintenant(idChapitre));

  /// Bouton « Supprimer tous les chapitres à supprimer » : toutes les
  /// suppressions prévues sont faites tout de suite ; renvoie le nombre
  /// d'archives supprimées (un chapitre ouvert dans le lecteur est épargné).
  Future<ResultatAction<int>> supprimerToutesSuppressionsPrevues() async {
    try {
      final nombre = await _service.supprimerToutesSuppressionsPrevues();
      // Relecture forcée, même pendant un téléchargement : la section rouge
      // doit se vider tout de suite.
      _suppressionsLues = false;
      await _demanderRechargement();
      return ResultatAction<int>.reussite(nombre);
    } catch (erreur, pile) {
      return ResultatAction<int>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// « Ne plus garder » : le chapitre suit de nouveau les règles.
  Future<ResultatAction<bool>> nePlusGarder(int idChapitre) =>
      _executer(() => _service.retirerGarde(idChapitre));

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
      // Une action du client change en général les suppressions prévues ou
      // les gardes : relecture forcée, même pendant un téléchargement.
      _suppressionsLues = false;
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
    _minuterieCompteARebours?.cancel();
    _minuterieCompteARebours = null;
    unawaited(_abonnement.cancel());
    super.dispose();
  }
}
