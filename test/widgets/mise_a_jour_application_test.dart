// Tests de la mise à jour de l'application côté interface : état, bandeau
// de l'accueil et section des Paramètres, avec un faux service (aucun
// réseau, aucun processus lancé).
import 'dart:async';
import 'dart:io';

import 'package:bibliotheque_perso/etat/etat_mise_a_jour_application.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_mise_a_jour_application.dart';
import 'package:bibliotheque_perso/widgets/mise_a_jour_application.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Faux service : résultats réglables, appels notés.
class FauxServiceMiseAJour implements ServiceMiseAJourApplication {
  FauxServiceMiseAJour({this.estWindows = true});

  final bool estWindows;
  final List<String> appels = <String>[];
  ResultatVerificationMiseAJour resultat = const ApplicationAJour();
  bool verificationActivee = true;
  DateTime? derniere;
  Object? erreurTelechargement;
  Completer<void>? attenteTelechargement;
  ResultatLancementInstallation lancement = const ResultatLancementInstallation(
    lance: true,
  );
  final List<VersionApplication> ignorees = <VersionApplication>[];

  @override
  bool get installationAutomatiquePossible => estWindows;

  @override
  Future<void> nettoyerInstallateurs() async => appels.add('nettoyer');

  @override
  Future<bool> chargerVerificationActivee() async => verificationActivee;

  @override
  Future<void> enregistrerVerificationActivee(bool active) async {
    appels.add('reglage $active');
    verificationActivee = active;
  }

  @override
  Future<DateTime?> chargerDerniereVerification() async => derniere;

  @override
  Future<ResultatVerificationMiseAJour> verifier({bool forcee = false}) async {
    appels.add('verifier $forcee');
    return resultat;
  }

  @override
  Future<void> ignorerVersion(VersionApplication version) async =>
      ignorees.add(version);

  @override
  Future<File> telecharger(
    ReleaseApplication release, {
    ProgressionTelechargement? progression,
  }) async {
    appels.add('telecharger');
    progression?.call(50, 100);
    await attenteTelechargement?.future;
    final erreur = erreurTelechargement;
    if (erreur != null) throw erreur;
    return File('installateur.exe');
  }

