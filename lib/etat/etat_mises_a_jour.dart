/// État de la recherche des nouveaux chapitres des titres suivis : bouton
/// « Rechercher les nouveaux chapitres » et planification sur ordinateur
/// (PLAYBOOK.md section 7).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/planification_mises_a_jour.dart';
import '../services/service_mises_a_jour.dart';
import '../services/service_parametres.dart';
import '../services/service_telechargement.dart';
import '../sources/erreur_source.dart';
import 'description_erreur.dart';

/// Bilan d'une vérification terminée, publié par
/// [EtatMisesAJour.finVerification].
class FinVerification {
  /// Crée le bilan ; [rapport] est `null` si la vérification a échoué
  /// entièrement ([erreur] renseignée).
  const FinVerification({required this.estManuelle, this.rapport, this.erreur});

  /// `true` si le client a demandé la vérification (bouton), `false` si elle
  /// vient du démarrage ou de la minuterie.
  final bool estManuelle;

  /// Rapport du service, ou `null` en cas d'échec global.
  final RapportMisesAJour? rapport;

  /// Échec global (base illisible…), ou `null`.
  final DescriptionErreur? erreur;

  /// Nombre total de nouveaux chapitres trouvés.
  int get nombreNouveauxChapitres => rapport?.nombreNouveauxChapitres ?? 0;

  /// Nombre de titres qui ont au moins un nouveau chapitre.
  int get nombreTitresAvecNouveautes =>
      rapport?.titresAvecNouveautes.length ?? 0;

  /// Nombre de sites distincts qui n'ont pas répondu (erreurs réseau ou de
  /// lecture du site) : plusieurs titres d'un même site en panne ne comptent
  /// qu'une fois.
  int get nombreSitesEnEchec {
    final echecs = rapport?.echecs ?? const <ResultatVerificationTitre>[];
    return echecs
        .where((resultat) => resultat.erreur is ErreurSource)
        .map((resultat) => resultat.titre.idSource ?? resultat.titre.urlTitre)
        .toSet()
        .length;
  }

  /// Titres non vérifiés pour une autre raison qu'un site injoignable (site
  /// supprimé, base occupée…) : ils ne doivent pas être comptés comme des
  /// sites en panne.
  int get nombreAutresEchecs {
    final echecs = rapport?.echecs ?? const <ResultatVerificationTitre>[];
    return echecs.where((resultat) => resultat.erreur is! ErreurSource).length;
  }

  /// `true` si de nouveaux chapitres ont été enregistrés.
  bool get aDesNouveautes => nombreNouveauxChapitres > 0;
}

/// Lance les recherches de nouveaux chapitres (à heures fixes et à la
/// demande) et expose leur avancement à l'interface.
///
/// Les horaires sont ceux du client : N vérifications par jour à partir de
/// 00:00 UTC (2 par défaut : 00:00 et 12:00), voir `PlanificationMisesAJour`.
///
/// L'état ne connaît pas la bibliothèque : l'écran écoute
/// [finVerification] et recharge `EtatBibliotheque` quand il y a des
/// nouveautés. Ainsi aucun état ne dépend d'un autre ni des écrans.
class EtatMisesAJour extends EtatNotifiant {
  /// Crée l'état. Rien ne part avant [demarrer].
  ///
  /// [planifier] (ordinateur : l'application ouverte fait elle-même les
  /// vérifications) : au [demarrer], vérification si une échéance est passée
  /// depuis la dernière, puis un minuteur jusqu'à chaque échéance suivante.
  /// Sur Android, c'est la tâche de fond WorkManager qui s'en charge.
  ///
  /// [serviceParametres] fournit le réglage « vérifications par jour » (sans
  /// lui : valeur par défaut). [surChangementPlanification] est appelé par
  /// [replanifier] (Android : réenregistrer la tâche de fond).
  /// [serviceTelechargement] : après une vérification qui a trouvé de
  /// nouveaux chapitres, les règles de téléchargement sont réappliquées pour
  /// que les favoris et suivis les téléchargent. [maintenant] permet aux
  /// tests de simuler l'heure.
  EtatMisesAJour(
    this._service, {
    bool planifier = false,
    ServiceParametres? serviceParametres,
    ServiceTelechargement? serviceTelechargement,
    Future<void> Function(PlanificationMisesAJour planification)?
    surChangementPlanification,
    DateTime Function()? maintenant,
  }) : _planifier = planifier,
       _serviceParametres = serviceParametres,
       _serviceTelechargement = serviceTelechargement,
       _surChangementPlanification = surChangementPlanification,
       _maintenant = maintenant ?? (() => DateTime.now().toUtc());

