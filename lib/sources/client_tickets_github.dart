/// Lecture des tickets (issues) du dépôt GitHub public de l'application, par
/// l'API REST publique de GitHub, sans jeton (version 0.4.0).
///
/// Sources (docs.github.com, relevées le 2026-11-27) :
/// - « List repository issues » : `GET /repos/{owner}/{repo}/issues`,
///   paramètres `state` (`open`, `closed`, `all`), `sort` (`created`,
///   `updated`, `comments`), `direction`, `since`, `per_page` (max 100),
///   `page` ; les pull requests y figurent aussi et se reconnaissent à la
///   clé `pull_request` ;
/// - « List issue comments » : `GET /repos/{owner}/{repo}/issues/{n}/comments`,
///   « ordered by ascending ID » ;
/// - « Rate limits for the REST API » : 60 requêtes par heure sans jeton
///   (par adresse IP) ; limite dépassée = 403 ou 429, avec
///   `x-ratelimit-remaining` à 0 et `x-ratelimit-reset` (secondes UNIX) ou
///   `retry-after` (secondes) ;
/// - « Creating an issue » : paramètres `title` et `body` de
///   `/issues/new` ; `labels` exige des droits sur le dépôt (sinon 404), il
///   n'est donc jamais utilisé.
library;

import 'dart:convert';

import 'client_http_poli.dart';
import 'constantes_sources.dart';
import 'erreur_source.dart';
import 'lecture_json.dart';
import 'limite_github.dart';

// [ErreurLimiteGithub] et [SuiviLimiteGithub] sont partagés avec le client de
// mise à jour : réexportés pour les appelants existants.
export 'limite_github.dart' show ErreurLimiteGithub, SuiviLimiteGithub;

/// État d'un ticket GitHub (champ `state`).
enum EtatTicketGithub {
  /// `open` : ticket ouvert.
  ouvert,

  /// `closed` : ticket fermé (voir [TicketGithub.raisonEtat]).
  ferme,
}

/// Ticket GitHub retrouvé par son repère `BP-` (résultat de
/// [ClientTicketsGithub.recupererTicketsParRepere]).
class TicketGithub {
  /// Crée un ticket lu depuis l'API.
  const TicketGithub({
    required this.repere,
    required this.numero,
    required this.titre,
    required this.etat,
    required this.raisonEtat,
    required this.etiquettes,
    required this.nombreCommentaires,
    required this.dateMiseAJour,
    required this.urlPage,
  });

  /// Repère `BP-` + 12 hexadécimaux (minuscules) trouvé dans le corps.
  final String repere;

  /// Numéro du ticket dans le dépôt (`number`).
  final int numero;

  /// Titre du ticket (`title`).
  final String titre;

  /// État du ticket (`state`).
  final EtatTicketGithub etat;

  /// Raison de l'état (`state_reason`, texte brut de GitHub : `completed`,
  /// `not_planned`, `reopened`, `duplicate`…), ou `null`.
  final String? raisonEtat;

  /// Noms des étiquettes (`labels[].name`).
  final List<String> etiquettes;

  /// Nombre de commentaires (`comments`).
  final int nombreCommentaires;

  /// Date de dernière mise à jour (`updated_at`, en UTC).
  final DateTime dateMiseAJour;

  /// Adresse de la page du ticket sur github.com (`html_url`).
  final String urlPage;
}

/// Commentaire d'un ticket GitHub (résultat de
/// [ClientTicketsGithub.recupererCommentaires]).
class CommentaireTicketGithub {
  /// Crée un commentaire lu depuis l'API.
  const CommentaireTicketGithub({
    required this.auteur,
    required this.date,
    required this.corps,
  });

  /// Identifiant GitHub de l'auteur (`user.login`), `null` si le compte a
  /// été supprimé (`user` vaut alors `null`).
  final String? auteur;

  /// Date de création (`created_at`, en UTC).
  final DateTime date;

  /// Corps du commentaire tel que saisi (`body`, Markdown brut, à afficher
  /// comme texte brut) ; vide s'il est absent.
  final String corps;
}

