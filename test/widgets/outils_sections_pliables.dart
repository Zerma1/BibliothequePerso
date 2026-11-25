// Outils de test des sections repliables (SectionPliable).
import 'package:bibliotheque_perso/widgets/section_pliable.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appuie sur l'en-tête de la section repliable intitulée [titre] (la
/// déplie si elle est repliée, la replie sinon), après l'avoir amenée à
/// l'écran.
Future<void> basculerSection(WidgetTester tester, String titre) async {
  final entete = find.descendant(
    of: find.byType(SectionPliable),
    matching: find.text(titre),
  );
  await tester.ensureVisible(entete);
  await tester.pumpAndSettle();
  await tester.tap(entete);
  await tester.pumpAndSettle();
}

/// Appuie sur l'en-tête de la section « Sites (n) » de la fiche d'un titre :
/// la déplie (elle est repliée au départ), ou la replie si elle l'est déjà.
Future<void> basculerSitesDuTitre(WidgetTester tester) async {
  final entete = find.descendant(
    of: find.byType(SectionPliable),
    matching: find.textContaining(
      RegExp('^${RegExp.escape(Textes.sitesDuTitre)} \\(\\d+\\)\$'),
    ),
  );
  await tester.ensureVisible(entete);
  await tester.pumpAndSettle();
  await tester.tap(entete);
  await tester.pumpAndSettle();
}

/// Déplie toutes les sections de l'écran Paramètres repliées au départ
/// (« Mes langues » est déjà dépliée). Les sections absentes (export sans
/// service) sont ignorées. De bas en haut : tous les en-têtes sont visibles
/// tant que rien n'est déplié, et déplier une section ne repousse que
/// celles d'en dessous, déjà traitées.
Future<void> deplierParametres(WidgetTester tester) async {
  for (final titre in <String>[
    Textes.sectionAPropos,
    Textes.sectionJournal,
    Textes.sectionSauvegardeExport,
    Textes.sectionSites,
    Textes.sectionTelechargements,
    Textes.sectionMisesAJour,
  ]) {
    if (find.text(titre).evaluate().isEmpty) {
      // Section construite à la demande plus bas dans la liste, ou absente.
      continue;
    }
    await basculerSection(tester, titre);
  }
}
