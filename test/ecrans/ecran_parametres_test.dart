// Tests de EcranParametres avec de faux services.
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/widgets/constantes_interface.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

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

  Future<void> afficher(WidgetTester tester) async {
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
  }

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
    await tester.tap(find.byTooltip(Textes.augmenter).at(1));
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

      // Premier « + » de l'écran : la section Mises à jour est en haut.
      await tester.tap(find.byTooltip(Textes.augmenter).first);
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
