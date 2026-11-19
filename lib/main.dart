/// Point d'entrée de l'application « Bibliothèque perso ».
///
/// Ouvre la base, assemble les dépôts, les sources et les services, puis
/// fournit les états à l'interface (PLAYBOOK.md section 4 : `main.dart`
/// initialise la base et les fournisseurs). Sur Android, planifie aussi la
/// recherche périodique de nouveaux chapitres avec `workmanager`
/// (PLAYBOOK.md section 7).
library;

import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as chemins;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseFactory;
import 'package:workmanager/workmanager.dart';

import 'donnees/base_de_donnees.dart';
import 'donnees/depot_categories.dart';
import 'donnees/depot_chapitres.dart';
import 'donnees/depot_listes.dart';
import 'donnees/depot_equivalences_categories.dart';
import 'donnees/depot_parametres.dart';
import 'donnees/depot_sources.dart';
import 'donnees/depot_telechargements.dart';
import 'donnees/depot_titres.dart';
import 'donnees/depot_titres_sources.dart';
import 'donnees/gestionnaire_transactions.dart';
import 'donnees/journal_fichier.dart';
import 'donnees/stockage_telechargements.dart';
import 'ecrans/ecran_accueil.dart';
import 'ecrans/ecran_erreur_demarrage.dart';
import 'etat/etat_bibliotheque.dart';
import 'etat/etat_export.dart';
import 'etat/etat_journal.dart';
import 'etat/etat_navigateur.dart';
import 'etat/etat_dossier_chapitres.dart';
import 'etat/etat_couvertures.dart';
import 'etat/etat_mises_a_jour.dart';
import 'etat/etat_parametres.dart';
import 'etat/etat_parutions.dart';
import 'etat/etat_rapports_erreur.dart';
import 'etat/etat_sources.dart';
import 'etat/etat_telechargements.dart';
import 'modeles/journal.dart';
import 'services/constantes_services.dart' show nomDossierRapports;
import 'services/service_ajout_site.dart';
import 'services/service_bibliotheque.dart';
import 'services/service_categories.dart';
import 'services/service_export.dart';
import 'services/service_import.dart';
import 'services/service_journal.dart';
import 'services/service_lecture_web.dart';
import 'services/planification_mises_a_jour.dart';
import 'services/service_mises_a_jour.dart';
import 'services/service_parametres.dart';
import 'services/service_sources_par_defaut.dart';
import 'services/service_rapports_erreur.dart';
import 'services/service_telechargement.dart';
import 'sources/client_http_poli.dart';
import 'sources/detecteur_type_site.dart';
import 'sources/fabrique_sources.dart';
import 'widgets/constantes_interface.dart' show versionApplication;
import 'widgets/textes.dart';

/// Nom unique de la tâche périodique Android. WorkManager s'en sert pour
/// reconnaître la tâche déjà planifiée à chaque lancement de l'application.
const String nomUniqueTacheMisesAJour = 'bibliotheque_perso.mises_a_jour';

/// Nom de tâche reçu par [repartiteurTachesDeFond] quand la tâche s'exécute.
const String nomTacheMisesAJour = 'verifierTitresSuivis';

/// Fréquence minimale de la tâche de fond Android : au plus une vérification
/// par heure (réglage maximal de 24 par jour), pour ménager la batterie et
/// la charge des sites (PLAYBOOK.md section 10). Android impose de toute
/// façon 15 minutes au minimum.
const Duration frequenceMinimaleTacheAndroid = Duration(hours: 1);

/// Fréquence de la tâche de fond Android pour [planification] : l'écart
/// entre deux échéances, au moins [frequenceMinimaleTacheAndroid].
Duration frequenceTacheAndroid(PlanificationMisesAJour planification) {
  final intervalle = planification.intervalle;
  return intervalle < frequenceMinimaleTacheAndroid
      ? frequenceMinimaleTacheAndroid
      : intervalle;
}

/// Dépôts, client HTTP et services de l'application, construits sur une même
/// base.
///
/// Partagé par l'application ([demarrer]) et par la tâche de fond Android
/// ([repartiteurTachesDeFond]), qui s'exécute dans un autre isolat et doit donc
/// tout reconstruire de son côté.
class ServicesApplication {
  /// Regroupe les éléments déjà construits.
  const ServicesApplication({
    required this.base,
    required this.client,
    required this.serviceAjoutSite,
    required this.serviceBibliotheque,
    required this.serviceMisesAJour,
    required this.serviceParametres,
    required this.serviceTelechargement,
    required this.serviceRapportsErreur,
    required this.serviceExport,
    required this.serviceImport,
    required this.serviceCategories,
    required this.serviceDossierChapitres,
    required this.serviceJournal,
    required this.serviceLectureWeb,
  });

