/// Rapport d'erreur exportable quand l'ajout d'un site ou la lecture d'un
/// titre échoue (tâche SO2 de l'étape 6).
///
/// Le texte produit peut être envoyé tel quel par le client (forum, ticket) :
/// il ne doit contenir **aucune donnée personnelle ni jeton**. Tout texte qui
/// vient du réseau ou d'une exception passe donc par
/// [masquerDonneesPersonnelles] avant d'y figurer.
library;

import '../modeles/source.dart';
import 'constantes_sources.dart';
import 'erreur_source.dart';

/// Texte qui remplace une valeur masquée dans un rapport.
const String texteMasque = '<masqué>';

// Adresse électronique (forme courante, pas la RFC 5322 complète).
final RegExp _motifCourriel = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}',
);

// Jeton JWT (trois blocs base64url, le premier commence toujours par « eyJ »,
// encodage de « {" »).
final RegExp _motifJwt = RegExp(
  r'eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]*)?',
);

// En-têtes d'authentification recopiés dans une page d'erreur ou une cause.
final RegExp _motifEnTeteAuthentification = RegExp(
  r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);

// Nom de paramètre sensible (jeton, mot de passe, session, cookie, clé
// d'API…), suivi de « = » (URL, cookie, formulaire) ou de « ": " (JSON).
// Les noms sont une liste fermée, encadrée par des limites de mot : un motif
// plus large (« auth » dans « author », « sig » dans « design ») masquerait
// des données utiles au diagnostic. Le préfixe `wordpress_logged_in_` est le
// cookie de connexion de WordPress (thèmes Madara et MangaThemesia).
// La valeur s'arrête au premier séparateur d'URL, guillemet ou espace.
final RegExp _motifParametreSensible = RegExp(
  r'''((?<![\w-])["']?(?:access_?token|refresh_?token|id_?token|auth_?token|token|jeton|authorization|password|passwd|pwd|pass|secret|client_?secret|session|session_?id|sessid|phpsessid|sid|cookie|set-cookie|api[_-]?key|apikey|key|csrf|csrf_?token|xsrf-token|nonce|signature|sig|code|wordpress_logged_in_[0-9a-f]*|wordpress_sec_[0-9a-f]*)["']?\s*[=:]\s*["']?)([^&;,"'<>\s]+)''',
  caseSensitive: false,
);

// Jeton temporaire d'un serveur MangaDex@Home : premier segment du chemin
// après l'hôte `*.mangadex.network` (docs/04-chapter/retrieving-chapter :
// baseUrl « valid for 15 minutes », de la forme
// https://<nœud>.mangadex.network:<port>/<jeton>).
final RegExp _motifJetonMangaDexAtHome = RegExp(
  r'(\.mangadex\.network(?::\d+)?/)([^/\s"<>]+)',
  caseSensitive: false,
);

// Adresse IPv4 (une page d'erreur Cloudflare ou d'hébergeur affiche souvent
// l'adresse du client).
final RegExp _motifIpv4 = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');

// Adresse IPv6 : forme complète (au moins quatre groupes, pour ne pas prendre
// une heure « 12:30:45 ») ou abrégée avec « :: » après au moins deux groupes.
// LIMITE : les écritures qui commencent par « :: » ne sont pas reconnues.
final RegExp _motifIpv6 = RegExp(
  r'\b(?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4}\b'
  r'|\b(?:[0-9A-Fa-f]{1,4}:){2,6}:(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?',
);

// Dossier personnel dans un chemin de fichier (cause d'une exception) :
// Windows, macOS et Linux.
final RegExp _motifDossierPersonnel = RegExp(
  r'([A-Za-z]:[\\/](?:Users|Utilisateurs|Documents and Settings)[\\/]|/Users/|/home/)([^\\/\s"<>]+)',
  caseSensitive: false,
);

/// Retire de [texte] les données personnelles et jetons connus : adresses
/// électroniques, jetons JWT, en-têtes `Bearer`/`Basic`, valeurs de
/// paramètres sensibles (token, password, session, cookie, api_key…), jeton
/// MangaDex@Home, adresses IP et nom d'utilisateur des chemins de fichiers.
///
/// LIMITE : nettoyage par motifs ; une donnée personnelle sans forme
/// reconnaissable (un pseudonyme dans une page HTML, par exemple) n'est pas
/// détectée. C'est pourquoi le rapport ne garde que le **début** de la
/// réponse.
String masquerDonneesPersonnelles(String texte) {
  var resultat = texte;
  resultat = resultat.replaceAll(_motifJwt, texteMasque);
  resultat = resultat.replaceAllMapped(
    _motifEnTeteAuthentification,
    (m) => '${m.group(1)} $texteMasque',
  );
  resultat = resultat.replaceAllMapped(
    _motifParametreSensible,
    (m) => '${m.group(1)}$texteMasque',
  );
  resultat = resultat.replaceAllMapped(
    _motifJetonMangaDexAtHome,
    (m) => '${m.group(1)}$texteMasque',
  );
  resultat = resultat.replaceAll(_motifCourriel, texteMasque);
  resultat = resultat.replaceAll(_motifIpv4, texteMasque);
  resultat = resultat.replaceAll(_motifIpv6, texteMasque);
  resultat = resultat.replaceAllMapped(
    _motifDossierPersonnel,
    (m) => '${m.group(1)}$texteMasque',
  );
  return resultat;
}

