/// Téléchargement des chapitres pour la lecture hors-ligne (PLAYBOOK.md
/// sections 5 et 7) et application des règles de conservation du client.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io' show Directory;
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../donnees/depot_chapitres.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_telechargements.dart';
import '../donnees/depot_titres.dart';
import '../donnees/erreur_stockage.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/source.dart';
import '../modeles/telechargement.dart';
import '../modeles/titre.dart';
import '../sources/client_http_poli.dart';
import '../sources/constantes_sources.dart';
import '../sources/erreur_source.dart';
import '../sources/fabrique_sources.dart';
import '../sources/signalement_mangadex.dart';
import '../sources/source_mangadex.dart';
import '../sources/source_site.dart';
import 'erreur_service.dart';
import 'politique_telechargement.dart';
import 'constantes_services.dart';
import 'service_bibliotheque.dart';
import 'service_parametres.dart';
import 'verrou_telechargement.dart';

/// Chapitre avec son titre et sa source, tels qu'il faut les passer au
/// stockage (la langue vide est remplacée par la langue de la source pour que
/// le nom de l'archive soit toujours le même).
class _ContexteChapitre {
  const _ContexteChapitre(this.chapitre, this.titre, this.source);

  final Chapitre chapitre;
  final Titre titre;
  final Source source;
}

/// Signal interne : le téléchargement a été annulé (ligne de file
/// supprimée) pendant son exécution.
class _Annulation implements Exception {
  const _Annulation();
}

/// Signal interne : le verrou de la file a été repris par un autre isolat
/// pendant le téléchargement d'un chapitre.
class _VerrouPerdu implements Exception {
  const _VerrouPerdu();
}

/// File de téléchargement persistante, lecture des archives et règles de
/// conservation (favoris / suivis).
///
/// Un seul chapitre est téléchargé à la fois : les images d'un chapitre
/// viennent du même serveur, et le délai par domaine de `ClientHttpPoli`
/// rendrait de toute façon le parallélisme inutile.
class ServiceTelechargement {
  /// Crée le service.
  ServiceTelechargement({
    required DepotTelechargements depotTelechargements,
    required DepotChapitres depotChapitres,
    required DepotTitres depotTitres,
    required DepotListes depotListes,
    required DepotSources depotSources,
    required StockageTelechargements stockage,
    required FabriqueSources fabriqueSources,
    required ClientHttpPoli client,
    required ServiceParametres serviceParametres,
    SignalementMangaDex? signalement,
    String? identifiantVerrou,
    Duration dureeVerrou = dureeVerrouParDefaut,
    DateTime Function()? horloge,
  }) : _identifiantVerrou = identifiantVerrou ?? _genererIdentifiant(),
       _dureeVerrou = dureeVerrou,
       _horloge = horloge ?? DateTime.now,
       _depotTelechargements = depotTelechargements,
       _depotChapitres = depotChapitres,
       _depotTitres = depotTitres,
       _depotListes = depotListes,
       _depotSources = depotSources,
       _stockage = stockage,
       _fabriqueSources = fabriqueSources,
       _client = client,
       _serviceParametres = serviceParametres,
       _signalement = signalement ?? SignalementMangaDex(client);

  final DepotTelechargements _depotTelechargements;
  final DepotChapitres _depotChapitres;
  final DepotTitres _depotTitres;
  final DepotListes _depotListes;
  final DepotSources _depotSources;
  final StockageTelechargements _stockage;
  final FabriqueSources _fabriqueSources;
  final ClientHttpPoli _client;
  final ServiceParametres _serviceParametres;
  final SignalementMangaDex _signalement;

  final String _identifiantVerrou;
  final Duration _dureeVerrou;
  final DateTime Function() _horloge;

  final StreamController<void> _changements =
      StreamController<void>.broadcast();

  /// Traitement de la file en cours, partagé si on le redemande.
  Future<void>? _traitement;

  /// Nouvel essai prévu quand le verrou était tenu par un autre isolat.
  Timer? _relance;

  /// Date du dernier renouvellement du verrou par ce service.
  DateTime? _dernierRenouvellement;

  /// Chapitres ouverts dans le lecteur, avec le nombre d'ouvertures (deux
  /// écrans peuvent ouvrir le même chapitre).
  final Map<int, int> _chapitresProteges = <int, int>{};

  /// Chapitres demandés à la main pendant cette session : les règles ne les
  /// retirent pas de la file.
  // LIMITE : en mémoire seulement (le modèle Telechargement ne distingue pas
  // une demande manuelle) ; après un redémarrage, une demande manuelle en
  // attente sur un chapitre que les règles ne veulent pas peut être retirée
  // de la file à la prochaine application des règles de ce titre.
  final Set<int> _demandesManuelles = <int>{};

  /// Nombre d'échecs par chapitre pendant cette session.
  // LIMITE : en mémoire ; sur Android, chaque passage de la tâche de fond
  // repart de zéro, soit au plus une relance par passage (quelques par jour).
  final Map<int, int> _echecs = <int, int>{};

  /// Durée de validité du verrou de la file s'il n'est pas renouvelé.
  ///
  /// Bien plus longue qu'une page (20 s d'attente maximale par requête dans
  /// `ClientHttpPoli`, le verrou est renouvelé entre les pages), mais assez
  /// courte pour qu'une application tuée ne bloque pas la file longtemps.
  static const Duration dureeVerrouParDefaut = Duration(minutes: 3);

  /// Prévient l'interface à chaque changement de la file (ajout,
  /// progression, fin, suppression).
  Stream<void> get changements => _changements.stream;

  /// `true` pendant que la file est traitée.
  bool get estEnCours => _traitement != null;

  /// Identifiant de ce service dans le verrou partagé de la file.
  String get identifiantVerrou => _identifiantVerrou;

  void _signaler() {
    if (!_changements.isClosed) {
      _changements.add(null);
    }
  }