  /// Lecture dans le navigateur intégré.
  final ServiceLectureWeb serviceLectureWeb;

  /// Journal de l'application (export, journal détaillé).
  final ServiceJournal serviceJournal;

  /// Dossier des chapitres (choix, déplacement, accès au NAS).
  final ServiceDossierChapitres serviceDossierChapitres;

  /// Catégories regroupées (groupes, suggestions, filtres).
  final ServiceCategories serviceCategories;

  /// Export des titres et des sites (section « Sauvegarde et export »).
  final ServiceExport serviceExport;

  /// Réimport d'un export JSON (même section).
  final ServiceImport serviceImport;

  /// Export des rapports d'erreur (ajout d'un site ou d'un titre échoué).
  final ServiceRapportsErreur serviceRapportsErreur;

  /// Base SQLite ouverte.
  final Database base;

  /// Client HTTP unique, partagé par tous les services.
  final ClientHttpPoli client;

  /// Ajout d'un site par URL.
  final ServiceAjoutSite serviceAjoutSite;

  /// Lecture et modification de la bibliothèque.
  final ServiceBibliotheque serviceBibliotheque;

  /// Recherche des nouveaux chapitres des titres suivis.
  final ServiceMisesAJour serviceMisesAJour;

  /// Réglages du client.
  final ServiceParametres serviceParametres;

  /// File de téléchargement, lecture hors-ligne et règles de conservation.
  final ServiceTelechargement serviceTelechargement;

  /// Libère le client HTTP et ferme la base.
  ///
  /// Réservé à l'isolat principal : sur Android, la connexion native est
  /// partagée par tout le processus, et la fermer depuis la tâche de fond la
  /// fermerait aussi pour l'application ouverte (voir [executerTacheDeFond]).
  Future<void> fermer() async {
    await serviceTelechargement.fermer();
    client.fermer();
    await base.close();
  }
}

