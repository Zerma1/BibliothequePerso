// Tests de EcranNavigateur : la vraie vue web est remplacée par un faux
// (aucune page chargée, aucun réseau) ; les événements de la page sont
// simulés par le test.
import 'package:bibliotheque_perso/ecrans/ecran_navigateur.dart';
import 'package:bibliotheque_perso/etat/etat_navigateur.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:bibliotheque_perso/widgets/vue_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';
import '../etat/outils_tests_navigateur.dart';

/// Fausse vue web : donne la fausse page à l'écran dès sa création.
class _FausseVueWeb extends StatefulWidget {
  const _FausseVueWeb(this.parametres, this.page);

  final ParametresVueWeb parametres;
  final FaussePage page;

  @override
  State<_FausseVueWeb> createState() => _EtatFausseVueWeb();
}

class _EtatFausseVueWeb extends State<_FausseVueWeb> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.parametres.surCreation(widget.page),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.white, child: Text('FAUSSE PAGE'));
}

void main() {
  const adresse1 = 'https://site.test/manga/titre/chapitre-1';

  late FauxServiceLectureWeb service;
  late FauxServiceBibliotheque bibliotheque;
  late FaussePage page;
  late ParametresVueWeb parametres;
  late EtatNavigateur etat;

  setUp(() {
    service = FauxServiceLectureWeb();
    service.chapitresParAdresse[adresse1] = chapitreDeTest(1, 1);
    bibliotheque = FauxServiceBibliotheque()..ajouterTitreDeTest('Mon titre');
    page = FaussePage();
  });

  Future<void> afficher(WidgetTester tester, {double largeur = 1000}) async {
    tester.view.physicalSize = Size(largeur, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    etat = EtatNavigateur(
      service,
      adresseInitiale: adresse1,
      idTitre: 1,
      serviceBibliotheque: bibliotheque,
      attendre: (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<EtatNavigateur>.value(
          value: etat,
          child: EcranNavigateur(
            constructeurVueWeb: (p) {
              parametres = p;
              return _FausseVueWeb(p, page);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    // Page « chargée » : sinon la barre de chargement indéterminée tourne
    // sans fin (pumpAndSettle n'aboutirait jamais).
    parametres.surProgression(100);
    await tester.pump();
  }

  testWidgets('chapitre reconnu : repère et enregistrement', (tester) async {
    await afficher(tester);
    expect(find.text('FAUSSE PAGE'), findsOneWidget);
    expect(parametres.adresseInitiale, adresse1);

    parametres.surFinChargement(adresse1);
    await tester.pumpAndSettle();
    expect(
      find.text(
        Textes.repereChapitreWeb(
          numero: 1,
          nomTitre: 'Mon titre',
          estLu: false,
        ),
      ),
      findsOneWidget,
    );

    page.images['https://img.test/1.png'] = octetsPng;
    await tester.tap(find.text(Textes.enregistrerCeChapitre));
    await tester.pumpAndSettle();

    expect(service.nombreEnregistrements, 1);
    expect(find.text(Textes.chapitreWebEnregistre), findsOneWidget);
    expect(
      find.text(
        Textes.repereChapitreWeb(
          numero: 1,
          nomTitre: 'Mon titre',
          estLu: false,
          estTelecharge: true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('images protégées : message clair du service', (tester) async {
    await afficher(tester);
    parametres.surFinChargement(adresse1);
    await tester.pumpAndSettle();
    page.canvas = 2;

    await tester.tap(find.text(Textes.enregistrerCeChapitre));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Ce site protège ses images : elles ne peuvent pas être '
        'enregistrées.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('page non reconnue : explication et bouton grisé', (
    tester,
  ) async {
    await afficher(tester);
    parametres.surAdresse('https://site.test/accueil');
    await tester.pumpAndSettle();

    expect(find.text(Textes.pageNonReconnue), findsOneWidget);
    final bouton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(Textes.enregistrerCeChapitre),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('barre d\'adresse : adresse suivie, saisie ouverte ou refusée', (
    tester,
  ) async {
    await afficher(tester);
    parametres.surAdresse('https://site.test/autre');
    await tester.pumpAndSettle();
    expect(find.text('https://site.test/autre'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'deux mots');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text(Textes.adresseNavigateurInvalide), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'exemple.com');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(page.chargees, <String>['https://exemple.com']);
  });

  testWidgets('navigation : précédente active selon l\'historique, '
      'recharger', (tester) async {
    await afficher(tester);
    parametres.surAdresse(adresse1);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(Textes.pagePrecedente));
    await tester.tap(find.byTooltip(Textes.rechargerPage));
    await tester.pump();
    expect(page.commandes, <String>['reculer', 'recharger']);
    // Page suivante : pas d'historique en avant.
    final suivante = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_forward),
    );
    expect(suivante.onPressed, isNull);
    expect(find.byTooltip(Textes.ouvrirNavigateurExterne), findsOneWidget);
  });

  testWidgets('erreur de chargement : message et « Réessayer »', (
    tester,
  ) async {
    await afficher(tester);
    parametres.surErreur('Hôte introuvable');
    await tester.pumpAndSettle();

    expect(
      find.text(Textes.erreurChargementPage('Hôte introuvable')),
      findsOneWidget,
    );
    await tester.tap(find.text(Textes.reessayer));
    await tester.pump();
    expect(page.commandes, <String>['recharger']);
  });

  testWidgets('écran étroit : recharger et navigateur externe dans le menu', (
    tester,
  ) async {
    await afficher(tester, largeur: 400);
    expect(find.byTooltip(Textes.rechargerPage), findsNothing);

    await tester.tap(find.byTooltip(Textes.autresActions));
    await tester.pumpAndSettle();
    expect(find.text(Textes.ouvrirNavigateurExterne), findsOneWidget);
    await tester.tap(find.text(Textes.rechargerPage));
    await tester.pumpAndSettle();
    expect(page.commandes, <String>['recharger']);
  });

  testWidgets('sans navigateur intégré (Linux) : jamais d\'écran intégré', (
    tester,
  ) async {
    forcerNavigateurIntegrePossible = false;
    addTearDown(() => forcerNavigateurIntegrePossible = null);
    await tester.pumpWidget(
      Provider<FabriqueEtatNavigateur>(
        create: (_) => FabriqueEtatNavigateur(service),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => EcranNavigateur.ouvrir(context, adresse1),
                child: Text(
                  EcranNavigateur.estDisponible(context) ? 'oui' : 'non',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('non'), findsOneWidget);
    await tester.tap(find.text('non'));
    await tester.pumpAndSettle();
    expect(find.byType(EcranNavigateur), findsNothing);
  });
}
