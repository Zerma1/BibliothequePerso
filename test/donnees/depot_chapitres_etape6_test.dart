// Tests de l'étape 6 sur DepotChapitres : bouton « Garder » en base
// (est_garde), suppressions prévues et dernières parutions par langue.
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotChapitres depot;
  late int idTitre;
  late int idAutreTitre;

  final maintenant = DateTime.utc(2026, 11, 16, 12);

  Chapitre chapitre(
    double numero, {
    String langue = 'en',
    int? titre,
    DateTime? publication,
    DateTime? detection,
  }) => Chapitre(
    idTitre: titre ?? idTitre,
    urlChapitre:
        'https://mangadex.org/chapter/${titre ?? idTitre}-$numero-$langue',
    nom: 'Chapitre $numero',
    numero: numero,
    langue: langue,
    datePublication: publication,
    dateDetection: detection,
  );

  Future<List<int>> enregistrer(List<Chapitre> chapitres) async {
    await depot.enregistrerChapitres(chapitres, dateDetection: maintenant);
    final ids = <int>[];
    for (final c in chapitres) {
      final lignes = await base.query(
        'chapitres',
        columns: <String>['id'],
        where: 'url_chapitre = ?',
        whereArgs: <Object?>[c.urlChapitre],
      );
      ids.add(lignes.single['id']! as int);
    }
    return ids;
  }

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotChapitres(base);
    final idSource = (await DepotSources(
      base,
    ).enregistrerSource(sourceMangaDex)).id!;
    final depotTitres = DepotTitres(base);
    idTitre = (await depotTitres.enregistrerTitre(titreReference(idSource)))
        .id!;
    idAutreTitre = (await depotTitres.enregistrerTitre(
      Titre(
        idSource: idSource,
        urlTitre: 'https://mangadex.org/title/autre',
        nom: 'Autre titre',
        typeTitre: TypeTitre.manhwa,
      ),
    )).id!;
  });

  tearDown(() async {
    await base.close();
  });

  group('est_garde', () {
    test('un nouveau chapitre n\'est pas gardé', () async {
      final ids = await enregistrer(<Chapitre>[chapitre(1)]);
      expect((await depot.chargerChapitre(ids.single))!.estGarde, isFalse);
      expect(await depot.chargerIdsChapitresGardes(), isEmpty);
    });

    test('marquerGarde garde le chapitre et annule sa suppression', () async {
      final ids = await enregistrer(<Chapitre>[chapitre(1), chapitre(2)]);
      await depot.enregistrerArchive(ids[0], 'manga/T/ch1.en.zip');
      await depot.planifierSuppression(ids[0], maintenant);

      expect(await depot.marquerGarde(ids[0]), isTrue);

      final garde = (await depot.chargerChapitre(ids[0]))!;
      expect(garde.estGarde, isTrue);
      expect(garde.dateSuppressionPrevue, isNull);
      expect(garde.estTelecharge, isTrue);
      expect(await depot.chargerIdsChapitresGardes(), <int>{ids[0]});

      expect(await depot.marquerGarde(ids[0], estGarde: false), isTrue);
      expect((await depot.chargerChapitre(ids[0]))!.estGarde, isFalse);
      expect(await depot.chargerIdsChapitresGardes(), isEmpty);
    });

    test('marquerGarde renvoie false pour un chapitre inconnu', () async {
      expect(await depot.marquerGarde(999), isFalse);
    });

    test('marquerGardes reprend des identifiants en ignorant les '
        'disparus', () async {
      final ids = await enregistrer(<Chapitre>[
        chapitre(1),
        chapitre(2),
        chapitre(3),
      ]);
      await depot.planifierSuppression(ids[1], maintenant);

      expect(await depot.marquerGardes(<int>[ids[0], ids[1], ids[1], 999]), 2);

      expect(await depot.chargerIdsChapitresGardes(), <int>{ids[0], ids[1]});
      expect(
        (await depot.chargerChapitre(ids[1]))!.dateSuppressionPrevue,
        isNull,
      );
      expect(await depot.marquerGardes(<int>[]), 0);
    });

    test('marquerGardes découpe les longues listes', () async {
      final ids = await enregistrer(<Chapitre>[
        for (var n = 1; n <= 3; n++) chapitre(n.toDouble()),
      ]);
      // Plus d'identifiants qu'un lot de paramètres : aucune erreur SQLite.
      final beaucoup = <int>[...ids, for (var i = 10000; i < 11200; i++) i];
      expect(await depot.marquerGardes(beaucoup), 3);
    });

    test('supprimer l\'archive retire le choix « Garder »', () async {
      final ids = await enregistrer(<Chapitre>[chapitre(1)]);
      await depot.enregistrerArchive(ids.single, 'manga/T/ch1.en.zip');
      await depot.marquerGarde(ids.single);

      await depot.enregistrerArchive(ids.single, null);

      final relu = (await depot.chargerChapitre(ids.single))!;
      expect(relu.estGarde, isFalse);
      expect(relu.estTelecharge, isFalse);
    });

    test('marquerTelecharge(false) retire aussi le choix « Garder »', () async {
      final ids = await enregistrer(<Chapitre>[chapitre(1)]);
      await depot.enregistrerArchive(ids.single, 'manga/T/ch1.en.zip');
      await depot.marquerGarde(ids.single);

      await depot.marquerTelecharge(ids.single, estTelecharge: false);

      expect((await depot.chargerChapitre(ids.single))!.estGarde, isFalse);
    });

    test(
      'un nouvel enregistrement d\'un chapitre connu garde est_garde',
      () async {
        final ids = await enregistrer(<Chapitre>[chapitre(1)]);
        await depot.marquerGarde(ids.single);
        await depot.enregistrerChapitres(<Chapitre>[chapitre(1)]);
        expect((await depot.chargerChapitre(ids.single))!.estGarde, isTrue);
      },
    );
  });

  group('suppressions prévues', () {
    test('chargerSuppressionsEchues exclut les chapitres gardés', () async {
      final ids = await enregistrer(<Chapitre>[chapitre(1), chapitre(2)]);
      final passe = maintenant.subtract(const Duration(hours: 1));
      await depot.planifierSuppression(ids[0], passe);
      await depot.planifierSuppression(ids[1], passe);
      // Écriture directe : une date restée en base malgré « Garder ».
      await base.update(
        'chapitres',
        <String, Object?>{'est_garde': 1},
        where: 'id = ?',
        whereArgs: <Object?>[ids[1]],
      );

      final echues = await depot.chargerSuppressionsEchues(maintenant);
      expect(echues.map((c) => c.id), <int>[ids[0]]);
    });

    test('chargerSuppressionsPrevues renvoie toutes les dates, la plus '
        'proche d\'abord, filtrables par titre', () async {
      final ids = await enregistrer(<Chapitre>[
        chapitre(1),
        chapitre(2),
        chapitre(3),
        chapitre(1, titre: idAutreTitre),
      ]);
      await depot.planifierSuppression(
        ids[0],
        maintenant.add(const Duration(hours: 20)),
      );
      await depot.planifierSuppression(
        ids[1],
        maintenant.subtract(const Duration(hours: 1)),
      );
      await depot.planifierSuppression(
        ids[3],
        maintenant.add(const Duration(hours: 2)),
      );

      expect((await depot.chargerSuppressionsPrevues()).map((c) => c.id), <int>[
        ids[1],
        ids[3],
        ids[0],
      ]);
      expect(
        (await depot.chargerSuppressionsPrevues(idTitre: idTitre))
            .map((c) => c.id),
        <int>[ids[1], ids[0]],
      );
    });

    test('repousserSuppressionPrevue ne fait que retarder une date '
        'existante', () async {
      final ids = await enregistrer(<Chapitre>[chapitre(1), chapitre(2)]);
      final prevue = maintenant.add(const Duration(hours: 1));
      await depot.planifierSuppression(ids[0], prevue);
      final plusTard = maintenant.add(const Duration(hours: 24));

      expect(await depot.repousserSuppressionPrevue(ids[0], plusTard), isTrue);
      expect(
        (await depot.chargerChapitre(ids[0]))!.dateSuppressionPrevue,
        plusTard,
      );

      // Une date plus proche n'avance jamais la suppression.
      expect(await depot.repousserSuppressionPrevue(ids[0], prevue), isFalse);
      expect(
        (await depot.chargerChapitre(ids[0]))!.dateSuppressionPrevue,
        plusTard,
      );

      // Sans suppression prévue, rien n'est créé.
      expect(await depot.repousserSuppressionPrevue(ids[1], plusTard), isFalse);
      expect(
        (await depot.chargerChapitre(ids[1]))!.dateSuppressionPrevue,
        isNull,
      );
      expect(await depot.repousserSuppressionPrevue(999, plusTard), isFalse);
    });
  });

  group('dernières parutions', () {
    test('par titre, dans les langues données, publication sinon '
        'détection', () async {
      await enregistrer(<Chapitre>[
        chapitre(1, langue: 'fr', publication: DateTime.utc(2026, 1, 1)),
        chapitre(2, langue: 'fr', publication: DateTime.utc(2026, 3, 1)),
        // Plus récent mais dans une langue non demandée.
        chapitre(3, langue: 'es', publication: DateTime.utc(2026, 6, 1)),
        // Autre titre : pas de date de publication → date de détection.
        chapitre(
          1,
          langue: 'EN',
          titre: idAutreTitre,
          detection: DateTime.utc(2026, 5, 5),
        ),
      ]);

      final parutions = await depot.chargerDernieresParutions(<String>[
        'fr',
        ' en ',
      ]);

      expect(parutions, <int, DateTime>{
        idTitre: DateTime.utc(2026, 3, 1),
        idAutreTitre: DateTime.utc(2026, 5, 5),
      });
      expect(parutions[idTitre]!.isUtc, isTrue);
    });

    test('titre sans chapitre dans ces langues : absent', () async {
      await enregistrer(<Chapitre>[
        chapitre(1, langue: 'es', publication: DateTime.utc(2026, 1, 1)),
      ]);
      expect(await depot.chargerDernieresParutions(<String>['fr']), isEmpty);
      expect(await depot.chargerDernieresParutions(<String>[]), isEmpty);
      expect(await depot.chargerDernieresParutions(<String>['  ']), isEmpty);
    });

    test('chargerDernierChapitreParu renvoie le plus récent, puis le plus '
        'grand numéro', () async {
      final ids = await enregistrer(<Chapitre>[
        chapitre(1, langue: 'fr', publication: DateTime.utc(2026, 1, 1)),
        chapitre(2, langue: 'fr', publication: DateTime.utc(2026, 3, 1)),
        chapitre(2.5, langue: 'fr', publication: DateTime.utc(2026, 3, 1)),
        chapitre(9, langue: 'es', publication: DateTime.utc(2026, 9, 1)),
      ]);

      final dernier = await depot.chargerDernierChapitreParu(idTitre, <String>[
        'FR',
      ]);
      expect(dernier?.id, ids[2]);
      expect(
        await depot.chargerDernierChapitreParu(idTitre, <String>['de']),
        isNull,
      );
      expect(
        await depot.chargerDernierChapitreParu(idTitre, <String>[]),
        isNull,
      );
    });
  });
}
