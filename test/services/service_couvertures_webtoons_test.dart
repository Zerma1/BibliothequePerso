// Couvertures WEBTOON jamais téléchargées (PLAYBOOK.md section 10) : le
// serveur d'images pstatic.net refuse les demandes sans Referer du site.
// Base en mémoire, dossier temporaire et page HTML enregistrée (aucun appel
// réseau réel).
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

const String _urlPetiteFrappe =
    'https://www.webtoons.com/fr/romance/'
    'the-gangster-daughter-of-the-henchman-dukes-family/list?title_no=11499';

const String _urlCouverture =
    'https://swebtoon-phinf.pstatic.net/20261109_63/couverture.jpg';

void main() {
  late Database base;
  late Directory dossier;
  late ServiceBibliotheque service;
  late DepotSources depotSources;
  late DepotTitres depotTitres;
  late StockageTelechargements stockage;
  late List<Uri> requetes;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('bibliotheque_webtoons');
    requetes = <Uri>[];
    final html = lireExemple('exemples_html/webtoons_petite_frappe_p1.html');
    final client = creerClientTest((http.Request requete) async {
      requetes.add(requete.url);
      if (requete.url.host.endsWith('pstatic.net')) {
        // Ne doit jamais arriver : l'image serait sinon servie normalement,
        // pour que le test échoue sur le nombre de requêtes.
        return http.Response.bytes(
          <int>[9, 8, 7],
          200,
          headers: <String, String>{'content-type': 'image/jpeg'},
        );
      }
      return http.Response(
        html,
        200,
        headers: <String, String>{'content-type': 'text/html; charset=UTF-8'},
      );
    }, HorlogeFactice());

    depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    stockage = StockageTelechargements(dossier.path);
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
      serviceParametres: ServiceParametres(DepotParametres(base)),
      stockage: stockage,
    );
  });

  tearDown(() async {
    await base.close();
    await dossier.delete(recursive: true);
  });

  Iterable<Uri> requetesImages() =>
      requetes.where((uri) => uri.host.endsWith('pstatic.net'));

  Future<Titre> titreWebtoon() async {
    final source = await depotSources.enregistrerSource(
      const Source(
        nom: 'webtoons.com',
        urlBase: 'https://www.webtoons.com',
        typeSource: TypeSource.webtoons,
      ),
    );
    return depotTitres.enregistrerTitre(
      Titre(
        idSource: source.id,
        urlTitre: _urlPetiteFrappe,
        nom: 'La Petite Frappe',
        urlCouverture: _urlCouverture,
      ),
    );
  }

  test("l'ajout d'un titre WEBTOON ne demande pas sa couverture", () async {
    // Le site doit être configuré avant l'ajout d'un titre.
    await depotSources.enregistrerSource(
      const Source(
        nom: 'webtoons.com',
        urlBase: 'https://www.webtoons.com',
        typeSource: TypeSource.webtoons,
      ),
    );
    final ajout = await service.ajouterTitreDepuisUrl(_urlPetiteFrappe);
    expect(ajout.titre.urlCouverture, contains('pstatic.net'));
    expect(await service.cheminCouvertureLocale(ajout.titre), isNull);

    expect(await service.chargerCouverture(ajout.titre), isNull);
    expect(await service.chargerCouvertureOriginale(ajout.titre), isNull);
    await service.actualiserTitre(ajout.titre);
    expect(requetesImages(), isEmpty);
  });

  test("l'affichage d'un titre WEBTOON renvoie une couverture vide sans "
      'aucune requête', () async {
    final titre = await titreWebtoon();
    expect(await service.chargerCouverture(titre), isNull);
    expect(await service.chargerCouvertureOriginale(titre), isNull);
    expect(requetes, isEmpty);
  });

  test('une vignette demandée avec le référent WEBTOON est refusée sans '
      'requête', () async {
    for (final referent in <String>[
      'https://www.webtoons.com',
      'https://m.webtoons.com',
    ]) {
      await expectLater(
        service.recupererVignette(_urlCouverture, referer: referent),
        throwsA(isA<ErreurSource>()),
      );
    }
    expect(service.estCouvertureEnCache(_urlCouverture), isFalse);
    expect(requetes, isEmpty);
  });

  test(
    'choisir une couverture du site WEBTOON est refusé sans requête',
    () async {
      final titre = await titreWebtoon();
      await expectLater(
        service.choisirCouverture(titre.id!, _urlCouverture),
        throwsA(isA<ErreurService>()),
      );
      expect(requetes, isEmpty);
    },
  );

  test("une image de l'appareil reste utilisée, et revenir à la couverture "
      'du site la retire sans requête', () async {
    final titre = await titreWebtoon();
    final image = File('${dossier.path}${Platform.pathSeparator}perso.png')
      ..writeAsBytesSync(<int>[1, 2, 3, 4, 5]);

    final choisi = await service.choisirCouvertureLocale(titre.id!, image.path);
    expect(await service.chargerCouverture(choisi), <int>[1, 2, 3, 4, 5]);
    expect(await service.chargerCouvertureOriginale(choisi), <int>[
      1,
      2,
      3,
      4,
      5,
    ]);

    final retabli = await service.retablirCouvertureDuSite(titre.id!);
    expect(retabli.couvertureChoisie, isNull);
    expect(await service.cheminCouvertureLocale(retabli), isNull);
    expect(await service.chargerCouverture(retabli), isNull);
    expect(requetes, isEmpty);
  });

  test('estSiteSansCouverture ne vise que WEBTOON', () {
    expect(
      ServiceBibliotheque.estSiteSansCouverture(
        const Source(
          nom: 'webtoons.com',
          urlBase: 'https://www.webtoons.com',
          typeSource: TypeSource.webtoons,
        ),
      ),
      isTrue,
    );
    expect(
      ServiceBibliotheque.estSiteSansCouverture(
        const Source(
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
        ),
      ),
      isFalse,
    );
    expect(ServiceBibliotheque.estSiteSansCouverture(null), isFalse);
  });
}
