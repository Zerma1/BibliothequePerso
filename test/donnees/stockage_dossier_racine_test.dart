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
Uint8List image(int graine, {int taille = 3000}) => Uint8List.fromList(
  List<int>.generate(taille, (i) => (i * 7 + graine) % 256),
);

Titre titre(String nom, {TypeTitre type = TypeTitre.manga}) =>
    Titre(urlTitre: 'https://exemple.org/$nom', nom: nom, typeTitre: type);

Chapitre chapitre(double numero, {String langue = 'fr'}) => Chapitre(
  urlChapitre: 'https://exemple.org/ch/$numero/$langue',
  nom: 'Chapitre $numero',
  numero: numero,
  langue: langue,
);

/// Écrit un chapitre de [pages] pages et renvoie son nom d'archive relatif.
Future<String> ecrireChapitre(
  StockageTelechargements stockage,
  Titre leTitre,
  Chapitre leChapitre, {
  int pages = 2,
}) async {
  final ecriture = await stockage.ouvrirEcriture(leTitre, leChapitre);
  for (var i = 0; i < pages; i++) {
    await ecriture.ajouterPage(image(i), extension: 'jpg');
  }
  await ecriture.finaliser();
  return ecriture.nomArchive;
}

Matcher erreurDeNature(NatureErreurStockage nature) =>
    isA<ErreurStockage>().having((e) => e.nature, 'nature', nature);

