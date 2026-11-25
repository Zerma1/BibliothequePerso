// Tests de l'étape 8 (M1) : DepotTitresSources, chapitres par site
// (DepotChapitres) et suppression d'une source liée (DepotSources).
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTitresSources depot;
  late DepotChapitres depotChapitres;
  late DepotTitres depotTitres;
  late int idMangaDex;
  late int idScanManga;
  late int idTitre;

  const urlScanManga = 'https://www.scan-manga.com/titre/12345';
  final dateAjout = DateTime.utc(2026, 11, 16, 12);

  /// Message d'une ErreurBaseDeDonnees, pour vérifier qu'il est clair.
  Matcher erreurContenant(String texte) => throwsA(
    isA<ErreurBaseDeDonnees>().having(
      (e) => e.message,
      'message',
      contains(texte),
    ),
  );

  Chapitre chapitre(String url, double numero, {int? idSource}) => Chapitre(
    idTitre: idTitre,
    urlChapitre: url,
    nom: 'Chapitre $numero',
    numero: numero,
    langue: 'fr',
    idSource: idSource,
  );

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotTitresSources(base);
    depotChapitres = DepotChapitres(base);
    depotTitres = DepotTitres(base);
    final depotSources = DepotSources(base);
    idMangaDex = (await depotSources.enregistrerSource(sourceMangaDex)).id!;
    idScanManga = (await depotSources.enregistrerSource(
      const Source(
        nom: 'Scan-Manga',
        urlBase: 'https://www.scan-manga.com',
        typeSource: TypeSource.scanManga,
        langueParDefaut: 'fr',
      ),
    )).id!;
    idTitre = (await depotTitres.enregistrerTitre(titreReference(idMangaDex)))
        .id!;
  });

  tearDown(() async {
    await base.close();
  });

  group('sites d\'un titre', () {
    test('un titre enregistré a son site principal', () async {
      final liens = await depot.chargerLiensTitre(idTitre);
      expect(liens, hasLength(1));
      expect(liens.single.idSource, idMangaDex);
      expect(liens.single.urlTitre, urlTitreReference);
      expect(liens.single.estPrincipale, isTrue);
      expect(await depot.chargerLienPrincipal(idTitre), liens.single);
      expect(await depot.chargerLiensTitre(999), isEmpty);
      expect(await depot.chargerLienPrincipal(999), isNull);
    });

    test('ajouter un site secondaire', () async {
      final lien = await depot.ajouterSourceSecondaire(
        idTitre,
        idScanManga,
        '  $urlScanManga ',
        dateAjout: dateAjout,
      );
      expect(lien.id, isNotNull);
      expect(lien.urlTitre, urlScanManga);
      expect(lien.estPrincipale, isFalse);
      expect(lien.dateAjout, dateAjout);

      final liens = await depot.chargerLiensTitre(idTitre);
      expect(liens.map((l) => l.idSource), <int>[idMangaDex, idScanManga]);
      expect(liens.last, lien);
      // Le site principal du titre ne change pas.
      final titre = await depotTitres.chargerTitre(idTitre);
      expect(titre!.idSource, idMangaDex);
      expect(titre.urlTitre, urlTitreReference);
    });

    test('ajout refusé : URL vide, titre ou source inexistant', () async {
      expect(
        () => depot.ajouterSourceSecondaire(idTitre, idScanManga, '  '),
        throwsArgumentError,
      );
      await expectLater(
        depot.ajouterSourceSecondaire(999, idScanManga, urlScanManga),
        erreurContenant("le titre n°999 n'existe pas"),
      );
      await expectLater(
        depot.ajouterSourceSecondaire(idTitre, 999, urlScanManga),
        erreurContenant("la source n°999 n'existe pas"),
      );
    });

    test('ajout refusé : adresse déjà utilisée par un autre titre', () async {
      final autre = await depotTitres.enregistrerTitre(
        Titre(
          idSource: idScanManga,
          urlTitre: urlScanManga,
          nom: 'Autre titre',
          typeTitre: TypeTitre.manga,
        ),
      );
      await expectLater(
        depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga),
        erreurContenant('déjà utilisée par un autre titre : « Autre titre »'),
      );
      // Même refus si l'adresse est un site secondaire de l'autre titre.
      await depot.ajouterSourceSecondaire(
        autre.id!,
        idMangaDex,
        'https://mangadex.org/title/autre',
      );
      await expectLater(
        depot.ajouterSourceSecondaire(
          idTitre,
          idScanManga,
          'https://mangadex.org/title/autre',
        ),
        erreurContenant('déjà utilisée par un autre titre'),
      );
      expect(await depot.chargerLiensTitre(idTitre), hasLength(1));
    });

    test('ajout refusé : adresse ou site déjà lié à ce titre', () async {
      await expectLater(
        depot.ajouterSourceSecondaire(idTitre, idScanManga, urlTitreReference),
        erreurContenant('déjà un site du titre'),
      );
      await expectLater(
        depot.ajouterSourceSecondaire(
          idTitre,
          idMangaDex,
          'https://mangadex.org/title/autre-adresse',
        ),
        erreurContenant('« MangaDex » est déjà lié au titre'),
      );
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await expectLater(
        depot.ajouterSourceSecondaire(
          idTitre,
          idScanManga,
          'https://www.scan-manga.com/titre/autre',
        ),
        erreurContenant('« Scan-Manga » est déjà lié au titre'),
      );
    });

    test(
      'trouver un titre par l\'URL de n\'importe lequel de ses sites',
      () async {
        await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
        expect((await depot.chargerTitreParUrl(urlScanManga))!.id, idTitre);
        expect(
          (await depot.chargerTitreParUrl(urlTitreReference))!.id,
          idTitre,
        );
        expect(
          (await depot.chargerLienParUrl(urlScanManga))!.idSource,
          idScanManga,
        );
        expect(await depot.chargerTitreParUrl('https://exemple.org/x'), isNull);
        // DepotTitres ne cherche que dans le site principal (inchangé).
        expect(await depotTitres.chargerTitreParUrl(urlScanManga), isNull);
      },
    );

    test('un titre supprimé emporte ses sites', () async {
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await depotTitres.supprimerTitre(idTitre);
      expect(await base.query('titres_sources'), isEmpty);
    });
  });

  group('site principal', () {
    test(
      'définir le principal échange les rôles et met à jour titres',
      () async {
        await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
        await depot.definirSourcePrincipale(idTitre, idScanManga);

        final liens = await depot.chargerLiensTitre(idTitre);
        expect(liens.first.idSource, idScanManga);
        expect(liens.first.estPrincipale, isTrue);
        expect(liens.first.urlTitre, urlScanManga);
        expect(liens.last.idSource, idMangaDex);
        expect(liens.last.estPrincipale, isFalse);
        expect(liens.last.urlTitre, urlTitreReference);

        final titre = await depotTitres.chargerTitre(idTitre);
        expect(titre!.idSource, idScanManga);
        expect(titre.urlTitre, urlScanManga);
        expect(await depotTitres.chargerTitreParUrl(urlScanManga), isNotNull);
        // Le titre garde son contenu.
        expect(titre.nom, nomTitreReference);
        expect(titre.titresAlternatifs, hasLength(6));
      },
    );

    test(
      'définir le principal actuel ne change rien ; site non lié refusé',
      () async {
        await depot.definirSourcePrincipale(idTitre, idMangaDex);
        expect(
          (await depot.chargerLienPrincipal(idTitre))!.idSource,
          idMangaDex,
        );
        await expectLater(
          depot.definirSourcePrincipale(idTitre, idScanManga),
          erreurContenant("n'est pas un site du titre"),
        );
      },
    );

    test(
      'une actualisation du titre par DepotTitres garde les sites',
      () async {
        await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
        final relu = await depotTitres.enregistrerTitre(
          titreReference(idMangaDex).copierAvec(resume: 'Nouveau résumé'),
        );
        expect(relu.id, idTitre);
        final liens = await depot.chargerLiensTitre(idTitre);
        expect(liens.map((l) => (l.idSource, l.estPrincipale)), <(int, bool)>[
          (idMangaDex, true),
          (idScanManga, false),
        ]);
      },
    );

    test('DepotTitres refuse un nouveau titre sur l\'adresse secondaire '
        'd\'un autre', () async {
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await expectLater(
        depotTitres.enregistrerTitre(
          Titre(idSource: idScanManga, urlTitre: urlScanManga, nom: 'Doublon'),
        ),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(await depotTitres.chargerTitres(), hasLength(1));
    });
  });

  group('chapitres par site', () {
    test('enregistrés sans source : site principal ; avec idSource : '
        'ce site', () async {
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        chapitre('https://mangadex.org/chapter/1', 1),
      ]);
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        chapitre('https://www.scan-manga.com/c/1', 1),
        chapitre('https://www.scan-manga.com/c/2', 2),
      ], idSource: idScanManga);

      final tous = await depotChapitres.chargerChapitres(idTitre);
      expect(tous.map((c) => (c.numero, c.idSource)), <(double, int?)>[
        (1, idMangaDex),
        (1, idScanManga),
        (2, idScanManga),
      ]);
      expect(
        await depotChapitres.chargerChapitres(idTitre, idSource: idMangaDex),
        hasLength(1),
      );
      expect(
        (await depotChapitres.chargerChapitres(
          idTitre,
          idSource: idScanManga,
        )).map((c) => c.urlChapitre),
        <String>[
          'https://www.scan-manga.com/c/1',
          'https://www.scan-manga.com/c/2',
        ],
      );
    });

    test('la source propre d\'un chapitre l\'emporte sur idSource', () async {
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        chapitre('https://mangadex.org/chapter/1', 1, idSource: idMangaDex),
      ], idSource: idScanManga);
      expect(
        (await depotChapitres.chargerChapitres(idTitre)).single.idSource,
        idMangaDex,
      );
    });

    test('un chapitre d\'un site non lié au titre est refusé, rien n\'est '
        'écrit', () async {
      await expectLater(
        depotChapitres.enregistrerChapitres(<Chapitre>[
          chapitre('https://mangadex.org/chapter/1', 1),
          chapitre('https://www.scan-manga.com/c/1', 1, idSource: idScanManga),
        ]),
        erreurContenant("n'est pas un site du titre"),
      );
      await expectLater(
        depotChapitres.enregistrerChapitres(<Chapitre>[
          chapitre('https://www.scan-manga.com/c/1', 1),
        ], idSource: idScanManga),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(await depotChapitres.chargerChapitres(idTitre), isEmpty);
    });

    test('un chapitre déjà connu garde sa source d\'origine', () async {
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        chapitre('https://mangadex.org/chapter/1', 1),
      ]);
      final nouveaux = await depotChapitres.enregistrerChapitres(<Chapitre>[
        chapitre('https://mangadex.org/chapter/1', 1),
      ], idSource: idScanManga);
      expect(nouveaux, 0);
      expect(
        (await depotChapitres.chargerChapitres(idTitre)).single.idSource,
        idMangaDex,
      );
    });

    test(
      'changer de site principal ne change pas la source des chapitres',
      () async {
        await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
        await depotChapitres.enregistrerChapitres(<Chapitre>[
          chapitre('https://mangadex.org/chapter/1', 1),
        ]);
        await depot.definirSourcePrincipale(idTitre, idScanManga);
        expect(
          (await depotChapitres.chargerChapitres(idTitre)).single.idSource,
          idMangaDex,
        );
        // Un nouveau chapitre sans source va au nouveau principal.
        await depotChapitres.enregistrerChapitres(<Chapitre>[
          chapitre('https://www.scan-manga.com/c/2', 2),
        ]);
        expect(
          (await depotChapitres.chargerChapitres(idTitre)).last.idSource,
          idScanManga,
        );
      },
    );
  });

  group('retrait d\'un site secondaire', () {
    /// Lie Scan-Manga au titre et enregistre ses chapitres : 1 lu, 2
    /// téléchargé, 3 gardé avec archive, 4 en cours de téléchargement, 5 en
    /// attente dans la file, 6 rien. Un chapitre MangaDex non lu aussi.
    Future<Map<int, int>> preparer() async {
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        chapitre('https://mangadex.org/chapter/1', 1),
      ]);
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        for (var n = 1; n <= 6; n++)
          chapitre('https://www.scan-manga.com/c/$n', n.toDouble()),
      ], idSource: idScanManga);
      final ids = <int, int>{
        for (final c in await depotChapitres.chargerChapitres(
          idTitre,
          idSource: idScanManga,
        ))
          c.numero.toInt(): c.id!,
      };
      await depotChapitres.marquerLu(ids[1]!);
      await depotChapitres.enregistrerArchive(ids[2]!, 'manga/T/ch2.fr.zip');
      await depotChapitres.enregistrerArchive(ids[3]!, 'manga/T/ch3.fr.zip');
      await depotChapitres.marquerGarde(ids[3]!);
      final file = DepotTelechargements(base);
      await file.ajouterPlusieursEnFile(<int>[ids[4]!, ids[5]!]);
      await base.update(
        'telechargements',
        <String, Object?>{'statut': 'en_cours'},
        where: 'id_chapitre = ?',
        whereArgs: <Object?>[ids[4]],
      );
      return ids;
    }

    test('supprime seulement les chapitres non conservés de ce site, dans '
        'la même transaction', () async {
      final ids = await preparer();
      final supprimes = await depot.retirerSourceSecondaire(
        idTitre,
        idScanManga,
      );
      expect(supprimes, 2);

      expect(
        (await depot.chargerLiensTitre(idTitre)).map((l) => l.idSource),
        <int>[idMangaDex],
      );
      final restants = await depotChapitres.chargerChapitres(
        idTitre,
        idSource: idScanManga,
      );
      expect(restants.map((c) => c.id), <int>[
        ids[1]!,
        ids[2]!,
        ids[3]!,
        ids[4]!,
      ]);
      // Le chapitre du site principal n'est pas touché.
      expect(
        await depotChapitres.chargerChapitres(idTitre, idSource: idMangaDex),
        hasLength(1),
      );
      // La file ne garde que le téléchargement en cours.
      expect(
        (await base.query('telechargements')).map((t) => t['id_chapitre']),
        <Object?>[ids[4]],
      );
    });

    test('méthode dédiée de DepotChapitres', () async {
      await preparer();
      expect(
        await depotChapitres.supprimerChapitresNonConserves(
          idTitre,
          idScanManga,
        ),
        2,
      );
      expect(
        await depotChapitres.supprimerChapitresNonConserves(
          idTitre,
          idScanManga,
        ),
        0,
      );
    });

    test(
      'le site principal ne peut pas être retiré ; site non lié refusé',
      () async {
        await expectLater(
          depot.retirerSourceSecondaire(idTitre, idMangaDex),
          erreurContenant('site principal'),
        );
        await expectLater(
          depot.retirerSourceSecondaire(idTitre, idScanManga),
          erreurContenant("n'est pas un site du titre"),
        );
        expect(await depot.chargerLiensTitre(idTitre), hasLength(1));
      },
    );

    test('la source ne peut pas être supprimée tant qu\'elle est liée ou que '
        'des chapitres en viennent', () async {
      await preparer();
      final depotSources = DepotSources(base);
      await expectLater(
        depotSources.supprimerSource(idScanManga),
        erreurContenant('1 titre(s) en dépendent'),
      );
      await depot.retirerSourceSecondaire(idTitre, idScanManga);
      await expectLater(
        depotSources.supprimerSource(idScanManga),
        erreurContenant('4 chapitre(s)'),
      );
      // Une fois ces chapitres supprimés par le client, plus rien ne bloque.
      await base.delete(
        'chapitres',
        where: 'id_source = ?',
        whereArgs: <Object?>[idScanManga],
      );
      await depotSources.supprimerSource(idScanManga);
      expect(await depotSources.chargerSource(idScanManga), isNull);
    });
  });

  group('lien seul (migration 8)', () {
    test('ajout en lien seul : enregistré et rechargé tel quel', () async {
      final lien = await depot.ajouterSourceSecondaire(
        idTitre,
        idScanManga,
        urlScanManga,
        dateAjout: dateAjout,
        lienSeul: true,
      );
      expect(lien.estLienSeul, isTrue);
      expect(lien.estPrincipale, isFalse);
      final liens = await depot.chargerLiensTitre(idTitre);
      expect(liens.map((l) => l.estLienSeul), <bool>[false, true]);
      expect(liens.last, lien);
      expect(await depot.chargerLienParUrl(urlScanManga), lien);
      // Par défaut, un site ajouté n'est pas un lien seul.
      expect((await depot.chargerLienPrincipal(idTitre))!.estLienSeul, isFalse);
    });

    test('un lien seul ne peut pas devenir site principal', () async {
      await depot.ajouterSourceSecondaire(
        idTitre,
        idScanManga,
        urlScanManga,
        lienSeul: true,
      );
      await expectLater(
        depot.definirSourcePrincipale(idTitre, idScanManga),
        erreurContenant('lien seul'),
      );
      // Rien n'a changé.
      expect((await depot.chargerLienPrincipal(idTitre))!.idSource, idMangaDex);
      expect((await depotTitres.chargerTitre(idTitre))!.idSource, idMangaDex);
    });

    test('le site principal ne peut pas être marqué lien seul ; site non '
        'lié refusé', () async {
      await expectLater(
        depot.marquerLienSeul(idTitre, idMangaDex, true),
        erreurContenant('site principal'),
      );
      await expectLater(
        depot.marquerLienSeul(idTitre, idScanManga, true),
        erreurContenant("n'est pas un site du titre"),
      );
      // Le principal marqué lisible : déjà le cas, rien à faire.
      expect(await depot.marquerLienSeul(idTitre, idMangaDex, false), 0);
      expect((await depot.chargerLienPrincipal(idTitre))!.estLienSeul, isFalse);
    });

    test('bascule : lien seul puis de nouveau lisible, et promotion '
        'possible ensuite', () async {
      await depot.ajouterSourceSecondaire(idTitre, idScanManga, urlScanManga);
      await depotChapitres.enregistrerChapitres(<Chapitre>[
        chapitre('https://www.scan-manga.com/c/1', 1),
        chapitre('https://www.scan-manga.com/c/2', 2),
      ], idSource: idScanManga);
      final lu = (await depotChapitres.chargerChapitres(
        idTitre,
        idSource: idScanManga,
      )).first;
      await depotChapitres.marquerLu(lu.id!);

      // Passage en lien seul : le chapitre non lu disparaît, le lu reste.
      expect(await depot.marquerLienSeul(idTitre, idScanManga, true), 1);
      expect((await depot.chargerLiensTitre(idTitre)).last.estLienSeul, isTrue);
      expect(
        (await depotChapitres.chargerChapitres(
          idTitre,
          idSource: idScanManga,
        )).map((c) => c.id),
        <int>[lu.id!],
      );
      // Déjà lien seul : rien à faire.
      expect(await depot.marquerLienSeul(idTitre, idScanManga, true), 0);

      // Aucun chapitre ne peut venir d'un lien seul.
      await expectLater(
        depotChapitres.enregistrerChapitres(<Chapitre>[
          chapitre('https://www.scan-manga.com/c/3', 3),
        ], idSource: idScanManga),
        erreurContenant('lien seul'),
      );

      // Le site redevient lisible : chapitres acceptés, promotion permise.
      expect(await depot.marquerLienSeul(idTitre, idScanManga, false), 0);
      expect(
        (await depot.chargerLiensTitre(idTitre)).last.estLienSeul,
        isFalse,
      );
      expect(
        await depotChapitres.enregistrerChapitres(<Chapitre>[
          chapitre('https://www.scan-manga.com/c/3', 3),
        ], idSource: idScanManga),
        1,
      );
      await depot.definirSourcePrincipale(idTitre, idScanManga);
      final principal = (await depot.chargerLienPrincipal(idTitre))!;
      expect(principal.idSource, idScanManga);
      expect(principal.estLienSeul, isFalse);
    });
  });
}
