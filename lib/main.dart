/// Point d'entrée de l'application « Bibliothèque perso ».
///
/// Ouvre la base, assemble les dépôts, les sources et les services, puis
/// fournit les états à l'interface (PLAYBOOK.md section 4 : `main.dart`
/// initialise la base et les fournisseurs). Sur Android, planifie aussi la
/// recherche périodique de nouveaux chapitres avec `workmanager`
/// (PLAYBOOK.md section 7).
library;

import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io' show File, Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, MissingPluginException;
import 'package:launch_at_startup/launch_at_startup.dart' show launchAtStartup;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as chemins;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseFactory;
// Préfixe : tray_manager exporte aussi `Image`, `Menu` et `MenuItem`, qui
// masqueraient ceux de Flutter.
import 'package:tray_manager/tray_manager.dart' as zone;
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
import 'etat/etat_theme.dart';
import 'widgets/theme_application.dart';
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

/// Fichier écrit par l'installateur Windows (`installateur/bibliotheque_perso.iss`)
/// à côté de l'exécutable : `{"dossierBibliotheque": "<chemin choisi>"}`.
const String nomFichierInstallation = 'installation.json';

/// Clé du dossier de la bibliothèque (chapitres téléchargés) dans
/// [nomFichierInstallation].
const String cleDossierBibliothequeInstallation = 'dossierBibliotheque';

