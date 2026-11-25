/// Téléchargement des chapitres pour la lecture hors-ligne (PLAYBOOK.md
/// sections 5 et 7) et application des règles de conservation du client.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as chemins;

import '../donnees/depot_chapitres.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_parametres.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_telechargements.dart';
import '../donnees/depot_titres.dart';
import '../donnees/depot_titres_sources.dart';
import '../donnees/erreur_stockage.dart';
import '../donnees/journal_fichier.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/journal.dart';
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
import 'constantes_services.dart';
import 'dossier_chapitres.dart';
import 'erreur_service.dart';
import 'extension_image.dart';
import 'politique_telechargement.dart';
import 'service_bibliotheque.dart';
import 'service_parametres.dart';
import 'verrou_telechargement.dart';

// Le changement du dossier des chapitres a besoin de la pause et du verrou
// de la file, qui restent privés : `ServiceDossierChapitres` est donc dans
// la même bibliothèque. Sans nouveau membre public ici, les faux
// `ServiceTelechargement` des tests de l'interface restent valables.
part 'service_dossier_chapitres.dart';
// Même raison pour les enregistrements faits depuis le navigateur intégré :
// ils consultent la pause et le changement de dossier, et ce dernier compte
// les enregistrements en cours. Extension plutôt que nouveaux membres
// publics, pour la même compatibilité avec les faux services.
part 'enregistrements_web_telechargement.dart';

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
/// Jusqu'à N chapitres sont téléchargés en même temps (réglage du client,
/// `ServiceParametres.chargerTelechargementsSimultanes`, 1 à 32). Le rythme
/// des requêtes reste celui de `ClientHttpPoli` : 1 s entre deux requêtes
/// vers un même domaine, créneau partagé par tous les chapitres en cours.
/// Plusieurs chapitres d'un même site avancent donc en alternance, sans
/// jamais solliciter ce site plus vite qu'avec un seul chapitre ; le gain
/// vient des chapitres de sites différents.
class ServiceTelechargement {
  /// Crée le service.
  ///
  /// [plafondTelechargementsSimultanes] : nombre maximal de chapitres en
  /// même temps quel que soit le réglage du client (tâche de fond Android :
  /// [telechargementsSimultanesTacheDeFond]). `null` : plafond déduit de
  /// l'isolat (voir [_plafondEffectif]).
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
    DepotTitresSources? depotTitresSources,
    DepotParametres? depotParametres,
    int? plafondTelechargementsSimultanes,
  }) : _plafondSimultanes = plafondTelechargementsSimultanes,
       _depotTitresSources = depotTitresSources,
       _depotParametres = depotParametres,
       _accesDossier = AccesDossierChapitres.accessible(
         stockage.dossierRacine,
         estPersonnalise: stockage.estPersonnalise,
       ),
       _identifiantVerrou = identifiantVerrou ?? _genererIdentifiant(),
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

  /// Sites de chaque titre (étape 8). Facultatif pour ne pas casser les
  /// appelants existants : sans lui, tous les chapitres sont considérés
  /// comme venant d'un site lié, et seul le site principal est connu.
  final DepotTitresSources? _depotTitresSources;

  /// Paramètres bruts, pour savoir si un déplacement des archives est resté
  /// inachevé ([ServiceParametres.cleDeplacementDossierEnCours]).
  /// Facultatif pour ne pas casser les appelants existants : sans lui, ce
  /// contrôle n'est pas fait.
  final DepotParametres? _depotParametres;

  /// Dernier état connu du dossier des chapitres (bandeau de l'interface,
  /// via `ServiceDossierChapitres.accesDossier`).
  AccesDossierChapitres _accesDossier;

  /// File en pause : aucun chapitre n'est commencé (celui en cours se
  /// termine). Posée par le changement du dossier des chapitres.
  // LIMITE : en mémoire, propre à cet isolat ; la tâche de fond Android est
  // tenue à l'écart pendant un déplacement par le verrou de la file.
  bool _enPause = false;

  /// `true` une fois le dossier des chapitres changé pendant cette session :
  /// le nouveau dossier ne s'applique qu'au prochain démarrage, et d'ici là
  /// la file reste en pause et le contrôle des archives manquantes ne fait
  /// rien (il comparerait la base à l'ancien dossier).
  bool _dossierChange = false;

  /// `true` si, en plus, les archives ont été déplacées : l'ancien dossier
  /// ne les contient plus, lecture et suppression sont refusées jusqu'au
  /// redémarrage (elles chercheraient au mauvais endroit).
  bool _archivesDeplacees = false;

  /// `true` pendant un changement du dossier des chapitres demandé dans
  /// cette session (`ServiceDossierChapitres.changerDossierChapitres`) :
  /// aucune archive n'est supprimée pendant ce temps (elle peut être en
  /// cours de copie vers le nouveau dossier).
  bool _changementDossierEnCours = false;

  final String _identifiantVerrou;
  final Duration _dureeVerrou;
  final DateTime Function() _horloge;

  final StreamController<void> _changements =
      StreamController<void>.broadcast();

  /// Plafond des téléchargements simultanés imposé à la construction (voir
  /// le constructeur), ou `null`.
  final int? _plafondSimultanes;

  /// Traitement de la file en cours, partagé si on le redemande.
  Future<void>? _traitement;

  /// `true` si [lancerTraitement] a été appelé pendant un traitement après
  /// sa dernière recherche d'un chapitre en attente : le traitement refait
  /// alors un passage avant de se terminer. Sans lui, un chapitre mis en
  /// file pendant la fin d'un traitement (file vue vide, suppressions
  /// échues, libération du verrou) attendrait la relance suivante.
  bool _relanceDemandee = false;

  /// Enregistrements de chapitres en cours depuis le navigateur intégré
  /// (`executerEnregistrementWeb`) : un changement du dossier des chapitres
  /// avec déplacement est refusé tant qu'il y en a un, comme pendant un
  /// téléchargement.
  int _enregistrementsWebEnCours = 0;

  /// Réveil de la boucle de la file pendant qu'elle attend la fin d'un
  /// chapitre : complété par [lancerTraitement] (chapitre ajouté, réglage du
  /// nombre de téléchargements simultanés changé) pour qu'un emplacement
  /// libre soit rempli sans attendre la fin des chapitres en cours.
  Completer<void>? _reveil;

  /// `true` dès que le verrou de la file a été repris par l'autre isolat
  /// pendant le traitement en cours : tous les chapitres en cours
  /// s'arrêtent à leur page suivante (et pas seulement celui qui l'a vu), et
  /// aucun autre n'est commencé. Remis à `false` au début de chaque
  /// traitement.
  bool _verrouPerdu = false;

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

  /// Valeur du réglage « Archive complète » lors du dernier
  /// [appliquerReglesATous] de cette session (`null` avant le premier) :
  /// sert à reconnaître une désactivation.
  // LIMITE : en mémoire ; une désactivation suivie d'un arrêt de
  // l'application avant l'application des règles n'est pas reconnue au
  // démarrage suivant (les téléchargements en trop restent alors en file).
  bool? _archiveCompleteAppliquee;

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
      Journal.actuel.erreur(
        CategorieJournal.stockage,
        'Contrôle des archives impossible',
        erreur: erreur,
        pile: pile,
      );
    }
    await appliquerReglesATous();
  }

  /// Remet à « non téléchargé » les chapitres marqués téléchargés dont
  /// l'archive n'est plus sur le disque (fichier effacé à la main, chemin
  /// enregistré invalide) et renvoie leur nombre.
  ///
  /// Rien n'est modifié si le dossier des chapitres est inaccessible (NAS
  /// éteint, lecteur réseau déconnecté, support démonté), s'il le devient
  /// pendant le contrôle, si le dossier a été changé pendant cette session
  /// ou si un déplacement des archives est resté inachevé : un dossier
  /// injoignable n'est pas une archive manquante.
  ///
  /// Sans cela, le lecteur proposerait une lecture hors-ligne impossible et
  /// les règles ne retéléchargeraient jamais ces chapitres. Aucun réseau :
  /// une vérification d'existence de fichier par chapitre.
  Future<int> reparerArchivesManquantes() async {
    // Dossier changé pendant cette session : la base serait comparée à
    // l'ancien dossier, qui ne contient plus (ou plus pour longtemps) les
    // archives.
    if (_dossierChange) return 0;
    // Déplacement inachevé : une partie des archives est dans le nouveau
    // dossier ; elles seraient vues comme perdues ici.
    if (await _deplacementInacheve()) return 0;
    // Dossier racine injoignable : support amovible démonté, NAS éteint,
    // partage réseau déconnecté. Toutes les archives sembleraient perdues
    // alors qu'elles reviendront avec le support : on ne touche à rien
    // (sinon tous les chapitres seraient retéléchargés). Pour un dossier
    // choisi par le client, le fichier repère doit aussi être présent (un
    // point de montage vide n'est pas le NAS).
    if (!await _stockage.estDossierRacineAccessible()) {
      await _actualiserAcces();
      return 0;
    }
    final telecharges = await _depotChapitres.chargerChapitresTelecharges();
    // Dossier choisi par le client (lecteur réseau, NAS) : un partage
    // instable peut répondre « fichier absent » par moments. Les chapitres
    // manquants d'affilée y sont donc mis en attente, et écrits seulement
    // quand une archive présente plus loin prouve que le partage répond ; une
    // trop longue suite de manquants arrête tout sans rien écrire.
    final personnalise = _stockage.estPersonnalise;
    final enAttente = <int>[];
    var nombre = 0;
    // `false` si le contrôle a été interrompu (dossier perdu, trop de
    // manquants d'affilée) : les chapitres en attente ne sont pas écrits.
    var termine = true;
    for (final chapitre in telecharges) {
      final id = chapitre.id;
      if (id == null) continue;
      try {
        final contexte = await _chargerContexte(id);
        if (contexte == null) continue;
        var existe = await _archivePresente(contexte);
        if (existe == null) {
          termine = false;
          break;
        }
        // Nouveau contrôle juste avant d'écrire : pour le dossier par défaut,
        // `estTelecharge` ne distingue pas un fichier absent d'un support
        // retiré à l'instant.
        if (!existe && !await _stockage.estDossierRacineAccessible()) {
          await _actualiserAcces();
          termine = false;
          break;
        }
        // Partage réseau : second contrôle de l'archive (le repère du
        // dossier vient d'être revérifié juste au-dessus).
        if (!existe && personnalise) {
          existe = await _archivePresente(contexte);
          if (existe == null) {
            termine = false;
            break;
          }
        }
        if (!personnalise) {
          if (!existe) {
            await _marquerArchiveManquante(id);
            nombre++;
          }
          continue;
        }
        if (existe) {
          // Le partage répond : les manquants précédents sont bien perdus.
          nombre += await _marquerArchivesManquantes(enAttente);
          enAttente.clear();
          continue;
        }
        enAttente.add(id);
        if (enAttente.length > nombreMaximalArchivesManquantesDAffilee) {
          Journal.actuel.avertissement(
            CategorieJournal.stockage,
            'Contrôle des archives arrêté : plus de '
            '$nombreMaximalArchivesManquantesDAffilee archives manquantes '
            "d'affilée sur ${_stockage.dossierRacine} (partage instable ?)",
          );
          termine = false;
          break;
        }
      } catch (erreur) {
        // Un chapitre illisible ne doit pas empêcher le contrôle des autres.
        Journal.actuel.avertissement(
          CategorieJournal.stockage,
          "Contrôle de l'archive du chapitre n°$id impossible",
          erreur: erreur,
        );
      }
    }
    // LIMITE : sur un dossier personnalisé, plus de
    // [nombreMaximalArchivesManquantesDAffilee] archives réellement effacées
    // à la main d'affilée ne sont pas réparées (contrôle arrêté à chaque
    // démarrage) ; le lecteur signale alors ces chapitres illisibles.
    if (termine) {
      nombre += await _marquerArchivesManquantes(enAttente);
    }
    if (nombre > 0) {
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        '$nombre archive(s) manquante(s) : chapitres remis à « non '
        'téléchargé »',
      );
      _signaler();
    }
    return nombre;
  }

  /// `true` si l'archive du chapitre est présente, `false` si elle manque
  /// (ou si son chemin enregistré est invalide), `null` si le dossier des
  /// chapitres a disparu pendant le contrôle (NAS éteint entre deux
  /// chapitres) : il faut alors arrêter tout le contrôle sans rien modifier.
  Future<bool?> _archivePresente(_ContexteChapitre contexte) async {
    try {
      return await _stockage.estTelecharge(contexte.titre, contexte.chapitre);
    } on ErreurStockage catch (erreur) {
      if (erreur.estDossierInaccessible) {
        await _actualiserAcces(nature: erreur.nature);
        return null;
      }
      // Chemin enregistré invalide : l'archive est introuvable.
      return false;
    }
  }

  /// Remet à « non téléchargé » les chapitres [ids] dont l'archive manque
  /// (voir [_marquerArchiveManquante]) et renvoie le nombre de réussites.
  Future<int> _marquerArchivesManquantes(List<int> ids) async {
    var nombre = 0;
    for (final id in ids) {
      try {
        await _marquerArchiveManquante(id);
        nombre++;
      } catch (erreur) {
        Journal.actuel.avertissement(
          CategorieJournal.stockage,
          'Archive manquante du chapitre n°$id non notée',
          erreur: erreur,
        );
      }
    }
    return nombre;
  }

  /// Remet un chapitre dont l'archive manque à « non téléchargé ».
  Future<void> _marquerArchiveManquante(int id) async {
    await _depotChapitres.enregistrerArchive(id, null);
    // Une ligne « terminé » restée dans la file empêcherait les règles de
    // remettre ce chapitre en file (elles ne relancent qu'un échec) : on la
    // retire pour qu'il soit retéléchargé s'il est voulu.
    final ligne = await _depotTelechargements.chargerParChapitre(id);
    if (ligne?.id != null && ligne!.statut == StatutTelechargement.termine) {
      await _depotTelechargements.supprimerTelechargement(ligne.id!);
    }
  }

  /// Après un déplacement avec conflits : remet à « non téléchargé » les
  /// chapitres dont l'archive est restée dans l'ancien dossier parce qu'un
  /// fichier **différent** occupait déjà son nom dans le nouveau
  /// ([cheminsEnConflit], chemins relatifs comme `nom_archive`). Sans cela,
  /// au prochain démarrage, le lecteur ouvrirait ce fichier étranger.
  /// Renvoie le nombre de chapitres remis à zéro.
  ///
  /// Une fois `nom_archive` effacé, le prochain téléchargement choisit un
  /// nom libre (`ch1.fr.2.zip`…) : le fichier étranger n'est jamais
  /// remplacé. Les couvertures en conflit ne concernent aucun chapitre.
  /// Lève l'erreur de la base : l'appelant ne doit pas enregistrer le
  /// nouveau dossier tant que ces chapitres pointent vers le fichier
  /// étranger.
  Future<int> _oublierArchivesEnConflit(List<String> cheminsEnConflit) async {
    if (cheminsEnConflit.isEmpty) return 0;
    final conflits = cheminsEnConflit.toSet();
    var nombre = 0;
    for (final chapitre
        in await _depotChapitres.chargerChapitresTelecharges()) {
      final id = chapitre.id;
      if (id == null) continue;
      var nom = chapitre.nomArchive;
      if (nom == null) {
        // Chapitre téléchargé avant la migration 4 : nom calculé.
        final contexte = await _chargerContexte(id);
        if (contexte == null) continue;
        nom = StockageTelechargements.nomArchiveDuChapitre(
          contexte.titre,
          contexte.chapitre,
        );
      }
      if (!conflits.contains(nom)) continue;
      await _marquerArchiveManquante(id);
      nombre++;
    }
    if (nombre > 0) _signaler();
    return nombre;
  }

  /// `true` si un déplacement des archives est en cours (changement de
  /// dossier demandé dans cette session) ou resté inachevé (repère en base,
  /// posé par cet isolat ou par l'autre) : aucune archive ne doit alors être
  /// supprimée, ni aucun chapitre téléchargé, dans l'ancien dossier.
  Future<bool> _deplacementEnCours() async =>
      _changementDossierEnCours || await _deplacementInacheve();

  /// Message des suppressions manuelles refusées pendant un déplacement.
  static const String _messageDeplacementEnCours =
      'Les chapitres sont en cours de déplacement vers un autre dossier : '
      'terminez (ou abandonnez) ce déplacement dans les Paramètres avant de '
      'supprimer des chapitres téléchargés.';

  /// Refuse une suppression manuelle d'archive pendant un déplacement
  /// ([_deplacementEnCours]) : l'archive est peut-être déjà copiée dans le
  /// nouveau dossier, l'effacer de l'ancien ne la supprimerait pas vraiment
  /// et marquerait à tort le chapitre « non téléchargé ».
  Future<void> _verifierAucunDeplacement() async {
    if (await _deplacementEnCours()) {
      throw const ErreurService(_messageDeplacementEnCours);
    }
  }

  /// `true` si le dossier des chapitres enregistré dans les réglages n'est
  /// plus celui de cette instance : le dossier a été changé depuis sa
  /// création (tâche de fond Android lancée juste avant le changement, ou
  /// autre isolat). Ses téléchargements iraient alors dans l'ancien
  /// dossier. Sans dépôt des paramètres, ce contrôle n'est pas fait. En cas
  /// de doute (base illisible), répond `true` : la file attendra.
  Future<bool> _dossierRegleChange() async {
    final depot = _depotParametres;
    if (depot == null) return false;
    try {
      final regle =
          (await depot.chargerTexte(ServiceParametres.cleDossierChapitres))
              ?.trim() ??
          '';
      if (regle.isEmpty) return _stockage.estPersonnalise;
      return !_stockage.estPersonnalise ||
          !chemins.equals(
            chemins.normalize(regle),
            chemins.normalize(_stockage.dossierRacine.trim()),
          );
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.parametres,
        'Dossier des chapitres réglé illisible',
        erreur: erreur,
      );
      return true;
    }
  }

  /// Avant chaque chapitre de la file : `false` si le dossier réglé a
  /// changé ([_dossierRegleChange]) ou si un déplacement est en cours
  /// ([_deplacementEnCours]). La file s'arrête alors sans échec ni nouvel
  /// essai : le prochain démarrage (ou l'abandon du déplacement) la relance
  /// sur le bon dossier.
  Future<bool> _dossierStablePourLaFile() async {
    if (await _deplacementEnCours()) return false;
    return !await _dossierRegleChange();
  }

  /// `true` si un déplacement des archives vers un autre dossier a commencé
  /// sans se terminer ([ServiceParametres.cleDeplacementDossierEnCours]).
  /// En cas de doute (base illisible), répond `true` : mieux vaut sauter un
  /// contrôle que remettre à tort des chapitres à « non téléchargé ».
  Future<bool> _deplacementInacheve() async {
    final depot = _depotParametres;
    if (depot == null) return false;
    try {
      final cible = await depot.chargerTexte(
        ServiceParametres.cleDeplacementDossierEnCours,
      );
      return cible != null && cible.trim().isNotEmpty;
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.parametres,
        'Repère de déplacement des archives illisible',
        erreur: erreur,
      );
      return true;
    }
  }

  // --------------------------------------------- Accès au dossier des chapitres

  /// `true` si le dossier des chapitres, **choisi par le client**, est
  /// injoignable en ce moment. Le dossier par défaut n'est jamais considéré
  /// comme injoignable : il est créé à la première écriture.
  Future<bool> _dossierInjoignable() async =>
      _stockage.estPersonnalise &&
      !await _stockage.estDossierRacineAccessible();

  /// Contrôle le dossier des chapitres, met à jour [_accesDossier] et
  /// prévient l'interface s'il a changé. Quand le dossier redevient
  /// accessible, la file est relancée (reprise normale des téléchargements).
  ///
  /// [nature] : nature connue du problème (erreur d'une écriture), sinon
  /// déduite du chemin. Ne lève jamais.
  Future<AccesDossierChapitres> _actualiserAcces({
    NatureErreurStockage? nature,
  }) async {
    bool injoignable;
    try {
      injoignable = await _dossierInjoignable();
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        'Contrôle du dossier des chapitres impossible',
        erreur: erreur,
      );
      injoignable = _stockage.estPersonnalise;
    }
    final ancien = _accesDossier;
    final nouveau = injoignable
        ? AccesDossierChapitres.inaccessible(
            _stockage.dossierRacine,
            estPersonnalise: _stockage.estPersonnalise,
            nature: _natureInaccessible(nature ?? ancien.nature),
          )
        : AccesDossierChapitres.accessible(
            _stockage.dossierRacine,
            estPersonnalise: _stockage.estPersonnalise,
          );
    _accesDossier = nouveau;
    if (nouveau != ancien) {
      // Seuls les changements d'état sont notés : le contrôle est refait
      // avant chaque chapitre et toutes les 2 minutes quand le NAS est
      // éteint, une ligne à chaque fois noierait le journal.
      if (nouveau.estAccessible) {
        Journal.actuel.info(
          CategorieJournal.stockage,
          'Dossier des chapitres accessible : ${nouveau.chemin}',
        );
      } else {
        Journal.actuel.avertissement(
          CategorieJournal.stockage,
          'Dossier des chapitres inaccessible (${nouveau.nature?.name}) : '
          '${nouveau.chemin}, téléchargements en pause',
        );
      }
      _signaler();
      // Retour du NAS : les téléchargements en attente repartent sans
      // attendre la prochaine action du client.
      if (nouveau.estAccessible && !_changements.isClosed) {
        unawaited(lancerTraitement());
      }
    }
    return nouveau;
  }

  /// Nature à afficher pour un dossier injoignable : celle de l'erreur si
  /// elle décrit une absence du dossier, sinon « partage réseau » pour un
  /// chemin réseau (`\\nas\…`) et « dossier introuvable » pour le reste.
  NatureErreurStockage _natureInaccessible(NatureErreurStockage? connue) {
    if (connue == NatureErreurStockage.dossierInaccessible ||
        connue == NatureErreurStockage.reseauIndisponible) {
      return connue!;
    }
    final chemin = _stockage.dossierRacine;
    return chemin.startsWith(r'\\') || chemin.startsWith('//')
        ? NatureErreurStockage.reseauIndisponible
        : NatureErreurStockage.dossierInaccessible;
  }

  /// Avant de commencer un chapitre : `false` si le dossier des chapitres
  /// est injoignable. La file s'arrête alors sans toucher aux
  /// téléchargements en attente (ni échec, ni compteur) et un seul nouvel
  /// essai est prévu ([attenteNouvelEssaiDossierInaccessible]) : un simple
  /// contrôle du disque, sans requête vers les sites.
  Future<bool> _dossierPretPourLaFile() async {
    final acces = await _actualiserAcces();
    if (acces.estAccessible) return true;
    _planifierNouvelEssai(attenteNouvelEssaiDossierInaccessible);
    return false;
  }

  /// Refuse la lecture et la suppression d'archives quand elles ont été
  /// déplacées vers un autre dossier pendant cette session : les services
  /// pointent encore sur l'ancien dossier jusqu'au redémarrage.
  void _verifierArchivesSurPlace() {
    if (_archivesDeplacees) {
      throw const ErreurService(_messageRedemarrage);
    }
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
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Reprise des chapitres gardés impossible',
        erreur: erreur,
        pile: pile,
      );
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
  /// base à maintenant + [delaiProtectionLecture] (24 h, en arrière-plan,
  /// sans bloquer l'ouverture du lecteur). Ce délai ne suit pas le réglage
  /// de conservation : voir [delaiProtectionLecture].
  ///
  /// LIMITE : une lecture qui dure plus de 24 h sans rouvrir le chapitre
  /// reste exposée côté tâche de fond ; et une date posée par les règles
  /// **après** l'ouverture vaut maintenant + la durée de conservation réglée
  /// (au moins 1 h) : avec un réglage court, la tâche de fond Android peut
  /// effacer un chapitre ouvert dont la lecture dure plus longtemps.
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
        _maintenant().add(delaiProtectionLecture),
      )) {
        _signaler();
      }
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Suppression prévue du chapitre n°$idChapitre non repoussée',
        erreur: erreur,
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

  /// Applique les règles à tous les titres favoris et suivis (à **tous** les
  /// titres de la bibliothèque si « Archive complète » est activée,
  /// `ServiceParametres.chargerArchiveComplete`), puis lance le traitement
  /// de la file (sans l'attendre).
  ///
  /// Un titre en erreur est journalisé et n'empêche pas les autres ; la file
  /// est lancée même si la lecture des listes échoue (l'erreur remonte alors
  /// à l'appelant).
  ///
  /// À appeler après un changement du réglage « Archive complète » : à
  /// l'activation, tous les chapitres manquants sont mis en file et les
  /// suppressions prévues annulées ; à la désactivation, les archives que
  /// les règles ordinaires ne veulent plus passent en suppression différée,
  /// et, une seule fois, toute la bibliothèque est recalculée pour retirer
  /// de la file les téléchargements automatiques qui ne sont plus voulus
  /// (titres sans liste ou des seules listes du client).
  Future<void> appliquerReglesATous() async {
    // Avant les règles : un chapitre gardé avec l'ancienne version ne doit
    // pas recevoir de suppression prévue.
    await _reprendreAnciensGardes();
    try {
      final ids = <int>{};
      final archiveComplete = await _serviceParametres.chargerArchiveComplete();
      // Désactivation dans cette session : les titres ni favoris ni suivis
      // gardaient en file tous leurs chapitres ; sans ce recalcul, la file
      // les téléchargerait quand même (des centaines de requêtes non
      // voulues, PLAYBOOK.md section 10). Les demandes manuelles de la
      // session restent (`_demandesManuelles`).
      final vientDEtreDesactivee =
          _archiveCompleteAppliquee == true && !archiveComplete;
      if (archiveComplete || vientDEtreDesactivee) {
        // Archive complète : toute la bibliothèque, y compris les titres
        // sans liste et ceux des listes du client. La file reste traitée
        // au plus N chapitres à la fois, avec le délai par domaine de
        // `ClientHttpPoli` : le volume ne change rien au rythme des requêtes.
        // Juste désactivée : même parcours, sans réseau (calcul en base),
        // pour vider la file de ce qui n'est plus voulu.
        final titres = await _depotTitres.chargerTitres();
        ids.addAll(titres.map((titre) => titre.id).whereType<int>());
      }
      for (final nomListe in <String>[nomListeFavoris, nomListeSuivis]) {
        final liste = await _depotListes.chargerListeParNom(nomListe);
        if (liste?.id == null) continue;
        final titres = await _depotTitres.chargerTitres(idListe: liste!.id);
        ids.addAll(titres.map((titre) => titre.id).whereType<int>());
      }
      // Retenu seulement une fois les titres lus : si la lecture a échoué,
      // la désactivation sera encore reconnue à l'appel suivant.
      _archiveCompleteAppliquee = archiveComplete;
      var aTelecharger = 0;
      var aSupprimer = 0;
      var enEchec = 0;
      for (final idTitre in ids) {
        try {
          final plan = await _appliquerRegles(idTitre, supprimerEchues: false);
          aTelecharger += plan.idsATelecharger.length;
          aSupprimer += plan.idsASupprimer.length;
        } catch (erreur, pile) {
          // Par exemple une écriture refusée pendant que l'autre isolat
          // écrit : ce titre sera repris à la prochaine application.
          enEchec++;
          Journal.actuel.avertissement(
            CategorieJournal.telechargement,
            'Règles du titre n°$idTitre non appliquées',
            erreur: erreur,
            pile: pile,
          );
        }
      }
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Règles appliquées à ${ids.length} titre(s)'
        '${archiveComplete ? ' (archive complète)' : ''} : '
        '$aTelecharger à télécharger, $aSupprimer à supprimer'
        '${enEchec > 0 ? ', $enEchec titre(s) en échec' : ''}',
      );
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
  /// suite : leur suppression est prévue après la durée de conservation
  /// réglée par le client (`ServiceParametres.chargerDelaiSuppression`, 24 h
  /// par défaut ; `Chapitre.dateSuppressionPrevue`), et
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
    final idsSourcesLiees = await _chargerIdsSourcesLiees(idTitre, idSource);
    final politique = PolitiqueTelechargement(
      reglages: await _serviceParametres.chargerReglagesTelechargement(),
      // Même résolution que ServiceBibliotheque.languesPourTitre : langues
      // propres au titre, sinon de la source si réglées (titre à un seul
      // site), sinon réglage général du client. Pour un titre à plusieurs
      // sites, changer de site principal ne doit pas changer ses langues
      // (relecture B1 : archives anglaises effacées).
      languesPreferees: ServiceBibliotheque.languesPreferees(
        source,
        general: await _serviceParametres.chargerLangues(),
        titre: titre,
        plusieursSites: (idsSourcesLiees?.length ?? 1) > 1,
      ),
      // Étape 8 : une version par numéro, le site principal départageant
      // deux versions équivalentes ; les chapitres d'un site retiré ne sont
      // plus suivis (leurs archives passent en suppression différée).
      idSourcePrincipale: idSource,
      idsSourcesLiees: idsSourcesLiees,
      // Relu à chaque calcul (une lecture en base) : la tâche de fond
      // Android voit ainsi le choix fait dans l'application, sans cache à
      // invalider entre les isolats.
      archiveComplete: await _serviceParametres.chargerArchiveComplete(),
    );
    final chapitres = await _depotChapitres.chargerChapitres(idTitre);
    final plan = politique.calculer(
      chapitres,
      estFavori: noms.contains(nomListeFavoris),
      estSuivi: noms.contains(nomListeSuivis),
    );
    return (plan: plan, chapitres: chapitres);
  }

  /// Sites liés et lus du titre (principal compris), ou `null` sans dépôt
  /// des sites (pas de filtre par site).
  Future<Set<int>?> _chargerIdsSourcesLiees(
    int idTitre,
    int idSourcePrincipale,
  ) async {
    final depot = _depotTitresSources;
    if (depot == null) return null;
    final liens = await depot.chargerLiensTitre(idTitre);
    // Un lien seul (tâche T4) compte comme un site retiré : ses chapitres
    // restants (lus ou téléchargés avant le passage en lien seul) ne sont
    // plus suivis et leurs archives suivent la règle des 24 h.
    return <int>{
      idSourcePrincipale,
      for (final lien in liens)
        if (!lien.estLienSeul) lien.idSource,
    };
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
    var misEnFile = 0;
    for (final idChapitre in plan.idsATelecharger) {
      if (await _mettreEnFileAutomatiquement(idChapitre)) misEnFile++;
    }
    var retiresDeLaFile = 0;
    var suppressionsPrevues = 0;
    var suppressionsAnnulees = 0;
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
        retiresDeLaFile++;
      }
    }
    // Suppression différée (décision du client) : une date est posée pour
    // les archives qui ne sont plus voulues, et retirée pour celles qui le
    // redeviennent. Une date déjà posée n'est pas repoussée : sinon chaque
    // application des règles relancerait le compte à rebours affiché.
    final aSupprimer = plan.idsASupprimer.toSet();
    // Durée réglée par le client (Paramètres), lue seulement si une nouvelle
    // suppression est à prévoir : la plupart des applications des règles
    // n'en prévoient aucune, inutile de relire le réglage pour chaque titre.
    // Les suppressions déjà prévues gardent leur date (voir plus haut).
    DateTime? echeance;
    for (final chapitre in chapitres) {
      final id = chapitre.id;
      if (id == null || !chapitre.estTelecharge) continue;
      // Choix « Garder » du client (`est_garde`) : jamais supprimé par les
      // règles. Un téléchargement manuel hors des règles (autre langue,
      // chapitre ancien) n'est pas exempté : le compte à rebours affiché
      // laisse au client le temps de le garder.
      final voulu = !aSupprimer.contains(id) || chapitre.estGarde;
      if (!voulu && chapitre.dateSuppressionPrevue == null) {
        echeance ??= _maintenant().add(
          await _serviceParametres.chargerDelaiSuppression(),
        );
        await _depotChapitres.planifierSuppression(id, echeance);
        suppressionsPrevues++;
      } else if (voulu && chapitre.dateSuppressionPrevue != null) {
        await _depotChapitres.planifierSuppression(id, null);
        suppressionsAnnulees++;
      }
    }
    // Une ligne seulement quand quelque chose change : les règles sont
    // appliquées à chaque lecture et à chaque démarrage, pour tous les
    // titres ; un titre déjà à jour ne mérite qu'une ligne de débogage.
    final aChange =
        misEnFile +
            retiresDeLaFile +
            suppressionsPrevues +
            suppressionsAnnulees >
        0;
    Journal.actuel.journaliser(
      aChange ? NiveauJournal.info : NiveauJournal.debogage,
      CategorieJournal.telechargement,
      'Règles du titre n°$idTitre : ${plan.idsATelecharger.length} à '
      'télécharger, ${plan.idsASupprimer.length} à supprimer ; $misEnFile '
      'mis en file, $retiresDeLaFile retiré(s) de la file, '
      '$suppressionsPrevues suppression(s) prévue(s), $suppressionsAnnulees '
      'annulée(s)',
    );
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
    // Dossier changé pendant cette session (les archives sont ou seront
    // ailleurs) ou injoignable : effacer échouerait, ou effacerait au mauvais
    // endroit en marquant le chapitre « non téléchargé ». Les échéances
    // restent en base et seront traitées plus tard.
    if (_dossierChange || await _dossierInjoignable()) return 0;
    // Déplacement en cours ou inachevé : l'archive est peut-être déjà dans
    // le nouveau dossier ; l'effacer de l'ancien laisserait sa copie et
    // marquerait le chapitre « non téléchargé ». Les échéances attendent.
    if (await _deplacementEnCours()) return 0;
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
        // de la date (jusqu'à 30 jours plus tôt), le client a pu changer ses
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
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Suppression prévue du chapitre n°$id impossible',
          erreur: erreur,
        );
      }
    }
    Journal.actuel.info(
      CategorieJournal.telechargement,
      'Suppressions échues : $nombre archive(s) supprimée(s), $annulees '
      'annulée(s) sur ${echues.length}',
    );
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
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Suppressions prévues non faites',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  /// Supprime tout de suite l'archive d'un chapitre (bouton « Supprimer
  /// maintenant » d'une suppression prévue, ou suppression demandée par le
  /// client) : même effet que [supprimerTelechargement].
  Future<void> supprimerMaintenant(int idChapitre) =>
      supprimerTelechargement(idChapitre);

  /// Suppression groupée en cours : un double clic (ou un second écran)
  /// attend la même au lieu d'en lancer une seconde.
  Future<int>? _suppressionGroupeeEnCours;

  /// Supprime tout de suite les archives de **toutes** les suppressions
  /// prévues (bouton « Supprimer tous les chapitres à supprimer » de
  /// l'onglet Téléchargements) et renvoie le nombre d'archives supprimées.
  ///
  /// Mêmes règles que [supprimerMaintenant] pour chaque chapitre, avec en
  /// plus :
  /// - un chapitre ouvert dans le lecteur ([protegerChapitre]) est épargné :
  ///   sa suppression reste prévue et sera faite plus tard ;
  /// - rien n'est supprimé, et une [ErreurService] au message clair est
  ///   levée, si un déplacement des archives est en cours ou inachevé, si
  ///   le dossier vient d'être changé (redémarrage demandé) ou si le dossier
  ///   des chapitres est inaccessible (NAS éteint) ;
  /// - un chapitre en erreur est journalisé et n'empêche pas les autres ;
  ///   si aucun n'a pu être supprimé, la première erreur est levée.
  ///
  /// Un second appel pendant la suppression partage la même.
  Future<int> supprimerToutesSuppressionsPrevues() =>
      _suppressionGroupeeEnCours ??= _supprimerToutesSuppressionsPrevues()
          .whenComplete(() => _suppressionGroupeeEnCours = null);

  Future<int> _supprimerToutesSuppressionsPrevues() async {
    // Contrôles avant toute écriture : en cas de refus, aucune archive n'est
    // touchée (pas de suppression à moitié faite).
    _verifierArchivesSurPlace();
    await _verifierAucunDeplacement();
    // NAS éteint : chaque effacement échouerait l'un après l'autre (attente
    // réseau à chaque fois). Le bandeau du dossier est mis à jour au passage.
    final acces = await _actualiserAcces();
    if (!acces.estAccessible) {
      throw ErreurService(
        "Aucun chapitre n'a été supprimé. ${acces.message ?? ''}".trim(),
      );
    }
    final prevues = await _depotChapitres.chargerSuppressionsPrevues();
    var nombre = 0;
    var epargnes = 0;
    var echecs = 0;
    Object? premiereErreur;
    StackTrace? premierePile;
    // Boucle bornée par la liste lue (aucune requête réseau : disque et base
    // seulement).
    for (final chapitre in prevues) {
      final id = chapitre.id;
      if (id == null) continue;
      // Chapitre lu en ce moment : l'effacer ferait échouer les pages
      // suivantes du lecteur. Sa date reste : il sera supprimé plus tard.
      if (estProtege(id)) {
        epargnes++;
        continue;
      }
      try {
        await supprimerTelechargement(id, signalerChangement: false);
        nombre++;
      } catch (erreur, pile) {
        echecs++;
        premiereErreur ??= erreur;
        premierePile ??= pile;
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Suppression immédiate du chapitre n°$id impossible',
          erreur: erreur,
        );
        // Dossier perdu en cours de route (NAS éteint entre deux
        // chapitres) : inutile d'essayer les suivants un par un.
        if (!(await _actualiserAcces()).estAccessible) break;
      }
    }
    Journal.actuel.info(
      CategorieJournal.telechargement,
      'Suppression de toutes les suppressions prévues : $nombre archive(s) '
      'supprimée(s), $epargnes épargnée(s) (chapitre ouvert), $echecs '
      'échec(s) sur ${prevues.length}',
    );
    if (nombre > 0 || echecs > 0) _signaler();
    final erreur = premiereErreur;
    if (nombre == 0 && erreur != null) {
      Error.throwWithStackTrace(erreur, premierePile ?? StackTrace.current);
    }
    return nombre;
  }

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
  /// suppression est de nouveau prévue, après la durée de conservation
  /// réglée (24 h par défaut).
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
  /// Renvoie `true` si la file a changé (pour le bilan du journal).
  Future<bool> _mettreEnFileAutomatiquement(int idChapitre) async {
    // Relu juste avant : l'autre isolat a pu le terminer depuis le calcul du
    // plan.
    final chapitre = await _depotChapitres.chargerChapitre(idChapitre);
    // Chapitre hébergé ailleurs (R4) : jamais téléchargeable. La politique
    // l'écarte déjà ; contrôle redit ici car il a pu devenir externe depuis
    // le calcul du plan.
    if (chapitre == null || chapitre.estTelecharge || chapitre.estExterne) {
      return false;
    }
    final existant = await _depotTelechargements.chargerParChapitre(idChapitre);
    if (existant == null) {
      await _depotTelechargements.ajouterEnFile(idChapitre);
      Journal.actuel.debogage(
        CategorieJournal.telechargement,
        'Chapitre n°$idChapitre mis en file (règles)',
      );
      return true;
    }
    // Seul un échec est relancé : « en attente » et « en cours » sont déjà
    // pris en charge, et « terminé » signifie qu'un autre traitement vient de
    // finir (l'état du chapitre sera à jour au prochain calcul).
    if (existant.statut != StatutTelechargement.echec) return false;
    // Pas de relance sans fin d'un chapitre que le site refuse.
    if ((_echecs[idChapitre] ?? 0) >= nombreMaximalEchecsAutomatiques) {
      return false;
    }
    await _depotTelechargements.enregistrerStatut(
      existant.id!,
      StatutTelechargement.enAttente,
    );
    Journal.actuel.debogage(
      CategorieJournal.telechargement,
      'Chapitre n°$idChapitre relancé après un échec (règles)',
    );
    return true;
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
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Chapitre n°$idChapitre mis en file (demande manuelle)',
      );
    } else if (existant.statut == StatutTelechargement.echec) {
      await _depotTelechargements.enregistrerStatut(
        existant.id!,
        StatutTelechargement.enAttente,
      );
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Chapitre n°$idChapitre relancé (demande manuelle)',
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
  ///
  /// Lève une [ErreurService] pendant un déplacement des archives (en cours
  /// ou inachevé) : archives et couverture sont peut-être déjà copiées
  /// ailleurs.
  Future<void> supprimerTitre(int idTitre) async {
    _verifierArchivesSurPlace();
    await _verifierAucunDeplacement();
    final chapitres = await _depotChapitres.chargerChapitres(idTitre);
    var archives = 0;
    for (final chapitre in chapitres) {
      final id = chapitre.id;
      if (id != null && chapitre.estTelecharge) {
        await supprimerTelechargement(id, signalerChangement: false);
        archives++;
      }
    }
    final titre = await _depotTitres.chargerTitre(idTitre);
    if (titre != null) {
      // Après les archives : le dossier du titre n'est retiré que vide.
      await _stockage.supprimerCouverture(titre);
    }
    await _depotTitres.supprimerTitre(idTitre);
    Journal.actuel.info(
      CategorieJournal.bibliotheque,
      'Titre n°$idTitre${titre == null ? '' : ' « ${titre.nom} »'} supprimé '
      'avec $archives archive(s)',
    );
    _signaler();
  }

  /// Supprime l'archive d'un chapitre et sa ligne de file.
  ///
  /// Si le chapitre est en cours de téléchargement, ce dernier s'arrête à la
  /// page suivante et son archive partielle est effacée (annulation). Un
  /// chapitre seulement en file (jamais téléchargé) perd sa ligne de file
  /// sans qu'aucune archive ne soit touchée.
  ///
  /// Lève une [ErreurService] (message clair) si le chapitre a une archive
  /// et qu'un déplacement des archives est en cours ou resté inachevé :
  /// l'archive est peut-être déjà copiée dans le nouveau dossier. Retirer de
  /// la file un chapitre sans archive reste possible.
  Future<void> supprimerTelechargement(
    int idChapitre, {
    bool signalerChangement = true,
  }) async {
    _verifierArchivesSurPlace();
    final avant = await _depotChapitres.chargerChapitre(idChapitre);
    if (avant != null && (avant.estTelecharge || avant.nomArchive != null)) {
      await _verifierAucunDeplacement();
    }
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
    if (avant != null && (avant.estTelecharge || avant.nomArchive != null)) {
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Archive du chapitre n°$idChapitre supprimée'
        '${avant.dateSuppressionPrevue != null ? ' (suppression prévue)' : ''}',
      );
    } else if (ligne != null) {
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Chapitre n°$idChapitre retiré de la file',
      );
    }
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
    // Lecture d'une archive : refusée si les archives viennent d'être
    // déplacées (message clair plutôt que « pas téléchargé »).
    _verifierArchivesSurPlace();
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
    // Étape 8 : le contenu d'un chapitre se demande au site d'où il vient
    // (un site secondaire peut être d'un autre type que le principal) ; un
    // chapitre sans site connu vient du site principal.
    final idSource = chapitre.idSource ?? titre?.idSource;
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
  ///
  /// File en pause (changement du dossier des chapitres) : rien n'est lancé.
  ///
  /// Pendant un traitement, l'appel le réveille : le nombre de
  /// téléchargements simultanés est relu et les emplacements libres sont
  /// remplis tout de suite. À appeler après
  /// `ServiceParametres.enregistrerTelechargementsSimultanes`.
  Future<void> lancerTraitement() {
    final enCours = _traitement;
    if (enCours != null) {
      // Demande notée même si la boucle est en train de finir : elle sera
      // servie par un nouveau passage ([_traiterFileTantQueDemande]).
      _relanceDemandee = true;
      _reveiller();
      return enCours;
    }
    if (_enPause) {
      return Future<void>.value();
    }
    _relance?.cancel();
    _relance = null;
    final nouveau = _traiterFileTantQueDemande().whenComplete(() {
      _traitement = null;
      _signaler();
    });
    _traitement = nouveau;
    return nouveau;
  }

  /// Traite la file, puis la retraite tant que [lancerTraitement] a été
  /// appelé pendant la fin du passage précédent ([_relanceDemandee]).
  ///
  /// Relance faite dans le même `Future` plutôt qu'après sa fin : celui qui
  /// attend [lancerTraitement] attend aussi le chapitre ajouté au dernier
  /// moment. Toujours borné : un passage de plus n'a lieu que si un appel
  /// est arrivé pendant le précédent (le drapeau est remis à `false` à
  /// chaque recherche d'un chapitre en attente), jamais en boucle seule.
  Future<void> _traiterFileTantQueDemande() async {
    do {
      _relanceDemandee = false;
      await _traiterFile();
    } while (_relanceDemandee && !_enPause && !_changements.isClosed);
    _relanceDemandee = false;
  }

  Future<void> _traiterFile() async {
    // Rend la main avant de commencer : `_traitement` est affecté avant
    // qu'une fin immédiate ne le remette à null.
    await Future<void>.value();
    if (_enPause) return;
    try {
      // Dossier des chapitres injoignable (NAS éteint) : la file attend, sans
      // rien demander aux sites ni compter d'échec.
      if (!await _dossierPretPourLaFile()) return;
      final verrou = await _prendreVerrou();
      if (verrou != null) {
        _planifierRelance(verrou);
        return;
      }
      try {
        _verrouPerdu = false;
        // Même contrôle qu'avant chaque chapitre, avant de toucher aux
        // archives partielles de l'ancien dossier.
        if (!await _dossierStablePourLaFile()) return;
        await _reprendreApresInterruption();
        await _traiterChapitresEnParallele();
      } finally {
        // Toujours après la fin de tous les chapitres en cours
        // (`_traiterChapitresEnParallele` les attend même en cas d'erreur) :
        // l'autre isolat ne doit pas reprendre la file pendant qu'on écrit.
        await _libererVerrou();
      }
    } catch (erreur, pile) {
      // Une erreur de base (par exemple une écriture concurrente de l'autre
      // isolat) ne doit pas remonter jusqu'à l'interface : la file sera
      // reprise au prochain lancement.
      Journal.actuel.erreur(
        CategorieJournal.telechargement,
        'Traitement de la file interrompu',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  /// Cœur de la file, verrou pris : garde jusqu'à N chapitres en cours
  /// ([_chargerLimiteSimultanes]) et commence le suivant dès qu'un
  /// emplacement se libère, jusqu'à ce que la file soit vide ou qu'un
  /// contrôle demande l'arrêt. Ne rend la main qu'une fois **tous** les
  /// chapitres commencés terminés (même si une erreur de base interrompt la
  /// boucle) : le verrou reste ainsi tenu, et renouvelé page après page,
  /// tant qu'une archive est en cours d'écriture.
  ///
  /// Les contrôles d'avant chapitre de la file à un seul chapitre sont faits
  /// avant **chaque** réservation (pause, dossier réglé ou en déplacement,
  /// verrou, dossier joignable). Quand l'un d'eux échoue, aucun chapitre
  /// n'est plus commencé ; ceux en cours se terminent (comme le chapitre en
  /// cours d'avant), sauf verrou perdu, où ils s'arrêtent à leur page
  /// suivante.
  Future<void> _traiterChapitresEnParallele() async {
    final enCours = <Future<void>>{};
    var limite = await _chargerLimiteSimultanes();
    // Ligne de début écrite au premier chapitre réservé seulement : la file
    // est relancée à chaque lecture et à chaque application des règles, une
    // ligne par relance sans rien à télécharger noierait le journal.
    var debutAnnonce = false;
    // Plus aucun chapitre ne doit être commencé (pause, dossier changé ou
    // injoignable, verrou perdu, erreur inattendue).
    var arret = false;
    // Dossier des chapitres devenu injoignable pendant un chapitre.
    var dossierPerdu = false;
    try {
      while (!_changements.isClosed) {
        // Les demandes arrivées jusqu'ici sont servies par le remplissage
        // qui suit (il relit la file) : seules les suivantes demandent un
        // nouveau passage.
        _relanceDemandee = false;
        // Remplissage des emplacements libres.
        while (!arret && enCours.length < limite) {
          // Pause demandée pendant le traitement (changement du dossier) :
          // les chapitres en cours se terminent, aucun autre n'est commencé.
          // Verrou repris par l'autre isolat (vu par un chapitre en cours) :
          // on lui laisse la file.
          if (_enPause || _verrouPerdu) {
            arret = true;
            break;
          }
          // Réglages relus avant chaque chapitre : la pause est propre à cet
          // isolat, et une tâche de fond Android lancée avant un changement
          // de dossier écrirait sinon dans l'ancien dossier (ou pendant la
          // copie). Arrêt sans échec : le chapitre reste en attente.
          if (!await _dossierStablePourLaFile()) {
            arret = true;
            break;
          }
          // Renouvelé avant chaque chapitre ; si un autre isolat a repris le
          // verrou entre-temps (le nôtre avait expiré), on lui laisse la file
          // plutôt que d'écrire les mêmes archives que lui.
          if (!await _renouvelerVerrou(verifier: true)) {
            _verrouPerdu = true;
            arret = true;
            break;
          }
          // Le NAS peut s'éteindre au milieu d'une longue file : contrôle
          // avant chaque chapitre, avant toute requête vers le site.
          if (!await _dossierPretPourLaFile()) {
            arret = true;
            break;
          }
          // Réservation atomique (en attente → en cours) : ni deux chapitres
          // en cours de ce traitement, ni les deux isolats (même s'ils se
          // croient tous deux propriétaires du verrou, voir la LIMITE plus
          // bas) ne peuvent prendre la même ligne. Les réservations de ce
          // traitement se font de plus une par une (chaque `await` ci-dessus
          // est fini avant la suivante).
          final suivant = await _depotTelechargements.reserverProchain();
          if (suivant == null) break;
          if (!debutAnnonce) {
            debutAnnonce = true;
            Journal.actuel.info(
              CategorieJournal.telechargement,
              "File de téléchargement : début, jusqu'à $limite chapitre(s) "
              'en même temps${_descriptionPlafond(limite)}',
            );
          }
          late final Future<void> tache;
          tache =
              _executerChapitre(
                suivant,
                surDossierPerdu: () {
                  dossierPerdu = true;
                  arret = true;
                },
                surErreur: () => arret = true,
              ).whenComplete(() {
                enCours.remove(tache);
              });
          enCours.add(tache);
        }
        if (enCours.isEmpty) {
          if (!arret) {
            // File vide : les suppressions prévues échues pendant le
            // traitement (qui peut durer longtemps) sont faites maintenant.
            await _supprimerArchivesEchuesSansErreur();
            await _planifierRepriseSiNecessaire();
          }
          return;
        }
        // Attente de la fin d'un chapitre, ou d'un réveil
        // ([lancerTraitement] : chapitre ajouté, réglage changé). Jamais de
        // boucle active : sans l'un ou l'autre, rien n'est relu.
        final reveil = _reveil = Completer<void>();
        await Future.any<void>(<Future<void>>[...enCours, reveil.future]);
        _reveil = null;
        if (!arret) {
          // Réglage relu à chaque emplacement libéré (une lecture en base) :
          // la jauge des Paramètres s'applique sans redémarrer la file. Une
          // baisse laisse finir les chapitres en trop sans en commencer.
          final nouvelle = await _chargerLimiteSimultanes();
          if (nouvelle != limite) {
            Journal.actuel.info(
              CategorieJournal.telechargement,
              'File de téléchargement : $limite → $nouvelle chapitre(s) en '
              'même temps${_descriptionPlafond(nouvelle)}',
            );
            limite = nouvelle;
          }
        }
      }
    } finally {
      _reveil = null;
      // Copie : chaque fin de chapitre retire sa tâche de l'ensemble.
      await Future.wait<void>(enCours.toList());
      if (dossierPerdu) {
        // Dossier devenu injoignable pendant un chapitre : la file attend
        // son retour (un seul nouvel essai prévu).
        _planifierNouvelEssai(attenteNouvelEssaiDossierInaccessible);
      }
    }
  }

  /// Télécharge un chapitre réservé, pour [_traiterChapitresEnParallele].
  /// Ne lève jamais : [surDossierPerdu] est appelé si le dossier des
  /// chapitres est devenu injoignable, [surErreur] pour une erreur
  /// inattendue (qui arrêtait toute la file quand un seul chapitre était
  /// traité à la fois : même effet ici, plus aucun chapitre n'est commencé).
  Future<void> _executerChapitre(
    Telechargement telechargement, {
    required void Function() surDossierPerdu,
    required void Function() surErreur,
  }) async {
    try {
      if (!await _telecharger(telechargement)) surDossierPerdu();
    } catch (erreur, pile) {
      surErreur();
      Journal.actuel.erreur(
        CategorieJournal.telechargement,
        'Traitement de la file interrompu (chapitre n°'
        '${telechargement.idChapitre})',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  /// Réveille la boucle de la file si elle attend (voir [_reveil]).
  void _reveiller() {
    final reveil = _reveil;
    if (reveil != null && !reveil.isCompleted) reveil.complete();
  }

  /// Nombre de chapitres à télécharger en même temps : réglage du client,
  /// ramené au plafond de l'isolat ([_plafondEffectif]). Ne lève jamais :
  /// un réglage illisible vaut la valeur par défaut.
  Future<int> _chargerLimiteSimultanes() async {
    int reglage;
    try {
      reglage = await _serviceParametres.chargerTelechargementsSimultanes();
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.parametres,
        'Nombre de téléchargements simultanés illisible',
        erreur: erreur,
      );
      reglage = telechargementsSimultanesParDefaut;
    }
    // Bornes redites ici : un faux `ServiceParametres` (ou une future
    // version) ne doit jamais lancer 0 ou 1000 chapitres.
    final borne = reglage.clamp(
      telechargementsSimultanesMinimum,
      telechargementsSimultanesMaximum,
    );
    final plafond = _plafondEffectif();
    return plafond != null && plafond < borne ? plafond : borne;
  }

  /// Plafond des téléchargements simultanés de cet isolat, ou `null`.
  ///
  /// Celui passé au constructeur s'il existe ; sinon
  /// [telechargementsSimultanesTacheDeFond] dans la tâche de fond Android,
  /// reconnue à son journal (`JournalFichier` installé avec
  /// [nomIsolatFond] avant la construction des services).
  // LIMITE : sans plafond passé au constructeur, la tâche de fond n'est
  // reconnue que par son journal ; si celui-ci n'a pas pu être ouvert, elle
  // suit le réglage du client (32 au plus). Passer
  // `plafondTelechargementsSimultanes` depuis `executerTacheDeFond`
  // (lib/main.dart) supprimerait cette dépendance.
  int? _plafondEffectif() {
    final impose = _plafondSimultanes;
    if (impose != null) {
      return impose < telechargementsSimultanesMinimum
          ? telechargementsSimultanesMinimum
          : impose;
    }
    final journal = Journal.actuel;
    if (journal is JournalFichier && journal.nomIsolat == nomIsolatFond) {
      return telechargementsSimultanesTacheDeFond;
    }
    return null;
  }

  /// Précision du journal quand [limite] vient du plafond de l'isolat.
  String _descriptionPlafond(int limite) {
    final plafond = _plafondEffectif();
    return plafond != null && limite >= plafond
        ? ' (plafond de cet isolat : $plafond)'
        : '';
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
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        'Nettoyage des archives partielles impossible',
        erreur: erreur,
      );
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
      final garde = await _renouvelerVerrou(verifier: true);
      // Partagé par tous les chapitres en cours (voir [_verrouPerdu]).
      if (!garde) _verrouPerdu = true;
      return garde;
    } catch (erreur) {
      // Un renouvellement manqué (base momentanément occupée) ne doit pas
      // faire échouer le chapitre : le verrou reste valable jusqu'à son
      // expiration, et sera revérifié à la page suivante.
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Renouvellement du verrou impossible',
        erreur: erreur,
      );
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
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Libération du verrou de téléchargement impossible',
        erreur: erreur,
      );
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
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Contrôle des téléchargements en cours impossible',
        erreur: erreur,
      );
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
  ///
  /// Exception : si le dossier des chapitres (choisi par le client) est
  /// injoignable, le téléchargement est remis en attente, sans échec ni
  /// compteur d'échecs, et la méthode renvoie `false` pour que la file
  /// s'arrête. Renvoie `true` dans tous les autres cas.
  Future<bool> _telecharger(Telechargement telechargement) async {
    final id = telechargement.id!;
    final idChapitre = telechargement.idChapitre;
    EcritureChapitre? ecriture;
    // Archive finalisée mais pas encore enregistrée en base : à effacer si
    // l'enregistrement échoue, sinon elle resterait sur le disque sans
    // qu'aucun chapitre ne la désigne.
    String? archiveOrpheline;
    // Durée et nombre de pages pour le journal (aide au diagnostic d'un site
    // lent ou d'un chapitre incomplet).
    final chrono = Stopwatch()..start();
    var nombrePages = 0;
    var description = 'chapitre n°$idChapitre';
    try {
      // Déjà « en cours » : la ligne a été réservée par reserverProchain().
      _signaler();

      final contexte = await _chargerContexte(idChapitre);
      // Chapitre disparu, ou devenu externe depuis sa mise en file (R4) :
      // la ligne est retirée sans rien demander au site.
      if (contexte == null || contexte.chapitre.estExterne) {
        await _depotTelechargements.supprimerTelechargement(id);
        Journal.actuel.info(
          CategorieJournal.telechargement,
          'Chapitre n°$idChapitre retiré de la file (disparu ou externe)',
        );
        return true;
      }
      description =
          'chapitre n°$idChapitre (« ${contexte.titre.nom} » '
          'ch. ${_formaterNumero(contexte.chapitre.numero)} '
          '${contexte.chapitre.langue}, ${contexte.source.nom})';
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Téléchargement du $description : début',
      );
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
        nombrePages = total;
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
            extension: extensionImage(octets, url),
          );
          // La ligne a disparu (le client a annulé ou supprimé le titre) :
          // on s'arrête sans solliciter le site pour les pages restantes.
          if (!await _depotTelechargements.enregistrerProgression(
            id,
            nombrePagesFaites: index + 1,
          )) {
            throw const _Annulation();
          }
          // Verrou repris par l'autre isolat, vu par un autre chapitre en
          // cours (ou par celui-ci) : chaque chapitre s'arrête à sa page
          // suivante, sans attendre son propre renouvellement.
          if (_verrouPerdu || !await _renouvelerVerrouSiNecessaire()) {
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
        Journal.actuel.info(
          CategorieJournal.telechargement,
          'Téléchargement du $description annulé à la fin',
        );
        return true;
      }
      archiveOrpheline = null;
      _echecs.remove(idChapitre);
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Téléchargement du $description : terminé en '
        '${_formaterDuree(chrono.elapsed)}, '
        '${contenu.estTexte ? 'texte' : '$nombrePages page(s)'}',
      );
    } on _Annulation {
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Téléchargement du $description annulé',
      );
      await _abandonner(ecriture);
    } on _VerrouPerdu {
      // L'autre isolat a repris la file : on efface seulement notre archive
      // partielle, sans toucher la ligne de file (c'est désormais à lui de
      // la gérer ; elle sera reprise comme interrompue).
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Téléchargement du $description abandonné : file reprise par '
        "l'autre isolat",
      );
      await _abandonner(ecriture);
    } catch (erreur, pile) {
      await _abandonner(ecriture);
      await _supprimerArchiveOrpheline(archiveOrpheline);
      if (await _estDossierDevenuInjoignable()) {
        // NAS éteint, partage déconnecté : le site n'y est pour rien. Le
        // chapitre retourne en attente (sans échec ni compteur) et la file
        // s'arrête jusqu'au retour du dossier.
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Téléchargement du $description suspendu : dossier des chapitres '
          'inaccessible (NAS ?)',
          erreur: erreur,
        );
        try {
          await _depotTelechargements.enregistrerStatut(
            id,
            StatutTelechargement.enAttente,
          );
        } catch (erreurStatut) {
          // La ligne restera « en cours » et sera reprise comme interrompue.
          Journal.actuel.avertissement(
            CategorieJournal.telechargement,
            'Téléchargement n°$id non remis en attente',
            erreur: erreurStatut,
          );
        }
        await _actualiserAcces(
          nature: erreur is ErreurStockage ? erreur.nature : null,
        );
        return false;
      }
      _echecs.update(idChapitre, (n) => n + 1, ifAbsent: () => 1);
      // La pile n'est utile que pour une erreur inattendue : un refus du
      // site (`ErreurSource`) se comprend avec son message.
      Journal.actuel.erreur(
        CategorieJournal.telechargement,
        'Téléchargement du $description en échec après '
        '${_formaterDuree(chrono.elapsed)} (échec n°${_echecs[idChapitre]}) : '
        '${_messageErreur(erreur)}',
        erreur: erreur,
        pile: erreur is ErreurSource ? null : pile,
      );
      try {
        await _depotTelechargements.enregistrerStatut(
          id,
          StatutTelechargement.echec,
          messageErreur: _messageErreur(erreur),
        );
      } catch (erreurStatut) {
        // La ligne restera « en cours » et sera reprise au prochain
        // traitement.
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Statut du téléchargement n°$id non enregistré',
          erreur: erreurStatut,
        );
      }
    } finally {
      _signaler();
    }
    return true;
  }

  /// `true` si l'échec d'un chapitre vient du dossier des chapitres choisi
  /// par le client, devenu injoignable.
  ///
  /// Le dossier est contrôlé **après** l'erreur, quelle qu'elle soit : une
  /// écriture coupée par la perte du partage remonte souvent comme une
  /// simple erreur d'écriture. À l'inverse, une erreur qui se dit « dossier
  /// introuvable » alors que le dossier racine répond (dossier du titre
  /// effacé à cet instant) reste un échec ordinaire : la remettre en attente
  /// relancerait le même chapitre sans fin. Toujours `false` pour le dossier
  /// par défaut, qui n'est jamais injoignable.
  Future<bool> _estDossierDevenuInjoignable() async {
    try {
      return await _dossierInjoignable();
    } catch (_) {
      return false;
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
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        'Archive orpheline $nomArchive non effacée',
        erreur: erreur,
      );
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
    if (_estImageMangaDexAtHome(url, contexte)) {
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
      // Pas de User-Agent précisé : `ClientHttpPoli` envoie celui de
      // l'application à tous les sites (tâche T1), ce qu'exigent aussi tous
      // les serveurs MangaDex (`uploads.mangadex.org`, E10).
      // Une page anti-robot HTML servie en 200 (E10) ne doit jamais être
      // écrite dans l'archive comme une page du chapitre. Une image servie
      // sans `Content-Type` `image/*` est reconnue par ses octets
      // (`detecterFormatImage`, retour X1 de la 0.2.1-test).
      exigerImage: true,
    );
  }

  /// `true` si [url] est une page servie par un nœud MangaDex@Home : chapitre
  /// d'une source MangaDex **et** adresse hors `mangadex.org`.
  ///
  /// `SignalementMangaDex.estServeurMangaDexAtHome` ne regarde que l'adresse
  /// (« base url that doesn't contain mangadex.org ») : seule, elle prenait
  /// les images de tous les autres sites (Madara, Scan-Manga…) pour des
  /// nœuds MangaDex@Home. Chacune était alors signalée à
  /// `api.mangadex.network` (une requête de plus par page, vers un tiers qui
  /// n'a rien servi) et téléchargée sans nouvelle tentative.
  static bool _estImageMangaDexAtHome(String url, _ContexteChapitre contexte) =>
      contexte.source.typeSource == TypeSource.mangaDex &&
      SignalementMangaDex.estServeurMangaDexAtHome(url);

  /// `true` si un échec sur [url] justifie de redemander les adresses des
  /// images : tout échec d'un nœud MangaDex@Home (nœud en panne), ou un 403
  /// sur une autre adresse MangaDex (adresse expirée). Les autres sites ne
  /// renouvellent pas leurs adresses : réessayer serait inutile.
  static bool _peutRenouvelerAdresse(
    String url,
    ErreurSource erreur,
    _ContexteChapitre contexte,
  ) {
    if (_estImageMangaDexAtHome(url, contexte)) return true;
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

  /// Numéro de chapitre lisible pour le journal : `12` plutôt que `12.0`.
  static String _formaterNumero(double numero) =>
      numero == numero.truncateToDouble() && numero.isFinite
      ? numero.toInt().toString()
      : numero.toString();

  /// Durée lisible pour le journal : `850 ms` ou `12,4 s`.
  static String _formaterDuree(Duration duree) {
    final ms = duree.inMilliseconds;
    if (ms < Duration.millisecondsPerSecond) return '$ms ms';
    return '${(ms / Duration.millisecondsPerSecond).toStringAsFixed(1).replaceAll('.', ',')} s';
  }
}
