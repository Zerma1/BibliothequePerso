/// Mise à jour automatique de l'application (version 0.4.0) : vérification
/// au démarrage, bandeau de l'accueil, téléchargement et lancement de
/// l'installateur.
library;

import '../services/service_mise_a_jour_application.dart';
import 'description_erreur.dart';

// Types des résultats réexportés : l'interface ne lit que lib/etat/.
export '../services/service_mise_a_jour_application.dart'
    show
        ApplicationAJour,
        EchecVerificationMiseAJour,
        NouvelleVersionDisponible,
        ResultatVerificationMiseAJour,
        VerificationNonFaite;

/// Ferme l'application (fournie par `main.dart`) une fois l'installateur
/// lancé.
typedef QuitterApplication = Future<void> Function();

/// Issue de [EtatMiseAJourApplication.mettreAJour].
class ResultatMiseAJour {
  /// Installateur lancé : l'application se ferme.
  const ResultatMiseAJour.lance() : urlPage = null, erreur = null;

  /// Plateforme sans installation automatique : page de la version à
  /// ouvrir dans le navigateur.
  const ResultatMiseAJour.page(Uri this.urlPage) : erreur = null;

  /// Échec du téléchargement ou du lancement.
  const ResultatMiseAJour.echec(DescriptionErreur this.erreur) : urlPage = null;

  /// Page à ouvrir, ou `null`.
  final Uri? urlPage;

  /// Erreur à afficher, ou `null`.
  final DescriptionErreur? erreur;

  /// `true` si l'installateur a été lancé.
  bool get estLance => urlPage == null && erreur == null;
}

/// État de la mise à jour de l'application : bandeau de l'accueil et
/// section des Paramètres.
///
/// Ne fait aucune requête lui-même : tout passe par
/// [ServiceMiseAJourApplication], qui limite les vérifications (une par
/// jour, limite de GitHub partagée avec les tickets).
class EtatMiseAJourApplication extends EtatNotifiant {
  /// Crée l'état branché sur [_service] ; [quitterApplication] ferme
  /// l'application une fois l'installateur lancé.
  EtatMiseAJourApplication(
    this._service, {
    required QuitterApplication quitterApplication,
  }) : _quitter = quitterApplication;

  final ServiceMiseAJourApplication _service;
  final QuitterApplication _quitter;

  NouvelleVersionDisponible? _nouvelleVersion;
  bool _bandeauMasque = false;
  bool _estEnVerification = false;
  ResultatVerificationMiseAJour? _dernierResultat;
  bool _estEnTelechargement = false;
  double? _progression;
  DescriptionErreur? _erreurMiseAJour;
  bool _verificationActivee =
      ServiceMiseAJourApplication.verificationActiveeParDefaut;
  DateTime? _derniereVerification;
  bool _estCharge = false;

  /// Nouvelle version trouvée par la dernière vérification, ou `null`.
  NouvelleVersionDisponible? get nouvelleVersion => _nouvelleVersion;

  /// `true` si le bandeau de l'accueil propose la mise à jour : version
  /// téléchargeable, non ignorée, non repoussée à « Plus tard » ; ou
  /// téléchargement en cours (sa progression reste visible).
  bool get bandeauVisible {
    if (_estEnTelechargement) return true;
    final nouvelle = _nouvelleVersion;
    return nouvelle != null &&
        nouvelle.estTelechargeable &&
        !nouvelle.estIgnoree &&
        !_bandeauMasque;
  }

  /// `true` pendant une vérification.
  bool get estEnVerification => _estEnVerification;

  /// Résultat de la dernière vérification (démarrage ou « Vérifier
  /// maintenant »), ou `null`.
  ResultatVerificationMiseAJour? get dernierResultat => _dernierResultat;

  /// `true` pendant le téléchargement de l'installateur.
  bool get estEnTelechargement => _estEnTelechargement;

  /// Avancée du téléchargement entre 0 et 1, ou `null` si la taille est
  /// inconnue (barre indéterminée).
  double? get progression => _progression;

  /// Erreur du dernier essai de mise à jour, ou `null`.
  DescriptionErreur? get erreurMiseAJour => _erreurMiseAJour;

  /// Réglage « Vérifier les mises à jour chaque jour ».
  bool get verificationActivee => _verificationActivee;

  /// Date (UTC) de la dernière vérification réussie, ou `null`.
  DateTime? get derniereVerification => _derniereVerification;

  /// `true` une fois les réglages lus.
  bool get estCharge => _estCharge;

  /// `true` si l'installateur peut être lancé sur cet appareil (Windows).
  bool get installationAutomatiquePossible =>
      _service.installationAutomatiquePossible;

  /// Au démarrage : supprime les installateurs restés dans le dossier
  /// temporaire, lit les réglages, puis vérifie (le service ignore la
  /// vérification si elle est désactivée ou trop récente). Ne lève jamais.
  Future<void> demarrer() async {
    await _service.nettoyerInstallateurs();
    await chargerReglages();
    await _verifier(forcee: false);
  }

