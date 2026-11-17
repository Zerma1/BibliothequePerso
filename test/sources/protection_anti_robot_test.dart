import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/protection_anti_robot.dart';
import 'package:bibliotheque_perso/sources/rapport_erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

void main() {
  final pageDefi = lireExemple('exemples_html/defi_anti_robot.html');
  final pageScanManga = lireExemple(
    'exemples_html/scan_manga_titre_potion.html',
  );

  group('estReponseDefiAntiRobot', () {
    test('403 avec « Just a moment » : défi', () {
      expect(
        estReponseDefiAntiRobot(
          codeStatut: 403,
          enTetes: const <String, String>{},
          corps: pageDefi,
        ),
        isTrue,
      );
    });

    test('503 et 429 avec un marqueur : défi', () {
      for (final code in <int>[503, 429]) {
        expect(
          estReponseDefiAntiRobot(
            codeStatut: code,
            enTetes: const <String, String>{},
            corps: '<script src="/cdn-cgi/challenge-platform/x"></script>',
          ),
          isTrue,
        );
      }
    });

    test('en-tête cf-mitigated: challenge suffit (casse ignorée)', () {
      expect(
        estReponseDefiAntiRobot(
          codeStatut: 403,
          enTetes: const <String, String>{'CF-Mitigated': 'challenge'},
          corps: '',
        ),
        isTrue,
      );
    });

    test('404 avec marqueur, ou 403 sans marqueur : pas un défi', () {
      expect(
        estReponseDefiAntiRobot(
          codeStatut: 404,
          enTetes: const <String, String>{},
          corps: pageDefi,
        ),
        isFalse,
      );
      expect(
        estReponseDefiAntiRobot(
          codeStatut: 403,
          enTetes: const <String, String>{},
          corps: '<html><title>Forbidden</title></html>',
        ),
        isFalse,
      );
    });
  });

  group('estPageDefiAntiRobot (réponse 200)', () {
    test('page de défi reconnue', () {
      expect(estPageDefiAntiRobot(pageDefi), isTrue);
    });

    test(
      'page ordinaire contenant le script challenge-platform : pas un défi',
      () {
        // Scan-Manga injecte ce script dans ses pages normales.
        expect(pageScanManga.contains('challenge-platform'), isTrue);
        expect(estPageDefiAntiRobot(pageScanManga), isFalse);
      },
    );
  });

  group('ClientHttpPoli', () {
    test(
      '403 « Just a moment » : erreur dédiée, sans nouvelle tentative',
      () async {
        var appels = 0;
        final client = creerClientTest((requete) async {
          appels++;
          return http.Response(pageDefi, 403);
        }, HorlogeFactice());
        final uri = Uri.parse(
          'https://www.scan-manga.com/6678/Potion-danomi-de-Ikinobimasu.html',
        );
        await expectLater(
          client.recupererTexte(uri),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.protectionAntiRobot, 'protection', isTrue)
                .having((e) => e.codeStatut, 'code', 403)
                .having(
                  (e) => e.message,
                  'message',
                  'Le site www.scan-manga.com a activé une protection '
                      'anti-robot : impossible de le lire automatiquement',
                )
                .having((e) => e.extraitReponse, 'extrait', isNotNull),
          ),
        );
        expect(appels, 1);
      },
    );

    test('503 de défi : aucune nouvelle tentative non plus', () async {
      var appels = 0;
      final client = creerClientTest((requete) async {
        appels++;
        return http.Response(pageDefi, 503);
      }, HorlogeFactice());
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/')),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.protectionAntiRobot,
            'protection',
            isTrue,
          ),
        ),
      );
      expect(appels, 1);
    });

    test('défi servi en 200 : erreur dédiée aussi', () async {
      final client = creerClientTest(
        (requete) async => http.Response(pageDefi, 200),
        HorlogeFactice(),
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/')),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.protectionAntiRobot,
            'protection',
            isTrue,
          ),
        ),
      );
    });

    test(
      'une erreur 403 ordinaire garde protectionAntiRobot à false',
      () async {
        final client = creerClientTest(
          (requete) async => http.Response('Interdit', 403),
          HorlogeFactice(),
        );
        await expectLater(
          client.recupererTexte(Uri.parse('https://exemple.org/')),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.protectionAntiRobot,
              'protection',
              isFalse,
            ),
          ),
        );
      },
    );
  });

  test('avecContexte garde la marque et le rapport la mentionne', () {
    final erreur = erreurProtectionAntiRobot(
      Uri.parse('https://exemple.org/titre'),
      codeStatut: 403,
    ).avecContexte(extraitReponse: 'Just a moment...');
    expect(erreur.protectionAntiRobot, isTrue);
    final texte = RapportErreurSource(erreur).versTexte();
    expect(texte, contains('Protection anti-robot : oui'));
    expect(texte, contains('Le site exemple.org a activé une protection'));
  });
}
