import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/donnees/gestionnaire_transactions.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotChapitres depot;
  late int idTitre;
  late int idAutreTitre;
  late int idScanManga;

  Chapitre chapitre(
    double numero, {
    String langue = 'en',
    int? titre,
    int? idSource,
    String? urlExterne,
  }) => Chapitre(
    idTitre: titre ?? idTitre,
    idSource: idSource,
    urlChapitre:
        'https://exemple.org/${titre ?? idTitre}/${idSource ?? 0}/'
        '$numero-$langue',
    nom: 'Chapitre $numero',
    numero: numero,
    langue: langue,
    urlExterne: urlExterne,
  );

  /// Numéros (et langue) des chapitres lus de [titre], triés.
  Future<List<String>> lus(int titre) async => <String>[
    for (final c in await depot.chargerChapitres(titre))
      if (c.estLu) '${c.numero}.${c.langue}',
  ];

  Future<List<int>> ids(int titre) async => <int>[
    for (final c in await depot.chargerChapitres(titre)) c.id!,
  ];

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotChapitres(base);
    final sources = DepotSources(base);
    final idMangaDex = (await sources.enregistrerSource(sourceMangaDex)).id!;
    idScanManga = (await sources.enregistrerSource(
      const Source(
        nom: 'Scan-Manga',
        urlBase: 'https://www.scan-manga.com',
        typeSource: TypeSource.scanManga,
      ),
    )).id!;
    final titres = DepotTitres(base);
    idTitre = (await titres.enregistrerTitre(titreReference(idMangaDex))).id!;
    idAutreTitre = (await titres.enregistrerTitre(
      Titre(
        idSource: idMangaDex,
        urlTitre: 'https://mangadex.org/title/autre',
        nom: 'Autre titre',
        typeTitre: TypeTitre.manga,
      ),
    )).id!;
    await DepotTitresSources(base).ajouterSourceSecondaire(
      idTitre,
      idScanManga,
      'https://www.scan-manga.com/reference',
    );
  });

  tearDown(() async {
    await base.close();
  });

  group('marquerLus', () {
    test('marque les chapitres donnés et renvoie le nombre de changements, '
        'doublons et inconnus ignorés', () async {
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(1),
        chapitre(2),
        chapitre(3),
      ]);
      final tous = await ids(idTitre);

      expect(await depot.marquerLus(<int>[tous[0], tous[2], tous[0], 999]), 2);
      expect(await lus(idTitre), <String>['1.0.en', '3.0.en']);
      // Déjà lus : rien ne change, rien n'est compté.
      expect(await depot.marquerLus(<int>[tous[0], tous[1]]), 1);
      expect(await lus(idTitre), hasLength(3));

      // Retour à « non lu ».
      expect(await depot.marquerLus(<int>[tous[1], tous[2]], lu: false), 2);
      expect(await lus(idTitre), <String>['1.0.en']);
      expect(await depot.compterNonLus(idTitre), 2);
    });

    test('une liste vide ne fait rien', () async {
      expect(await depot.marquerLus(const <int>[]), 0);
    });

    test('seule la colonne est_lu est écrite', () async {
      await depot.enregistrerChapitres(<Chapitre>[chapitre(1)]);
      final id = (await ids(idTitre)).single;
      await depot.enregistrerArchive(id, 'manga/Titre/ch1.en.zip');
      await depot.marquerGarde(id);
      final avant = (await depot.chargerChapitre(id))!;

      expect(await depot.marquerLus(<int>[id]), 1);

      expect(await depot.chargerChapitre(id), avant.copierAvec(estLu: true));
    });

    test('plus d\'ids que la taille d\'un lot : tout est marqué', () async {
      final nombre = tailleMaxLotParametresSql * 2 + 7;
      await depot.enregistrerChapitres(<Chapitre>[
        for (var n = 1; n <= nombre; n++) chapitre(n.toDouble()),
      ]);
      final tous = await ids(idTitre);
      expect(tous, hasLength(nombre));

      expect(await depot.marquerLus(tous), nombre);
      expect(await depot.compterNonLus(idTitre), 0);
      expect(await depot.marquerLus(tous, lu: false), nombre);
      expect(await depot.compterNonLus(idTitre), nombre);
    });

    test('accepte une transaction extérieure, annulée avec elle', () async {
      await depot.enregistrerChapitres(<Chapitre>[chapitre(1), chapitre(2)]);
      final tous = await ids(idTitre);
      final gestionnaire = GestionnaireTransactions(base);

      await expectLater(
        gestionnaire.executerEnTransaction((txn) async {
          expect(await depot.marquerLus(tous, executeur: txn), 2);
          throw StateError('annulation');
        }),
        throwsStateError,
      );
      expect(await lus(idTitre), isEmpty);

      final nombre = await gestionnaire.executerEnTransaction(
        (txn) => depot.marquerLus(tous, executeur: txn),
      );
      expect(nombre, 2);
      expect(await lus(idTitre), hasLength(2));
    });
  });

  group('marquerLusJusqua', () {
    setUp(() async {
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(1),
        chapitre(2),
        chapitre(2, langue: 'fr'),
        chapitre(2.5),
        chapitre(3),
        // Chapitre externe (lu chez l'éditeur).
        chapitre(1.5, urlExterne: 'https://editeur.example/1.5'),
        chapitre(4),
      ]);
      // Chapitres du site secondaire.
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(2, idSource: idScanManga),
        chapitre(5, idSource: idScanManga),
      ]);
      // Un autre titre, jamais touché.
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(1, titre: idAutreTitre),
      ]);
    });

    test('marque tous les chapitres de numéro ≤ numero, toutes langues, '
        'tous sites, externes compris', () async {
      expect(await depot.marquerLusJusqua(idTitre, 2.5), 6);
      expect(await lus(idTitre), <String>[
        '1.0.en',
        '1.5.en',
        '2.0.en',
        '2.0.fr',
        '2.0.en',
        '2.5.en',
      ]);
      final lusParSite = <int?>{
        for (final c in await depot.chargerChapitres(idTitre))
          if (c.estLu) c.idSource,
      };
      expect(lusParSite, hasLength(2));
      expect(await lus(idAutreTitre), isEmpty);
    });

    test('ne compte que les chapitres dont l\'état change', () async {
      expect(await depot.marquerLusJusqua(idTitre, 1), 1);
      expect(await depot.marquerLusJusqua(idTitre, 2), 4);
      expect(await depot.marquerLusJusqua(idTitre, 2), 0);
    });

    test('lu: false remet les chapitres jusqu\'au numéro à non lus', () async {
      await depot.marquerTousLus(idTitre);
      expect(await depot.marquerLusJusqua(idTitre, 3, lu: false), 7);
      expect(await lus(idTitre), <String>['4.0.en', '5.0.en']);
    });

    test('un numéro sous le premier chapitre ne marque rien', () async {
      expect(await depot.marquerLusJusqua(idTitre, 0.5), 0);
      expect(await lus(idTitre), isEmpty);
    });

    test('un titre inconnu ne marque rien', () async {
      expect(await depot.marquerLusJusqua(999, 100), 0);
    });

    test('un numéro non fini est refusé', () async {
      await expectLater(
        depot.marquerLusJusqua(idTitre, double.nan),
        throwsArgumentError,
      );
      await expectLater(
        depot.marquerLusJusqua(idTitre, double.infinity),
        throwsArgumentError,
      );
    });

    test('accepte une transaction extérieure', () async {
      final nombre = await GestionnaireTransactions(base).executerEnTransaction(
        (txn) => depot.marquerLusJusqua(idTitre, 1.5, executeur: txn),
      );
      expect(nombre, 2);
      expect(await lus(idTitre), <String>['1.0.en', '1.5.en']);
    });
  });
}
