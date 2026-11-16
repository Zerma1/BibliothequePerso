// Tests de l'étape 6 sur StockageTelechargements : couvertures enregistrées
// sur l'appareil (`<type>/<titre>/couverture.<ext>`).
import 'dart:io';
import 'dart:typed_data';

import 'package:bibliotheque_perso/donnees/constantes_donnees.dart';
import 'package:bibliotheque_perso/donnees/erreur_stockage.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Octets factices d'une image : contenu distinct pour chaque [graine].
Uint8List image(int graine, {int taille = 500}) => Uint8List.fromList(
  List<int>.generate(taille, (i) => (i * 3 + graine) % 256),
);

Titre titre(String nom, {TypeTitre type = TypeTitre.manga}) =>
    Titre(urlTitre: 'https://exemple.org/$nom', nom: nom, typeTitre: type);

void main() {
  late Directory dossier;
  late String racine;
  late StockageTelechargements stockage;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('couvertures_test_');
    racine = p.join(dossier.path, 'bibliotheque_perso');
    stockage = StockageTelechargements(racine);
  });

  tearDown(() async {
    if (await dossier.exists()) {
      await dossier.delete(recursive: true);
    }
  });

  test('enregistre la couverture dans le dossier du titre', () async {
    final chemin = await stockage.enregistrerCouverture(
      titre('One Punch Man'),
      image(1),
      '.JPG',
    );
    expect(chemin, p.join(racine, 'manga', 'One Punch Man', 'couverture.jpg'));
    expect(await File(chemin).readAsBytes(), image(1));
    expect(await File('$chemin.part').exists(), isFalse);
    expect(await stockage.cheminCouverture(titre('One Punch Man')), chemin);
    expect(await stockage.chargerCouverture(titre('One Punch Man')), image(1));
  });

  test('le suffixe de source est respecté', () async {
    final chemin = await stockage.enregistrerCouverture(
      titre('Titre'),
      image(1),
      'png',
      nomSource: 'Site B',
    );
    expect(chemin, p.join(racine, 'manga', 'Titre (Site B)', 'couverture.png'));
    expect(await stockage.chargerCouverture(titre('Titre')), isNull);
    expect(
      await stockage.chargerCouverture(titre('Titre'), nomSource: 'Site B'),
      image(1),
    );
  });

  test('sans couverture : null', () async {
    expect(await stockage.chargerCouverture(titre('Absent')), isNull);
    expect(await stockage.cheminCouverture(titre('Absent')), isNull);
    expect(await stockage.supprimerCouverture(titre('Absent')), isFalse);
  });

  test('une nouvelle couverture remplace l\'ancienne, même d\'une autre '
      'extension', () async {
    final t = titre('Remplacée');
    final premier = await stockage.enregistrerCouverture(t, image(1), 'jpg');
    await stockage.enregistrerCouverture(t, image(2), 'jpg');
    expect(await stockage.chargerCouverture(t), image(2));

    final second = await stockage.enregistrerCouverture(t, image(3), 'webp');
    expect(await File(premier).exists(), isFalse);
    expect(await stockage.cheminCouverture(t), second);
    expect(await stockage.chargerCouverture(t), image(3));
  });

  test(
    'refuse une image vide, trop grosse ou une extension invalide',
    () async {
      final t = titre('Refus');
      await expectLater(
        stockage.enregistrerCouverture(t, <int>[], 'jpg'),
        throwsA(isA<ErreurStockage>()),
      );
      await expectLater(
        stockage.enregistrerCouverture(
          t,
          Uint8List(tailleMaxCouverture + 1),
          'jpg',
        ),
        throwsA(isA<ErreurStockage>()),
      );
      await expectLater(
        stockage.enregistrerCouverture(t, image(1), '../x'),
        throwsA(isA<ArgumentError>()),
      );
      expect(await stockage.cheminCouverture(t), isNull);
    },
  );

  test(
    'supprimerCouverture garde les archives et retire le dossier vide',
    () async {
      final t = titre('Avec chapitre');
      final ecriture = await stockage.ouvrirEcriture(
        t,
        const Chapitre(
          urlChapitre: 'https://exemple.org/ch/1',
          nom: 'Chapitre 1',
          numero: 1,
          langue: 'fr',
        ),
      );
      await ecriture.ajouterPage(image(9), extension: 'jpg');
      await ecriture.finaliser();
      await stockage.enregistrerCouverture(t, image(1), 'jpg');

      // La couverture ne gêne pas la suppression de l'archive, et le dossier
      // reste tant qu'elle existe.
      expect(await stockage.supprimerArchive(ecriture.nomArchive), isTrue);
      final dossierTitre = Directory(stockage.cheminDossierTitre(t));
      expect(await dossierTitre.exists(), isTrue);

      expect(await stockage.supprimerCouverture(t), isTrue);
      expect(await stockage.cheminCouverture(t), isNull);
      expect(await dossierTitre.exists(), isFalse);
    },
  );

  test('supprimerCouverture ne touche pas aux archives restantes', () async {
    final t = titre('Archives');
    final ecriture = await stockage.ouvrirEcriture(
      t,
      const Chapitre(
        urlChapitre: 'https://exemple.org/ch/2',
        nom: 'Chapitre 2',
        numero: 2,
        langue: 'fr',
      ),
    );
    await ecriture.ajouterPage(image(9), extension: 'jpg');
    await ecriture.finaliser();
    await stockage.enregistrerCouverture(t, image(1), 'png');

    expect(await stockage.supprimerCouverture(t), isTrue);
    expect(await stockage.existeArchive(ecriture.nomArchive), isTrue);
  });

  test('nettoyerFichiersPartiels retire une couverture interrompue', () async {
    final t = titre('Interrompue');
    await stockage.enregistrerCouverture(t, image(1), 'jpg');
    final orphelin = File(
      p.join(stockage.cheminDossierTitre(t), 'couverture.png.part'),
    );
    await orphelin.writeAsBytes(image(2));

    // Un .part n'est jamais pris pour une couverture.
    expect(await stockage.chargerCouverture(t), image(1));
    expect(await stockage.nettoyerFichiersPartiels(), 1);
    expect(await orphelin.exists(), isFalse);
    expect(await stockage.chargerCouverture(t), image(1));
  });

  test('nomFichierCouvertureAvec normalise l\'extension', () {
    expect(
      StockageTelechargements.nomFichierCouvertureAvec('.WebP'),
      'couverture.webp',
    );
    expect(
      () => StockageTelechargements.nomFichierCouvertureAvec(''),
      throwsArgumentError,
    );
  });
}
