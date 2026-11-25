// Étape 8 (M3) : section « Sites » de la fiche, filtre par site, nom du site
// de chaque chapitre, et état EtatTitre correspondant. Faux services, aucun
// réseau.
import 'package:bibliotheque_perso/ecrans/ecran_bibliotheque.dart';
import 'package:bibliotheque_perso/ecrans/ecran_titre.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque service;
  late FauxServiceTelechargement telechargement;

  /// Titre n°1 sur MangaDex (principal, site 1) et Scan-Manga (secondaire,
  /// site 2) ; le chapitre 1 existe sur les deux sites, en français.
  void preparer({bool avecSecondaire = true}) {
    service.sources.addAll(<Source>[
      const Source(
        id: 1,
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
      ),
      const Source(
        id: 2,
        nom: 'Scan-Manga',
        urlBase: 'https://www.scan-manga.com',
        typeSource: TypeSource.scanManga,
      ),
    ]);
    service.ajouterTitreDeTest(
      'Shinigami',
      idSource: 1,
      idsListes: <int>{1},
      chapitres: <Chapitre>[
        const Chapitre(
          id: 1,
          idSource: 1,
          urlChapitre: 'https://mangadex.org/chapter/1',
          nom: '',
          numero: 1,
          langue: 'fr',
        ),
        if (avecSecondaire) ...<Chapitre>[
          const Chapitre(
            id: 2,
            idSource: 2,
            urlChapitre: 'https://www.scan-manga.com/lecture/1',
            nom: '',
            numero: 1,
            langue: 'fr',
          ),
          const Chapitre(
            id: 3,
            idSource: 2,
            urlChapitre: 'https://www.scan-manga.com/lecture/2',
            nom: 'Seulement sur Scan-Manga',
            numero: 2,
            langue: 'fr',
          ),
          const Chapitre(
            id: 4,
            idSource: 2,
            urlChapitre: 'https://www.scan-manga.com/lecture/3',
            nom: 'Déjà téléchargé',
            numero: 3,
            langue: 'fr',
            estTelecharge: true,
          ),
        ],
      ],
    );
    if (avecSecondaire) {
      service.ajouterSiteDeTest(
        1,
        2,
        'https://www.scan-manga.com/titre/shinigami',
      );
    }
  }

  setUp(() {
    service = FauxServiceBibliotheque();
    telechargement = FauxServiceTelechargement(service);
  });

  group('EtatTitre', () {
    late EtatTitre etat;

    Future<void> charger() async {
      etat = EtatTitre(service, 1, serviceTelechargement: telechargement);
      await etat.charger();
    }

    tearDown(() => etat.dispose());

    test('charge les sites, le principal d\'abord, avec leur nom', () async {
      preparer();
      await charger();
      expect(etat.sites.map((s) => s.nomSite), <String>[
        'MangaDex',
        'Scan-Manga',
      ]);
      expect(etat.sites.first.estPrincipal, isTrue);
      expect(etat.sites.last.nombreChapitres, 3);
      expect(etat.aPlusieursSites, isTrue);
      final chapitre3 = etat.chapitres.firstWhere((c) => c.id == 3);
      expect(etat.nomSiteDe(chapitre3), 'Scan-Manga');
    });

    test('un seul site : pas de nom de site ni de filtre', () async {
      preparer(avecSecondaire: false);
      await charger();
      expect(etat.sites, hasLength(1));
      expect(etat.aPlusieursSites, isFalse);
    });

    test('la version retenue est celle du site principal, '
        'comme dans le service', () async {
      preparer();
      await charger();
      final numero1 = etat.groupes.firstWhere((g) => g.numero == 1);
      expect(numero1.retenu.id, 1);
      expect(numero1.autres.map((c) => c.id), <int>[2]);
    });

    test('le filtre par site ne garde que les chapitres de ce site', () async {
      preparer();
      await charger();
      expect(etat.nombreNumeros, 3);
      etat.filtrerParSite(1);
      expect(etat.nombreNumeros, 1);
      expect(etat.groupes.single.retenu.id, 1);
      etat.filtrerParSite(2);
      expect(etat.groupes.map((g) => g.retenu.id), <int>[4, 3, 2]);
      etat.filtrerParSite(null);
      expect(etat.nombreNumeros, 3);
    });

    test('compte les chapitres retirés et les archives du site', () async {
      preparer();
      await charger();
      expect(etat.nombreChapitresRetiresAvecSite(2), 2);
      expect(etat.nombreTelechargesDuSite(2), 1);
    });

    test(
      'chapitres retirés : même filtre que la suppression en base '
      '(lus, archives, gardés et téléchargements en cours épargnés)',
      () async {
        preparer();
        Chapitre chapitre(
          int id, {
          bool estLu = false,
          bool estGarde = false,
          String? nomArchive,
        }) => Chapitre(
          id: id,
          idSource: 2,
          urlChapitre: 'https://www.scan-manga.com/lecture/$id',
          nom: '',
          numero: id.toDouble(),
          langue: 'fr',
          estLu: estLu,
          estGarde: estGarde,
          nomArchive: nomArchive,
        );
        service.chapitresParTitre[1]!.addAll(<Chapitre>[
          chapitre(20, estLu: true),
          chapitre(21, nomArchive: 'archive_21.zip'),
          chapitre(22, estGarde: true),
          chapitre(23),
          chapitre(24),
          // Sans site connu : la requête (id_source = ?) ne le supprime pas.
          const Chapitre(
            id: 25,
            urlChapitre: 'https://mangadex.org/chapter/25',
            nom: '',
            numero: 25,
            langue: 'fr',
          ),
        ]);
        telechargement.modifierLigne(23, StatutTelechargement.enCours);
        telechargement.modifierLigne(24, StatutTelechargement.enAttente);
        await charger();
        // Chapitres 2 et 3 (préparés) et 24 (seulement en attente : son
        // entrée de file disparaît avec lui).
        expect(etat.nombreChapitresRetiresAvecSite(2), 3);
        // Site 1 : seul le chapitre 1 ; le 25, sans site connu, n'est pas
        // compté (pas de repli sur le site principal, comme la requête).
        expect(etat.nombreChapitresRetiresAvecSite(1), 1);
      },
    );

    test('ajouter un site : règles appliquées puis fiche relue', () async {
      preparer(avecSecondaire: false);
      service.chapitresSiteAjoute = <Chapitre>[
        const Chapitre(
          id: 10,
          urlChapitre: 'https://www.scan-manga.com/lecture/9',
          nom: '',
          numero: 9,
          langue: 'fr',
        ),
      ];
      await charger();
      final resultat = await etat.ajouterSite(
        ' https://www.scan-manga.com/titre/shinigami ',
      );
      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee, 1);
      expect(service.journalSites, <String>[
        'ajouter:1:https://www.scan-manga.com/titre/shinigami',
      ]);
      expect(telechargement.reglesAppliquees, <int>[1]);
      expect(etat.sites, hasLength(2));
      expect(etat.nombreNumeros, 2);
      expect(etat.estEnModificationSites, isFalse);
    });

    test('adresse vide : refus sans appel au service', () async {
      preparer();
      await charger();
      final resultat = await etat.ajouterSite('  ');
      expect(resultat.erreur?.nature, NatureErreur.adresseVide);
      expect(service.journalSites, isEmpty);
    });

    test('refus du service : message lisible, rien n\'est appliqué', () async {
      preparer();
      await charger();
      service.erreurSites = const ErreurService(
        "Ce site n'est pas encore configuré.",
      );
      final resultat = await etat.ajouterSite('https://exemple.org/titre');
      expect(resultat.erreur?.nature, NatureErreur.refus);
      expect(telechargement.reglesAppliquees, isEmpty);
    });

    test('retirer un site : chapitres retirés, règles, fiche relue', () async {
      preparer();
      await charger();
      etat.filtrerParSite(2);
      final resultat = await etat.retirerSite(2);
      expect(resultat.donnee, 2);
      expect(telechargement.reglesAppliquees, <int>[1]);
      expect(etat.sites, hasLength(1));
      // Le filtre d'un site retiré revient à « tous les sites ».
      expect(etat.idSiteFiltre, isNull);
    });

    test('définir le site principal change la version retenue', () async {
      preparer();
      await charger();
      final resultat = await etat.definirSitePrincipal(2);
      expect(resultat.estReussi, isTrue);
      expect(etat.titre!.idSource, 2);
      expect(etat.sites.first.nomSite, 'Scan-Manga');
      final numero1 = etat.groupes.firstWhere((g) => g.numero == 1);
      expect(numero1.retenu.id, 2);
      expect(telechargement.reglesAppliquees, <int>[1]);
    });

    test('actualisation : sites qui n\'ont pas répondu', () async {
      preparer();
      await charger();
      service.erreursParSiteActualisation = <int, Object>{
        2: const ErreurSource('https://www.scan-manga.com', 'Délai dépassé'),
      };
      final resultat = await etat.actualiser();
      expect(resultat.estReussi, isTrue);
      expect(etat.sitesSansReponse, <String>['Scan-Manga']);
    });
  });

  testWidgets('ajout d\'un titre déjà présent : message et fiche ouverte', (
    tester,
  ) async {
    preparer();
    service.idTitreDejaPresent = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranBibliotheque(),
        bibliotheque: service,
        telechargement: telechargement,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FloatingActionButton, Textes.boutonAjouterTitre),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, Textes.champUrlTitre),
      'https://www.scan-manga.com/titre/shinigami',
    );
    await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
    await tester.pumpAndSettle();
    expect(find.text(Textes.titreDejaPresent), findsOneWidget);
    expect(find.byType(EcranTitre), findsOneWidget);
    expect(find.text(Textes.sitesDuTitreAvecNombre(2)), findsOneWidget);
    // Aucun titre créé en double.
    expect(service.titres, hasLength(1));
  });

  group('fiche', () {
    Future<void> afficher(WidgetTester tester, {double largeur = 1200}) async {
      tester.view.physicalSize = Size(largeur, 3200);
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
      await tester.pumpAndSettle();
      // Section « Sites » repliée au départ (retour 0.2.0-test).
      await basculerSitesDuTitre(tester);
    }

    testWidgets('section Sites, filtre et nom du site des chapitres', (
      tester,
    ) async {
      preparer();
      await afficher(tester);
      // En-tête : nombre de sites et site principal.
      expect(find.text(Textes.sitesDuTitreAvecNombre(2)), findsOneWidget);
      expect(find.text(Textes.resumeSitesDuTitre('MangaDex')), findsOneWidget);
      expect(
        find.text('${Textes.sitePrincipal} · ${Textes.chapitresDuSite(1)}'),
        findsOneWidget,
      );
      expect(
        find.text('${Textes.siteSecondaire} · ${Textes.chapitresDuSite(3)}'),
        findsOneWidget,
      );
      expect(find.text(Textes.ouvrirCeSite), findsNWidgets(2));
      // Le principal ne peut être ni retiré ni redéfini.
      expect(find.text(Textes.retirerSite), findsOneWidget);
      expect(find.text(Textes.definirSitePrincipal), findsOneWidget);
      expect(find.text(Textes.legendeSiteChapitre), findsOneWidget);
      expect(find.text(Textes.chapitreDuSite('Scan-Manga')), findsWidgets);

      await tester.tap(find.widgetWithText(ChoiceChip, 'MangaDex'));
      await tester.pumpAndSettle();
      expect(find.text('Seulement sur Scan-Manga'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, Textes.tousLesSites));
      await tester.pumpAndSettle();
      expect(find.text('Seulement sur Scan-Manga'), findsOneWidget);
    });

    testWidgets('un seul site : ni filtre ni nom de site', (tester) async {
      preparer(avecSecondaire: false);
      await afficher(tester, largeur: 400);
      expect(find.text(Textes.sitesDuTitreAvecNombre(1)), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      // Seule la ligne « Site » des informations nomme le site.
      expect(find.text(Textes.chapitreDuSite('MangaDex')), findsOneWidget);
      expect(find.text(Textes.legendeSiteChapitre), findsNothing);
      expect(find.text(Textes.ajouterAutreSite), findsOneWidget);
    });

    testWidgets('section Sites repliable : l\'en-tête reste, le contenu se '
        'cache', (tester) async {
      preparer();
      // `afficher` a déplié la section, repliée au départ.
      await afficher(tester);
      expect(find.text(Textes.ajouterAutreSite), findsOneWidget);

      await basculerSitesDuTitre(tester);
      expect(find.text(Textes.ajouterAutreSite), findsNothing);
      expect(find.text(Textes.ouvrirCeSite), findsNothing);
      expect(find.text(Textes.sitesDuTitreAvecNombre(2)), findsOneWidget);
    });

    testWidgets('retirer : confirmation avec chapitres et archives', (
      tester,
    ) async {
      preparer();
      await afficher(tester);
      await tester.tap(find.text(Textes.retirerSite));
      await tester.pumpAndSettle();
      expect(
        find.text(
          Textes.confirmationRetraitSite(
            nombreNonLusRetires: 2,
            nombreTelecharges: 1,
            // Réglage par défaut du faux service des paramètres.
            delaiSuppression: const Duration(hours: 24),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.retirerSite));
      await tester.pumpAndSettle();
      expect(service.journalSites, <String>['retirer:1:2']);
      expect(find.text(Textes.siteRetire(2)), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('ajouter un site refusé : message et rapport d\'erreur', (
      tester,
    ) async {
      preparer(avecSecondaire: false);
      service.erreurSites = const ErreurSource(
        'https://exemple.org/titre',
        'Page illisible',
      );
      await afficher(tester);
      await tester.tap(find.text(Textes.ajouterAutreSite));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://exemple.org/titre',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      // Le dialogue reste ouvert avec l'erreur et le bouton de rapport.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(Textes.exporterRapport), findsOneWidget);

      // Un simple refus (site non configuré) n'a rien à rapporter.
      service.erreurSites = const ErreurService(
        "Ce site n'est pas encore configuré.",
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      expect(find.textContaining('pas encore configuré'), findsOneWidget);
      expect(find.text(Textes.exporterRapport), findsNothing);
    });

    testWidgets('ajouter un site réussi : message et deux sites', (
      tester,
    ) async {
      preparer(avecSecondaire: false);
      await afficher(tester);
      await tester.tap(find.text(Textes.ajouterAutreSite));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://www.scan-manga.com/titre/shinigami',
      );
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(Textes.siteAjouteAuTitre(0)), findsOneWidget);
      expect(find.text(Textes.ouvrirCeSite), findsNWidgets(2));
      expect(telechargement.reglesAppliquees, contains(1));
    });

    testWidgets('actualisation : indique le site qui n\'a pas répondu', (
      tester,
    ) async {
      preparer();
      service.nombreNouveaux = 0;
      service.erreursParSiteActualisation = <int, Object>{
        2: const ErreurSource('https://www.scan-manga.com', 'Délai dépassé'),
      };
      await afficher(tester);
      await tester.tap(find.byTooltip(Textes.actualiser));
      await tester.pumpAndSettle();
      expect(
        find.text(
          Textes.actualisationSitesSansReponse(0, <String>['Scan-Manga']),
        ),
        findsOneWidget,
      );
    });
  });
}
