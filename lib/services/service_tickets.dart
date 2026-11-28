/// Tickets GitHub créés depuis l'application (version 0.4.0).
///
/// Décisions du client : la création passe par la page « New issue »
/// pré-remplie du dépôt public, **sans jeton** ; l'application garde le
/// ticket en base avec un repère `BP-…` écrit dans son texte, puis suit son
/// avancée par l'API publique de GitHub.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../donnees/depot_tickets.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/journal.dart';
import '../modeles/ticket.dart';
import '../sources/client_tickets_github.dart';
import '../sources/constantes_sources.dart';
import '../sources/erreur_source.dart';
import 'erreur_service.dart';

export '../sources/client_tickets_github.dart' show CommentaireTicketGithub;

/// Ticket enregistré par [ServiceTickets.preparerTicket], avec l'adresse de
/// la page GitHub de création pré-remplie à ouvrir dans le navigateur.
class TicketPrepare {
  /// Crée le résultat de la préparation.
  const TicketPrepare({required this.ticket, required this.urlCreation});

  /// Ticket enregistré en base (avec son identifiant et son repère).
  final Ticket ticket;

  /// Page `https://github.com/…/issues/new?title=…&body=…` à ouvrir.
  final Uri urlCreation;
}

/// Résultat d'une actualisation des tickets ([ServiceTickets.actualiser]).
///
/// Ne lève jamais : une erreur de GitHub ou de la base est rangée dans
/// [messageErreur] (et [heureReprise] pour une limite de requêtes).
class ResultatActualisationTickets {
  /// Crée un résultat.
  const ResultatActualisationTickets({
    this.ignoree = false,
    this.nombreSuivis = 0,
    this.nombreRetrouves = 0,
    this.nombreNouveautes = 0,
    this.messageErreur,
    this.heureReprise,
  });

  /// `true` si rien n'a été demandé à GitHub : actualisation automatique
  /// trop rapprochée de la précédente, ou limite de requêtes en cours (voir
  /// alors [heureReprise]).
  final bool ignoree;

  /// Nombre de tickets suivis dans l'application.
  final int nombreSuivis;

  /// Nombre de tickets retrouvés sur GitHub lors de cette actualisation.
  final int nombreRetrouves;

  /// Nombre de tickets qui ont changé sur GitHub depuis le relevé précédent
  /// et que l'utilisateur n'a pas encore consultés.
  final int nombreNouveautes;

  /// Message lisible (en français) si l'actualisation a échoué en tout ou
  /// partie, sinon `null`.
  final String? messageErreur;

  /// Heure (UTC) à partir de laquelle GitHub accepte de nouveau les
  /// requêtes, si sa limite est atteinte.
  final DateTime? heureReprise;

  /// `true` si une erreur est survenue.
  bool get aEchoue => messageErreur != null;
}

/// Création et suivi des tickets GitHub de l'application.
class ServiceTickets {
  /// Crée le service.
  ///
  /// [versionApplication] et [systeme] sont recopiés dans la section
  /// « Informations » de chaque ticket (système : plateforme et version de
  /// l'OS de l'appareil par défaut). [horloge] remplace `DateTime.now` dans
  /// les tests ; [aleatoire] remplace `Random.secure()` pour les repères.
  ServiceTickets(
    this._depot,
    this._client, {
    required String versionApplication,
    String? systeme,
    DateTime Function()? horloge,
    Random? aleatoire,
  }) : _versionApplication = versionApplication,
       _systeme = systeme ?? descriptionSystemeParDefaut(),
       _horloge = horloge ?? DateTime.now,
       _aleatoire = aleatoire ?? Random.secure();

  final DepotTickets _depot;
  final ClientTicketsGithub _client;
  final String _versionApplication;
  final String _systeme;
  final DateTime Function() _horloge;
  final Random _aleatoire;

  Future<ResultatActualisationTickets>? _actualisationEnCours;
  DateTime? _derniereActualisation;

  /// Délai minimal entre deux actualisations **automatiques** : sans jeton,
  /// GitHub n'accorde que 60 requêtes par heure et par adresse IP.
  static const Duration intervalleMinActualisationAuto = Duration(minutes: 5);

  /// Marge retirée à la plus ancienne date de création pour le paramètre
  /// `since` : l'horloge de l'appareil peut avancer sur celle de GitHub.
  static const Duration margeDepuisCreation = Duration(days: 1);

  /// Préfixe des repères écrits dans les tickets.
  static const String prefixeRepere = 'BP-';

