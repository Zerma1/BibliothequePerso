// Tests de EtatCategories (section « Catégories regroupées ») et du
// regroupement vu depuis EtatBibliotheque et EtatTitre, avec de faux
// services en mémoire.
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_bibliotheque.dart';
import 'package:bibliotheque_perso/etat/etat_categories.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceCategories service;

  // Catégories créées dans cet ordre : 1 survival, 2 action, 3 survie,
  // 4 comédie, 5 comedy.
  setUp(() {
    bibliotheque = FauxServiceBibliotheque()
      ..ajouterTitreDeTest(
        'Alpha',
        nomsCategories: <String>['survival', 'action'],
      )
      ..ajouterTitreDeTest('Beta', nomsCategories: <String>['survie'])
      ..ajouterTitreDeTest(
        'Gamma',
        nomsCategories: <String>['comédie', 'comedy', 'action'],
      );
    service = FauxServiceCategories(bibliotheque);
  });

  group('EtatCategories', () {
    late EtatCategories etat;
    late int nombreRelectures;

    setUp(() {
      nombreRelectures = 0;
      etat = EtatCategories(
        service,
        surModification: () async => nombreRelectures++,
      );
    });

    tearDown(() => etat.dispose());

    test('lit les catégories, les groupes et les suggestions', () async {
      await etat.charger();

      expect(etat.estCharge, isTrue);
      expect(etat.erreur, isNull);
      expect(etat.categories, hasLength(5));
      expect(etat.groupes, isEmpty);
      expect(etat.suggestions.map((s) => s.reference.nom), <String>[
        'comédie',
        'survie',
      ]);
    });

    test('une suggestion confirmée est appliquée puis la bibliothèque est '
        'relue', () async {
      await etat.charger();
      final survie = etat.suggestions.firstWhere(
        (s) => s.reference.nom == 'survie',
      );

      final resultat = await etat.appliquerSuggestion(survie);

      expect(resultat.estReussi, isTrue);
      expect(service.equivalences, <int, int>{1: 3});
      expect(nombreRelectures, 1);
      expect(etat.groupes.single.reference.nom, 'survie');
      expect(etat.suggestions.map((s) => s.reference.nom), <String>['comédie']);
      expect(etat.estEnModification, isFalse);
    });

    test('« Ignorer » masque la suggestion sans rien écrire', () async {
      await etat.charger();
      etat.ignorerSuggestion(etat.suggestions.first);

      expect(etat.suggestions.map((s) => s.reference.nom), <String>['survie']);
      expect(service.journal, isEmpty);

      // Toujours masquée après une relecture (session).
      await etat.charger();
      expect(etat.suggestions, hasLength(1));
    });

    test('un regroupement refusé rend le message du service', () async {
      service.regrouperDeTest(3, <int>[1]);
      await etat.charger();

      // « survival » (1) est rattachée : elle ne peut pas être référence.
      final resultat = await etat.regrouper(1, <int>{2});

      expect(resultat.estReussi, isFalse);
      expect(resultat.erreur!.nature, NatureErreur.refus);
      expect(resultat.erreur!.detail, contains('déjà rattachée'));
      expect(service.equivalences, <int, int>{1: 3});
      // Relu quand même : un regroupement partiel a pu être enregistré.
      expect(nombreRelectures, 1);
    });

    test('une erreur d\'écriture devient un échec lisible', () async {
      await etat.charger();
      service.erreurEcriture = const ErreurService('Base verrouillée.');

      final resultat = await etat.regrouper(3, <int>{1});

      expect(resultat.erreur!.detail, 'Base verrouillée.');
    });

    test('détache une catégorie et défait un groupe', () async {
      service.regrouperDeTest(4, <int>[5]);
      service.regrouperDeTest(3, <int>[1]);
      await etat.charger();
      expect(etat.groupes, hasLength(2));

      // Groupes triés par référence : « comédie » (avec comedy) d'abord.
      final detache = await etat.detacher(etat.groupes.first.rattachees.single);
      expect(detache.donnee, isTrue);
      expect(service.equivalences, <int, int>{1: 3});

      final groupe = etat.groupes.single;
      final defait = await etat.dissoudre(groupe);
      expect(defait.donnee, 1);
      expect(service.equivalences, isEmpty);
      expect(etat.groupes, isEmpty);
      expect(nombreRelectures, 2);
    });

    test('choix du dialogue : références possibles et catégories '
        'rattachables', () async {
      service.regrouperDeTest(3, <int>[1]);
      service.regrouperDeTest(4, <int>[5]);
      await etat.charger();

      // Une catégorie rattachée ne peut pas être référence.
      expect(
        etat.referencesPossibles('').map((c) => c.nom),
        isNot(contains('survival')),
      );
      // Pour « action » : pas elle-même, pas les références d'autres
      // groupes ; une rattachée ailleurs reste proposée.
      expect(
        etat.rattachablesA(2, '').map((c) => c.nom),
        unorderedEquals(<String>['survival', 'comedy']),
      );
      // Pour « survie » : sa catégorie déjà rattachée n'est pas reproposée.
      expect(
        etat.rattachablesA(3, '').map((c) => c.nom),
        unorderedEquals(<String>['action', 'comedy']),
      );
      expect(etat.groupeDe(5)!.reference.nom, 'comédie');
    });

    test('la recherche ignore accents et majuscules', () {
      final categories = <Categorie>[
        const Categorie(id: 1, nom: 'comédie'),
        const Categorie(id: 2, nom: 'sci-fi'),
      ];
      expect(EtatCategories.filtrer(categories, 'COMEDIE'), hasLength(1));
      expect(EtatCategories.filtrer(categories, 'sci fi').single.id, 2);
      expect(EtatCategories.filtrer(categories, '  '), hasLength(2));
    });

    test('une erreur de lecture est affichable', () async {
      service.erreurLecture = const ErreurService(
        "Les catégories n'ont pas pu être lues.",
      );
      await etat.charger();

      expect(etat.estCharge, isFalse);
      expect(etat.erreur!.nature, NatureErreur.refus);
    });
  });

  group('EtatBibliotheque avec catégories regroupées', () {
    late EtatBibliotheque etat;

    setUp(() {
      service.regrouperDeTest(3, <int>[1]);
      etat = EtatBibliotheque(bibliotheque, serviceCategories: service);
    });

    tearDown(() => etat.dispose());

    test('un groupe ne fait qu\'une entrée, avec ses autres noms', () async {
      await etat.charger();

      expect(etat.gereCategoriesRegroupees, isTrue);
      expect(etat.categories.map((c) => c.nom), <String>[
        'action',
        'comedy',
        'comédie',
        'survie',
      ]);
      expect(etat.autresNoms(3), <String>['survival']);
      expect(etat.autresNoms(2), isEmpty);
      // Chercher un autre nom montre la référence.
      final trouvees = etat.grouperCategories('surviv');
      expect(trouvees.single.categories.single.nom, 'survie');
    });

    test(
      'inclure et exclure se font en une seule lecture, par groupe',
      () async {
        await etat.charger();
        final avant = service.nombreLecturesTitres;

        await etat.appliquerFiltreCategories(
          incluses: <int>{3},
          exclues: <int>{},
        );
        expect(service.nombreLecturesTitres, avant + 1);
        // « survie » trouve aussi le titre classé « survival ».
        expect(etat.titres.map((t) => t.nom), <String>['Alpha', 'Beta']);

        await etat.appliquerFiltreCategories(
          incluses: <int>{2},
          exclues: <int>{3},
        );
        expect(service.nombreLecturesTitres, avant + 2);
        expect(service.derniersFiltres!.incluses, <int>{2});
        expect(service.derniersFiltres!.exclues, <int>{3});
        expect(etat.titres.map((t) => t.nom), <String>['Gamma']);
      },
    );

    test('un filtre sur une catégorie regroupée suit sa référence', () async {
      await etat.charger();
      // Filtre posé avant le regroupement (5 = comedy), puis regroupé.
      await etat.appliquerFiltreCategories(
        incluses: <int>{5},
        exclues: <int>{},
      );
      service.regrouperDeTest(4, <int>[5]);
      await etat.charger();

      expect(etat.idsCategoriesChoisies, <int>{4});
      expect(etat.titres.map((t) => t.nom), <String>['Gamma']);
    });

    test('une modification des groupes relit la bibliothèque', () async {
      await etat.charger();
      final etatCategories = etat.etatCategories!;
      expect(identical(etatCategories, etat.etatCategories), isTrue);
      await etatCategories.charger();

      await etatCategories.regrouper(4, <int>{5});

      expect(etat.categories.map((c) => c.nom), isNot(contains('comedy')));
      expect(etat.autresNoms(4), <String>['comedy']);
    });

    test(
      'la fiche d\'un titre n\'affiche pas de doublon de même sens',
      () async {
        service.regrouperDeTest(4, <int>[5]);
        final fiche = etat.creerEtatTitre(3);
        addTearDown(fiche.dispose);

        await fiche.charger();

        expect(fiche.categories.map((c) => c.nom), <String>[
          'action',
          'comédie',
        ]);
      },
    );

    test(
      'sans service de catégories : ancien chemin, aucune gestion',
      () async {
        final ancien = EtatBibliotheque(bibliotheque);
        addTearDown(ancien.dispose);
        await ancien.charger();

        expect(ancien.gereCategoriesRegroupees, isFalse);
        expect(ancien.etatCategories, isNull);
        expect(ancien.categories, hasLength(5));
        await ancien.appliquerFiltreCategories(
          incluses: <int>{2},
          exclues: <int>{1},
        );
        expect(ancien.titres.map((t) => t.nom), <String>['Gamma']);
        expect(service.nombreLecturesTitres, 0);
      },
    );
  });
}
