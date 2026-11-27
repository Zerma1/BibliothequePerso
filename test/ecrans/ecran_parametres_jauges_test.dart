// Tests des jauges des Paramètres (préférence du client : des jauges
// partout), de la durée de conservation avant suppression et de la section
// « Apparence ».
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_theme.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceParametres parametres;
  late FauxServiceTelechargement telechargement;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    parametres = FauxServiceParametres();
    telechargement = FauxServiceTelechargement(bibliotheque);
  });

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        parametres: parametres,
        telechargement: telechargement,
      ),
    );
    await tester.pump();
    await tester.pump();
    await deplierParametres(tester);
  }

  /// Texte [texte] dans la jauge de clé [cle].
  Finder texteDansJauge(String cle, String texte) => find.descendant(
    of: find.byKey(ValueKey<String>(cle)),
    matching: find.text(texte),
  );

  Future<void> glisserAuBout(
    WidgetTester tester,
    String cle, {
    bool versLaDroite = true,
  }) async {
    await tester.ensureVisible(curseurJauge(cle));
    await tester.pumpAndSettle();
    await tester.drag(
      curseurJauge(cle),
      Offset(versLaDroite ? 2000 : -2000, 0),
    );
    await tester.pumpAndSettle();
  }

  group('limites de téléchargement (0 à 500)', () {
    testWidgets('crans serrés au début, bornes de chaque limite', (
      tester,
    ) async {
      await afficher(tester);

      final favoris = tester.widget<Slider>(
        curseurJauge('jauge.limite.favorisLusConserves'),
      );
      // 0 à 500 : 25 crans (0 à 10 de 1 en 1, puis de plus en plus espacés).
      expect(favoris.divisions, 24);
      // « avant » des suivis commence à 1 : un cran de moins.
      final avant = tester.widget<Slider>(
        curseurJauge('jauge.limite.suivisAvant'),
      );
      expect(avant.divisions, 23);
    });

    testWidgets('glisser modifie le brouillon sans enregistrer ; « − » '
        'ajuste de 1 en 1', (tester) async {
      await afficher(tester);
      const cle = 'jauge.limite.favorisLusConserves';

      await glisserAuBout(tester, cle);
      expect(
        etatDe(tester).valeur(LimiteTelechargement.favorisLusConserves),
        500,
      );
      expect(texteDansJauge(cle, '500'), findsOneWidget);
      expect(
        find.text(
          Textes.explicationLimite(
            LimiteTelechargement.favorisLusConserves,
            500,
          ),
        ),
        findsOneWidget,
      );
      // Rien d'enregistré avant « Enregistrer ».
      expect(parametres.nombreEnregistrements, 0);
      expect(find.text(Textes.modificationsNonEnregistrees), findsOneWidget);

      await tester.tap(boutonJauge(cle, plus: false));
      await tester.pump();
      expect(
        etatDe(tester).valeur(LimiteTelechargement.favorisLusConserves),
        499,
      );
      // Hors des crans : le curseur se place sur le plus proche (500).
      final curseur = tester.widget<Slider>(curseurJauge(cle));
      expect(curseur.value, curseur.max);
    });

    testWidgets('« avant » des suivis ne descend pas sous 1', (tester) async {
      parametres.reglages = parametres.reglages.copierAvec(suivisAvant: 1);
      await afficher(tester);
      const cle = 'jauge.limite.suivisAvant';

      final moins = tester.widget<IconButton>(boutonJauge(cle, plus: false));
      expect(moins.onPressed, isNull);
      await glisserAuBout(tester, cle, versLaDroite: false);
      expect(etatDe(tester).valeur(LimiteTelechargement.suivisAvant), 1);
    });
  });

  group('recherches par jour et « En attente »', () {
    testWidgets('jauge de 1 à 24 enregistrée au lâcher', (tester) async {
      await afficher(tester);
      const cle = 'jauge.recherchesParJour';
      expect(tester.widget<Slider>(curseurJauge(cle)).divisions, 23);

      await glisserAuBout(tester, cle);
      expect(parametres.verificationsParJour, 24);
      expect(texteDansJauge(cle, '24'), findsOneWidget);
      expect(find.text(Textes.planificationEnregistree), findsOneWidget);
    });

    testWidgets('24 recherches par jour : « En attente » vaut 1 h, sans '
        'curseur et boutons inactifs', (tester) async {
      parametres.verificationsParJour = 24;
      await afficher(tester);
      const cle = 'jauge.heuresEnAttente';

      expect(curseurJauge(cle), findsNothing);
      expect(texteDansJauge(cle, Textes.valeurHeures(1)), findsOneWidget);
      for (final plus in <bool>[true, false]) {
        final bouton = tester.widget<IconButton>(boutonJauge(cle, plus: plus));
        expect(bouton.onPressed, isNull);
      }
    });

    testWidgets('« En attente » : maximum dynamique (8 par jour → 3 h)', (
      tester,
    ) async {
      parametres.verificationsParJour = 8;
      await afficher(tester);
      const cle = 'jauge.heuresEnAttente';

      expect(tester.widget<Slider>(curseurJauge(cle)).divisions, 2);
      await glisserAuBout(tester, cle);
      expect(parametres.heuresEnAttente, 3);
      expect(texteDansJauge(cle, Textes.valeurHeures(3)), findsOneWidget);
    });
  });

  group('durée de conservation avant suppression', () {
    testWidgets('crans proposés, libellé lisible, enregistrée au lâcher', (
      tester,
    ) async {
      await afficher(tester);
      const cle = 'jauge.delaiSuppression';

      expect(texteDansJauge(cle, '24 h'), findsOneWidget);
      expect(find.text(Textes.explicationDelaiSuppression), findsOneWidget);
      expect(
        tester.widget<Slider>(curseurJauge(cle)).divisions,
        EtatParametres.delaisSuppressionProposes.length - 1,
      );
      expect(
        find.text(Textes.introReglesTelechargement(const Duration(hours: 24))),
        findsOneWidget,
      );

      await glisserAuBout(tester, cle);
      expect(parametres.delaiSuppression, const Duration(days: 30));
      expect(texteDansJauge(cle, '30 jours'), findsOneWidget);
      expect(
        find.text(Textes.delaiSuppressionEnregistre(const Duration(days: 30))),
        findsOneWidget,
      );
      // L'introduction des règles suit la durée réglée.
      expect(
        find.text(Textes.introReglesTelechargement(const Duration(days: 30))),
        findsOneWidget,
      );
    });

    testWidgets('− / + passent d\'un cran à l\'autre', (tester) async {
      await afficher(tester);
      const cle = 'jauge.delaiSuppression';

      await tester.ensureVisible(boutonJauge(cle, plus: true));
      await tester.tap(boutonJauge(cle, plus: true));
      await tester.pumpAndSettle();
      expect(parametres.delaiSuppression, const Duration(days: 2));
      expect(texteDansJauge(cle, '2 jours'), findsOneWidget);

      await tester.tap(boutonJauge(cle, plus: false));
      await tester.pumpAndSettle();
      await tester.tap(boutonJauge(cle, plus: false));
      await tester.pumpAndSettle();
      expect(parametres.delaiSuppression, const Duration(hours: 12));
    });

    testWidgets('une durée hors des crans (5 h) garde sa valeur affichée', (
      tester,
    ) async {
      parametres.delaiSuppression = const Duration(hours: 5);
      await afficher(tester);
      const cle = 'jauge.delaiSuppression';

      expect(texteDansJauge(cle, '5 h'), findsOneWidget);
      await tester.ensureVisible(boutonJauge(cle, plus: true));
      await tester.tap(boutonJauge(cle, plus: true));
      await tester.pumpAndSettle();
      // Cran suivant : 6 h.
      expect(parametres.delaiSuppression, const Duration(hours: 6));
    });

    testWidgets('pendant le glissement, seule la jauge montre l\'aperçu : '
        'les textes gardent la durée enregistrée', (tester) async {
      await afficher(tester);
      const cle = 'jauge.delaiSuppression';
      final etat = Provider.of<EtatParametres>(
        tester.element(find.byKey(const ValueKey<String>(cle))),
        listen: false,
      );

      etat.previsualiserDelaiSuppression(const Duration(days: 30));
      await tester.pump();

      expect(etat.delaiSuppression, const Duration(days: 30));
      expect(etat.delaiSuppressionEnregistre, const Duration(hours: 24));
      expect(texteDansJauge(cle, '30 jours'), findsOneWidget);
      expect(
        find.text(Textes.introReglesTelechargement(const Duration(hours: 24))),
        findsOneWidget,
      );
      expect(parametres.delaiSuppression, const Duration(hours: 24));
    });
  });

  group('Apparence', () {
    testWidgets('Système / Clair / Sombre : choix appliqué et enregistré', (
      tester,
    ) async {
      await afficher(tester);

      final choix = tester.widget<SegmentedButton<ModeTheme>>(
        find.byType(SegmentedButton<ModeTheme>),
      );
      expect(choix.selected, <ModeTheme>{ModeTheme.systeme});
      for (final mode in ModeTheme.values) {
        expect(find.text(Textes.nomModeTheme(mode)), findsOneWidget);
      }

      await tester.ensureVisible(
        find.text(Textes.nomModeTheme(ModeTheme.sombre)),
      );
      await tester.tap(find.text(Textes.nomModeTheme(ModeTheme.sombre)));
      await tester.pumpAndSettle();

      expect(parametres.modeTheme, ModeTheme.sombre);
      expect(
        tester
            .widget<SegmentedButton<ModeTheme>>(
              find.byType(SegmentedButton<ModeTheme>),
            )
            .selected,
        <ModeTheme>{ModeTheme.sombre},
      );
      expect(
        find.text(Textes.resumeApparence(ModeTheme.sombre)),
        findsOneWidget,
      );
    });
  });
}

/// État des Paramètres fourni à l'écran.
EtatParametres etatDe(WidgetTester tester) => Provider.of<EtatParametres>(
  tester.element(find.byType(EcranParametres)),
  listen: false,
);