/// Assemble les dépôts et les services sur une base déjà ouverte.
///
/// [client] permet aux tests de fournir un client sans réseau ; [stockage]
/// désigne le dossier des archives hors-ligne (dossier temporaire dans les
/// tests).
ServicesApplication assemblerServices(
  Database base, {
  ClientHttpPoli? client,
  required StockageTelechargements stockage,
  String? dossierApplication,
}) {
  // Rapports et exports : dossier de l'application, jamais le NAS.
  final racineApplication = dossierApplication ?? stockage.dossierRacine;
  // Un seul client HTTP par isolat : le délai minimal entre deux requêtes
  // vers un même domaine est ainsi partagé par tous les services
  // (PLAYBOOK.md section 6).
  final clientUtilise = client ?? ClientHttpPoli();
  final fabriqueSources = FabriqueSources(clientUtilise);
  final depotSources = DepotSources(base);
  final depotTitres = DepotTitres(base);
  final depotListes = DepotListes(base);
  final depotChapitres = DepotChapitres(base);
  // Sites de chaque titre (étape 8) : sans ce dépôt, l'ajout d'un autre site
  // à un titre est refusé et seuls les sites principaux sont exportés.
  final depotTitresSources = DepotTitresSources(base);
  final serviceAjoutSite = ServiceAjoutSite(
    depotSources,
    DetecteurTypeSite(clientUtilise),
    // Vérifie qu'une page générique collée est lisible avant d'ajouter le site.
    client: clientUtilise,
  );
  final serviceParametres = ServiceParametres(DepotParametres(base));
  final serviceBibliotheque = ServiceBibliotheque(
    depotSources: depotSources,
    depotTitres: depotTitres,
    depotChapitres: depotChapitres,
    depotListes: depotListes,
    depotCategories: DepotCategories(base),
    fabriqueSources: fabriqueSources,
    serviceAjoutSite: serviceAjoutSite,
    client: clientUtilise,
    // Réglages du client (langues générales, niveaux de contenu) : sans eux,
    // le service appliquerait les valeurs par défaut.
    serviceParametres: serviceParametres,
    // Couvertures enregistrées sur l'appareil, lisibles hors-ligne.
    stockage: stockage,
    depotTitresSources: depotTitresSources,
  );
  final serviceMisesAJour = ServiceMisesAJour(
    depotTitres: depotTitres,
    depotListes: depotListes,
    depotSources: depotSources,
    serviceBibliotheque: serviceBibliotheque,
    // Horaires réglés par le client et date de la dernière vérification,
    // partagée entre l'application et la tâche de fond.
    serviceParametres: serviceParametres,
  );
  final serviceTelechargement = ServiceTelechargement(
    depotTelechargements: DepotTelechargements(base),
    depotChapitres: depotChapitres,
    depotTitres: depotTitres,
    depotListes: depotListes,
    depotSources: depotSources,
    stockage: stockage,
    fabriqueSources: fabriqueSources,
    client: clientUtilise,
    serviceParametres: serviceParametres,
    depotTitresSources: depotTitresSources,
    // Repère « déplacement des archives inachevé », contrôlé au démarrage.
    depotParametres: DepotParametres(base),
  );
  final serviceDossierChapitres = ServiceDossierChapitres(
    serviceTelechargement: serviceTelechargement,
    depotParametres: DepotParametres(base),
  );
  // Navigateur intégré : chapitre reconnu, marqué lu, images enregistrées.
  final serviceLectureWeb = ServiceLectureWeb(
    depotChapitres: depotChapitres,
    depotTitres: depotTitres,
    depotTitresSources: depotTitresSources,
    depotSources: depotSources,
    stockage: stockage,
    serviceTelechargement: serviceTelechargement,
    estRedemarrageNecessaire: () =>
        serviceDossierChapitres.redemarrageNecessaire,
  );
  return ServicesApplication(
    base: base,
    client: clientUtilise,
    serviceAjoutSite: serviceAjoutSite,
    serviceBibliotheque: serviceBibliotheque,
    serviceMisesAJour: serviceMisesAJour,
    serviceParametres: serviceParametres,
    serviceTelechargement: serviceTelechargement,
    // Rapports d'erreur : `<dossier de l'application>/rapports/` (par défaut
    // `Documents/bibliotheque_perso/rapports/`).
    serviceRapportsErreur: ServiceRapportsErreur(
      chemins.join(racineApplication, nomDossierRapports),
      versionApplication: versionApplication,
      // Les dernières lignes du journal sont jointes aux rapports.
      dossierJournaux: cheminDossierJournaux(racineApplication),
    ),
    // Exports à côté des rapports : `<dossier de l'application>/exports/`.
    serviceExport: ServiceExport(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotChapitres: depotChapitres,
      depotListes: depotListes,
      depotCategories: DepotCategories(base),
      dossierExports: ServiceExport.cheminDossierExports(racineApplication),
      serviceParametres: serviceParametres,
      versionApplication: versionApplication,
      depotTitresSources: depotTitresSources,
      depotEquivalences: DepotEquivalencesCategories(base),
    ),
    // Réimport d'un export JSON (Paramètres → Sauvegarde et export).
    serviceImport: ServiceImport(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotTitresSources: depotTitresSources,
      depotListes: depotListes,
      depotCategories: DepotCategories(base),
      serviceParametres: serviceParametres,
      // Tout ou rien : l'import entier passe par une seule transaction.
      depotParametres: DepotParametres(base),
      gestionnaireTransactions: GestionnaireTransactions(base),
      depotEquivalences: DepotEquivalencesCategories(base),
    ),
    // Catégories regroupées et filtres de la bibliothèque.
    serviceCategories: ServiceCategories.surBase(base),
    // Dossier des chapitres (Paramètres) et bandeau « dossier inaccessible ».
    serviceDossierChapitres: serviceDossierChapitres,
    serviceLectureWeb: serviceLectureWeb,
    // Journal (Paramètres → exporter, journal détaillé) : dossier de
    // l'application, jamais le NAS.
    serviceJournal: ServiceJournal(
      dossierJournaux: cheminDossierJournaux(racineApplication),
      dossierRapports: chemins.join(racineApplication, nomDossierRapports),
      depotParametres: DepotParametres(base),
    ),
  );
}