  /// Nombre d'octets aléatoires d'un repère (12 caractères hexadécimaux).
  static const int nombreOctetsRepere = 6;

  /// Nombre maximal d'essais pour tirer un repère libre (une collision sur
  /// 48 bits est déjà improbable ; la borne évite toute boucle sans fin).
  static const int nombreMaxEssaisRepere = 5;

  /// Longueur maximale du titre saisi (le reste est coupé).
  static const int longueurMaxTitre = 200;

  /// Description du système par défaut : plateforme et version de l'OS,
  /// sans nom d'appareil ni chemin.
  static String descriptionSystemeParDefaut() {
    try {
      return '${Platform.operatingSystem} (${Platform.operatingSystemVersion})';
    } catch (_) {
      return 'inconnu';
    }
  }

  /// Libellé affichable d'un [type] de ticket.
  static String libelleType(TypeTicket type) => switch (type) {
    TypeTicket.bug => 'Bug',
    TypeTicket.suggestion => 'Suggestion',
    TypeTicket.question => 'Question',
  };

  /// Titre envoyé à GitHub : `[Bug] titre`, `[Suggestion] titre`…
  static String titreGithub(TypeTicket type, String titre) =>
      '[${libelleType(type)}] ${titre.trim()}';

  /// Tire un repère `BP-` + 12 hexadécimaux minuscules (fonction pure,
  /// [aleatoire] fourni par l'appelant).
  static String genererRepere(Random aleatoire) {
    final tampon = StringBuffer(prefixeRepere);
    for (var i = 0; i < nombreOctetsRepere; i++) {
      tampon.write(aleatoire.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return tampon.toString();
  }

  /// Corps Markdown du ticket (fonction pure).
  ///
  /// Ne contient que ce que l'utilisateur a écrit, la version de
  /// l'application et le système : aucun chemin, aucun journal. La dernière
  /// ligne porte le [repere] qui permet de retrouver le ticket.
  static String construireCorps({
    required TypeTicket type,
    required String description,
    required String repere,
    required String versionApplication,
    required String systeme,
  }) {
    final texte = description.trim();
    return '**Type :** ${libelleType(type)}\n'
        '\n'
        '### Description\n'
        '\n'
        '${texte.isEmpty ? '(aucune description)' : texte}\n'
        '\n'
        '### Informations\n'
        '\n'
        "- Version de l'application : $versionApplication\n"
        '- Système : $systeme\n'
        '\n'
        '---\n'
        "Repère : $repere (ne pas modifier : permet le suivi depuis l'application)\n";
  }

  /// Traduit le `state_reason` de GitHub : `completed` → terminé,
  /// `not_planned` → non retenu, autre chose (`reopened`, `duplicate`…) ou
  /// absent → `null`.
  static RaisonFermetureTicket? raisonDepuisGithub(String? raison) =>
      switch (raison) {
        'completed' => RaisonFermetureTicket.termine,
        'not_planned' => RaisonFermetureTicket.nonRetenu,
        _ => null,
      };

  /// Date `since` à demander à GitHub pour [tickets] (fonction pure) : la
  /// plus ancienne date de création moins [margeDepuisCreation], ou `null`
  /// s'il n'y a aucun ticket.
  ///
  /// La date de création (et non celle du dernier relevé) est retenue pour
  /// rester simple et sûr : chaque ticket suivi a été modifié sur GitHub
  /// après sa création locale, donc il est toujours renvoyé ; un ticket
  /// absent du résultat est bien introuvable.
  static DateTime? dateDepuis(List<Ticket> tickets) {
    DateTime? plusAncienne;
    for (final ticket in tickets) {
      if (plusAncienne == null || ticket.dateCreation.isBefore(plusAncienne)) {
        plusAncienne = ticket.dateCreation;
      }
    }
    return plusAncienne?.toUtc().subtract(margeDepuisCreation);
  }

  /// `true` si une actualisation automatique est permise à [maintenant]
  /// (fonction pure) : aucune actualisation depuis
  /// [intervalleMinActualisationAuto].
  static bool actualisationAutoPermise(
    DateTime? derniere,
    DateTime maintenant,
  ) =>
      derniere == null ||
      !maintenant.toUtc().isBefore(
        derniere.toUtc().add(intervalleMinActualisationAuto),
      );

  /// Enregistre un nouveau ticket en base **avant** l'ouverture de la page
  /// de création, et renvoie l'adresse pré-remplie à ouvrir.
  ///
  /// Le ticket est enregistré d'abord : si l'utilisateur envoie l'issue, le
  /// repère est déjà connu et l'issue sera retrouvée à l'actualisation. S'il
  /// abandonne, le ticket reste « non retrouvé » et peut être retiré.
  ///
  /// Lève une [ErreurService] si le titre est vide ou si la base refuse
  /// l'enregistrement.
  Future<TicketPrepare> preparerTicket({
    required String titre,
    required TypeTicket type,
    required String description,
  }) async {
    var titreNettoye = titre.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (titreNettoye.isEmpty) {
      throw const ErreurService('Le titre du ticket est obligatoire.');
    }
    if (titreNettoye.runes.length > longueurMaxTitre) {
      titreNettoye = String.fromCharCodes(
        titreNettoye.runes.take(longueurMaxTitre),
      );
    }
    try {
      final repere = await _tirerRepereLibre();
      final ticket = await _depot.enregistrer(
        Ticket(
          repere: repere,
          titre: titreNettoye,
          type: type,
          dateCreation: _horloge().toUtc(),
        ),
      );
      final url = construireUrlCreationTicket(
        titre: titreGithub(type, titreNettoye),
        corps: construireCorps(
          type: type,
          description: description,
          repere: repere,
          versionApplication: _versionApplication,
          systeme: _systeme,
        ),
      );
      // Ni titre ni description au journal : ils peuvent être personnels.
      Journal.actuel.info(
        CategorieJournal.interface,
        'Ticket préparé (${type.name}, repère $repere)',
      );
      return TicketPrepare(ticket: ticket, urlCreation: url);
    } on ErreurBaseDeDonnees catch (erreur) {
      Journal.actuel.erreur(
        CategorieJournal.base,
        "Ticket : échec de l'enregistrement",
        erreur: erreur,
      );
      throw ErreurService(
        "Le ticket n'a pas pu être enregistré.",
        cause: erreur,
      );
    }
  }

  /// Tire un repère qui n'existe pas encore en base (au plus
  /// [nombreMaxEssaisRepere] essais).
  Future<String> _tirerRepereLibre() async {
    for (var essai = 0; essai < nombreMaxEssaisRepere; essai++) {
      final repere = genererRepere(_aleatoire);
      if (await _depot.chargerParRepere(repere) == null) {
        return repere;
      }
    }
    throw const ErreurBaseDeDonnees(
      'Aucun repère libre trouvé pour le ticket.',
    );
  }

  /// Relève sur GitHub l'état de tous les tickets suivis, en **une seule**
  /// recherche (paginée par le client, au plus quelques pages).
  ///
  /// - [demandeParUtilisateur] à `false` (actualisation automatique, par
  ///   exemple à l'ouverture de l'écran) : ignorée si une actualisation a eu
  ///   lieu depuis moins de [intervalleMinActualisationAuto] ;
  /// - demandée par l'utilisateur : toujours lancée, sauf si la limite de
  ///   GitHub est en cours (le résultat donne alors [heureReprise]).
  ///
  /// Une actualisation déjà en cours est partagée plutôt que relancée. Ne
  /// lève jamais : les erreurs sont rangées dans le résultat.
  Future<ResultatActualisationTickets> actualiser({
    bool demandeParUtilisateur = false,
  }) {
    final enCours = _actualisationEnCours;
    if (enCours != null) {
      return enCours;
    }
    final nouvelle = _actualiser(demandeParUtilisateur)
        .whenComplete(() => _actualisationEnCours = null);
    _actualisationEnCours = nouvelle;
    return nouvelle;
  }

  Future<ResultatActualisationTickets> _actualiser(
    bool demandeParUtilisateur,
  ) async {
    final maintenant = _horloge().toUtc();
    final List<Ticket> tickets;
    try {
      tickets = await _depot.chargerTous();
    } catch (erreur, pile) {
      Journal.actuel.erreur(
        CategorieJournal.base,
        'Tickets : lecture impossible',
        erreur: erreur,
        pile: pile,
      );
      return const ResultatActualisationTickets(
        messageErreur: 'Les tickets enregistrés ne peuvent pas être lus.',
      );
    }
    if (tickets.isEmpty) {
      return const ResultatActualisationTickets();
    }

    // Limite GitHub en cours : aucune requête, même demandée par
    // l'utilisateur (insister peut faire bannir l'application).
    final reprise = _client.heureReprise;
    if (reprise != null && maintenant.isBefore(reprise)) {
      return ResultatActualisationTickets(
        ignoree: true,
        nombreSuivis: tickets.length,
        nombreRetrouves: tickets.where((t) => t.estRetrouve).length,
        messageErreur: _messageLimite(reprise),
        heureReprise: reprise,
      );
    }

    if (!demandeParUtilisateur) {
      // Le dernier relevé en base compte aussi : la limite tient après un
      // redémarrage de l'application.
      var derniere = _derniereActualisation;
      for (final ticket in tickets) {
        final releve = ticket.dateDernierReleve;
        if (releve != null && (derniere == null || releve.isAfter(derniere))) {
          derniere = releve;
        }
      }
      if (!actualisationAutoPermise(derniere, maintenant)) {
        return ResultatActualisationTickets(
          ignoree: true,
          nombreSuivis: tickets.length,
          nombreRetrouves: tickets.where((t) => t.estRetrouve).length,
        );
      }
    }
    _derniereActualisation = maintenant;

    // Réseau d'abord : rien n'est écrit en base si GitHub ne répond pas.
    final Map<String, TicketGithub> trouves;
    try {
      trouves = await _client.recupererTicketsParRepere(<String>{
        for (final ticket in tickets) ticket.repere,
      }, depuis: dateDepuis(tickets));
    } on ErreurLimiteGithub catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.reseau,
        'Tickets : limite de requêtes GitHub atteinte',
      );
      return ResultatActualisationTickets(
        nombreSuivis: tickets.length,
        nombreRetrouves: tickets.where((t) => t.estRetrouve).length,
        messageErreur: _messageLimite(erreur.heureReprise),
        heureReprise: erreur.heureReprise,
      );
    } on ErreurSource catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.reseau,
        'Tickets : actualisation impossible',
        erreur: erreur,
      );
      return ResultatActualisationTickets(
        nombreSuivis: tickets.length,
        nombreRetrouves: tickets.where((t) => t.estRetrouve).length,
        messageErreur: 'Impossible de joindre GitHub : ${erreur.message}.',
      );
    } catch (erreur, pile) {
      Journal.actuel.erreur(
        CategorieJournal.reseau,
        'Tickets : erreur inattendue pendant l\'actualisation',
        erreur: erreur,
        pile: pile,
      );
      return ResultatActualisationTickets(
        nombreSuivis: tickets.length,
        nombreRetrouves: tickets.where((t) => t.estRetrouve).length,
        messageErreur: "Erreur inattendue pendant l'actualisation des tickets.",
      );
    }

    // LIMITE : chaque relevé est écrit séparément (pas de transaction
    // commune) ; si la base échoue au milieu, les tickets déjà écrits gardent
    // leur relevé, les autres le reçoivent à la prochaine actualisation.
    var retrouves = 0;
    var nouveautes = 0;
    var echecsBase = 0;
    for (final ticket in tickets) {
      final id = ticket.id;
      if (id == null) {
        continue;
      }
      // Le client range ses résultats sous le repère normalisé (`BP-` +
      // hexadécimaux minuscules).
      final normalise = extraireReperesTicket(ticket.repere);
      final github = normalise.isEmpty ? null : trouves[normalise.first];
      try {
        if (github == null) {
          await _depot.enregistrerReleveSansResultat(id);
          continue;
        }
        final aJour = await _depot.enregistrerReleve(
          id,
          numero: github.numero,
          etat: github.etat == EtatTicketGithub.ferme
              ? EtatTicket.ferme
              : EtatTicket.ouvert,
          raisonFermeture: github.etat == EtatTicketGithub.ferme
              ? raisonDepuisGithub(github.raisonEtat)
              : null,
          etiquettes: github.etiquettes,
          nombreCommentaires: github.nombreCommentaires,
          dateMajGithub: github.dateMiseAJour,
        );
        retrouves++;
        if (aJour.aDesNouveautes &&
            aJour.dateMajGithub != ticket.dateMajGithub) {
          nouveautes++;
        }
      } catch (erreur) {
        echecsBase++;
        Journal.actuel.erreur(
          CategorieJournal.base,
          'Tickets : relevé non enregistré (repère ${ticket.repere})',
          erreur: erreur,
        );
      }
    }
    Journal.actuel.info(
      CategorieJournal.reseau,
      'Tickets actualisés : $retrouves retrouvé(s) sur ${tickets.length}, '
      '$nouveautes nouveauté(s)',
    );
    return ResultatActualisationTickets(
      nombreSuivis: tickets.length,
      nombreRetrouves: retrouves,
      nombreNouveautes: nouveautes,
      messageErreur: echecsBase == 0
          ? null
          : '$echecsBase ticket(s) n\'ont pas pu être mis à jour.',
    );
  }

  /// Charge tous les tickets suivis, les plus récents d'abord.
  ///
  /// Lève une [ErreurService] si la base ne peut pas être lue.
  Future<List<Ticket>> chargerTickets() async {
    try {
      return await _depot.chargerTous();
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService(
        'Les tickets enregistrés ne peuvent pas être lus.',
        cause: erreur,
      );
    }
  }

  /// Nombre de tickets qui ont changé sur GitHub depuis leur dernière
  /// consultation (pastille « nouveau »). Renvoie 0 si la base ne peut pas
  /// être lue : une pastille absente vaut mieux qu'une erreur.
  Future<int> nombreTicketsAvecNouveautes() async {
    try {
      final tickets = await _depot.chargerTous();
      return tickets.where((ticket) => ticket.aDesNouveautes).length;
    } catch (_) {
      return 0;
    }
  }

  /// Récupère les commentaires du [ticket] (du plus ancien au plus récent)
  /// et le marque consulté (il n'est plus signalé « nouveau »).
  ///
  /// Ticket non retrouvé sur GitHub : liste vide, sans requête ni
  /// consultation. Ticket sans commentaire au dernier relevé : liste vide
  /// sans requête (économie de la limite de 60 requêtes par heure), mais
  /// marqué consulté.
  ///
  /// Lève une [ErreurService] au message lisible si GitHub ne répond pas
  /// (ou si sa limite est atteinte) ; le ticket n'est alors pas marqué
  /// consulté.
  Future<List<CommentaireTicketGithub>> chargerCommentaires(
    Ticket ticket,
  ) async {
    final numero = ticket.numero;
    final id = ticket.id;
    if (numero == null || id == null) {
      return const <CommentaireTicketGithub>[];
    }
    final List<CommentaireTicketGithub> commentaires;
    if (ticket.nombreCommentaires == 0) {
      commentaires = const <CommentaireTicketGithub>[];
    } else {
      try {
        commentaires = await _client.recupererCommentaires(numero);
      } on ErreurLimiteGithub catch (erreur) {
        throw ErreurService(_messageLimite(erreur.heureReprise), cause: erreur);
      } on ErreurSource catch (erreur) {
        Journal.actuel.avertissement(
          CategorieJournal.reseau,
          'Tickets : commentaires du ticket n°$numero illisibles',
          erreur: erreur,
        );
        throw ErreurService(
          'Impossible de lire les commentaires sur GitHub : '
          '${erreur.message}.',
          cause: erreur,
        );
      }
    }
    try {
      await _depot.marquerConsulte(id);
    } on ErreurBaseDeDonnees catch (erreur) {
      // Les commentaires restent affichables ; seule la pastille persiste.
      Journal.actuel.avertissement(
        CategorieJournal.base,
        'Tickets : consultation non enregistrée (n°$numero)',
        erreur: erreur,
      );
    }
    return commentaires;
  }

  /// Retire le [ticket] de l'application (rien n'est supprimé sur GitHub).
  /// Renvoie `false` s'il n'existait plus.
  ///
  /// Lève une [ErreurService] si la base refuse la suppression.
  Future<bool> retirerTicket(Ticket ticket) async {
    final id = ticket.id;
    if (id == null) {
      return false;
    }
    try {
      final retire = await _depot.supprimer(id);
      Journal.actuel.info(
        CategorieJournal.interface,
        'Ticket retiré (repère ${ticket.repere})',
      );
      return retire;
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService("Le ticket n'a pas pu être retiré.", cause: erreur);
    }
  }

  /// Page du [ticket] sur github.com, ou `null` s'il n'est pas encore
  /// retrouvé (numéro inconnu).
  static Uri? urlPageTicket(Ticket ticket) {
    final numero = ticket.numero;
    if (numero == null) {
      return null;
    }
    return Uri(
      scheme: 'https',
      host: hoteSiteGithub,
      path: '/$proprietaireDepotTickets/$nomDepotTickets/issues/$numero',
    );
  }

  static String _messageLimite(DateTime reprise) {
    final locale = reprise.toLocal();
    String deux(int n) => n.toString().padLeft(2, '0');
    return 'Limite de requêtes GitHub atteinte : nouvel essai possible à '
        '${deux(locale.hour)}:${deux(locale.minute)}.';
  }
}
