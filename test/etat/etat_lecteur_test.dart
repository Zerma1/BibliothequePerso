// Tests de EtatLecteur : faux services pour la navigation et le marquage
// « lu », puis vrais services sur une base en mémoire avec une archive .zip
// écrite dans un dossier temporaire (aucun réseau).
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_lecteur.dart';
import 'package:bibliotheque_perso/etat/outils_chapitres.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';
import 'outils_tests_etat.dart';

/// Faux service de bibliothèque qui note les marquages « lu » dans un
/// journal partagé (pour vérifier l'ordre lu → règles).
class _BibliothequeJournalisee extends FauxServiceBibliotheque {
  _BibliothequeJournalisee(this.journal);

  final List<String> journal;

  @override
  Future<void> marquerLu(int idChapitre, {bool estLu = true}) {
    journal.add('lu:$idChapitre');
    return super.marquerLu(idChapitre, estLu: estLu);
  }
}

void main() {
  group('avec de faux services', () {
    late List<String> journal;
    late _BibliothequeJournalisee bibliotheque;
    late FauxServiceTelechargement telechargement;

    setUp(() {
      journal = <String>[];
      bibliotheque = _BibliothequeJournalisee(journal);
      telechargement = FauxServiceTelechargement(bibliotheque);
      // Le faux service de téléchargement écrit dans le même journal.
      telechargement.journal.clear();
      bibliotheque.sources.add(
        const Source(
          id: 1,
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
          langueParDefaut: 'fr,en',
        ),
      );
      bibliotheque.ajouterTitreDeTest(
        'Titre',
        idSource: 1,
        chapitres: const <Chapitre>[
          Chapitre(
            id: 1,
            urlChapitre: 'u1',
            nom: 'Un',
            numero: 1,
            langue: 'fr',
          ),
          Chapitre(
            id: 2,
            urlChapitre: 'u2',
            nom: 'Deux',
            numero: 2,
            langue: 'fr',
          ),
          // Le numéro 3 existe en deux langues : le français est retenu.
          Chapitre(
            id: 3,
            urlChapitre: 'u3en',
            nom: 'Three',
            numero: 3,
            langue: 'en',
          ),
          Chapitre(
            id: 4,
            urlChapitre: 'u3fr',
            nom: 'Trois',
            numero: 3,
            langue: 'fr',
          ),
        ],
      );
      telechargement
        ..ajouterChapitreTelecharge(1, nombrePages: 3)
        ..ajouterChapitreTelecharge(2, nombrePages: 2)
        ..ajouterChapitreTelecharge(4, nombrePages: 1);
    });

    EtatLecteur creer(int idChapitre) {
      final etat = EtatLecteur(
        serviceBibliotheque: bibliotheque,
        serviceTelechargement: telechargement,
        idTitre: 1,
        idChapitre: idChapitre,
      );
      addTearDown(etat.dispose);
      return etat;
    }

    List<String> journalComplet() => <String>[
      ...journal,
      ...telechargement.journal,
    ];

    test('ouvre un chapitre téléchargé et lit ses pages', () async {
      final etat = creer(1);
      await etat.charger();

      expect(etat.nature, NatureContenu.images);
      expect(etat.nombrePages, 3);
      expect(etat.pageCourante, 0);
      expect(await etat.page(0), pngMinimal);
      // Une page déjà lue n'est pas relue dans l'archive.
      expect(identical(etat.page(1), etat.page(1)), isTrue);
      expect(etat.chapitrePrecedent, isNull);
      expect(etat.chapitreSuivant!.id, 2);
    });

    test(
      'la dernière page marque le chapitre lu PUIS applique les règles',
      () async {
        final etat = creer(1);
        await etat.charger();

        etat.signalerPageVisible(1);
        await pumpEventQueue();
        expect(etat.pageCourante, 1);
        expect(journal, isEmpty);

        etat.signalerPageVisible(2);
        await pumpEventQueue();
        expect(journal, <String>['lu:1']);
        expect(telechargement.reglesAppliquees, <int>[1]);
        expect(etat.chapitre!.estLu, isTrue);

        // Revenir sur la dernière page ne marque pas une seconde fois.
        etat.signalerPageVisible(2);
        await pumpEventQueue();
        expect(journal, <String>['lu:1']);
        expect(telechargement.reglesAppliquees, <int>[1]);
      },
    );

    test('l\'ordre lu puis règles est respecté', () async {
      final journalCommun = <String>[];
      // Les deux faux services écrivent dans la même liste.
      final biblio = _BibliothequeJournalisee(journalCommun)
        ..sources.addAll(bibliotheque.sources);
      biblio.ajouterTitreDeTest(
        'Titre',
        idSource: 1,
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
        ],
      );
      final service = _TelechargementJournalise(biblio, journalCommun)
        ..ajouterChapitreTelecharge(1, nombrePages: 1);
      final etat = EtatLecteur(
        serviceBibliotheque: biblio,
        serviceTelechargement: service,
        idTitre: 1,
        idChapitre: 1,
      );
      addTearDown(etat.dispose);
      await etat.charger();
      etat.signalerPageVisible(0);
      await pumpEventQueue();

      expect(journalCommun, <String>['lu:1', 'regles:1']);
    });

    test('passer au chapitre suivant marque le précédent lu ; la version '
        'retenue (français) est ouverte', () async {
      final etat = creer(2);
      await etat.charger();
      expect(etat.chapitreSuivant!.id, 4);

      await etat.allerAuSuivant();
      expect(journal, <String>['lu:2']);
      expect(telechargement.reglesAppliquees, <int>[1]);
      expect(etat.chapitre!.id, 4);
      expect(etat.nombrePages, 1);
      expect(etat.chapitreSuivant, isNull);

      await etat.allerAuPrecedent();
      expect(etat.chapitre!.id, 2);
      // Revenir en arrière ne marque rien.
      expect(journal, <String>['lu:2']);
      expect(journalComplet(), contains('regles:1'));
    });

    test('chapitre non téléchargé : téléchargement depuis le lecteur, puis '
        'ouverture automatique à la fin', () async {
      final etat = creer(3);
      await etat.charger();
      expect(etat.nature, NatureContenu.nonTelecharge);
      expect(etat.etatHorsLigne.statut, StatutHorsLigne.nonTelecharge);

      await etat.telechargerChapitre();
      expect(etat.etatHorsLigne.statut, StatutHorsLigne.enFile);

      telechargement.modifierLigne(3, StatutTelechargement.termine);
      await pumpEventQueue();
      expect(etat.nature, NatureContenu.images);
      expect(etat.nombrePages, 1);
    });

    test('chapitre texte : HTML rendu lisible', () async {
      telechargement.textes[1] = '<p>Bonjour&nbsp;!</p><p>Suite</p>';
      telechargement.pages.remove(1);
      final etat = creer(1);
      await etat.charger();

      expect(etat.nature, NatureContenu.texte);
      expect(etat.texte, 'Bonjour !\n\nSuite');
      await etat.marquerFinLecture();
      expect(journal, <String>['lu:1']);
    });

    test('archive absente : erreur et Réessayer', () async {
      telechargement.pages.remove(2);
      final etat = creer(2);
      await etat.charger();
      expect(etat.erreur!.nature, NatureErreur.refus);
    });

    test('titre introuvable', () async {
      final etat = EtatLecteur(
        serviceBibliotheque: bibliotheque,
        serviceTelechargement: telechargement,
        idTitre: 99,
        idChapitre: 1,
      );
      addTearDown(etat.dispose);
      await etat.charger();
      expect(etat.erreur!.nature, NatureErreur.introuvable);
    });

    test('une page illisible est relue au « Réessayer »', () async {
      telechargement.pagesIllisibles.add(1);
      final etat = creer(1);
      await etat.charger();

      await expectLater(etat.page(1), throwsA(isA<Object>()));
      telechargement.pagesIllisibles.clear();
      etat.relirePage(1);
      expect(await etat.page(1), pngMinimal);
    });
  });

  group('texteLisibleDepuisHtml', () {
    test('paragraphes, retours à la ligne et listes', () {
      expect(
        texteLisibleDepuisHtml(
          '<h1>Titre</h1>\n<p>Ligne 1<br/>Ligne 2</p><ul><li>a</li><li>b</li></ul>',
        ),
        'Titre\n\nLigne 1\nLigne 2\n\n• a\n• b',
      );
    });

    test('entités et balises inconnues', () {
      expect(
        texteLisibleDepuisHtml(
          '<p>&laquo;&nbsp;Oui&nbsp;&raquo; &amp; <em>non</em> &#233;t&#xE9;</p>',
        ),
        '« Oui » & non été',
      );
    });

    test('ignore scripts, styles et commentaires', () {
      expect(
        texteLisibleDepuisHtml(
          '<style>p{}</style><script>alert(1)</script><!-- note --><p>Texte</p>',
        ),
        'Texte',
      );
    });
  });

  group('avec les vrais services et une archive sur disque', () {
    late Database base;
    late Directory dossier;
    late ServiceTelechargement service;
    late int idChapitre;
    late int idTitre;
    late DepotChapitres depotChapitres;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      base = await ouvrirBaseDeTest();
      dossier = await Directory.systemTemp.createTemp('lecteur_test');
      final client = creerClientTest(
        (http.Request requete) async => http.Response('', 404),
        HorlogeFactice(),
      );
      final depotSources = DepotSources(base);
      final depotTitres = DepotTitres(base);
      depotChapitres = DepotChapitres(base);
      final stockage = StockageTelechargements(dossier.path);
      service = ServiceTelechargement(
        depotTelechargements: DepotTelechargements(base),
        depotChapitres: depotChapitres,
        depotTitres: depotTitres,
        depotListes: DepotListes(base),
        depotSources: depotSources,
        stockage: stockage,
        fabriqueSources: FabriqueSources(client),
        client: client,
        serviceParametres: ServiceParametres(DepotParametres(base)),
      );
      final source = await depotSources.enregistrerSource(sourceMangaDex);
      final titre = await depotTitres.enregistrerTitre(
        Titre(idSource: source.id, urlTitre: urlTitreReference, nom: 'Lecture'),
      );
      idTitre = titre.id!;
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: idTitre,
          urlChapitre: 'https://mangadex.org/chapter/a',
          nom: 'Premier',
          numero: 1,
          langue: 'en',
        ),
      ]);
      final chapitre = (await depotChapitres.chargerChapitres(idTitre)).single;
      idChapitre = chapitre.id!;
      // Archive écrite comme le ferait le téléchargement.
      final ecriture = await stockage.ouvrirEcriture(titre, chapitre);
      await ecriture.ajouterPage(pngMinimal, extension: 'png');
      await ecriture.ajouterPage(pngMinimal, extension: 'png');
      await ecriture.finaliser();
      await depotChapitres.marquerTelecharge(idChapitre, estTelecharge: true);
    });

    tearDown(() async {
      await service.fermer();
      await base.close();
      await dossier.delete(recursive: true);
    });

    test('lit les pages dans l\'archive et marque lu en base', () async {
      final client = creerClientTest(
        (http.Request requete) async => http.Response('', 404),
        HorlogeFactice(),
      );
      final depotSources = DepotSources(base);
      final services = ServiceBibliotheque(
        depotSources: depotSources,
        depotTitres: DepotTitres(base),
        depotChapitres: depotChapitres,
        depotListes: DepotListes(base),
        depotCategories: DepotCategories(base),
        fabriqueSources: FabriqueSources(client),
        serviceAjoutSite: ServiceAjoutSite(
          depotSources,
          DetecteurTypeSite(client),
        ),
        client: client,
      );
      final etat = EtatLecteur(
        serviceBibliotheque: services,
        serviceTelechargement: service,
        idTitre: idTitre,
        idChapitre: idChapitre,
      );
      addTearDown(etat.dispose);
      await etat.charger();

      expect(etat.nature, NatureContenu.images);
      expect(etat.nombrePages, 2);
      expect(await etat.page(1), pngMinimal);

      etat.signalerPageVisible(1);
      await etat.marquerFinLecture();
      final relu = await depotChapitres.chargerChapitre(idChapitre);
      expect(relu!.estLu, isTrue);
    });
  });
}

/// Faux service de téléchargement qui écrit dans un journal partagé.
class _TelechargementJournalise extends FauxServiceTelechargement {
  _TelechargementJournalise(super.bibliotheque, this.journalCommun);

  final List<String> journalCommun;

  @override
  Future<void> appliquerReglesATous() async {
    journalCommun.add('reglesATous');
  }

  @override
  Future<PlanTelechargement> appliquerRegles(int idTitre) async {
    journalCommun.add('regles:$idTitre');
    return super.appliquerRegles(idTitre);
  }
}
