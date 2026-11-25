import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotChapitres depot;
  late int idTitre;

  Chapitre chapitre(double numero, {String langue = 'en'}) => Chapitre(
    idTitre: idTitre,
    urlChapitre: 'https://mangadex.org/chapter/$numero-$langue',
    nom: 'Chapitre $numero',
    numero: numero,
    langue: langue,
  );

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotChapitres(base);
    final idSource = (await DepotSources(
      base,
    ).enregistrerSource(sourceMangaDex)).id!;
    idTitre = (await DepotTitres(
      base,
    ).enregistrerTitre(titreReference(idSource))).id!;
  });

  tearDown(() async {
    await base.close();
  });

  test('une liste vide n\'insère rien', () async {
    expect(await depot.enregistrerChapitres(<Chapitre>[]), 0);
    expect(await depot.chargerChapitres(idTitre), isEmpty);
    expect(await depot.compterNonLus(idTitre), 0);
  });

  test('seuls les nouveaux chapitres sont insérés et comptés', () async {
    expect(
      await depot.enregistrerChapitres(<Chapitre>[chapitre(1), chapitre(2)]),
      2,
    );
    // Le chapitre 2 est déjà connu, et le 3 est présent deux fois.
    expect(
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(2),
        chapitre(3),
        chapitre(3),
      ]),
      1,
    );
    expect(await depot.chargerChapitres(idTitre), hasLength(3));
  });

  test('un chapitre déjà connu garde son état de lecture', () async {
    await depot.enregistrerChapitres(<Chapitre>[chapitre(1)]);
    final enregistre = (await depot.chargerChapitres(idTitre)).single;
    await depot.marquerLu(enregistre.id!);

    await depot.enregistrerChapitres(<Chapitre>[chapitre(1)]);

    expect((await depot.chargerChapitre(enregistre.id!))!.estLu, isTrue);
  });

  test(
    'les chapitres sont triés par numéro et gardent numéro et langue',
    () async {
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(10),
        chapitre(2),
        chapitre(10.5, langue: 'fr'),
      ]);
      final chapitres = await depot.chargerChapitres(idTitre);
      expect(chapitres.map((c) => c.numero), <double>[2, 10, 10.5]);
      expect(chapitres.last.langue, 'fr');
    },
  );

  test('la date de détection est remplie à l\'insertion', () async {
    final detection = DateTime.utc(2026, 11, 15, 12);
    await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1),
    ], dateDetection: detection);
    expect(
      (await depot.chargerChapitres(idTitre)).single.dateDetection,
      detection,
    );
  });

  test(
    'marquer lu, non lu et tout lu met à jour le compte des non-lus',
    () async {
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(1),
        chapitre(2),
        chapitre(3),
      ]);
      expect(await depot.compterNonLus(idTitre), 3);

      final premier = (await depot.chargerChapitres(idTitre)).first;
      await depot.marquerLu(premier.id!);
      expect(await depot.compterNonLus(idTitre), 2);

      await depot.marquerLu(premier.id!, estLu: false);
      expect(await depot.compterNonLus(idTitre), 3);

      await depot.marquerTousLus(idTitre);
      expect(await depot.compterNonLus(idTitre), 0);
    },
  );

  test('marquer téléchargé est persisté', () async {
    await depot.enregistrerChapitres(<Chapitre>[chapitre(1)]);
    final enregistre = (await depot.chargerChapitres(idTitre)).single;
    expect(enregistre.estTelecharge, isFalse);

    await depot.marquerTelecharge(enregistre.id!);
    expect(
      (await depot.chargerChapitre(enregistre.id!))!.estTelecharge,
      isTrue,
    );
  });

  test(
    'un chapitre d\'un titre inexistant est refusé et rien n\'est écrit',
    () async {
      await expectLater(
        depot.enregistrerChapitres(<Chapitre>[
          chapitre(1),
          const Chapitre(
            idTitre: 999,
            urlChapitre: 'https://exemple.org/orphelin',
            nom: 'Orphelin',
            numero: 1,
          ),
        ]),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      // La transaction annule aussi le chapitre valide.
      expect(await depot.chargerChapitres(idTitre), isEmpty);
    },
  );

  test('un chapitre sans idTitre est refusé et rien n\'est écrit', () async {
    await expectLater(
      depot.enregistrerChapitres(<Chapitre>[
        chapitre(1),
        const Chapitre(
          urlChapitre: 'https://exemple.org/sans-titre',
          nom: 'Sans titre',
          numero: 2,
        ),
      ]),
      throwsA(
        isA<ErreurBaseDeDonnees>().having(
          (erreur) => erreur.message,
          'message',
          contains('idTitre'),
        ),
      ),
    );
    expect(await depot.chargerChapitres(idTitre), isEmpty);
  });

  test("enregistrerArchive : chemin et est_telecharge cohérents", () async {
    await depot.enregistrerChapitres(<Chapitre>[chapitre(1), chapitre(2)]);
    final ids = (await depot.chargerChapitres(idTitre))
        .map((c) => c.id!)
        .toList();

    expect(
      await depot.enregistrerArchive(ids[0], 'manga/Titre/ch1.en.zip'),
      isTrue,
    );
    var charge = (await depot.chargerChapitre(ids[0]))!;
    expect(charge.nomArchive, 'manga/Titre/ch1.en.zip');
    expect(charge.estTelecharge, isTrue);

    // null = plus téléchargé : chemin et suppression prévue effacés.
    await depot.planifierSuppression(ids[0], DateTime.utc(2027));
    expect(await depot.enregistrerArchive(ids[0], null), isTrue);
    charge = (await depot.chargerChapitre(ids[0]))!;
    expect(charge.nomArchive, isNull);
    expect(charge.estTelecharge, isFalse);
    expect(charge.dateSuppressionPrevue, isNull);

    expect(await depot.enregistrerArchive(9999, 'manga/x/ch1.zip'), isFalse);
    expect(() => depot.enregistrerArchive(ids[0], '  '), throwsArgumentError);
  });

  test(
    "enregistrerArchive : un chemin repris retire l'ancien propriétaire",
    () async {
      await depot.enregistrerChapitres(<Chapitre>[chapitre(1), chapitre(2)]);
      final ids = (await depot.chargerChapitres(idTitre))
          .map((c) => c.id!)
          .toList();
      const nom = 'manga/Titre/ch1.en.zip';
      await depot.enregistrerArchive(ids[0], nom);
      await depot.planifierSuppression(ids[0], DateTime.utc(2027));

      // L'archive du premier n'existait plus : le second obtient ce nom.
      await depot.enregistrerArchive(ids[1], nom);
      final premier = (await depot.chargerChapitre(ids[0]))!;
      expect(premier.nomArchive, isNull);
      expect(premier.estTelecharge, isFalse);
      expect(premier.dateSuppressionPrevue, isNull);
      expect((await depot.chargerChapitre(ids[1]))!.nomArchive, nom);

      // Réenregistrer le même nom sur le même chapitre ne change rien.
      expect(await depot.enregistrerArchive(ids[1], nom), isTrue);
      expect((await depot.chargerChapitre(ids[1]))!.estTelecharge, isTrue);
    },
  );

  test('marquerTelecharge(false) efface aussi le chemin enregistré', () async {
    await depot.enregistrerChapitres(<Chapitre>[chapitre(1)]);
    final id = (await depot.chargerChapitres(idTitre)).single.id!;
    await depot.enregistrerArchive(id, 'manga/Titre/ch1.en.zip');
    await depot.marquerTelecharge(id, estTelecharge: false);
    final charge = (await depot.chargerChapitre(id))!;
    expect(charge.estTelecharge, isFalse);
    expect(charge.nomArchive, isNull);
    // marquerTelecharge(true) ne touche pas au chemin.
    await depot.enregistrerArchive(id, 'manga/Titre/ch1.en.zip');
    await depot.marquerTelecharge(id);
    expect(
      (await depot.chargerChapitre(id))!.nomArchive,
      'manga/Titre/ch1.en.zip',
    );
  });

  test('suppressions planifiées : échues seulement, annulation', () async {
    await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1),
      chapitre(2),
      chapitre(3),
    ]);
    final ids = (await depot.chargerChapitres(idTitre))
        .map((c) => c.id!)
        .toList();
    final maintenant = DateTime.utc(2026, 11, 15, 12);
    expect(await depot.chargerSuppressionsEchues(maintenant), isEmpty);

    await depot.planifierSuppression(
      ids[0],
      maintenant.subtract(const Duration(days: 1)),
    );
    await depot.planifierSuppression(ids[1], maintenant);
    await depot.planifierSuppression(
      ids[2],
      maintenant.add(const Duration(days: 1)),
    );
    expect(
      (await depot.chargerChapitre(ids[2]))!.dateSuppressionPrevue,
      maintenant.add(const Duration(days: 1)),
    );

    final echues = await depot.chargerSuppressionsEchues(maintenant);
    expect(echues.map((c) => c.id).toList(), <int?>[ids[0], ids[1]]);

    expect(await depot.planifierSuppression(ids[0], null), isTrue);
    expect(
      (await depot.chargerSuppressionsEchues(maintenant))
          .map((c) => c.id)
          .toList(),
      <int?>[ids[1]],
    );
    expect(await depot.planifierSuppression(9999, maintenant), isFalse);
  });

  test(
    "chargerChapitresTelecharges : seuls les téléchargés, filtre par titre",
    () async {
      expect(await depot.chargerChapitresTelecharges(), isEmpty);

      final idSource = (await DepotSources(base).chargerSources()).first.id!;
      final idAutreTitre = (await DepotTitres(base).enregistrerTitre(
        titreReference(idSource).copierAvec(
          urlTitre: 'https://mangadex.org/title/autre',
          nom: 'Autre titre',
        ),
      )).id!;
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(2),
        chapitre(1),
        chapitre(3),
        Chapitre(
          idTitre: idAutreTitre,
          urlChapitre: 'https://mangadex.org/chapter/autre-1',
          nom: 'Chapitre 1',
          numero: 1,
          langue: 'en',
        ),
      ]);
      final chapitres = await depot.chargerChapitres(idTitre);
      final autre = (await depot.chargerChapitres(idAutreTitre)).single;
      await depot.marquerTelecharge(chapitres[2].id!);
      await depot.marquerTelecharge(chapitres[0].id!);
      await depot.marquerTelecharge(autre.id!);

      final tous = await depot.chargerChapitresTelecharges();
      expect(tous.map((c) => c.id).toList(), <int?>[
        chapitres[0].id,
        chapitres[2].id,
        autre.id,
      ]);
      expect(tous.every((c) => c.estTelecharge), isTrue);

      final duTitre = await depot.chargerChapitresTelecharges(idTitre: idTitre);
      expect(duTitre.map((c) => c.numero).toList(), <double>[1, 3]);

      await depot.marquerTelecharge(chapitres[0].id!, estTelecharge: false);
      expect(
        (await depot.chargerChapitresTelecharges(idTitre: idTitre))
            .map((c) => c.id)
            .toList(),
        <int?>[chapitres[2].id],
      );
    },
  );
}
