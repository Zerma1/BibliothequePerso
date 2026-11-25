// Tests de EtatExport avec un faux service.
import 'dart:async';

import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_export.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  late FauxServiceExport service;
  late EtatExport etat;

  setUp(() {
    service = FauxServiceExport();
    etat = EtatExport(service);
  });

  tearDown(() => etat.dispose());

  test('un export réussi renvoie le résultat et le garde', () async {
    final resultat = await etat.exporter();

    expect(resultat.estReussi, isTrue);
    expect(resultat.donnee!.nombreTitres, 12);
    expect(etat.dernierResultat?.cheminMarkdown, 'C:/exports/export.md');
    expect(etat.erreur, isNull);
    expect(etat.estEnCours, isFalse);
    expect(etat.dossierExports, 'C:/exports');
  });

  test('estEnCours vaut true pendant l\'export, avec notifications', () async {
    final retenue = Completer<void>();
    service.retenue = retenue;
    var notifications = 0;
    etat.addListener(() => notifications++);

    final enCours = etat.exporter();
    expect(etat.estEnCours, isTrue);
    retenue.complete();
    await enCours;

    expect(etat.estEnCours, isFalse);
    expect(notifications, 2);
  });

  test('une ErreurService devient un refus lisible', () async {
    service.erreur = const ErreurService('Disque plein.');

    final resultat = await etat.exporter();

    expect(resultat.estReussi, isFalse);
    expect(resultat.erreur!.nature, NatureErreur.refus);
    expect(resultat.erreur!.detail, 'Disque plein.');
    expect(etat.erreur, isNotNull);
    expect(etat.estEnCours, isFalse);
  });

  test('une ErreurBaseDeDonnees devient une erreur de base', () async {
    service.erreur = const ErreurBaseDeDonnees('Base illisible.');

    final resultat = await etat.exporter();

    expect(resultat.erreur!.nature, NatureErreur.baseDeDonnees);
  });
}