/// Expression d'un repère de ticket : `BP-` suivi de 12 hexadécimaux, sans
/// lettre ni chiffre collé avant ou après (un texte plus long n'est pas un
/// repère).
final RegExp _expressionRepere = RegExp(
  r'(?<![0-9A-Za-z])BP-([0-9A-Fa-f]{12})(?![0-9A-Za-z])',
);

/// Renvoie les repères `BP-…` présents dans [texte], normalisés (`BP-` +
/// hexadécimaux en minuscules), sans doublon, dans l'ordre d'apparition.
List<String> extraireReperesTicket(String texte) {
  final reperes = <String>{};
  for (final correspondance in _expressionRepere.allMatches(texte)) {
    reperes.add('BP-${correspondance.group(1)!.toLowerCase()}');
  }
  return reperes.toList(growable: false);
}

/// Construit l'adresse de création d'un ticket pré-rempli sur le dépôt
/// public : `https://github.com/<propriétaire>/<dépôt>/issues/new?title=…&body=…`.
///
/// Les valeurs sont encodées par `Uri(queryParameters: …)` (espaces en `+`,
/// caractères spéciaux en `%XX`, UTF-8). Si l'adresse dépasse [longueurMax]
/// caractères, le corps est tronqué sur une limite de caractère (jamais au
/// milieu d'un caractère composé de deux unités UTF-16), de préférence
/// après un espace, puis suivi de [mentionCorpsTicketTronque] ; les repères
/// `BP-…` coupés par la troncature sont recopiés à la fin, pour que le
/// ticket reste retrouvable. Si le titre seul est encore trop long, il est
/// tronqué lui aussi. Pas de paramètre `labels` (il exige des droits sur le
/// dépôt, sinon GitHub répond 404).
Uri construireUrlCreationTicket({
  required String titre,
  required String corps,
  int longueurMax = longueurMaxUrlCreationTicket,
}) {
  final complete = _urlCreation(titre, corps);
  if (complete.toString().length <= longueurMax) {
    return complete;
  }
  final reperes = extraireReperesTicket(corps);
  final caracteresCorps = corps.runes.toList(growable: false);

  String corpsTronque(int nombre) {
    var debut = String.fromCharCodes(caracteresCorps.take(nombre));
    // Coupure propre : on revient au dernier blanc s'il est proche, pour ne
    // pas couper un mot (ni un repère) en deux.
    final dernierBlanc = debut.lastIndexOf(RegExp(r'\s'));
    if (dernierBlanc > 0 && debut.length - dernierBlanc < 80) {
      debut = debut.substring(0, dernierBlanc);
    }
    final manquants = reperes.where((repere) => !debut.contains(repere));
    return <String>[
      if (debut.trimRight().isNotEmpty) debut.trimRight(),
      mentionCorpsTicketTronque,
      if (manquants.isNotEmpty) manquants.join(' '),
    ].join('\n\n');
  }

  bool tient(String titreEssai, String corpsEssai) =>
      _urlCreation(titreEssai, corpsEssai).toString().length <= longueurMax;

  // Le titre seul (corps réduit à la mention et aux repères) doit tenir ;
  // sinon on le raccourcit d'abord, par recherche dichotomique.
  var titreRetenu = titre;
  if (!tient(titre, corpsTronque(0))) {
    final caracteresTitre = titre.runes.toList(growable: false);
    var bas = 0;
    var haut = caracteresTitre.length;
    while (bas < haut) {
      final milieu = (bas + haut + 1) ~/ 2;
      final essai = '${String.fromCharCodes(caracteresTitre.take(milieu))}…';
      if (tient(essai, corpsTronque(0))) {
        bas = milieu;
      } else {
        haut = milieu - 1;
      }
    }
    titreRetenu = '${String.fromCharCodes(caracteresTitre.take(bas))}…';
  }

  // Plus grand nombre de caractères du corps qui tient, par dichotomie.
  // LIMITE : la longueur encodée n'est pas strictement croissante (un repère
  // gardé n'est plus recopié à la fin) ; la dichotomie trouve alors une
  // coupure valide, pas forcément la plus longue possible.
  var bas = 0;
  var haut = caracteresCorps.length;
  while (bas < haut) {
    final milieu = (bas + haut + 1) ~/ 2;
    if (tient(titreRetenu, corpsTronque(milieu))) {
      bas = milieu;
    } else {
      haut = milieu - 1;
    }
  }
  return _urlCreation(titreRetenu, corpsTronque(bas));
}

