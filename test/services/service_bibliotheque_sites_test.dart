// Étape 8 (tâche M2) : plusieurs sites pour un même titre, côté
// ServiceBibliotheque. Base en mémoire ; les sites sont des adaptateurs
// simulés (aucune requête réseau, le client HTTP répond toujours 404).
import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/contenu_chapitre.dart';
import 'package:bibliotheque_perso/modeles/fiche_titre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/constantes_services.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_sources_par_defaut.dart';
import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:bibliotheque_perso/sources/source_site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Site simulé : fiches et chapitres par adresse de titre, panne réglable,
/// journal des appels.
class _SiteSimule implements SourceSite {
  final Map<String, FicheTitre> fiches = <String, FicheTitre>{};
  final Map<String, List<Chapitre>> chapitres = <String, List<Chapitre>>{};
  final List<String> appels = <String>[];
  bool enPanne = false;

  void erreurSiPanne(String url) {
    if (enPanne) throw ErreurSource(url, 'site injoignable', codeStatut: 503);
  }

  @override
  Future<FicheTitre> recupererFiche(String urlTitre) async {
    appels.add('fiche $urlTitre');
    erreurSiPanne(urlTitre);
    final fiche = fiches[urlTitre];
    if (fiche == null) {
      throw ErreurSource(urlTitre, "Cette page n'est pas un titre");
    }
    return fiche;
  }

  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) async {
    appels.add('chapitres $urlTitre');
    erreurSiPanne(urlTitre);
    return chapitres[urlTitre] ?? const <Chapitre>[];
  }

  @override
  Future<List<Titre>> rechercher(String requete) async => const <Titre>[];

  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) async =>
      throw ErreurSource(urlChapitre, 'non simulé');
}

/// Fabrique qui renvoie le site simulé de l'hôte de la source, sinon le
/// comportement réel (erreur pour un type sans adaptateur).
class _FabriqueSimulee extends FabriqueSources {
  _FabriqueSimulee(super.client, this.sites);

  final Map<String, _SiteSimule> sites;

  @override
  SourceSite creer(Source source, {List<String>? niveauxContenuRecherche}) {
    final site = sites[Uri.parse(source.urlBase).host];
    return site ??
        super.creer(source, niveauxContenuRecherche: niveauxContenuRecherche);
  }
}

const String _urlPrincipale = 'https://mangadex.org/title/abc';
const String _urlScanManga = 'https://www.scan-manga.com/lecture/abc.html';

Chapitre _chapitre(String url, double numero, {String langue = 'fr'}) =>
    Chapitre(
      urlChapitre: url,
      nom: 'Chapitre $numero',
      numero: numero,
      langue: langue,
    );

