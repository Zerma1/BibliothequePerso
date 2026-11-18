import 'dart:async';
import 'dart:convert';

import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'outils_tests_sources.dart';

void main() {
  late HorlogeFactice horloge;
  late List<http.Request> requetes;

  setUp(() {
    horloge = HorlogeFactice();
    requetes = <http.Request>[];
  });

  /// Client dont chaque appel renvoie la réponse suivante de [reponses].
  ClientHttpPoli clientAvecReponses(List<http.Response> reponses) {
    var indice = 0;
    return creerClientTest((requete) async {
      requetes.add(requete);
      return reponses[indice++];
    }, horloge);
  }

  group('En-têtes', () {
    test("envoie le User-Agent honnête de l'application par défaut et le "
        'Referer demandé', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('ok', 200),
      ]);
      await client.recupererOctets(
        Uri.parse('https://exemple.org/image.jpg'),
        referer: 'https://exemple.org/chapitre-1',
      );
      expect(requetes.single.headers['user-agent'], userAgentApplication);
      expect(client.userAgentParDefaut, userAgentApplication);
      expect(requetes.single.headers['user-agent'], isNot(contains('Mozilla')));
      expect(
        requetes.single.headers['referer'],
        'https://exemple.org/chapitre-1',
      );
    });

    test(
      'le User-Agent peut être remplacé et le Referer est absent par défaut',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('ok', 200),
        ]);
        await client.recupererTexte(
          Uri.parse('https://exemple.org/'),
          userAgent: 'AutreClient/1.0',
        );
        expect(requetes.single.headers['user-agent'], 'AutreClient/1.0');
        expect(requetes.single.headers.containsKey('referer'), isFalse);
      },
    );
  });

  group('Délai par domaine', () {
    test('deux requêtes vers le même domaine sont espacées d\'1 s', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('a', 200),
        http.Response('b', 200),
      ]);
      await client.recupererTexte(Uri.parse('https://exemple.org/a'));
      await client.recupererTexte(Uri.parse('https://exemple.org/b'));
      expect(horloge.attentes, <Duration>[const Duration(seconds: 1)]);
    });

    test('aucune attente entre deux domaines différents', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('a', 200),
        http.Response('b', 200),
      ]);
      await client.recupererTexte(Uri.parse('https://exemple.org/a'));
      await client.recupererTexte(Uri.parse('https://autre.org/b'));
      expect(horloge.attentes, isEmpty);
    });

    test(
      'aucune attente si la seconde requête arrive après le délai',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('a', 200),
          http.Response('b', 200),
        ]);
        await client.recupererTexte(Uri.parse('https://exemple.org/a'));
        horloge.avancer(const Duration(seconds: 2));
        await client.recupererTexte(Uri.parse('https://exemple.org/b'));
        expect(horloge.attentes, isEmpty);
      },
    );

    test('trois requêtes lancées en même temps obtiennent des créneaux '
        'distincts', () async {
      // Horloge figée : les trois appels partent au même instant, comme en
      // réalité ; seule la réservation des créneaux doit les espacer.
      final instant = DateTime.utc(2026, 11, 15, 12);
      final client = ClientHttpPoli(
        client: MockClient((requete) async => http.Response('ok', 200)),
        maintenant: () => instant,
        attendre: (duree) async => horloge.attentes.add(duree),
      );
      await Future.wait(<Future<String>>[
        client.recupererTexte(Uri.parse('https://exemple.org/1')),
        client.recupererTexte(Uri.parse('https://exemple.org/2')),
        client.recupererTexte(Uri.parse('https://exemple.org/3')),
      ]);
      expect(horloge.attentes, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
    });

    test('une LimiteRequetes plus stricte ajoute son propre délai', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('a', 200),
        http.Response('b', 200),
      ]);
      const limite = LimiteRequetes('cle', Duration(milliseconds: 1500));
      await client.recupererTexte(
        Uri.parse('https://exemple.org/a'),
        limite: limite,
      );
      await client.recupererTexte(
        Uri.parse('https://exemple.org/b'),
        limite: limite,
      );
      // Le créneau retenu est le plus tardif des deux : 1,5 s d'un coup.
      expect(horloge.attentes, <Duration>[const Duration(milliseconds: 1500)]);
    });

    test('limite et domaine mêlés : 1 s par domaine reste garantie entre '
        'trois requêtes simultanées', () async {
      final instant = DateTime.utc(2026, 11, 15, 12);
      final client = ClientHttpPoli(
        client: MockClient((requete) async => http.Response('ok', 200)),
        maintenant: () => instant,
        attendre: (duree) async => horloge.attentes.add(duree),
      );
      const limite = LimiteRequetes('cle', Duration(milliseconds: 1500));
      await Future.wait(<Future<String>>[
        client.recupererTexte(
          Uri.parse('https://exemple.org/a'),
          limite: limite,
        ),
        client.recupererTexte(
          Uri.parse('https://exemple.org/b'),
          limite: limite,
        ),
        client.recupererTexte(Uri.parse('https://exemple.org/c')),
      ]);
      // Départs : A à 0 s ; B à 1,5 s (limite) ; C à 2,5 s, soit 1 s après
      // B (et non 2 s, ce qui ne l'aurait mis qu'à 0,5 s de B).
      expect(horloge.attentes, <Duration>[
        const Duration(milliseconds: 1500),
        const Duration(milliseconds: 2500),
      ]);
    });

    test('un 429 repousse le créneau de tout le domaine', () async {
      final client = ClientHttpPoli(
        client: MockClient((requete) async {
          if (requete.url.path == '/a') {
            return http.Response(
              'trop',
              429,
              headers: <String, String>{'retry-after': '30'},
            );
          }
          return http.Response('ok', 200);
        }),
        maintenant: horloge.lire,
        attendre: horloge.attendre,
        nombreNouvellesTentatives: 0,
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/a')),
        throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 429)),
      );
      expect(horloge.attentes, isEmpty);
      // Une autre requête vers le même domaine attend les 30 s demandées…
      await client.recupererTexte(Uri.parse('https://exemple.org/b'));
      expect(horloge.attentes, <Duration>[const Duration(seconds: 30)]);
      // … mais un autre domaine n'est pas concerné.
      await client.recupererTexte(Uri.parse('https://autre.org/c'));
      expect(horloge.attentes, hasLength(1));
    });
  });

  group('Nouvelles tentatives', () {
    test(
      'une erreur 500 suivie d\'un succès réussit à la 2e tentative',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('panne', 500),
          http.Response('ok', 200),
        ]);
        final texte = await client.recupererTexte(
          Uri.parse('https://exemple.org/'),
        );
        expect(texte, 'ok');
        expect(requetes, hasLength(2));
      },
    );

    test(
      'au plus 2 nouvelles tentatives, puis ErreurSource avec le code',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('panne', 503),
          http.Response('panne', 503),
          http.Response('panne', 503),
          http.Response('jamais', 200),
        ]);
        await expectLater(
          client.recupererTexte(Uri.parse('https://exemple.org/x')),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.codeStatut, 'codeStatut', 503)
                .having((e) => e.url, 'url', 'https://exemple.org/x'),
          ),
        );
        expect(requetes, hasLength(3));
      },
    );

    test(
      'une erreur 404 échoue tout de suite, sans nouvelle tentative',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('absent', 404),
          http.Response('ok', 200),
        ]);
        await expectLater(
          client.recupererTexte(Uri.parse('https://exemple.org/x')),
          throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 404)),
        );
        expect(requetes, hasLength(1));
      },
    );

    test('une erreur 429 respecte Retry-After puis réessaie', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response(
          'trop',
          429,
          headers: <String, String>{'retry-after': '5'},
        ),
        http.Response('ok', 200),
      ]);
      expect(
        await client.recupererTexte(Uri.parse('https://exemple.org/')),
        'ok',
      );
      expect(requetes, hasLength(2));
      expect(horloge.attentes.first, const Duration(seconds: 5));
    });

    test(
      'une erreur 429 respecte X-RateLimit-Retry-After (horodatage UNIX)',
      () async {
        final fin = horloge.maintenant.add(const Duration(seconds: 7));
        final client = clientAvecReponses(<http.Response>[
          http.Response(
            'trop',
            429,
            headers: <String, String>{
              'x-ratelimit-retry-after':
                  '${fin.millisecondsSinceEpoch ~/ 1000}',
            },
          ),
          http.Response('ok', 200),
        ]);
        expect(
          await client.recupererTexte(Uri.parse('https://exemple.org/')),
          'ok',
        );
        expect(horloge.attentes.first, const Duration(seconds: 7));
      },
    );

    test('une erreur 429 qui demande une attente déraisonnable échoue tout '
        'de suite', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response(
          'trop',
          429,
          headers: <String, String>{'retry-after': '3600'},
        ),
      ]);
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/')),
        throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 429)),
      );
      expect(requetes, hasLength(1));
    });

    test(
      'une erreur 429 répétée finit en ErreurSource après 3 essais',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('trop', 429),
          http.Response('trop', 429),
          http.Response('trop', 429),
        ]);
        await expectLater(
          client.recupererTexte(Uri.parse('https://exemple.org/')),
          throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 429)),
        );
        expect(requetes, hasLength(3));
      },
    );

    test('une erreur réseau est réessayée puis levée en ErreurSource avec '
        'sa cause', () async {
      var appels = 0;
      final client = creerClientTest((requete) async {
        appels++;
        throw http.ClientException('connexion refusée', requete.url);
      }, horloge);
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/')),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.cause,
            'cause',
            isA<http.ClientException>(),
          ),
        ),
      );
      expect(appels, 3);
    });

    test('un délai dépassé est levé en ErreurSource', () async {
      var appels = 0;
      final client = creerClientTest(
        (requete) {
          appels++;
          // Réponse qui n'arrive jamais : seul le délai d'expiration y met fin.
          return Completer<http.Response>().future;
        },
        horloge,
        delaiExpiration: const Duration(milliseconds: 20),
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/')),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.cause,
            'cause',
            isA<TimeoutException>(),
          ),
        ),
      );
      expect(appels, 3);
    });
  });

  group('Validation et décodage', () {
    test('une URL non http(s) lève une ErreurSource sans requête', () async {
      final client = clientAvecReponses(<http.Response>[]);
      await expectLater(
        client.recupererTexte(Uri.parse('ftp://exemple.org/')),
        throwsA(isA<ErreurSource>()),
      );
      await expectLater(
        client.recupererTexte(Uri.parse('/relative')),
        throwsA(isA<ErreurSource>()),
      );
      expect(requetes, isEmpty);
    });

    test('un texte sans charset déclaré est décodé en UTF-8', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response.bytes(
          utf8.encode('Résumé — 死神'),
          200,
          headers: <String, String>{'content-type': 'text/html'},
        ),
      ]);
      expect(
        await client.recupererTexte(Uri.parse('https://exemple.org/')),
        'Résumé — 死神',
      );
    });

    test('le charset déclaré est respecté (latin-1)', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response.bytes(
          latin1.encode('Résumé'),
          200,
          headers: <String, String>{
            'content-type': 'text/html; charset=ISO-8859-1',
          },
        ),
      ]);
      expect(
        await client.recupererTexte(Uri.parse('https://exemple.org/')),
        'Résumé',
      );
    });

    test('windows-1252 (inconnu de dart:convert) est lu en latin-1', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response.bytes(
          // Octets hors 0x80-0x9F : identiques en windows-1252 et latin-1.
          latin1.encode('Résumé à lire'),
          200,
          headers: <String, String>{
            'content-type': 'text/html; charset=windows-1252',
          },
        ),
      ]);
      expect(
        await client.recupererTexte(Uri.parse('https://exemple.org/')),
        'Résumé à lire',
      );
    });

    test('recupererOctets renvoie le corps brut', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response.bytes(<int>[1, 2, 3, 255], 200),
      ]);
      expect(
        await client.recupererOctets(Uri.parse('https://exemple.org/i.png')),
        <int>[1, 2, 3, 255],
      );
    });

    test('une erreur 403 (baseUrl MangaDex expirée) expose le code 403, sans '
        'nouvelle tentative', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('interdit', 403),
        http.Response('jamais', 200),
      ]);
      await expectLater(
        client.recupererOctetsAvecDetails(
          Uri.parse('https://noeud.mangadex.network/jeton/data/h/1.png'),
        ),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.codeStatut, 'code', 403)
              .having((e) => e.octetsRecus, 'octets', 8)
              .having((e) => e.duree, 'durée', isNotNull),
        ),
      );
      expect(requetes, hasLength(1));
    });

    test('le client injecté est bien celui qui est appelé', () async {
      var appele = false;
      final client = ClientHttpPoli(
        client: MockClient((requete) async {
          appele = true;
          return http.Response('ok', 200);
        }),
        attendre: horloge.attendre,
        maintenant: horloge.lire,
      );
      await client.recupererTexte(Uri.parse('https://exemple.org/'));
      expect(appele, isTrue);
    });
  });

  group('recupererOctetsAvecDetails', () {
    test('renvoie octets, en-têtes (minuscules), durée et code', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response.bytes(
          <int>[9, 8, 7],
          200,
          headers: <String, String>{'X-Cache': 'HIT', 'content-type': 'x/y'},
        ),
      ]);
      final reponse = await client.recupererOctetsAvecDetails(
        Uri.parse('https://exemple.org/i.png'),
        referer: 'https://exemple.org/',
      );
      expect(reponse.octets, <int>[9, 8, 7]);
      expect(reponse.enTetes['x-cache'], 'HIT');
      expect(reponse.enTetes['content-type'], 'x/y');
      expect(reponse.codeStatut, 200);
      expect(reponse.duree.isNegative, isFalse);
      expect(requetes.single.method, 'GET');
      expect(requetes.single.headers['referer'], 'https://exemple.org/');
    });

    test(
      'nouvellesTentatives: 0 n\'insiste pas après une erreur 500',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('panne', 500),
          http.Response('ok', 200),
        ]);
        await expectLater(
          client.recupererOctetsAvecDetails(
            Uri.parse('https://exemple.org/i.png'),
            nouvellesTentatives: 0,
          ),
          throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 500)),
        );
        expect(requetes, hasLength(1));
      },
    );

    test('nouvellesTentatives est plafonné à la règle du client', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('panne', 500),
        http.Response('panne', 500),
        http.Response('panne', 500),
        http.Response('jamais', 200),
      ]);
      await expectLater(
        client.recupererOctetsAvecDetails(
          Uri.parse('https://exemple.org/i.png'),
          nouvellesTentatives: 10,
        ),
        throwsA(isA<ErreurSource>()),
      );
      expect(requetes, hasLength(3));
    });

    group('exigerImage (E10)', () {
      // Début d'un vrai JPEG (marqueurs SOI + APP0 « JFIF »).
      const debutJpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];

      test('page anti-robot HTML reçue après redirection : ErreurSource '
          'sans nouvelle tentative', () async {
        // `package:http` (IOClient) suit la redirection 302 vers
        // /edge/challenge et rend la page finale en 200 ; MockClient ne suit
        // pas les redirections : on simule donc directement cette réponse
        // finale, telle qu'observée le 2026-11-16 (text/html, <!doctype html>).
        final client = clientAvecReponses(<http.Response>[
          http.Response(
            '<!doctype html><html><head><title>Challenge</title></head>'
            '<body>Vérification</body></html>',
            200,
            headers: <String, String>{
              'Content-Type': 'text/html; charset=utf-8',
            },
          ),
          http.Response.bytes(
            debutJpeg,
            200,
            headers: <String, String>{'content-type': 'image/jpeg'},
          ),
        ]);
        const url = 'https://uploads.mangadex.org/covers/id/fichier.jpg';
        await expectLater(
          client.recupererOctets(Uri.parse(url), exigerImage: true),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.url, 'url', url)
                .having((e) => e.message, 'message', contains('text/html'))
                .having((e) => e.codeStatut, 'code', 200)
                .having((e) => e.octetsRecus, 'octets', greaterThan(0))
                .having(
                  (e) => e.extraitReponse,
                  'extrait',
                  contains('<!doctype html>'),
                ),
          ),
        );
        expect(requetes, hasLength(1));
      });

      test('JPEG : octets renvoyés', () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response.bytes(
            debutJpeg,
            200,
            headers: <String, String>{'Content-Type': 'Image/JPEG'},
          ),
        ]);
        final octets = await client.recupererOctets(
          Uri.parse('https://uploads.mangadex.org/covers/id/fichier.jpg'),
          exigerImage: true,
        );
        expect(octets, debutJpeg);
      });

      test('Content-Type absent et contenu texte : ErreurSource', () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response.bytes(utf8.encode('Fichier introuvable'), 200),
        ]);
        await expectLater(
          client.recupererOctetsAvecDetails(
            Uri.parse('https://exemple.org/i.jpg'),
            exigerImage: true,
          ),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('absent'),
                contains('contenu : texte'),
                contains('Fichier introuvable'),
              ),
            ),
          ),
        );
      });

      test(
        'WEBP servi sans Content-Type (Ruri Dragon ch. 47) : accepté',
        () async {
          // En-tête d'un vrai WEBP sans perte : « RIFF », taille, « WEBPVP8L ».
          final webp = <int>[
            ...ascii.encode('RIFF'),
            0x24,
            0x10,
            0x00,
            0x00,
            ...ascii.encode('WEBPVP8L'),
            0x18,
            0x10,
            0x00,
            0x00,
            0x2F,
            0xFF,
            0xC3,
            0x8B,
          ];
          final client = clientAvecReponses(<http.Response>[
            http.Response.bytes(webp, 200),
          ]);
          final reponse = await client.recupererOctetsAvecDetails(
            Uri.parse('https://exemple.org/ch-47/01.jpg'),
            exigerImage: true,
          );
          expect(reponse.octets, webp);
        },
      );

      test('Content-Type générique ou faux : les octets décident', () async {
        const png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0];
        final client = clientAvecReponses(<http.Response>[
          http.Response.bytes(
            png,
            200,
            headers: <String, String>{
              'content-type': 'application/octet-stream',
            },
          ),
          http.Response.bytes(
            debutJpeg,
            200,
            headers: <String, String>{'content-type': 'text/html'},
          ),
        ]);
        expect(
          await client.recupererOctets(
            Uri.parse('https://exemple.org/a.png'),
            exigerImage: true,
          ),
          png,
        );
        expect(
          await client.recupererOctets(
            Uri.parse('https://exemple.org/b.jpg'),
            exigerImage: true,
          ),
          debutJpeg,
        );
      });

      test('page HTML annoncée image/jpeg : refusée (E10)', () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response(
            '  <!DOCTYPE html><html><body>Accès refusé</body></html>',
            200,
            headers: <String, String>{'content-type': 'image/jpeg'},
          ),
        ]);
        await expectLater(
          client.recupererOctets(
            Uri.parse('https://exemple.org/i.jpg'),
            exigerImage: true,
          ),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.message,
              'message',
              allOf(contains('image/jpeg'), contains('page HTML')),
            ),
          ),
        );
      });

      test('format sans signature connue annoncé image/* : accepté', () async {
        final svg = utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>');
        final client = clientAvecReponses(<http.Response>[
          http.Response.bytes(
            svg,
            200,
            headers: <String, String>{'content-type': 'image/svg+xml'},
          ),
        ]);
        expect(
          await client.recupererOctets(
            Uri.parse('https://exemple.org/i.svg'),
            exigerImage: true,
          ),
          svg,
        );
      });

      test('binaire non reconnu : message sans aucun octet binaire', () async {
        final binaire = <int>[
          for (var i = 0; i < 300; i++) (i * 37 + 11) % 256,
        ];
        final client = clientAvecReponses(<http.Response>[
          http.Response.bytes(binaire, 200),
        ]);
        await expectLater(
          client.recupererOctets(
            Uri.parse('https://exemple.org/i.bin'),
            exigerImage: true,
          ),
          throwsA(
            isA<ErreurSource>()
                .having(
                  (e) => e.message,
                  'message',
                  "Réponse qui n'est pas une image (Content-Type : absent ; "
                      'contenu : données binaires non reconnues)',
                )
                .having((e) => e.extraitReponse, 'extrait', isNull)
                .having((e) => e.octetsRecus, 'octets', 300),
          ),
        );
      });

      test('extrait du message limité à 80 caractères imprimables', () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response.bytes(
            utf8.encode('Erreur\u0007 ${'x' * 200}'),
            200,
            headers: <String, String>{'content-type': 'text/plain'},
          ),
        ]);
        await expectLater(
          client.recupererOctets(
            Uri.parse('https://exemple.org/i.jpg'),
            exigerImage: true,
          ),
          throwsA(
            isA<ErreurSource>().having(
              (e) {
                final extrait = e.message.split(') : ').last;
                return extrait.length <= 81 &&
                    extrait.runes.every((c) => c >= 0x20 && c != 0x7F);
              },
              'extrait court et imprimable',
              isTrue,
            ),
          ),
        );
      });

      test('sans exigerImage : comportement inchangé (HTML accepté)', () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response(
            '<!doctype html>',
            200,
            headers: <String, String>{'content-type': 'text/html'},
          ),
        ]);
        final octets = await client.recupererOctets(
          Uri.parse('https://exemple.org/i.jpg'),
        );
        expect(utf8.decode(octets), '<!doctype html>');
      });
    });

    test('erreur HTTP au corps binaire : message sans octet binaire', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response.bytes(<int>[0, 1, 2, 0xFF, 0xFE, 0x80], 404),
      ]);
      await expectLater(
        client.recupererOctets(Uri.parse('https://exemple.org/i.png')),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.message, 'message', 'Réponse HTTP 404')
              .having((e) => e.extraitReponse, 'extrait', isNull),
        ),
      );
    });

    test('une erreur réseau donne 0 octet reçu', () async {
      final client = creerClientTest((requete) async {
        throw http.ClientException('coupure', requete.url);
      }, horloge);
      await expectLater(
        client.recupererOctetsAvecDetails(
          Uri.parse('https://exemple.org/i.png'),
          nouvellesTentatives: 0,
        ),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.octetsRecus, 'octets', 0)
              .having((e) => e.duree, 'durée', isNotNull),
        ),
      );
    });
  });

  group('envoyerJson', () {
    test(
      'envoie un POST JSON avec Content-Type exactement application/json',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('{"ok":true}', 200),
        ]);
        final texte = await client.envoyerJson(
          Uri.parse('https://exemple.org/report'),
          <String, Object>{'url': 'https://a/b', 'success': true, 'bytes': 3},
          userAgent: userAgentApplication,
          // Une tentative d'écrasement du Content-Type est ignorée.
          enTetes: const <String, String>{'Content-Type': 'text/plain'},
        );
        expect(texte, '{"ok":true}');
        final requete = requetes.single;
        expect(requete.method, 'POST');
        expect(requete.headers['content-type'], 'application/json');
        expect(requete.headers['user-agent'], userAgentApplication);
        expect(requete.headers.containsKey('referer'), isFalse);
        expect(jsonDecode(requete.body), <String, Object>{
          'url': 'https://a/b',
          'success': true,
          'bytes': 3,
        });
      },
    );

    test(
      'aucune nouvelle tentative par défaut (POST non idempotent)',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response('panne', 503),
          http.Response('ok', 200),
        ]);
        await expectLater(
          client.envoyerJson(Uri.parse('https://exemple.org/report'), 1),
          throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 503)),
        );
        expect(requetes, hasLength(1));
      },
    );

    test('un délai dépassé n\'est pas renvoyé par défaut', () async {
      var appels = 0;
      final client = creerClientTest(
        (requete) {
          appels++;
          return Completer<http.Response>().future;
        },
        horloge,
        delaiExpiration: const Duration(milliseconds: 20),
      );
      await expectLater(
        client.envoyerJson(Uri.parse('https://exemple.org/report'), 1),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.cause,
            'cause',
            isA<TimeoutException>(),
          ),
        ),
      );
      expect(appels, 1);
    });

    test('nouvelles tentatives possibles si l\'appelant les demande', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('panne', 503),
        http.Response('ok', 200),
      ]);
      expect(
        await client.envoyerJson(
          Uri.parse('https://exemple.org/report'),
          1,
          nouvellesTentatives: 1,
        ),
        'ok',
      );
      expect(requetes, hasLength(2));
    });

    test('respecte le délai par domaine partagé avec les GET', () async {
      final client = clientAvecReponses(<http.Response>[
        http.Response('a', 200),
        http.Response('b', 200),
      ]);
      await client.recupererTexte(Uri.parse('https://exemple.org/a'));
      await client.envoyerJson(Uri.parse('https://exemple.org/report'), 1);
      expect(horloge.attentes, <Duration>[const Duration(seconds: 1)]);
    });

    test(
      'un 429 repousse le créneau du domaine sans renvoyer le POST',
      () async {
        final client = clientAvecReponses(<http.Response>[
          http.Response(
            'trop',
            429,
            headers: <String, String>{'retry-after': '10'},
          ),
          http.Response('ok', 200),
        ]);
        await expectLater(
          client.envoyerJson(Uri.parse('https://exemple.org/report'), 1),
          throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 429)),
        );
        expect(requetes, hasLength(1));
        await client.recupererTexte(Uri.parse('https://exemple.org/x'));
        expect(horloge.attentes, <Duration>[const Duration(seconds: 10)]);
      },
    );

    test(
      'un corps impossible à encoder lève une ErreurSource sans requête',
      () async {
        final client = clientAvecReponses(<http.Response>[]);
        await expectLater(
          client.envoyerJson(Uri.parse('https://exemple.org/report'), Object()),
          throwsA(isA<ErreurSource>()),
        );
        expect(requetes, isEmpty);
      },
    );

    test('une URL invalide lève une ErreurSource sans requête', () async {
      final client = clientAvecReponses(<http.Response>[]);
      await expectLater(
        client.envoyerJson(Uri.parse('ftp://exemple.org/'), 1),
        throwsA(isA<ErreurSource>()),
      );
      expect(requetes, isEmpty);
    });
  });
}
