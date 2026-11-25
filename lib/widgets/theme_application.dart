/// Thèmes clair et sombre de l'application, et conversion du choix du
/// client (Paramètres → Apparence) en `ThemeMode`.
library;

import 'package:material_ui/material_ui.dart';

import '../etat/etat_theme.dart';
import 'constantes_interface.dart';

/// Thème Material 3 de [luminosite], dérivé de l'indigo du logo.
///
/// Une seule couleur source pour les deux thèmes : `ColorScheme.fromSeed`
/// calcule des couleurs dont le contraste est garanti en clair comme en
/// sombre (texte sur fond, rouge des suppressions prévues sur son fond),
/// ce qu'une palette faite à la main ne garantirait pas.
// L'orange du logo n'entre pas dans la palette : dans l'application, l'orange
// signale un doublon (décision du client) ; en faire une couleur d'accent
// brouillerait ce signal.
ThemeData construireTheme(Brightness luminosite) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(couleurLogoIndigo),
    brightness: luminosite,
  ),
);

/// Thème clair de l'application.
final ThemeData themeClair = construireTheme(Brightness.light);

/// Thème sombre de l'application.
final ThemeData themeSombre = construireTheme(Brightness.dark);

/// `ThemeMode` de `MaterialApp` pour le choix du client ; `null` (état du
/// thème absent, par exemple sur l'écran d'erreur de démarrage) suit le
/// système.
ThemeMode versThemeMode(ModeTheme? mode) => switch (mode) {
  ModeTheme.clair => ThemeMode.light,
  ModeTheme.sombre => ThemeMode.dark,
  ModeTheme.systeme || null => ThemeMode.system,
};
