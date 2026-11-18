// Export et import du format 5 : description personnelle d'un titre
// (migration 12). Bases en mémoire ; aucun réseau.
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
import 'package:bibliotheque_perso/services/constantes_services.dart';
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

/// Texte d'une description sur deux paragraphes.
const String _description = "Mon avis : l'humour.\n\nÀ relire.";

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

  /// Un titre MangaDex avec une description personnelle.
  Future<void> remplirOrigine() async {
    final source = await DepotSources(origine.base)
        .enregistrerSource(sourceMangaDex);
    final titre = await origine.titres.enregistrerTitre(
      Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Site'),
    );
    await origine.titres.enregistrerDescriptionPerso(titre.id!, _description);
  }

  test("l'export contient la description personnelle (format 5)", () async {
    await remplirOrigine();
    final json = jsonDecode(await origine.json()) as Map<String, Object?>;
    expect(json['version'], 5);
    expect(versionFormatExport, 5);
    final titre =
        (json['titres']! as List<Object?>).single! as Map<String, Object?>;
    expect(titre['descriptionPerso'], _description);
  });

  test("un titre sans description l'exporte à null", () async {
    final source = await DepotSources(origine.base)
        .enregistrerSource(sourceMangaDex);
    await origine.titres.enregistrerTitre(
      Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Site'),
    );
    final json = jsonDecode(await origine.json()) as Map<String, Object?>;
    final titre =
        (json['titres']! as List<Object?>).single! as Map<String, Object?>;
    expect(titre.containsKey('descriptionPerso'), isTrue);
    expect(titre['descriptionPerso'], isNull);
  });

  test("un titre ajouté par l'import reçoit sa description", () async {
    await remplirOrigine();
    await DepotSources(cible.base).enregistrerSource(sourceMangaDex);
    final resultat = await cible.import.importerTexte(await origine.json());
    expect(resultat.erreurs, isEmpty);
    expect(resultat.titresAjoutes, 1);
    final importe = (await cible.titres.chargerTitres()).single;
    expect(importe.descriptionPerso, _description);
  });

  test('un titre existant sans description reçoit celle du fichier', () async {
    await remplirOrigine();
    final source = await DepotSources(cible.base)
        .enregistrerSource(sourceMangaDex);
    final existant = await cible.titres.enregistrerTitre(
      Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Ici'),
    );
    final resultat = await cible.import.importerTexte(await origine.json());
    expect(resultat.titresCompletes, 1);
    final relu = (await cible.titres.chargerTitre(existant.id!))!;
    expect(relu.descriptionPerso, _description);
    expect(relu.nom, 'Ici');
  });

  test("la description d'un titre existant n'est jamais remplacée", () async {
    await remplirOrigine();
    final source = await DepotSources(cible.base)
        .enregistrerSource(sourceMangaDex);
    final existant = await cible.titres.enregistrerTitre(
      Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Ici'),
    );
    await cible.titres.enregistrerDescriptionPerso(
      existant.id!,
      'Ma description ici',
    );
    final resultat = await cible.import.importerTexte(await origine.json());
    expect(resultat.titresIgnores, 1);
    expect(
      (await cible.titres.chargerTitre(existant.id!))!.descriptionPerso,
      'Ma description ici',
    );
  });

  test("sans transaction, l'import écrit aussi la description", () async {
    await remplirOrigine();
    final source = await DepotSources(cible.base)
        .enregistrerSource(sourceMangaDex);
    final existant = await cible.titres.enregistrerTitre(
      Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Ici'),
    );
    final sansTransaction = ServiceImport(
      depotSources: DepotSources(cible.base),
      depotTitres: cible.titres,
      depotTitresSources: DepotTitresSources(cible.base),
      depotListes: DepotListes(cible.base),
      depotCategories: DepotCategories(cible.base),
      serviceParametres: cible.parametres,
    );
    await sansTransaction.importerTexte(await origine.json());
    expect(
      (await cible.titres.chargerTitre(existant.id!))!.descriptionPerso,
      _description,
    );
  });

  test("un ancien format (4) s'importe sans description", () {
    final contenu = ServiceImport.lireJson(
      jsonEncode(<String, Object?>{
        'format': 'bibliotheque_perso-export',
        'version': 4,
        'titres': <Object?>[
          <String, Object?>{'nom': 'Ancien', 'url': 'https://mangadex.org/x'},
        ],
      }),
    );
    expect(contenu.titres.single.descriptionPerso, isNull);
  });

  test(
    'une description vide, mal typée ou trop longue est lue sans erreur',
    () {
      TitreImporte lire(Object? description) => ServiceImport.lireJson(
        jsonEncode(<String, Object?>{
          'format': 'bibliotheque_perso-export',
          'version': 5,
          'titres': <Object?>[
            <String, Object?>{
              'nom': 'Titre',
              'url': 'https://mangadex.org/x',
              'descriptionPerso': description,
            },
          ],
        }),
      ).titres.single;

      expect(lire('  \n ').descriptionPerso, isNull);
      expect(lire(42).descriptionPerso, isNull);
      expect(lire('  Texte  ').descriptionPerso, 'Texte');
      // Trop longue (fichier modifié à la main) : coupée à la limite.
      expect(
        lire('x' * (longueurMaxDescriptionPerso + 10)).descriptionPerso,
        hasLength(longueurMaxDescriptionPerso),
      );
    },
  );
}