  final ServiceMisesAJour _service;
  final bool _planifier;
  final ServiceParametres? _serviceParametres;
  final ServiceTelechargement? _serviceTelechargement;
  final Future<void> Function(PlanificationMisesAJour planification)?
  _surChangementPlanification;
  final DateTime Function() _maintenant;

  Timer? _minuterie;
  bool _estDemarre = false;
  DateTime? _prochaineEcheance;

  /// Numéro de programmation : une lecture du réglage plus ancienne (deux
  /// [replanifier] rapprochés) ne remplace pas le minuteur le plus récent.
  int _numeroProgrammation = 0;

  /// Vérification en cours, partagée par le bouton et le minuteur.
  Future<void>? _enCours;

  /// Vrai si le client a cliqué pendant la vérification en cours : le bilan
  /// lui sera alors affiché même si elle avait été lancée automatiquement.
  bool _demandeManuelle = false;

  RapportMisesAJour? _dernierRapport;
  DateTime? _dateDerniereVerification;
  DescriptionErreur? _erreur;

  final ValueNotifier<FinVerification?> _finVerification =
      ValueNotifier<FinVerification?>(null);

  /// `true` pendant une vérification.
  bool get estEnCours => _enCours != null;

  /// Rapport de la dernière vérification réussie, ou `null`.
  RapportMisesAJour? get dernierRapport => _dernierRapport;

  /// Fin (UTC) de la dernière vérification réussie faite par cet état, ou
  /// `null`.
  DateTime? get dateDerniereVerification => _dateDerniereVerification;

  /// Prochaine vérification programmée (UTC), ou `null` sans minuteur.
  DateTime? get prochaineEcheance => _prochaineEcheance;

  /// Erreur de la dernière vérification, ou `null` si elle a réussi.
  DescriptionErreur? get erreur => _erreur;

  /// Publie un [FinVerification] (nouvel objet) à la fin de chaque
  /// vérification réussie ou en échec. Une vérification automatique qui
  /// n'était pas due (échéance déjà traitée) ne publie rien.
  ValueListenable<FinVerification?> get finVerification => _finVerification;

  /// Lance la vérification au démarrage et le minuteur, si [planifier] a été
  /// demandé au constructeur. Les appels suivants sont sans effet.
  void demarrer() {
    if (_estDemarre || estLibere) {
      return;
    }
    _estDemarre = true;
    if (_planifier) {
      // Application fermée à l'heure prévue : on rattrape la vérification
      // manquée dès l'ouverture (le service ne fait rien si elle a déjà eu
      // lieu, par exemple dans la tâche de fond).
      unawaited(_verifier(estManuelle: false));
      unawaited(_programmer());
    }
  }

  /// À appeler quand le réglage « vérifications par jour » a changé :
  /// reprogramme le minuteur (ordinateur) et prévient
  /// `surChangementPlanification` (tâche de fond Android).
  Future<void> replanifier() async {
    if (estLibere) return;
    if (_planifier && _estDemarre) {
      await _programmer();
    }
    final rappel = _surChangementPlanification;
    if (rappel != null) {
      try {
        await rappel(await _chargerPlanification());
      } catch (exception, pile) {
        debugPrint('Replanification impossible : $exception\n$pile');
      }
    }
  }

  Future<PlanificationMisesAJour> _chargerPlanification() async {
    final parametres = _serviceParametres;
    if (parametres == null) {
      return PlanificationMisesAJour(PlanificationMisesAJour.parDefautParJour);
    }
    return parametres.chargerPlanification();
  }