/// Ouvre la base puis construit tous les services.
///
/// Sans paramètre : base et dossier de téléchargement de l'application. Les
/// tests passent [chemin] (`inMemoryDatabasePath`), [fabrique]
/// (`databaseFactoryFfi`), [client] et [dossierTelechargements] (dossier
/// temporaire). Lève l'erreur d'ouverture de la base si elle ne peut pas
/// être ouverte.
Future<ServicesApplication> construireServices({
  String? chemin,
  DatabaseFactory? fabrique,
  ClientHttpPoli? client,
  bool? annulerTransactionOuverte,
  String? dossierTelechargements,
}) async {
  final base = await ouvrirBaseDeDonnees(
    chemin: chemin,
    fabrique: fabrique,
    annulerTransactionOuverte: annulerTransactionOuverte,
  );
  // Dossier de l'application (rapports, exports) : toujours le dossier par
  // défaut, même quand les chapitres sont sur un NAS (accessibles NAS éteint).
  final String dossierApplication;
  final StockageTelechargements stockage;
  try {
    dossierApplication =
        dossierTelechargements ?? await cheminParDefautDossierTelechargements();
    // Chapitres : dossier choisi par le client (Paramètres), sinon défaut.
    stockage = dossierTelechargements == null
        ? await ServiceDossierChapitres.creerStockage(DepotParametres(base))
        : StockageTelechargements(dossierTelechargements);
  } catch (_) {
    // Sans dossier de téléchargement, l'application ne démarre pas : on ne
    // laisse pas la base ouverte derrière l'erreur. Pas de fermeture dans
    // la tâche de fond Android (connexion partagée avec l'application).
    if (annulerTransactionOuverte != false) {
      await base.close();
    }
    rethrow;
  }
  // MangaDex et Scan-Manga présents dès le premier lancement (demande du
  // client). Sans réseau, ne lève jamais d'erreur, ne modifie jamais une source
  // existante et ne recrée pas une source que le client a supprimée.
  await ServiceSourcesParDefaut(
    depotSources: DepotSources(base),
    serviceParametres: ServiceParametres(DepotParametres(base)),
  ).assurerSourcesParDefaut();
  final services = assemblerServices(
    base,
    client: client,
    stockage: stockage,
    dossierApplication: dossierApplication,
  );
  // Réglage « journal détaillé » du client (ne lève jamais).
  await services.serviceJournal.appliquerReglageJournal();
  return services;
}

/// Point d'entrée de la tâche de fond Android, appelé par `workmanager`.
///
/// Doit rester une fonction de premier niveau annotée `vm:entry-point` :
/// elle est lancée dans un isolat séparé, sans passer par [main], et le
/// compilateur la supprimerait en mode release sans cette annotation.
/// Seule la tâche [nomTacheMisesAJour] déclenche une vérification : une tâche
/// ajoutée plus tard (téléchargements…) ne doit pas solliciter les sites.
@pragma('vm:entry-point')
void repartiteurTachesDeFond() {
  Workmanager().executeTask((nomTache, donnees) async {
    if (nomTache != nomTacheMisesAJour) {
      return true;
    }
    return executerTacheDeFond();
  });
}

/// Recherche les mises à jour depuis la tâche de fond.
///
/// Renvoie `false` uniquement si la base ne s'ouvre pas : WorkManager
/// relancera alors la tâche plus tard. Une erreur de site (ou toute autre
/// erreur pendant la vérification) renvoie `true` : la tâche a bien tourné,
/// le prochain passage périodique réessaiera de toute façon, et une
/// relance immédiate solliciterait inutilement les sites.
Future<bool> executerTacheDeFond({
  String? chemin,
  DatabaseFactory? fabrique,
  ClientHttpPoli? client,
  String? dossierTelechargements,
}) async {
  // Chaque isolat a son propre `Journal.actuel` : la tâche de fond installe
  // le sien (lignes marquées `[fond]`). En cas d'échec, `installer` renvoie
  // null et la tâche continue sans journal de fichier.
  // Le journal précédent est remis à la fin : dans un isolat dédié (Android)
  // c'est sans effet, mais un appel depuis un isolat qui a déjà son journal
  // (tests) ne doit ni le fermer ni lui laisser un journal fermé.
  final journalPrecedent = Journal.actuel;
  final journalFond = await JournalFichier.installer(
    dossierApplication: dossierTelechargements,
    nomIsolat: nomIsolatFond,
  );
  Future<void> terminerJournal() async {
    if (journalFond == null) return;
    await journalFond.fermer();
    if (identical(Journal.actuel, journalFond)) {
      Journal.actuel = journalPrecedent;
    }
  }

  Journal.actuel.info(
    CategorieJournal.demarrage,
    'Tâche de fond : début (version $versionApplication)',
  );
  final ServicesApplication services;
  try {
    services = await construireServices(
      chemin: chemin,
      fabrique: fabrique,
      client: client,
      // Connexion native partagée avec l'application si elle est ouverte :
      // ne pas annuler sa transaction en cours.
      annulerTransactionOuverte: false,
      dossierTelechargements: dossierTelechargements,
    );
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.base,
      'Tâche de fond : base impossible à ouvrir',
      erreur: erreur,
      pile: pile,
    );
    Journal.actuel.info(
      CategorieJournal.demarrage,
      'Tâche de fond : fin (échec, nouvel essai par WorkManager)',
    );
    await terminerJournal();
    return false;
  }
  try {
    await _verifierEtTelechargerEnFond(services);
  } finally {
    Journal.actuel.info(CategorieJournal.demarrage, 'Tâche de fond : fin');
    await terminerJournal();
  }
  return true;
}

