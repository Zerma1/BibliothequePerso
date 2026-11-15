/// Point d'entrée de l'application « Bibliothèque perso ».
///
/// Ouvre la base, assemble les dépôts, les sources et les services, puis
/// fournit les états à l'interface (PLAYBOOK.md section 4 : `main.dart`
/// initialise la base et les fournisseurs). Sur Android, planifie aussi la
/// recherche périodique de nouveaux chapitres avec `workmanager`
/// (PLAYBOOK.md section 7).
library;

import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseFactory;
import 'package:workmanager/workmanager.dart';

import 'donnees/base_de_donnees.dart';
import 'donnees/depot_categories.dart';
import 'donnees/depot_chapitres.dart';
import 'donnees/depot_listes.dart';
import 'donnees/depot_sources.dart';
import 'donnees/depot_titres.dart';
import 'ecrans/ecran_accueil.dart';
import 'ecrans/ecran_erreur_demarrage.dart';
import 'etat/constantes_etat.dart';
import 'etat/etat_bibliotheque.dart';
import 'etat/etat_couvertures.dart';
import 'etat/etat_mises_a_jour.dart';
import 'etat/etat_sources.dart';
import 'services/service_ajout_site.dart';
import 'services/service_bibliotheque.dart';
import 'services/service_mises_a_jour.dart';
import 'sources/client_http_poli.dart';
import 'sources/detecteur_type_site.dart';
import 'sources/fabrique_sources.dart';
import 'widgets/textes.dart';

/// Nom unique de la tâche périodique Android. WorkManager s'en sert pour
/// reconnaître la tâche déjà planifiée à chaque lancement de l'application.
const String nomUniqueTacheMisesAJour = 'bibliotheque_perso.mises_a_jour';

/// Nom de tâche reçu par [repartiteurTachesDeFond] quand la tâche s'exécute.
const String nomTacheMisesAJour = 'verifierTitresSuivis';

/// Période de la recherche de mises à jour en arrière-plan sur Android.
///
/// Même période que sur ordinateur ([intervalleMisesAJourBureau], six
/// heures) : assez fréquent pour un suivi de chapitres, assez rare pour
/// ménager la batterie et la charge des sites (PLAYBOOK.md section 10).
/// Android impose de toute façon 15 minutes au minimum.
const Duration frequenceMisesAJourAndroid = intervalleMisesAJourBureau;

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

  /// Libère le client HTTP et ferme la base.
  ///
  /// Réservé à l'isolat principal : sur Android, la connexion native est
  /// partagée par tout le processus, et la fermer depuis la tâche de fond la
  /// fermerait aussi pour l'application ouverte (voir [executerTacheDeFond]).
  Future<void> fermer() async {
    client.fermer();
    await base.close();
  }
}

/// Assemble les dépôts et les services sur une base déjà ouverte.
///
/// [client] permet aux tests de fournir un client sans réseau.
ServicesApplication assemblerServices(Database base, {ClientHttpPoli? client}) {
  // Un seul client HTTP par isolat : le délai minimal entre deux requêtes
  // vers un même domaine est ainsi partagé par tous les services
  // (PLAYBOOK.md section 6).
  final clientUtilise = client ?? ClientHttpPoli();
  final depotSources = DepotSources(base);
  final depotTitres = DepotTitres(base);
  final depotListes = DepotListes(base);
  final serviceAjoutSite = ServiceAjoutSite(
    depotSources,
    DetecteurTypeSite(clientUtilise),
  );
  final serviceBibliotheque = ServiceBibliotheque(
    depotSources: depotSources,
    depotTitres: depotTitres,
    depotChapitres: DepotChapitres(base),
    depotListes: depotListes,
    depotCategories: DepotCategories(base),
    fabriqueSources: FabriqueSources(clientUtilise),
    serviceAjoutSite: serviceAjoutSite,
    client: clientUtilise,
  );
  final serviceMisesAJour = ServiceMisesAJour(
    depotTitres: depotTitres,
    depotListes: depotListes,
    depotSources: depotSources,
    serviceBibliotheque: serviceBibliotheque,
  );
  return ServicesApplication(
    base: base,
    client: clientUtilise,
    serviceAjoutSite: serviceAjoutSite,
    serviceBibliotheque: serviceBibliotheque,
    serviceMisesAJour: serviceMisesAJour,
  );
}

