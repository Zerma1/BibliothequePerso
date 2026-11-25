import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTitres depot;
  late Titre depuisLeSite;
  late Titre titre;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotTitres(base);
    final idSource = (await DepotSources(
      base,
    ).enregistrerSource(sourceMangaDex)).id!;
    depuisLeSite = titreReference(idSource);
    titre = await depot.enregistrerTitre(depuisLeSite);
  });

  tearDown(() async {
    await base.close();
  });

  test('un titre neuf n\'a pas de description personnelle', () async {
    expect(titre.descriptionPerso, isNull);
    expect((await base.query('titres')).single['description_perso'], isNull);
  });

  test('la description est écrite nettoyée, sans toucher au résumé du '
      'site', () async {
    final modifie = await depot.enregistrerDescriptionPerso(
      titre.id!,
      '  \nMon avis :\n\nà relire.  \n',
    );
    expect(modifie.descriptionPerso, 'Mon avis :\n\nà relire.');
    expect(modifie.resume, titre.resume);
    expect(
      modifie.copierAvec(effacerDescriptionPerso: true),
      titre,
      reason: 'seule la description a changé',
    );
    expect(
      (await depot.chargerTitre(titre.id!))!.descriptionPerso,
      'Mon avis :\n\nà relire.',
    );
  });

  test('un texte vide ou null efface la description (NULL)', () async {
    for (final effacement in <String?>['   \n ', '', null]) {
      await depot.enregistrerDescriptionPerso(titre.id!, 'Texte');
      final efface = await depot.enregistrerDescriptionPerso(
        titre.id!,
        effacement,
      );
      expect(efface.descriptionPerso, isNull, reason: '« $effacement »');
      expect(
        (await base.query('titres')).single['description_perso'],
        isNull,
        reason: '« $effacement »',
      );
    }
  });

  test('un titre inexistant est refusé', () async {
    await expectLater(
      depot.enregistrerDescriptionPerso(9999, 'Texte'),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
  });

  test(
    'une actualisation depuis le site ne perd jamais la description',
    () async {
      await depot.enregistrerDescriptionPerso(titre.id!, 'Ma description');

      // Titre reconstruit par la source : description à null, par URL.
      final actualise = await depot.enregistrerTitre(
        depuisLeSite.copierAvec(resume: 'Nouveau résumé du site.'),
      );
      expect(actualise.id, titre.id);
      expect(actualise.resume, 'Nouveau résumé du site.');
      expect(actualise.descriptionPerso, 'Ma description');

      // Même avec une autre description dans le Titre donné, par identifiant.
      final parId = await depot.enregistrerTitre(
        actualise.copierAvec(descriptionPerso: 'Autre texte'),
      );
      expect(parId.descriptionPerso, 'Ma description');
    },
  );

  test(
    'l\'insertion écrit la description du Titre (import), nettoyée',
    () async {
      final importe = await depot.enregistrerTitre(
        depuisLeSite.copierAvec(
          urlTitre: 'https://mangadex.org/title/autre',
          descriptionPerso: '  Importée  ',
        ),
      );
      expect(importe.descriptionPerso, 'Importée');

      final videImporte = await depot.enregistrerTitre(
        depuisLeSite.copierAvec(
          urlTitre: 'https://mangadex.org/title/vide',
          descriptionPerso: '   ',
        ),
      );
      expect(videImporte.descriptionPerso, isNull);
    },
  );

  test('dans une transaction annulée, rien n\'est écrit', () async {
    await expectLater(
      base.transaction((txn) async {
        final dansTxn = await depot.enregistrerDescriptionPerso(
          titre.id!,
          'Provisoire',
          executeur: txn,
        );
        expect(dansTxn.descriptionPerso, 'Provisoire');
        throw StateError('annulation');
      }),
      throwsStateError,
    );
    expect((await depot.chargerTitre(titre.id!))!.descriptionPerso, isNull);
  });
}