/// Vérification des mises à jour puis téléchargements de la tâche de fond,
/// sur des [services] déjà construits ; libère le client HTTP à la fin.
Future<void> _verifierEtTelechargerEnFond(ServicesApplication services) async {
  // LIMITE : si l'application est ouverte au même moment, les deux isolats
  // partagent la même connexion native (sqflite, singleInstance) : le verrou
  // des transactions n'étant pas commun aux isolats, une écriture peut
  // échouer ; le titre concerné sera revérifié au passage suivant. Les deux
  // isolats peuvent aussi vérifier les mêmes titres en même temps (requêtes
  // en double, sans conséquence sur les données).
  try {
    // WorkManager n'est pas exact à la minute (et la tâche peut passer
    // plusieurs fois entre deux échéances) : on ne vérifie que si une
    // échéance (00:00, 12:00 UTC… selon le réglage) est passée depuis la
    // dernière vérification.
    final rapport = await services.serviceMisesAJour.verifierSiEcheancePassee();
    Journal.actuel.info(
      CategorieJournal.misesAJour,
      rapport == null
          ? 'Tâche de fond : bilan : aucune vérification due'
          : 'Tâche de fond : bilan : ${rapport.nombreNouveauxChapitres} '
                'nouveau(x) chapitre(s), ${rapport.echecs.length} échec(s)',
    );
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.misesAJour,
      'Tâche de fond : vérification interrompue',
      erreur: erreur,
      pile: pile,
    );
  }
  // Téléchargements après la vérification, même si elle a échoué : les
  // règles mettent en file les nouveaux chapitres des favoris et suivis, puis
  // on attend la fin de la file avant de rendre la main à WorkManager.
  // LIMITE : Android interrompt une tâche WorkManager au bout d'environ
  // 10 minutes ; les chapitres restants seront repris au passage suivant ou
  // à l'ouverture de l'application (reprise après interruption).
  // LIMITE : si l'application est ouverte, son propre ServiceTelechargement
  // peut traiter la même file en même temps (deux isolats) ; la contrainte
  // d'unicité de la file évite les doublons de lignes, mais un chapitre peut
  // être téléchargé deux fois.
  try {
    await services.serviceTelechargement.appliquerReglesATous();
    await services.serviceTelechargement.lancerTraitement();
    Journal.actuel.info(
      CategorieJournal.telechargement,
      'Tâche de fond : file de téléchargement traitée',
    );
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.telechargement,
      'Tâche de fond : téléchargements interrompus',
      erreur: erreur,
      pile: pile,
    );
  } finally {
    // On libère le client HTTP mais on ne ferme PAS la base : la connexion
    // native est partagée par tout le processus Android, et la fermer ici la
    // fermerait aussi pour l'application ouverte (documentation sqflite).
    await services.serviceTelechargement.fermer();
    services.client.fermer();
  }
}

/// Lance l'application.
Future<void> main() async {
  // Exigé par path_provider (chemin de la base) et par les plugins appelés
  // avant runApp (workmanager).
  WidgetsFlutterBinding.ensureInitialized();
  // workmanager n'est utilisé que sur Android (planifié dans [demarrer], une
  // fois le réglage lu) : sur Windows et Linux, la planification passe par
  // un minuteur de EtatMisesAJour, actif tant que l'application est ouverte
  // (PLAYBOOK.md section 7).
  await demarrer();
}

/// `true` une fois `Workmanager().initialize` appelé dans cet isolat.
bool _workmanagerInitialise = false;