/// Début d'un corps de réponse, prêt à être cité dans une erreur ou un
/// rapport : espaces regroupés, données personnelles masquées
/// ([masquerDonneesPersonnelles]), puis tronqué à [longueur] caractères
/// (suivi de « … » s'il a été coupé).
///
/// Le masquage a lieu **avant** la troncature finale, pour qu'un jeton coupé
/// en deux ne puisse pas échapper aux motifs.
String extraireDebutReponse(
  String texte, {
  int longueur = longueurMaxExtraitReponse,
}) {
  var compact = texte.replaceAll(RegExp(r'\s+'), ' ').trim();
  // On ne nettoie qu'un morceau raisonnable (une page HTML peut peser des
  // mégaoctets) : 4 fois la longueur voulue laisse une large marge.
  final marge = longueur * 4;
  if (compact.length > marge) {
    compact = compact.substring(0, marge);
  }
  final nettoye = masquerDonneesPersonnelles(compact);
  if (nettoye.length <= longueur) {
    return nettoye;
  }
  return '${nettoye.substring(0, longueur)}…';
}

/// Rapport d'erreur d'une [ErreurSource], exportable en texte
/// ([versTexte]) sans donnée personnelle.
///
/// Le service complète le contexte ([action], [typeDetecte],
/// [versionApplication], [systeme]) et écrit le texte dans un fichier
/// (tâche SE5).
class RapportErreurSource {
  /// Crée le rapport de [erreur].
  ///
  /// - [action] : ce que faisait le client (« Ajout d'un site »…) ;
  /// - [typeDetecte] : type du site s'il est connu du service (sinon celui
  ///   de l'erreur) ;
  /// - [date] : instant de l'échec (par défaut maintenant), écrit en UTC ;
  /// - [versionApplication], [systeme] : informations techniques facultatives
  ///   (par exemple `1.2.0+5`, `windows`).
  RapportErreurSource(
    this.erreur, {
    this.action,
    TypeSource? typeDetecte,
    DateTime? date,
    this.versionApplication,
    this.systeme,
  }) : typeDetecte = typeDetecte ?? erreur.typeDetecte,
       date = (date ?? DateTime.now()).toUtc();

  /// Erreur rapportée.
  final ErreurSource erreur;

  /// Action en cours au moment de l'échec, si connue.
  final String? action;

  /// Type technique du site, si connu.
  final TypeSource? typeDetecte;

  /// Instant de l'échec (UTC).
  final DateTime date;

  /// Version de l'application, si fournie.
  final String? versionApplication;

  /// Système d'exploitation, si fourni.
  final String? systeme;

  /// Produit le texte du rapport : une information par ligne, puis le début
  /// de la réponse. Toutes les valeurs venues du réseau ou d'une exception
  /// sont passées par [masquerDonneesPersonnelles].
  String versTexte() {
    final tampon = StringBuffer()
      ..writeln("Rapport d'erreur — Bibliothèque perso")
      ..writeln('Date (UTC) : ${date.toIso8601String()}');
    void ligne(String libelle, Object? valeur) {
      if (valeur != null && '$valeur'.trim().isNotEmpty) {
        tampon.writeln('$libelle : $valeur');
      }
    }

    ligne(
      'Action',
      action == null ? null : masquerDonneesPersonnelles(action!),
    );
    ligne('Version', versionApplication);
    ligne('Système', systeme);
    ligne('Type de site détecté', typeDetecte?.name ?? 'inconnu');
    ligne('Adresse', masquerDonneesPersonnelles(erreur.url));
    ligne('Domaine', Uri.tryParse(erreur.url)?.host);
    ligne('Code HTTP', erreur.codeStatut);
    ligne(
      'Protection anti-robot',
      erreur.protectionAntiRobot ? 'oui (aucun contournement)' : null,
    );
    ligne('Message', masquerDonneesPersonnelles(erreur.message));
    final cause = erreur.cause;
    if (cause != null) {
      ligne(
        'Cause',
        '${cause.runtimeType} : ${masquerDonneesPersonnelles('$cause')}',
      );
    }
    ligne('Octets reçus', erreur.octetsRecus);
    ligne('Durée (ms)', erreur.duree?.inMilliseconds);
    // L'extrait est déjà nettoyé à sa création ; on le repasse au filtre au
    // cas où une erreur aurait été construite à la main avec un texte brut.
    final extrait = erreur.extraitReponse;
    tampon.writeln('Début de la réponse :');
    tampon.writeln(
      extrait == null || extrait.isEmpty
          ? '(aucune réponse reçue)'
          : masquerDonneesPersonnelles(extrait),
    );
    return tampon.toString();
  }
}
