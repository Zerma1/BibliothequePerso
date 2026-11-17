// Partie de la bibliothèque `service_telechargement.dart` : le changement
// du dossier des chapitres a besoin de la pause et du verrou de la file, qui
// restent privés au service de téléchargement.
part of 'service_telechargement.dart';

/// Message des actions refusées entre un changement de dossier (avec
/// déplacement des archives) et le redémarrage de l'application.
const String _messageRedemarrage =
    "Le dossier des chapitres vient d'être changé : redémarrez "
    "l'application pour lire ou supprimer des chapitres téléchargés.";

/// Dossier des chapitres téléchargés (paramètres) : choix d'un dossier
/// local, d'un lecteur réseau ou d'un NAS, déplacement des archives, retour
/// au dossier par défaut, et état d'accès pour le bandeau « dossier
/// inaccessible ».
///
/// Le dossier choisi est enregistré dans [ServiceParametres.cleDossierChapitres]
/// et ne s'applique qu'**au prochain démarrage** ([creerStockage]) : d'ici
/// là, la file de téléchargement reste en pause.
///
/// Les rapports d'erreur et les exports ne suivent jamais ce dossier : ils
/// restent dans le dossier par défaut, pour rester accessibles même NAS
/// éteint (décision de l'orchestrateur, 2026-11-17).
class ServiceDossierChapitres {
  /// Crée le service.
  ///
  /// [cheminDossierParDefaut] : dossier par défaut de l'application
  /// (`cheminParDefautDossierTelechargements`, remplacé dans les tests).
  ServiceDossierChapitres({
    required ServiceTelechargement serviceTelechargement,
    required DepotParametres depotParametres,
    Future<String> Function()? cheminDossierParDefaut,
  }) : _service = serviceTelechargement,
       _depot = depotParametres,
       _cheminDossierParDefaut =
           cheminDossierParDefaut ?? cheminParDefautDossierTelechargements;

  final ServiceTelechargement _service;
  final DepotParametres _depot;
  final Future<String> Function() _cheminDossierParDefaut;

  /// Changement de dossier en cours (un seul à la fois).
  Future<ResultatChangementDossier>? _changement;

  /// Crée le stockage des archives d'après le réglage enregistré : dossier
  /// choisi par le client ([StockageTelechargements.personnalise]) ou
  /// dossier par défaut. À appeler au démarrage (`construireServices`).
  ///
  /// Ne vérifie pas que le dossier choisi est joignable (NAS éteint au
  /// démarrage) : l'application démarre quand même, le bandeau
  /// ([accesDossier]) prévient le client et rien n'est modifié en base. Une
  /// erreur de lecture de la base remonte : se rabattre sur le dossier par
  /// défaut ferait croire toutes les archives perdues.
  static Future<StockageTelechargements> creerStockage(
    DepotParametres depot,
  ) async {
    return StockageTelechargements.depuisReglage(
      await depot.chargerTexte(ServiceParametres.cleDossierChapitres),
    );
  }

  /// Prévient l'interface à chaque changement (accès au dossier, pause,
  /// file) : même flux que `ServiceTelechargement.changements`.
  Stream<void> get changements => _service.changements;

  /// Dossier des chapitres utilisé pendant cette session.
  String get dossierActuel => _service._stockage.dossierRacine;

  /// `true` si le dossier de cette session a été choisi par le client.
  bool get estDossierPersonnalise => _service._stockage.estPersonnalise;

  /// `true` si le dossier a été changé pendant cette session : il faut
  /// redémarrer l'application pour l'utiliser.
  bool get redemarrageNecessaire => _service._dossierChange;

  /// `true` si la file de téléchargement est en pause (changement de
  /// dossier demandé ou fait).
  bool get estFileEnPause => _service._enPause;

  /// Dernier état connu du dossier des chapitres, pour le bandeau
  /// (`AccesDossierChapitres.message`). Mis à jour par la file avant chaque
  /// chapitre, au démarrage et par [verifierAccesDossier] ; [changements]
  /// prévient quand il change.
  AccesDossierChapitres get accesDossier => _service._accesDossier;

