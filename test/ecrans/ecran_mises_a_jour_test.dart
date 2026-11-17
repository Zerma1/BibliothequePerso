// Tests de l'onglet « Mises à jour » (EcranMisesAJour, EtatParutions) avec
// de faux services (aucune base, aucun réseau).
import 'dart:async';

import 'package:bibliotheque_perso/ecrans/ecran_accueil.dart';
import 'package:bibliotheque_perso/ecrans/ecran_mises_a_jour.dart';
import 'package:bibliotheque_perso/etat/etat_parutions.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';

/// Heure fixe des tests (dates relatives).
final DateTime _maintenant = DateTime(2026, 11, 16, 15);

/// Ligne de test : titre [nom], dernier chapitre [numero] paru [ilYA] plus
/// tôt (aucun si `null`).
ParutionTitre _ligne(
  FauxServiceBibliotheque service,
  String nom, {
  Duration? ilYA,
  double numero = 1,
  bool estLu = false,
  bool estEnAttente = false,
}) {
  final titre = service.ajouterTitreDeTest(nom);
  final date = ilYA == null ? null : _maintenant.subtract(ilYA).toUtc();
  return ParutionTitre(
    titre: titre,
    langues: const <String>['fr', 'en'],
    derniereParution: date,
    dernierChapitre: date == null
        ? null
        : Chapitre(
            id: titre.id! * 100,
            idTitre: titre.id,
            urlChapitre: 'https://exemple.test/${titre.id}',
            nom: '',
            numero: numero,
            langue: 'fr',
            estLu: estLu,
          ),
    estEnAttente: estEnAttente,
  );
}

