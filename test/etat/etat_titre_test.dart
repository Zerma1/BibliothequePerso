// Tests de EtatTitre avec les vrais services, une base en mémoire et les
// réponses MangaDex enregistrées.
import 'dart:async';

import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../donnees/outils_tests_donnees.dart';
import 'outils_tests_etat.dart';

void main() {
  late ServicesDeTest services;
  late EtatTitre etat;

  setUp(() async {
    services = await creerServicesReels();
    final ajout = await services.bibliotheque.ajouterTitreDepuisUrl(
      urlTitreReference,
    );
    etat = EtatTitre(services.bibliotheque, ajout.titre.id!);
    await etat.charger();
  });

  tearDown(() async {
    etat.dispose();
    await services.fermer();
  });

  test('charge la fiche, la source MangaDex et les catégories', () {
    expect(etat.erreur, isNull);
    expect(etat.titre!.nom, contains('Shinigami'));
    expect(etat.titre!.titresAlternatifs, hasLength(6));
    expect(etat.estMangaDex, isTrue);
    expect(
      etat.categories.map((categorie) => categorie.nom),
      containsAll(<String>['gore', 'action', 'fantasy']),
    );
    expect(etat.listes, isNotEmpty);
    expect(etat.idsListesDuTitre, isEmpty);
  });

  test('trie les chapitres par numéro décroissant', () {
    final numeros = etat.chapitres.map((chapitre) => chapitre.numero).toList();
    expect(numeros, isNotEmpty);
    for (var i = 1; i < numeros.length; i++) {
      expect(numeros[i - 1], greaterThanOrEqualTo(numeros[i]));
    }
  });

  test('marque un chapitre lu puis tous lus et non lus', () async {
    final total = etat.chapitres.length;
    expect(etat.nombreNonLus, total);

    final resultat = await etat.marquerLu(etat.chapitres.first);
    expect(resultat.estReussi, isTrue);
    expect(etat.chapitres.first.estLu, isTrue);
    expect(etat.nombreNonLus, total - 1);
    expect(etat.titre!.nombreChapitresNonLus, total - 1);

    await etat.marquerTousLus();
    expect(etat.nombreNonLus, 0);

    await etat.marquerTousLus(estLu: false);
    expect(etat.nombreNonLus, total);

    // L'état local correspond à la base.
    await etat.charger();
    expect(etat.nombreNonLus, total);
  });

  test('ajoute puis retire le titre d\'une liste', () async {
    final suivis = etat.listes.firstWhere(
      (liste) => liste.nom == nomListeSuivis,
    );

    await etat.ajouterALaListe(suivis.id!);
    expect(etat.idsListesDuTitre, contains(suivis.id));
    final enBase = await services.bibliotheque.chargerListesDuTitre(
      etat.idTitre,
    );
    expect(enBase.map((liste) => liste.id), contains(suivis.id));

    await etat.retirerDeLaListe(suivis.id!);
    expect(etat.idsListesDuTitre, isEmpty);
  });

  test('actualise sans compter les chapitres déjà connus', () async {
    final resultat = await etat.actualiser();

    expect(resultat.estReussi, isTrue);
    expect(resultat.donnee, 0);
    expect(etat.estEnActualisation, isFalse);
  });

  test('une actualisation impossible devient une erreur de site', () async {
    services.siteEnPanne = true;
    final avant = etat.chapitres.length;

    final resultat = await etat.actualiser();

    expect(resultat.erreur!.nature, NatureErreur.site);
    expect(etat.chapitres, hasLength(avant));
    expect(etat.erreur, isNull);
  });

  test(
    'un titre supprimé pendant l\'actualisation est signalé, sans '
    'chargement infini',
    () async {
      final faux = FauxServiceBibliotheque()..ajouterTitreDeTest('Éphémère');
      faux.avantAjout = faux.titres.clear;
      final etatFaux = EtatTitre(faux, 1);
      await etatFaux.charger();
      expect(etatFaux.titre, isNotNull);

      final resultat = await etatFaux.actualiser();

      expect(resultat.erreur!.nature, NatureErreur.introuvable);
      expect(etatFaux.erreur!.nature, NatureErreur.introuvable);
      expect(etatFaux.titre, isNull);
      expect(etatFaux.estEnActualisation, isFalse);
      etatFaux.dispose();
    },
  );

  test('un chargement périmé n\'écrase pas le plus récent', () async {
    final faux = FauxServiceBibliotheque()..ajouterTitreDeTest('Premier');
    final retenue = Completer<void>();
    faux.retenue = retenue;
    final etatFaux = EtatTitre(faux, 1);

    final ancien = etatFaux.charger();
    faux.retenue = null;
    faux.titres[0] = faux.titres[0].copierAvec(nom: 'Renommé');
    await etatFaux.charger();
    expect(etatFaux.titre!.nom, 'Renommé');

    // L'ancien chargement se termine après : sa réponse est ignorée.
    faux.titres[0] = faux.titres[0].copierAvec(nom: 'Périmé');
    retenue.complete();
    await ancien;
    expect(etatFaux.titre!.nom, 'Renommé');
    expect(etatFaux.estEnChargement, isFalse);
    etatFaux.dispose();
  });

  test('un titre supprimé est signalé comme introuvable', () async {
    await services.bibliotheque.supprimerTitre(etat.idTitre);

    await etat.charger();

    expect(etat.erreur!.nature, NatureErreur.introuvable);
    expect(etat.titre, isNull);
  });
}