  /// Contrôle tout de suite le dossier des chapitres (au retour au premier
  /// plan, bouton « Réessayer » du bandeau) et renvoie son état. S'il
  /// redevient accessible, les téléchargements en attente reprennent. Ne
  /// lève jamais ; aucune requête réseau vers les sites.
  ///
  /// LIMITE : un partage réseau éteint peut mettre plusieurs secondes à
  /// répondre (délai du système).
  Future<AccesDossierChapitres> verifierAccesDossier() =>
      _service._actualiserAcces();

  /// Dossier choisi par le client dans les réglages, ou `null` pour le
  /// dossier par défaut. Peut différer de [dossierActuel] avant un
  /// redémarrage.
  Future<String?> chargerDossierChoisi() async {
    final texte = await _depot.chargerTexte(
      ServiceParametres.cleDossierChapitres,
    );
    final propre = texte?.trim() ?? '';
    return propre.isEmpty ? null : propre;
  }

  /// Chemin du dossier par défaut de l'application (affiché à côté du
  /// bouton « Revenir au dossier par défaut »).
  Future<String> chargerCheminDossierParDefaut() => _cheminDossierParDefaut();

  /// Dossier vers lequel un déplacement des archives a commencé sans se
  /// terminer, ou `null`. L'interface propose alors de le reprendre
  /// ([changerDossierChapitres] avec ce dossier) ou de l'abandonner
  /// ([abandonnerDeplacementInacheve]).
  Future<String?> chargerDeplacementInacheve() async {
    final texte = await _depot.chargerTexte(
      ServiceParametres.cleDeplacementDossierEnCours,
    );
    final propre = texte?.trim() ?? '';
    return propre.isEmpty ? null : propre;
  }

  /// Oublie un déplacement inachevé : le contrôle des archives manquantes
  /// reprend au prochain démarrage, et les chapitres dont l'archive est
  /// restée dans l'autre dossier seront retéléchargés selon les règles.
  Future<void> abandonnerDeplacementInacheve() =>
      _depot.supprimer(ServiceParametres.cleDeplacementDossierEnCours);

  /// Lève la pause posée par un changement de dossier refusé (chapitre en
  /// cours de téléchargement) quand le client y renonce, et relance la
  /// file. Sans effet après un changement réussi : la file reste en pause
  /// jusqu'au redémarrage.
  void reprendreFile() {
    if (_service._dossierChange || !_service._enPause) return;
    _service._enPause = false;
    _service._signaler();
    unawaited(_service.lancerTraitement());
  }