void main() {
  late FauxServiceBibliotheque service;

  setUp(() => service = FauxServiceBibliotheque());

  Future<void> afficher(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(ecran, bibliotheque: service, maintenant: () => _maintenant),
    );
    await tester.pump();
  }

  testWidgets('chargement puis liste vide expliquée', (tester) async {
    service.retenue = Completer<void>();
    await afficher(tester, const EcranMisesAJour());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    service.retenue!.complete();
    await tester.pump();
    expect(find.text(Textes.misesAJourVide), findsOneWidget);
  });

  testWidgets('erreur puis « Réessayer »', (tester) async {
    service.erreurLecture = const ErreurService('Base occupée.');
    await afficher(tester, const EcranMisesAJour());
    expect(find.text('Base occupée.'), findsOneWidget);

    service.erreurLecture = null;
    await tester.tap(find.text(Textes.reessayer));
    await tester.pump();
    expect(find.text(Textes.misesAJourVide), findsOneWidget);
  });

  testWidgets('lignes triées, badge « Nouveau », section « En attente »', (
    tester,
  ) async {
    service.parutions = <ParutionTitre>[
      _ligne(service, 'Récent', ilYA: const Duration(hours: 1), numero: 12),
      _ligne(
        service,
        'Ancien',
        ilYA: const Duration(days: 3),
        numero: 4,
        estLu: true,
      ),
      _ligne(service, 'Sans chapitre', estEnAttente: true),
    ];
    await afficher(tester, const EcranMisesAJour());

    expect(find.text('Récent'), findsOneWidget);
    expect(
      find.text(
        Textes.dernierChapitreParu(
          'Chapitre 12',
          'fr',
          _maintenant.subtract(const Duration(hours: 1)),
          _maintenant,
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining("aujourd'hui"), findsOneWidget);
    expect(find.textContaining('il y a 3 jours'), findsOneWidget);
    // Seul le titre dont le dernier chapitre n'est pas lu a le badge.
    expect(find.text(Textes.nouveau), findsOneWidget);
    // Titres sans chapitre dans les langues : à la fin, sous un intertitre.
    expect(find.text(Textes.sectionSansParution), findsOneWidget);
    expect(
      find.textContaining(Textes.aucuneParution(const <String>['fr', 'en'])),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Sans chapitre')).dy,
      greaterThan(tester.getTopLeft(find.text(Textes.sectionSansParution)).dy),
    );
  });

  testWidgets('l\'onglet porte le nombre de titres avec une nouveauté', (
    tester,
  ) async {
    service.parutions = <ParutionTitre>[
      _ligne(service, 'Un', ilYA: const Duration(hours: 2)),
      _ligne(service, 'Deux', ilYA: const Duration(hours: 3)),
    ];
    await afficher(tester, const EcranAccueil());
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.descendant(
          of: find.byType(Badge),
          matching: find.text('2'),
        ),
      ),
      findsOneWidget,
    );

    // Choisir l'onglet relit la liste (chapitres lus depuis la
    // bibliothèque).
    final lectures = service.nombreLecturesParutions;
    await tester.tap(find.text(Textes.ongletMisesAJour));
    await tester.pumpAndSettle();
    expect(service.nombreLecturesParutions, lectures + 1);
    expect(find.text('Un'), findsWidgets);
  });

  testWidgets('une recherche de nouveaux chapitres recharge la liste', (
    tester,
  ) async {
    final misesAJour = FauxServiceMisesAJour();
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranMisesAJour(),
        bibliotheque: service,
        misesAJour: misesAJour,
      ),
    );
    await tester.pump();
    final lectures = service.nombreLecturesParutions;

    await tester.tap(find.byTooltip(Textes.rechercherNouveauxChapitres));
    await tester.pump();
    await tester.pump();
    expect(misesAJour.nombreAppels, 1);
    expect(service.nombreLecturesParutions, greaterThan(lectures));
  });

  test(
    'EtatParutions : compte les nouveautés et sépare les sections',
    () async {
      service.parutions = <ParutionTitre>[
        _ligne(service, 'A', ilYA: const Duration(hours: 1)),
        _ligne(service, 'B', ilYA: const Duration(days: 1), estLu: true),
        _ligne(service, 'C'),
      ];
      final etat = EtatParutions(service, maintenant: () => _maintenant);
      addTearDown(etat.dispose);

      await etat.charger();

      expect(etat.estCharge, isTrue);
      expect(etat.nombreNouveautes, 1);
      expect(etat.avecParution.map((l) => l.titre.nom), <String>['A', 'B']);
      expect(etat.sansParution.map((l) => l.titre.nom), <String>['C']);
      expect(etat.estVide, isFalse);
    },
  );

  test('textes : dates relatives et langues attendues', () {
    final maintenant = DateTime(2026, 11, 16, 10);
    expect(
      Textes.dateRelative(DateTime(2026, 11, 16, 1), maintenant),
      "aujourd'hui",
    );
    expect(Textes.dateRelative(DateTime(2026, 11, 15, 23), maintenant), 'hier');
    expect(
      Textes.dateRelative(DateTime(2026, 11, 12), maintenant),
      'il y a 4 jours',
    );
    expect(
      Textes.dateRelative(DateTime(2026, 10, 1), maintenant),
      Textes.formaterDate(DateTime(2026, 10, 1)),
    );
    expect(
      Textes.aucuneParution(const <String>['fr', 'en', 'pt-br']),
      'Pas encore de chapitre en français, anglais ou portugais (brésil)',
    );
    expect(Textes.aucuneParution(const <String>['fr']), endsWith('français'));
  });

  group('critère « Nouveau » (retour 0.2.0-test : titres « nouveaux » depuis '
      'le 30/10/2023)', () {
    /// Ligne dont le dernier chapitre a les dates données.
    ParutionTitre ligneDatee({
      DateTime? publication,
      DateTime? detection,
      bool estLu = false,
    }) => ParutionTitre(
      titre: Titre(id: 1, urlTitre: 'u', nom: 'n'),
      langues: const <String>['fr'],
      derniereParution: publication ?? detection,
      dernierChapitre: Chapitre(
        id: 1,
        idTitre: 1,
        urlChapitre: 'c',
        nom: '',
        numero: 1,
        langue: 'fr',
        estLu: estLu,
        datePublication: publication,
        dateDetection: detection,
      ),
    );

    test('un chapitre publié il y a des années n\'est jamais « Nouveau », '
        'même découvert aujourd\'hui (ajout du titre)', () {
      final ligne = ligneDatee(
        publication: DateTime.utc(2023, 10, 30),
        detection: _maintenant.toUtc(),
      );
      expect(EtatParutions.estNouveaute(ligne, _maintenant), isFalse);
    });

    test(
      'un chapitre non lu paru depuis moins d\'une semaine est « Nouveau »',
      () {
        final ligne = ligneDatee(
          publication: _maintenant.subtract(const Duration(days: 6)).toUtc(),
          detection: _maintenant.toUtc(),
        );
        expect(EtatParutions.estNouveaute(ligne, _maintenant), isTrue);
        expect(
          EtatParutions.estNouveaute(
            ligneDatee(
              publication: _maintenant
                  .subtract(const Duration(days: 8))
                  .toUtc(),
            ),
            _maintenant,
          ),
          isFalse,
        );
      },
    );

    test('sans date de publication, la date de découverte compte', () {
      expect(
        EtatParutions.estNouveaute(
          ligneDatee(
            detection: _maintenant.subtract(const Duration(days: 1)).toUtc(),
          ),
          _maintenant,
        ),
        isTrue,
      );
      expect(
        EtatParutions.estNouveaute(
          ligneDatee(
            detection: _maintenant.subtract(const Duration(days: 30)).toUtc(),
          ),
          _maintenant,
        ),
        isFalse,
      );
    });

    test('un chapitre lu n\'est jamais « Nouveau »', () {
      final ligne = ligneDatee(publication: _maintenant.toUtc(), estLu: true);
      expect(EtatParutions.estNouveaute(ligne, _maintenant), isFalse);
    });

    testWidgets('ni badge ni compte pour un dernier chapitre ancien non lu', (
      tester,
    ) async {
      service.parutions = <ParutionTitre>[
        _ligne(service, 'Abandonné', ilYA: const Duration(days: 750)),
        _ligne(service, 'Récent', ilYA: const Duration(hours: 5)),
      ];
      await afficher(tester, const EcranAccueil());
      await tester.tap(find.text(Textes.ongletMisesAJour));
      await tester.pumpAndSettle();

      expect(find.text(Textes.nouveau), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.descendant(
            of: find.byType(Badge),
            matching: find.text('1'),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  test('titre de test sans identifiant : aucun badge', () {
    final ligne = ParutionTitre(
      titre: Titre(urlTitre: 'u', nom: 'n'),
      langues: const <String>['fr'],
    );
    expect(ligne.aNouveaute, isFalse);
  });
}
