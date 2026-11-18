import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const urlTitre = 'https://mangadex.org/title/ruri';

  group('Titre.descriptionPerso', () {
    test('par défaut null, écrite NULL en base', () {
      final titre = Titre(urlTitre: urlTitre, nom: 'Ruri Dragon');
      expect(titre.descriptionPerso, isNull);
      final map = titre.versMap();
      expect(map.containsKey('description_perso'), isTrue);
      expect(map['description_perso'], isNull);
    });

    test('aller-retour versMap / depuisMap', () {
      final titre = Titre(
        id: 1,
        idSource: 2,
        urlTitre: urlTitre,
        nom: 'Ruri Dragon',
        resume: 'Résumé du site.',
        descriptionPerso: "Mon avis : l'humour.\nÀ relire.",
      );
      final map = titre.versMap();
      expect(map['description_perso'], "Mon avis : l'humour.\nÀ relire.");
      expect(map['resume'], 'Résumé du site.');
      expect(Titre.depuisMap(map), titre);
    });

    test('colonne absente (base ancienne) : null', () {
      expect(
        Titre.depuisMap(<String, Object?>{
          'url_titre': urlTitre,
          'nom': 'Ruri Dragon',
          'type_titre': 'manga',
        }).descriptionPerso,
        isNull,
      );
    });

    test('copierAvec : remplacer, garder, effacer', () {
      final titre = Titre(urlTitre: urlTitre, nom: 'Ruri Dragon');
      final avec = titre.copierAvec(descriptionPerso: 'Texte');
      expect(avec.descriptionPerso, 'Texte');
      // Non fournie : inchangée.
      expect(avec.copierAvec(nom: 'Autre').descriptionPerso, 'Texte');
      // Effacement, prioritaire sur une valeur donnée.
      expect(
        avec.copierAvec(effacerDescriptionPerso: true).descriptionPerso,
        isNull,
      );
      expect(
        avec
            .copierAvec(descriptionPerso: 'X', effacerDescriptionPerso: true)
            .descriptionPerso,
        isNull,
      );
    });

    test('== et hashCode tiennent compte de la description', () {
      final titre = Titre(urlTitre: urlTitre, nom: 'Ruri Dragon');
      final a = titre.copierAvec(descriptionPerso: 'Texte');
      final b = titre.copierAvec(descriptionPerso: 'Texte');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(titre));
      expect(a, isNot(titre.copierAvec(descriptionPerso: 'Autre')));
    });
  });
}
