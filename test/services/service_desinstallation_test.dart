// Mode désinstallation (appelé par l'installateur Windows) : analyse des
// arguments, écritures en base dans l'ordre, réglages nettoyés, code de
// sortie. Base en mémoire ou fichier temporaire : jamais la vraie base.
import 'dart:io';

import 'package:bibliotheque_perso/donnees/base_de_donnees.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/constantes_services.dart';
import 'package:bibliotheque_perso/services/service_desinstallation.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_sources_par_defaut.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as chemins;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

/// Compte les lignes de [table].
Future<int> compter(Database base, String table) async =>
    Sqflite.firstIntValue(await base.rawQuery('SELECT COUNT(*) FROM $table'))!;

/// Bibliothèque de test : 2 sources, 2 titres, 3 chapitres (2 téléchargés,
/// dont un gardé), 2 lignes de file, et les réglages concernés.
Future<void> remplir(Database base) async {
  final source1 = (await DepotSources(base).enregistrerSource(sourceMangaDex))
      .id!;
  final source2 = (await DepotSources(base).enregistrerSource(
    const Source(
      nom: 'Autre',
      urlBase: 'https://autre.exemple',
      typeSource: TypeSource.generique,
    ),
  )).id!;
  final titre1 = (await DepotTitres(
    base,
  ).enregistrerTitre(titreReference(source1))).id!;
  final titre2 = (await DepotTitres(base).enregistrerTitre(
    titreReference(source2)
        .copierAvec(urlTitre: 'https://autre.exemple/t/2', nom: 'Deuxième'),
  )).id!;
  Future<int> chapitre(int idTitre, String url, {String? archive}) =>
      base.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': url,
        'nom': url,
        'numero': 1.0,
        'est_lu': 1,
        'est_telecharge': archive == null ? 0 : 1,
        'nom_archive': archive,
        'est_garde': archive == null ? 0 : 1,
      });
  final c1 = await chapitre(titre1, 'https://mangadex.org/c/1', archive: 'a');
  final c2 = await chapitre(titre1, 'https://mangadex.org/c/2', archive: 'b');
  await chapitre(titre2, 'https://autre.exemple/c/1');
  for (final id in <int>[c1, c2]) {
    await base.insert('telechargements', <String, Object?>{
      'id_chapitre': id,
      'statut': 'termine',
      'date_ajout': 1,
      'date_maj': 1,
    });
  }
  final parametres = DepotParametres(base);
  await parametres.enregistrerTexte(ServiceParametres.cleChapitresGardes, '1');
  await parametres.enregistrerTexte(
    ServiceParametres.cleDeplacementDossierEnCours,
    'D:/ailleurs',
  );
  await parametres.enregistrerTexte(
    ServiceParametres.cleSourcesParDefautProposees,
    'mangadex,scan-manga',
  );
  await parametres.enregistrerTexte(ServiceParametres.cleLangues, 'fr,en');
}

