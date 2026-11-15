/// Point d'entrée de l'application « Bibliothèque perso ».
///
/// Ouvre la base, assemble les dépôts, les sources et les services, puis
/// fournit les états à l'interface (PLAYBOOK.md section 4 : `main.dart`
/// initialise la base et les fournisseurs).
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'donnees/base_de_donnees.dart';
import 'donnees/depot_categories.dart';
import 'donnees/depot_chapitres.dart';
import 'donnees/depot_listes.dart';
import 'donnees/depot_sources.dart';
import 'donnees/depot_titres.dart';
import 'ecrans/ecran_accueil.dart';
import 'ecrans/ecran_erreur_demarrage.dart';
import 'etat/etat_bibliotheque.dart';
import 'etat/etat_couvertures.dart';
import 'etat/etat_sources.dart';
import 'services/service_ajout_site.dart';
import 'services/service_bibliotheque.dart';
import 'sources/client_http_poli.dart';
import 'sources/detecteur_type_site.dart';
import 'sources/fabrique_sources.dart';
import 'widgets/textes.dart';

/// Lance l'application.
Future<void> main() async {
  // Exigé par path_provider (chemin de la base) avant runApp.
  WidgetsFlutterBinding.ensureInitialized();
  // À FAIRE (étape 4) : initialiser workmanager uniquement si Platform.isAndroid.
  await demarrer();
}

/// Ouvre la base et affiche l'application, ou un écran d'erreur lisible si
/// la base ne peut pas être ouverte (au lieu d'un plantage).
Future<void> demarrer() async {
  Widget application;
  try {
    final base = await ouvrirBaseDeDonnees();
    // Un seul client HTTP pour toute l'application : le délai minimal entre
    // deux requêtes vers un même domaine est ainsi partagé par tous les
    // services (PLAYBOOK.md section 6).
    final client = ClientHttpPoli();
    final depotSources = DepotSources(base);
    final serviceAjoutSite = ServiceAjoutSite(
      depotSources,
      DetecteurTypeSite(client),
    );
    final serviceBibliotheque = ServiceBibliotheque(
      depotSources: depotSources,
      depotTitres: DepotTitres(base),
      depotChapitres: DepotChapitres(base),
      depotListes: DepotListes(base),
      depotCategories: DepotCategories(base),
      fabriqueSources: FabriqueSources(client),
      serviceAjoutSite: serviceAjoutSite,
      client: client,
    );
    application = construireApplication(
      serviceBibliotheque: serviceBibliotheque,
      serviceAjoutSite: serviceAjoutSite,
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
