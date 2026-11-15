/// État de la recherche des nouveaux chapitres des titres suivis : bouton
/// « Rechercher les nouveaux chapitres » et planification sur ordinateur
/// (PLAYBOOK.md section 7).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/service_mises_a_jour.dart';
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

/// Lance les recherches de nouveaux chapitres (au démarrage, périodiquement
/// et à la demande) et expose leur avancement à l'interface.
///
/// L'état ne connaît pas la bibliothèque : l'écran écoute
/// [finVerification] et recharge `EtatBibliotheque` quand il y a des
/// nouveautés. Ainsi aucun état ne dépend d'un autre ni des écrans.
class EtatMisesAJour extends EtatNotifiant {
  /// Crée l'état. Rien ne part avant [demarrer].
  ///
  /// [verifierAuDemarrage] lance une vérification dès [demarrer] ;
  /// [intervalle] (ordinateur uniquement) programme une vérification
  /// périodique tant que l'application est ouverte.
  EtatMisesAJour(
    this._service, {
    bool verifierAuDemarrage = false,
    Duration? intervalle,
  }) : _verifierAuDemarrage = verifierAuDemarrage,
       _intervalle = intervalle;

  final ServiceMisesAJour _service;
  final bool _verifierAuDemarrage;
  final Duration? _intervalle;

  Timer? _minuterie;
  bool _estDemarre = false;

  /// Vérification en cours, partagée par le bouton et la minuterie.
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

  /// Fin (UTC) de la dernière vérification réussie, ou `null`.
  DateTime? get dateDerniereVerification => _dateDerniereVerification;

  /// Erreur de la dernière vérification, ou `null` si elle a réussi.
  DescriptionErreur? get erreur => _erreur;

  /// Publie un [FinVerification] (nouvel objet) à la fin de chaque
  /// vérification, réussie ou non.
  ValueListenable<FinVerification?> get finVerification => _finVerification;

  /// Lance la vérification au démarrage et la minuterie, selon les options du
  /// constructeur. Les appels suivants sont sans effet.
  void demarrer() {
    if (_estDemarre || estLibere) {
      return;
    }
    _estDemarre = true;
    if (_verifierAuDemarrage) {
      unawaited(_verifier(estManuelle: false));
    }
    final intervalle = _intervalle;
    if (intervalle != null) {
      _minuterie = Timer.periodic(
        intervalle,
        (_) => unawaited(_verifier(estManuelle: false)),
      );
    }
  }

  /// Vérification demandée par le client. Si une vérification est déjà en
  /// cours, attend sa fin au lieu d'en relancer une.
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
    final nouvelle = _executer();
    _enCours = nouvelle;
    _erreur = null;
    notifier();
    return nouvelle;
  }

  Future<void> _executer() async {
    await Future<void>.value();
    RapportMisesAJour? rapport;
    DescriptionErreur? erreur;
    try {
      rapport = await _service.verifierTitresSuivis();
    } catch (exception, pile) {
      // Le service garde déjà les erreurs par titre ; seule une panne
      // générale (base de données…) arrive ici.
      erreur = DescriptionErreur.depuis(exception, pile);
    }
    final estManuelle = _demandeManuelle;
    _demandeManuelle = false;
    _enCours = null;
    if (estLibere) {
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
