import 'package:bibliotheque_perso/modeles/contenu_chapitre.dart';
import 'package:bibliotheque_perso/modeles/fiche_titre.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FicheTitre', () {
    final titre = Titre(urlTitre: 'https://exemple.org/t', nom: 'T');

    test('== et hashCode comparent le titre et les catégories', () {
      final a = FicheTitre(
        titre: titre,
        categories: <String>['Action', 'Gore'],
      );
      final b = FicheTitre(
        titre: titre,
        categories: <String>['Action', 'Gore'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(FicheTitre(titre: titre, categories: <String>['Action'])),
      );
      expect(
        a,
        isNot(
          FicheTitre(
            titre: titre.copierAvec(nom: 'Autre'),
            categories: <String>['Action', 'Gore'],
          ),
        ),
      );
    });

    test('la liste des catégories est copiée et non modifiable', () {
      final source = <String>['Action'];
      final fiche = FicheTitre(titre: titre, categories: source);
      source.add('Gore');
      expect(fiche.categories, <String>['Action']);
      expect(() => fiche.categories.add('x'), throwsUnsupportedError);
    });

    test('sans catégories, la liste est vide', () {
      expect(FicheTitre(titre: titre).categories, isEmpty);
    });

    test('toString mentionne le nom et les catégories', () {
      final texte = FicheTitre(
        titre: titre,
        categories: <String>['Magic'],
      ).toString();
      expect(texte, contains('T'));
      expect(texte, contains('Magic'));
    });
  });

  group('ContenuChapitre', () {
    test('contenu en images : ordre conservé, liste non modifiable', () {
      final urls = <String>['https://e.org/1.png', 'https://e.org/2.png'];
      final contenu = ContenuChapitre.images(
        urls,
        urlReferer: 'https://e.org/chapitre',
      );
      urls.clear();
      expect(contenu.urlsImages, <String>[
        'https://e.org/1.png',
        'https://e.org/2.png',
      ]);
      expect(contenu.estTexte, isFalse);
      expect(contenu.texteHtml, isNull);
      expect(contenu.urlReferer, 'https://e.org/chapitre');
      expect(() => contenu.urlsImages.add('x'), throwsUnsupportedError);
    });

    test('contenu texte : pas d\'images', () {
      final contenu = ContenuChapitre.texte('<p>Bonjour</p>');
      expect(contenu.estTexte, isTrue);
      expect(contenu.urlsImages, isEmpty);
      expect(contenu.urlReferer, isNull);
      expect(contenu.toString(), contains('texte'));
    });

    test('== et hashCode', () {
      expect(
        ContenuChapitre.images(<String>['a', 'b']),
        ContenuChapitre.images(<String>['a', 'b']),
      );
      expect(
        ContenuChapitre.images(<String>['a', 'b']).hashCode,
        ContenuChapitre.images(<String>['a', 'b']).hashCode,
      );
      expect(
        ContenuChapitre.images(<String>['a', 'b']),
        isNot(ContenuChapitre.images(<String>['b', 'a'])),
      );
      expect(
        ContenuChapitre.images(<String>['a']),
        isNot(ContenuChapitre.images(<String>['a'], urlReferer: 'r')),
      );
      expect(ContenuChapitre.texte('x'), ContenuChapitre.texte('x'));
      expect(ContenuChapitre.texte('x'), isNot(ContenuChapitre.texte('y')));
    });
  });
}
