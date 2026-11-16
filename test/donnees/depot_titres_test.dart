import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/liste_lecture.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTitres depotTitres;
  late DepotListes depotListes;
  late DepotCategories depotCategories;
  late DepotChapitres depotChapitres;
  late int idSource;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depotTitres = DepotTitres(base);
    depotListes = DepotListes(base);
    depotCategories = DepotCategories(base);
    depotChapitres = DepotChapitres(base);
    idSource = (await DepotSources(base).enregistrerSource(sourceMangaDex)).id!;
  });

  tearDown(() async {
    await base.close();
  });

  Future<ListeLecture> liste(String nom) async =>
      (await depotListes.chargerListeParNom(nom))!;

  group('titre de référence MangaDex', () {
    late Titre titre;

    setUp(() async {
      titre = await depotTitres.enregistrerTitre(
        titreReference(idSource),
        categories: categoriesReference,
      );
      await depotListes.ajouterTitre(
        (await liste(nomListeFavoris)).id!,
        titre.id!,
      );
      await depotListes.ajouterTitre(
        (await liste(nomListeSuivis)).id!,
        titre.id!,
      );
    });

    test('est enregistré avec ses 6 titres alternatifs', () async {
      final relu = (await depotTitres.chargerTitre(titre.id!))!;
      expect(relu.nom, nomTitreReference);
      expect(relu.typeTitre, TypeTitre.manga);
      expect(relu.titresAlternatifs, hasLength(6));
      expect(
        relu.titresAlternatifs.map((alternatif) => alternatif.nom),
        titresAlternatifsReference.map((alternatif) => alternatif.nom),
      );
      expect(
        relu.titresAlternatifs.map((alternatif) => alternatif.langue),
        containsAll(<String>['ja', 'ko', 'zh']),
      );
      expect(
        relu.titresAlternatifs.every(
          (alternatif) => alternatif.idTitre == titre.id,
        ),
        isTrue,
      );
    });

    test('a ses 9 catégories normalisées', () async {
      final categories = await depotCategories.chargerCategoriesDuTitre(
        titre.id!,
      );
      expect(
        categories.map((categorie) => categorie.nom),
        unorderedEquals(categoriesReference.map((nom) => nom.toLowerCase())),
      );
    });

    test('est présent dans Favoris et Suivis', () async {
      final listes = await depotListes.chargerListesDuTitre(titre.id!);
      expect(listes.map((liste) => liste.nom), <String>[
        nomListeFavoris,
        nomListeSuivis,
      ]);
    });

    test('une recherche « death\'s daughter » le retrouve', () async {
      final resultats = await depotTitres.chargerTitres(
        recherche: "death's daughter",
      );
      expect(resultats, hasLength(1));
      expect(resultats.single.id, titre.id);
      expect(resultats.single.titresAlternatifs, hasLength(6));
    });

    test('la recherche porte aussi sur le nom principal et les écritures '
        'asiatiques', () async {
      expect(
        await depotTitres.chargerTitres(recherche: 'SHINIGAMI'),
        hasLength(1),
      );
      expect(await depotTitres.chargerTitres(recherche: '漆黒の剣'), hasLength(1));
      expect(await depotTitres.chargerTitres(recherche: '칠흑의 검'), hasLength(1));
      expect(await depotTitres.chargerTitres(recherche: 'One Punch'), isEmpty);
    });

    test(
      'les caractères spéciaux de LIKE sont cherchés littéralement',
      () async {
        expect(await depotTitres.chargerTitres(recherche: '%'), isEmpty);
        expect(await depotTitres.chargerTitres(recherche: '_'), isEmpty);
      },
    );

    test('le filtre par liste et par catégorie le retrouve', () async {
      final favoris = await liste(nomListeFavoris);
      final gore = (await depotCategories.chargerCategories()).firstWhere(
        (categorie) => categorie.nom == 'gore',
      );

      expect(
        await depotTitres.chargerTitres(idListe: favoris.id),
        hasLength(1),
      );
      expect(
        await depotTitres.chargerTitres(idCategorie: gore.id),
        hasLength(1),
      );
      expect(
        await depotTitres.chargerTitres(
          recherche: 'ebony',
          idListe: favoris.id,
          idCategorie: gore.id,
          idSource: idSource,
        ),
        hasLength(1),
      );

      final autreListe = await depotListes.creerListe('À lire plus tard');
      expect(await depotTitres.chargerTitres(idListe: autreListe.id), isEmpty);
    });

    test(
      'l\'enregistrer une seconde fois met à jour sans créer de doublon',
      () async {
        final misAJour = await depotTitres.enregistrerTitre(
          titreReference(idSource).copierAvec(
            resume: 'Nouveau résumé',
            titresAlternatifs: const <TitreAlternatif>[
              TitreAlternatif(nom: "Death's Daughter and the Ebony Blade"),
              TitreAlternatif(nom: "Death's Daughter and the Ebony Blade"),
              TitreAlternatif(nom: '   '),
            ],
          ),
          categories: <String>[' ACTION ', 'action', 'Gore'],
        );

        expect(misAJour.id, titre.id);
        expect(misAJour.resume, 'Nouveau résumé');
        expect(misAJour.titresAlternatifs, hasLength(1));
        expect(await depotTitres.chargerTitres(), hasLength(1));
        expect(
          (await depotCategories.chargerCategoriesDuTitre(titre.id!))
              .map((categorie) => categorie.nom),
          <String>['action', 'gore'],
        );
        // Les listes sont conservées : la ligne n'a pas été supprimée puis
        // recréée.
        expect(await depotListes.chargerListesDuTitre(titre.id!), hasLength(2));
      },
    );

    test(
      'sans catégories fournies, les catégories existantes sont gardées',
      () async {
        await depotTitres.enregistrerTitre(titre.copierAvec(statut: 'Terminé'));
        expect(
          await depotCategories.chargerCategoriesDuTitre(titre.id!),
          hasLength(9),
        );
      },
    );

    test('la suppression efface en cascade chapitres, noms, listes et '
        'catégories liées', () async {
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: titre.id!,
          urlChapitre: 'https://mangadex.org/chapter/a',
          nom: 'Chapitre 1',
          numero: 1,
        ),
      ]);

      await depotTitres.supprimerTitre(titre.id!);

      expect(await depotTitres.chargerTitre(titre.id!), isNull);
      for (final table in <String>[
        'chapitres',
        'titres_alternatifs',
        'titres_listes',
        'titres_categories',
      ]) {
        expect(await base.query(table), isEmpty, reason: table);
      }
      // Les listes et les catégories elles-mêmes restent.
      expect(await depotListes.chargerListes(), hasLength(4));
      expect(await depotCategories.chargerCategories(), hasLength(9));
    });
  });

  test('une bibliothèque vide renvoie des listes vides', () async {
    expect(await depotTitres.chargerTitres(), isEmpty);
    expect(await depotTitres.chargerTitres(recherche: 'death'), isEmpty);
    expect(await depotTitres.chargerTitres(recherche: '   '), isEmpty);
    expect(await depotTitres.chargerTitre(1), isNull);
    expect(await depotTitres.chargerTitreParUrl(urlTitreReference), isNull);
  });

  test('une recherche vide renvoie tous les titres, triés par nom', () async {
    for (final nom in <String>['Zeta', 'alpha', 'Beta']) {
      await depotTitres.enregistrerTitre(
        Titre(
          idSource: idSource,
          urlTitre: 'https://exemple.org/$nom',
          nom: nom,
        ),
      );
    }
    final titres = await depotTitres.chargerTitres(recherche: '');
    expect(titres.map((titre) => titre.nom), <String>['alpha', 'Beta', 'Zeta']);
  });

  test('le nombre de chapitres non lus est calculé au chargement', () async {
    final titre = await depotTitres.enregistrerTitre(titreReference(idSource));
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (var numero = 1; numero <= 3; numero++)
        Chapitre(
          idTitre: titre.id!,
          urlChapitre: 'https://mangadex.org/chapter/$numero',
          nom: 'Chapitre $numero',
          numero: numero.toDouble(),
        ),
    ]);
    final chapitres = await depotChapitres.chargerChapitres(titre.id!);
    await depotChapitres.marquerLu(chapitres.first.id!);

    final relu = await depotTitres.chargerTitreParUrl(urlTitreReference);
    expect(relu!.nombreChapitresNonLus, 2);
  });

  test('la date de vérification est enregistrée en UTC', () async {
    final titre = await depotTitres.enregistrerTitre(titreReference(idSource));
    final date = DateTime.utc(2026, 11, 15, 8, 30);
    await depotTitres.enregistrerDateVerification(titre.id!, date);
    final relu = await depotTitres.chargerTitre(titre.id!);
    expect(relu!.dateDerniereVerification, date);
  });

  test(
    'mettre à jour un titre ne réécrit pas sa date de vérification',
    () async {
      final titre = await depotTitres.enregistrerTitre(
        titreReference(idSource),
      );
      final date = DateTime.utc(2026, 11, 15, 8, 30);
      await depotTitres.enregistrerDateVerification(titre.id!, date);

      // Titre reconstruit par une source : date de vérification à null.
      await depotTitres.enregistrerTitre(
        titreReference(idSource).copierAvec(resume: 'Résumé mis à jour'),
      );
      // Même chose avec une date différente fournie dans l'objet.
      await depotTitres.enregistrerTitre(
        titre.copierAvec(dateDerniereVerification: DateTime.utc(2000)),
      );

      final relu = (await depotTitres.chargerTitre(titre.id!))!;
      expect(relu.dateDerniereVerification, date);
    },
  );

  test(
    'la date de vérification fournie à l\'insertion est conservée',
    () async {
      final date = DateTime.utc(2026, 1, 1);
      final titre = await depotTitres.enregistrerTitre(
        titreReference(idSource).copierAvec(dateDerniereVerification: date),
      );
      expect(titre.dateDerniereVerification, date);
    },
  );

  group('langues préférées du titre', () {
    test('enregistrées normalisées, puis remises à null', () async {
      final titre = await depotTitres.enregistrerTitre(
        titreReference(idSource),
      );
      expect(titre.languesPreferees, isNull);

      expect(
        await depotTitres.enregistrerLanguesPreferees(titre.id!, ' FR, en,fr,'),
        isTrue,
      );
      var relu = (await depotTitres.chargerTitre(titre.id!))!;
      expect(relu.languesPreferees, 'fr,en');
      expect(relu.listeLanguesPreferees, <String>['fr', 'en']);

      await depotTitres.enregistrerLanguesPreferees(titre.id!, null);
      relu = (await depotTitres.chargerTitre(titre.id!))!;
      expect(relu.languesPreferees, isNull);
      expect(relu.listeLanguesPreferees, isEmpty);

      // Une liste vide après nettoyage revient aussi au réglage général.
      await depotTitres.enregistrerLanguesPreferees(titre.id!, ' , ');
      relu = (await depotTitres.chargerTitre(titre.id!))!;
      expect(relu.languesPreferees, isNull);
    });

    test('un titre inexistant renvoie false', () async {
      expect(await depotTitres.enregistrerLanguesPreferees(999, 'fr'), isFalse);
    });

    test('un code de langue invalide est refusé', () async {
      final titre = await depotTitres.enregistrerTitre(
        titreReference(idSource),
      );
      expect(
        () => depotTitres.enregistrerLanguesPreferees(titre.id!, "fr;DROP"),
        throwsArgumentError,
      );
      expect(
        (await depotTitres.chargerTitre(titre.id!))!.languesPreferees,
        isNull,
      );
    });

    test("l'actualisation du titre depuis le site ne les écrase pas", () async {
      final titre = await depotTitres.enregistrerTitre(
        titreReference(idSource),
      );
      await depotTitres.enregistrerLanguesPreferees(titre.id!, 'en,fr');

      // Titre reconstruit par une source : languesPreferees à null.
      await depotTitres.enregistrerTitre(
        titreReference(idSource).copierAvec(resume: 'Résumé mis à jour'),
      );
      // Même chose avec une autre valeur fournie dans l'objet.
      final relu = await depotTitres.enregistrerTitre(
        titre.copierAvec(languesPreferees: 'ja'),
      );
      expect(relu.languesPreferees, 'en,fr');
    });

    test(
      "les langues fournies à l'insertion sont gardées, normalisées",
      () async {
        final titre = await depotTitres.enregistrerTitre(
          titreReference(idSource).copierAvec(languesPreferees: 'FR,fr, en'),
        );
        expect(titre.languesPreferees, 'fr,en');
      },
    );
  });

  test(
    'la recherche à la casse exacte trouve un nom à majuscule accentuée',
    () async {
      await depotTitres.enregistrerTitre(
        Titre(
          idSource: idSource,
          urlTitre: 'https://exemple.org/elise',
          nom: 'Élise et le Château',
          titresAlternatifs: const <TitreAlternatif>[
            TitreAlternatif(nom: 'Étoile du Nord', langue: 'fr'),
          ],
        ),
      );
      expect(await depotTitres.chargerTitres(recherche: 'Élise'), hasLength(1));
      expect(
        await depotTitres.chargerTitres(recherche: 'Château'),
        hasLength(1),
      );
      // Repli de casse ASCII toujours actif sur le reste du mot.
      expect(await depotTitres.chargerTitres(recherche: 'ÉLISE'), hasLength(1));
      // Recherche dans les titres alternatifs, à la casse exacte.
      expect(
        await depotTitres.chargerTitres(recherche: 'Étoile'),
        hasLength(1),
      );
    },
  );

  test('un titre sans idSource est refusé', () async {
    await expectLater(
      depotTitres.enregistrerTitre(
        Titre(urlTitre: 'https://exemple.org/sans-source', nom: 'Sans source'),
      ),
      throwsA(
        isA<ErreurBaseDeDonnees>().having(
          (erreur) => erreur.message,
          'message',
          contains('idSource'),
        ),
      ),
    );
    expect(await depotTitres.chargerTitres(), isEmpty);
  });

  test('un titre d\'une source inexistante est refusé', () async {
    await expectLater(
      depotTitres.enregistrerTitre(titreReference(999)),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(await depotTitres.chargerTitres(), isEmpty);
  });

  test('changer l\'URL vers celle d\'un autre titre lève une '
      'ErreurBaseDeDonnees', () async {
    await depotTitres.enregistrerTitre(titreReference(idSource));
    final autre = await depotTitres.enregistrerTitre(
      Titre(
        idSource: idSource,
        urlTitre: 'https://exemple.org/autre',
        nom: 'A',
      ),
    );
    await expectLater(
      depotTitres.enregistrerTitre(
        autre.copierAvec(urlTitre: urlTitreReference),
      ),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(
      (await depotTitres.chargerTitre(autre.id!))!.urlTitre,
      'https://exemple.org/autre',
    );
  });
}
