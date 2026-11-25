// Tests de l'onglet Téléchargements, étape 6 : section des suppressions
// prévues (rouge, compte à rebours, « Garder » / « Supprimer maintenant »)
// et repère « gardé ».
import 'package:bibliotheque_perso/ecrans/ecran_telechargements.dart';
import 'package:bibliotheque_perso/etat/etat_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

final DateTime _maintenant = DateTime.utc(2026, 11, 16, 12);

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceTelechargement telechargement;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque()
      ..ajouterTitreDeTest(
        'Shinigami',
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: '', numero: 1, langue: 'fr'),
          Chapitre(id: 2, urlChapitre: 'u2', nom: '', numero: 2, langue: 'fr'),
          Chapitre(id: 3, urlChapitre: 'u3', nom: '', numero: 3, langue: 'fr'),
        ],
      );
    telechargement = FauxServiceTelechargement(bibliotheque)
      ..ajouterChapitreTelecharge(1)
      ..ajouterChapitreTelecharge(2)
      ..planifierSuppressionDeTest(
        1,
        _maintenant.add(const Duration(hours: 5, minutes: 30)),
      );
  });

  Future<void> afficher(WidgetTester tester, {double largeur = 400}) async {
    tester.view.physicalSize = Size(largeur, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranTelechargements(),
        bibliotheque: bibliotheque,
        telechargement: telechargement,
        maintenant: () => _maintenant,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('section rouge avec compte à rebours, puis « Garder »', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text(Textes.sectionSuppressionsPrevues(1)), findsOneWidget);
    expect(
      find.text(Textes.suppressionDans(const Duration(hours: 5, minutes: 30))),
      findsOneWidget,
    );
    expect(find.text('Shinigami'), findsOneWidget);
    // File vide : dit sous son intertitre.
    expect(find.text(Textes.sectionFile), findsOneWidget);
    expect(find.text(Textes.fileVide), findsOneWidget);

    await tester.tap(find.text(Textes.garder));
    await tester.pumpAndSettle();

    expect(telechargement.journal, contains('garder:1'));
    expect(find.text(Textes.chapitreGarde), findsOneWidget);
    // Plus de suppression prévue, plus rien dans la file : écran vide.
    expect(find.text(Textes.telechargementsVide), findsOneWidget);
  });

  testWidgets('« Supprimer maintenant » efface l\'archive', (tester) async {
    await afficher(tester);

    await tester.tap(find.text(Textes.supprimerMaintenant));
    await tester.pumpAndSettle();

    expect(telechargement.journal, contains('supprimerMaintenant:1'));
    expect(find.text(Textes.sectionSuppressionsPrevues(1)), findsNothing);
  });

  group('« Supprimer tous les chapitres à supprimer »', () {
    setUp(() {
      telechargement.planifierSuppressionDeTest(
        2,
        _maintenant.add(const Duration(hours: 8)),
      );
    });

    testWidgets('annuler la confirmation ne supprime rien', (tester) async {
      await afficher(tester);
      expect(find.text(Textes.sectionSuppressionsPrevues(2)), findsOneWidget);

      await tester.tap(find.text(Textes.supprimerToutesSuppressionsPrevues));
      await tester.pumpAndSettle();
      expect(
        find.text(Textes.confirmationSupprimerToutesSuppressionsPrevues(2)),
        findsOneWidget,
      );
      await tester.tap(find.text(Textes.annuler));
      await tester.pumpAndSettle();

      expect(telechargement.journal, isNot(contains('supprimerToutes')));
      expect(find.text(Textes.sectionSuppressionsPrevues(2)), findsOneWidget);
    });

    testWidgets('confirmer supprime tout et affiche le nombre supprimé', (
      tester,
    ) async {
      await afficher(tester);

      await tester.tap(find.text(Textes.supprimerToutesSuppressionsPrevues));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.supprimer));
      await tester.pumpAndSettle();

      expect(telechargement.journal, contains('supprimerToutes'));
      expect(find.text(Textes.suppressionsPrevuesFaites(2)), findsOneWidget);
      // Section vidée, bouton disparu.
      expect(find.textContaining('Suppressions prévues'), findsNothing);
      expect(
        find.text(Textes.supprimerToutesSuppressionsPrevues),
        findsNothing,
      );
    });

    testWidgets('un refus du service (déplacement en cours) est affiché', (
      tester,
    ) async {
      telechargement.erreurSuppression = const ErreurService(
        'Les chapitres sont en cours de déplacement.',
      );
      await afficher(tester);

      await tester.tap(find.text(Textes.supprimerToutesSuppressionsPrevues));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.supprimer));
      await tester.pumpAndSettle();

      expect(find.textContaining('en cours de déplacement'), findsOneWidget);
      expect(find.text(Textes.sectionSuppressionsPrevues(2)), findsOneWidget);
    });

    test("EtatTelechargements : un chapitre ouvert dans le lecteur est "
        'épargné', () async {
      telechargement.protegerChapitre(2);
      final etat = EtatTelechargements(
        telechargement,
        bibliotheque,
        controlerEcheances: false,
        maintenant: () => _maintenant,
      );
      addTearDown(etat.dispose);
      await etat.charger();

      final resultat = await etat.supprimerToutesSuppressionsPrevues();

      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee, 1);
      expect(etat.suppressionsPrevues.map((e) => e.idChapitre), <int>[2]);
    });
  });

  testWidgets('repère « gardé » sur une ligne de la file', (tester) async {
    telechargement
      ..modifierLigne(2, StatutTelechargement.termine)
      ..gardes.add(2)
      ..planifierSuppressionDeTest(1, null);
    await afficher(tester, largeur: 1000);

    expect(find.text(Textes.sectionSuppressionsPrevues(1)), findsNothing);
    // Sans suppression prévue, pas de bouton de suppression groupée.
    expect(find.text(Textes.supprimerToutesSuppressionsPrevues), findsNothing);
    expect(find.text(Textes.garde), findsOneWidget);
    expect(find.byTooltip(Textes.infoGarde), findsOneWidget);
  });

  test('EtatTelechargements : suppressions prévues et temps restant', () async {
    final etat = EtatTelechargements(
      telechargement,
      bibliotheque,
      controlerEcheances: false,
      maintenant: () => _maintenant,
    );
    addTearDown(etat.dispose);

    await etat.charger();

    expect(etat.estVide, isFalse);
    expect(etat.suppressionsPrevues, hasLength(1));
    final prevue = etat.suppressionsPrevues.single;
    expect(prevue.idChapitre, 1);
    expect(prevue.titre?.nom, 'Shinigami');
    expect(
      prevue.tempsRestant(etat.maintenant),
      const Duration(hours: 5, minutes: 30),
    );
    // Échéance dépassée : jamais négatif.
    expect(
      prevue.tempsRestant(_maintenant.add(const Duration(days: 2))),
      Duration.zero,
    );

    final resultat = await etat.nePlusGarder(1);
    expect(resultat.estReussi, isTrue);
    expect(telechargement.journal, contains('retirerGarde:1'));
  });
}