/// Initialise `workmanager` (une fois) et (ré)enregistre la tâche périodique
/// de mises à jour pour [planification].
///
/// Fréquence : l'écart entre deux échéances ([frequenceTacheAndroid]) ;
/// premier passage : à la prochaine échéance. La politique `update`
/// (disponible dans workmanager 0.10.10, WorkManager 2.8) met à jour la tâche
/// existante sans l'annuler : elle sert au démarrage comme au changement du
/// réglage.
/// LIMITE : d'après la documentation de workmanager, `update` garde le
/// rythme d'origine de la tâche ; le premier passage peut donc ne pas tomber
/// pile à l'échéance. C'est sans conséquence : la tâche ne vérifie que si
/// une échéance est passée (`verifierSiEcheancePassee`), au pire avec le
/// retard d'une période.
///
/// Une erreur ici n'empêche pas l'application de fonctionner : seules les
/// vérifications en arrière-plan seraient perdues.
///
/// [enAttente] : planification de la surveillance des titres « En attente »
/// (étape 6, à chaque heure pleine par défaut) ; la tâche passe alors au
/// rythme le plus rapide des deux, et `verifierSiEcheancePassee` choisit à
/// chaque passage la vérification due (complète ou « En attente »).
// LIMITE : la tâche garde ce rythme même quand la liste « En attente » est
// vide ; chaque passage sans échéance due ne lit que la base (aucun réseau).
Future<void> planifierMisesAJourAndroid(
  PlanificationMisesAJour planification, {
  PlanificationMisesAJour? enAttente,
  DateTime? maintenant,
}) async {
  try {
    if (!_workmanagerInitialise) {
      await Workmanager().initialize(repartiteurTachesDeFond);
      _workmanagerInitialise = true;
    }
    final instant = (maintenant ?? DateTime.now()).toUtc();
    var frequence = frequenceTacheAndroid(planification);
    var prochaine = planification.prochaineEcheance(instant);
    if (enAttente != null) {
      final frequenceEnAttente = frequenceTacheAndroid(enAttente);
      if (frequenceEnAttente < frequence) frequence = frequenceEnAttente;
      final prochaineEnAttente = enAttente.prochaineEcheance(instant);
      if (prochaineEnAttente.isBefore(prochaine)) {
        prochaine = prochaineEnAttente;
      }
    }
    await Workmanager().registerPeriodicTask(
      nomUniqueTacheMisesAJour,
      nomTacheMisesAJour,
      frequency: frequence,
      initialDelay: prochaine.difference(instant),
      // Inutile de réveiller l'appareil sans réseau : toutes les
      // vérifications échoueraient.
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.misesAJour,
      'Planification Android des mises à jour impossible',
      erreur: erreur,
      pile: pile,
    );
  }
}

/// Lit les deux planifications enregistrées (vérification complète et titres
/// « En attente ») puis (ré)enregistre la tâche de fond Android.
Future<void> planifierAndroidDepuisReglages(
  ServiceParametres serviceParametres,
) async {
  await planifierMisesAJourAndroid(
    await serviceParametres.chargerPlanification(),
    enAttente: await serviceParametres.chargerPlanificationEnAttente(),
  );
}

/// `true` une fois le fichier de journal de l'application installé. Tant
/// qu'il ne l'est pas, chaque appel de [demarrer] (bouton « Réessayer » de
/// l'écran d'erreur) retente de l'ouvrir.
bool _fichierJournalInstalle = false;

/// `true` une fois les captures d'erreurs et l'écoute du cycle de vie
/// installées (une seule fois par exécution).
bool _gestionnairesErreursInstalles = false;

/// Écoute du cycle de vie : vide le journal quand l'application passe en
/// arrière-plan ou s'arrête. Gardée ici pour ne pas être libérée.
AppLifecycleListener? _ecouteCycleDeVie;

/// Délai maximal d'attente de l'écriture du journal à la fermeture de la
/// fenêtre (Windows, Linux) : au-delà, l'application se ferme quand même.
const Duration delaiMaxVidageJournalFermeture = Duration(seconds: 2);

