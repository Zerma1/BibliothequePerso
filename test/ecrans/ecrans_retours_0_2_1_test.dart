// Tests de widgets des retours du client sur la 0.2.1-test (X4 à X10),
// avec de faux services (aucune base, aucun réseau).
import 'package:bibliotheque_perso/ecrans/ecran_bibliotheque.dart';
import 'package:bibliotheque_perso/ecrans/ecran_gestion_listes.dart';
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/ecrans/ecran_sources.dart';
import 'package:bibliotheque_perso/ecrans/ecran_titre.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/carte_titre.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

/// Chapitres 1 à [nombre], non lus.
List<Chapitre> _chapitres(int nombre) => <Chapitre>[
  for (var i = 1; i <= nombre; i++)
    Chapitre(
      id: i,
      urlChapitre: 'https://mangadex.org/chapter/$i',
      nom: '',
      numero: i.toDouble(),
      langue: 'en',
    ),
];

void main() {
  late FauxServiceBibliotheque service;

  setUp(() => service = FauxServiceBibliotheque());

  /// Fenêtre large : toute la ligne des puces de listes est visible.
  void fenetreLarge(WidgetTester tester, {double hauteur = 1200}) {
    tester.view.physicalSize = Size(2200, hauteur);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('X4 : listes personnelles', () {
    Future<void> afficher(WidgetTester tester) async {
      fenetreLarge(tester);
      await tester.pumpWidget(
        envelopper(const EcranBibliotheque(), bibliotheque: service),
      );
      await tester.pump();
    }

    testWidgets('« Terminés » est une puce comme les autres ; « + » crée une '
        'liste', (tester) async {
      await afficher(tester);
      expect(find.widgetWithText(FilterChip, nomListeTermines), findsOneWidget);

      await tester.tap(find.byTooltip(Textes.nouvelleListe));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champNomListe),
        'Coups de cœur',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.creer));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Coups de cœur'), findsOneWidget);
      expect(find.text(Textes.listeCreee('Coups de cœur')), findsOneWidget);
    });

    testWidgets('un nom refusé reste affiché dans le dialogue', (tester) async {
      await afficher(tester);
      service.erreurListes = const ErreurService('Nom déjà pris.');
      await tester.tap(find.byTooltip(Textes.nouvelleListe));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champNomListe),
        'Favoris',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.creer));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Nom déjà pris.'), findsOneWidget);
    });

    testWidgets('appui long sur une liste perso : renommer puis supprimer', (
      tester,
    ) async {
      await afficher(tester);

      await tester.longPress(
        find.widgetWithText(FilterChip, 'À lire plus tard'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.renommerListe));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champNomListe),
        'Plus tard',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.renommer));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Plus tard'), findsOneWidget);

      // Clic droit (ordinateur) : même menu.
      await tester.tap(
        find.widgetWithText(FilterChip, 'Plus tard'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.supprimerListe));
      await tester.pumpAndSettle();
      expect(
        find.text(Textes.confirmationSuppressionListe('Plus tard')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.supprimer));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Plus tard'), findsNothing);
      expect(service.listes.any((liste) => liste.id == 3), isFalse);
    });

    testWidgets('liste système : menu grisé avec explication', (tester) async {
      await afficher(tester);

      await tester.longPress(find.widgetWithText(FilterChip, nomListeFavoris));
      await tester.pumpAndSettle();

      expect(find.text(Textes.listeSysteme), findsOneWidget);
      final renommer = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text(Textes.renommerListe),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(renommer.enabled, isFalse);
      // Un appui sur l'entrée grisée ne fait rien.
      await tester.tap(find.text(Textes.renommerListe), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('« Gérer les listes » : glisser-déposer enregistre l\'ordre', (
      tester,
    ) async {
      await afficher(tester);
      await tester.tap(find.byTooltip(Textes.gererListes));
      await tester.pumpAndSettle();
      expect(find.byType(EcranGestionListes), findsOneWidget);
      expect(find.text(Textes.listeSysteme), findsNWidgets(5));

      // Favoris (première ligne) glissée sous Suivis.
      final poignee = find.byIcon(Icons.drag_handle).first;
      final hauteurLigne =
          tester.getCenter(find.text(nomListeSuivis)).dy -
          tester.getCenter(find.text(nomListeFavoris)).dy;
      final geste = await tester.startGesture(tester.getCenter(poignee));
      await tester.pump();
      // Glisser en plusieurs pas, comme un vrai doigt.
      for (var pas = 0; pas < 8; pas++) {
        await geste.moveBy(Offset(0, hauteurLigne * 1.5 / 8));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await geste.up();
      await tester.pumpAndSettle();

      // Favoris est descendue (la position exacte dépend du seuil de
      // ReorderableListView) ; l'ordre est enregistré par le service.
      expect(service.listes.first.nom, nomListeSuivis);
      expect(
        service.listes.indexWhere((liste) => liste.nom == nomListeFavoris),
        greaterThan(0),
      );
    });
  });

  group('X5 : sources', () {
    late FauxServiceAjoutSite ajoutSite;

    Future<void> afficher(WidgetTester tester) async {
      fenetreLarge(tester, hauteur: 1600);
      ajoutSite = FauxServiceAjoutSite(service);
      service.sources.add(
        const Source(
          id: 1,
          nom: 'Scans',
          urlBase: 'https://scans.test',
          typeSource: TypeSource.generique,
          configurationSelecteurs: '{"selecteurTitre":"h1"}',
        ),
      );
      await tester.pumpWidget(
        envelopper(
          const EcranSources(),
          bibliotheque: service,
          ajoutSite: ajoutSite,
        ),
      );
      await tester.pump();
    }

    testWidgets('toucher un site ouvre la modification ; type modifiable, '
        'avertissement, types incohérents grisés', (tester) async {
      await afficher(tester);
      await tester.tap(find.text('Scans'));
      await tester.pumpAndSettle();
      expect(find.text(Textes.modifierSite), findsOneWidget);

      await tester.tap(
        find.text(Textes.libelleTypeSource(TypeSource.generique)),
      );
      await tester.pumpAndSettle();
      final mangaDex = tester.widget<DropdownMenuItem<TypeSource>>(
        find
            .ancestor(
              of: find.text(Textes.libelleTypeSource(TypeSource.mangaDex)),
              matching: find.byType(DropdownMenuItem<TypeSource>),
            )
            .last,
      );
      expect(mangaDex.enabled, isFalse);
      await tester.tap(
        find.text(Textes.libelleTypeSource(TypeSource.madara)).last,
      );
      await tester.pumpAndSettle();
      expect(find.text(Textes.avertissementEffacementReglages), findsOneWidget);
      // Plus de sélecteurs CSS pour un autre type que générique.
      expect(find.text(Textes.reglagesAvancesSelecteurs), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, Textes.enregistrer));
      await tester.pumpAndSettle();
      expect(ajoutSite.sourcesModifiees.single.typeSource, TypeSource.madara);
      expect(ajoutSite.sourcesModifiees.single.configurationSelecteurs, isNull);
    });

    testWidgets('« Supprimer » : confirmation, refus si des titres en '
        'dépendent', (tester) async {
      await afficher(tester);
      service.ajouterTitreDeTest('Titre du site', idSource: 1);

      await tester.tap(find.text('Scans'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, Textes.supprimer));
      await tester.pumpAndSettle();
      expect(
        find.text(Textes.confirmationSuppressionSite('Scans')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.supprimer));
      await tester.pumpAndSettle();
      expect(find.text(Textes.erreurSiteAvecTitres(1)), findsOneWidget);
      expect(service.sources, hasLength(1));

      // Sans titre, la suppression passe.
      service.titres.clear();
      await tester.tap(find.text('Scans'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, Textes.supprimer));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, Textes.supprimer));
      await tester.pumpAndSettle();
      expect(service.sources, isEmpty);
      expect(find.text(Textes.siteSupprime('Scans')), findsOneWidget);
    });
  });

  group('X6 : modifier un titre', () {
    Future<void> afficherFiche(WidgetTester tester) async {
      fenetreLarge(tester, hauteur: 2400);
      service.ajouterTitreDeTest(
        'Shinigami',
        idSource: 1,
        nomsCategories: <String>['action'],
        chapitres: _chapitres(2),
      );
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

    testWidgets('« Modifier la fiche » : seuls les champs changés sont '
        'envoyés ; repère et « Rendre au site »', (tester) async {
      await afficherFiche(tester);

      await tester.tap(find.byTooltip(Textes.modifierFiche));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, Textes.champNomTitre),
        'Nouveau nom',
      );
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champAjoutCategorie),
        'Fantasy',
      );
      await tester.tap(find.byTooltip(Textes.ajouter));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'Fantasy'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, Textes.enregistrer));
      await tester.pumpAndSettle();

      expect(find.text(Textes.ficheModifiee), findsOneWidget);
      final titre = service.titres.single;
      expect(titre.nom, 'Nouveau nom');
      expect(titre.champsManuels, <ChampTitre>{
        ChampTitre.nom,
        ChampTitre.categories,
      });
      expect(
        find.text(
          Textes.champsModifiesALaMain(<ChampTitre>[
            ChampTitre.nom,
            ChampTitre.categories,
          ]),
        ),
        findsOneWidget,
      );

      // Le formulaire montre le repère ; « Rendre au site » le retire.
      await tester.tap(find.byTooltip(Textes.modifierFiche));
      await tester.pumpAndSettle();
      expect(find.text(Textes.modifieALaMain), findsNWidgets(2));
      await tester.tap(find.text(Textes.rendreAuSite).first);
      await tester.pumpAndSettle();
      expect(find.text(Textes.champRenduAuSite), findsOneWidget);
      expect(service.titres.single.champsManuels, <ChampTitre>{
        ChampTitre.categories,
      });
    });

    testWidgets('formulaire inchangé : rien n\'est envoyé', (tester) async {
      await afficherFiche(tester);
      await tester.tap(find.byTooltip(Textes.modifierFiche));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, Textes.enregistrer));
      await tester.pumpAndSettle();
      expect(find.text(Textes.aucuneModification), findsOneWidget);
      expect(service.titres.single.champsManuels, isEmpty);
    });

    testWidgets('dialogue d\'ajout : rechercher sur MangaDex puis ajouter un '
        'résultat', (tester) async {
      fenetreLarge(tester);
      service.resultatsRecherche = <Titre>[
        Titre(
          urlTitre: 'https://mangadex.org/title/trouve',
          nom: 'Titre trouvé',
          auteur: 'Une autrice',
        ),
      ];
      await tester.pumpWidget(
        envelopper(const EcranBibliotheque(), bibliotheque: service),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FloatingActionButton, Textes.boutonAjouterTitre),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.modeRechercher));
      await tester.pumpAndSettle();

      // « Ajouter » attend le choix d'un résultat.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, Textes.ajouter),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextField, Textes.champRechercheMangaDex),
        'trouvé',
      );
      await tester.tap(find.byTooltip(Textes.rechercher));
      await tester.pumpAndSettle();
      expect(service.recherches.single.requete, 'trouvé');
      await tester.tap(find.text('Titre trouvé'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CarteTitre), findsOneWidget);
    });
  });

  group('X7 : archive complète', () {
    testWidgets('l\'interrupteur demande confirmation puis applique les '
        'règles à tous', (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final parametres = FauxServiceParametres();
      final telechargement = FauxServiceTelechargement(service);
      await tester.pumpWidget(
        envelopper(
          const EcranParametres(),
          bibliotheque: service,
          parametres: parametres,
          telechargement: telechargement,
        ),
      );
      await tester.pump();
      await tester.pump();
      await basculerSection(tester, Textes.sectionTelechargements);

      final interrupteur = find.widgetWithText(
        SwitchListTile,
        Textes.archiveComplete,
      );
      expect(find.text(Textes.explicationArchiveComplete), findsOneWidget);

      // Annuler : rien ne change.
      await tester.tap(interrupteur);
      await tester.pumpAndSettle();
      expect(find.text(Textes.confirmationArchiveComplete), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, Textes.annuler));
      await tester.pumpAndSettle();
      expect(parametres.archiveComplete, isFalse);

      await tester.tap(interrupteur);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, Textes.activer));
      await tester.pumpAndSettle();
      expect(parametres.archiveComplete, isTrue);
      expect(telechargement.nombreAppelsReglesATous, 1);
      expect(tester.widget<SwitchListTile>(interrupteur).value, isTrue);

      // Désactivation sans confirmation.
      await tester.tap(interrupteur);
      await tester.pumpAndSettle();
      expect(parametres.archiveComplete, isFalse);
      expect(telechargement.nombreAppelsReglesATous, 2);
    });
  });

  group('X10 : chapitres lus en lot', () {
    Future<void> afficherFiche(WidgetTester tester) async {
      fenetreLarge(tester, hauteur: 2400);
      service.ajouterTitreDeTest(
        'Shinigami',
        idSource: 1,
        chapitres: _chapitres(5),
      );
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

    Set<int> lus() => <int>{
      for (final chapitre in service.chapitresParTitre[1]!)
        if (chapitre.estLu) chapitre.id!,
    };

    testWidgets('appui long : mode sélection, cases, « Marquer lus »', (
      tester,
    ) async {
      await afficherFiche(tester);
      expect(find.byType(Checkbox), findsNothing);

      await tester.longPress(find.text('Chapitre 4'));
      await tester.pump();
      expect(find.text(Textes.chapitresSelectionnes(1)), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(5));

      // En mode sélection, un appui coche au lieu d'ouvrir le menu.
      await tester.tap(find.text('Chapitre 2'));
      await tester.pump();
      expect(find.text(Textes.chapitresSelectionnes(2)), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byTooltip(Textes.marquerSelectionLus));
      await tester.pumpAndSettle();
      expect(lus(), <int>{4, 2});
      expect(service.nombreMarquagesEnLot, 1);
      expect(find.text(Textes.chapitresMarques(2, lu: true)), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('appui long puis glisser étend la sélection ; « Tout '
        'sélectionner », « Marquer non lus », « Annuler »', (tester) async {
      await afficherFiche(tester);

      final geste = await tester.startGesture(
        tester.getCenter(find.text('Chapitre 5')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await geste.moveTo(tester.getCenter(find.text('Chapitre 3')));
      await tester.pump();
      await geste.up();
      await tester.pump();
      expect(find.text(Textes.chapitresSelectionnes(3)), findsOneWidget);

      await tester.tap(find.byTooltip(Textes.toutSelectionner));
      await tester.pump();
      expect(find.text(Textes.chapitresSelectionnes(5)), findsOneWidget);
      await tester.tap(find.byTooltip(Textes.marquerSelectionLus));
      await tester.pumpAndSettle();
      expect(lus(), <int>{1, 2, 3, 4, 5});

      await tester.longPress(find.text('Chapitre 1'));
      await tester.pump();
      await tester.tap(find.byTooltip(Textes.marquerSelectionNonLus));
      await tester.pumpAndSettle();
      expect(lus(), <int>{2, 3, 4, 5});

      await tester.longPress(find.text('Chapitre 2'));
      await tester.pump();
      await tester.tap(find.byTooltip(Textes.annulerSelection));
      await tester.pump();
      expect(find.byType(Checkbox), findsNothing);
      expect(lus(), <int>{2, 3, 4, 5});
    });

    testWidgets('souris : clic maintenu et glisser sélectionne', (
      tester,
    ) async {
      await afficherFiche(tester);

      final souris = await tester.startGesture(
        tester.getCenter(find.text('Chapitre 1')),
        kind: PointerDeviceKind.mouse,
      );
      await souris.moveBy(const Offset(0, -kDragSlopDefault * 2));
      await souris.moveTo(tester.getCenter(find.text('Chapitre 4')));
      await tester.pump();
      await souris.up();
      await tester.pump();

      expect(find.text(Textes.chapitresSelectionnes(4)), findsOneWidget);
    });

    testWidgets('une seule ligne sélectionnée : « Lus jusqu\'ici » dans la '
        'barre', (tester) async {
      await afficherFiche(tester);

      await tester.longPress(find.text('Chapitre 3'));
      await tester.pump();
      expect(find.byTooltip(Textes.lusJusquIci), findsOneWidget);
      // Deux lignes : l'action disparaît.
      await tester.tap(find.text('Chapitre 5'));
      await tester.pump();
      expect(find.byTooltip(Textes.lusJusquIci), findsNothing);
      await tester.tap(find.text('Chapitre 5'));
      await tester.pump();

      await tester.tap(find.byTooltip(Textes.lusJusquIci));
      await tester.pumpAndSettle();
      expect(lus(), <int>{1, 2, 3});
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text(Textes.chapitresMarques(3, lu: true)), findsOneWidget);
    });

    testWidgets('chapitre téléchargé : « ⋮ » ouvre son menu (accès mobile)', (
      tester,
    ) async {
      fenetreLarge(tester, hauteur: 2400);
      service.ajouterTitreDeTest(
        'Shinigami',
        idSource: 1,
        chapitres: _chapitres(3),
      );
      final telechargement = FauxServiceTelechargement(service)
        ..ajouterChapitreTelecharge(2);
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

      // Seul le chapitre téléchargé a le bouton.
      expect(find.byTooltip(Textes.ouvrirMenuChapitre), findsOneWidget);
      await tester.tap(find.byTooltip(Textes.ouvrirMenuChapitre));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.marquerLusJusquIci));
      await tester.pumpAndSettle();
      expect(lus(), <int>{1, 2});
    });

    testWidgets('menu d\'un chapitre : « Marquer lus jusqu\'ici »', (
      tester,
    ) async {
      await afficherFiche(tester);

      await tester.tap(find.text('Chapitre 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.marquerLusJusquIci));
      await tester.pumpAndSettle();

      expect(lus(), <int>{1, 2, 3});
      expect(find.text(Textes.chapitresMarques(3, lu: true)), findsOneWidget);
    });
  });
}
