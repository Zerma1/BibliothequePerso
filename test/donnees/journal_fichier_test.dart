import 'dart:io';
import 'dart:isolate';

import 'package:bibliotheque_perso/donnees/journal_fichier.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Ligne d'entrée : `2026-11-18T14:03:12.345 INFO   [app] reseau : …`.
final RegExp ligneEntree = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3} (DEBUG |INFO  |AVERT |ERREUR) '
  r'\[\w+\] \w+ : ',
);

/// Écrit [nombre] entrées depuis un isolat séparé (concurrence réelle).
Future<void> ecrireDepuisIsolat(String dossier, String nom, int nombre) =>
    Isolate.run(() async {
      final journal = JournalFichier(dossier, nomIsolat: nom);
      for (var i = 0; i < nombre; i++) {
        journal.info(CategorieJournal.reseau, '$nom ligne $i');
        if (i % 50 == 0) await Future<void>.delayed(Duration.zero);
      }
      await journal.fermer();
    });

void main() {
  late Directory temporaire;
  late String dossier;

  setUp(() async {
    temporaire = await Directory.systemTemp.createTemp('journal_test_');
    dossier = p.join(temporaire.path, nomDossierJournaux);
  });

  tearDown(() async {
    Journal.actuel = const JournalSilencieux();
    try {
      await temporaire.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> lireJour(String cleJour, {int numero = 1}) =>
      File(p.join(dossier, nomFichierJournal(cleJour, numero))).readAsString();

  test('format des lignes, niveau minimal et isolat', () async {
    final journal = JournalFichier(
      dossier,
      nomIsolat: nomIsolatFond,
      horloge: () => DateTime(2026, 11, 18, 9, 5, 7, 42),
    );
    journal.debogage(CategorieJournal.base, 'ignoré (débogage désactivé)');
    journal.info(CategorieJournal.misesAJour, 'Début\nsuite du message');
    journal.erreur(
      CategorieJournal.telechargement,
      'Chapitre 12 abandonné',
      erreur: const SocketException('injoignable'),
      pile: StackTrace.fromString('#0 a\n#1 b\n'),
    );
    await journal.fermer();

    final contenu = await lireJour('2026-11-18');
    expect(
      contenu,
      '2026-11-18T09:05:07.042 INFO   [fond] misesAJour : Début\n'
      '    suite du message\n'
      '2026-11-18T09:05:07.042 ERREUR [fond] telechargement : '
      'Chapitre 12 abandonné\n'
      '    erreur : SocketException: injoignable\n'
      '    pile :\n'
      '      #0 a\n'
      '      #1 b\n',
    );
  });

  test('débogage activé à la demande ; rien après fermeture', () async {
    final journal = JournalFichier(dossier)
      ..niveauMinimal = NiveauJournal.debogage;
    expect(journal.estActif(NiveauJournal.debogage), isTrue);
    journal.debogage(CategorieJournal.base, 'détail');
    await journal.fermer();
    journal.info(CategorieJournal.base, 'après fermeture');
    await journal.vider();
    final lignes = await journal.chargerDernieresLignes(10);
    expect(lignes, hasLength(1));
    expect(lignes.single, contains('DEBUG  [app] base : détail'));
  });

  test("écriture regroupée : rien sur le disque avant l'intervalle", () async {
    final journal = JournalFichier(
      dossier,
      intervalleVidage: const Duration(milliseconds: 100),
    );
    journal.info(CategorieJournal.interface, 'clic');
    expect(await Directory(dossier).exists(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await listerFichiersJournal(dossier), hasLength(1));
    await journal.fermer();
  });

  test('un fichier par jour et suppression après 14 jours', () async {
    // Vieux fichiers déjà présents.
    await Directory(dossier).create(recursive: true);
    for (final nom in [
      'journal-2026-11-01.log', // 17 jours : supprimé
      'journal-2026-11-04.2.log', // 14 jours : supprimé
      'journal-2026-11-05.log', // 13 jours : gardé (jusqu'au lendemain)
      'autre.txt', // pas un journal : ignoré
    ]) {
      await File(p.join(dossier, nom)).writeAsString('x\n');
    }
    var maintenant = DateTime(2026, 11, 18, 23, 59, 59, 900);
    final journal = JournalFichier(dossier, horloge: () => maintenant);
    await journal.supprimerAnciensJournaux();
    expect((await listerFichiersJournal(dossier)).map((f) => f.nom), [
      'journal-2026-11-05.log',
    ]);
    journal.info(CategorieJournal.demarrage, 'avant minuit');
    maintenant = DateTime(2026, 11, 19, 0, 0, 0, 100);
    journal.info(CategorieJournal.demarrage, 'après minuit');
    await journal.fermer();

    final noms = (await listerFichiersJournal(dossier))
        .map((f) => f.nom)
        .toList();
    // Changement de jour : nouveau nettoyage, le 5 a maintenant 14 jours.
    expect(noms, ['journal-2026-11-18.log', 'journal-2026-11-19.log']);
    expect(await File(p.join(dossier, 'autre.txt')).exists(), isTrue);
    expect(await lireJour('2026-11-18'), contains('avant minuit'));
    expect(await lireJour('2026-11-19'), contains('après minuit'));
  });

  test('au-delà de la taille maximale : fichier .2.log', () async {
    final journal = JournalFichier(
      dossier,
      horloge: () => DateTime(2026, 11, 18, 12),
      tailleMaxFichier: 300,
    );
    for (var i = 0; i < 10; i++) {
      journal.info(CategorieJournal.reseau, 'requête numéro $i ${'x' * 40}');
      await journal.vider();
    }
    await journal.fermer();
    final fichiers = await listerFichiersJournal(dossier);
    expect(fichiers.map((f) => f.numero), containsAllInOrder([1, 2, 3]));
    for (final fichier in fichiers) {
      expect(await File(fichier.chemin).length(), lessThanOrEqualTo(300));
    }
    final lignes = await chargerDernieresLignesJournal(dossier, 100);
    expect(lignes, hasLength(10));
    expect(lignes.first, contains('requête numéro 0'));
    expect(lignes.last, contains('requête numéro 9'));
  });

  test('N dernières lignes, en remontant sur le fichier précédent', () async {
    var jour = 17;
    final journal = JournalFichier(
      dossier,
      horloge: () => DateTime(2026, 11, jour, 10),
    );
    for (var i = 0; i < 5; i++) {
      journal.info(CategorieJournal.base, 'veille $i');
    }
    await journal.vider();
    jour = 18;
    for (var i = 0; i < 3; i++) {
      journal.info(CategorieJournal.base, 'jour $i');
    }
    final lignes = await journal.chargerDernieresLignes(5);
    expect(lignes.map((l) => l.split(' : ').last), [
      'veille 3',
      'veille 4',
      'jour 0',
      'jour 1',
      'jour 2',
    ]);
    expect(await journal.chargerDernieresLignes(0), isEmpty);
    expect(await chargerDernieresLignesJournal('/inexistant/x', 3), isEmpty);
    await journal.fermer();
  });

  test(
    'masque les données sensibles et coupe les messages trop longs',
    () async {
      final journal = JournalFichier(dossier);
      journal.info(
        CategorieJournal.reseau,
        'GET https://site.org/a?token=SECRET1&page=2 '
        '{Authorization: Bearer SECRET2}',
      );
      journal.avertissement(
        CategorieJournal.sources,
        'Page inattendue',
        erreur: FormatException('<html>${'a' * 5000}</html> password=SECRET3'),
      );
      await journal.fermer();
      final contenu = (await journal.chargerDernieresLignes(20)).join('\n');
      expect(contenu, isNot(contains('SECRET')));
      expect(contenu, contains('token=***&page=2'));
      expect(contenu, contains('Authorization: ***'));
      expect(contenu, contains('caractères coupés'));
      expect(contenu.length, lessThan(longueurMaxMessageJournal + 500));
    },
  );

  test("écriture impossible : aucune exception, l'appelant continue", () async {
    // Un fichier à la place du dossier : la création du dossier échoue.
    final bloquant = File(p.join(temporaire.path, 'bloquant'));
    await bloquant.writeAsString('x');
    final journal = JournalFichier(p.join(bloquant.path, 'journaux'));
    journal.erreur(CategorieJournal.stockage, 'perdu', erreur: Exception('x'));
    journal.info(CategorieJournal.stockage, 'perdu aussi');
    await journal.vider();
    expect(await journal.listerFichiers(), isEmpty);
    expect(await journal.chargerDernieresLignes(5), isEmpty);
    await journal.supprimerAnciensJournaux();
    await journal.fermer();
  });

  test('erreur dont toString lève : entrée écrite quand même', () async {
    final journal = JournalFichier(dossier);
    journal.erreur(
      CategorieJournal.base,
      'bizarre',
      erreur: _ErreurIllisible(),
    );
    await journal.fermer();
    final lignes = await journal.chargerDernieresLignes(5);
    expect(lignes.join('\n'), contains('_ErreurIllisible illisible'));
  });

  test('deux isolats écrivent dans le même fichier sans se gêner', () async {
    await Future.wait([
      ecrireDepuisIsolat(dossier, 'app', 400),
      ecrireDepuisIsolat(dossier, 'fond', 400),
    ]);
    final lignes = await chargerDernieresLignesJournal(dossier, 10000);
    expect(lignes, hasLength(800));
    for (final ligne in lignes) {
      expect(ligne, matches(ligneEntree));
    }
    for (final nom in ['app', 'fond']) {
      final numeros = lignes
          .where((l) => l.contains('[$nom]'))
          .map((l) => int.parse(l.split(' ').last))
          .toList();
      expect(numeros, List<int>.generate(400, (i) => i));
    }
  });

  test('ouvrir et installer dans Journal.actuel', () async {
    final journal = await JournalFichier.installer(
      dossierApplication: temporaire.path,
      nomIsolat: nomIsolatFond,
    );
    expect(journal, isNotNull);
    expect(Journal.actuel, same(journal));
    expect(journal!.dossier, cheminDossierJournaux(temporaire.path));
    Journal.actuel.info(CategorieJournal.demarrage, 'Tâche de fond lancée');
    await Journal.actuel.fermer();
    final lignes = await journal.chargerDernieresLignes(1);
    expect(lignes.single, contains('[fond] demarrage : Tâche de fond lancée'));
  });
}

class _ErreurIllisible {
  @override
  String toString() => throw StateError('toString impossible');
}
