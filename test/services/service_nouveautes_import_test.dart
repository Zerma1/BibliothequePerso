// Badge « Nouveau » après un import (relecture de U5) : la première
// vérification d'un titre importé, sur un site sans date de publication, ne
// doit marquer aucun chapitre comme nouveau. Réponses MangaDex enregistrées
// (dates de publication retirées) et base en mémoire ; aucun appel réseau.
import 'dart:convert';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_import.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Flux MangaDex d'une seule page, **sans date de publication** : se
/// comporte comme un site qui ne date pas ses chapitres.
String _fluxSansDates() {
  final flux = lireJsonExemple('manga_flux_page1.json');
  final donnees = <Object?>[
    for (final entree in flux['data']! as List<Object?>)
      if (entree is Map<String, Object?>)
        <String, Object?>{
          ...entree,
          'attributes': <String, Object?>{
            ...entree['attributes']! as Map<String, Object?>,
            'publishAt': null,
          },
        },
  ];
  return jsonEncode(<String, Object?>{
    ...flux,
    'data': donnees,
    'total': donnees.length,
  });
}

/// Export minimal : MangaDex et le titre de référence, suivi.
final String _export = jsonEncode(<String, Object?>{
  'format': 'bibliotheque_perso-export',
  'version': 2,
  'sources': <Object?>[
    <String, Object?>{
      'nom': 'MangaDex',
      'urlBase': 'https://mangadex.org',
      'type': 'mangaDex',
    },
  ],
  'titres': <Object?>[
    <String, Object?>{
      'nom': nomTitreReference,
      'url': urlTitreReference,
      'urlSource': 'https://mangadex.org',
      'listes': <String>[nomListeSuivis],
    },
  ],
});

void main() {
  late Database base;
  late ServiceBibliotheque service;
  late ServiceImport import;
  late DepotTitres depotTitres;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    final fiche = lireExemple('exemples_json/manga_fiche.json');
    final flux = _fluxSansDates();
    final client = creerClientTest((http.Request requete) async {
      final chemin = requete.url.path;
      if (chemin.endsWith('/feed')) return reponseJson(flux);
      if (chemin.startsWith('/manga/')) return reponseJson(fiche);
      return http.Response('introuvable', 404);
    }, HorlogeFactice());
    final depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    final parametres = ServiceParametres(DepotParametres(base));
    service = ServiceBibliotheque(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotChapitres: DepotChapitres(base),
      depotListes: DepotListes(base),
      depotCategories: DepotCategories(base),
      fabriqueSources: FabriqueSources(client),
      serviceAjoutSite: ServiceAjoutSite(
        depotSources,
        DetecteurTypeSite(client),
      ),
      client: client,
      serviceParametres: parametres,
      depotTitresSources: DepotTitresSources(base),
    );
    import = ServiceImport(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotTitresSources: DepotTitresSources(base),
      depotListes: DepotListes(base),
      depotCategories: DepotCategories(base),
      serviceParametres: parametres,
    );
  });

  tearDown(() => base.close());

  /// Importe l'export, puis recule l'ajout des sites de deux heures : la
  /// vérification qui suit a lieu « deux heures après l'import ».
  Future<Titre> importerIlYADeuxHeures() async {
    final resultat = await import.importerTexte(_export);
    expect(resultat.titresAjoutes, 1);
    await base.rawUpdate(
      'UPDATE titres_sources SET date_ajout = date_ajout - ?',
      <Object?>[const Duration(hours: 2).inMilliseconds],
    );
    return (await depotTitres.chargerTitreParUrl(urlTitreReference))!;
  }

  test('la première vérification deux heures après un import ne marque '
      'aucun chapitre « Nouveau » (site sans dates)', () async {
    final titre = await importerIlYADeuxHeures();

    final resultat = await service.actualiserTitre(titre);
    expect(resultat.nombreNouveauxChapitres, greaterThan(0));

    final lignes = await service.chargerDernieresParutions();
    final ligne = lignes.single;
    expect(ligne.dernierChapitre, isNotNull);
    expect(ligne.dernierChapitre!.datePublication, isNull);
    // Datés de l'ajout du site : ce sont les chapitres déjà parus alors.
    expect(ligne.dernierChapitre!.dateDetection, ligne.dateAjoutSite);
    expect(ligne.estDecouvertApresAjout, isFalse);
    expect(ligne.estNouveaute(DateTime.now().toUtc()), isFalse);
  });

  test('un titre déjà vérifié sans chapitre (en attente) garde ses '
      'nouveautés à la vérification suivante', () async {
    final titre = await importerIlYADeuxHeures();
    // Une vérification a eu lieu après l'ajout, sans trouver de chapitre.
    await depotTitres.enregistrerDateVerification(
      titre.id!,
      DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    final verifie = (await depotTitres.chargerTitre(titre.id!))!;

    await service.actualiserTitre(verifie);

    final ligne = (await service.chargerDernieresParutions()).single;
    expect(ligne.estDecouvertApresAjout, isTrue);
    expect(ligne.estNouveaute(DateTime.now().toUtc()), isTrue);
  });
}
