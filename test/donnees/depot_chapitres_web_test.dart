// Tests de la migration 13 sur DepotChapitres : chapitres enregistrés depuis
// le navigateur intégré (colonne chapitres.origine), y compris sur un site en
// lien seul.
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotChapitres depot;
  late int idTitre;
  late int idMangaDex;
  late int idComix;

  const urlComix = 'https://comix.to/title/ruri';
  const urlCh12 = 'https://comix.to/title/ruri/chapter-12';
  final maintenant = DateTime.utc(2026, 11, 19, 12);

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotChapitres(base);
    final depotSources = DepotSources(base);
    idMangaDex = (await depotSources.enregistrerSource(sourceMangaDex)).id!;
    idComix = (await depotSources.enregistrerSource(
      const Source(
        nom: 'Comix',
        urlBase: 'https://comix.to',
        typeSource: TypeSource.generique,
        langueParDefaut: 'en',
      ),
    )).id!;
    idTitre = (await DepotTitres(
      base,
    ).enregistrerTitre(titreReference(idMangaDex))).id!;
    await DepotTitresSources(base)
        .ajouterSourceSecondaire(idTitre, idComix, urlComix, lienSeul: true);
  });

  tearDown(() async {
    await base.close();
  });

  Chapitre chapitreSite(double numero, {int? idSource}) => Chapitre(
    idTitre: idTitre,
    idSource: idSource,
    urlChapitre: 'https://comix.to/title/ruri/site-$numero',
    nom: 'Chapitre $numero',
    numero: numero,
    langue: 'en',
  );

  group('enregistrerChapitreWeb', () {
    test('un chapitre web est accepté sur un site en lien seul', () async {
      final chapitre = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: '  $urlCh12#page-3 ',
        dateDetection: maintenant,
      );
      expect(chapitre.id, isNotNull);
      expect(chapitre.origine, OrigineChapitre.web);
      expect(chapitre.estWeb, isTrue);
      expect(chapitre.idSource, idComix);
      expect(chapitre.urlChapitre, urlCh12);
      expect(chapitre.nom, 'Chapitre 12');
      // Langue par défaut de la source.
      expect(chapitre.langue, 'en');
      expect(chapitre.dateDetection, maintenant);
      // Tel qu'en base.
      expect(await depot.chargerChapitre(chapitre.id!), chapitre);
      expect(
        (await base.query('chapitres')).single['origine'],
        OrigineChapitre.web.name,
      );
    });

    test('titre et langue donnés sont enregistrés, 10.5 garde sa '
        'décimale', () async {
      final avecTitre = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 3,
        url: 'https://comix.to/title/ruri/chapter-3',
        titre: '  Le retour  ',
        langue: 'fr',
      );
      expect(avecTitre.nom, 'Le retour');
      expect(avecTitre.langue, 'fr');
      final intermediaire = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 10.5,
        url: 'https://comix.to/title/ruri/chapter-10-5',
      );
      expect(intermediaire.nom, 'Chapitre 10.5');
    });

    test('idempotent par adresse (normalisée) et par numéro', () async {
      final premier = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: urlCh12,
      );
      final memeAdresse = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: '$urlCh12/#haut',
      );
      final memeNumero = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: 'https://comix.to/title/ruri/chapter-12?page=2',
      );
      // Même adresse, numéro différent (mal deviné) : même chapitre.
      final autreNumero = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 13,
        url: urlCh12,
      );
      expect(memeAdresse, premier);
      expect(memeNumero, premier);
      expect(autreNumero, premier);
      expect(await base.query('chapitres'), hasLength(1));
    });

    test("l'état lu est conservé quand le chapitre est réenregistré", () async {
      final premier = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: urlCh12,
      );
      await depot.marquerLu(premier.id!);
      final second = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: urlCh12,
      );
      expect(second.estLu, isTrue);
    });

    test('un même numéro sur un autre site du titre est un autre '
        'chapitre', () async {
      await depot.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: idTitre,
          urlChapitre: 'https://mangadex.org/chapter/12',
          nom: 'Chapitre 12',
          numero: 12,
        ),
      ]);
      final web = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: urlCh12,
      );
      expect(web.idSource, idComix);
      expect(await base.query('chapitres'), hasLength(2));
    });

    test('refusé si le site n\'est pas lié au titre, si le titre manque ou '
        'si l\'adresse appartient à un autre titre', () async {
      final idAutreSource = (await DepotSources(base).enregistrerSource(
        const Source(
          nom: 'Autre',
          urlBase: 'https://autre.example',
          typeSource: TypeSource.generique,
        ),
      )).id!;
      await expectLater(
        depot.enregistrerChapitreWeb(
          idTitre,
          idAutreSource,
          numero: 1,
          url: 'https://autre.example/ch1',
        ),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      await expectLater(
        depot.enregistrerChapitreWeb(
          9999,
          idComix,
          numero: 1,
          url: 'https://comix.to/x',
        ),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      // Adresse déjà prise par un chapitre d'un autre titre.
      final idAutreTitre = (await DepotTitres(base).enregistrerTitre(
        titreReference(idAutreSource)
            .copierAvec(urlTitre: 'https://autre.example/titre'),
      )).id!;
      await depot.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: idAutreTitre,
          urlChapitre: urlCh12,
          nom: 'Chapitre 12',
          numero: 12,
        ),
      ]);
      await expectLater(
        depot.enregistrerChapitreWeb(
          idTitre,
          idComix,
          numero: 12,
          url: urlCh12,
        ),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('adresse vide ou numéro non fini : ArgumentError', () async {
      await expectLater(
        depot.enregistrerChapitreWeb(idTitre, idComix, numero: 1, url: ' #/'),
        throwsArgumentError,
      );
      await expectLater(
        depot.enregistrerChapitreWeb(
          idTitre,
          idComix,
          numero: double.nan,
          url: urlCh12,
        ),
        throwsArgumentError,
      );
    });
  });

  group('lien seul et chapitres du site', () {
    test('un chapitre du site reste refusé sur un lien seul (dépôt)', () async {
      await expectLater(
        depot.enregistrerChapitres(<Chapitre>[
          chapitreSite(1, idSource: idComix),
        ]),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(await base.query('chapitres'), isEmpty);
    });

    test('un chapitre web passé à enregistrerChapitres est accepté sur un '
        'lien seul', () async {
      final nouveaux = await depot.enregistrerChapitres(<Chapitre>[
        chapitreSite(
          1,
          idSource: idComix,
        ).copierAvec(origine: OrigineChapitre.web),
      ]);
      expect(nouveaux, 1);
    });

    test('les déclencheurs refusent un chapitre du site sur un lien seul, '
        'quel que soit le chemin d\'écriture', () async {
      // Insertion directe.
      await expectLater(
        base.insert('chapitres', <String, Object?>{
          'id_titre': idTitre,
          'id_source': idComix,
          'url_chapitre': 'https://comix.to/direct',
          'nom': 'Direct',
          'numero': 1.0,
        }),
        throwsA(isA<DatabaseException>()),
      );
      // Un chapitre web inséré directement est accepté…
      final id = await base.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'id_source': idComix,
        'url_chapitre': 'https://comix.to/direct',
        'nom': 'Direct',
        'numero': 1.0,
        'origine': 'web',
      });
      // … mais ne peut pas redevenir un chapitre du site.
      await expectLater(
        base.update(
          'chapitres',
          <String, Object?>{'origine': 'site'},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      // Un chapitre du site principal ne peut pas être déplacé vers le lien
      // seul.
      final idSite = await base.insert('chapitres', <String, Object?>{
        'id_titre': idTitre,
        'url_chapitre': 'https://mangadex.org/chapter/1',
        'nom': 'Chapitre 1',
        'numero': 1.0,
      });
      await expectLater(
        base.update(
          'chapitres',
          <String, Object?>{'id_source': idComix},
          where: 'id = ?',
          whereArgs: <Object?>[idSite],
        ),
        throwsA(isA<DatabaseException>()),
      );
      // Valeur inconnue refusée par le CHECK.
      await expectLater(
        base.update(
          'chapitres',
          <String, Object?>{'origine': 'autre'},
          where: 'id = ?',
          whereArgs: <Object?>[idSite],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('passage en lien seul : chapitres web et lus gardés, chapitres '
        'site non lus supprimés ; un chapitre site gardé reste '
        'modifiable', () async {
      final depotSites = DepotTitresSources(base);
      await depotSites.marquerLienSeul(idTitre, idComix, false);
      await depot.enregistrerChapitres(<Chapitre>[
        chapitreSite(1, idSource: idComix),
        chapitreSite(2, idSource: idComix),
      ]);
      final lu = (await depot.chargerChapitres(
        idTitre,
        idSource: idComix,
      )).firstWhere((c) => c.numero == 1);
      await depot.marquerLu(lu.id!);
      final web = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 3,
        url: 'https://comix.to/title/ruri/chapter-3',
      );

      final supprimes = await depotSites.marquerLienSeul(
        idTitre,
        idComix,
        true,
      );
      expect(supprimes, 1);
      final restants = await depot.chargerChapitres(idTitre, idSource: idComix);
      expect(restants.map((c) => c.id), <int>[lu.id!, web.id!]);
      // Le chapitre site gardé peut toujours changer d'état.
      await depot.marquerLu(lu.id!, estLu: false);
      await depot.enregistrerArchive(lu.id!, 'manga/Ruri/ch1.en.zip');
      expect((await depot.chargerChapitre(lu.id!))!.estTelecharge, isTrue);
    });

    test('retrait du site : les chapitres web non lus suivent la règle '
        'habituelle', () async {
      final web = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 3,
        url: 'https://comix.to/title/ruri/chapter-3',
      );
      final webLu = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 4,
        url: 'https://comix.to/title/ruri/chapter-4',
      );
      await depot.marquerLu(webLu.id!);
      final supprimes = await DepotTitresSources(base)
          .retirerSourceSecondaire(idTitre, idComix);
      expect(supprimes, 1);
      expect(await depot.chargerChapitre(web.id!), isNull);
      expect(await depot.chargerChapitre(webLu.id!), isNotNull);
    });
  });

  group('actualisation depuis le site', () {
    test('ne supprime ni ne modifie un chapitre web', () async {
      // Le site redevient lisible et donne le même chapitre (même adresse),
      // avec un lien externe : le chapitre web n'est pas touché.
      final web = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: urlCh12,
        titre: 'Titre web',
      );
      await depot.marquerLu(web.id!);
      await DepotTitresSources(base).marquerLienSeul(idTitre, idComix, false);
      final nouveaux = await depot.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: idTitre,
          idSource: idComix,
          urlChapitre: urlCh12,
          nom: 'Titre du site',
          numero: 12,
          langue: 'fr',
          urlExterne: 'https://editeur.example/12',
        ),
        chapitreSite(13, idSource: idComix),
      ]);
      expect(nouveaux, 1);
      final apres = (await depot.chargerChapitre(web.id!))!;
      expect(apres, web.copierAvec(estLu: true));
      expect(apres.urlExterne, isNull);
      expect(apres.origine, OrigineChapitre.web);
    });
  });

  group('chargerChapitreParUrl', () {
    test('retrouve un chapitre par url_chapitre ou url_externe, adresse '
        'normalisée', () async {
      final web = await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: urlCh12,
      );
      await depot.enregistrerChapitres(<Chapitre>[
        Chapitre(
          idTitre: idTitre,
          urlChapitre: 'https://mangadex.org/chapter/5/',
          nom: 'Chapitre 5',
          numero: 5,
          urlExterne: 'https://editeur.example/ruri/5#debut',
        ),
      ]);
      final externe = (await depot.chargerChapitres(
        idTitre,
        idSource: idMangaDex,
      )).single;

      expect(await depot.chargerChapitreParUrl(urlCh12), web);
      expect(await depot.chargerChapitreParUrl(' $urlCh12/#page-2 '), web);
      expect(await depot.chargerChapitreParUrl(urlCh12, idTitre: idTitre), web);
      // Adresse en base avec un / final, cherchée sans.
      expect(
        await depot.chargerChapitreParUrl('https://mangadex.org/chapter/5'),
        externe,
      );
      // Par le lien externe (fragment en base, pas dans la recherche).
      expect(
        await depot.chargerChapitreParUrl('https://editeur.example/ruri/5/'),
        externe,
      );
    });

    test('null si inconnu, adresse vide ou autre titre', () async {
      await depot.enregistrerChapitreWeb(
        idTitre,
        idComix,
        numero: 12,
        url: urlCh12,
      );
      expect(
        await depot.chargerChapitreParUrl('https://comix.to/inconnu'),
        isNull,
      );
      expect(await depot.chargerChapitreParUrl('  '), isNull);
      expect(
        await depot.chargerChapitreParUrl(urlCh12, idTitre: idTitre + 1),
        isNull,
      );
      // Préfixe d'une adresse connue : pas une correspondance.
      expect(
        await depot.chargerChapitreParUrl('https://comix.to/title/ruri'),
        isNull,
      );
    });
  });
}