/// Ouvre la base puis construit tous les services.
///
/// Sans paramètre : base de l'application. Les tests passent [chemin]
/// (`inMemoryDatabasePath`), [fabrique] (`databaseFactoryFfi`) et [client].
/// Lève l'erreur d'ouverture de la base si elle ne peut pas être ouverte.
Future<ServicesApplication> construireServices({
  String? chemin,
  DatabaseFactory? fabrique,
  ClientHttpPoli? client,
  bool? annulerTransactionOuverte,
}) async {
  final base = await ouvrirBaseDeDonnees(
    chemin: chemin,
    fabrique: fabrique,
    annulerTransactionOuverte: annulerTransactionOuverte,
  );
  return assemblerServices(base, client: client);
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
    final rapport = await services.serviceMisesAJour.verifierTitresSuivis();
    debugPrint(
      'Tâche de fond : ${rapport.nombreNouveauxChapitres} nouveau(x) '
      'chapitre(s), ${rapport.echecs.length} échec(s).',
    );
  } catch (erreur, pile) {
    debugPrint('Tâche de fond : vérification interrompue : $erreur\n$pile');
  } finally {
    // On libère le client HTTP mais on ne ferme PAS la base : la connexion
    // native est partagée par tout le processus Android, et la fermer ici la
    // fermerait aussi pour l'application ouverte (documentation sqflite).
    services.client.fermer();
  }
  return true;
}

/// Lance l'application.
Future<void> main() async {
  // Exigé par path_provider (chemin de la base) et par les plugins appelés
  // avant runApp (workmanager).
  WidgetsFlutterBinding.ensureInitialized();
  // workmanager n'est utilisé que sur Android : sur Windows et Linux, la
  // planification passe par une minuterie de EtatMisesAJour, active tant que
  // l'application est ouverte (PLAYBOOK.md section 7).
  if (Platform.isAndroid) {
    await planifierMisesAJourAndroid();
  }
  await demarrer();
}

/// Initialise `workmanager` et planifie la tâche périodique de mises à jour.
///
/// Une erreur ici n'empêche pas l'application de démarrer : seules les
/// vérifications en arrière-plan seraient perdues.
Future<void> planifierMisesAJourAndroid() async {
  try {
    await Workmanager().initialize(repartiteurTachesDeFond);
    await Workmanager().registerPeriodicTask(
      nomUniqueTacheMisesAJour,
      nomTacheMisesAJour,
      frequency: frequenceMisesAJourAndroid,
      // Inutile de réveiller l'appareil sans réseau : toutes les
      // vérifications échoueraient.
      constraints: Constraints(networkType: NetworkType.connected),
      // `keep` : la tâche est enregistrée à chaque lancement ; garder celle
      // qui existe évite de repousser sa prochaine exécution à chaque
      // ouverture de l'application. Attention : changer la fréquence plus
      // tard exigera la politique `update` (documentation de workmanager).
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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
    application = construireApplication(
      serviceBibliotheque: services.serviceBibliotheque,
      serviceAjoutSite: services.serviceAjoutSite,
      serviceMisesAJour: services.serviceMisesAJour,
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
}) {
  // Les états sont fournis au-dessus de MaterialApp : les écrans ouverts par
  // Navigator et les boîtes de dialogue y ont accès.
  return MultiProvider(
    providers: [
      Provider<EtatCouvertures>(
        create: (_) => EtatCouvertures(serviceBibliotheque),
      ),
      ChangeNotifierProvider<EtatBibliotheque>(
        create: (_) => EtatBibliotheque(serviceBibliotheque)..charger(),
      ),
      ChangeNotifierProvider<EtatSources>(
        create: (_) =>
            EtatSources(serviceBibliotheque, serviceAjoutSite)..charger(),
      ),
      // Sur ordinateur, vérification au démarrage puis à intervalle régulier
      // tant que l'application est ouverte ; sur Android, c'est la tâche
      // workmanager qui s'en charge, l'état ne sert qu'au bouton manuel.
      ChangeNotifierProvider<EtatMisesAJour>(
        create: (_) => EtatMisesAJour(
          serviceMisesAJour,
          verifierAuDemarrage: Platform.isWindows || Platform.isLinux,
          intervalle: Platform.isWindows || Platform.isLinux
              ? intervalleMisesAJourBureau
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
