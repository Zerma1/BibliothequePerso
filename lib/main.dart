/// Point d'entrée de l'application « Bibliothèque perso ».
///
/// Ouvre la base, assemble les dépôts, les sources et les services, puis
/// fournit les états à l'interface (PLAYBOOK.md section 4 : `main.dart`
/// initialise la base et les fournisseurs). Sur Android, planifie aussi la
/// recherche périodique de nouveaux chapitres avec `workmanager`
/// (PLAYBOOK.md section 7).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseFactory;
import 'package:workmanager/workmanager.dart';

import 'donnees/base_de_donnees.dart';
import 'donnees/depot_categories.dart';
import 'donnees/depot_chapitres.dart';
import 'donnees/depot_listes.dart';
import 'donnees/depot_parametres.dart';
import 'donnees/depot_sources.dart';
import 'donnees/depot_telechargements.dart';
import 'donnees/depot_titres.dart';
import 'donnees/stockage_telechargements.dart';
import 'ecrans/ecran_accueil.dart';
import 'ecrans/ecran_erreur_demarrage.dart';
import 'etat/etat_bibliotheque.dart';
import 'etat/etat_couvertures.dart';
import 'etat/etat_mises_a_jour.dart';
import 'etat/etat_parametres.dart';
import 'etat/etat_sources.dart';
import 'etat/etat_telechargements.dart';
import 'services/service_ajout_site.dart';
import 'services/service_bibliotheque.dart';
import 'services/planification_mises_a_jour.dart';
import 'services/service_mises_a_jour.dart';
import 'services/service_parametres.dart';
import 'services/service_telechargement.dart';
import 'sources/client_http_poli.dart';
import 'sources/detecteur_type_site.dart';
import 'sources/fabrique_sources.dart';
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
  });

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
}) {
  // Un seul client HTTP par isolat : le délai minimal entre deux requêtes
  // vers un même domaine est ainsi partagé par tous les services
  // (PLAYBOOK.md section 6).
  final clientUtilise = client ?? ClientHttpPoli();
  final fabriqueSources = FabriqueSources(clientUtilise);
  final depotSources = DepotSources(base);
  final depotTitres = DepotTitres(base);
  final depotListes = DepotListes(base);
  final depotChapitres = DepotChapitres(base);
  final serviceAjoutSite = ServiceAjoutSite(
    depotSources,
    DetecteurTypeSite(clientUtilise),
  );
  final serviceBibliotheque = ServiceBibliotheque(
    depotSources: depotSources,
    depotTitres: depotTitres,
    depotChapitres: depotChapitres,
    depotListes: depotListes,
    depotCategories: DepotCategories(base),
    fabriqueSources: fabriqueSources,
    serviceAjoutSite: serviceAjoutSite,
    client: clientUtilise,
  );
  final serviceParametres = ServiceParametres(DepotParametres(base));
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
  );
  return ServicesApplication(
    base: base,
    client: clientUtilise,
    serviceAjoutSite: serviceAjoutSite,
    serviceBibliotheque: serviceBibliotheque,
    serviceMisesAJour: serviceMisesAJour,
    serviceParametres: serviceParametres,
    serviceTelechargement: serviceTelechargement,
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
  final StockageTelechargements stockage;
  try {
    stockage = dossierTelechargements == null
        ? await StockageTelechargements.parDefaut()
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
  return assemblerServices(base, client: client, stockage: stockage);
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
    debugPrint('Tâche de fond : base impossible à ouvrir : $erreur\n$pile');
    return false;
  }
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
    debugPrint(
      rapport == null
          ? 'Tâche de fond : aucune vérification due.'
          : 'Tâche de fond : ${rapport.nombreNouveauxChapitres} nouveau(x) '
                'chapitre(s), ${rapport.echecs.length} échec(s).',
    );
  } catch (erreur, pile) {
    debugPrint('Tâche de fond : vérification interrompue : $erreur\n$pile');
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
  } catch (erreur, pile) {
    debugPrint('Tâche de fond : téléchargements interrompus : $erreur\n$pile');
  } finally {
    // On libère le client HTTP mais on ne ferme PAS la base : la connexion
    // native est partagée par tout le processus Android, et la fermer ici la
    // fermerait aussi pour l'application ouverte (documentation sqflite).
    await services.serviceTelechargement.fermer();
    services.client.fermer();
  }
  return true;
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
Future<void> planifierMisesAJourAndroid(
  PlanificationMisesAJour planification, {
  DateTime? maintenant,
}) async {
  try {
    if (!_workmanagerInitialise) {
      await Workmanager().initialize(repartiteurTachesDeFond);
      _workmanagerInitialise = true;
    }
    final instant = (maintenant ?? DateTime.now()).toUtc();
    await Workmanager().registerPeriodicTask(
      nomUniqueTacheMisesAJour,
      nomTacheMisesAJour,
      frequency: frequenceTacheAndroid(planification),
      initialDelay: planification
          .prochaineEcheance(instant)
          .difference(instant),
      // Inutile de réveiller l'appareil sans réseau : toutes les
      // vérifications échoueraient.
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } catch (erreur, pile) {
    debugPrint('Planification des mises à jour impossible : $erreur\n$pile');
  }
}

/// Ouvre la base et affiche l'application, ou un écran d'erreur lisible si
/// la base ne peut pas être ouverte (au lieu d'un plantage).
Future<void> demarrer() async {
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
        debugPrint('Reprise des téléchargements impossible : $erreur\n$pile');
      }),
    );
    if (Platform.isAndroid) {
      // Sans attendre : l'affichage ne dépend pas de la tâche de fond.
      unawaited(
        services.serviceParametres
            .chargerPlanification()
            .then(planifierMisesAJourAndroid)
            .catchError((Object erreur, StackTrace pile) {
              debugPrint('Planification Android impossible : $erreur\n$pile');
            }),
      );
    }
    application = construireApplication(
      serviceBibliotheque: services.serviceBibliotheque,
      serviceAjoutSite: services.serviceAjoutSite,
      serviceMisesAJour: services.serviceMisesAJour,
      serviceTelechargement: services.serviceTelechargement,
      serviceParametres: services.serviceParametres,
    );
  } catch (erreur, pile) {
    debugPrint('Démarrage impossible : $erreur\n$pile');
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
}) {
  // Les états sont fournis au-dessus de MaterialApp : les écrans ouverts par
  // Navigator et les boîtes de dialogue y ont accès.
  return MultiProvider(
    providers: [
      Provider<EtatCouvertures>(
        create: (_) => EtatCouvertures(serviceBibliotheque),
      ),
      ChangeNotifierProvider<EtatBibliotheque>(
        create: (_) => EtatBibliotheque(
          serviceBibliotheque,
          serviceTelechargement: serviceTelechargement,
        )..charger(),
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
      ChangeNotifierProvider<EtatParametres>(
        create: (_) =>
            EtatParametres(serviceParametres, serviceTelechargement)..charger(),
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
              ? (planification) => planifierMisesAJourAndroid(planification)
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
