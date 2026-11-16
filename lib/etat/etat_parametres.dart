/// État de l'écran Paramètres, sections « Mes langues » (langues de lecture),
/// « Téléchargements » (limites des règles de conservation des favoris et
/// suivis) et « Mises à jour » (nombre de recherches par jour).
library;

import 'package:flutter/foundation.dart';

import '../services/planification_mises_a_jour.dart';
import '../services/politique_telechargement.dart';
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
  EtatParametres(this._serviceParametres, this._serviceTelechargement);

  final ServiceParametres _serviceParametres;
  final ServiceTelechargement _serviceTelechargement;

  /// Valeur maximale d'une limite (même borne que le service).
  static const int limiteMaximale = ServiceParametres.limiteMaximale;

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

  /// Horaires des recherches de mises à jour.
  PlanificationMisesAJour get planification => _planification;

  /// Nombre de recherches de mises à jour par jour.
  int get verificationsParJour => _planification.verificationsParJour;

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
    notifier();
    try {
      await _serviceParametres.enregistrerVerificationsParJour(borne);
      _planification = PlanificationMisesAJour(borne);
      return ResultatAction<PlanificationMisesAJour>.reussite(_planification);
    } catch (erreur, pile) {
      return ResultatAction<PlanificationMisesAJour>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    } finally {
      _estEnEnregistrementPlanification = false;
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
      debugPrint('Date de vérification illisible : $erreur\n$pile');
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
  /// une archive dans une langue retirée n'est supprimée qu'après 24 heures
  /// (le client peut revenir en arrière ou la garder).
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
        await _serviceTelechargement.appliquerReglesATous();
      } catch (erreur, pile) {
        debugPrint('Règles non appliquées après les langues : $erreur\n$pile');
      }
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnEnregistrementLangues = false;
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
      _langues = await _serviceParametres.chargerLangues();
      _planification = await _serviceParametres.chargerPlanification();
      _derniereVerification = await _serviceParametres
          .chargerDerniereVerification();
      _enregistres = reglages;
      _brouillon = reglages;
      _estCharge = true;
    } catch (erreur, pile) {
      _erreur = DescriptionErreur.depuis(erreur, pile);
    }
    _estEnChargement = false;
    notifier();
  }

  /// Change une limite du brouillon, ramenée entre 0 et [limiteMaximale].
  void modifier(LimiteTelechargement limite, int valeur) {
    final bornee = valeur.clamp(0, limiteMaximale);
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
        debugPrint('Règles non appliquées après réglage : $erreur\n$pile');
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
