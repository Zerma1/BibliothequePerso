// Export (format 3) et import des regroupements de catégories, et comptage
// léger de la bibliothèque à l'import. Bases en mémoire ; aucun réseau.
import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_equivalences_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/donnees/gestionnaire_transactions.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_categories.dart';
import 'package:bibliotheque_perso/services/service_export.dart';
import 'package:bibliotheque_perso/services/service_import.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

/// Une base en mémoire avec ses services d'export, d'import et de
/// catégories, assemblés comme dans l'application.
class _Bibliotheque {
  _Bibliotheque(this.base)
    : titres = DepotTitres(base),
      categories = ServiceCategories.surBase(base);

  final Database base;
  final DepotTitres titres;
  final ServiceCategories categories;

  ServiceExport get export => ServiceExport(
    depotSources: DepotSources(base),
    depotTitres: titres,
    depotChapitres: DepotChapitres(base),
    depotListes: DepotListes(base),
    depotCategories: DepotCategories(base),
    dossierExports: Directory.systemTemp.path,
    horloge: () => DateTime.utc(2026, 11, 17, 10),
    depotTitresSources: DepotTitresSources(base),
    depotEquivalences: DepotEquivalencesCategories(base),
  );

  ServiceImport import({bool avecEquivalences = true, bool tout = true}) =>
      ServiceImport(
        depotSources: DepotSources(base),
        depotTitres: titres,
        depotTitresSources: DepotTitresSources(base),
        depotListes: DepotListes(base),
        depotCategories: DepotCategories(base),
        serviceParametres: ServiceParametres(DepotParametres(base)),
        depotParametres: DepotParametres(base),
        gestionnaireTransactions: tout ? GestionnaireTransactions(base) : null,
        depotEquivalences: avecEquivalences
            ? DepotEquivalencesCategories(base)
            : null,
      );

  Future<String> json() async =>
      ServiceExport.produireJson(await export.chargerContenu());

  Future<int> id(String nom) async => (await categories.chargerCategories())
      .firstWhere((categorie) => categorie.nom == nom)
      .id!;

  /// Groupes sous forme lisible : « survie ← supervivencia, survival ».
  Future<List<String>> groupes() async => <String>[
    for (final groupe in await categories.chargerGroupes())
      '${groupe.reference.nom} ← '
          '${groupe.rattachees.map((c) => c.nom).join(', ')}',
  ];
}