Uri _urlCreation(String titre, String corps) => Uri(
  scheme: 'https',
  host: hoteSiteGithub,
  path: '/$proprietaireDepotTickets/$nomDepotTickets/issues/new',
  queryParameters: <String, String>{'title': titre, 'body': corps},
);

/// Fonction qui donne l'heure courante (remplaçable dans les tests).
typedef HorlogeTicketsGithub = DateTime Function();

/// Client de lecture de l'API REST publique de GitHub pour les tickets du
/// dépôt [proprietaireDepotTickets]/[nomDepotTickets], **sans jeton**.
///
/// Toutes les requêtes passent par [ClientHttpPoli] (User-Agent de
/// l'application, 1 s entre deux requêtes vers `api.github.com`, délai
/// d'expiration, nouvelles tentatives sur erreur réseau ou 5xx).
///
/// Méthode de recherche retenue : la **liste des tickets** du dépôt
/// (`state=all`, `sort=updated`, `per_page=100`), filtrée localement sur le
/// corps, plutôt que la recherche (`GET /search/issues`). Raisons :
/// - une seule requête couvre 100 tickets, donc **tous** les repères
///   suivis à la fois, quand la recherche coûterait une requête par repère
///   (10 par minute sans jeton) ;
/// - [recupererTicketsParRepere] accepte `depuis` (`since`) : seuls les
///   tickets modifiés depuis la dernière vérification sont renvoyés ;
/// - pas de dépendance à l'index de recherche (un ticket tout juste créé peut
///   y manquer) ni à son découpage des mots (`BP-` + hexadécimaux).
class ClientTicketsGithub {
  /// Crée le client ; [maintenant] remplace `DateTime.now` dans les tests.
  ///
  /// [limite] : suivi de la limite GitHub à partager avec les autres
  /// clients sans jeton (la limite de 60 requêtes par heure vaut pour toute
  /// l'adresse IP) ; à défaut, un suivi propre à ce client.
  ClientTicketsGithub(
    this._client, {
    HorlogeTicketsGithub? maintenant,
    SuiviLimiteGithub? limite,
  }) : _limite = limite ?? SuiviLimiteGithub(maintenant: maintenant);

  final ClientHttpPoli _client;
  final SuiviLimiteGithub _limite;

  /// Requêtes restantes dans la fenêtre courante selon la dernière réponse
  /// (`x-ratelimit-remaining`), ou `null` si inconnu.
  int? get requetesRestantes => _limite.requetesRestantes;

  /// Heure (UTC) avant laquelle aucune requête n'est envoyée, après une
  /// limite atteinte, ou `null`.
  DateTime? get heureReprise => _limite.heureReprise;

  /// En-têtes envoyés à l'API (en plus du User-Agent de [ClientHttpPoli]).
  static const Map<String, String> _enTetes = <String, String>{
    'Accept': typeMediaApiGithub,
    'X-GitHub-Api-Version': versionApiGithub,
  };

