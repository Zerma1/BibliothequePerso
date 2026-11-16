import 'dart:io';

import 'package:bibliotheque_perso/donnees/base_de_donnees.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTelechargements depot;
  late DepotChapitres depotChapitres;
  late int idTitre;
  late List<int> idsChapitres;
  late DateTime instant;

  // Horloge factice : avance d'une seconde à chaque lecture, pour que l'ordre
  // de la file soit déterministe.
  DateTime horloge() {
    instant = instant.add(const Duration(seconds: 1));
    return instant;
  }

  setUp(() async {
    instant = DateTime.utc(2026, 11, 15, 12);
    base = await ouvrirBaseDeTest();
    depot = DepotTelechargements(base, horloge: horloge);
    depotChapitres = DepotChapitres(base);
    final idSource = (await DepotSources(
      base,
    ).enregistrerSource(sourceMangaDex)).id!;
    idTitre = (await DepotTitres(
      base,
    ).enregistrerTitre(titreReference(idSource))).id!;
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (var numero = 1; numero <= 4; numero++)
        Chapitre(
          idTitre: idTitre,
          urlChapitre: 'https://mangadex.org/chapter/$numero',
          nom: 'Chapitre $numero',
          numero: numero.toDouble(),
          langue: 'en',
        ),
    ]);
    idsChapitres = (await depotChapitres.chargerChapitres(idTitre))
        .map((c) => c.id!)
        .toList();
  });

  tearDown(() async {
    await base.close();
  });

  test('ajouterEnFile crée un téléchargement en attente daté', () async {
    final telechargement = await depot.ajouterEnFile(idsChapitres[0]);
    expect(telechargement.id, isNotNull);
    expect(telechargement.idChapitre, idsChapitres[0]);
    expect(telechargement.statut, StatutTelechargement.enAttente);
    expect(telechargement.nombrePagesTotal, 0);
    expect(telechargement.nombrePagesFaites, 0);
    expect(telechargement.messageErreur, isNull);
    expect(telechargement.dateAjout, DateTime.utc(2026, 11, 15, 12, 0, 1));
    expect(telechargement.dateMaj, telechargement.dateAjout);
  });

  test(
    'ajouterEnFile ne crée pas de doublon et ne modifie pas l\'existant',
    () async {
      final premier = await depot.ajouterEnFile(idsChapitres[0]);
      await depot.enregistrerStatut(
        premier.id!,
        StatutTelechargement.echec,
        messageErreur: 'Erreur 403',
      );
      final second = await depot.ajouterEnFile(idsChapitres[0]);
      expect(second.id, premier.id);
      expect(second.statut, StatutTelechargement.echec);
      expect(await depot.chargerFile(), hasLength(1));
    },
  );

  test('ajouterEnFile refuse un chapitre inexistant', () async {
    await expectLater(
      depot.ajouterEnFile(9999),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(await depot.chargerFile(), isEmpty);
  });

  test('ajouterPlusieursEnFile compte les nouveaux, tout ou rien', () async {
    await depot.ajouterEnFile(idsChapitres[1]);
    expect(await depot.ajouterPlusieursEnFile(idsChapitres), 3);
    expect(await depot.ajouterPlusieursEnFile(<int>[]), 0);

    await base.delete('telechargements');
    await expectLater(
      depot.ajouterPlusieursEnFile(<int>[idsChapitres[0], 9999]),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(await depot.chargerFile(), isEmpty);
  });

  test('chargerFile suit l\'ordre d\'ajout et filtre par statut', () async {
    await depot.ajouterEnFile(idsChapitres[2]);
    await depot.ajouterEnFile(idsChapitres[0]);
    // Même date d'ajout pour tout le lot : l'ordre d'insertion départage.
    await depot.ajouterPlusieursEnFile(<int>[idsChapitres[3], idsChapitres[1]]);
    expect((await depot.chargerFile()).map((t) => t.idChapitre).toList(), <int>[
      idsChapitres[2],
      idsChapitres[0],
      idsChapitres[3],
      idsChapitres[1],
    ]);

    final premier = await depot.chargerParChapitre(idsChapitres[2]);
    await depot.enregistrerStatut(premier!.id!, StatutTelechargement.enCours);
    final enCours = await depot.chargerFile(
      statuts: <StatutTelechargement>{StatutTelechargement.enCours},
    );
    expect(enCours.single.idChapitre, idsChapitres[2]);
    expect(
      await depot.chargerFile(
        statuts: <StatutTelechargement>{
          StatutTelechargement.enAttente,
          StatutTelechargement.enCours,
        },
      ),
      hasLength(4),
    );
    expect(await depot.chargerFile(statuts: <StatutTelechargement>{}), isEmpty);
  });

  test('chargerProchainEnAttente renvoie le plus ancien en attente', () async {
    expect(await depot.chargerProchainEnAttente(), isNull);
    final premier = await depot.ajouterEnFile(idsChapitres[0]);
    final second = await depot.ajouterEnFile(idsChapitres[1]);
    expect((await depot.chargerProchainEnAttente())!.id, premier.id);

    await depot.enregistrerStatut(premier.id!, StatutTelechargement.enCours);
    expect((await depot.chargerProchainEnAttente())!.id, second.id);

    await depot.enregistrerStatut(second.id!, StatutTelechargement.termine);
    expect(await depot.chargerProchainEnAttente(), isNull);
  });

  test('enregistrerStatut : message d\'échec, relance et date_maj', () async {
    final telechargement = await depot.ajouterEnFile(idsChapitres[0]);
    final id = telechargement.id!;
    await depot.enregistrerProgression(
      id,
      nombrePagesFaites: 5,
      nombrePagesTotal: 20,
    );
    expect(
      await depot.enregistrerStatut(
        id,
        StatutTelechargement.echec,
        messageErreur: 'Erreur 403',
      ),
      isTrue,
    );
    var charge = (await depot.chargerTelechargement(id))!;
    expect(charge.statut, StatutTelechargement.echec);
    expect(charge.messageErreur, 'Erreur 403');
    expect(charge.nombrePagesFaites, 5);
    expect(charge.dateMaj!.isAfter(charge.dateAjout!), isTrue);
    expect(charge.dateAjout, telechargement.dateAjout);

    // Relance : retour en attente, message effacé, progression à 0.
    await depot.enregistrerStatut(id, StatutTelechargement.enAttente);
    charge = (await depot.chargerTelechargement(id))!;
    expect(charge.statut, StatutTelechargement.enAttente);
    expect(charge.messageErreur, isNull);
    expect(charge.nombrePagesFaites, 0);
    expect(charge.nombrePagesTotal, 20);

    expect(
      await depot.enregistrerStatut(9999, StatutTelechargement.echec),
      isFalse,
    );
  });

  test('le statut terminé marque aussi le chapitre téléchargé', () async {
    final telechargement = await depot.ajouterEnFile(idsChapitres[1]);
    await depot.enregistrerStatut(
      telechargement.id!,
      StatutTelechargement.termine,
    );
    expect(
      (await depotChapitres.chargerChapitre(idsChapitres[1]))!.estTelecharge,
      isTrue,
    );
    expect(
      (await depotChapitres.chargerChapitre(idsChapitres[0]))!.estTelecharge,
      isFalse,
    );
  });

  test("le statut terminé enregistre aussi le nomArchive donné", () async {
    final telechargement = await depot.ajouterEnFile(idsChapitres[2]);
    await depot.enregistrerStatut(
      telechargement.id!,
      StatutTelechargement.termine,
      nomArchive: 'manga/Titre/ch3.en.zip',
    );
    final chapitre = (await depotChapitres.chargerChapitre(idsChapitres[2]))!;
    expect(chapitre.estTelecharge, isTrue);
    expect(chapitre.nomArchive, 'manga/Titre/ch3.en.zip');

    // Ignoré pour un autre statut.
    final autre = await depot.ajouterEnFile(idsChapitres[3]);
    await depot.enregistrerStatut(
      autre.id!,
      StatutTelechargement.echec,
      nomArchive: 'manga/Titre/ch4.en.zip',
    );
    expect(
      (await depotChapitres.chargerChapitre(idsChapitres[3]))!.nomArchive,
      isNull,
    );
  });

  test('enregistrerProgression met à jour les compteurs', () async {
    final id = (await depot.ajouterEnFile(idsChapitres[0])).id!;
    expect(
      await depot.enregistrerProgression(
        id,
        nombrePagesFaites: 3,
        nombrePagesTotal: 12,
      ),
      isTrue,
    );
    // Sans total : seul le nombre de pages faites change.
    await depot.enregistrerProgression(id, nombrePagesFaites: 4);
    final charge = (await depot.chargerTelechargement(id))!;
    expect(charge.nombrePagesFaites, 4);
    expect(charge.nombrePagesTotal, 12);
    expect(charge.progression, closeTo(4 / 12, 1e-9));

    expect(
      () => depot.enregistrerProgression(id, nombrePagesFaites: -1),
      throwsArgumentError,
    );
    expect(
      () => depot.enregistrerProgression(
        id,
        nombrePagesFaites: 1,
        nombrePagesTotal: -2,
      ),
      throwsArgumentError,
    );
    expect(
      await depot.enregistrerProgression(9999, nombrePagesFaites: 1),
      isFalse,
    );
  });

  test('reprise après interruption : en_cours redevient en_attente', () async {
    await depot.ajouterPlusieursEnFile(idsChapitres);
    final file = await depot.chargerFile();
    await depot.enregistrerStatut(file[0].id!, StatutTelechargement.enCours);
    await depot.enregistrerProgression(file[0].id!, nombrePagesFaites: 7);
    await depot.enregistrerStatut(file[1].id!, StatutTelechargement.enCours);
    await depot.enregistrerStatut(file[2].id!, StatutTelechargement.termine);

    expect(await depot.reprendreApresInterruption(), 2);

    final apres = await depot.chargerFile();
    expect(apres[0].statut, StatutTelechargement.enAttente);
    expect(apres[0].nombrePagesFaites, 0);
    expect(apres[1].statut, StatutTelechargement.enAttente);
    expect(apres[2].statut, StatutTelechargement.termine);
    expect(apres[3].statut, StatutTelechargement.enAttente);
    // L'ordre de la file est conservé.
    expect((await depot.chargerProchainEnAttente())!.id, file[0].id);
    expect(await depot.reprendreApresInterruption(), 0);
  });

  test(
    "reprise avec ancienneteMinimale : seuls les en_cours trop vieux",
    () async {
      await depot.ajouterPlusieursEnFile(idsChapitres);
      final file = await depot.chargerFile();
      // Horloge : chaque lecture avance d'une seconde.
      await depot.enregistrerStatut(file[0].id!, StatutTelechargement.enCours);
      final vieux = (await depot.chargerTelechargement(file[0].id!))!.dateMaj!;
      instant = instant.add(const Duration(minutes: 10));
      await depot.enregistrerStatut(file[1].id!, StatutTelechargement.enCours);
      await depot.enregistrerProgression(file[1].id!, nombrePagesFaites: 3);

      // Prochaine lecture de l'horloge : vieux + 10 min + 3 s environ.
      expect(
        await depot.reprendreApresInterruption(
          ancienneteMinimale: const Duration(minutes: 5),
        ),
        1,
      );
      final apres = await depot.chargerFile();
      expect(apres[0].statut, StatutTelechargement.enAttente);
      expect(apres[0].dateMaj!.isAfter(vieux), isTrue);
      expect(apres[1].statut, StatutTelechargement.enCours);
      expect(apres[1].nombrePagesFaites, 3);

      // Délai plus long que l'âge du second : il reste en cours.
      expect(
        await depot.reprendreApresInterruption(
          ancienneteMinimale: const Duration(hours: 1),
        ),
        0,
      );
      // Délai nul : tout « en cours » antérieur à maintenant est repris.
      expect(
        await depot.reprendreApresInterruption(
          ancienneteMinimale: Duration.zero,
        ),
        1,
      );
      expect(
        () => depot.reprendreApresInterruption(
          ancienneteMinimale: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    "reserverProchain prend les en_attente dans l'ordre de la file",
    () async {
      expect(await depot.reserverProchain(), isNull);
      await depot.ajouterPlusieursEnFile(<int>[
        idsChapitres[0],
        idsChapitres[1],
      ]);
      final file = await depot.chargerFile();
      await depot.enregistrerStatut(file[0].id!, StatutTelechargement.echec);
      await depot.ajouterEnFile(idsChapitres[2]);

      final premier = await depot.reserverProchain();
      expect(premier!.idChapitre, idsChapitres[1]);
      expect(premier.statut, StatutTelechargement.enCours);
      expect(premier.dateMaj!.isAfter(premier.dateAjout!), isTrue);
      expect(
        (await depot.chargerTelechargement(premier.id!))!.statut,
        StatutTelechargement.enCours,
      );

      final second = await depot.reserverProchain();
      expect(second!.idChapitre, idsChapitres[2]);
      // L'échec n'est jamais réservé, et la file est maintenant vide.
      expect(await depot.reserverProchain(), isNull);
      expect(
        (await depot.chargerTelechargement(file[0].id!))!.statut,
        StatutTelechargement.echec,
      );
    },
  );

  test(
    "deux réservations simultanées sur la même base : une seule réussit",
    () async {
      await depot.ajouterEnFile(idsChapitres[0]);
      final autreDepot = DepotTelechargements(base, horloge: horloge);
      final resultats = await Future.wait(<Future<Telechargement?>>[
        depot.reserverProchain(),
        autreDepot.reserverProchain(),
      ]);
      expect(resultats.whereType<Telechargement>(), hasLength(1));
      expect(resultats.where((r) => r == null), hasLength(1));
      expect(
        (await depot.chargerFile()).single.statut,
        StatutTelechargement.enCours,
      );
    },
  );

  test(
    "réservations concurrentes : chaque téléchargement est pris une fois",
    () async {
      await depot.ajouterPlusieursEnFile(idsChapitres);
      final autreDepot = DepotTelechargements(base, horloge: horloge);
      final pris = <int>[];
      Future<void> travailleur(DepotTelechargements d) async {
        while (true) {
          final t = await d.reserverProchain();
          if (t == null) {
            return;
          }
          pris.add(t.id!);
        }
      }

      await Future.wait(<Future<void>>[
        travailleur(depot),
        travailleur(autreDepot),
      ]);
      expect(pris, hasLength(idsChapitres.length));
      expect(pris.toSet(), hasLength(idsChapitres.length));
    },
  );

  test(
    "deux connexions sur le même fichier (deux isolats) : une seule réussit",
    () async {
      final dossier = await Directory.systemTemp.createTemp('reservation_');
      final chemin = p.join(dossier.path, 'base.db');
      final premiere = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      // Seconde connexion indépendante, comme celle d'un autre isolat.
      final seconde = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        final idSource = (await DepotSources(
          premiere,
        ).enregistrerSource(sourceMangaDex)).id!;
        final id = (await DepotTitres(
          premiere,
        ).enregistrerTitre(titreReference(idSource))).id!;
        await DepotChapitres(premiere).enregistrerChapitres(<Chapitre>[
          Chapitre(
            idTitre: id,
            urlChapitre: 'https://mangadex.org/chapter/1',
            nom: 'Chapitre 1',
            numero: 1,
            langue: 'en',
          ),
        ]);
        final idChapitre = (await DepotChapitres(premiere).chargerChapitres(id))
            .single
            .id!;
        await DepotTelechargements(premiere).ajouterEnFile(idChapitre);

        final resultats = await Future.wait(<Future<Telechargement?>>[
          DepotTelechargements(premiere).reserverProchain(),
          DepotTelechargements(seconde).reserverProchain(),
        ]);
        expect(resultats.whereType<Telechargement>(), hasLength(1));
        expect(
          (await DepotTelechargements(seconde).chargerFile()).single.statut,
          StatutTelechargement.enCours,
        );
      } finally {
        await seconde.close();
        await premiere.close();
        await dossier.delete(recursive: true);
      }
    },
  );

  test('suppression d\'un téléchargement et des terminés', () async {
    await depot.ajouterPlusieursEnFile(idsChapitres);
    final file = await depot.chargerFile();
    await depot.enregistrerStatut(file[0].id!, StatutTelechargement.termine);
    await depot.enregistrerStatut(file[1].id!, StatutTelechargement.termine);

    expect(await depot.supprimerTelechargement(file[3].id!), isTrue);
    expect(await depot.supprimerTelechargement(file[3].id!), isFalse);
    expect(await depot.supprimerTermines(), 2);
    expect((await depot.chargerFile()).map((t) => t.id).toList(), <int?>[
      file[2].id,
    ]);
    // Retirer de la file ne change pas l'état téléchargé du chapitre.
    expect(
      (await depotChapitres.chargerChapitre(file[0].idChapitre))!.estTelecharge,
      isTrue,
    );
  });

  test('supprimer le titre vide la file de ses chapitres (CASCADE)', () async {
    await depot.ajouterPlusieursEnFile(idsChapitres);
    await base.delete('titres', where: 'id = ?', whereArgs: <Object?>[idTitre]);
    expect(await depot.chargerFile(), isEmpty);
  });

  test('la contrainte CHECK refuse un statut inconnu', () async {
    await expectLater(
      base.insert('telechargements', <String, Object?>{
        'id_chapitre': idsChapitres[0],
        'statut': 'enCours',
        'date_ajout': 0,
        'date_maj': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
