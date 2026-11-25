// Tests de l'interface de l'étape 6 avec de faux services : rapport d'erreur
// exportable, choix de la couverture, listes Planifié / En attente, repère
// « gardé », langues régionales d'un site, surveillance « En attente ».
import 'package:bibliotheque_perso/ecrans/ecran_bibliotheque.dart';
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/ecrans/ecran_sources.dart';
import 'package:bibliotheque_perso/ecrans/ecran_titre.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_bibliotheque.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/sources/couverture_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;

  setUp(() => bibliotheque = FauxServiceBibliotheque());

  void taille(
    WidgetTester tester, {
    double largeur = 1000,
    double hauteur = 1400,
  }) {
    tester.view.physicalSize = Size(largeur, hauteur);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('rapport d\'erreur', () {
    testWidgets('ajout d\'un site en échec : export et chemin affiché', (
      tester,
    ) async {
      final ajoutSite = FauxServiceAjoutSite(bibliotheque)
        ..erreurAjout = const ErreurSource('https://exemple.test', 'HTTP 403');
      final rapports = FauxServiceRapportsErreur();
      taille(tester);
      await tester.pumpWidget(
        envelopper(
          const EcranSources(),
          bibliotheque: bibliotheque,
          ajoutSite: ajoutSite,
          rapports: rapports,
        ),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterSite),
      );
      await tester.pumpAndSettle();
      // Pas de bouton tant que rien n'a échoué.
      expect(find.text(Textes.exporterRapport), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextFormField, Textes.champUrlSite),
        'https://exemple.test',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.exporterRapport));
      await tester.pumpAndSettle();

      expect(rapports.exportes, hasLength(1));
      expect(rapports.exportes.single.erreur, isA<ErreurSource>());
      expect(rapports.exportes.single.action, Textes.actionRapportAjoutSite);
      expect(find.text(Textes.rapportEnregistre), findsOneWidget);
      expect(find.text('C:/rapports/rapport_1.txt'), findsOneWidget);
      await tester.tap(find.text(Textes.fermer));
      await tester.pumpAndSettle();
      expect(find.text(Textes.rapportEnregistre), findsNothing);
    });

    testWidgets('ajout d\'un titre : bouton pour une erreur du site, pas pour '
        'un simple refus', (tester) async {
      final rapports = FauxServiceRapportsErreur();
      bibliotheque.erreurAjout = const ErreurService(
        "Ce site n'est pas encore configuré.",
      );
      taille(tester);
      await tester.pumpWidget(
        envelopper(
          const EcranBibliotheque(),
          bibliotheque: bibliotheque,
          rapports: rapports,
        ),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterTitre),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champUrlTitre),
        'https://exemple.test/manga/x',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      expect(find.text(Textes.exporterRapport), findsNothing);

      bibliotheque.erreurAjout = const ErreurSource(
        'https://mangadex.org/title/x',
        'Réponse illisible',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.exporterRapport));
      await tester.pumpAndSettle();
      expect(rapports.exportes.single.action, Textes.actionRapportAjoutTitre);
    });

    test('une erreur du service causée par un site est rapportable', () {
      final description = DescriptionErreur.depuis(
        const ErreurService(
          'Le site ne répond pas.',
          cause: ErreurSource('https://x.test', 'HTTP 500'),
        ),
      );
      expect(description.estRapportable, isTrue);
      expect(description.cause, isA<ErreurService>());
      expect(
        DescriptionErreur.depuis(const ErreurService('Refus.')).estRapportable,
        isFalse,
      );
      expect(
        const DescriptionErreur(NatureErreur.adresseVide).estRapportable,
        isFalse,
      );
    });
  });

  group('fiche d\'un titre', () {
    void preparer({Set<int> listes = const <int>{1}}) {
      bibliotheque.sources.add(
        const Source(
          id: 1,
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
        ),
      );
      bibliotheque.ajouterTitreDeTest(
        'Shinigami',
        idSource: 1,
        idsListes: listes,
        urlCouverture: 'https://uploads.mangadex.org/covers/a/v1.jpg',
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: '', numero: 1, langue: 'fr'),
        ],
      );
    }

    Future<FauxServiceTelechargement> afficher(WidgetTester tester) async {
      final telechargement = FauxServiceTelechargement(bibliotheque);
      taille(tester);
      await tester.pumpWidget(
        envelopper(
          ChangeNotifierProvider<EtatTitre>(
            create: (_) => EtatTitre(
              bibliotheque,
              1,
              serviceTelechargement: telechargement,
            )..charger(),
            child: const EcranTitre(),
          ),
          bibliotheque: bibliotheque,
          telechargement: telechargement,
        ),
      );
      await tester.pump();
      await tester.pump();
      return telechargement;
    }

    testWidgets(
      'choisir une couverture du site, puis revenir à celle du site',
      (tester) async {
        preparer();
        bibliotheque.couverturesSite = const <CouvertureSite>[
          CouvertureSite(
            url: 'https://uploads.mangadex.org/covers/a/v1.jpg',
            volume: '1',
            langue: 'ja',
          ),
          CouvertureSite(
            url: 'https://uploads.mangadex.org/covers/a/v2.jpg',
            urlMiniature:
                'https://uploads.mangadex.org/covers/a/v2.jpg.256.jpg',
            volume: '2',
            langue: 'ja',
          ),
        ];
        await afficher(tester);

        await tester.tap(find.text(Textes.changerCouverture));
        await tester.pumpAndSettle();
        expect(find.text(Textes.couverturesDuSite), findsOneWidget);
        // La couverture actuelle est signalée.
        expect(
          find.text(
            '${Textes.legendeCouverture('1', 'ja')} · '
            '${Textes.couvertureActuelle}',
          ),
          findsOneWidget,
        );
        // Les miniatures passent par le service, avec le Referer du site.
        expect(
          bibliotheque.couverturesDemandees,
          contains('https://uploads.mangadex.org/covers/a/v2.jpg.256.jpg'),
        );
        expect(bibliotheque.referersDemandes, contains('https://mangadex.org'));

        await tester.tap(find.text(Textes.legendeCouverture('2', 'ja')));
        await tester.pumpAndSettle();
        expect(find.text(Textes.couvertureChangee), findsOneWidget);
        expect(
          bibliotheque.titres.single.couvertureChoisie,
          'https://uploads.mangadex.org/covers/a/v2.jpg',
        );

        await tester.tap(find.text(Textes.changerCouverture));
        await tester.pumpAndSettle();
        await tester.tap(find.text(Textes.revenirCouvertureSite));
        await tester.pumpAndSettle();
        expect(bibliotheque.titres.single.couvertureChoisie, isNull);
      },
    );

    testWidgets('image de l\'appareil, site sans autre couverture, erreur', (
      tester,
    ) async {
      preparer();
      await afficher(tester);

      await tester.tap(find.text(Textes.changerCouverture));
      await tester.pumpAndSettle();
      expect(find.text(Textes.aucuneCouvertureSite), findsOneWidget);

      bibliotheque.erreurCouvertures = const ErreurService(
        "L'image choisie est illisible.",
      );
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champCheminImage),
        'D:/images/couverture.png',
      );
      await tester.tap(find.text(Textes.utiliserImage));
      await tester.pumpAndSettle();
      // L'erreur reste dans le dialogue.
      expect(find.text("L'image choisie est illisible."), findsOneWidget);

      bibliotheque.erreurCouvertures = null;
      await tester.tap(find.text(Textes.utiliserImage));
      await tester.pumpAndSettle();
      expect(
        bibliotheque.titres.single.couvertureChoisie,
        'D:/images/couverture.png',
      );
    });

    testWidgets('la puce « En attente » montre l\'état sans pouvoir être '
        'changée', (tester) async {
      preparer(listes: <int>{1, idListeEnAttente});
      await afficher(tester);

      final puce = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'En attente'),
      );
      expect(puce.selected, isTrue);
      expect(puce.onSelected, isNull);
      expect(puce.tooltip, Textes.listeAutomatique);

      // « Planifié » se coche comme une liste ordinaire.
      await tester.tap(find.widgetWithText(FilterChip, 'Planifié'));
      await tester.pump();
      await tester.pump();
      expect(bibliotheque.listesParTitre[1], contains(idListePlanifie));
    });

    testWidgets('repère « Gardé » et « Ne plus garder »', (tester) async {
      preparer();
      final telechargement = FauxServiceTelechargement(bibliotheque)
        ..ajouterChapitreTelecharge(1);
      await telechargement.annulerSuppression(1);
      // Plus haut : la section « Sites » (étape 8) repousse les chapitres.
      taille(tester, hauteur: 2200);
      await tester.pumpWidget(
        envelopper(
          ChangeNotifierProvider<EtatTitre>(
            create: (_) => EtatTitre(
              bibliotheque,
              1,
              serviceTelechargement: telechargement,
            )..charger(),
            child: const EcranTitre(),
          ),
          bibliotheque: bibliotheque,
          telechargement: telechargement,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(Textes.garde), findsOneWidget);
      await tester.tap(find.text(Textes.nePlusGarder));
      await tester.pumpAndSettle();

      expect(telechargement.journal, contains('retirerGarde:1'));
      expect(find.text(Textes.garde), findsNothing);
      expect(find.text(Textes.gardeRetiree), findsOneWidget);
    });
  });

  group('ajout d\'un titre placé « En attente »', () {
    testWidgets('message dédié et pas de case « En attente »', (tester) async {
      final faux = _BibliothequeEnAttente();
      taille(tester);
      await tester.pumpWidget(
        envelopper(const EcranBibliotheque(), bibliotheque: faux),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterTitre),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'En attente'), findsNothing);
      expect(find.widgetWithText(CheckboxListTile, 'Planifié'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, Textes.champUrlTitre),
        'https://mangadex.org/title/abc',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      expect(
        find.text(Textes.titreAjouteEnAttente('Titre ajouté 1')),
        findsOneWidget,
      );
    });
  });

  group('langues d\'un site (P3)', () {
    test('variantes régionales acceptées', () {
      expect(EtatSources.languesValides(''), isTrue);
      expect(EtatSources.languesValides('fr'), isTrue);
      expect(EtatSources.languesValides('pt-br'), isTrue);
      expect(EtatSources.languesValides('fr, pt-BR,es-la'), isTrue);
      expect(EtatSources.languesValides('f1'), isFalse);
      expect(EtatSources.languesValides('français'), isFalse);
    });

    testWidgets('le réglage avancé d\'un site enregistre « fr,pt-br »', (
      tester,
    ) async {
      bibliotheque.sources.add(
        const Source(
          id: 1,
          nom: 'Lecture',
          urlBase: 'https://lecture.test',
          typeSource: TypeSource.madara,
        ),
      );
      final ajoutSite = FauxServiceAjoutSite(bibliotheque);
      taille(tester, largeur: 900);
      await tester.pumpWidget(
        envelopper(
          const EcranParametres(),
          bibliotheque: bibliotheque,
          ajoutSite: ajoutSite,
        ),
      );
      await tester.pump();
      await tester.pump();
      // Section Sites repliée au départ.
      await basculerSection(tester, Textes.sectionSites);
      // La section Sites est bas dans la liste (construite à la demande).
      await tester.scrollUntilVisible(
        find.byTooltip(Textes.modifierSite),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byTooltip(Textes.modifierSite));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(Textes.modifierSite));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.reglageAvanceLangues));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, Textes.champLangues),
        'fr,pt-br',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, Textes.enregistrer),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(Textes.erreurLangues), findsNothing);
      expect(ajoutSite.sourcesModifiees.single.langueParDefaut, 'fr,pt-br');
    });
  });

  group('surveillance des titres « En attente »', () {
    testWidgets('écart réglable de 1 h à l\'intervalle normal', (tester) async {
      final parametres = FauxServiceParametres()..verificationsParJour = 8;
      taille(tester, largeur: 900);
      await tester.pumpWidget(
        envelopper(
          const EcranParametres(),
          bibliotheque: bibliotheque,
          parametres: parametres,
        ),
      );
      await tester.pump();
      await tester.pump();
      // Section des recherches repliée au départ.
      await basculerSection(tester, Textes.sectionMisesAJour);

      expect(find.text(Textes.valeurHeures(1)), findsOneWidget);
      // Deuxième « + » : celui de la surveillance « En attente ».
      await tester.tap(find.byTooltip(Textes.augmenter).at(1));
      await tester.pumpAndSettle();
      expect(parametres.heuresEnAttente, 2);
      expect(find.text(Textes.valeurHeures(2)), findsOneWidget);
      expect(find.text(Textes.surveillanceEnregistree), findsOneWidget);

      // Au maximum (8 par jour → toutes les 3 h), « + » est désactivé.
      await tester.tap(find.byTooltip(Textes.augmenter).at(1));
      await tester.pumpAndSettle();
      expect(parametres.heuresEnAttente, 3);
      final plus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline).at(1),
      );
      expect(plus.onPressed, isNull);
    });
  });

  group('EtatBibliotheque : catégories incluses et exclues', () {
    test('toutes les incluses, aucune des exclues, et regroupement', () async {
      bibliotheque
        ..ajouterTitreDeTest('A', nomsCategories: <String>['action', 'école'])
        ..ajouterTitreDeTest('B', nomsCategories: <String>['action'])
        ..ajouterTitreDeTest('C', nomsCategories: <String>['école', '4-koma']);
      final etat = EtatBibliotheque(bibliotheque);
      addTearDown(etat.dispose);
      await etat.charger();
      final action = etat.categories.firstWhere((c) => c.nom == 'action');
      final ecole = etat.categories.firstWhere((c) => c.nom == 'école');
      final koma = etat.categories.firstWhere((c) => c.nom == '4-koma');

      await etat.appliquerFiltreCategories(
        incluses: <int>{action.id!, ecole.id!},
        exclues: <int>{},
      );
      expect(etat.titres.map((t) => t.nom), <String>['A']);
      expect(etat.aUnFiltre, isTrue);
      expect(etat.nombreFiltresCategories, 2);

      // Exclusion seule : tout sauf les titres « école ».
      await etat.appliquerFiltreCategories(
        incluses: <int>{},
        exclues: <int>{ecole.id!},
      );
      expect(etat.titres.map((t) => t.nom), <String>['B']);
      expect(etat.etatCategorie(ecole.id!), EtatFiltreCategorie.exclue);
      expect(etat.etatCategorie(action.id!), EtatFiltreCategorie.neutre);

      // Les deux combinés.
      await etat.appliquerFiltreCategories(
        incluses: <int>{ecole.id!},
        exclues: <int>{koma.id!},
      );
      expect(etat.titres.map((t) => t.nom), <String>['A']);
      expect(etat.etatCategorie(ecole.id!), EtatFiltreCategorie.incluse);

      // Une catégorie à la fois incluse et exclue compte comme exclue.
      await etat.appliquerFiltreCategories(
        incluses: <int>{action.id!},
        exclues: <int>{action.id!},
      );
      expect(etat.titres.map((t) => t.nom), <String>['C']);

      await etat.effacerFiltreCategories();
      expect(etat.titres, hasLength(3));
      expect(etat.aUnFiltre, isFalse);

      final groupes = etat.grouperCategories('');
      expect(groupes.map((g) => g.initiale), <String>['A', 'E', '#']);
      expect(etat.grouperCategories('ECOLE').single.categories.single, ecole);
    });
  });
}

/// Faux service dont l'ajout place le titre dans « En attente ».
class _BibliothequeEnAttente extends FauxServiceBibliotheque {
  @override
  Future<ResultatAjoutTitre> ajouterTitreDepuisUrl(
    String urlTitre, {
    List<int> idsListes = const <int>[],
  }) async {
    final titre = ajouterTitreDeTest(
      'Titre ajouté ${titres.length + 1}',
      idsListes: <int>{...idsListes, idListeEnAttente},
    );
    return ResultatAjoutTitre(titre, 0, estEnAttente: true);
  }
}
