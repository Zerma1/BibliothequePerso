import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final titre = Titre(
    id: 7,
    idSource: 1,
    urlTitre: 'https://mangadex.org/title/12e28a8a-cbfe-4e12-bab8-b6fb0b9a59b4',
    nom:
        'Shinigami ni Sodaterareta Shoujo wa Shikkoku no Tsurugi wo Mune ni '
        'Idaku',
    typeTitre: TypeTitre.manga,
    urlCouverture: 'https://exemple.org/couverture.jpg',
    resume: 'Résumé',
    auteur: 'Auteur',
    statut: 'En cours',
    titresAlternatifs: const <TitreAlternatif>[
      TitreAlternatif(
        id: 1,
        idTitre: 7,
        nom: "Death's Daughter and the Ebony Blade",
        langue: 'en',
      ),
    ],
    dateDerniereVerification: DateTime.utc(2026, 11, 15, 10, 30),
  );

  group('Titre', () {
    test('versMap puis depuisMap redonne le même titre', () {
      final map = titre.versMap();
      expect(map['type_titre'], 'manga');
      expect(map['date_derniere_verification'], isA<int>());
      // Les titres alternatifs ne sont pas une colonne de `titres`.
      expect(map.containsKey('titres_alternatifs'), isFalse);

      final relu = Titre.depuisMap(
        map,
        titresAlternatifs: titre.titresAlternatifs,
      );
      expect(relu, titre);
      expect(relu.hashCode, titre.hashCode);
    });

    test('versMap omet l\'identifiant d\'un titre non enregistré', () {
      final nouveau = Titre(idSource: 1, urlTitre: 'u', nom: 'n');
      expect(nouveau.versMap().containsKey('id'), isFalse);
    });

    test('depuisMap lit le nombre de chapitres non lus s\'il est fourni', () {
      final map = titre.versMap()..['nombre_chapitres_non_lus'] = 4;
      expect(Titre.depuisMap(map).nombreChapitresNonLus, 4);
      expect(Titre.depuisMap(titre.versMap()).nombreChapitresNonLus, 0);
    });

    test('copierAvec remplace seulement les champs donnés', () {
      final copie = titre.copierAvec(nom: 'Autre', nombreChapitresNonLus: 2);
      expect(copie.nom, 'Autre');
      expect(copie.nombreChapitresNonLus, 2);
      expect(copie.urlTitre, titre.urlTitre);
      expect(copie.titresAlternatifs, titre.titresAlternatifs);
      expect(copie, isNot(titre));
    });

    test('l\'égalité compare aussi les titres alternatifs', () {
      expect(
        titre.copierAvec(titresAlternatifs: const <TitreAlternatif>[]),
        isNot(titre),
      );
    });

    test('la liste des titres alternatifs ne peut pas être modifiée', () {
      expect(
        () => titre.titresAlternatifs.add(const TitreAlternatif(nom: 'x')),
        throwsUnsupportedError,
      );
    });

    test('un type de titre inconnu lève une ErreurBaseDeDonnees', () {
      final map = titre.versMap()..['type_titre'] = 'bd';
      expect(() => Titre.depuisMap(map), throwsA(isA<ErreurBaseDeDonnees>()));
    });

    test('un nom manquant ou mal typé lève une ErreurBaseDeDonnees', () {
      expect(
        () => Titre.depuisMap(titre.versMap()..remove('nom')),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(
        () => Titre.depuisMap(titre.versMap()..['id_source'] = '1'),
        throwsA(
          isA<ErreurBaseDeDonnees>().having(
            (erreur) => erreur.message,
            'message',
            contains('id_source'),
          ),
        ),
      );
    });

    test('un titre sans idSource (construit par un adaptateur) fait '
        'l\'aller-retour', () {
      final sansSource = Titre(urlTitre: 'https://exemple.org/t', nom: 'T');
      expect(sansSource.idSource, isNull);
      expect(sansSource.versMap()['id_source'], isNull);
      expect(Titre.depuisMap(sansSource.versMap()), sansSource);
      expect(sansSource.copierAvec(idSource: 3).idSource, 3);
    });

    test('toString mentionne le nom', () {
      expect(titre.toString(), contains('Shinigami'));
    });
  });

  group('TitreAlternatif', () {
    const alternatif = TitreAlternatif(
      id: 3,
      idTitre: 7,
      nom: '被死神抚养的少女怀抱漆黑之剑',
      langue: 'zh',
    );

    test('versMap puis depuisMap redonne le même titre alternatif', () {
      expect(TitreAlternatif.depuisMap(alternatif.versMap()), alternatif);
    });

    test('une langue NULL devient une chaîne vide', () {
      final map = alternatif.versMap()..['langue'] = null;
      expect(TitreAlternatif.depuisMap(map).langue, '');
    });

    test('copierAvec, == et hashCode sont cohérents', () {
      final copie = alternatif.copierAvec(langue: 'zh');
      expect(copie, alternatif);
      expect(copie.hashCode, alternatif.hashCode);
      expect(alternatif.copierAvec(nom: 'Autre'), isNot(alternatif));
    });
  });
}