  /// Lit le réglage et la date de la dernière vérification (le service ne
  /// lève pas : valeurs par défaut si la base ne répond pas).
  Future<void> chargerReglages() async {
    _verificationActivee = await _service.chargerVerificationActivee();
    _derniereVerification = await _service.chargerDerniereVerification();
    _estCharge = true;
    notifier();
  }

  /// « Vérifier maintenant » : vérification forcée, résultat renvoyé pour
  /// l'afficher.
  Future<ResultatVerificationMiseAJour> verifierMaintenant() =>
      _verifier(forcee: true);

  Future<ResultatVerificationMiseAJour> _verifier({
    required bool forcee,
  }) async {
    _estEnVerification = true;
    notifier();
    final resultat = await _service.verifier(forcee: forcee);
    _estEnVerification = false;
    // Une vérification automatique sautée (désactivée, trop récente) ne
    // change rien à ce qui est affiché.
    if (resultat is! VerificationNonFaite) {
      _dernierResultat = resultat;
      switch (resultat) {
        case NouvelleVersionDisponible():
          _nouvelleVersion = resultat;
        case ApplicationAJour():
          _nouvelleVersion = null;
        case EchecVerificationMiseAJour():
        case VerificationNonFaite():
          // Un échec réseau n'efface pas une version déjà trouvée.
          break;
      }
      _derniereVerification = await _service.chargerDerniereVerification();
    }
    notifier();
    return resultat;
  }

  /// Active ou désactive la vérification quotidienne.
  Future<ResultatAction<bool>> modifierVerificationActivee(bool active) async {
    try {
      await _service.enregistrerVerificationActivee(active);
      _verificationActivee = active;
      notifier();
      return ResultatAction<bool>.reussite(active);
    } catch (exception, pile) {
      return ResultatAction<bool>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }

  /// « Plus tard » : le bandeau disparaît jusqu'au prochain démarrage.
  void masquerBandeau() {
    _bandeauMasque = true;
    notifier();
  }

  /// « Ignorer cette version » : elle n'est plus proposée automatiquement.
  Future<ResultatAction<bool>> ignorerVersion() async {
    final nouvelle = _nouvelleVersion;
    if (nouvelle == null) return const ResultatAction<bool>.reussite(false);
    try {
      await _service.ignorerVersion(nouvelle.release.version);
      _nouvelleVersion = NouvelleVersionDisponible(
        nouvelle.release,
        estIgnoree: true,
      );
      notifier();
      return const ResultatAction<bool>.reussite(true);
    } catch (exception, pile) {
      return ResultatAction<bool>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }

  /// « Mettre à jour » : hors Windows, renvoie la page de la version (rien
  /// n'est téléchargé : l'installateur ne servirait pas) ; sous Windows,
  /// télécharge et vérifie l'installateur, le lance puis ferme
  /// l'application.
  Future<ResultatMiseAJour> mettreAJour() async {
    final nouvelle = _nouvelleVersion;
    if (nouvelle == null || _estEnTelechargement) {
      return const ResultatMiseAJour.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    final release = nouvelle.release;
    if (!_service.installationAutomatiquePossible) {
      final page = Uri.tryParse(release.urlPage);
      if (page != null) return ResultatMiseAJour.page(page);
    }
    _estEnTelechargement = true;
    _progression = 0;
    _erreurMiseAJour = null;
    notifier();
    try {
      final fichier = await _service.telecharger(
        release,
        progression: _suivreProgression,
      );
      final lancement = await _service.lancerInstallation(
        fichier,
        release: release,
      );
      if (lancement.lance) {
        await _quitter();
        return const ResultatMiseAJour.lance();
      }
      final page = lancement.urlPage;
      if (page != null) return ResultatMiseAJour.page(page);
      return _echec(
        DescriptionErreur(
          NatureErreur.refus,
          detail: lancement.messageErreur ?? '',
        ),
      );
    } catch (exception, pile) {
      // ErreurService (message lisible du service) ou erreur imprévue.
      return _echec(DescriptionErreur.depuis(exception, pile));
    } finally {
      _estEnTelechargement = false;
      _progression = null;
      notifier();
    }
  }

  ResultatMiseAJour _echec(DescriptionErreur erreur) {
    _erreurMiseAJour = erreur;
    return ResultatMiseAJour.echec(erreur);
  }

  void _suivreProgression(int recus, int? total) {
    final nouvelle = total == null || total <= 0
        ? null
        : (recus / total).clamp(0.0, 1.0);
    final ancienne = _progression;
    // Un rafraîchissement par point de pourcentage au plus : la barre reste
    // fluide sans reconstruire l'écran à chaque morceau reçu.
    if (nouvelle == null
        ? ancienne == null
        : ancienne != null && (nouvelle - ancienne).abs() < 0.01) {
      return;
    }
    _progression = nouvelle;
    notifier();
  }
}
