import 'package:bibliotheque_perso/donnees/depot_tickets.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/ticket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outils_tests_donnees.dart';

void main() {
  late Database base;
  late DepotTickets depot;
  late DateTime maintenant;

  Ticket nouveau(String repere, DateTime creation) => Ticket(
    repere: repere,
    titre: 'Ticket $repere',
    type: TypeTicket.question,
    dateCreation: creation,
  );

  setUp(() async {
    base = await ouvrirBaseDeTest();
    maintenant = DateTime.utc(2026, 11, 27, 12);
    depot = DepotTickets(base, horloge: () => maintenant);
  });

  tearDown(() async {
    await base.close();
  });

  test('enregistrer puis charger par repère', () async {
    final ticket = await depot.enregistrer(
      nouveau('BP-000000000001', DateTime.utc(2026, 11, 27)),
    );
    expect(ticket.id, isNotNull);
    expect(await depot.chargerParRepere('BP-000000000001'), ticket);
    expect(await depot.chargerParRepere('BP-inconnu'), isNull);
  });

  test('un repère déjà utilisé est refusé', () async {
    await depot.enregistrer(nouveau('BP-000000000001', DateTime.utc(2026)));
    await expectLater(
      depot.enregistrer(nouveau('BP-000000000001', DateTime.utc(2027))),
      throwsA(isA<ErreurBaseDeDonnees>()),
    );
  });

  test('chargerTous renvoie les plus récents d\'abord', () async {
    await depot.enregistrer(nouveau('BP-a', DateTime.utc(2026, 1)));
    await depot.enregistrer(nouveau('BP-c', DateTime.utc(2026, 3)));
    await depot.enregistrer(nouveau('BP-b', DateTime.utc(2026, 2)));
    final tous = await depot.chargerTous();
    expect(tous.map((t) => t.repere), <String>['BP-c', 'BP-b', 'BP-a']);
  });

  test('enregistrerReleve remplit les infos GitHub ; le premier relevé '
      'n\'est pas signalé nouveau', () async {
    final ticket = await depot.enregistrer(
      nouveau('BP-1', DateTime.utc(2026, 11, 27)),
    );
    final majGithub = DateTime.utc(2026, 11, 27, 11);
    final releve = await depot.enregistrerReleve(
      ticket.id!,
      numero: 7,
      etat: EtatTicket.ouvert,
      etiquettes: const <String>['question'],
      nombreCommentaires: 0,
      dateMajGithub: majGithub,
    );
    expect(releve.numero, 7);
    expect(releve.etat, EtatTicket.ouvert);
    expect(releve.raisonFermeture, isNull);
    expect(releve.etiquettes, <String>['question']);
    expect(releve.nombreCommentaires, 0);
    expect(releve.dateMajGithub, majGithub);
    expect(releve.dateDernierReleve, maintenant);
    expect(releve.dateConsultation, majGithub);
    expect(releve.aDesNouveautes, isFalse);

    // Changement suivant : signalé, puis effacé par la consultation.
    maintenant = DateTime.utc(2026, 11, 28, 12);
    final ferme = await depot.enregistrerReleve(
      ticket.id!,
      numero: 7,
      etat: EtatTicket.ferme,
      raisonFermeture: RaisonFermetureTicket.termine,
      etiquettes: const <String>[],
      nombreCommentaires: 1,
      dateMajGithub: DateTime.utc(2026, 11, 28, 10),
    );
    expect(ferme.raisonFermeture, RaisonFermetureTicket.termine);
    expect(ferme.dateConsultation, majGithub);
    expect(ferme.aDesNouveautes, isTrue);

    expect(await depot.marquerConsulte(ticket.id!), isTrue);
    final consulte = await depot.chargerParRepere('BP-1');
    expect(consulte!.dateConsultation, maintenant);
    expect(consulte.aDesNouveautes, isFalse);

    // Réouverture : la raison de fermeture est effacée.
    final rouvert = await depot.enregistrerReleve(
      ticket.id!,
      numero: 7,
      etat: EtatTicket.ouvert,
      etiquettes: const <String>[],
      nombreCommentaires: 1,
      dateMajGithub: DateTime.utc(2026, 11, 29),
    );
    expect(rouvert.raisonFermeture, isNull);
  });

  test(
    'enregistrerReleve refuse un ticket inconnu ou un numéro déjà pris',
    () async {
      final a = await depot.enregistrer(nouveau('BP-a', DateTime.utc(2026)));
      final b = await depot.enregistrer(nouveau('BP-b', DateTime.utc(2026)));
      Future<Ticket> relever(int id) => depot.enregistrerReleve(
        id,
        numero: 5,
        etat: EtatTicket.ouvert,
        etiquettes: const <String>[],
        nombreCommentaires: 0,
        dateMajGithub: DateTime.utc(2026),
      );
      await relever(a.id!);
      await expectLater(relever(b.id!), throwsA(isA<ErreurBaseDeDonnees>()));
      await expectLater(relever(999), throwsA(isA<ErreurBaseDeDonnees>()));
    },
  );

  test(
    'enregistrerReleveSansResultat ne change que la date du relevé',
    () async {
      final ticket = await depot.enregistrer(
        nouveau('BP-a', DateTime.utc(2026)),
      );
      expect(await depot.enregistrerReleveSansResultat(ticket.id!), isTrue);
      final relu = await depot.chargerParRepere('BP-a');
      expect(relu, ticket.copierAvec(dateDernierReleve: maintenant));
      expect(await depot.enregistrerReleveSansResultat(999), isFalse);
      expect(await depot.marquerConsulte(999), isFalse);
    },
  );

  test('supprimer retire le ticket de la liste', () async {
    final ticket = await depot.enregistrer(nouveau('BP-a', DateTime.utc(2026)));
    expect(await depot.supprimer(ticket.id!), isTrue);
    expect(await depot.chargerTous(), isEmpty);
    expect(await depot.supprimer(ticket.id!), isFalse);
  });

  test('la base refuse les valeurs hors des contraintes CHECK', () async {
    await expectLater(
      base.insert('tickets', <String, Object?>{
        'repere': 'BP-x',
        'titre': 'x',
        'type_ticket': 'autre',
        'date_creation': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
