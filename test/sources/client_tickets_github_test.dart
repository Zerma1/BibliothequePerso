// Tests de ClientTicketsGithub : réponses JSON enregistrées
// (test/sources/exemples_json/github_*.json), aucun appel réseau réel.

import 'package:bibliotheque_perso/sources/client_tickets_github.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

const String _lienPage2 =
    'https://api.github.com/repositories/123/issues?state=all&sort=updated'
    '&direction=desc&per_page=100&page=2';

http.Response _reponse(
  String corps, {
  int statut = 200,
  Map<String, String> enTetes = const <String, String>{},
}) {
  final base = reponseJson(corps, statut: statut);
  return http.Response.bytes(
    base.bodyBytes,
    statut,
    headers: <String, String>{...base.headers, ...enTetes},
  );
}

void main() {
  late HorlogeFactice horloge;
  late List<http.Request> requetes;

  setUp(() {
    horloge = HorlogeFactice();
    requetes = <http.Request>[];
  });

  ClientTicketsGithub creer(
    Future<http.Response> Function(http.Request requete) gestionnaire,
  ) {
    return ClientTicketsGithub(
      creerClientTest((requete) {
        requetes.add(requete);
        return gestionnaire(requete);
      }, horloge),
      maintenant: horloge.lire,
    );
  }

  Future<http.Response> deuxPages(http.Request requete) async {
    if (requete.url.queryParameters['page'] == '2') {
      return _reponse(lireExemple('exemples_json/github_tickets_page2.json'));
    }
    return _reponse(
      lireExemple('exemples_json/github_tickets_page1.json'),
      enTetes: <String, String>{
        'link': '<$_lienPage2>; rel="next", <$_lienPage2>; rel="last"',
        'x-ratelimit-remaining': '58',
      },
    );
  }

  group('extraireReperesTicket', () {
    test('normalise et ignore les faux repères', () {
      expect(
        extraireReperesTicket(
          'BP-0123456789AB, XBP-ffffffffffff, BP-fffffffffffff0, '
          'bp-aaaaaaaaaaaa, (BP-a1b2c3d4e5f6) BP-0123456789ab',
        ),
        <String>['BP-0123456789ab', 'BP-a1b2c3d4e5f6'],
      );
    });
  });

  group('recupererTicketsParRepere', () {
    test('lit la liste, ignore les pull requests, suit Link', () async {
      final client = creer(deuxPages);
      final tickets = await client.recupererTicketsParRepere(<String>{
        'BP-0123456789ab',
        'BP-A1B2C3D4E5F6',
        'BP-000000000000',
      });

      expect(requetes, hasLength(2));
      final premiere = requetes.first;
      expect(premiere.url.host, hoteApiGithub);
      expect(premiere.url.path, '/repos/Zerma1/BibliothequePerso/issues');
      expect(premiere.url.queryParameters, <String, String>{
        'state': 'all',
        'sort': 'updated',
        'direction': 'desc',
        'per_page': '100',
      });
      expect(premiere.headers['Accept'], 'application/vnd.github+json');
      expect(premiere.headers['X-GitHub-Api-Version'], versionApiGithub);
      expect(premiere.headers['User-Agent'], userAgentApplication);
      expect(requetes[1].url.toString(), _lienPage2);
      // 1 s entre deux requêtes vers api.github.com.
      expect(horloge.attentes, contains(const Duration(seconds: 1)));

      expect(
        tickets.keys,
        unorderedEquals(<String>['BP-0123456789ab', 'BP-a1b2c3d4e5f6']),
      );
      final ticket = tickets['BP-0123456789ab']!;
      // Le n° 7 (pull request) cite aussi le repère : il est ignoré.
      expect(ticket.numero, 5);
      expect(ticket.titre, "Plantage à l'ouverture d'un chapitre");
      expect(ticket.etat, EtatTicketGithub.ferme);
      expect(ticket.raisonEtat, 'completed');
      expect(ticket.etiquettes, <String>['bug', 'priorité haute']);
      expect(ticket.nombreCommentaires, 2);
      expect(ticket.dateMiseAJour, DateTime.utc(2026, 11, 25, 18, 45, 12));
      expect(
        ticket.urlPage,
        'https://github.com/Zerma1/BibliothequePerso/issues/5',
      );
      // Deux tickets portent le même repère : le plus ancien est gardé.
      expect(tickets['BP-a1b2c3d4e5f6']!.numero, 1);
      expect(tickets['BP-a1b2c3d4e5f6']!.etat, EtatTicketGithub.ouvert);
      expect(client.requetesRestantes, 58);
    });

    test("s'arrête dès que tous les repères sont trouvés", () async {
      final client = creer(deuxPages);
      final tickets = await client.recupererTicketsParRepere(<String>{
        'BP-0123456789ab',
      });
      expect(requetes, hasLength(1));
      expect(tickets, hasLength(1));
    });

    test('envoie since au format attendu', () async {
      final client = creer(deuxPages);
      await client.recupererTicketsParRepere(<String>{
        'BP-0123456789ab',
      }, depuis: DateTime.utc(2026, 11, 20, 8, 30, 15, 123));
      expect(
        requetes.single.url.queryParameters['since'],
        '2026-11-20T08:30:15Z',
      );
    });

    test('aucun repère valide : aucune requête', () async {
      final client = creer(deuxPages);
      expect(await client.recupererTicketsParRepere(<String>{'abc'}), isEmpty);
      expect(requetes, isEmpty);
    });

    test(
      '403 limite atteinte : erreur dédiée puis plus aucune requête',
      () async {
        final reset = horloge.maintenant.add(const Duration(minutes: 30));
        final client = creer(
          (_) async => _reponse(
            '{"message":"API rate limit exceeded for 1.2.3.4.",'
            '"documentation_url":"https://docs.github.com/rest/overview/rate-limits-for-the-rest-api"}',
            statut: 403,
            enTetes: <String, String>{
              'x-ratelimit-limit': '60',
              'x-ratelimit-remaining': '0',
              'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
            },
          ),
        );
        await expectLater(
          client.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
          throwsA(
            isA<ErreurLimiteGithub>()
                .having((e) => e.heureReprise, 'heureReprise', reset)
                .having((e) => e.codeStatut, 'codeStatut', 403),
          ),
        );
        expect(requetes, hasLength(1));
        expect(client.heureReprise, reset);

        await expectLater(
          client.recupererCommentaires(5),
          throwsA(isA<ErreurLimiteGithub>()),
        );
        expect(requetes, hasLength(1));

        // Après l'heure de reprise, les requêtes repartent.
        horloge.avancer(const Duration(minutes: 31));
        await expectLater(
          client.recupererCommentaires(5),
          throwsA(isA<ErreurLimiteGithub>()),
        );
        expect(requetes, hasLength(2));
      },
    );

    test('429 avec retry-after long : erreur dédiée sans insister', () async {
      final client = creer(
        (_) async => _reponse(
          '{"message":"You have exceeded a secondary rate limit."}',
          statut: 429,
          enTetes: <String, String>{'retry-after': '120'},
        ),
      );
      await expectLater(
        client.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
        throwsA(
          isA<ErreurLimiteGithub>().having(
            (e) => e.heureReprise,
            'heureReprise',
            horloge.maintenant.add(const Duration(seconds: 120)),
          ),
        ),
      );
      expect(requetes, hasLength(1));
    });

    test(
      'quota épuisé sur une réponse réussie : prochaine requête bloquée',
      () async {
        final reset = horloge.maintenant.add(const Duration(minutes: 10));
        final client = creer(
          (_) async => _reponse(
            '[]',
            enTetes: <String, String>{
              'x-ratelimit-remaining': '0',
              'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
            },
          ),
        );
        expect(
          await client.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
          isEmpty,
        );
        await expectLater(
          client.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
          throwsA(isA<ErreurLimiteGithub>()),
        );
        expect(requetes, hasLength(1));
      },
    );

    test('404 : ErreurSource explicite', () async {
      final client = creer(
        (_) async => _reponse('{"message":"Not Found"}', statut: 404),
      );
      await expectLater(
        client.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e, 'type', isNot(isA<ErreurLimiteGithub>()))
              .having((e) => e.codeStatut, 'codeStatut', 404)
              .having((e) => e.message, 'message', contains('Introuvable')),
        ),
      );
    });

    test(
      'réseau absent : ErreurSource après les nouvelles tentatives',
      () async {
        final client = creer(
          (_) async => throw http.ClientException('Connexion refusée'),
        );
        await expectLater(
          client.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.message,
              'message',
              'Erreur réseau',
            ),
          ),
        );
        expect(requetes, hasLength(nombreMaxNouvellesTentatives + 1));
      },
    );

    test('JSON inattendu : ErreurSource', () async {
      final client = creer((_) async => _reponse('{"message":"objet"}'));
      await expectLater(
        client.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
        throwsA(isA<ErreurSource>()),
      );
      final client2 = creer(
        (_) async => _reponse(
          '[{"number":"5","body":"BP-0123456789ab","state":"open"}]',
        ),
      );
      await expectLater(
        client2.recupererTicketsParRepere(<String>{'BP-0123456789ab'}),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('Structure JSON inattendue'),
          ),
        ),
      );
    });
  });

  group('recupererCommentaires', () {
    test('lit auteur, date et corps', () async {
      final client = creer(
        (_) async =>
            _reponse(lireExemple('exemples_json/github_commentaires.json')),
      );
      final commentaires = await client.recupererCommentaires(5);
      expect(
        requetes.single.url.path,
        '/repos/Zerma1/BibliothequePerso/issues/5/comments',
      );
      expect(requetes.single.url.queryParameters['per_page'], '100');
      expect(commentaires, hasLength(2));
      expect(commentaires[0].auteur, 'Zerma1');
      expect(commentaires[0].date, DateTime.utc(2026, 11, 24, 12));
      expect(commentaires[0].corps, contains('**Corrigé**'));
      expect(commentaires[1].auteur, isNull);
    });
  });

  group('construireUrlCreationTicket', () {
    test('encode le titre et le corps, sans labels', () {
      final url = construireUrlCreationTicket(
        titre: "Problème d'affichage & co",
        corps: 'Ligne 1\nRepère : BP-0123456789ab #+?',
      );
      expect(url.scheme, 'https');
      expect(url.host, 'github.com');
      expect(url.path, '/Zerma1/BibliothequePerso/issues/new');
      expect(url.queryParameters, <String, String>{
        'title': "Problème d'affichage & co",
        'body': 'Ligne 1\nRepère : BP-0123456789ab #+?',
      });
      expect(url.toString(), isNot(contains('labels')));
      expect(url.toString(), contains('%26'));
    });

    test('tronque le corps trop long en gardant le repère', () {
      final corps = 'Repère : BP-0123456789ab\n${'é😀 mot ' * 3000}';
      final url = construireUrlCreationTicket(titre: 'Titre', corps: corps);
      expect(
        url.toString().length,
        lessThanOrEqualTo(longueurMaxUrlCreationTicket),
      );
      final corpsRecu = url.queryParameters['body']!;
      expect(corpsRecu, contains(mentionCorpsTicketTronque));
      expect(extraireReperesTicket(corpsRecu), <String>['BP-0123456789ab']);
      expect(corpsRecu.length, greaterThan(500));
      // Aucun caractère coupé en deux (pas de demi-paire UTF-16).
      expect(corpsRecu.contains('�'), isFalse);
    });

    test('recopie à la fin un repère placé après la coupure', () {
      final corps = '${'texte ' * 3000}\nRepère : BP-a1b2c3d4e5f6';
      final url = construireUrlCreationTicket(titre: 'Titre', corps: corps);
      final corpsRecu = url.queryParameters['body']!;
      expect(
        url.toString().length,
        lessThanOrEqualTo(longueurMaxUrlCreationTicket),
      );
      expect(corpsRecu.endsWith('BP-a1b2c3d4e5f6'), isTrue);
    });

    test('raccourcit aussi un titre démesuré', () {
      final url = construireUrlCreationTicket(
        titre: 'T' * 9000,
        corps: 'BP-0123456789ab',
      );
      expect(
        url.toString().length,
        lessThanOrEqualTo(longueurMaxUrlCreationTicket),
      );
      expect(url.queryParameters['title']!.endsWith('…'), isTrue);
      expect(extraireReperesTicket(url.queryParameters['body']!), <String>[
        'BP-0123456789ab',
      ]);
    });
  });
}
