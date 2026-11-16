// Tests de l'étape 6 sur les modèles : Chapitre.estGarde,
// Titre.niveauContenu et Titre.couvertureChoisie.
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chapitre.estGarde', () {
    const chapitre = Chapitre(
      id: 1,
      idTitre: 2,
      urlChapitre: 'https://exemple.org/ch/1',
      nom: 'Chapitre 1',
      numero: 1,
      estGarde: true,
    );

    test('aller-retour versMap / depuisMap', () {
      final map = chapitre.versMap();
      expect(map['est_garde'], 1);
      expect(Chapitre.depuisMap(map), chapitre);
    });

    test('colonne absente : non gardé', () {
      final map = chapitre.versMap()..remove('est_garde');
      expect(Chapitre.depuisMap(map).estGarde, isFalse);
    });

    test('valeur invalide : erreur', () {
      final map = chapitre.versMap()..['est_garde'] = 3;
      expect(
        () => Chapitre.depuisMap(map),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('copierAvec, == et hashCode', () {
      final nonGarde = chapitre.copierAvec(estGarde: false);
      expect(nonGarde.estGarde, isFalse);
      expect(nonGarde, isNot(chapitre));
      expect(nonGarde.copierAvec(estGarde: true), chapitre);
      expect(nonGarde.copierAvec(estGarde: true).hashCode, chapitre.hashCode);
      expect(chapitre.copierAvec(nom: 'x').estGarde, isTrue);
    });
  });

  group('Titre : niveau de contenu et couverture choisie', () {
    final titre = Titre(
      id: 1,
      idSource: 2,
      urlTitre: 'https://exemple.org/titre',
      nom: 'Titre',
      urlCouverture: 'https://exemple.org/couverture.jpg',
      niveauContenu: niveauContenuSuggestif,
      couvertureChoisie: 'https://exemple.org/vol2.jpg',
    );

    test('aller-retour versMap / depuisMap', () {
      final map = titre.versMap();
      expect(map['niveau_contenu'], niveauContenuSuggestif);
      expect(map['couverture_choisie'], 'https://exemple.org/vol2.jpg');
      expect(Titre.depuisMap(map), titre);
    });

    test('couvertureAffichee : choisie, sinon celle du site', () {
      expect(titre.couvertureAffichee, 'https://exemple.org/vol2.jpg');
      expect(
        titre.copierAvec(effacerCouvertureChoisie: true).couvertureAffichee,
        'https://exemple.org/couverture.jpg',
      );
    });

    test('copierAvec remplace ou efface les nouveaux champs', () {
      final copie = titre.copierAvec(
        niveauContenu: niveauContenuErotique,
        couvertureChoisie: '/images/a.png',
      );
      expect(copie.niveauContenu, niveauContenuErotique);
      expect(copie.couvertureChoisie, '/images/a.png');
      expect(copie, isNot(titre));

      final efface = titre.copierAvec(
        niveauContenu: niveauContenuErotique,
        effacerNiveauContenu: true,
        couvertureChoisie: '/images/a.png',
        effacerCouvertureChoisie: true,
      );
      expect(efface.niveauContenu, isNull);
      expect(efface.couvertureChoisie, isNull);

      // Champs inchangés par défaut.
      expect(titre.copierAvec(nom: 'Autre').niveauContenu, titre.niveauContenu);
      expect(titre.copierAvec().hashCode, titre.hashCode);
    });

    test('niveaux par défaut : tout sauf pornographic', () {
      expect(niveauxContenu, hasLength(4));
      expect(
        niveauxContenuParDefaut,
        isNot(contains(niveauContenuPornographique)),
      );
      expect(niveauxContenu, containsAll(niveauxContenuParDefaut));
    });
  });
}
