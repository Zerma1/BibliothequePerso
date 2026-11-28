/// Mise à jour automatique de l'application (version 0.4.0).
///
/// Demande du client : une fois par jour, vérifier la dernière version
/// publiée depuis `main` (release GitHub `vX.Y.Z`) et proposer de se mettre à
/// jour toute seule. Le réseau est assuré par [ClientMiseAJourGithub] ; ce
/// service décide **quand** vérifier, **quoi** proposer, où télécharger et
/// comment lancer l'installateur.
///
/// Installateur (en-tête de `installateur/bibliotheque_perso.iss`) :
/// `/ACTION=METTREAJOUR` choisit la mise à jour sans question ; `/SILENT`
/// (Inno Setup) n'affiche que la fenêtre de progression. Les deux vont
/// ensemble : `WizardSilent` vaut vrai avec `/SILENT` comme avec
/// `/VERYSILENT`, donc l'application ouverte est arrêtée sans question
/// (`FermerApplication(..., not WizardSilent)`) et installation.json est
/// gardé tel quel.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import '../donnees/depot_parametres.dart';
import '../modeles/journal.dart';
import '../sources/client_mise_a_jour_github.dart';
import '../sources/constantes_sources.dart';
import '../sources/erreur_source.dart';
import '../sources/limite_github.dart';
import 'erreur_service.dart';

export '../sources/client_mise_a_jour_github.dart'
    show
        ProgressionTelechargement,
        ReleaseApplication,
        VersionApplication,
        FichierRelease;

/// Lance un programme **détaché** (il survit à la fermeture de
/// l'application) ; remplaçable dans les tests pour ne rien lancer.
typedef LanceurProcessus = Future<void> Function(
  String executable,
  List<String> arguments,
);

/// Raison pour laquelle aucune vérification n'a été faite.
enum RaisonNonVerification {
  /// Le client a désactivé « Vérifier les mises à jour ».
  desactivee,

  /// Une vérification a eu lieu il y a moins de
  /// [ServiceMiseAJourApplication.intervalleVerification].
  tropRecente,

  /// La dernière tentative a échoué il y a moins de
  /// [ServiceMiseAJourApplication.intervalleApresEchec].
  echecRecent,
}

/// Résultat de [ServiceMiseAJourApplication.verifier] (jamais une
/// exception).
sealed class ResultatVerificationMiseAJour {
  const ResultatVerificationMiseAJour();
}

/// Rien n'a été demandé à GitHub (voir [raison]).
class VerificationNonFaite extends ResultatVerificationMiseAJour {
  /// Crée le résultat.
  const VerificationNonFaite(this.raison);

  /// Pourquoi rien n'a été vérifié.
  final RaisonNonVerification raison;
}

/// L'application est à jour (ou le dépôt n'a encore aucune release).
class ApplicationAJour extends ResultatVerificationMiseAJour {
  /// Crée le résultat.
  const ApplicationAJour({this.derniereVersion});

  /// Dernière version publiée, ou `null` si le dépôt n'a aucune release.
  final VersionApplication? derniereVersion;
}

/// Une version plus récente que celle de l'application est publiée.
class NouvelleVersionDisponible extends ResultatVerificationMiseAJour {
  /// Crée le résultat.
  const NouvelleVersionDisponible(this.release, {this.estIgnoree = false});

  /// Release publiée (notes, page, installateur).
  final ReleaseApplication release;

  /// `true` si le client a choisi « Ignorer cette version » pour cette
  /// version : seule une vérification **forcée** la renvoie alors
  /// (l'interface peut l'afficher avec la mention « ignorée ») ; une
  /// vérification automatique renvoie [ApplicationAJour].
  final bool estIgnoree;

  /// `true` si l'installateur et son empreinte sont joints : le
  /// téléchargement peut être proposé. Sinon, seul le lien vers
  /// [ReleaseApplication.urlPage] est utilisable.
  bool get estTelechargeable => release.estTelechargeable;
}

/// La vérification a échoué ; [message] est lisible tel quel.
class EchecVerificationMiseAJour extends ResultatVerificationMiseAJour {
  /// Crée le résultat.
  const EchecVerificationMiseAJour(this.message, {this.heureReprise});

  /// Explication en français, affichable telle quelle.
  final String message;

