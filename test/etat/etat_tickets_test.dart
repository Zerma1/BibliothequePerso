// Tests de EtatTickets (tickets GitHub, version 0.4.0) avec un faux service.
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_tickets.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/ticket.dart';
import 'package:bibliotheque_perso/services/service_tickets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'faux_service_tickets.dart';

void main() {
  late FauxServiceTickets service;
  late EtatTickets etat;

  setUp(() {
    service = FauxServiceTickets();
    etat = EtatTickets(service);
  });

  tearDown(() => etat.dispose());

  test(
    "l'ouverture lit la liste puis lance une actualisation automatique",
    () async {
      service.tickets = <Ticket>[
        ticketRetrouve(nouveau: true),
        ticketRetrouve(id: 2),
        ticketEnAttente(),
      ];

      await etat.ouvrir();

      expect(etat.estCharge, isTrue);
      expect(etat.tickets, hasLength(3));
      expect(etat.nombreNouveautes, 1);
      expect(service.actualisations, <bool>[false]);
    },
  );

  test('le bouton « Actualiser » demande une actualisation forcée', () async {
    await etat.actualiser(demandeParUtilisateur: true);
    expect(service.actualisations, <bool>[true]);
    expect(etat.estEnActualisation, isFalse);
  });

  test("une limite GitHub donne un message et l'heure de reprise, gardés "
      'après une actualisation automatique ignorée', () async {
    final reprise = DateTime.utc(2026, 11, 27, 15, 30);
    service.resultatActualisation = ResultatActualisationTickets(
      messageErreur: 'Limite de requêtes GitHub atteinte.',
      heureReprise: reprise,
    );
    await etat.actualiser(demandeParUtilisateur: true);
    expect(etat.messageActualisation, 'Limite de requêtes GitHub atteinte.');
    expect(etat.heureReprise, reprise);

    service.resultatActualisation = const ResultatActualisationTickets(
      ignoree: true,
    );
    await etat.actualiser();
    expect(etat.messageActualisation, isNotNull);

    service.resultatActualisation = const ResultatActualisationTickets();
    await etat.actualiser(demandeParUtilisateur: true);
    expect(etat.messageActualisation, isNull);
    expect(etat.heureReprise, isNull);
  });

  test('une base illisible donne une erreur, sans actualisation', () async {
    service.erreurChargement = const ErreurBaseDeDonnees('Base illisible.');

    await etat.ouvrir();

    expect(etat.erreur?.nature, NatureErreur.baseDeDonnees);
    expect(service.actualisations, isEmpty);
  });

  test(
    'un ticket préparé est listé et sa page de création est gardée',
    () async {
      final resultat = await etat.preparerTicket(
        type: TypeTicket.question,
        titre: 'Comment exporter ?',
        description: '',
      );

      expect(resultat.estReussi, isTrue);
      final ticket = resultat.donnee!.ticket;
      expect(etat.tickets.single.titre, 'Comment exporter ?');
      expect(etat.urlCreation(ticket), service.urlCreation);
      expect(etat.urlPage(ticket), isNull);
    },
  );

  test('un titre vide est refusé avec le message du service', () async {
    final resultat = await etat.preparerTicket(
      type: TypeTicket.bug,
      titre: '  ',
      description: 'x',
    );

    expect(resultat.estReussi, isFalse);
    expect(resultat.erreur?.nature, NatureErreur.refus);
    expect(etat.tickets, isEmpty);
  });

  test(
    'lire les commentaires marque le ticket consulté (pastille relue)',
    () async {
      service.tickets = <Ticket>[
        ticketRetrouve(nouveau: true, commentaires: 1),
      ];
      service.commentaires = <CommentaireTicketGithub>[
        CommentaireTicketGithub(
          auteur: 'mainteneur',
          date: DateTime.utc(2026, 11, 26),
          corps: 'Merci !',
        ),
      ];
      await etat.charger();
      expect(etat.nombreNouveautes, 1);

      final resultat = await etat.chargerCommentaires(etat.tickets.single);

      expect(resultat.donnee, hasLength(1));
      expect(etat.nombreNouveautes, 0);
    },
  );

  test('retirer un ticket le retire de la liste', () async {
    service.tickets = <Ticket>[ticketRetrouve(), ticketEnAttente()];
    await etat.charger();

    final resultat = await etat.retirerTicket(etat.tickets.first);

    expect(resultat.donnee, isTrue);
    expect(etat.tickets, hasLength(1));
    expect(service.retires, hasLength(1));
  });

  test('chargerNombreNouveautes lit la pastille sans lire la liste', () async {
    service.tickets = <Ticket>[ticketRetrouve(nouveau: true)];
    await etat.chargerNombreNouveautes();
    expect(etat.nombreNouveautes, 1);
    expect(etat.estCharge, isFalse);
  });
}