  /// Retrouve les tickets dont le corps contient l'un des [reperes]
  /// (`BP-` + 12 hexadécimaux, casse indifférente).
  ///
  /// Renvoie une table « repère normalisé → ticket » ; un repère absent de la
  /// table n'a pas été trouvé (ticket supprimé, transféré, ou plus ancien que
  /// [depuis]). Les pull requests sont ignorées. Si plusieurs tickets portent
  /// le même repère, le plus ancien (plus petit numéro) est gardé.
  ///
  /// [depuis] : seuls les tickets mis à jour après cette date sont lus
  /// (paramètre `since`), pour économiser les requêtes.
  ///
  /// Au plus [nombreMaxPagesApiGithub] pages de 100 tickets (suivant
  /// l'en-tête `Link` `rel="next"`), arrêt dès que tous les repères sont
  /// trouvés. Lève [ErreurLimiteGithub] si la limite est atteinte, une
  /// [ErreurSource] sinon (404, réseau absent, JSON inattendu).
  Future<Map<String, TicketGithub>> recupererTicketsParRepere(
    Set<String> reperes, {
    DateTime? depuis,
  }) async {
    final cherches = <String>{
      for (final repere in reperes) ...extraireReperesTicket(repere),
    };
    final trouves = <String, TicketGithub>{};
    if (cherches.isEmpty) {
      return trouves;
    }
    Uri? adresse = Uri(
      scheme: 'https',
      host: hoteApiGithub,
      path: '/repos/$proprietaireDepotTickets/$nomDepotTickets/issues',
      queryParameters: <String, String>{
        'state': 'all',
        // Les tickets récemment modifiés d'abord : ce sont ceux dont l'état
        // a pu changer, et ils tiennent le plus souvent dans la 1re page.
        'sort': 'updated',
        'direction': 'desc',
        'per_page': '$taillePageApiGithub',
        if (depuis != null) 'since': _dateIso(depuis),
      },
    );
    for (
      var page = 0;
      adresse != null && page < nombreMaxPagesApiGithub;
      page++
    ) {
      final (liste, suivante) = await _recupererListe(adresse);
      final url = adresse.toString();
      for (final objet in liste) {
        // « You can identify pull requests by the pull_request key ».
        if (objet.containsKey('pull_request')) {
          continue;
        }
        final corps = objet.lireTexteOptionnel('body', url) ?? '';
        for (final repere in extraireReperesTicket(corps)) {
          if (!cherches.contains(repere)) {
            continue;
          }
          final ticket = _lireTicket(objet, repere, url);
          final deja = trouves[repere];
          if (deja == null || ticket.numero < deja.numero) {
            trouves[repere] = ticket;
          }
        }
      }
      if (trouves.length == cherches.length) {
        break;
      }
      adresse = suivante;
    }
    return trouves;
  }

  /// Récupère les commentaires du ticket [numero], du plus ancien au plus
  /// récent (au plus [nombreMaxPagesApiGithub] pages de 100).
  ///
  /// Lève [ErreurLimiteGithub] si la limite est atteinte, une [ErreurSource]
  /// sinon (404 : ticket inexistant ; réseau absent ; JSON inattendu).
  Future<List<CommentaireTicketGithub>> recupererCommentaires(
    int numero,
  ) async {
    final commentaires = <CommentaireTicketGithub>[];
    Uri? adresse = Uri(
      scheme: 'https',
      host: hoteApiGithub,
      path:
          '/repos/$proprietaireDepotTickets/$nomDepotTickets/issues/$numero/comments',
      queryParameters: <String, String>{'per_page': '$taillePageApiGithub'},
    );
    for (
      var page = 0;
      adresse != null && page < nombreMaxPagesApiGithub;
      page++
    ) {
      final (liste, suivante) = await _recupererListe(adresse);
      final url = adresse.toString();
      for (final objet in liste) {
        final auteur = objet.lireObjetOptionnel('user', url);
        commentaires.add(
          CommentaireTicketGithub(
            auteur: auteur?.lireTexteOptionnel('login', url),
            date: _lireDate(objet, 'created_at', url),
            corps: objet.lireTexteOptionnel('body', url) ?? '',
          ),
        );
      }
      adresse = suivante;
    }
    return commentaires;
  }

  /// Lit une page de liste JSON et l'adresse de la page suivante (en-tête
  /// `Link`), en traduisant les erreurs de limite et 404.
  Future<(List<Map<String, Object?>>, Uri?)> _recupererListe(Uri uri) async {
    final url = uri.toString();
    // Aucune requête pendant la limite : insister peut faire bannir
    // l'application (« Exceeding the rate limit »).
    _limite.verifierAvantRequete(url);
    final ReponseOctets reponse;
    try {
      reponse = await _client.recupererOctetsAvecDetails(
        uri,
        enTetes: _enTetes,
      );
    } on ErreurSource catch (erreur) {
      throw _traduireErreur(erreur, url);
    }
    _limite.noterReponse(reponse.enTetes);

    final Object? valeur;
    try {
      valeur = jsonDecode(utf8.decode(reponse.octets));
    } on FormatException catch (erreur) {
      throw ErreurSource(
        url,
        'JSON invalide',
        cause: erreur,
        codeStatut: reponse.codeStatut,
      );
    }
    if (valeur is! List<Object?>) {
      throw ErreurSource(
        url,
        'JSON inattendu : une liste était attendue',
        codeStatut: reponse.codeStatut,
      );
    }
    final liste = <Map<String, Object?>>[];
    for (final element in valeur) {
      if (element is! Map<String, Object?>) {
        throw ErreurSource(
          url,
          "JSON inattendu : la liste doit contenir des objets",
          codeStatut: reponse.codeStatut,
        );
      }
      liste.add(element);
    }
    return (liste, _pageSuivante(reponse.enTetes['link']));
  }

