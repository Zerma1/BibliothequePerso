// Tests de EtatTitre avec les vrais services, une base en mémoire et les
// réponses MangaDex enregistrées.
import 'dart:async';

import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/etat/outils_chapitres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
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

  test('un titre supprimé pendant l\'actualisation est signalé, sans '
      'chargement infini', () async {
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
  });

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

  test("les relectures de la file pendant un téléchargement sont "
      "regroupées", () async {
    final faux = FauxServiceBibliotheque()
      ..ajouterTitreDeTest(
        'Titre',
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
        ],
      );
    final telechargement = FauxServiceTelechargement(faux);
    final etatFaux = EtatTitre(faux, 1, serviceTelechargement: telechargement);
    addTearDown(etatFaux.dispose);
    await etatFaux.charger();
    final avant = telechargement.nombreLecturesFile;

    // Dix signaux pendant une lecture lente de la file : une lecture en
    // cours, puis une seule relecture à la fin.
    final retenue = Completer<void>();
    telechargement.retenueFile = retenue;
    for (var i = 1; i <= 10; i++) {
      telechargement.modifierLigne(
        1,
        StatutTelechargement.enCours,
        faites: i,
        total: 10,
      );
      await pumpEventQueue();
    }
    telechargement.retenueFile = null;
    retenue.complete();
    await pumpEventQueue();

    expect(telechargement.nombreLecturesFile - avant, 2);
    expect(etatFaux.etatHorsLigne(etatFaux.chapitres.single).progression, 1.0);
    final horsLigne = etatFaux.etatHorsLigne(etatFaux.chapitres.single);
    expect(horsLigne.statut, StatutHorsLigne.enCours);
  });

  test("une relecture de la file périmée n'écrase pas un chargement plus "
      "récent", () async {
    final faux = FauxServiceBibliotheque()
      ..ajouterTitreDeTest(
        'Titre',
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
        ],
      );
    final telechargement = FauxServiceTelechargement(faux);
    final etatFaux = EtatTitre(faux, 1, serviceTelechargement: telechargement);
    addTearDown(etatFaux.dispose);
    await etatFaux.charger();

    // La relecture déclenchée par le signal attend la base…
    final retenue = Completer<void>();
    faux.retenue = retenue;
    telechargement.modifierLigne(1, StatutTelechargement.termine);
    await pumpEventQueue();
    // … pendant qu'un chargement plus récent lit un nouveau chapitre.
    faux.retenue = null;
    faux.chapitresParTitre[1]!.add(
      const Chapitre(id: 2, urlChapitre: 'u2', nom: 'Deux', numero: 2),
    );
    await etatFaux.charger();
    expect(etatFaux.chapitres, hasLength(2));

    faux.chapitresParTitre[1]!.removeLast();
    retenue.complete();
    await pumpEventQueue();
    expect(etatFaux.chapitres, hasLength(2));
  });

  group('suppressions prévues, doublons et langues (faux services)', () {
    late FauxServiceBibliotheque faux;
    late FauxServiceTelechargement telechargement;
    late EtatTitre etatFaux;
    final maintenant = DateTime.utc(2026, 11, 16, 10);

    setUp(() async {
      faux = FauxServiceBibliotheque()
        ..ajouterTitreDeTest(
          'Titre',
          chapitres: const <Chapitre>[
            Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
            Chapitre(id: 2, urlChapitre: 'u2', nom: 'Deux A', numero: 2),
            Chapitre(id: 3, urlChapitre: 'u3', nom: 'Deux B', numero: 2),
            Chapitre(id: 4, urlChapitre: 'u4', nom: 'Oneshot', numero: 0),
            Chapitre(id: 5, urlChapitre: 'u5', nom: 'Oneshot', numero: 0),
          ],
        );
      telechargement = FauxServiceTelechargement(faux);
      for (final id in <int>[1, 2, 3, 4, 5]) {
        telechargement.ajouterChapitreTelecharge(id);
      }
      telechargement.planifierSuppressionDeTest(
        1,
        maintenant.add(const Duration(hours: 23, minutes: 5)),
      );
      etatFaux = EtatTitre(
        faux,
        1,
        serviceTelechargement: telechargement,
        maintenant: () => maintenant,
      );
      await etatFaux.charger();
    });

    tearDown(() => etatFaux.dispose());

    Chapitre chapitre(int id) =>
        etatFaux.chapitres.firstWhere((chapitre) => chapitre.id == id);

    test('une suppression prévue affiche son compte à rebours', () {
      final horsLigne = etatFaux.etatHorsLigne(chapitre(1));
      expect(horsLigne.aSuppressionPrevue, isTrue);
      expect(
        horsLigne.tempsAvantSuppression(etatFaux.maintenant),
        const Duration(hours: 23, minutes: 5),
      );
      expect(etatFaux.nombreSuppressionsPrevues, 1);
      expect(etatFaux.etatHorsLigne(chapitre(4)).aSuppressionPrevue, isFalse);
    });

    test('« Garder » annule la suppression prévue', () async {
      final resultat = await etatFaux.garder(chapitre(1));

      expect(resultat.estReussi, isTrue);
      expect(telechargement.gardes, contains(1));
      expect(etatFaux.etatHorsLigne(chapitre(1)).aSuppressionPrevue, isFalse);
      expect(etatFaux.nombreSuppressionsPrevues, 0);
    });

    test('« Supprimer maintenant » efface l\'archive tout de suite', () async {
      final resultat = await etatFaux.supprimerMaintenant(chapitre(1));

      expect(resultat.estReussi, isTrue);
      expect(telechargement.journal, contains('supprimerMaintenant:1'));
      expect(chapitre(1).estTelecharge, isFalse);
    });

    test('les doublons sont signalés, jamais les oneshots', () async {
      expect(etatFaux.estDoublon(chapitre(2)), isTrue);
      expect(etatFaux.estDoublon(chapitre(3)), isTrue);
      expect(etatFaux.estDoublon(chapitre(4)), isFalse);
      expect(etatFaux.etatHorsLigne(chapitre(3)).estDoublon, isTrue);
      expect(etatFaux.nombreDoublons, 2);

      // Le client supprime l'un des deux : l'autre n'est plus un doublon.
      await etatFaux.supprimerMaintenant(chapitre(3));
      expect(etatFaux.estDoublon(chapitre(2)), isFalse);
    });

    test('chaque oneshot forme sa propre ligne', () {
      final oneshots = etatFaux.groupes
          .where((groupe) => groupe.numero == 0)
          .map((groupe) => groupe.retenu.id)
          .toList();
      expect(oneshots, unorderedEquals(<int>[4, 5]));
      // Le numéro 2 regroupe ses deux versions.
      expect(
        etatFaux.groupes.singleWhere((g) => g.numero == 2).versions,
        hasLength(2),
      );
    });

    test('langues : réglage général par défaut, puis propres au titre et '
        'retour au général', () async {
      expect(etatFaux.langues, <String>['fr', 'en']);
      expect(etatFaux.languesGenerales, <String>['fr', 'en']);
      expect(etatFaux.aLanguesPropres, isFalse);

      // Langue retirée seulement : pas de relecture du site.
      final retrait = await etatFaux.modifierLangues(<String>['en']);
      expect(retrait.estReussi, isTrue);
      expect(retrait.donnee, 0);
      expect(etatFaux.langues, <String>['en']);
      expect(etatFaux.aLanguesPropres, isTrue);
      expect(telechargement.journal, contains('langues:1:en'));

      final retour = await etatFaux.modifierLangues(null);
      expect(retour.estReussi, isTrue);
      expect(etatFaux.aLanguesPropres, isFalse);
      expect(etatFaux.langues, <String>['fr', 'en']);
    });

    test('une langue ajoutée relit le site puis applique les règles', () async {
      faux.nombreNouveaux = 4;
      telechargement.reglesAppliquees.clear();

      final resultat = await etatFaux.modifierLangues(<String>['ja', 'fr']);

      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee, 4);
      expect(etatFaux.langues, <String>['ja', 'fr']);
      // Une fois par modifierLanguesTitre, une fois après l'actualisation.
      expect(telechargement.reglesAppliquees, <int>[1, 1]);
    });

    test('site injoignable : les langues restent enregistrées', () async {
      faux.erreurAjout = const ErreurService('hors ligne');

      final resultat = await etatFaux.modifierLangues(<String>['ko']);

      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee, isNull);
      expect(etatFaux.langues, <String>['ko']);
    });
  });

  test('un titre supprimé est signalé comme introuvable', () async {
    await services.bibliotheque.supprimerTitre(etat.idTitre);

    await etat.charger();

    expect(etat.erreur!.nature, NatureErreur.introuvable);
    expect(etat.titre, isNull);
  });
}
