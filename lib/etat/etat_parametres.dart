/// État de l'écran Paramètres, sections « Mes langues » (langues de lecture),
/// « Téléchargements » (limites des règles de conservation des favoris et
/// suivis) et « Mises à jour » (nombre de recherches par jour).
library;

import 'dart:async';

import '../modeles/journal.dart';
import '../services/planification_mises_a_jour.dart';
import '../services/politique_telechargement.dart';
import '../services/service_bibliotheque.dart';
import '../services/service_parametres.dart';
import '../services/service_telechargement.dart';
import 'description_erreur.dart';

/// Une des quatre limites réglables.
enum LimiteTelechargement {
  /// Favoris : chapitres lus gardés.
  favorisLusConserves,

  /// Suivis : chapitres téléchargés au départ.
  suivisInitial,

  /// Suivis : chapitres gardés jusqu'au dernier lu.
  suivisAvant,

  /// Suivis : chapitres téléchargés après le dernier lu.
  suivisApres,
}

/// Réglages de téléchargement en cours de modification.
///
/// Les boutons + / − modifient un brouillon ; rien n'est écrit tant que le
/// client n'a pas appuyé sur « Enregistrer » (les règles relancent des
/// téléchargements ou en suppriment : on évite de le faire à chaque appui).
class EtatParametres extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire les réglages.
  ///
  /// [serviceBibliotheque] sert à recalculer la liste « En attente » quand
  /// les langues changent (sans lui, elle l'est à la prochaine recherche de
  /// nouveaux chapitres).
  EtatParametres(
    this._serviceParametres,
    this._serviceTelechargement, {
    this._serviceBibliotheque,
  });

  final ServiceParametres _serviceParametres;
  final ServiceTelechargement _serviceTelechargement;
  final ServiceBibliotheque? _serviceBibliotheque;

  /// Valeur maximale d'une limite (même borne que le service).
  static const int limiteMaximale = ServiceParametres.limiteMaximale;

  /// Valeur minimale de [limite] (mêmes bornes que le service) : 0 pour
  /// « favoris : lus gardés » et « suivis : au départ », 1 pour « avant » et
  /// « après » des suivis.
  static int minimumLimite(LimiteTelechargement limite) => switch (limite) {
    LimiteTelechargement.favorisLusConserves ||
    LimiteTelechargement.suivisInitial => ServiceParametres.limiteMinimale,
    LimiteTelechargement.suivisAvant || LimiteTelechargement.suivisApres =>
      ServiceParametres.limiteMinimaleSuivisAvantApres,
  };

  ReglagesTelechargement _enregistres = const ReglagesTelechargement();
  ReglagesTelechargement _brouillon = const ReglagesTelechargement();
  bool _estCharge = false;
  bool _estEnChargement = false;
  bool _estEnEnregistrement = false;
  DescriptionErreur? _erreur;

  /// Réglages affichés (brouillon).
  ReglagesTelechargement get reglages => _brouillon;

  /// Valeurs par défaut choisies par le client.
  ReglagesTelechargement get reglagesParDefaut =>
      const ReglagesTelechargement();

  /// `true` si le brouillon diffère des réglages enregistrés.
  bool get estModifie => _brouillon != _enregistres;

  /// `true` si le brouillon vaut déjà les valeurs par défaut.
  bool get estParDefaut => _brouillon == const ReglagesTelechargement();

  /// `true` une fois les réglages lus.
  bool get estCharge => _estCharge;

  /// `true` pendant la lecture.
  bool get estEnChargement => _estEnChargement;

  /// `true` pendant l'enregistrement.
  bool get estEnEnregistrement => _estEnEnregistrement;

  /// Erreur de la dernière lecture, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// Valeur d'une limite dans le brouillon.
  int valeur(LimiteTelechargement limite) {
    switch (limite) {
      case LimiteTelechargement.favorisLusConserves:
        return _brouillon.favorisLusConserves;
      case LimiteTelechargement.suivisInitial:
        return _brouillon.suivisInitial;
      case LimiteTelechargement.suivisAvant:
        return _brouillon.suivisAvant;
      case LimiteTelechargement.suivisApres:
        return _brouillon.suivisApres;
    }
  }

  // ------------------------------------------------------------ Mises à jour

  /// Minimum de recherches par jour (l'écran n'importe pas les services).
  static const int minimumParJour = PlanificationMisesAJour.minimumParJour;

  /// Maximum de recherches par jour.
  static const int maximumParJour = PlanificationMisesAJour.maximumParJour;

  PlanificationMisesAJour _planification = PlanificationMisesAJour(
    PlanificationMisesAJour.parDefautParJour,
  );
  DateTime? _derniereVerification;
  bool _estEnEnregistrementPlanification = false;

  /// Valeur affichée pendant le glissement de la jauge des recherches par
  /// jour (rien n'est enregistré avant le lâcher), ou `null`.
  int? _apercuParJour;

  /// Horaires des recherches de mises à jour (ceux de la valeur affichée
  /// par la jauge pendant son glissement : le client voit les horaires
  /// qu'il s'apprête à choisir).
  PlanificationMisesAJour get planification {
    final apercu = _apercuParJour;
    return apercu == null ? _planification : PlanificationMisesAJour(apercu);
  }

  /// Nombre de recherches de mises à jour par jour (valeur affichée).
  int get verificationsParJour =>
      _apercuParJour ?? _planification.verificationsParJour;

  /// Affiche [nombre] pendant le glissement de la jauge, sans l'enregistrer.
  void previsualiserVerificationsParJour(int nombre) {
    final borne = nombre.clamp(minimumParJour, maximumParJour);
    if (borne == _apercuParJour) return;
    _apercuParJour = borne;
    notifier();
  }

  /// Date (UTC) de la dernière recherche de mises à jour, ou `null`.
  DateTime? get derniereVerification => _derniereVerification;

  /// `true` pendant l'enregistrement du nombre de vérifications.
  bool get estEnEnregistrementPlanification =>
      _estEnEnregistrementPlanification;

  /// Change le nombre de recherches par jour (ramené entre 1 et 24) et
  /// l'enregistre aussitôt : contrairement aux limites de téléchargement,
  /// ce réglage ne déclenche ni téléchargement ni suppression. L'écran
  /// prévient ensuite `EtatMisesAJour.replanifier`.
  Future<ResultatAction<PlanificationMisesAJour>> modifierVerificationsParJour(
    int nombre,
  ) async {
    final borne = nombre.clamp(
      PlanificationMisesAJour.minimumParJour,
      PlanificationMisesAJour.maximumParJour,
    );
    _estEnEnregistrementPlanification = true;
    // La jauge garde la valeur lâchée pendant l'enregistrement (pas de
    // retour visible à l'ancienne valeur).
    _apercuParJour = borne;
    notifier();
    try {
      await _serviceParametres.enregistrerVerificationsParJour(borne);
      _planification = PlanificationMisesAJour(borne);
      // L'écart « En attente » ne dépasse jamais l'intervalle normal : le
      // service le ramène, on relit la valeur appliquée.
      _heuresEnAttente = await _serviceParametres.chargerHeuresEnAttente();
      return ResultatAction<PlanificationMisesAJour>.reussite(_planification);
    } catch (erreur, pile) {
      return ResultatAction<PlanificationMisesAJour>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    } finally {
      _apercuParJour = null;
      _estEnEnregistrementPlanification = false;
      notifier();
    }
  }

  int _heuresEnAttente = 1;
  bool _estEnEnregistrementEnAttente = false;

  /// Valeur affichée pendant le glissement de la jauge « En attente », ou
  /// `null`.
  int? _apercuHeuresEnAttente;

  /// Borne basse de l'écart « En attente » (même borne que le service).
  static const int minimumHeuresEnAttente =
      ServiceParametres.minimumHeuresEnAttente;

  /// Écart en heures entre deux vérifications des titres « En attente »
  /// (valeur affichée), jamais au-delà de [maximumHeuresEnAttente].
  int get heuresEnAttente => (_apercuHeuresEnAttente ?? _heuresEnAttente).clamp(
    minimumHeuresEnAttente,
    maximumHeuresEnAttente,
  );

  /// Affiche [heures] pendant le glissement de la jauge, sans l'enregistrer.
  void previsualiserHeuresEnAttente(int heures) {
    final borne = heures.clamp(minimumHeuresEnAttente, maximumHeuresEnAttente);
    if (borne == _apercuHeuresEnAttente) return;
    _apercuHeuresEnAttente = borne;
    notifier();
  }

  /// Écart maximal autorisé : l'intervalle des vérifications normales.
  int get maximumHeuresEnAttente =>
      ServiceParametres.maximumHeuresEnAttente(verificationsParJour);

  /// `true` pendant l'enregistrement de l'écart « En attente ».
  bool get estEnEnregistrementEnAttente => _estEnEnregistrementEnAttente;

  /// Change l'écart des vérifications des titres « En attente » (ramené
  /// entre 1 h et l'intervalle normal) et l'enregistre aussitôt. L'écran
  /// prévient ensuite `EtatMisesAJour.replanifier`.
  Future<ResultatAction<int>> modifierHeuresEnAttente(int heures) async {
    _estEnEnregistrementEnAttente = true;
    _apercuHeuresEnAttente = heures.clamp(
      minimumHeuresEnAttente,
      maximumHeuresEnAttente,
    );
    notifier();
    try {
      await _serviceParametres.enregistrerHeuresEnAttente(heures);
      _heuresEnAttente = await _serviceParametres.chargerHeuresEnAttente();
      return ResultatAction<int>.reussite(_heuresEnAttente);
    } catch (erreur, pile) {
      return ResultatAction<int>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _apercuHeuresEnAttente = null;
      _estEnEnregistrementEnAttente = false;
      notifier();
    }
  }

  // ------------------------------- Durée de conservation avant suppression

  /// Durée de conservation tant que le client n'a rien choisi (24 h).
  static const Duration delaiSuppressionParDefaut =
      ServiceParametres.delaiSuppressionParDefaut;

  /// Crans de la jauge, du plus court au plus long (1 h à 30 jours).
  static const List<Duration> delaisSuppressionProposes =
      ServiceParametres.delaisSuppressionProposes;

  Duration _delaiSuppression = delaiSuppressionParDefaut;

  /// Valeur affichée pendant le glissement de la jauge, ou `null`.
  Duration? _apercuDelaiSuppression;
  bool _estEnEnregistrementDelai = false;

  /// Durée pendant laquelle une archive sortie des règles reste sur
  /// l'appareil avant d'être supprimée, **telle qu'affichée par la jauge** :
  /// pendant le glissement, c'est l'aperçu, pas encore enregistré. Pour les
  /// textes qui décrivent le comportement réel (« supprimé dans … »), lire
  /// [delaiSuppressionEnregistre].
  Duration get delaiSuppression => _apercuDelaiSuppression ?? _delaiSuppression;

  /// Durée de conservation enregistrée (dernière valeur lue ou enregistrée),
  /// sans l'aperçu de la jauge : sert aux légendes et explications des
  /// autres écrans, qui ne doivent pas annoncer une durée non enregistrée.
  Duration get delaiSuppressionEnregistre => _delaiSuppression;

  /// `true` pendant l'enregistrement de la durée de conservation.
  bool get estEnEnregistrementDelai => _estEnEnregistrementDelai;

  /// Affiche [delai] pendant le glissement de la jauge, sans l'enregistrer.
  void previsualiserDelaiSuppression(Duration delai) {
    if (delai == _apercuDelaiSuppression) return;
    _apercuDelaiSuppression = delai;
    notifier();
  }

  /// Enregistre la durée de conservation (le service l'arrondit à l'heure
  /// et la borne). Ne relance pas les règles : seules les nouvelles
  /// suppressions prévues utilisent la nouvelle durée.
  Future<ResultatAction<Duration>> modifierDelaiSuppression(
    Duration delai,
  ) async {
    _estEnEnregistrementDelai = true;
    _apercuDelaiSuppression = delai;
    notifier();
    try {
      await _serviceParametres.enregistrerDelaiSuppression(delai);
      _delaiSuppression = await _serviceParametres.chargerDelaiSuppression();
      return ResultatAction<Duration>.reussite(_delaiSuppression);
    } catch (erreur, pile) {
      return ResultatAction<Duration>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    } finally {
      _apercuDelaiSuppression = null;
      _estEnEnregistrementDelai = false;
      notifier();
    }
  }

  /// Relit la date de la dernière vérification (après une recherche).
  Future<void> rechargerDerniereVerification() async {
    try {
      _derniereVerification = await _serviceParametres
          .chargerDerniereVerification();
      notifier();
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.parametres,
        'Date de la dernière vérification illisible',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  // ------------------------------------------------------------ Mes langues

  /// Nombre maximal de langues (même borne que le service).
  static const int nombreMaximalLangues =
      ServiceParametres.nombreMaximalLangues;

  List<String> _langues = List<String>.of(ServiceParametres.languesParDefaut);
  bool _estEnEnregistrementLangues = false;

  /// Langues de lecture du client, la favorite d'abord.
  List<String> get langues => _langues;

  /// Langue favorite (la première).
  String get langueFavorite => _langues.first;

  /// `true` pendant l'enregistrement des langues.
  bool get estEnEnregistrementLangues => _estEnEnregistrementLangues;

  /// `true` si une langue peut encore être ajoutée.
  bool get peutAjouterLangue => _langues.length < nombreMaximalLangues;

  /// `true` si une langue peut être retirée (il en faut au moins une).
  bool get peutRetirerLangue => _langues.length > 1;

  /// Ajoute [code] en dernière position (la moins préférée).
  Future<ResultatAction<bool>> ajouterLangue(String code) {
    if (_langues.contains(code)) {
      return Future<ResultatAction<bool>>.value(
        const ResultatAction<bool>.reussite(true),
      );
    }
    return _enregistrerLangues(<String>[..._langues, code]);
  }

  /// Retire [code] (refusé par le service s'il ne restait qu'elle).
  Future<ResultatAction<bool>> retirerLangue(String code) =>
      _enregistrerLangues(<String>[
        for (final langue in _langues)
          if (langue != code) langue,
      ]);

  /// Déplace [code] de [decalage] rangs (−1 : plus préférée, +1 : moins).
  Future<ResultatAction<bool>> deplacerLangue(String code, int decalage) {
    final index = _langues.indexOf(code);
    final cible = index + decalage;
    if (index < 0 || cible < 0 || cible >= _langues.length) {
      return Future<ResultatAction<bool>>.value(
        const ResultatAction<bool>.reussite(true),
      );
    }
    final nouvelles = List<String>.of(_langues)
      ..removeAt(index)
      ..insert(cible, code);
    return _enregistrerLangues(nouvelles);
  }

  /// « Choisir comme favorite » : [code] passe en première position.
  Future<ResultatAction<bool>> choisirFavorite(String code) =>
      deplacerLangue(code, -_langues.indexOf(code));

  /// Enregistre aussitôt (comme le nombre de recherches par jour) puis
  /// applique les règles à tous les favoris et suivis : sans risque, car
  /// une archive dans une langue retirée n'est supprimée qu'après la durée
  /// de conservation réglée (le client peut revenir en arrière ou la
  /// garder).
  // LIMITE : les chapitres d'une langue ajoutée n'apparaissent qu'à la
  // prochaine recherche de nouveaux chapitres ou actualisation d'un titre
  // (le site n'est pas relu pour tous les titres ici : trop de requêtes).
  Future<ResultatAction<bool>> _enregistrerLangues(
    List<String> nouvelles,
  ) async {
    _estEnEnregistrementLangues = true;
    notifier();
    try {
      await _serviceParametres.enregistrerLangues(nouvelles);
      // Relues : le service nettoie les codes et borne leur nombre.
      _langues = await _serviceParametres.chargerLangues();
      try {
        // Un titre peut entrer dans « En attente » (plus aucun chapitre dans
        // les langues) ou en sortir : classement recalculé (base seulement).
        await _serviceBibliotheque?.classerTousEnAttente();
      } catch (erreur, pile) {
        Journal.actuel.avertissement(
          CategorieJournal.bibliotheque,
          'Classement « En attente » non refait après les langues',
          erreur: erreur,
          pile: pile,
        );
      }
      try {
        await _serviceTelechargement.appliquerReglesATous();
      } catch (erreur, pile) {
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Règles non appliquées après les langues',
          erreur: erreur,
          pile: pile,
        );
      }
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnEnregistrementLangues = false;
      notifier();
    }
  }

  // -------------------------------------------------- Archive complète (X7)

  bool _archiveComplete = ServiceParametres.archiveCompleteParDefaut;
  bool _estEnEnregistrementArchive = false;

  /// `true` si « Archive complète » est active : tous les chapitres de tous
  /// les titres sont téléchargés, et aucun n'est supprimé automatiquement.
  bool get archiveComplete => _archiveComplete;

  /// `true` pendant l'enregistrement de « Archive complète ».
  bool get estEnEnregistrementArchive => _estEnEnregistrementArchive;

  /// Active ou désactive « Archive complète » (enregistré aussitôt), puis
  /// applique les règles à toute la bibliothèque : à l'activation, tous les
  /// chapitres de tous les titres entrent dans la file.
  Future<ResultatAction<bool>> modifierArchiveComplete(bool active) async {
    _estEnEnregistrementArchive = true;
    notifier();
    try {
      await _serviceParametres.enregistrerArchiveComplete(active);
      _archiveComplete = await _serviceParametres.chargerArchiveComplete();
      try {
        await _serviceTelechargement.appliquerReglesATous();
      } catch (erreur, pile) {
        // Réglage enregistré : il sera appliqué au prochain démarrage ou à
        // la prochaine recherche de nouveaux chapitres.
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Règles non appliquées (archive complète)',
          erreur: erreur,
          pile: pile,
        );
      }
      return ResultatAction<bool>.reussite(_archiveComplete);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnEnregistrementArchive = false;
      notifier();
    }
  }

  // ------------------------------------------ Téléchargements simultanés

  /// Borne basse de la jauge (même borne que le service).
  static const int minimumTelechargementsSimultanes =
      ServiceParametres.minimumTelechargementsSimultanes;

  /// Borne haute de la jauge (même borne que le service).
  static const int maximumTelechargementsSimultanes =
      ServiceParametres.maximumTelechargementsSimultanes;

  int _telechargementsSimultanes =
      ServiceParametres.telechargementsSimultanesParDefautClient;

  /// Valeur affichée pendant que le client fait glisser la jauge (rien
  /// n'est enregistré avant qu'il la lâche), ou `null`.
  int? _apercuSimultanes;
  bool _estEnEnregistrementSimultanes = false;

  /// Nombre de chapitres téléchargés en même temps (valeur affichée).
  int get telechargementsSimultanes =>
      _apercuSimultanes ?? _telechargementsSimultanes;

  /// `true` pendant l'enregistrement du nombre de téléchargements
  /// simultanés.
  bool get estEnEnregistrementSimultanes => _estEnEnregistrementSimultanes;

  /// Affiche [nombre] pendant le glissement de la jauge, sans l'enregistrer.
  void previsualiserTelechargementsSimultanes(int nombre) {
    final borne = nombre.clamp(
      minimumTelechargementsSimultanes,
      maximumTelechargementsSimultanes,
    );
    if (borne == _apercuSimultanes) return;
    _apercuSimultanes = borne;
    notifier();
  }

  /// Enregistre le nombre de téléchargements simultanés (ramené entre les
  /// bornes) puis relance la file : un traitement en cours relit le réglage
  /// et remplit aussitôt les emplacements libres.
  Future<ResultatAction<int>> modifierTelechargementsSimultanes(
    int nombre,
  ) async {
    _estEnEnregistrementSimultanes = true;
    _apercuSimultanes = nombre.clamp(
      minimumTelechargementsSimultanes,
      maximumTelechargementsSimultanes,
    );
    notifier();
    try {
      await _serviceParametres.enregistrerTelechargementsSimultanes(nombre);
      _telechargementsSimultanes = await _serviceParametres
          .chargerTelechargementsSimultanes();
      // Ne lève jamais d'erreur et peut durer toute la file : pas attendu.
      unawaited(_serviceTelechargement.lancerTraitement());
      return ResultatAction<int>.reussite(_telechargementsSimultanes);
    } catch (erreur, pile) {
      return ResultatAction<int>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _apercuSimultanes = null;
      _estEnEnregistrementSimultanes = false;
      notifier();
    }
  }

  /// Lit les réglages enregistrés.
  Future<void> charger() async {
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final reglages = await _serviceParametres.chargerReglagesTelechargement();
      _archiveComplete = await _serviceParametres.chargerArchiveComplete();
      _langues = await _serviceParametres.chargerLangues();
      _planification = await _serviceParametres.chargerPlanification();
      _heuresEnAttente = await _serviceParametres.chargerHeuresEnAttente();
      _derniereVerification = await _serviceParametres
          .chargerDerniereVerification();
      _telechargementsSimultanes = await _serviceParametres
          .chargerTelechargementsSimultanes();
      _delaiSuppression = await _serviceParametres.chargerDelaiSuppression();
      _enregistres = reglages;
      _brouillon = reglages;
      _estCharge = true;
    } catch (erreur, pile) {
      _erreur = DescriptionErreur.depuis(erreur, pile);
    }
    _estEnChargement = false;
    notifier();
  }

  /// Change une limite du brouillon, ramenée entre [minimumLimite] et
  /// [limiteMaximale].
  void modifier(LimiteTelechargement limite, int valeur) {
    final bornee = valeur.clamp(minimumLimite(limite), limiteMaximale);
    switch (limite) {
      case LimiteTelechargement.favorisLusConserves:
        _brouillon = _brouillon.copierAvec(favorisLusConserves: bornee);
      case LimiteTelechargement.suivisInitial:
        _brouillon = _brouillon.copierAvec(suivisInitial: bornee);
      case LimiteTelechargement.suivisAvant:
        _brouillon = _brouillon.copierAvec(suivisAvant: bornee);
      case LimiteTelechargement.suivisApres:
        _brouillon = _brouillon.copierAvec(suivisApres: bornee);
    }
    notifier();
  }

  /// Ajoute [pas] (positif ou négatif) à une limite.
  void ajouter(LimiteTelechargement limite, int pas) =>
      modifier(limite, valeur(limite) + pas);

  /// Remet les valeurs par défaut dans le brouillon (à enregistrer).
  void remettreParDefaut() {
    _brouillon = const ReglagesTelechargement();
    notifier();
  }

  /// Annule les modifications non enregistrées.
  void annulerModifications() {
    _brouillon = _enregistres;
    notifier();
  }

  /// Applique les règles de téléchargement à toute la bibliothèque, par
  /// exemple après un import (nouveaux titres suivis, archive complète
  /// activée par le fichier). Une erreur est seulement journalisée : les
  /// règles seront appliquées au prochain démarrage.
  Future<void> appliquerReglesATous() async {
    try {
      await _serviceTelechargement.appliquerReglesATous();
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Règles non appliquées',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  /// Enregistre le brouillon puis applique les règles à tous les titres
  /// favoris et suivis.
  Future<ResultatAction<bool>> enregistrer() async {
    _estEnEnregistrement = true;
    notifier();
    try {
      await _serviceParametres.enregistrerReglagesTelechargement(_brouillon);
      _enregistres = _brouillon;
      try {
        await _serviceTelechargement.appliquerReglesATous();
      } catch (erreur, pile) {
        // Les réglages sont enregistrés : ils seront appliqués au prochain
        // démarrage ou à la prochaine lecture.
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Règles non appliquées après réglage',
          erreur: erreur,
          pile: pile,
        );
      }
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnEnregistrement = false;
      notifier();
    }
  }
}
