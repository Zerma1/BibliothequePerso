// Tâches T3 et T4 : liens seuls dans la section « Sites » de la fiche, ajout
// « quand même comme simple lien », diagnostic « Pourquoi ce site n'est pas
// lisible ? ». Faux services, aucun réseau.
import 'package:bibliotheque_perso/ecrans/ecran_titre.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/lien_titre_source.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

const String _urlRuri = 'https://ruri-dragon.online/';

void main() {
  late FauxServiceBibliotheque service;
  late FauxServiceTelechargement telechargement;

  /// Titre n°1 sur MangaDex (site 1) ; avec [secondaire], Scan-Manga
  /// (site 2) en site lu, ou en lien seul si [lienSeul].
  void preparer({bool secondaire = false, bool lienSeul = false}) {
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
      'Ruri Dragon',
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
        if (secondaire && !lienSeul) ...<Chapitre>[
          const Chapitre(
            id: 2,
            idSource: 2,
            urlChapitre: 'https://www.scan-manga.com/lecture/2',
            nom: 'Non lu',
            numero: 2,
            langue: 'fr',
          ),
          const Chapitre(
            id: 3,
            idSource: 2,
            urlChapitre: 'https://www.scan-manga.com/lecture/3',
            nom: 'Lu',
            numero: 3,
            langue: 'fr',
            estLu: true,
          ),
        ],
      ],
    );
    if (secondaire) {
      service.sitesSecondaires[1] = <LienTitreSource>[
        LienTitreSource(
          idTitre: 1,
          idSource: 2,
          urlTitre: 'https://www.scan-manga.com/titre/ruri',
          estLienSeul: lienSeul,
        ),
      ];
    }
  }

  setUp(() {
    service = FauxServiceBibliotheque();
    telechargement = FauxServiceTelechargement(service);
  });

  test('peutAjouterCommeLienSeul suit le service', () {
    final illisible = DescriptionErreur.depuis(
      const ErreurSource(_urlRuri, 'Aucun lien de chapitre'),
    );
    final nonConfigure = DescriptionErreur.depuis(
      const ErreurService('Non configuré', ajoutLienSeulPossible: true),
    );
    final dejaLie = DescriptionErreur.depuis(
      const ErreurService('Adresse déjà liée'),
    );
    expect(EtatTitre.peutAjouterCommeLienSeul(illisible), isTrue);
    expect(EtatTitre.peutAjouterCommeLienSeul(nonConfigure), isTrue);
    expect(EtatTitre.peutAjouterCommeLienSeul(dejaLie), isFalse);
    expect(
      EtatTitre.peutAjouterCommeLienSeul(
        const DescriptionErreur(NatureErreur.adresseVide),
      ),
      isFalse,
    );
  });

  group('EtatTitre (liens seuls)', () {
    late EtatTitre etat;

    Future<void> charger() async {
      etat = EtatTitre(service, 1, serviceTelechargement: telechargement);
      await etat.charger();
    }

    tearDown(() => etat.dispose());

    test(
      'ajouter un lien seul : aucune lecture, règles, fiche relue',
      () async {
        preparer();
        await charger();
        service.erreurSites = const ErreurSource(_urlRuri, 'Illisible');
        final resultat = await etat.ajouterLienSeul(' $_urlRuri ');
        expect(resultat.estReussi, isTrue);
        expect(service.journalSites, <String>['lienSeul:1:$_urlRuri']);
        expect(telechargement.reglesAppliquees, <int>[1]);
        expect(etat.sites.last.estLienSeul, isTrue);
        // Un lien seul sans chapitre ne fait pas apparaître le filtre par site.
        expect(etat.aPlusieursSites, isFalse);
        expect(etat.sitesAvecChapitres, hasLength(1));
      },
    );

    test('passer en lien seul : chapitres non lus retirés, lus gardés, '
        'règles appliquées', () async {
      preparer(secondaire: true);
      await charger();
      expect(etat.nombreChapitresRetiresAvecSite(2), 1);
      final resultat = await etat.passerEnLienSeul(2);
      expect(resultat.donnee, 1);
      expect(service.journalSites, <String>['marquerLienSeul:1:2:true']);
      expect(telechargement.reglesAppliquees, <int>[1]);
      expect(etat.sites.last.estLienSeul, isTrue);
      // Le chapitre lu reste : le site garde sa place dans le filtre.
      expect(etat.chapitres.map((c) => c.id), containsAll(<int>[1, 3]));
      expect(etat.aPlusieursSites, isTrue);
    });

    test(
      'essayer de le lire : site lu, relu seul, règles appliquées',
      () async {
        preparer(secondaire: true, lienSeul: true);
        await charger();
        final resultat = await etat.essayerDeLire(2);
        expect(resultat.estReussi, isTrue);
        expect(service.journalSites, <String>['essayerDeLireLienSeul:1:2']);
        expect(telechargement.reglesAppliquees, <int>[1]);
        expect(etat.sites.last.estLienSeul, isFalse);
      },
    );

    test('essayer de le lire, toujours illisible : retour en lien seul et '
        'erreur renvoyée', () async {
      preparer(secondaire: true, lienSeul: true);
      await charger();
      service.erreurActualisationSite = const ErreurSource(
        'https://www.scan-manga.com/titre/ruri',
        'Protection anti-robot',
        protectionAntiRobot: true,
      );
      final resultat = await etat.essayerDeLire(2);
      expect(resultat.erreur?.nature, NatureErreur.site);
      expect(service.journalSites, <String>['essayerDeLireLienSeul:1:2']);
      expect(etat.sites.last.estLienSeul, isTrue);
      expect(etat.estEnModificationSites, isFalse);
    });

    test('diagnostic : rendu du service, adresse nettoyée', () async {
      preparer();
      await charger();
      service.diagnosticSite = const DiagnosticLisibilite(
        raisons: <String>['Aucun lien de chapitre trouvé'],
      );
      final resultat = await etat.diagnostiquerSite(' $_urlRuri ');
      expect(resultat.donnee?.estLisible, isFalse);
      expect(service.sitesDiagnostiques, <String>[_urlRuri]);
    });
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

    Future<void> ajouterRefuse(WidgetTester tester) async {
      await tester.tap(find.text(Textes.ajouterAutreSite));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _urlRuri);
      await tester.tap(find.widgetWithText(FilledButton, Textes.ajouter));
      await tester.pumpAndSettle();
    }

    testWidgets('lien seul : marqué, « Ouvrir dans le navigateur » et '
        '« Essayer de le lire », sans « Définir comme site principal »', (
      tester,
    ) async {
      preparer(secondaire: true, lienSeul: true);
      await afficher(tester);
      expect(
        find.text(
          '${Textes.siteSecondaire} · ${Textes.lienSeul}\n'
          '${Textes.explicationLigneLienSeul}',
        ),
        findsOneWidget,
      );
      expect(find.text(Textes.ouvrirDansNavigateur), findsOneWidget);
      expect(find.text(Textes.essayerDeLire), findsOneWidget);
      expect(find.text(Textes.definirSitePrincipal), findsNothing);
      expect(find.text(Textes.passerEnLienSeul), findsNothing);
      expect(find.text(Textes.retirerSite), findsOneWidget);
      // Aucun chapitre de ce site : pas de filtre par site.
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.text(Textes.essayerDeLire));
      await tester.pumpAndSettle();
      expect(find.text(Textes.lienSeulLu(0)), findsOneWidget);
      expect(telechargement.reglesAppliquees, contains(1));
      expect(find.text(Textes.definirSitePrincipal), findsOneWidget);
    });

    testWidgets('site lu passé en lien seul : confirmation qui annonce les '
        'chapitres retirés', (tester) async {
      preparer(secondaire: true);
      await afficher(tester);
      await tester.tap(find.text(Textes.passerEnLienSeul));
      await tester.pumpAndSettle();
      expect(
        find.text(
          Textes.confirmationPassageLienSeul(
            nombreNonLusRetires: 1,
            nombreTelecharges: 0,
            delaiSuppression: const Duration(hours: 24),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, Textes.passerEnLienSeul),
      );
      await tester.pumpAndSettle();
      expect(service.journalSites, <String>['marquerLienSeul:1:2:true']);
      expect(find.text(Textes.sitePasseEnLienSeul(1)), findsOneWidget);
      expect(find.text(Textes.ouvrirDansNavigateur), findsOneWidget);
      expect(telechargement.reglesAppliquees, contains(1));
    });

    testWidgets('ajout refusé (site illisible) : diagnostic puis ajout comme '
        'simple lien', (tester) async {
      preparer();
      service.erreurSites = const ErreurSource(_urlRuri, 'Page illisible');
      service.diagnosticSite = const DiagnosticLisibilite(
        raisons: <String>['Aucun lien de chapitre trouvé'],
        remarques: <String>['Site dédié à une seule œuvre'],
      );
      await afficher(tester);
      await ajouterRefuse(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(Textes.explicationAjoutLienSeul), findsOneWidget);
      expect(find.text(Textes.ajouterCommeLienSeul), findsOneWidget);

      // Diagnostic seulement à la demande (une requête au site).
      expect(service.sitesDiagnostiques, isEmpty);
      await tester.tap(find.text(Textes.pourquoiIllisible));
      await tester.pumpAndSettle();
      expect(service.sitesDiagnostiques, <String>[_urlRuri]);
      expect(find.text('• Aucun lien de chapitre trouvé'), findsOneWidget);
      expect(find.text('• Site dédié à une seule œuvre'), findsOneWidget);
      expect(find.text(Textes.explicationProtectionAntiRobot), findsNothing);

      await tester.tap(find.text(Textes.ajouterCommeLienSeul));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(Textes.lienSeulAjoute), findsOneWidget);
      expect(service.journalSites.last, 'lienSeul:1:$_urlRuri');
      expect(find.text(Textes.ouvrirDansNavigateur), findsOneWidget);
      expect(telechargement.reglesAppliquees, contains(1));
    });

    testWidgets('diagnostic d\'une protection anti-robot : explication', (
      tester,
    ) async {
      preparer();
      service.erreurSites = const ErreurSource(
        _urlRuri,
        'Protection anti-robot',
        protectionAntiRobot: true,
      );
      service.diagnosticSite = const DiagnosticLisibilite(
        raisons: <String>['Le site est protégé'],
        protectionAntiRobot: true,
      );
      await afficher(tester);
      await ajouterRefuse(tester);
      await tester.tap(find.text(Textes.pourquoiIllisible));
      await tester.pumpAndSettle();
      expect(find.text(Textes.explicationProtectionAntiRobot), findsOneWidget);
    });

    testWidgets('refus qui ne dépend pas du site : ni diagnostic ni lien '
        'seul', (tester) async {
      preparer();
      service.erreurSites = const ErreurService(
        'Cette adresse est déjà un site de « Ruri Dragon ».',
      );
      await afficher(tester);
      await ajouterRefuse(tester);
      expect(find.textContaining('déjà un site'), findsOneWidget);
      expect(find.text(Textes.ajouterCommeLienSeul), findsNothing);
      expect(find.text(Textes.pourquoiIllisible), findsNothing);
    });
  });
}
