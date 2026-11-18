import 'dart:async';

import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/source_mangathemesia.dart';
import 'package:bibliotheque_perso/sources/source_webtoons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

/// Branchement du journal dans `lib/sources/` : `ClientHttpPoli` (catégorie
/// `reseau`) et adaptateurs (catégorie `sources`). Aucun appel réseau.
void main() {
  late JournalMemoire journal;
  late HorlogeFactice horloge;

  setUp(() {
    journal = JournalMemoire();
    Journal.actuel = journal;
    horloge = HorlogeFactice();
  });

  tearDown(() {
    Journal.actuel = const JournalSilencieux();
  });

  List<EntreeJournal> entreesDe(String categorie) =>
      journal.entrees.where((e) => e.categorie == categorie).toList();

  group('ClientHttpPoli', () {
    test('une requête réussie = une ligne info : méthode, URL, code, taille, '
        'durée, essais', () async {
      final client = creerClientTest(
        (_) async => http.Response('<p>secret du corps</p>', 200),
        horloge,
      );
      await client.recupererTexte(Uri.parse('https://exemple.org/page'));

      final lignes = entreesDe(CategorieJournal.reseau);
      expect(lignes, hasLength(1));
      final ligne = lignes.single;
      expect(ligne.niveau, NiveauJournal.info);
      expect(ligne.message, contains('GET https://exemple.org/page'));
      expect(ligne.message, contains('HTTP 200'));
      expect(ligne.message, contains('22 o'));
      expect(ligne.message, contains(' ms'));
      expect(ligne.message, contains('1 essai'));
      // Jamais le corps de la réponse.
      expect(ligne.message, isNot(contains('secret du corps')));
    });

    test("les données sensibles de l'URL sont masquées", () async {
      final client = creerClientTest(
        (_) async => http.Response('ok', 200),
        horloge,
      );
      await client.recupererOctets(
        Uri.parse(
          'https://abc.mangadex.network/jetonSession123/data/hash/1.jpg'
          '?token=motdepasse',
        ),
      );
      final message = journal.entrees.single.message;
      expect(message, isNot(contains('jetonSession123')));
      expect(message, isNot(contains('motdepasse')));
      expect(message, contains(valeurMasqueeJournal));
    });

    test('attente de politesse en débogage', () async {
      final client = creerClientTest(
        (_) async => http.Response('ok', 200),
        horloge,
      );
      await client.recupererTexte(Uri.parse('https://exemple.org/a'));
      await client.recupererTexte(Uri.parse('https://exemple.org/b'));
      final debogage = journal.entrees
          .where((e) => e.niveau == NiveauJournal.debogage)
          .toList();
      expect(debogage, hasLength(1));
      expect(debogage.single.message, contains('exemple.org'));
      expect(
        entreesDe(CategorieJournal.reseau)
            .where((e) => e.niveau == NiveauJournal.info),
        hasLength(2),
      );
    });

    test('429 avec Retry-After puis succès : avertissements puis une ligne '
        'info avec 2 essais', () async {
      var appel = 0;
      final client = creerClientTest((_) async {
        appel++;
        return appel == 1
            ? http.Response(
                'trop',
                429,
                headers: <String, String>{'retry-after': '3'},
              )
            : http.Response('ok', 200);
      }, horloge);
      await client.recupererTexte(Uri.parse('https://exemple.org/a'));

      final avertissements = journal.entrees
          .where((e) => e.niveau == NiveauJournal.avertissement)
          .map((e) => e.message)
          .toList();
      expect(avertissements, hasLength(2));
      expect(avertissements.first, contains('429'));
      expect(avertissements.first, contains('3000 ms'));
      expect(avertissements.last, contains('nouvel essai 2/3'));
      final info = journal.entrees.singleWhere(
        (e) => e.niveau == NiveauJournal.info,
      );
      expect(info.message, contains('2 essais'));
    });

    test('délais dépassés : avertissements puis une erreur finale, sans '
        "l'objet ErreurSource joint", () async {
      final client = creerClientTest(
        (_) => Completer<http.Response>().future,
        horloge,
        delaiExpiration: const Duration(milliseconds: 10),
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/lent')),
        throwsA(isA<ErreurSource>()),
      );
      final erreurs = journal.entrees
          .where((e) => e.niveau == NiveauJournal.erreur)
          .toList();
      expect(erreurs, hasLength(1));
      expect(erreurs.single.message, contains('délai dépassé'));
      expect(erreurs.single.message, contains('3 essais'));
      expect(erreurs.single.erreur, isNot(isA<ErreurSource>()));
      expect(
        journal.entrees.where((e) => e.message.contains('délai dépassé (')),
        hasLength(3),
      );
    });

    test("404 : un avertissement, sans l'extrait de la page", () async {
      final client = creerClientTest(
        (_) async => http.Response('Page introuvable pour Jean Dupont', 404),
        horloge,
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/absent')),
        throwsA(isA<ErreurSource>()),
      );
      final ligne = journal.entrees.single;
      expect(ligne.niveau, NiveauJournal.avertissement);
      expect(ligne.message, contains('HTTP 404'));
      expect(ligne.message, isNot(contains('Jean Dupont')));
    });

    test('page anti-robot : une erreur', () async {
      final client = creerClientTest(
        (_) async => http.Response(
          '<html><title>Just a moment...</title>challenge-platform</html>',
          403,
        ),
        horloge,
      );
      await expectLater(
        client.recupererTexte(Uri.parse('https://exemple.org/')),
        throwsA(isA<ErreurSource>()),
      );
      final ligne = journal.entrees.single;
      expect(ligne.niveau, NiveauJournal.erreur);
      expect(ligne.message, contains('anti-robot'));
      expect(ligne.message, isNot(contains('Just a moment')));
    });

    test(
      "image refusée : erreur avec le type détecté, sans l'extrait",
      () async {
        final client = creerClientTest(
          (_) async => http.Response(
            '<html><body>Bonjour Jean Dupont</body></html>',
            200,
            headers: <String, String>{'content-type': 'text/html'},
          ),
          horloge,
        );
        await expectLater(
          client.recupererOctets(
            Uri.parse('https://exemple.org/1.jpg'),
            exigerImage: true,
          ),
          throwsA(isA<ErreurSource>()),
        );
        final erreur = journal.entrees.singleWhere(
          (e) => e.niveau == NiveauJournal.erreur,
        );
        expect(erreur.message, contains('image refusée'));
        expect(erreur.message, contains('text/html'));
        expect(erreur.message, isNot(contains('Jean Dupont')));
      },
    );
  });

  group('Adaptateurs', () {
    const urlTitre =
        'https://mangareader.themesia.com/manga/kaze-no-doragon-raida/';
    final htmlFiche = lireExemple('exemples_html/mangathemesia_fiche.html');

    SourceMangaThemesia creerSource(
      Future<http.Response> Function(http.Request) gestionnaire,
    ) {
      return SourceMangaThemesia(
        creerClientTest(gestionnaire, horloge),
        urlBase: 'https://mangareader.themesia.com',
        maintenant: horloge.lire,
      );
    }

    test('fiche et chapitres lus : une ligne info chacun', () async {
      final source = creerSource(
        (_) async => http.Response(
          htmlFiche,
          200,
          headers: <String, String>{'content-type': 'text/html; charset=UTF-8'},
        ),
      );
      final fiche = await source.recupererFiche(urlTitre);
      final chapitres = await source.recupererChapitres(urlTitre);

      final lignes = entreesDe(CategorieJournal.sources);
      expect(lignes, hasLength(2));
      expect(lignes.every((e) => e.niveau == NiveauJournal.info), isTrue);
      expect(lignes.first.message, contains('MangaThemesia'));
      expect(lignes.first.message, contains(fiche.titre.nom));
      expect(lignes.last.message, contains('${chapitres.length} chapitre'));
    });

    test('échec de structure : un avertissement court', () async {
      final source = creerSource(
        (_) async => http.Response('<html><body>rien</body></html>', 200),
      );
      await expectLater(
        source.recupererFiche(urlTitre),
        throwsA(isA<ErreurSource>()),
      );
      final ligne = entreesDe(CategorieJournal.sources).single;
      expect(ligne.niveau, NiveauJournal.avertissement);
      expect(ligne.message, contains('échec'));
    });

    test(
      'épisode WEBTOON protégé : un avertissement, aucune requête',
      () async {
        var requetes = 0;
        final source = SourceWebtoons(
          creerClientTest((_) async {
            requetes++;
            return http.Response('', 200);
          }, horloge),
        );
        await expectLater(
          source.recupererContenu(
            'https://www.webtoons.com/fr/a/b/episode-1/viewer?title_no=1'
            '&episode_no=1',
          ),
          throwsA(isA<ErreurSource>()),
        );
        expect(requetes, 0);
        final ligne = entreesDe(CategorieJournal.sources).single;
        expect(ligne.niveau, NiveauJournal.avertissement);
        expect(ligne.message, contains('protégé'));
      },
    );
  });
}
