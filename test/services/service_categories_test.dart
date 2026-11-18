// ServiceCategories : groupes de catégories de même sens, catégories
// effectives, filtres de la bibliothèque et suggestions de regroupement.
// Base en mémoire ; aucun appel réseau.
import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_equivalences_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/categorie.dart';
import 'package:bibliotheque_perso/modeles/equivalence_categorie.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_categories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTitres depotTitres;
  late DepotCategories depotCategories;
  late ServiceCategories service;
  late int idSource;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depotTitres = DepotTitres(base);
    depotCategories = DepotCategories(base);
    service = ServiceCategories.surBase(base);
    idSource = (await DepotSources(base).enregistrerSource(sourceMangaDex)).id!;
  });

  tearDown(() => base.close());

  Future<Titre> titre(String nom, List<String> categories) =>
      depotTitres.enregistrerTitre(
        Titre(
          idSource: idSource,
          urlTitre: 'https://mangadex.org/title/$nom',
          nom: nom,
        ),
        categories: categories,
      );

  Future<int> id(String nom) async =>
      (await depotCategories.chargerCategories())
          .firstWhere((categorie) => categorie.nom == nom)
          .id!;

  List<String> noms(Iterable<Object> elements) => <String>[
    for (final element in elements)
      switch (element) {
        Titre(:final nom) => nom,
        Categorie(:final nom) => nom,
        _ => '$element',
      },
  ];

  group('groupes', () {
    test('rattacher crée un groupe, visible dans chargerGroupes', () async {
      await titre('A', <String>['Survival', 'Survie', 'Action']);
      await service.rattacherCategorie(
        await id('survival'),
        await id('survie'),
      );

      final groupes = await service.chargerGroupes();
      expect(groupes, hasLength(1));
      expect(groupes.single.reference.nom, 'survie');
      expect(noms(groupes.single.rattachees), <String>['survival']);
    });

    test('les catégories effectives cachent les rattachées', () async {
      final a = await titre('A', <String>['Survival', 'Survie', 'Action']);
      await service.rattacherCategorie(
        await id('survival'),
        await id('survie'),
      );

      expect(noms(await service.chargerCategoriesEffectives()), <String>[
        'action',
        'survie',
      ]);
      expect(
        noms(await service.chargerCategoriesEffectivesDuTitre(a.id!)),
        <String>['action', 'survie'],
      );
      expect(
        (await service.chargerCategorieEffective(await id('survival')))?.nom,
        'survie',
      );
      // Toutes les catégories restent listées pour l'écran de gestion.
      expect(noms(await service.chargerCategories()), <String>[
        'action',
        'survie',
        'survival',
      ]);
    });

    test('regrouper sa propre référence est refusé par une ErreurService '
        'lisible', () async {
      await titre('A', <String>['Survie']);
      final survie = await id('survie');
      await expectLater(
        service.rattacherCategorie(survie, survie),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('propre référence'),
          ),
        ),
      );
    });

    test(
      'une référence rattachée ailleurs est refusée (un seul niveau)',
      () async {
        await titre('A', <String>['Survival', 'Survie', 'Supervivencia']);
        await service.rattacherCategorie(
          await id('survival'),
          await id('survie'),
        );
        await expectLater(
          service.rattacherCategorie(
            await id('supervivencia'),
            await id('survival'),
          ),
          throwsA(
            isA<ErreurService>().having(
              (e) => e.message,
              'message',
              contains('déjà rattachée'),
            ),
          ),
        );
      },
    );

    test('une catégorie inconnue est refusée par une ErreurService', () async {
      await titre('A', <String>['Survie']);
      await expectLater(
        service.rattacherCategorie(9999, await id('survie')),
        throwsA(isA<ErreurService>()),
      );
    });

    test(
      'détacher et dissoudre rendent les catégories indépendantes',
      () async {
        await titre('A', <String>['Survival', 'Survie', 'Supervivencia']);
        final survie = await id('survie');
        await service.regrouperCategories(survie, <int>[
          await id('survival'),
          await id('supervivencia'),
          survie, // ignorée : c'est la référence
        ]);
        expect(
          noms((await service.chargerGroupes()).single.rattachees),
          <String>['supervivencia', 'survival'],
        );

        expect(await service.detacherCategorie(await id('survival')), isTrue);
        expect(await service.detacherCategorie(await id('survival')), isFalse);
        expect(await service.dissoudreGroupe(survie), 1);
        expect(await service.chargerGroupes(), isEmpty);
        expect(await service.chargerCategoriesEffectives(), hasLength(3));
      },
    );

    test('regrouper plusieurs catégories est tout ou rien', () async {
      await titre('A', <String>['Survival', 'Survie', 'Comedy', 'Comédie']);
      // « comedy » devient la référence d'un groupe : elle ne peut plus être
      // rattachée ailleurs.
      await service.rattacherCategorie(await id('comédie'), await id('comedy'));

      await expectLater(
        service.regrouperCategories(await id('survie'), <int>[
          await id('survival'),
          await id('comedy'),
        ]),
        throwsA(isA<ErreurService>()),
      );
      // « survival » n'a pas été gardée : la transaction est annulée.
      final groupes = await service.chargerGroupes();
      expect(noms(groupes.map((g) => g.reference)), <String>['comedy']);
    });
  });

  group('chargerTitresFiltres', () {
    setUp(() async {
      await titre('Anglais', <String>['Survival', 'Action']);
      await titre('Français', <String>['Survie']);
      await titre('Sans', <String>['Comedy']);
      await service.rattacherCategorie(
        await id('survival'),
        await id('survie'),
      );
    });

    test(
      'inclure la référence trouve aussi les titres de ses rattachées',
      () async {
        final titres = await service.chargerTitresFiltres(
          idsCategoriesIncluses: <int>{await id('survie')},
        );
        expect(noms(titres), <String>['Anglais', 'Français']);
      },
    );

    test('inclure une rattachée revient à inclure tout son groupe', () async {
      final titres = await service.chargerTitresFiltres(
        idsCategoriesIncluses: <int>{await id('survival')},
      );
      expect(noms(titres), <String>['Anglais', 'Français']);
    });

    test('exclure un groupe écarte tous ses titres', () async {
      final titres = await service.chargerTitresFiltres(
        idsCategoriesExclues: <int>{await id('survie')},
      );
      expect(noms(titres), <String>['Sans']);
    });

    test('inclusions (toutes requises) et exclusions se cumulent', () async {
      expect(
        noms(
          await service.chargerTitresFiltres(
            idsCategoriesIncluses: <int>{
              await id('survie'),
              await id('action'),
            },
          ),
        ),
        <String>['Anglais'],
      );
      expect(
        noms(
          await service.chargerTitresFiltres(
            idsCategoriesIncluses: <int>{await id('survie')},
            idsCategoriesExclues: <int>{await id('action')},
            recherche: 'fran',
          ),
        ),
        <String>['Français'],
      );
    });

    test('sans filtre de catégorie, tous les titres', () async {
      expect(await service.chargerTitresFiltres(), hasLength(3));
    });
  });

  group('comparaison des noms', () {
    test('sans accents, sans majuscules, tirets et espaces confondus', () {
      expect(
        ServiceCategories.cleDeComparaison('Science-Fiction'),
        'science fiction',
      );
      expect(ServiceCategories.cleDeComparaison('  Comédie '), 'comedie');
      expect(ServiceCategories.cleDeComparaison("Girls' Love"), 'girls love');
      expect(
        ServiceCategories.cleDeComparaison('Œuvre_Tragique'),
        'oeuvre tragique',
      );
      // Les écritures non latines sont gardées (jamais une clé vide).
      expect(ServiceCategories.cleDeComparaison('恋愛'), '恋愛');
    });

    test(
      'le dictionnaire donne le libellé français, anglais ou déjà français',
      () {
        expect(ServiceCategories.libelleFrancais('Sci-Fi'), 'science-fiction');
        expect(ServiceCategories.libelleFrancais('SciFi'), 'science-fiction');
        expect(
          ServiceCategories.libelleFrancais('Slice of Life'),
          'tranche de vie',
        );
        expect(
          ServiceCategories.libelleFrancais('tranche-de-vie'),
          'tranche de vie',
        );
        expect(ServiceCategories.libelleFrancais('comedie'), 'comédie');
        expect(
          ServiceCategories.libelleFrancais('Martial Arts'),
          'arts martiaux',
        );
        expect(ServiceCategories.libelleFrancais('Sports'), 'sport');
        expect(ServiceCategories.libelleFrancais('inconnu'), isNull);
      },
    );

    test('même clé de sens pour une catégorie et sa traduction', () {
      expect(
        ServiceCategories.cleDeSens('Survival'),
        ServiceCategories.cleDeSens('survie'),
      );
      expect(
        ServiceCategories.cleDeSens('Psychological'),
        ServiceCategories.cleDeSens('Psychologique'),
      );
      expect(
        ServiceCategories.cleDeSens('Survival'),
        isNot(ServiceCategories.cleDeSens('Supernatural')),
      );
    });
  });

  group('calculerSuggestions (pur)', () {
    Categorie c(int id, String nom) => Categorie(id: id, nom: nom);

    test('propose la catégorie au libellé français comme référence', () {
      final suggestions = ServiceCategories.calculerSuggestions(<Categorie>[
        c(1, 'survival'),
        c(2, 'survie'),
        c(3, 'comedy'),
        c(4, 'comédie'),
        c(5, 'comedie'),
        c(6, 'action'),
        c(7, 'gore'),
      ], const <EquivalenceCategorie>[]);
      expect(suggestions, hasLength(2));
      final comedie = suggestions.first;
      expect(comedie.reference.nom, 'comédie');
      expect(noms(comedie.aRattacher), <String>['comedie', 'comedy']);
      expect(comedie.libelleFrancais, 'comédie');
      final survie = suggestions.last;
      expect(survie.reference.nom, 'survie');
      expect(noms(survie.aRattacher), <String>['survival']);
      expect(noms(survie.toutes), <String>['survie', 'survival']);
    });

    test('le libellé français écrit autrement reste préféré', () {
      final suggestions = ServiceCategories.calculerSuggestions(<Categorie>[
        c(1, 'sci-fi'),
        c(2, 'science fiction'),
      ], const <EquivalenceCategorie>[]);
      expect(suggestions.single.reference.nom, 'science fiction');
      expect(noms(suggestions.single.aRattacher), <String>['sci-fi']);
    });

    test('sans libellé français présent, la première par nom', () {
      final suggestions = ServiceCategories.calculerSuggestions(<Categorie>[
        c(1, 'scifi'),
        c(2, 'sci-fi'),
      ], const <EquivalenceCategorie>[]);
      expect(suggestions.single.reference.nom, 'sci-fi');
      expect(suggestions.single.libelleFrancais, 'science-fiction');
      expect(noms(suggestions.single.aRattacher), <String>['scifi']);
    });

    test('des catégories hors dictionnaire qui ne diffèrent que par les '
        'accents sont proposées', () {
      final suggestions = ServiceCategories.calculerSuggestions(<Categorie>[
        c(1, 'école'),
        c(2, 'ecole'),
      ], const <EquivalenceCategorie>[]);
      expect(suggestions.single.libelleFrancais, isNull);
      expect(suggestions.single.toutes, hasLength(2));
    });

    test('un groupe déjà fait n\'est pas reproposé', () {
      final suggestions = ServiceCategories.calculerSuggestions(
        <Categorie>[c(1, 'survival'), c(2, 'survie')],
        const <EquivalenceCategorie>[
          EquivalenceCategorie(idCategorie: 1, idReference: 2),
        ],
      );
      expect(suggestions, isEmpty);
    });

    test('une référence existante reste la référence et son groupe est '
        'complété', () {
      final suggestions = ServiceCategories.calculerSuggestions(
        <Categorie>[c(1, 'survival'), c(2, 'survie'), c(3, 'humour')],
        const <EquivalenceCategorie>[
          // Le client a fait de « survival » une référence (choix gardé).
          EquivalenceCategorie(idCategorie: 3, idReference: 1),
        ],
      );
      expect(suggestions.single.reference.nom, 'survival');
      expect(noms(suggestions.single.aRattacher), <String>['survie']);
    });

    test(
      'une catégorie rattachée à un autre groupe n\'est jamais proposée',
      () {
        final suggestions = ServiceCategories.calculerSuggestions(
          <Categorie>[c(1, 'comedy'), c(2, 'comédie'), c(3, 'humour')],
          const <EquivalenceCategorie>[
            EquivalenceCategorie(idCategorie: 1, idReference: 3),
          ],
        );
        expect(suggestions, isEmpty);
      },
    );
  });

  group('suggestions en base', () {
    test('rien n\'est appliqué sans confirmation, puis la suggestion '
        'confirmée regroupe', () async {
      final a = await titre('A', categoriesReference);
      await titre('B', <String>['Survie', 'Comédie', 'Fantastique']);

      final suggestions = await service.suggererRegroupements();
      expect(noms(suggestions.map((s) => s.reference)), <String>[
        'comédie',
        'fantastique',
        'survie',
      ]);
      // Aucune écriture : pas encore de groupe.
      expect(await service.chargerGroupes(), isEmpty);

      for (final suggestion in suggestions) {
        await service.appliquerSuggestion(suggestion);
      }
      expect(await service.chargerGroupes(), hasLength(3));
      expect(
        noms(await service.chargerCategoriesEffectivesDuTitre(a.id!)),
        <String>[
          'action',
          'adaptation',
          'comédie',
          'fantastique',
          'gore',
          'magic',
          'military',
          'supernatural',
          'survie',
        ],
      );
      expect(await service.suggererRegroupements(), isEmpty);
    });

    test(
      'une erreur de lecture de la base devient une ErreurService',
      () async {
        final depotEquivalences = DepotEquivalencesCategories(base);
        final enPanne = ServiceCategories(
          depotCategories: depotCategories,
          depotEquivalences: depotEquivalences,
          depotTitres: depotTitres,
        );
        await base.close();
        await expectLater(
          enPanne.chargerGroupes(),
          throwsA(isA<ErreurService>()),
        );
        // Réouverte pour le tearDown.
        base = await ouvrirBaseDeTest();
      },
    );
  });
}
