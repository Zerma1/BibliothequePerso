import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotListes depot;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotListes(base);
  });

  tearDown(() async {
    await base.close();
  });

  test('une base neuve contient seulement Favoris puis Suivis', () async {
    final listes = await depot.chargerListes();
    expect(listes.map((liste) => liste.nom), <String>[
      nomListeFavoris,
      nomListeSuivis,
    ]);
    expect(listes.every((liste) => liste.estSysteme), isTrue);
  });

  test('créer une liste la place après les listes existantes', () async {
    final premiere = await depot.creerListe('  À lire  ');
    final seconde = await depot.creerListe('Terminés');

    expect(premiere.nom, 'À lire');
    expect(premiere.estSysteme, isFalse);
    expect(seconde.ordre, greaterThan(premiere.ordre));
    expect(premiere.ordre, greaterThan(ordreListeSuivis));
    expect((await depot.chargerListes()).last, seconde);
  });

  test('un nom vide ou déjà utilisé est refusé', () async {
    await depot.creerListe('À lire');
    await expectLater(
      depot.creerListe('   '),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.creerListe('À lire'),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    // Insensible à la casse : « favoris » entrerait en conflit avec la liste
    // système.
    await expectLater(
      depot.creerListe('favoris'),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
  });

  test('renommer une liste du client fonctionne', () async {
    final liste = await depot.creerListe('À lire');
    final renommee = await depot.renommerListe(liste.id!, 'Plus tard');
    expect(renommee.nom, 'Plus tard');
    expect((await depot.chargerListe(liste.id!))!.nom, 'Plus tard');
  });

  test('une liste système ne peut être ni renommée ni supprimée', () async {
    for (final nom in <String>[nomListeFavoris, nomListeSuivis]) {
      final liste = (await depot.chargerListeParNom(nom))!;
      await expectLater(
        depot.renommerListe(liste.id!, 'Autre nom'),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      await expectLater(
        depot.supprimerListe(liste.id!),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    }
    expect(await depot.chargerListes(), hasLength(2));
  });

  test('renommer ou supprimer une liste inexistante lève une erreur', () async {
    await expectLater(
      depot.renommerListe(999, 'Nom'),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.supprimerListe(999),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
  });

  test(
    'supprimer une liste garde ses titres mais retire leur appartenance',
    () async {
      final idSource = (await DepotSources(
        base,
      ).enregistrerSource(sourceMangaDex)).id!;
      final depotTitres = DepotTitres(base);
      final titre = await depotTitres.enregistrerTitre(
        titreReference(idSource),
      );
      final liste = await depot.creerListe('À lire');
      await depot.ajouterTitre(liste.id!, titre.id!);

      await depot.supprimerListe(liste.id!);

      expect(await depot.chargerListe(liste.id!), isNull);
      expect(await depotTitres.chargerTitre(titre.id!), isNotNull);
      expect(await base.query('titres_listes'), isEmpty);
    },
  );

  test(
    'ajouter deux fois un titre ne crée pas de doublon, retirer l\'enlève',
    () async {
      final idSource = (await DepotSources(
        base,
      ).enregistrerSource(sourceMangaDex)).id!;
      final titre = await DepotTitres(base)
          .enregistrerTitre(titreReference(idSource));
      final favoris = (await depot.chargerListeParNom(nomListeFavoris))!;

      await depot.ajouterTitre(favoris.id!, titre.id!);
      await depot.ajouterTitre(favoris.id!, titre.id!);
      expect(await depot.chargerListesDuTitre(titre.id!), hasLength(1));

      await depot.retirerTitre(favoris.id!, titre.id!);
      expect(await depot.chargerListesDuTitre(titre.id!), isEmpty);
      // Retirer un titre absent ne fait rien.
      await depot.retirerTitre(favoris.id!, titre.id!);
    },
  );

  test('ajouter un titre inexistant ou dans une liste inexistante lève une '
      'ErreurBaseDeDonnees', () async {
    final idSource = (await DepotSources(
      base,
    ).enregistrerSource(sourceMangaDex)).id!;
    final titre = await DepotTitres(base)
        .enregistrerTitre(titreReference(idSource));
    final favoris = (await depot.chargerListeParNom(nomListeFavoris))!;

    await expectLater(
      depot.ajouterTitre(favoris.id!, 999),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.ajouterTitre(999, titre.id!),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(await base.query('titres_listes'), isEmpty);
  });
}
