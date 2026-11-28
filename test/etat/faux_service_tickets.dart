// Faux ServiceTickets pour les tests de l'interface (aucun réseau, aucune
// base).
import 'package:bibliotheque_perso/modeles/ticket.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_tickets.dart';

/// Faux service : tickets en mémoire, résultats et erreurs réglables.
class FauxServiceTickets implements ServiceTickets {
  /// Tickets « en base ».
  List<Ticket> tickets = <Ticket>[];

  /// Erreur levée par [chargerTickets], si réglée.
  Object? erreurChargement;

  /// Résultat renvoyé par [actualiser].
  ResultatActualisationTickets resultatActualisation =
      const ResultatActualisationTickets();

  /// Valeurs de `demandeParUtilisateur` reçues par [actualiser].
  final List<bool> actualisations = <bool>[];

  /// Commentaires renvoyés par [chargerCommentaires].
  List<CommentaireTicketGithub> commentaires = <CommentaireTicketGithub>[];

  /// Erreur levée par [chargerCommentaires], si réglée.
  Object? erreurCommentaires;

  /// Tickets retirés.
  final List<Ticket> retires = <Ticket>[];

  /// Saisies reçues par [preparerTicket].
  final List<(String, TypeTicket, String)> preparations =
      <(String, TypeTicket, String)>[];

  /// Adresse de création renvoyée par [preparerTicket].
  Uri urlCreation = Uri.parse('https://github.com/exemple/depot/issues/new');

  int _prochainId = 100;

  @override
  Future<List<Ticket>> chargerTickets() async {
    final erreur = erreurChargement;
    if (erreur != null) throw erreur;
    return List<Ticket>.of(tickets);
  }

  @override
  Future<int> nombreTicketsAvecNouveautes() async =>
      tickets.where((t) => t.aDesNouveautes).length;

  @override
  Future<ResultatActualisationTickets> actualiser({
    bool demandeParUtilisateur = false,
  }) async {
    actualisations.add(demandeParUtilisateur);
    return resultatActualisation;
  }

  @override
  Future<TicketPrepare> preparerTicket({
    required String titre,
    required TypeTicket type,
    required String description,
  }) async {
    preparations.add((titre, type, description));
    if (titre.trim().isEmpty) {
      throw const ErreurService('Le titre du ticket est obligatoire.');
    }
    final ticket = Ticket(
      id: _prochainId++,
      repere: 'BP-000000000001',
      titre: titre.trim(),
      type: type,
      dateCreation: DateTime.utc(2026, 11, 27),
    );
    tickets.insert(0, ticket);
    return TicketPrepare(ticket: ticket, urlCreation: urlCreation);
  }

  @override
  Future<List<CommentaireTicketGithub>> chargerCommentaires(
    Ticket ticket,
  ) async {
    final erreur = erreurCommentaires;
    if (erreur != null) throw erreur;
    // Comme le vrai service : le ticket est marqué consulté.
    tickets = <Ticket>[
      for (final t in tickets)
        t.id == ticket.id && t.dateMajGithub != null
            ? t.copierAvec(dateConsultation: t.dateMajGithub)
            : t,
    ];
    return commentaires;
  }

  @override
  Future<bool> retirerTicket(Ticket ticket) async {
    retires.add(ticket);
    tickets.removeWhere((t) => t.id == ticket.id);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Ticket de test retrouvé sur GitHub.
Ticket ticketRetrouve({
  int id = 1,
  String titre = 'Plantage au démarrage',
  TypeTicket type = TypeTicket.bug,
  EtatTicket etat = EtatTicket.ouvert,
  RaisonFermetureTicket? raison,
  List<String> etiquettes = const <String>[],
  int commentaires = 0,
  bool nouveau = false,
}) {
  final maj = DateTime.utc(2026, 11, 26, 10);
  return Ticket(
    id: id,
    repere: 'BP-00000000000$id',
    titre: titre,
    type: type,
    dateCreation: DateTime.utc(2026, 11, 25),
    numero: 40 + id,
    etat: etat,
    raisonFermeture: raison,
    etiquettes: etiquettes,
    nombreCommentaires: commentaires,
    dateMajGithub: maj,
    dateDernierReleve: maj,
    dateConsultation: nouveau
        ? maj.subtract(const Duration(hours: 1))
        : maj.add(const Duration(hours: 1)),
  );
}

/// Ticket de test pas encore retrouvé sur GitHub.
Ticket ticketEnAttente({int id = 9, String titre = 'Idée de tri'}) => Ticket(
  id: id,
  repere: 'BP-00000000000$id',
  titre: titre,
  type: TypeTicket.suggestion,
  dateCreation: DateTime.utc(2026, 11, 27),
);
