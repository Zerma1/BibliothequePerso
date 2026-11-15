import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:bibliotheque_perso/sources/source_mangadex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

void main() {
  final fabrique = FabriqueSources(
    creerClientTest(
      (requete) async => http.Response('', 200),
      HorlogeFactice(),
    ),
  );

  test('une source MangaDex donne un SourceMangaDex filtré sur sa langue', () {
    final adaptateur = fabrique.creer(
      const Source(
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
        langueParDefaut: 'fr',
      ),
    );
    expect(adaptateur, isA<SourceMangaDex>());
    expect((adaptateur as SourceMangaDex).languesChapitres, <String>['fr']);
  });

  test('pt, es et zh incluent leurs variantes régionales', () {
    for (final cas in <String, List<String>>{
      'pt': <String>['pt', 'pt-br'],
      'es': <String>['es', 'es-la'],
      'zh': <String>['zh', 'zh-hk'],
    }.entries) {
      final adaptateur = fabrique.creer(
        Source(
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
          langueParDefaut: cas.key,
        ),
      );
      expect(
        (adaptateur as SourceMangaDex).languesChapitres,
        cas.value,
        reason: cas.key,
      );
    }
  });

  test('sans langue par défaut, toutes les langues sont demandées', () {
    final adaptateur = fabrique.creer(
      const Source(
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
      ),
    );
    expect((adaptateur as SourceMangaDex).languesChapitres, isEmpty);
  });

  test('les types sans adaptateur (étape 6) lèvent une ErreurSource', () {
    for (final type in <TypeSource>[
      TypeSource.madara,
      TypeSource.mangaThemesia,
      TypeSource.generique,
    ]) {
      expect(
        () => fabrique.creer(
          Source(nom: 'Site', urlBase: 'https://exemple.org', typeSource: type),
        ),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.url,
            'url',
            'https://exemple.org',
          ),
        ),
      );
    }
  });
}
