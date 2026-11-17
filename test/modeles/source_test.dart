import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = Source(
    id: 1,
    nom: 'MangaDex',
    urlBase: 'https://mangadex.org',
    typeSource: TypeSource.mangaDex,
    langueParDefaut: 'en',
  );

  test('versMap puis depuisMap redonne la même source', () {
    final map = source.versMap();
    expect(map['type_source'], 'mangaDex');
    expect(map['est_active'], 1);
    expect(Source.depuisMap(map), source);
  });

  test('tous les types de source font l\'aller-retour', () {
    for (final type in TypeSource.values) {
      final copie = source.copierAvec(typeSource: type);
      expect(Source.depuisMap(copie.versMap()).typeSource, type);
    }
  });

  test('le type scanManga est stocké sous son nom', () {
    expect(TypeSource.values, contains(TypeSource.scanManga));
    final map = source.copierAvec(typeSource: TypeSource.scanManga).versMap();
    expect(map['type_source'], 'scanManga');
    expect(Source.depuisMap(map).typeSource, TypeSource.scanManga);
  });

  test('le type webtoons est stocké sous son nom', () {
    expect(TypeSource.values, contains(TypeSource.webtoons));
    final map = source.copierAvec(typeSource: TypeSource.webtoons).versMap();
    expect(map['type_source'], 'webtoons');
    expect(Source.depuisMap(map).typeSource, TypeSource.webtoons);
  });

  test('copierAvec, == et hashCode sont cohérents', () {
    final inactive = source.copierAvec(estActive: false);
    expect(inactive.estActive, isFalse);
    expect(inactive, isNot(source));
    expect(source.copierAvec(), source);
    expect(source.copierAvec().hashCode, source.hashCode);
  });

  test('un type de source inconnu lève une ErreurBaseDeDonnees', () {
    final map = source.versMap()..['type_source'] = 'wordpress';
    expect(() => Source.depuisMap(map), throwsA(isA<ErreurBaseDeDonnees>()));
  });

  test('un booléen différent de 0 ou 1 lève une ErreurBaseDeDonnees', () {
    final map = source.versMap()..['est_active'] = 2;
    expect(() => Source.depuisMap(map), throwsA(isA<ErreurBaseDeDonnees>()));
  });

  test('toString mentionne le type', () {
    expect(source.toString(), contains('mangaDex'));
  });
}
