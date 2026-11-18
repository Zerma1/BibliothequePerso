// ServiceBibliotheque : description personnelle d'un titre (la fiche du
// site n'est pas modifiable) et gestion des listes personnelles (X4). Base
// en mémoire, dossier temporaire, aucun appel réseau.
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/constantes_services.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

void main() {
  late Database base;
  late Directory dossier;
  late DepotTitres depotTitres;
  late DepotCategories depotCategories;
  late DepotListes depotListes;
  late StockageTelechargements stockage;
  late ServiceBibliotheque service;
  late Titre titre;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('modification_titre');
    final client = creerClientTest(
      (http.Request requete) async => http.Response('introuvable', 404),
      HorlogeFactice(),
    );
    final depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotCategories = DepotCategories(base);
    depotListes = DepotListes(base);
    stockage = StockageTelechargements(dossier.path);
    service = ServiceBibliotheque(
      depotSources: depotSources,
      depotTitres: depotTitres,
      depotChapitres: DepotChapitres(base),
      depotListes: depotListes,
      depotCategories: depotCategories,
      fabriqueSources: FabriqueSources(client),
      serviceAjoutSite: ServiceAjoutSite(
        depotSources,
        DetecteurTypeSite(client),
      ),
      client: client,
      serviceParametres: ServiceParametres(DepotParametres(base)),
      stockage: stockage,
    );
    final source = await depotSources.enregistrerSource(
      const Source(
        nom: 'Exemple',
        urlBase: 'https://exemple.test',
        typeSource: TypeSource.generique,
      ),
    );
    titre = await depotTitres.enregistrerTitre(
      Titre(
        idSource: source.id,
        urlTitre: 'https://exemple.test/titre',
        nom: 'Nom du site',
        resume: 'Résumé du site',
        auteur: 'Auteur du site',
      ),
      categories: <String>['Action'],
    );
  });

  tearDown(() async {
    await base.close();
    await dossier.delete(recursive: true);
  });
  group('description personnelle', () {
    test(
      'elle est nettoyée autour, garde ses paragraphes et est relue',
      () async {
        final modifie = await service.enregistrerDescriptionPerso(
          titre.id!,
          "  \nMon avis : l'humour.\n\nÀ relire.  \n",
        );
        expect(modifie.descriptionPerso, "Mon avis : l'humour.\n\nÀ relire.");
        // La fiche du site n'est pas touchée.
        expect(modifie.nom, 'Nom du site');
        expect(modifie.resume, 'Résumé du site');
        expect(
          (await depotTitres.chargerTitre(titre.id!))!.descriptionPerso,
          "Mon avis : l'humour.\n\nÀ relire.",
        );
      },
    );

    test('null ou un texte vide efface la description', () async {
      for (final effacement in <String?>[null, '', '  \n ']) {
        await service.enregistrerDescriptionPerso(titre.id!, 'Texte');
        final efface = await service.enregistrerDescriptionPerso(
          titre.id!,
          effacement,
        );
        expect(efface.descriptionPerso, isNull, reason: '« $effacement »');
      }
    });

    test('un texte trop long est refusé sans rien écrire', () async {
      await service.enregistrerDescriptionPerso(titre.id!, 'Avant');
      await expectLater(
        service.enregistrerDescriptionPerso(
          titre.id!,
          'x' * (longueurMaxDescriptionPerso + 1),
        ),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('trop longue'),
          ),
        ),
      );
      expect(
        (await depotTitres.chargerTitre(titre.id!))!.descriptionPerso,
        'Avant',
      );
      // Exactement la limite : acceptée.
      final limite = await service.enregistrerDescriptionPerso(
        titre.id!,
        'y' * longueurMaxDescriptionPerso,
      );
      expect(limite.descriptionPerso, hasLength(longueurMaxDescriptionPerso));
    });

    test('un titre disparu donne une erreur claire', () async {
      await expectLater(
        service.enregistrerDescriptionPerso(999, 'Texte'),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains("n'existe plus"),
          ),
        ),
      );
    });

    test(
      "l'actualisation depuis le site ne remplace pas la description",
      () async {
        await service.enregistrerDescriptionPerso(titre.id!, 'Ma description');
        await depotTitres.enregistrerTitre(
          titre.copierAvec(resume: 'Nouveau résumé du site'),
        );
        final relu = (await depotTitres.chargerTitre(titre.id!))!;
        expect(relu.resume, 'Nouveau résumé du site');
        expect(relu.descriptionPerso, 'Ma description');
      },
    );
  });

  group('listes personnelles', () {
    test(
      'créer nettoie le nom et refuse un doublon ou une liste système',
      () async {
        final liste = await service.creerListe('  À   relire ');
        expect(liste.nom, 'À relire');
        for (final nom in <String>['à relire', 'favoris', '   ']) {
          await expectLater(
            service.creerListe(nom),
            throwsA(isA<ErreurService>()),
          );
        }
        await expectLater(
          service.creerListe('x' * (longueurMaxNomListe + 1)),
          throwsA(isA<ErreurService>()),
        );
      },
    );

    test('renommer une liste du client, jamais une liste système', () async {
      final liste = await service.creerListe('À relire');
      final renommee = await service.renommerListe(liste.id!, ' Plus  tard ');
      expect(renommee.nom, 'Plus tard');
      final favoris = (await depotListes.chargerListeParNom(nomListeFavoris))!;
      await expectLater(
        service.renommerListe(favoris.id!, 'Préférés'),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('liste système'),
          ),
        ),
      );
    });

    test('supprimer une liste du client garde ses titres', () async {
      final liste = await service.creerListe('À relire');
      await service.ajouterTitreALaListe(liste.id!, titre.id!);
      await service.supprimerListe(liste.id!);
      expect(await depotListes.chargerListe(liste.id!), isNull);
      expect(await depotTitres.chargerTitre(titre.id!), isNotNull);
      final suivis = (await depotListes.chargerListeParNom(nomListeSuivis))!;
      await expectLater(
        service.supprimerListe(suivis.id!),
        throwsA(isA<ErreurService>()),
      );
    });

    test('réordonner les listes, système comprises', () async {
      final a = await service.creerListe('A');
      final b = await service.creerListe('B');
      final avant = await service.chargerListes();
      final ordre = <int>[b.id!, a.id!];
      final apres = await service.reordonnerListes(ordre);
      expect(apres.take(2).map((l) => l.id), ordre);
      expect(apres, hasLength(avant.length));
      expect((await service.chargerListes()).first.id, b.id);
      await expectLater(
        service.reordonnerListes(<int>[a.id!, a.id!]),
        throwsA(isA<ErreurService>()),
      );
      await expectLater(
        service.reordonnerListes(<int>[999]),
        throwsA(isA<ErreurService>()),
      );
    });
  });
}