  /// Heure (UTC) où GitHub accepte de nouveau les requêtes, si sa limite est
  /// atteinte.
  final DateTime? heureReprise;
}

/// Résultat de [ServiceMiseAJourApplication.lancerInstallation] (jamais une
/// exception).
class ResultatLancementInstallation {
  /// Crée le résultat.
  const ResultatLancementInstallation({
    this.lance = false,
    this.urlPage,
    this.messageErreur,
  });

  /// `true` si l'installateur est lancé : l'interface ferme l'application
  /// (l'installateur l'arrêterait de toute façon).
  final bool lance;

  /// Plateforme sans installation automatique (Android, Linux) : page de la
  /// release à ouvrir dans le navigateur.
  final Uri? urlPage;

  /// Message lisible si le lancement a échoué, sinon `null`.
  final String? messageErreur;
}

/// Vérification quotidienne, téléchargement vérifié et lancement de
/// l'installateur de la dernière version de l'application.
class ServiceMiseAJourApplication {
  /// Crée le service.
  ///
  /// [versionApplication] : version de l'application en cours
  /// (`X.Y.Z`, `X.Y.Z+N` ou `X.Y.Z-test` acceptés). [dossierTemporaire] :
  /// dossier parent du sous-dossier [nomDossierTelechargement] (par défaut
  /// `Directory.systemTemp`). [lanceur], [estWindows] et [horloge]
  /// remplacent le lancement réel, la plateforme et `DateTime.now` dans les
  /// tests.
  ServiceMiseAJourApplication(
    this._depot,
    this._client, {
    required String versionApplication,
    Directory? dossierTemporaire,
    LanceurProcessus? lanceur,
    bool? estWindows,
    DateTime Function()? horloge,
  }) : _versionApplication = versionApplication,
       _dossierTemporaire = dossierTemporaire,
       _lanceur = lanceur ?? _lancerDetache,
       _estWindows = estWindows ?? Platform.isWindows,
       _horloge = horloge ?? DateTime.now;

  final DepotParametres _depot;
  final ClientMiseAJourGithub _client;
  final String _versionApplication;
  final Directory? _dossierTemporaire;
  final LanceurProcessus _lanceur;
  final bool _estWindows;
  final DateTime Function() _horloge;

  Future<ResultatVerificationMiseAJour>? _verificationEnCours;
  Future<File>? _telechargementEnCours;
  DateTime? _dernierEchec;

  /// Clé : « Vérifier les mises à jour », entier 1 (activé, par défaut) ou 0.
  // Clés lues ici plutôt que par des méthodes de `ServiceParametres` : ce
  // service est implémenté par de faux services dans les tests de
  // l'interface, qui devraient tous suivre (même choix que
  // `ServiceJournal` pour `journal.detaille`).
  static const String cleVerificationActivee = 'application.mise_a_jour.active';

  /// Clé : date (UTC, ISO 8601) de la dernière vérification réussie.
  static const String cleDerniereVerification =
      'application.mise_a_jour.derniere';

  /// Clé : version (`X.Y.Z`) pour laquelle le client a choisi « Ignorer
  /// cette version ».
  static const String cleVersionIgnoree =
      'application.mise_a_jour.version_ignoree';

  /// « Vérifier les mises à jour » tant que le client n'a rien choisi.
  static const bool verificationActiveeParDefaut = true;

  /// Écart minimal entre deux vérifications automatiques (demande du client :
  /// une fois par jour).
  static const Duration intervalleVerification = Duration(hours: 24);

  /// Après un échec (réseau absent…), délai avant un nouvel essai
  /// automatique : l'échec n'est pas enregistré comme une vérification (le
  /// client n'attend pas 24 h pour rien), mais on ne réessaie pas à chaque
  /// appel (limite de 60 requêtes par heure de GitHub, partagée avec les
  /// tickets).
  static const Duration intervalleApresEchec = Duration(hours: 1);

  /// Sous-dossier du dossier temporaire réservé aux installateurs.
  static const String nomDossierTelechargement = 'bibliotheque_perso_maj';

