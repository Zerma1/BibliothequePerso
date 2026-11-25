/// Dossier des chapitres téléchargés : choix du dossier (local, lecteur
/// réseau, NAS), déplacement des archives, et état d'accès pour le bandeau
/// « dossier inaccessible » de l'écran d'accueil.
library;

import 'dart:async';

import '../modeles/journal.dart';
import '../services/dossier_chapitres.dart';
import '../services/service_telechargement.dart';
import 'description_erreur.dart';

// Les écrans n'importent que les états (PLAYBOOK.md section 4) : les valeurs
// échangées avec le service leur sont fournies par cet état.
export '../services/dossier_chapitres.dart'
    show AccesDossierChapitres, ResultatChangementDossier;

/// État du dossier des chapitres, mis à jour en direct par
/// `ServiceDossierChapitres.changements` (accès au dossier, pause de la
/// file).
class EtatDossierChapitres extends EtatNotifiant {
  /// Crée l'état et s'abonne aux changements ; appeler [charger] pour lire
  /// les réglages (dossier choisi, déplacement inachevé).
  EtatDossierChapitres(this._service) {
    _abonnement = _service.changements.listen((_) => notifier());
  }

  final ServiceDossierChapitres _service;
  StreamSubscription<void>? _abonnement;

  bool _estCharge = false;
  bool _estEnChargement = false;
  DescriptionErreur? _erreur;
  String? _dossierChoisi;
  String? _cheminParDefaut;
  String? _deplacementInacheve;

  bool _estEnVerification = false;
  Future<AccesDossierChapitres>? _verificationEnCours;

  bool _estEnChangement = false;
  int _faits = 0;
  int _total = 0;

  // ------------------------------------------------------------ Session

  /// Dossier des chapitres utilisé pendant cette session.
  String get dossierActuel => _service.dossierActuel;

  /// `true` si le dossier de cette session a été choisi par le client.
  bool get estDossierPersonnalise => _service.estDossierPersonnalise;

  /// `true` si le dossier a été changé pendant cette session : il faut
  /// redémarrer l'application pour l'utiliser.
  bool get redemarrageNecessaire => _service.redemarrageNecessaire;

  /// `true` si la file de téléchargement est en pause.
  bool get estFileEnPause => _service.estFileEnPause;

  /// `true` si la file a été mise en pause par un changement refusé
  /// (chapitre en cours de téléchargement) : le client peut y renoncer avec
  /// [reprendreFile]. Après un changement réussi, la pause dure jusqu'au
  /// redémarrage.
  bool get peutReprendreFile =>
      _service.estFileEnPause && !_service.redemarrageNecessaire;

  /// Dernier état connu du dossier des chapitres.
  AccesDossierChapitres get accesDossier => _service.accesDossier;

  /// `true` pendant [verifierAcces] (bouton « Réessayer » du bandeau).
  bool get estEnVerification => _estEnVerification;

  // ----------------------------------------------------------- Réglages

  /// `true` une fois les réglages lus par [charger].
  bool get estCharge => _estCharge;

  /// Erreur de la dernière lecture des réglages, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// Dossier enregistré dans les réglages (`null` : dossier par défaut).
  /// Peut différer de [dossierActuel] avant un redémarrage.
  String? get dossierChoisi => _dossierChoisi;

  /// Chemin du dossier par défaut de l'application, ou `null` avant
  /// [charger].
  String? get cheminParDefaut => _cheminParDefaut;

  /// Dossier vers lequel un déplacement est resté inachevé, ou `null`.
  String? get deplacementInacheve => _deplacementInacheve;

  /// Dossier qui sera utilisé au prochain démarrage s'il diffère de
  /// [dossierActuel], sinon `null`.
  String? get dossierAuProchainDemarrage {
    if (!_estCharge || !redemarrageNecessaire) return null;
    return _dossierChoisi ?? _cheminParDefaut;
  }

  // ---------------------------------------------------------- Changement

  /// `true` pendant un changement de dossier (déplacement compris).
  bool get estEnChangement => _estEnChangement;

  /// Fichiers déjà déplacés pendant le changement en cours.
  int get faits => _faits;

  /// Nombre total de fichiers à déplacer (0 tant qu'il n'est pas connu).
  int get total => _total;

  /// Progression du déplacement entre 0 et 1, ou `null` si le total n'est
  /// pas encore connu (barre indéterminée).
  double? get progression =>
      _total <= 0 ? null : (_faits / _total).clamp(0, 1).toDouble();