  /// Transforme l'[ErreurSource] de [ClientHttpPoli] en erreur lisible :
  /// [ErreurLimiteGithub] (403/429 de limite), 404 explicite, sinon
  /// inchangée (réseau absent, délai dépassé, 5xx…).
  ErreurSource _traduireErreur(ErreurSource erreur, String url) {
    final limite = _limite.traduireLimite(erreur, url);
    if (limite != null) {
      return limite;
    }
    if (erreur.codeStatut == 404) {
      return ErreurSource(
        url,
        'Introuvable sur GitHub (dépôt privé ou supprimé, ou ticket '
        'inexistant)',
        cause: erreur,
        codeStatut: 404,
      );
    }
    return erreur;
  }

  /// Adresse `rel="next"` de l'en-tête `Link` (« Using pagination in the
  /// REST API »), seulement si elle reste sur `https://api.github.com`.
  static Uri? _pageSuivante(String? lien) {
    if (lien == null) {
      return null;
    }
    final correspondance = RegExp(r'<([^>]+)>\s*;\s*rel="next"')
        .firstMatch(lien);
    final suivante = Uri.tryParse(correspondance?.group(1) ?? '');
    if (suivante == null ||
        suivante.scheme != 'https' ||
        suivante.host != hoteApiGithub) {
      return null;
    }
    return suivante;
  }

  TicketGithub _lireTicket(
    Map<String, Object?> objet,
    String repere,
    String url,
  ) {
    final etatTexte = objet.lireTexte('state', url);
    final EtatTicketGithub etat;
    switch (etatTexte) {
      case 'open':
        etat = EtatTicketGithub.ouvert;
      case 'closed':
        etat = EtatTicketGithub.ferme;
      default:
        throw ErreurSource(url, 'JSON inattendu : état « $etatTexte » inconnu');
    }
    return TicketGithub(
      repere: repere,
      numero: objet.lireEntier('number', url),
      titre: objet.lireTexte('title', url),
      etat: etat,
      raisonEtat: objet.lireTexteOptionnel('state_reason', url),
      etiquettes: _lireEtiquettes(objet, url),
      nombreCommentaires: objet.lireEntier('comments', url),
      dateMiseAJour: _lireDate(objet, 'updated_at', url),
      urlPage: objet.lireTexte('html_url', url),
    );
  }

  /// Noms des étiquettes : le schéma de GitHub décrit chaque élément de
  /// `labels` comme un texte **ou** un objet avec `name`.
  static List<String> _lireEtiquettes(Map<String, Object?> objet, String url) {
    final valeur = objet['labels'];
    if (valeur == null) {
      return const <String>[];
    }
    if (valeur is! List<Object?>) {
      throw ErreurSource(
        url,
        'JSON inattendu : « labels » doit être une liste',
      );
    }
    final noms = <String>[];
    for (final element in valeur) {
      if (element is String) {
        noms.add(element);
      } else if (element is Map<String, Object?>) {
        final nom = element.lireTexteOptionnel('name', url);
        if (nom != null) {
          noms.add(nom);
        }
      }
    }
    return List<String>.unmodifiable(noms);
  }

  static DateTime _lireDate(
    Map<String, Object?> objet,
    String cle,
    String url,
  ) {
    final texte = objet.lireTexte(cle, url);
    final date = DateTime.tryParse(texte);
    if (date == null) {
      throw ErreurSource(url, 'JSON inattendu : date « $cle » illisible');
    }
    return date.toUtc();
  }

  /// Date ISO 8601 attendue par `since` : `YYYY-MM-DDTHH:MM:SSZ`.
  static String _dateIso(DateTime date) {
    final texte = date.toUtc().toIso8601String();
    // `toIso8601String` ajoute les millisecondes ; on les retire.
    final point = texte.indexOf('.');
    return point < 0 ? texte : '${texte.substring(0, point)}Z';
  }
}
