// Tests du navigateur intégré (tâche N3) : base en mémoire, archives dans un
// dossier temporaire, faux service de téléchargement. Aucun appel réseau :
// le service n'en fait jamais.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/constantes_services.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_lecture_web.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/detection_image.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Vrai service de téléchargement (pause, changement de dossier, file en
/// base) dont seules les règles sont remplacées : il note les titres dont
/// les règles sont appliquées, sans lancer la file.
class _ServiceTelechargementEspion extends ServiceTelechargement {
  _ServiceTelechargementEspion({
    required super.depotTelechargements,
    required super.depotChapitres,
    required super.depotTitres,
    required super.depotListes,
    required super.depotSources,
    required super.stockage,
    required super.fabriqueSources,
    required super.client,
    required super.serviceParametres,
    required super.depotParametres,
  });

  final List<int> titresAppliques = <int>[];
  bool echouer = false;

  @override
  Future<PlanTelechargement> appliquerRegles(int idTitre) async {
    titresAppliques.add(idTitre);
    if (echouer) {
      throw StateError('règles en panne');
    }
    return PlanTelechargement.vide;
  }
}

/// Début d'un PNG valide, suivi d'octets quelconques.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  1,
  2,
  3,
]);

/// Début d'un JPEG valide, suivi d'octets quelconques.
final Uint8List _jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 4, 5, 6]);

const String _urlSiteA = 'https://www.site-a.example';
const String _urlSoloA = '$_urlSiteA/manga/solo-leveling/';
const String _urlKaijuA = '$_urlSiteA/manga/kaiju-n8/';
const String _urlSiteB = 'https://lien-seul.example';
const String _urlSoloB = '$_urlSiteB/oeuvre/solo-leveling';

