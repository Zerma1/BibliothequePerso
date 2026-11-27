// Tests de ServiceTickets : base en mémoire et faux client GitHub, aucun
// appel réseau.

import 'dart:async';
import 'dart:math';

import 'package:bibliotheque_perso/donnees/depot_tickets.dart';
import 'package:bibliotheque_perso/modeles/ticket.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_tickets.dart';
import 'package:bibliotheque_perso/sources/client_tickets_github.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

/// Faux client : réponses programmées, appels comptés.
class _FauxClient implements ClientTicketsGithub {
  Map<String, TicketGithub> tickets = <String, TicketGithub>{};
  List<CommentaireTicketGithub> commentaires = <CommentaireTicketGithub>[];
  Object? erreur;
  Completer<void>? attente;
  int appelsTickets = 0;
  int appelsCommentaires = 0;
  Set<String>? derniersReperes;
  DateTime? dernierDepuis;

  @override
  DateTime? heureReprise;

  @override
  int? get requetesRestantes => null;

  @override
  Future<Map<String, TicketGithub>> recupererTicketsParRepere(
    Set<String> reperes, {
    DateTime? depuis,
  }) async {
    appelsTickets++;
    derniersReperes = reperes;
    dernierDepuis = depuis;
    await attente?.future;
    final e = erreur;
    if (e != null) throw e;
    return tickets;
  }

  @override
  Future<List<CommentaireTicketGithub>> recupererCommentaires(
    int numero,
  ) async {
    appelsCommentaires++;
    final e = erreur;
    if (e != null) throw e;
    return commentaires;
  }
}

TicketGithub _github(
  String repere,
  int numero, {
  EtatTicketGithub etat = EtatTicketGithub.ouvert,
  String? raison,
  DateTime? maj,
  int commentaires = 0,
}) => TicketGithub(
  repere: repere,
  numero: numero,
  titre: 'Titre $numero',
  etat: etat,
  raisonEtat: raison,
  etiquettes: const <String>['bug'],
  nombreCommentaires: commentaires,
  dateMiseAJour: maj ?? DateTime.utc(2026, 11, 27, 10),
  urlPage: 'https://github.com/Zerma1/BibliothequePerso/issues/$numero',
);