/// Dossier de la bibliothèque choisi dans l'installateur Windows, ou `null`.
///
/// Lit [nomFichierInstallation] dans le dossier de l'exécutable
/// ([cheminExecutable], par défaut `Platform.resolvedExecutable` ; les tests
/// passent un chemin dans un dossier temporaire). Renvoie `null` si le
/// fichier est absent (lancement depuis IntelliJ, archive .zip, Android,
/// Linux), illisible ou sans chemin : l'application garde alors son réglage
/// ou le dossier par défaut. Ne lève jamais : une erreur de lecture est
/// seulement journalisée.
///
/// Ne valide pas le dossier (NAS éteint, droits) : c'est à l'appelant de le
/// traiter comme un dossier choisi dans les Paramètres.
Future<String?> chargerDossierBibliothequeInstallation({
  String? cheminExecutable,
}) async {
  final fichier = File(
    chemins.join(
      chemins.dirname(cheminExecutable ?? Platform.resolvedExecutable),
      nomFichierInstallation,
    ),
  );
  try {
    if (!await fichier.exists()) return null;
    var texte = await fichier.readAsString();
    // Fichier réenregistré à la main avec un éditeur qui ajoute un BOM UTF-8 :
    // jsonDecode le refuserait.
    if (texte.isNotEmpty && texte.codeUnitAt(0) == 0xFEFF) {
      texte = texte.substring(1);
    }
    final Object? donnees = jsonDecode(texte);
    if (donnees is! Map<String, Object?>) return null;
    final valeur = donnees[cleDossierBibliothequeInstallation];
    if (valeur is! String) return null;
    final propre = valeur.trim();
    return propre.isEmpty ? null : propre;
  } catch (erreur) {
    Journal.actuel.avertissement(
      CategorieJournal.demarrage,
      'Fichier $nomFichierInstallation illisible : ignoré',
      erreur: erreur,
    );
    return null;
  }
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
    // Dossier de bibliothèque choisi dans l'installateur Windows : appliqué
    // une fois, au premier démarrage, s'il n'y a pas déjà de réglage.
    if (dossierTelechargements == null && Platform.isWindows) {
      await ServiceDossierChapitres.appliquerDossierInstallation(
        DepotParametres(base),
        await chargerDossierBibliothequeInstallation(),
        depotChapitres: DepotChapitres(base),
      );
    }
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
///
/// [arguments] : arguments de la ligne de commande (transmis par le programme
/// natif Windows) ; [argumentDemarrageMasque] signale un démarrage avec
/// Windows en mode « icône masquée ».
Future<void> main(List<String> arguments) async {
  // Exigé par path_provider (chemin de la base) et par les plugins appelés
  // avant runApp (workmanager).
  WidgetsFlutterBinding.ensureInitialized();
  _demarrageMasque =
      Platform.isWindows && arguments.contains(argumentDemarrageMasque);
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

/// Canal de la fenêtre Windows (`windows/runner/flutter_window.cpp`).
///
/// Sous Windows, le moteur Flutter ne transmet la demande de fermeture
/// (`System.requestAppExit`) que si la fenêtre est la dernière fenêtre de
/// premier niveau du processus ; les fenêtres cachées du navigateur intégré
/// (flutter_inappwebview_windows) l'en empêchent. Le programme natif pose donc
/// lui-même la question à Dart par ce canal, à chaque WM_CLOSE.
const MethodChannel canalFenetre = MethodChannel('bibliotheque_perso/fenetre');

/// Méthode du [canalFenetre] appelée à la fermeture de la fenêtre.
const String methodeDemanderFermeture = 'demanderFermeture';

/// Méthode native du [canalFenetre] : cache la fenêtre (le processus continue).
const String methodeCacher = 'cacher';

/// Méthode native du [canalFenetre] : affiche la fenêtre au premier plan (même
/// cachée, réduite ou jamais affichée).
const String methodeAfficher = 'afficher';

/// Méthode native du [canalFenetre] : reposte WM_CLOSE, qui revient à Dart par
/// [methodeDemanderFermeture] (vraie fermeture si [quitterApplication] l'a
/// demandée).
const String methodeQuitter = 'quitter';

/// Argument de ligne de commande du démarrage avec Windows en mode « icône
/// masquée » : le programme natif n'affiche pas la fenêtre
/// (`windows/runner/flutter_window.h`, même valeur).
const String argumentDemarrageMasque = '--demarrage-masque';

/// Nom de l'entrée de démarrage dans
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (et dans
/// `...\Explorer\StartupApproved\Run`). À retirer aussi par le désinstallateur.
const String nomEntreeDemarrageWindows = 'Bibliotheque perso';

/// Logo de l'icône de la zone de notification (déclaré dans `pubspec.yaml`).
const String cheminIconeZoneNotification = 'assets/logo/logo.ico';

// LIMITE : textes affichés hors de lib/widgets/textes.dart (scope de
// l'intégrateur) ; à déplacer dans `Textes` par developpeur-interface.

/// Info-bulle de l'icône de la zone de notification.
const String texteInfoBulleZoneNotification =
    'Bibliothèque perso (continue en arrière-plan)';

/// Menu de l'icône : afficher la fenêtre.
const String texteMenuOuvrir = 'Ouvrir Bibliothèque perso';

/// Menu de l'icône : recherche manuelle des nouveaux chapitres.
const String texteMenuRechercher = 'Rechercher les nouveaux chapitres';

/// Menu de l'icône : vraie fermeture de l'application.
const String texteMenuQuitter = 'Quitter';

/// `true` si l'application a été lancée par Windows en mode « icône masquée »
/// ([argumentDemarrageMasque]).
bool _demarrageMasque = false;

/// `true` après « Quitter » : la prochaine demande de fermeture ferme vraiment
/// au lieu de cacher la fenêtre.
bool _quitterDemande = false;

/// `true` dès que la fenêtre a été cachée une première fois (journal).
bool _fenetreDejaCachee = false;

/// Icône de la zone de notification (Windows), ou `null` si elle n'est pas
/// installée : la croix ferme alors vraiment l'application. Gardée ici : une
/// icône libérée par le ramasse-miettes disparaît.
zone.TrayIcon? _iconeZoneNotification;

/// Menu, éléments et image de l'icône, gardés pour la même raison.
final List<Object> _elementsZoneNotification = <Object>[];

/// Navigateur de l'application : donne au menu de l'icône (hors de l'arbre
/// des widgets) l'accès aux états fournis au-dessus de [MaterialApp].
final GlobalKey<NavigatorState> cleNavigateurApplication =
    GlobalKey<NavigatorState>(debugLabel: 'navigateurApplication');

/// `true` si la croix cache la fenêtre dans la zone de notification au lieu
/// de fermer l'application.
bool get fermetureVersZoneNotification =>
    _iconeZoneNotification != null && !_quitterDemande;

/// Répond à une demande du [canalFenetre].
///
/// [methodeDemanderFermeture] : si l'icône de la zone de notification est
/// installée et que « Quitter » n'a pas été choisi, la fenêtre est seulement
/// cachée (l'application, ses vérifications et ses téléchargements
/// continuent) et la réponse est `'cancel'`. Sinon la demande passe par
/// `handleRequestAppExit`, comme une demande venue du moteur : tous les
/// `AppLifecycleListener.onExitRequested` sont appelés (vidage du journal).
/// Renvoie `'exit'` ou `'cancel'` (nom de [AppExitResponse]).
Future<Object?> traiterAppelFenetre(MethodCall appel) async {
  if (appel.method == methodeDemanderFermeture) {
    if (fermetureVersZoneNotification) {
      await _cacherFenetre();
      return AppExitResponse.cancel.name;
    }
    final reponse = await WidgetsBinding.instance.handleRequestAppExit();
    if (reponse == AppExitResponse.exit) {
      // Retirée avant la fin du processus : sinon une icône fantôme reste
      // dans la zone de notification jusqu'au survol de la souris.
      _retirerZoneNotification();
    } else {
      _quitterDemande = false;
    }
    return reponse.name;
  }
  throw MissingPluginException('Méthode inconnue : ${appel.method}');
}

/// Cache la fenêtre ; l'application continue dans la zone de notification.
Future<void> _cacherFenetre() async {
  try {
    await canalFenetre.invokeMethod<void>(methodeCacher);
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.interface,
      'Fenêtre impossible à cacher',
      erreur: erreur,
      pile: pile,
    );
    return;
  }
  Journal.actuel.info(
    CategorieJournal.interface,
    _fenetreDejaCachee
        ? 'Fenêtre cachée dans la zone de notification'
        : 'Fenêtre cachée dans la zone de notification (première fois) : '
              "l'application continue en arrière-plan",
  );
  // LIMITE : tray_manager 0.9.1 n'a pas de bulle de notification ; le
  // message « continue en arrière-plan » est dans l'info-bulle de l'icône.
  _fenetreDejaCachee = true;
}

/// Affiche la fenêtre au premier plan (clic sur l'icône, menu « Ouvrir »,
/// démarrage masqué sans icône). Ne lève jamais.
Future<void> afficherFenetre() async {
  if (!Platform.isWindows) return;
  try {
    await canalFenetre.invokeMethod<void>(methodeAfficher);
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.interface,
      'Fenêtre impossible à afficher',
      erreur: erreur,
      pile: pile,
    );
  }
}

/// Ferme vraiment l'application (menu « Quitter » de l'icône).
///
/// Passe par la même demande de fermeture que la croix
/// ([methodeQuitter] → WM_CLOSE → [methodeDemanderFermeture]), donc par
/// `onExitRequested` et le vidage du journal. Ne lève jamais.
Future<void> quitterApplication() async {
  _quitterDemande = true;
  Journal.actuel.info(
    CategorieJournal.demarrage,
    'Quitter demandé depuis la zone de notification',
  );
  try {
    await canalFenetre.invokeMethod<void>(methodeQuitter);
  } catch (erreur, pile) {
    _quitterDemande = false;
    Journal.actuel.erreur(
      CategorieJournal.demarrage,
      'Fermeture impossible depuis la zone de notification',
      erreur: erreur,
      pile: pile,
    );
  }
}

/// Lance la recherche des nouveaux chapitres comme le bouton de l'interface
/// (menu de l'icône), si l'application est affichée normalement (pas sur
/// l'écran d'erreur de démarrage).
void _rechercherNouveauxChapitres() {
  final contexte = cleNavigateurApplication.currentContext;
  final etat = contexte?.read<EtatMisesAJour?>();
  if (etat == null) return;
  Journal.actuel.info(
    CategorieJournal.misesAJour,
    'Recherche des nouveaux chapitres demandée depuis la zone de notification',
  );
  unawaited(etat.verifierMaintenant());
}

/// Installe l'icône de la zone de notification (Windows seulement, une fois).
///
/// Clic ou double clic : [afficherFenetre] ; clic droit : menu « Ouvrir »,
/// « Rechercher les nouveaux chapitres », « Quitter ». Renvoie `true` si
/// l'icône est en place. En cas d'échec (journalisé), la croix ferme
/// l'application comme avant.
Future<bool> installerZoneNotification() async {
  if (!Platform.isWindows) return false;
  if (_iconeZoneNotification != null) return true;
  try {
    final icone = zone.TrayIcon.create();
    if (icone == null) {
      throw StateError('TrayIcon.create a renvoyé null');
    }
    final image = zone.ImageAsset.fromAsset(cheminIconeZoneNotification);
    if (image == null) {
      icone.dispose();
      throw StateError('Logo illisible : $cheminIconeZoneNotification');
    }
    icone.icon = image;
    icone.setTooltip(texteInfoBulleZoneNotification);

    final menu = zone.Menu.create();
    if (menu == null) {
      icone.dispose();
      throw StateError('Menu.create a renvoyé null');
    }
    zone.MenuItem? element(String texte, void Function() action) {
      final item = zone.MenuItem.createWithLabelAndType(
        texte,
        zone.MenuItemType.normal,
      );
      item?.addListener((evenement) {
        if (evenement is zone.MenuItemClickedEvent) action();
      });
      return item;
    }

    final ouvrir = element(texteMenuOuvrir, () => unawaited(afficherFenetre()));
    final rechercher = element(
      texteMenuRechercher,
      _rechercherNouveauxChapitres,
    );
    final quitter = element(
      texteMenuQuitter,
      () => unawaited(quitterApplication()),
    );
    menu.addItem(ouvrir);
    menu.addItem(rechercher);
    menu.addSeparator();
    menu.addItem(quitter);
    icone.setContextMenu(menu);
    // Le déclencheur par défaut est « aucun » : sans cette ligne, le clic
    // droit n'ouvre pas le menu.
    icone.setContextMenuTrigger(zone.ContextMenuTrigger.rightClicked);
    icone.addListener((evenement) {
      if (evenement is zone.TrayIconClickedEvent ||
          evenement is zone.TrayIconDoubleClickedEvent) {
        unawaited(afficherFenetre());
      }
    });
    icone.setVisible(true);
    _iconeZoneNotification = icone;
    _elementsZoneNotification.addAll([
      image,
      menu,
      ?ouvrir,
      ?rechercher,
      ?quitter,
    ]);
    Journal.actuel.info(
      CategorieJournal.demarrage,
      'Icône de la zone de notification installée',
    );
    return true;
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.demarrage,
      'Icône de la zone de notification impossible : la croix fermera '
      "l'application",
      erreur: erreur,
      pile: pile,
    );
    return false;
  }
}

