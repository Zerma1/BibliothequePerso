// Tests du rapport d'erreur exportable (SO2). Toutes les « données
// personnelles » ci-dessous sont fictives.
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/rapport_erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

void main() {
  group('masquerDonneesPersonnelles', () {
    test('adresse électronique', () {
      expect(
        masquerDonneesPersonnelles('Contact : jean.dupont+test@exemple.fr.'),
        'Contact : $texteMasque.',
      );
    });

    test('jeton JWT et en-tête Bearer', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.abcDEF_123-xyz';
      expect(
        masquerDonneesPersonnelles('jeton $jwt fin'),
        'jeton $texteMasque fin',
      );
      expect(
        masquerDonneesPersonnelles('Authorization: Bearer abc.def-123'),
        isNot(contains('abc.def-123')),
      );
    });

    test('paramètres sensibles dans une URL, un cookie ou du JSON', () {
      final texte = masquerDonneesPersonnelles(
        'https://site.exemple/page?id=12&token=SECRET1&session_id=SECRET2 '
        'Cookie: PHPSESSID=SECRET3; '
        '{"password":"SECRET4","api_key": "SECRET5"} '
        'wordpress_logged_in_0a1b2c=SECRET6',
      );
      for (var i = 1; i <= 6; i++) {
        expect(texte, isNot(contains('SECRET$i')), reason: 'SECRET$i');
      }
      // Les paramètres ordinaires restent lisibles.
      expect(texte, contains('id=12'));
    });

    test('les noms proches mais anodins ne sont pas masqués', () {
      const texte = '"author":"Ayamine Maito","design":"x","inside":"y"';
      expect(masquerDonneesPersonnelles(texte), texte);
    });

    test('jeton MangaDex@Home dans baseUrl', () {
      final texte = masquerDonneesPersonnelles(
        'https://abcd.efgh.mangadex.network:44300/JETONSECRET/data/h/1.png',
      );
      expect(texte, isNot(contains('JETONSECRET')));
      expect(texte, contains('/data/h/1.png'));
    });

    test('adresses IP v4 et v6, mais pas une heure', () {
      final texte = masquerDonneesPersonnelles(
        'Votre IP : 192.0.2.17 / 2001:db8:85a3:0:0:8a2e:370:7334 / '
        '2001:db8::1 à 12:30:45',
      );
      expect(texte, isNot(contains('192.0.2.17')));
      expect(texte, isNot(contains('2001:db8')));
      expect(texte, contains('12:30:45'));
    });

    test('nom du dossier personnel dans un chemin', () {
      expect(
        masquerDonneesPersonnelles(r'C:\Users\quelquun\Documents\a.zip'),
        'C:\\Users\\$texteMasque\\Documents\\a.zip',
      );
      expect(
        masquerDonneesPersonnelles('/home/quelquun/a.zip'),
        '/home/$texteMasque/a.zip',
      );
    });

    test('un texte sans donnée sensible est inchangé', () {
      const texte =
          '{"result":"ok","data":{"id":"12e28a8a-cbfe-4e12-bab8-b6fb0b9a59b4"}}';
      expect(masquerDonneesPersonnelles(texte), texte);
    });
  });

  group('extraireDebutReponse', () {
    test('espaces regroupés et texte court gardé tel quel', () {
      expect(
        extraireDebutReponse('  <html>\n\t<body> a </body>  '),
        '<html> <body> a </body>',
      );
    });

    test('tronqué à longueurMaxExtraitReponse avec « … »', () {
      final extrait = extraireDebutReponse('a' * 5000);
      expect(extrait.length, longueurMaxExtraitReponse + 1);
      expect(extrait, endsWith('…'));
    });

    test('masqué avant la troncature : aucun morceau de jeton', () {
      final texte = '${'x' * 290} token=ABCDEFGHIJKLMNOPQRSTUVWXYZ suite';
      final extrait = extraireDebutReponse(texte);
      expect(extrait, isNot(contains('ABCDEFGHIJ')));
    });
  });

  group('ErreurSource.avecContexte', () {
    test('complète sans remplacer une valeur déjà posée', () {
      const erreur = ErreurSource(
        'https://exemple.org',
        'Échec',
        codeStatut: 500,
        extraitReponse: 'premier',
      );
      final completee = erreur.avecContexte(
        typeDetecte: TypeSource.madara,
        extraitReponse: 'second',
      );
      expect(completee.typeDetecte, TypeSource.madara);
      expect(completee.extraitReponse, 'premier');
      expect(completee.codeStatut, 500);
      expect(completee.url, erreur.url);
      expect(completee.message, erreur.message);
      expect(
        completee.avecContexte(typeDetecte: TypeSource.generique).typeDetecte,
        TypeSource.madara,
      );
    });
  });

  group('ClientHttpPoli : extrait des réponses en erreur', () {
    test('code HTTP et extrait nettoyé (adresse IP masquée)', () async {
      final client = creerClientTest(
        (requete) async => http.Response(
          '<html><body>Accès refusé. Votre IP : 203.0.113.9</body></html>',
          403,
          headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
        ),
        HorlogeFactice(),
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://site.exemple/')),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.codeStatut, 'code', 403)
              .having(
                (e) => e.extraitReponse,
                'extrait',
                contains('Accès refusé'),
              )
              .having(
                (e) => e.extraitReponse,
                'extrait',
                isNot(contains('203.0.113.9')),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('203.0.113.9')),
              ),
        ),
      );
    });

    test('pas de réponse (erreur réseau) : extrait absent', () async {
      // Connexion refusée simulée ; l'horloge factice rend les nouvelles
      // tentatives instantanées.
      final client = creerClientTest(
        (requete) async => throw http.ClientException('connexion refusée'),
        HorlogeFactice(),
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://site.exemple/')),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.extraitReponse,
            'extrait',
            isNull,
          ),
        ),
      );
    });
  });

  group('RapportErreurSource.versTexte', () {
    test('contient les informations utiles, sans donnée personnelle', () {
      final erreur = const ErreurSource(
        'https://site.exemple/manga/x?token=SECRETURL',
        'Réponse HTTP 500 : contact admin@site.exemple',
        codeStatut: 500,
        cause: FormatException(r'C:\Users\quelquun\cache.json'),
        octetsRecus: 1234,
        duree: Duration(milliseconds: 850),
        extraitReponse: '<html>Erreur interne 198.51.100.4</html>',
      ).avecContexte(typeDetecte: TypeSource.madara);
      final texte = RapportErreurSource(
        erreur,
        action: "Lecture d'un titre",
        date: DateTime.utc(2026, 11, 16, 10, 30),
        versionApplication: '1.2.0+5',
        systeme: 'windows',
      ).versTexte();

      expect(texte, contains("Rapport d'erreur"));
      expect(texte, contains('Date (UTC) : 2026-11-16T10:30:00.000Z'));
      expect(texte, contains("Action : Lecture d'un titre"));
      expect(texte, contains('Version : 1.2.0+5'));
      expect(texte, contains('Système : windows'));
      expect(texte, contains('Type de site détecté : madara'));
      expect(texte, contains('Domaine : site.exemple'));
      expect(texte, contains('Code HTTP : 500'));
      expect(texte, contains('Cause : FormatException'));
      expect(texte, contains('Octets reçus : 1234'));
      expect(texte, contains('Durée (ms) : 850'));
      expect(texte, contains('<html>Erreur interne'));
      for (final secret in <String>[
        'SECRETURL',
        'admin@site.exemple',
        'quelquun',
        '198.51.100.4',
      ]) {
        expect(texte, isNot(contains(secret)), reason: secret);
      }
    });

    test('type inconnu et aucune réponse reçue', () {
      final texte = RapportErreurSource(
        const ErreurSource('https://site.exemple', 'Délai dépassé (20 s)'),
      ).versTexte();
      expect(texte, contains('Type de site détecté : inconnu'));
      expect(texte, contains('(aucune réponse reçue)'));
      expect(texte, isNot(contains('Code HTTP')));
    });

    test("le type passé au rapport l'emporte sur celui de l'erreur", () {
      final rapport = RapportErreurSource(
        const ErreurSource(
          'https://site.exemple',
          'x',
          typeDetecte: TypeSource.madara,
        ),
        typeDetecte: TypeSource.mangaThemesia,
      );
      expect(rapport.typeDetecte, TypeSource.mangaThemesia);
      expect(rapport.date.isUtc, isTrue);
    });
  });
}
