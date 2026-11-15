// Tests de CarteTitre, ImageCouverture et PastilleCategorie.
import 'package:bibliotheque_perso/etat/etat_couvertures.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/widgets/carte_titre.dart';
import 'package:bibliotheque_perso/widgets/pastille_categorie.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/outils_tests_etat.dart';

/// Affiche [enfant] dans une petite zone, avec l'accès aux couvertures.
Widget _cadre(Widget enfant, FauxServiceBibliotheque service) {
  return Provider<EtatCouvertures>(
    create: (_) => EtatCouvertures(service),
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 180, height: 290, child: enfant)),
      ),
    ),
  );
}

void main() {
  testWidgets('affiche le nom et le badge des non-lus', (tester) async {
    final service = FauxServiceBibliotheque();
    var appuis = 0;
    await tester.pumpWidget(
      _cadre(
        CarteTitre(
          titre: Titre(
            id: 1,
            urlTitre: 'https://exemple.test/t',
            nom: 'Mon manga',
            nombreChapitresNonLus: 5,
          ),
          surAppui: () => appuis++,
        ),
        service,
      ),
    );
    await tester.pump();

    expect(find.text('Mon manga'), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // Sans adresse de couverture : espace réservé, aucune requête.
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(service.couverturesDemandees, isEmpty);

    await tester.tap(find.byType(CarteTitre));
    expect(appuis, 1);
  });

  testWidgets('pas de badge quand tout est lu', (tester) async {
    await tester.pumpWidget(
      _cadre(
        CarteTitre(
          titre: Titre(urlTitre: 'https://exemple.test/t', nom: 'Lu'),
        ),
        FauxServiceBibliotheque(),
      ),
    );
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets(
    'la couverture passe par le service et affiche un espace réservé en cas '
    'd\'erreur',
    (tester) async {
      final service = FauxServiceBibliotheque();
      await tester.pumpWidget(
        _cadre(
          CarteTitre(
            titre: Titre(
              urlTitre: 'https://exemple.test/t',
              nom: 'Sans réseau',
              urlCouverture: 'https://exemple.test/c.jpg',
            ),
          ),
          service,
        ),
      );
      await tester.pump();

      expect(service.couverturesDemandees, <String>[
        'https://exemple.test/c.jpg',
      ]);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('affiche les octets reçus avec Image.memory', (tester) async {
    final service = FauxServiceBibliotheque()..octetsCouverture = pngMinimal;
    await tester.pumpWidget(
      _cadre(
        CarteTitre(
          titre: Titre(
            urlTitre: 'https://exemple.test/t',
            nom: 'Avec image',
            urlCouverture: 'https://exemple.test/c.png',
          ),
        ),
        service,
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
  });

  testWidgets('PastilleCategorie : étiquette ou puce de filtre', (
    tester,
  ) async {
    bool? choix;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const PastilleCategorie(nom: 'action'),
              PastilleCategorie(
                nom: 'gore',
                surSelection: (valeur) => choix = valeur,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Action'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Action'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Gore'), findsOneWidget);
    await tester.tap(find.text('Gore'));
    expect(choix, isTrue);
  });
}
