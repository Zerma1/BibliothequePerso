import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:bibliotheque_perso/sources/sites_externes.dart';
import 'package:bibliotheque_perso/sources/source_webtoons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

/// Pages réelles enregistrées le 2026-11-17 (aucun appel réseau dans les
/// tests).
const String urlPetiteFrappe =
    'https://www.webtoons.com/fr/romance/'
    'the-gangster-daughter-of-the-henchman-dukes-family/list?title_no=11499';
const String urlTowerOfGod =
    'https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95';

final String htmlPetiteFrappe = lireExemple(
  'exemples_html/webtoons_petite_frappe_p1.html',
);
final String htmlTowerOfGod1 = lireExemple(
  'exemples_html/webtoons_tower_of_god_p1.html',
);
final String htmlTowerOfGod2 = lireExemple(
  'exemples_html/webtoons_tower_of_god_p2.html',
);

/// Réponse HTML UTF-8, comme le site.
http.Response reponseHtml(String corps, {int statut = 200}) {
  return http.Response(
    corps,
    statut,
    headers: <String, String>{'content-type': 'text/html; charset=UTF-8'},
  );
}

void main() {
  group('adresses et détection', () {
    test('webtoons.com, www. et m. sont reconnus sans requête', () {
      for (final url in <String>[
        'https://webtoons.com',
        urlPetiteFrappe,
        'https://m.webtoons.com/fr/romance/x/list?title_no=1',
        'http://WWW.Webtoons.com/',
      ]) {
        expect(
          DetecteurTypeSite.verifierDomaine(Uri.parse(url)),
          TypeSource.webtoons,
          reason: url,
        );
      }
      for (final url in <String>[
        'https://webtoon-phinf.pstatic.net/a.jpg',
        'https://webtoons.org',
        'https://static.webtoons.com',
      ]) {
        expect(
          DetecteurTypeSite.verifierDomaine(Uri.parse(url)),
          isNull,
          reason: url,
        );
      }
    });

    test('detecter ne fait aucune requête pour WEBTOON', () async {
      var requetes = 0;
      final detecteur = DetecteurTypeSite(
        creerClientTest((requete) async {
          requetes++;
          return reponseHtml('');
        }, HorlogeFactice()),
      );
      expect(await detecteur.detecter(urlPetiteFrappe), TypeSource.webtoons);
      expect(requetes, 0);
    });

    test('validerUrlTitre rend la forme canonique www sans page', () {
      expect(
        SourceWebtoons.validerUrlTitre(' $urlPetiteFrappe ').toString(),
        urlPetiteFrappe,
      );
      expect(
        SourceWebtoons.validerUrlTitre(
          'http://m.webtoons.com/en/fantasy/tower-of-god/list?title_no=95'
          '&page=3',
        ).toString(),
        urlTowerOfGod,
      );
    });

    test('validerUrlTitre refuse une autre adresse', () {
      for (final url in <String>[
        'https://www.webtoons.com/',
        'https://www.webtoons.com/fr/romance/x/list',
        'https://www.webtoons.com/fr/romance/x/list?title_no=abc',
        'https://www.webtoons.com/fr/romance/x/ep-1/viewer?title_no=1'
            '&episode_no=1',
        'https://exemple.org/fr/romance/x/list?title_no=1',
        'ftp://www.webtoons.com/fr/romance/x/list?title_no=1',
      ]) {
        expect(
          () => SourceWebtoons.validerUrlTitre(url),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.url, 'url', url)
                .having((e) => e.typeDetecte, 'type', TypeSource.webtoons),
          ),
          reason: url,
        );
      }
    });

    test("adressePage n'ajoute jamais page=1 (interdit par robots.txt)", () {
      final uri = Uri.parse(urlTowerOfGod);
      expect(SourceWebtoons.adressePage(uri, 1).toString(), urlTowerOfGod);
      expect(
        SourceWebtoons.adressePage(uri, 2).toString(),
        '$urlTowerOfGod&page=2',
      );
    });

    test('langue lue dans l’adresse', () {
      expect(
        SourceWebtoons.langueDepuisAdresse(Uri.parse(urlPetiteFrappe)),
        'fr',
      );
      expect(
        SourceWebtoons.langueDepuisAdresse(Uri.parse(urlTowerOfGod)),
        'en',
      );
      expect(
        SourceWebtoons.langueDepuisAdresse(
          Uri.parse('https://www.webtoons.com/zh-hant/a/b/list?title_no=1'),
        ),
        'zh',
      );
      expect(
        SourceWebtoons.langueDepuisAdresse(Uri.parse('https://webtoons.com')),
        '',
      );
    });

    test('dates françaises et anglaises', () {
      expect(
        SourceWebtoons.convertirDate('13 nov. 2026'),
        DateTime.utc(2026, 11, 13),
      );
      expect(
        SourceWebtoons.convertirDate(' 2 févr. 2025 '),
        DateTime.utc(2025, 2, 2),
      );
      expect(
        SourceWebtoons.convertirDate('Dec 22, 2024'),
        DateTime.utc(2024, 12, 22),
      );
      expect(
        SourceWebtoons.convertirDate('Sept. 3, 2024'),
        DateTime.utc(2024, 9, 3),
      );
      expect(SourceWebtoons.convertirDate('22.12.2024'), isNull);
      expect(SourceWebtoons.convertirDate('13 xyz 2026'), isNull);
    });

    test('nomSiteExterne : WEBTOON', () {
      expect(
        nomSiteExterne(
          'https://www.webtoons.com/fr/romance/x/ep-1/viewer?title_no=1',
        ),
        'WEBTOON',
      );
      expect(nomSiteExterne('https://m.webtoons.com/x'), 'WEBTOON');
      expect(nomSiteExterne('https://webtoons.com/x'), 'WEBTOON');
    });

    test('la fabrique crée SourceWebtoons', () {
      final fabrique = FabriqueSources(
        creerClientTest((r) async => reponseHtml(''), HorlogeFactice()),
      );
      expect(
        fabrique.creer(
          const Source(
            nom: 'WEBTOON',
            urlBase: 'https://www.webtoons.com',
            typeSource: TypeSource.webtoons,
          ),
        ),
        isA<SourceWebtoons>(),
      );
    });
  });

  group('analyse du HTML enregistré', () {
    test('fiche de La Petite Frappe du Duc de Pacotille', () {
      final fiche = SourceWebtoons.analyserFiche(
        htmlPetiteFrappe,
        Uri.parse(urlPetiteFrappe),
      );
      final titre = fiche.titre;
      expect(titre.urlTitre, urlPetiteFrappe);
      expect(titre.nom, 'La Petite Frappe du Duc de Pacotille');
      expect(titre.typeTitre, TypeTitre.autre);
      expect(
        titre.urlCouverture,
        'https://swebtoon-phinf.pstatic.net/20261109_63/'
        '17941951748430yXzM_JPEG/4Thumb_Poster.jpg?type=crop540_540',
      );
      expect(titre.resume, startsWith('Benjamine du duc de Hachania, Léonora'));
      expect(titre.resume, endsWith('pour sauver les siens.'));
      expect(titre.auteur, 'eclair, LM & SOLO HAM, LM & BBUSHU');
      expect(titre.statut, 'Nouvel épisode chaque VENDREDI');
      expect(fiche.categories, <String>['Romance']);
    });

    test('fiche de Tower of God', () {
      final fiche = SourceWebtoons.analyserFiche(
        htmlTowerOfGod1,
        Uri.parse(urlTowerOfGod),
      );
      expect(fiche.titre.nom, 'Tower of God');
      expect(fiche.titre.auteur, 'SIU');
      expect(fiche.titre.statut, 'EVERY MONDAY');
      expect(fiche.categories, <String>['Fantasy']);
      expect(fiche.titre.resume, startsWith('What do you desire?'));
    });

    test('épisodes de La Petite Frappe (page unique)', () {
      final uri = Uri.parse(urlPetiteFrappe);
      final episodes = SourceWebtoons.analyserEpisodes(htmlPetiteFrappe, uri);
      expect(episodes.map((e) => e.nom), <String>['Ep. 2', 'Ep. 1', 'Ep. 0']);
      expect(episodes.map((e) => e.numero), <double>[3, 2, 1]);
      final premier = episodes.last;
      expect(
        premier.urlChapitre,
        'https://www.webtoons.com/fr/romance/'
        'the-gangster-daughter-of-the-henchman-dukes-family/ep-0/viewer'
        '?title_no=11499&episode_no=1',
      );
      expect(premier.urlExterne, premier.urlChapitre);
      expect(premier.langue, 'fr');
      expect(premier.datePublication, DateTime.utc(2026, 11, 13));
      expect(SourceWebtoons.aPageSuivante(htmlPetiteFrappe, uri, 1), isFalse);
    });

    test('épisodes de Tower of God, page 2 et pagination', () {
      final uri = Uri.parse(urlTowerOfGod);
      final episodes = SourceWebtoons.analyserEpisodes(htmlTowerOfGod2, uri);
      expect(episodes, hasLength(9));
      expect(episodes.first.nom, '[Season 3] Ep. 226');
      // Rang « #643 », et non l'identifiant episode_no=644.
      expect(episodes.first.numero, 643);
      expect(episodes.first.langue, 'en');
      expect(episodes.first.datePublication, DateTime.utc(2024, 12, 22));
      expect(episodes.last.numero, 635);
      expect(SourceWebtoons.aPageSuivante(htmlTowerOfGod1, uri, 1), isTrue);
      expect(SourceWebtoons.aPageSuivante(htmlTowerOfGod2, uri, 2), isTrue);
      // Page 10 : la flèche pg_next mène à la page 11.
      expect(SourceWebtoons.aPageSuivante(htmlTowerOfGod2, uri, 10), isTrue);
      expect(SourceWebtoons.aPageSuivante(htmlTowerOfGod2, uri, 11), isFalse);
    });

    test('une page qui n’est pas une liste lève une ErreurSource', () {
      expect(
        () => SourceWebtoons.analyserFiche(
          '<html><body><p>Erreur</p></body></html>',
          Uri.parse(urlPetiteFrappe),
        ),
        throwsA(isA<ErreurSource>()),
      );
      expect(
        () => SourceWebtoons.analyserEpisodes(
          '<html><body></body></html>',
          Uri.parse(urlPetiteFrappe),
        ),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('réseau simulé', () {
    test(
      'fiche puis épisodes : une seule requête, User-Agent honnête',
      () async {
        final requetes = <http.Request>[];
        final source = SourceWebtoons(
          creerClientTest((requete) async {
            requetes.add(requete);
            return reponseHtml(htmlPetiteFrappe);
          }, HorlogeFactice()),
        );
        final fiche = await source.recupererFiche(urlPetiteFrappe);
        final episodes = await source.recupererChapitres(urlPetiteFrappe);
        expect(fiche.titre.nom, 'La Petite Frappe du Duc de Pacotille');
        expect(episodes.map((e) => e.numero), <double>[1, 2, 3]);
        expect(requetes, hasLength(1));
        expect(requetes.single.url.toString(), urlPetiteFrappe);
        expect(requetes.single.headers['User-Agent'], userAgentApplication);
      },
    );

    test(
      'toutes les pages sont lues, 1 s entre deux, page=1 jamais demandée',
      () async {
        final horloge = HorlogeFactice();
        final adresses = <String>[];
        final source = SourceWebtoons(
          creerClientTest((requete) async {
            adresses.add(requete.url.toString());
            final page = requete.url.queryParameters['page'];
            return reponseHtml(page == '2' ? htmlTowerOfGod2 : htmlTowerOfGod1);
          }, horloge),
          nombreMaxPages: 2,
        );
        final episodes = await source.recupererChapitres(urlTowerOfGod);
        expect(adresses, <String>[urlTowerOfGod, '$urlTowerOfGod&page=2']);
        expect(horloge.attentes, contains(const Duration(seconds: 1)));
        expect(episodes, hasLength(18));
        // Du plus ancien au plus récent.
        expect(episodes.first.numero, 635);
        expect(episodes.last.nom, '[Season 3] Ep. 235 (Season 3 Finale)');
        expect(
          episodes.map((e) => e.numero).toList(),
          orderedEquals(List<double>.of(episodes.map((e) => e.numero))..sort()),
        );
      },
    );

    test('une page suivante déjà vue arrête la lecture', () async {
      var requetes = 0;
      final source = SourceWebtoons(
        creerClientTest((requete) async {
          requetes++;
          // Le site ignorerait `page` : toujours la même page.
          return reponseHtml(htmlTowerOfGod1);
        }, HorlogeFactice()),
      );
      final episodes = await source.recupererChapitres(urlTowerOfGod);
      expect(requetes, 2);
      expect(episodes, hasLength(9));
    });

    test('une erreur HTTP lève une ErreurSource typée webtoons', () async {
      final source = SourceWebtoons(
        creerClientTest(
          (requete) async => reponseHtml('introuvable', statut: 404),
          HorlogeFactice(),
        ),
      );
      await expectLater(
        source.recupererChapitres(urlPetiteFrappe),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.typeDetecte,
            'type',
            TypeSource.webtoons,
          ),
        ),
      );
    });

    test('recupererContenu lève une ErreurSource sans requête', () async {
      var requetes = 0;
      final source = SourceWebtoons(
        creerClientTest((requete) async {
          requetes++;
          return reponseHtml('');
        }, HorlogeFactice()),
      );
      const url =
          'https://www.webtoons.com/fr/romance/x/ep-0/viewer?title_no=1'
          '&episode_no=1';
      await expectLater(
        source.recupererContenu(url),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.url, 'url', url)
              .having((e) => e.typeDetecte, 'type', TypeSource.webtoons)
              .having(
                (e) => e.message,
                'message',
                contains('uniquement sur WEBTOON'),
              ),
        ),
      );
      expect(await source.rechercher('tower'), isEmpty);
      expect(requetes, 0);
    });
  });
}
