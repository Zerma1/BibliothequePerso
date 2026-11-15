// Tests de EcranTitre avec de faux services.
import 'package:bibliotheque_perso/ecrans/ecran_lecteur.dart';
import 'package:bibliotheque_perso/ecrans/ecran_titre.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';

void main() {
  late FauxServiceBibliotheque service;

  /// Prépare un titre de la source [type] avec deux chapitres.
  void preparer({TypeSource type = TypeSource.mangaDex}) {
    service.sources.add(
      Source(
        id: 1,
        nom: 'Site de test',
        urlBase: 'https://mangadex.org',
        typeSource: type,
      ),
    );
    final titre = service.ajouterTitreDeTest(
      'Shinigami',
      idSource: 1,
      nomsCategories: <String>['action', 'gore'],
      idsListes: <int>{1},
      urlCouverture: 'https://uploads.mangadex.org/covers/c.jpg',
      chapitres: <Chapitre>[
        Chapitre(
          id: 1,
          urlChapitre: 'https://mangadex.org/chapter/1',
          nom: 'Le début',
          numero: 1,
          langue: 'en',
          datePublication: DateTime.utc(2026, 1, 10, 12),
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'https://mangadex.org/chapter/2',
          nom: '',
          numero: 2,
          langue: 'fr',
        ),
      ],
    );
    service.titres[0] = titre.copierAvec(
      auteur: 'Auteur de test',
      statut: 'En cours',
      resume: 'Une jeune fille élevée par la Mort.',
      titresAlternatifs: const <TitreAlternatif>[
        TitreAlternatif(nom: "Death's Daughter", langue: 'en'),
        TitreAlternatif(nom: '死神に育てられた少女', langue: 'ja'),
      ],
    );
  }

  setUp(() => service = FauxServiceBibliotheque());

  Future<void> afficher(WidgetTester tester, {double largeur = 1200}) async {
    tester.view.physicalSize = Size(largeur, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        ChangeNotifierProvider<EtatTitre>(
          create: (_) => EtatTitre(service, 1)..charger(),
          child: const EcranTitre(),
        ),
        bibliotheque: service,
      ),
    );
    await tester.pump();
  }

  testWidgets('affiche la fiche complète et crédite MangaDex', (tester) async {
    preparer();
    await afficher(tester);

    expect(find.text('Shinigami'), findsWidgets);
    expect(find.textContaining('Auteur de test'), findsOneWidget);
    expect(find.textContaining('En cours'), findsOneWidget);
    expect(find.text('Une jeune fille élevée par la Mort.'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Gore'), findsOneWidget);
    expect(find.text(Textes.creditMangaDex), findsOneWidget);
    expect(find.text(Textes.ouvrirSurLeSite), findsOneWidget);
    // La couverture est demandée avec le Referer du site du titre.
    expect(service.referersDemandes, contains('https://mangadex.org'));

    // Titres alternatifs repliés par défaut.
    expect(find.text(Textes.titresAlternatifs(2)), findsOneWidget);
    expect(find.text("Death's Daughter"), findsNothing);
    await tester.tap(find.text(Textes.titresAlternatifs(2)));
    await tester.pumpAndSettle();
    expect(find.text("Death's Daughter"), findsOneWidget);

    // Chapitres : le plus grand numéro en haut, avec langue et date.
    final haut2 = tester.getTopLeft(find.text('Chapitre 2')).dy;
    final haut1 = tester.getTopLeft(find.text('Le début')).dy;
    expect(haut2, lessThan(haut1));
    // Langue et date sont dans leurs propres colonnes.
    expect(find.text('FR'), findsOneWidget);
    // « EN » aussi dans les titres alternatifs dépliés.
    expect(find.text('EN'), findsNWidgets(2));
    expect(find.text('10/01/2026'), findsOneWidget);
    expect(find.text(Textes.enTeteNumeros(2, 2)), findsOneWidget);
  });

  group('chapitres hors-ligne', () {
    late FauxServiceTelechargement telechargement;

    Future<void> afficherAvecTelechargements(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        envelopper(
          ChangeNotifierProvider<EtatTitre>(
            create: (_) =>
                EtatTitre(service, 1, serviceTelechargement: telechargement)
                  ..charger(),
            child: const EcranTitre(),
          ),
          bibliotheque: service,
          telechargement: telechargement,
        ),
      );
      await tester.pump();
    }

    setUp(() => telechargement = FauxServiceTelechargement(service));

    testWidgets('légende des colonnes et des icônes', (tester) async {
      preparer();
      await afficherAvecTelechargements(tester);

      for (final colonne in <String>[
        Textes.colonneChapitre,
        Textes.colonneLangue,
        Textes.colonneDate,
        Textes.colonneHorsLigne,
        Textes.colonneLu,
      ]) {
        expect(find.text(colonne), findsOneWidget);
      }
      expect(find.text(Textes.aideAppuiChapitre), findsOneWidget);
      expect(find.text('Téléchargé'), findsOneWidget);
      expect(find.text('Non téléchargé (en ligne seulement)'), findsOneWidget);
    });

    testWidgets('chaque ligne montre son état hors-ligne', (tester) async {
      preparer();
      telechargement.ajouterChapitreTelecharge(1);
      telechargement.modifierLigne(
        2,
        StatutTelechargement.enCours,
        faites: 1,
        total: 4,
      );
      await afficherAvecTelechargements(tester);

      expect(
        find.byTooltip('Téléchargé — appuyer pour supprimer le téléchargement'),
        findsOneWidget,
      );
      expect(find.text('25 %'), findsOneWidget);

      // La progression suit la file en direct.
      telechargement.modifierLigne(
        2,
        StatutTelechargement.enCours,
        faites: 3,
        total: 4,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('75 %'), findsOneWidget);
    });

    testWidgets(
      'un appui sur un chapitre non téléchargé ouvre un menu, jamais le site',
      (tester) async {
        preparer();
        await afficherAvecTelechargements(tester);

        await tester.tap(find.text('Le début'));
        await tester.pumpAndSettle();
        expect(find.text(Textes.telecharger), findsOneWidget);
        expect(
          find.widgetWithText(ListTile, Textes.ouvrirSurLeSite),
          findsOneWidget,
        );

        await tester.tap(find.text(Textes.telecharger));
        await tester.pumpAndSettle();
        expect(telechargement.journal, contains('telecharger:1'));
        expect(find.text(Textes.telechargementAjoute), findsOneWidget);
        expect(
          find.byTooltip(
            'En file d\'attente — appuyer pour retirer de la file',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('un chapitre téléchargé s\'ouvre dans le lecteur', (
      tester,
    ) async {
      preparer();
      telechargement.ajouterChapitreTelecharge(1, nombrePages: 2);
      await afficherAvecTelechargements(tester);

      await tester.tap(find.text('Le début'));
      await tester.pumpAndSettle();
      expect(find.byType(EcranLecteur), findsOneWidget);
      expect(find.text(Textes.pageSurTotal(1, 2)), findsOneWidget);
    });

    testWidgets('supprimer le téléchargement après confirmation', (
      tester,
    ) async {
      preparer();
      telechargement.ajouterChapitreTelecharge(1);
      await afficherAvecTelechargements(tester);

      await tester.tap(
        find.byTooltip('Téléchargé — appuyer pour supprimer le téléchargement'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, Textes.supprimer));
      await tester.pumpAndSettle();

      expect(telechargement.journal, contains('supprimer:1'));
      expect(find.text(Textes.telechargementSupprime), findsOneWidget);
    });

    testWidgets('marquer lu ou changer de liste applique les règles', (
      tester,
    ) async {
      preparer();
      await afficherAvecTelechargements(tester);

      await tester.tap(find.byTooltip(Textes.marquerLu).first);
      await tester.pump();
      expect(telechargement.reglesAppliquees, <int>[1]);

      await tester.tap(find.widgetWithText(FilterChip, 'Suivis'));
      await tester.pump();
      expect(telechargement.reglesAppliquees, <int>[1, 1]);

      // Une liste personnelle ne déclenche pas de téléchargement.
      await tester.tap(find.widgetWithText(FilterChip, 'À lire plus tard'));
      await tester.pump();
      expect(telechargement.reglesAppliquees, <int>[1, 1]);
    });

    testWidgets('un même numéro en deux langues tient sur une ligne', (
      tester,
    ) async {
      preparer();
      service.chapitresParTitre[1]!.add(
        const Chapitre(
          id: 3,
          idTitre: 1,
          urlChapitre: 'https://mangadex.org/chapter/3',
          nom: 'The beginning',
          numero: 1,
          langue: 'en',
        ),
      );
      // Le chapitre 1 existant devient la version française.
      service.chapitresParTitre[1]![0] = service.chapitresParTitre[1]![0]
          .copierAvec(langue: 'fr');
      service.sources[0] = service.sources[0].copierAvec(
        langueParDefaut: 'fr,en',
      );
      await afficherAvecTelechargements(tester);

      expect(find.text(Textes.enTeteNumeros(2, 2)), findsOneWidget);
      expect(find.text('Le début'), findsOneWidget);
      expect(find.text('The beginning'), findsNothing);
      await tester.tap(find.text(Textes.autresVersions(1)));
      await tester.pump();
      expect(find.text('The beginning'), findsOneWidget);
    });
  });

  testWidgets(
    'pas de crédit MangaDex pour un autre site, disposition étroite',
    (tester) async {
      preparer(type: TypeSource.madara);
      await afficher(tester, largeur: 400);

      expect(find.text(Textes.creditMangaDex), findsNothing);
      expect(find.text('Le début'), findsOneWidget);
    },
  );

  testWidgets('marque un chapitre lu puis tout non lu', (tester) async {
    preparer();
    await afficher(tester);

    await tester.tap(find.byTooltip(Textes.marquerLu).first);
    await tester.pump();
    expect(find.text(Textes.enTeteChapitres(2, 1)), findsOneWidget);
    expect(find.byTooltip(Textes.marquerNonLu), findsOneWidget);
    expect(service.chapitresParTitre[1]!.where((c) => c.estLu), hasLength(1));
  });

  testWidgets('menu : tout marquer comme lu', (tester) async {
    preparer();
    await afficher(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.toutMarquerLu));
    await tester.pumpAndSettle();

    expect(find.text(Textes.enTeteChapitres(2, 0)), findsOneWidget);
  });

  testWidgets('coche et décoche les listes', (tester) async {
    preparer();
    await afficher(tester);

    final suivis = find.widgetWithText(FilterChip, 'Suivis');
    expect(tester.widget<FilterChip>(suivis).selected, isFalse);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Favoris'))
          .selected,
      isTrue,
    );

    await tester.tap(suivis);
    await tester.pump();
    expect(tester.widget<FilterChip>(suivis).selected, isTrue);
    expect(service.listesParTitre[1], contains(2));

    await tester.tap(suivis);
    await tester.pump();
    expect(service.listesParTitre[1], isNot(contains(2)));
  });

  testWidgets('actualise et annonce les nouveaux chapitres', (tester) async {
    preparer();
    service.nombreNouveaux = 1;
    await afficher(tester);

    await tester.tap(find.byTooltip(Textes.actualiser));
    await tester.pump();
    await tester.pump();

    expect(find.text(Textes.actualisationTerminee(1)), findsOneWidget);
  });

  testWidgets('une actualisation refusée affiche le message', (tester) async {
    preparer();
    service.erreurAjout = const ErreurService('Le site n\'existe plus.');
    await afficher(tester);

    await tester.tap(find.byTooltip(Textes.actualiser));
    await tester.pump();
    await tester.pump();

    expect(find.text('Le site n\'existe plus.'), findsOneWidget);
  });

  testWidgets('supprime le titre après confirmation et ferme la fiche', (
    tester,
  ) async {
    preparer();
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // La fiche est ouverte par-dessus un autre écran, comme dans
    // l'application, pour vérifier qu'elle se ferme.
    await tester.pumpWidget(
      envelopper(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => EcranTitre.ouvrir(context, 1),
              child: const Text('ouvrir'),
            ),
          ),
        ),
        bibliotheque: service,
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byType(EcranTitre), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.supprimerTitre));
    await tester.pumpAndSettle();
    expect(
      find.text(Textes.confirmationSuppression('Shinigami')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, Textes.supprimer));
    await tester.pumpAndSettle();

    expect(service.titres, isEmpty);
    expect(find.byType(EcranTitre), findsNothing);
    expect(find.text(Textes.titreSupprime('Shinigami')), findsOneWidget);
  });

  testWidgets('titre introuvable : message et bouton Réessayer', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.textContaining(Textes.erreurIntrouvable), findsOneWidget);
    expect(find.text(Textes.reessayer), findsOneWidget);
  });
}