  /// Programme un minuteur ponctuel jusqu'à la prochaine échéance ; à son
  /// déclenchement, il vérifie puis se reprogramme. Un minuteur ponctuel
  /// (plutôt que périodique) suit les heures fixes UTC même si l'ordinateur
  /// a été mis en veille entre-temps.
  Future<void> _programmer() async {
    final numero = ++_numeroProgrammation;
    PlanificationMisesAJour planification;
    try {
      planification = await _chargerPlanification();
    } catch (exception, pile) {
      // Réglage illisible : on garde la valeur par défaut plutôt que de ne
      // plus jamais vérifier.
      debugPrint('Planification illisible : $exception\n$pile');
      planification = PlanificationMisesAJour(
        PlanificationMisesAJour.parDefautParJour,
      );
    }
    if (estLibere || numero != _numeroProgrammation) return;
    _minuterie?.cancel();
    final maintenant = _maintenant();
    final prochaine = planification.prochaineEcheance(maintenant);
    _prochaineEcheance = prochaine;
    _minuterie = Timer(prochaine.difference(maintenant), () {
      _minuterie = null;
      unawaited(_verifier(estManuelle: false));
      unawaited(_programmer());
    });
    notifier();
  }

  /// Vérification demandée par le client (toujours faite, quelle que soit
  /// l'heure). Si une vérification est déjà en cours, attend sa fin au lieu
  /// d'en relancer une.
  Future<void> verifierMaintenant() => _verifier(estManuelle: true);

  Future<void> _verifier({required bool estManuelle}) {
    if (estLibere) {
      return Future<void>.value();
    }
    if (estManuelle) {
      _demandeManuelle = true;
    }
    final enCours = _enCours;
    if (enCours != null) {
      return enCours;
    }
    // `_executer` commence par rendre la main (`await` immédiat) : `_enCours`
    // est donc toujours affecté avant qu'elle ne le remette à `null`, même si
    // le service échouait de façon synchrone.
    final nouvelle = _executer(automatique: !estManuelle);
    _enCours = nouvelle;
    _erreur = null;
    notifier();
    return nouvelle;
  }

  Future<void> _executer({required bool automatique}) async {
    await Future<void>.value();
    RapportMisesAJour? rapport;
    DescriptionErreur? erreur;
    try {
      rapport = automatique
          ? await _service.verifierSiEcheancePassee()
          : await _service.verifierTitresSuivis();
      // Le client a cliqué pendant un contrôle automatique qui n'avait rien
      // à faire : sa demande est servie quand même.
      if (rapport == null && _demandeManuelle) {
        rapport = await _service.verifierTitresSuivis();
      }
    } catch (exception, pile) {
      // Le service garde déjà les erreurs par titre ; seule une panne
      // générale (base de données…) arrive ici.
      erreur = DescriptionErreur.depuis(exception, pile);
    }
    final telechargement = _serviceTelechargement;
    if (telechargement != null &&
        rapport != null &&
        rapport.nombreNouveauxChapitres > 0) {
      try {
        // Les nouveaux chapitres des favoris et suivis entrent dans la file
        // (le traitement part en arrière-plan, sans être attendu ici).
        await telechargement.appliquerReglesATous();
      } catch (exception, pile) {
        debugPrint(
          'Règles non appliquées après mise à jour : $exception\n$pile',
        );
      }
    }
    final estManuelle = _demandeManuelle;
    _demandeManuelle = false;
    _enCours = null;
    if (estLibere) {
      return;
    }
    if (rapport == null && erreur == null) {
      // Contrôle automatique sans vérification due : rien à annoncer.
      notifier();
      return;
    }
    if (rapport != null) {
      _dernierRapport = rapport;
      _dateDerniereVerification = rapport.fin;
    }
    _erreur = erreur;
    notifier();
    _finVerification.value = FinVerification(
      estManuelle: estManuelle,
      rapport: rapport,
      erreur: erreur,
    );
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _minuterie = null;
    _finVerification.dispose();
    super.dispose();
  }
}
