// Tests de SourceMangaDex avec de VRAIES réponses de l'API, enregistrées le
// 2026-11-15 dans test/sources/exemples_json/ (aucun appel réseau ici) :
// - manga_fiche.json : GET /manga/12e28a8a-…?includes[]=cover_art&
//   includes[]=author&includes[]=artist
// - manga_flux_page1.json : GET /manga/12e28a8a-…/feed?limit=100&offset=0&…
//   (première page réelle, total = 217)
// - manga_recherche.json : GET /manga?title=Shinigami ni Sodaterareta&limit=5&
//   includes[]=cover_art
// - at_home_serveur.json : GET /at-home/server/ef4aae9e-…
// Enregistrées le 2026-11-16 (étape 6, User-Agent de l'application) :
// - couvertures_liste.json : GET /cover?manga[]=12e28a8a-…&limit=100&
//   offset=0&order[volume]=asc (10 couvertures, volumes 1 à 10)
// - manga_recherche_filtre.json : GET /manga?title=Shinigami ni Sodaterareta
//   &limit=5&includes[]=cover_art&includes[]=author&includes[]=artist&
//   contentRating[]=safe&contentRating[]=suggestive
// Enregistrée le 2026-11-16 (tâche R4, User-Agent de l'application) :
// - manga_flux_ruri_dragon.json : GET /manga/141609b6-…/feed?limit=100&
//   offset=0&order[chapter]=asc&order[createdAt]=asc&contentRating[]=(les 4)
//   &includeFuturePublishAt=0 (sans includeExternalUrl : total 324, dont
//   des chapitres MANGA Plus et VIZ avec externalUrl)
// Les pages 2 et 3 du flux ne sont pas enregistrées (dix requêtes au plus) :
// les tests de pagination les reconstruisent à partir des entrées réelles de
// la page 1, en gardant la structure exacte de l'enveloppe (result, response,
// data, limit, offset, total).
import 'dart:convert';

import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/couverture_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/source_mangadex.dart';
import 'package:bibliotheque_perso/sources/source_site.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

const String idReference = '12e28a8a-cbfe-4e12-bab8-b6fb0b9a59b4';
const String idChapitreReference = 'ef4aae9e-eea8-4931-8435-9f907870f4d8';
const String urlTitreReference =
    'https://mangadex.org/title/$idReference/'
    'shinigami-ni-sodaterareta-shoujo-wa-shikkoku-no-tsurugi-wo-mune-ni-idaku';

