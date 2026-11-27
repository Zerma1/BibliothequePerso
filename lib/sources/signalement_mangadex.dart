/// Signalement MangaDex@Home : chaque image chargée depuis un serveur du
/// réseau MangaDex@Home doit être signalée à MangaDex (PLAYBOOK.md
/// section 6, « Règles d'usage de MangaDex »).
///
/// Source consultée le 2026-11-15 :
/// https://api.mangadex.org/docs/04-chapter/retrieving-chapter/ (sections
/// « MangaDex@Home, load successes, failures and retries » et « The
/// MangaDex@Home report endpoint »). Règles citées :
/// - « For each image you retrieve (successfully or not) from a base url
///   that doesn't contain mangadex.org [...] Call the network report
///   endpoint to notify it » ;
/// - « It is a POST request to https://api.mangadex.network/report » ;
/// - champs `url` (« The full URL of the image (including https://) »),
///   `success`, `cached` (« true iff the server returned an X-Cache header
///   with a value starting with HIT »), `bytes`, `duration` (« The time (in
///   miliseconds) that the complete retrieval (not TTFB) of the image
///   took ») ;
/// - « The content-type header must be exactly application/json » ;
/// - « On a failure that doesn't result in any response (connection
///   failure, bad SSL certificate, ...) just put 0 for bytes ».
library;

import '../modeles/journal.dart';
import 'client_http_poli.dart';
import 'constantes_sources.dart';
import 'erreur_source.dart';

/// Issue d'un appel à [SignalementMangaDex.signaler].
enum ResultatSignalement {
  /// L'image ne vient pas d'un serveur MangaDex@Home : rien n'a été envoyé.
  nonRequis,

  /// Le signalement a été accepté (réponse 2xx).
  envoye,

  /// L'envoi a échoué ; l'erreur a été avalée et journalisée.
  echec,
}

/// Envoie les signalements MangaDex@Home exigés par la documentation.
///
/// Un échec de signalement ne fait **jamais** échouer le téléchargement :
/// toutes les erreurs sont avalées et journalisées (`Journal`), sans l'URL
/// complète ni le texte de l'erreur (ils peuvent contenir le jeton).
class SignalementMangaDex {
  /// Crée le service de signalement, qui passe par [_client] (seule classe
  /// autorisée à faire du réseau). [adresse] permet de changer le point
  /// d'accès dans les tests.
  SignalementMangaDex(this._client, {Uri? adresse})
    : adresse = adresse ?? Uri.parse(urlSignalementMangaDexAtHome);

  final ClientHttpPoli _client;

  /// Point d'accès du signalement (`https://api.mangadex.network/report`).
  final Uri adresse;

  /// Indique si [urlImage] a été servie par un serveur MangaDex@Home, donc
  /// doit être signalée.
  ///
  /// Règle de la doc : signaler toute image chargée « from a base url that
  /// doesn't contain mangadex.org ». L'URL d'une page est
  /// `<baseUrl>/<data|data-saver>/<hash>/<fichier>` ; le hash et le nom de
  /// fichier sont hexadécimaux, donc « mangadex.org » ne peut venir que de
  /// `baseUrl` : chercher dans l'URL complète revient à appliquer la règle
  /// à `baseUrl` (que le service ne conserve pas). Exemples :
  /// `https://uploads.mangadex.org/...` → non ;
  /// `https://abcdef.xyz123.mangadex.network:12345/jeton/...` → oui.
  ///
  /// Une URL qui n'est pas en http(s) n'est pas une image téléchargée : non.
  static bool estServeurMangaDexAtHome(String urlImage) {
    final uri = Uri.tryParse(urlImage.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return false;
    }
    return !urlImage.toLowerCase().contains(marqueurServeurOfficielMangaDex);
  }

