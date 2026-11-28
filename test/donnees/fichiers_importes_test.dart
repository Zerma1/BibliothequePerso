import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_fichiers_importes.dart';
import 'package:bibliotheque_perso/donnees/depot_positions_lecture.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/empreinte_sha256.dart';
import 'package:bibliotheque_perso/donnees/erreur_stockage.dart';
import 'package:bibliotheque_perso/donnees/migrations.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/fichier_importe.dart';
import 'package:bibliotheque_perso/modeles/position_lecture.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  group('empreinte SHA-256', () {
    test('vecteurs officiels FIPS 180-4', () {
      expect(
        empreinteSha256(<int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        empreinteSha256(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        empreinteSha256(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      expect(
        empreinteSha256(List<int>.filled(1000000, 0x61)),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });

    test('calcul en flux sur un fichier = calcul en mémoire', () async {
      final dossier = await Directory.systemTemp.createTemp('sha_test_');
      try {
        final octets = List<int>.generate(200003, (i) => i * 31 % 256);
        final fichier = File(p.join(dossier.path, 'f.bin'))
          ..writeAsBytesSync(octets);
        expect(
          await calculerEmpreinteSha256Fichier(fichier.path),
          empreinteSha256(octets),
        );
      } finally {
        await dossier.delete(recursive: true);
      }
    });
  });

  group('modèles', () {
    test('FormatFichierLocal : extension, type par défaut, pagination', () {
      expect(
        FormatFichierLocal.depuisNomFichier('Tome 1.CBZ'),
        FormatFichierLocal.cbz,
      );
      expect(
        FormatFichierLocal.depuisNomFichier('a.epub'),
        FormatFichierLocal.epub,
      );
      expect(FormatFichierLocal.depuisNomFichier('a.cbr'), isNull);
      expect(FormatFichierLocal.depuisNomFichier('sans'), isNull);
      expect(FormatFichierLocal.cbz.typeTitreParDefaut, TypeTitre.manga);
      expect(FormatFichierLocal.pdf.typeTitreParDefaut, TypeTitre.livre);
      expect(FormatFichierLocal.epub.typeTitreParDefaut, TypeTitre.livre);
      expect(FormatFichierLocal.epub.estPagine, isFalse);
      expect(FormatFichierLocal.pdf.estPagine, isTrue);
    });

    test('FichierImporte : aller-retour versMap / depuisMap', () {
      final fichier = FichierImporte(
        idChapitre: 3,
        format: FormatFichierLocal.pdf,
        empreinteSha256: 'a' * 64,
        taille: 12,
        nomOrigine: 'livre.pdf',
        dateImport: DateTime.utc(2026, 11, 28),
      );
      expect(FichierImporte.depuisMap(fichier.versMap()), fichier);
      expect(fichier.copierAvec(taille: 13).taille, 13);
      expect(fichier.copierAvec(), fichier);
    });

    test('PositionLecture : aller-retour et contrôles', () {
      final page = PositionLecture.page(
        idChapitre: 1,
        page: 4,
        nombrePages: 20,
        dateMaj: DateTime.utc(2026),
      );
      final epub = PositionLecture.epub(
        idChapitre: 2,
        section: 3,
        fraction: 0.25,
        dateMaj: DateTime.utc(2026),
      );
      expect(PositionLecture.depuisMap(page.versMap()), page);
      expect(PositionLecture.depuisMap(epub.versMap()), epub);
      expect(
        () => PositionLecture(idChapitre: 1, dateMaj: DateTime.utc(2026)),
        throwsArgumentError,
      );
      expect(
        () => PositionLecture.epub(
          idChapitre: 1,
          section: 0,
          fraction: 1.5,
          dateMaj: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });
  });

  group('base', () {
    late Database base;
    late DepotFichiersImportes depot;
    late DepotChapitres depotChapitres;
    final empreinte = 'b' * 64;

    setUp(() async {
      base = await ouvrirBaseDeTest();
      depot = DepotFichiersImportes(base);
      depotChapitres = DepotChapitres(base);
    });

    tearDown(() async {
      await base.close();
    });

    Future<ImportEnregistre> importer({String? empreinteImport}) =>
        depot.enregistrerImport(
          nom: 'Mon livre',
          format: FormatFichierLocal.epub,
          empreinteSha256: empreinteImport ?? empreinte,
          taille: 42,
          nomOrigine: 'mon livre.epub',
          nomArchive: 'livre/Mon livre/import.epub',
          dateImport: DateTime.utc(2026, 11, 28),
        );

    test('adresse en dur de la migration = constante', () {
      expect(urlBaseFichiersLocaux, 'local://fichiers-locaux');
      expect(
        objetsMigration15.map((o) => o.$3).join(),
        contains("'$urlBaseFichiersLocaux'"),
      );
    });

    test('aucune source créée tant que rien n\'est importé', () async {
      expect(await DepotSources(base).chargerSources(), isEmpty);
    });

    test('la source Fichiers locaux est créée une fois, inactive', () async {
      final a = await depot.chargerOuCreerSourceFichiersLocaux();
      final b = await depot.chargerOuCreerSourceFichiersLocaux();
      expect(a, b);
      expect(a.estFichiersLocaux, isTrue);
      expect(a.estActive, isFalse);
      expect(a.nom, nomSourceFichiersLocaux);
    });

    test('la source Fichiers locaux ne peut être ni supprimée, ni activée, '
        'ni changer d\'adresse', () async {
      final source = await depot.chargerOuCreerSourceFichiersLocaux();
      final depotSources = DepotSources(base);
      await expectLater(
        depotSources.supprimerSource(source.id!),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      await expectLater(
        depotSources.enregistrerSource(source.copierAvec(estActive: true)),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      await expectLater(
        depotSources.enregistrerSource(
          source.copierAvec(urlBase: 'https://exemple.org'),
        ),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      // Filet de sécurité SQL, hors dépôt.
      await expectLater(
        base.delete('sources'),
        throwsA(isA<DatabaseException>()),
      );
      // Le nom reste modifiable.
      final renommee = await depotSources.enregistrerSource(
        source.copierAvec(nom: 'Mes fichiers'),
      );
      expect(renommee.nom, 'Mes fichiers');
      // Désinstallation partielle : la source système est gardée sans
      // faire échouer la suppression des autres.
      await depotSources.enregistrerSource(sourceMangaDex);
      final bilan = await depotSources.supprimerSourcesInutilisees();
      expect(bilan, (supprimees: 1, gardees: 1));
    });

    test(
      'enregistrerImport crée titre, chapitre et fichier ; doublon refusé',
      () async {
        final import = await importer();
        expect(import.titre.typeTitre, TypeTitre.livre);
        expect(import.titre.nom, 'Mon livre');
        final chapitre = await depotChapitres.chargerChapitre(
          import.chapitre.id!,
        );
        expect(chapitre!.estTelecharge, isTrue);
        expect(chapitre.estGarde, isTrue);
        expect(chapitre.nomArchive, 'livre/Mon livre/import.epub');
        expect(await depot.chargerParEmpreinte(empreinte), import.fichier);
        expect(await depot.chargerFichierImporte(chapitre.id!), import.fichier);
        expect(await depot.chargerIdsChapitresImportes(), {chapitre.id});
        expect(await depot.chargerFichiersImportes(), [import.fichier]);
        await expectLater(importer(), throwsA(isA<ErreurBaseDeDonnees>()));
        await expectLater(
          importer(empreinteImport: 'pas une empreinte'),
          throwsArgumentError,
        );
      },
    );

    test(
      'les règles de conservation ne peuvent rien prévoir sur un import',
      () async {
        final import = await importer();
        final id = import.chapitre.id!;
        expect(
          await depotChapitres.planifierSuppression(id, DateTime.utc(2027)),
          isFalse,
        );
        expect(
          (await depotChapitres.chargerChapitre(id))!.dateSuppressionPrevue,
          isNull,
        );
        expect(
          await depotChapitres.chargerSuppressionsEchues(DateTime.utc(2030)),
          isEmpty,
        );
      },
    );

    test('marquerTousNonTelecharges épargne les imports par défaut', () async {
      final import = await importer();
      final id = import.chapitre.id!;
      await depotChapitres.marquerTousNonTelecharges();
      expect((await depotChapitres.chargerChapitre(id))!.estTelecharge, isTrue);
      await depotChapitres.marquerTousNonTelecharges(
        inclureFichiersImportes: true,
      );
      final apres = (await depotChapitres.chargerChapitre(id))!;
      expect(apres.estTelecharge, isFalse);
      expect(apres.nomArchive, isNull);
    });

    test('supprimer le titre supprime chapitre, fichier et position', () async {
      final import = await importer();
      final positions = DepotPositionsLecture(base);
      await positions.enregistrerPosition(
        PositionLecture.epub(
          idChapitre: import.chapitre.id!,
          section: 2,
          fraction: 0.5,
          dateMaj: DateTime.utc(2026),
        ),
      );
      await DepotTitres(base).supprimerTitre(import.titre.id!);
      expect(await depot.chargerFichiersImportes(), isEmpty);
      expect(await base.query('positions_lecture'), isEmpty);
      // Réimport possible après suppression.
      await importer();
    });

    test(
      'positions : enregistrer, remplacer, charger par titre, effacer',
      () async {
        final import = await importer();
        final id = import.chapitre.id!;
        final positions = DepotPositionsLecture(base);
        expect(await positions.chargerPosition(id), isNull);
        final premiere = PositionLecture.page(
          idChapitre: id,
          page: 1,
          dateMaj: DateTime.utc(2026),
        );
        await positions.enregistrerPosition(premiere);
        final seconde = premiere.copierAvec(page: 7, nombrePages: 9);
        await positions.enregistrerPosition(seconde);
        expect(await positions.chargerPosition(id), seconde);
        expect(await positions.chargerPositionsDuTitre(import.titre.id!), {
          id: seconde,
        });
        expect(await positions.effacerPosition(id), isTrue);
        expect(await positions.chargerPosition(id), isNull);
        await expectLater(
          positions.enregistrerPosition(premiere.copierAvec(idChapitre: 999)),
          throwsA(isA<ErreurBaseDeDonnees>()),
        );
      },
    );
  });

  group('stockage', () {
    late Directory dossier;
    late StockageTelechargements stockage;
    late String source;

    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('import_test_');
      stockage = StockageTelechargements(p.join(dossier.path, 'racine'));
      final archive = Archive()
        ..add(ArchiveFile.bytes('p10.jpg', <int>[10]))
        ..add(ArchiveFile.bytes('p2.jpg', <int>[2]))
        ..add(ArchiveFile.bytes('__MACOSX/._p2.jpg', <int>[0]))
        ..add(ArchiveFile.bytes('info.txt', <int>[0]))
        ..add(ArchiveFile.bytes('P1.PNG', <int>[1]));
      source = p.join(dossier.path, 'Tome 1.cbz');
      File(source).writeAsBytesSync(ZipEncoder().encode(archive));
    });

    tearDown(() async {
      await dossier.delete(recursive: true);
    });

    Future<String> importer() => stockage.importerFichier(
      source,
      typeTitre: TypeTitre.manga,
      nomTitre: 'Tome: 1',
      format: FormatFichierLocal.cbz,
    );

    test('copie sous import.cbz puis import.2.cbz, sans .part', () async {
      final premier = await importer();
      final second = await importer();
      expect(premier, 'manga/Tome 1/import.cbz');
      expect(second, 'manga/Tome 1/import.2.cbz');
      expect(StockageTelechargements.estNomArchiveValide(premier), isTrue);
      expect(StockageTelechargements.estFichierImporte(second), isTrue);
      expect(
        StockageTelechargements.estFichierImporte('manga/T/ch1.fr.zip'),
        isFalse,
      );
      expect(
        StockageTelechargements.formatFichierImporte(premier),
        FormatFichierLocal.cbz,
      );
      expect(await stockage.existeArchive(premier), isTrue);
      final restes = Directory(p.join(dossier.path, 'racine'))
          .listSync(recursive: true)
          .where((e) => e.path.endsWith('.part'));
      expect(restes, isEmpty);
      // Le fichier d'origine n'est pas touché.
      expect(File(source).existsSync(), isTrue);
    });

    test('lecture CBZ en ordre naturel, entrées et octets', () async {
      final nom = await importer();
      expect(await stockage.compterPagesCbz(nom), 3);
      expect(await stockage.lirePageCbz(nom, 0), <int>[1]);
      expect(await stockage.lirePageCbz(nom, 1), <int>[2]);
      expect(await stockage.lirePageCbz(nom, 2), <int>[10]);
      await expectLater(
        stockage.lirePageCbz(nom, 3),
        throwsA(isA<ErreurStockage>()),
      );
      expect(
        await stockage.listerEntreesFichierImporte(nom),
        contains('info.txt'),
      );
      expect(await stockage.lireEntreeFichierImporte(nom, 'info.txt'), <int>[
        0,
      ]);
      expect(await stockage.lireEntreeFichierImporte(nom, 'absent'), isNull);
      expect(
        await stockage.lireFichierImporte(nom),
        File(source).readAsBytesSync(),
      );
      expect(File(stockage.cheminFichierImporte(nom)).existsSync(), isTrue);
    });

    test('une archive téléchargée n\'est pas lue comme un import', () {
      expect(
        () => stockage.cheminFichierImporte('manga/T/ch1.zip'),
        throwsA(isA<ErreurStockage>()),
      );
    });

    test('suppression, nettoyage des .part et déplacement', () async {
      final nom = await importer();
      final partiel = File('${stockage.cheminFichierImporte(nom)}.part')
        ..writeAsBytesSync(<int>[1]);
      final orphelin = File(
        p.join(dossier.path, 'racine', 'manga', 'Tome 1', 'import.pdf.part'),
      )..writeAsBytesSync(<int>[1]);
      expect(await stockage.nettoyerFichiersPartiels(), 2);
      expect(partiel.existsSync() || orphelin.existsSync(), isFalse);

      final cible = p.join(dossier.path, 'nouveau');
      final bilan = await stockage.deplacerArchivesVers(cible);
      expect(bilan.nombreCopies, 1);
      final nouveau = StockageTelechargements.personnalise(cible);
      expect(await nouveau.compterPagesCbz(nom), 3);
      expect(await nouveau.supprimerFichierImporte(nom), isTrue);
      expect(await nouveau.existeArchive(nom), isFalse);
    });

    test('source absente : erreur claire', () async {
      await expectLater(
        stockage.importerFichier(
          p.join(dossier.path, 'absent.pdf'),
          typeTitre: TypeTitre.livre,
          nomTitre: 'X',
          format: FormatFichierLocal.pdf,
        ),
        throwsA(isA<ErreurStockage>()),
      );
    });
  });
}
