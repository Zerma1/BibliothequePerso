/// Réglages du client (écran Paramètres) : noms des clés et valeurs par
/// défaut. Le stockage est assuré par `DepotParametres`.
library;

import '../donnees/depot_parametres.dart';
import '../modeles/constantes.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'planification_mises_a_jour.dart';
import 'politique_telechargement.dart';
import 'verrou_telechargement.dart';

/// Lecture et écriture des réglages, avec leurs valeurs par défaut.
class ServiceParametres {
  /// Crée le service.
  const ServiceParametres(this._depot);

  final DepotParametres _depot;

  /// Clé : chapitres lus gardés pour un favori.
  static const String cleFavorisLusConserves =
      'telechargement.favoris.lus_conserves';

  /// Clé : chapitres téléchargés au départ pour un titre suivi.
  static const String cleSuivisInitial = 'telechargement.suivis.initial';

  /// Clé : chapitres gardés jusqu'au dernier lu pour un titre suivi.
  static const String cleSuivisAvant = 'telechargement.suivis.avant';

  /// Clé : chapitres téléchargés après le dernier lu pour un titre suivi.
  static const String cleSuivisApres = 'telechargement.suivis.apres';

  /// Clé : nombre de recherches de mises à jour par jour (1 à 24).
  static const String cleVerificationsParJour = 'mises_a_jour.par_jour';

  /// Clé : date (UTC, ISO 8601) de la dernière recherche de mises à jour.
  static const String cleDerniereVerification = 'mises_a_jour.derniere';

  /// Clé : langues de lecture du client (« fr,en »).
  static const String cleLangues = 'langues.preferees';

  /// Langues de lecture tant que le client n'a rien choisi.
  static const List<String> languesParDefaut = languesParDefautClient;

  /// Nombre maximal de langues retenues (borne raisonnable : au-delà, le
  /// filtre de MangaDex n'a plus d'intérêt).
  static const int nombreMaximalLangues = 10;

  /// Clé : verrou de la file de téléchargement (propriétaire et expiration),
  /// partagé entre l'application et la tâche de fond Android. Ce n'est pas un
  /// réglage du client mais la table `parametres` est le seul stockage commun
  /// aux deux isolats.
  static const String cleVerrouTelechargement = 'telechargement.verrou';

  /// Valeur maximale acceptée pour une limite, pour éviter qu'une faute de
  /// frappe (1000 au lieu de 10) ne lance des centaines de téléchargements.
  static const int limiteMaximale = 500;

  /// Réglages de téléchargement (valeurs par défaut si rien n'est enregistré
  /// ou si une valeur est illisible).
  Future<ReglagesTelechargement> chargerReglagesTelechargement() async {
    const defaut = ReglagesTelechargement();
    Future<int> lire(String cle, int valeurParDefaut, {int minimum = 0}) async {
      final valeur = await _depot.chargerEntier(cle);
      if (valeur == null || valeur < minimum || valeur > limiteMaximale) {
        return valeurParDefaut;
      }
      return valeur;
    }

    return ReglagesTelechargement(
      favorisLusConserves: await lire(
        cleFavorisLusConserves,
        defaut.favorisLusConserves,
      ),
      suivisInitial: await lire(cleSuivisInitial, defaut.suivisInitial),
      suivisAvant: await lire(
        cleSuivisAvant,
        defaut.suivisAvant,
        minimum: minimumSuivisAvantApres,
      ),
      suivisApres: await lire(
        cleSuivisApres,
        defaut.suivisApres,
        minimum: minimumSuivisAvantApres,
      ),
    );
  }

  /// Enregistre les réglages de téléchargement. Les valeurs sont ramenées
  /// entre 0 et [limiteMaximale] ; « avant » et « après » des suivis valent
  /// au moins [minimumSuivisAvantApres].
  Future<void> enregistrerReglagesTelechargement(
    ReglagesTelechargement reglages,
  ) async {
    int borner(int valeur) => valeur.clamp(0, limiteMaximale);
    int bornerAvantApres(int valeur) =>
        valeur.clamp(minimumSuivisAvantApres, limiteMaximale);
    await _depot.enregistrerEntier(
      cleFavorisLusConserves,
      borner(reglages.favorisLusConserves),
    );
    await _depot.enregistrerEntier(
      cleSuivisInitial,
      borner(reglages.suivisInitial),
    );
    await _depot.enregistrerEntier(
      cleSuivisAvant,
      bornerAvantApres(reglages.suivisAvant),
    );
    await _depot.enregistrerEntier(
      cleSuivisApres,
      bornerAvantApres(reglages.suivisApres),
    );
  }

