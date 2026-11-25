// Tests du réglage « Démarrer avec Windows » (Paramètres → Démarrage) et de
// son état.
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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

  group('état', () {
    test('lit le mode enregistré', () async {
      parametres.modeDemarrage = ModeDemarrage.iconeMasquee;
      final etat = EtatParametres(parametres, telechargement, estWindows: true);
      addTearDown(etat.dispose);
      await etat.charger();
      expect(etat.modeDemarrage, ModeDemarrage.iconeMasquee);
      expect(etat.demarrageAvecWindowsDisponible, isTrue);
    });

    test('enregistre puis appelle le rappel avec le mode choisi', () async {
      final appels = <ModeDemarrage>[];
      final etat = EtatParametres(
        parametres,
        telechargement,
        estWindows: true,
        surChangementModeDemarrage: (mode) async {
          // L'inscription n'a lieu qu'une fois le choix enregistré.
          expect(parametres.modeDemarrage, mode);
          appels.add(mode);
          return true;
        },
      );
      addTearDown(etat.dispose);
      await etat.charger();

      final resultat = await etat.modifierModeDemarrage(
        ModeDemarrage.pleineFenetre,
      );
      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee, isTrue);
      expect(appels, <ModeDemarrage>[ModeDemarrage.pleineFenetre]);
      expect(parametres.modeDemarrage, ModeDemarrage.pleineFenetre);
      expect(etat.modeDemarrage, ModeDemarrage.pleineFenetre);
      expect(etat.estEnEnregistrementDemarrage, isFalse);

      // Même mode : rien n'est refait.
      await etat.modifierModeDemarrage(ModeDemarrage.pleineFenetre);
      expect(appels, hasLength(1));
    });

    test('refus de Windows : ancien mode rétabli et réenregistré', () async {
      parametres.modeDemarrage = ModeDemarrage.pleineFenetre;
      final etat = EtatParametres(
        parametres,
        telechargement,
        estWindows: true,
        surChangementModeDemarrage: (_) async => false,
      );
      addTearDown(etat.dispose);
      await etat.charger();

      final resultat = await etat.modifierModeDemarrage(
        ModeDemarrage.iconeMasquee,
      );
      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee, isFalse);
      expect(etat.modeDemarrage, ModeDemarrage.pleineFenetre);
      expect(parametres.modeDemarrage, ModeDemarrage.pleineFenetre);
    });

    test('rappel en erreur : traité comme un refus', () async {
      final etat = EtatParametres(
        parametres,
        telechargement,
        estWindows: true,
        surChangementModeDemarrage: (_) async => throw StateError('registre'),
      );
      addTearDown(etat.dispose);
      await etat.charger();

      final resultat = await etat.modifierModeDemarrage(
        ModeDemarrage.pleineFenetre,
      );
      expect(resultat.donnee, isFalse);
      expect(etat.modeDemarrage, ModeDemarrage.desactive);
      expect(parametres.modeDemarrage, ModeDemarrage.desactive);
    });

    test('sans rappel : le choix est seulement enregistré', () async {
      final etat = EtatParametres(parametres, telechargement, estWindows: true);
      addTearDown(etat.dispose);
      await etat.charger();

      final resultat = await etat.modifierModeDemarrage(
        ModeDemarrage.iconeMasquee,
      );
      expect(resultat.donnee, isTrue);
      expect(parametres.modeDemarrage, ModeDemarrage.iconeMasquee);
    });
  });

  group('écran', () {
    Future<void> ouvrir(
      WidgetTester tester, {
      required bool estWindows,
      InscriptionDemarrage? surChangementModeDemarrage,
    }) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        envelopper(
          const EcranParametres(),
          bibliotheque: bibliotheque,
          parametres: parametres,
          telechargement: telechargement,
          estWindows: estWindows,
          surChangementModeDemarrage: surChangementModeDemarrage,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('section absente hors de Windows', (tester) async {
      await ouvrir(tester, estWindows: false);
      expect(find.text(Textes.sectionDemarrage), findsNothing);
      expect(find.byType(SegmentedButton<ModeDemarrage>), findsNothing);
    });

    testWidgets('sous Windows : résumé, trois choix, explication, '
        'enregistrement et inscription', (tester) async {
      final appels = <ModeDemarrage>[];
      await ouvrir(
        tester,
        estWindows: true,
        surChangementModeDemarrage: (mode) async {
          appels.add(mode);
          return true;
        },
      );
      expect(find.text(Textes.sectionDemarrage), findsOneWidget);
      expect(
        find.text(Textes.resumeDemarrage(ModeDemarrage.desactive)),
        findsOneWidget,
      );

      await basculerSection(tester, Textes.sectionDemarrage);
      expect(find.byType(SegmentedButton<ModeDemarrage>), findsOneWidget);
      for (final mode in ModeDemarrage.values) {
        expect(find.text(Textes.nomModeDemarrage(mode)), findsOneWidget);
      }
      expect(
        find.text(Textes.explicationModeDemarrage(ModeDemarrage.desactive)),
        findsOneWidget,
      );

      await tester.tap(
        find.text(Textes.nomModeDemarrage(ModeDemarrage.iconeMasquee)),
      );
      await tester.pumpAndSettle();

      expect(parametres.modeDemarrage, ModeDemarrage.iconeMasquee);
      expect(appels, <ModeDemarrage>[ModeDemarrage.iconeMasquee]);
      expect(
        find.text(Textes.explicationModeDemarrage(ModeDemarrage.iconeMasquee)),
        findsOneWidget,
      );
      final bouton = tester.widget<SegmentedButton<ModeDemarrage>>(
        find.byType(SegmentedButton<ModeDemarrage>),
      );
      expect(bouton.selected, <ModeDemarrage>{ModeDemarrage.iconeMasquee});
      expect(find.text(Textes.demarrageRefuseParWindows), findsNothing);
    });

    testWidgets("refus de Windows : message et retour à l'ancien choix", (
      tester,
    ) async {
      await ouvrir(
        tester,
        estWindows: true,
        surChangementModeDemarrage: (_) async => false,
      );
      await basculerSection(tester, Textes.sectionDemarrage);

      await tester.tap(
        find.text(Textes.nomModeDemarrage(ModeDemarrage.pleineFenetre)),
      );
      await tester.pumpAndSettle();

      expect(find.text(Textes.demarrageRefuseParWindows), findsOneWidget);
      expect(parametres.modeDemarrage, ModeDemarrage.desactive);
      final bouton = tester.widget<SegmentedButton<ModeDemarrage>>(
        find.byType(SegmentedButton<ModeDemarrage>),
      );
      expect(bouton.selected, <ModeDemarrage>{ModeDemarrage.desactive});
    });
  });
}
