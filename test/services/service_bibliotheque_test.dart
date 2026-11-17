// Tests de bout en bout de la couche services : réponses MangaDex réelles
// enregistrées (aucun appel réseau) et base SQLite en mémoire.
import 'dart:convert';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Réponse du flux réduite à une seule page (total = nombre d'entrées), pour
/// que le service n'ait pas à paginer dans ce test.
String _fluxUnePage() {
  final flux = lireJsonExemple('manga_flux_page1.json');
  final donnees = flux['data']! as List<Object?>;
  return jsonEncode(<String, Object?>{...flux, 'total': donnees.length});
}

void main() {
  late Database base;
  late ServiceBibliotheque service;
  late ServiceAjoutSite serviceAjoutSite;
  late DepotListes depotListes;
  late List<Uri> requetes;
  late ServiceParametres parametres;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    requetes = <Uri>[];
    final fiche = lireExemple('exemples_json/manga_fiche.json');
    final flux = _fluxUnePage();
    final client = creerClientTest((http.Request requete) async {
      requetes.add(requete.url);
      final chemin = requete.url.path;
      if (chemin.endsWith('/feed')) {
        return reponseJson(flux);
      }
      if (chemin.startsWith('/manga/')) {
        return reponseJson(fiche);
      }
      return http.Response('introuvable', 404);
    }, HorlogeFactice());

    final depotSources = DepotSources(base);
    depotListes = DepotListes(base);
    serviceAjoutSite = ServiceAjoutSite(
      depotSources,
      DetecteurTypeSite(client),
    );
    service = ServiceBibliotheque(
      depotSources: depotSources,
      depotTitres: DepotTitres(base),
      depotChapitres: DepotChapitres(base),
      depotListes: depotListes,
      depotCategories: DepotCategories(base),
      fabriqueSources: FabriqueSources(client),
      serviceAjoutSite: serviceAjoutSite,
      client: client,
      serviceParametres: parametres = ServiceParametres(DepotParametres(base)),
    );
  });

  tearDown(() => base.close());

  group('ServiceAjoutSite', () {
    test('ramène une URL de titre à la racine du site', () {
      final uri = Uri.parse('https://www.MangaDex.org/title/abc/slug');
      expect(ServiceAjoutSite.calculerUrlBase(uri), 'https://www.mangadex.org');
      expect(ServiceAjoutSite.proposerNom(uri), 'mangadex.org');
    });

    test(
      'ajoute MangaDex sans requête réseau puis réutilise la source',
      () async {
        final premiere = await serviceAjoutSite.ajouterSite(
          'https://mangadex.org/title/12e28a8a-cbfe-4e12-bab8-b6fb0b9a59b4',
          langueParDefaut: 'EN',
        );
        final seconde = await serviceAjoutSite.ajouterSite(
          'https://mangadex.org',
        );

        expect(premiere.typeSource, TypeSource.mangaDex);
        expect(premiere.langueParDefaut, 'en');
        expect(seconde.id, premiere.id);
        expect(requetes, isEmpty);
      },
    );

    test('retrouve la source d\'une URL avec ou sans www', () async {
      await serviceAjoutSite.ajouterSite('https://mangadex.org');
      final trouvee = await serviceAjoutSite.trouverSourcePourUrl(
        'https://www.mangadex.org/title/x',
      );
      expect(trouvee, isNotNull);
    });

    test(
      "la version mobile d'un site déjà configuré ne crée pas de doublon",
      () async {
        final www = await serviceAjoutSite.ajouterSite(
          'https://www.webtoons.com',
        );
        final mobile = await serviceAjoutSite.ajouterSite(
          'https://m.webtoons.com/fr/romance/x/list?title_no=1',
        );
        final sansPrefixe = await serviceAjoutSite.ajouterSite(
          'https://webtoons.com',
        );

        expect(mobile.id, www.id);
        expect(sansPrefixe.id, www.id);
        expect(
          (await DepotSources(base).chargerSources()).where(
            (source) => source.typeSource == TypeSource.webtoons,
          ),
          hasLength(1),
        );
        expect(requetes, isEmpty);
      },
    );
  });

  group('ServiceBibliotheque.ajouterTitreDepuisUrl', () {
    test('ajoute le titre de référence avec fiche, catégories, chapitres et listes', () async {
      final listes = await depotListes.chargerListes();
      final idsSysteme = listes
          .where((liste) => liste.estSysteme)
          .map((liste) => liste.id!)
          .toList();

      final resultat = await service.ajouterTitreDepuisUrl(
        '$urlTitreReference/shinigami-ni-sodaterareta',
        idsListes: idsSysteme,
      );
      final titre = resultat.titre;

      expect(titre.nom, contains('Shinigami ni Sodaterareta'));
      expect(titre.titresAlternatifs, hasLength(6));
      expect(titre.dateDerniereVerification, isNotNull);
      expect(resultat.nombreNouveauxChapitres, greaterThan(0));

      final categories = await service.chargerCategoriesDuTitre(titre.id!);
      expect(
        categories.map((categorie) => categorie.nom),
        containsAll(<String>['gore', 'action', 'fantasy', 'adaptation']),
      );

      final listesDuTitre = await service.chargerListesDuTitre(titre.id!);
      expect(
        listesDuTitre.map((liste) => liste.nom),
        containsAll(<String>[nomListeFavoris, nomListeSuivis]),
      );

      final trouves = await service.chargerTitres(
        recherche: "death's daughter",
      );
      expect(trouves.single.id, titre.id);
    });

    test(
      'ne recompte pas les chapitres déjà connus lors d\'une actualisation',
      () async {
        final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
        final actualisation = await service.actualiserTitre(ajout.titre);

        expect(actualisation.nombreNouveauxChapitres, 0);
        expect(actualisation.titre.id, ajout.titre.id);
      },
    );

    test('refuse un site qui n\'est pas configuré', () async {
      expect(
        service.ajouterTitreDepuisUrl('https://exemple.test/manga/un-titre'),
        throwsA(isA<ErreurService>()),
      );
    });
  });

  group('ServiceBibliotheque.chargerChapitre', () {
    test(
      "charge un chapitre par son identifiant, ou null s'il n'existe pas",
      () async {
        final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
        final chapitres = await service.chargerChapitres(ajout.titre.id!);
        final premier = chapitres.first;

        final charge = await service.chargerChapitre(premier.id!);
        expect(charge!.urlChapitre, premier.urlChapitre);
        expect(await service.chargerChapitre(999999), isNull);
      },
    );
  });

  group('ServiceBibliotheque.languesPreferees', () {
    Source source(String langues) => Source(
      nom: 'Site',
      urlBase: 'https://exemple.test',
      typeSource: TypeSource.mangaDex,
      langueParDefaut: langues,
    );

    test('découpe les langues du site dans leur ordre, sans doublon', () {
      expect(
        ServiceBibliotheque.languesPreferees(source(' EN, fr ,,en')),
        <String>['en', 'fr'],
      );
    });

    test('retombe sur les langues du client sans réglage du site', () {
      final parDefaut = <String>['fr', 'en'];
      expect(ServiceBibliotheque.languesPreferees(source('')), parDefaut);
      expect(ServiceBibliotheque.languesPreferees(null), parDefaut);
      expect(
        ServiceBibliotheque.languesPreferees(
          source(''),
          general: <String>['es', 'en'],
        ),
        <String>['es', 'en'],
      );
    });
  });

  group('langues du réglage général', () {
    List<String> languesDemandees() => requetes
        .where((uri) => uri.path.endsWith('/feed'))
        .expand(
          (uri) =>
              uri.queryParametersAll['translatedLanguage[]'] ??
              const <String>[],
        )
        .toSet()
        .toList();

    test("MangaDex ajouté automatiquement suit le réglage général pour le flux et le titre", () async {
      await parametres.enregistrerLangues(<String>['es']);
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);

      final source = await service.chargerSource(ajout.titre.idSource!);
      expect(source!.langueParDefaut, isEmpty);
      expect(languesDemandees(), containsAll(<String>['es']));
      expect(languesDemandees(), isNot(contains('fr')));
      expect(await service.languesPourTitre(ajout.titre), <String>['es']);
    });

    test(
      "le flux d'une source réglée couvre ses langues et le réglage général",
      () async {
        await parametres.enregistrerLangues(<String>['es']);
        await serviceAjoutSite.ajouterSite(
          'https://mangadex.org',
          langueParDefaut: 'en',
        );
        final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);

        expect(languesDemandees(), containsAll(<String>['en', 'es']));
        expect(await service.languesPourTitre(ajout.titre), <String>['en']);
      },
    );
  });
}