/// Installe le journal de fichier de l'application, les captures d'erreurs
/// non interceptées et le vidage du journal à la mise en pause.
///
/// Ne lève jamais d'exception : si le journal ne peut pas être ouvert,
/// l'application démarre quand même (journal silencieux), et l'ouverture
/// est retentée au prochain appel.
Future<void> _installerJournalApplication() async {
  if (!_fichierJournalInstalle) {
    try {
      final journal = await JournalFichier.installer();
      if (journal != null) {
        _fichierJournalInstalle = true;
        Journal.actuel.info(
          CategorieJournal.demarrage,
          'Démarrage : version $versionApplication, système '
          '${Platform.operatingSystem} (${Platform.operatingSystemVersion}), '
          'journaux dans ${journal.dossier}',
        );
      }
    } catch (_) {
      // Le journal ne doit jamais empêcher le démarrage.
    }
  }
  if (_gestionnairesErreursInstalles) return;
  _gestionnairesErreursInstalles = true;
  // Erreurs du framework (construction, dessin…) : affichage habituel en
  // mode débogage, puis écriture dans le journal.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Journal.actuel.erreur(
      CategorieJournal.interface,
      'Erreur Flutter (${details.library ?? 'bibliothèque inconnue'})',
      erreur: details.exception,
      pile: details.stack,
    );
  };
  // Erreurs asynchrones non interceptées ailleurs. Renvoyer `true` les marque
  // comme traitées : en mode débogage, elles sont donc aussi affichées dans
  // la console, pour ne pas être masquées pendant le développement.
  WidgetsBinding.instance.platformDispatcher.onError = (erreur, pile) {
    if (kDebugMode) {
      FlutterError.presentError(
        FlutterErrorDetails(
          exception: erreur,
          stack: pile,
          library: 'bibliotheque_perso',
          context: ErrorDescription('erreur asynchrone non interceptée'),
        ),
      );
    }
    Journal.actuel.erreur(
      CategorieJournal.demarrage,
      'Erreur non interceptée',
      erreur: erreur,
      pile: pile,
    );
    return true;
  };
  // Mise en pause (Android), fenêtre masquée (ordinateur) ou arrêt : les
  // entrées en attente sont écrites tout de suite, pour ne pas être perdues
  // si le système tue l'application.
  _ecouteCycleDeVie ??= AppLifecycleListener(
    onHide: () => unawaited(Journal.actuel.vider()),
    onPause: () => unawaited(Journal.actuel.vider()),
    onDetach: () {
      Journal.actuel.info(CategorieJournal.demarrage, 'Arrêt');
      unawaited(Journal.actuel.vider());
    },
    // Fermeture de la fenêtre (Windows, Linux) : `onDetach` n'y est pas
    // garanti ; on attend l'écriture du journal (au plus
    // [delaiMaxVidageJournalFermeture]) avant d'accepter la fermeture.
    // Sans effet sur Android, qui ne fait pas de demande de fermeture.
    onExitRequested: () async {
      Journal.actuel.info(CategorieJournal.demarrage, 'Fermeture demandée');
      try {
        await Journal.actuel.vider().timeout(delaiMaxVidageJournalFermeture);
      } catch (_) {
        // Délai dépassé ou écriture impossible : on ferme quand même.
      }
      return AppExitResponse.exit;
    },
  );
}

/// Ouvre la base et affiche l'application, ou un écran d'erreur lisible si
/// la base ne peut pas être ouverte (au lieu d'un plantage).
Future<void> demarrer() async {
  await _installerJournalApplication();
  Widget application;
  try {
    final services = await construireServices();
    // Reprise des téléchargements interrompus et application des règles, en
    // arrière-plan : l'affichage n'attend pas (l'écran Téléchargements suit
    // la file en direct).
    unawaited(
      services.serviceTelechargement.demarrer().catchError((
        Object erreur,
        StackTrace pile,
      ) {
        Journal.actuel.erreur(
          CategorieJournal.telechargement,
          'Reprise des téléchargements impossible',
          erreur: erreur,
          pile: pile,
        );
      }),
    );
    if (Platform.isAndroid) {
      // Sans attendre : l'affichage ne dépend pas de la tâche de fond.
      unawaited(
        planifierAndroidDepuisReglages(services.serviceParametres)
            .catchError((Object erreur, StackTrace pile) {
              Journal.actuel.erreur(
                CategorieJournal.misesAJour,
                'Planification Android impossible',
                erreur: erreur,
                pile: pile,
              );
            }),
      );
    }
    application = construireApplication(
      serviceBibliotheque: services.serviceBibliotheque,
      serviceAjoutSite: services.serviceAjoutSite,
      serviceMisesAJour: services.serviceMisesAJour,
      serviceTelechargement: services.serviceTelechargement,
      serviceParametres: services.serviceParametres,
      serviceRapportsErreur: services.serviceRapportsErreur,
      serviceExport: services.serviceExport,
      serviceImport: services.serviceImport,
      serviceCategories: services.serviceCategories,
      serviceDossierChapitres: services.serviceDossierChapitres,
      serviceJournal: services.serviceJournal,
      serviceLectureWeb: services.serviceLectureWeb,
    );
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.demarrage,
      'Démarrage impossible',
      erreur: erreur,
      pile: pile,
    );
    application = BibliothequePersoApp(
      accueil: EcranErreurDemarrage(
        detail: erreur.toString(),
        surReessayer: demarrer,
      ),
    );
  }
  runApp(application);
}