  /// Paramètres de l'installateur : mise à jour sans question, avec la
  /// barre de progression visible (`/SILENT`, et non `/VERYSILENT`, pour
  /// que le client voie que quelque chose se passe), sans redémarrage de
  /// Windows, puis relance de l'application (`/RELANCER`, lu par la section
  /// `[Run]` de `installateur/bibliotheque_perso.iss`). `/SUPPRESSMSGBOXES`
  /// est volontairement absent : une erreur de l'installateur reste visible.
  static const List<String> parametresInstallation = <String>[
    '/ACTION=METTREAJOUR',
    '/SILENT',
    '/NORESTART',
    '/RELANCER',
  ];

  // ------------------------------------------------------- Règles pures

  /// Version de l'application lue dans [texte] (fonction pure) : `v`
  /// initial, suffixe `+N` et suffixe `-…` (`-test`) retirés ; une version
  /// de test `X.Y.Z-test` vaut donc `X.Y.Z`. `null` si illisible.
  static VersionApplication? lireVersion(String texte) {
    var propre = texte.trim();
    if (propre.startsWith('v') || propre.startsWith('V')) {
      propre = propre.substring(1);
    }
    final plus = propre.indexOf('+');
    if (plus >= 0) propre = propre.substring(0, plus);
    final tiret = propre.indexOf('-');
    if (tiret >= 0) propre = propre.substring(0, tiret);
    return VersionApplication.analyser(propre);
  }

  /// `true` si une vérification automatique est due à [maintenant] (fonction
  /// pure) : jamais faite, faite il y a au moins [intervalleVerification],
  /// ou datée dans le futur (horloge de l'appareil reculée).
  static bool verificationDue(DateTime? derniere, DateTime maintenant) {
    if (derniere == null) return true;
    final ecart = maintenant.toUtc().difference(derniere.toUtc());
    return ecart.isNegative || ecart >= intervalleVerification;
  }

  /// Nom attendu de l'installateur de [version] (fonction pure).
  static String nomInstallateur(VersionApplication version) =>
      '$prefixeNomInstallateur$version$suffixeNomInstallateur';

  // ------------------------------------------------------------ Réglages

  /// `true` si « Vérifier les mises à jour » est activé
  /// ([verificationActiveeParDefaut] si rien n'est enregistré ou si la
  /// valeur est illisible, ou si la base ne répond pas).
  Future<bool> chargerVerificationActivee() async {
    try {
      final valeur = await _depot.chargerEntier(cleVerificationActivee);
      if (valeur == 1) return true;
      if (valeur == 0) return false;
    } catch (erreur) {
      _journaliserBase('lecture du réglage impossible', erreur);
    }
    return verificationActiveeParDefaut;
  }

  /// Active ou désactive « Vérifier les mises à jour ».
  Future<void> enregistrerVerificationActivee(bool active) async {
    await _depot.enregistrerEntier(cleVerificationActivee, active ? 1 : 0);
    Journal.actuel.info(
      CategorieJournal.parametres,
      'Réglage mises à jour de l\'application : '
      '${active ? 'vérification activée' : 'vérification désactivée'}',
    );
  }

  /// Date de la dernière vérification réussie, ou `null`.
  Future<DateTime?> chargerDerniereVerification() async {
    try {
      final texte = await _depot.chargerTexte(cleDerniereVerification);
      return texte == null ? null : DateTime.tryParse(texte)?.toUtc();
    } catch (erreur) {
      _journaliserBase(
        'lecture de la dernière vérification impossible',
        erreur,
      );
      return null;
    }
  }

  /// Version ignorée par le client, ou `null`.
  Future<VersionApplication?> chargerVersionIgnoree() async {
    try {
      final texte = await _depot.chargerTexte(cleVersionIgnoree);
      return texte == null ? null : VersionApplication.analyser(texte.trim());
    } catch (erreur) {
      _journaliserBase('lecture de la version ignorée impossible', erreur);
      return null;
    }
  }

  /// « Ignorer cette version » : [version] n'est plus proposée
  /// automatiquement ; une version plus récente le sera.
  Future<void> ignorerVersion(VersionApplication version) async {
    await _depot.enregistrerTexte(cleVersionIgnoree, version.toString());
    Journal.actuel.info(
      CategorieJournal.parametres,
      'Mise à jour : version $version ignorée',
    );
  }

