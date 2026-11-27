// Tests de EtatTheme (Paramètres → Apparence) et de la conversion du
// choix en ThemeMode.
import 'package:bibliotheque_perso/etat/etat_theme.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/theme_application.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'outils_tests_etat.dart';

/// Faux service dont l'enregistrement du thème échoue.
class _ParametresEnPanne extends FauxServiceParametres {
  @override
  Future<void> enregistrerModeTheme(ModeTheme mode) async =>
      throw const ErreurService('Base occupée.');

  @override
  Future<ModeTheme> chargerModeTheme() async =>
      throw const ErreurService('Base occupée.');
}

void main() {
  test('lit le choix enregistré, puis l\'applique et l\'enregistre', () async {
    final parametres = FauxServiceParametres()..modeTheme = ModeTheme.clair;
    final etat = EtatTheme(parametres);
    expect(etat.mode, ModeTheme.systeme);

    await etat.charger();
    expect(etat.mode, ModeTheme.clair);

    final resultat = await etat.modifier(ModeTheme.sombre);
    expect(resultat.estReussi, isTrue);
    expect(etat.mode, ModeTheme.sombre);
    expect(parametres.modeTheme, ModeTheme.sombre);
  });

  test('mode initial donné avant l\'affichage', () {
    final etat = EtatTheme(
      FauxServiceParametres(),
      modeInitial: ModeTheme.sombre,
    );
    expect(etat.mode, ModeTheme.sombre);
  });

  test('erreurs : lecture ignorée (thème du système), enregistrement '
      'annulé', () async {
    final etat = EtatTheme(_ParametresEnPanne());
    await etat.charger();
    expect(etat.mode, ModeTheme.systeme);

    final resultat = await etat.modifier(ModeTheme.sombre);
    expect(resultat.estReussi, isFalse);
    expect(etat.mode, ModeTheme.systeme);
    expect(etat.estEnEnregistrement, isFalse);
  });

  test('conversion en ThemeMode', () {
    expect(versThemeMode(ModeTheme.systeme), ThemeMode.system);
    expect(versThemeMode(ModeTheme.clair), ThemeMode.light);
    expect(versThemeMode(ModeTheme.sombre), ThemeMode.dark);
    expect(versThemeMode(null), ThemeMode.system);
  });

  test('thèmes clair et sombre issus de l\'indigo du logo', () {
    expect(themeClair.colorScheme.brightness, Brightness.light);
    expect(themeSombre.colorScheme.brightness, Brightness.dark);
    expect(themeClair.useMaterial3, isTrue);
    // Même couleur source : les deux schémas sont ceux de fromSeed.
    expect(
      themeSombre.colorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
      ).primary,
    );
  });

  testWidgets('une application qui surveille l\'état passe au sombre sans '
      'redémarrer', (tester) async {
    final etat = EtatTheme(FauxServiceParametres());
    late BuildContext contexte;
    await tester.pumpWidget(
      ChangeNotifierProvider<EtatTheme>.value(
        value: etat,
        // Même branchement que la racine de l'application (main.dart).
        child: Builder(
          builder: (context) => MaterialApp(
            theme: themeClair,
            darkTheme: themeSombre,
            themeMode: versThemeMode(context.watch<EtatTheme?>()?.mode),
            home: Builder(
              builder: (context) {
                contexte = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await etat.modifier(ModeTheme.clair);
    await tester.pumpAndSettle();
    expect(Theme.of(contexte).brightness, Brightness.light);

    await etat.modifier(ModeTheme.sombre);
    await tester.pumpAndSettle();
    expect(Theme.of(contexte).brightness, Brightness.dark);
  });
}
