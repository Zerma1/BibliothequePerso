/// Tickets GitHub de l'application (version 0.4.0) : liste, actualisation,
/// création et consultation des commentaires.
library;

import '../modeles/ticket.dart';
import '../services/service_tickets.dart';
import 'description_erreur.dart';

/// État de l'écran « Mes tickets » et de sa pastille dans les Paramètres.
///
/// Ne fait aucune requête lui-même : tout passe par [ServiceTickets], qui
/// limite les actualisations automatiques (60 requêtes par heure sans
/// jeton GitHub).
class EtatTickets extends EtatNotifiant {
  /// Crée l'état branché sur le [_service].
  EtatTickets(this._service);

  final ServiceTickets _service;

  List<Ticket> _tickets = const <Ticket>[];
  bool _estCharge = false;
  bool _estEnChargement = false;
  DescriptionErreur? _erreur;
  bool _estEnActualisation = false;
  String? _messageActualisation;
  DateTime? _heureReprise;
  int _nombreNouveautes = 0;

  /// Pages de création pré-remplies des tickets préparés pendant cette
  /// session, par identifiant : elles permettent de rouvrir la page si le
  /// client l'a fermée sans valider.
  // LIMITE : la description saisie n'est pas gardée en base, et le service
  // ne sait pas reconstruire l'adresse d'un ticket préparé lors d'une
  // session précédente ; après un redémarrage, le bouton disparaît.
  final Map<int, Uri> _urlsCreation = <int, Uri>{};

  /// Tickets suivis, les plus récents d'abord.
  List<Ticket> get tickets => _tickets;

  /// `true` une fois la liste lue au moins une fois.
  bool get estCharge => _estCharge;

  /// `true` pendant la lecture de la liste.
  bool get estEnChargement => _estEnChargement;

  /// Erreur de lecture de la liste, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` pendant une actualisation sur GitHub.
  bool get estEnActualisation => _estEnActualisation;

  /// Message lisible de la dernière actualisation échouée (limite GitHub,
  /// réseau…), ou `null`.
  String? get messageActualisation => _messageActualisation;

  /// Heure (UTC) à partir de laquelle GitHub accepte de nouveau les
  /// requêtes, si sa limite est atteinte.
  DateTime? get heureReprise => _heureReprise;

  /// Nombre de tickets qui ont changé sur GitHub depuis leur consultation
  /// (pastille).
  int get nombreNouveautes => _nombreNouveautes;

  /// Page de création pré-remplie du [ticket] si elle est connue (ticket
  /// préparé pendant cette session), sinon `null`.
  Uri? urlCreation(Ticket ticket) {
    final id = ticket.id;
    return id == null ? null : _urlsCreation[id];
  }

  /// Page du [ticket] sur github.com, ou `null` s'il n'est pas retrouvé.
  Uri? urlPage(Ticket ticket) => ServiceTickets.urlPageTicket(ticket);

  /// Relit seulement le nombre de nouveautés (pastille au démarrage), sans
  /// requête réseau. Ne lève jamais.
  Future<void> chargerNombreNouveautes() async {
    final nombre = await _service.nombreTicketsAvecNouveautes();
    if (nombre != _nombreNouveautes) {
      _nombreNouveautes = nombre;
      notifier();
    }
  }

  /// Lit la liste en base (sans réseau).
  Future<void> charger() async {
    if (_estEnChargement) return;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      _appliquerListe(await _service.chargerTickets());
    } catch (exception, pile) {
      _erreur = DescriptionErreur.depuis(exception, pile);
    } finally {
      _estEnChargement = false;
      notifier();
    }
  }

  /// À l'ouverture de l'écran : liste en base, puis actualisation
  /// automatique (ignorée par le service si elle est trop rapprochée).
  Future<void> ouvrir() async {
    await charger();
    if (_erreur == null) {
      await actualiser();
    }
  }

  /// Relève l'état des tickets sur GitHub puis relit la liste. Le bouton
  /// « Actualiser » passe [demandeParUtilisateur] à `true`.
  Future<ResultatActualisationTickets> actualiser({
    bool demandeParUtilisateur = false,
  }) async {
    _estEnActualisation = true;
    notifier();
    final resultat = await _service.actualiser(
      demandeParUtilisateur: demandeParUtilisateur,
    );
    _estEnActualisation = false;
    // Une actualisation automatique ignorée sans erreur ne doit pas effacer
    // le message d'une précédente (la limite peut être encore en cours).
    if (!resultat.ignoree || resultat.aEchoue) {
      _messageActualisation = resultat.messageErreur;
      _heureReprise = resultat.heureReprise;
    }
    notifier();
    if (!resultat.ignoree) {
      await _relireSansAttente();
    }
    return resultat;
  }

  /// Enregistre un nouveau ticket et renvoie la page de création à ouvrir.
  Future<ResultatAction<TicketPrepare>> preparerTicket({
    required TypeTicket type,
    required String titre,
    required String description,
  }) async {
    try {
      final prepare = await _service.preparerTicket(
        titre: titre,
        type: type,
        description: description,
      );
      final id = prepare.ticket.id;
      if (id != null) {
        _urlsCreation[id] = prepare.urlCreation;
      }
      await _relireSansAttente();
      return ResultatAction<TicketPrepare>.reussite(prepare);
    } catch (exception, pile) {
      return ResultatAction<TicketPrepare>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }

  /// Commentaires du [ticket] (le ticket est alors marqué consulté et la
  /// pastille relue).
  Future<ResultatAction<List<CommentaireTicketGithub>>> chargerCommentaires(
    Ticket ticket,
  ) async {
    try {
      final commentaires = await _service.chargerCommentaires(ticket);
      await _relireSansAttente();
      return ResultatAction<List<CommentaireTicketGithub>>.reussite(
        commentaires,
      );
    } catch (exception, pile) {
      return ResultatAction<List<CommentaireTicketGithub>>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }

  /// Retire le [ticket] de l'application (rien n'est supprimé sur GitHub).
  Future<ResultatAction<bool>> retirerTicket(Ticket ticket) async {
    try {
      final retire = await _service.retirerTicket(ticket);
      final id = ticket.id;
      if (id != null) {
        _urlsCreation.remove(id);
      }
      await _relireSansAttente();
      return ResultatAction<bool>.reussite(retire);
    } catch (exception, pile) {
      return ResultatAction<bool>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    }
  }

  /// Relit la liste sans afficher le chargement : la liste déjà affichée
  /// reste en place. Une erreur de lecture est affichée comme au
  /// chargement.
  Future<void> _relireSansAttente() async {
    try {
      _appliquerListe(await _service.chargerTickets());
      _erreur = null;
    } catch (exception, pile) {
      _erreur = DescriptionErreur.depuis(exception, pile);
    }
    notifier();
  }

  void _appliquerListe(List<Ticket> tickets) {
    _tickets = List<Ticket>.unmodifiable(tickets);
    _estCharge = true;
    _nombreNouveautes = tickets.where((t) => t.aDesNouveautes).length;
  }
}