void main() {
  late _Bibliotheque origine;
  late _Bibliotheque cible;

  setUp(() async {
    origine = _Bibliotheque(await ouvrirBaseDeTest());
    cible = _Bibliotheque(await ouvrirBaseDeTest());
  });

  tearDown(() async {
    await origine.base.close();
    await cible.base.close();
  });

  /// Un site MangaDex, un titre aux catégories anglaises et françaises, et
  /// deux groupes (dont un dont une catégorie n'a plus aucun titre).
  Future<void> remplirOrigine() async {
    final source = await DepotSources(origine.base)
        .enregistrerSource(sourceMangaDex);
    await origine.titres.enregistrerTitre(
      Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Mort'),
      categories: <String>['Survival', 'Survie', 'Comedy', 'Comédie'],
    );
    final supervivencia = await DepotCategories(origine.base)
        .enregistrerCategorie('Supervivencia');
    await origine.categories.regrouperCategories(
      await origine.id('survie'),
      <int>[await origine.id('survival'), supervivencia.id!],
    );
    await origine.categories.rattacherCategorie(
      await origine.id('comedy'),
      await origine.id('comédie'),
    );
  }

  /// Texte d'un export de format 3 minimal (aucun titre) avec ces
  /// regroupements.
  String exportAvec(List<Object?> equivalences) => jsonEncode(<String, Object?>{
    'format': 'bibliotheque_perso-export',
    'version': 3,
    'titres': <Object?>[],
    'equivalences': equivalences,
  });

  group('export', () {
    test('le JSON (format 3 et suivants) et le Markdown contiennent les '
        'regroupements', () async {
      await remplirOrigine();
      final contenu = await origine.export.chargerContenu();
      final json = jsonDecode(
        ServiceExport.produireJson(contenu),
      ) as Map<String, Object?>;
      // Format 4 depuis les champs protégés et l'archive complète.
      expect(json['version'], 4);
      expect(json['equivalences'], <Map<String, Object?>>[
        <String, Object?>{'categorie': 'comedy', 'reference': 'comédie'},
        <String, Object?>{'categorie': 'supervivencia', 'reference': 'survie'},
        <String, Object?>{'categorie': 'survival', 'reference': 'survie'},
      ]);
      final markdown = ServiceExport.produireMarkdown(contenu);
      expect(markdown, contains('## Catégories regroupées'));
      expect(markdown, contains('- survie ← supervivencia, survival'));
    });

    test(
      'sans regroupement, la liste est vide et le Markdown sans section',
      () async {
        final contenu = await origine.export.chargerContenu();
        expect(
          (jsonDecode(ServiceExport.produireJson(contenu))
              as Map<String, Object?>)['equivalences'],
          isEmpty,
        );
        expect(
          ServiceExport.produireMarkdown(contenu),
          isNot(contains('Catégories regroupées')),
        );
      },
    );
  });

  group('import', () {
    test('un export réimporté recrée les groupes, catégories sans titre '
        'comprises', () async {
      await remplirOrigine();
      final resultat = await cible.import().importerTexte(await origine.json());

      expect(resultat.versionFormat, 4);
      expect(resultat.regroupementsAjoutes, 3);
      expect(resultat.erreurs, isEmpty);
      expect(resultat.resume, contains('3 catégories regroupées'));
      expect(await cible.groupes(), <String>[
        'comédie ← comedy',
        'survie ← supervivencia, survival',
      ]);
      // Réimporter ne change rien et ne signale rien.
      final encore = await cible.import().importerTexte(await origine.json());
      expect(encore.regroupementsAjoutes, 0);
      expect(encore.erreurs, isEmpty);
    });

    test('un regroupement incohérent est refusé ligne par ligne, sans '
        'arrêter les autres', () async {
      final resultat = await cible.import().importerTexte(
        exportAvec(<Object?>[
          <String, Object?>{'categorie': 'Survival', 'reference': 'Survie'},
          // « survie » est déjà une référence : elle ne peut pas être
          // rattachée.
          <String, Object?>{'categorie': 'survie', 'reference': 'survivre'},
          // « survival » est rattachée : elle ne peut pas servir de
          // référence.
          <String, Object?>{
            'categorie': 'supervivencia',
            'reference': 'survival',
          },
          <String, Object?>{'categorie': 'Comedy', 'reference': 'comedy'},
          <String, Object?>{'categorie': 'drame'},
          'illisible',
          <String, Object?>{'categorie': 'Drama', 'reference': 'Drame'},
        ]),
      );
      expect(resultat.regroupementsAjoutes, 2);
      expect(await cible.groupes(), <String>[
        'drame ← drama',
        'survie ← survival',
      ]);
      expect(resultat.erreurs.map((e) => e.partie).toSet(), <PartieImport>{
        PartieImport.equivalence,
      });
      expect(
        resultat.erreurs.map((e) => e.numero),
        unorderedEquals(<int>[2, 3, 4, 5, 6]),
      );
      expect(
        resultat.erreurs.firstWhere((e) => e.numero == 3).description,
        contains('ne peut pas servir de référence'),
      );
    });

    test('le choix du client sur cet appareil est gardé', () async {
      final source = await DepotSources(cible.base)
          .enregistrerSource(sourceMangaDex);
      await cible.titres.enregistrerTitre(
        Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Mort'),
        categories: <String>['Comedy', 'Humour', 'Comédie'],
      );
      await cible.categories.rattacherCategorie(
        await cible.id('comedy'),
        await cible.id('humour'),
      );
      final resultat = await cible.import().importerTexte(
        exportAvec(<Map<String, Object?>>[
          <String, Object?>{'categorie': 'comedy', 'reference': 'comédie'},
        ]),
      );
      expect(resultat.regroupementsAjoutes, 0);
      expect(
        resultat.erreurs.single.message,
        contains('déjà regroupée avec « humour »'),
      );
      expect(await cible.groupes(), <String>['humour ← comedy']);
    });

    test('sans transaction commune, même résultat', () async {
      await remplirOrigine();
      final resultat = await cible
          .import(tout: false)
          .importerTexte(await origine.json());
      expect(resultat.regroupementsAjoutes, 3);
      expect(await cible.groupes(), hasLength(2));
    });

    test('sans dépôt des regroupements, une erreur le signale', () async {
      final resultat = await cible
          .import(avecEquivalences: false)
          .importerTexte(
            exportAvec(<Map<String, Object?>>[
              <String, Object?>{'categorie': 'survival', 'reference': 'survie'},
            ]),
          );
      expect(resultat.regroupementsAjoutes, 0);
      expect(resultat.erreurs.single.partie, PartieImport.equivalence);
    });

    test(
      'un export de format 2 (sans regroupements) se lit toujours',
      () async {
        final contenu = ServiceImport.lireJson(
          jsonEncode(<String, Object?>{
            'format': 'bibliotheque_perso-export',
            'version': 2,
            'titres': <Object?>[],
          }),
        );
        expect(contenu.versionFormat, 2);
        expect(contenu.equivalences, isEmpty);
        expect(contenu.erreursLecture, isEmpty);
      },
    );

    test('la bibliothèque vide est détectée par un simple comptage', () async {
      // Réglages appliqués seulement si la bibliothèque est vide.
      final fichier = jsonEncode(<String, Object?>{
        'format': 'bibliotheque_perso-export',
        'version': 3,
        'reglages': <String, Object?>{
          'langues': <String>['pt-br', 'en'],
        },
        'titres': <Object?>[],
      });
      final vide = await cible.import().importerTexte(fichier);
      expect(vide.reglagesGenerauxAppliques, isTrue);
      expect(
        await ServiceParametres(DepotParametres(cible.base)).chargerLangues(),
        <String>['pt-br', 'en'],
      );

      final source = await DepotSources(cible.base)
          .enregistrerSource(sourceMangaDex);
      await cible.titres.enregistrerTitre(
        Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Mort'),
      );
      final pasVide = await cible.import().importerTexte(fichier);
      expect(pasVide.reglagesGenerauxAppliques, isFalse);
    });
  });
}
