// Tests de EcranTelechargements avec de faux services.
import 'package:bibliotheque_perso/ecrans/ecran_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceTelechargement service;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    service = FauxServiceTelechargement(bibliotheque);
    bibliotheque.ajouterTitreDeTest(
      'Solo Leveling',
      chapitres: const <Chapitre>[
        Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
        Chapitre(id: 2, urlChapitre: 'u2', nom: 'Deux', numero: 2),
        Chapitre(id: 3, urlChapitre: 'u3', nom: 'Trois', numero: 3),
      ],
    );
  });

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      envelopper(
        const EcranTelechargements(),
        bibliotheque: bibliotheque,
        telechargement: service,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('file vide : message d\'aide', (tester) async {
    await afficher(tester);
    expect(find.text(Textes.telechargementsVide), findsOneWidget);
  });

  testWidgets('affiche titre, chapitre, statut et progression', (tester) async {
    service
      ..modifierLigne(1, StatutTelechargement.enCours, faites: 5, total: 20)
      ..modifierLigne(2, StatutTelechargement.enAttente)
      ..modifierLigne(3, StatutTelechargement.echec, messageErreur: 'HTTP 403');
    await afficher(tester);

    expect(find.text('Solo Leveling'), findsNWidgets(3));
    expect(find.text('Un'), findsOneWidget);
    expect(find.text('En cours : 5 / 20 pages'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(find.text('Échec : HTTP 403'), findsOneWidget);
    final barre = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(barre.value, 0.25);

    // La progression avance en direct.
    service.modifierLigne(
      1,
      StatutTelechargement.enCours,
      faites: 10,
      total: 20,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('En cours : 10 / 20 pages'), findsOneWidget);
  });

  testWidgets('réessayer un échec et retirer de la file', (tester) async {
    service
      ..modifierLigne(2, StatutTelechargement.enAttente)
      ..modifierLigne(3, StatutTelechargement.echec, messageErreur: 'panne');
    await afficher(tester);

    await tester.tap(find.byTooltip(Textes.reessayer));
    await tester.pump();
    await tester.pump();
    expect(find.text('En attente'), findsNWidgets(2));

    await tester.tap(find.byTooltip(Textes.retirerDeLaFile).first);
    await tester.pump();
    await tester.pump();
    expect(service.journal, contains('supprimer:2'));
  });

  testWidgets("supprimer un chapitre terminé demande confirmation", (
    tester,
  ) async {
    service.modifierLigne(1, StatutTelechargement.termine);
    await afficher(tester);

    // Annuler : rien n'est supprimé.
    await tester.tap(find.byTooltip(Textes.supprimerTelechargement));
    await tester.pumpAndSettle();
    expect(
      find.text(
        Textes.confirmationSuppressionTelechargement(
          Textes.chapitreDuTitre('Solo Leveling', 'Un'),
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(Textes.annuler));
    await tester.pumpAndSettle();
    expect(service.journal, isNot(contains('supprimer:1')));

    // Confirmer : l'archive est supprimée.
    await tester.tap(find.byTooltip(Textes.supprimerTelechargement));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Textes.supprimer));
    await tester.pumpAndSettle();
    expect(service.journal, contains('supprimer:1'));
    expect(find.text(Textes.telechargementSupprime), findsOneWidget);
  });

  testWidgets('vider les terminés', (tester) async {
    service
      ..modifierLigne(1, StatutTelechargement.termine)
      ..modifierLigne(2, StatutTelechargement.enAttente);
    await afficher(tester);

    await tester.tap(find.byTooltip(Textes.viderTermines));
    await tester.pump();
    await tester.pump();
    expect(find.text('Terminé'), findsNothing);
    expect(find.text(Textes.terminesRetires(1)), findsOneWidget);
  });

  testWidgets('erreur : message et Réessayer', (tester) async {
    service.erreurFile = const ErreurService('File illisible.');
    await afficher(tester);

    expect(find.text('File illisible.'), findsOneWidget);
    service.erreurFile = null;
    await tester.tap(find.text(Textes.reessayer));
    await tester.pump();
    await tester.pump();
    expect(find.text(Textes.telechargementsVide), findsOneWidget);
  });
}
