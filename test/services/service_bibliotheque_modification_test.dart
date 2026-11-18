// ServiceBibliotheque : modification d'un titre à la main (X6), champs
// rendus au site, et gestion des listes personnelles (X4). Base en mémoire,
// couvertures dans un dossier temporaire, aucun appel réseau.
import 'dart:io';
import 'dart:typed_data';

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
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
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

/// En-tête PNG : reconnu par ses octets.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, //
]);

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

  group('modifier un titre', () {
    test('les champs donnés sont nettoyés, écrits et protégés', () async {
      final modifie = await service.modifierTitre(
        titre.id!,
        nom: '  Mon   nom  ',
        resume: 'Mon résumé',
        niveauContenu: ' Suggestive ',
        titresAlternatifs: const <TitreAlternatif>[
          TitreAlternatif(nom: ' Autre nom ', langue: 'FR'),
          TitreAlternatif(nom: 'autre nom'),
          TitreAlternatif(nom: 'Mon nom'),
          TitreAlternatif(nom: '  '),
        ],
        categories: <String>['Comédie', ' comédie ', '', 'Drame'],
      );
      expect(modifie.nom, 'Mon nom');
      expect(modifie.resume, 'Mon résumé');
      expect(modifie.auteur, 'Auteur du site');
      expect(modifie.niveauContenu, 'suggestive');
      expect(
        modifie.titresAlternatifs.map((a) => (a.nom, a.langue)),
        <(String, String)>[('Autre nom', 'fr')],
      );
      expect(
        (await depotCategories.chargerCategoriesDuTitre(titre.id!))
            .map((c) => c.nom)
            .toSet(),
        <String>{'comédie', 'drame'},
      );
      expect(modifie.champsManuels, <ChampTitre>{
        ChampTitre.nom,
        ChampTitre.resume,
        ChampTitre.niveauContenu,
        ChampTitre.titresAlternatifs,
        ChampTitre.categories,
      });
    });

    test(
      "l'actualisation depuis le site ne remplace pas un champ protégé",
      () async {
        await service.modifierTitre(titre.id!, nom: 'Mon nom');
        await depotTitres.enregistrerTitre(
          titre.copierAvec(nom: 'Nouveau nom du site', resume: 'Nouveau'),
        );
        final relu = (await depotTitres.chargerTitre(titre.id!))!;
        expect(relu.nom, 'Mon nom');
        expect(relu.resume, 'Nouveau');
      },
    );

    test('un nom vide, trop long ou un niveau inconnu est refusé', () async {
      await expectLater(
        service.modifierTitre(titre.id!, nom: '   '),
        throwsA(isA<ErreurService>()),
      );
      await expectLater(
        service.modifierTitre(titre.id!, nom: 'x' * (longueurMaxNomTitre + 1)),
        throwsA(isA<ErreurService>()),
      );
      await expectLater(
        service.modifierTitre(titre.id!, niveauContenu: 'violent'),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('Niveau de contenu inconnu'),
          ),
        ),
      );
      expect(
        (await depotTitres.chargerTitre(titre.id!))!.champsManuels,
        isEmpty,
      );
    });

    test('un titre disparu donne une erreur claire', () async {
      await expectLater(
        service.modifierTitre(999, nom: 'X'),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains("n'existe plus"),
          ),
        ),
      );
    });

    test('un texte vide efface la valeur, qui reste protégée', () async {
      final modifie = await service.modifierTitre(titre.id!, auteur: '');
      expect(modifie.auteur, isNull);
      expect(modifie.estManuel(ChampTitre.auteur), isTrue);
    });

    test('la couverture enregistrée suit le titre renommé', () async {
      await stockage.enregistrerCouverture(titre, _png, 'png');
      final modifie = await service.modifierTitre(titre.id!, nom: 'Renommé');
      expect(await stockage.cheminCouverture(titre), isNull);
      final chemin = await stockage.cheminCouverture(modifie);
      expect(chemin, isNotNull);
      expect(chemin, endsWith('.png'));
      expect(await stockage.chargerCouverture(modifie), _png);
    });
  });

  group('rendre des champs au site', () {
    test(
      'le verrou est retiré, la valeur attend la prochaine actualisation',
      () async {
        await service.modifierTitre(titre.id!, nom: 'Mon nom', resume: 'R');
        final rendu = await service.rendreChampsAuSite(titre.id!, <ChampTitre>{
          ChampTitre.nom,
        });
        expect(rendu.nom, 'Mon nom');
        expect(rendu.champsManuels, <ChampTitre>{ChampTitre.resume});
        await depotTitres.enregistrerTitre(titre.copierAvec(nom: 'Du site'));
        expect((await depotTitres.chargerTitre(titre.id!))!.nom, 'Du site');
      },
    );

    test('un titre disparu donne une erreur claire', () async {
      await expectLater(
        service.rendreChampsAuSite(999, <ChampTitre>{ChampTitre.nom}),
        throwsA(isA<ErreurService>()),
      );
    });
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
