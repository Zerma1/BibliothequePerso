// Tests de EcranSources et EcranAjoutSite avec de faux services.
import 'dart:async';

import 'package:bibliotheque_perso/ecrans/ecran_ajout_site.dart';
import 'package:bibliotheque_perso/ecrans/ecran_sources.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
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

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranSources(),
        bibliotheque: bibliotheque,
        ajoutSite: ajoutSite,
      ),
    );
  }

  Future<void> ouvrirAjout(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(FloatingActionButton, Textes.boutonAjouterSite),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EcranAjoutSite), findsOneWidget);
  }

  testWidgets('chargement, puis message d\'aide quand aucun site', (
    tester,
  ) async {
    bibliotheque.retenue = Completer<void>();
    await afficher(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    bibliotheque.retenue!.complete();
    await tester.pump();
    expect(find.text(Textes.sourcesVide), findsOneWidget);
  });

  testWidgets('erreur de base avec bouton Réessayer', (tester) async {
    bibliotheque.erreurLecture = const ErreurBaseDeDonnees('Disque plein');
    await afficher(tester);
    await tester.pump();

    expect(find.textContaining(Textes.erreurBaseDeDonnees), findsOneWidget);

    bibliotheque
      ..erreurLecture = null
      ..sources.add(
        const Source(
          id: 1,
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
          langueParDefaut: 'en',
        ),
      );
    await tester.tap(find.text(Textes.reessayer));
    await tester.pump();

    expect(find.text('MangaDex'), findsOneWidget);
    expect(find.textContaining('langue : EN'), findsOneWidget);
  });

  testWidgets('affiche le type Scan-Manga (lecture sur le site)', (
    tester,
  ) async {
    bibliotheque.sources.add(
      const Source(
        id: 2,
        nom: 'Scan-Manga',
        urlBase: 'https://www.scan-manga.com',
        typeSource: TypeSource.scanManga,
        langueParDefaut: 'fr',
      ),
    );
    await afficher(tester);
    await tester.pump();

    expect(find.text('Scan-Manga'), findsOneWidget);
    expect(
      find.textContaining('Scan-Manga (lecture sur le site)'),
      findsOneWidget,
    );
  });

  testWidgets('le formulaire propose le type Scan-Manga sans débordement', (
    tester,
  ) async {
    // Écran étroit de téléphone : le libellé long ne doit pas déborder.
    tester.view.physicalSize = const Size(360, 800);
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
    await ouvrirAjout(tester);

    await tester.tap(find.text(Textes.typeAutomatique));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(Textes.libelleTypeSource(TypeSource.scanManga)).last,
    );
    await tester.pumpAndSettle();

    expect(
      find.text(Textes.libelleTypeSource(TypeSource.scanManga)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajoute un site avec nom, langue et type corrigé', (
    tester,
  ) async {
    await afficher(tester);
    await tester.pump();
    await ouvrirAjout(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champUrlSite),
      'https://www.lecture.test/manga/x',
    );
    await tester.pump();
    // Le nom proposé apparaît dès la saisie de l'adresse.
    expect(find.text(Textes.nomPropose('lecture.test')), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champNomSite),
      'Lecture',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champLangue),
      'fr',
    );
    await tester.tap(find.text(Textes.typeAutomatique));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(Textes.libelleTypeSource(TypeSource.mangaThemesia)).last,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
    await tester.pumpAndSettle();

    final appel = ajoutSite.dernierAppel!;
    expect(appel.nom, 'Lecture');
    expect(appel.langue, 'fr');
    expect(appel.type, TypeSource.mangaThemesia);
    expect(find.byType(EcranAjoutSite), findsNothing);
    expect(find.text(Textes.siteAjoute('Lecture')), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
  });

  testWidgets('refuse une langue mal saisie et une adresse vide', (
    tester,
  ) async {
    await afficher(tester);
    await tester.pump();
    await ouvrirAjout(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champLangue),
      'f1',
    );
    await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
    await tester.pump();

    expect(find.text(Textes.champObligatoire), findsOneWidget);
    expect(find.text(Textes.erreurLangue), findsOneWidget);
    expect(ajoutSite.dernierAppel, isNull);
  });

  testWidgets('une erreur du site s\'affiche sous le formulaire', (
    tester,
  ) async {
    ajoutSite.erreurAjout = const ErreurSource(
      'https://exemple.test',
      'Délai dépassé (20 s)',
    );
    await afficher(tester);
    await tester.pump();
    await ouvrirAjout(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champUrlSite),
      'https://exemple.test',
    );
    await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
    await tester.pumpAndSettle();

    expect(find.byType(EcranAjoutSite), findsOneWidget);
    expect(find.textContaining('Délai dépassé'), findsOneWidget);
  });

  testWidgets('montre la progression pendant la détection', (tester) async {
    ajoutSite.retenue = Completer<void>();
    await afficher(tester);
    await tester.pump();
    await ouvrirAjout(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champUrlSite),
      'https://exemple.test',
    );
    await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
    await tester.pump();

    expect(find.text(Textes.detectionEnCours), findsOneWidget);
    ajoutSite.retenue!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(EcranAjoutSite), findsNothing);
  });
}