void main() {
  late Database base;
  late DepotSources depotSources;
  late DepotChapitres depotChapitres;
  late DepotTitresSources depotLiens;
  late DepotListes depotListes;
  late ServiceBibliotheque service;
  late _SiteSimule mangaDex;
  late _SiteSimule scanManga;
  late Source sourceMangaDex;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depotSources = DepotSources(base);
    depotChapitres = DepotChapitres(base);
    depotLiens = DepotTitresSources(base);
    depotListes = DepotListes(base);
    final ClientHttpPoli client = creerClientTest(
      (http.Request requete) async => http.Response('introuvable', 404),
      HorlogeFactice(),
    );
    mangaDex = _SiteSimule()
      ..fiches[_urlPrincipale] = FicheTitre(
        titre: Titre(urlTitre: _urlPrincipale, nom: 'Titre MangaDex'),
        categories: const <String>['Action'],
      )
      ..chapitres[_urlPrincipale] = <Chapitre>[
        _chapitre('https://mangadex.org/chapter/1', 1),
        _chapitre('https://mangadex.org/chapter/2', 2, langue: 'en'),
      ];
    scanManga = _SiteSimule()
      ..fiches[_urlScanManga] = FicheTitre(
        titre: Titre(urlTitre: _urlScanManga, nom: 'Titre Scan-Manga'),
      )
      ..chapitres[_urlScanManga] = <Chapitre>[
        _chapitre('https://www.scan-manga.com/lecture/abc/1', 1),
        _chapitre('https://www.scan-manga.com/lecture/abc/2', 2),
        _chapitre('https://www.scan-manga.com/lecture/abc/3', 3),
      ];
    sourceMangaDex = await depotSources.enregistrerSource(
      const Source(
        nom: nomMangaDex,
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
      ),
    );
    service = ServiceBibliotheque(
      depotSources: depotSources,
      depotTitres: DepotTitres(base),
      depotChapitres: depotChapitres,
      depotListes: depotListes,
      depotCategories: DepotCategories(base),
      fabriqueSources: _FabriqueSimulee(client, <String, _SiteSimule>{
        'mangadex.org': mangaDex,
        'www.scan-manga.com': scanManga,
      }),
      serviceAjoutSite: ServiceAjoutSite(
        depotSources,
        DetecteurTypeSite(client),
      ),
      client: client,
      depotTitresSources: depotLiens,
    );
  });

  tearDown(() => base.close());

  Future<Titre> ajouterTitrePrincipal() async =>
      (await service.ajouterTitreDepuisUrl(_urlPrincipale)).titre;

  Future<Source?> sourceScanManga() =>
      depotSources.chargerSourceParUrl(urlBaseScanManga);

  group('ajouterSiteAuTitre', () {
    test('ajoute le lien, enregistre les chapitres avec leur site et crée '
        'Scan-Manga qui manquait', () async {
      final titre = await ajouterTitrePrincipal();

      final resultat = await service.ajouterSiteAuTitre(
        titre.id!,
        _urlScanManga,
      );

      expect(resultat.nombreNouveauxChapitres, 3);
      final scan = await sourceScanManga();
      expect(scan, isNotNull);
      expect(scan!.typeSource, TypeSource.scanManga);
      final liens = await depotLiens.chargerLiensTitre(titre.id!);
      expect(liens.map((l) => l.urlTitre), <String>[
        _urlPrincipale,
        _urlScanManga,
      ]);
      final chapitresScan = await depotChapitres.chargerChapitres(
        titre.id!,
        idSource: scan.id,
      );
      expect(chapitresScan, hasLength(3));
      // La fiche du titre reste celle du site principal.
      expect(resultat.titre.nom, 'Titre MangaDex');
      expect(scanManga.appels, <String>[
        'fiche $_urlScanManga',
        'chapitres $_urlScanManga',
      ]);
    });

    test("refuse une adresse déjà utilisée par un autre titre, sans "
        'interroger le site', () async {
      final titre = await ajouterTitrePrincipal();
      mangaDex.fiches['https://mangadex.org/title/autre'] = FicheTitre(
        titre: Titre(
          urlTitre: 'https://mangadex.org/title/autre',
          nom: 'Autre',
        ),
      );
      final autre = await service.ajouterTitreDepuisUrl(
        'https://mangadex.org/title/autre',
      );
      await service.ajouterSiteAuTitre(autre.titre.id!, _urlScanManga);
      scanManga.appels.clear();

      await expectLater(
        service.ajouterSiteAuTitre(titre.id!, _urlScanManga),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('Autre'),
          ),
        ),
      );
      expect(scanManga.appels, isEmpty);
    });

    test('refuse un site déjà lié au titre', () async {
      final titre = await ajouterTitrePrincipal();
      await expectLater(
        service.ajouterSiteAuTitre(
          titre.id!,
          'https://mangadex.org/title/encore-un',
        ),
        throwsA(isA<ErreurService>()),
      );
    });

    test("refuse un site inconnu non configuré, et un site que "
        "l'application ne sait pas lire, sans rien écrire", () async {
      final titre = await ajouterTitrePrincipal();
      await expectLater(
        service.ajouterSiteAuTitre(titre.id!, 'https://inconnu.test/titre/1'),
        throwsA(isA<ErreurService>()),
      );
      await depotSources.enregistrerSource(
        const Source(
          // Le type générique est le seul encore sans adaptateur (Madara est
          // lisible depuis l'étape 7).
          nom: 'Generique',
          urlBase: 'https://madara.test',
          typeSource: TypeSource.generique,
        ),
      );
      await expectLater(
        service.ajouterSiteAuTitre(titre.id!, 'https://madara.test/manga/x'),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('pas encore lisible'),
          ),
        ),
      );
      expect(await depotLiens.chargerLiensTitre(titre.id!), hasLength(1));
    });

    test("un site en panne ou une adresse qui n'est pas un titre n'écrit "
        'rien', () async {
      final titre = await ajouterTitrePrincipal();
      scanManga.enPanne = true;
      await expectLater(
        service.ajouterSiteAuTitre(titre.id!, _urlScanManga),
        throwsA(isA<ErreurSource>()),
      );
      scanManga.enPanne = false;
      await expectLater(
        service.ajouterSiteAuTitre(
          titre.id!,
          'https://www.scan-manga.com/accueil.html',
        ),
        throwsA(isA<ErreurSource>()),
      );
      expect(await sourceScanManga(), isNull);
      expect(await depotLiens.chargerLiensTitre(titre.id!), hasLength(1));
      expect(await depotChapitres.chargerChapitres(titre.id!), hasLength(2));
    });
  });

  test('chargerSitesDuTitre donne le nom de chaque site et son nombre de '
      'chapitres, principal en tête', () async {
    final titre = await ajouterTitrePrincipal();
    await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);

    final sites = await service.chargerSitesDuTitre(titre.id!);

    expect(sites.map((s) => s.nomSite), <String>[nomMangaDex, nomScanManga]);
    expect(sites.map((s) => s.nombreChapitres), <int>[2, 3]);
    expect(sites.map((s) => s.estPrincipal), <bool>[true, false]);
    expect(await service.chargerSitesDuTitre(999), isEmpty);
  });

  test("ajouter l'adresse d'un site secondaire renvoie le titre existant, "
      'sans requête, et le range dans les listes demandées', () async {
    final titre = await ajouterTitrePrincipal();
    await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
    scanManga.appels.clear();
    final idFavoris = (await depotListes.chargerListeParNom(nomListeFavoris))!
        .id!;

    final resultat = await service.ajouterTitreDepuisUrl(
      _urlScanManga,
      idsListes: <int>[idFavoris],
    );

    expect(resultat.estDejaPresent, isTrue);
    expect(resultat.titre.id, titre.id);
    expect(scanManga.appels, isEmpty);
    expect(
      (await depotListes.chargerListesDuTitre(titre.id!)).map((l) => l.nom),
      contains(nomListeFavoris),
    );
    expect(await DepotTitres(base).chargerTitres(), hasLength(1));
  });

  group('actualiserTitre', () {
    test(
      'interroge tous les sites ; la fiche ne vient que du principal',
      () async {
        final titre = await ajouterTitrePrincipal();
        await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
        scanManga.appels.clear();
        scanManga.chapitres[_urlScanManga]!.add(
          _chapitre('https://www.scan-manga.com/lecture/abc/4', 4),
        );
        mangaDex.chapitres[_urlPrincipale]!.add(
          _chapitre('https://mangadex.org/chapter/3', 3),
        );

        final resultat = await service.actualiserTitre(titre);

        expect(resultat.nombreNouveauxChapitres, 2);
        expect(resultat.aDesErreursDeSite, isFalse);
        expect(scanManga.appels, <String>['chapitres $_urlScanManga']);
      },
    );

    test("un site en panne n'empêche pas les autres et son erreur est "
        'rendue', () async {
      final titre = await ajouterTitrePrincipal();
      await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
      final idScan = (await sourceScanManga())!.id!;
      mangaDex.enPanne = true;
      scanManga.chapitres[_urlScanManga]!.add(
        _chapitre('https://www.scan-manga.com/lecture/abc/4', 4),
      );

      final resultat = await service.actualiserTitre(titre);

      expect(resultat.nombreNouveauxChapitres, 1);
      expect(resultat.erreursParSite.keys, <int>[sourceMangaDex.id!]);
      expect(resultat.erreursParSite.containsKey(idScan), isFalse);
    });

    test('lève la première erreur si aucun site ne répond', () async {
      final titre = await ajouterTitrePrincipal();
      await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
      mangaDex.enPanne = true;
      scanManga.enPanne = true;

      await expectLater(
        service.actualiserTitre(titre),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('retirerSiteDuTitre', () {
    test('supprime les chapitres non lus, garde les lus et prévoit la '
        'suppression des archives dans 24 h', () async {
      final titre = await ajouterTitrePrincipal();
      await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
      final idScan = (await sourceScanManga())!.id!;
      final chapitresScan = await depotChapitres.chargerChapitres(
        titre.id!,
        idSource: idScan,
      );
      await depotChapitres.marquerLu(chapitresScan[0].id!);
      await depotChapitres.enregistrerArchive(chapitresScan[1].id!, 'a.zip');
      final avant = DateTime.now().toUtc();

      final supprimes = await service.retirerSiteDuTitre(titre.id!, idScan);

      expect(supprimes, 1);
      expect(await depotLiens.chargerLiensTitre(titre.id!), hasLength(1));
      final restants = await depotChapitres.chargerChapitres(
        titre.id!,
        idSource: idScan,
      );
      expect(restants.map((c) => c.id), <int>[
        chapitresScan[0].id!,
        chapitresScan[1].id!,
      ]);
      expect(restants[0].dateSuppressionPrevue, isNull);
      final echeance = restants[1].dateSuppressionPrevue!;
      expect(
        echeance.isAfter(
          avant
              .add(delaiSuppressionDifferee)
              .subtract(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });

    test('refuse de retirer le site principal', () async {
      final titre = await ajouterTitrePrincipal();
      await expectLater(
        service.retirerSiteDuTitre(titre.id!, sourceMangaDex.id!),
        throwsA(isA<ErreurService>()),
      );
    });
  });

  group('definirSitePrincipal', () {
    test('relit la fiche sur le nouveau site principal', () async {
      final titre = await ajouterTitrePrincipal();
      await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
      final idScan = (await sourceScanManga())!.id!;

      final resultat = await service.definirSitePrincipal(titre.id!, idScan);

      expect(resultat.titre.id, titre.id);
      expect(resultat.titre.nom, 'Titre Scan-Manga');
      expect(resultat.titre.idSource, idScan);
      expect(resultat.titre.urlTitre, _urlScanManga);
      final liens = await depotLiens.chargerLiensTitre(titre.id!);
      expect(liens.first.idSource, idScan);
      expect(liens.first.estPrincipale, isTrue);
      // Les chapitres de l'ancien principal restent.
      expect(await depotChapitres.chargerChapitres(titre.id!), hasLength(5));
    });

    test('si le nouveau site ne répond pas, rien ne change', () async {
      final titre = await ajouterTitrePrincipal();
      await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
      final idScan = (await sourceScanManga())!.id!;
      scanManga.enPanne = true;

      await expectLater(
        service.definirSitePrincipal(titre.id!, idScan),
        throwsA(isA<ErreurSource>()),
      );
      final relu = await DepotTitres(base).chargerTitre(titre.id!);
      expect(relu!.idSource, sourceMangaDex.id);
      expect(relu.nom, 'Titre MangaDex');
    });
  });
}
