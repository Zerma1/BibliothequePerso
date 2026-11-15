import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bibliotheque_perso/donnees/erreur_stockage.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Octets factices d'une image : contenu distinct pour chaque [graine].
Uint8List image(int graine, {int taille = 2000}) => Uint8List.fromList(
  List<int>.generate(taille, (i) => (i * 7 + graine) % 256),
);

Titre titre(String nom, {TypeTitre type = TypeTitre.manga}) =>
    Titre(urlTitre: 'https://exemple.org/$nom', nom: nom, typeTitre: type);

Chapitre chapitre(double numero, {String langue = 'en'}) => Chapitre(
  urlChapitre: 'https://exemple.org/ch/$numero/$langue',
  nom: 'Chapitre $numero',
  numero: numero,
  langue: langue,
);

void main() {
  late Directory dossier;
  late String racine;
  late StockageTelechargements stockage;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('stockage_test_');
    racine = p.join(dossier.path, 'bibliotheque_perso');
    stockage = StockageTelechargements(racine);
  });

  tearDown(() async {
    if (await dossier.exists()) {
      await dossier.delete(recursive: true);
    }
  });

  group('chemins', () {
    test('exemples du playbook', () {
      expect(
        stockage.cheminChapitre(titre('One Punch Man'), chapitre(1)),
        p.join(racine, 'manga', 'One Punch Man', 'ch1.en.zip'),
      );
      expect(
        stockage.cheminChapitre(
          titre('Solo Leveling', type: TypeTitre.manhwa),
          chapitre(10.5, langue: 'fr'),
        ),
        p.join(racine, 'manhwa', 'Solo Leveling', 'ch10.5.fr.zip'),
      );
    });

    test('numéros sans zéros inutiles', () {
      expect(StockageTelechargements.formaterNumero(1), '1');
      expect(StockageTelechargements.formaterNumero(1.0), '1');
      expect(StockageTelechargements.formaterNumero(10.5), '10.5');
      expect(StockageTelechargements.formaterNumero(10.50), '10.5');
      expect(StockageTelechargements.formaterNumero(2.25), '2.25');
      expect(StockageTelechargements.formaterNumero(0), '0');
      expect(StockageTelechargements.formaterNumero(100), '100');
      expect(
        () => StockageTelechargements.formaterNumero(double.nan),
        throwsArgumentError,
      );
      expect(
        () => StockageTelechargements.formaterNumero(double.infinity),
        throwsArgumentError,
      );
    });

    test('langues : normalisation et repli sans langue', () {
      expect(
        StockageTelechargements.nomFichierChapitre(chapitre(1, langue: '')),
        'ch1.zip',
      );
      expect(
        StockageTelechargements.nomFichierChapitre(chapitre(1, langue: '  ')),
        'ch1.zip',
      );
      expect(
        StockageTelechargements.nomFichierChapitre(chapitre(1, langue: 'EN ')),
        'ch1.en.zip',
      );
      expect(
        StockageTelechargements.nomFichierChapitre(
          chapitre(3, langue: 'pt-BR'),
        ),
        'ch3.pt-br.zip',
      );
      expect(
        StockageTelechargements.nomFichierChapitre(chapitre(3, langue: 'f/r')),
        'ch3.fr.zip',
      );
    });

    test('nettoyage des caractères interdits et de la fin du nom', () {
      expect(
        StockageTelechargements.nettoyerNom(
          'Re:Zero <Kara> "Hajimeru" / Isekai | Seikatsu? *',
        ),
        'ReZero Kara Hajimeru  Isekai  Seikatsu',
      );
      expect(StockageTelechargements.nettoyerNom(r'A\B'), 'AB');
      expect(
        StockageTelechargements.nettoyerNom('Dr. Stone...  '),
        'Dr. Stone',
      );
      expect(StockageTelechargements.nettoyerNom('  Berserk'), 'Berserk');
      expect(StockageTelechargements.nettoyerNom('Bip\u0007Bip'), 'BipBip');
      expect(StockageTelechargements.nettoyerNom('死神に育てられた少女'), '死神に育てられた少女');
    });

    test('noms vides, réservés ou trop longs', () {
      expect(StockageTelechargements.nettoyerNom('???'), 'sans nom');
      expect(StockageTelechargements.nettoyerNom('..'), 'sans nom');
      expect(StockageTelechargements.nettoyerNom(''), 'sans nom');
      expect(StockageTelechargements.nettoyerNom('CON'), 'CON_');
      expect(StockageTelechargements.nettoyerNom('nul.txt'), 'nul.txt_');
      expect(StockageTelechargements.nettoyerNom('Console'), 'Console');
      expect(StockageTelechargements.nettoyerNom('a' * 150), 'a' * 100);
      // L'emoji (2 unités UTF-16) ne tient pas : il n'est pas coupé en deux.
      expect(StockageTelechargements.nettoyerNom('${'a' * 99}😀b'), 'a' * 99);
    });

    test('un nom malveillant reste dans le dossier racine', () {
      final chemin = stockage.cheminChapitre(titre('../../..'), chapitre(1));
      expect(p.isWithin(racine, chemin), isTrue);
      expect(chemin, p.join(racine, 'manga', 'sans nom', 'ch1.en.zip'));
    });

    test('collision entre sources : suffixe « (nom de la source) »', () {
      expect(
        stockage.cheminChapitre(
          titre('One Punch Man'),
          chapitre(1),
          nomSource: 'MangaDex',
        ),
        p.join(racine, 'manga', 'One Punch Man (MangaDex)', 'ch1.en.zip'),
      );
      expect(
        StockageTelechargements.nomDossierTitre(
          'One Punch Man',
          nomSource: 'Site: X?',
        ),
        'One Punch Man (Site X)',
      );
      // Un nom de source vide ne déclenche pas de suffixe.
      expect(
        StockageTelechargements.nomDossierTitre(
          'One Punch Man',
          nomSource: ' ',
        ),
        'One Punch Man',
      );
      // Le suffixe survit à la troncature d'un nom très long.
      expect(
        StockageTelechargements.nomDossierTitre('a' * 150, nomSource: 'Lel'),
        '${'a' * 100} (Lel)',
      );
    });

    test('extensions des pages', () {
      expect(StockageTelechargements.normaliserExtension('.WebP'), 'webp');
      expect(StockageTelechargements.normaliserExtension('jpeg'), 'jpeg');
      expect(
        () => StockageTelechargements.normaliserExtension('j/g'),
        throwsArgumentError,
      );
      expect(
        () => StockageTelechargements.normaliserExtension(''),
        throwsArgumentError,
      );
      expect(
        StockageTelechargements.extensionDepuisUrl(
          'https://uploads.mangadex.org/data/abc/1-f3.JPG?t=1',
        ),
        'jpg',
      );
      expect(
        StockageTelechargements.extensionDepuisUrl('https://exemple.org/page'),
        isNull,
      );
      expect(
        StockageTelechargements.extensionDepuisUrl(
          'https://exemple.org/image.extensiontroplongue',
        ),
        isNull,
      );
    });
  });

  group('archives', () {
    final titreTest = titre('One Punch Man');
    final chapitreTest = chapitre(1);

    test('écriture page par page puis lecture sans extraction', () async {
      final pages = <Uint8List>[image(1), image(2, taille: 3000), image(3)];
      final extensions = <String>['jpg', 'png', '.WEBP'];
      final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      final partiel = File(ecriture.cheminPartiel);
      expect(ecriture.cheminPartiel, '${ecriture.cheminFinal}.part');

      var tailleAvant = 0;
      for (var i = 0; i < pages.length; i++) {
        await ecriture.ajouterPage(pages[i], extension: extensions[i]);
        // Chaque page est déjà sur le disque, dans le .part.
        final taille = await partiel.length();
        expect(taille, greaterThanOrEqualTo(tailleAvant + pages[i].length));
        tailleAvant = taille;
        // Un .part n'est jamais pris pour un chapitre téléchargé.
        expect(await stockage.estTelecharge(titreTest, chapitreTest), isFalse);
      }
      expect(ecriture.nombrePages, 3);

      final cheminFinal = await ecriture.finaliser();
      expect(cheminFinal, stockage.cheminChapitre(titreTest, chapitreTest));
      expect(ecriture.estFermee, isTrue);
      expect(await partiel.exists(), isFalse);
      expect(await File(cheminFinal).exists(), isTrue);
      expect(await stockage.estTelecharge(titreTest, chapitreTest), isTrue);

      expect(await stockage.compterPages(titreTest, chapitreTest), 3);
      for (var i = 0; i < pages.length; i++) {
        expect(await stockage.lirePage(titreTest, chapitreTest, i), pages[i]);
      }
      expect(await stockage.lireTexte(titreTest, chapitreTest), isNull);

      // Contenu de l'archive : noms img<n> avec l'extension d'origine, mode
      // store (sans recompression).
      final archive = ZipDecoder().decodeBytes(
        await File(cheminFinal).readAsBytes(),
      );
      expect(archive.map((entree) => entree.name).toList(), <String>[
        'img1.jpg',
        'img2.png',
        'img3.webp',
      ]);
      for (final entree in archive) {
        expect(entree.compression, CompressionType.none);
      }
    });

    test(
      'les pages sont lues dans l\'ordre numérique (img2 avant img10)',
      () async {
        final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
        for (var i = 1; i <= 11; i++) {
          await ecriture.ajouterPage(image(i, taille: 50), extension: 'jpg');
        }
        await ecriture.finaliser();
        expect(await stockage.compterPages(titreTest, chapitreTest), 11);
        expect(
          await stockage.lirePage(titreTest, chapitreTest, 9),
          image(10, taille: 50),
        );
        expect(
          await stockage.lirePage(titreTest, chapitreTest, 1),
          image(2, taille: 50),
        );
      },
    );

    test('lecture : indice hors limites, chapitre absent ou abîmé', () async {
      await expectLater(
        stockage.lirePage(titreTest, chapitreTest, 0),
        throwsA(isA<ErreurStockage>()),
      );
      await expectLater(
        stockage.compterPages(titreTest, chapitreTest),
        throwsA(isA<ErreurStockage>()),
      );

      final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await ecriture.ajouterPage(image(1), extension: 'jpg');
      await ecriture.finaliser();
      await expectLater(
        stockage.lirePage(titreTest, chapitreTest, 1),
        throwsA(isA<ErreurStockage>()),
      );
      await expectLater(
        stockage.lirePage(titreTest, chapitreTest, -1),
        throwsA(isA<ErreurStockage>()),
      );

      // Archive remplacée par des octets qui ne sont pas un zip.
      await File(stockage.cheminChapitre(titreTest, chapitreTest))
          .writeAsBytes(image(9, taille: 100));
      await expectLater(
        stockage.lirePage(titreTest, chapitreTest, 0),
        throwsA(isA<ErreurStockage>()),
      );
    });

    test('une archive interrompue (.part) n\'est jamais lue', () async {
      final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await ecriture.ajouterPage(image(1), extension: 'jpg');
      expect(await File(ecriture.cheminPartiel).exists(), isTrue);
      expect(await stockage.estTelecharge(titreTest, chapitreTest), isFalse);
      await expectLater(
        stockage.compterPages(titreTest, chapitreTest),
        throwsA(isA<ErreurStockage>()),
      );
      await ecriture.abandonner();
    });

    test('abandon : le .part est supprimé et l\'écriture est fermée', () async {
      final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await ecriture.ajouterPage(image(1), extension: 'jpg');
      await ecriture.abandonner();
      expect(ecriture.estFermee, isTrue);
      expect(await File(ecriture.cheminPartiel).exists(), isFalse);
      expect(await stockage.estTelecharge(titreTest, chapitreTest), isFalse);
      // Un second abandon ne fait rien ; toute autre opération est refusée.
      await ecriture.abandonner();
      await expectLater(
        ecriture.ajouterPage(image(2), extension: 'jpg'),
        throwsA(isA<ErreurStockage>()),
      );
      await expectLater(ecriture.finaliser(), throwsA(isA<ErreurStockage>()));
      // Le chapitre peut être rouvert après l'abandon.
      final nouvelle = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await nouvelle.abandonner();
    });

    test('un chapitre vide n\'est jamais finalisé', () async {
      final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await expectLater(ecriture.finaliser(), throwsA(isA<ErreurStockage>()));
      expect(ecriture.estFermee, isTrue);
      expect(await File(ecriture.cheminPartiel).exists(), isFalse);
      expect(await stockage.estTelecharge(titreTest, chapitreTest), isFalse);
    });

    test('pages invalides refusées', () async {
      final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await expectLater(
        ecriture.ajouterPage(Uint8List(0), extension: 'jpg'),
        throwsA(isA<ErreurStockage>()),
      );
      await expectLater(
        ecriture.ajouterPage(image(1), extension: 'j?g'),
        throwsArgumentError,
      );
      expect(ecriture.nombrePages, 0);
      await ecriture.abandonner();
    });

    test('deux écritures simultanées du même chapitre sont refusées', () async {
      final premiere = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await expectLater(
        stockage.ouvrirEcriture(titreTest, chapitreTest),
        throwsA(isA<ErreurStockage>()),
      );
      // Un autre chapitre du même titre reste possible.
      final autre = await stockage.ouvrirEcriture(titreTest, chapitre(2));
      await autre.abandonner();
      await premiere.abandonner();
    });

    test('chapitre texte : contenu.html en UTF-8', () async {
      final roman = titre('Mushoku Tensei', type: TypeTitre.roman);
      final ecriture = await stockage.ouvrirEcriture(roman, chapitreTest);
      const html = '<p>Été, « guillemets » et 漢字.</p>';
      await ecriture.ajouterTexte(html);
      await expectLater(
        ecriture.ajouterPage(image(1), extension: 'jpg'),
        throwsA(isA<ErreurStockage>()),
      );
      await expectLater(
        ecriture.ajouterTexte(html),
        throwsA(isA<ErreurStockage>()),
      );
      await ecriture.finaliser();
      expect(await stockage.lireTexte(roman, chapitreTest), html);
      expect(await stockage.compterPages(roman, chapitreTest), 0);
      expect(
        stockage.cheminChapitre(roman, chapitreTest),
        p.join(racine, 'roman', 'Mushoku Tensei', 'ch1.en.zip'),
      );
    });

    test('une nouvelle finalisation remplace l\'archive existante', () async {
      final premiere = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await premiere.ajouterPage(image(1), extension: 'jpg');
      await premiere.ajouterPage(image(2), extension: 'jpg');
      await premiere.finaliser();

      final seconde = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      // Pendant la réécriture, l'ancienne archive complète reste lisible.
      expect(await stockage.compterPages(titreTest, chapitreTest), 2);
      await seconde.ajouterPage(image(5), extension: 'png');
      await seconde.finaliser();
      expect(await stockage.compterPages(titreTest, chapitreTest), 1);
      expect(await stockage.lirePage(titreTest, chapitreTest, 0), image(5));
    });

    test('suppression d\'un chapitre puis du dossier vide du titre', () async {
      final ecriture = await stockage.ouvrirEcriture(titreTest, chapitreTest);
      await ecriture.ajouterPage(image(1), extension: 'jpg');
      await ecriture.finaliser();
      final dossierTitre = Directory(stockage.cheminDossierTitre(titreTest));

      expect(await stockage.supprimerChapitre(titreTest, chapitreTest), isTrue);
      expect(await stockage.estTelecharge(titreTest, chapitreTest), isFalse);
      expect(await dossierTitre.exists(), isFalse);
      expect(
        await stockage.supprimerChapitre(titreTest, chapitreTest),
        isFalse,
      );
    });

    test('la suppression garde le dossier s\'il reste des chapitres', () async {
      for (final numero in <double>[1, 2]) {
        final ecriture = await stockage.ouvrirEcriture(
          titreTest,
          chapitre(numero),
        );
        await ecriture.ajouterPage(image(1), extension: 'jpg');
        await ecriture.finaliser();
      }
      await stockage.supprimerChapitre(titreTest, chapitre(1));
      expect(await stockage.estTelecharge(titreTest, chapitre(2)), isTrue);
    });

    test(
      'nettoyage des .part orphelins, sans toucher aux écritures en cours',
      () async {
        expect(await stockage.nettoyerFichiersPartiels(), 0);

        final complete = await stockage.ouvrirEcriture(titreTest, chapitre(1));
        await complete.ajouterPage(image(1), extension: 'jpg');
        await complete.finaliser();

        // Deux .part laissés par une interruption (application tuée).
        final orphelin1 = File(
          '${stockage.cheminChapitre(titreTest, chapitre(2))}.part',
        );
        final orphelin2 = File(
          '${stockage.cheminChapitre(titre('Berserk'), chapitre(3))}.part',
        );
        for (final orphelin in <File>[orphelin1, orphelin2]) {
          await orphelin.create(recursive: true);
          await orphelin.writeAsBytes(image(1, taille: 10));
        }
        final enCours = await stockage.ouvrirEcriture(titreTest, chapitre(4));
        await enCours.ajouterPage(image(4), extension: 'jpg');

        expect(await stockage.nettoyerFichiersPartiels(), 2);
        expect(await orphelin1.exists(), isFalse);
        expect(await orphelin2.exists(), isFalse);
        expect(await File(enCours.cheminPartiel).exists(), isTrue);
        expect(await stockage.estTelecharge(titreTest, chapitre(1)), isTrue);

        await enCours.finaliser();
        expect(await stockage.compterPages(titreTest, chapitre(4)), 1);
      },
    );
  });
}