  /// Remet les réglages de téléchargement à leurs valeurs par défaut.
  Future<void> reinitialiserReglagesTelechargement() async {
    for (final cle in <String>[
      cleFavorisLusConserves,
      cleSuivisInitial,
      cleSuivisAvant,
      cleSuivisApres,
    ]) {
      await _depot.supprimer(cle);
    }
  }

  /// Nombre de recherches de mises à jour par jour (2 par défaut : 00:00 et
  /// 12:00 UTC).
  Future<int> chargerVerificationsParJour() async {
    final valeur = await _depot.chargerEntier(cleVerificationsParJour);
    if (valeur == null ||
        valeur < PlanificationMisesAJour.minimumParJour ||
        valeur > PlanificationMisesAJour.maximumParJour) {
      return PlanificationMisesAJour.parDefautParJour;
    }
    return valeur;
  }

  /// Enregistre le nombre de recherches par jour (ramené entre 1 et 24).
  Future<void> enregistrerVerificationsParJour(int nombre) =>
      _depot.enregistrerEntier(
        cleVerificationsParJour,
        nombre.clamp(
          PlanificationMisesAJour.minimumParJour,
          PlanificationMisesAJour.maximumParJour,
        ),
      );

  /// Planification correspondant au réglage enregistré.
  Future<PlanificationMisesAJour> chargerPlanification() async =>
      PlanificationMisesAJour(await chargerVerificationsParJour());

  /// Clé : écart en heures entre deux vérifications des titres « En
  /// attente ».
  static const String cleHeuresEnAttente = 'mises_a_jour.en_attente.heures';

  /// Clé : date (UTC, ISO 8601) de la dernière vérification des titres « En
  /// attente ».
  static const String cleDerniereVerificationEnAttente =
      'mises_a_jour.en_attente.derniere';

  /// Écart maximal (en heures) accepté pour les titres « En attente » avec
  /// [verificationsParJour] vérifications normales par jour : l'intervalle
  /// normal, au moins 1 h (décision de l'étape 6 : la surveillance accrue
  /// n'est jamais plus lente que la normale).
  static int maximumHeuresEnAttente(int verificationsParJour) {
    final parJour = verificationsParJour.clamp(
      PlanificationMisesAJour.minimumParJour,
      PlanificationMisesAJour.maximumParJour,
    );
    final heures = Duration.hoursPerDay ~/ parJour;
    return heures < 1 ? 1 : heures;
  }

  /// Écart en heures entre deux vérifications des titres « En attente » (1
  /// par défaut : à chaque heure pleine), ramené entre 1 et l'intervalle
  /// normal ([maximumHeuresEnAttente]) : si le client réduit ensuite
  /// l'intervalle normal, la valeur suit.
  Future<int> chargerHeuresEnAttente() async {
    final maximum = maximumHeuresEnAttente(await chargerVerificationsParJour());
    final valeur = await _depot.chargerEntier(cleHeuresEnAttente);
    if (valeur == null || valeur < 1) {
      return heuresEnAttenteParDefaut.clamp(1, maximum);
    }
    return valeur > maximum ? maximum : valeur;
  }

  /// Enregistre l'écart des vérifications « En attente » (ramené entre 1 et
  /// l'intervalle normal).
  Future<void> enregistrerHeuresEnAttente(int heures) async {
    final maximum = maximumHeuresEnAttente(await chargerVerificationsParJour());
    await _depot.enregistrerEntier(
      cleHeuresEnAttente,
      heures.clamp(1, maximum),
    );
  }

  /// Planification des vérifications des titres « En attente » (toutes les
  /// [chargerHeuresEnAttente] heures pleines).
  Future<PlanificationMisesAJour> chargerPlanificationEnAttente() async =>
      PlanificationMisesAJour.toutesLesHeures(await chargerHeuresEnAttente());

  /// Date de la dernière vérification des titres « En attente », ou `null`.
  Future<DateTime?> chargerDerniereVerificationEnAttente() async {
    final texte = await _depot.chargerTexte(cleDerniereVerificationEnAttente);
    return texte == null ? null : DateTime.tryParse(texte)?.toUtc();
  }