/// Application complète branchée sur les services donnés.
///
/// Séparée de [demarrer] pour que les tests puissent fournir de faux
/// services sans base ni réseau.
Widget construireApplication({
  required ServiceBibliotheque serviceBibliotheque,
  required ServiceAjoutSite serviceAjoutSite,
  required ServiceMisesAJour serviceMisesAJour,
  required ServiceTelechargement serviceTelechargement,
  required ServiceParametres serviceParametres,
  ServiceRapportsErreur? serviceRapportsErreur,
  ServiceExport? serviceExport,
  ServiceImport? serviceImport,
  ServiceCategories? serviceCategories,
  ServiceDossierChapitres? serviceDossierChapitres,
  ServiceJournal? serviceJournal,
  ServiceLectureWeb? serviceLectureWeb,
}) {
  // Les états sont fournis au-dessus de MaterialApp : les écrans ouverts par
  // Navigator et les boîtes de dialogue y ont accès.
  return MultiProvider(
    providers: [
      Provider<EtatCouvertures>(
        create: (_) => EtatCouvertures(serviceBibliotheque),
      ),
      // Sans service (tests), le bouton « Exporter le rapport d'erreur »
      // n'est simplement pas affiché.
      if (serviceRapportsErreur != null)
        Provider<EtatRapportsErreur>(
          create: (_) => EtatRapportsErreur(serviceRapportsErreur),
        ),
      // Sans service (tests), la section « Sauvegarde et export » est
      // masquée.
      if (serviceExport != null)
        ChangeNotifierProvider<EtatExport>(
          create: (_) => EtatExport(
            serviceExport,
            serviceImport: serviceImport,
            listerExports: serviceExport.listerExportsJson,
          ),
        ),
      // Navigateur intégré : sans service (tests), les liens s'ouvrent dans
      // le navigateur du système.
      if (serviceLectureWeb != null)
        Provider<FabriqueEtatNavigateur>(
          create: (_) => FabriqueEtatNavigateur(
            serviceLectureWeb,
            serviceBibliotheque: serviceBibliotheque,
          ),
        ),
      // Sans service (tests), la section « Journal » est masquée.
      if (serviceJournal != null)
        ChangeNotifierProvider<EtatJournal>(
          create: (_) => EtatJournal(
            serviceJournal,
            mesurerTaille: (chemin) => File(chemin).length(),
          )..charger(),
        ),
      ChangeNotifierProvider<EtatBibliotheque>(
        create: (_) => EtatBibliotheque(
          serviceBibliotheque,
          serviceTelechargement: serviceTelechargement,
          serviceParametres: serviceParametres,
          serviceCategories: serviceCategories,
        )..charger(),
      ),
      ChangeNotifierProvider<EtatParutions>(
        create: (_) => EtatParutions(serviceBibliotheque)..charger(),
      ),
      ChangeNotifierProvider<EtatSources>(
        create: (_) => EtatSources(
          serviceBibliotheque,
          serviceAjoutSite,
          serviceTelechargement: serviceTelechargement,
        )..charger(),
      ),
      ChangeNotifierProvider<EtatTelechargements>(
        create: (_) =>
            EtatTelechargements(serviceTelechargement, serviceBibliotheque)
              ..charger(),
      ),
      // Sans service (tests), la section « Dossier des chapitres » et les
      // bandeaux de l'accueil sont masqués.
      if (serviceDossierChapitres != null)
        ChangeNotifierProvider<EtatDossierChapitres>(
          create: (_) =>
              EtatDossierChapitres(serviceDossierChapitres)..charger(),
        ),
      ChangeNotifierProvider<EtatParametres>(
        create: (_) => EtatParametres(
          serviceParametres,
          serviceTelechargement,
          serviceBibliotheque: serviceBibliotheque,
        )..charger(),
      ),
      // Sur ordinateur, vérification au démarrage si une échéance a été
      // manquée, puis à chaque échéance tant que l'application est ouverte ;
      // sur Android, c'est la tâche workmanager qui s'en charge : l'état sert
      // au bouton manuel et réenregistre la tâche quand le réglage change.
      ChangeNotifierProvider<EtatMisesAJour>(
        create: (_) => EtatMisesAJour(
          serviceMisesAJour,
          planifier: Platform.isWindows || Platform.isLinux,
          serviceParametres: serviceParametres,
          serviceTelechargement: serviceTelechargement,
          surChangementPlanification: Platform.isAndroid
              ? (_) => planifierAndroidDepuisReglages(serviceParametres)
              : null,
        )..demarrer(),
      ),
    ],
    child: const BibliothequePersoApp(accueil: EcranAccueil()),
  );
}

/// Racine de l'application : thème Material 3 (clair et sombre).
class BibliothequePersoApp extends StatelessWidget {
  /// Crée la racine de l'application avec son écran d'[accueil].
  const BibliothequePersoApp({super.key, required this.accueil});

  /// Premier écran affiché.
  final Widget accueil;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Textes.titreApplication,
      // Material 3 avec une palette dérivée d'une seule couleur, pour garder un thème
      // cohérent en clair comme en sombre sans définir chaque couleur à la main.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: accueil,
    );
  }
}