void main() {
  group('Analyse des arguments', () {
    test('le mode est reconnu par son option, et seulement elle', () {
      expect(estModeDesinstallation(<String>[argumentDesinstallation]), isTrue);
      expect(estModeDesinstallation(<String>['--demarrage-masque']), isFalse);
      expect(estModeDesinstallation(const <String>[]), isFalse);
    });

    test('les trois options sont reconnues', () {
      final options = OptionsDesinstallation.depuisArguments(<String>[
        argumentDesinstallation,
        argumentSupprimerSources,
        argumentSupprimerTitres,
        argumentChapitresSupprimes,
      ]);

      expect(options.estValide, isTrue);
      expect(options.supprimerSources, isTrue);
      expect(options.supprimerTitres, isTrue);
      expect(options.chapitresSupprimes, isTrue);
    });

    test(
      'supprimer les sources entraîne toujours la suppression des titres',
      () {
        final options = OptionsDesinstallation.depuisArguments(<String>[
          argumentDesinstallation,
          argumentSupprimerSources,
        ]);

        expect(options.supprimerTitres, isTrue);
        expect(options.aQuelqueChoseAFaire, isTrue);
      },
    );

    test('les chapitres ne sont marqués que si les titres sont gardés', () {
      expect(
        OptionsDesinstallation.depuisArguments(<String>[
          argumentChapitresSupprimes,
        ]).doitMarquerChapitres,
        isTrue,
      );
      expect(
        OptionsDesinstallation.depuisArguments(<String>[
          argumentChapitresSupprimes,
          argumentSupprimerTitres,
        ]).doitMarquerChapitres,
        isFalse,
      );
    });

    test("sans option, il n'y a rien à faire", () {
      final options = OptionsDesinstallation.depuisArguments(<String>[
        argumentDesinstallation,
      ]);

      expect(options.estValide, isTrue);
      expect(options.aQuelqueChoseAFaire, isFalse);
    });

    test('un argument inconnu ou mal écrit rend les options non valides', () {
      final options = OptionsDesinstallation.depuisArguments(<String>[
        argumentDesinstallation,
        '--SUPPRIMER-TITRES',
        '--supprimer-listes',
      ]);

      expect(options.estValide, isFalse);
      expect(options.argumentsInconnus, <String>[
        '--SUPPRIMER-TITRES',
        '--supprimer-listes',
      ]);
      expect(options.supprimerTitres, isFalse);
    });

    test('les doublons sont acceptés', () {
      final options = OptionsDesinstallation.depuisArguments(<String>[
        argumentSupprimerTitres,
        argumentSupprimerTitres,
      ]);

      expect(options.estValide, isTrue);
      expect(options.supprimerTitres, isTrue);
    });
  });

  group('ServiceDesinstallation', () {
    late Database base;
    late ServiceDesinstallation service;
    late DepotParametres parametres;

    setUp(() async {
      base = await ouvrirBaseDeTest();
      service = ServiceDesinstallation.surBase(base);
      parametres = DepotParametres(base);
      await remplir(base);
    });

    tearDown(() async {
      if (base.isOpen) await base.close();
    });

    Future<ResultatDesinstallation> executer(List<String> arguments) =>
        service.executer(OptionsDesinstallation.depuisArguments(arguments));

    test('chapitres effacés seuls : chapitres non téléchargés, file vidée, '
        'titres et sources gardés', () async {
      final resultat = await executer(<String>[argumentChapitresSupprimes]);

      expect(resultat.estReussi, isTrue);
      expect(resultat.codeSortie, codeSortieDesinstallationReussie);
      expect(resultat.chapitresMarques, 2);
      expect(resultat.telechargementsRetires, 2);
      expect(
        await base.query('chapitres', where: 'est_telecharge = 1'),
        isEmpty,
      );
      expect(await compter(base, 'telechargements'), 0);
      expect(await compter(base, 'titres'), 2);
      expect(await compter(base, 'sources'), 2);
      // Réglages liés aux archives effacées : supprimés ; les autres restent.
      expect(
        await parametres.chargerTexte(ServiceParametres.cleChapitresGardes),
        isNull,
      );
      expect(
        await parametres.chargerTexte(
          ServiceParametres.cleDeplacementDossierEnCours,
        ),
        isNull,
      );
      expect(
        await parametres.chargerTexte(
          ServiceParametres.cleSourcesParDefautProposees,
        ),
        'mangadex,scan-manga',
      );
      expect(resultat.reglagesSupprimes, 2);
    });

    test('titres : titres et chapitres supprimés, sources et repère des '
        'sources par défaut gardés', () async {
      final resultat = await executer(<String>[
        argumentSupprimerTitres,
        argumentChapitresSupprimes,
      ]);

      expect(resultat.estReussi, isTrue);
      expect(resultat.titresSupprimes, 2);
      // Inutile de marquer des chapitres qui disparaissent avec leurs titres.
      expect(resultat.chapitresMarques, 0);
      expect(await compter(base, 'titres'), 0);
      expect(await compter(base, 'chapitres'), 0);
      expect(await compter(base, 'sources'), 2);
      expect(
        await parametres.chargerTexte(ServiceParametres.cleChapitresGardes),
        isNull,
      );
      expect(
        await parametres.chargerTexte(
          ServiceParametres.cleSourcesParDefautProposees,
        ),
        'mangadex,scan-manga',
      );
    });

    test('sources : tout est supprimé et les sources par défaut reviennent '
        'au prochain démarrage, comme après une installation neuve', () async {
      final resultat = await executer(<String>[
        argumentSupprimerSources,
        argumentSupprimerTitres,
      ]);

      expect(resultat.estReussi, isTrue);
      expect(resultat.titresSupprimes, 2);
      expect(resultat.sourcesSupprimees, 2);
      expect(resultat.sourcesGardees, 0);
      expect(await compter(base, 'sources'), 0);
      expect(
        await parametres.chargerTexte(
          ServiceParametres.cleSourcesParDefautProposees,
        ),
        isNull,
      );
      // Réglages du client sans lien avec les données : gardés.
      expect(
        await parametres.chargerTexte(ServiceParametres.cleLangues),
        'fr,en',
      );

      final demarrage = await ServiceSourcesParDefaut(
        depotSources: DepotSources(base),
        serviceParametres: ServiceParametres(parametres),
      ).assurerSourcesParDefaut();
      expect(demarrage.ajoutees.map((source) => source.nom), <String>[
        nomMangaDex,
        nomScanManga,
      ]);
    });

    test('des arguments non valides ne modifient rien', () async {
      final resultat = await executer(<String>[
        argumentSupprimerSources,
        '--inconnu',
      ]);

      expect(resultat.estReussi, isFalse);
      expect(resultat.etapeEchouee, EtapeDesinstallation.arguments);
      expect(resultat.codeSortie, codeSortieDesinstallationEchec);
      expect(await compter(base, 'titres'), 2);
      expect(await compter(base, 'sources'), 2);
    });

    test(
      'une erreur de base est rendue dans le résultat, sans exception',
      () async {
        await base.close();

        final resultat = await executer(<String>[argumentSupprimerTitres]);

        expect(resultat.estReussi, isFalse);
        expect(resultat.etapeEchouee, EtapeDesinstallation.titres);
        expect(resultat.codeSortie, codeSortieDesinstallationEchec);
      },
    );
  });

  group('executerModeDesinstallation', () {
    late Directory dossier;
    late String chemin;

    setUp(() async {
      sqfliteFfiInit();
      dossier = await Directory.systemTemp.createTemp('desinstallation_');
      chemin = chemins.join(dossier.path, 'bibliotheque.db');
    });

    tearDown(() async {
      await dossier.delete(recursive: true);
    });

    test(
      'ouvre la base, supprime titres et sources, la ferme et renvoie 0',
      () async {
        final base = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        await remplir(base);
        await base.close();

        final code = await executerModeDesinstallation(
          <String>[
            argumentDesinstallation,
            argumentSupprimerSources,
            argumentSupprimerTitres,
            argumentChapitresSupprimes,
          ],
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );

        expect(code, codeSortieDesinstallationReussie);
        final relue = await ouvrirBaseDeDonnees(
          chemin: chemin,
          fabrique: databaseFactoryFfi,
        );
        expect(await compter(relue, 'titres'), 0);
        expect(await compter(relue, 'sources'), 0);
        await relue.close();
      },
    );

    test('base absente : rien à faire, 0, et aucune base créée', () async {
      final code = await executerModeDesinstallation(
        <String>[argumentDesinstallation, argumentSupprimerTitres],
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );

      expect(code, codeSortieDesinstallationReussie);
      expect(File(chemin).existsSync(), isFalse);
    });

    test("sans option, la base n'est pas ouverte et le code vaut 0", () async {
      final code = await executerModeDesinstallation(
        <String>[argumentDesinstallation],
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );

      expect(code, codeSortieDesinstallationReussie);
      expect(File(chemin).existsSync(), isFalse);
    });

    test('argument inconnu : 1, base intacte', () async {
      final base = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      await remplir(base);
      await base.close();

      final code = await executerModeDesinstallation(
        <String>[argumentDesinstallation, argumentSupprimerTitres, '--oups'],
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );

      expect(code, codeSortieDesinstallationEchec);
      final relue = await ouvrirBaseDeDonnees(
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );
      expect(await compter(relue, 'titres'), 2);
      await relue.close();
    });

    test('fichier illisible : 1, sans exception', () async {
      await File(chemin).writeAsString("ceci n'est pas une base SQLite");

      final code = await executerModeDesinstallation(
        <String>[argumentDesinstallation, argumentSupprimerTitres],
        chemin: chemin,
        fabrique: databaseFactoryFfi,
      );

      expect(code, codeSortieDesinstallationEchec);
    });
  });
}
