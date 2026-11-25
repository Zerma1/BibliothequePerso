// Tests de l'étape 6 sur DepotTitres et DepotListes : niveau de contenu,
// couverture choisie et listes système « Planifié » / « En attente ».
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTitres depot;
  late int idSource;

  Titre titre(String nom, {String? niveau}) => Titre(
    idSource: idSource,
    urlTitre: 'https://mangadex.org/title/$nom',
    nom: nom,
    typeTitre: TypeTitre.manga,
    niveauContenu: niveau,
  );

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotTitres(base);
    idSource = (await DepotSources(base).enregistrerSource(sourceMangaDex)).id!;
  });

  tearDown(() async {
    await base.close();
  });

  group('niveau de contenu', () {
    test('est enregistré et relu', () async {
      final enregistre = await depot.enregistrerTitre(
        titre('A', niveau: niveauContenuSuggestif),
      );
      expect(enregistre.niveauContenu, niveauContenuSuggestif);
    });

    test('une actualisation sans niveau garde le niveau connu', () async {
      final enregistre = await depot.enregistrerTitre(
        titre('A', niveau: niveauContenuPornographique),
      );
      final actualise = await depot.enregistrerTitre(
        titre('A').copierAvec(resume: 'Nouveau résumé'),
      );
      expect(actualise.id, enregistre.id);
      expect(actualise.resume, 'Nouveau résumé');
      expect(actualise.niveauContenu, niveauContenuPornographique);

      // Un nouveau niveau donné par le site remplace l'ancien.
      final change = await depot.enregistrerTitre(
        titre('A', niveau: niveauContenuErotique),
      );
      expect(change.niveauContenu, niveauContenuErotique);
    });

    test(
      'chargerTitres filtre par niveaux, inconnus inclus par défaut',
      () async {
        await depot.enregistrerTitre(
          titre('Sage', niveau: niveauContenuTousPublics),
        );
        await depot.enregistrerTitre(
          titre('Explicite', niveau: niveauContenuPornographique),
        );
        await depot.enregistrerTitre(
          titre('Erotique', niveau: niveauContenuErotique),
        );
        await depot.enregistrerTitre(titre('Inconnu'));

        Future<List<String>> noms({
          List<String>? niveaux,
          bool inconnus = true,
        }) async => (await depot.chargerTitres(
          niveauxContenu: niveaux,
          inclureNiveauInconnu: inconnus,
        )).map((t) => t.nom).toList();

        expect(await noms(), <String>[
          'Erotique',
          'Explicite',
          'Inconnu',
          'Sage',
        ]);
        expect(await noms(niveaux: niveauxContenuParDefaut), <String>[
          'Erotique',
          'Inconnu',
          'Sage',
        ]);
        expect(
          await noms(niveaux: niveauxContenuParDefaut, inconnus: false),
          <String>['Erotique', 'Sage'],
        );
        expect(await noms(niveaux: <String>[]), <String>['Inconnu']);
        expect(await noms(niveaux: <String>[], inconnus: false), isEmpty);
      },
    );

    test('le filtre se cumule avec la recherche', () async {
      await depot.enregistrerTitre(
        titre('Sage', niveau: niveauContenuTousPublics),
      );
      await depot.enregistrerTitre(
        titre('Sage explicite', niveau: niveauContenuPornographique),
      );
      final resultat = await depot.chargerTitres(
        recherche: 'sage',
        niveauxContenu: niveauxContenuParDefaut,
      );
      expect(resultat.map((t) => t.nom), <String>['Sage']);
    });
  });

  group('couverture choisie', () {
    test('est enregistrée, effacée, et jamais écrasée par une '
        'actualisation', () async {
      final enregistre = await depot.enregistrerTitre(titre('A'));
      final id = enregistre.id!;
      expect(enregistre.couvertureChoisie, isNull);
      expect(enregistre.couvertureAffichee, isNull);

      expect(
        await depot.enregistrerCouvertureChoisie(
          id,
          '  https://uploads.mangadex.org/covers/x/vol2.jpg ',
        ),
        isTrue,
      );
      var relu = (await depot.chargerTitre(id))!;
      expect(
        relu.couvertureChoisie,
        'https://uploads.mangadex.org/covers/x/vol2.jpg',
      );
      expect(relu.couvertureAffichee, relu.couvertureChoisie);

      // Actualisation depuis le site : le choix du client reste.
      relu = await depot.enregistrerTitre(
        titre('A').copierAvec(urlCouverture: 'https://site/couverture.jpg'),
      );
      expect(
        relu.couvertureChoisie,
        'https://uploads.mangadex.org/covers/x/vol2.jpg',
      );
      expect(relu.urlCouverture, 'https://site/couverture.jpg');

      // Retour à la couverture du site (null ou vide).
      await depot.enregistrerCouvertureChoisie(id, '   ');
      relu = (await depot.chargerTitre(id))!;
      expect(relu.couvertureChoisie, isNull);
      expect(relu.couvertureAffichee, 'https://site/couverture.jpg');
      await depot.enregistrerCouvertureChoisie(id, r'C:\Images\a.png');
      await depot.enregistrerCouvertureChoisie(id, null);
      expect((await depot.chargerTitre(id))!.couvertureChoisie, isNull);
    });

    test('est gardée à l\'insertion d\'un nouveau titre', () async {
      final enregistre = await depot.enregistrerTitre(
        titre('A').copierAvec(couvertureChoisie: '/home/moi/a.png'),
      );
      expect(enregistre.couvertureChoisie, '/home/moi/a.png');
    });

    test('titre inconnu : false', () async {
      expect(await depot.enregistrerCouvertureChoisie(999, 'x'), isFalse);
    });
  });

  group('listes système de l\'étape 6', () {
    late DepotListes listes;

    setUp(() {
      listes = DepotListes(base);
    });

    test(
      'Planifié et En attente existent, dans l\'ordre, après Suivis',
      () async {
        final toutes = await listes.chargerListes();
        expect(toutes.map((l) => l.nom), <String>[
          nomListeFavoris,
          nomListeSuivis,
          nomListePlanifie,
          nomListeEnAttente,
          // Ajoutée ensuite par la migration 11.
          nomListeTermines,
        ]);
        expect(toutes.every((l) => l.estSysteme), isTrue);
        expect(
          (await listes.chargerListeParNom(nomListeEnAttente))?.ordre,
          ordreListeEnAttente,
        );
      },
    );

    test('ne peuvent être ni renommées ni supprimées', () async {
      for (final nom in <String>[nomListePlanifie, nomListeEnAttente]) {
        final liste = (await listes.chargerListeParNom(nom))!;
        await expectLater(
          listes.renommerListe(liste.id!, 'Autre'),
          throwsA(isA<ErreurBaseDeDonnees>()),
        );
        await expectLater(
          listes.supprimerListe(liste.id!),
          throwsA(isA<ErreurBaseDeDonnees>()),
        );
      }
      expect(await listes.chargerListes(), hasLength(nomsListesSysteme.length));
    });

    test('une liste du client est placée après les listes système', () async {
      final creee = await listes.creerListe('À lire');
      expect(creee.ordre, ordreListeTermines + 1);
      expect((await listes.chargerListes()).last, creee);
    });

    test('un titre peut être ajouté à Planifié', () async {
      final enregistre = await depot.enregistrerTitre(titre('A'));
      final planifie = (await listes.chargerListeParNom(nomListePlanifie))!;
      await listes.ajouterTitre(planifie.id!, enregistre.id!);
      expect(
        (await depot.chargerTitres(idListe: planifie.id)).single.id,
        enregistre.id,
      );
    });
  });
}
