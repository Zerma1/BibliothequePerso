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
}