void main() {
  late Database base;
  late Directory dossier;
  late DepotChapitres depotChapitres;
  late DepotTitres depotTitres;
  late DepotTitresSources depotTitresSources;
  late DepotSources depotSources;
  late StockageTelechargements stockage;
  late _ServiceTelechargementEspion telechargement;
  late DepotTelechargements depotTelechargements;
  late DepotParametres depotParametres;
  late ServiceDossierChapitres dossiers;
  late ServiceLectureWeb service;
  late JournalMemoire journal;
  late Source siteA;
  late Source siteB;
  late Titre solo;
  late Titre kaiju;
  late Chapitre soloChapitre1;
  late bool redemarrageNecessaire;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('lecture_web_test');
    journal = JournalMemoire();
    Journal.actuel = journal;
    redemarrageNecessaire = false;
    depotChapitres = DepotChapitres(base);
    depotTitres = DepotTitres(base);
    depotTitresSources = DepotTitresSources(base);
    depotSources = DepotSources(base);
    stockage = StockageTelechargements(dossier.path);
    depotTelechargements = DepotTelechargements(base);
    depotParametres = DepotParametres(base);
    // Aucune requête attendue : toute adresse répond 404.
    final client = creerClientTest(
      (requete) async => http.Response('introuvable', 404),
      HorlogeFactice(),
    );
    telechargement = _ServiceTelechargementEspion(
      depotTelechargements: depotTelechargements,
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotListes: DepotListes(base),
      depotSources: depotSources,
      stockage: stockage,
      fabriqueSources: FabriqueSources(client),
      client: client,
      serviceParametres: ServiceParametres(depotParametres),
      depotParametres: depotParametres,
    );
    addTearDown(telechargement.fermer);
    dossiers = ServiceDossierChapitres(
      serviceTelechargement: telechargement,
      depotParametres: depotParametres,
      cheminDossierParDefaut: () async => dossier.path,
      // Jamais le vrai `emplacements.json` du poste (path_provider) : rien
      // n'est écrit, pour ne pas ajouter de fichier au dossier des chapitres.
      cheminFichierEmplacements: () async => null,
    );
    service = ServiceLectureWeb(
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotTitresSources: depotTitresSources,
      depotSources: depotSources,
      stockage: stockage,
      serviceTelechargement: telechargement,
      estRedemarrageNecessaire: () => redemarrageNecessaire,
    );

    siteA = await depotSources.enregistrerSource(
      const Source(
        nom: 'Site A',
        urlBase: _urlSiteA,
        typeSource: TypeSource.madara,
        langueParDefaut: 'fr',
      ),
    );
    // Site générique en lien seul, avec un motif de numéro propre.
    siteB = await depotSources.enregistrerSource(
      const Source(
        nom: 'Lien seul',
        urlBase: _urlSiteB,
        typeSource: TypeSource.generique,
        langueParDefaut: 'en',
        configurationSelecteurs: r'{"motifNumeroChapitre": "lecture-(\\d+)"}',
      ),
    );
    solo = await depotTitres.enregistrerTitre(
      Titre(
        idSource: siteA.id,
        urlTitre: _urlSoloA,
        nom: 'Solo Leveling',
        typeTitre: TypeTitre.manga,
      ),
    );
    kaiju = await depotTitres.enregistrerTitre(
      Titre(idSource: siteA.id, urlTitre: _urlKaijuA, nom: 'Kaiju n°8'),
    );
    await depotTitresSources.ajouterSourceSecondaire(
      solo.id!,
      siteB.id!,
      _urlSoloB,
      lienSeul: true,
    );
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      Chapitre(
        idTitre: solo.id,
        urlChapitre: '${_urlSoloA}chapter-1/',
        nom: 'Chapitre 1',
        numero: 1,
        langue: 'fr',
      ),
    ]);
    soloChapitre1 = (await depotChapitres.chargerChapitres(solo.id!)).single;
  });

  tearDown(() async {
    Journal.actuel = const JournalSilencieux();
    await base.close();
    await dossier.delete(recursive: true);
  });

  group('extraireNumeroChapitre', () {
    test('lit le numéro après chapitre, chapter, ch, episode ou ep', () {
      double? numero(String url) =>
          ServiceLectureWeb.extraireNumeroChapitre(url);
      expect(numero('https://s.example/manga/x/chapter-12/'), 12);
      expect(numero('https://s.example/x/chapitre-10.5'), 10.5);
      expect(numero('https://s.example/x/ch_3'), 3);
      expect(numero('https://s.example/x/episode/7'), 7);
      expect(numero('https://s.example/x/ep.4'), 4);
      expect(numero('https://s.example/x/Chapter-8'), 8);
    });

    test('lit la forme chapter-10-5 comme 10,5 mais ignore un identifiant', () {
      expect(
        ServiceLectureWeb.extraireNumeroChapitre(
          'https://s.example/x/chapter-10-5/',
        ),
        10.5,
      );
      expect(
        ServiceLectureWeb.extraireNumeroChapitre(
          'https://s.example/x/chapter-3-1234567',
        ),
        3,
      );
    });

    test('cherche aussi dans les paramètres et ignore le fragment', () {
      expect(
        ServiceLectureWeb.extraireNumeroChapitre(
          'https://s.example/lire?serie=x&chapter=15#page-3',
        ),
        15,
      );
    });

    test('prend la dernière correspondance du chemin', () {
      expect(
        ServiceLectureWeb.extraireNumeroChapitre(
          'https://s.example/ep-2-le-retour/chapter-9',
        ),
        9,
      );
    });

    test("refuse une adresse sans mot-clé ni numéro plausible", () {
      double? numero(String url) =>
          ServiceLectureWeb.extraireNumeroChapitre(url);
      expect(numero('https://s.example/manga/kaiju-8/'), isNull);
      expect(numero('https://s.example/archives/march-12'), isNull);
      expect(numero('https://s.example/chapter/4815162'), isNull);
      expect(numero('https://s.example/x/chocolate-3'), isNull);
    });

    test('essaie le motif réglé du site avant le motif par défaut', () {
      expect(
        ServiceLectureWeb.extraireNumeroChapitre(
          'https://s.example/oeuvre/lecture-42',
          motifNumeroChapitre: r'lecture-(\d+)',
        ),
        42,
      );
      // Motif sans groupe : tout le texte reconnu sert de numéro.
      expect(
        ServiceLectureWeb.extraireNumeroChapitre(
          'https://s.example/oeuvre/n7',
          motifNumeroChapitre: r'n\d+',
        ),
        7,
      );
    });

    test('revient au motif par défaut si le motif réglé est invalide', () {
      expect(
        ServiceLectureWeb.extraireNumeroChapitre(
          'https://s.example/x/chapter-5',
          motifNumeroChapitre: '(',
        ),
        5,
      );
    });
  });

  group('evaluerCorrespondanceTitre', () {
    test("vaut 2 quand le chapitre est sous l'adresse du titre", () {
      expect(
        ServiceLectureWeb.evaluerCorrespondanceTitre(
          '${_urlSoloA}chapter-3',
          _urlSoloA,
        ),
        2,
      );
    });

    test("vaut 1 quand le chapitre contient l'identifiant du titre", () {
      expect(
        ServiceLectureWeb.evaluerCorrespondanceTitre(
          '$_urlSiteA/solo-leveling-chapter-3/',
          _urlSoloA,
        ),
        1,
      );
    });

    test('vaut 0 sans indice ou pour une adresse de titre générique', () {
      expect(
        ServiceLectureWeb.evaluerCorrespondanceTitre(
          '$_urlSiteA/chapter/99',
          _urlSoloA,
        ),
        0,
      );
      expect(
        ServiceLectureWeb.evaluerCorrespondanceTitre(
          '$_urlSiteA/manga/autre/chapter-1',
          '$_urlSiteA/manga/',
        ),
        0,
      );
    });
  });

  group('morceauxLisiblesChemin', () {
    test("garde le nom d'une œuvre sans le numéro ni l'extension", () {
      expect(
        ServiceLectureWeb.morceauxLisiblesChemin(
          'https://s.example/manga/one-piece/chapter-3',
        ),
        <String>['one-piece'],
      );
      expect(
        ServiceLectureWeb.morceauxLisiblesChemin(
          'https://s.example/solo-leveling-chapitre-3.html',
        ),
        <String>['solo-leveling'],
      );
    });

    test('ignore mots-clés, segments génériques et identifiants internes', () {
      List<String> morceaux(String url) =>
          ServiceLectureWeb.morceauxLisiblesChemin(url);
      expect(morceaux('https://s.example/chapter/4815162'), isEmpty);
      expect(morceaux('https://s.example/read/chapters/12'), isEmpty);
      expect(
        morceaux(
          'https://s.example/chapter/ef4aae9e-eea8-4931-8435-9f907870f4d8',
        ),
        isEmpty,
      );
      expect(morceaux('https://s.example/x/a1b2c3d4/ep-2'), isEmpty);
      expect(morceaux('https://s.example/one/ch-3'), isEmpty);
    });
  });

  group('validerImagesChapitre', () {
    test('renvoie le format de chaque image dans l\'ordre', () {
      expect(
        ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
          ImageRecue(_png),
          ImageRecue(_jpeg),
        ]),
        <FormatImage>[FormatImage.png, FormatImage.jpeg],
      );
    });

    test('refuse une page sans image', () {
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(const <ImageRecue>[]),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('Aucune image'),
          ),
        ),
      );
    });

    test('refuse des pages en canvas ou chiffrées avec un message clair', () {
      final refusProtege = throwsA(
        isA<ErreurService>().having(
          (e) => e.message,
          'message',
          messageImagesProtegees,
        ),
      );
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
          ImageRecue(_png),
          ImageRecue(_jpeg, estProtegee: true),
        ]),
        refusProtege,
      );
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
          ImageRecue(_png),
        ], pagesProtegees: true),
        refusProtege,
      );
      // Même sans image ordinaire : le message dit pourquoi.
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(
          const <ImageRecue>[],
          pagesProtegees: true,
        ),
        refusProtege,
      );
    });

    test('refuse une image blob:, data: ou servie par un éditeur protégé', () {
      final refusProtege = throwsA(
        isA<ErreurService>().having(
          (e) => e.message,
          'message',
          messageImagesProtegees,
        ),
      );
      for (final adresse in <String>[
        'blob:https://site.example/4f1c-22aa',
        'BLOB:https://site.example/4f1c-22aa',
        'data:image/png;base64,iVBORw0KGgo=',
        'https://mangaplus.shueisha.co.jp/page/1.jpg',
        'https://jumpg-assets.mangaplus.shueisha.co.jp/page/1.jpg',
      ]) {
        expect(
          () => ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
            ImageRecue(_png, adresse: 'https://cdn.site.example/1.png'),
            ImageRecue(_jpeg, adresse: adresse),
          ]),
          refusProtege,
          reason: adresse,
        );
      }
      // Un autre domaine qui finit pareil n'est pas un sous-domaine.
      expect(
        ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
          ImageRecue(
            _png,
            adresse: 'https://faux-mangaplus.shueisha.co.jp.example/1.png',
          ),
        ]),
        <FormatImage>[FormatImage.png],
      );
    });

    test('refuse un chapitre au-delà de 300 Mo', () {
      expect(tailleMaxTotaleChapitreWeb, 300 * 1024 * 1024);
      final grosse = Uint8List(tailleMaxImageChapitreWeb);
      grosse.setAll(0, _png);
      final nombre =
          tailleMaxTotaleChapitreWeb ~/ tailleMaxImageChapitreWeb + 1;
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(
          List<ImageRecue>.filled(nombre, ImageRecue(grosse)),
        ),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('trop lourdes'),
          ),
        ),
      );
    });

    test("refuse une page qui n'est pas une image reconnue", () {
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
          ImageRecue(_png),
          ImageRecue('<!doctype html><html></html>'.codeUnits),
        ]),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            allOf(contains('page 2'), contains('page HTML')),
          ),
        ),
      );
    });

    test('refuse une image vide ou trop grande', () {
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
          ImageRecue(Uint8List(0)),
        ]),
        throwsA(isA<ErreurService>()),
      );
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(<ImageRecue>[
          ImageRecue(Uint8List(tailleMaxImageChapitreWeb + 1)),
        ]),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('trop grande'),
          ),
        ),
      );
    });

    test("refuse plus d'images que le maximum par chapitre", () {
      expect(
        () => ServiceLectureWeb.validerImagesChapitre(
          List<ImageRecue>.filled(
            nombreMaxImagesChapitreWeb + 1,
            ImageRecue(_png),
          ),
        ),
        throwsA(isA<ErreurService>()),
      );
    });
  });

  group('reconnaitreChapitre', () {
    test(
      'reconnaît un chapitre connu malgré le fragment et le / final',
      () async {
        final reconnu = await service.reconnaitreChapitre(
          '${_urlSoloA}chapter-1#page-4',
        );
        expect(reconnu, isA<ChapitreConnu>());
        expect((reconnu! as ChapitreConnu).chapitre.id, soloChapitre1.id);
        expect(reconnu.idTitre, solo.id);
      },
    );

    test(
      'propose un chapitre web sur le site du titre, version sans www comprise',
      () async {
        final reconnu = await service.reconnaitreChapitre(
          'https://site-a.example/manga/solo-leveling/chapter-2/',
        );
        expect(reconnu, isA<ChapitreWebPossible>());
        final possible = reconnu! as ChapitreWebPossible;
        expect(possible.idTitre, solo.id);
        expect(possible.idSource, siteA.id);
        expect(possible.numero, 2);
        expect(possible.estLienSeul, isFalse);
      },
    );

    test('reconnaît un lien seul avec le motif réglé du site', () async {
      final reconnu = await service.reconnaitreChapitre('$_urlSoloB/lecture-7');
      final possible = reconnu! as ChapitreWebPossible;
      expect(possible.idTitre, solo.id);
      expect(possible.idSource, siteB.id);
      expect(possible.numero, 7);
      expect(possible.estLienSeul, isTrue);
    });

    test(
      "sans titre donné, n'attribue pas une adresse sans indice du titre",
      () async {
        expect(
          await service.reconnaitreChapitre('$_urlSiteA/chapter/99'),
          isNull,
        );
      },
    );

    test(
      'avec un titre donné, lui attribue une adresse de son site sans indice',
      () async {
        final reconnu = await service.reconnaitreChapitre(
          '$_urlSiteA/chapter/99',
          idTitre: solo.id,
        );
        expect((reconnu! as ChapitreWebPossible).idTitre, solo.id);
      },
    );

    test("avec un titre donné, n'attribue pas une adresse qui nomme une autre "
        'œuvre', () async {
      // One Piece n'est pas dans la bibliothèque : le chapitre ne doit pas
      // être noté (puis marqué lu) sous Solo Leveling.
      expect(
        await service.reconnaitreChapitre(
          '$_urlSiteA/manga/one-piece/chapter-3',
          idTitre: solo.id,
        ),
        isNull,
      );
      expect(
        await service.noterChapitreAffiche(
          '$_urlSiteA/one-piece-chapitre-3.html',
          idTitre: solo.id,
        ),
        isNull,
      );
      expect((await depotChapitres.chargerChapitres(solo.id!)).length, 1);
    });

    test(
      'avec un titre donné, lui attribue une adresse à identifiant interne',
      () async {
        final reconnu = await service.reconnaitreChapitre(
          '$_urlSiteA/chapter/ef4aae9e-eea8-4931-8435-9f907870f4d8/ch-12',
          idTitre: solo.id,
        );
        final possible = reconnu! as ChapitreWebPossible;
        expect(possible.idTitre, solo.id);
        expect(possible.numero, 12);
      },
    );

    test(
      "attribue à l'autre titre une adresse qui le désigne clairement",
      () async {
        final reconnu = await service.reconnaitreChapitre(
          '${_urlKaijuA}chapter-4',
          idTitre: solo.id,
        );
        final possible = reconnu! as ChapitreWebPossible;
        expect(possible.idTitre, kaiju.id);
        expect(possible.numero, 4);
      },
    );

    test(
      "ne reconnaît ni un site inconnu, ni la fiche, ni une page sans numéro",
      () async {
        expect(
          await service.reconnaitreChapitre(
            'https://inconnu.example/manga/solo-leveling/chapter-2',
          ),
          isNull,
        );
        expect(await service.reconnaitreChapitre(_urlSoloA), isNull);
        expect(
          await service.reconnaitreChapitre(_urlSoloA, idTitre: solo.id),
          isNull,
        );
        expect(
          await service.reconnaitreChapitre('${_urlSoloA}commentaires'),
          isNull,
        );
        expect(await service.reconnaitreChapitre('about:blank'), isNull);
        expect(await service.reconnaitreChapitre(''), isNull);
      },
    );

    test('renvoie null sans lever si la base est fermée', () async {
      await base.close();
      expect(
        await service.reconnaitreChapitre('${_urlSoloA}chapter-2'),
        isNull,
      );
      expect(
        journal.entrees.where((e) => e.niveau == NiveauJournal.avertissement),
        isNotEmpty,
      );
      // Rouverte pour le tearDown.
      base = await ouvrirBaseDeTest();
    });
  });

  group('noterChapitreAffiche', () {
    test(
      'enregistre un chapitre web dans la langue du site, une seule fois',
      () async {
        final premier = await service.noterChapitreAffiche(
          '$_urlSoloB/lecture-7#haut',
        );
        expect(premier, isNotNull);
        expect(premier!.origine, OrigineChapitre.web);
        expect(premier.numero, 7);
        expect(premier.langue, 'en');
        expect(premier.idSource, siteB.id);
        expect(premier.urlChapitre, '$_urlSoloB/lecture-7');
        expect(premier.estLu, isFalse);

        final second = await service.noterChapitreAffiche(
          '$_urlSoloB/lecture-7',
        );
        expect(second!.id, premier.id);
        expect((await depotChapitres.chargerChapitres(solo.id!)).length, 2);
      },
    );

    test('partage un enregistrement demandé deux fois en même temps', () async {
      final appels = <Future<Chapitre?>>[
        service.noterChapitreAffiche('${_urlSoloA}chapter-2'),
        service.noterChapitreAffiche('${_urlSoloA}chapter-2'),
      ];
      expect(identical(appels[0], appels[1]), isTrue);
      final resultats = await Future.wait(appels);
      expect(resultats[0]!.id, resultats[1]!.id);
      final chapitres = await depotChapitres.chargerChapitres(
        solo.id!,
        idSource: siteA.id,
      );
      expect(chapitres.where((c) => c.numero == 2), hasLength(1));
    });

    test('renvoie un chapitre connu sans rien créer', () async {
      final chapitre = await service.noterChapitreAffiche(
        '${_urlSoloA}chapter-1',
      );
      expect(chapitre!.id, soloChapitre1.id);
      expect((await depotChapitres.chargerChapitres(solo.id!)).length, 1);
    });

    test('renvoie null pour une page qui n\'est pas un chapitre', () async {
      expect(await service.noterChapitreAffiche(_urlSoloA), isNull);
      expect((await depotChapitres.chargerChapitres(solo.id!)).length, 1);
    });

    test("journalise l'enregistrement sans l'adresse complète", () async {
      await service.noterChapitreAffiche('${_urlSoloA}chapter-2?jeton=secret');
      final messages = journal.entrees.map((e) => e.message).join('\n');
      expect(messages, contains('noté'));
      expect(messages, isNot(contains('secret')));
    });
  });

  group('quitterChapitre', () {
    late Chapitre chapitre2;

    setUp(() async {
      chapitre2 = (await service.noterChapitreAffiche(
        '${_urlSoloA}chapter-2',
      ))!;
    });

    test(
      'marque lu le chapitre quitté pour le suivant et applique les règles',
      () async {
        expect(await service.quitterChapitre(soloChapitre1, chapitre2), isTrue);
        expect(
          (await depotChapitres.chargerChapitre(soloChapitre1.id!))!.estLu,
          isTrue,
        );
        expect(telechargement.titresAppliques, <int>[solo.id!]);
      },
    );

    test('ne marque rien en revenant en arrière', () async {
      expect(await service.quitterChapitre(chapitre2, soloChapitre1), isFalse);
      expect(
        (await depotChapitres.chargerChapitre(chapitre2.id!))!.estLu,
        isFalse,
      );
      expect(telechargement.titresAppliques, isEmpty);
    });

    test(
      "ne marque rien en passant à un autre titre ou hors d'un chapitre",
      () async {
        final autre = (await service.noterChapitreAffiche(
          '${_urlKaijuA}chapter-5',
        ))!;
        expect(await service.quitterChapitre(soloChapitre1, autre), isFalse);
        expect(await service.quitterChapitre(soloChapitre1, null), isFalse);
        expect(
          await service.quitterChapitre(soloChapitre1, soloChapitre1),
          isFalse,
        );
        expect(
          (await depotChapitres.chargerChapitre(soloChapitre1.id!))!.estLu,
          isFalse,
        );
        expect(telechargement.titresAppliques, isEmpty);
      },
    );

    test('garde le marquage si les règles échouent', () async {
      telechargement.echouer = true;
      expect(await service.quitterChapitre(soloChapitre1, chapitre2), isTrue);
      expect(
        (await depotChapitres.chargerChapitre(soloChapitre1.id!))!.estLu,
        isTrue,
      );
      expect(
        journal.entrees.where((e) => e.niveau == NiveauJournal.avertissement),
        isNotEmpty,
      );
    });
  });

  group('enregistrerImagesChapitre', () {
    late Chapitre chapitre2;

    setUp(() async {
      chapitre2 = (await service.noterChapitreAffiche(
        '${_urlSoloA}chapter-2',
      ))!;
    });

    test(
      "écrit l'archive dans l'ordre et marque le chapitre téléchargé",
      () async {
        final enregistre = await service.enregistrerImagesChapitre(
          chapitre2,
          <ImageRecue>[
            ImageRecue(_png, adresse: 'https://cdn.site-a.example/1.png'),
            ImageRecue(_jpeg, adresse: 'https://cdn.site-a.example/2.jpg'),
          ],
        );
        expect(enregistre.estTelecharge, isTrue);
        expect(enregistre.nomArchive, 'manga/Solo Leveling/ch2.fr.zip');
        final nom = enregistre.nomArchive!;
        expect(await stockage.existeArchive(nom), isTrue);
        expect(await stockage.compterPagesArchive(nom), 2);
        expect(await stockage.lirePageArchive(nom, 0), _png);
        expect(await stockage.lirePageArchive(nom, 1), _jpeg);
        expect(
          journal.entrees.map((e) => e.message).join('\n'),
          allOf(contains('enregistré depuis la page'), contains('cdn.site-a')),
        );
      },
    );

    test('numérote une archive en doublon comme la file', () async {
      final surB = await depotChapitres.enregistrerChapitreWeb(
        solo.id!,
        siteB.id!,
        numero: 2,
        url: '$_urlSoloB/lecture-2',
        langue: 'fr',
      );
      final premier = await service.enregistrerImagesChapitre(
        chapitre2,
        <ImageRecue>[ImageRecue(_png)],
      );
      final second = await service.enregistrerImagesChapitre(surB, <ImageRecue>[
        ImageRecue(_jpeg),
      ]);
      expect(premier.nomArchive, 'manga/Solo Leveling/ch2.fr.zip');
      expect(second.nomArchive, 'manga/Solo Leveling/ch2.fr.2.zip');
    });

    test('remplace la langue vide par celle du site', () async {
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: solo.id,
          urlChapitre: '${_urlSoloA}chapter-5',
          nom: 'Chapitre 5',
          numero: 5,
        ),
      ]);
      final chapitre5 = (await depotChapitres.chargerChapitreParUrl(
        '${_urlSoloA}chapter-5',
      ))!;
      final enregistre = await service.enregistrerImagesChapitre(
        chapitre5,
        <ImageRecue>[ImageRecue(_png)],
      );
      expect(enregistre.nomArchive, 'manga/Solo Leveling/ch5.fr.zip');
    });

    test("n'écrit rien si une page n'est pas une image", () async {
      await expectLater(
        service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
          ImageRecue(_png),
          ImageRecue('<html>défi</html>'.codeUnits),
        ]),
        throwsA(isA<ErreurService>()),
      );
      final relu = (await depotChapitres.chargerChapitre(chapitre2.id!))!;
      expect(relu.estTelecharge, isFalse);
      expect(relu.nomArchive, isNull);
      final fichiers = await dossier.list(recursive: true).toList();
      expect(fichiers.whereType<File>(), isEmpty);
    });

    test('refuse les pages protégées sans rien écrire', () async {
      await expectLater(
        service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
          ImageRecue(_png),
        ], pagesProtegees: true),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            messageImagesProtegees,
          ),
        ),
      );
      expect(
        (await depotChapitres.chargerChapitre(chapitre2.id!))!.estTelecharge,
        isFalse,
      );
    });

    test("refuse un chapitre d'un site aux images brouillées", () async {
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: solo.id,
          urlChapitre: '${_urlSoloA}chapter-6',
          nom: 'Chapitre 6',
          numero: 6,
          langue: 'fr',
          urlExterne: 'https://mangaplus.shueisha.co.jp/viewer/1000',
        ),
      ]);
      final externe = (await depotChapitres.chargerChapitreParUrl(
        '${_urlSoloA}chapter-6',
      ))!;
      await expectLater(
        service.enregistrerImagesChapitre(externe, <ImageRecue>[
          ImageRecue(_jpeg),
        ]),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            messageImagesProtegees,
          ),
        ),
      );
      final fichiers = await dossier.list(recursive: true).toList();
      expect(fichiers.whereType<File>(), isEmpty);
    });

    test(
      'refuse tant que le dossier des chapitres attend un redémarrage',
      () async {
        redemarrageNecessaire = true;
        await expectLater(
          service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
            ImageRecue(_png),
          ]),
          throwsA(
            isA<ErreurService>().having(
              (e) => e.message,
              'message',
              contains('redémarrez'),
            ),
          ),
        );
      },
    );

    test("refuse une image d'un domaine protégé sans rien écrire", () async {
      await expectLater(
        service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
          ImageRecue(
            _jpeg,
            adresse: 'https://www.mangaplus.shueisha.co.jp/img/1.jpg',
          ),
        ]),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            messageImagesProtegees,
          ),
        ),
      );
      final fichiers = await dossier.list(recursive: true).toList();
      expect(fichiers.whereType<File>(), isEmpty);
    });

    test(
      'retire de la file la ligne en attente du chapitre enregistré',
      () async {
        await depotTelechargements.ajouterEnFile(chapitre2.id!);
        final enregistre = await service.enregistrerImagesChapitre(
          chapitre2,
          <ImageRecue>[ImageRecue(_png)],
        );
        expect(enregistre.estTelecharge, isTrue);
        expect(
          await depotTelechargements.chargerParChapitre(chapitre2.id!),
          isNull,
        );
      },
    );

    test("laisse dans la file une ligne qui n'est pas en attente", () async {
      final ligne = await depotTelechargements.ajouterEnFile(chapitre2.id!);
      await depotTelechargements.enregistrerStatut(
        ligne.id!,
        StatutTelechargement.echec,
        messageErreur: 'site en panne',
      );
      await service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
        ImageRecue(_png),
      ]);
      expect(
        (await depotTelechargements.chargerParChapitre(chapitre2.id!))!.statut,
        StatutTelechargement.echec,
      );
    });

    group('changement du dossier des chapitres', () {
      late Directory autre;
      late String nas;

      setUp(() async {
        // Hors du dossier actuel : le déplacement n'y copie pas ses propres
        // fichiers.
        autre = await Directory.systemTemp.createTemp('lecture_web_nas');
        nas = await StockageTelechargements.validerDossier(
          '${autre.path}${Platform.pathSeparator}nas',
        );
      });

      tearDown(() async {
        await autre.delete(recursive: true);
      });

      Matcher refus(String extrait) => throwsA(
        isA<ErreurService>().having(
          (e) => e.message,
          'message',
          contains(extrait),
        ),
      );

      test('refuse un enregistrement pendant le changement puis jusqu\'au '
          'redémarrage', () async {
        final changement = dossiers.changerDossierChapitres(
          nas,
          deplacerArchives: false,
        );
        await expectLater(
          service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
            ImageRecue(_png),
          ]),
          refus('en train de changer'),
        );
        await changement;
        await expectLater(
          service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
            ImageRecue(_png),
          ]),
          refus('redémarrez'),
        );
        final relu = (await depotChapitres.chargerChapitre(chapitre2.id!))!;
        expect(relu.estTelecharge, isFalse);
      });

      test(
        'refuse un changement avec déplacement pendant un enregistrement',
        () async {
          final ecriture = Completer<void>();
          final enregistrement = telechargement.executerEnregistrementWeb(
            () => ecriture.future,
          );
          // Le compteur est pris après une lecture en base.
          await pumpEventQueue();
          expect(telechargement.nombreEnregistrementsWebEnCours, 1);
          await expectLater(
            dossiers.changerDossierChapitres(nas),
            refus('navigateur'),
          );
          // Pause gardée : aucun nouvel enregistrement ne commence.
          expect(dossiers.estFileEnPause, isTrue);
          await expectLater(
            service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
              ImageRecue(_png),
            ]),
            refus('en train de changer'),
          );
          ecriture.complete();
          await enregistrement;
          expect(telechargement.nombreEnregistrementsWebEnCours, 0);
          // Le client réessaie : le changement aboutit.
          final resultat = await dossiers.changerDossierChapitres(nas);
          expect(resultat.redemarrageNecessaire, isTrue);
        },
      );

      test('refuse un enregistrement si un déplacement est inachevé', () async {
        await depotParametres.enregistrerTexte(
          ServiceParametres.cleDeplacementDossierEnCours,
          nas,
        );
        await expectLater(
          service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
            ImageRecue(_png),
          ]),
          refus('inachevé'),
        );
        expect(telechargement.nombreEnregistrementsWebEnCours, 0);
      });

      test('libère le compteur même si l\'écriture échoue', () async {
        await expectLater(
          telechargement.executerEnregistrementWeb<void>(
            () async => throw StateError('disque plein'),
          ),
          throwsStateError,
        );
        expect(telechargement.nombreEnregistrementsWebEnCours, 0);
      });
    });

    test('refuse un chapitre non enregistré ou disparu', () async {
      await expectLater(
        service.enregistrerImagesChapitre(
          const Chapitre(
            urlChapitre: 'https://x.example/c',
            nom: 'c',
            numero: 1,
          ),
          <ImageRecue>[ImageRecue(_png)],
        ),
        throwsA(isA<ErreurService>()),
      );
      await expectLater(
        service.enregistrerImagesChapitre(
          chapitre2.copierAvec(id: 999999),
          <ImageRecue>[ImageRecue(_png)],
        ),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains("n'existe plus"),
          ),
        ),
      );
    });

    test('partage un enregistrement demandé deux fois (double clic)', () async {
      final premier = service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
        ImageRecue(_png),
      ]);
      final second = service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
        ImageRecue(_png),
      ]);
      expect(identical(premier, second), isTrue);
      final resultats = await Future.wait(<Future<Chapitre>>[premier, second]);
      expect(resultats[0].nomArchive, 'manga/Solo Leveling/ch2.fr.zip');
      final archives = (await dossier.list(recursive: true).toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'));
      expect(archives, hasLength(1));
    });

    test('réenregistre un chapitre déjà téléchargé sous le même nom', () async {
      await service.enregistrerImagesChapitre(chapitre2, <ImageRecue>[
        ImageRecue(_png),
      ]);
      final relu = (await depotChapitres.chargerChapitre(chapitre2.id!))!;
      final encore = await service.enregistrerImagesChapitre(relu, <ImageRecue>[
        ImageRecue(_jpeg),
        ImageRecue(_png),
      ]);
      expect(encore.nomArchive, 'manga/Solo Leveling/ch2.fr.zip');
      expect(await stockage.compterPagesArchive(encore.nomArchive!), 2);
    });
  });

  test("l'espacement des requêtes d'images est celui de ClientHttpPoli", () {
    expect(delaiRequetesImagesNavigateur, delaiMinimalParDomaine);
    expect(delaiRequetesImagesNavigateur, const Duration(seconds: 1));
  });

  test('un appel non attendu ne laisse pas de Future en erreur', () async {
    // noter et quitter ne lèvent jamais : l'interface peut les lancer sans
    // les attendre.
    await base.close();
    final note = await service.noterChapitreAffiche('${_urlSoloA}chapter-9');
    expect(note, isNull);
    final quitte = await service.quitterChapitre(
      soloChapitre1,
      soloChapitre1.copierAvec(id: 12345, numero: 2),
    );
    expect(quitte, isFalse);
    base = await ouvrirBaseDeTest();
  });
}
