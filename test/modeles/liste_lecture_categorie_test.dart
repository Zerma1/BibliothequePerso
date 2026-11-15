import 'package:bibliotheque_perso/modeles/categorie.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/liste_lecture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ListeLecture', () {
    const favoris = ListeLecture(
      id: 1,
      nom: nomListeFavoris,
      estSysteme: true,
      ordre: ordreListeFavoris,
    );

    test('versMap puis depuisMap redonne la même liste', () {
      final map = favoris.versMap();
      expect(map['est_systeme'], 1);
      expect(ListeLecture.depuisMap(map), favoris);
    });

    test('copierAvec, == et hashCode sont cohérents', () {
      expect(favoris.copierAvec(), favoris);
      expect(favoris.copierAvec().hashCode, favoris.hashCode);
      expect(favoris.copierAvec(nom: 'Autre'), isNot(favoris));
    });

    test('un ordre manquant lève une ErreurBaseDeDonnees', () {
      expect(
        () => ListeLecture.depuisMap(favoris.versMap()..remove('ordre')),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('toString mentionne le nom', () {
      expect(favoris.toString(), contains(nomListeFavoris));
    });
  });

  group('Categorie', () {
    test('normaliserNom met en minuscules et retire les espaces autour', () {
      expect(Categorie.normaliserNom('  Science Fiction '), 'science fiction');
      expect(Categorie.normaliserNom(''), '');
    });

    test('versMap puis depuisMap redonne la même catégorie', () {
      const categorie = Categorie(id: 2, nom: 'gore');
      expect(Categorie.depuisMap(categorie.versMap()), categorie);
      expect(categorie.copierAvec(), categorie);
      expect(categorie.copierAvec().hashCode, categorie.hashCode);
      expect(categorie.copierAvec(nom: 'action'), isNot(categorie));
      expect(categorie.toString(), contains('gore'));
    });

    test('un nom mal typé lève une ErreurBaseDeDonnees', () {
      expect(
        () => Categorie.depuisMap(<String, Object?>{'id': 1, 'nom': 3}),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });
  });

  test('ErreurBaseDeDonnees affiche son message et sa cause', () {
    const erreur = ErreurBaseDeDonnees('Problème', cause: 'origine');
    expect(erreur.toString(), contains('Problème'));
    expect(erreur.toString(), contains('origine'));
  });
}
