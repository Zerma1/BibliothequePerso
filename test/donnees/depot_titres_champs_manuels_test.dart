import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTitres depot;
  late DepotCategories depotCategories;
  late Titre titre;
  late Titre depuisLeSite;

  Future<List<String>> categoriesDe(int idTitre) async => <String>[
    for (final categorie in await depotCategories.chargerCategoriesDuTitre(
      idTitre,
    ))
      categorie.nom,
  ]..sort();

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotTitres(base);
    depotCategories = DepotCategories(base);
    final idSource = (await DepotSources(
      base,
    ).enregistrerSource(sourceMangaDex)).id!;
    depuisLeSite = titreReference(idSource)
        .copierAvec(niveauContenu: niveauContenuTousPublics);
    titre = await depot.enregistrerTitre(
      depuisLeSite,
      categories: <String>['Action', 'Comedy'],
    );
  });

  tearDown(() async {
    await base.close();
  });

  test('un titre neuf n\'a aucun champ manuel', () async {
    expect(titre.champsManuels, isEmpty);
    final ligne = (await base.query('titres')).single;
    expect(ligne['champs_manuels'], '[]');
  });

  test('la modification manuelle écrit seulement les champs donnés et les '
      'verrouille', () async {
    final modifie = await depot.enregistrerModificationManuelle(
      titre.id!,
      nom: '  La fille de la Mort  ',
      resume: 'Mon résumé.',
      titresAlternatifs: const <TitreAlternatif>[
        TitreAlternatif(nom: 'Shinigami', langue: 'ja'),
        TitreAlternatif(nom: '   '),
      ],
      categories: <String>['Fantasy'],
      niveauContenu: niveauContenuSuggestif,
    );

    expect(modifie.nom, 'La fille de la Mort');
    expect(modifie.resume, 'Mon résumé.');
    expect(modifie.titresAlternatifs.map((a) => a.nom), <String>['Shinigami']);
    expect(modifie.niveauContenu, niveauContenuSuggestif);
    expect(await categoriesDe(titre.id!), <String>['fantasy']);
    // Champs non donnés : inchangés et non verrouillés.
    expect(modifie.auteur, titre.auteur);
    expect(modifie.statut, titre.statut);
    expect(modifie.urlCouverture, titre.urlCouverture);
    expect(modifie.champsManuels, <ChampTitre>{
      ChampTitre.nom,
      ChampTitre.resume,
      ChampTitre.titresAlternatifs,
      ChampTitre.categories,
      ChampTitre.niveauContenu,
    });
  });

  test('les verrous s\'ajoutent aux précédents', () async {
    await depot.enregistrerModificationManuelle(titre.id!, nom: 'Nom perso');
    final modifie = await depot.enregistrerModificationManuelle(
      titre.id!,
      auteur: 'Moi',
    );
    expect(modifie.champsManuels, <ChampTitre>{
      ChampTitre.nom,
      ChampTitre.auteur,
    });
    expect(modifie.nom, 'Nom perso');
    expect(modifie.auteur, 'Moi');
  });

  test('un texte vide efface la valeur et la garde verrouillée', () async {
    final modifie = await depot.enregistrerModificationManuelle(
      titre.id!,
      resume: '   ',
      statut: '',
      niveauContenu: '',
    );
    expect(modifie.resume, isNull);
    expect(modifie.statut, isNull);
    expect(modifie.niveauContenu, isNull);

    final actualise = await depot.enregistrerTitre(depuisLeSite);
    expect(actualise.resume, isNull);
    expect(actualise.statut, isNull);
    expect(actualise.niveauContenu, isNull);
  });

  test('l\'actualisation par enregistrerTitre respecte les champs '
      'verrouillés', () async {
    await depot.enregistrerModificationManuelle(
      titre.id!,
      nom: 'Nom perso',
      resume: 'Résumé perso',
      statut: 'Abandonné',
      titresAlternatifs: const <TitreAlternatif>[
        TitreAlternatif(nom: 'Alias perso'),
      ],
      categories: <String>['Perso'],
      niveauContenu: niveauContenuErotique,
    );

    // Le site renvoie d'autres valeurs (dont des champs non verrouillés).
    final actualise = await depot.enregistrerTitre(
      depuisLeSite.copierAvec(
        nom: 'Nom du site',
        resume: 'Résumé du site',
        statut: 'Terminé',
        auteur: 'Auteur du site',
        urlCouverture: 'https://uploads.mangadex.org/covers/autre.jpg',
        niveauContenu: niveauContenuTousPublics,
        titresAlternatifs: const <TitreAlternatif>[
          TitreAlternatif(nom: 'Alias du site'),
        ],
      ),
      categories: <String>['Action', 'Drama'],
    );

    expect(actualise.nom, 'Nom perso');
    expect(actualise.resume, 'Résumé perso');
    expect(actualise.statut, 'Abandonné');
    expect(actualise.niveauContenu, niveauContenuErotique);
    expect(actualise.titresAlternatifs.map((a) => a.nom), <String>[
      'Alias perso',
    ]);
    expect(await categoriesDe(titre.id!), <String>['perso']);
    // Non verrouillés : mis à jour depuis le site.
    expect(actualise.auteur, 'Auteur du site');
    expect(
      actualise.urlCouverture,
      'https://uploads.mangadex.org/covers/autre.jpg',
    );
    // Les verrous ne bougent pas.
    expect(actualise.champsManuels, hasLength(6));
  });

  test('un Titre avec id (et sans champs manuels) ne retire pas les '
      'verrous', () async {
    final modifie = await depot.enregistrerModificationManuelle(
      titre.id!,
      nom: 'Nom perso',
    );
    final actualise = await depot.enregistrerTitre(
      modifie.copierAvec(
        nom: 'Nom du site',
        champsManuels: const <ChampTitre>{},
      ),
    );
    expect(actualise.nom, 'Nom perso');
    expect(actualise.champsManuels, <ChampTitre>{ChampTitre.nom});
  });

  test('rendre un champ au site : la valeur du site revient à la prochaine '
      'actualisation', () async {
    await depot.enregistrerModificationManuelle(
      titre.id!,
      nom: 'Nom perso',
      resume: 'Résumé perso',
      categories: <String>['Perso'],
    );

    expect(
      await depot.rendreChampsAuSite(titre.id!, <ChampTitre>{
        ChampTitre.nom,
        ChampTitre.categories,
        // Pas verrouillé : ignoré.
        ChampTitre.auteur,
      }),
      isTrue,
    );
    final rendu = (await depot.chargerTitre(titre.id!))!;
    // La valeur ne change pas tout de suite.
    expect(rendu.nom, 'Nom perso');
    expect(rendu.champsManuels, <ChampTitre>{ChampTitre.resume});

    final actualise = await depot.enregistrerTitre(
      depuisLeSite,
      categories: <String>['Action'],
    );
    expect(actualise.nom, nomTitreReference);
    expect(await categoriesDe(titre.id!), <String>['action']);
    // Toujours verrouillé.
    expect(actualise.resume, 'Résumé perso');
  });

  test('rendre au site un titre inexistant renvoie false', () async {
    expect(
      await depot.rendreChampsAuSite(999, <ChampTitre>{ChampTitre.nom}),
      isFalse,
    );
  });

  test('erreurs : nom vide, niveau inconnu, titre inexistant ; rien '
      'd\'écrit', () async {
    await expectLater(
      depot.enregistrerModificationManuelle(titre.id!, nom: '  '),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.enregistrerModificationManuelle(
        titre.id!,
        resume: 'Ne doit pas être écrit',
        niveauContenu: 'inconnu',
      ),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.enregistrerModificationManuelle(999, nom: 'Nom'),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(await depot.chargerTitre(titre.id!), titre);
  });

  test('sans champ donné, rien n\'est écrit', () async {
    expect(await depot.enregistrerModificationManuelle(titre.id!), titre);
  });

  test('dans une transaction extérieure annulée, rien n\'est écrit', () async {
    await expectLater(
      base.transaction((txn) async {
        await depot.enregistrerModificationManuelle(
          titre.id!,
          nom: 'Nom perso',
          executeur: txn,
        );
        throw StateError('annulation');
      }),
      throwsA(isA<StateError>()),
    );
    expect(await depot.chargerTitre(titre.id!), titre);
  });

  test('à l\'insertion, les champs manuels fournis sont gardés', () async {
    final importe = await depot.enregistrerTitre(
      depuisLeSite.copierAvec(
        urlTitre: 'https://mangadex.org/title/autre',
        champsManuels: <ChampTitre>{ChampTitre.auteur},
      ),
    );
    expect(importe.champsManuels, <ChampTitre>{ChampTitre.auteur});
  });
}
