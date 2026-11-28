// Tests de l'écran « Mes tickets » et de son détail (version 0.4.0), avec
// un faux service et un faux navigateur : aucun réseau.
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/ecrans/ecran_tickets.dart';
import 'package:bibliotheque_perso/etat/etat_tickets.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/ticket.dart';
import 'package:bibliotheque_perso/services/service_tickets.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/faux_service_tickets.dart';
import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceTickets service;
  late List<Uri> liensOuverts;
  late bool ouvertureReussie;

  setUp(() {
    service = FauxServiceTickets();
    liensOuverts = <Uri>[];
    ouvertureReussie = true;
  });

  Future<bool> fauxNavigateur(Uri adresse) async {
    liensOuverts.add(adresse);
    return ouvertureReussie;
  }

  Future<void> afficher(
    WidgetTester tester, {
    Size taille = const Size(900, 1200),
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EtatTickets>(
        create: (_) => EtatTickets(service),
        // Fournisseur au-dessus du Navigator : le détail poussé le lit aussi.
        child: MaterialApp(home: EcranTickets(ouvrirLien: fauxNavigateur)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la liste montre type, état, commentaires, étiquettes et '
      '« Nouveau »', (tester) async {
    service.tickets = <Ticket>[
      ticketRetrouve(
        nouveau: true,
        commentaires: 2,
        etiquettes: const <String>['bug', 'confirmé'],
      ),
      ticketRetrouve(
        id: 2,
        titre: 'Tri par date',
        type: TypeTicket.suggestion,
        etat: EtatTicket.ferme,
        raison: RaisonFermetureTicket.nonRetenu,
      ),
      ticketEnAttente(),
    ];
    await afficher(tester);

    expect(service.actualisations, <bool>[false]);
    expect(find.text('Plantage au démarrage'), findsOneWidget);
    expect(
      find.textContaining('Bug · Ouvert · 2 commentaires'),
      findsOneWidget,
    );
    expect(find.text('confirmé'), findsOneWidget);
    expect(find.text(Textes.ticketNouveau), findsOneWidget);
    expect(find.textContaining('Fermé : non retenu'), findsOneWidget);
    expect(find.textContaining('En attente de publication'), findsOneWidget);
  });

  testWidgets('liste vide : message d\'aide', (tester) async {
    await afficher(tester);
    expect(find.text(Textes.aucunTicket), findsOneWidget);
  });

  testWidgets('base illisible : erreur et « Réessayer »', (tester) async {
    service.erreurChargement = const ErreurBaseDeDonnees('Base illisible.');
    await afficher(tester);
    expect(find.text(Textes.reessayer), findsOneWidget);

    service.erreurChargement = null;
    await tester.tap(find.text(Textes.reessayer));
    await tester.pumpAndSettle();
    expect(find.text(Textes.aucunTicket), findsOneWidget);
  });

  testWidgets('limite GitHub : message affiché au-dessus de la liste, et '
      '« Actualiser » force la demande', (tester) async {
    service.tickets = <Ticket>[ticketRetrouve()];
    service.resultatActualisation = const ResultatActualisationTickets(
      messageErreur:
          'Limite de requêtes GitHub atteinte : nouvel essai '
          'possible à 15:30.',
    );
    await afficher(tester);
    expect(find.textContaining('15:30'), findsOneWidget);
    expect(find.text('Plantage au démarrage'), findsOneWidget);

    await tester.tap(find.byTooltip(Textes.actualiser));
    await tester.pumpAndSettle();
    expect(service.actualisations, <bool>[false, true]);
  });

  testWidgets('nouveau ticket : titre obligatoire, puis ouverture de la page '
      'de création', (tester) async {
    await afficher(tester);
    await tester.tap(find.text(Textes.nouveauTicket));
    await tester.pumpAndSettle();
    expect(find.text(Textes.avertissementTicketPublic), findsOneWidget);

    await tester.tap(find.text(Textes.continuerSurGithub));
    await tester.pumpAndSettle();
    expect(find.text(Textes.champObligatoire), findsOneWidget);
    expect(service.preparations, isEmpty);

    await tester.tap(find.text('Suggestion'));
    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.libelleTitreTicket),
      'Mode lecture continue',
    );
    await tester.tap(find.text(Textes.continuerSurGithub));
    await tester.pumpAndSettle();

    expect(service.preparations.single.$1, 'Mode lecture continue');
    expect(service.preparations.single.$2, TypeTicket.suggestion);
    expect(liensOuverts, <Uri>[service.urlCreation]);
    expect(find.text(Textes.ticketPrepare), findsOneWidget);
    expect(find.text('Mode lecture continue'), findsOneWidget);
  });

  testWidgets('navigateur indisponible : l\'adresse est proposée à la copie', (
    tester,
  ) async {
    ouvertureReussie = false;
    await afficher(tester);
    await tester.tap(find.text(Textes.nouveauTicket));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, Textes.libelleTitreTicket),
      'Bug',
    );
    await tester.tap(find.text(Textes.continuerSurGithub));
    await tester.pumpAndSettle();

    expect(find.text(Textes.ouvertureImpossible), findsOneWidget);
    expect(
      find.widgetWithText(SelectableText, service.urlCreation.toString()),
      findsOneWidget,
    );
    expect(find.text(Textes.copierAdresse), findsOneWidget);
  });

  testWidgets('détail : commentaires, « Voir sur GitHub » et retrait '
      'confirmé', (tester) async {
    service.tickets = <Ticket>[ticketRetrouve(commentaires: 1, nouveau: true)];
    service.commentaires = <CommentaireTicketGithub>[
      CommentaireTicketGithub(
        auteur: null,
        date: DateTime.utc(2026, 11, 26, 9),
        corps: 'Corrigé dans la prochaine version.',
      ),
    ];
    await afficher(tester);
    await tester.tap(find.text('Plantage au démarrage'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(SelectableText, 'Corrigé dans la prochaine version.'),
      findsOneWidget,
    );
    expect(find.textContaining(Textes.auteurInconnu), findsOneWidget);

    await tester.tap(find.text(Textes.voirSurGithub));
    await tester.pumpAndSettle();
    expect(liensOuverts.single.path, endsWith('/issues/41'));

    await tester.tap(find.text(Textes.retirerDeMaListe));
    await tester.pumpAndSettle();
    expect(find.text(Textes.confirmationRetraitTicket), findsOneWidget);
    await tester.tap(find.text(Textes.retirer));
    await tester.pumpAndSettle();

    expect(service.retires, hasLength(1));
    expect(find.text(Textes.aucunTicket), findsOneWidget);
    expect(find.text(Textes.ticketRetire), findsOneWidget);
  });

  testWidgets('détail d\'un ticket non publié : explication, sans '
      'commentaires ni lien GitHub', (tester) async {
    service.tickets = <Ticket>[ticketEnAttente()];
    await afficher(tester, taille: const Size(400, 900));
    await tester.tap(find.text('Idée de tri'));
    await tester.pumpAndSettle();

    expect(find.textContaining(Textes.ticketEnAttente), findsOneWidget);
    expect(find.text(Textes.voirSurGithub), findsNothing);
    expect(find.text(Textes.commentaires), findsNothing);
    // Page de création inconnue (ticket d'une session précédente).
    expect(find.text(Textes.rouvrirPageCreation), findsNothing);
  });

  testWidgets('Paramètres : section « Aide et retours » avec la pastille', (
    tester,
  ) async {
    service.tickets = <Ticket>[ticketRetrouve(nouveau: true)];
    final etat = EtatTickets(service);
    addTearDown(etat.dispose);
    await etat.chargerNombreNouveautes();
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EtatTickets>.value(
        value: etat,
        child: envelopper(
          const EcranParametres(),
          bibliotheque: FauxServiceBibliotheque(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(Textes.sectionAideRetours), findsOneWidget);
    expect(find.text(Textes.ticketsAvecNouveautes(1)), findsOneWidget);
    await basculerSection(tester, Textes.sectionAideRetours);
    expect(find.text(Textes.mesTickets), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
  });
}