  /// Change le dossier des chapitres téléchargés.
  ///
  /// [nouveauDossier] : chemin complet choisi par le client (disque local,
  /// lecteur réseau `Z:\…`, chemin UNC `\\nas\partage\…`, dossier monté) ;
  /// `null` ou vide pour revenir au dossier par défaut.
  ///
  /// Étapes : le dossier est validé (création, essai d'écriture, fichier
  /// repère), puis la file est mise en pause. Avec [deplacerArchives], les
  /// archives et couvertures sont déplacées (progression dans
  /// [surProgression] : `(faits, total)`), verrou de la file tenu pour que
  /// la tâche de fond Android n'écrive rien pendant ce temps. Le réglage est
  /// enregistré **après** le déplacement réussi. Sans [deplacerArchives],
  /// seul le réglage change : les chapitres restés dans l'ancien dossier
  /// seront retéléchargés dans le nouveau selon les règles.
  ///
  /// Le nouveau dossier s'applique au prochain démarrage
  /// ([ResultatChangementDossier.redemarrageNecessaire]) ; d'ici là la file
  /// reste en pause, et après un déplacement la lecture et la suppression
  /// d'archives sont refusées (message clair).
  ///
  /// Lève une [ErreurService] au message clair, sans rien enregistrer :
  /// - dossier refusé (chemin incomplet, accès refusé, disque plein, réseau
  ///   absent…), ou déjà utilisé ;
  /// - chapitre en cours de téléchargement : la file est **laissée en
  ///   pause** pour s'arrêter après ce chapitre, le client réessaie un
  ///   instant plus tard (ou appelle [reprendreFile] s'il renonce) ;
  /// - file tenue par la tâche de fond Android ;
  /// - autre déplacement inachevé vers un autre dossier ;
  /// - copie interrompue : les fichiers déjà déplacés restent dans le
  ///   nouveau dossier, [chargerDeplacementInacheve] le signale et relancer
  ///   la même demande reprend où elle s'est arrêtée ;
  /// - changement déjà fait ou déjà en cours pendant cette session.
  Future<ResultatChangementDossier> changerDossierChapitres(
    String? nouveauDossier, {
    bool deplacerArchives = true,
    void Function(int faits, int total)? surProgression,
  }) async {
    // Deux demandes à la fois (double clic) déplaceraient les mêmes fichiers
    // en parallèle : la seconde est refusée.
    if (_changement != null) {
      throw const ErreurService(
        'Un changement du dossier des chapitres est déjà en cours.',
      );
    }
    final changement = _changer(
      nouveauDossier,
      deplacerArchives: deplacerArchives,
      surProgression: surProgression,
    );
    _changement = changement;
    try {
      return await changement;
    } finally {
      _changement = null;
    }
  }

  Future<ResultatChangementDossier> _changer(
    String? nouveauDossier, {
    required bool deplacerArchives,
    required void Function(int faits, int total)? surProgression,
  }) async {
    final service = _service;
    if (service._dossierChange) {
      throw const ErreurService(
        'Le dossier des chapitres a déjà été changé : redémarrez '
        "l'application avant de le changer à nouveau.",
      );
    }
    final parDefaut = await _cheminDossierParDefaut();
    final demande = nouveauDossier?.trim() ?? '';
    final cible = demande.isEmpty ? parDefaut : demande;
    // Choisir le chemin du dossier par défaut revient à y revenir : le
    // réglage est effacé plutôt que d'en faire un dossier « personnalisé »
    // (qui exigerait son fichier repère).
    final versDefaut = demande.isEmpty || _memeChemin(cible, parDefaut);
    if (_memeChemin(cible, service._stockage.dossierRacine)) {
      throw const ErreurService("C'est déjà le dossier des chapitres.");
    }
    if (deplacerArchives) {
      final inacheve = await chargerDeplacementInacheve();
      if (inacheve != null && !_memeChemin(inacheve, cible)) {
        throw ErreurService(
          'Un déplacement des chapitres vers « $inacheve » est resté '
          'inachevé : reprenez-le (même dossier) ou abandonnez-le avant '
          "d'en choisir un autre.",
        );
      }
    }

    // Validation avant toute autre action : un dossier refusé ne met même
    // pas la file en pause.
    final String valide;
    try {
      valide = await StockageTelechargements.validerDossier(cible);
    } on ErreurStockage catch (erreur) {
      throw ErreurService(erreur.message, cause: erreur);
    }

    final etaitEnPause = service._enPause;
    service._enPause = true;
    // Pause gardée après un refus « chapitre en cours » : la file s'arrête
    // après ce chapitre et la demande suivante du client peut aboutir.
    var garderPause = false;
    var reussi = false;
    try {
      BilanDeplacement? bilan;
      if (deplacerArchives) {
        if (service.estEnCours) {
          garderPause = true;
          throw const ErreurService(
            'Un chapitre est en cours de téléchargement : la file est mise '
            "en pause et s'arrêtera à la fin de ce chapitre. Réessayez dans "
            'un instant.',
          );
        }
        bilan = await _deplacer(valide, surProgression);
      }
      // Réglage enregistré seulement maintenant : un déplacement échoué ne
      // laisse jamais un réglage qui pointe vers un dossier incomplet.
      if (versDefaut) {
        await _depot.supprimer(ServiceParametres.cleDossierChapitres);
      } else {
        await _depot.enregistrerTexte(
          ServiceParametres.cleDossierChapitres,
          valide,
        );
      }
      // LIMITE : réglage et repère de déplacement sont deux écritures
      // séparées. Si la seconde échoue, le déplacement reste signalé comme
      // inachevé : le contrôle des archives est seulement suspendu jusqu'à
      // ce que le client le reprenne ou l'abandonne (rien n'est perdu).
      await _depot.supprimer(ServiceParametres.cleDeplacementDossierEnCours);
      service._dossierChange = true;
      service._archivesDeplacees = deplacerArchives;
      reussi = true;
      return ResultatChangementDossier(
        dossierChoisi: versDefaut ? null : valide,
        cheminDossier: valide,
        bilan: bilan,
      );
    } finally {
      if (!reussi && !garderPause) {
        // Échec : la file reprend comme avant, toujours sur l'ancien dossier
        // (le réglage n'a pas changé).
        service._enPause = etaitEnPause;
        if (!etaitEnPause) unawaited(service.lancerTraitement());
      }
      service._signaler();
    }
  }