  /// Oublie la version ignorée (elle est de nouveau proposée).
  Future<void> annulerVersionIgnoree() => _depot.supprimer(cleVersionIgnoree);

  // -------------------------------------------------------- Vérification

  /// Vérifie si une nouvelle version est publiée.
  ///
  /// Sans [forcee] : rien n'est demandé à GitHub si la vérification est
  /// désactivée, si la dernière date de moins de [intervalleVerification],
  /// ou si un échec date de moins de [intervalleApresEchec]. [forcee]
  /// (« Vérifier maintenant ») passe outre ces trois règles, mais jamais la
  /// limite de requêtes de GitHub.
  ///
  /// Une vérification en cours est partagée plutôt que relancée. Ne lève
  /// jamais : les erreurs sont rangées dans [EchecVerificationMiseAJour].
  Future<ResultatVerificationMiseAJour> verifier({bool forcee = false}) {
    final enCours = _verificationEnCours;
    if (enCours != null) return enCours;
    final nouvelle = _verifier(forcee)
        .whenComplete(() => _verificationEnCours = null);
    _verificationEnCours = nouvelle;
    return nouvelle;
  }

  Future<ResultatVerificationMiseAJour> _verifier(bool forcee) async {
    try {
      final maintenant = _horloge().toUtc();
      if (!forcee) {
        if (!await chargerVerificationActivee()) {
          return const VerificationNonFaite(RaisonNonVerification.desactivee);
        }
        if (!verificationDue(await chargerDerniereVerification(), maintenant)) {
          return const VerificationNonFaite(RaisonNonVerification.tropRecente);
        }
        final echec = _dernierEchec;
        if (echec != null &&
            !maintenant.isBefore(echec) &&
            maintenant.difference(echec) < intervalleApresEchec) {
          return const VerificationNonFaite(RaisonNonVerification.echecRecent);
        }
      }

      final actuelle = lireVersion(_versionApplication);
      if (actuelle == null) {
        // Ne devrait pas arriver (version lue dans pubspec.yaml) : sans
        // version, on ne peut rien comparer, et rien n'est demandé à GitHub.
        Journal.actuel.avertissement(
          CategorieJournal.misesAJour,
          "Mise à jour de l'application : version actuelle illisible "
          '($_versionApplication)',
        );
        return const EchecVerificationMiseAJour(
          "La version de l'application est illisible : vérification "
          'impossible.',
        );
      }

      final ReleaseApplication? release;
      try {
        release = await _client.recupererDerniereVersion();
      } on ErreurLimiteGithub catch (erreur) {
        _dernierEchec = maintenant;
        Journal.actuel.avertissement(
          CategorieJournal.misesAJour,
          "Mise à jour de l'application : limite de requêtes GitHub atteinte",
        );
        return EchecVerificationMiseAJour(
          '${erreur.message}.',
          heureReprise: erreur.heureReprise,
        );
      } on ErreurSource catch (erreur) {
        _dernierEchec = maintenant;
        Journal.actuel.avertissement(
          CategorieJournal.misesAJour,
          "Mise à jour de l'application : vérification impossible",
          erreur: erreur,
        );
        return EchecVerificationMiseAJour(
          'Impossible de vérifier les mises à jour : ${erreur.message}.',
        );
      }

      // Réseau d'abord : la date n'est enregistrée qu'après une réponse
      // lisible de GitHub.
      _dernierEchec = null;
      await _enregistrerDerniereVerification(maintenant);

      if (release == null || release.version.compareTo(actuelle) <= 0) {
        Journal.actuel.info(
          CategorieJournal.misesAJour,
          "Mise à jour de l'application : à jour ($actuelle, dernière "
          '${release?.version ?? 'aucune'})',
        );
        return ApplicationAJour(derniereVersion: release?.version);
      }
      final ignoree = await chargerVersionIgnoree() == release.version;
      Journal.actuel.info(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : ${release.version} disponible "
        '(actuelle $actuelle'
        '${release.estTelechargeable ? '' : ', sans installateur'}'
        '${ignoree ? ', ignorée' : ''})',
      );
      if (ignoree && !forcee) {
        return ApplicationAJour(derniereVersion: release.version);
      }
      return NouvelleVersionDisponible(release, estIgnoree: ignoree);
    } catch (erreur, pile) {
      _dernierEchec = _horloge().toUtc();
      Journal.actuel.erreur(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : erreur inattendue",
        erreur: erreur,
        pile: pile,
      );
      return const EchecVerificationMiseAJour(
        'Erreur inattendue pendant la vérification des mises à jour.',
      );
    }
  }

