// Tests de EtatSources avec les vrais services et une base en mémoire.
import 'dart:async';

import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  late ServicesDeTest services;
  late EtatSources etat;

  setUp(() async {
    services = await creerServicesReels();
    etat = EtatSources(services.bibliotheque, services.ajoutSite);
    await etat.charger();
  });

  tearDown(() async {
    etat.dispose();
    await services.fermer();
  });

  test('aucun site au départ', () {
    expect(etat.estCharge, isTrue);
    expect(etat.estVide, isTrue);
  });

  test('ajoute MangaDex sans requête réseau, avec nom et langue', () async {
    final resultat = await etat.ajouterSite(
      'https://mangadex.org/title/abc',
      nom: 'Mon MangaDex',
      langueParDefaut: 'FR',
    );

    expect(resultat.estReussi, isTrue);
    final ajout = resultat.donnee!;
    expect(ajout.etaitDejaConfigure, isFalse);
    expect(ajout.source.typeSource, TypeSource.mangaDex);
    expect(ajout.source.nom, 'Mon MangaDex');
    expect(ajout.source.langueParDefaut, 'fr');
    expect(etat.sources, hasLength(1));
    expect(services.requetes, isEmpty);
  });

  test('signale un site déjà configuré', () async {
    await etat.ajouterSite('https://mangadex.org');
    final resultat = await etat.ajouterSite('https://mangadex.org/title/x');

    expect(resultat.donnee!.etaitDejaConfigure, isTrue);
    expect(etat.sources, hasLength(1));
  });

  test('le type forcé remplace la détection (aucun téléchargement)', () async {
    final resultat = await etat.ajouterSite(
      'https://lecture.exemple.test/manga/x',
      typeForce: TypeSource.madara,
    );

    expect(resultat.donnee!.source.typeSource, TypeSource.madara);
    expect(services.requetes, isEmpty);
  });

  test('une adresse invalide devient une erreur de site lisible', () async {
    final resultat = await etat.ajouterSite('ftp://exemple.test');

    expect(resultat.erreur!.nature, NatureErreur.site);
    expect(resultat.erreur!.detail, contains('http://'));
    expect(etat.estEnAjout, isFalse);
  });

  test('un site injoignable devient une erreur de site', () async {
    services.siteEnPanne = true;
    final resultat = await etat.ajouterSite('https://exemple.test');

    expect(resultat.erreur!.nature, NatureErreur.site);
  });

  test('une adresse vide est refusée', () async {
    final resultat = await etat.ajouterSite('');
    expect(resultat.erreur!.nature, NatureErreur.adresseVide);
  });

  test('propose un nom à partir de l\'adresse', () {
    expect(
      etat.proposerNom('https://www.exemple.test/manga/x'),
      'exemple.test',
    );
    expect(etat.proposerNom('pas une adresse'), '');
  });

  test('un chargement périmé n\'écrase pas le plus récent', () async {
    final faux = FauxServiceBibliotheque();
    final retenue = Completer<void>();
    faux.retenue = retenue;
    final etatFaux = EtatSources(faux, FauxServiceAjoutSite(faux));

    final ancien = etatFaux.charger();
    faux
      ..retenue = null
      ..erreurLecture = null;
    faux.sources.add(
      const Source(
        id: 1,
        nom: 'Récent',
        urlBase: 'https://recent.test',
        typeSource: TypeSource.generique,
      ),
    );
    await etatFaux.charger();
    expect(etatFaux.sources, hasLength(1));

    // L'ancien chargement échoue après coup : son erreur est ignorée.
    faux.erreurLecture = const ErreurBaseDeDonnees('ancienne panne');
    retenue.complete();
    await ancien;
    expect(etatFaux.erreur, isNull);
    expect(etatFaux.sources, hasLength(1));
    etatFaux.dispose();
  });

  test('une erreur de base au chargement est exposée', () async {
    final faux = FauxServiceBibliotheque()
      ..erreurLecture = const ErreurBaseDeDonnees('Disque plein');
    final etatFaux = EtatSources(faux, FauxServiceAjoutSite(faux));

    await etatFaux.charger();

    expect(etatFaux.erreur!.nature, NatureErreur.baseDeDonnees);
    expect(etatFaux.erreur!.detail, 'Disque plein');
    etatFaux.dispose();
  });
}