  /// Enregistre la date de la dernière vérification des titres « En
  /// attente ».
  Future<void> enregistrerDerniereVerificationEnAttente(DateTime date) =>
      _depot.enregistrerTexte(
        cleDerniereVerificationEnAttente,
        date.toUtc().toIso8601String(),
      );

  /// Clé : niveaux de contenu affichés dans la bibliothèque et demandés à la
  /// recherche (« safe,suggestive,erotica »).
  static const String cleNiveauxContenu = 'bibliotheque.niveaux_contenu';

  /// Niveaux de contenu choisis par le client, dans l'ordre de
  /// `niveauxContenu` (du plus sage au plus explicite). Par défaut
  /// `niveauxContenuParDefaut` (tout sauf `pornographic`). Les valeurs
  /// inconnues sont ignorées ; une liste vide enregistrée reste vide (le
  /// client n'affiche alors que les titres sans niveau connu).
  Future<List<String>> chargerNiveauxContenu() async {
    final texte = await _depot.chargerTexte(cleNiveauxContenu);
    if (texte == null) return List<String>.of(niveauxContenuParDefaut);
    return nettoyerNiveauxContenu(texte.split(','));
  }

  /// Enregistre les niveaux de contenu choisis (valeurs inconnues ignorées).
  Future<void> enregistrerNiveauxContenu(Iterable<String> niveaux) =>
      _depot.enregistrerTexte(
        cleNiveauxContenu,
        nettoyerNiveauxContenu(niveaux).join(','),
      );

  /// Remet le filtre de niveau de contenu à sa valeur par défaut.
  Future<void> reinitialiserNiveauxContenu() =>
      _depot.supprimer(cleNiveauxContenu);

  /// Garde les niveaux connus (`niveauxContenu`), sans doublon, dans l'ordre
  /// du plus sage au plus explicite.
  static List<String> nettoyerNiveauxContenu(Iterable<String> niveaux) {
    final choisis = niveaux.map((n) => n.trim().toLowerCase()).toSet();
    return <String>[
      for (final niveau in niveauxContenu)
        if (choisis.contains(niveau)) niveau,
    ];
  }

  /// Langues de lecture du client (codes ISO 639-1 par ordre de préférence,
  /// la première étant la langue favorite). Jamais vide : [languesParDefaut]
  /// si rien n'est enregistré ou si la valeur est illisible.
  Future<List<String>> chargerLangues() async {
    final langues = nettoyerLangues(
      (await _depot.chargerTexte(cleLangues) ?? '').split(','),
    );
    return langues.isEmpty ? List<String>.of(languesParDefaut) : langues;
  }

  /// Enregistre les langues de lecture du client (nettoyées, sans doublon,
  /// au plus [nombreMaximalLangues]).
  ///
  /// Lève une [ErreurService] si aucune langue valable ne reste : le client
  /// doit toujours lire dans au moins une langue.
  Future<void> enregistrerLangues(List<String> langues) async {
    final propres = nettoyerLangues(langues);
    if (propres.isEmpty) {
      throw const ErreurService('Choisissez au moins une langue de lecture.');
    }
    await _depot.enregistrerTexte(cleLangues, propres.join(','));
  }

  /// Nettoie une liste de codes de langue : minuscules, sans espaces, codes
  /// invalides et doublons retirés (le premier garde sa place), au plus
  /// [nombreMaximalLangues].
  ///
  /// Variantes régionales (tâche P3) : un code `xx-yy` est accepté tel quel
  /// (`pt-br`, `es-la`, `zh-hk`), distinct de sa langue de base `xx` ; la
  /// forme `pt_BR` (souvent vue dans les réglages système) devient `pt-br`.
  /// La correspondance avec les chapitres (exacte d'abord, langue de base
  /// en repli) est décrite par `PolitiqueTelechargement.rangLangue`.
  static List<String> nettoyerLangues(Iterable<String> langues) {
    final propres = <String>[];
    for (final langue in langues) {
      final code = langue.trim().toLowerCase().replaceAll('_', '-');
      if (!_motifLangue.hasMatch(code) || propres.contains(code)) continue;
      propres.add(code);
      if (propres.length >= nombreMaximalLangues) break;
    }
    return propres;
  }

  static final RegExp _motifLangue = RegExp(r'^[a-z]{2,3}(-[a-z0-9]{2,4})?$');

