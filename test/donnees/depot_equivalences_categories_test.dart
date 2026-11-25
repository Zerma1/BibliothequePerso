import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_equivalences_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/gestionnaire_transactions.dart';
import 'package:bibliotheque_perso/modeles/categorie.dart';
import 'package:bibliotheque_perso/modeles/equivalence_categorie.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/groupe_categories.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotCategories depotCategories;
  late DepotEquivalencesCategories depot;
  late DepotTitres depotTitres;
  late int idSource;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depotCategories = DepotCategories(base);
    depot = DepotEquivalencesCategories(base);
    depotTitres = DepotTitres(base);
    idSource = (await DepotSources(base).enregistrerSource(sourceMangaDex)).id!;
  });

  tearDown(() async {
    await base.close();
  });

  Future<int> categorie(String nom) async =>
      (await depotCategories.enregistrerCategorie(nom)).id!;

  Future<Titre> titre(String nom, List<String> categories) =>
      depotTitres.enregistrerTitre(
        Titre(
          idSource: idSource,
          urlTitre: 'https://mangadex.org/title/$nom',
          nom: nom,
        ),
        categories: categories,
      );

  List<String> noms(Iterable<Titre> titres) =>
      titres.map((t) => t.nom).toList();

  group('rattachement et détachement', () {
    test('rattacher puis lister les groupes', () async {
      final idSurvie = await categorie('Survie');
      final idSurvival = await categorie('Survival');
      final idComedie = await categorie('Comédie');
      final idComedy = await categorie('Comedy');
      await categorie('Action');

      final equivalence = await depot.rattacherCategorie(idSurvival, idSurvie);
      expect(
        equivalence,
        EquivalenceCategorie(idCategorie: idSurvival, idReference: idSurvie),
      );
      await depot.rattacherCategorie(idComedy, idComedie);

      expect(await depot.chargerGroupes(), <GroupeCategories>[
        GroupeCategories(
          reference: Categorie(id: idComedie, nom: 'comédie'),
          rattachees: <Categorie>[Categorie(id: idComedy, nom: 'comedy')],
        ),
        GroupeCategories(
          reference: Categorie(id: idSurvie, nom: 'survie'),
          rattachees: <Categorie>[Categorie(id: idSurvival, nom: 'survival')],
        ),
      ]);
      expect(await depot.chargerEquivalences(), hasLength(2));
      expect(
        (await depot.chargerCategoriesEffectives()).map((c) => c.nom),
        <String>['action', 'comédie', 'survie'],
      );
      expect(
        await depot.chargerCategorieEffective(idSurvival),
        Categorie(id: idSurvie, nom: 'survie'),
      );
      expect(
        await depot.chargerCategorieEffective(idSurvie),
        Categorie(id: idSurvie, nom: 'survie'),
      );
      expect(await depot.chargerCategorieEffective(9999), isNull);
    });

    test(
      'rattacher deux fois ne change rien, changer de groupe remplace',
      () async {
        final idSurvie = await categorie('survie');
        final idSurvivre = await categorie('survivre');
        final idSurvival = await categorie('survival');

        await depot.rattacherCategorie(idSurvival, idSurvie);
        await depot.rattacherCategorie(idSurvival, idSurvie);
        expect(await depot.chargerEquivalences(), hasLength(1));

        await depot.rattacherCategorie(idSurvival, idSurvivre);
        expect(await depot.chargerEquivalences(), <EquivalenceCategorie>[
          EquivalenceCategorie(
            idCategorie: idSurvival,
            idReference: idSurvivre,
          ),
        ]);
      },
    );

    test('détacher une catégorie et dissoudre un groupe', () async {
      final idSurvie = await categorie('survie');
      final idSurvival = await categorie('survival');
      final idSupervivencia = await categorie('supervivencia');
      await depot.rattacherCategorie(idSurvival, idSurvie);
      await depot.rattacherCategorie(idSupervivencia, idSurvie);

      expect(await depot.detacherCategorie(idSurvival), isTrue);
      expect(await depot.detacherCategorie(idSurvival), isFalse);
      expect(
        (await depot.chargerGroupes()).single.rattachees.single.id,
        idSupervivencia,
      );

      expect(await depot.dissoudreGroupe(idSurvie), 1);
      expect(await depot.chargerGroupes(), isEmpty);
      expect(await depotCategories.chargerCategories(), hasLength(3));
    });

    test('fonctionne dans une transaction partagée', () async {
      final idSurvie = await categorie('survie');
      final idSurvival = await categorie('survival');
      await GestionnaireTransactions(base).executerEnTransaction((txn) async {
        await depot.rattacherCategorie(idSurvival, idSurvie, executeur: txn);
        expect(await depot.chargerGroupes(executeur: txn), hasLength(1));
        expect(await depot.detacherCategorie(idSurvival, executeur: txn), true);
      });
      expect(await depot.chargerEquivalences(), isEmpty);
    });
  });

  group('refus', () {
    test('une catégorie ne peut pas être sa propre référence', () async {
      final id = await categorie('survie');
      await expectLater(
        depot.rattacherCategorie(id, id),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('une catégorie inconnue est refusée', () async {
      final id = await categorie('survie');
      await expectLater(
        depot.rattacherCategorie(9999, id),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      await expectLater(
        depot.rattacherCategorie(id, 9999),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(await depot.chargerEquivalences(), isEmpty);
    });

    test('les chaînes et les cycles sont refusés', () async {
      final idSurvie = await categorie('survie');
      final idSurvival = await categorie('survival');
      final idSupervivencia = await categorie('supervivencia');
      await depot.rattacherCategorie(idSurvival, idSurvie);

      // Chaîne supervivencia → survival → survie.
      await expectLater(
        depot.rattacherCategorie(idSupervivencia, idSurvival),
        throwsA(
          isA<ErreurBaseDeDonnees>().having(
            (e) => e.message,
            'message',
            contains('survival'),
          ),
        ),
      );
      // Chaîne survie → supervivencia (survie est une référence).
      await expectLater(
        depot.rattacherCategorie(idSurvie, idSupervivencia),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      // Cycle survie → survival.
      await expectLater(
        depot.rattacherCategorie(idSurvie, idSurvival),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(await depot.chargerEquivalences(), <EquivalenceCategorie>[
        EquivalenceCategorie(idCategorie: idSurvival, idReference: idSurvie),
      ]);
    });
  });

  group('catégories effectives et filtres de la bibliothèque', () {
    late int idSurvie;
    late int idSurvival;
    late int idAction;

    setUp(() async {
      await titre('A survie', <String>['Survie']);
      await titre('B survival', <String>['Survival', 'Action']);
      await titre('C les deux', <String>['Survie', 'Survival']);
      await titre('D action', <String>['Action']);
      final categories = <String, int>{
        for (final c in await depotCategories.chargerCategories()) c.nom: c.id!,
      };
      idSurvie = categories['survie']!;
      idSurvival = categories['survival']!;
      idAction = categories['action']!;
    });

    test('sans groupe, le filtre est exact', () async {
      expect(
        noms(await depotTitres.chargerTitres(idCategorie: idSurvie)),
        <String>['A survie', 'C les deux'],
      );
    });

    test(
      'le filtre sur une référence trouve les catégories rattachées',
      () async {
        await depot.rattacherCategorie(idSurvival, idSurvie);

        expect(
          noms(await depotTitres.chargerTitres(idCategorie: idSurvie)),
          <String>['A survie', 'B survival', 'C les deux'],
        );
        // Filtrer sur une catégorie rattachée = filtrer sur tout son groupe.
        expect(
          noms(await depotTitres.chargerTitres(idCategorie: idSurvival)),
          <String>['A survie', 'B survival', 'C les deux'],
        );
        // Correspondance exacte si demandée.
        expect(
          noms(
            await depotTitres.chargerTitres(
              idCategorie: idSurvie,
              suivreEquivalences: false,
            ),
          ),
          <String>['A survie', 'C les deux'],
        );
      },
    );

    test('inclusion et exclusion suivent les groupes', () async {
      await depot.rattacherCategorie(idSurvival, idSurvie);

      expect(
        noms(
          await depotTitres.chargerTitres(
            idsCategoriesIncluses: <int>{idSurvie, idAction},
          ),
        ),
        <String>['B survival'],
      );
      expect(
        noms(
          await depotTitres.chargerTitres(
            idsCategoriesExclues: <int>{idSurvie},
          ),
        ),
        <String>['D action'],
      );
      expect(
        noms(
          await depotTitres.chargerTitres(
            idsCategoriesExclues: <int>{idSurvie},
            suivreEquivalences: false,
          ),
        ),
        <String>['B survival', 'D action'],
      );
      expect(
        noms(
          await depotTitres.chargerTitres(
            idCategorie: idAction,
            idsCategoriesExclues: <int>{idSurvival},
          ),
        ),
        <String>['D action'],
      );
    });

    test('catégories effectives d\'un titre, sans doublon', () async {
      await depot.rattacherCategorie(idSurvival, idSurvie);
      final lesDeux = (await depotTitres.chargerTitres(recherche: 'C les deux'))
          .single;
      final survival = (await depotTitres.chargerTitres(
        recherche: 'B survival',
      )).single;

      expect(
        await depot.chargerCategoriesEffectivesDuTitre(lesDeux.id!),
        <Categorie>[Categorie(id: idSurvie, nom: 'survie')],
      );
      expect(
        (await depot.chargerCategoriesEffectivesDuTitre(survival.id!))
            .map((c) => c.nom),
        <String>['action', 'survie'],
      );
      // Les catégories enregistrées du titre ne changent pas.
      expect(
        (await depotCategories.chargerCategoriesDuTitre(survival.id!))
            .map((c) => c.nom),
        <String>['action', 'survival'],
      );
    });

    test('supprimer la référence défait le groupe', () async {
      await depot.rattacherCategorie(idSurvival, idSurvie);
      await base.delete(
        'categories',
        where: 'id = ?',
        whereArgs: <Object?>[idSurvie],
      );

      expect(await depot.chargerGroupes(), isEmpty);
      expect(
        noms(await depotTitres.chargerTitres(idCategorie: idSurvival)),
        <String>['B survival', 'C les deux'],
      );
    });

    test('supprimer une catégorie rattachée la retire du groupe', () async {
      final idSupervivencia = await categorie('supervivencia');
      await depot.rattacherCategorie(idSurvival, idSurvie);
      await depot.rattacherCategorie(idSupervivencia, idSurvie);
      await base.delete(
        'categories',
        where: 'id = ?',
        whereArgs: <Object?>[idSurvival],
      );

      expect(
        (await depot.chargerGroupes()).single.rattachees.map((c) => c.nom),
        <String>['supervivencia'],
      );
    });

    test('le nettoyage des catégories inutilisées garde les groupes', () async {
      final idSupervivencia = await categorie('supervivencia');
      final idOrpheline = await categorie('orpheline');
      await depot.rattacherCategorie(idSupervivencia, idSurvie);

      expect(await depotCategories.supprimerCategoriesInutilisees(), 1);
      final restantes = (await depotCategories.chargerCategories())
          .map((c) => c.id)
          .toSet();
      expect(restantes, contains(idSupervivencia));
      expect(restantes, isNot(contains(idOrpheline)));
    });
  });

  test('compterTitres compte tous les titres', () async {
    expect(await depotTitres.compterTitres(), 0);
    await titre('A', <String>[]);
    await titre('B', <String>[]);
    expect(await depotTitres.compterTitres(), 2);
    await GestionnaireTransactions(base).executerEnTransaction((txn) async {
      expect(await depotTitres.compterTitres(executeur: txn), 2);
    });
  });
}
