import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotSources depot;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotSources(base);
  });

  tearDown(() async {
    await base.close();
  });

  test('aucune source dans une base neuve', () async {
    expect(await depot.chargerSources(), isEmpty);
    expect(await depot.chargerSource(1), isNull);
  });

  test('une source enregistrée est relue à l\'identique', () async {
    final enregistree = await depot.enregistrerSource(sourceMangaDex);
    expect(enregistree.id, isNotNull);
    expect(await depot.chargerSource(enregistree.id!), enregistree);
    expect(
      await depot.chargerSourceParUrl('https://mangadex.org'),
      enregistree,
    );
  });

  test('une source générique garde sa configuration JSON', () async {
    final source = await depot.enregistrerSource(
      const Source(
        nom: 'Site perso',
        urlBase: 'https://exemple.org',
        typeSource: TypeSource.generique,
        configurationSelecteurs: '{"titre":"h1"}',
        estActive: false,
      ),
    );
    final relue = (await depot.chargerSource(source.id!))!;
    expect(relue.configurationSelecteurs, '{"titre":"h1"}');
    expect(relue.estActive, isFalse);
  });

  test('la mise à jour modifie la ligne existante', () async {
    final source = await depot.enregistrerSource(sourceMangaDex);
    await depot.enregistrerSource(source.copierAvec(estActive: false));
    final sources = await depot.chargerSources();
    expect(sources, hasLength(1));
    expect(sources.single.estActive, isFalse);
  });

  test('une URL de base en double est refusée', () async {
    await depot.enregistrerSource(sourceMangaDex);
    await expectLater(
      depot.enregistrerSource(sourceMangaDex.copierAvec(nom: 'Copie')),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
  });

  test(
    'une source utilisée par des titres ne peut pas être supprimée',
    () async {
      final source = await depot.enregistrerSource(sourceMangaDex);
      final titre = await DepotTitres(base)
          .enregistrerTitre(titreReference(source.id!));

      await expectLater(
        depot.supprimerSource(source.id!),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );

      await DepotTitres(base).supprimerTitre(titre.id!);
      await depot.supprimerSource(source.id!);
      expect(await depot.chargerSources(), isEmpty);
    },
  );
}
