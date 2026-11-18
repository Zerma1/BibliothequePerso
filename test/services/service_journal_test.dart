// Tests de ServiceJournal (fichiers, export, réglage « journal détaillé »)
// et de la fin du journal jointe aux rapports d'erreur : dossier temporaire
// et base en mémoire, aucun réseau.
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/journal_fichier.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:bibliotheque_perso/services/constantes_services.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_journal.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_rapports_erreur.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as chemins;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

void main() {
  late Directory temporaire;
  late String dossierJournaux;
  late String dossierRapports;
  late Database base;
  late DepotParametres depot;
  // 18 novembre 2026, 14 h 30 (heure locale) : jour des fichiers « du jour ».
  final maintenant = DateTime(2026, 11, 18, 14, 30, 5);

  ServiceJournal creerService({DepotParametres? depotParametres}) =>
      ServiceJournal(
        dossierJournaux: dossierJournaux,
        dossierRapports: dossierRapports,
        depotParametres: depotParametres,
        horloge: () => maintenant,
      );

  Future<void> ecrireJournal(String nom, String contenu) async {
    await Directory(dossierJournaux).create(recursive: true);
    await File(chemins.join(dossierJournaux, nom)).writeAsString(contenu);
  }

  setUp(() async {
    temporaire = await Directory.systemTemp.createTemp('service_journal_');
    dossierJournaux = chemins.join(temporaire.path, 'journaux');
    dossierRapports = chemins.join(temporaire.path, 'rapports');
    base = await ouvrirBaseDeTest();
    depot = DepotParametres(base);
  });

  tearDown(() async {
    Journal.actuel = const JournalSilencieux();
    await base.close();
    await temporaire.delete(recursive: true);
  });

  group('fichiers du journal', () {
    test('sont listés du plus ancien au plus récent', () async {
      await ecrireJournal('journal-2026-11-18.log', 'b\n');
      await ecrireJournal('journal-2026-11-17.log', 'a\n');
      await ecrireJournal('autre.txt', 'ignoré\n');

      final fichiers = await creerService().listerFichiers();

      expect(fichiers.map((f) => f.nom), <String>[
        'journal-2026-11-17.log',
        'journal-2026-11-18.log',
      ]);
    });

    test("donnent une liste vide si le dossier n'existe pas", () async {
      expect(await creerService().listerFichiers(), isEmpty);
    });
  });

  group('export du journal', () {
    test('copie seulement le fichier du jour par défaut', () async {
      await ecrireJournal('journal-2026-11-17.log', 'hier\n');
      await ecrireJournal('journal-2026-11-18.log', "aujourd'hui\n");

      final chemin = await creerService().exporterJournal();

      expect(chemins.dirname(chemin), dossierRapports);
      expect(chemins.basename(chemin), 'journal_export_20261118_143005.log');
      expect(await File(chemin).readAsString(), "aujourd'hui\n");
    });

    test('met bout à bout les derniers jours dans l\'ordre', () async {
      await ecrireJournal('journal-2026-11-10.log', 'trop ancien\n');
      await ecrireJournal('journal-2026-11-17.log', 'hier\n');
      await ecrireJournal('journal-2026-11-18.log', 'matin\n');
      await ecrireJournal('journal-2026-11-18.2.log', 'soir\n');

      final chemin = await creerService().exporterJournal(jours: 2);

      expect(await File(chemin).readAsString(), 'hier\nmatin\nsoir\n');
    });

    test('ne remplace pas un export de la même seconde', () async {
      await ecrireJournal('journal-2026-11-18.log', 'x\n');
      final service = creerService();

      final premier = await service.exporterJournal();
      final second = await service.exporterJournal();

      expect(second, isNot(premier));
      expect(chemins.basename(second), endsWith('_2.log'));
    });

    test('refuse un journal vide avec un message clair', () async {
      await ecrireJournal('journal-2026-11-10.log', 'trop ancien\n');

      await expectLater(
        creerService().exporterJournal(),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('vide'),
          ),
        ),
      );
      expect(Directory(dossierRapports).existsSync(), isFalse);
    });

    test('garde au plus 20 journaux exportés', () async {
      await ecrireJournal('journal-2026-11-18.log', 'x\n');
      await Directory(dossierRapports).create(recursive: true);
      for (var i = 0; i < nombreMaximalJournauxExportes; i++) {
        final numero = i.toString().padLeft(2, '0');
        await File(
          chemins.join(
            dossierRapports,
            'journal_export_20260101_0000$numero.log',
          ),
        ).writeAsString('ancien');
      }
      await File(chemins.join(dossierRapports, 'rapport_20260101_000000.txt'))
          .writeAsString('rapport');

      await creerService().exporterJournal();

      final noms = Directory(dossierRapports)
          .listSync()
          .map((f) => chemins.basename(f.path))
          .toList();
      expect(
        noms.where((n) => n.startsWith('journal_export_')),
        hasLength(nombreMaximalJournauxExportes),
      );
      expect(noms, isNot(contains('journal_export_20260101_000000.log')));
      expect(noms, contains('rapport_20260101_000000.txt'));
    });
  });

  group('réglage « journal détaillé »', () {
    test('est désactivé tant que rien n\'est choisi', () async {
      expect(
        await creerService(depotParametres: depot).chargerJournalDetaille(),
        isFalse,
      );
      expect(await creerService().chargerJournalDetaille(), isFalse);
    });

    test('est enregistré et appliqué au journal de fichier', () async {
      final journal = JournalFichier(dossierJournaux);
      Journal.actuel = journal;
      final service = creerService(depotParametres: depot);

      await service.enregistrerJournalDetaille(true);

      expect(journal.niveauMinimal, NiveauJournal.debogage);
      expect(
        await depot.chargerEntier(ServiceParametres.cleJournalDetaille),
        1,
      );
      expect(await service.chargerJournalDetaille(), isTrue);

      await service.enregistrerJournalDetaille(false);
      expect(journal.niveauMinimal, NiveauJournal.info);
      await journal.fermer();
    });

    test('est relu et appliqué au démarrage', () async {
      await depot.enregistrerEntier(ServiceParametres.cleJournalDetaille, 1);
      final journal = JournalFichier(dossierJournaux);
      Journal.actuel = journal;

      final actif = await creerService(depotParametres: depot)
          .appliquerReglageJournal();

      expect(actif, isTrue);
      expect(journal.niveauMinimal, NiveauJournal.debogage);
      await journal.fermer();
    });

    test('ignore une valeur illisible', () async {
      await depot.enregistrerEntier(ServiceParametres.cleJournalDetaille, 7);
      expect(
        await creerService(depotParametres: depot).chargerJournalDetaille(),
        isFalse,
      );
    });

    test("ne change rien si le journal n'est pas un fichier", () async {
      final memoire = JournalMemoire(niveauMinimal: NiveauJournal.info);
      Journal.actuel = memoire;

      expect(ServiceJournal.appliquerNiveau(true), isFalse);
      expect(memoire.niveauMinimal, NiveauJournal.info);
    });
  });

  group('rapport d\'erreur', () {
    test('joint les 200 dernières lignes du journal', () async {
      await ecrireJournal(
        'journal-2026-11-18.log',
        '${List<String>.generate(250, (i) => 'ligne $i').join('\n')}\n',
      );
      final service = ServiceRapportsErreur(
        dossierRapports,
        dossierJournaux: dossierJournaux,
        versionApplication: '0.2.2',
        systeme: 'windows',
      );

      final chemin = await service.exporterRapport(
        StateError('panne'),
        action: 'Essai',
      );
      final texte = await File(chemin).readAsString();

      expect(texte, contains(ServiceRapportsErreur.titreSectionJournal));
      expect(texte, contains('ligne 249'));
      expect(texte, contains('ligne 50\n'));
      expect(texte, isNot(contains('ligne 49\n')));
    });

    test(
      'joint aussi l\'erreur elle-même avec un journal de fichier',
      () async {
        final journal = JournalFichier(dossierJournaux);
        Journal.actuel = journal;
        final service = ServiceRapportsErreur(dossierRapports);

        final chemin = await service.exporterRapport(
          StateError('panne'),
          action: "Ajout d'un site",
        );
        final texte = await File(chemin).readAsString();

        expect(texte, contains("Rapport d'erreur demandé (Ajout d'un site)"));
        await journal.fermer();
      },
    );

    test('reste sans section quand aucun journal n\'existe', () async {
      final service = ServiceRapportsErreur(
        dossierRapports,
        dossierJournaux: dossierJournaux,
      );

      final chemin = await service.exporterRapport(StateError('panne'));

      expect(
        await File(chemin).readAsString(),
        isNot(contains(ServiceRapportsErreur.titreSectionJournal)),
      );
    });

    test('masque une donnée sensible restée dans une ligne', () {
      final texte = ServiceRapportsErreur.ajouterLignesJournal('Rapport\n', [
        'GET https://site.test/?token=abc123',
      ]);

      expect(texte, contains('token=***'));
      expect(texte, isNot(contains('abc123')));
    });
  });

  group('journal des services', () {
    test('un réglage modifié est noté', () async {
      final memoire = JournalMemoire();
      Journal.actuel = memoire;

      await ServiceParametres(depot).enregistrerArchiveComplete(true);

      expect(
        memoire.entrees.single,
        const EntreeJournal(
          niveau: NiveauJournal.info,
          categorie: CategorieJournal.parametres,
          message: 'Réglage « Archive complète » activée',
        ),
      );
    });
  });
}
