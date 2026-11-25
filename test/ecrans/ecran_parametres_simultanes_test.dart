// Tests de la jauge « Téléchargements simultanés » (Paramètres →
// Téléchargements) et de son état.
import 'package:bibliotheque_perso/ecrans/ecran_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/outils_tests_etat.dart';
import '../widgets/outils_sections_pliables.dart';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceParametres parametres;
  late FauxServiceTelechargement telechargement;

  setUp(() {
    bibliotheque = FauxServiceBibliotheque();
    parametres = FauxServiceParametres()..telechargementsSimultanes = 5;
    telechargement = FauxServiceTelechargement(bibliotheque);
  });

  test('état : lecture, aperçu sans enregistrement, enregistrement borné '
      'puis relance de la file', () async {
    final etat = EtatParametres(parametres, telechargement);
    await etat.charger();
    expect(etat.telechargementsSimultanes, 5);

    etat.previsualiserTelechargementsSimultanes(12);
    expect(etat.telechargementsSimultanes, 12);
    expect(parametres.telechargementsSimultanes, 5);

    final resultat = await etat.modifierTelechargementsSimultanes(40);
    expect(resultat.donnee, EtatParametres.maximumTelechargementsSimultanes);
    expect(parametres.telechargementsSimultanes, 32);
    expect(etat.telechargementsSimultanes, 32);
    expect(telechargement.nombreLancementsTraitement, 1);
  });

  testWidgets('jauge : valeur affichée, phrase explicative, enregistrée au '
      'lâcher', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      envelopper(
        const EcranParametres(),
        bibliotheque: bibliotheque,
        parametres: parametres,
        telechargement: telechargement,
      ),
    );
    await tester.pump();
    await tester.pump();
    await deplierParametres(tester);

    const cle = 'jauge.simultanes';
    final jaugeEntiere = find.byKey(const ValueKey<String>(cle));
    expect(
      find.descendant(
        of: jaugeEntiere,
        matching: find.text(Textes.libelleTelechargementsSimultanes),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: jaugeEntiere, matching: find.text('5')),
      findsOneWidget,
    );
    expect(
      find.text(Textes.explicationTelechargementsSimultanes),
      findsOneWidget,
    );
    // Un cran par valeur, de 1 à 32 : 31 intervalles.
    final jauge = tester.widget<Slider>(curseurJauge(cle));
    expect(jauge.divisions, 31);

    // Glissement jusqu'au bout droit de la jauge.
    await tester.ensureVisible(curseurJauge(cle));
    await tester.pumpAndSettle();
    await tester.drag(curseurJauge(cle), const Offset(1000, 0));
    await tester.pumpAndSettle();

    expect(parametres.telechargementsSimultanes, 32);
    expect(
      find.descendant(of: jaugeEntiere, matching: find.text('32')),
      findsOneWidget,
    );
    expect(telechargement.nombreLancementsTraitement, 1);

    // « − » : une valeur de moins, enregistrée aussitôt.
    await tester.tap(boutonJauge(cle, plus: false));
    await tester.pumpAndSettle();
    expect(parametres.telechargementsSimultanes, 31);
  });
}
