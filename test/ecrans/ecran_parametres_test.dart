// Tests de EcranParametres avec de faux services.
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_theme.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/constantes_interface.dart';
import 'package:bibliotheque_perso/widgets/section_pliable.dart';
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
    bibliotheque.sources.add(
      const Source(
        id: 1,
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
        langueParDefaut: 'fr,en',
      ),
    );
  });

  /// Affiche l'écran ; avec [toutDeplier], toutes les sections sont
  /// dépliées (seule « Mes langues » l'est au départ).
  Future<void> afficher(WidgetTester tester, {bool toutDeplier = true}) async {
    tester.view.physicalSize = const Size(900, 4000);
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
    if (toutDeplier) await deplierParametres(tester);
  }

  group('sections pliables (retour 0.2.0-test)', () {
    testWidgets('seule « Mes langues » est dépliée au départ ; les autres '
        'montrent un résumé', (tester) async {
      await afficher(tester, toutDeplier: false);

      // Six sections (dont « Apparence ») : pas de service d'export ici
      // (section masquée).
      expect(find.byType(SectionPliable), findsNWidgets(6));
      expect(
        find.text(Textes.resumeApparence(ModeTheme.systeme)),
        findsOneWidget,
      );
      // Mes langues : dépliée.
      expect(find.text(Textes.ajouterLangue), findsOneWidget);
      expect(
        find.text(Textes.listeLangues(<String>['fr', 'en'])),
        findsOneWidget,
      );
      // Les autres : repliées, avec leur résumé.
      expect(find.text(Textes.verificationsParJour), findsNothing);
      expect(find.text(Textes.resumeRecherches(2)), findsOneWidget);
      expect(find.text(Textes.resumeTelechargements), findsOneWidget);
      expect(find.text(Textes.nombreSites(1)), findsOneWidget);
      expect(find.byTooltip(Textes.modifierSite), findsNothing);
      expect(
        find.text(Textes.versionComplete(versionApplication)),
        findsOneWidget,
      );
      expect(find.text(Textes.creditMangaDexComplet), findsNothing);

      // Déplier puis replier une section.
      await basculerSection(tester, Textes.sectionSites);
      expect(find.byTooltip(Textes.modifierSite), findsOneWidget);
      await basculerSection(tester, Textes.sectionSites);
      expect(find.byTooltip(Textes.modifierSite), findsNothing);
    });

    testWidgets('un brouillon non enregistré est signalé section repliée', (
      tester,
    ) async {
      await afficher(tester, toutDeplier: false);
      await basculerSection(tester, Textes.sectionTelechargements);
      await tester.tap(
        boutonJauge('jauge.limite.favorisLusConserves', plus: true),
      );
      await tester.pump();
      await basculerSection(tester, Textes.sectionTelechargements);

      expect(find.text(Textes.modificationsNonEnregistrees), findsOneWidget);
      expect(find.text(Textes.resumeTelechargements), findsNothing);
    });

    testWidgets('erreur de lecture des réglages : message et « Réessayer » '
        'dans la section dépliée', (tester) async {
      parametres.erreurLecture = const ErreurService('Base occupée.');
      await afficher(tester, toutDeplier: false);

      expect(find.text('Base occupée.'), findsOneWidget);
      expect(find.text(Textes.reessayer), findsOneWidget);
    });
  });

  group('Mes langues', () {
    testWidgets('affiche les langues en français, la favorite d\'abord', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.text(Textes.sectionLangues), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('Anglais'), findsOneWidget);
      expect(find.text('fr · ${Textes.favorite}'), findsOneWidget);
      // La favorite n'a pas de bouton « Choisir comme favorite ».
      expect(find.byTooltip(Textes.choisirCommeFavorite), findsOneWidget);
    });

    testWidgets('ajoute une langue depuis la liste, avec recherche sans '
        'accents', (tester) async {
      await afficher(tester);

      await tester.tap(find.text(Textes.ajouterLangue));
      await tester.pumpAndSettle();
      // Les langues déjà choisies ne sont pas proposées.
      expect(find.widgetWithText(ListTile, 'Français'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'japon');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Japonais'));
      await tester.pumpAndSettle();

      expect(parametres.langues, <String>['fr', 'en', 'ja']);
      expect(telechargement.nombreAppelsReglesATous, 1);
      expect(find.text(Textes.languesEnregistrees), findsOneWidget);
    });

    testWidgets('« Choisir comme favorite » met la langue en premier, et la '
        'dernière langue ne peut pas être retirée', (tester) async {
      await afficher(tester);

      await tester.tap(find.byTooltip(Textes.choisirCommeFavorite));
      await tester.pumpAndSettle();
      expect(parametres.langues, <String>['en', 'fr']);
      expect(find.text('en · ${Textes.favorite}'), findsOneWidget);

      await tester.tap(find.byTooltip(Textes.retirerLangue).last);
      await tester.pumpAndSettle();
      expect(parametres.langues, <String>['en']);
      final retirer = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(retirer.onPressed, isNull);
    });
  });

  testWidgets('les langues d\'un site sont un réglage avancé, replié s\'il '
      'est vide', (tester) async {
    bibliotheque.sources[0] = bibliotheque.sources[0].copierAvec(
      langueParDefaut: '',
    );
    await afficher(tester);
    expect(find.text(Textes.languesSite('')), findsNothing);
    expect(find.textContaining(Textes.languesSite('')), findsOneWidget);

    await tester.tap(find.byTooltip(Textes.modifierSite));
    await tester.pumpAndSettle();

    expect(find.text(Textes.reglageAvanceLangues), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, Textes.champLangues),
      findsNothing,
    );
    await tester.tap(find.text(Textes.reglageAvanceLangues));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, Textes.champLangues),
      findsOneWidget,
    );
  });

  testWidgets('les quatre limites, leurs explications et l\'enregistrement', (
    tester,
  ) async {
    await afficher(tester);

    for (final limite in LimiteTelechargement.values) {
      expect(find.text(Textes.libelleLimite(limite)), findsOneWidget);
    }
    expect(
      find.text(
        Textes.explicationLimite(LimiteTelechargement.favorisLusConserves, 10),
      ),
      findsOneWidget,
    );

    // « Enregistrer » inactif tant que rien n'a changé.
    final enregistrer = find.widgetWithText(FilledButton, Textes.enregistrer);
    expect(tester.widget<FilledButton>(enregistrer).onPressed, isNull);

    // + sur la première limite (favoris : 10 → 11).
    await tester.tap(
      boutonJauge('jauge.limite.favorisLusConserves', plus: true),
    );
    await tester.pump();
    expect(
      find.text(
        Textes.explicationLimite(LimiteTelechargement.favorisLusConserves, 11),
      ),
      findsOneWidget,
    );
    await tester.tap(enregistrer);
    await tester.pump();
    await tester.pump();

    expect(parametres.reglages.favorisLusConserves, 11);
    expect(telechargement.nombreAppelsReglesATous, 1);
    expect(find.text(Textes.reglagesEnregistres), findsOneWidget);

    // Valeurs par défaut : remet 10 dans le brouillon.
    await tester.tap(find.text(Textes.valeursParDefaut));
    await tester.pump();
    expect(
      find.text(
        Textes.explicationLimite(LimiteTelechargement.favorisLusConserves, 10),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'mises à jour : nombre par jour, horaires et dernière recherche',
    (tester) async {
      parametres.derniereVerification = DateTime.utc(2026, 11, 15, 12, 5);
      await afficher(tester);

      expect(find.text(Textes.verificationsParJour), findsOneWidget);
      expect(find.textContaining('00:00 et 12:00 UTC'), findsOneWidget);
      expect(
        find.text(Textes.derniereRecherche(DateTime.utc(2026, 11, 15, 12, 5))),
        findsOneWidget,
      );

      await tester.tap(boutonJauge('jauge.recherchesParJour', plus: true));
      await tester.pump();
      await tester.pump();
      expect(parametres.verificationsParJour, 3);
      expect(find.textContaining('00:00, 08:00 et 16:00 UTC'), findsOneWidget);
      expect(find.text(Textes.planificationEnregistree), findsOneWidget);
    },
  );

  testWidgets('modifier les langues d\'un site', (tester) async {
    await afficher(tester);

    expect(find.textContaining(Textes.languesSite('fr,en')), findsOneWidget);
    await tester.tap(find.byTooltip(Textes.modifierSite));
    await tester.pumpAndSettle();
    expect(find.text(Textes.aideLangues), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champLangues),
      'fr,e',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, Textes.enregistrer).last,
    );
    await tester.pumpAndSettle();
    expect(find.text(Textes.erreurLangues), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champLangues),
      'en, fr',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, Textes.enregistrer).last,
    );
    await tester.pumpAndSettle();

    expect(bibliotheque.sources.single.langueParDefaut, 'en,fr');
    expect(telechargement.nombreAppelsReglesATous, 1);
    expect(find.text(Textes.siteModifie('MangaDex')), findsOneWidget);
  });

  testWidgets('supprimer un site qui a des titres : message clair', (
    tester,
  ) async {
    bibliotheque.ajouterTitreDeTest('Titre', idSource: 1);
    await afficher(tester);

    await tester.tap(find.byTooltip(Textes.supprimerSite));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, Textes.supprimer));
    await tester.pumpAndSettle();

    expect(find.text(Textes.erreurSiteAvecTitres(1)), findsOneWidget);
    expect(bibliotheque.sources, hasLength(1));
  });

  testWidgets('À propos : version et crédit MangaDex', (tester) async {
    await afficher(tester);

    expect(
      find.text(Textes.versionComplete(versionApplication)),
      findsOneWidget,
    );
    expect(find.text(Textes.creditMangaDexComplet), findsOneWidget);
  });
}
