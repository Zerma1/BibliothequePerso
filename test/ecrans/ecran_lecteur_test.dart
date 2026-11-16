// Tests de EcranLecteur avec de faux services (pages PNG en mémoire).
import 'package:bibliotheque_perso/ecrans/ecran_lecteur.dart';
import 'package:bibliotheque_perso/etat/etat_lecteur.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceTelechargement telechargement;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    telechargement = FauxServiceTelechargement(bibliotheque);
    bibliotheque.sources.add(
      const Source(
        id: 1,
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
      ),
    );
    bibliotheque.ajouterTitreDeTest(
      'Titre',
      idSource: 1,
      chapitres: const <Chapitre>[
        Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
        Chapitre(id: 2, urlChapitre: 'u2', nom: 'Deux', numero: 2),
        Chapitre(id: 3, urlChapitre: 'u3', nom: 'Trois', numero: 3),
      ],
    );
    telechargement
      ..ajouterChapitreTelecharge(1, nombrePages: 2)
      ..ajouterChapitreTelecharge(2, nombrePages: 1);
  });

  Future<void> afficher(WidgetTester tester, int idChapitre) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        ChangeNotifierProvider<EtatLecteur>(
          create: (_) => EtatLecteur(
            serviceBibliotheque: bibliotheque,
            serviceTelechargement: telechargement,
            idTitre: 1,
            idChapitre: idChapitre,
          )..charger(),
          child: const EcranLecteur(),
        ),
        bibliotheque: bibliotheque,
        telechargement: telechargement,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('affiche les pages, la position et le zoom', (tester) async {
    await afficher(tester, 1);

    expect(find.text('Un'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.text(Textes.pageSurTotal(1, 2)), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip(Textes.agrandir), findsOneWidget);
    // Premier chapitre : pas de précédent.
    final precedent = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_previous),
    );
    expect(precedent.onPressed, isNull);
  });

  testWidgets('arrivé en bas, le chapitre est marqué lu et le pied propose '
      'le suivant', (tester) async {
    await afficher(tester, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    // Images bornées plutôt que pumpAndSettle : le décodage des pages (mis
    // en cache par le test précédent) ne se termine pas en temps simulé.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(telechargement.reglesAppliquees, <int>[1]);
    expect(bibliotheque.chapitresParTitre[1]!.first.estLu, isTrue);
    expect(find.text(Textes.finDuChapitre), findsOneWidget);
    expect(find.text(Textes.creditMangaDexComplet), findsOneWidget);

    await tester.tap(find.textContaining('${Textes.chapitreSuivant} :'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Deux'), findsOneWidget);
  });

  testWidgets('chapitre non téléchargé : télécharger ou ouvrir sur le site', (
    tester,
  ) async {
    await afficher(tester, 3);

    expect(find.text(Textes.lecteurNonTelecharge), findsOneWidget);
    expect(find.text(Textes.ouvrirSurLeSite), findsOneWidget);
    await tester.tap(find.text(Textes.telecharger));
    await tester.pumpAndSettle();
    expect(telechargement.journal, contains('telecharger:3'));
    expect(find.textContaining('file d\'attente'), findsOneWidget);
  });

  testWidgets('chapitre texte lisible', (tester) async {
    telechargement.textes[2] = '<p>Il était une fois.</p>';
    telechargement.pages.remove(2);
    await afficher(tester, 2);

    expect(find.text('Il était une fois.'), findsOneWidget);
  });
}