void main() {
  late HorlogeFactice horloge;
  late List<http.Request> requetes;

  setUp(() {
    horloge = HorlogeFactice();
    requetes = <http.Request>[];
  });

  /// Source dont l'API simulée répond avec [repondre].
  SourceMangaDex creerSource(
    http.Response Function(http.Request requete) repondre, {
    List<String> languesChapitres = const <String>[],
    bool qualiteReduite = false,
    int taillePageChapitres = taillePageMaxFluxMangaDex,
    List<String>? niveauxContenuRecherche,
  }) {
    return SourceMangaDex(
      creerClientTest((requete) async {
        requetes.add(requete);
        return repondre(requete);
      }, horloge),
      languesChapitres: languesChapitres,
      qualiteReduite: qualiteReduite,
      taillePageChapitres: taillePageChapitres,
      niveauxContenuRecherche: niveauxContenuRecherche,
    );
  }

  /// Enveloppe `ChapterList` (api.yaml) autour d'entrées réelles.
  String pageFlux(List<Object?> donnees, int limit, int offset, int total) {
    return jsonEncode(<String, Object?>{
      'result': 'ok',
      'response': 'collection',
      'data': donnees,
      'limit': limit,
      'offset': offset,
      'total': total,
    });
  }

  /// Copie des entrées réelles avec un `id` suffixé par [suffixe].
  List<Object?> avecIdsDistincts(List<Object?> donnees, String suffixe) {
    return <Object?>[
      for (final d in donnees)
        <String, Object?>{
          ...(d! as Map<String, Object?>),
          'id': '${(d as Map<String, Object?>)['id']}-$suffixe',
        },
    ];
  }

  group('Extraction des UUID', () {
    test('URL de titre avec ou sans nom lisible, avec ou sans www', () {
      expect(SourceMangaDex.extraireIdTitre(urlTitreReference), idReference);
      expect(
        SourceMangaDex.extraireIdTitre(
          'https://mangadex.org/title/$idReference',
        ),
        idReference,
      );
      expect(
        SourceMangaDex.extraireIdTitre(
          'https://www.mangadex.org/title/${idReference.toUpperCase()}/x?tab=art',
        ),
        idReference,
      );
    });

    test('URL de chapitre', () {
      expect(
        SourceMangaDex.extraireIdChapitre(
          'https://mangadex.org/chapter/$idChapitreReference',
        ),
        idChapitreReference,
      );
      expect(
        SourceMangaDex.extraireIdChapitre(
          'https://mangadex.org/chapter/$idChapitreReference/1',
        ),
        idChapitreReference,
      );
    });

    test('les URLs qui ne correspondent pas lèvent une ErreurSource', () {
      for (final url in <String>[
        'https://exemple.org/title/$idReference',
        'https://mangadex.org/chapter/$idReference',
        'https://mangadex.org/title/pas-un-uuid',
        'https://mangadex.org/title/',
        'https://api.mangadex.org/manga/$idReference',
        'ftp://mangadex.org/title/$idReference',
        idReference,
      ]) {
        expect(
          () => SourceMangaDex.extraireIdTitre(url),
          throwsA(isA<ErreurSource>()),
          reason: url,
        );
      }
      expect(
        () => SourceMangaDex.extraireIdChapitre(urlTitreReference),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('recupererFiche (titre de référence)', () {
    late SourceMangaDex source;

    setUp(() {
      source = creerSource(
        (requete) => reponseJson(lireExemple('exemples_json/manga_fiche.json')),
      );
    });

    test(
      'appelle GET /manga/{id} avec les includes et un User-Agent honnête',
      () async {
        await source.recupererFiche(urlTitreReference);
        final url = requetes.single.url;
        expect(url.host, 'api.mangadex.org');
        expect(url.path, '/manga/$idReference');
        expect(url.queryParametersAll['includes[]'], <String>[
          'cover_art',
          'author',
          'artist',
        ]);
        expect(requetes.single.headers['user-agent'], userAgentApplication);
      },
    );

    test(
      'titre principal, type, auteur, statut, couverture et résumé',
      () async {
        final fiche = await source.recupererFiche(urlTitreReference);
        final titre = fiche.titre;
        expect(
          titre.nom,
          'Shinigami ni Sodaterareta Shoujo wa Shikkoku no Tsurugi wo Mune ni '
          'Idaku',
        );
        expect(titre.urlTitre, 'https://mangadex.org/title/$idReference');
        expect(titre.typeTitre, TypeTitre.manga);
        expect(titre.auteur, 'Ayamine Maito');
        expect(titre.statut, 'ongoing');
        expect(
          titre.urlCouverture,
          'https://uploads.mangadex.org/covers/$idReference/'
          '2e9341cc-267d-487b-95e5-a00cd23a3c36.jpg',
        );
        // Pas de résumé français dans la réponse : l'anglais est choisi.
        expect(titre.resume, startsWith('Olivia is just a baby'));
        expect(titre.id, isNull);
        expect(titre.idSource, isNull);
      },
    );

    test('les 6 titres alternatifs, avec leur langue convertie', () async {
      final fiche = await source.recupererFiche(urlTitreReference);
      expect(fiche.titre.titresAlternatifs, const <TitreAlternatif>[
        TitreAlternatif(nom: '死神に育てられた少女は漆黒の剣を胸に抱く', langue: 'ja'),
        // `ja-ro` (romanisation) n'a pas de code ISO 639-1 : langue vide.
        TitreAlternatif(
          nom:
              'Shinigami ni Sodaterareta Shoujo wa Shikkoku no Tsurugi o Mune '
              'ni Idaku',
        ),
        TitreAlternatif(
          nom: "Death's Daughter and the Ebony Blade",
          langue: 'en',
        ),
        TitreAlternatif(
          nom: 'The Little Girl Raised by Death Holds the Sword of Death Tight',
          langue: 'en',
        ),
        TitreAlternatif(nom: '사신에게 길러진 소녀는 칠흑의 검을 가슴에 품는다', langue: 'ko'),
        TitreAlternatif(nom: '被死神抚养的少女怀抱漆黑之剑', langue: 'zh'),
      ]);
    });

    test('les 9 tags attendus, et aucun autre', () async {
      final fiche = await source.recupererFiche(urlTitreReference);
      expect(
        fiche.categories,
        unorderedEquals(<String>[
          'Gore',
          'Action',
          'Comedy',
          'Survival',
          'Magic',
          'Military',
          'Fantasy',
          'Supernatural',
          'Adaptation',
        ]),
      );
      expect(fiche.categories, hasLength(9));
    });

    test('une URL de titre invalide échoue sans requête', () async {
      await expectLater(
        source.recupererFiche('https://mangadex.org/chapter/$idReference'),
        throwsA(isA<ErreurSource>()),
      );
      expect(requetes, isEmpty);
    });
  });

  group('rechercher', () {
    test(
      'appelle GET /manga?title=… et renvoie le titre de référence',
      () async {
        final source = creerSource(
          (requete) =>
              reponseJson(lireExemple('exemples_json/manga_recherche.json')),
        );
        final titres = await source.rechercher('  Shinigami ni Sodaterareta ');
        final url = requetes.single.url;
        expect(url.path, '/manga');
        expect(url.queryParameters['title'], 'Shinigami ni Sodaterareta');
        expect(url.queryParametersAll['includes[]'], contains('cover_art'));
        expect(titres, hasLength(1));
        expect(
          titres.single.urlTitre,
          'https://mangadex.org/title/$idReference',
        );
        expect(titres.single.urlCouverture, isNotNull);
        expect(titres.single.titresAlternatifs, hasLength(6));
      },
    );

    test('une requête vide renvoie une liste vide sans appel réseau', () async {
      final source = creerSource((requete) => reponseJson('{}'));
      expect(await source.rechercher('   '), isEmpty);
      expect(requetes, isEmpty);
    });

    test(
      'aucun résultat : liste vide (cas légitime, pas une erreur)',
      () async {
        final source = creerSource(
          (requete) => reponseJson(
            '{"result":"ok","response":"collection","data":[],"limit":20,'
            '"offset":0,"total":0}',
          ),
        );
        expect(await source.rechercher('zzzz'), isEmpty);
      },
    );
  });

  group('Niveau de contenu (contentRating)', () {
    test('la fiche réelle donne niveauContenu = safe', () async {
      final source = creerSource(
        (requete) => reponseJson(lireExemple('exemples_json/manga_fiche.json')),
      );
      final fiche = await source.recupererFiche(urlTitreReference);
      expect(fiche.titre.niveauContenu, niveauContenuTousPublics);
    });

    test('les résultats de recherche portent aussi leur niveau', () async {
      final source = creerSource(
        (requete) =>
            reponseJson(lireExemple('exemples_json/manga_recherche.json')),
      );
      final titres = await source.rechercher('Shinigami');
      expect(titres.single.niveauContenu, 'safe');
    });

    test('valeur absente ou inconnue : null ; casse tolérée', () {
      expect(SourceMangaDex.niveauContenuDepuisApi(null), isNull);
      expect(SourceMangaDex.niveauContenuDepuisApi('inconnu'), isNull);
      expect(SourceMangaDex.niveauContenuDepuisApi(''), isNull);
      expect(
        SourceMangaDex.niveauContenuDepuisApi(' Pornographic '),
        niveauContenuPornographique,
      );
      for (final niveau in niveauxContenu) {
        expect(SourceMangaDex.niveauContenuDepuisApi(niveau), niveau);
      }
    });

    test("sans filtre : aucun contentRating[] (défaut de l'API)", () async {
      final source = creerSource(
        (requete) =>
            reponseJson(lireExemple('exemples_json/manga_recherche.json')),
      );
      await source.rechercher('Shinigami');
      expect(
        requetes.single.url.queryParametersAll.containsKey('contentRating[]'),
        isFalse,
      );
    });

    test(
      'avec filtre : contentRating[] envoyé (réponse réelle filtrée)',
      () async {
        final source = creerSource(
          (requete) => reponseJson(
            lireExemple('exemples_json/manga_recherche_filtre.json'),
          ),
          niveauxContenuRecherche: <String>['safe', 'suggestive', 'safe'],
        );
        final titres = await source.rechercher('Shinigami ni Sodaterareta');
        // Doublon retiré, ordre gardé.
        expect(
          requetes.single.url.queryParametersAll['contentRating[]'],
          <String>['safe', 'suggestive'],
        );
        expect(titres, hasLength(1));
        expect(titres.single.niveauContenu, 'safe');
      },
    );

    test('filtre vide : aucun résultat, sans appel réseau', () async {
      final source = creerSource(
        (requete) => reponseJson('{}'),
        niveauxContenuRecherche: const <String>[],
      );
      expect(await source.rechercher('Shinigami'), isEmpty);
      expect(requetes, isEmpty);
    });

    test('niveau inconnu : ArgumentError à la construction', () {
      expect(
        () => creerSource(
          (requete) => reponseJson('{}'),
          niveauxContenuRecherche: <String>['tout'],
        ),
        throwsArgumentError,
      );
    });

    test('le flux de chapitres demande toujours les quatre niveaux', () async {
      final source = creerSource(
        (requete) => reponseJson(pageFlux(<Object?>[], 500, 0, 0)),
        niveauxContenuRecherche: <String>['safe'],
      );
      await source.recupererChapitres(urlTitreReference);
      expect(
        requetes.single.url.queryParametersAll['contentRating[]'],
        niveauxContenu,
      );
    });
  });

  group('recupererCouvertures', () {
    test('GET /cover avec manga[], limit, offset et order[volume]', () async {
      final source = creerSource(
        (requete) =>
            reponseJson(lireExemple('exemples_json/couvertures_liste.json')),
      );
      await source.recupererCouvertures(urlTitreReference);
      final url = requetes.single.url;
      expect(url.host, 'api.mangadex.org');
      expect(url.path, '/cover');
      expect(url.queryParametersAll['manga[]'], <String>[idReference]);
      expect(url.queryParameters['limit'], '100');
      expect(url.queryParameters['offset'], '0');
      expect(url.queryParameters['order[volume]'], 'asc');
      expect(requetes.single.headers['user-agent'], userAgentApplication);
    });

    test("les 10 couvertures réelles, dans l'ordre des volumes", () async {
      final source = creerSource(
        (requete) =>
            reponseJson(lireExemple('exemples_json/couvertures_liste.json')),
      );
      final couvertures = await source.recupererCouvertures(urlTitreReference);
      expect(couvertures, hasLength(10));
      expect(couvertures.map((c) => c.volume).toList(), <String>[
        for (var i = 1; i <= 10; i++) '$i',
      ]);
      expect(couvertures.every((c) => c.langue == 'ja'), isTrue);
      expect(
        couvertures.first,
        const CouvertureSite(
          url:
              'https://uploads.mangadex.org/covers/$idReference/'
              'c4efd44d-b107-4634-a8e9-062e45b25253.jpg',
          urlMiniature:
              'https://uploads.mangadex.org/covers/$idReference/'
              'c4efd44d-b107-4634-a8e9-062e45b25253.jpg.512.jpg',
          volume: '1',
          langue: 'ja',
        ),
      );
      // Le volume 10 est la couverture principale de la fiche réelle.
      expect(
        couvertures.last.url,
        'https://uploads.mangadex.org/covers/$idReference/'
        '2e9341cc-267d-487b-95e5-a00cd23a3c36.jpg',
      );
    });

    test('SourceMangaDex est une SourceAvecCouvertures', () {
      final SourceSite source = creerSource((requete) => reponseJson('{}'));
      expect(source, isA<SourceAvecCouvertures>());
    });

    test('pagination reconstruite : 2 pages pour 150 couvertures', () async {
      final reelles =
          lireJsonExemple('couvertures_liste.json')['data']! as List<Object?>;
      Object? copie(int i) {
        final base = reelles[i % reelles.length]! as Map<String, Object?>;
        final attributs = base['attributes']! as Map<String, Object?>;
        return <String, Object?>{
          ...base,
          'id': 'c-$i',
          'attributes': <String, Object?>{
            ...attributs,
            'volume': '${i + 1}',
            'fileName': 'f$i.jpg',
          },
        };
      }

      final source = creerSource((requete) {
        final offset = int.parse(requete.url.queryParameters['offset']!);
        final fin = offset + 100 > 150 ? 150 : offset + 100;
        return reponseJson(
          pageFlux(
            <Object?>[for (var i = offset; i < fin; i++) copie(i)],
            100,
            offset,
            150,
          ),
        );
      });
      final couvertures = await source.recupererCouvertures(urlTitreReference);
      expect(couvertures, hasLength(150));
      expect(requetes.map((r) => r.url.queryParameters['offset']), <String>[
        '0',
        '100',
      ]);
    });

    test('volume et langue null ; fileName vide ignoré', () async {
      final source = creerSource(
        (requete) => reponseJson(
          pageFlux(
            <Object?>[
              <String, Object?>{
                'id': 'a',
                'type': 'cover_art',
                'attributes': <String, Object?>{
                  'volume': null,
                  'fileName': 'x.png',
                  'locale': null,
                },
                'relationships': <Object?>[],
              },
              <String, Object?>{
                'id': 'b',
                'type': 'cover_art',
                'attributes': <String, Object?>{'volume': '2', 'fileName': ''},
                'relationships': <Object?>[],
              },
            ],
            100,
            0,
            2,
          ),
        ),
      );
      final couvertures = await source.recupererCouvertures(urlTitreReference);
      expect(couvertures, hasLength(1));
      expect(couvertures.single.volume, isNull);
      expect(couvertures.single.langue, isNull);
      expect(couvertures.single.urlMiniature, endsWith('/x.png.512.jpg'));
    });

    test('aucune couverture : liste vide (pas une erreur)', () async {
      final source = creerSource(
        (requete) => reponseJson(pageFlux(<Object?>[], 100, 0, 0)),
      );
      expect(await source.recupererCouvertures(urlTitreReference), isEmpty);
    });

    test('URL de titre invalide : ErreurSource sans requête', () async {
      final source = creerSource((requete) => reponseJson('{}'));
      await expectLater(
        source.recupererCouvertures('https://exemple.org/title/x'),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.typeDetecte,
            'typeDetecte',
            TypeSource.mangaDex,
          ),
        ),
      );
      expect(requetes, isEmpty);
    });
  });

  group('recupererChapitres', () {
    test(
      'parcourt toutes les pages jusqu\'au total (première page réelle)',
      () async {
        final page1 = lireJsonExemple('manga_flux_page1.json');
        final donnees = page1['data']! as List<Object?>;
        expect(page1['total'], 217);
        final source = creerSource((requete) {
          final offset = int.parse(requete.url.queryParameters['offset']!);
          switch (offset) {
            case 0:
              return reponseJson(
                lireExemple('exemples_json/manga_flux_page1.json'),
              );
            // Entrées réelles réutilisées avec un id distinct par page, sinon
            // le dédoublonnage par UUID les retirerait.
            case 100:
              return reponseJson(
                pageFlux(avecIdsDistincts(donnees, 'p2'), 100, 100, 217),
              );
            case 200:
              return reponseJson(
                pageFlux(
                  avecIdsDistincts(donnees.sublist(0, 17), 'p3'),
                  100,
                  200,
                  217,
                ),
              );
          }
          return reponseJson(pageFlux(<Object?>[], 100, offset, 217));
        }, taillePageChapitres: 100);

        final chapitres = await source.recupererChapitres(urlTitreReference);
        expect(chapitres, hasLength(217));
        expect(requetes.map((r) => r.url.queryParameters['offset']), <String>[
          '0',
          '100',
          '200',
        ]);
        // Paramètres de api.yaml (feedParameters) envoyés à chaque page.
        final premiere = requetes.first.url;
        expect(premiere.path, '/manga/$idReference/feed');
        expect(premiere.queryParameters['limit'], '100');
        expect(premiere.queryParameters['order[chapter]'], 'asc');
        expect(premiere.queryParameters['order[createdAt]'], 'asc');
        expect(premiere.queryParametersAll['contentRating[]'], <String>[
          'safe',
          'suggestive',
          'erotica',
          'pornographic',
        ]);
        // Chapitres externes inclus (R4) : paramètre absent = tous.
        expect(
          premiere.queryParameters.containsKey('includeExternalUrl'),
          isFalse,
        );
        expect(
          premiere.queryParametersAll.containsKey('translatedLanguage[]'),
          isFalse,
        );
        // Une requête par seconde au plus vers api.mangadex.org.
        expect(horloge.attentes, <Duration>[
          const Duration(seconds: 1),
          const Duration(seconds: 1),
        ]);
      },
    );

    test('convertit numéro (double), langue, nom, URL et date', () async {
      final source = creerSource(
        (requete) => reponseJson(
          pageFlux(
            lireJsonExemple('manga_flux_page1.json')['data']! as List<Object?>,
            500,
            0,
            100,
          ),
        ),
      );
      final chapitres = await source.recupererChapitres(urlTitreReference);
      expect(chapitres, hasLength(100));

      final anglais = chapitres.firstWhere(
        (c) =>
            c.urlChapitre ==
            'https://mangadex.org/chapter/$idChapitreReference',
      );
      expect(anglais.numero, 1.0);
      expect(anglais.langue, 'en');
      expect(anglais.nom, 'Chapitre 1 : The Girl Raised by Death.');
      expect(anglais.datePublication, DateTime.utc(2019, 9, 7, 18, 57, 37));
      expect(anglais.idTitre, isNull);

      final sansTitre = chapitres.first;
      expect(sansTitre.nom, 'Chapitre 1');
      expect(sansTitre.langue, 'id');

      // pt-br → pt, es-la → es (on garde la langue, pas la région).
      expect(chapitres.where((c) => c.langue == 'pt'), isNotEmpty);
      expect(chapitres.where((c) => c.langue == 'es'), isNotEmpty);
      expect(chapitres.any((c) => c.langue.contains('-')), isFalse);
      // Chapitre intermédiaire réel (5.5 en français).
      expect(chapitres.where((c) => c.numero == 5.5), hasLength(1));
    });

    test('pagination reconstruite : 3 pages de 40 pour 100 chapitres', () async {
      final donnees =
          lireJsonExemple('manga_flux_page1.json')['data']! as List<Object?>;
      final source = creerSource((requete) {
        final offset = int.parse(requete.url.queryParameters['offset']!);
        final limit = int.parse(requete.url.queryParameters['limit']!);
        final fin = offset + limit > 100 ? 100 : offset + limit;
        return reponseJson(
          pageFlux(donnees.sublist(offset, fin), limit, offset, 100),
        );
      }, taillePageChapitres: 40);
      final chapitres = await source.recupererChapitres(urlTitreReference);
      expect(requetes, hasLength(3));
      expect(chapitres.map((c) => c.urlChapitre).toList(), <String>[
        for (final d in donnees)
          'https://mangadex.org/chapter/${(d! as Map<String, Object?>)['id']}',
      ]);
    });

    test('filtre par langue quand languesChapitres est renseigné', () async {
      final source = creerSource(
        (requete) => reponseJson(pageFlux(<Object?>[], 500, 0, 0)),
        languesChapitres: <String>['fr', 'pt-br'],
      );
      await source.recupererChapitres(urlTitreReference);
      expect(
        requetes.single.url.queryParametersAll['translatedLanguage[]'],
        <String>['fr', 'pt-br'],
      );
    });

    test('aucun chapitre : liste vide après une seule requête', () async {
      final source = creerSource(
        (requete) => reponseJson(pageFlux(<Object?>[], 500, 0, 0)),
      );
      expect(await source.recupererChapitres(urlTitreReference), isEmpty);
      expect(requetes, hasLength(1));
    });

    test('au-delà de 10 000 résultats : ErreurSource explicite', () async {
      final entree =
          (lireJsonExemple('manga_flux_page1.json')['data']! as List<Object?>)
              .first;
      final source = creerSource((requete) {
        final limit = int.parse(requete.url.queryParameters['limit']!);
        final offset = int.parse(requete.url.queryParameters['offset']!);
        return reponseJson(
          pageFlux(List<Object?>.filled(limit, entree), limit, offset, 25000),
        );
      }, taillePageChapitres: 5000);
      await expectLater(
        source.recupererChapitres(urlTitreReference),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('10000'),
          ),
        ),
      );
      // Le total de la première page suffit : une seule requête.
      expect(requetes, hasLength(1));
    });

    test('jamais offset + limit > 10 000 quand le total est juste sous le '
        'plafond', () async {
      final entree =
          (lireJsonExemple('manga_flux_page1.json')['data']! as List<Object?>)
                  .first!
              as Map<String, Object?>;
      var compteur = 0;
      final source = creerSource((requete) {
        final limit = int.parse(requete.url.queryParameters['limit']!);
        final offset = int.parse(requete.url.queryParameters['offset']!);
        final nombre = offset + limit > 10000 ? 10000 - offset : limit;
        // Ids distincts pour que le dédoublonnage ne retire rien.
        final page = <Object?>[
          for (var i = 0; i < nombre; i++)
            <String, Object?>{...entree, 'id': 'id-${compteur++}'},
        ];
        return reponseJson(pageFlux(page, limit, offset, 10000));
      }, taillePageChapitres: 3000);
      final chapitres = await source.recupererChapitres(urlTitreReference);
      expect(chapitres, hasLength(10000));
      for (final r in requetes) {
        final somme =
            int.parse(r.url.queryParameters['offset']!) +
            int.parse(r.url.queryParameters['limit']!);
        expect(somme, lessThanOrEqualTo(10000));
      }
      expect(requetes.last.url.queryParameters['limit'], '1000');
    });

    test('dédoublonne par UUID une entrée revenue sur deux pages', () async {
      final donnees =
          lireJsonExemple('manga_flux_page1.json')['data']! as List<Object?>;
      final source = creerSource((requete) {
        final offset = int.parse(requete.url.queryParameters['offset']!);
        // Page 2 décalée d'un cran (chapitre ajouté entre-temps) : sa
        // première entrée est la dernière de la page 1.
        return reponseJson(
          offset == 0
              ? pageFlux(donnees.sublist(0, 10), 10, 0, 20)
              : pageFlux(donnees.sublist(9, 19), 10, 10, 20),
        );
      }, taillePageChapitres: 10);
      final chapitres = await source.recupererChapitres(urlTitreReference);
      expect(chapitres, hasLength(19));
      expect(chapitres.map((c) => c.urlChapitre).toSet(), hasLength(19));
    });
  });

  group('recupererContenu', () {
    const urlChapitre = 'https://mangadex.org/chapter/$idChapitreReference';

    /// Réponse `ChapterResponse` (api.yaml) construite avec l'entrée réelle
    /// du chapitre dans manga_flux_page1.json (sans externalUrl).
    String reponseChapitre() {
      final donnees =
          lireJsonExemple('manga_flux_page1.json')['data']! as List<Object?>;
      return jsonEncode(<String, Object?>{
        'result': 'ok',
        'response': 'entity',
        'data': donnees.firstWhere(
          (d) => (d! as Map<String, Object?>)['id'] == idChapitreReference,
        ),
      });
    }

    /// API simulée : `GET /chapter/{id}` puis `GET /at-home/server/{id}`
    /// (réponse [corpsAtHome], par défaut at_home_serveur.json).
    http.Response Function(http.Request) apiChapitre([String? corpsAtHome]) {
      return (requete) => reponseJson(
        requete.url.path.startsWith('/chapter/')
            ? reponseChapitre()
            : corpsAtHome ?? lireExemple('exemples_json/at_home_serveur.json'),
      );
    }

    test(
      'construit baseUrl/data/hash/fichier pour les 36 pages réelles',
      () async {
        final source = creerSource(apiChapitre());
        final contenu = await source.recupererContenu(urlChapitre);
        // Chapitre inconnu de l'instance : GET /chapter/{id} vérifie
        // d'abord qu'il n'est pas externe.
        expect(requetes.map((r) => r.url.toString()), <String>[
          'https://api.mangadex.org/chapter/$idChapitreReference',
          'https://api.mangadex.org/at-home/server/$idChapitreReference',
        ]);
        expect(contenu.estTexte, isFalse);
        expect(contenu.urlReferer, isNull);
        expect(contenu.urlsImages, hasLength(36));
        expect(
          contenu.urlsImages.first,
          'https://cmdxd98sb0x3yprd.mangadex.network/data/'
          '8c1b7554f57083c33583051ef86a1fca/'
          'W1-74edca434fb491498aa4483a443771acf8b680e7a4ec8bb7482718e2d89958c7.png',
        );
      },
    );

    test('qualité réduite : data-saver et la liste dataSaver', () async {
      final source = creerSource(apiChapitre(), qualiteReduite: true);
      final contenu = await source.recupererContenu(urlChapitre);
      final attendu =
          ((lireJsonExemple('at_home_serveur.json')['chapter']!
                      as Map<String, Object?>)['dataSaver']!
                  as List<Object?>)
              .first;
      expect(
        contenu.urlsImages.first,
        'https://cmdxd98sb0x3yprd.mangadex.network/data-saver/'
        '8c1b7554f57083c33583051ef86a1fca/$attendu',
      );
    });

    test('deux appels at-home sont espacés de 1,5 s (40 par minute)', () async {
      final source = creerSource(apiChapitre());
      await source.recupererContenu(urlChapitre);
      final avant = horloge.attentes.length;
      await source.recupererContenu(urlChapitre);
      // Le second appel connaît déjà le chapitre : seul /at-home est
      // rappelé, et il attend le délai propre à ce point d'accès.
      expect(requetes, hasLength(3));
      final total = horloge.attentes
          .sublist(avant)
          .fold<Duration>(Duration.zero, (somme, d) => somme + d);
      expect(total, delaiMinimalAtHomeMangaDex);
    });

    test('aucune page : ErreurSource plutôt qu\'un contenu vide', () async {
      final source = creerSource(
        apiChapitre(
          '{"result":"ok","baseUrl":"https://uploads.mangadex.org",'
          '"chapter":{"hash":"abc","data":[],"dataSaver":[]}}',
        ),
      );
      await expectLater(
        source.recupererContenu(urlChapitre),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('Chapitres externes (Ruri Dragon, R4)', () {
    const idRuri = '141609b6-cf86-4266-904c-6648f389cdc9';
    const urlRuri = 'https://mangadex.org/title/$idRuri/ruri-dragon';
    // Entrées réelles de manga_flux_ruri_dragon.json.
    const idVizEn = '1f493000-615a-4fac-8347-3cbcc6ff8230';
    const idMangaPlusFr = '06ef8154-1f94-4091-926f-8e396f55733c';
    const idInterneEsLa = '969c2e97-e592-4570-9eff-42bb736b7d11';

    SourceMangaDex sourceRuri() => creerSource((requete) {
      if (requete.url.path.endsWith('/feed')) {
        // Page réelle (100 entrées, total 324) présentée comme complète.
        final page = lireJsonExemple('manga_flux_ruri_dragon.json');
        return reponseJson(
          pageFlux(page['data']! as List<Object?>, 500, 0, 100),
        );
      }
      return reponseJson(lireExemple('exemples_json/at_home_serveur.json'));
    });

    test('réponse réelle : total 324, chapitres externes et internes', () {
      final page = lireJsonExemple('manga_flux_ruri_dragon.json');
      expect(page['total'], 324);
      expect(page['data'], hasLength(100));
    });

    test('le flux ne filtre plus les chapitres externes ni vides', () async {
      final source = sourceRuri();
      await source.recupererChapitres(urlRuri);
      final parametres = requetes.single.url.queryParameters;
      expect(parametres.containsKey('includeExternalUrl'), isFalse);
      expect(parametres.containsKey('includeEmptyPages'), isFalse);
      expect(parametres['includeFuturePublishAt'], '0');
    });

    test('chaque chapitre externe reçoit son urlExterne', () async {
      final chapitres = await sourceRuri().recupererChapitres(urlRuri);
      expect(chapitres, hasLength(100));
      Chapitre parId(String id) => chapitres.firstWhere(
        (c) => c.urlChapitre == 'https://mangadex.org/chapter/$id',
      );
      // Externe avec pages = 0 : gardé (includeEmptyPages ne l'exclut plus).
      final viz = parId(idVizEn);
      expect(viz.urlExterne, 'https://viz.com/shonenjump/-/chapter/24786');
      expect(viz.numero, 1.0);
      expect(viz.langue, 'en');
      expect(
        parId(idMangaPlusFr).urlExterne,
        'https://mangaplus.shueisha.co.jp/viewer/7001938',
      );
      // Chapitre hébergé sur MangaDex : pas de lien externe.
      final interne = parId(idInterneEsLa);
      expect(interne.urlExterne, isNull);
      expect(interne.langue, 'es');
      // Dans la page réelle : 96 externes, 4 internes.
      expect(chapitres.where((c) => c.urlExterne != null), hasLength(96));
    });

    test('chapitre vide et non externe : ignoré', () async {
      final page = lireJsonExemple('manga_flux_ruri_dragon.json');
      final interne =
          (page['data']! as List<Object?>).firstWhere(
                (d) => (d! as Map<String, Object?>)['id'] == idInterneEsLa,
              )!
              as Map<String, Object?>;
      final vide = <String, Object?>{
        ...interne,
        'id': '$idInterneEsLa-vide',
        'attributes': <String, Object?>{
          ...(interne['attributes']! as Map<String, Object?>),
          'pages': 0,
        },
      };
      final source = creerSource(
        (requete) => reponseJson(pageFlux(<Object?>[interne, vide], 500, 0, 2)),
      );
      final chapitres = await source.recupererChapitres(urlRuri);
      expect(chapitres.map((c) => c.urlChapitre), <String>[
        'https://mangadex.org/chapter/$idInterneEsLa',
      ]);
    });

    group('externalUrl invalide : flux conservé, lien MangaDex', () {
      late List<String?> journal;
      late DebugPrintCallback debugPrintOriginal;

      setUp(() {
        journal = <String?>[];
        debugPrintOriginal = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) =>
            journal.add(message);
      });

      tearDown(() => debugPrint = debugPrintOriginal);

      /// Entrée réelle VIZ du flux de Ruri Dragon, `externalUrl` remplacé.
      Map<String, Object?> entreeAvecUrl(Object? externalUrl) {
        final page = lireJsonExemple('manga_flux_ruri_dragon.json');
        final viz =
            (page['data']! as List<Object?>).firstWhere(
                  (d) => (d! as Map<String, Object?>)['id'] == idVizEn,
                )!
                as Map<String, Object?>;
        return <String, Object?>{
          ...viz,
          'attributes': <String, Object?>{
            ...(viz['attributes']! as Map<String, Object?>),
            'externalUrl': externalUrl,
          },
        };
      }

      final cas = <String, Object?>{
        'schéma non http(s)': 'javascript:alert(1)',
        'ftp': 'ftp://exemple.com/ch/1',
        'sans hôte': 'https:///chemin?jeton=secret',
        'mal formée': 'http://[::1',
        'trop longue': 'https://exemple.com/${'a' * 600}?jeton=secret',
        'pas un texte': 42,
      };
      for (final MapEntry(key: nom, value: valeur) in cas.entries) {
        test('$nom : chapitre externe vers sa page MangaDex', () async {
          final source = creerSource(
            (requete) => reponseJson(
              pageFlux(<Object?>[entreeAvecUrl(valeur)], 500, 0, 1),
            ),
          );
          final chapitres = await source.recupererChapitres(urlRuri);
          expect(chapitres, hasLength(1));
          expect(
            chapitres.single.urlExterne,
            'https://mangadex.org/chapter/$idVizEn',
          );
          expect(
            chapitres.single.urlChapitre,
            'https://mangadex.org/chapter/$idVizEn',
          );
          // Journalisé avec l'identifiant, jamais avec la valeur reçue.
          expect(journal, hasLength(1));
          expect(journal.single, contains(idVizEn));
          expect(journal.single, isNot(contains('secret')));
          expect(journal.single, isNot(contains('javascript')));
        });
      }

      test('une entrée abîmée ne bloque pas les autres chapitres', () async {
        final page = lireJsonExemple('manga_flux_ruri_dragon.json');
        final donnees = <Object?>[
          for (final d in page['data']! as List<Object?>)
            (d! as Map<String, Object?>)['id'] == idVizEn
                ? entreeAvecUrl('pas une url')
                : d,
        ];
        final source = creerSource(
          (requete) => reponseJson(pageFlux(donnees, 500, 0, 100)),
        );
        final chapitres = await source.recupererChapitres(urlRuri);
        expect(chapitres, hasLength(100));
        expect(
          chapitres
              .firstWhere(
                (c) => c.urlChapitre == 'https://mangadex.org/chapter/$idVizEn',
              )
              .urlExterne,
          'https://mangadex.org/chapter/$idVizEn',
        );
        expect(
          chapitres
              .firstWhere(
                (c) =>
                    c.urlChapitre ==
                    'https://mangadex.org/chapter/$idMangaPlusFr',
              )
              .urlExterne,
          'https://mangaplus.shueisha.co.jp/viewer/7001938',
        );
      });

      test('recupererContenu : chapitre traité comme externe, sans '
          '/at-home', () async {
        final source = creerSource(
          (requete) => reponseJson(
            jsonEncode(<String, Object?>{
              'result': 'ok',
              'response': 'entity',
              'data': entreeAvecUrl('ftp://exemple.com/ch/1'),
            }),
          ),
        );
        await expectLater(
          source.recupererContenu('https://mangadex.org/chapter/$idVizEn'),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.message,
              'message',
              contains('hébergé sur un site externe'),
            ),
          ),
        );
        expect(requetes.map((r) => r.url.path), <String>[
          '/chapter/$idVizEn',
        ]);
      });

      test('vide ou null : chapitre interne, rien de journalisé', () async {
        for (final valeur in <Object?>['', '   ', null]) {
          final source = creerSource(
            (requete) => reponseJson(
              pageFlux(<Object?>[entreeAvecUrl(valeur)], 500, 0, 1),
            ),
          );
          final chapitres = await source.recupererChapitres(urlRuri);
          // pages = 0 et pas d'externalUrl : illisible, retiré du flux.
          expect(chapitres, isEmpty, reason: '$valeur');
        }
        expect(journal, isEmpty);
      });
    });

    test(
      'recupererContenu après le flux : erreur claire, sans /at-home',
      () async {
        final source = sourceRuri();
        await source.recupererChapitres(urlRuri);
        await expectLater(
          source.recupererContenu(
            'https://mangadex.org/chapter/$idMangaPlusFr',
          ),
          throwsA(
            isA<ErreurSource>()
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('hébergé sur un site externe'),
                    contains('MANGA Plus'),
                  ),
                )
                .having(
                  (e) => e.typeDetecte,
                  'typeDetecte',
                  TypeSource.mangaDex,
                ),
          ),
        );
        // Seule la requête du flux : ni /chapter ni /at-home.
        expect(requetes, hasLength(1));
      },
    );

    test('recupererContenu sans flux : GET /chapter puis erreur, sans '
        '/at-home', () async {
      final page = lireJsonExemple('manga_flux_ruri_dragon.json');
      final entree = (page['data']! as List<Object?>).firstWhere(
        (d) => (d! as Map<String, Object?>)['id'] == idVizEn,
      );
      final source = creerSource(
        (requete) => reponseJson(
          jsonEncode(<String, Object?>{
            'result': 'ok',
            'response': 'entity',
            'data': entree,
          }),
        ),
      );
      await expectLater(
        source.recupererContenu('https://mangadex.org/chapter/$idVizEn'),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('hébergé sur un site externe (VIZ'),
          ),
        ),
      );
      expect(requetes.map((r) => r.url.path), <String>['/chapter/$idVizEn']);
    });

    test(
      'chapitre interne du même flux : /at-home appelé directement',
      () async {
        final source = sourceRuri();
        await source.recupererChapitres(urlRuri);
        final contenu = await source.recupererContenu(
          'https://mangadex.org/chapter/$idInterneEsLa',
        );
        expect(contenu.urlsImages, isNotEmpty);
        expect(requetes.last.url.path, '/at-home/server/$idInterneEsLa');
        expect(requetes, hasLength(2));
      },
    );

    test('estServeurMangaDex : site, sous-domaines et nœuds @Home (E10)', () {
      for (final hote in <String>[
        'mangadex.org',
        'www.mangadex.org',
        'uploads.mangadex.org',
        'api.mangadex.org',
        'UPLOADS.MangaDex.org',
        'abcdef.xyz123.mangadex.network',
        'api.mangadex.network',
      ]) {
        expect(SourceMangaDex.estServeurMangaDex(hote), isTrue, reason: hote);
      }
      for (final hote in <String>[
        'mangadex.org.exemple.com',
        'fauxmangadex.org',
        'mangaplus.shueisha.co.jp',
        '',
      ]) {
        expect(SourceMangaDex.estServeurMangaDex(hote), isFalse, reason: hote);
      }
      // estHoteMangaDex reste limité au site public.
      expect(SourceMangaDex.estHoteMangaDex('uploads.mangadex.org'), isFalse);
    });

    test('nomSiteExterne : nom lisible du site', () {
      expect(
        SourceMangaDex.nomSiteExterne(
          'https://mangaplus.shueisha.co.jp/viewer/7001938',
        ),
        'MANGA Plus',
      );
      expect(
        SourceMangaDex.nomSiteExterne(
          'https://viz.com/shonenjump/-/chapter/24786',
        ),
        'VIZ',
      );
      expect(
        SourceMangaDex.nomSiteExterne('https://www.Exemple-Editeur.com/ch/1'),
        'exemple-editeur.com',
      );
      expect(SourceMangaDex.nomSiteExterne('pas une url'), 'pas une url');
    });
  });

  group('Réponses invalides', () {
    test(
      'JSON invalide : ErreurSource avec FormatException en cause',
      () async {
        final source = creerSource((requete) => reponseJson('{"result":"ok",'));
        await expectLater(
          source.recupererFiche(urlTitreReference),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.cause,
              'cause',
              isA<FormatException>(),
            ),
          ),
        );
      },
    );

    test('JSON qui n\'est pas un objet : ErreurSource', () async {
      final source = creerSource((requete) => reponseJson('[1, 2]'));
      await expectLater(
        source.recupererChapitres(urlTitreReference),
        throwsA(isA<ErreurSource>()),
      );
    });

    test(
      'structure inattendue (data n\'est pas une liste) : ErreurSource',
      () async {
        final source = creerSource(
          (requete) => reponseJson('{"result":"ok","data":{},"total":0}'),
        );
        await expectLater(
          source.recupererChapitres(urlTitreReference),
          throwsA(
            isA<ErreurSource>().having(
              (e) => e.message,
              'message',
              contains('data'),
            ),
          ),
        );
      },
    );

    test('result = error : ErreurSource avec le détail de l\'API', () async {
      final source = creerSource(
        (requete) => reponseJson(
          '{"result":"error","errors":[{"id":"x","status":400,'
          '"title":"Bad Request","detail":"limit invalide"}]}',
        ),
      );
      await expectLater(
        source.rechercher('x'),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.message,
            'message',
            contains('limit invalide'),
          ),
        ),
      );
    });

    test(
      'titre introuvable (404) : ErreurSource sans nouvelle tentative',
      () async {
        final source = creerSource(
          (requete) => reponseJson(
            '{"result":"error","errors":[{"status":404,"title":"Not found"}]}',
            statut: 404,
          ),
        );
        await expectLater(
          source.recupererFiche(urlTitreReference),
          throwsA(isA<ErreurSource>().having((e) => e.codeStatut, 'code', 404)),
        );
        expect(requetes, hasLength(1));
      },
    );

    test(
      '404 : type MangaDex et extrait de la réponse pour le rapport',
      () async {
        final source = creerSource(
          (requete) => reponseJson(
            '{"result":"error","errors":[{"status":404,"title":"Not found"}]}',
            statut: 404,
          ),
        );
        await expectLater(
          source.recupererFiche(urlTitreReference),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.typeDetecte, 'type', TypeSource.mangaDex)
                .having(
                  (e) => e.extraitReponse,
                  'extrait',
                  contains('Not found'),
                ),
          ),
        );
      },
    );

    test(
      'structure inattendue (200) : extrait du début de la réponse',
      () async {
        final source = creerSource(
          (requete) => reponseJson('{"result":"ok","data":{},"total":0}'),
        );
        await expectLater(
          source.recupererChapitres(urlTitreReference),
          throwsA(
            isA<ErreurSource>()
                .having((e) => e.typeDetecte, 'type', TypeSource.mangaDex)
                .having(
                  (e) => e.extraitReponse,
                  'extrait',
                  '{"result":"ok","data":{},"total":0}',
                ),
          ),
        );
      },
    );
  });

  group('Conversions', () {
    test('codes de langue MangaDex vers ISO 639-1', () {
      expect(SourceMangaDex.convertirCodeLangue('en'), 'en');
      expect(SourceMangaDex.convertirCodeLangue('pt-br'), 'pt');
      expect(SourceMangaDex.convertirCodeLangue('zh-hk'), 'zh');
      expect(SourceMangaDex.convertirCodeLangue('ja-ro'), '');
      expect(SourceMangaDex.convertirCodeLangue('ko-ro'), '');
      expect(SourceMangaDex.convertirCodeLangue('xyz'), '');
    });

    test('type déduit de la langue d\'origine', () {
      expect(SourceMangaDex.typeDepuisLangueOriginale('ja'), TypeTitre.manga);
      expect(SourceMangaDex.typeDepuisLangueOriginale('ko'), TypeTitre.manhwa);
      expect(SourceMangaDex.typeDepuisLangueOriginale('zh'), TypeTitre.manhua);
      expect(
        SourceMangaDex.typeDepuisLangueOriginale('zh-hk'),
        TypeTitre.manhua,
      );
      expect(SourceMangaDex.typeDepuisLangueOriginale('fr'), TypeTitre.autre);
      expect(SourceMangaDex.typeDepuisLangueOriginale(null), TypeTitre.autre);
    });

    test('numéros de chapitre', () {
      expect(SourceMangaDex.convertirNumero('10.5'), 10.5);
      expect(SourceMangaDex.convertirNumero('12a'), 12);
      expect(SourceMangaDex.convertirNumero(null), 0);
      expect(SourceMangaDex.convertirNumero('extra'), 0);
      expect(SourceMangaDex.convertirNumero('10,5'), 10.5);
    });

    test('numéros non finis ou en notation scientifique : 0', () {
      for (final texte in <String>[
        'NaN',
        'Infinity',
        '-Infinity',
        '1e3',
        '2.5E-1',
      ]) {
        expect(SourceMangaDex.convertirNumero(texte), 0, reason: texte);
      }
    });

    test('variantes régionales des langues de chapitres', () {
      expect(SourceMangaDex.languesApiDepuisIso('pt'), <String>['pt', 'pt-br']);
      expect(SourceMangaDex.languesApiDepuisIso('es'), <String>['es', 'es-la']);
      expect(SourceMangaDex.languesApiDepuisIso('zh'), <String>['zh', 'zh-hk']);
      expect(SourceMangaDex.languesApiDepuisIso('FR'), <String>['fr']);
      expect(SourceMangaDex.languesApiDepuisIso(''), isEmpty);
    });

    test('préférence « fr,en » découpée en codes ISO dans l\'ordre', () {
      expect(SourceMangaDex.languesIsoDepuisPreference('fr,en'), <String>[
        'fr',
        'en',
      ]);
      // Espaces ignorés, codes vides ignorés, doublons et casse ramenés.
      expect(
        SourceMangaDex.languesIsoDepuisPreference(' en , ,FR,en,fr '),
        <String>['en', 'fr'],
      );
      expect(SourceMangaDex.languesIsoDepuisPreference(''), isEmpty);
      expect(SourceMangaDex.languesIsoDepuisPreference(' , ,'), isEmpty);
    });

    test('préférence de langues vers codes translatedLanguage[]', () {
      expect(SourceMangaDex.languesDepuisPreference('fr,en'), <String>[
        'fr',
        'en',
      ]);
      expect(SourceMangaDex.languesDepuisPreference('pt,en'), <String>[
        'pt',
        'pt-br',
        'en',
      ]);
      expect(SourceMangaDex.languesDepuisPreference('fr'), <String>['fr']);
      expect(SourceMangaDex.languesDepuisPreference('pt,PT, pt'), <String>[
        'pt',
        'pt-br',
      ]);
      expect(SourceMangaDex.languesDepuisPreference(''), isEmpty);
    });
  });
}
