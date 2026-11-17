// Étape 8 (tâche M2) : plusieurs sites pour un même titre, côté
// ServiceBibliotheque. Base en mémoire ; les sites sont des adaptateurs
// simulés (aucune requête réseau : le client HTTP simulé sert quelques
// pages enregistrées et répond 404 ailleurs).
import 'dart:convert';

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

/// Page HTML encodée en UTF-8, comme un vrai site.
http.Response _pageHtml(String corps, {int statut = 200}) =>
    http.Response.bytes(
      utf8.encode(corps),
      statut,
      headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
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
  // Pages servies par le client HTTP simulé (adresse → réponse) ; toute
  // autre adresse répond 404. Les requêtes reçues sont notées.
  late Map<String, http.Response> pages;
  late List<String> requetes;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depotSources = DepotSources(base);
    depotChapitres = DepotChapitres(base);
    depotLiens = DepotTitresSources(base);
    depotListes = DepotListes(base);
    pages = <String, http.Response>{};
    requetes = <String>[];
    final ClientHttpPoli client = creerClientTest((http.Request requete) async {
      requetes.add(requete.url.toString());
      return pages[requete.url.toString()] ?? http.Response('introuvable', 404);
    }, HorlogeFactice());
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

    test("refuse un site inconnu non configuré, et une page générique sans "
        "chapitre, sans rien écrire et en permettant l'ajout comme simple "
        'lien', () async {
      final titre = await ajouterTitrePrincipal();
      Object? erreurInconnu;
      try {
        await service.ajouterSiteAuTitre(
          titre.id!,
          'https://inconnu.test/titre/1',
        );
      } catch (erreur) {
        erreurInconnu = erreur;
      }
      expect(erreurInconnu, isA<ErreurService>());
      expect(
        ServiceBibliotheque.peutAjouterCommeLienSeul(erreurInconnu!),
        isTrue,
      );

      await depotSources.enregistrerSource(
        const Source(
          nom: 'Generique',
          urlBase: 'https://generique.test',
          typeSource: TypeSource.generique,
        ),
      );
      pages['https://generique.test/oeuvre/x'] = _pageHtml(
        '<html><head><title>X</title></head><body><h1>X</h1>'
        '<p>Une page sans aucun lien de chapitre.</p></body></html>',
      );
      Object? erreurGenerique;
      try {
        await service.ajouterSiteAuTitre(
          titre.id!,
          'https://generique.test/oeuvre/x',
        );
      } catch (erreur) {
        erreurGenerique = erreur;
      }
      expect(
        erreurGenerique,
        isA<ErreurSource>().having(
          (e) => e.message,
          'message',
          contains('Aucun lien de chapitre'),
        ),
      );
      expect(
        ServiceBibliotheque.peutAjouterCommeLienSeul(erreurGenerique!),
        isTrue,
      );
      expect(await depotLiens.chargerLiensTitre(titre.id!), hasLength(1));
    });

    test('des réglages génériques illisibles donnent un message clair, sans '
        'requête', () async {
      final titre = await ajouterTitrePrincipal();
      await depotSources.enregistrerSource(
        const Source(
          nom: 'Mal réglé',
          urlBase: 'https://mal-regle.test',
          typeSource: TypeSource.generique,
          configurationSelecteurs: '{pas du json',
        ),
      );
      Object? erreur;
      try {
        await service.ajouterSiteAuTitre(
          titre.id!,
          'https://mal-regle.test/oeuvre/x',
        );
      } catch (e) {
        erreur = e;
      }
      expect(
        erreur,
        isA<ErreurService>().having(
          (e) => e.message,
          'message',
          contains('réglages du site « Mal réglé » sont illisibles'),
        ),
      );
      expect(ServiceBibliotheque.peutAjouterCommeLienSeul(erreur!), isTrue);
      expect(requetes, isEmpty);
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

  group('liens seuls (T4)', () {
    test("un site inconnu est enregistré comme simple lien générique, sans "
        'aucune requête', () async {
      final titre = await ajouterTitrePrincipal();
      requetes.clear();

      final resultat = await service.ajouterSiteAuTitre(
        titre.id!,
        ' https://protege.test/oeuvre/x ',
        lienSeul: true,
      );

      expect(resultat.nombreNouveauxChapitres, 0);
      expect(resultat.titre.id, titre.id);
      expect(requetes, isEmpty);
      final source = await depotSources.chargerSourceParUrl(
        'https://protege.test',
      );
      expect(source, isNotNull);
      expect(source!.typeSource, TypeSource.generique);
      expect(source.nom, 'protege.test');
      final liens = await depotLiens.chargerLiensTitre(titre.id!);
      expect(liens, hasLength(2));
      expect(liens.last.urlTitre, 'https://protege.test/oeuvre/x');
      expect(liens.last.estLienSeul, isTrue);

      final sites = await service.chargerSitesDuTitre(titre.id!);
      expect(sites.map((s) => s.estLienSeul), <bool>[false, true]);
      expect(sites.last.nombreChapitres, 0);
    });

    test(
      'un site reconnu par son domaine garde son type, sans le lire',
      () async {
        final titre = await ajouterTitrePrincipal();

        await service.ajouterSiteAuTitre(
          titre.id!,
          _urlScanManga,
          lienSeul: true,
        );

        expect(scanManga.appels, isEmpty);
        expect((await sourceScanManga())!.typeSource, TypeSource.scanManga);
        expect(
          await depotChapitres.chargerChapitres(
            titre.id!,
            idSource: (await sourceScanManga())!.id,
          ),
          isEmpty,
        );
      },
    );

    test("l'actualisation et la vérification d'un site n'interrogent jamais "
        'un lien seul', () async {
      final titre = await ajouterTitrePrincipal();
      await service.ajouterSiteAuTitre(
        titre.id!,
        _urlScanManga,
        lienSeul: true,
      );
      final idScan = (await sourceScanManga())!.id!;
      mangaDex.appels.clear();

      final resultat = await service.actualiserTitre(titre);
      final parSite = await service.actualiserSiteDuTitre(titre, idScan);

      expect(resultat.aDesErreursDeSite, isFalse);
      expect(parSite.nombreNouveauxChapitres, 0);
      expect(scanManga.appels, isEmpty);
      expect(mangaDex.appels, hasLength(2));
    });

    test(
      'un lien seul ne peut pas devenir le site principal, sans requête',
      () async {
        final titre = await ajouterTitrePrincipal();
        await service.ajouterSiteAuTitre(
          titre.id!,
          _urlScanManga,
          lienSeul: true,
        );
        final idScan = (await sourceScanManga())!.id!;

        await expectLater(
          service.definirSitePrincipal(titre.id!, idScan),
          throwsA(isA<ErreurService>()),
        );
        expect(scanManga.appels, isEmpty);
      },
    );

    test(
      'marquer un site lu comme lien seul supprime ses chapitres non lus '
      'et prévoit la suppression de ses archives, puis il redevient lu',
      () async {
        final titre = await ajouterTitrePrincipal();
        await service.ajouterSiteAuTitre(titre.id!, _urlScanManga);
        final idScan = (await sourceScanManga())!.id!;
        final chapitresScan = await depotChapitres.chargerChapitres(
          titre.id!,
          idSource: idScan,
        );
        await depotChapitres.marquerLu(chapitresScan[0].id!);
        await depotChapitres.enregistrerArchive(chapitresScan[1].id!, 'a.zip');

        final supprimes = await service.marquerLienSeul(
          titre.id!,
          idScan,
          true,
        );

        expect(supprimes, 1);
        final restants = await depotChapitres.chargerChapitres(
          titre.id!,
          idSource: idScan,
        );
        expect(restants, hasLength(2));
        expect(restants[1].dateSuppressionPrevue, isNotNull);
        expect(
          (await service.chargerSitesDuTitre(titre.id!)).last.estLienSeul,
          isTrue,
        );

        expect(await service.marquerLienSeul(titre.id!, idScan, false), 0);
        expect(
          (await service.chargerSitesDuTitre(titre.id!)).last.estLienSeul,
          isFalse,
        );
      },
    );

    test('refuse de marquer le site principal comme lien seul', () async {
      final titre = await ajouterTitrePrincipal();
      await expectLater(
        service.marquerLienSeul(titre.id!, sourceMangaDex.id!, true),
        throwsA(isA<ErreurService>()),
      );
    });

    test("peutAjouterCommeLienSeul : oui pour un site illisible ou protégé, "
        'non pour une adresse invalide ou déjà liée', () async {
      const protection = ErreurSource(
        'https://protege.test/oeuvre/x',
        'protection',
        codeStatut: 403,
        protectionAntiRobot: true,
      );
      expect(ServiceBibliotheque.peutAjouterCommeLienSeul(protection), isTrue);

      final titre = await ajouterTitrePrincipal();
      Object? invalide;
      try {
        await service.ajouterSiteAuTitre(titre.id!, 'pas une adresse');
      } catch (erreur) {
        invalide = erreur;
      }
      expect(invalide, isA<ErreurSource>());
      expect(ServiceBibliotheque.peutAjouterCommeLienSeul(invalide!), isFalse);

      Object? dejaLie;
      try {
        await service.ajouterSiteAuTitre(titre.id!, _urlPrincipale);
      } catch (erreur) {
        dejaLie = erreur;
      }
      expect(dejaLie, isA<ErreurService>());
      expect(ServiceBibliotheque.peutAjouterCommeLienSeul(dejaLie!), isFalse);
    });
  });

  group('diagnostiquerSite (T3)', () {
    test(
      'une page générique avec des liens de chapitres est lisible',
      () async {
        pages['https://generique.test/oeuvre/x'] = _pageHtml(
          '<html><head><title>X</title></head><body><h1>X</h1><ul>'
          '<li><a href="/oeuvre/x/chapter-1/">Chapter 1</a></li>'
          '<li><a href="/oeuvre/x/chapter-2/">Chapter 2</a></li>'
          '</ul></body></html>',
        );

        final diagnostic = await service.diagnostiquerSite(
          'https://generique.test/oeuvre/x',
        );

        expect(diagnostic.estLisible, isTrue);
        expect(diagnostic.nombreLiensChapitres, 2);
        expect(requetes, <String>['https://generique.test/oeuvre/x']);
      },
    );

    test('une page sans chapitre donne sa raison', () async {
      pages['https://generique.test/oeuvre/x'] = _pageHtml(
        '<html><head><title>X</title></head><body><h1>X</h1>'
        '<p>Rien à lire ici, seulement du texte.</p></body></html>',
      );

      final diagnostic = await service.diagnostiquerSite(
        'https://generique.test/oeuvre/x',
      );

      expect(diagnostic.estLisible, isFalse);
      expect(diagnostic.raisons.single, contains('Aucun lien de chapitre'));
    });

    test('reconnaît une protection anti-robot sans la contourner', () async {
      pages['https://protege.test/oeuvre/x'] = _pageHtml(
        '<html><head><title>Just a moment...</title></head><body>'
        '<script src="/cdn-cgi/challenge-platform/h/b"></script>'
        '</body></html>',
        statut: 403,
      );

      final diagnostic = await service.diagnostiquerSite(
        'https://protege.test/oeuvre/x',
      );

      expect(diagnostic.protectionAntiRobot, isTrue);
      expect(diagnostic.estLisible, isFalse);
      expect(diagnostic.raisons.single, contains('protection anti-robot'));
      // Une seule requête : aucune nouvelle tentative sur un défi.
      expect(requetes, hasLength(1));
    });

    test('une erreur HTTP donne son code, sans lever', () async {
      final diagnostic = await service.diagnostiquerSite(
        'https://generique.test/absent',
      );

      expect(diagnostic.estLisible, isFalse);
      expect(diagnostic.raisons.single, contains('404'));
    });

    test('un site injoignable donne la raison « injoignable », sans lever', () {
      final diagnostic = ServiceBibliotheque.diagnosticDepuisErreur(
        const ErreurSource('https://loin.test/', 'Connexion refusée'),
        Uri.parse('https://loin.test/'),
      );

      expect(diagnostic.estLisible, isFalse);
      expect(diagnostic.raisons.single, contains('injoignable'));
    });

    test('une adresse invalide ou un site à adaptateur dédié ne font aucune '
        'requête', () async {
      final invalide = await service.diagnostiquerSite('pas une adresse');
      final mangaDexDiagnostic = await service.diagnostiquerSite(
        'https://mangadex.org/title/abc',
      );

      expect(invalide.estLisible, isFalse);
      expect(mangaDexDiagnostic.estLisible, isTrue);
      expect(mangaDexDiagnostic.remarques.single, contains('MangaDex'));
      expect(requetes, isEmpty);
    });

    test("un thème Madara reconnu dans la page n'est pas jugé sur les "
        'critères génériques', () async {
      pages['https://madara.test/manga/x/'] = _pageHtml(
        '<html><head><title>X</title></head><body>'
        '<div class="wp-manga-section">X</div></body></html>',
      );

      final diagnostic = await service.diagnostiquerSite(
        'https://madara.test/manga/x/',
      );

      expect(diagnostic.estLisible, isTrue);
      expect(diagnostic.remarques.single, contains('Madara'));
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