  @override
  Future<ResultatLancementInstallation> lancerInstallation(
    File installateur, {
    required ReleaseApplication release,
  }) async {
    appels.add('lancer');
    return lancement;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReleaseApplication _release({bool telechargeable = true}) {
  final fichier = FichierRelease(
    nom: 'f',
    url: Uri.parse('https://github.com/exemple/depot/releases/download/f'),
    taille: 100,
  );
  return ReleaseApplication(
    etiquette: 'v9.1.0',
    version: VersionApplication.analyser('9.1.0')!,
    nom: null,
    notes: 'Correction du lecteur.',
    datePublication: null,
    urlPage: 'https://github.com/exemple/depot/releases/tag/v9.1.0',
    installateur: telechargeable ? fichier : null,
    fichierEmpreinte: telechargeable ? fichier : null,
  );
}

void main() {
  late FauxServiceMiseAJour service;
  late EtatMiseAJourApplication etat;
  late int fermetures;

  void creer({bool estWindows = true}) {
    service = FauxServiceMiseAJour(estWindows: estWindows);
    fermetures = 0;
    etat = EtatMiseAJourApplication(
      service,
      quitterApplication: () async => fermetures++,
    );
  }

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<EtatMiseAJourApplication>.value(
        value: etat,
        child: MaterialApp(
          home: Scaffold(
            body: ZoneBandeauMiseAJour(
              child: ListView(
                children: const <Widget>[SectionMiseAJourApplication()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('EtatMiseAJourApplication', () {
    test('le démarrage nettoie puis vérifie sans forcer', () async {
      creer();
      service.resultat = NouvelleVersionDisponible(_release());
      await etat.demarrer();
      expect(service.appels, <String>['nettoyer', 'verifier false']);
      expect(etat.bandeauVisible, isTrue);
      expect(etat.estCharge, isTrue);
    });

    test(
      'pas de bandeau pour une version ignorée ou sans installateur',
      () async {
        creer();
        service.resultat = NouvelleVersionDisponible(
          _release(),
          estIgnoree: true,
        );
        await etat.demarrer();
        expect(etat.bandeauVisible, isFalse);
        service.resultat = NouvelleVersionDisponible(
          _release(telechargeable: false),
        );
        await etat.verifierMaintenant();
        expect(etat.bandeauVisible, isFalse);
      },
    );

    test('hors Windows, la page est renvoyée sans téléchargement', () async {
      creer(estWindows: false);
      service.resultat = NouvelleVersionDisponible(_release());
      await etat.demarrer();
      final resultat = await etat.mettreAJour();
      expect(resultat.urlPage, isNotNull);
      expect(service.appels, isNot(contains('telecharger')));
      expect(fermetures, 0);
    });

    test(
      "une erreur de téléchargement est gardée et rien n'est lancé",
      () async {
        creer();
        service.resultat = NouvelleVersionDisponible(_release());
        service.erreurTelechargement = const ErreurService('Réseau absent.');
        await etat.demarrer();
        final resultat = await etat.mettreAJour();
        expect(resultat.erreur?.detail, 'Réseau absent.');
        expect(etat.erreurMiseAJour, isNotNull);
        expect(etat.estEnTelechargement, isFalse);
        expect(service.appels, isNot(contains('lancer')));
      },
    );
  });

  group('Bandeau de mise à jour', () {
    testWidgets('« Plus tard » masque le bandeau', (tester) async {
      creer();
      service.resultat = NouvelleVersionDisponible(_release());
      await etat.demarrer();
      await afficher(tester);
      expect(find.text(Textes.versionDisponible('9.1.0')), findsOneWidget);
      await tester.tap(find.text(Textes.plusTard));
      await tester.pumpAndSettle();
      expect(find.text(Textes.versionDisponible('9.1.0')), findsNothing);
    });

    testWidgets('« Ignorer cette version » enregistre la version', (
      tester,
    ) async {
      creer();
      service.resultat = NouvelleVersionDisponible(_release());
      await etat.demarrer();
      await afficher(tester);
      await tester.tap(find.text(Textes.ignorerCetteVersion));
      await tester.pumpAndSettle();
      expect(service.ignorees.single.toString(), '9.1.0');
      expect(find.text(Textes.versionDisponible('9.1.0')), findsNothing);
      expect(find.text(Textes.versionIgnoree('9.1.0')), findsOneWidget);
    });

    testWidgets('les notes de version sont affichées', (tester) async {
      creer();
      service.resultat = NouvelleVersionDisponible(_release());
      await etat.demarrer();
      await afficher(tester);
      await tester.tap(find.text(Textes.notesDeVersion).first);
      await tester.pumpAndSettle();
      expect(find.text('Correction du lecteur.'), findsOneWidget);
      expect(find.text(Textes.ouvrirPageVersion), findsOneWidget);
      await tester.tap(find.text(Textes.fermer));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('« Mettre à jour » : confirmation, progression, lancement puis '
        'fermeture', (tester) async {
      creer();
      service.resultat = NouvelleVersionDisponible(_release());
      service.attenteTelechargement = Completer<void>();
      await etat.demarrer();
      await afficher(tester);
      await tester.tap(find.widgetWithText(FilledButton, Textes.mettreAJour));
      await tester.pumpAndSettle();
      expect(find.text(Textes.confirmationMiseAJour), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(Textes.mettreAJour),
        ),
      );
      await tester.pump();
      await tester.pump();
      // Téléchargement en cours : la barre remplace les boutons.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.text(Textes.telechargementMiseAJour('9.1.0', 0.5)),
        findsOneWidget,
      );
      expect(find.text(Textes.plusTard), findsNothing);
      service.attenteTelechargement!.complete();
      await tester.pumpAndSettle();
      expect(
        service.appels,
        containsAllInOrder(<String>['telecharger', 'lancer']),
      );
      expect(fermetures, 1);
    });

    testWidgets("un échec de lancement affiche l'erreur sans fermer", (
      tester,
    ) async {
      creer();
      service.resultat = NouvelleVersionDisponible(_release());
      service.lancement = const ResultatLancementInstallation(
        messageErreur: "L'installateur n'a pas pu être lancé.",
      );
      await etat.demarrer();
      await afficher(tester);
      await tester.tap(find.widgetWithText(FilledButton, Textes.mettreAJour));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(Textes.mettreAJour),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("L'installateur n'a pas pu être lancé."),
        findsOneWidget,
      );
      expect(fermetures, 0);
    });
  });

  group('Section des Paramètres', () {
    testWidgets('« Vérifier maintenant » force la vérification', (
      tester,
    ) async {
      creer();
      await etat.demarrer();
      await afficher(tester);
      await tester.tap(find.text(Textes.sectionMiseAJourApplication));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.verifierMaintenant));
      await tester.pumpAndSettle();
      expect(service.appels.last, 'verifier true');
      // Résultat dans la section et dans le message temporaire.
      expect(find.text(Textes.applicationAJour), findsWidgets);
    });

    testWidgets("l'échec affiche le message et l'heure de reprise", (
      tester,
    ) async {
      creer();
      await etat.demarrer();
      final reprise = DateTime.utc(2026, 11, 27, 13, 5);
      service.resultat = EchecVerificationMiseAJour(
        'Limite de GitHub atteinte.',
        heureReprise: reprise,
      );
      await afficher(tester);
      await tester.tap(find.text(Textes.sectionMiseAJourApplication));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Textes.verifierMaintenant));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Limite de GitHub atteinte. ${Textes.heureRepriseGithub(reprise)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets("l'interrupteur enregistre le réglage", (tester) async {
      creer();
      await etat.demarrer();
      await afficher(tester);
      await tester.tap(find.text(Textes.sectionMiseAJourApplication));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(service.appels, contains('reglage false'));
      expect(etat.verificationActivee, isFalse);
    });
  });
}
