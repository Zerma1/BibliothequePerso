/// Point d'entrée de l'application « Bibliothèque perso ».
///
/// Pour l'instant, l'application affiche seulement un écran d'accueil temporaire :
/// la base de données et les fournisseurs (providers) arrivent aux étapes suivantes
/// de la feuille de route (PLAYBOOK.md section 11).
library;

import 'package:material_ui/material_ui.dart';

/// Lance l'application.
void main() {
  // À FAIRE (étape 1) : initialiser sqflite_common_ffi sur Windows et Linux uniquement,
  // ouvrir la base SQLite et appliquer les migrations avant runApp.
  // À FAIRE (étape 1) : envelopper l'application dans les fournisseurs (provider).
  // À FAIRE (étape 4) : initialiser workmanager uniquement si Platform.isAndroid.
  runApp(const BibliothequePersoApp());
}

/// Racine de l'application : thème Material 3 et écran d'accueil.
class BibliothequePersoApp extends StatelessWidget {
  /// Crée la racine de l'application.
  const BibliothequePersoApp({super.key});

  /// Titre affiché dans la barre de l'application et par le système.
  static const String titreApplication = 'Bibliothèque perso';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: titreApplication,
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
      home: const _EcranAccueilTemporaire(),
    );
  }
}

/// Écran d'accueil provisoire, remplacé par `EcranBibliotheque` à l'étape 3.
class _EcranAccueilTemporaire extends StatelessWidget {
  const _EcranAccueilTemporaire();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(BibliothequePersoApp.titreApplication)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bienvenue ! Votre bibliothèque est encore vide.\n'
            'Les sources et les titres arriveront dans les prochaines étapes.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
