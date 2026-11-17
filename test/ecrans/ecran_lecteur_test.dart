// Tests de EcranLecteur avec de faux services (pages PNG en mémoire).
import 'package:bibliotheque_perso/ecrans/ecran_lecteur.dart';
import 'package:bibliotheque_perso/etat/etat_lecteur.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/widgets/constantes_interface.dart';
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

  testWidgets('R4 : le pied propose le lien du chapitre externe sauté', (
    tester,
  ) async {
    bibliotheque.chapitresParTitre[1]!.insert(
      1,
      const Chapitre(
        id: 4,
        idTitre: 1,
        urlChapitre: 'u15',
        nom: 'Chez l\'éditeur',
        numero: 1.5,
        urlExterne: 'https://mangaplus.shueisha.co.jp/viewer/1',
      ),
    );
    telechargement.textes[1] = '<p>Court.</p>';
    telechargement.pages.remove(1);
    await afficher(tester, 1);

    expect(
      find.text(Textes.chapitresExternesSuivants(1, 'MANGA Plus')),
      findsOneWidget,
    );
    expect(find.textContaining(Textes.lireSur('MANGA Plus')), findsOneWidget);
    // « Chapitre suivant » saute le chapitre externe.
    expect(
      find.text('${Textes.chapitreSuivant} : ${Textes.nomChapitre('Deux', 2)}'),
      findsOneWidget,
    );
  });

  testWidgets('R4 : un chapitre externe affiche seulement son lien', (
    tester,
  ) async {
    bibliotheque.chapitresParTitre[1]!.add(
      const Chapitre(
        id: 4,
        idTitre: 1,
        urlChapitre: 'u4',
        nom: 'Quatre',
        numero: 4,
        urlExterne: 'https://mangaplus.shueisha.co.jp/viewer/4',
      ),
    );
    await afficher(tester, 4);

    expect(
      find.text(Textes.lecteurChapitreExterne('MANGA Plus')),
      findsOneWidget,
    );
    expect(find.text(Textes.telecharger), findsNothing);
    expect(telechargement.journal, isNot(contains('telecharger:4')));
  });

  testWidgets('chapitre texte lisible', (tester) async {
    telechargement.textes[2] = '<p>Il était une fois.</p>';
    telechargement.pages.remove(2);
    await afficher(tester, 2);

    expect(find.text('Il était une fois.'), findsOneWidget);
  });

  testWidgets('en remontant, une page déjà vue garde sa hauteur réelle dès '
      'sa reconstruction (retour 0.2.0-test : sauts vers le bas)', (
    tester,
  ) async {
    telechargement.ajouterChapitreTelecharge(3, nombrePages: 20);
    await afficher(tester, 3);
    // Hauteur provisoire d'une page jamais décodée (écran de 1200 px).
    final hauteurProvisoire = 1200 * fractionHauteurPageProvisoire;
    final pagesProvisoires = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == hauteurProvisoire,
    );

    /// Laisse le moteur décoder les images (hors temps simulé).
    Future<void> decoder() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    // Descente jusqu'en bas : chaque page est décodée une fois.
    for (var i = 0; i < 60; i++) {
      await decoder();
      if (find.text(Textes.finDuChapitre).evaluate().isNotEmpty) break;
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await decoder();
    }
    expect(find.text(Textes.finDuChapitre), findsOneWidget);

    // Remontée sans laisser décoder : les pages reconstruites (parfois
    // relues dans l'archive) réservent déjà leur hauteur réelle, aucune
    // n'est provisoire.
    for (var i = 0; i < 60; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      expect(pagesProvisoires, findsNothing);
    }
    expect(find.text(Textes.pageSurTotal(1, 20)), findsOneWidget);
  });
}