void main() {
  late Directory temporaire;

  setUp(() async {
    temporaire = await Directory.systemTemp.createTemp('racine_test_');
  });

  tearDown(() async {
    if (await temporaire.exists()) {
      await temporaire.delete(recursive: true);
    }
  });

  group('validerDossier', () {
    test('crée le dossier, écrit le repère et ne laisse aucun essai', () async {
      final candidat = p.join(temporaire.path, 'nas', 'Mangas');
      final valide = await StockageTelechargements.validerDossier(
        '  $candidat  ',
      );
      expect(valide, p.normalize(candidat));
      expect(await Directory(candidat).exists(), isTrue);
      final noms = await Directory(candidat)
          .list()
          .map((e) => p.basename(e.path))
          .toList();
      expect(noms, <String>[nomFichierMarqueurRacine]);
    });

    test('dossier existant : le repère existant est gardé', () async {
      final candidat = p.join(temporaire.path, 'existant');
      await Directory(candidat).create();
      await File(p.join(candidat, nomFichierMarqueurRacine))
          .writeAsString('ancien');
      await StockageTelechargements.validerDossier(candidat);
      expect(
        await File(p.join(candidat, nomFichierMarqueurRacine)).readAsString(),
        'ancien',
      );
    });

    test('chemin vide ou relatif refusé', () async {
      for (final chemin in <String>['', '   ', 'Mangas', p.join('a', 'b')]) {
        await expectLater(
          StockageTelechargements.validerDossier(chemin),
          throwsA(erreurDeNature(NatureErreurStockage.cheminInvalide)),
        );
      }
    });

    test('un fichier est refusé', () async {
      final fichier = File(p.join(temporaire.path, 'fichier.txt'));
      await fichier.writeAsString('x');
      await expectLater(
        StockageTelechargements.validerDossier(fichier.path),
        throwsA(erreurDeNature(NatureErreurStockage.cheminInvalide)),
      );
    });

    test('un dossier sous un fichier ne peut pas être créé', () async {
      final fichier = File(p.join(temporaire.path, 'fichier.txt'));
      await fichier.writeAsString('x');
      await expectLater(
        StockageTelechargements.validerDossier(p.join(fichier.path, 'sous')),
        throwsA(isA<ErreurStockage>()),
      );
    });
  });

  group('natureDepuisErreurFichier', () {
    NatureErreurStockage nature(int code, {required bool windows}) =>
        StockageTelechargements.natureDepuisErreurFichier(
          FileSystemException('échec', 'x', OSError('message', code)),
          surWindows: windows,
        );

    test('codes Windows', () {
      expect(nature(5, windows: true), NatureErreurStockage.accesRefuse);
      expect(
        nature(112, windows: true),
        NatureErreurStockage.espaceInsuffisant,
      );
      expect(
        nature(53, windows: true),
        NatureErreurStockage.reseauIndisponible,
      );
      expect(
        nature(67, windows: true),
        NatureErreurStockage.reseauIndisponible,
      );
      expect(
        nature(3, windows: true),
        NatureErreurStockage.dossierInaccessible,
      );
      expect(nature(9999, windows: true), NatureErreurStockage.autre);
    });

    test('codes Linux et Android', () {
      expect(nature(13, windows: false), NatureErreurStockage.accesRefuse);
      expect(
        nature(28, windows: false),
        NatureErreurStockage.espaceInsuffisant,
      );
      expect(
        nature(112, windows: false),
        NatureErreurStockage.reseauIndisponible,
      );
      expect(
        nature(5, windows: false),
        NatureErreurStockage.dossierInaccessible,
      );
    });

    test('erreurDisque : message clair et nature', () {
      final erreur = StockageTelechargements.erreurDisque(
        'Impossible de copier',
        const FileSystemException('échec', 'x', OSError('m', 28)),
      );
      if (!Platform.isWindows) {
        expect(erreur.nature, NatureErreurStockage.espaceInsuffisant);
        expect(erreur.message, contains('disque est plein'));
      }
      expect(erreur.message, startsWith('Impossible de copier : '));
    });
  });

  group('dossier personnalisé inaccessible', () {
    test('NAS éteint : erreur claire, rien créé, rien perdu', () async {
      final racine = p.join(temporaire.path, 'nas_eteint', 'Mangas');
      final stockage = StockageTelechargements.personnalise(racine);
      expect(await stockage.estDossierRacineAccessible(), isFalse);
      await expectLater(
        stockage.verifierDossierRacine(),
        throwsA(
          isA<ErreurStockage>().having(
            (e) => e.estDossierInaccessible,
            'inaccessible',
            isTrue,
          ),
        ),
      );
      await expectLater(
        stockage.ouvrirEcriture(titre('Berserk'), chapitre(1)),
        throwsA(erreurDeNature(NatureErreurStockage.dossierInaccessible)),
      );
      await expectLater(
        stockage.enregistrerCouverture(titre('Berserk'), image(1), 'jpg'),
        throwsA(erreurDeNature(NatureErreurStockage.dossierInaccessible)),
      );
      // Aucun dossier recréé en silence.
      expect(await Directory(racine).exists(), isFalse);
      expect(
        await Directory(p.join(temporaire.path, 'nas_eteint')).exists(),
        isFalse,
      );
    });

    test('point de montage vide (repère absent) : refus', () async {
      final racine = p.join(temporaire.path, 'montage');
      await Directory(racine).create();
      final stockage = StockageTelechargements.personnalise(racine);
      expect(await stockage.estDossierRacineAccessible(), isFalse);
      await expectLater(
        stockage.ouvrirEcriture(titre('Berserk'), chapitre(1)),
        throwsA(erreurDeNature(NatureErreurStockage.dossierInaccessible)),
      );
      expect(await Directory(racine).list().isEmpty, isTrue);
      expect(await stockage.nettoyerFichiersPartiels(), 0);
    });

    test('lecture, existence et suppression : erreur inaccessible', () async {
      final racine = await StockageTelechargements.validerDossier(
        p.join(temporaire.path, 'nas'),
      );
      final stockage = StockageTelechargements.personnalise(racine);
      final nom = await ecrireChapitre(stockage, titre('Berserk'), chapitre(1));
      expect(await stockage.existeArchive(nom), isTrue);
      expect(await stockage.compterPagesArchive(nom), 2);

      // « Extinction du NAS » : le dossier disparaît.
      final cache = '$racine.cache';
      await Directory(racine).rename(cache);
      await expectLater(
        stockage.existeArchive(nom),
        throwsA(erreurDeNature(NatureErreurStockage.dossierInaccessible)),
      );
      await expectLater(
        stockage.lirePageArchive(nom, 0),
        throwsA(erreurDeNature(NatureErreurStockage.dossierInaccessible)),
      );
      await expectLater(
        stockage.supprimerArchive(nom),
        throwsA(erreurDeNature(NatureErreurStockage.dossierInaccessible)),
      );
      expect(await Directory(racine).exists(), isFalse);

      // Retour du NAS : tout est de nouveau lisible.
      await Directory(cache).rename(racine);
      expect(await stockage.estDossierRacineAccessible(), isTrue);
      expect(await stockage.lirePageArchive(nom, 1), image(1));
    });

    test('dossier accessible : archive absente = false', () async {
      final racine = await StockageTelechargements.validerDossier(
        p.join(temporaire.path, 'nas'),
      );
      final stockage = StockageTelechargements.personnalise(racine);
      expect(await stockage.existeArchive('manga/X/ch1.fr.zip'), isFalse);
    });

    test('dossier par défaut : créé à la première écriture', () async {
      final racine = p.join(temporaire.path, 'defaut');
      final stockage = StockageTelechargements(racine);
      expect(stockage.estPersonnalise, isFalse);
      expect(await stockage.estDossierRacineAccessible(), isFalse);
      await stockage.verifierDossierRacine();
      await ecrireChapitre(stockage, titre('Berserk'), chapitre(1));
      expect(await stockage.estDossierRacineAccessible(), isTrue);
    });

    test('depuisReglage : chemin choisi = stockage personnalisé', () async {
      final stockage = await StockageTelechargements.depuisReglage(
        '  ${temporaire.path}  ',
      );
      expect(stockage.estPersonnalise, isTrue);
      expect(stockage.dossierRacine, temporaire.path);
    });
  });

  group('deplacerArchivesVers', () {
    late String ancienne;
    late StockageTelechargements stockage;

    setUp(() async {
      ancienne = p.join(temporaire.path, 'ancien');
      stockage = StockageTelechargements(ancienne);
    });

    test('déplace archives et couvertures, garde le reste', () async {
      final nom1 = await ecrireChapitre(
        stockage,
        titre('Berserk'),
        chapitre(1),
      );
      final nom2 = await ecrireChapitre(
        stockage,
        titre('Berserk'),
        chapitre(2),
        pages: 3,
      );
      final nom3 = await ecrireChapitre(
        stockage,
        titre('Solo Leveling', type: TypeTitre.manhwa),
        chapitre(10.5),
      );
      await stockage.enregistrerCouverture(titre('Berserk'), image(9), 'png');
      // Fichiers qui ne doivent pas bouger.
      final partiel = File(
        p.join(ancienne, 'manga', 'Berserk', 'ch3.fr.zip.part'),
      );
      await partiel.writeAsBytes(image(3));
      final export = File(p.join(ancienne, 'exports', 'sauvegarde.zip'));
      await export.create(recursive: true);
      await export.writeAsString('export');

      final progression = <(int, int)>[];
      final nouvelle = p.join(temporaire.path, 'nas', 'Mangas');
      final bilan = await stockage.deplacerArchivesVers(
        nouvelle,
        surProgression: (faits, total) => progression.add((faits, total)),
      );

      expect(bilan.nombreFichiers, 4);
      expect(bilan.nombreCopies, 4);
      expect(bilan.nombreDejaPresents, 0);
      expect(bilan.octetsCopies, greaterThan(0));
      expect(progression, <(int, int)>[(0, 4), (1, 4), (2, 4), (3, 4), (4, 4)]);

      final nouveau = StockageTelechargements.personnalise(nouvelle);
      expect(await nouveau.estDossierRacineAccessible(), isTrue);
      expect(await nouveau.compterPagesArchive(nom2), 3);
      expect(await nouveau.lirePageArchive(nom1, 1), image(1));
      expect(await nouveau.existeArchive(nom3), isTrue);
      expect(await nouveau.chargerCouverture(titre('Berserk')), image(9));

      // Ancien dossier : archives retirées, le reste intact.
      expect(await Directory(ancienne).exists(), isTrue);
      expect(await stockage.existeArchive(nom1), isFalse);
      expect(await stockage.existeArchive(nom3), isFalse);
      expect(await partiel.exists(), isTrue);
      expect(await export.readAsString(), 'export');
      expect(
        await Directory(p.join(ancienne, 'manhwa')).exists(),
        isFalse,
        reason: 'dossiers de titre et de type vides retirés',
      );
      // Aucun .part laissé dans le nouveau dossier.
      final restes = await Directory(nouvelle)
          .list(recursive: true)
          .where((e) => e.path.endsWith(suffixeArchivePartielle))
          .toList();
      expect(restes, isEmpty);
    });

    test(
      'reprise : fichier déjà copié non recopié, copie interrompue refaite',
      () async {
        final nom1 = await ecrireChapitre(
          stockage,
          titre('Berserk'),
          chapitre(1),
        );
        final nom2 = await ecrireChapitre(
          stockage,
          titre('Berserk'),
          chapitre(2),
        );
        final nouvelle = p.join(temporaire.path, 'nas');
        // Interruption simulée : ch1 déjà copié (ancien pas encore
        // supprimé), ch2 copié à moitié dans son `.part`.
        final cible1 = File(p.joinAll(<String>[nouvelle, ...nom1.split('/')]));
        final cible2 = File(p.joinAll(<String>[nouvelle, ...nom2.split('/')]));
        await cible1.parent.create(recursive: true);
        await File(stockage.cheminDepuisNomArchive(nom1)).copy(cible1.path);
        final octets2 = await File(stockage.cheminDepuisNomArchive(nom2))
            .readAsBytes();
        final partiel2 = File('${cible2.path}$suffixeArchivePartielle');
        await partiel2.writeAsBytes(octets2.sublist(0, octets2.length ~/ 2));

        final bilan = await stockage.deplacerArchivesVers(nouvelle);
        expect(bilan.nombreFichiers, 2);
        expect(bilan.nombreDejaPresents, 1);
        expect(bilan.nombreCopies, 1);
        expect(bilan.nombreConflits, 0);
        expect(await cible2.readAsBytes(), octets2);
        expect(await partiel2.exists(), isFalse);
        expect(await stockage.existeArchive(nom1), isFalse);
        expect(await stockage.existeArchive(nom2), isFalse);

        // Relance après succès : rien à faire.
        final encore = await stockage.deplacerArchivesVers(nouvelle);
        expect(encore.nombreFichiers, 0);
      },
    );

    group('cible déjà présente', () {
      late String nouvelle;
      late String nom1;
      late String nom2;
      late File ancien1;
      late File ancien2;
      late File cible1;
      late File cible2;

      setUp(() async {
        nom1 = await ecrireChapitre(stockage, titre('Berserk'), chapitre(1));
        nom2 = await ecrireChapitre(stockage, titre('Berserk'), chapitre(2));
        nouvelle = p.join(temporaire.path, 'nas');
        ancien1 = File(stockage.cheminDepuisNomArchive(nom1));
        ancien2 = File(stockage.cheminDepuisNomArchive(nom2));
        cible1 = File(p.joinAll(<String>[nouvelle, ...nom1.split('/')]));
        cible2 = File(p.joinAll(<String>[nouvelle, ...nom2.split('/')]));
        await cible1.parent.create(recursive: true);
      });

      test('identique : non recopiée, ancien supprimé', () async {
        await ancien1.copy(cible1.path);
        final octets1 = await ancien1.readAsBytes();

        final bilan = await stockage.deplacerArchivesVers(nouvelle);

        expect(bilan.nombreDejaPresents, 1);
        expect(bilan.nombreCopies, 1);
        expect(bilan.nombreConflits, 0);
        expect(bilan.cheminsEnConflit, isEmpty);
        expect(await ancien1.exists(), isFalse);
        expect(await cible1.readAsBytes(), octets1);
      });

      test("taille différente : conflit, cible intacte, ancien conservé, "
          'les autres fichiers sont déplacés', () async {
        final autre = image(42, taille: 1234);
        await cible1.writeAsBytes(autre);
        final octets1 = await ancien1.readAsBytes();
        expect(octets1.length, isNot(autre.length));

        final bilan = await stockage.deplacerArchivesVers(nouvelle);

        expect(bilan.nombreFichiers, 2);
        expect(bilan.nombreCopies, 1);
        expect(bilan.nombreDejaPresents, 0);
        expect(bilan.nombreConflits, 1);
        expect(bilan.aDesConflits, isTrue);
        expect(bilan.cheminsEnConflit, <String>[nom1]);
        expect(await cible1.readAsBytes(), autre);
        expect(await ancien1.readAsBytes(), octets1);
        // Le fichier suivant a bien été déplacé.
        expect(await ancien2.exists(), isFalse);
        expect(await cible2.exists(), isTrue);
        // Aucun .part laissé à côté de la cible en conflit.
        expect(
          await File('${cible1.path}$suffixeArchivePartielle').exists(),
          isFalse,
        );
      });

      test('même taille, contenu différent : conflit', () async {
        final octets1 = await ancien1.readAsBytes();
        final modifie = Uint8List.fromList(octets1);
        // Un seul octet différent, en fin de fichier.
        modifie[modifie.length - 1] ^= 0xFF;
        await cible1.writeAsBytes(modifie);

        final bilan = await stockage.deplacerArchivesVers(nouvelle);

        expect(bilan.nombreConflits, 1);
        expect(bilan.nombreDejaPresents, 0);
        expect(bilan.cheminsEnConflit, <String>[nom1]);
        expect(await cible1.readAsBytes(), modifie);
        expect(await ancien1.readAsBytes(), octets1);
      });

      test(
        'grand fichier identique sur plusieurs blocs : déjà présent',
        () async {
          // Plus de 64 Kio : la comparaison passe par plusieurs blocs.
          final gros = image(5, taille: 200 * 1024 + 17);
          await ancien1.writeAsBytes(gros);
          await cible1.writeAsBytes(gros);

          final bilan = await stockage.deplacerArchivesVers(nouvelle);

          expect(bilan.nombreDejaPresents, 1);
          expect(bilan.nombreConflits, 0);
          expect(await ancien1.exists(), isFalse);
        },
      );

      test(
        'relance après conflit : toujours en conflit, rien écrasé',
        () async {
          final autre = image(42, taille: 1234);
          await cible1.writeAsBytes(autre);
          await stockage.deplacerArchivesVers(nouvelle);

          final encore = await stockage.deplacerArchivesVers(nouvelle);

          expect(encore.nombreFichiers, 1);
          expect(encore.cheminsEnConflit, <String>[nom1]);
          expect(await cible1.readAsBytes(), autre);
          expect(await ancien1.exists(), isTrue);
        },
      );
    });

    test('bilan : égalité selon les chemins en conflit', () {
      const a = BilanDeplacement(
        nombreFichiers: 1,
        nombreCopies: 0,
        nombreDejaPresents: 0,
        octetsCopies: 0,
        cheminsEnConflit: <String>['manga/Berserk/ch1.fr.zip'],
      );
      const b = BilanDeplacement(
        nombreFichiers: 1,
        nombreCopies: 0,
        nombreDejaPresents: 0,
        octetsCopies: 0,
        cheminsEnConflit: <String>['manga/Berserk/ch1.fr.zip'],
      );
      const c = BilanDeplacement(
        nombreFichiers: 1,
        nombreCopies: 0,
        nombreDejaPresents: 0,
        octetsCopies: 0,
        cheminsEnConflit: <String>['manga/Berserk/ch2.fr.zip'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.nombreConflits, 1);
    });

    test('ancien dossier jamais créé : rien à déplacer', () async {
      final bilan = await stockage.deplacerArchivesVers(
        p.join(temporaire.path, 'nas'),
      );
      expect(
        bilan,
        const BilanDeplacement(
          nombreFichiers: 0,
          nombreCopies: 0,
          nombreDejaPresents: 0,
          octetsCopies: 0,
        ),
      );
    });

    test('même dossier, sous-dossier ou dossier parent refusés', () async {
      await ecrireChapitre(stockage, titre('Berserk'), chapitre(1));
      for (final cible in <String>[
        ancienne,
        p.join(ancienne, 'nas'),
        temporaire.path,
      ]) {
        await expectLater(
          stockage.deplacerArchivesVers(cible),
          throwsA(erreurDeNature(NatureErreurStockage.cheminInvalide)),
        );
      }
      expect(
        await File(p.join(ancienne, 'manga', 'Berserk', 'ch1.fr.zip')).exists(),
        isTrue,
      );
    });

    test('téléchargement en cours : refus', () async {
      final ecriture = await stockage.ouvrirEcriture(
        titre('Berserk'),
        chapitre(1),
      );
      await expectLater(
        stockage.deplacerArchivesVers(p.join(temporaire.path, 'nas')),
        throwsA(isA<ErreurStockage>()),
      );
      await ecriture.abandonner();
    });

    test('ancien dossier personnalisé inaccessible : refus', () async {
      final perso = StockageTelechargements.personnalise(
        p.join(temporaire.path, 'nas_eteint'),
      );
      await expectLater(
        perso.deplacerArchivesVers(p.join(temporaire.path, 'nas2')),
        throwsA(erreurDeNature(NatureErreurStockage.dossierInaccessible)),
      );
    });
  });
}
