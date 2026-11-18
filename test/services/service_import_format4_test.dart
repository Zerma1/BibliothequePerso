// Export et import du format 4 : champs d'un titre modifiés à la main
// (migration 10) et réglage « Archive complète ». Bases en mémoire ; aucun
// réseau.
import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/donnees/gestionnaire_transactions.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_export.dart';
import 'package:bibliotheque_perso/services/service_import.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

/// Une base en mémoire avec ses services d'export et d'import, assemblés
/// comme dans l'application.
class _Bibliotheque {
  _Bibliotheque(this.base)
    : titres = DepotTitres(base),
      parametres = ServiceParametres(DepotParametres(base));

  final Database base;
  final DepotTitres titres;
  final ServiceParametres parametres;

  ServiceExport get export => ServiceExport(
    depotSources: DepotSources(base),
    depotTitres: titres,
    depotChapitres: DepotChapitres(base),
    depotListes: DepotListes(base),
    depotCategories: DepotCategories(base),
    dossierExports: Directory.systemTemp.path,
    serviceParametres: parametres,
    depotTitresSources: DepotTitresSources(base),
  );

  ServiceImport get import => ServiceImport(
    depotSources: DepotSources(base),
    depotTitres: titres,
    depotTitresSources: DepotTitresSources(base),
    depotListes: DepotListes(base),
    depotCategories: DepotCategories(base),
    serviceParametres: parametres,
    depotParametres: DepotParametres(base),
    gestionnaireTransactions: GestionnaireTransactions(base),
  );

  Future<String> json() async =>
      ServiceExport.produireJson(await export.chargerContenu());
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

  /// Un titre MangaDex dont le nom et les catégories ont été modifiés à la
  /// main, et l'archive complète activée.
  Future<Titre> remplirOrigine() async {
    final source = await DepotSources(origine.base)
        .enregistrerSource(sourceMangaDex);
    final titre = await origine.titres.enregistrerTitre(
      Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Site'),
      categories: <String>['Action'],
    );
    await origine.titres.enregistrerModificationManuelle(
      titre.id!,
      nom: 'Mon nom',
      categories: <String>['Drame'],
    );
    await origine.parametres.enregistrerArchiveComplete(true);
    return titre;
  }

  test("l'export contient les champs protégés et l'archive complète", () async {
    await remplirOrigine();
    final json = jsonDecode(await origine.json()) as Map<String, Object?>;
    // Format 4 ou plus récent (5 : description personnelle).
    expect(json['version'], greaterThanOrEqualTo(4));
    final reglages = json['reglages']! as Map<String, Object?>;
    expect(reglages['archiveComplete'], isTrue);
    final titre =
        (json['titres']! as List<Object?>).single! as Map<String, Object?>;
    expect(titre['nom'], 'Mon nom');
    expect(titre['champsManuels'], <String>['nom', 'categories']);
  });

  test('un titre importé garde ses champs protégés', () async {
    await remplirOrigine();
    await DepotSources(cible.base).enregistrerSource(sourceMangaDex);
    final resultat = await cible.import.importerTexte(
      await origine.json(),
      appliquerReglagesGeneraux: true,
    );
    expect(resultat.erreurs, isEmpty);
    expect(resultat.titresAjoutes, 1);
    final importe = (await cible.titres.chargerTitres()).single;
    expect(importe.nom, 'Mon nom');
    expect(importe.champsManuels, <ChampTitre>{
      ChampTitre.nom,
      ChampTitre.categories,
    });
    // Une actualisation depuis le site ne remplace plus ce nom.
    await cible.titres.enregistrerTitre(importe.copierAvec(nom: 'Site'));
    expect((await cible.titres.chargerTitre(importe.id!))!.nom, 'Mon nom');
    expect(await cible.parametres.chargerArchiveComplete(), isTrue);
    expect(resultat.reglagesGenerauxAppliques, isTrue);
    expect(resultat.archiveCompleteActivee, isTrue);
    expect(resultat.resume, contains('Archive complète » activée'));
  });

