// Réglages du client : valeurs par défaut, nettoyage et bornes (base en
// mémoire).
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotParametres depot;
  late ServiceParametres parametres;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotParametres(base);
    parametres = ServiceParametres(depot);
  });

  tearDown(() => base.close());

  group('langues de lecture', () {
    test('valent français puis anglais tant que rien n\'est choisi', () async {
      expect(await parametres.chargerLangues(), <String>['fr', 'en']);
    });

    test('sont nettoyées, sans doublon, dans leur ordre', () async {
      await parametres.enregistrerLangues(<String>[
        ' EN',
        'fr',
        'en',
        '',
        'x!',
        'pt-BR',
      ]);
      expect(await parametres.chargerLangues(), <String>['en', 'fr', 'pt-br']);
    });

    test('ne peuvent pas être vides', () async {
      await expectLater(
        parametres.enregistrerLangues(<String>[' ', '??']),
        throwsA(isA<ErreurService>()),
      );
      await depot.enregistrerTexte(ServiceParametres.cleLangues, ',,');
      expect(await parametres.chargerLangues(), <String>['fr', 'en']);
    });
  });

  test('« avant » et « après » des suivis valent au moins 1', () async {
    await parametres.enregistrerReglagesTelechargement(
      const ReglagesTelechargement(suivisAvant: 0, suivisApres: -3),
    );
    final reglages = await parametres.chargerReglagesTelechargement();
    expect(reglages.suivisAvant, 1);
    expect(reglages.suivisApres, 1);

    // Une valeur 0 écrite par une ancienne version retombe sur le défaut.
    await depot.enregistrerEntier(ServiceParametres.cleSuivisAvant, 0);
    expect((await parametres.chargerReglagesTelechargement()).suivisAvant, 5);
  });

  group('téléchargements simultanés', () {
    test('valent 3 tant que rien n\'est choisi', () async {
      expect(await parametres.chargerTelechargementsSimultanes(), 3);
    });

    test('sont ramenés entre 1 et 32 à l\'enregistrement', () async {
      await parametres.enregistrerTelechargementsSimultanes(12);
      expect(await parametres.chargerTelechargementsSimultanes(), 12);
      await parametres.enregistrerTelechargementsSimultanes(0);
      expect(await parametres.chargerTelechargementsSimultanes(), 1);
      await parametres.enregistrerTelechargementsSimultanes(1000);
      expect(await parametres.chargerTelechargementsSimultanes(), 32);
    });

    test('une valeur hors bornes écrite en base retombe sur 3', () async {
      await depot.enregistrerEntier(
        ServiceParametres.cleTelechargementsSimultanes,
        500,
      );
      expect(await parametres.chargerTelechargementsSimultanes(), 3);
      await depot.enregistrerEntier(
        ServiceParametres.cleTelechargementsSimultanes,
        0,
      );
      expect(await parametres.chargerTelechargementsSimultanes(), 3);
    });
  });

  group('thème', () {
    test('suit le système tant que rien n\'est choisi', () async {
      expect(await parametres.chargerModeTheme(), ModeTheme.systeme);
    });

    test('se relit après enregistrement', () async {
      await parametres.enregistrerModeTheme(ModeTheme.sombre);
      expect(await parametres.chargerModeTheme(), ModeTheme.sombre);
      await parametres.enregistrerModeTheme(ModeTheme.clair);
      expect(await parametres.chargerModeTheme(), ModeTheme.clair);
    });

    test('une valeur inconnue écrite en base retombe sur le système', () async {
      await depot.enregistrerTexte(ServiceParametres.cleModeTheme, 'violet');
      expect(await parametres.chargerModeTheme(), ModeTheme.systeme);
    });
  });

  group('durée de conservation avant suppression', () {
    test('vaut 24 h tant que rien n\'est choisi', () async {
      expect(
        await parametres.chargerDelaiSuppression(),
        const Duration(hours: 24),
      );
    });

    test('se relit après enregistrement, arrondie à l\'heure', () async {
      await parametres.enregistrerDelaiSuppression(const Duration(days: 7));
      expect(
        await parametres.chargerDelaiSuppression(),
        const Duration(days: 7),
      );
      await parametres.enregistrerDelaiSuppression(
        const Duration(hours: 5, minutes: 40),
      );
      expect(
        await parametres.chargerDelaiSuppression(),
        const Duration(hours: 6),
      );
    });

    test('est ramenée entre 1 h et 30 jours à l\'enregistrement', () async {
      await parametres.enregistrerDelaiSuppression(Duration.zero);
      expect(
        await parametres.chargerDelaiSuppression(),
        const Duration(hours: 1),
      );
      await parametres.enregistrerDelaiSuppression(const Duration(days: 90));
      expect(
        await parametres.chargerDelaiSuppression(),
        const Duration(days: 30),
      );
    });

    test('une valeur hors bornes écrite en base retombe sur 24 h', () async {
      for (final heures in <int>[0, -5, 721]) {
        await depot.enregistrerEntier(
          ServiceParametres.cleHeuresAvantSuppression,
          heures,
        );
        expect(
          await parametres.chargerDelaiSuppression(),
          const Duration(hours: 24),
        );
      }
    });

    test('les crans proposés sont croissants, bornes et défaut compris', () {
      const crans = ServiceParametres.delaisSuppressionProposes;
      for (var i = 1; i < crans.length; i++) {
        expect(crans[i] > crans[i - 1], isTrue);
      }
      expect(crans.first, ServiceParametres.delaiSuppressionMinimum);
      expect(crans.last, ServiceParametres.delaiSuppressionMaximum);
      expect(crans, contains(ServiceParametres.delaiSuppressionParDefaut));
    });
  });

  test(
    'les chapitres gardés se relisent, valeurs illisibles ignorées',
    () async {
      expect(await parametres.chargerChapitresGardes(), isEmpty);
      await parametres.enregistrerChapitresGardes(<int>[3, 7, 3]);
      expect(await parametres.chargerChapitresGardes(), <int>{3, 7});

      await depot.enregistrerTexte(
        ServiceParametres.cleChapitresGardes,
        '4,x,9',
      );
      expect(await parametres.chargerChapitresGardes(), <int>{4, 9});

      await parametres.enregistrerChapitresGardes(const <int>[]);
      expect(await parametres.chargerChapitresGardes(), isEmpty);
    },
  );
}