  /// Déplace les archives vers [destination] en tenant le verrou de la
  /// file (renouvelé pendant toute la copie), et renvoie le bilan.
  Future<BilanDeplacement> _deplacer(
    String destination,
    void Function(int faits, int total)? surProgression,
  ) async {
    final service = _service;
    // Le verrou partagé tient la tâche de fond Android à l'écart : elle
    // écrirait sinon de nouvelles archives dans l'ancien dossier pendant la
    // copie.
    final autre = await service._prendreVerrou();
    if (autre != null) {
      throw const ErreurService(
        'Des chapitres sont en cours de téléchargement en arrière-plan : '
        'réessayez dans quelques minutes.',
      );
    }
    Timer? renouvellement;
    final etaitInacheve = await chargerDeplacementInacheve() != null;
    var faits = 0;
    try {
      // Repère posé avant la première copie : si l'application est fermée
      // pendant le déplacement, le contrôle du prochain démarrage ne prend
      // pas les archives déjà déplacées pour des archives perdues.
      await _depot.enregistrerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
        destination,
      );
      renouvellement = Timer.periodic(
        service._dureeVerrou ~/ fractionRenouvellementVerrou,
        (_) async {
          try {
            await service._renouvelerVerrou(verifier: false);
          } catch (erreur) {
            // Le verrou reste valable jusqu'à son expiration ; prochain
            // essai au tour suivant.
            debugPrint('Verrou non renouvelé pendant le déplacement : $erreur');
          }
        },
      );
      return await service._stockage.deplacerArchivesVers(
        destination,
        surProgression: (fait, total) {
          faits = fait;
          surProgression?.call(fait, total);
        },
      );
    } on ErreurStockage catch (erreur) {
      if (faits == 0 && !etaitInacheve) {
        // Aucun fichier n'a quitté l'ancien dossier (refus avant la
        // première copie) : rien d'inachevé à signaler.
        try {
          await _depot.supprimer(
            ServiceParametres.cleDeplacementDossierEnCours,
          );
        } catch (erreurRepere) {
          debugPrint('Repère de déplacement non effacé : $erreurRepere');
        }
        throw ErreurService(erreur.message, cause: erreur);
      }
      throw ErreurService(
        '${erreur.message} Les chapitres déjà déplacés ne sont pas perdus : '
        'relancez le changement vers le même dossier pour terminer.',
        cause: erreur,
      );
    } finally {
      renouvellement?.cancel();
      await service._libererVerrou();
    }
  }

  /// `true` si [a] et [b] désignent le même chemin (même écriture une fois
  /// normalisée ; sous Windows, sans tenir compte de la casse).
  static bool _memeChemin(String a, String b) =>
      chemins.equals(chemins.normalize(a.trim()), chemins.normalize(b.trim()));
}
