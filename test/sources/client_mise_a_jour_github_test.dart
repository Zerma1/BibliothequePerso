// Tests de ClientMiseAJourGithub, de comparerVersions et du calcul SHA-256 :
// réponses enregistrées (test/sources/exemples_json/github_release_latest.json)
// et flux simulés, aucun appel réseau réel.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:bibliotheque_perso/sources/client_mise_a_jour_github.dart';
import 'package:bibliotheque_perso/sources/empreinte_sha256.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/limite_github.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'outils_tests_sources.dart';

const String _urlExe =
    'https://github.com/Zerma1/BibliothequePerso/releases/download/v0.4.0/'
    'bibliotheque_perso-0.4.0-installation.exe';

Map<String, Object?> _release() =>
    jsonDecode(lireExemple('exemples_json/github_release_latest.json'))
        as Map<String, Object?>;

void main() {
  late HorlogeFactice horloge;
  late List<http.BaseRequest> requetes;
  late Directory dossier;

  setUp(() async {
    horloge = HorlogeFactice();
    requetes = <http.BaseRequest>[];
    dossier = await Directory.systemTemp.createTemp('maj_test_');
  });

  tearDown(() async {
    if (await dossier.exists()) {
      await dossier.delete(recursive: true);
    }
  });

  ClientMiseAJourGithub creer(
    Future<http.Response> Function(http.Request requete) gestionnaire,
  ) {
    return ClientMiseAJourGithub(
      creerClientTest((requete) {
        requetes.add(requete);
        return gestionnaire(requete);
      }, horloge),
      limite: SuiviLimiteGithub(maintenant: horloge.lire),
    );
  }

  /// Client dont les réponses arrivent en plusieurs morceaux (flux).
  ClientMiseAJourGithub creerEnFlux(
    List<List<int>> morceaux, {
    int? tailleAnnoncee,
    int statut = 200,
  }) {
    return ClientMiseAJourGithub(
      ClientHttpPoli(
        client: MockClient.streaming((requete, _) async {
          requetes.add(requete);
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(morceaux),
            statut,
            contentLength: tailleAnnoncee,
          );
        }),
        maintenant: horloge.lire,
        attendre: horloge.attendre,
      ),
    );
  }

  group('comparerVersions', () {
    test('compare numériquement X.Y.Z', () {
      expect(comparerVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(comparerVersions('0.4.0', '0.4.0'), 0);
      expect(comparerVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(comparerVersions('0.3.3', '0.3.10'), lessThan(0));
    });

    test("refuse ce qui n'est pas X.Y.Z", () {
      for (final mauvaise in <String>[
        'v0.4.0',
        '0.4',
        '0.4.0-test',
        '0.4.0+12',
        '0.4.0.1',
        '',
        '0.a.0',
      ]) {
        expect(
          () => comparerVersions(mauvaise, '0.4.0'),
          throwsFormatException,
          reason: mauvaise,
        );
      }
    });
  });

  group('CalculEmpreinteSha256', () {
    test('vecteurs officiels (NIST)', () {
      expect(
        calculerSha256(<int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        calculerSha256(ascii.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        calculerSha256(
          ascii.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('un million de « a » par morceaux irréguliers', () {
      final calcul = CalculEmpreinteSha256();
      var restant = 1000000;
      var taille = 1;
      while (restant > 0) {
        final n = taille < restant ? taille : restant;
        calcul.ajouter(List<int>.filled(n, 0x61));
        restant -= n;
        taille = taille * 3 % 997 + 1;
      }
      expect(
        calcul.terminer(),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });

  group('recupererDerniereVersion', () {
    test('lit la release et ses deux fichiers', () async {
      final client = creer(
        (_) async => reponseJson(
          lireExemple('exemples_json/github_release_latest.json'),
        ),
      );
      final release = await client.recupererDerniereVersion();
      expect(release, isNotNull);
      expect(release!.etiquette, 'v0.4.0');
      expect(release.version, const VersionApplication(0, 4, 0));
      expect(release.nom, 'Version 0.4.0');
      expect(release.notes, contains('Mise à jour automatique'));
      expect(release.datePublication, DateTime.utc(2026, 12, 1, 10, 5, 39));
      expect(
        release.urlPage,
        'https://github.com/Zerma1/BibliothequePerso/releases/tag/v0.4.0',
      );
      expect(release.installateur!.url.toString(), _urlExe);
      expect(release.installateur!.taille, 31457280);
      expect(release.fichierEmpreinte!.url.toString(), '$_urlExe.sha256');
      expect(release.estTelechargeable, isTrue);
      // Point d'accès et en-têtes de l'API.
      expect(
        requetes.single.url.toString(),
        'https://api.github.com/repos/Zerma1/BibliothequePerso/releases/latest',
      );
      expect(requetes.single.headers['Accept'], 'application/vnd.github+json');
    });

    test('release ancienne sans installateur : valide, sans fichier', () async {
      final json = _release()..['assets'] = <Object?>[];
      final client = creer((_) async => reponseJson(jsonEncode(json)));
      final release = await client.recupererDerniereVersion();
      expect(release!.version, const VersionApplication(0, 4, 0));
      expect(release.installateur, isNull);
      expect(release.fichierEmpreinte, isNull);
      expect(release.estTelechargeable, isFalse);
    });

    test("fichier en cours d'envoi (state open) : ignoré", () async {
      final json = _release();
      ((json['assets']! as List<Object?>).first!
              as Map<String, Object?>)['state'] =
          'open';
      final client = creer((_) async => reponseJson(jsonEncode(json)));
      final release = await client.recupererDerniereVersion();
      expect(release!.installateur, isNull);
      expect(release.estTelechargeable, isFalse);
    });

    test('404 (aucune release) : null', () async {
      final client = creer(
        (_) async => reponseJson('{"message":"Not Found"}', statut: 404),
      );
      expect(await client.recupererDerniereVersion(), isNull);
    });

    test('étiquette autre que vX.Y.Z : ErreurSource', () async {
      for (final etiquette in <String>['v0.4.0-test', '0.4.0', 'v0.4']) {
        final json = _release()..['tag_name'] = etiquette;
        final client = creer((_) async => reponseJson(jsonEncode(json)));
        await expectLater(
          client.recupererDerniereVersion(),
          throwsA(isA<ErreurSource>()),
          reason: etiquette,
        );
      }
    });

    test('adresse de fichier hors du dépôt : ErreurSource', () async {
      final json = _release();
      ((json['assets']! as List<Object?>).first!
              as Map<String, Object?>)['browser_download_url'] =
          'https://exemple.invalid/bibliotheque_perso-0.4.0-installation.exe';
      final client = creer((_) async => reponseJson(jsonEncode(json)));
      await expectLater(
        client.recupererDerniereVersion(),
        throwsA(isA<ErreurSource>()),
      );
    });

    test('limite atteinte : ErreurLimiteGithub, plus aucune requête', () async {
      final reset =
          horloge.maintenant
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch ~/
          1000;
      final client = creer(
        (_) async => http.Response(
          '{"message":"API rate limit exceeded"}',
          403,
          headers: <String, String>{
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '$reset',
          },
        ),
      );
      await expectLater(
        client.recupererDerniereVersion(),
        throwsA(isA<ErreurLimiteGithub>()),
      );
      await expectLater(
        client.recupererDerniereVersion(),
        throwsA(isA<ErreurLimiteGithub>()),
      );
      expect(requetes, hasLength(1));
    });
  });

  group('recupererEmpreinteAttendue', () {
    const empreinte =
        '574f2a4ac49af7d2700d5a80f40da2b6768b16618f57f1d5c0024321e3421372';
    final url = Uri.parse('$_urlExe.sha256');

    test('format sha256sum (deux espaces, LF)', () async {
      final client = creer(
        (_) async => http.Response(
          '$empreinte  bibliotheque_perso-0.4.0-installation.exe\n',
          200,
        ),
      );
      expect(await client.recupererEmpreinteAttendue(url), empreinte);
    });

    test('majuscules et CRLF tolérés, rendue en minuscules', () async {
      final client = creer(
        (_) async => http.Response(
          '${empreinte.toUpperCase()} *bibliotheque_perso-0.4.0-installation.exe\r\n',
          200,
        ),
      );
      expect(await client.recupererEmpreinteAttendue(url), empreinte);
    });

    test('autre nom de fichier : ErreurSource', () async {
      final client = creer(
        (_) async => http.Response(
          '$empreinte  bibliotheque_perso-0.3.3-installation.exe\n',
          200,
        ),
      );
      await expectLater(
        client.recupererEmpreinteAttendue(url),
        throwsA(isA<ErreurSource>()),
      );
    });

    test('contenu illisible : ErreurSource', () async {
      final client = creer(
        (_) async => http.Response('<html>Not Found</html>', 200),
      );
      await expectLater(
        client.recupererEmpreinteAttendue(url),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('telechargerInstallateur', () {
    final contenu = List<int>.generate(70000, (i) => i * 7 % 256);
    final empreinte = calculerSha256(contenu);
    List<List<int>> enMorceaux(List<int> octets) => <List<int>>[
      for (var i = 0; i < octets.length; i += 16384)
        octets.sublist(
          i,
          i + 16384 < octets.length ? i + 16384 : octets.length,
        ),
    ];

    test('écrit le fichier vérifié, sans .part restant', () async {
      final client = creerEnFlux(
        enMorceaux(contenu),
        tailleAnnoncee: contenu.length,
      );
      final chemin = '${dossier.path}${Platform.pathSeparator}installateur.exe';
      final progressions = <int>[];
      final fichier = await client.telechargerInstallateur(
        Uri.parse(_urlExe),
        chemin,
        empreinteAttendue: empreinte.toUpperCase(),
        tailleAttendue: contenu.length,
        progression: (recus, total) {
          expect(total, contenu.length);
          progressions.add(recus);
        },
      );
      expect(fichier.path, chemin);
      expect(await fichier.readAsBytes(), contenu);
      expect(await File('$chemin.part').exists(), isFalse);
      expect(progressions, <int>[16384, 32768, 49152, 65536, 70000]);
      expect(requetes.single.url.toString(), _urlExe);
    });

    test('empreinte différente : fichier supprimé, erreur dédiée', () async {
      final client = creerEnFlux(enMorceaux(contenu));
      final chemin = '${dossier.path}${Platform.pathSeparator}installateur.exe';
      await expectLater(
        client.telechargerInstallateur(
          Uri.parse(_urlExe),
          chemin,
          empreinteAttendue: 'a' * 64,
        ),
        throwsA(
          isA<ErreurEmpreinteInstallateur>().having(
            (e) => e.empreinteObtenue,
            'empreinteObtenue',
            empreinte,
          ),
        ),
      );
      expect(await File(chemin).exists(), isFalse);
      expect(await File('$chemin.part').exists(), isFalse);
    });

    test('taille annoncée trop grande : refus avant écriture', () async {
      final client = creerEnFlux(enMorceaux(contenu), tailleAnnoncee: 70000);
      final chemin = '${dossier.path}${Platform.pathSeparator}installateur.exe';
      await expectLater(
        client.telechargerInstallateur(
          Uri.parse(_urlExe),
          chemin,
          empreinteAttendue: empreinte,
          tailleMax: 50000,
        ),
        throwsA(isA<ErreurSource>()),
      );
      expect(await File('$chemin.part').exists(), isFalse);
    });

    test('flux plus long que le maximum (sans taille annoncée)', () async {
      final client = creerEnFlux(enMorceaux(contenu));
      final chemin = '${dossier.path}${Platform.pathSeparator}installateur.exe';
      await expectLater(
        client.telechargerInstallateur(
          Uri.parse(_urlExe),
          chemin,
          empreinteAttendue: empreinte,
          tailleMax: 50000,
        ),
        throwsA(isA<ErreurSource>()),
      );
      expect(await File('$chemin.part').exists(), isFalse);
    });

    test('taille reçue différente de la release : ErreurSource', () async {
      final client = creerEnFlux(enMorceaux(contenu));
      final chemin = '${dossier.path}${Platform.pathSeparator}installateur.exe';
      await expectLater(
        client.telechargerInstallateur(
          Uri.parse(_urlExe),
          chemin,
          empreinteAttendue: empreinte,
          tailleAttendue: contenu.length + 1,
        ),
        throwsA(isA<ErreurSource>()),
      );
      expect(await File('$chemin.part').exists(), isFalse);
    });

    test(
      'coupure réseau pendant le flux : ErreurSource, .part supprimé',
      () async {
        final client = ClientMiseAJourGithub(
          ClientHttpPoli(
            client: MockClient.streaming((requete, _) async {
              final sortie = StreamController<List<int>>();
              sortie.add(contenu.sublist(0, 1000));
              sortie.addError(const SocketException('Connexion coupée'));
              unawaited(sortie.close());
              return http.StreamedResponse(sortie.stream, 200);
            }),
            maintenant: horloge.lire,
            attendre: horloge.attendre,
          ),
        );
        final chemin =
            '${dossier.path}${Platform.pathSeparator}installateur.exe';
        await expectLater(
          client.telechargerInstallateur(
            Uri.parse(_urlExe),
            chemin,
            empreinteAttendue: empreinte,
          ),
          throwsA(isA<ErreurSource>()),
        );
        expect(await File('$chemin.part').exists(), isFalse);
      },
    );

    test('404 : ErreurSource sans fichier créé', () async {
      final client = creerEnFlux(<List<int>>[
        utf8.encode('Not Found'),
      ], statut: 404);
      final chemin = '${dossier.path}${Platform.pathSeparator}installateur.exe';
      await expectLater(
        client.telechargerInstallateur(
          Uri.parse(_urlExe),
          chemin,
          empreinteAttendue: empreinte,
        ),
        throwsA(
          isA<ErreurSource>().having((e) => e.codeStatut, 'codeStatut', 404),
        ),
      );
      expect(await File('$chemin.part').exists(), isFalse);
    });

    test("deux téléchargements sur github.com : 1 s d'écart", () async {
      final client = creerEnFlux(enMorceaux(contenu));
      final chemin = '${dossier.path}${Platform.pathSeparator}installateur.exe';
      for (var i = 0; i < 2; i++) {
        await client.telechargerInstallateur(
          Uri.parse(_urlExe),
          chemin,
          empreinteAttendue: empreinte,
        );
      }
      expect(horloge.attentes, <Duration>[const Duration(seconds: 1)]);
    });
  });
}