  static String _genererIdentifiant() {
    Random generateur;
    try {
      generateur = Random.secure();
    } on UnsupportedError {
      generateur = Random();
    }
    final aleatoire = List<String>.generate(
      nombreBlocsIdentifiantVerrou,
      (_) => generateur
          .nextInt(borneBlocIdentifiantVerrou)
          .toRadixString(baseBlocIdentifiantVerrou)
          .padLeft(largeurBlocIdentifiantVerrou, '0'),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$aleatoire';
  }

  // ------------------------------------------------------------ Démarrage

  /// À appeler au démarrage : contrôle que chaque chapitre marqué téléchargé
  /// a bien son archive ([reparerArchivesManquantes]), applique les règles
  /// (ce qui reprend aussi les anciens chapitres gardés et supprime les
  /// archives dont la suppression prévue est échue) puis traite la file.
  ///
  /// La reprise des téléchargements interrompus (statut « en cours » remis
  /// en attente, archives partielles effacées) se fait au début de chaque
  /// traitement, une fois le verrou de la file obtenu, et seulement pour les
  /// éléments anciens : la faire ici sans verrou effacerait le `.zip.part`
  /// que la tâche de fond Android est peut-être en train d'écrire.
  Future<void> demarrer() async {
    try {
      await reparerArchivesManquantes();
    } catch (erreur, pile) {
      // Le contrôle sera refait au prochain démarrage ; il ne doit pas
      // empêcher la file de tourner.
      debugPrint('Contrôle des archives impossible : $erreur\n$pile');
    }
    await appliquerReglesATous();
  }

  /// Remet à « non téléchargé » les chapitres marqués téléchargés dont
  /// l'archive n'est plus sur le disque (fichier effacé à la main, chemin
  /// enregistré invalide) et renvoie leur nombre. Si le dossier racine
  /// lui-même est absent (support démonté), rien n'est modifié.
  ///
  /// Sans cela, le lecteur proposerait une lecture hors-ligne impossible et
  /// les règles ne retéléchargeraient jamais ces chapitres. Aucun réseau :
  /// une vérification d'existence de fichier par chapitre.
  Future<int> reparerArchivesManquantes() async {
    // Dossier racine absent : support amovible démonté, carte SD retirée,
    // dossier réglé momentanément inaccessible. Toutes les archives
    // sembleraient perdues alors qu'elles reviendront avec le support : on
    // ne touche à rien (sinon tous les chapitres seraient retéléchargés).
    if (!await Directory(_stockage.dossierRacine).exists()) {
      return 0;
    }
    final telecharges = await _depotChapitres.chargerChapitresTelecharges();
    var nombre = 0;
    for (final chapitre in telecharges) {
      final id = chapitre.id;
      if (id == null) continue;
      try {
        final contexte = await _chargerContexte(id);
        if (contexte == null) continue;
        bool existe;
        try {
          existe = await _stockage.estTelecharge(
            contexte.titre,
            contexte.chapitre,
          );
        } on ErreurStockage {
          // Chemin enregistré invalide : l'archive est introuvable.
          existe = false;
        }
        if (!existe) {
          await _depotChapitres.enregistrerArchive(id, null);
          // Une ligne « terminé » restée dans la file empêcherait les règles
          // de remettre ce chapitre en file (elles ne relancent qu'un
          // échec) : on la retire pour qu'il soit retéléchargé s'il est
          // voulu.
          final ligne = await _depotTelechargements.chargerParChapitre(id);
          if (ligne?.id != null &&
              ligne!.statut == StatutTelechargement.termine) {
            await _depotTelechargements.supprimerTelechargement(ligne.id!);
          }
          nombre++;
        }
      } catch (erreur) {
        // Un chapitre illisible ne doit pas empêcher le contrôle des autres.
        debugPrint('Contrôle de l\'archive du chapitre n°$id : $erreur');
      }
    }
    if (nombre > 0) _signaler();
    return nombre;
  }

  /// Reprise des chapitres gardés mémorisés avant la migration 5 (faite une
  /// fois par service, partagée si on la redemande).
  Future<void>? _repriseGardes;

  /// Reprend dans `chapitres.est_garde` les chapitres gardés que l'ancienne
  /// version mémorisait dans `parametres`, puis supprime cette clé. Ne lève
  /// jamais : en cas d'échec, la clé reste et la reprise sera refaite au
  /// prochain démarrage (elle est idempotente).
  Future<void> _reprendreAnciensGardes() => _repriseGardes ??= () async {
    try {
      final anciens = await _serviceParametres.chargerChapitresGardes();
      if (anciens.isEmpty) return;
      // Base d'abord, clé ensuite : un arrêt entre les deux refait
      // seulement la reprise (sans effet la seconde fois).
      await _depotChapitres.marquerGardes(anciens);
      await _serviceParametres.supprimerChapitresGardes();
    } catch (erreur, pile) {
      debugPrint('Reprise des chapitres gardés impossible : $erreur\n$pile');
      _repriseGardes = null;
    }
  }();

  /// Libère le service (annule le nouvel essai prévu).
  Future<void> fermer() {
    _relance?.cancel();
    _relance = null;
    return _changements.close();
  }

  // ------------------------------------------- Protection pendant la lecture

  /// Protège un chapitre ouvert dans le lecteur : les règles de conservation
  /// ne suppriment pas son archive tant qu'il n'est pas libéré par
  /// [libererChapitre] (appeler autant de fois l'une que l'autre).
  ///
  /// La protection est en mémoire, donc propre à cet isolat : la tâche de
  /// fond Android (autre isolat) ne la voit pas. Pour qu'elle n'efface pas
  /// le chapitre ouvert, une suppression déjà prévue est aussi repoussée en
  /// base à maintenant + [delaiSuppressionDifferee] (en arrière-plan, sans
  /// bloquer l'ouverture du lecteur).
  ///
  /// LIMITE : une lecture qui dure plus de 24 h sans rouvrir le chapitre
  /// reste exposée côté tâche de fond ; et une date posée par les règles
  /// **après** l'ouverture vaut déjà maintenant + 24 h.
  void protegerChapitre(int idChapitre) {
    _chapitresProteges.update(
      idChapitre,
      (nombre) => nombre + 1,
      ifAbsent: () => 1,
    );
    unawaited(_repousserSuppressionPrevue(idChapitre));
  }

  /// Repousse en base la suppression prévue d'un chapitre ouvert (voir
  /// [protegerChapitre]). Ne lève jamais : un échec laisse seulement la
  /// protection en mémoire.
  Future<void> _repousserSuppressionPrevue(int idChapitre) async {
    try {
      // Une seule requête conditionnelle (date existante et plus proche) :
      // pas de course avec « Garder » ni avec l'autre isolat, et une
      // suppression jamais créée pour un chapitre qui n'en avait pas.
      if (await _depotChapitres.repousserSuppressionPrevue(
        idChapitre,
        _maintenant().add(delaiSuppressionDifferee),
      )) {
        _signaler();
      }
    } catch (erreur) {
      debugPrint(
        'Suppression prévue du chapitre n°$idChapitre non repoussée : $erreur',
      );
    }
  }

  /// Retire la protection posée par [protegerChapitre]. Le chapitre sera
  /// supprimé à la prochaine application des règles s'il n'est plus voulu.
  void libererChapitre(int idChapitre) {
    final nombre = _chapitresProteges[idChapitre];
    if (nombre == null) return;
    if (nombre <= 1) {
      _chapitresProteges.remove(idChapitre);
    } else {
      _chapitresProteges[idChapitre] = nombre - 1;
    }
  }

  /// `true` si le chapitre est ouvert dans le lecteur (voir
  /// [protegerChapitre]).
  bool estProtege(int idChapitre) => _chapitresProteges.containsKey(idChapitre);

  // ------------------------------------------------- Règles de conservation

  /// Applique les règles à tous les titres favoris et suivis, puis lance le
  /// traitement de la file (sans l'attendre).
  ///
  /// Un titre en erreur est journalisé et n'empêche pas les autres ; la file
  /// est lancée même si la lecture des listes échoue (l'erreur remonte alors
  /// à l'appelant).
  Future<void> appliquerReglesATous() async {
    // Avant les règles : un chapitre gardé avec l'ancienne version ne doit
    // pas recevoir de suppression prévue.
    await _reprendreAnciensGardes();
    try {
      final ids = <int>{};
      for (final nomListe in <String>[nomListeFavoris, nomListeSuivis]) {
        final liste = await _depotListes.chargerListeParNom(nomListe);
        if (liste?.id == null) continue;
        final titres = await _depotTitres.chargerTitres(idListe: liste!.id);
        ids.addAll(titres.map((titre) => titre.id).whereType<int>());
      }
      for (final idTitre in ids) {
        try {
          await _appliquerRegles(idTitre, supprimerEchues: false);
        } catch (erreur, pile) {
          // Par exemple une écriture refusée pendant que l'autre isolat
          // écrit : ce titre sera repris à la prochaine application.
          debugPrint(
            'Règles du titre n°$idTitre non appliquées : $erreur\n$pile',
          );
        }
      }
    } finally {
      // Une seule passe pour tous les titres (et même si la lecture des
      // listes a échoué) : les échéances concernent aussi des titres sortis
      // de Favoris et Suivis entre-temps.
      await _supprimerArchivesEchuesSansErreur();
      unawaited(lancerTraitement());
    }
  }

  /// Applique les règles à un titre (après une lecture, un changement de
  /// liste ou de réglages), puis lance le traitement de la file.
  ///
  /// Un titre retiré de Favoris et de Suivis perd ses téléchargements en
  /// attente (sauf ceux demandés à la main pendant cette session) ; ses
  /// archives déjà présentes sont gardées (et leurs suppressions prévues
  /// annulées).
  ///
  /// Les archives qui ne sont plus voulues ne sont pas effacées tout de
  /// suite : leur suppression est prévue dans 24 heures
  /// ([delaiSuppressionDifferee], `Chapitre.dateSuppressionPrevue`), et
  /// annulée si le chapitre redevient voulu entre-temps. Les suppressions
  /// échues (de tous les titres) sont faites à la fin.
  Future<PlanTelechargement> appliquerRegles(int idTitre) async {
    try {
      return await _appliquerRegles(idTitre, supprimerEchues: true);
    } finally {
      unawaited(lancerTraitement());
    }
  }

  /// Enregistre les langues propres à un titre ([langues] `null` ou vide :
  /// retour au réglage général) puis applique les règles de ce titre : les
  /// archives dans une langue retirée passent en suppression différée, les
  /// chapitres d'une langue ajoutée sont mis en file.
  ///
  /// Les chapitres d'une langue ajoutée ne sont connus qu'après une
  /// actualisation du titre (`ServiceBibliotheque.actualiserTitre`, qui
  /// demande au site les langues du titre) : l'interface l'appelle ensuite,
  /// puis [appliquerRegles]. Lève une `ErreurService` si le titre n'existe
  /// plus.
  Future<PlanTelechargement> modifierLanguesTitre(
    int idTitre,
    List<String>? langues,
  ) async {
    await ServiceBibliotheque.enregistrerLanguesTitre(
      _depotTitres,
      idTitre,
      langues,
    );
    return appliquerRegles(idTitre);
  }

  /// Calcule le plan d'un titre à partir de l'état actuel de la base (listes,
  /// réglages, langues, chapitres). Renvoie `null` si le titre n'existe plus.
  /// Lecture seule.
  Future<({PlanTelechargement plan, List<Chapitre> chapitres})?> _calculerPlan(
    int idTitre,
  ) async {
    final titre = await _depotTitres.chargerTitre(idTitre);
    final idSource = titre?.idSource;
    if (titre == null || idSource == null) {
      return null;
    }
    final source = await _depotSources.chargerSource(idSource);
    final listes = await _depotListes.chargerListesDuTitre(idTitre);
    final noms = listes.map((liste) => liste.nom).toSet();
    final politique = PolitiqueTelechargement(
      reglages: await _serviceParametres.chargerReglagesTelechargement(),
      // Même résolution que ServiceBibliotheque.languesPourTitre : langues
      // propres au titre, sinon de la source si réglées, sinon réglage
      // général du client.
      languesPreferees: ServiceBibliotheque.languesPreferees(
        source,
        general: await _serviceParametres.chargerLangues(),
        titre: titre,
      ),
    );
    final chapitres = await _depotChapitres.chargerChapitres(idTitre);
    final plan = politique.calculer(
      chapitres,
      estFavori: noms.contains(nomListeFavoris),
      estSuivi: noms.contains(nomListeSuivis),
    );
    return (plan: plan, chapitres: chapitres);
  }

  Future<PlanTelechargement> _appliquerRegles(
    int idTitre, {
    required bool supprimerEchues,
  }) async {
    final calcul = await _calculerPlan(idTitre);
    if (calcul == null) {
      return PlanTelechargement.vide;
    }
    final (:plan, :chapitres) = calcul;

    // Ordre : mise en file d'abord, suppressions ensuite. Si une étape
    // échoue au milieu, le client garde ses archives et la file est déjà
    // complète ; l'inverse pourrait laisser un trou dans sa lecture.
    // LIMITE : pas de transaction commune (les dépôts ouvrent chacune la
    // leur) ; une application suivante des règles termine le travail.
    for (final idChapitre in plan.idsATelecharger) {
      await _mettreEnFileAutomatiquement(idChapitre);
    }
    // Les téléchargements en attente qui ne sont plus voulus (lecture qui a
    // avancé, titre retiré de Favoris et Suivis) sont retirés de la file ;
    // ceux que le client a demandés à la main restent.
    final idsChapitres = chapitres.map((c) => c.id).whereType<int>().toSet();
    // Chapitres devenus externes (R4) : retirés de la file même s'ils avaient
    // été demandés à la main (ils n'ont aucune page à télécharger). Les
    // échecs aussi : sinon « Réessayer » resterait proposé.
    final idsExternes = <int>{
      for (final chapitre in chapitres)
        if (chapitre.id != null && chapitre.estExterne) chapitre.id!,
    };
    final file = await _depotTelechargements.chargerFile(
      statuts: <StatutTelechargement>{
        StatutTelechargement.enAttente,
        StatutTelechargement.echec,
      },
    );
    for (final telechargement in file) {
      final idChapitre = telechargement.idChapitre;
      if (!idsChapitres.contains(idChapitre)) continue;
      final plusVoulu =
          telechargement.statut == StatutTelechargement.enAttente &&
          !plan.idsVoulus.contains(idChapitre) &&
          !_demandesManuelles.contains(idChapitre);
      if (plusVoulu || idsExternes.contains(idChapitre)) {
        await _depotTelechargements.supprimerTelechargement(telechargement.id!);
      }
    }
    // Suppression différée (décision du client) : une date est posée pour
    // les archives qui ne sont plus voulues, et retirée pour celles qui le
    // redeviennent. Une date déjà posée n'est pas repoussée : sinon chaque
    // application des règles relancerait le compte à rebours affiché.
    final aSupprimer = plan.idsASupprimer.toSet();
    final echeance = _maintenant().add(delaiSuppressionDifferee);
    for (final chapitre in chapitres) {
      final id = chapitre.id;
      if (id == null || !chapitre.estTelecharge) continue;
      // Choix « Garder » du client (`est_garde`) : jamais supprimé par les
      // règles. Un téléchargement manuel hors des règles (autre langue,
      // chapitre ancien) n'est pas exempté : le compte à rebours affiché
      // laisse 24 h au client pour le garder.
      final voulu = !aSupprimer.contains(id) || chapitre.estGarde;
      if (!voulu && chapitre.dateSuppressionPrevue == null) {
        await _depotChapitres.planifierSuppression(id, echeance);
      } else if (voulu && chapitre.dateSuppressionPrevue != null) {
        await _depotChapitres.planifierSuppression(id, null);
      }
    }
    if (supprimerEchues) {
      await _supprimerArchivesEchuesSansErreur(signalerChangement: false);
    }
    _signaler();
    return plan;
  }

  // ---------------------------------------------------- Suppression différée

  /// Supprime les archives dont la suppression prévue est échue (tous
  /// titres) et renvoie leur nombre.
  ///
  /// Appelée au démarrage, à chaque application des règles et en fin de
  /// file ; l'interface peut aussi l'appeler régulièrement (par exemple au
  /// retour au premier plan). Un chapitre ouvert dans le lecteur
  /// ([protegerChapitre]) ou gardé par le client est épargné. Les règles du
  /// titre sont recalculées juste avant : un chapitre qui n'est plus à
  /// supprimer (réglages changés, titre retiré de Favoris et Suivis) perd sa
  /// date au lieu d'être effacé. Un chapitre en erreur est journalisé et
  /// n'empêche pas les autres.
  Future<int> supprimerArchivesEchues() async {
    final nombre = await _supprimerArchivesEchues();
    if (nombre > 0) _signaler();
    return nombre;
  }

  Future<int> _supprimerArchivesEchues() async {
    // Avant tout effacement : un chapitre gardé avec l'ancienne version (clé
    // `parametres`) n'a pas encore `est_garde` et serait sinon supprimé si
    // cette méthode passe avant `appliquerReglesATous` (tâche de fond,
    // appel de l'interface au retour au premier plan).
    await _reprendreAnciensGardes();
    final echues = await _depotChapitres.chargerSuppressionsEchues(
      _maintenant(),
    );
    if (echues.isEmpty) return 0;
    // Chapitres encore à supprimer selon les règles, par titre (un calcul
    // par titre concerné, pas par chapitre).
    final aSupprimerParTitre = <int, Set<int>>{};
    var nombre = 0;
    var annulees = 0;
    for (final chapitre in echues) {
      final id = chapitre.id;
      // Chapitre lu en ce moment : supprimé au prochain passage, une fois le
      // lecteur fermé (effacer l'archive ferait échouer les pages suivantes).
      if (id == null || estProtege(id)) continue;
      try {
        // Les règles sont recalculées juste avant d'effacer : depuis la pose
        // de la date (jusqu'à 24 h plus tôt), le client a pu changer ses
        // réglages ou ses langues, revenir en arrière dans sa lecture, ou
        // retirer le titre de Favoris et Suivis (règle : alors rien n'est
        // supprimé). Sans ce contrôle, la tâche de fond effacerait une
        // archive redevenue voulue avant que l'application n'annule la date.
        final idTitre = chapitre.idTitre;
        var aSupprimer = const <int>{};
        if (idTitre != null) {
          aSupprimer = aSupprimerParTitre[idTitre] ??=
              (await _calculerPlan(idTitre))?.plan.idsASupprimer.toSet() ??
              const <int>{};
        }
        // Les chapitres gardés sont déjà exclus par la requête des échéances
        // (`est_garde`), même gardés dans l'autre isolat.
        if (!aSupprimer.contains(id)) {
          // Plus à supprimer : la date n'a plus lieu d'être.
          await _depotChapitres.planifierSuppression(id, null);
          annulees++;
          continue;
        }
        await supprimerTelechargement(id, signalerChangement: false);
        nombre++;
      } catch (erreur) {
        debugPrint('Suppression prévue du chapitre n°$id impossible : $erreur');
      }
    }
    // Les dates annulées changent l'affichage (fin du compte à rebours
    // rouge) même si rien n'a été effacé.
    if (annulees > 0) _signaler();
    return nombre;
  }

  /// Comme [supprimerArchivesEchues], sans jamais lever (appel depuis les
  /// règles ou la file, qui ne doivent pas échouer pour si peu).
  Future<void> _supprimerArchivesEchuesSansErreur({
    bool signalerChangement = true,
  }) async {
    try {
      final nombre = await _supprimerArchivesEchues();
      if (nombre > 0 && signalerChangement) _signaler();
    } catch (erreur, pile) {
      debugPrint('Suppressions prévues non faites : $erreur\n$pile');
    }
  }

  /// Supprime tout de suite l'archive d'un chapitre (bouton « Supprimer
  /// maintenant » d'une suppression prévue, ou suppression demandée par le
  /// client) : même effet que [supprimerTelechargement].
  Future<void> supprimerMaintenant(int idChapitre) =>
      supprimerTelechargement(idChapitre);

  /// Annule la suppression prévue d'un chapitre (bouton « Garder ») : les
  /// règles ne le suppriment plus jamais automatiquement ; seul le client
  /// peut encore le supprimer. Sans effet visible si aucune suppression
  /// n'était prévue (le chapitre est simplement marqué gardé).
  Future<void> annulerSuppression(int idChapitre) async {
    // Une seule requête : le chapitre est marqué gardé et sa date effacée
    // ensemble, sans fenêtre où l'autre isolat pourrait le supprimer.
    await _depotChapitres.marquerGarde(idChapitre);
    _signaler();
  }

  /// Retire le choix « Garder » d'un chapitre ([annulerSuppression]) puis
  /// applique les règles de son titre : s'il n'est plus voulu, sa
  /// suppression est de nouveau prévue dans 24 heures.
  Future<void> retirerGarde(int idChapitre) async {
    await _depotChapitres.marquerGarde(idChapitre, estGarde: false);
    final idTitre = (await _depotChapitres.chargerChapitre(idChapitre))
        ?.idTitre;
    if (idTitre != null) {
      await appliquerRegles(idTitre);
    } else {
      _signaler();
    }
  }

  /// Chapitres gardés par le client ([annulerSuppression]) : l'interface
  /// peut l'indiquer à côté du chapitre (`Chapitre.estGarde` donne la même
  /// information chapitre par chapitre).
  Future<Set<int>> chargerChapitresGardes() =>
      _depotChapitres.chargerIdsChapitresGardes();

  /// Chapitres dont la suppression est prévue (tous titres, ou seulement
  /// [idTitre]), la plus proche d'abord : section rouge de l'onglet
  /// Téléchargements, avec le compte à rebours
  /// (`Chapitre.dateSuppressionPrevue`).
  Future<List<Chapitre>> chargerSuppressionsPrevues({int? idTitre}) =>
      _depotChapitres.chargerSuppressionsPrevues(idTitre: idTitre);

  /// Met un chapitre voulu par les règles en file, ou relance son échec.
  Future<void> _mettreEnFileAutomatiquement(int idChapitre) async {
    // Relu juste avant : l'autre isolat a pu le terminer depuis le calcul du
    // plan.
    final chapitre = await _depotChapitres.chargerChapitre(idChapitre);
    // Chapitre hébergé ailleurs (R4) : jamais téléchargeable. La politique
    // l'écarte déjà ; contrôle redit ici car il a pu devenir externe depuis
    // le calcul du plan.
    if (chapitre == null || chapitre.estTelecharge || chapitre.estExterne) {
      return;
    }
    final existant = await _depotTelechargements.chargerParChapitre(idChapitre);
    if (existant == null) {
      await _depotTelechargements.ajouterEnFile(idChapitre);
      return;
    }
    // Seul un échec est relancé : « en attente » et « en cours » sont déjà
    // pris en charge, et « terminé » signifie qu'un autre traitement vient de
    // finir (l'état du chapitre sera à jour au prochain calcul).
    if (existant.statut != StatutTelechargement.echec) return;
    // Pas de relance sans fin d'un chapitre que le site refuse.
    if ((_echecs[idChapitre] ?? 0) >= nombreMaximalEchecsAutomatiques) return;
    await _depotTelechargements.enregistrerStatut(
      existant.id!,
      StatutTelechargement.enAttente,
    );
  }

  // ------------------------------------------------- Actions du client

  /// File de téléchargement (tous statuts), dans l'ordre d'ajout.
  Future<List<Telechargement>> chargerFile() =>
      _depotTelechargements.chargerFile();

  /// Ajoute un chapitre à la file (téléchargement manuel) et lance la file.
  ///
  /// Une demande manuelle relance aussi un chapitre que les règles ne
  /// relancent plus (trop d'échecs), et n'est pas retirée de la file par les
  /// règles pendant cette session.
  ///
  /// Lève une [ErreurService] pour un chapitre hébergé sur un site externe
  /// (`Chapitre.estExterne`) : il se lit sur ce site et n'a aucune page à
  /// télécharger (R4).
  Future<void> telechargerChapitre(int idChapitre) async {
    final chapitre = await _depotChapitres.chargerChapitre(idChapitre);
    if (chapitre != null && chapitre.estExterne) {
      throw const ErreurService(
        "Ce chapitre se lit sur le site de l'éditeur : il ne peut pas être "
        'téléchargé.',
      );
    }
    _demandesManuelles.add(idChapitre);
    _echecs.remove(idChapitre);
    final existant = await _depotTelechargements.chargerParChapitre(idChapitre);
    if (existant == null) {
      await _depotTelechargements.ajouterEnFile(idChapitre);
    } else if (existant.statut == StatutTelechargement.echec) {
      await _depotTelechargements.enregistrerStatut(
        existant.id!,
        StatutTelechargement.enAttente,
      );
    }
    _signaler();
    unawaited(lancerTraitement());
  }

  /// Supprime un titre de la bibliothèque avec ses archives : à utiliser à
  /// la place de `ServiceBibliotheque.supprimerTitre`, qui laisserait les
  /// fichiers `.zip` sur l'appareil.
  ///
  /// Les archives sont effacées d'abord (et leurs chapitres marqués non
  /// téléchargés), puis la couverture enregistrée : si une suppression de
  /// fichier échoue, l'erreur remonte et le titre reste, pour pouvoir
  /// réessayer sans perdre la trace des fichiers. Un téléchargement en cours
  /// pour ce titre s'arrête à la page suivante (sa ligne de file disparaît
  /// avec le titre).
  Future<void> supprimerTitre(int idTitre) async {
    final chapitres = await _depotChapitres.chargerChapitres(idTitre);
    for (final chapitre in chapitres) {
      final id = chapitre.id;
      if (id != null && chapitre.estTelecharge) {
        await supprimerTelechargement(id, signalerChangement: false);
      }
    }
    final titre = await _depotTitres.chargerTitre(idTitre);
    if (titre != null) {
      // Après les archives : le dossier du titre n'est retiré que vide.
      await _stockage.supprimerCouverture(titre);
    }
    await _depotTitres.supprimerTitre(idTitre);
    _signaler();
  }

  /// Supprime l'archive d'un chapitre et sa ligne de file.
  ///
  /// Si le chapitre est en cours de téléchargement, ce dernier s'arrête à la
  /// page suivante et son archive partielle est effacée (annulation). Un
  /// chapitre seulement en file (jamais téléchargé) perd sa ligne de file
  /// sans qu'aucune archive ne soit touchée.
  Future<void> supprimerTelechargement(
    int idChapitre, {
    bool signalerChangement = true,
  }) async {
    // Ligne de file d'abord : un téléchargement qui se termine pendant cette
    // suppression ne peut plus s'enregistrer « terminé » (sa ligne a
    // disparu) et efface lui-même son archive. Dans l'ordre inverse, il
    // pourrait marquer le chapitre téléchargé juste après l'effacement.
    final ligne = await _depotTelechargements.chargerParChapitre(idChapitre);
    if (ligne?.id != null) {
      await _depotTelechargements.supprimerTelechargement(ligne!.id!);
    }
    final chapitre = await _depotChapitres.chargerChapitre(idChapitre);
    final nomArchive = chapitre?.nomArchive;
    if (nomArchive != null) {
      // Nom réellement écrit, enregistré au téléchargement : le seul sûr
      // quand le chapitre a des homonymes (`ch1.fr.2.zip`).
      await _stockage.supprimerArchive(nomArchive);
    } else if (chapitre != null && chapitre.estTelecharge) {
      // Chapitre téléchargé avant la migration 4 (pas de nom enregistré) :
      // seul le nom calculé est possible. Jamais pour un chapitre non
      // téléchargé : son nom calculé (`ch0.fr.zip` d'un oneshot, `ch1.fr.zip`
      // d'un autre groupe) est souvent l'archive d'un AUTRE chapitre.
      final contexte = await _chargerContexte(idChapitre);
      if (contexte != null) {
        await _stockage.supprimerChapitre(contexte.titre, contexte.chapitre);
      }
    }
    // Efface aussi le nom d'archive et la suppression prévue.
    await _depotChapitres.enregistrerArchive(idChapitre, null);
    // Un chapitre supprimé n'a plus à être « gardé » : s'il est retéléchargé,
    // les règles s'appliquent à nouveau normalement.
    if (chapitre?.estGarde ?? false) {
      await _depotChapitres.marquerGarde(idChapitre, estGarde: false);
    }
    if (signalerChangement) {
      _signaler();
    }
  }

  /// Doublons téléchargés d'un titre : groupes de chapitres de même numéro
  /// et même langue (voir `PolitiqueTelechargement.trouverDoublons`), à
  /// montrer au client pour qu'il choisisse lesquels supprimer.
  Future<List<List<Chapitre>>> chargerDoublons(int idTitre) async =>
      PolitiqueTelechargement.trouverDoublons(
        await _depotChapitres.chargerChapitres(idTitre),
      );

  /// Retire de la file les téléchargements terminés (l'archive reste).
  Future<int> viderTermines() async {
    final nombre = await _depotTelechargements.supprimerTermines();
    _signaler();
    return nombre;
  }

  // ---------------------------------------------------------------- Lecture

  /// Nombre de pages d'un chapitre téléchargé (0 pour un chapitre texte).
  Future<int> compterPages(int idChapitre) async {
    final contexte = await _exigerContexte(idChapitre);
    return _stockage.compterPages(contexte.titre, contexte.chapitre);
  }

  /// Octets de la page [index] (à partir de 0), lus dans l'archive.
  Future<Uint8List> lirePage(int idChapitre, int index) async {
    final contexte = await _exigerContexte(idChapitre);
    return _stockage.lirePage(contexte.titre, contexte.chapitre, index);
  }

  /// Texte HTML d'un chapitre de roman, ou `null` s'il s'agit d'images.
  Future<String?> lireTexte(int idChapitre) async {
    final contexte = await _exigerContexte(idChapitre);
    return _stockage.lireTexte(contexte.titre, contexte.chapitre);
  }

  Future<_ContexteChapitre> _exigerContexte(int idChapitre) async {
    final contexte = await _chargerContexte(idChapitre);
    if (contexte == null) {
      throw const ErreurService('Ce chapitre n\'existe plus.');
    }
    return contexte;
  }

  Future<_ContexteChapitre?> _chargerContexte(int idChapitre) async {
    final chapitre = await _depotChapitres.chargerChapitre(idChapitre);
    final idTitre = chapitre?.idTitre;
    if (chapitre == null || idTitre == null) return null;
    final titre = await _depotTitres.chargerTitre(idTitre);
    final idSource = titre?.idSource;
    if (titre == null || idSource == null) return null;
    final source = await _depotSources.chargerSource(idSource);
    if (source == null) return null;
    // Nom calculé de l'archive (repli quand aucun `nomArchive` n'est
    // enregistré, c'est-à-dire pour un nouveau téléchargement ou un chapitre
    // téléchargé avant la migration 4) : une langue vide est remplacée par
    // la première langue de la source (PLAYBOOK.md section 5), sinon par la
    // langue par défaut fixe (« fr ») et non par le réglage général, pour
    // que ce repli ne dépende pas d'un réglage qui peut changer. Dès que le
    // nom est enregistré, c'est lui qui sert à la lecture et à la
    // suppression.
    final langues = ServiceBibliotheque.languesPreferees(source);
    final chapitrePourChemin = chapitre.langue.isEmpty && langues.isNotEmpty
        ? chapitre.copierAvec(langue: langues.first)
        : chapitre;
    // LIMITE : le suffixe « (nom de la source) » prévu par le playbook en cas
    // de titres homonymes de sources différentes n'est pas encore appliqué.
    return _ContexteChapitre(chapitrePourChemin, titre, source);
  }

  // ------------------------------------------------------ Traitement file

  /// Lance le traitement de la file s'il n'est pas déjà en cours. Renvoie le
  /// traitement (déjà en cours ou nouveau) : les tests peuvent l'attendre.
  ///
  /// Si un autre isolat (tâche de fond Android ou application ouverte) tient
  /// le verrou de la file, rien n'est traité : un nouvel essai est prévu à
  /// l'expiration de ce verrou, et tout appel suivant réessaie aussi. Ne lève
  /// jamais d'erreur (elles sont journalisées) : l'appel peut être lancé sans
  /// être attendu.
  Future<void> lancerTraitement() {
    final enCours = _traitement;
    if (enCours != null) {
      return enCours;
    }
    _relance?.cancel();
    _relance = null;
    final nouveau = _traiterFile().whenComplete(() {
      _traitement = null;
      _signaler();
    });
    _traitement = nouveau;
    return nouveau;
  }

  Future<void> _traiterFile() async {
    // Rend la main avant de commencer : `_traitement` est affecté avant
    // qu'une fin immédiate ne le remette à null.
    await Future<void>.value();
    try {
      final verrou = await _prendreVerrou();
      if (verrou != null) {
        _planifierRelance(verrou);
        return;
      }
      try {
        await _reprendreApresInterruption();
        while (!_changements.isClosed) {
          // Renouvelé avant chaque chapitre ; si un autre isolat a repris le
          // verrou entre-temps (le nôtre avait expiré), on lui laisse la file
          // plutôt que d'écrire les mêmes archives que lui.
          if (!await _renouvelerVerrou(verifier: true)) {
            return;
          }
          // Réservation atomique (en attente → en cours) : même si les deux
          // isolats se croient propriétaires du verrou (voir la LIMITE
          // ci-dessous), un chapitre n'est jamais pris par les deux.
          final suivant = await _depotTelechargements.reserverProchain();
          if (suivant == null) {
            // File vide : les suppressions prévues échues pendant le
            // traitement (qui peut durer longtemps) sont faites maintenant.
            await _supprimerArchivesEchuesSansErreur();
            await _planifierRepriseSiNecessaire();
            return;
          }
          await _telecharger(suivant);
        }
      } finally {
        await _libererVerrou();
      }
    } catch (erreur, pile) {
      // Une erreur de base (par exemple une écriture concurrente de l'autre
      // isolat) ne doit pas remonter jusqu'à l'interface : la file sera
      // reprise au prochain lancement.
      debugPrint('Traitement de la file interrompu : $erreur\n$pile');
    }
  }

  /// Remet en attente les téléchargements « en cours » et efface les
  /// archives partielles, **anciens** seulement (rien d'écrit depuis une
  /// durée de verrou). Appelé avec le verrou : un « en cours » ancien ne
  /// peut venir que d'un traitement interrompu (application tuée, tâche de
  /// fond arrêtée par Android). Un « en cours » récent peut être celui de
  /// l'autre isolat dans la fenêtre de course du verrou (voir la LIMITE plus
  /// bas) : sa progression est écrite à chaque page, il n'est donc pas
  /// touché.
  Future<void> _reprendreApresInterruption() async {
    await _depotTelechargements.reprendreApresInterruption(
      ancienneteMinimale: _dureeVerrou,
    );
    try {
      await _stockage.nettoyerFichiersPartiels(
        ancienneteMinimale: _dureeVerrou,
      );
    } catch (erreur) {
      // Un fichier partiel impossible à effacer ne doit pas bloquer la file :
      // l'écriture du même chapitre repartira de zéro.
      debugPrint('Nettoyage des archives partielles impossible : $erreur');
    }
  }

  // ------------------------------------------------- Verrou entre isolats

  // LIMITE : DepotParametres n'offre pas de compare-and-set atomique. La
  // prise du verrou se fait donc en trois temps : lecture, écriture, relecture
  // de contrôle. Fenêtre de course : si les deux isolats lisent le verrou
  // libre avant que l'un ou l'autre ne l'écrive, et que la relecture du
  // premier se fait avant l'écriture du second, les deux se croient
  // propriétaires. Le perdant s'en aperçoit au renouvellement suivant (avant
  // le chapitre suivant, ou entre deux pages d'un long chapitre) et
  // s'arrête. Un même chapitre n'est jamais pris par
  // les deux (DepotTelechargements.reserverProchain est atomique), et la
  // reprise après interruption ne touche que les « en cours » et `.zip.part`
  // anciens (rien d'écrit depuis une durée de verrou) : le chapitre en cours
  // de l'autre n'est donc ni remis en attente ni effacé. La fenêtre ne dure
  // que quelques millisecondes et ne s'ouvre que si la tâche de fond démarre
  // pile au lancement d'un traitement dans l'application.

  /// Essaie de prendre le verrou de la file. Renvoie `null` en cas de succès,
  /// sinon le verrou de l'autre propriétaire.
  Future<VerrouTelechargement?> _prendreVerrou() async {
    final actuel = await _serviceParametres.chargerVerrouTelechargement();
    if (actuel != null &&
        !actuel.estLibrePour(_identifiantVerrou, _maintenant())) {
      return actuel;
    }
    await _renouvelerVerrou(verifier: false);
    // Relecture de contrôle : si l'autre isolat a écrit juste après nous,
    // c'est lui qui garde la file.
    final relu = await _serviceParametres.chargerVerrouTelechargement();
    if (relu != null && relu.proprietaire != _identifiantVerrou) {
      return relu;
    }
    return null;
  }

  /// Repousse l'expiration du verrou. Avec [verifier], s'assure d'abord que
  /// le verrou est toujours à nous (ou libre) et renvoie `false` sinon.
  Future<bool> _renouvelerVerrou({required bool verifier}) async {
    if (verifier) {
      final actuel = await _serviceParametres.chargerVerrouTelechargement();
      if (actuel != null && actuel.proprietaire != _identifiantVerrou) {
        return false;
      }
    }
    final maintenant = _maintenant();
    await _serviceParametres.enregistrerVerrouTelechargement(
      VerrouTelechargement(
        proprietaire: _identifiantVerrou,
        expiration: maintenant.add(_dureeVerrou),
      ),
    );
    _dernierRenouvellement = maintenant;
    return true;
  }

  /// Renouvelle le verrou pendant un long chapitre (entre deux pages), au
  /// plus une fois par fraction de sa durée
  /// ([fractionRenouvellementVerrou]) pour ne pas écrire en base à chaque
  /// page.
  ///
  /// Renvoie `false` si le verrou a été perdu (notre verrou a expiré et
  /// l'autre isolat l'a repris) : le chapitre doit alors être abandonné.
  /// Continuer écrirait la même archive que l'autre isolat, qui reprendra
  /// ce chapitre à son tour (sa ligne « en cours » ne sera plus rafraîchie,
  /// donc vue comme interrompue).
  Future<bool> _renouvelerVerrouSiNecessaire() async {
    final dernier = _dernierRenouvellement;
    if (dernier != null &&
        _maintenant().difference(dernier) <
            _dureeVerrou ~/ fractionRenouvellementVerrou) {
      return true;
    }
    try {
      return await _renouvelerVerrou(verifier: true);
    } catch (erreur) {
      // Un renouvellement manqué (base momentanément occupée) ne doit pas
      // faire échouer le chapitre : le verrou reste valable jusqu'à son
      // expiration, et sera revérifié à la page suivante.
      debugPrint('Renouvellement du verrou impossible : $erreur');
      return true;
    }
  }

  /// Libère le verrou s'il est toujours à nous.
  Future<void> _libererVerrou() async {
    _dernierRenouvellement = null;
    try {
      final actuel = await _serviceParametres.chargerVerrouTelechargement();
      if (actuel?.proprietaire == _identifiantVerrou) {
        await _serviceParametres.supprimerVerrouTelechargement();
      }
    } catch (erreur) {
      // Le verrou expirera de lui-même.
      debugPrint('Libération du verrou de téléchargement impossible : $erreur');
    }
  }

  /// Prévoit un seul nouvel essai à l'expiration du verrou de l'autre
  /// isolat (au moins 5 s plus tard, au plus une durée de verrou) : l'autre
  /// a pu être tué, et la file ne doit pas rester bloquée jusqu'à la
  /// prochaine action du client. Une lecture en base par essai, sans réseau.
  void _planifierRelance(VerrouTelechargement verrou) {
    _planifierNouvelEssai(
      verrou.expiration.difference(_maintenant()) + margeNouvelEssaiVerrou,
    );
  }

  /// Après une file vidée : s'il reste des téléchargements « en cours » trop
  /// récents pour être repris (application tuée juste avant ce démarrage,
  /// ou chapitre de l'autre isolat), un seul nouvel essai est prévu une
  /// durée de verrou plus tard, quand ils seront assez anciens pour être
  /// repris s'ils sont vraiment abandonnés. Lecture en base seulement.
  Future<void> _planifierRepriseSiNecessaire() async {
    try {
      final enCours = await _depotTelechargements.chargerFile(
        statuts: <StatutTelechargement>{StatutTelechargement.enCours},
      );
      if (enCours.isNotEmpty) {
        _planifierNouvelEssai(_dureeVerrou + margeNouvelEssaiVerrou);
      }
    } catch (erreur) {
      debugPrint('Contrôle des téléchargements en cours impossible : $erreur');
    }
  }

  /// Prévoit un seul nouvel essai de traitement après [attente] (ramenée
  /// entre 5 s et une durée de verrou un peu dépassée).
  void _planifierNouvelEssai(Duration demandee) {
    if (_changements.isClosed) return;
    const minimum = attenteMinimaleNouvelEssai;
    final maximum = _dureeVerrou + margeNouvelEssaiVerrou;
    final attente = demandee < minimum
        ? minimum
        : (demandee > maximum ? maximum : demandee);
    _relance?.cancel();
    _relance = Timer(attente, () {
      _relance = null;
      if (!_changements.isClosed) {
        unawaited(lancerTraitement());
      }
    });
  }

  DateTime _maintenant() => _horloge().toUtc();

  /// Télécharge un chapitre de la file. Ne lève jamais : toute erreur met le
  /// téléchargement en échec (ou est journalisée si même cela échoue).
  Future<void> _telecharger(Telechargement telechargement) async {
    final id = telechargement.id!;
    final idChapitre = telechargement.idChapitre;
    EcritureChapitre? ecriture;
    // Archive finalisée mais pas encore enregistrée en base : à effacer si
    // l'enregistrement échoue, sinon elle resterait sur le disque sans
    // qu'aucun chapitre ne la désigne.
    String? archiveOrpheline;
    try {
      // Déjà « en cours » : la ligne a été réservée par reserverProchain().
      _signaler();

      final contexte = await _chargerContexte(idChapitre);
      // Chapitre disparu, ou devenu externe depuis sa mise en file (R4) :
      // la ligne est retirée sans rien demander au site.
      if (contexte == null || contexte.chapitre.estExterne) {
        await _depotTelechargements.supprimerTelechargement(id);
        return;
      }
      final adaptateur = _fabriqueSources.creer(contexte.source);
      var contenu = await adaptateur.recupererContenu(
        contexte.chapitre.urlChapitre,
      );
      ecriture = await _stockage.ouvrirEcriture(
        contexte.titre,
        contexte.chapitre,
      );

      final texte = contenu.texteHtml;
      if (contenu.estTexte && texte != null) {
        await ecriture.ajouterTexte(texte);
      } else {
        final total = contenu.urlsImages.length;
        await _depotTelechargements.enregistrerProgression(
          id,
          nombrePagesFaites: 0,
          nombrePagesTotal: total,
        );
        for (var index = 0; index < total; index++) {
          final (octets, url, contenuAJour) = await _telechargerPage(
            contenu,
            index,
            adaptateur,
            contexte,
          );
          contenu = contenuAJour;
          await ecriture.ajouterPage(
            octets,
            extension:
                StockageTelechargements.extensionDepuisUrl(url) ??
                extensionImageParDefaut,
          );
          // La ligne a disparu (le client a annulé ou supprimé le titre) :
          // on s'arrête sans solliciter le site pour les pages restantes.
          if (!await _depotTelechargements.enregistrerProgression(
            id,
            nombrePagesFaites: index + 1,
          )) {
            throw const _Annulation();
          }
          if (!await _renouvelerVerrouSiNecessaire()) {
            throw const _VerrouPerdu();
          }
          _signaler();
        }
      }
      // Nom réellement retenu par le stockage (`ch1.fr.2.zip` en cas de
      // doublon) : enregistré avec le statut, dans la même transaction, pour
      // que la lecture et la suppression retrouvent toujours cette archive.
      final nomArchive = ecriture.nomArchive;
      // Archive neuve (aucun nom déjà connu en base pour ce chapitre) : si
      // l'enregistrement du statut échoue, plus rien ne la référence et il
      // faut l'effacer. Un re-téléchargement réutilise au contraire le nom
      // enregistré : l'archive reste référencée par la base, on la garde.
      final estArchiveNeuve =
          contexte.chapitre.nomArchive == null &&
          !contexte.chapitre.estTelecharge;
      await ecriture.finaliser();
      ecriture = null;
      if (estArchiveNeuve) archiveOrpheline = nomArchive;
      if (!await _depotTelechargements.enregistrerStatut(
        id,
        StatutTelechargement.termine,
        nomArchive: nomArchive,
      )) {
        // Annulé pendant la toute dernière page : l'archive finie n'est
        // plus voulue et ne serait suivie par aucune ligne en base.
        archiveOrpheline = null;
        await _stockage.supprimerArchive(nomArchive);
        return;
      }
      archiveOrpheline = null;
      _echecs.remove(idChapitre);
    } on _Annulation {
      await _abandonner(ecriture);
    } on _VerrouPerdu {
      // L'autre isolat a repris la file : on efface seulement notre archive
      // partielle, sans toucher la ligne de file (c'est désormais à lui de
      // la gérer ; elle sera reprise comme interrompue).
      debugPrint('Téléchargement n°$id abandonné : verrou repris ailleurs');
      await _abandonner(ecriture);
    } catch (erreur, pile) {
      debugPrint('Téléchargement n°$id en échec : $erreur\n$pile');
      await _abandonner(ecriture);
      await _supprimerArchiveOrpheline(archiveOrpheline);
      _echecs.update(idChapitre, (n) => n + 1, ifAbsent: () => 1);
      try {
        await _depotTelechargements.enregistrerStatut(
          id,
          StatutTelechargement.echec,
          messageErreur: _messageErreur(erreur),
        );
      } catch (erreurStatut) {
        // La ligne restera « en cours » et sera reprise au prochain
        // traitement.
        debugPrint(
          'Statut du téléchargement n°$id non enregistré : $erreurStatut',
        );
      }
    } finally {
      _signaler();
    }
  }

  static Future<void> _abandonner(EcritureChapitre? ecriture) async {
    try {
      await ecriture?.abandonner();
    } catch (_) {
      // L'archive partielle sera effacée au début du prochain traitement.
    }
  }

  /// Efface une archive finalisée que la base ne référence pas (voir
  /// `archiveOrpheline` dans [_telecharger]), sans lever : on est déjà dans
  /// un chemin d'échec.
  Future<void> _supprimerArchiveOrpheline(String? nomArchive) async {
    if (nomArchive == null) return;
    try {
      await _stockage.supprimerArchive(nomArchive);
    } catch (erreur) {
      // LIMITE : l'archive reste sur le disque sans chapitre associé ; elle
      // sera remplacée si ce chapitre est retéléchargé sous le même nom.
      debugPrint('Archive orpheline $nomArchive non effacée : $erreur');
    }
  }

  /// Télécharge une page. Sur MangaDex, une adresse d'images expirée (403
  /// après 15 minutes) ou un nœud MangaDex@Home en panne est remplacée une
  /// fois en redemandant le contenu du chapitre (règle de la documentation).
  Future<(Uint8List, String, ContenuChapitre)> _telechargerPage(
    ContenuChapitre contenu,
    int index,
    SourceSite adaptateur,
    _ContexteChapitre contexte,
  ) async {
    var contenuCourant = contenu;
    for (var essai = 0; essai < nombreEssaisParPage; essai++) {
      final url = contenuCourant.urlsImages[index];
      try {
        final octets = await _recupererImage(url, contenuCourant, contexte);
        return (octets, url, contenuCourant);
      } on ErreurSource catch (erreur) {
        final dernierEssai = essai >= nombreEssaisParPage - 1;
        if (dernierEssai || !_peutRenouvelerAdresse(url, erreur, contexte)) {
          rethrow;
        }
        contenuCourant = await adaptateur.recupererContenu(
          contexte.chapitre.urlChapitre,
        );
        if (contenuCourant.urlsImages.length <= index) {
          throw ErreurSource(
            url,
            'Le chapitre a changé pendant le téléchargement.',
            cause: erreur,
          );
        }
      }
    }
    // Inatteignable : la boucle renvoie ou relance toujours.
    throw StateError('Téléchargement de page interrompu');
  }

  Future<Uint8List> _recupererImage(
    String url,
    ContenuChapitre contenu,
    _ContexteChapitre contexte,
  ) async {
    final uri = Uri.parse(url);
    if (SignalementMangaDex.estServeurMangaDexAtHome(url)) {
      // Une seule tentative : chaque échec doit être signalé, puis on change
      // de serveur plutôt que d'insister (documentation MangaDex).
      try {
        final reponse = await _client.recupererOctetsAvecDetails(
          uri,
          userAgent: userAgentApplication,
          nouvellesTentatives: 0,
          // Une page d'erreur HTML servie en 200 n'est pas une page du
          // chapitre : signalée comme un échec, puis nœud renouvelé.
          exigerImage: true,
        );
        unawaited(_signalement.signalerReussite(url, reponse));
        return reponse.octets;
      } on ErreurSource catch (erreur) {
        unawaited(_signalement.signalerEchec(url, erreur));
        rethrow;
      }
    }
    return _client.recupererOctets(
      uri,
      referer: contenu.urlReferer ?? contexte.source.urlBase,
      // MangaDex exige un User-Agent honnête sur tous ses serveurs
      // (`uploads.mangadex.org`, nœuds `*.mangadex.network`…).
      userAgent: SourceMangaDex.estServeurMangaDex(uri.host)
          ? userAgentApplication
          : null,
      // Une page anti-robot HTML servie en 200 (E10) ne doit jamais être
      // écrite dans l'archive comme une page du chapitre.
      // LIMITE : un site qui servirait ses images sans `Content-Type`
      // `image/*` (par exemple `application/octet-stream`) verrait ses
      // téléchargements échouer (message « n'est pas une image » dans la
      // file) ; il faudrait alors un contrôle des octets propre à ce site.
      exigerImage: true,
    );
  }

  /// `true` si un échec sur [url] justifie de redemander les adresses des
  /// images : tout échec d'un nœud MangaDex@Home (nœud en panne), ou un 403
  /// sur une autre adresse MangaDex (adresse expirée). Les autres sites ne
  /// renouvellent pas leurs adresses : réessayer serait inutile.
  static bool _peutRenouvelerAdresse(
    String url,
    ErreurSource erreur,
    _ContexteChapitre contexte,
  ) {
    if (SignalementMangaDex.estServeurMangaDexAtHome(url)) return true;
    final hote = Uri.tryParse(url)?.host ?? '';
    final estMangaDex =
        contexte.source.typeSource == TypeSource.mangaDex ||
        SourceMangaDex.estServeurMangaDex(hote);
    return estMangaDex && erreur.codeStatut == 403;
  }

  static String _messageErreur(Object erreur) {
    if (erreur is ErreurSource) return erreur.message;
    if (erreur is ErreurService) return erreur.message;
    return erreur.toString();
  }
}
