import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/ticket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final creation = DateTime.utc(2026, 11, 27, 10);
  final complet = Ticket(
    id: 3,
    repere: 'BP-0123456789ab',
    titre: 'Plantage au démarrage',
    type: TypeTicket.bug,
    dateCreation: creation,
    numero: 42,
    etat: EtatTicket.ferme,
    raisonFermeture: RaisonFermetureTicket.nonRetenu,
    etiquettes: const <String>['bug', "besoin d'infos"],
    nombreCommentaires: 2,
    dateMajGithub: DateTime.utc(2026, 11, 28),
    dateDernierReleve: DateTime.utc(2026, 11, 28, 1),
    dateConsultation: DateTime.utc(2026, 11, 27, 12),
  );

  test('versMap puis depuisMap redonne le même ticket', () {
    final map = complet.versMap();
    expect(map['type_ticket'], 'bug');
    expect(map['etat'], 'ferme');
    expect(map['raison_fermeture'], 'non_retenu');
    expect(map['etiquettes'], '["bug","besoin d\'infos"]');
    expect(Ticket.depuisMap(map), complet);
    expect(Ticket.depuisMap(map).hashCode, complet.hashCode);
  });

  test('un ticket pas encore retrouvé a des infos GitHub vides', () {
    final ticket = Ticket(
      repere: 'BP-aaaaaaaaaaaa',
      titre: 'Idée',
      type: TypeTicket.suggestion,
      dateCreation: creation,
    );
    final relu = Ticket.depuisMap(ticket.versMap());
    expect(relu, ticket);
    expect(relu.estRetrouve, isFalse);
    expect(relu.etat, isNull);
    expect(relu.etiquettes, isEmpty);
    expect(relu.aDesNouveautes, isFalse);
  });

  test('aDesNouveautes compare la mise à jour GitHub à la consultation', () {
    expect(complet.aDesNouveautes, isTrue);
    expect(
      complet
          .copierAvec(dateConsultation: DateTime.utc(2026, 11, 29))
          .aDesNouveautes,
      isFalse,
    );
  });

  test('copierAvec remplace seulement les champs donnés', () {
    final copie = complet.copierAvec(titre: 'Autre', etiquettes: <String>[]);
    expect(copie.titre, 'Autre');
    expect(copie.etiquettes, isEmpty);
    expect(copie.repere, complet.repere);
    expect(copie == complet, isFalse);
  });

  test('des valeurs invalides en base lèvent une ErreurBaseDeDonnees', () {
    final map = complet.versMap();
    expect(
      () => Ticket.depuisMap(<String, Object?>{...map, 'etat': 'perdu'}),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(
      () => Ticket.depuisMap(<String, Object?>{...map, 'etiquettes': '{'}),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(
      () => Ticket.depuisMap(<String, Object?>{...map, 'etiquettes': '[1]'}),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
    expect(
      () => Ticket.depuisMap(<String, Object?>{...map, 'date_creation': null}),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
  });
}