  Future<void> _enregistrerDerniereVerification(DateTime date) async {
    try {
      await _depot.enregistrerTexte(
        cleDerniereVerification,
        date.toUtc().toIso8601String(),
      );
    } catch (erreur) {
      // La réponse reste utilisable : seule la règle « une fois par jour »
      // en pâtit (nouvel essai au prochain appel).
      _journaliserBase('date de vérification non enregistrée', erreur);
    }
  }

  // ------------------------------------------------------ Téléchargement

  /// Dossier réservé aux installateurs téléchargés
  /// (`<temporaire>/bibliotheque_perso_maj`, pas encore créé).
  Directory get dossierTelechargement => Directory(
    '${(_dossierTemporaire ?? Directory.systemTemp).path}'
    '${Platform.pathSeparator}$nomDossierTelechargement',
  );

  /// Télécharge l'installateur de [release] dans [dossierTelechargement] et
  /// vérifie son empreinte SHA-256 ; renvoie le fichier prêt à lancer.
  ///
  /// Les anciens installateurs du dossier sont d'abord supprimés. Un
  /// téléchargement déjà en cours est partagé (une seule connexion).
  ///
  /// Lève une [ErreurService] au message lisible si la release n'a pas
  /// d'installateur vérifiable, si GitHub ne répond pas, ou si le fichier
  /// est refusé (taille ou empreinte) : rien n'est alors laissé sur le
  /// disque.
  Future<File> telecharger(
    ReleaseApplication release, {
    ProgressionTelechargement? progression,
  }) {
    final enCours = _telechargementEnCours;
    if (enCours != null) return enCours;
    final nouveau = _telecharger(
      release,
      progression,
    ).whenComplete(() => _telechargementEnCours = null);
    _telechargementEnCours = nouveau;
    return nouveau;
  }

