// Tests de l'étape 8 (M1) sur les modèles : LienTitreSource et
// Chapitre.idSource.
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/lien_titre_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LienTitreSource', () {
    final lien = LienTitreSource(
      id: 3,
      idTitre: 1,
      idSource: 2,
      urlTitre: 'https://www.scan-manga.com/titre/1',
      estPrincipale: true,
      dateAjout: DateTime.utc(2026, 11, 16, 10),
    );

    test('aller-retour versMap / depuisMap', () {
      final map = lien.versMap();
      expect(map['id_titre'], 1);
      expect(map['id_source'], 2);
      expect(map['url_titre'], 'https://www.scan-manga.com/titre/1');
      expect(map['est_principale'], 1);
      expect(
        map['date_ajout'],
        DateTime.utc(2026, 11, 16, 10).millisecondsSinceEpoch,
      );
      expect(LienTitreSource.depuisMap(map), lien);
    });

    test('par défaut : secondaire, sans identifiant ni date', () {
      const secondaire = LienTitreSource(
        idTitre: 1,
        idSource: 2,
        urlTitre: 'https://exemple.org/t',
      );
      expect(secondaire.estPrincipale, isFalse);
      final map = secondaire.versMap();
      expect(map.containsKey('id'), isFalse);
      expect(map['est_principale'], 0);
      expect(map['date_ajout'], isNull);
    });

    test('depuisMap : type invalide ou colonne obligatoire absente', () {
      expect(
        () => LienTitreSource.depuisMap(lien.versMap()..['id_source'] = 'x'),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(
        () => LienTitreSource.depuisMap(lien.versMap()..remove('url_titre')),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      expect(
        () => LienTitreSource.depuisMap(lien.versMap()..['est_principale'] = 2),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('copierAvec, == et hashCode', () {
      expect(lien.copierAvec(), lien);
      expect(lien.copierAvec().hashCode, lien.hashCode);
      final secondaire = lien.copierAvec(estPrincipale: false);
      expect(secondaire.estPrincipale, isFalse);
      expect(secondaire, isNot(lien));
      expect(secondaire.copierAvec(estPrincipale: true), lien);
      expect(lien.copierAvec(idSource: 9).idSource, 9);
    });

    test('estLienSeul : défaut, versMap / depuisMap, copierAvec, ==', () {
      expect(lien.estLienSeul, isFalse);
      expect(lien.versMap()['lien_seul'], 0);
      final lienSeul = lien.copierAvec(estPrincipale: false, estLienSeul: true);
      expect(lienSeul.estLienSeul, isTrue);
      expect(lienSeul.versMap()['lien_seul'], 1);
      expect(LienTitreSource.depuisMap(lienSeul.versMap()), lienSeul);
      expect(lienSeul.copierAvec().estLienSeul, isTrue);
      expect(lienSeul, isNot(lien.copierAvec(estPrincipale: false)));
      expect(
        lienSeul.hashCode,
        lien.copierAvec(estPrincipale: false, estLienSeul: true).hashCode,
      );
      expect(lienSeul.copierAvec(estLienSeul: false).estLienSeul, isFalse);
    });

    test('estLienSeul : colonne absente (avant la migration 8) ou '
        'invalide', () {
      final sansColonne = lien.versMap()..remove('lien_seul');
      expect(LienTitreSource.depuisMap(sansColonne).estLienSeul, isFalse);
      expect(
        () => LienTitreSource.depuisMap(lien.versMap()..['lien_seul'] = 2),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });
  });

  group('Chapitre.idSource', () {
    const chapitre = Chapitre(
      idTitre: 1,
      urlChapitre: 'https://mangadex.org/chapter/1',
      nom: 'Chapitre 1',
      numero: 1,
    );

    test('par défaut null (site principal du titre)', () {
      expect(chapitre.idSource, isNull);
      expect(chapitre.versMap()['id_source'], isNull);
    });

    test('aller-retour versMap / depuisMap', () {
      final avecSource = chapitre.copierAvec(idSource: 4);
      expect(avecSource.versMap()['id_source'], 4);
      expect(Chapitre.depuisMap(avecSource.versMap()), avecSource);
    });

    test('colonne absente (base avant la migration 7) : null', () {
      final map = chapitre.copierAvec(idSource: 4).versMap()
        ..remove('id_source');
      expect(Chapitre.depuisMap(map).idSource, isNull);
    });

    test('type invalide : erreur', () {
      final map = chapitre.versMap()..['id_source'] = 'MangaDex';
      expect(
        () => Chapitre.depuisMap(map),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('== et hashCode tiennent compte de la source', () {
      expect(chapitre.copierAvec(idSource: 4), isNot(chapitre));
      expect(
        chapitre.copierAvec(idSource: 4),
        chapitre.copierAvec(idSource: 4),
      );
      expect(
        chapitre.copierAvec(idSource: 4).hashCode,
        chapitre.copierAvec(idSource: 4).hashCode,
      );
      // copierAvec sans argument garde la source.
      expect(chapitre.copierAvec(idSource: 4).copierAvec().idSource, 4);
    });
  });
}
