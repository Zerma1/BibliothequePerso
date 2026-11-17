// Tâche T3 : aide « Critères de lecture », réglages avancés (sélecteurs CSS)
// d'un site générique et diagnostic après un refus, dans l'écran d'ajout de
// site. Faux services, aucun réseau.
import 'dart:convert';

import 'package:bibliotheque_perso/ecrans/ecran_sources.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceAjoutSite ajoutSite;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    ajoutSite = FauxServiceAjoutSite(bibliotheque);
  });

  group('EtatSources (réglages avancés)', () {
    test('clés et libellés : ceux du service', () {
      expect(
        EtatSources.clesReglagesGeneriques,
        ServiceAjoutSite.clesReglagesGeneriques,
      );
      expect(
        EtatSources.libelleReglageGenerique('selecteurTitre'),
        ServiceAjoutSite.libelleReglageGenerique('selecteurTitre'),
      );
    });

    test('un champ : vide ou valide sans message, motif invalide refusé', () {
      expect(
        EtatSources.erreurReglageGenerique('motifNumeroChapitre', '  '),
        isNull,
      );
      expect(
        EtatSources.erreurReglageGenerique(
          'motifNumeroChapitre',
          r'chapitre-(\d+)',
        ),
        isNull,
      );
      final message = EtatSources.erreurReglageGenerique(
        'motifNumeroChapitre',
        '(non fermé',
      );
      expect(message, contains('(non fermé'));
      // Libellé retiré : il est déjà affiché au-dessus du champ.
      expect(
        message,
        isNot(
          startsWith(
            ServiceAjoutSite.libelleReglageGenerique('motifNumeroChapitre'),
          ),
        ),
      );
    });

    test('ensemble : le message nomme le champ fautif', () {
      expect(
        EtatSources.erreurReglagesGeneriques(const <String, String>{
          'selecteurTitre': 'h1',
        }),
        isNull,
      );
      expect(
        EtatSources.erreurReglagesGeneriques(const <String, String>{
          'motifNumeroChapitre': '(',
        }),
        startsWith(
          ServiceAjoutSite.libelleReglageGenerique('motifNumeroChapitre'),
        ),
      );
    });

    test('réglage invalide : refusé avant l\'ajout, site non ajouté', () async {
      final etat = EtatSources(bibliotheque, ajoutSite);
      addTearDown(etat.dispose);
      final resultat = await etat.ajouterSite(
        'https://ruri-dragon.online',
        reglagesGeneriques: const <String, String>{
          'motifNumeroChapitre': '(non fermé',
        },
      );
      expect(resultat.estReussi, isFalse);
      expect(resultat.erreur!.nature, NatureErreur.refus);
      expect(
        resultat.erreur!.detail,
        startsWith(
          ServiceAjoutSite.libelleReglageGenerique('motifNumeroChapitre'),
        ),
      );
      expect(ajoutSite.dernierAppel, isNull);
      expect(bibliotheque.sources, isEmpty);
    });

    test('site générique : réglages enregistrés par modifierSource', () async {
      final etat = EtatSources(bibliotheque, ajoutSite);
      addTearDown(etat.dispose);
      final resultat = await etat.ajouterSite(
        'https://ruri-dragon.online',
        reglagesGeneriques: const <String, String>{
          'selecteurLiensChapitres': '.chapitres a',
        },
      );
      expect(resultat.estReussi, isTrue);
      expect(ajoutSite.sourcesModifiees, hasLength(1));
      expect(
        jsonDecode(ajoutSite.sourcesModifiees.single.configurationSelecteurs!),
        <String, Object?>{'selecteurLiensChapitres': '.chapitres a'},
      );
      expect(
        resultat.donnee!.source.configurationSelecteurs,
        contains('.chapitres a'),
      );
    });

    test('autre type ou rien de rempli : aucune modification', () async {
      final etat = EtatSources(bibliotheque, ajoutSite);
      addTearDown(etat.dispose);
      await etat.ajouterSite(
        'https://madara.exemple',
        typeForce: TypeSource.madara,
        reglagesGeneriques: const <String, String>{'selecteurTitre': 'h1'},
      );
      await etat.ajouterSite('https://vide.exemple');
      expect(ajoutSite.sourcesModifiees, isEmpty);
    });

    test('diagnostic : rendu du service', () async {
      final etat = EtatSources(bibliotheque, ajoutSite);
      addTearDown(etat.dispose);
      final resultat = await etat.diagnostiquerSite(' https://a.exemple ');
      expect(resultat.donnee?.estLisible, isTrue);
      expect(bibliotheque.sitesDiagnostiques, <String>['https://a.exemple']);
    });
  });

  group('écran', () {
    Future<void> ouvrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        envelopper(
          const EcranSources(),
          bibliotheque: bibliotheque,
          ajoutSite: ajoutSite,
        ),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterSite),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('aide « Critères de lecture » repliable', (tester) async {
      await ouvrir(tester);
      expect(find.text(Textes.criteresLecture), findsOneWidget);
      expect(find.text(Textes.aideCriteresLecture), findsNothing);
      await tester.tap(find.text(Textes.criteresLecture));
      await tester.pumpAndSettle();
      expect(find.text(Textes.aideCriteresLecture), findsOneWidget);
    });

    testWidgets('réglages avancés : une ligne par clé, enregistrés en JSON', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(find.text(Textes.reglagesAvancesSelecteurs));
      await tester.pumpAndSettle();
      for (final cle in EtatSources.clesReglagesGeneriques) {
        expect(find.byKey(ValueKey<String>('reglage_$cle')), findsOneWidget);
      }
      await tester.enterText(
        find.widgetWithText(TextFormField, Textes.champUrlSite),
        'https://ruri-dragon.online',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reglage_selecteurImagesChapitre')),
        '.lecture img',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(ajoutSite.sourcesModifiees.single.configurationSelecteurs!),
        <String, Object?>{'selecteurImagesChapitre': '.lecture img'},
      );
    });

    testWidgets('motif invalide : refusé avant l\'envoi', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.text(Textes.reglagesAvancesSelecteurs));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, Textes.champUrlSite),
        'https://ruri-dragon.online',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reglage_motifNumeroChapitre')),
        '(non fermé',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      // Sous le champ (sans le libellé) et sous le formulaire (avec).
      expect(
        find.text(
          EtatSources.erreurReglageGenerique(
            'motifNumeroChapitre',
            '(non fermé',
          )!,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          EtatSources.erreurReglagesGeneriques(const <String, String>{
            'motifNumeroChapitre': '(non fermé',
          })!,
        ),
        findsOneWidget,
      );
      expect(ajoutSite.dernierAppel, isNull);
      expect(bibliotheque.sources, isEmpty);
    });

    testWidgets('type non générique : pas de réglages avancés', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.text(Textes.typeAutomatique));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(Textes.libelleTypeSource(TypeSource.madara)).last,
      );
      await tester.pumpAndSettle();
      expect(find.text(Textes.reglagesAvancesSelecteurs), findsNothing);
    });

    testWidgets('échec : « Pourquoi ce site n\'est pas lisible ? »', (
      tester,
    ) async {
      ajoutSite.erreurAjout = const ErreurSource(
        'https://bloque.exemple',
        'Protection anti-robot',
        protectionAntiRobot: true,
      );
      bibliotheque.diagnosticSite = const DiagnosticLisibilite(
        raisons: <String>['Le site bloque les programmes automatiques'],
        protectionAntiRobot: true,
      );
      await ouvrir(tester);
      expect(find.text(Textes.pourquoiIllisible), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, Textes.champUrlSite),
        'https://bloque.exemple',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.pourquoiIllisible));
      await tester.pumpAndSettle();
      expect(bibliotheque.sitesDiagnostiques, <String>[
        'https://bloque.exemple',
      ]);
      expect(find.text(Textes.explicationProtectionAntiRobot), findsOneWidget);
      expect(
        find.text('• Le site bloque les programmes automatiques'),
        findsOneWidget,
      );
    });
  });
}
