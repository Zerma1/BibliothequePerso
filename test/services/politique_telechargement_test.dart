// Tests des règles de conservation des chapitres demandées par le client.
import 'package:bibliotheque_perso/modeles/chapitre.dart';
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
}
