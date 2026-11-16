// Tests de EcranBibliotheque avec de faux services (aucune base, aucun réseau).
import 'dart:async';

import 'package:bibliotheque_perso/ecrans/ecran_bibliotheque.dart';
import 'package:bibliotheque_perso/etat/constantes_etat.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_mises_a_jour.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/widgets/carte_titre.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

/// Chapitres non lus de test.
List<Chapitre> _chapitres(int nombre) => <Chapitre>[
  for (var i = 1; i <= nombre; i++)
    Chapitre(
      id: i,
      urlChapitre: 'https://exemple.test/c$i-${DateTime.now().microsecond}',
      nom: '',
      numero: i.toDouble(),
    ),
];

void main() {
  late FauxServiceBibliotheque service;

  setUp(() => service = FauxServiceBibliotheque());

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(const EcranBibliotheque(), bibliotheque: service),
    );
  }

  testWidgets('montre un indicateur pendant le chargement', (tester) async {
    service.retenue = Completer<void>();
    await afficher(tester);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    service.retenue!.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('affiche l\'erreur puis réessaie', (tester) async {
    service.erreurLecture = const ErreurSource('https://x.test', 'Panne');
    await afficher(tester);
    await tester.pump();

    expect(find.textContaining(Textes.erreurSite), findsOneWidget);
    expect(find.textContaining('Panne'), findsOneWidget);

    service.erreurLecture = null;
    await tester.tap(find.text(Textes.reessayer));
    await tester.pump();

    expect(find.text(Textes.bibliothequeVide), findsOneWidget);
  });

  testWidgets('bibliothèque vide : message d\'aide', (tester) async {
    await afficher(tester);
    await tester.pump();

    expect(find.text(Textes.bibliothequeVide), findsOneWidget);
    expect(find.byType(CarteTitre), findsNothing);
  });

  testWidgets('grille, badges, filtres par catégorie et par liste, recherche', (
    tester,
  ) async {
    service
      ..ajouterTitreDeTest(
        'Shinigami',
        nomsCategories: <String>['action', 'gore'],
        idsListes: <int>{1, 2},
        chapitres: _chapitres(2),
      )
      ..ajouterTitreDeTest(
        'Solo Leveling',
        nomsCategories: <String>['fantasy'],
        idsListes: <int>{3},
      );
    await afficher(tester);
    await tester.pump();

    expect(find.byType(CarteTitre), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget);

    // Dans la barre : seulement « Toutes les catégories » et l'entonnoir ;
    // les catégories sont dans une fenêtre.
    expect(find.widgetWithText(FilterChip, 'Gore'), findsNothing);
    await tester.tap(find.byTooltip(Textes.filtrerParCategories));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Gore'));
    await tester.pump();
    // Brouillon : rien n'est appliqué avant « Appliquer ».
    expect(find.byType(CarteTitre), findsNWidgets(2));
    await tester.tap(find.text(Textes.appliquer));
    await tester.pumpAndSettle();
    expect(find.byType(CarteTitre), findsOneWidget);
    expect(find.text('Shinigami'), findsOneWidget);
    expect(find.byTooltip(Textes.filtreCategoriesActif(1)), findsOneWidget);
    // « Toutes les catégories » retire le filtre.
    await tester.tap(find.text(Textes.toutesLesCategories));
    await tester.pump();
    expect(find.byType(CarteTitre), findsNWidgets(2));
    // Les listes système (Planifié, En attente) précèdent celle du client :
    // la ligne défile jusqu'à elle.
    await tester.ensureVisible(
      find.widgetWithText(FilterChip, 'À lire plus tard'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'À lire plus tard'));
    await tester.pump();
    expect(find.byType(CarteTitre), findsOneWidget);
    expect(find.text('Solo Leveling'), findsOneWidget);

    await tester.ensureVisible(find.text(Textes.toutesLesListes));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.toutesLesListes));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'shini');
    await tester.pump(const Duration(milliseconds: 100));
    // Délai de frappe pas encore écoulé : la grille n'a pas changé.
    expect(find.byType(CarteTitre), findsNWidgets(2));
    await tester.pump(delaiAvantRecherche);
    await tester.pump();
    expect(find.byType(CarteTitre), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'introuvable');
    await tester.pump(delaiAvantRecherche);
    await tester.pump();
    expect(find.text(Textes.aucunResultat), findsOneWidget);

    // Le bouton « effacer » recharge sans attendre.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(find.byType(CarteTitre), findsNWidgets(2));
  });

  testWidgets(
    'la couverture est demandée par titre (appareil d\'abord, puis site)',
    (tester) async {
      service.octetsCouverture = pngMinimal;
      service.ajouterTitreDeTest(
        'Avec couverture',
        urlCouverture: 'https://images.test/c.jpg',
      );
      service.ajouterTitreDeTest('Sans couverture');
      await afficher(tester);
      await tester.pump();
      await tester.pump();

      // Seul le titre qui a une couverture la demande, au service (qui lit
      // l'appareil puis le site) et non directement par son adresse.
      expect(service.couverturesChargees, <int>[1]);
      expect(service.couverturesDemandees, isEmpty);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets('niveau de contenu : panneau, enregistrement et filtre', (
    tester,
  ) async {
    final parametres = FauxServiceParametres();
    service
      ..ajouterTitreDeTest('Tous publics')
      ..ajouterTitreDeTest('Explicite');
    service.remplacerTitreDeTest(
      service.titres[1].copierAvec(niveauContenu: 'pornographic'),
    );
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranBibliotheque(),
        bibliotheque: service,
        parametres: parametres,
      ),
    );
    await tester.pump();

    // Par défaut, tout sauf pornographique.
    expect(find.byType(CarteTitre), findsOneWidget);
    expect(service.derniersNiveauxDemandes, <String>[
      'safe',
      'suggestive',
      'erotica',
    ]);

    // Téléphone : le panneau est une feuille du bas (la ligne des filtres
    // défile jusqu'au bouton).
    await tester.ensureVisible(find.text(Textes.boutonContenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.boutonContenu));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text(Textes.libelleNiveauContenu('pornographic')));
    await tester.pumpAndSettle();
    expect(parametres.niveaux, contains('pornographic'));
    await tester.tap(find.text(Textes.afficherTitres(2)));
    await tester.pumpAndSettle();
    expect(find.byType(CarteTitre), findsNWidgets(2));
  });

  testWidgets('bibliothèque vide : un seul bouton « Ajouter un titre »', (
    tester,
  ) async {
    await afficher(tester);
    await tester.pump();

    expect(find.text(Textes.boutonAjouterTitre), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('fenêtre des catégories : recherche, regroupement, inclure et '
      'exclure', (tester) async {
    service
      ..ajouterTitreDeTest('A', nomsCategories: <String>['action', 'comédie'])
      ..ajouterTitreDeTest('B', nomsCategories: <String>['action'])
      ..ajouterTitreDeTest('C', nomsCategories: <String>['comédie', 'drame']);
    await afficher(tester);
    await tester.pump();

    await tester.tap(find.byTooltip(Textes.filtrerParCategories));
    await tester.pumpAndSettle();
    // Toutes les catégories, regroupées par initiale.
    expect(find.text('D'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Drame'), findsOneWidget);

    // Recherche sans accent ni majuscule.
    await tester.enterText(
      find.widgetWithText(TextField, Textes.rechercherCategorie),
      'COMEDIE',
    );
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'Comédie'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Action'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, Textes.rechercherCategorie),
      '',
    );
    await tester.pump();

    // Action : incluse (un appui) ; drame : exclue (deux appuis).
    await tester.tap(find.widgetWithText(FilterChip, 'Action'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Drame'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Drame'));
    await tester.pump();
    expect(find.text(Textes.resumeFiltreCategories(1, 1)), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle), findsOneWidget);
    await tester.tap(find.text(Textes.appliquer));
    await tester.pumpAndSettle();
    // A et B ont action ; aucun n'a drame.
    expect(find.byType(CarteTitre), findsNWidgets(2));
    expect(find.text('C'), findsNothing);

    // Comédie exclue en plus : il ne reste que B.
    await tester.tap(find.byTooltip(Textes.filtreCategoriesActif(2)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Comédie'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Comédie'));
    await tester.pump();
    await tester.tap(find.text(Textes.appliquer));
    await tester.pumpAndSettle();
    expect(find.byType(CarteTitre), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    // « Annuler » ne change rien ; « Tout effacer » puis « Appliquer »
    // retire le filtre.
    await tester.tap(find.byTooltip(Textes.filtreCategoriesActif(3)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.effacerCategories));
    await tester.pump();
    await tester.tap(find.text(Textes.annuler).last);
    await tester.pumpAndSettle();
    expect(find.byType(CarteTitre), findsOneWidget);
    await tester.tap(find.byTooltip(Textes.filtreCategoriesActif(3)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.effacerCategories));
    await tester.pump();
    await tester.tap(find.text(Textes.appliquer));
    await tester.pumpAndSettle();
    expect(find.byType(CarteTitre), findsNWidgets(3));
  });

  testWidgets(
    'le dialogue coche Favoris et Suivis même si les listes n\'étaient pas '
    'chargées',
    (tester) async {
      service.erreurLecture = const ErreurSource('https://x.test', 'Panne');
      await afficher(tester);
      await tester.pump();
      expect(find.text(Textes.reessayer), findsOneWidget);

      service.erreurLecture = null;
      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterTitre),
      );
      await tester.pumpAndSettle();

      final cases = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .map((caseListe) => caseListe.value)
          .toList();
      // Favoris, Suivis, Planifié, À lire plus tard (« En attente » est
      // automatique : pas de case).
      expect(cases, <bool?>[true, true, false, false]);
    },
  );

  testWidgets(
    'le dialogue d\'ajout coche Favoris et Suivis et ajoute le titre',
    (tester) async {
      await afficher(tester);
      await tester.pump();

      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterTitre),
      );
      await tester.pumpAndSettle();

      final cases = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(cases, hasLength(4));
      expect(cases.map((caseListe) => caseListe.value), <bool?>[
        true,
        true,
        false,
        false,
      ]);

      // Adresse vide : l'erreur reste dans le dialogue.
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pump();
      expect(find.text(Textes.erreurAdresseVide), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, Textes.champUrlTitre),
        'https://mangadex.org/title/abc',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('3 nouveaux chapitres'), findsOneWidget);
      expect(find.byType(CarteTitre), findsOneWidget);
      expect(service.listesParTitre[1], <int>{1, 2});
    },
  );

  group('recherche des nouveaux chapitres', () {
    late FauxServiceMisesAJour misesAJour;

    setUp(() => misesAJour = FauxServiceMisesAJour());

    Future<void> afficherAvecMisesAJour(
      WidgetTester tester, {
      bool auDemarrage = false,
    }) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        envelopper(
          const EcranBibliotheque(),
          bibliotheque: service,
          misesAJour: misesAJour,
          verifierMisesAJourAuDemarrage: auDemarrage,
        ),
      );
    }

    Finder bouton() => find.byTooltip(Textes.rechercherNouveauxChapitres);

    testWidgets('indicateur et bouton désactivé pendant la vérification, '
        'puis « Aucun nouveau chapitre »', (tester) async {
      await afficherAvecMisesAJour(tester);
      await tester.pump();
      misesAJour.retenue = Completer<void>();

      await tester.tap(bouton());
      await tester.pump();

      expect(bouton(), findsNothing);
      final enCours = find.byTooltip(Textes.rechercheNouveauxChapitresEnCours);
      expect(enCours, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: enCours, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );

      misesAJour.retenue!.complete();
      await tester.pump();
      await tester.pump();

      expect(bouton(), findsOneWidget);
      expect(find.text('Aucun nouveau chapitre.'), findsOneWidget);
      expect(misesAJour.nombreAppels, 1);
    });

    testWidgets('nouveautés : bilan avec sites en échec et badge mis à jour', (
      tester,
    ) async {
      final titre = service.ajouterTitreDeTest('Shinigami', idSource: 1);
      final autre = service.ajouterTitreDeTest('Solo Leveling', idSource: 2);
      misesAJour
        ..pendantVerification = () {
          // Le vrai service enregistre les chapitres en base : le faux les
          // ajoute au faux service de la bibliothèque.
          service.chapitresParTitre[titre.id!]!.addAll(_chapitres(2));
        }
        ..resultats = <ResultatVerificationTitre>[
          ResultatVerificationTitre(titre: titre, nombreNouveauxChapitres: 2),
          ResultatVerificationTitre(
            titre: autre,
            erreur: const ErreurSource('https://site2.test', 'Panne'),
          ),
        ];
      await afficherAvecMisesAJour(tester);
      await tester.pump();
      expect(find.byType(Badge), findsNothing);

      await tester.tap(bouton());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          '2 nouveaux chapitres pour 1 titre. 1 site n\'a pas répondu.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(CarteTitre, 'Shinigami'),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('une vérification automatique sans nouveauté reste '
        'silencieuse', (tester) async {
      await afficherAvecMisesAJour(tester, auDemarrage: true);
      await tester.pump();
      await tester.pump();

      expect(misesAJour.nombreAppels, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('une vérification automatique avec nouveautés recharge la '
        'grille et l\'annonce', (tester) async {
      final titre = service.ajouterTitreDeTest('Shinigami', idSource: 1);
      misesAJour
        ..pendantVerification = (() {
          service.chapitresParTitre[titre.id!]!.addAll(_chapitres(3));
        })
        ..resultats = <ResultatVerificationTitre>[
          ResultatVerificationTitre(titre: titre, nombreNouveauxChapitres: 3),
        ];
      await afficherAvecMisesAJour(tester, auDemarrage: true);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('3 nouveaux chapitres pour 1 titre.'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('une panne générale affiche l\'erreur', (tester) async {
      misesAJour.erreur = const ErreurSource('https://site.test', 'Panne');
      await afficherAvecMisesAJour(tester);
      await tester.pump();

      await tester.tap(bouton());
      await tester.pump();
      await tester.pump();

      expect(find.textContaining(Textes.erreurSite), findsOneWidget);
      expect(bouton(), findsOneWidget);
    });
  });

  testWidgets('un refus du service s\'affiche dans le dialogue', (
    tester,
  ) async {
    service.erreurAjout = const ErreurService('Site non configuré.');
    await afficher(tester);
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

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Site non configuré.'), findsOneWidget);
  });
}
