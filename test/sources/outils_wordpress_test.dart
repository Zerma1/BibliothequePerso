import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/sources/outils_wordpress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

void main() {
  final maintenant = DateTime.utc(2026, 11, 17, 12);

  group('dates', () {
    test('dates absolues', () {
      for (final cas in <String, DateTime>{
        'October 11, 2017': DateTime.utc(2017, 10, 11),
        'April 6, 2019': DateTime.utc(2019, 4, 6),
        '13 nov. 2026': DateTime.utc(2026, 11, 13),
        '2017-10-11 08:53:07': DateTime.utc(2017, 10, 11),
        '11/10/2017': DateTime.utc(2017, 10, 11),
      }.entries) {
        expect(
          OutilsWordPress.convertirDate(cas.key, maintenant),
          cas.value,
          reason: cas.key,
        );
      }
    });

    test('dates relatives (anglais et français)', () {
      for (final cas in <String, Duration>{
        '2 days ago': const Duration(days: 2),
        '1 hour ago': const Duration(hours: 1),
        '5 mins ago': const Duration(minutes: 5),
        'an hour ago': const Duration(hours: 1),
        'il y a 3 heures': const Duration(hours: 3),
        'il y a 2 mois': const Duration(days: 60),
        'yesterday': const Duration(days: 1),
        'hier': const Duration(days: 1),
      }.entries) {
        expect(
          OutilsWordPress.convertirDate(cas.key, maintenant),
          maintenant.subtract(cas.value),
          reason: cas.key,
        );
      }
    });

    test(
      'jour absent du mois : null, sans débordement sur le mois suivant',
      () {
        for (final texte in <String>[
          '31/02/2025',
          '2025-02-29',
          '2025-04-31',
          '31 févr. 2025',
          'February 30, 2024',
        ]) {
          expect(
            OutilsWordPress.convertirDate(texte, maintenant),
            isNull,
            reason: texte,
          );
        }
        // Année bissextile : le 29 février existe.
        expect(
          OutilsWordPress.convertirDate('29/02/2024', maintenant),
          DateTime.utc(2024, 2, 29),
        );
      },
    );

    test("date relative démesurée : null, jamais d'exception", () {
      for (final texte in <String>[
        '300000 years ago',
        '101 years ago',
        'il y a 2000000 jours',
        '99999999999999999999999 days ago',
        '9223372036854775807 weeks ago',
      ]) {
        expect(
          OutilsWordPress.convertirDate(texte, maintenant),
          isNull,
          reason: texte,
        );
      }
      // Sous le plafond de 100 ans : lue.
      expect(
        OutilsWordPress.convertirDate('99 years ago', maintenant),
        maintenant.subtract(const Duration(days: 365 * 99)),
      );
    });

    test('format inconnu : null', () {
      for (final texte in <String>['', 'bientôt', '32/13/2020', 'new']) {
        expect(
          OutilsWordPress.convertirDate(texte, maintenant),
          isNull,
          reason: texte,
        );
      }
    });
  });

  test('numéros de chapitre', () {
    final adresse = Uri.parse('https://s.test/manga/x/chapitre/');
    expect(OutilsWordPress.numeroChapitre('Chapter 15', adresse), 15);
    expect(OutilsWordPress.numeroChapitre('Ch. 10.5 - Titre', adresse), 10.5);
    expect(OutilsWordPress.numeroChapitre('Épisode 3', adresse), 3);
    expect(OutilsWordPress.numeroChapitre('Prologue', adresse), 0);
    expect(
      OutilsWordPress.numeroChapitre(
        'Bonus',
        Uri.parse('https://s.test/manga/x/chapter-4-5/'),
      ),
      4.5,
    );
    expect(
      OutilsWordPress.numeroChapitre(
        'Bonus',
        Uri.parse('https://s.test/manga/x/chapter-10-la-fin/'),
      ),
      10,
    );
  });

  test('langue : lang de la page, puis préférence, puis vide', () {
    expect(
      OutilsWordPress.langueDepuisPage(
        parse('<html lang="en-US"></html>'),
        'fr',
      ),
      'en',
    );
    expect(
      OutilsWordPress.langueDepuisPage(parse('<html lang="pt_BR"></html>'), ''),
      'pt',
    );
    expect(
      OutilsWordPress.langueDepuisPage(parse('<p></p>'), ' fr , en'),
      'fr',
    );
    expect(OutilsWordPress.langueDepuisPage(parse('<p></p>'), ''), '');
  });

  test('adresse des images différées', () {
    final base = Uri.parse('https://s.test/manga/x/');
    String? adresse(String balise) =>
        OutilsWordPress.adresseImage(parse(balise).querySelector('img')!, base);
    expect(
      adresse('<img data-src=" https://cdn.test/1.jpg" src="/dflazy.jpg">'),
      'https://cdn.test/1.jpg',
    );
    expect(
      adresse('<img src="data:image/svg+xml,x" data-lazy-src="/2.webp">'),
      'https://s.test/2.webp',
    );
    expect(
      adresse('<img data-srcset="/a-193.jpg 193w, /a-125.jpg 125w">'),
      'https://s.test/a-193.jpg',
    );
    expect(
      adresse('<img src="https://s.test/themes/madara/images/dflazy.jpg">'),
      isNull,
    );
  });

  test('type depuis un texte du site', () {
    expect(OutilsWordPress.typeDepuisTexte('Manhwa'), TypeTitre.manhwa);
    expect(OutilsWordPress.typeDepuisTexte('type Manga'), TypeTitre.manga);
    expect(OutilsWordPress.typeDepuisTexte('Light Novel'), TypeTitre.roman);
    expect(OutilsWordPress.typeDepuisTexte('Comic'), TypeTitre.autre);
  });

  test('séparation des noms', () {
    expect(
      OutilsWordPress.separerNoms(' A, B ; C | D / E, -, N/A, A '),
      <String>['A', 'B', 'C', 'D', 'E'],
    );
    expect(OutilsWordPress.separerNoms('Fate/Zero'), <String>['Fate/Zero']);
  });

  test('racine du site', () {
    expect(
      OutilsWordPress.racineSite(Uri.parse('https://s.test/a/b/?x=1')),
      'https://s.test/',
    );
    expect(
      OutilsWordPress.racineSite(Uri.parse('http://s.test:8080/a/')),
      'http://s.test:8080/',
    );
  });

  group('ClientHttpPoli.envoyerFormulaire', () {
    test(
      'POST de formulaire : corps encodé, en-têtes, aucun réessai',
      () async {
        final requetes = <http.Request>[];
        final client = creerClientTest((requete) async {
          requetes.add(requete);
          return http.Response('erreur', 500);
        }, HorlogeFactice());
        await expectLater(
          client.envoyerFormulaire(
            Uri.parse('https://s.test/wp-admin/admin-ajax.php'),
            champs: <String, String>{'action': 'a b', 'manga': '12'},
            referer: 'https://s.test/manga/x/',
          ),
          throwsA(anything),
        );
        expect(requetes, hasLength(1));
        final requete = requetes.single;
        expect(requete.method, 'POST');
        expect(requete.bodyFields, <String, String>{
          'action': 'a b',
          'manga': '12',
        });
        expect(
          requete.headers['Content-Type'],
          'application/x-www-form-urlencoded; charset=UTF-8',
        );
        expect(requete.headers['X-Requested-With'], 'XMLHttpRequest');
        expect(requete.headers['Referer'], 'https://s.test/manga/x/');
      },
    );

    test(
      'lecture : réessais demandés, plafonnés à la règle du client',
      () async {
        var appels = 0;
        final client = creerClientTest((requete) async {
          appels++;
          return appels < 3
              ? http.Response('panne', 503)
              : http.Response('<ul></ul>', 200);
        }, HorlogeFactice());
        final texte = await client.envoyerFormulaire(
          Uri.parse('https://s.test/manga/x/ajax/chapters/'),
          nouvellesTentatives: 10,
        );
        expect(texte, '<ul></ul>');
        expect(appels, 3);
      },
    );
  });
}