  /// Valeur du champ `cached` : vrai si l'en-tête `X-Cache` de la réponse
  /// commence par `HIT` (« true iff the server returned an X-Cache header
  /// with a value starting with HIT »).
  ///
  /// [enTetes] vient de [ReponseOctets.enTetes] (noms en minuscules) ; la
  /// recherche du nom ignore la casse au cas où. La valeur est comparée sans
  /// tenir compte de la casse ni des espaces autour.
  static bool estEnCache(Map<String, String> enTetes) {
    for (final entree in enTetes.entries) {
      if (entree.key.toLowerCase() == 'x-cache') {
        return entree.value.trim().toUpperCase().startsWith('HIT');
      }
    }
    return false;
  }

  /// Signale le chargement de [urlImage] si (et seulement si) elle vient
  /// d'un serveur MangaDex@Home (voir [estServeurMangaDexAtHome]).
  ///
  /// - [succes] : image récupérée correctement ;
  /// - [enCache] : voir [estEnCache] ;
  /// - [octets] : taille reçue (0 si aucune réponse) ;
  /// - [duree] : durée de la récupération complète, envoyée en ms.
  ///
  /// Ne lève jamais d'exception : renvoie [ResultatSignalement.echec] et
  /// journalise si l'envoi échoue.
  Future<ResultatSignalement> signaler({
    required String urlImage,
    required bool succes,
    required bool enCache,
    required int octets,
    required Duration duree,
  }) async {
    if (!estServeurMangaDexAtHome(urlImage)) {
      return ResultatSignalement.nonRequis;
    }
    try {
      await _client.envoyerJson(
        adresse,
        <String, Object>{
          'url': urlImage,
          'success': succes,
          'bytes': octets < 0 ? 0 : octets,
          'duration': duree.isNegative ? 0 : duree.inMilliseconds,
          'cached': enCache,
        },
        // API MangaDex : User-Agent honnête obligatoire ; aucun en-tête
        // d'authentification (l'application n'en utilise pas).
        userAgent: userAgentApplication,
        // Une seule tentative : voir ClientHttpPoli.envoyerJson.
        nouvellesTentatives: 0,
      );
      return ResultatSignalement.envoye;
    } on Object catch (erreur) {
      // Toute erreur (ErreurSource, mais aussi une erreur inattendue) est
      // avalée : le signalement est un service rendu à MangaDex, jamais une
      // condition du téléchargement. L'URL n'est pas journalisée en entier :
      // `baseUrl` contient un jeton d'accès temporaire.
      Journal.actuel.avertissement(
        CategorieJournal.reseau,
        'Signalement MangaDex@Home impossible '
        '(${Uri.tryParse(urlImage)?.host ?? '?'}) : ${erreur.runtimeType}',
      );
      return ResultatSignalement.echec;
    }
  }

  /// Signale un téléchargement réussi à partir de la [reponse] de
  /// `ClientHttpPoli.recupererOctetsAvecDetails`.
  Future<ResultatSignalement> signalerReussite(
    String urlImage,
    ReponseOctets reponse,
  ) {
    return signaler(
      urlImage: urlImage,
      succes: true,
      enCache: estEnCache(reponse.enTetes),
      octets: reponse.octets.length,
      duree: reponse.duree,
    );
  }

  /// Signale un téléchargement échoué à partir de l'[erreur] levée par
  /// `ClientHttpPoli.recupererOctetsAvecDetails`.
  ///
  /// Taille et durée viennent de [ErreurSource.octetsRecus] et
  /// [ErreurSource.duree] ; à défaut, 0 octet et [dureeParDefaut] (par
  /// exemple mesurée par l'appelant). `cached` vaut toujours `false` : les
  /// en-têtes d'une réponse en erreur ne sont pas conservés.
  Future<ResultatSignalement> signalerEchec(
    String urlImage,
    ErreurSource erreur, {
    Duration dureeParDefaut = Duration.zero,
  }) {
    return signaler(
      urlImage: urlImage,
      succes: false,
      enCache: false,
      octets: erreur.octetsRecus ?? 0,
      duree: erreur.duree ?? dureeParDefaut,
    );
  }
}
