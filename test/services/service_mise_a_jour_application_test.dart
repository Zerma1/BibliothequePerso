// Tests de ServiceMiseAJourApplication : base en mémoire, faux client GitHub,
// dossier temporaire et faux lanceur ; aucun appel réseau, aucun processus
// lancé.

import 'dart:async';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_mise_a_jour_application.dart';
import 'package:bibliotheque_perso/sources/client_mise_a_jour_github.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/limite_github.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

const String _empreinte =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// Faux client : réponses programmées, appels comptés, fichier écrit sur le
/// disque comme le vrai client.
class _FauxClient implements ClientMiseAJourGithub {
  ReleaseApplication? release;
  Object? erreur;
  Object? erreurTelechargement;
  Completer<void>? attente;
  int appelsVersion = 0;
  int appelsEmpreinte = 0;
  int appelsTelechargement = 0;
  String? nomEmpreinteDemande;
  String? cheminDemande;

  @override
  Future<ReleaseApplication?> recupererDerniereVersion() async {
    appelsVersion++;
    await attente?.future;
    final e = erreur;
    if (e != null) throw e;
    return release;
  }

  @override
  Future<String> recupererEmpreinteAttendue(
    Uri url, {
    String? nomFichierAttendu,
  }) async {
    appelsEmpreinte++;
    nomEmpreinteDemande = nomFichierAttendu;
    return _empreinte;
  }

  @override
  Future<File> telechargerInstallateur(
    Uri url,
    String cheminDestination, {
    required String empreinteAttendue,
    int? tailleAttendue,
    int tailleMax = 0,
    ProgressionTelechargement? progression,
  }) async {
    appelsTelechargement++;
    cheminDemande = cheminDestination;
    await attente?.future;
    final e = erreurTelechargement;
    if (e != null) throw e;
    progression?.call(3, 3);
    return File(cheminDestination).writeAsBytes(<int>[1, 2, 3]);
  }
}

ReleaseApplication _release(String version, {bool telechargeable = true}) {
  final v = VersionApplication.analyser(version)!;
  final base =
      'https://github.com/Zerma1/BibliothequePerso/releases/download/v$version/'
      'bibliotheque_perso-$version-installation.exe';
  return ReleaseApplication(
    etiquette: 'v$version',
    version: v,
    nom: 'Version $version',
    notes: '',
    datePublication: DateTime.utc(2026, 11, 27),
    urlPage:
        'https://github.com/Zerma1/BibliothequePerso/releases/tag/v$version',
    installateur: telechargeable
        ? FichierRelease(nom: 'exe', url: Uri.parse(base), taille: 3)
        : null,
    fichierEmpreinte: telechargeable
        ? FichierRelease(nom: 'sha', url: Uri.parse('$base.sha256'), taille: 1)
        : null,
  );
}

