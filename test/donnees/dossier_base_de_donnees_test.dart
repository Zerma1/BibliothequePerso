/// Dossier de la base : résolution Windows, lecture de `installation.json`,
/// déplacement depuis l'ancien dossier. Uniquement des dossiers temporaires,
/// jamais le vrai `%APPDATA%`.
library;

import 'dart:io';

import 'package:bibliotheque_perso/donnees/constantes_donnees.dart';
import 'package:bibliotheque_perso/donnees/dossier_base_de_donnees.dart';
import 'package:bibliotheque_perso/donnees/fichier_emplacements.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaire;
  late JournalMemoire journal;

  setUp(() async {
    temporaire = await Directory.systemTemp.createTemp('dossier_base_test');
    journal = JournalMemoire();
    Journal.actuel = journal;
  });

  tearDown(() async {
    Journal.actuel = const JournalSilencieux();
    if (await temporaire.exists()) await temporaire.delete(recursive: true);
  });

  /// Écrit [contenu] dans [chemin] (dossiers créés au besoin).
  Future<File> ecrire(String chemin, String contenu) async {
    final fichier = File(chemin);
    await fichier.parent.create(recursive: true);
    return fichier.writeAsString(contenu);
  }

  group('verifierDossierBaseWindows', () {
    test('accepte un chemin avec lecteur ou un partage réseau', () {
      expect(verifierDossierBaseWindows(r'D:\Base'), isTrue);
      expect(verifierDossierBaseWindows(r'\\nas\partage\Base'), isTrue);
      expect(verifierDossierBaseWindows('  D:/Base  '), isTrue);
    });

    test('refuse une racine de lecteur ou de partage', () {
      expect(verifierDossierBaseWindows(r'C:\'), isFalse);
      expect(verifierDossierBaseWindows('D:/'), isFalse);
      expect(verifierDossierBaseWindows(r'\\nas\partage'), isFalse);
      expect(verifierDossierBaseWindows(r'\\nas\partage\'), isFalse);
    });

    test("refuse un dossier imbriqué avec le défaut ou avec l'ancien "
        'dossier, accepte le défaut lui-même', () {
      const appData = r'C:\Users\client\AppData\Roaming';
      bool verifier(String chemin) =>
          verifierDossierBaseWindows(chemin, dossierAppData: appData);

      expect(
        verifier(r'C:\Users\client\AppData\Roaming\bibliotheque_perso'),
        isTrue,
      );
      expect(
        verifier(r'c:\users\client\appdata\roaming\BIBLIOTHEQUE_PERSO\x'),
        isFalse,
      );
      expect(verifier(appData), isFalse);
      expect(verifier(r'C:\Users\client'), isFalse);
      expect(
        verifier(r'C:\Users\client\AppData\Roaming\io.github.zerma1'),
        isFalse,
      );
      expect(
        verifier(
          r'C:\Users\client\AppData\Roaming\io.github.zerma1\bibliotheque_perso',
        ),
        isFalse,
      );
      expect(verifier(r'C:\Users\client\AppData\Roaming\autre'), isTrue);
      expect(verifier(r'D:\Base'), isTrue);
    });

    test('refuse un chemin vide ou relatif', () {
      expect(verifierDossierBaseWindows(''), isFalse);
      expect(verifierDossierBaseWindows('   '), isFalse);
      expect(verifierDossierBaseWindows('Base'), isFalse);
      expect(verifierDossierBaseWindows(r'..\Base'), isFalse);
      expect(verifierDossierBaseWindows(r'\Base'), isFalse);
      expect(verifierDossierBaseWindows('D:Base'), isFalse);
    });
  });

  group('resoudreDossierBaseWindows', () {
    const appData = r'C:\Users\client\AppData\Roaming';

    test(r'par défaut : %APPDATA%\bibliotheque_perso', () {
      expect(
        resoudreDossierBaseWindows(
          dossierBaseInstallation: null,
          dossierAppData: appData,
        ),
        r'C:\Users\client\AppData\Roaming\bibliotheque_perso',
      );
    });

    test("dossier choisi à l'installation, normalisé", () {
      expect(
        resoudreDossierBaseWindows(
          dossierBaseInstallation: r' D:/Donnees\Base\ ',
          dossierAppData: appData,
        ),
        r'D:\Donnees\Base',
      );
    });

    test('dossier invalide : défaut et avertissement', () {
      expect(
        resoudreDossierBaseWindows(
          dossierBaseInstallation: 'Base',
          dossierAppData: appData,
        ),
        r'C:\Users\client\AppData\Roaming\bibliotheque_perso',
      );
      expect(journal.entrees.single.niveau, NiveauJournal.avertissement);
    });

    test('ancien dossier', () {
      expect(
        cheminAncienDossierBaseWindows(appData),
        r'C:\Users\client\AppData\Roaming\io.github.zerma1\bibliotheque_perso',
      );
    });
  });

  group('chargerDossierBaseInstallation', () {
    late String exe;
    setUp(() => exe = p.join(temporaire.path, 'bibliotheque_perso.exe'));

    Future<void> ecrireInstallation(String contenu) =>
        ecrire(p.join(temporaire.path, nomFichierInstallationWindows), contenu);

    test('fichier absent : null', () async {
      expect(
        await chargerDossierBaseInstallation(cheminExecutable: exe),
        isNull,
      );
    });

    test('lit dossierBase à côté de dossierBibliotheque, BOM toléré', () async {
      await ecrireInstallation(
        '\uFEFF{"dossierBibliotheque": "D:\\\\Mangas", '
        '"dossierBase": "  D:\\\\Base  "}',
      );
      expect(
        await chargerDossierBaseInstallation(cheminExecutable: exe),
        r'D:\Base',
      );
    });

    test('clé absente, vide ou non textuelle : null', () async {
      await ecrireInstallation('{"dossierBibliotheque": "D:\\\\Mangas"}');
      expect(
        await chargerDossierBaseInstallation(cheminExecutable: exe),
        isNull,
      );
      await ecrireInstallation('{"dossierBase": "  "}');
      expect(
        await chargerDossierBaseInstallation(cheminExecutable: exe),
        isNull,
      );
      await ecrireInstallation('{"dossierBase": 3}');
      expect(
        await chargerDossierBaseInstallation(cheminExecutable: exe),
        isNull,
      );
    });

    test('JSON illisible : null et avertissement, sans erreur', () async {
      await ecrireInstallation('{pas du json');
      expect(
        await chargerDossierBaseInstallation(cheminExecutable: exe),
        isNull,
      );
      expect(journal.entrees.single.niveau, NiveauJournal.avertissement);
    });
  });

  group('migrerAncienDossierBase', () {
    late String parent;
    late String ancien;
    late String cible;

    setUp(() {
      parent = p.join(temporaire.path, 'io.github.zerma1');
      ancien = p.join(parent, 'bibliotheque_perso');
      cible = p.join(temporaire.path, 'bibliotheque_perso');
    });

    Future<ResultatMigrationDossierBase> migrer() => migrerAncienDossierBase(
      ancienDossier: ancien,
      dossierCible: cible,
      dossierParentAncien: parent,
    );

    Future<void> remplirAncien() async {
      await ecrire(p.join(ancien, nomFichierBaseDeDonnees), 'BASE' * 1000);
      await ecrire(p.join(ancien, '$nomFichierBaseDeDonnees-wal'), 'WAL');
      await ecrire(
        p.join(ancien, nomFichierEmplacements),
        contenuFichierEmplacements(r'D:\Mangas'),
      );
      await ecrire(p.join(ancien, 'sous', 'autre.txt'), 'autre');
    }

    test(
      'déplace tout le contenu, puis supprime les anciens dossiers vides',
      () async {
        await remplirAncien();
        final baseAvant = await File(p.join(ancien, nomFichierBaseDeDonnees))
            .readAsBytes();

        final resultat = await migrer();

        expect(
          resultat,
          ResultatMigrationDossierBase(
            dossierUtilise: cible,
            issue: IssueMigrationDossierBase.deplacee,
            nombreFichiersDeplaces: 4,
          ),
        );
        expect(
          await File(p.join(cible, nomFichierBaseDeDonnees)).readAsBytes(),
          baseAvant,
        );
        expect(
          await File(p.join(cible, '$nomFichierBaseDeDonnees-wal'))
              .readAsString(),
          'WAL',
        );
        expect(
          await File(p.join(cible, nomFichierEmplacements)).exists(),
          isTrue,
        );
        expect(
          await File(p.join(cible, 'sous', 'autre.txt')).readAsString(),
          'autre',
        );
        // Aucune copie temporaire restée.
        final restes = await Directory(cible)
            .list(recursive: true)
            .where((e) => e.path.endsWith(suffixeCopieMigrationBase))
            .toList();
        expect(restes, isEmpty);
        expect(await Directory(ancien).exists(), isFalse);
        expect(await Directory(parent).exists(), isFalse);
        expect(journal.entrees.last.niveau, NiveauJournal.info);
      },
    );

    test('le dossier parent non vide est gardé', () async {
      await remplirAncien();
      await ecrire(p.join(parent, 'autre_appli', 'x.txt'), 'x');

      final resultat = await migrer();

      expect(resultat.issue, IssueMigrationDossierBase.deplacee);
      expect(await Directory(ancien).exists(), isFalse);
      expect(
        await File(p.join(parent, 'autre_appli', 'x.txt')).exists(),
        isTrue,
      );
    });

    test('ancien dossier sans base : rien à faire', () async {
      await ecrire(p.join(ancien, nomFichierEmplacements), '{}');

      final resultat = await migrer();

      expect(resultat.issue, IssueMigrationDossierBase.aucuneAncienneBase);
      expect(resultat.dossierUtilise, cible);
      expect(
        await File(p.join(ancien, nomFichierEmplacements)).exists(),
        isTrue,
      );
    });

    test('ancien dossier absent : rien à faire', () async {
      final resultat = await migrer();
      expect(resultat.issue, IssueMigrationDossierBase.aucuneAncienneBase);
      expect(resultat.dossierUtilise, cible);
    });

    test('base déjà dans la cible seulement : rien à faire', () async {
      await ecrire(p.join(cible, nomFichierBaseDeDonnees), 'NOUVELLE');
      final resultat = await migrer();
      expect(resultat.issue, IssueMigrationDossierBase.baseDejaEnPlace);
      expect(resultat.dossierUtilise, cible);
    });

    test(
      'deux bases : la cible est gardée, rien supprimé, avertissement',
      () async {
        await remplirAncien();
        await ecrire(p.join(cible, nomFichierBaseDeDonnees), 'NOUVELLE');

        final resultat = await migrer();

        expect(resultat.issue, IssueMigrationDossierBase.conflitDeuxBases);
        expect(resultat.dossierUtilise, cible);
        expect(
          await File(p.join(cible, nomFichierBaseDeDonnees)).readAsString(),
          'NOUVELLE',
        );
        expect(
          await File(p.join(ancien, nomFichierBaseDeDonnees)).readAsString(),
          'BASE' * 1000,
        );
        expect(
          await File(p.join(ancien, 'sous', 'autre.txt')).exists(),
          isTrue,
        );
        expect(journal.entrees.single.niveau, NiveauJournal.avertissement);
      },
    );

    test('même dossier : rien à faire', () async {
      await remplirAncien();
      final resultat = await migrerAncienDossierBase(
        ancienDossier: ancien,
        dossierCible: p.join(ancien, '.'),
      );
      expect(resultat.issue, IssueMigrationDossierBase.memeDossier);
      expect(
        await File(p.join(ancien, nomFichierBaseDeDonnees)).exists(),
        isTrue,
      );
    });

    test('dossiers imbriqués : rien déplacé, ancien dossier utilisé', () async {
      await remplirAncien();
      final resultat = await migrerAncienDossierBase(
        ancienDossier: ancien,
        dossierCible: p.join(ancien, 'nouveau'),
      );
      expect(resultat.issue, IssueMigrationDossierBase.dossiersImbriques);
      expect(resultat.dossierUtilise, ancien);
      expect(
        await File(p.join(ancien, nomFichierBaseDeDonnees)).exists(),
        isTrue,
      );
    });

    test('annexes SQLite périmées de la cible supprimées', () async {
      await ecrire(p.join(ancien, nomFichierBaseDeDonnees), 'BASE');
      await ecrire(p.join(cible, '$nomFichierBaseDeDonnees-wal'), 'PERIME');
      await ecrire(p.join(cible, '$nomFichierBaseDeDonnees-shm'), 'PERIME');

      final resultat = await migrer();

      expect(resultat.issue, IssueMigrationDossierBase.deplacee);
      expect(
        await File(p.join(cible, '$nomFichierBaseDeDonnees-wal')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(cible, '$nomFichierBaseDeDonnees-shm')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(cible, nomFichierBaseDeDonnees)).readAsString(),
        'BASE',
      );
    });

    test(
      "échec de copie : copies effacées, ancien dossier intact et utilisé",
      () async {
        await remplirAncien();
        // La cible est un fichier : impossible d'y créer le dossier.
        await ecrire(cible, 'je suis un fichier');

        final resultat = await migrer();

        expect(resultat.issue, IssueMigrationDossierBase.echec);
        expect(resultat.dossierUtilise, ancien);
        expect(
          await File(p.join(ancien, nomFichierBaseDeDonnees)).readAsString(),
          'BASE' * 1000,
        );
        expect(
          await File(p.join(ancien, 'sous', 'autre.txt')).exists(),
          isTrue,
        );
        expect(journal.entrees.last.niveau, NiveauJournal.erreur);
      },
    );

    test(
      'échec en cours de copie : la base n\'arrive jamais dans la cible',
      () async {
        await remplirAncien();
        // Un dossier porte le nom d'un fichier à copier : le renommage de la
        // copie échoue, après que d'autres fichiers ont pu être copiés.
        await Directory(p.join(cible, nomFichierEmplacements))
            .create(recursive: true);
        await File(p.join(cible, nomFichierEmplacements, 'x'))
            .writeAsString('x');

        final resultat = await migrer();

        expect(resultat.issue, IssueMigrationDossierBase.echec);
        expect(resultat.dossierUtilise, ancien);
        expect(
          await File(p.join(cible, nomFichierBaseDeDonnees)).exists(),
          isFalse,
        );
        final restes = await Directory(cible)
            .list(recursive: true)
            .where((e) => e is File && !e.path.endsWith('x'))
            .toList();
        expect(restes, isEmpty);
        expect(
          await File(p.join(ancien, nomFichierBaseDeDonnees)).exists(),
          isTrue,
        );
      },
    );

    test(
      'base ouverte par un autre processus (Windows) : rien déplacé',
      () async {
        await remplirAncien();
        final base = File(p.join(ancien, nomFichierBaseDeDonnees));
        // Sous Windows, un fichier ouvert ne peut pas être renommé, comme une
        // base ouverte par SQLite.
        final ouvert = await base.open(mode: FileMode.append);
        try {
          final resultat = await migrer();
          expect(resultat.issue, IssueMigrationDossierBase.baseOccupee);
          expect(resultat.dossierUtilise, ancien);
          expect(await base.exists(), isTrue);
          expect(
            await File(p.join(cible, nomFichierBaseDeDonnees)).exists(),
            isFalse,
          );
        } finally {
          await ouvert.close();
        }
      },
      skip: Platform.isWindows
          ? false
          : 'renommage bloqué seulement sous Windows',
    );
  });

  group('dossiersCandidatsMigrationWindows', () {
    const appData = r'C:\Users\client\AppData\Roaming';

    test("cible par défaut : seulement l'ancien dossier", () {
      expect(
        dossiersCandidatsMigrationWindows(
          dossierCible: r'c:\users\CLIENT\AppData\Roaming\bibliotheque_perso',
          dossierAppData: appData,
        ),
        <DossierCandidatBase>[
          (
            dossier:
                r'C:\Users\client\AppData\Roaming\io.github.zerma1'
                r'\bibliotheque_perso',
            parent: r'C:\Users\client\AppData\Roaming\io.github.zerma1',
          ),
        ],
      );
    });

    test(r"cible choisie à l'installation : %APPDATA%\bibliotheque_perso "
        "d'abord, puis l'ancien dossier", () {
      final candidats = dossiersCandidatsMigrationWindows(
        dossierCible: r'D:\Base',
        dossierAppData: appData,
      );
      expect(candidats.map((c) => c.dossier), <String>[
        r'C:\Users\client\AppData\Roaming\bibliotheque_perso',
        r'C:\Users\client\AppData\Roaming\io.github.zerma1\bibliotheque_perso',
      ]);
      expect(candidats.first.parent, isNull);
    });
  });

  group('migrerDossiersCandidatsBase', () {
    late String defaut;
    late String parentAncien;
    late String ancien;
    late String cible;

    setUp(() {
      defaut = p.join(temporaire.path, 'bibliotheque_perso');
      parentAncien = p.join(temporaire.path, 'io.github.zerma1');
      ancien = p.join(parentAncien, 'bibliotheque_perso');
      cible = p.join(temporaire.path, 'choisi', 'Base');
    });

    Future<ResultatMigrationDossierBase> migrer() =>
        migrerDossiersCandidatsBase(
          dossierCible: cible,
          candidats: <DossierCandidatBase>[
            (dossier: defaut, parent: null),
            (dossier: ancien, parent: parentAncien),
          ],
        );

    test('déplace la base du dossier par défaut en priorité, laisse '
        "l'ancienne (conflit au démarrage suivant)", () async {
      await ecrire(p.join(defaut, nomFichierBaseDeDonnees), 'DEFAUT');
      await ecrire(p.join(ancien, nomFichierBaseDeDonnees), 'ANCIENNE');

      final resultat = await migrer();

      expect(resultat.issue, IssueMigrationDossierBase.deplacee);
      expect(resultat.dossierUtilise, cible);
      expect(
        await File(p.join(cible, nomFichierBaseDeDonnees)).readAsString(),
        'DEFAUT',
      );
      expect(await Directory(defaut).exists(), isFalse);
      expect(
        await File(p.join(ancien, nomFichierBaseDeDonnees)).readAsString(),
        'ANCIENNE',
      );

      // Démarrage suivant : rien supprimé, avertissement de conflit.
      final suivant = await migrer();
      expect(suivant.dossierUtilise, cible);
      expect(
        await File(p.join(ancien, nomFichierBaseDeDonnees)).exists(),
        isTrue,
      );
      expect(journal.entrees.last.niveau, NiveauJournal.avertissement);
    });

    test(
      "dossier par défaut sans base : l'ancien dossier est déplacé",
      () async {
        await ecrire(p.join(defaut, 'autre.txt'), 'garde');
        await ecrire(p.join(ancien, nomFichierBaseDeDonnees), 'ANCIENNE');

        final resultat = await migrer();

        expect(resultat.issue, IssueMigrationDossierBase.deplacee);
        expect(
          await File(p.join(cible, nomFichierBaseDeDonnees)).readAsString(),
          'ANCIENNE',
        );
        expect(await Directory(parentAncien).exists(), isFalse);
        // Dossier par défaut non vide et sans base : pas touché.
        expect(await File(p.join(defaut, 'autre.txt')).exists(), isTrue);
      },
    );

    test('dossier par défaut vidé : supprimé une fois vide, sous-dossiers '
        'vides compris', () async {
      await ecrire(p.join(defaut, nomFichierBaseDeDonnees), 'DEFAUT');
      await Directory(p.join(defaut, 'vide')).create(recursive: true);

      final resultat = await migrer();

      expect(resultat.issue, IssueMigrationDossierBase.deplacee);
      expect(await Directory(defaut).exists(), isFalse);
    });

    test('base restée en .verification dans un candidat : restaurée puis '
        'déplacée', () async {
      await ecrire(
        p.join(ancien, '$nomFichierBaseDeDonnees$suffixeVerificationBaseLibre'),
        'ANCIENNE',
      );

      final resultat = await migrer();

      expect(resultat.issue, IssueMigrationDossierBase.deplacee);
      expect(
        await File(p.join(cible, nomFichierBaseDeDonnees)).readAsString(),
        'ANCIENNE',
      );
      expect(
        journal.entrees.any((e) => e.message.contains('remise sous son nom')),
        isTrue,
      );
    });

    test('base restée en .verification dans la cible : restaurée, rien '
        'déplacé', () async {
      await ecrire(
        p.join(cible, '$nomFichierBaseDeDonnees$suffixeVerificationBaseLibre'),
        'CIBLE',
      );

      final resultat = await migrer();

      expect(resultat.issue, IssueMigrationDossierBase.baseDejaEnPlace);
      expect(
        await File(p.join(cible, nomFichierBaseDeDonnees)).readAsString(),
        'CIBLE',
      );
    });

    test(
      'base et .verification présentes : rien touché, avertissement',
      () async {
        await ecrire(p.join(cible, nomFichierBaseDeDonnees), 'BASE');
        final renommee = p.join(
          cible,
          '$nomFichierBaseDeDonnees$suffixeVerificationBaseLibre',
        );
        await ecrire(renommee, 'AUTRE');

        expect(await restaurerBaseEnVerification(cible), isFalse);
        expect(await File(renommee).readAsString(), 'AUTRE');
        expect(
          await File(p.join(cible, nomFichierBaseDeDonnees)).readAsString(),
          'BASE',
        );
        expect(journal.entrees.single.niveau, NiveauJournal.avertissement);
      },
    );

    test("cible choisie à l'installation absente : avertissement « base "
        "attendue absente »", () async {
      await migrerDossiersCandidatsBase(
        dossierCible: cible,
        candidats: const <DossierCandidatBase>[],
        cibleChoisieAInstallation: true,
      );
      expect(
        journal.entrees.single.message,
        startsWith('Base attendue absente'),
      );

      // Cible présente, ou cible par défaut : pas d'avertissement.
      journal.entrees.clear();
      await Directory(cible).create(recursive: true);
      await migrerDossiersCandidatsBase(
        dossierCible: cible,
        candidats: const <DossierCandidatBase>[],
        cibleChoisieAInstallation: true,
      );
      await Directory(cible).delete();
      await migrerDossiersCandidatsBase(
        dossierCible: cible,
        candidats: const <DossierCandidatBase>[],
      );
      expect(journal.entrees, isEmpty);
    });

    test('aucune base nulle part : cible utilisée', () async {
      final resultat = await migrer();
      expect(resultat.issue, IssueMigrationDossierBase.aucuneAncienneBase);
      expect(resultat.dossierUtilise, cible);
    });

    test(
      'base du dossier par défaut occupée : utilisée, ancien non regardé',
      () async {
        await ecrire(p.join(defaut, nomFichierBaseDeDonnees), 'DEFAUT');
        await ecrire(p.join(ancien, nomFichierBaseDeDonnees), 'ANCIENNE');
        final ouvert = await File(p.join(defaut, nomFichierBaseDeDonnees))
            .open(mode: FileMode.append);
        try {
          final resultat = await migrer();
          expect(resultat.issue, IssueMigrationDossierBase.baseOccupee);
          expect(resultat.dossierUtilise, defaut);
          expect(
            await File(p.join(ancien, nomFichierBaseDeDonnees)).exists(),
            isTrue,
          );
        } finally {
          await ouvert.close();
        }
      },
      skip: Platform.isWindows
          ? false
          : 'renommage bloqué seulement sous Windows',
    );
  });

  test('preparerDossierBaseDeDonnees refuse de toucher au vrai dossier '
      'dans les tests', () async {
    expect(Platform.environment['FLUTTER_TEST'], 'true');
    await expectLater(preparerDossierBaseDeDonnees(), throwsStateError);
    // Aucun résultat mémorisé après l'erreur : nouvel essai, même refus.
    await expectLater(preparerDossierBaseDeDonnees(), throwsStateError);
    await expectLater(cheminParDefautFichierEmplacements(), throwsStateError);
  });
}