  test("un import ne coupe jamais l'archive complète de l'appareil", () async {
    await remplirOrigine();
    await origine.parametres.enregistrerArchiveComplete(false);
    await DepotSources(cible.base).enregistrerSource(sourceMangaDex);
    await cible.parametres.enregistrerArchiveComplete(true);
    final resultat = await cible.import.importerTexte(
      await origine.json(),
      appliquerReglagesGeneraux: true,
    );
    expect(await cible.parametres.chargerArchiveComplete(), isTrue);
    expect(resultat.archiveCompleteActivee, isFalse);
    expect(resultat.resume, isNot(contains('Archive complète')));
  });

  test(
    "l'archive complète déjà active n'est pas annoncée dans le bilan",
    () async {
      await remplirOrigine();
      await DepotSources(cible.base).enregistrerSource(sourceMangaDex);
      await cible.parametres.enregistrerArchiveComplete(true);
      final resultat = await cible.import.importerTexte(
        await origine.json(),
        appliquerReglagesGeneraux: true,
      );
      expect(await cible.parametres.chargerArchiveComplete(), isTrue);
      expect(resultat.archiveCompleteActivee, isFalse);
    },
  );

  test("sans transaction, l'import active aussi l'archive complète", () async {
    await remplirOrigine();
    await DepotSources(cible.base).enregistrerSource(sourceMangaDex);
    final sansTransaction = ServiceImport(
      depotSources: DepotSources(cible.base),
      depotTitres: cible.titres,
      depotTitresSources: DepotTitresSources(cible.base),
      depotListes: DepotListes(cible.base),
      depotCategories: DepotCategories(cible.base),
      serviceParametres: cible.parametres,
    );
    final resultat = await sansTransaction.importerTexte(
      await origine.json(),
      appliquerReglagesGeneraux: true,
    );
    expect(await cible.parametres.chargerArchiveComplete(), isTrue);
    expect(resultat.archiveCompleteActivee, isTrue);
  });

  test(
    "sans les réglages généraux, l'archive complète de l'appareil reste",
    () async {
      await remplirOrigine();
      await DepotSources(cible.base).enregistrerSource(sourceMangaDex);
      await cible.import.importerTexte(
        await origine.json(),
        appliquerReglagesGeneraux: false,
      );
      expect(await cible.parametres.chargerArchiveComplete(), isFalse);
    },
  );

  test(
    "un titre existant aux catégories protégées n'est pas complété",
    () async {
      await remplirOrigine();
      final source = await DepotSources(cible.base)
          .enregistrerSource(sourceMangaDex);
      final existant = await cible.titres.enregistrerTitre(
        Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Ici'),
      );
      await cible.titres.enregistrerModificationManuelle(
        existant.id!,
        categories: <String>['Romance'],
      );
      final resultat = await cible.import.importerTexte(await origine.json());
      expect(resultat.titresIgnores, 1);
      final relu = (await cible.titres.chargerTitre(existant.id!))!;
      expect(relu.nom, 'Ici');
      expect(
        (await DepotCategories(cible.base)
                .chargerCategoriesDuTitre(existant.id!))
            .map((c) => c.nom),
        <String>['romance'],
      );
    },
  );

  test("un ancien format (3) s'importe sans champ protégé ni réglage", () {
    final contenu = ServiceImport.lireJson(
      jsonEncode(<String, Object?>{
        'format': 'bibliotheque_perso-export',
        'version': 3,
        'reglages': <String, Object?>{
          'langues': <String>['fr'],
        },
        'titres': <Object?>[
          <String, Object?>{'nom': 'Ancien', 'url': 'https://mangadex.org/x'},
        ],
      }),
    );
    expect(contenu.archiveComplete, isNull);
    expect(contenu.titres.single.champsManuels, isEmpty);
  });

  test('des noms de champs inconnus sont ignorés', () {
    final contenu = ServiceImport.lireJson(
      jsonEncode(<String, Object?>{
        'format': 'bibliotheque_perso-export',
        'version': 4,
        'reglages': <String, Object?>{'archiveComplete': 'oui'},
        'titres': <Object?>[
          <String, Object?>{
            'nom': 'Titre',
            'url': 'https://mangadex.org/x',
            'champsManuels': <Object?>['nom', 'inconnu', 3],
          },
        ],
      }),
    );
    expect(contenu.archiveComplete, isNull);
    expect(contenu.titres.single.champsManuels, <ChampTitre>{ChampTitre.nom});
  });
}
