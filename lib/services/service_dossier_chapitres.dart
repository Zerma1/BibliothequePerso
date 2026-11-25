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
  ///
  /// [cheminFichierEmplacements] : chemin du fichier `emplacements.json`
  /// réécrit après chaque changement réussi ([ecrireEmplacements] ;
  /// `cheminParDefautFichierEmplacements` sinon, remplacé dans les tests).
  ServiceDossierChapitres({
    required ServiceTelechargement serviceTelechargement,
    required DepotParametres depotParametres,
    Future<String> Function()? cheminDossierParDefaut,
    Future<String?> Function()? cheminFichierEmplacements,
  }) : _service = serviceTelechargement,
       _depot = depotParametres,
       _cheminDossierParDefaut =
           cheminDossierParDefaut ?? cheminParDefautDossierTelechargements,
       _cheminFichierEmplacements =
           cheminFichierEmplacements ?? cheminParDefautFichierEmplacements;

  final ServiceTelechargement _service;
  final DepotParametres _depot;
  final Future<String> Function() _cheminDossierParDefaut;
  final Future<String?> Function() _cheminFichierEmplacements;

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
  ///
  /// Le dossier obtenu est aussi écrit dans `emplacements.json`
  /// ([ecrireEmplacements], sans jamais lever) pour le désinstalleur
  /// Windows. [cheminFichierEmplacements] : chemin de ce fichier
  /// (`cheminParDefautFichierEmplacements` sinon, remplacé dans les tests).
  static Future<StockageTelechargements> creerStockage(
    DepotParametres depot, {
    Future<String?> Function()? cheminFichierEmplacements,
  }) async {
    final stockage = await StockageTelechargements.depuisReglage(
      await depot.chargerTexte(ServiceParametres.cleDossierChapitres),
    );
    // Réécrit à chaque démarrage, pas seulement au changement : le fichier
    // reste juste même s'il a été effacé, ou si le réglage a changé par un
    // autre chemin (dossier de l'installateur appliqué juste avant, base
    // restaurée, version antérieure à ce fichier).
    await ecrireEmplacements(
      stockage.dossierRacine,
      cheminFichierEmplacements: cheminFichierEmplacements,
    );
    return stockage;
  }

  /// Écrit `emplacements.json` (`ecrireFichierEmplacements`) avec
  /// [dossierChapitres], pour que le désinstalleur Windows sache quel
  /// dossier de chapitres effacer : il ne sait pas lire la base SQLite où le
  /// réglage est enregistré.
  ///
  /// [cheminFichierEmplacements] renvoie le chemin du fichier, ou `null` pour
  /// ne rien écrire (Android) ; `cheminParDefautFichierEmplacements` par
  /// défaut.
  ///
  /// Ne lève jamais : un échec (disque plein, droits, `path_provider`
  /// indisponible) est seulement noté dans le journal. Le fichier ne sert
  /// qu'à la désinstallation, il ne doit jamais empêcher le démarrage ni un
  /// changement de dossier.
  static Future<void> ecrireEmplacements(
    String dossierChapitres, {
    Future<String?> Function()? cheminFichierEmplacements,
  }) async {
    try {
      final chemin =
          await (cheminFichierEmplacements ??
              cheminParDefautFichierEmplacements)();
      if (chemin == null) return;
      await ecrireFichierEmplacements(chemin, dossierChapitres);
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        'Fichier $nomFichierEmplacements non écrit : le désinstalleur ne '
        'saura pas où sont les chapitres téléchargés',
        erreur: erreur,
      );
    }
  }

  /// Clé (table `parametres`) : dossier de la bibliothèque choisi dans
  /// l'installateur Windows et déjà appliqué par
  /// [appliquerDossierInstallation].
  // Repère séparé du réglage : si le client revient ensuite au dossier par
  // défaut (réglage effacé), le même `installation.json` ne doit pas
  // rechoisir le dossier de l'installateur au démarrage suivant.
  static const String cleDossierInstallationApplique =
      'installation.dossier_applique';

  /// Clé (table `parametres`) : dossier choisi dans l'installateur Windows
  /// qui n'a **pas** été appliqué automatiquement, parce que des chapitres
  /// étaient déjà téléchargés dans le dossier actuel. L'interface le propose
  /// au client ([DossierInstallationEnAttente]).
  static const String cleDossierInstallationEnAttente =
      'installation.dossier_en_attente';

  /// Applique au premier démarrage le dossier de la bibliothèque choisi dans
  /// l'installateur Windows ([chemin], lu dans `installation.json`, `null`
  /// s'il est absent ou invalide). À appeler **avant** [creerStockage].
  ///
  /// Le dossier n'est enregistré dans [ServiceParametres.cleDossierChapitres]
  /// que si : aucun dossier n'est déjà réglé, [chemin] diffère du dossier
  /// par défaut (sans tenir compte de la casse ni du séparateur final), il
  /// n'a pas déjà été appliqué ou refusé ([cleDossierInstallationApplique]),
  /// **aucun chapitre n'est marqué téléchargé** ([depotChapitres]) et
  /// `StockageTelechargements.validerDossier` l'accepte. Le repère est alors
  /// posé avec le réglage.
  ///
  /// Chapitres déjà téléchargés (ou [depotChapitres] absent, ce qui empêche
  /// de le vérifier) : rien n'est réglé, le chemin est seulement mémorisé
  /// dans [cleDossierInstallationEnAttente] pour que l'interface propose au
  /// client de déplacer ses chapitres
  /// ([DossierInstallationEnAttente.chargerDossierInstallationEnAttente]).
  ///
  /// Dossier refusé (NAS éteint, accès refusé…) : rien n'est enregistré, pas
  /// même le repère, pour réessayer au prochain démarrage ; l'application
  /// démarre sur le dossier par défaut. Ne lève jamais (un avertissement est
  /// écrit dans le journal).
  ///
  /// [cheminDossierParDefaut] : remplacé dans les tests
  /// (`cheminParDefautDossierTelechargements` sinon).
  static Future<void> appliquerDossierInstallation(
    DepotParametres depot,
    String? chemin, {
    DepotChapitres? depotChapitres,
    Future<String> Function()? cheminDossierParDefaut,
  }) async {
    final demande = chemin?.trim() ?? '';
    if (demande.isEmpty) return;
    try {
      final regle = await depot.chargerTexte(
        ServiceParametres.cleDossierChapitres,
      );
      // Un dossier déjà réglé (par le client ou une installation
      // précédente) l'emporte toujours sur l'installateur. Une proposition
      // restée en attente n'a alors plus de sens.
      if ((regle?.trim() ?? '').isNotEmpty) {
        await _effacerEnAttente(depot);
        return;
      }
      final parDefaut =
          await (cheminDossierParDefaut ??
              cheminParDefautDossierTelechargements)();
      if (_memeCheminInstallation(demande, parDefaut)) return;
      final applique = await depot.chargerTexte(cleDossierInstallationApplique);
      if (applique != null && _memeCheminInstallation(demande, applique)) {
        return;
      }
      // Basculer sur un dossier vide alors que des chapitres sont déjà
      // téléchargés dans le dossier actuel les ferait tous passer pour
      // perdus (remis à « non téléchargé », archives orphelines, chapitres
      // enregistrés depuis le navigateur perdus) : la décision revient au
      // client, qui pourra déplacer ses chapitres. Sans dépôt pour le
      // vérifier, on reste prudent.
      // LIMITE : charge la liste des chapitres téléchargés (aucun dépôt ne
      // les compte) ; ne se produit qu'au démarrage, tant que le dossier de
      // l'installateur n'a été ni appliqué ni refusé.
      final aDesChapitres =
          depotChapitres == null ||
          (await depotChapitres.chargerChapitresTelecharges()).isNotEmpty;
      if (aDesChapitres) {
        await depot.enregistrerTexte(
          cleDossierInstallationEnAttente,
          chemins.normalize(demande),
        );
        Journal.actuel.info(
          CategorieJournal.stockage,
          "Dossier choisi à l'installation « $demande » non appliqué : des "
          'chapitres sont déjà téléchargés, le client choisira',
        );
        return;
      }
      final String valide;
      try {
        valide = await StockageTelechargements.validerDossier(demande);
      } on ErreurStockage catch (erreur) {
        // Repère volontairement non posé : le NAS était peut-être éteint,
        // on réessaiera au prochain démarrage.
        Journal.actuel.avertissement(
          CategorieJournal.stockage,
          "Dossier choisi à l'installation « $demande » refusé : dossier par "
          'défaut gardé, nouvel essai au prochain démarrage',
          erreur: erreur,
        );
        return;
      }
      // LIMITE : réglage et repère sont deux écritures séparées. Si la
      // seconde échoue, le réglage suffit à ne plus rien appliquer aux
      // démarrages suivants (dossier déjà réglé) ; seul le retour au
      // dossier par défaut le réappliquerait une fois.
      await depot.enregistrerTexte(
        ServiceParametres.cleDossierChapitres,
        valide,
      );
      await depot.enregistrerTexte(cleDossierInstallationApplique, valide);
      // Proposition d'un démarrage précédent devenue inutile (les chapitres
      // téléchargés ont été supprimés depuis).
      await _effacerEnAttente(depot);
      Journal.actuel.info(
        CategorieJournal.stockage,
        "Dossier des chapitres choisi à l'installation appliqué : $valide",
      );
    } catch (erreur) {
      // Base illisible ou autre imprévu : on démarre sur le réglage actuel
      // plutôt que d'empêcher le démarrage.
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        "Dossier choisi à l'installation non appliqué",
        erreur: erreur,
      );
    }
  }

  /// Efface la proposition en attente, si elle existe (lecture d'abord pour
  /// ne rien écrire au démarrage dans le cas courant).
  static Future<void> _effacerEnAttente(DepotParametres depot) async {
    if (await depot.chargerTexte(cleDossierInstallationEnAttente) != null) {
      await depot.supprimer(cleDossierInstallationEnAttente);
    }
  }

  /// Clôt la proposition du dossier de l'installateur : repère posé avec son
  /// chemin (plus jamais reproposé ni appliqué), puis proposition effacée.
  /// Sans effet s'il n'y a rien en attente.
  // Repère d'abord : si l'effacement échoue ensuite, le repère suffit à ne
  // plus rien proposer (voir `chargerDossierInstallationEnAttente`).
  static Future<void> _clorePropositionInstallation(
    DepotParametres depot,
  ) async {
    final enAttente = await depot.chargerTexte(cleDossierInstallationEnAttente);
    if (enAttente == null) return;
    await depot.enregistrerTexte(cleDossierInstallationApplique, enAttente);
    await depot.supprimer(cleDossierInstallationEnAttente);
  }

  /// Comparaison des chemins de l'installateur : normalisés, sans séparateur
  /// final et sans tenir compte de la casse (chemins Windows).
  static bool _memeCheminInstallation(String a, String b) {
    String propre(String chemin) {
      var texte = chemins.normalize(chemin.trim()).toLowerCase();
      while (texte.length > 1 &&
          (texte.endsWith('/') || texte.endsWith(r'\')) &&
          !texte.endsWith(r':\') &&
          !texte.endsWith(':/')) {
        texte = texte.substring(0, texte.length - 1);
      }
      return texte;
    }

    return propre(a) == propre(b);
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
  /// restée dans l'autre dossier seront retéléchargés selon les règles. La
  /// file, arrêtée pendant le déplacement inachevé, est relancée.
  Future<void> abandonnerDeplacementInacheve() async {
    await _depot.supprimer(ServiceParametres.cleDeplacementDossierEnCours);
    Journal.actuel.info(
      CategorieJournal.stockage,
      'Déplacement inachevé des chapitres abandonné',
    );
    _service._signaler();
    unawaited(_service.lancerTraitement());
  }

  /// Texte de `avertissementAvantChangement` pour le dossier [inacheve].
  static String _avertissementAbandon(String inacheve) =>
      'Un déplacement des chapitres vers « $inacheve » est resté inachevé : '
      'les chapitres déjà copiés dans ce dossier ne seront pas utilisés '
      '(vous pourrez les y effacer) et seront retéléchargés dans le nouveau '
      'dossier selon vos règles.';

  /// Lève la pause posée par un changement de dossier refusé (chapitre en
  /// cours de téléchargement) quand le client y renonce, et relance la
  /// file. Sans effet après un changement réussi : la file reste en pause
  /// jusqu'au redémarrage.
  void reprendreFile() {
    if (_service._dossierChange || !_service._enPause) return;
    _service._enPause = false;
    Journal.actuel.info(
      CategorieJournal.telechargement,
      'File de téléchargement reprise (demande du client)',
    );
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
  /// - chapitre en cours d'enregistrement depuis le navigateur intégré
  ///   (`ServiceLectureWeb.enregistrerImagesChapitre`) : même règle, pause
  ///   gardée ;
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
    // Aucune suppression d'archive pendant le changement (règles échues,
    // bouton « Supprimer ») : un fichier en cours de copie serait effacé de
    // l'ancien dossier en laissant sa copie dans le nouveau.
    _service._changementDossierEnCours = true;
    final demande = nouveauDossier?.trim() ?? '';
    Journal.actuel.info(
      CategorieJournal.stockage,
      'Changement du dossier des chapitres demandé vers '
      '« ${demande.isEmpty ? 'dossier par défaut' : demande} » '
      '(${deplacerArchives ? 'avec' : 'sans'} déplacement)',
    );
    try {
      final resultat = await changement;
      final bilan = resultat.bilan;
      final detail = bilan == null
          ? 'archives non déplacées'
          : '${bilan.nombreFichiers} fichier(s), ${bilan.nombreCopies} '
                'copié(s), ${bilan.nombreDejaPresents} déjà présent(s), '
                '${bilan.cheminsEnConflit.length} conflit(s)';
      Journal.actuel.info(
        CategorieJournal.stockage,
        'Dossier des chapitres changé : ${resultat.cheminDossier} ($detail), '
        'effectif au prochain démarrage',
      );
      return resultat;
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        'Changement du dossier des chapitres refusé ou interrompu',
        erreur: erreur,
      );
      rethrow;
    } finally {
      _changement = null;
      _service._changementDossierEnCours = false;
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
    final inacheve = await chargerDeplacementInacheve();
    String? avertissement;
    if (inacheve != null && !_memeChemin(inacheve, cible)) {
      if (deplacerArchives) {
        throw ErreurService(
          'Un déplacement des chapitres vers « $inacheve » est resté '
          'inachevé : reprenez-le (même dossier) ou abandonnez-le avant '
          "d'en choisir un autre.",
        );
      }
      // Sans déplacement, le déplacement inachevé est abandonné : le client
      // l'a lu avant de confirmer ([avertissementAvantChangement]), le
      // résultat le redit.
      avertissement = _avertissementAbandon(inacheve);
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
    if (!etaitEnPause) {
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'File de téléchargement en pause (changement du dossier)',
      );
    }
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
        // Même règle pour un chapitre enregistré depuis le navigateur : son
        // archive s'écrit dans l'ancien dossier et ne serait pas déplacée.
        // Les nouveaux enregistrements sont déjà refusés (changement en
        // cours, puis pause gardée) : réessayer un instant plus tard aboutit.
        if (service._enregistrementsWebEnCours > 0) {
          garderPause = true;
          throw const ErreurService(
            "Un chapitre est en cours d'enregistrement depuis le navigateur : "
            'réessayez dans un instant.',
          );
        }
        bilan = await _deplacer(valide, surProgression);
        // Conflits (décision de l'orchestrateur, 2026-11-17) : le lecteur ne
        // doit jamais ouvrir le fichier différent resté sous ce nom dans le
        // nouveau dossier. Ces chapitres sont remis à « non téléchargé » et
        // seront retéléchargés sous un nom libre. Fait **avant** le réglage :
        // si cette écriture échoue, le dossier ne change pas (l'inverse
        // laisserait des chapitres pointer vers le fichier étranger).
        // Le repère de déplacement reste posé en cas d'échec : relancer la
        // même demande retrouve les mêmes conflits et refait cette étape.
        try {
          await service._oublierArchivesEnConflit(bilan.cheminsEnConflit);
        } catch (erreur) {
          throw ErreurService(
            "Les chapitres en conflit n'ont pas pu être notés à retélécharger "
            ': relancez le changement vers le même dossier pour terminer.',
            cause: erreur,
          );
        }
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
      // Le désinstalleur doit effacer le dossier où les chapitres iront
      // désormais, même avant le redémarrage qui l'applique. Ne lève jamais.
      // LIMITE : sans déplacement des archives, les chapitres restés dans
      // l'ancien dossier n'y figurent plus (le fichier ne porte qu'un
      // dossier) : le désinstalleur les laissera.
      await ecrireEmplacements(
        valide,
        cheminFichierEmplacements: _cheminFichierEmplacements,
      );
      // Dossier de l'installateur en attente : le client a maintenant choisi
      // (en l'acceptant, ou en préférant un autre dossier), on ne le lui
      // repropose plus. Le changement est déjà fait : un échec ici est
      // seulement noté (au pire, la proposition reviendra une fois).
      try {
        await _clorePropositionInstallation(_depot);
      } catch (erreur) {
        Journal.actuel.avertissement(
          CategorieJournal.stockage,
          "Proposition du dossier de l'installateur non close",
          erreur: erreur,
        );
      }
      return ResultatChangementDossier(
        dossierChoisi: versDefaut ? null : valide,
        cheminDossier: valide,
        bilan: bilan,
        avertissement: avertissement,
      );
    } finally {
      if (!reussi && !garderPause) {
        // Échec : la file reprend comme avant, toujours sur l'ancien dossier
        // (le réglage n'a pas changé).
        service._enPause = etaitEnPause;
        if (!etaitEnPause) {
          Journal.actuel.info(
            CategorieJournal.telechargement,
            'File de téléchargement reprise (changement du dossier annulé)',
          );
          unawaited(service.lancerTraitement());
        }
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
            Journal.actuel.avertissement(
              CategorieJournal.stockage,
              'Verrou non renouvelé pendant le déplacement',
              erreur: erreur,
            );
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
          Journal.actuel.avertissement(
            CategorieJournal.stockage,
            'Repère de déplacement non effacé',
            erreur: erreurRepere,
          );
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

/// Avertissement avant un changement du dossier des chapitres.
///
/// Extension plutôt que méthode de [ServiceDossierChapitres] : elle n'utilise
/// que des méthodes publiques, et les faux services des tests de
/// l'interface (`implements ServiceDossierChapitres`) restent valables sans
/// changement.
extension AvertissementDossierChapitres on ServiceDossierChapitres {
  /// Avertissement à montrer au client **avant** de confirmer un changement
  /// de dossier, ou `null` s'il n'y a rien de particulier à signaler.
  ///
  /// Cas prévu : un déplacement est resté inachevé
  /// ([ServiceDossierChapitres.chargerDeplacementInacheve]) et le client
  /// choisit un autre dossier sans déplacer les archives ([deplacerArchives]
  /// à `false`). Les archives déjà copiées dans le dossier du déplacement
  /// inachevé ne seront alors plus utilisées, et ces chapitres seront
  /// retéléchargés. Le même texte est repris dans
  /// [ResultatChangementDossier.avertissement]. Ne modifie rien ; peut lever
  /// l'erreur de lecture de la base.
  Future<String?> avertissementAvantChangement(
    String? nouveauDossier, {
    required bool deplacerArchives,
  }) async {
    if (deplacerArchives) return null;
    final inacheve = await chargerDeplacementInacheve();
    if (inacheve == null) return null;
    final demande = nouveauDossier?.trim() ?? '';
    final cible = demande.isEmpty
        ? await chargerCheminDossierParDefaut()
        : demande;
    // Vers le dossier du déplacement inachevé lui-même : les archives déjà
    // copiées y sont, elles serviront au prochain démarrage.
    if (ServiceDossierChapitres._memeChemin(inacheve, cible)) return null;
    return ServiceDossierChapitres._avertissementAbandon(inacheve);
  }
}

/// Dossier choisi dans l'installateur Windows mais non appliqué au
/// démarrage, parce que des chapitres étaient déjà téléchargés
/// ([ServiceDossierChapitres.appliquerDossierInstallation]).
///
/// L'interface le propose au client : s'il accepte, elle appelle
/// [ServiceDossierChapitres.changerDossierChapitres] avec ce chemin (et
/// `deplacerArchives: true`), qui clôt la proposition à la réussite ; s'il
/// refuse, [ignorerDossierInstallationEnAttente].
///
/// Extension (comme [AvertissementDossierChapitres]) pour que les faux
/// services des tests de l'interface (`implements ServiceDossierChapitres`)
/// restent valables. LIMITE : elle lit la base par le dépôt privé du vrai
/// service ; appelée sur un faux service, elle lève `NoSuchMethodError`
/// (les tests de l'interface utilisent alors un vrai service sur une base
/// en mémoire).
extension DossierInstallationEnAttente on ServiceDossierChapitres {
  /// Chemin du dossier de l'installateur à proposer au client, ou `null`
  /// s'il n'y a rien à proposer (déjà appliqué, refusé ou choisi). Peut
  /// lever l'erreur de lecture de la base.
  Future<String?> chargerDossierInstallationEnAttente() async {
    final texte = await _depot.chargerTexte(
      ServiceDossierChapitres.cleDossierInstallationEnAttente,
    );
    final propre = texte?.trim() ?? '';
    if (propre.isEmpty) return null;
    // Repère déjà posé pour ce chemin (effacement interrompu) : la
    // proposition a déjà reçu sa réponse.
    final applique = await _depot.chargerTexte(
      ServiceDossierChapitres.cleDossierInstallationApplique,
    );
    if (applique != null &&
        ServiceDossierChapitres._memeCheminInstallation(propre, applique)) {
      return null;
    }
    return propre;
  }

  /// Le client refuse le dossier de l'installateur : il garde son dossier
  /// actuel et ce dossier ne lui sera plus proposé (ni appliqué aux
  /// démarrages suivants). Sans effet s'il n'y a rien en attente. Peut
  /// lever l'erreur d'écriture de la base.
  Future<void> ignorerDossierInstallationEnAttente() async {
    await ServiceDossierChapitres._clorePropositionInstallation(_depot);
    Journal.actuel.info(
      CategorieJournal.stockage,
      "Dossier choisi à l'installation refusé par le client",
    );
  }
}