  /// Clé : chapitres que le client a choisi de garder (« Garder » sur une
  /// suppression prévue), identifiants séparés par des virgules.
  ///
  /// Ancien stockage (avant la migration 5) : le choix est désormais la
  /// colonne `chapitres.est_garde`. `ServiceTelechargement` reprend ces
  /// identifiants une fois puis supprime la clé ; rien n'y est plus écrit.
  static const String cleChapitresGardes = 'telechargement.gardes';

  /// Nombre maximal de chapitres gardés mémorisés : borne la taille du texte
  /// enregistré (les plus anciens sont oubliés au-delà).
  static const int nombreMaximalChapitresGardes = 5000;

  /// Chapitres gardés mémorisés par l'ancien stockage ([cleChapitresGardes]),
  /// à reprendre dans `chapitres.est_garde`. Valeurs illisibles ignorées.
  Future<Set<int>> chargerChapitresGardes() async {
    final texte = await _depot.chargerTexte(cleChapitresGardes) ?? '';
    return <int>{
      for (final morceau in texte.split(',')) ?int.tryParse(morceau.trim()),
    };
  }

  /// Supprime l'ancien stockage des chapitres gardés, une fois repris en
  /// base.
  Future<void> supprimerChapitresGardes() =>
      _depot.supprimer(cleChapitresGardes);

  /// Enregistre les chapitres gardés dans l'ancien stockage (au plus
  /// [nombreMaximalChapitresGardes], les derniers ajoutés étant conservés).
  ///
  /// Gardé pour les tests de la reprise : le service n'y écrit plus.
  Future<void> enregistrerChapitresGardes(Iterable<int> ids) async {
    final liste = ids.toSet().toList();
    final bornee = liste.length > nombreMaximalChapitresGardes
        ? liste.sublist(liste.length - nombreMaximalChapitresGardes)
        : liste;
    if (bornee.isEmpty) {
      await _depot.supprimer(cleChapitresGardes);
    } else {
      await _depot.enregistrerTexte(cleChapitresGardes, bornee.join(','));
    }
  }

  /// Verrou de la file de téléchargement, ou `null` s'il est libre (ou
  /// illisible).
  Future<VerrouTelechargement?> chargerVerrouTelechargement() async =>
      VerrouTelechargement.depuisTexte(
        await _depot.chargerTexte(cleVerrouTelechargement),
      );

  /// Enregistre (prend ou renouvelle) le verrou de la file.
  Future<void> enregistrerVerrouTelechargement(VerrouTelechargement verrou) =>
      _depot.enregistrerTexte(cleVerrouTelechargement, verrou.versTexte());

  /// Libère le verrou de la file.
  Future<void> supprimerVerrouTelechargement() =>
      _depot.supprimer(cleVerrouTelechargement);

  /// Clé : identifiants des sources par défaut déjà proposées au client
  /// (« mangadex,scan-manga »). Une source proposée puis supprimée par le
  /// client n'est jamais recréée (tâche R9).
  static const String cleSourcesParDefautProposees =
      'sources.par_defaut.proposees';

  /// Identifiants des sources par défaut déjà proposées (vide si aucune).
  Future<Set<String>> chargerSourcesParDefautProposees() async {
    final texte = await _depot.chargerTexte(cleSourcesParDefautProposees) ?? '';
    return <String>{
      for (final morceau in texte.split(','))
        if (morceau.trim().isNotEmpty) morceau.trim(),
    };
  }

  /// Enregistre les identifiants des sources par défaut déjà proposées
  /// (vides et identifiants contenant une virgule ignorés).
  Future<void> enregistrerSourcesParDefautProposees(
    Iterable<String> identifiants,
  ) {
    final propres = <String>{
      for (final identifiant in identifiants)
        if (identifiant.trim().isNotEmpty && !identifiant.contains(','))
          identifiant.trim(),
    };
    return _depot.enregistrerTexte(
      cleSourcesParDefautProposees,
      propres.join(','),
    );
  }

  /// Date de la dernière recherche de mises à jour, ou `null`.
  Future<DateTime?> chargerDerniereVerification() async {
    final texte = await _depot.chargerTexte(cleDerniereVerification);
    return texte == null ? null : DateTime.tryParse(texte)?.toUtc();
  }

  /// Enregistre la date de la dernière recherche de mises à jour.
  Future<void> enregistrerDerniereVerification(DateTime date) =>
      _depot.enregistrerTexte(
        cleDerniereVerification,
        date.toUtc().toIso8601String(),
      );
}
