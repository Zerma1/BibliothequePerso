import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dateAjout = DateTime.utc(2026, 11, 15, 10);
  final dateMaj = DateTime.utc(2026, 11, 15, 11);

  Telechargement exemple() => Telechargement(
    id: 4,
    idChapitre: 12,
    statut: StatutTelechargement.echec,
    nombrePagesTotal: 20,
    nombrePagesFaites: 7,
    messageErreur: 'Erreur 403',
    dateAjout: dateAjout,
    dateMaj: dateMaj,
  );

  group('StatutTelechargement', () {
    test('les valeurs SQL sont celles de la contrainte CHECK', () {
      expect(
        StatutTelechargement.values.map((s) => s.valeurSql).toList(),
        <String>['en_attente', 'en_cours', 'termine', 'echec'],
      );
    });

    test('depuisValeurSql retrouve chaque statut', () {
      for (final statut in StatutTelechargement.values) {
        expect(StatutTelechargement.depuisValeurSql(statut.valeurSql), statut);
      }
    });

    test('une valeur inconnue lève une ErreurBaseDeDonnees', () {
      expect(
        () => StatutTelechargement.depuisValeurSql('enCours'),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });
  });

  group('Telechargement', () {
    test('versMap produit les colonnes snake_case attendues', () {
      expect(exemple().versMap(), <String, Object?>{
        'id': 4,
        'id_chapitre': 12,
        'statut': 'echec',
        'nombre_pages_total': 20,
        'nombre_pages_faites': 7,
        'message_erreur': 'Erreur 403',
        'date_ajout': dateAjout.millisecondsSinceEpoch,
        'date_maj': dateMaj.millisecondsSinceEpoch,
      });
    });

    test('versMap omet l\'id absent', () {
      expect(
        const Telechargement(idChapitre: 1).versMap().containsKey('id'),
        isFalse,
      );
    });

    test('depuisMap(versMap()) redonne le même objet', () {
      expect(Telechargement.depuisMap(exemple().versMap()), exemple());
    });

    test('depuisMap refuse un statut inconnu ou un type inattendu', () {
      final statutInvalide = exemple().versMap()..['statut'] = 'fini';
      expect(
        () => Telechargement.depuisMap(statutInvalide),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
      final typeInvalide = exemple().versMap()..['id_chapitre'] = '12';
      expect(
        () => Telechargement.depuisMap(typeInvalide),
        throwsA(isA<ErreurBaseDeDonnees>()),
      );
    });

    test('valeurs par défaut : en attente, 0 page, sans erreur', () {
      const telechargement = Telechargement(idChapitre: 3);
      expect(telechargement.statut, StatutTelechargement.enAttente);
      expect(telechargement.nombrePagesTotal, 0);
      expect(telechargement.nombrePagesFaites, 0);
      expect(telechargement.messageErreur, isNull);
    });

    test('copierAvec ne remplace que les champs donnés', () {
      final copie = exemple().copierAvec(
        statut: StatutTelechargement.enCours,
        nombrePagesFaites: 8,
      );
      expect(copie.statut, StatutTelechargement.enCours);
      expect(copie.nombrePagesFaites, 8);
      expect(copie.idChapitre, 12);
      expect(copie.messageErreur, 'Erreur 403');
      expect(exemple().copierAvec(), exemple());
    });

    test('== et hashCode comparent tous les champs', () {
      expect(exemple(), exemple());
      expect(exemple().hashCode, exemple().hashCode);
      expect(exemple() == exemple().copierAvec(nombrePagesFaites: 8), isFalse);
    });

    test('progression : null si le total est inconnu, plafonnée à 1', () {
      expect(const Telechargement(idChapitre: 1).progression, isNull);
      expect(
        const Telechargement(
          idChapitre: 1,
          nombrePagesTotal: 4,
          nombrePagesFaites: 1,
        ).progression,
        0.25,
      );
      expect(
        const Telechargement(
          idChapitre: 1,
          nombrePagesTotal: 2,
          nombrePagesFaites: 3,
        ).progression,
        1,
      );
    });
  });
}