void main() {
  late Database base;
  late DepotTickets depot;
  late _FauxClient client;
  late ServiceTickets service;
  late DateTime maintenant;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    maintenant = DateTime.utc(2026, 11, 27, 12);
    depot = DepotTickets(base, horloge: () => maintenant);
    client = _FauxClient();
    service = ServiceTickets(
      depot,
      client,
      versionApplication: '0.4.0',
      systeme: 'windows (Windows 11)',
      horloge: () => maintenant,
      aleatoire: Random(42),
    );
  });

  tearDown(() async {
    await base.close();
  });

  group('règles pures', () {
    test('un repère est BP- suivi de 12 hexadécimaux minuscules', () {
      final repere = ServiceTickets.genererRepere(Random(1));
      expect(repere, matches(RegExp(r'^BP-[0-9a-f]{12}$')));
      expect(extraireReperesTicket(repere), <String>[repere]);
    });

    test('le corps contient la description, les informations et le repère', () {
      final corps = ServiceTickets.construireCorps(
        type: TypeTicket.bug,
        description: '  La lecture plante.  ',
        repere: 'BP-0123456789ab',
        versionApplication: '0.4.0',
        systeme: 'windows (Windows 11)',
      );
      expect(corps, contains('**Type :** Bug'));
      expect(corps, contains('La lecture plante.'));
      expect(corps, contains("- Version de l'application : 0.4.0"));
      expect(corps, contains('- Système : windows (Windows 11)'));
      expect(
        corps.trimRight().split('\n').last,
        "Repère : BP-0123456789ab (ne pas modifier : permet le suivi depuis "
        "l'application)",
      );
    });

    test('state_reason est traduit en raison de fermeture', () {
      expect(
        ServiceTickets.raisonDepuisGithub('completed'),
        RaisonFermetureTicket.termine,
      );
      expect(
        ServiceTickets.raisonDepuisGithub('not_planned'),
        RaisonFermetureTicket.nonRetenu,
      );
      expect(ServiceTickets.raisonDepuisGithub('duplicate'), isNull);
      expect(ServiceTickets.raisonDepuisGithub(null), isNull);
    });

    test("l'actualisation automatique attend cinq minutes", () {
      final t = DateTime.utc(2026, 1, 1, 12);
      expect(ServiceTickets.actualisationAutoPermise(null, t), isTrue);
      expect(
        ServiceTickets.actualisationAutoPermise(
          t,
          t.add(const Duration(minutes: 4)),
        ),
        isFalse,
      );
      expect(
        ServiceTickets.actualisationAutoPermise(
          t,
          t.add(const Duration(minutes: 5)),
        ),
        isTrue,
      );
    });

    test("l'adresse de la page d'un ticket retrouvé suit son numéro", () {
      final ticket = Ticket(
        repere: 'BP-0123456789ab',
        titre: 't',
        type: TypeTicket.bug,
        dateCreation: DateTime.utc(2026),
      );
      expect(ServiceTickets.urlPageTicket(ticket), isNull);
      expect(
        ServiceTickets.urlPageTicket(ticket.copierAvec(numero: 7)).toString(),
        'https://github.com/Zerma1/BibliothequePerso/issues/7',
      );
    });
  });

  group('preparerTicket', () {
    test(
      "enregistre le ticket avant de renvoyer l'adresse pré-remplie",
      () async {
        final prepare = await service.preparerTicket(
          titre: '  Écran   noir ',
          type: TypeTicket.suggestion,
          description: 'Détail',
        );
        expect(prepare.ticket.id, isNotNull);
        expect(prepare.ticket.titre, 'Écran noir');
        expect(await depot.chargerTous(), <Ticket>[prepare.ticket]);
        final parametres = prepare.urlCreation.queryParameters;
        expect(prepare.urlCreation.host, 'github.com');
        expect(parametres['title'], '[Suggestion] Écran noir');
        expect(parametres['body'], contains(prepare.ticket.repere));
        expect(client.appelsTickets, 0);
      },
    );

    test('un titre vide est refusé sans rien enregistrer', () async {
      await expectLater(
        service.preparerTicket(
          titre: '   ',
          type: TypeTicket.bug,
          description: '',
        ),
        throwsA(isA<ErreurService>()),
      );
      expect(await depot.chargerTous(), isEmpty);
    });
  });

  group('actualiser', () {
    test('sans ticket, aucune requête', () async {
      final resultat = await service.actualiser(demandeParUtilisateur: true);
      expect(resultat.nombreSuivis, 0);
      expect(client.appelsTickets, 0);
    });

    test(
      'une seule requête pour tous les repères, relevés enregistrés',
      () async {
        final a = await service.preparerTicket(
          titre: 'A',
          type: TypeTicket.bug,
          description: '',
        );
        final b = await service.preparerTicket(
          titre: 'B',
          type: TypeTicket.question,
          description: '',
        );
        client.tickets = <String, TicketGithub>{
          a.ticket.repere: _github(
            a.ticket.repere,
            12,
            etat: EtatTicketGithub.ferme,
            raison: 'not_planned',
          ),
        };
        final resultat = await service.actualiser(demandeParUtilisateur: true);
        expect(client.appelsTickets, 1);
        expect(client.derniersReperes, <String>{
          a.ticket.repere,
          b.ticket.repere,
        });
        expect(
          client.dernierDepuis,
          maintenant.subtract(ServiceTickets.margeDepuisCreation),
        );
        expect(resultat.aEchoue, isFalse);
        expect(resultat.nombreSuivis, 2);
        expect(resultat.nombreRetrouves, 1);
        expect(resultat.nombreNouveautes, 0);

        final ticketA = (await depot.chargerParRepere(a.ticket.repere))!;
        expect(ticketA.numero, 12);
        expect(ticketA.etat, EtatTicket.ferme);
        expect(ticketA.raisonFermeture, RaisonFermetureTicket.nonRetenu);
        final ticketB = (await depot.chargerParRepere(b.ticket.repere))!;
        expect(ticketB.estRetrouve, isFalse);
        expect(ticketB.dateDernierReleve, maintenant);
      },
    );

    test(
      'un changement après le premier relevé compte comme nouveauté',
      () async {
        final a = await service.preparerTicket(
          titre: 'A',
          type: TypeTicket.bug,
          description: '',
        );
        client.tickets = <String, TicketGithub>{
          a.ticket.repere: _github(a.ticket.repere, 3),
        };
        await service.actualiser(demandeParUtilisateur: true);
        expect(await service.nombreTicketsAvecNouveautes(), 0);

        client.tickets = <String, TicketGithub>{
          a.ticket.repere: _github(
            a.ticket.repere,
            3,
            maj: DateTime.utc(2026, 11, 27, 11),
            commentaires: 1,
          ),
        };
        final resultat = await service.actualiser(demandeParUtilisateur: true);
        expect(resultat.nombreNouveautes, 1);
        expect(await service.nombreTicketsAvecNouveautes(), 1);
      },
    );

    test(
      "l'actualisation automatique est ignorée moins de 5 minutes après",
      () async {
        await service.preparerTicket(
          titre: 'A',
          type: TypeTicket.bug,
          description: '',
        );
        await service.actualiser();
        expect(client.appelsTickets, 1);

        maintenant = maintenant.add(const Duration(minutes: 2));
        final ignoree = await service.actualiser();
        expect(ignoree.ignoree, isTrue);
        expect(client.appelsTickets, 1);

        await service.actualiser(demandeParUtilisateur: true);
        expect(client.appelsTickets, 2);

        maintenant = maintenant.add(const Duration(minutes: 6));
        await service.actualiser();
        expect(client.appelsTickets, 3);
      },
    );

    test(
      'une limite GitHub en cours bloque même la demande utilisateur',
      () async {
        await service.preparerTicket(
          titre: 'A',
          type: TypeTicket.bug,
          description: '',
        );
        final reprise = maintenant.add(const Duration(minutes: 30));
        client.heureReprise = reprise;
        final resultat = await service.actualiser(demandeParUtilisateur: true);
        expect(client.appelsTickets, 0);
        expect(resultat.ignoree, isTrue);
        expect(resultat.heureReprise, reprise);
        expect(resultat.messageErreur, contains('Limite'));
      },
    );

    test('une limite atteinte pendant la requête est rapportée', () async {
      await service.preparerTicket(
        titre: 'A',
        type: TypeTicket.bug,
        description: '',
      );
      final reprise = maintenant.add(const Duration(hours: 1));
      client.erreur = ErreurLimiteGithub(
        'https://api.github.com',
        'limite',
        heureReprise: reprise,
      );
      final resultat = await service.actualiser(demandeParUtilisateur: true);
      expect(resultat.heureReprise, reprise);
      expect(resultat.aEchoue, isTrue);
    });

    test("une erreur réseau n'écrit rien et ne lève pas", () async {
      final a = await service.preparerTicket(
        titre: 'A',
        type: TypeTicket.bug,
        description: '',
      );
      client.erreur = const ErreurSource(
        'https://api.github.com',
        'hors ligne',
      );
      final resultat = await service.actualiser(demandeParUtilisateur: true);
      expect(resultat.messageErreur, contains('hors ligne'));
      expect(
        (await depot.chargerParRepere(a.ticket.repere))!.dateDernierReleve,
        isNull,
      );
    });

    test('deux actualisations simultanées partagent la même requête', () async {
      await service.preparerTicket(
        titre: 'A',
        type: TypeTicket.bug,
        description: '',
      );
      client.attente = Completer<void>();
      final premiere = service.actualiser(demandeParUtilisateur: true);
      final seconde = service.actualiser(demandeParUtilisateur: true);
      expect(identical(premiere, seconde), isTrue);
      client.attente!.complete();
      await Future.wait(<Future<Object?>>[premiere, seconde]);
      expect(client.appelsTickets, 1);
    });
  });

  group('commentaires et retrait', () {
    test('un ticket non retrouvé ne fait aucune requête', () async {
      final a = await service.preparerTicket(
        titre: 'A',
        type: TypeTicket.bug,
        description: '',
      );
      expect(await service.chargerCommentaires(a.ticket), isEmpty);
      expect(client.appelsCommentaires, 0);
    });

    test('charger les commentaires marque le ticket consulté', () async {
      final a = await service.preparerTicket(
        titre: 'A',
        type: TypeTicket.bug,
        description: '',
      );
      client.tickets = <String, TicketGithub>{
        a.ticket.repere: _github(a.ticket.repere, 3, commentaires: 1),
      };
      await service.actualiser(demandeParUtilisateur: true);
      client.tickets = <String, TicketGithub>{
        a.ticket.repere: _github(
          a.ticket.repere,
          3,
          maj: DateTime.utc(2026, 11, 27, 11),
          commentaires: 2,
        ),
      };
      await service.actualiser(demandeParUtilisateur: true);
      expect(await service.nombreTicketsAvecNouveautes(), 1);

      client.commentaires = <CommentaireTicketGithub>[
        CommentaireTicketGithub(
          auteur: 'Zerma1',
          date: DateTime.utc(2026, 11, 27, 11),
          corps: 'Corrigé.',
        ),
      ];
      final ticket = (await depot.chargerParRepere(a.ticket.repere))!;
      final commentaires = await service.chargerCommentaires(ticket);
      expect(commentaires.single.corps, 'Corrigé.');
      expect(await service.nombreTicketsAvecNouveautes(), 0);
    });

    test(
      'une erreur GitHub sur les commentaires devient une ErreurService',
      () async {
        final a = await service.preparerTicket(
          titre: 'A',
          type: TypeTicket.bug,
          description: '',
        );
        client.tickets = <String, TicketGithub>{
          a.ticket.repere: _github(a.ticket.repere, 3, commentaires: 1),
        };
        await service.actualiser(demandeParUtilisateur: true);
        client.erreur = const ErreurSource(
          'https://api.github.com',
          'hors ligne',
        );
        final ticket = (await depot.chargerParRepere(a.ticket.repere))!;
        await expectLater(
          service.chargerCommentaires(ticket),
          throwsA(isA<ErreurService>()),
        );
      },
    );

    test("retirer un ticket le supprime de l'application", () async {
      final a = await service.preparerTicket(
        titre: 'A',
        type: TypeTicket.bug,
        description: '',
      );
      expect(await service.retirerTicket(a.ticket), isTrue);
      expect(await service.chargerTickets(), isEmpty);
      expect(await service.retirerTicket(a.ticket), isFalse);
    });
  });
}