void main() {
  late Database base;
  late DepotParametres depot;
  late _FauxClient client;
  late Directory temporaire;
  late DateTime maintenant;
  late List<List<String>> lancements;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotParametres(base);
    client = _FauxClient();
    temporaire = await Directory.systemTemp.createTemp('service_maj_');
    maintenant = DateTime.utc(2026, 11, 27, 12);
    lancements = <List<String>>[];
  });

  tearDown(() async {
    await base.close();
    if (await temporaire.exists()) {
      await temporaire.delete(recursive: true);
    }
  });

  ServiceMiseAJourApplication creer({
    String version = '0.4.0+12',
    bool estWindows = true,
  }) => ServiceMiseAJourApplication(
    depot,
    client,
    versionApplication: version,
    dossierTemporaire: temporaire,
    estWindows: estWindows,
    horloge: () => maintenant,
    lanceur: (executable, arguments) async {
      lancements.add(<String>[executable, ...arguments]);
    },
  );

  group('règles pures', () {
    test('lit la version en retirant v, +N et -test', () {
      final lire = ServiceMiseAJourApplication.lireVersion;
      expect(lire('0.4.0+12').toString(), '0.4.0');
      expect(lire('0.3.2-test').toString(), '0.3.2');
      expect(lire('0.3.2-test+9').toString(), '0.3.2');
      expect(lire('v1.2.3').toString(), '1.2.3');
      expect(lire('0.4'), isNull);
      expect(lire(''), isNull);
    });

    test('une vérification est due après 24 h ou si la date est future', () {
      final due = ServiceMiseAJourApplication.verificationDue;
      final midi = DateTime.utc(2026, 11, 27, 12);
      expect(due(null, midi), isTrue);
      expect(due(midi.subtract(const Duration(hours: 23)), midi), isFalse);
      expect(due(midi.subtract(const Duration(hours: 24)), midi), isTrue);
      expect(due(midi.add(const Duration(hours: 1)), midi), isTrue);
    });
  });

  group('réglages', () {
    test('la vérification est activée par défaut et se désactive', () async {
      final service = creer();
      expect(await service.chargerVerificationActivee(), isTrue);
      await service.enregistrerVerificationActivee(false);
      expect(await service.chargerVerificationActivee(), isFalse);
    });
  });

  group('verifier', () {
    test('propose une version plus récente et enregistre la date', () async {
      client.release = _release('0.5.0');
      final resultat = await creer().verifier();
      expect(resultat, isA<NouvelleVersionDisponible>());
      final nouvelle = resultat as NouvelleVersionDisponible;
      expect(nouvelle.release.version.toString(), '0.5.0');
      expect(nouvelle.estTelechargeable, isTrue);
      expect(nouvelle.estIgnoree, isFalse);
      expect(await creer().chargerDerniereVerification(), maintenant);
    });

    test('compare numériquement (0.10.0 plus récente que 0.9.9)', () async {
      client.release = _release('0.10.0');
      final resultat = await creer(version: '0.9.9').verifier();
      expect(resultat, isA<NouvelleVersionDisponible>());
    });

    test('une version de test X.Y.Z-test est à jour face à X.Y.Z', () async {
      client.release = _release('0.4.0');
      final resultat = await creer(version: '0.4.0-test').verifier();
      expect(resultat, isA<ApplicationAJour>());
    });

    test('un dépôt sans release est considéré à jour', () async {
      client.release = null;
      final resultat = await creer().verifier();
      expect(resultat, isA<ApplicationAJour>());
      expect((resultat as ApplicationAJour).derniereVersion, isNull);
    });

    test(
      'signale une release sans installateur comme non téléchargeable',
      () async {
        client.release = _release('0.5.0', telechargeable: false);
        final resultat = await creer().verifier() as NouvelleVersionDisponible;
        expect(resultat.estTelechargeable, isFalse);
      },
    );

    test('ne demande rien si la vérification est désactivée', () async {
      final service = creer();
      await service.enregistrerVerificationActivee(false);
      final resultat = await service.verifier();
      expect(resultat, isA<VerificationNonFaite>());
      expect(
        (resultat as VerificationNonFaite).raison,
        RaisonNonVerification.desactivee,
      );
      expect(client.appelsVersion, 0);
    });

    test('une seule vérification par 24 h, sauf si elle est forcée', () async {
      client.release = _release('0.4.0');
      final service = creer();
      await service.verifier();
      maintenant = maintenant.add(const Duration(hours: 23));
      final resultat = await service.verifier();
      expect(
        (resultat as VerificationNonFaite).raison,
        RaisonNonVerification.tropRecente,
      );
      expect(client.appelsVersion, 1);
      await service.verifier(forcee: true);
      expect(client.appelsVersion, 2);
      maintenant = maintenant.add(const Duration(hours: 25));
      await service.verifier();
      expect(client.appelsVersion, 3);
    });

    test('la vérification forcée passe outre le réglage désactivé', () async {
      client.release = _release('0.5.0');
      final service = creer();
      await service.enregistrerVerificationActivee(false);
      expect(
        await service.verifier(forcee: true),
        isA<NouvelleVersionDisponible>(),
      );
    });

    test(
      "une version ignorée n'est plus proposée, une plus récente l'est",
      () async {
        client.release = _release('0.5.0');
        final service = creer();
        await service.ignorerVersion(const VersionApplication(0, 5, 0));
        expect(await service.verifier(), isA<ApplicationAJour>());
        final forcee =
            await service.verifier(forcee: true) as NouvelleVersionDisponible;
        expect(forcee.estIgnoree, isTrue);
        client.release = _release('0.5.1');
        final suivante =
            await service.verifier(forcee: true) as NouvelleVersionDisponible;
        expect(suivante.estIgnoree, isFalse);
      },
    );

    test("rend la limite GitHub avec l'heure de reprise sans lever", () async {
      final reprise = DateTime.utc(2026, 11, 27, 13);
      client.erreur = ErreurLimiteGithub(
        'https://api.github.com',
        'Limite de requêtes GitHub atteinte : nouvel essai possible à 14:00',
        heureReprise: reprise,
      );
      final resultat = await creer().verifier();
      expect(resultat, isA<EchecVerificationMiseAJour>());
      expect((resultat as EchecVerificationMiseAJour).heureReprise, reprise);
      expect(resultat.message, contains('Limite'));
      expect(await creer().chargerDerniereVerification(), isNull);
    });

    test(
      'une erreur réseau est rendue lisible et retentée après 1 h',
      () async {
        client.erreur = const ErreurSource('https://api.github.com', 'Délai');
        final service = creer();
        final resultat = await service.verifier();
        expect(
          (resultat as EchecVerificationMiseAJour).message,
          contains('Délai'),
        );
        expect(
          (await service.verifier() as VerificationNonFaite).raison,
          RaisonNonVerification.echecRecent,
        );
        client.erreur = null;
        client.release = _release('0.4.0');
        maintenant = maintenant.add(const Duration(hours: 1));
        expect(await service.verifier(), isA<ApplicationAJour>());
        expect(client.appelsVersion, 2);
      },
    );

    test('une erreur inattendue ne lève pas', () async {
      client.erreur = StateError('bogue');
      expect(await creer().verifier(), isA<EchecVerificationMiseAJour>());
    });

    test("une version d'application illisible ne demande rien", () async {
      final resultat = await creer(version: 'inconnue').verifier();
      expect(resultat, isA<EchecVerificationMiseAJour>());
      expect(client.appelsVersion, 0);
    });

    test('deux vérifications simultanées partagent la même requête', () async {
      client.release = _release('0.5.0');
      client.attente = Completer<void>();
      final service = creer();
      final premiere = service.verifier(forcee: true);
      final seconde = service.verifier(forcee: true);
      client.attente!.complete();
      expect(identical(await premiere, await seconde), isTrue);
      expect(client.appelsVersion, 1);
    });
  });

  group('telecharger', () {
    test('télécharge dans le dossier dédié et nettoie les anciens', () async {
      final service = creer();
      final dossier = service.dossierTelechargement;
      await dossier.create(recursive: true);
      final ancien = File(
        '${dossier.path}/bibliotheque_perso-0.3.3-installation.exe',
      );
      final partiel = File(
        '${dossier.path}/bibliotheque_perso-0.4.0-installation.exe.part',
      );
      final autre = File('${dossier.path}/notes.txt');
      for (final f in <File>[ancien, partiel, autre]) {
        await f.writeAsString('x');
      }
      final progressions = <int>[];
      final fichier = await service.telecharger(
        _release('0.5.0'),
        progression: (recus, total) => progressions.add(recus),
      );
      expect(
        fichier.path,
        endsWith(
          '${ServiceMiseAJourApplication.nomDossierTelechargement}'
          '${Platform.pathSeparator}bibliotheque_perso-0.5.0-installation.exe',
        ),
      );
      expect(await fichier.exists(), isTrue);
      expect(
        client.nomEmpreinteDemande,
        'bibliotheque_perso-0.5.0-installation.exe',
      );
      expect(progressions, <int>[3]);
      expect(await ancien.exists(), isFalse);
      expect(await partiel.exists(), isFalse);
      expect(await autre.exists(), isTrue);
    });

    test("refuse une release sans installateur vérifiable", () async {
      await expectLater(
        creer().telecharger(_release('0.5.0', telechargeable: false)),
        throwsA(isA<ErreurService>()),
      );
      expect(client.appelsEmpreinte, 0);
    });

    test(
      'une empreinte incorrecte devient une ErreurService lisible',
      () async {
        client.erreurTelechargement = const ErreurEmpreinteInstallateur(
          'https://github.com',
          'refusé',
          empreinteAttendue: 'a',
          empreinteObtenue: 'b',
        );
        await expectLater(
          creer().telecharger(_release('0.5.0')),
          throwsA(
            isA<ErreurService>().having(
              (e) => e.message,
              'message',
              contains('abîmé'),
            ),
          ),
        );
      },
    );

    test(
      'deux téléchargements simultanés partagent la même connexion',
      () async {
        client.attente = Completer<void>();
        final service = creer();
        final premier = service.telecharger(_release('0.5.0'));
        final second = service.telecharger(_release('0.5.0'));
        client.attente!.complete();
        expect((await premier).path, (await second).path);
        expect(client.appelsTelechargement, 1);
      },
    );
  });

  group('lancerInstallation', () {
    test(
      'lance sous Windows le fichier téléchargé avec les bons paramètres',
      () async {
        final service = creer();
        final release = _release('0.5.0');
        final fichier = await service.telecharger(release);
        final resultat = await service.lancerInstallation(
          fichier,
          release: release,
        );
        expect(resultat.lance, isTrue);
        expect(lancements, hasLength(1));
        expect(lancements.single.first, fichier.absolute.path);
        expect(lancements.single.sublist(1), <String>[
          '/ACTION=METTREAJOUR',
          '/SILENT',
          '/NORESTART',
          '/RELANCER',
        ]);
      },
    );

    test("refuse un fichier hors du dossier dédié", () async {
      final service = creer();
      final release = _release('0.5.0');
      final etranger = File(
        '${temporaire.path}/bibliotheque_perso-0.5.0-installation.exe',
      );
      await etranger.writeAsString('x');
      final resultat = await service.lancerInstallation(
        etranger,
        release: release,
      );
      expect(resultat.lance, isFalse);
      expect(resultat.messageErreur, isNotNull);
      expect(lancements, isEmpty);
    });

    test(
      'hors Windows, renvoie la page de la release sans rien lancer',
      () async {
        final service = creer(estWindows: false);
        final release = _release('0.5.0');
        expect(service.installationAutomatiquePossible, isFalse);
        final resultat = await service.lancerInstallation(
          File('x.exe'),
          release: release,
        );
        expect(resultat.lance, isFalse);
        expect(resultat.urlPage.toString(), release.urlPage);
        expect(lancements, isEmpty);
      },
    );

    test("un échec du lancement est rendu sans lever", () async {
      final release = _release('0.5.0');
      final service = ServiceMiseAJourApplication(
        depot,
        client,
        versionApplication: '0.4.0',
        dossierTemporaire: temporaire,
        estWindows: true,
        lanceur: (_, _) async => throw const ProcessException('x', []),
      );
      final fichier = await service.telecharger(release);
      final resultat = await service.lancerInstallation(
        fichier,
        release: release,
      );
      expect(resultat.lance, isFalse);
      expect(resultat.messageErreur, isNotNull);
    });
  });
}