  /// Lit le dossier choisi, le dossier par défaut et un éventuel
  /// déplacement inachevé. Une erreur de lecture devient [erreur].
  Future<void> charger() async {
    if (_estEnChargement) return;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final choisi = await _service.chargerDossierChoisi();
      final parDefaut = await _service.chargerCheminDossierParDefaut();
      final inacheve = await _service.chargerDeplacementInacheve();
      _dossierChoisi = choisi;
      _cheminParDefaut = parDefaut;
      _deplacementInacheve = inacheve;
      _estCharge = true;
    } catch (exception, pile) {
      _erreur = DescriptionErreur.depuis(exception, pile);
    } finally {
      _estEnChargement = false;
      notifier();
    }
  }

  /// Contrôle tout de suite l'accès au dossier (bouton « Réessayer », retour
  /// au premier plan). Deux appels rapprochés n'en font qu'un. Ne lève
  /// jamais.
  Future<AccesDossierChapitres> verifierAcces() {
    final enCours = _verificationEnCours;
    if (enCours != null) return enCours;
    final nouvelle = _verifier();
    _verificationEnCours = nouvelle;
    return nouvelle;
  }

  Future<AccesDossierChapitres> _verifier() async {
    _estEnVerification = true;
    notifier();
    try {
      return await _service.verifierAccesDossier();
    } catch (exception) {
      // Le service ne lève jamais ; par prudence, l'état connu est gardé.
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        'Vérification du dossier des chapitres impossible',
        erreur: exception,
      );
      return _service.accesDossier;
    } finally {
      _estEnVerification = false;
      _verificationEnCours = null;
      notifier();
    }
  }

  /// Avertissement à montrer au client avant de confirmer le changement vers
  /// [nouveauDossier] (`null` ou vide : dossier par défaut), ou `null` s'il
  /// n'y a rien à signaler (par exemple un déplacement inachevé qui serait
  /// abandonné par un changement sans déplacement). Ne modifie rien ; une
  /// erreur de lecture devient l'erreur du résultat.
  Future<ResultatAction<String?>> avertissementAvantChangement(
    String? nouveauDossier, {
    required bool deplacerArchives,
  }) async {
    try {
      final texte = await _service.avertissementAvantChangement(
        nouveauDossier,
        deplacerArchives: deplacerArchives,
      );
      return ResultatAction<String?>.reussite(texte);
    } catch (exception, pile) {
      return ResultatAction<String?>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }

  /// Change le dossier des chapitres pour [nouveauDossier] (`null` ou vide :
  /// dossier par défaut), en déplaçant les archives si [deplacerArchives].
  /// La progression est exposée par [faits] et [total]. Un refus du service
  /// devient l'erreur du résultat, avec son message tel quel.
  Future<ResultatAction<ResultatChangementDossier>> changerDossier(
    String? nouveauDossier, {
    bool deplacerArchives = true,
  }) async {
    if (_estEnChangement) {
      // Double clic : le premier changement continue, rien n'est relancé.
      return const ResultatAction<ResultatChangementDossier>.echec(
        DescriptionErreur(
          NatureErreur.refus,
          detail: 'Un changement du dossier des chapitres est déjà en cours.',
        ),
      );
    }
    _estEnChangement = true;
    _faits = 0;
    _total = 0;
    notifier();
    try {
      final resultat = await _service.changerDossierChapitres(
        nouveauDossier,
        deplacerArchives: deplacerArchives,
        surProgression: (faits, total) {
          _faits = faits;
          _total = total;
          notifier();
        },
      );
      return ResultatAction<ResultatChangementDossier>.reussite(resultat);
    } catch (exception, pile) {
      return ResultatAction<ResultatChangementDossier>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    } finally {
      _estEnChangement = false;
      notifier();
      // Dossier choisi et déplacement inachevé ont pu changer, même après
      // un échec (copie interrompue).
      unawaited(charger());
    }
  }

  /// Renonce au changement refusé (chapitre en cours) : la file reprend.
  void reprendreFile() {
    _service.reprendreFile();
    notifier();
  }

  /// Oublie le déplacement inachevé ; les chapitres restés dans l'autre
  /// dossier seront retéléchargés selon les règles.
  Future<ResultatAction<bool>> abandonnerDeplacementInacheve() async {
    try {
      await _service.abandonnerDeplacementInacheve();
      _deplacementInacheve = null;
      notifier();
      return const ResultatAction<bool>.reussite(true);
    } catch (exception, pile) {
      return ResultatAction<bool>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    _abonnement = null;
    super.dispose();
  }
}