/// Retire l'icône de la zone de notification (fin de l'application).
void _retirerZoneNotification() {
  final icone = _iconeZoneNotification;
  if (icone == null) return;
  _iconeZoneNotification = null;
  try {
    icone.setVisible(false);
    icone.dispose();
  } catch (_) {
    // Fin du processus : Windows retirera l'icône au plus tard au survol.
  }
  _elementsZoneNotification.clear();
}

/// Inscrit ([actif]) ou désinscrit l'application du démarrage avec Windows.
///
/// À appeler quand le réglage « Démarrage avec Windows » change, et à chaque
/// démarrage si le réglage n'est pas « Off » (l'entrée garde ainsi le chemin
/// de l'exécutable à jour après une réinstallation ailleurs). [masque] :
/// lancement en mode « icône masquée » ([argumentDemarrageMasque]) ; ignoré
/// si [actif] vaut `false`.
///
/// Écrit `"<chemin de l'exécutable>" [--demarrage-masque]` sous le nom
/// [nomEntreeDemarrageWindows] dans `HKCU\...\CurrentVersion\Run` (aucun droit
/// administrateur). Renvoie `true` si l'inscription est appliquée ; `false`
/// hors de Windows (rien n'est fait) ou en cas d'erreur (journalisée). Ne lève
/// jamais.
Future<bool> appliquerDemarrageAvecWindows({
  required bool actif,
  bool masque = false,
}) async {
  if (!Platform.isWindows) return false;
  try {
    launchAtStartup.setup(
      appName: nomEntreeDemarrageWindows,
      // Guillemets : launch_at_startup écrit le chemin tel quel, et un
      // chemin avec des espaces (« Program Files ») serait mal découpé.
      appPath: '"${Platform.resolvedExecutable}"',
      args: [if (actif && masque) argumentDemarrageMasque],
    );
    if (actif) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    Journal.actuel.info(
      CategorieJournal.parametres,
      actif
          ? 'Démarrage avec Windows activé (${masque ? 'icône masquée' : 'pleine fenêtre'})'
          : 'Démarrage avec Windows désactivé',
    );
    return true;
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.parametres,
      'Démarrage avec Windows impossible à modifier',
      erreur: erreur,
      pile: pile,
    );
    return false;
  }
}

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
    // Sous Windows, la demande arrive par [canalFenetre].
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
  if (Platform.isWindows) {
    canalFenetre.setMethodCallHandler(traiterAppelFenetre);
  }
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
    // Thème lu avant l'affichage (pas d'éclair du thème du système) ; une
    // erreur ne bloque jamais le démarrage : thème du système.
    final modeTheme = await chargerModeThemeInitial(services.serviceParametres);
    // Démarrage avec Windows : réinscrit à chaque lancement pour garder le
    // chemin de l'exécutable à jour (après une mise à jour ou un déplacement).
    if (Platform.isWindows) {
      try {
        final mode = await services.serviceParametres.chargerModeDemarrage();
        if (mode != ModeDemarrage.desactive) {
          await appliquerDemarrageAvecWindows(
            actif: true,
            masque: mode == ModeDemarrage.iconeMasquee,
          );
        }
      } catch (erreur, pile) {
        Journal.actuel.avertissement(
          CategorieJournal.demarrage,
          'Démarrage avec Windows non vérifié',
          erreur: erreur,
          pile: pile,
        );
      }
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
      modeTheme: modeTheme,
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
    // Démarrage masqué : l'écran d'erreur doit être vu, sinon l'application
    // tournerait cachée sans rien faire.
    if (_demarrageMasque) unawaited(afficherFenetre());
    runApp(application);
    return;
  }
  runApp(application);
  // Windows : la croix cache la fenêtre dans la zone de notification
  // (seulement une fois les services démarrés, pour ne pas garder en vie une
  // application en erreur).
  if (Platform.isWindows) {
    final iconeInstallee = await installerZoneNotification();
    if (_demarrageMasque) {
      Journal.actuel.info(
        CategorieJournal.demarrage,
        'Démarrage avec Windows : fenêtre gardée dans la zone de notification',
      );
      // Sans icône, la fenêtre cachée serait inaccessible.
      if (!iconeInstallee) unawaited(afficherFenetre());
    }
  }
}

