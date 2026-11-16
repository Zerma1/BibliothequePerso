// Tests des règles de conservation des chapitres demandées par le client.
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/services/classement_listes.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chapitres 1 à [nombre] (id = numéro), [lus] premiers lus, et ceux de
/// [telecharges] déjà sur l'appareil.
List<Chapitre> _chapitres(
  int nombre, {
  int lus = 0,
  Set<int> telecharges = const <int>{},
  String langue = 'fr',
}) {
  return <Chapitre>[
    for (var n = 1; n <= nombre; n++)
      Chapitre(
        id: n,
        urlChapitre: 'https://exemple.test/$langue/$n',
        nom: 'Chapitre $n',
        numero: n.toDouble(),
        langue: langue,
        estLu: n <= lus,
        estTelecharge: telecharges.contains(n),
      ),
  ];
}

Set<int> _intervalle(int debut, int fin) => <int>{
  for (var n = debut; n <= fin; n++) n,
};

void main() {
  const politique = PolitiqueTelechargement(
    languesPreferees: <String>['fr', 'en'],
  );

  group('titre seulement suivi', () {
    test('sans lecture, télécharge les chapitres 1 à 10', () {
      final plan = politique.calculer(
        _chapitres(50),
        estFavori: false,
        estSuivi: true,
      );
      expect(plan.idsVoulus, _intervalle(1, 10));
      expect(plan.idsATelecharger, <int>[for (var n = 1; n <= 10; n++) n]);
    });

    test('avant le 6e chapitre lu, la fenêtre initiale ne bouge pas', () {
      final plan = politique.calculer(
        _chapitres(50, lus: 5, telecharges: _intervalle(1, 10)),
        estFavori: false,
        estSuivi: true,
      );
      expect(plan.idsVoulus, _intervalle(1, 10));
      expect(plan.idsATelecharger, isEmpty);
      expect(plan.idsASupprimer, isEmpty);
    });

    test('au 6e chapitre lu, supprime le 1 et télécharge le 11', () {
      final plan = politique.calculer(
        _chapitres(50, lus: 6, telecharges: _intervalle(1, 10)),
        estFavori: false,
        estSuivi: true,
      );
      // Dernier lu = 6 : on garde 2..6 (5 chapitres) et 7..11 (5 suivants).
      expect(plan.idsVoulus, _intervalle(2, 11));
      expect(plan.idsASupprimer, <int>[1]);
      expect(plan.idsATelecharger, <int>[11]);
    });

    test('la vague suit la lecture (dernier lu = 20)', () {
      final plan = politique.calculer(
        _chapitres(50, lus: 20, telecharges: _intervalle(10, 19)),
        estFavori: false,
        estSuivi: true,
      );
      expect(plan.idsVoulus, _intervalle(16, 25));
      expect(plan.idsASupprimer, <int>[10, 11, 12, 13, 14, 15]);
      expect(plan.idsATelecharger, <int>[20, 21, 22, 23, 24, 25]);
    });

    test('ne dépasse pas le dernier chapitre paru', () {
      final plan = politique.calculer(
        _chapitres(8, lus: 7),
        estFavori: false,
        estSuivi: true,
      );
      expect(plan.idsVoulus, _intervalle(3, 8));
    });

    test('les limites sont réglables', () {
      const reglee = PolitiqueTelechargement(
        reglages: ReglagesTelechargement(
          suivisInitial: 3,
          suivisAvant: 2,
          suivisApres: 4,
        ),
      );
      expect(
        reglee
            .calculer(_chapitres(30), estFavori: false, estSuivi: true)
            .idsVoulus,
        _intervalle(1, 3),
      );
      expect(
        reglee
            .calculer(_chapitres(30, lus: 10), estFavori: false, estSuivi: true)
            .idsVoulus,
        _intervalle(9, 14),
      );
    });
  });

  group('titre favori', () {
    test('télécharge tous les non lus et garde les 10 derniers lus', () {
      final plan = politique.calculer(
        _chapitres(40, lus: 25, telecharges: _intervalle(1, 25)),
        estFavori: true,
        estSuivi: true,
      );
      expect(plan.idsVoulus, _intervalle(16, 40));
      expect(plan.idsASupprimer, <int>[for (var n = 1; n <= 15; n++) n]);
      expect(plan.idsATelecharger, <int>[for (var n = 26; n <= 40; n++) n]);
    });

    test('sans lecture, télécharge tout', () {
      final plan = politique.calculer(
        _chapitres(12),
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, _intervalle(1, 12));
    });

    test('le nombre de lus gardés est réglable (0 = aucun)', () {
      const reglee = PolitiqueTelechargement(
        reglages: ReglagesTelechargement(favorisLusConserves: 0),
      );
      final plan = reglee.calculer(
        _chapitres(10, lus: 4, telecharges: _intervalle(1, 4)),
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, _intervalle(5, 10));
      expect(plan.idsASupprimer, <int>[1, 2, 3, 4]);
    });
  });

  test('ni favori ni suivi : rien n\'est téléchargé ni supprimé', () {
    final plan = politique.calculer(
      _chapitres(10, telecharges: <int>{3}),
      estFavori: false,
      estSuivi: false,
    );
    expect(plan.idsATelecharger, isEmpty);
    expect(plan.idsASupprimer, isEmpty);
  });

  group('langues', () {
    test('une seule version par numéro, en français de préférence', () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'en1',
          nom: 'en',
          numero: 1,
          langue: 'en',
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
        ),
        const Chapitre(
          id: 3,
          urlChapitre: 'en2',
          nom: 'en',
          numero: 2,
          langue: 'en',
        ),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{2, 3});
    });

    test('un numéro lu dans une langue compte comme lu', () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'en1',
          nom: 'en',
          numero: 1,
          langue: 'en',
          estLu: true,
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
        ),
        const Chapitre(
          id: 3,
          urlChapitre: 'fr2',
          nom: 'fr',
          numero: 2,
          langue: 'fr',
        ),
      ];
      const sansLus = PolitiqueTelechargement(
        reglages: ReglagesTelechargement(favorisLusConserves: 0),
        languesPreferees: <String>['fr', 'en'],
      );
      final plan = sansLus.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{3});
    });

    test('garde une traduction déjà téléchargée plutôt que d\'en prendre une autre', () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'fr1-a',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1-b',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
          estTelecharge: true,
        ),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{2});
      expect(plan.idsATelecharger, isEmpty);
    });
  });

  group("remplacement de l'anglais par le français", () {
    test("garde l'anglais tant que le français n'est pas téléchargé", () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'en1',
          nom: 'en',
          numero: 1,
          langue: 'en',
          estTelecharge: true,
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
        ),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, <int>[2]);
      expect(plan.idsASupprimer, isEmpty);
    });

    test("supprime l'anglais une fois le français téléchargé", () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'en1',
          nom: 'en',
          numero: 1,
          langue: 'en',
          estTelecharge: true,
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
          estTelecharge: true,
        ),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, isEmpty);
      expect(plan.idsASupprimer, <int>[1]);
    });

    test("un favori déjà lu garde l'anglais téléchargé, sans retélécharger "
        'le français', () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'en1',
          nom: 'en',
          numero: 1,
          langue: 'en',
          estLu: true,
          estTelecharge: true,
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
        ),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{1});
      expect(plan.idsATelecharger, isEmpty);
      expect(plan.idsASupprimer, isEmpty);
    });

    test("un favori déjà lu sans version téléchargée prend toujours le "
        'français', () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'en1',
          nom: 'en',
          numero: 1,
          langue: 'en',
          estLu: true,
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
        ),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, <int>[2]);
    });

    test('un favori déjà lu avec une version dans une langue non choisie '
        "ne la garde pas", () {
      final chapitres = <Chapitre>[
        const Chapitre(
          id: 1,
          urlChapitre: 'ru1',
          nom: 'ru',
          numero: 1,
          langue: 'ru',
          estLu: true,
          estTelecharge: true,
        ),
        const Chapitre(
          id: 2,
          urlChapitre: 'fr1',
          nom: 'fr',
          numero: 1,
          langue: 'fr',
        ),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, <int>[2]);
      expect(plan.idsASupprimer, <int>[1]);
    });
  });

  group('langues non choisies par le client', () {
    Chapitre version(
      int id,
      double numero,
      String langue, {
      bool estTelecharge = false,
      bool estLu = false,
    }) => Chapitre(
      id: id,
      urlChapitre: 'https://exemple.test/$id',
      nom: '$langue $numero',
      numero: numero,
      langue: langue,
      estTelecharge: estTelecharge,
      estLu: estLu,
    );

    test('seules les versions fr et en sont voulues parmi ru, ja, en, fr', () {
      final chapitres = <Chapitre>[
        version(1, 1, 'ru'),
        version(2, 1, 'ja'),
        version(3, 1, 'en'),
        version(4, 2, 'ru'),
        version(5, 2, 'fr'),
        version(6, 3, 'ja'),
        version(7, 3, 'en'),
        version(8, 3, 'fr'),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{3, 5, 8});
      expect(plan.idsATelecharger, <int>[3, 5, 8]);
    });

    test('un numéro disponible seulement en russe est ignoré', () {
      final chapitres = <Chapitre>[
        version(1, 1, 'fr'),
        version(2, 2, 'ru'),
        version(3, 3, 'fr'),
      ];
      for (final (favori, suivi) in <(bool, bool)>[
        (true, false),
        (false, true),
      ]) {
        final plan = politique.calculer(
          chapitres,
          estFavori: favori,
          estSuivi: suivi,
        );
        expect(plan.idsVoulus, <int>{1, 3});
      }
    });

    test('une archive en russe déjà téléchargée est à supprimer', () {
      final chapitres = <Chapitre>[
        version(1, 1, 'ru', estTelecharge: true),
        version(2, 1, 'fr'),
        version(3, 2, 'ru', estTelecharge: true),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      // Même en attendant le français, le russe n'est pas gardé.
      expect(plan.idsASupprimer, <int>[1, 3]);
      expect(plan.idsATelecharger, <int>[2]);
    });

    test('une variante régionale compte comme sa langue', () {
      const portugais = PolitiqueTelechargement(
        languesPreferees: <String>['pt'],
      );
      final plan = portugais.calculer(
        <Chapitre>[version(1, 1, 'pt-br'), version(2, 2, 'es')],
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{1});
    });

    test('lire un numéro ignoré fait quand même avancer la fenêtre', () {
      final chapitres = <Chapitre>[
        for (var n = 1; n <= 20; n++) version(n, n.toDouble(), 'fr'),
        version(99, 15.5, 'ru', estLu: true),
      ];
      const reglee = PolitiqueTelechargement(
        reglages: ReglagesTelechargement(
          suivisInitial: 2,
          suivisAvant: 1,
          suivisApres: 1,
        ),
        languesPreferees: <String>['fr'],
      );
      final plan = reglee.calculer(chapitres, estFavori: false, estSuivi: true);
      expect(plan.idsVoulus, <int>{15, 16});
    });
  });

  group('fenêtre des suivis', () {
    test('la fenêtre initiale reste en position absolue (initial 10, avant et après 2)', () {
      const reglee = PolitiqueTelechargement(
        reglages: ReglagesTelechargement(
          suivisInitial: 10,
          suivisAvant: 2,
          suivisApres: 2,
        ),
      );
      expect(
        reglee
            .calculer(_chapitres(30, lus: 4), estFavori: false, estSuivi: true)
            .idsVoulus,
        _intervalle(3, 10),
      );
      expect(
        reglee
            .calculer(_chapitres(30, lus: 9), estFavori: false, estSuivi: true)
            .idsVoulus,
        _intervalle(8, 11),
      );
    });

    test('avant et après valent au moins 1', () {
      const reglee = PolitiqueTelechargement(
        reglages: ReglagesTelechargement(
          suivisInitial: 0,
          suivisAvant: 0,
          suivisApres: 0,
        ),
      );
      expect(
        reglee
            .calculer(_chapitres(30, lus: 5), estFavori: false, estSuivi: true)
            .idsVoulus,
        <int>{5, 6},
      );
    });
  });

  group('oneshots et doublons', () {
    Chapitre chapitre(
      int id,
      double numero, {
      String langue = 'fr',
      bool estTelecharge = false,
    }) => Chapitre(
      id: id,
      urlChapitre: 'https://exemple.test/$id',
      nom: 'Chapitre $id',
      numero: numero,
      langue: langue,
      estTelecharge: estTelecharge,
    );

    test('chaque oneshot de numéro 0 est un chapitre distinct', () {
      final plan = politique.calculer(
        <Chapitre>[chapitre(1, 0), chapitre(2, 0), chapitre(3, 1)],
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{1, 2, 3});
      expect(
        politique.choisirVersions(<Chapitre>[chapitre(1, 0), chapitre(2, 0)]),
        hasLength(2),
      );
    });

    test(
      "les règles ne suppriment pas un doublon de même numéro et même langue",
      () {
        final plan = politique.calculer(
          <Chapitre>[
            chapitre(1, 1, estTelecharge: true),
            chapitre(2, 1, estTelecharge: true),
            chapitre(3, 1, langue: 'en', estTelecharge: true),
          ],
          estFavori: true,
          estSuivi: false,
        );
        expect(plan.idsVoulus, <int>{1});
        // Le doublon français reste ; l'anglais, remplacé, est supprimé.
        expect(plan.idsASupprimer, <int>[3]);
      },
    );

    test('trouve les doublons téléchargés, sans regrouper les oneshots', () {
      final doublons = PolitiqueTelechargement.trouverDoublons(<Chapitre>[
        chapitre(1, 1, estTelecharge: true),
        chapitre(2, 1, estTelecharge: true),
        chapitre(3, 1, langue: 'en', estTelecharge: true),
        chapitre(4, 2, estTelecharge: true),
        chapitre(5, 2),
        chapitre(6, 0, estTelecharge: true),
        chapitre(7, 0, estTelecharge: true),
      ]);
      expect(
        doublons.map((groupe) => groupe.map((c) => c.id).toList()).toList(),
        <List<int>>[
          <int>[1, 2],
        ],
      );
    });
  });

  group('chapitres hébergés sur un site externe (R4)', () {
    Chapitre version(
      int id,
      double numero, {
      String langue = 'fr',
      bool externe = false,
      bool estLu = false,
      bool estTelecharge = false,
    }) => Chapitre(
      id: id,
      urlChapitre: 'https://exemple.test/$id',
      nom: 'Chapitre $numero',
      numero: numero,
      langue: langue,
      estLu: estLu,
      estTelecharge: estTelecharge,
      urlExterne: externe
          ? 'https://mangaplus.shueisha.co.jp/viewer/$id'
          : null,
    );

    test("un favori n'en télécharge jamais aucun", () {
      final plan = politique.calculer(
        <Chapitre>[
          version(1, 1, externe: true),
          version(2, 2, externe: true),
          version(3, 3),
        ],
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, <int>[3]);
      expect(plan.idsVoulus, <int>{3});
    });

    test('la version hébergée passe avant une version externe, même dans '
        'une langue préférée', () {
      final chapitres = <Chapitre>[
        version(1, 1, externe: true),
        version(2, 1, langue: 'en'),
      ];
      final plan = politique.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, <int>[2]);
      expect(politique.choisirVersions(chapitres).single.chapitre.id, 2);
    });

    test('une version externe reste affichée quand elle est la seule dans '
        'les langues du client', () {
      final chapitres = <Chapitre>[
        version(1, 1, externe: true),
        version(2, 1, langue: 'ru'),
      ];
      expect(politique.choisirVersions(chapitres).single.chapitre.id, 1);
      expect(
        politique
            .calculer(chapitres, estFavori: true, estSuivi: false)
            .idsATelecharger,
        isEmpty,
      );
    });

    test('les numéros seulement externes ne comptent pas dans la fenêtre '
        'des suivis', () {
      final plan =
          const PolitiqueTelechargement(
            reglages: ReglagesTelechargement(suivisInitial: 2),
            languesPreferees: <String>['fr'],
          ).calculer(
            <Chapitre>[
              version(1, 1, externe: true),
              version(2, 2),
              version(3, 3),
              version(4, 4),
            ],
            estFavori: false,
            estSuivi: true,
          );
      expect(plan.idsATelecharger, <int>[2, 3]);
    });

    test("l'archive d'un chapitre devenu externe n'est jamais supprimée", () {
      final plan = politique.calculer(
        <Chapitre>[
          version(1, 1, externe: true, estLu: true, estTelecharge: true),
          version(2, 1, estTelecharge: false),
          for (var n = 2; n <= 10; n++)
            version(n + 1, n.toDouble(), estLu: true),
        ],
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsASupprimer, isEmpty);
    });

    test("un titre dont les seuls chapitres dans les langues sont externes "
        "n'est pas « en attente »", () {
      final chapitres = <Chapitre>[version(1, 1, externe: true)];
      expect(
        ClassementListes.aChapitreDansLesLangues(chapitres, <String>['fr']),
        isTrue,
      );
      expect(politique.estTelechargeable(chapitres.single), isFalse);
    });
  });

  group('plusieurs sites pour un titre (étape 8)', () {
    // Site principal : 1 ; sites secondaires : 2 et 3 (3 retiré du titre).
    const multiSites = PolitiqueTelechargement(
      languesPreferees: <String>['fr', 'en'],
      idSourcePrincipale: 1,
      idsSourcesLiees: <int>{1, 2},
    );

    Chapitre version(
      int id,
      double numero,
      int idSource, {
      String langue = 'fr',
      bool externe = false,
      bool estTelecharge = false,
      DateTime? datePublication,
    }) => Chapitre(
      id: id,
      urlChapitre: 'https://site$idSource.test/$id',
      nom: 'Chapitre $numero',
      numero: numero,
      langue: langue,
      idSource: idSource,
      estTelecharge: estTelecharge,
      datePublication: datePublication,
      urlExterne: externe ? 'https://externe.test/$id' : null,
    );

    test('une seule version par numéro : la langue préférée passe avant le '
        'site principal', () {
      final chapitres = <Chapitre>[
        version(1, 1, 1, langue: 'en'),
        version(2, 1, 2),
      ];
      final plan = multiSites.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, <int>[2]);
    });

    test('à langue égale, la version hébergée passe avant la version '
        'externe du site principal', () {
      final plan = multiSites.calculer(
        <Chapitre>[version(1, 1, 1, externe: true), version(2, 1, 2)],
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, <int>[2]);
    });

    test('à langue et hébergement égaux, le site principal passe avant la '
        'version plus ancienne du site secondaire', () {
      final chapitres = <Chapitre>[
        version(1, 1, 2, datePublication: DateTime.utc(2020)),
        version(2, 1, 1, datePublication: DateTime.utc(2024)),
      ];
      expect(multiSites.choisirVersions(chapitres).single.chapitre.id, 2);
    });

    test('entre deux sites secondaires équivalents, la plus ancienne', () {
      const sansPrincipal = PolitiqueTelechargement(
        languesPreferees: <String>['fr'],
        idSourcePrincipale: 9,
      );
      final chapitres = <Chapitre>[
        version(1, 1, 2, datePublication: DateTime.utc(2024)),
        version(2, 1, 3, datePublication: DateTime.utc(2020)),
      ];
      expect(sansPrincipal.choisirVersions(chapitres).single.chapitre.id, 2);
    });

    test("une version déjà téléchargée d'un site secondaire n'est pas "
        'retéléchargée depuis le principal', () {
      final plan = multiSites.calculer(
        <Chapitre>[
          version(1, 1, 2, estTelecharge: true),
          version(2, 1, 1),
        ],
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsATelecharger, isEmpty);
      expect(plan.idsVoulus, <int>{1});
      expect(plan.idsASupprimer, isEmpty);
    });

    test("un site retiré n'est jamais retenu et ses archives sont à "
        'supprimer, même pour un titre ni favori ni suivi', () {
      final chapitres = <Chapitre>[
        version(1, 1, 3, estTelecharge: true),
        version(2, 1, 1, langue: 'en'),
        version(3, 2, 3),
      ];
      final favori = multiSites.calculer(
        chapitres,
        estFavori: true,
        estSuivi: false,
      );
      expect(favori.idsATelecharger, <int>[2]);
      expect(favori.idsASupprimer, <int>[1]);
      expect(multiSites.estTelechargeable(chapitres[2]), isFalse);

      final niFavoriNiSuivi = multiSites.calculer(
        chapitres,
        estFavori: false,
        estSuivi: false,
      );
      expect(niFavoriNiSuivi.idsATelecharger, isEmpty);
      expect(niFavoriNiSuivi.idsASupprimer, <int>[1]);
    });

    test('sans sites connus, un chapitre sans site vient du principal', () {
      const chapitre = Chapitre(
        id: 1,
        urlChapitre: 'https://ancien.test/1',
        nom: 'Chapitre 1',
        numero: 1,
        langue: 'fr',
      );
      expect(multiSites.estDuSitePrincipal(chapitre), isTrue);
      expect(multiSites.estDeSiteRetire(chapitre), isFalse);
    });
  });
}
