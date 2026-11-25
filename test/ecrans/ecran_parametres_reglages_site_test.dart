// « Modifier le site » : réglages avancés (sélecteurs CSS) d'un site
// générique, préremplis, vérifiés et enregistrés par modifierSource.
// Faux services, aucun réseau.
import 'dart:convert';

import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceAjoutSite ajoutSite;
  late FauxServiceParametres parametres;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    ajoutSite = FauxServiceAjoutSite(bibliotheque);
    parametres = FauxServiceParametres();
  });

  Future<void> ouvrirDialogue(WidgetTester tester, Source source) async {
    bibliotheque.sources.add(source);
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        ajoutSite: ajoutSite,
        parametres: parametres,
      ),
    );
    await tester.pump();
    await tester.pump();
    await deplierParametres(tester);
    await tester.tap(find.byTooltip(Textes.modifierSite));
    await tester.pumpAndSettle();
  }

  Future<void> enregistrer(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(FilledButton, Textes.enregistrer).last,
    );
    await tester.pumpAndSettle();
  }

  Finder champ(String cle) => find.byKey(ValueKey<String>('reglage_$cle'));

  const generique = Source(
    id: 1,
    nom: 'Ruri',
    urlBase: 'https://ruri-dragon.online',
    typeSource: TypeSource.generique,
    configurationSelecteurs: '{"selecteurTitre":"h1.titre"}',
  );

  testWidgets('site générique : section dépliée et préremplie', (tester) async {
    await ouvrirDialogue(tester, generique);
    expect(find.text(Textes.reglagesAvancesSelecteurs), findsOneWidget);
    for (final cle in EtatSources.clesReglagesGeneriques) {
      expect(champ(cle), findsOneWidget);
    }
    expect(
      tester.widget<TextFormField>(champ('selecteurTitre')).controller!.text,
      'h1.titre',
    );
  });

  testWidgets('modifier un réglage : enregistré par modifierSource', (
    tester,
  ) async {
    await ouvrirDialogue(tester, generique);
    await tester.enterText(champ('selecteurImagesChapitre'), '.lecture img');
    await enregistrer(tester);
    expect(
      jsonDecode(ajoutSite.sourcesModifiees.single.configurationSelecteurs!),
      <String, Object?>{
        'selecteurTitre': 'h1.titre',
        'selecteurImagesChapitre': '.lecture img',
      },
    );
    expect(find.text(Textes.siteModifie('Ruri')), findsOneWidget);
  });

  testWidgets('tout vider : réglages effacés', (tester) async {
    await ouvrirDialogue(tester, generique);
    await tester.enterText(champ('selecteurTitre'), '');
    await enregistrer(tester);
    expect(ajoutSite.sourcesModifiees.single.configurationSelecteurs, isNull);
    expect(bibliotheque.sources.single.configurationSelecteurs, isNull);
  });

  testWidgets('rien changé : réglages enregistrés gardés tels quels', (
    tester,
  ) async {
    await ouvrirDialogue(tester, generique);
    await enregistrer(tester);
    expect(
      ajoutSite.sourcesModifiees.single.configurationSelecteurs,
      generique.configurationSelecteurs,
    );
  });

  testWidgets('ancien réglage aujourd\'hui refusé : renommage possible', (
    tester,
  ) async {
    const ancien = Source(
      id: 1,
      nom: 'Ruri',
      urlBase: 'https://ruri-dragon.online',
      typeSource: TypeSource.generique,
      configurationSelecteurs: '{"motifNumeroChapitre":"(non fermé"}',
    );
    await ouvrirDialogue(tester, ancien);
    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.champNomSiteObligatoire),
      'Ruri Dragon',
    );
    await enregistrer(tester);
    final modifiee = ajoutSite.sourcesModifiees.single;
    expect(modifiee.nom, 'Ruri Dragon');
    expect(modifiee.configurationSelecteurs, ancien.configurationSelecteurs);
    expect(find.text(Textes.siteModifie('Ruri Dragon')), findsOneWidget);
  });

  testWidgets('motif invalide : message sous le champ, rien enregistré', (
    tester,
  ) async {
    await ouvrirDialogue(tester, generique);
    await tester.enterText(champ('motifNumeroChapitre'), '(non fermé');
    await enregistrer(tester);
    expect(
      find.text(
        EtatSources.erreurReglageGenerique(
          'motifNumeroChapitre',
          '(non fermé',
        )!,
      ),
      findsOneWidget,
    );
    expect(ajoutSite.sourcesModifiees, isEmpty);
  });

  testWidgets('autre type de site : pas de réglages avancés', (tester) async {
    await ouvrirDialogue(
      tester,
      const Source(
        id: 1,
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
      ),
    );
    expect(find.text(Textes.reglagesAvancesSelecteurs), findsNothing);
    await enregistrer(tester);
    expect(ajoutSite.sourcesModifiees.single.configurationSelecteurs, isNull);
  });
}
