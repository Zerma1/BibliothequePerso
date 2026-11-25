// Tests de EtatBibliotheque avec les vrais services, une base en mémoire et
// les réponses MangaDex enregistrées (aucun appel réseau).
import 'dart:async';

import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_bibliotheque.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../donnees/outils_tests_donnees.dart';
import 'outils_tests_etat.dart';

void main() {
  late ServicesDeTest services;
  late EtatBibliotheque etat;

  setUp(() async {
    services = await creerServicesReels();
    etat = EtatBibliotheque(services.bibliotheque);
  });

  tearDown(() async {
    etat.dispose();
    await services.fermer();
  });

  test('une bibliothèque neuve est vide, avec Favoris et Suivis', () async {
    final etats = <bool>[];
    etat.addListener(() => etats.add(etat.estEnChargement));

    await etat.charger();

    expect(etats, <bool>[true, false]);
    expect(etat.estCharge, isTrue);
    expect(etat.estVide, isTrue);
    expect(etat.aUnFiltre, isFalse);
    expect(etat.erreur, isNull);
    expect(
      etat.listes.map((liste) => liste.nom),
      containsAll(<String>[nomListeFavoris, nomListeSuivis]),
    );
    // X3 : seule Suivis est cochée par défaut (Favoris reste proposée).
    expect(etat.idsListesParDefaut, <int>{
      etat.listes.firstWhere((liste) => liste.nom == nomListeSuivis).id!,
    });
  });

  test(
    'ajoute un titre MangaDex dans Suivis (liste par défaut) puis le filtre',
    () async {
      await etat.charger();
      final resultat = await etat.ajouterTitre(
        '$urlTitreReference/slug',
        etat.idsListesParDefaut,
      );

      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee!.nombreNouveauxChapitres, greaterThan(0));
      expect(etat.titres, hasLength(1));
      expect(etat.titres.single.nombreChapitresNonLus, greaterThan(0));
      expect(
        etat.categories.map((categorie) => categorie.nom),
        contains('gore'),
      );
      expect(etat.estEnAjout, isFalse);

      final suivis = etat.listes.firstWhere(
        (liste) => liste.nom == nomListeSuivis,
      );
      await etat.choisirListe(suivis.id);
      expect(etat.titres, hasLength(1));
      final favoris = etat.listes.firstWhere(
        (liste) => liste.nom == nomListeFavoris,
      );
      await etat.choisirListe(favoris.id);
      expect(etat.titres, isEmpty);

      final autreListe = await services.bibliotheque.creerListe('Plus tard');
      await etat.choisirListe(autreListe.id);
      expect(etat.titres, isEmpty);
      expect(etat.estVide, isTrue);
      expect(etat.aUnFiltre, isTrue);

      await etat.choisirListe(null);
      final gore = etat.categories.firstWhere(
        (categorie) => categorie.nom == 'gore',
      );
      await etat.choisirCategorie(gore.id);
      expect(etat.titres, hasLength(1));
      await etat.choisirCategorie(null);

      // La recherche porte aussi sur les titres alternatifs.
      await etat.modifierRecherche("death's daughter");
      expect(etat.titres, hasLength(1));
      await etat.modifierRecherche('aucun titre de ce nom');
      expect(etat.titres, isEmpty);
    },
  );

  test('une adresse vide est refusée sans appeler le service', () async {
    final resultat = await etat.ajouterTitre('   ', <int>{});

    expect(resultat.estReussi, isFalse);
    expect(resultat.erreur!.nature, NatureErreur.adresseVide);
    expect(services.requetes, isEmpty);
  });

  test('un site non configuré devient un refus lisible', () async {
    final resultat = await etat.ajouterTitre(
      'https://exemple.test/manga/un-titre',
      <int>{},
    );

    expect(resultat.erreur!.nature, NatureErreur.refus);
    expect(resultat.erreur!.detail, contains('Sources'));
  });

  test('un site en panne devient une erreur de site, sans plantage', () async {
    services.siteEnPanne = true;

    final resultat = await etat.ajouterTitre(urlTitreReference, <int>{});

    expect(resultat.erreur!.nature, NatureErreur.site);
    expect(etat.estEnAjout, isFalse);
  });

  test('supprime un titre', () async {
    await etat.ajouterTitre(urlTitreReference, <int>{});
    final idTitre = etat.titres.single.id!;

    final resultat = await etat.supprimerTitre(idTitre);

    expect(resultat.estReussi, isTrue);
    expect(etat.titres, isEmpty);
  });

  test('avec les téléchargements, la suppression passe par le service des '
      'téléchargements (archives effacées)', () async {
    final faux = FauxServiceBibliotheque()
      ..ajouterTitreDeTest(
        'Titre',
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
        ],
      );
    final telechargement = FauxServiceTelechargement(faux)
      ..ajouterChapitreTelecharge(1);
    final etatFaux = EtatBibliotheque(
      faux,
      serviceTelechargement: telechargement,
    );
    addTearDown(etatFaux.dispose);
    await etatFaux.charger();

    final resultat = await etatFaux.supprimerTitre(1);

    expect(resultat.estReussi, isTrue);
    expect(telechargement.titresSupprimes, <int>[1]);
    expect(telechargement.pages, isEmpty);
    expect(etatFaux.titres, isEmpty);
  });

  test(
    'une erreur de chargement est exposée, puis effacée au rechargement',
    () async {
      final faux = FauxServiceBibliotheque()
        ..erreurLecture = const ErreurService('Base verrouillée');
      final etatFaux = EtatBibliotheque(faux);

      await etatFaux.charger();
      expect(etatFaux.erreur!.nature, NatureErreur.refus);
      expect(etatFaux.estEnChargement, isFalse);

      faux.erreurLecture = null;
      await etatFaux.charger();
      expect(etatFaux.erreur, isNull);
      expect(etatFaux.estVide, isTrue);
      etatFaux.dispose();
    },
  );

  test('recharge la bibliothèque même quand l\'ajout échoue', () async {
    final faux = FauxServiceBibliotheque();
    faux
      ..erreurAjout = const ErreurSource('https://x.test', 'panne')
      // Le titre a été enregistré avant l'échec.
      ..avantAjout = () => faux.ajouterTitreDeTest('Enregistré à moitié');
    final etatFaux = EtatBibliotheque(faux);
    await etatFaux.charger();

    final resultat = await etatFaux.ajouterTitre('https://x.test/t', <int>{});

    expect(resultat.estReussi, isFalse);
    expect(etatFaux.titres, hasLength(1));
    etatFaux.dispose();
  });

  group('E11 : règles de téléchargement après un ajout', () {
    test('un ajout réussi applique les règles au titre ajouté', () async {
      final faux = FauxServiceBibliotheque();
      final telechargement = FauxServiceTelechargement(faux);
      final etatFaux = EtatBibliotheque(
        faux,
        serviceTelechargement: telechargement,
      );
      await etatFaux.charger();

      final resultat = await etatFaux.ajouterTitre(
        'https://mangadex.org/title/nouveau',
        etatFaux.idsListesParDefaut,
      );

      expect(resultat.estReussi, isTrue);
      expect(telechargement.reglesAppliquees, <int>[
        resultat.donnee!.titre.id!,
      ]);
      etatFaux.dispose();
    });

    test('une erreur des règles ne fait pas échouer l\'ajout', () async {
      final faux = FauxServiceBibliotheque();
      final telechargement = FauxServiceTelechargement(faux)
        ..erreurRegles = const ErreurService('file indisponible');
      final etatFaux = EtatBibliotheque(
        faux,
        serviceTelechargement: telechargement,
      );
      await etatFaux.charger();

      final resultat = await etatFaux.ajouterTitre(
        'https://mangadex.org/title/nouveau',
        <int>{},
      );

      expect(resultat.estReussi, isTrue);
      expect(telechargement.reglesAppliquees, hasLength(1));
      expect(etatFaux.titres, hasLength(1));
      etatFaux.dispose();
    });

    test('un ajout échoué n\'applique aucune règle', () async {
      final faux = FauxServiceBibliotheque()
        ..erreurAjout = const ErreurSource('https://x.test', 'panne');
      final telechargement = FauxServiceTelechargement(faux);
      final etatFaux = EtatBibliotheque(
        faux,
        serviceTelechargement: telechargement,
      );
      await etatFaux.charger();

      await etatFaux.ajouterTitre('https://x.test/t', <int>{});

      expect(telechargement.reglesAppliquees, isEmpty);
      etatFaux.dispose();
    });
  });

  test('la recherche attend la fin de la frappe', () async {
    await etat.ajouterTitre(urlTitreReference, <int>{});
    final chargements = <bool>[];
    etat.addListener(() => chargements.add(etat.estEnChargement));

    // Trois frappes rapprochées : un seul chargement.
    unawaited(etat.modifierRecherche('s'));
    unawaited(etat.modifierRecherche('sh'));
    await etat.modifierRecherche('shi');

    expect(chargements.where((enCours) => enCours), hasLength(1));
    expect(etat.titres, hasLength(1));
  });

  test('ne notifie plus après dispose', () async {
    final faux = FauxServiceBibliotheque()
      ..erreurLecture = const ErreurSource('https://x.test', 'panne');
    final etatFaux = EtatBibliotheque(faux);
    final chargement = etatFaux.charger();
    etatFaux.dispose();
    // Ne doit pas lever « used after being disposed ».
    await chargement;
  });
}
