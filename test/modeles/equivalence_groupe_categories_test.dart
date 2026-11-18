import 'package:bibliotheque_perso/modeles/categorie.dart';
import 'package:bibliotheque_perso/modeles/equivalence_categorie.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/groupe_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EquivalenceCategorie', () {
    const equivalence = EquivalenceCategorie(idCategorie: 2, idReference: 1);

    test('versMap puis depuisMap redonne le même objet', () {
      expect(equivalence.versMap(), <String, Object?>{
        'id_categorie': 2,
        'id_reference': 1,
      });
      expect(
        EquivalenceCategorie.depuisMap(equivalence.versMap()),
        equivalence,
      );
    });

    test('depuisMap refuse une colonne manquante ou mal typée', () {
      expect(
        () => EquivalenceCategorie.depuisMap(<String, Object?>{
          'id_categorie': 2,
        }),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(
        () => EquivalenceCategorie.depuisMap(<String, Object?>{
          'id_categorie': '2',
          'id_reference': 1,
        }),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('copierAvec, == et hashCode', () {
      final copie = equivalence.copierAvec(idReference: 3);
      expect(copie.idCategorie, 2);
      expect(copie.idReference, 3);
      expect(copie, isNot(equivalence));
      expect(
        equivalence.copierAvec(),
        const EquivalenceCategorie(idCategorie: 2, idReference: 1),
      );
      expect(equivalence.copierAvec().hashCode, equivalence.hashCode);
    });
  });

  group('GroupeCategories', () {
    const survie = Categorie(id: 1, nom: 'survie');
    const survival = Categorie(id: 2, nom: 'survival');

    test('égalité, toutes et immuabilité', () {
      final rattachees = <Categorie>[survival];
      final groupe = GroupeCategories(
        reference: survie,
        rattachees: rattachees,
      );
      rattachees.add(const Categorie(id: 3, nom: 'autre'));

      expect(groupe.rattachees, <Categorie>[survival]);
      expect(groupe.toutes, <Categorie>[survie, survival]);
      expect(
        () => groupe.rattachees.add(survie),
        throwsA(isA<UnsupportedError>()),
      );
      final identique = GroupeCategories(
        reference: survie,
        rattachees: const <Categorie>[survival],
      );
      expect(groupe, identique);
      expect(groupe.hashCode, identique.hashCode);
      expect(groupe.copierAvec(rattachees: const <Categorie>[]), isNot(groupe));
    });
  });
}
