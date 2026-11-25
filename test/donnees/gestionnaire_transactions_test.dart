import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/donnees/gestionnaire_transactions.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

/// Exception propre au test, levée pour annuler la transaction.
class _Annulation implements Exception {
  const _Annulation();
}

void main() {
  late Database base;
  late GestionnaireTransactions gestionnaire;
  late DepotSources depotSources;
  late DepotTitres depotTitres;
  late DepotTitresSources depotTitresSources;
  late DepotListes depotListes;
  late DepotCategories depotCategories;
  late DepotParametres depotParametres;

  const sourceSecondaire = Source(
    nom: 'Site secondaire',
    urlBase: 'https://secondaire.exemple',
    typeSource: TypeSource.madara,
  );
  const urlSecondaire = 'https://secondaire.exemple/manga/reference';

  setUp(() async {
    base = await ouvrirBaseDeTest();
    gestionnaire = GestionnaireTransactions(base);
    depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotTitresSources = DepotTitresSources(base);
    depotListes = DepotListes(base);
    depotCategories = DepotCategories(base);
    depotParametres = DepotParametres(base);
  });

  tearDown(() => base.close());

  /// Nombre de lignes de chaque table touchée par un import.
  Future<Map<String, int>> compterLignes() async {
    final resultat = <String, int>{};
    for (final table in <String>[
      'sources',
      'titres',
      'titres_sources',
      'titres_alternatifs',
      'listes',
      'titres_listes',
      'categories',
      'titres_categories',
      'parametres',
    ]) {
      // Nom de table constant, choisi par le test : pas de valeur extérieure.
      resultat[table] =
          Sqflite.firstIntValue(
            await base.rawQuery('SELECT COUNT(*) FROM $table'),
          ) ??
          0;
    }
    return resultat;
  }

  /// Fait, dans [txn], toutes les écritures et lectures d'un import : sites,
  /// titre (avec catégories), site secondaire, liste, langues, couverture et
  /// réglage. Renvoie l'identifiant du titre créé.
  Future<int> ecrireCommeUnImport(Transaction txn) async {
    expect(await depotSources.chargerSources(executeur: txn), isEmpty);
    final principale = await depotSources.enregistrerSource(
      sourceMangaDex,
      executeur: txn,
    );
    final secondaire = await depotSources.enregistrerSource(
      sourceSecondaire,
      executeur: txn,
    );
    expect(await depotSources.chargerSources(executeur: txn), hasLength(2));
    expect(
      await depotTitresSources.chargerTitreParUrl(
        urlTitreReference,
        executeur: txn,
      ),
      isNull,
    );

    final titre = await depotTitres.enregistrerTitre(
      titreReference(principale.id!),
      categories: categoriesReference,
      executeur: txn,
    );
    final idTitre = titre.id!;
    // Relu dans la transaction : titres alternatifs compris.
    expect(
      titre.titresAlternatifs,
      hasLength(titresAlternatifsReference.length),
    );

    // Ligne principale créée par le déclencheur de la migration 7, visible
    // dans la transaction.
    final liens = await depotTitresSources.chargerLiensTitre(
      idTitre,
      executeur: txn,
    );
    expect(liens, hasLength(1));
    expect(liens.single.estPrincipale, isTrue);

    await depotTitresSources.ajouterSourceSecondaire(
      idTitre,
      secondaire.id!,
      urlSecondaire,
      executeur: txn,
    );
    expect(
      (await depotTitresSources.chargerLienParUrl(
        urlSecondaire,
        executeur: txn,
      ))?.idTitre,
      idTitre,
    );
    expect(
      (await depotTitresSources.chargerTitreParUrl(
        urlSecondaire,
        executeur: txn,
      ))?.id,
      idTitre,
    );
    await depotTitresSources.marquerLienSeul(
      idTitre,
      secondaire.id!,
      true,
      executeur: txn,
    );

    final liste = await depotListes.creerListe('À relire', executeur: txn);
    await depotListes.ajouterTitre(liste.id!, idTitre, executeur: txn);
    expect(
      (await depotListes.chargerListesDuTitre(
        idTitre,
        executeur: txn,
      )).map((l) => l.nom),
      contains('À relire'),
    );
    expect(
      (await depotListes.chargerListes(executeur: txn)).map((l) => l.nom),
      contains('À relire'),
    );

    expect(
      await depotCategories.chargerCategoriesDuTitre(idTitre, executeur: txn),
      hasLength(categoriesReference.length),
    );
    await depotCategories.enregistrerCategorie('Isekai', executeur: txn);

    expect(
      await depotTitres.enregistrerLanguesPreferees(
        idTitre,
        'fr,en',
        executeur: txn,
      ),
      isTrue,
    );
    expect(
      await depotTitres.enregistrerCouvertureChoisie(
        idTitre,
        'https://uploads.mangadex.org/covers/autre.jpg',
        executeur: txn,
      ),
      isTrue,
    );
    await depotParametres.enregistrerTexte(
      'langues_lecture',
      'fr',
      executeur: txn,
    );
    expect(
      await depotParametres.chargerTexte('langues_lecture', executeur: txn),
      'fr',
    );

    final relu = await depotTitres.chargerTitre(idTitre, executeur: txn);
    expect(relu?.languesPreferees, 'fr,en');
    expect(await depotTitres.chargerTitres(executeur: txn), hasLength(1));
    return idTitre;
  }

  group('executerEnTransaction', () {
    test('validée : toutes les écritures sont enregistrées', () async {
      final idTitre = await gestionnaire.executerEnTransaction(
        ecrireCommeUnImport,
      );

      final titre = await depotTitres.chargerTitre(idTitre);
      expect(titre?.nom, nomTitreReference);
      expect(titre?.languesPreferees, 'fr,en');
      expect(
        titre?.couvertureChoisie,
        'https://uploads.mangadex.org/covers/autre.jpg',
      );
      final liens = await depotTitresSources.chargerLiensTitre(idTitre);
      expect(liens, hasLength(2));
      expect(liens.last.estLienSeul, isTrue);
      expect(
        (await depotListes.chargerListesDuTitre(idTitre)).map((l) => l.nom),
        contains('À relire'),
      );
      expect(
        await depotCategories.chargerCategoriesDuTitre(idTitre),
        hasLength(categoriesReference.length),
      );
      expect(await depotParametres.chargerTexte('langues_lecture'), 'fr');
    });

    test('annulée par une exception : rien n\'est écrit', () async {
      final avant = await compterLignes();

      await expectLater(
        gestionnaire.executerEnTransaction<void>((txn) async {
          await ecrireCommeUnImport(txn);
          throw const _Annulation();
        }),
        throwsA(isA<_Annulation>()),
      );

      expect(await compterLignes(), avant);
      expect(await depotSources.chargerSources(), isEmpty);
      expect(await depotTitres.chargerTitres(), isEmpty);
      expect(await depotListes.chargerListeParNom('À relire'), isNull);
      expect(await depotParametres.chargerTexte('langues_lecture'), isNull);
    });

    test("une ErreurBaseDeDonnees rattrapée n'interrompt pas la "
        'transaction', () async {
      await gestionnaire.executerEnTransaction((txn) async {
        await depotListes.creerListe('Ma liste', executeur: txn);
        // Contrainte UNIQUE : seule l'instruction fautive est annulée.
        await expectLater(
          depotListes.creerListe('Ma liste', executeur: txn),
          throwsA(isA<ErreurBaseDeDonnees>()),
        );
        await depotSources.enregistrerSource(sourceMangaDex, executeur: txn);
        await expectLater(
          depotSources.enregistrerSource(
            sourceMangaDex.copierAvec(nom: 'Doublon'),
            executeur: txn,
          ),
          throwsA(isA<ErreurBaseDeDonnees>()),
        );
        await depotListes.creerListe('Autre liste', executeur: txn);
      });

      expect(await depotListes.chargerListeParNom('Ma liste'), isNotNull);
      expect(await depotListes.chargerListeParNom('Autre liste'), isNotNull);
      expect(await depotSources.chargerSources(), hasLength(1));
    });

    test('annulée après une erreur rattrapée : rien n\'est écrit', () async {
      final avant = await compterLignes();
      await expectLater(
        gestionnaire.executerEnTransaction<void>((txn) async {
          final source = await depotSources.enregistrerSource(
            sourceMangaDex,
            executeur: txn,
          );
          // Titre sur une source absente : refusé avant toute écriture.
          await expectLater(
            depotTitres.enregistrerTitre(
              titreReference(source.id! + 100),
              executeur: txn,
            ),
            throwsA(isA<ErreurBaseDeDonnees>()),
          );
          await depotTitres.enregistrerTitre(
            titreReference(source.id!),
            executeur: txn,
          );
          throw const _Annulation();
        }),
        throwsA(isA<_Annulation>()),
      );
      expect(await compterLignes(), avant);
    });
  });

  group('sans exécuteur (comportement d\'origine)', () {
    test('chaque écriture est validée seule', () async {
      final source = await depotSources.enregistrerSource(sourceMangaDex);
      final titre = await depotTitres.enregistrerTitre(
        titreReference(source.id!),
        categories: categoriesReference,
      );
      final liste = await depotListes.creerListe('Ma liste');
      await depotListes.ajouterTitre(liste.id!, titre.id!);
      await expectLater(
        depotListes.creerListe('Ma liste'),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );

      // Les écritures réussies restent après l'échec.
      expect(await depotTitres.chargerTitres(), hasLength(1));
      expect(
        (await depotListes.chargerListesDuTitre(titre.id!)).map((l) => l.nom),
        contains('Ma liste'),
      );
      expect(
        await depotTitresSources.chargerLiensTitre(titre.id!),
        hasLength(1),
      );
    });

    test('enregistrerTitre reste atomique (source absente : rien '
        "d'écrit)", () async {
      final avant = await compterLignes();
      await expectLater(
        depotTitres.enregistrerTitre(
          titreReference(42),
          categories: categoriesReference,
        ),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(await compterLignes(), avant);
    });
  });

  group('executerAtomiquement', () {
    test('avec la base comme exécuteur : transaction propre, annulée en cas '
        "d'erreur", () async {
      final avant = await compterLignes();
      await expectLater(
        GestionnaireTransactions.executerAtomiquement<void>(base, base, (
          executeur,
        ) async {
          expect(executeur, isA<Transaction>());
          await executeur.insert('listes', <String, Object?>{
            'nom': 'Temporaire',
            'est_systeme': 0,
            'ordre': 99,
          });
          throw const _Annulation();
        }),
        throwsA(isA<_Annulation>()),
      );
      expect(await compterLignes(), avant);
    });

    test('avec une transaction : pas de transaction imbriquée', () async {
      await gestionnaire.executerEnTransaction((txn) async {
        final resultat = await GestionnaireTransactions.executerAtomiquement(
          base,
          txn,
          (executeur) async {
            expect(identical(executeur, txn), isTrue);
            return 7;
          },
        );
        expect(resultat, 7);
      });
    });
  });
}