  Future<File> _telecharger(
    ReleaseApplication release,
    ProgressionTelechargement? progression,
  ) async {
    final installateur = release.installateur;
    final empreinte = release.fichierEmpreinte;
    if (installateur == null || empreinte == null) {
      throw const ErreurService(
        "Cette version n'a pas d'installateur vérifiable : "
        'téléchargez-la depuis sa page.',
      );
    }
    final nom = nomInstallateur(release.version);
    final dossier = dossierTelechargement;
    await nettoyerInstallateurs();
    try {
      // Empreinte d'abord : sans elle, rien n'est téléchargé.
      final attendue = await _client.recupererEmpreinteAttendue(
        empreinte.url,
        nomFichierAttendu: nom,
      );
      await dossier.create(recursive: true);
      final fichier = await _client.telechargerInstallateur(
        installateur.url,
        '${dossier.path}${Platform.pathSeparator}$nom',
        empreinteAttendue: attendue,
        tailleAttendue: installateur.taille,
        progression: progression,
      );
      Journal.actuel.info(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : installateur ${release.version} "
        'téléchargé et vérifié',
      );
      return fichier;
    } on ErreurLimiteGithub catch (erreur) {
      throw ErreurService('${erreur.message}.', cause: erreur);
    } on ErreurEmpreinteInstallateur catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : empreinte de l'installateur "
        'incorrecte',
        erreur: erreur,
      );
      throw ErreurService(
        "L'installateur téléchargé est abîmé ou a été remplacé : il a été "
        'supprimé. Réessayez plus tard.',
        cause: erreur,
      );
    } on ErreurSource catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : téléchargement impossible",
        erreur: erreur,
      );
      throw ErreurService(
        'Téléchargement de la mise à jour impossible : ${erreur.message}.',
        cause: erreur,
      );
    } on FileSystemException catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : dossier temporaire inutilisable",
        erreur: erreur,
      );
      throw ErreurService(
        'Le dossier temporaire ne peut pas recevoir la mise à jour.',
        cause: erreur,
      );
    }
  }

  /// Supprime les installateurs (et morceaux `.part`) laissés dans
  /// [dossierTelechargement]. Seuls les fichiers nommés comme un
  /// installateur de l'application sont touchés. Ne lève jamais ; à appeler
  /// aussi au démarrage, après une mise à jour.
  Future<void> nettoyerInstallateurs() async {
    final dossier = dossierTelechargement;
    try {
      if (!await dossier.exists()) return;
      await for (final element in dossier.list(followLinks: false)) {
        if (element is! File || !_estNomInstallateur(_nomFichier(element))) {
          continue;
        }
        try {
          await element.delete();
        } on FileSystemException {
          // LIMITE : installateur encore en cours d'exécution (verrouillé par
          // Windows) ou antivirus : il sera supprimé au prochain nettoyage.
        }
      }
    } on FileSystemException catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        "Mise à jour de l'application : nettoyage du dossier temporaire "
        'impossible',
        erreur: erreur,
      );
    }
  }

  static String _nomFichier(FileSystemEntity element) => element
      .uri
      .pathSegments
      .lastWhere((segment) => segment.isNotEmpty, orElse: () => '');

  /// `true` pour `bibliotheque_perso-X.Y.Z-installation.exe` (ou `.part`).
  static bool _estNomInstallateur(String nom) {
    var base = nom;
    if (base.endsWith('.part')) {
      base = base.substring(0, base.length - '.part'.length);
    }
    if (!base.startsWith(prefixeNomInstallateur) ||
        !base.endsWith(suffixeNomInstallateur)) {
      return false;
    }
    final version = base.substring(
      prefixeNomInstallateur.length,
      base.length - suffixeNomInstallateur.length,
    );
    return VersionApplication.analyser(version) != null;
  }

  // ---------------------------------------------------------- Lancement

  /// `true` si l'installation automatique est possible sur cet appareil
  /// (Windows seulement : l'installateur est un `.exe` Inno Setup).
  bool get installationAutomatiquePossible => _estWindows;

  /// Lance l'installateur [installateur] de [release], détaché, avec
  /// [parametresInstallation], puis rend la main : l'interface ferme alors
  /// l'application.
  ///
  /// Hors Windows : rien n'est lancé, [ResultatLancementInstallation.urlPage]
  /// donne la page de la release à ouvrir. Par sécurité, seul un fichier de
  /// [dossierTelechargement] au nom de l'installateur de [release] est
  /// lancé. Ne lève jamais.
  Future<ResultatLancementInstallation> lancerInstallation(
    File installateur, {
    required ReleaseApplication release,
  }) async {
    if (!_estWindows) {
      return ResultatLancementInstallation(
        urlPage: Uri.tryParse(release.urlPage),
      );
    }
    try {
      final attendu = File(
        '${dossierTelechargement.path}${Platform.pathSeparator}'
        '${nomInstallateur(release.version)}',
      ).absolute.path;
      // Jamais un autre fichier que celui téléchargé et vérifié par
      // `telecharger` : on n'exécute rien venu d'ailleurs.
      if (installateur.absolute.path.toLowerCase() != attendu.toLowerCase() ||
          !await installateur.exists()) {
        return const ResultatLancementInstallation(
          messageErreur:
              "L'installateur est introuvable : téléchargez de nouveau la "
              'mise à jour.',
        );
      }
      await _lanceur(attendu, parametresInstallation);
      Journal.actuel.info(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : installateur ${release.version} "
        'lancé',
      );
      return const ResultatLancementInstallation(lance: true);
    } catch (erreur, pile) {
      Journal.actuel.erreur(
        CategorieJournal.misesAJour,
        "Mise à jour de l'application : lancement de l'installateur "
        'impossible',
        erreur: erreur,
        pile: pile,
      );
      return const ResultatLancementInstallation(
        messageErreur: "L'installateur n'a pas pu être lancé.",
      );
    }
  }

  static Future<void> _lancerDetache(
    String executable,
    List<String> arguments,
  ) async {
    // Détaché : l'installateur continue après la fermeture de
    // l'application, qu'il doit justement remplacer.
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }

  static void _journaliserBase(String description, Object erreur) =>
      Journal.actuel.avertissement(
        CategorieJournal.base,
        "Mise à jour de l'application : $description",
        erreur: erreur,
      );
}
