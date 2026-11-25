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

  test('une base neuve contient seulement les listes système, dans '
      'l\'ordre', () async {
    final listes = await depot.chargerListes();
    expect(listes.map((liste) => liste.nom), nomsListesSysteme);
    expect(listes.map((liste) => liste.nom), <String>[
      nomListeFavoris,
      nomListeSuivis,
      nomListePlanifie,
      nomListeEnAttente,
      nomListeTermines,
    ]);
    expect(listes.every((liste) => liste.estSysteme), isTrue);
    expect(
      (await depot.chargerListeParNom(nomListeTermines))!.ordre,
      ordreListeTermines,
    );
  });

  test('créer une liste la place après les listes existantes', () async {
    final premiere = await depot.creerListe('  À lire  ');
    final seconde = await depot.creerListe('Finis');

    expect(premiere.nom, 'À lire');
    expect(premiere.estSysteme, isFalse);
    expect(seconde.ordre, greaterThan(premiere.ordre));
    expect(premiere.ordre, greaterThan(ordreListeTermines));
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
    expect(await depot.chargerListes(), hasLength(nomsListesSysteme.length));
  });

  test('les cinq listes système refusent renommage et suppression avec un '
      'message clair', () async {
    for (final nom in nomsListesSysteme) {
      final liste = (await depot.chargerListeParNom(nom))!;
      expect(liste.estSysteme, isTrue, reason: nom);
      await expectLater(
        depot.renommerListe(liste.id!, 'Autre nom'),
        throwsA(
          isA<ErreurBaseDeDonnees>().having(
            (e) => e.message,
            'message',
            '« $nom » est une liste système : elle ne peut pas être renommée.',
          ),
        ),
      );
      await expectLater(
        depot.supprimerListe(liste.id!),
        throwsA(
          isA<ErreurBaseDeDonnees>().having(
            (e) => e.message,
            'message',
            '« $nom » est une liste système : elle ne peut pas être supprimée.',
          ),
        ),
      );
      expect(await depot.chargerListe(liste.id!), liste, reason: nom);
    }
  });

  test('« En attente (perso) » est une liste ordinaire', () async {
    final perso = await depot.creerListe('En attente (perso)');
    expect(perso.estSysteme, isFalse);
    final renommee = await depot.renommerListe(perso.id!, 'Pause');
    expect(renommee.nom, 'Pause');
    await depot.supprimerListe(perso.id!);
    expect(await depot.chargerListe(perso.id!), isNull);
    expect(await depot.chargerListeParNom(nomListeEnAttente), isNotNull);
  });

  test('« Terminés (perso) » est une liste ordinaire, « Terminés » est '
      'protégée même sous une autre casse', () async {
    final perso = await depot.creerListe('Terminés (perso)');
    expect(perso.estSysteme, isFalse);
    expect((await depot.renommerListe(perso.id!, 'Finis')).nom, 'Finis');
    await depot.supprimerListe(perso.id!);
    expect(await depot.chargerListe(perso.id!), isNull);

    final termines = (await depot.chargerListeParNom('TERMINéS'))!;
    expect(termines.nom, nomListeTermines);
    expect(termines.estSysteme, isTrue);
    // Une liste du client ne peut pas prendre le nom de la liste système.
    await expectLater(
      depot.creerListe('terminés'),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.renommerListe(termines.id!, 'Lus'),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.supprimerListe(termines.id!),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(await depot.chargerListeParNom(nomListeTermines), termines);
  });

  test(
    'renommer vers un nom déjà pris (même casse différente) est refusé',
    () async {
      final liste = await depot.creerListe('À lire');
      await depot.creerListe('Finis');
      for (final nom in <String>['Finis', 'suivis', ' Favoris ', 'terminés']) {
        await expectLater(
          depot.renommerListe(liste.id!, nom),
          throwsA(isA<ErreurBaseDeDonnees>()),
          reason: nom,
        );
      }
      expect((await depot.chargerListe(liste.id!))!.nom, 'À lire');
      // Changer seulement la casse de son propre nom est accepté.
      expect((await depot.renommerListe(liste.id!, 'à lire')).nom, 'à lire');
    },
  );

  test('enregistrerOrdre réordonne toutes les listes', () async {
    final a = await depot.creerListe('A');
    final b = await depot.creerListe('B');
    final avant = await depot.chargerListes();
    final idsInverses = <int>[for (final l in avant.reversed) l.id!];

    final resultat = await depot.enregistrerOrdre(idsInverses);

    expect(resultat.map((l) => l.id), idsInverses);
    expect(resultat.map((l) => l.ordre), <int>[0, 1, 2, 3, 4, 5, 6]);
    final relues = await depot.chargerListes();
    expect(relues, resultat);
    expect(relues.first.id, b.id);
    expect(relues[1].id, a.id);
    // Une liste créée ensuite va à la fin.
    final c = await depot.creerListe('C');
    expect((await depot.chargerListes()).last.id, c.id);
  });

  test('enregistrerOrdre partiel : les listes absentes suivent, dans leur '
      'ordre', () async {
    final a = await depot.creerListe('A');
    final suivis = (await depot.chargerListeParNom(nomListeSuivis))!;

    await depot.enregistrerOrdre(<int>[a.id!, suivis.id!]);

    expect((await depot.chargerListes()).map((l) => l.nom), <String>[
      'A',
      nomListeSuivis,
      nomListeFavoris,
      nomListePlanifie,
      nomListeEnAttente,
      nomListeTermines,
    ]);
  });

  test('enregistrerOrdre refuse un doublon ou une liste inconnue sans rien '
      'écrire', () async {
    final avant = await depot.chargerListes();
    final premier = avant.last.id!;
    await expectLater(
      depot.enregistrerOrdre(<int>[premier, premier]),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    await expectLater(
      depot.enregistrerOrdre(<int>[premier, 999]),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(await depot.chargerListes(), avant);
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
