import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const urlTitre = 'https://mangadex.org/title/ruri';

  group('Titre.champsManuels', () {
    test('par défaut vide, écrit "[]" en base', () {
      final titre = Titre(urlTitre: urlTitre, nom: 'Ruri Dragon');
      expect(titre.champsManuels, isEmpty);
      expect(titre.versMap()['champs_manuels'], '[]');
    });

    test('aller-retour versMap / depuisMap, ordre stable', () {
      final titre = Titre(
        id: 1,
        idSource: 2,
        urlTitre: urlTitre,
        nom: 'Ruri Dragon',
        champsManuels: <ChampTitre>{ChampTitre.resume, ChampTitre.nom},
      );
      final map = titre.versMap();
      // Ordre de ChampTitre.values, quel que soit l'ordre d'ajout.
      expect(map['champs_manuels'], '["nom","resume"]');
      expect(Titre.depuisMap(map), titre);
      expect(titre.estManuel(ChampTitre.nom), isTrue);
      expect(titre.estManuel(ChampTitre.auteur), isFalse);
    });

    test('colonne absente ou NULL : aucun champ manuel', () {
      final map = <String, Object?>{
        'url_titre': urlTitre,
        'nom': 'Ruri Dragon',
        'type_titre': 'manga',
      };
      expect(Titre.depuisMap(map).champsManuels, isEmpty);
      expect(
        Titre.depuisMap(<String, Object?>{...map, 'champs_manuels': null})
            .champsManuels,
        isEmpty,
      );
    });

    test('un nom inconnu est ignoré', () {
      expect(
        Titre.decoderChampsManuels('["auteur","champFutur"]'),
        <ChampTitre>{ChampTitre.auteur},
      );
    });

    test('un texte invalide lève une ErreurBaseDeDonnees', () {
      for (final texte in <String>['pas du json', '{"a":1}', '[1]']) {
        expect(
          () => Titre.decoderChampsManuels(texte),
          throwsA(isA<ErreurBaseDeDonnees>()),
          reason: texte,
        );
      }
    });

    test('copierAvec, == et hashCode (ordre indifférent)', () {
      final titre = Titre(urlTitre: urlTitre, nom: 'Ruri Dragon');
      final a = titre.copierAvec(
        champsManuels: <ChampTitre>{ChampTitre.nom, ChampTitre.categories},
      );
      final b = titre.copierAvec(
        champsManuels: <ChampTitre>{ChampTitre.categories, ChampTitre.nom},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(titre));
      // Non fourni : inchangé.
      expect(a.copierAvec(nom: 'Autre').champsManuels, a.champsManuels);
    });

    test('l\'ensemble ne peut pas être modifié', () {
      final titre = Titre(
        urlTitre: urlTitre,
        nom: 'Ruri Dragon',
        champsManuels: <ChampTitre>{ChampTitre.nom},
      );
      expect(
        () => titre.champsManuels.add(ChampTitre.auteur),
        throwsUnsupportedError,
      );
    });
  });
}
