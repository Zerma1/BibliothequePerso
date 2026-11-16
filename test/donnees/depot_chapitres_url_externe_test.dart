// Tests de la tâche R4 sur DepotChapitres : chapitres hébergés sur un site
// externe (colonne url_externe, migration 6).
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotChapitres depot;
  late int idTitre;

  const lienEditeur = 'https://editeur.example/ruri/1';
  final maintenant = DateTime.utc(2026, 11, 16, 12);

  Chapitre chapitre(double numero, {String? urlExterne}) => Chapitre(
    idTitre: idTitre,
    urlChapitre: 'https://mangadex.org/chapter/$numero',
    nom: 'Chapitre $numero',
    numero: numero,
    langue: 'en',
    urlExterne: urlExterne,
  );

  Future<Chapitre> charger(double numero) async {
    final lignes = await base.query(
      'chapitres',
      where: 'url_chapitre = ?',
      whereArgs: <Object?>['https://mangadex.org/chapter/$numero'],
    );
    return Chapitre.depuisMap(lignes.single);
  }

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

  test('un nouveau chapitre externe est enregistré avec son lien', () async {
    final nouveaux = await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1, urlExterne: lienEditeur),
      chapitre(2),
    ], dateDetection: maintenant);
    expect(nouveaux, 2);
    final externe = await charger(1);
    expect(externe.urlExterne, lienEditeur);
    expect(externe.estExterne, isTrue);
    expect((await charger(2)).estExterne, isFalse);
    // Chargement par les méthodes habituelles du dépôt.
    final chapitres = await depot.chargerChapitres(idTitre);
    expect(chapitres.first.urlExterne, lienEditeur);
  });

  test('un lien vide ou fait d\'espaces est enregistré comme NULL', () async {
    await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1, urlExterne: '  '),
    ], dateDetection: maintenant);
    final ligne = (await base.query('chapitres')).single;
    expect(ligne['url_externe'], isNull);
  });

  test('un lien externe nouveau ou modifié met à jour ce seul champ, sans '
      'toucher à la lecture ni au téléchargement', () async {
    await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1),
    ], dateDetection: maintenant);
    final id = (await charger(1)).id!;
    await depot.marquerLu(id);
    await depot.enregistrerArchive(id, 'manga/Titre/ch1.en.zip');
    await depot.planifierSuppression(id, DateTime.utc(2026, 12));
    final avant = await charger(1);

    // Le chapitre devient externe : aucun nouveau chapitre.
    expect(
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(
          1,
          urlExterne: lienEditeur,
        ).copierAvec(nom: 'Autre nom', dateDetection: DateTime.utc(2030)),
      ]),
      0,
    );
    expect(await charger(1), avant.copierAvec(urlExterne: lienEditeur));

    // Le lien change.
    await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1, urlExterne: 'https://editeur.example/nouveau'),
    ]);
    expect(
      await charger(1),
      avant.copierAvec(urlExterne: 'https://editeur.example/nouveau'),
    );
  });

  test('un chapitre externe qui devient hébergé perd son lien, et seulement '
      'lui', () async {
    await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1, urlExterne: lienEditeur),
    ], dateDetection: maintenant);
    final id = (await charger(1)).id!;
    await depot.marquerLu(id);
    await depot.marquerGarde(id);
    final avant = await charger(1);

    expect(await depot.enregistrerChapitres(<Chapitre>[chapitre(1)]), 0);
    final apres = await charger(1);
    expect(apres.urlExterne, isNull);
    expect(apres.estExterne, isFalse);
    expect(apres, avant.copierAvec(effacerUrlExterne: true));
  });

  test('un lien inchangé ne modifie pas la ligne', () async {
    await depot.enregistrerChapitres(<Chapitre>[
      chapitre(1, urlExterne: lienEditeur),
      chapitre(2),
    ], dateDetection: maintenant);
    final avant = await base.query('chapitres', orderBy: 'id');
    // total_changes() compte les lignes écrites sur la connexion : il ne
    // doit pas bouger si rien n'a changé (INSERT OR IGNORE ignoré, UPDATE
    // filtré par « IS NOT »).
    Future<Object?> changements() async =>
        (await base.rawQuery('SELECT total_changes() AS n')).single['n'];
    final changementsAvant = await changements();

    expect(
      await depot.enregistrerChapitres(<Chapitre>[
        chapitre(1, urlExterne: lienEditeur),
        chapitre(2),
      ]),
      0,
    );
    expect(await changements(), changementsAvant);
    expect(await base.query('chapitres', orderBy: 'id'), avant);
  });
}
