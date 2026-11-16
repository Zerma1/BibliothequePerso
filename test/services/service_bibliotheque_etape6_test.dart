// Étape 6 côté ServiceBibliotheque : liste « En attente », onglet Mises à
// jour, couvertures sur l'appareil, niveau de contenu. Base en mémoire,
// dossier temporaire et réponses MangaDex enregistrées (aucun appel réseau).
import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/constantes_services.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

String _fluxUnePage() {
  final flux = lireJsonExemple('manga_flux_page1.json');
  final donnees = flux['data']! as List<Object?>;
  return jsonEncode(<String, Object?>{...flux, 'total': donnees.length});
}

void main() {
  late Database base;
  late Directory dossier;
  late ServiceBibliotheque service;
  late ServiceParametres parametres;
  late DepotListes depotListes;
  late DepotTitres depotTitres;
  late DepotChapitres depotChapitres;
  late DepotSources depotSources;
  late StockageTelechargements stockage;
  late List<Uri> requetes;
  late bool siteEnPanne;
  // En-têtes des requêtes de couverture, et réponse HTML au lieu de l'image.
  late List<Map<String, String>> enTetesCouverture;
  late bool couvertureEnHtml;
  // Le serveur n'a pas de vignette 512 px (404).
  late bool vignetteAbsente;

  // Taille des images servies (`null` : trois octets).
  int? tailleImage;

  setUp(() async {
    vignetteAbsente = false;
    tailleImage = null;
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('bibliotheque_etape6');
    requetes = <Uri>[];
    siteEnPanne = false;
    enTetesCouverture = <Map<String, String>>[];
    couvertureEnHtml = false;
    final fiche = lireExemple('exemples_json/manga_fiche.json');
    final couvertures = lireExemple('exemples_json/couvertures_liste.json');
    final recherche = lireExemple('exemples_json/manga_recherche_filtre.json');
    final flux = _fluxUnePage();
    final client = creerClientTest((http.Request requete) async {
      requetes.add(requete.url);
      if (siteEnPanne) return http.Response('panne', 503);
      final chemin = requete.url.path;
      if (requete.url.host == 'uploads.mangadex.org') {
        enTetesCouverture.add(requete.headers);
        if (vignetteAbsente && requete.url.path.endsWith('.512.jpg')) {
          return http.Response('introuvable', 404);
        }
        if (couvertureEnHtml) {
          // Page anti-robot servie en 200 (journal des erreurs, E10).
          return http.Response(
            '<!doctype html><title>challenge</title>',
            200,
            headers: <String, String>{'content-type': 'text/html'},
          );
        }
        return http.Response.bytes(
          tailleImage == null
              ? <int>[9, 8, 7]
              : List<int>.filled(tailleImage!, 1),
          200,
          headers: <String, String>{'content-type': 'image/jpeg'},
        );
      }
      if (chemin.endsWith('/feed')) return reponseJson(flux);
      if (chemin == '/cover') return reponseJson(couvertures);
      if (chemin == '/manga') return reponseJson(recherche);
      if (chemin.startsWith('/manga/')) return reponseJson(fiche);
      return http.Response('introuvable', 404);
    }, HorlogeFactice());

    depotSources = DepotSources(base);
    depotListes = DepotListes(base);
    depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    stockage = StockageTelechargements(dossier.path);
    parametres = ServiceParametres(DepotParametres(base));
    service = ServiceBibliotheque(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotChapitres: depotChapitres,
      depotListes: depotListes,
      depotCategories: DepotCategories(base),
      fabriqueSources: FabriqueSources(client),
      serviceAjoutSite: ServiceAjoutSite(
        depotSources,
        DetecteurTypeSite(client),
      ),
      client: client,
      serviceParametres: parametres,
      stockage: stockage,
    );
  });

  tearDown(() async {
    await base.close();
    await dossier.delete(recursive: true);
  });

  Future<int> idListe(String nom) async =>
      (await depotListes.chargerListeParNom(nom))!.id!;

  Future<Set<String>> listesDe(int idTitre) async =>
      (await depotListes.chargerListesDuTitre(idTitre))
          .map((liste) => liste.nom)
          .toSet();

  group('liste « En attente »', () {
    test("un titre suivi sans chapitre dans les langues du client y entre, "
        "puis en sort quand les langues changent", () async {
      await parametres.enregistrerLangues(<String>['ko']);
      final ajout = await service.ajouterTitreDepuisUrl(
        urlTitreReference,
        idsListes: <int>[await idListe(nomListeSuivis)],
      );
      expect(ajout.estEnAttente, isTrue);
      expect(await listesDe(ajout.titre.id!), contains(nomListeEnAttente));

      await parametres.enregistrerLangues(<String>['fr']);
      expect(await service.classerTousEnAttente(), 0);
      expect(
        await listesDe(ajout.titre.id!),
        isNot(contains(nomListeEnAttente)),
      );
    });

    test("un titre qui n'est ni favori, ni suivi, ni planifié n'y entre "
        'jamais', () async {
      await parametres.enregistrerLangues(<String>['ko']);
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      expect(ajout.estEnAttente, isFalse);
      expect(await listesDe(ajout.titre.id!), isEmpty);
    });

    test(
      'un titre planifié y entre, et en sort quand il quitte « Planifié »',
      () async {
        await parametres.enregistrerLangues(<String>['ko']);
        final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
        final idPlanifie = await idListe(nomListePlanifie);

        await service.ajouterTitreALaListe(idPlanifie, ajout.titre.id!);
        expect(await listesDe(ajout.titre.id!), contains(nomListeEnAttente));

        await service.retirerTitreDeLaListe(idPlanifie, ajout.titre.id!);
        expect(await listesDe(ajout.titre.id!), isEmpty);
      },
    );

    test('le client ne peut pas modifier « En attente » à la main', () async {
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      final idEnAttente = await idListe(nomListeEnAttente);
      await expectLater(
        service.ajouterTitreALaListe(idEnAttente, ajout.titre.id!),
        throwsA(isA<ErreurService>()),
      );
      await expectLater(
        service.retirerTitreDeLaListe(idEnAttente, ajout.titre.id!),
        throwsA(isA<ErreurService>()),
      );
    });
  });

  group('onglet Mises à jour', () {
    late int idSource;

    setUp(() async {
      idSource = (await depotSources.enregistrerSource(
        const Source(
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
        ),
      )).id!;
    });

    Future<Titre> titreAvec(
      String nom,
      List<(double, String, DateTime)> chapitres, {
      String liste = nomListeSuivis,
    }) async {
      final titre = await depotTitres.enregistrerTitre(
        Titre(
          idSource: idSource,
          urlTitre: 'https://mangadex.org/title/$nom',
          nom: nom,
        ),
      );
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        for (final (numero, langue, date) in chapitres)
          Chapitre(
            idTitre: titre.id,
            urlChapitre: 'https://mangadex.org/chapter/$nom-$numero-$langue',
            nom: 'Chapitre $numero',
            numero: numero,
            langue: langue,
            datePublication: date,
          ),
      ]);
      await depotListes.ajouterTitre(await idListe(liste), titre.id!);
      return titre;
    }

    test('trie les titres par dernière parution dans leurs langues, avec le '
        'dernier chapitre paru', () async {
      final ancien = await titreAvec('Ancien', <(double, String, DateTime)>[
        (1, 'fr', DateTime.utc(2025, 1, 1)),
      ]);
      // Le chapitre russe, plus récent, ne compte pas (langues fr, en).
      final recent = await titreAvec('Récent', <(double, String, DateTime)>[
        (1, 'en', DateTime.utc(2026, 3, 1)),
        (2, 'ru', DateTime.utc(2026, 10, 1)),
      ], liste: nomListeFavoris);
      final sansChapitre = await titreAvec(
        'Sans chapitre',
        <(double, String, DateTime)>[(1, 'ru', DateTime.utc(2026, 11, 1))],
      );
      // Un titre seulement planifié n'est pas dans l'onglet.
      await titreAvec('Planifié seul', <(double, String, DateTime)>[
        (1, 'fr', DateTime.utc(2026, 11, 2)),
      ], liste: nomListePlanifie);

      final lignes = await service.chargerDernieresParutions();

      expect(lignes.map((l) => l.titre.id), <int>[
        recent.id!,
        ancien.id!,
        sansChapitre.id!,
      ]);
      expect(lignes.first.derniereParution, DateTime.utc(2026, 3, 1));
      expect(lignes.first.dernierChapitre!.numero, 1);
      expect(lignes.first.aNouveaute, isTrue);
      expect(lignes.last.dernierChapitre, isNull);
    });

    test("un titre dont les seuls chapitres dans vos langues sont externes "
        "n'est pas en attente, et ils comptent comme parus", () async {
      final titre = await depotTitres.enregistrerTitre(
        Titre(
          idSource: idSource,
          urlTitre: 'https://mangadex.org/title/externe',
          nom: 'Ruri Dragon',
        ),
      );
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: titre.id,
          urlChapitre: 'https://mangadex.org/chapter/externe-1',
          nom: 'Chapitre 1',
          numero: 1,
          langue: 'en',
          datePublication: DateTime.utc(2026, 9, 1),
          urlExterne: 'https://mangaplus.shueisha.co.jp/viewer/1',
        ),
      ]);
      await depotListes.ajouterTitre(await idListe(nomListeSuivis), titre.id!);

      expect(await service.classerEnAttente(titre.id!), isFalse);
      expect(await listesDe(titre.id!), isNot(contains(nomListeEnAttente)));
      final ligne = (await service.chargerDernieresParutions()).single;
      expect(ligne.derniereParution, DateTime.utc(2026, 9, 1));
      expect(ligne.dernierChapitre!.estExterne, isTrue);
    });

    test('respecte les langues propres à un titre', () async {
      final titre = await titreAvec('Russe', <(double, String, DateTime)>[
        (1, 'ru', DateTime.utc(2026, 10, 1)),
      ]);
      await service.modifierLanguesTitre(titre.id!, <String>['ru']);
      final lignes = await service.chargerDernieresParutions();
      expect(lignes.single.langues, <String>['ru']);
      expect(lignes.single.derniereParution, DateTime.utc(2026, 10, 1));
    });
  });

  group('couvertures', () {
    test("la couverture est enregistrée sur l'appareil à l'ajout, sans "
        "nouvelle requête à l'actualisation", () async {
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      expect(await service.cheminCouvertureLocale(ajout.titre), isNotNull);
      expect(await service.chargerCouverture(ajout.titre), <int>[9, 8, 7]);

      requetes.clear();
      await service.actualiserTitre(ajout.titre);
      expect(
        requetes.where((uri) => uri.host == 'uploads.mangadex.org'),
        isEmpty,
      );
    });

    test(
      'le niveau de contenu de la fiche est enregistré et filtrable',
      () async {
        final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
        expect(ajout.titre.niveauContenu, niveauContenuTousPublics);
        expect(
          await service.chargerTitres(
            niveauxContenu: <String>[niveauContenuPornographique],
            inclureNiveauInconnu: false,
          ),
          isEmpty,
        );
      },
    );

    test('liste les couvertures du site puis retient celle choisie', () async {
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      final proposees = await service.recupererCouverturesDuSite(ajout.titre);
      expect(proposees, isNotEmpty);

      final titre = await service.choisirCouverture(
        ajout.titre.id!,
        proposees[1].url,
      );
      expect(titre.couvertureChoisie, proposees[1].url);
      expect(titre.couvertureAffichee, proposees[1].url);

      final retabli = await service.retablirCouvertureDuSite(titre.id!);
      expect(retabli.couvertureChoisie, isNull);
    });

    test(
      "une image de l'appareil peut être choisie comme couverture",
      () async {
        final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
        final image = File('${dossier.path}${Platform.pathSeparator}perso.png')
          ..writeAsBytesSync(<int>[1, 2, 3, 4, 5]);

        final titre = await service.choisirCouvertureLocale(
          ajout.titre.id!,
          image.path,
        );
        expect(titre.couvertureChoisie, image.path);
        expect(ServiceBibliotheque.estCouvertureLocale(image.path), isTrue);
        final chemin = await service.cheminCouvertureLocale(titre);
        expect(chemin, endsWith('.png'));
        expect(await service.chargerCouverture(titre), <int>[1, 2, 3, 4, 5]);
      },
    );

    test("une image vide de l'appareil est refusée", () async {
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      final image = File('${dossier.path}${Platform.pathSeparator}vide.jpg')
        ..writeAsBytesSync(<int>[]);
      await expectLater(
        service.choisirCouvertureLocale(ajout.titre.id!, image.path),
        throwsA(isA<ErreurService>()),
      );
    });

    test("une couverture indisponible ne fait pas échouer l'affichage et "
        "n'est pas redemandée dans la session", () async {
      final titre = await depotTitres.enregistrerTitre(
        Titre(
          idSource: (await depotSources.enregistrerSource(
            const Source(
              nom: 'MangaDex',
              urlBase: 'https://mangadex.org',
              typeSource: TypeSource.mangaDex,
            ),
          )).id,
          urlTitre: urlTitreReference,
          nom: 'Sans image',
          urlCouverture: 'https://uploads.mangadex.org/covers/x/y.jpg',
        ),
      );
      siteEnPanne = true;
      expect(await service.chargerCouverture(titre), isNull);
      final nombre = requetes.length;
      expect(await service.chargerCouverture(titre), isNull);
      expect(requetes.length, nombre);
    });

    test("la couverture est demandée à uploads.mangadex.org avec le "
        "User-Agent de l'application (E10)", () async {
      await service.recupererCouverture(
        'https://uploads.mangadex.org/covers/x/y.jpg',
        referer: 'https://mangadex.org',
      );
      expect(enTetesCouverture, hasLength(1));
      expect(enTetesCouverture.single['user-agent'], userAgentApplication);
    });

    test("une réponse HTML est refusée et n'est gardée ni en cache ni sur "
        "l'appareil", () async {
      const url = 'https://uploads.mangadex.org/covers/x/y.jpg';
      couvertureEnHtml = true;
      await expectLater(
        service.recupererCouverture(url),
        throwsA(isA<ErreurSource>()),
      );
      // Pas en cache : la demande suivante repart vers le site, et reçoit
      // cette fois la vraie image.
      couvertureEnHtml = false;
      expect(await service.recupererCouverture(url), <int>[9, 8, 7]);
      expect(enTetesCouverture, hasLength(2));
    });

    test('le cache des couvertures oublie les moins récemment demandées '
        'au-delà de sa taille maximale', () async {
      // Trois images dépassent la taille maximale, deux non.
      tailleImage = tailleMaximaleCacheCouvertures ~/ 3 + 1;
      const prefixe = 'https://uploads.mangadex.org/covers/x';
      await service.recupererCouverture('$prefixe/1.jpg');
      await service.recupererCouverture('$prefixe/2.jpg');
      // Redemandée : servie par le cache et devenue la plus récente.
      await service.recupererCouverture('$prefixe/1.jpg');
      expect(enTetesCouverture, hasLength(2));
      await service.recupererCouverture('$prefixe/3.jpg');

      expect(service.estCouvertureEnCache('$prefixe/1.jpg'), isTrue);
      expect(service.estCouvertureEnCache('$prefixe/2.jpg'), isFalse);
      expect(service.estCouvertureEnCache('$prefixe/3.jpg'), isTrue);
      // L'oubliée repart vers le site si on la redemande.
      await service.recupererCouverture('$prefixe/2.jpg');
      expect(enTetesCouverture, hasLength(4));
    });

    test('le cache des couvertures garde au plus '
        '$nombreMaximalCouverturesEnCache images', () async {
      const prefixe = 'https://uploads.mangadex.org/covers/x';
      for (var i = 0; i <= nombreMaximalCouverturesEnCache; i++) {
        await service.recupererCouverture('$prefixe/$i.jpg');
      }
      expect(service.estCouvertureEnCache('$prefixe/0.jpg'), isFalse);
      expect(service.estCouvertureEnCache('$prefixe/1.jpg'), isTrue);
      expect(
        service.estCouvertureEnCache(
          '$prefixe/$nombreMaximalCouverturesEnCache.jpg',
        ),
        isTrue,
      );
    });

    test("une couverture HTML refusée à l'ajout n'est pas enregistrée sur "
        "l'appareil", () async {
      couvertureEnHtml = true;
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      expect(await service.cheminCouvertureLocale(ajout.titre), isNull);
      expect(await service.chargerCouverture(ajout.titre), isNull);
    });

    test("une page HTML enregistrée par une ancienne version est remplacée "
        "par la vraie image à l'affichage", () async {
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      await stockage.enregistrerCouverture(
        ajout.titre,
        utf8.encode('\n<!doctype html><title>challenge</title>'),
        'jpg',
      );
      expect(await service.chargerCouverture(ajout.titre), <int>[9, 8, 7]);
      final chemin = (await service.cheminCouvertureLocale(ajout.titre))!;
      expect(File(chemin).readAsBytesSync(), <int>[9, 8, 7]);
    });

    test("l'adresse de vignette n'est calculée que pour les couvertures "
        'MangaDex', () {
      expect(
        ServiceBibliotheque.adresseVignette(
          'https://uploads.mangadex.org/covers/abc/def.png',
        ),
        'https://uploads.mangadex.org/covers/abc/def.png.512.jpg',
      );
      expect(
        ServiceBibliotheque.adresseVignette(
          'https://uploads.mangadex.org/covers/abc/def.png.512.jpg',
        ),
        'https://uploads.mangadex.org/covers/abc/def.png.512.jpg',
      );
      expect(
        ServiceBibliotheque.adresseVignette('https://exemple.org/covers/a.jpg'),
        'https://exemple.org/covers/a.jpg',
      );
      expect(
        ServiceBibliotheque.adresseVignette('C:/images/a.jpg'),
        'C:/images/a.jpg',
      );
    });

    test(
      "la grille enregistre la vignette, la fiche demande l'originale",
      () async {
        final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
        final couvertures = requetes
            .where((uri) => uri.host == 'uploads.mangadex.org')
            .toList();
        expect(couvertures, hasLength(1));
        expect(couvertures.single.path, endsWith('.512.jpg'));
        expect(
          await service.cheminCouvertureLocale(ajout.titre),
          endsWith('.jpg'),
        );

        requetes.clear();
        expect(await service.chargerCouvertureOriginale(ajout.titre), <int>[
          9,
          8,
          7,
        ]);
        final originale = requetes.single;
        expect(originale.host, 'uploads.mangadex.org');
        expect(originale.path, isNot(endsWith('.512.jpg')));
      },
    );

    test("sans vignette sur le site (404), l'image d'origine est "
        'enregistrée', () async {
      vignetteAbsente = true;
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      expect(await service.chargerCouverture(ajout.titre), <int>[9, 8, 7]);
      expect(
        requetes.where((uri) => uri.host == 'uploads.mangadex.org'),
        hasLength(2),
      );
    });

    test("l'originale indisponible : la fiche affiche la vignette, sans "
        'redemander dans la session', () async {
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      siteEnPanne = true;
      requetes.clear();
      expect(await service.chargerCouvertureOriginale(ajout.titre), <int>[
        9,
        8,
        7,
      ]);
      final nombre = requetes.length;
      expect(await service.chargerCouvertureOriginale(ajout.titre), <int>[
        9,
        8,
        7,
      ]);
      expect(requetes.length, nombre);
    });

    test('donne le nom lisible du site externe', () {
      expect(
        ServiceBibliotheque.nomSiteExterne(
          'https://mangaplus.shueisha.co.jp/viewer/1',
        ),
        'MANGA Plus',
      );
    });

    test('reconnaît une page web parmi des octets de couverture', () {
      expect(
        ServiceBibliotheque.ressembleAUnePageWeb(utf8.encode(' <html>')),
        isTrue,
      );
      expect(
        ServiceBibliotheque.ressembleAUnePageWeb(<int>[0xFF, 0xD8, 0xFF]),
        isFalse,
      );
      expect(ServiceBibliotheque.ressembleAUnePageWeb(<int>[]), isFalse);
    });

    test('supprimer un titre efface sa couverture enregistrée', () async {
      final ajout = await service.ajouterTitreDepuisUrl(urlTitreReference);
      final chemin = (await service.cheminCouvertureLocale(ajout.titre))!;
      await service.supprimerTitre(ajout.titre.id!);
      expect(File(chemin).existsSync(), isFalse);
    });
  });

  group('erreurs de site', () {
    test(
      "une erreur du site porte le type de la source pour le rapport",
      () async {
        siteEnPanne = true;
        await expectLater(
          service.ajouterTitreDepuisUrl(urlTitreReference),
          throwsA(
            isA<ErreurSource>().having(
              (erreur) => erreur.typeDetecte,
              'typeDetecte',
              TypeSource.mangaDex,
            ),
          ),
        );
      },
    );

    test('la recherche demande les niveaux de contenu du réglage', () async {
      await parametres.enregistrerNiveauxContenu(<String>[
        niveauContenuTousPublics,
      ]);
      final source = await ServiceAjoutSite(
        depotSources,
        DetecteurTypeSite(
          creerClientTest(
            (_) async => http.Response('', 404),
            HorlogeFactice(),
          ),
        ),
      ).ajouterSite('https://mangadex.org');
      await service.rechercherSurSource(source, 'shinigami');
      final demande = requetes.lastWhere((uri) => uri.path == '/manga');
      expect(demande.queryParametersAll['contentRating[]'], <String>['safe']);
    });
  });
}