/// Thème enregistré par le client, lu avant le premier affichage.
///
/// Ne lève jamais : en cas d'erreur (base illisible…), l'erreur est
/// journalisée et le thème par défaut (système) est renvoyé.
Future<ModeTheme> chargerModeThemeInitial(
  ServiceParametres serviceParametres,
) async {
  try {
    return await serviceParametres.chargerModeTheme();
  } catch (erreur, pile) {
    Journal.actuel.avertissement(
      CategorieJournal.parametres,
      'Thème enregistré illisible au démarrage : thème du système',
      erreur: erreur,
      pile: pile,
    );
    return ServiceParametres.modeThemeParDefaut;
  }
}

/// Application complète branchée sur les services donnés.
///
/// Séparée de [demarrer] pour que les tests puissent fournir de faux
/// services sans base ni réseau. [modeTheme] : thème déjà lu au démarrage
/// (par défaut, celui du service, puis le choix enregistré une fois lu).
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
  ModeTheme? modeTheme,
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
        // Créé tout de suite (suppressions différées, même fenêtre cachée).
        lazy: false,
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
      // Thème choisi dans Paramètres → Apparence (suivi par la racine).
      ChangeNotifierProvider<EtatTheme>(
        create: (_) =>
            EtatTheme(serviceParametres, modeInitial: modeTheme)..charger(),
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
        // Créé tout de suite : avec un démarrage dans la zone de notification,
        // aucun écran ne le lirait et les vérifications ne démarreraient pas.
        lazy: false,
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
      // Palette dérivée de l'indigo du logo, en clair comme en sombre.
      theme: themeClair,
      darkTheme: themeSombre,
      // Choix du client (Paramètres → Apparence) ; absent sur l'écran
      // d'erreur de démarrage : thème du système.
      themeMode: versThemeMode(context.watch<EtatTheme?>()?.mode),
      // Accès aux états depuis le menu de la zone de notification.
      navigatorKey: cleNavigateurApplication,
      home: accueil,
    );
  }
}
