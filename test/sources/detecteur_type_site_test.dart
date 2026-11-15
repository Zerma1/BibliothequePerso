import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

void main() {
  late HorlogeFactice horloge;

  setUp(() => horloge = HorlogeFactice());

  group('validerUrl', () {
    test('accepte http et https', () {
      expect(
        DetecteurTypeSite.validerUrl('https://exemple.org').host,
        'exemple.org',
      );
      expect(
        DetecteurTypeSite.validerUrl(' http://exemple.org/ ').scheme,
        'http',
      );
    });

    test(
      'refuse les autres schémas, les URLs sans domaine et le texte libre',
      () {
        for (final url in <String>[
          'ftp://exemple.org',
          'exemple.org',
          'https://',
          '',
          'javascript:alert(1)',
          'file:///C:/page.html',
        ]) {
          expect(
            () => DetecteurTypeSite.validerUrl(url),
            throwsA(isA<ErreurSource>()),
            reason: url,
          );
        }
      },
    );
  });

  group('detecter', () {
    test('mangadex.org et www.mangadex.org donnent mangaDex sans requête', () async {
      var appels = 0;
      final detecteur = DetecteurTypeSite(
        creerClientTest((requete) async {
          appels++;
          return http.Response('', 200);
        }, horloge),
      );
      expect(
        await detecteur.detecter('https://mangadex.org'),
        TypeSource.mangaDex,
      );
      expect(
        await detecteur.detecter(
          'https://www.mangadex.org/title/12e28a8a-cbfe-4e12-bab8-b6fb0b9a59b4',
        ),
        TypeSource.mangaDex,
      );
      expect(appels, 0);
    });

    test(
      'un autre domaine télécharge la page d\'accueil et l\'analyse',
      () async {
        final urls = <Uri>[];
        final detecteur = DetecteurTypeSite(
          creerClientTest((requete) async {
            urls.add(requete.url);
            return http.Response(
              lireExemple('exemples_html/accueil_madara.html'),
              200,
            );
          }, horloge),
        );
        expect(
          await detecteur.detecter('https://exemple-madara.org/'),
          TypeSource.madara,
        );
        expect(urls.single.toString(), 'https://exemple-madara.org/');
      },
    );

    test('une URL invalide lève une ErreurSource', () async {
      final detecteur = DetecteurTypeSite(
        creerClientTest((requete) async => http.Response('', 200), horloge),
      );
      await expectLater(
        detecteur.detecter('mangadex.org'),
        throwsA(isA<ErreurSource>()),
      );
    });

    test('une page inaccessible lève une ErreurSource', () async {
      final detecteur = DetecteurTypeSite(
        creerClientTest((requete) async => http.Response('', 404), horloge),
      );
      await expectLater(
        detecteur.detecter('https://exemple.org/'),
        throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 404)),
      );
    });
  });

  group('detecterDepuisHtml', () {
    test('page Madara enregistrée', () {
      expect(
        DetecteurTypeSite.detecterDepuisHtml(
          lireExemple('exemples_html/accueil_madara.html'),
        ),
        TypeSource.madara,
      );
    });

    test('page d\'accueil MangaThemesia enregistrée (bixbox + /manga/)', () {
      expect(
        DetecteurTypeSite.detecterDepuisHtml(
          lireExemple('exemples_html/accueil_mangathemesia.html'),
        ),
        TypeSource.mangaThemesia,
      );
    });

    test('lecteur MangaThemesia enregistré (ts_reader)', () {
      expect(
        DetecteurTypeSite.detecterDepuisHtml(
          lireExemple('exemples_html/lecteur_mangathemesia.html'),
        ),
        TypeSource.mangaThemesia,
      );
    });

    test('page sans marqueur : générique', () {
      expect(
        DetecteurTypeSite.detecterDepuisHtml(
          lireExemple('exemples_html/accueil_generique.html'),
        ),
        TypeSource.generique,
      );
      expect(DetecteurTypeSite.detecterDepuisHtml(''), TypeSource.generique);
    });

    test('chaque marqueur Madara suffit seul', () {
      expect(
        DetecteurTypeSite.detecterDepuisHtml(
          '<div class="c-blog wp-manga-section"></div>',
        ),
        TypeSource.madara,
      );
      expect(
        DetecteurTypeSite.detecterDepuisHtml(
          '<script src="/wp-content/themes/madara/js/x.js"></script>',
        ),
        TypeSource.madara,
      );
      expect(
        DetecteurTypeSite.detecterDepuisHtml('<a href="/manga/titre/">T</a>'),
        TypeSource.madara,
      );
    });

    test(
      'un marqueur Madara fort l\'emporte sur un marqueur MangaThemesia',
      () {
        expect(
          DetecteurTypeSite.detecterDepuisHtml(
            '<div class="bixbox"><div class="wp-manga-item"></div></div>',
          ),
          TypeSource.madara,
        );
      },
    );
  });
}
