import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:bibliotheque_perso/sources/sites_externes.dart';
import 'package:bibliotheque_perso/sources/source_mangadex.dart';
import 'package:bibliotheque_perso/sources/source_scan_manga.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

/// Pages réelles enregistrées le 2026-11-16 (aucun appel réseau dans les
/// tests).
const String urlPotion =
    'https://www.scan-manga.com/6678/Potion-danomi-de-Ikinobimasu.html';
const String urlMurim =
    'https://www.scan-manga.com/7676-38512/Murim-Login.html';

final String htmlPotion = lireExemple(
  'exemples_html/scan_manga_titre_potion.html',
);
final String htmlMurim = lireExemple(
  'exemples_html/scan_manga_titre_murim_login.html',
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
    test('scan-manga.com et www.scan-manga.com sont reconnus sans requête', () {
      for (final url in <String>[
        'https://scan-manga.com',
        'https://www.scan-manga.com/6678/Potion.html',
        'http://WWW.Scan-Manga.com/',
      ]) {
        expect(
          DetecteurTypeSite.verifierDomaine(Uri.parse(url)),
          TypeSource.scanManga,
          reason: url,
        );
      }
      expect(
        DetecteurTypeSite.verifierDomaine(Uri.parse('https://scan-manga.org')),
        isNull,
      );
      expect(
        DetecteurTypeSite.verifierDomaine(
          Uri.parse('https://static.scan-manga.com'),
        ),
        isNull,
      );
    });

    test('detecter ne fait aucune requête pour Scan-Manga', () async {
      var requetes = 0;
      final detecteur = DetecteurTypeSite(
        creerClientTest((requete) async {
          requetes++;
          return reponseHtml('');
        }, HorlogeFactice()),
      );
      expect(
        await detecteur.detecter('https://www.scan-manga.com/'),
        TypeSource.scanManga,
      );
      expect(requetes, 0);
    });

    test('validerUrlTitre accepte les deux formes de fiche', () {
      expect(SourceScanManga.validerUrlTitre(urlPotion).toString(), urlPotion);
      expect(
        SourceScanManga.validerUrlTitre(' $urlMurim ').toString(),
        urlMurim,
      );
    });

    test('validerUrlTitre refuse une autre adresse', () {
      for (final url in <String>[
        'https://www.scan-manga.com/',
        'https://www.scan-manga.com/lecture-en-ligne/A-Chapitre-1-FR_1.html',
        'https://www.scan-manga.com/abc/Potion.html',
        'https://exemple.org/6678/Potion.html',
        'ftp://www.scan-manga.com/6678/Potion.html',
      ]) {
        expect(
          () => SourceScanManga.validerUrlTitre(url),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.url, 'url', url)
                .having((e) => e.typeDetecte, 'type', TypeSource.scanManga),
          ),
          reason: url,
        );
      }
    });

    test('nomSiteExterne : Scan-Manga, MANGA Plus, VIZ, domaine sinon', () {
      expect(
        nomSiteExterne(
          'https://www.scan-manga.com/lecture-en-ligne/A-Chapitre-1-FR_1.html',
        ),
        'Scan-Manga',
      );
      expect(nomSiteExterne('https://scan-manga.com/x'), 'Scan-Manga');
      expect(
        SourceMangaDex.nomSiteExterne('https://www.scan-manga.com/x'),
        'Scan-Manga',
      );
      expect(
        SourceMangaDex.nomSiteExterne('https://mangaplus.shueisha.co.jp/v/1'),
        'MANGA Plus',
      );
      expect(nomSiteExterne('https://www.viz.com/x'), 'VIZ');
      expect(nomSiteExterne('https://www.Autre-Site.fr/x'), 'autre-site.fr');
      expect(nomSiteExterne('pas une adresse'), 'pas une adresse');
    });

    test('la fabrique crée un SourceScanManga', () {
      final fabrique = FabriqueSources(
        creerClientTest((requete) async => reponseHtml(''), HorlogeFactice()),
      );
      expect(
        fabrique.creer(
          const Source(
            nom: 'Scan-Manga',
            urlBase: 'https://www.scan-manga.com',
            typeSource: TypeSource.scanManga,
            langueParDefaut: 'fr',
          ),
        ),
        isA<SourceScanManga>(),
      );
    });
  });

  group('langue et type', () {
    test("langue d'après le suffixe, fr par défaut", () {
      expect(SourceScanManga.langueDepuisSuffixe('FR'), 'fr');
      expect(SourceScanManga.langueDepuisSuffixe('VUS'), 'en');
      expect(SourceScanManga.langueDepuisSuffixe('vus'), 'en');
      expect(SourceScanManga.langueDepuisSuffixe('ES'), 'es');
      expect(SourceScanManga.langueDepuisSuffixe('XYZ'), 'fr');
      expect(SourceScanManga.langueDepuisSuffixe(null), 'fr');
    });

    test("type d'après la catégorie du site", () {
      expect(SourceScanManga.typeDepuisCategorie('Manga'), TypeTitre.manga);
      expect(SourceScanManga.typeDepuisCategorie('Manhwa'), TypeTitre.manhwa);
      expect(SourceScanManga.typeDepuisCategorie('Manhua'), TypeTitre.manhua);
      expect(SourceScanManga.typeDepuisCategorie('Novel'), TypeTitre.roman);
      expect(SourceScanManga.typeDepuisCategorie('Webtoon'), TypeTitre.autre);
      expect(SourceScanManga.typeDepuisCategorie(null), TypeTitre.autre);
    });
  });

  group('fiche', () {
    test('Potion-danomi : nom, alternatifs, couverture, résumé, auteurs', () {
      final fiche = SourceScanManga.analyserFiche(
        htmlPotion,
        Uri.parse(urlPotion),
      );
      final titre = fiche.titre;
      expect(titre.urlTitre, urlPotion);
      expect(titre.nom, 'Potion-danomi de Ikinobimasu!');
      expect(titre.titresAlternatifs.map((t) => t.nom), <String>[
        'I Shall Survive Using Potions!',
        'Potion Danomi de Ikinobimasu!',
        'Potion Loli',
        'Potion Tanomi de Ikinobimasu!',
      ]);
      expect(
        titre.urlCouverture,
        'https://static.scan-manga.com/img/manga/'
        'Potion-danomi_de_Ikinobimasu_1_5975.jpg',
      );
      expect(titre.resume, startsWith('Kaoru Nagase a été prise'));
      expect(titre.resume, contains('\nKaoru, qui est maintenant'));
      // Le caractère caché du site n'est pas repris.
      expect(titre.resume, isNot(contains('£')));
      expect(titre.resume, endsWith('dans un autre monde !'));
      expect(titre.auteur, 'Funa, Hibiki Kokonoe');
      expect(titre.statut, 'En pause');
      expect(titre.typeTitre, TypeTitre.manga);
      expect(fiche.categories, <String>[
        'Aventure',
        'Comédie',
        'Fantaisie',
        'Isekai',
        'Shonen',
      ]);
    });

    test('Murim Login : manhwa, en cours, genres sans info-bulles', () {
      final fiche = SourceScanManga.analyserFiche(
        htmlMurim,
        Uri.parse(urlMurim),
      );
      expect(fiche.titre.nom, 'Murim Login');
      expect(fiche.titre.titresAlternatifs.map((t) => t.nom), <String>[
        'Log-in Murim',
      ]);
      expect(fiche.titre.typeTitre, TypeTitre.manhwa);
      expect(fiche.titre.statut, 'En cours');
      expect(fiche.titre.auteur, 'Zerobic, Jang Cheol-Byuk');
      expect(fiche.categories, <String>[
        'Action',
        'Arts martiaux',
        'Aventure',
        'Comédie',
        'Drame',
        'Fantaisie',
        'Isekai',
        'Webcomic',
        'Seinen',
      ]);
    });

    test("une page qui n'est pas une fiche lève une ErreurSource", () {
      expect(
        () => SourceScanManga.analyserFiche(
          '<html><body><h1>Just a moment...</h1></body></html>',
          Uri.parse(urlPotion),
        ),
        throwsA(isA<ErreurSource>().having((e) => e.url, 'url', urlPotion)),
      );
    });
  });

  group('chapitres', () {
    test('Potion-danomi : un chapitre externe, lien de lecture', () {
      final chapitres = SourceScanManga.analyserChapitres(
        htmlPotion,
        Uri.parse(urlPotion),
      );
      expect(chapitres, hasLength(1));
      final chapitre = chapitres.single;
      const lecture =
          'https://www.scan-manga.com/lecture-en-ligne/'
          'Potion-danomi-de-Ikinobimasu-Chapitre-1-FR_116250.html';
      expect(chapitre.urlChapitre, lecture);
      expect(chapitre.urlExterne, lecture);
      expect(chapitre.estExterne, isTrue);
      expect(chapitre.nom, 'Chapitre 1 : Négociation et Nouveau Monde');
      expect(chapitre.numero, 1);
      expect(chapitre.langue, 'fr');
      expect(chapitre.datePublication, isNull);
    });

    test('Murim Login : 251 chapitres, du plus ancien au plus récent', () {
      final chapitres = SourceScanManga.analyserChapitres(
        htmlMurim,
        Uri.parse(urlMurim),
      );
      expect(chapitres, hasLength(251));
      expect(chapitres.first.numero, 1);
      expect(chapitres.last.numero, 251);
      expect(chapitres.last.nom, 'Chapitre 251');
      expect(
        chapitres.last.urlChapitre,
        'https://www.scan-manga.com/lecture-en-ligne/'
        'Murim-Login-Chapitre-251-FR_583214.html',
      );
      expect(chapitres.map((c) => c.urlChapitre).toSet(), hasLength(251));
      expect(chapitres.every((c) => c.urlExterne == c.urlChapitre), isTrue);
      expect(chapitres.every((c) => c.langue == 'fr'), isTrue);
    });

    test('suffixe VUS, lien relatif, numéro décimal, doublon ignoré', () {
      const html = '''
<div class="fiche_technique"></div>
<ul>
<li class='chapitre'><div class='chapitre_nom'><a href="/lecture-en-ligne/T-Chapitre-12.5-VUS_9.html">Chapitre 12.5</a> : Bonus</div>
<a href="/lecture-en-ligne/T-Chapitre-12.5-VUS_9.html" class='lecture_en_ligne'>Lire en ligne</a></li>
<li class='chapitre'><div class='chapitre_nom'><a href="/lecture-en-ligne/T-Chapitre-12.5-VUS_9.html">Chapitre 12.5</a></div></li>
<li class='chapitre'><div class='chapitre_nom'><a href="https://exemple.org/lecture-en-ligne/T-Chapitre-1-FR_1.html">Chapitre 1</a></div></li>
<li class='chapitre'><div class='chapitre_nom'><a href="https://www.scan-manga.com/publications/T-Chapitre-2_3.html">Chapitre 2</a></div></li>
</ul>''';
      final chapitres = SourceScanManga.analyserChapitres(
        html,
        Uri.parse(urlPotion),
      );
      expect(chapitres, hasLength(1));
      expect(
        chapitres.single.urlChapitre,
        'https://www.scan-manga.com/lecture-en-ligne/T-Chapitre-12.5-VUS_9.html',
      );
      expect(chapitres.single.numero, 12.5);
      expect(chapitres.single.langue, 'en');
      expect(chapitres.single.nom, 'Chapitre 12.5 : Bonus');
    });

    test('une fiche sans chapitre donne une liste vide', () {
      expect(
        SourceScanManga.analyserChapitres(
          '<div class="fiche_technique"></div>',
          Uri.parse(urlPotion),
        ),
        isEmpty,
      );
    });
  });

  group('réseau simulé', () {
    test(
      'fiche puis chapitres : une seule requête, User-Agent par défaut',
      () async {
        final requetes = <http.Request>[];
        final client = creerClientTest((requete) async {
          requetes.add(requete);
          return reponseHtml(htmlPotion);
        }, HorlogeFactice());
        final source = SourceScanManga(client);
        final fiche = await source.recupererFiche(urlPotion);
        final chapitres = await source.recupererChapitres(urlPotion);
        expect(fiche.titre.nom, 'Potion-danomi de Ikinobimasu!');
        expect(chapitres, hasLength(1));
        expect(requetes, hasLength(1));
        expect(requetes.single.url.toString(), urlPotion);
        expect(
          requetes.single.headers['User-Agent'],
          client.userAgentParDefaut,
        );
      },
    );

    test('la page est redemandée après la durée du cache', () async {
      var requetes = 0;
      var maintenant = DateTime.utc(2026, 11, 16, 12);
      final source = SourceScanManga(
        creerClientTest((requete) async {
          requetes++;
          return reponseHtml(htmlPotion);
        }, HorlogeFactice()),
        maintenant: () => maintenant,
      );
      await source.recupererChapitres(urlPotion);
      maintenant = maintenant.add(const Duration(minutes: 2));
      await source.recupererChapitres(urlPotion);
      expect(requetes, 2);
    });

    test('erreur HTTP : ErreurSource avec URL, code et type', () async {
      final source = SourceScanManga(
        creerClientTest(
          (requete) async => reponseHtml('Introuvable', statut: 404),
          HorlogeFactice(),
        ),
      );
      await expectLater(
        source.recupererChapitres(urlPotion),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.url, 'url', urlPotion)
              .having((e) => e.codeStatut, 'code', 404)
              .having((e) => e.typeDetecte, 'type', TypeSource.scanManga),
        ),
      );
    });

    test('page inattendue : ErreurSource avec extrait de la réponse', () async {
      final source = SourceScanManga(
        creerClientTest(
          (requete) async => reponseHtml('<html><body>Défi</body></html>'),
          HorlogeFactice(),
        ),
      );
      await expectLater(
        source.recupererFiche(urlPotion),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.typeDetecte, 'type', TypeSource.scanManga)
              .having((e) => e.extraitReponse, 'extrait', contains('Défi')),
        ),
      );
    });

    test('recupererContenu lève une ErreurSource sans requête', () async {
      var requetes = 0;
      final source = SourceScanManga(
        creerClientTest((requete) async {
          requetes++;
          return reponseHtml('');
        }, HorlogeFactice()),
      );
      const lecture =
          'https://www.scan-manga.com/lecture-en-ligne/'
          'Potion-danomi-de-Ikinobimasu-Chapitre-1-FR_116250.html';
      await expectLater(
        source.recupererContenu(lecture),
        throwsA(
          isA<ErreurSource>()
              .having((e) => e.url, 'url', lecture)
              .having(
                (e) => e.message,
                'message',
                contains('lisible uniquement sur Scan-Manga'),
              )
              .having((e) => e.typeDetecte, 'type', TypeSource.scanManga),
        ),
      );
      expect(requetes, 0);
    });

    test('rechercher renvoie une liste vide sans requête', () async {
      var requetes = 0;
      final source = SourceScanManga(
        creerClientTest((requete) async {
          requetes++;
          return reponseHtml('');
        }, HorlogeFactice()),
      );
      expect(await source.rechercher('potion'), isEmpty);
      expect(requetes, 0);
    });
  });
}
