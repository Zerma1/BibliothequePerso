/// Client HTTP « poli » : seule classe du projet autorisée à importer
/// `package:http` (PLAYBOOK.md section 6, règles réseau).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../modeles/journal.dart';
import 'constantes_sources.dart';
import 'detection_image.dart';
import 'erreur_source.dart';
import 'protection_anti_robot.dart';
import 'rapport_erreur_source.dart';

/// Fonction qui donne l'heure courante (remplaçable dans les tests).
typedef FonctionHorloge = DateTime Function();

/// Fonction qui attend une durée (remplaçable dans les tests pour ne pas
/// ralentir la suite de tests).
typedef FonctionAttente = Future<void> Function(Duration duree);

/// Limite de débit supplémentaire, plus stricte que la règle « 1 s par
/// domaine », pour un point d'accès particulier.
///
/// Exemple : l'API MangaDex limite `GET /at-home/server/{id}` à 40 requêtes
/// par minute (docs/2-limitations).
class LimiteRequetes {
  /// Crée une limite identifiée par [cle] : deux requêtes portant la même clé
  /// sont espacées d'au moins [delaiMinimal].
  const LimiteRequetes(this.cle, this.delaiMinimal);

  /// Identifiant partagé par toutes les requêtes soumises à cette limite.
  final String cle;

  /// Écart minimal entre le début de deux requêtes de même [cle].
  final Duration delaiMinimal;
}

/// Octets d'une réponse réussie, avec les informations utiles pour mesurer le
/// téléchargement (signalement MangaDex@Home : cache, taille, durée).
class ReponseOctets {
  /// Crée le résultat d'un téléchargement réussi.
  const ReponseOctets({
    required this.octets,
    required this.enTetes,
    required this.duree,
    required this.codeStatut,
  });

  /// Corps brut de la réponse.
  final Uint8List octets;

  /// En-têtes de la réponse, noms en minuscules (normalisés par
  /// [ClientHttpPoli]), par exemple `x-cache` ou `content-type`.
  final Map<String, String> enTetes;

  /// Durée de la requête réussie, du départ à la réception complète du corps
  /// (hors attente du créneau du domaine et hors tentatives précédentes).
  final Duration duree;

  /// Code de statut HTTP (2xx).
  final int codeStatut;
}

/// Client HTTP qui respecte la charge des sites lus.
///
/// Il applique les règles de PLAYBOOK.md section 6 :
/// - en-tête `User-Agent` honnête de l'application par défaut, pour tous les
///   sites ([userAgentApplication], tâche T1 : un faux User-Agent de
///   navigateur est repéré par les protections anti-robot) ;
/// - page de défi anti-robot (403/429/503 « Just a moment… ») reconnue et
///   signalée par une [ErreurSource] dont `protectionAntiRobot` vaut `true`,
///   sans nouvelle tentative ni contournement ;
/// - en-tête `Referer` optionnel, que beaucoup de sites exigent pour les
///   images ;
/// - au moins [delaiParDomaine] entre le début de deux requêtes vers un même
///   domaine, plus les éventuelles [LimiteRequetes] plus strictes ;
/// - délai d'expiration de [delaiExpiration] par tentative ;
/// - au plus [nombreNouvellesTentatives] nouvelles tentatives, seulement sur
///   une erreur réseau, un délai dépassé, une réponse 5xx ou 429 (aucune par
///   défaut pour un `POST`, voir [envoyerJson]) ;
/// - tout échec lève une [ErreurSource] avec l'URL et la cause.
class ClientHttpPoli {
  /// Crée le client.
  ///
  /// [client] permet d'injecter un `MockClient` dans les tests ; [maintenant]
  /// et [attendre] permettent de simuler le temps.
  ClientHttpPoli({
    http.Client? client,
    this.userAgentParDefaut = userAgentApplication,
    this.delaiParDomaine = delaiMinimalParDomaine,
    this.delaiExpiration = delaiExpirationRequete,
    this.nombreNouvellesTentatives = nombreMaxNouvellesTentatives,
    FonctionHorloge? maintenant,
    FonctionAttente? attendre,
  }) : _client = client ?? http.Client(),
       _maintenant = maintenant ?? DateTime.now,
       _attendre = attendre ?? _attendreReellement;

  final http.Client _client;
  final FonctionHorloge _maintenant;
  final FonctionAttente _attendre;

  /// User-Agent envoyé quand la requête n'en précise pas d'autre.
  final String userAgentParDefaut;

  /// Écart minimal entre le début de deux requêtes vers un même domaine.
  final Duration delaiParDomaine;

  /// Délai d'expiration de chaque tentative.
  final Duration delaiExpiration;

  /// Nombre maximal de nouvelles tentatives après le premier échec.
  final int nombreNouvellesTentatives;

  /// Premier instant où une nouvelle requête peut partir, par domaine ou par
  /// clé de [LimiteRequetes].
  final Map<String, DateTime> _creneauxLibres = <String, DateTime>{};

  static Future<void> _attendreReellement(Duration duree) =>
      Future<void>.delayed(duree);

  /// Récupère [uri] et renvoie le corps décodé en texte (HTML, JSON…).
  ///
  /// Le jeu de caractères vient de l'en-tête `Content-Type` ; à défaut, on
  /// décode en UTF-8 (le défaut de `package:http` est latin-1, ce qui abîme
  /// les pages UTF-8 qui ne déclarent pas leur encodage).
  ///
  /// Lève une [ErreurSource] en cas d'échec, avec `protectionAntiRobot` à
  /// `true` si la page reçue (même en 200) est un défi anti-robot.
  Future<String> recupererTexte(
    Uri uri, {
    String? referer,
    String? userAgent,
    Map<String, String> enTetes = const <String, String>{},
    LimiteRequetes? limite,
  }) async {
    final (reponse, _) = await _executer(
      uri,
      referer: referer,
      userAgent: userAgent,
      enTetes: enTetes,
      limite: limite,
      nouvellesTentatives: nombreNouvellesTentatives,
    );
    final String texte;
    try {
      texte = _decoderTexte(reponse);
    } on FormatException catch (erreur) {
      throw ErreurSource(
        uri.toString(),
        'Réponse illisible (encodage du texte)',
        cause: erreur,
        codeStatut: reponse.statusCode,
      );
    }
    // Certains défis sont servis en 200 (après une redirection suivie par
    // `package:http`) : sans ce contrôle, l'adaptateur analyserait la page
    // de défi et signalerait une « structure inattendue » trompeuse.
    if (estPageDefiAntiRobot(texte)) {
      Journal.actuel.erreur(
        CategorieJournal.reseau,
        'GET ${masquerDonneesSensibles(uri.toString())} : protection '
        'anti-robot détectée (page de défi servie en '
        'HTTP ${reponse.statusCode})',
      );
      throw erreurProtectionAntiRobot(
        uri,
        codeStatut: reponse.statusCode,
        octetsRecus: reponse.bodyBytes.length,
        extraitReponse: _extrait(reponse),
      );
    }
    return texte;
  }

  /// Récupère [uri] et renvoie le corps brut (images…).
  ///
  /// [referer] est envoyé dans l'en-tête `Referer`, que beaucoup de sites
  /// exigent pour servir leurs images. Lève une [ErreurSource] en cas d'échec.
  ///
  /// [exigerImage] : voir [recupererOctetsAvecDetails].
  Future<Uint8List> recupererOctets(
    Uri uri, {
    String? referer,
    String? userAgent,
    Map<String, String> enTetes = const <String, String>{},
    LimiteRequetes? limite,
    bool exigerImage = false,
  }) async {
    final reponse = await recupererOctetsAvecDetails(
      uri,
      referer: referer,
      userAgent: userAgent,
      enTetes: enTetes,
      limite: limite,
      exigerImage: exigerImage,
    );
    return reponse.octets;
  }

  /// Comme [recupererOctets], mais renvoie aussi les en-têtes de la réponse
  /// et la durée de la requête réussie ([ReponseOctets]).
  ///
  /// [nouvellesTentatives] remplace, pour cet appel, le nombre de nouvelles
  /// tentatives (plafonné à [nombreNouvellesTentatives]). Pour une image
  /// servie par MangaDex@Home, passer `0` : la doc demande de signaler
  /// chaque échec puis de redemander une adresse de serveur
  /// (`/at-home/server`) plutôt que d'insister sur le même nœud.
  ///
  /// En cas d'échec, l'[ErreurSource] levée porte [ErreurSource.codeStatut],
  /// [ErreurSource.octetsRecus] et [ErreurSource.duree] de la dernière
  /// tentative.
  ///
  /// [exigerImage] : `true` pour lever une [ErreurSource] si la réponse
  /// finale (après les redirections suivies par `package:http`) n'est pas une
  /// image. Les **octets** décident d'abord : une signature JPEG, PNG, GIF,
  /// WEBP, AVIF, HEIF ou BMP ([detecterFormatImage]) est acceptée quel que
  /// soit le `Content-Type` (absent, `application/octet-stream` ou faux).
  /// Sans signature reconnue, seul un `Content-Type` `image/*` est accepté,
  /// et jamais pour une page HTML : une page anti-robot servie en 200 n'est
  /// pas prise pour une image (journal des erreurs, E10). L'erreur porte le
  /// code de statut, la taille, la durée, le type détecté et, si la réponse
  /// est du texte, un court extrait nettoyé (jamais d'octets binaires) ;
  /// aucune nouvelle tentative (la même requête recevrait la même page).
  Future<ReponseOctets> recupererOctetsAvecDetails(
    Uri uri, {
    String? referer,
    String? userAgent,
    Map<String, String> enTetes = const <String, String>{},
    LimiteRequetes? limite,
    int? nouvellesTentatives,
    bool exigerImage = false,
  }) async {
    final (reponse, duree) = await _executer(
      uri,
      referer: referer,
      userAgent: userAgent,
      enTetes: enTetes,
      limite: limite,
      nouvellesTentatives: _plafonnerTentatives(nouvellesTentatives),
      // Une ligne par image (60 par chapitre) noierait le journal : le
      // succès n'est gardé qu'en débogage, les échecs restent visibles.
      niveauSucces: NiveauJournal.debogage,
    );
    if (exigerImage) {
      _verifierImage(uri, reponse, duree);
    }
    return ReponseOctets(
      octets: reponse.bodyBytes,
      // `IOClient` met déjà les noms en minuscules, mais pas tous les clients
      // (MockClient, clients web) : on normalise pour une lecture fiable.
      enTetes: Map<String, String>.unmodifiable(<String, String>{
        for (final entree in reponse.headers.entries)
          entree.key.toLowerCase(): entree.value,
      }),
      duree: duree,
      codeStatut: reponse.statusCode,
    );
  }

  /// Envoie [corps] encodé en JSON par `POST` vers [uri] et renvoie le corps
  /// de la réponse décodé en texte.
  ///
  /// L'en-tête `Content-Type` vaut exactement `application/json` (le corps
  /// est transmis en octets UTF-8 : avec un corps texte, `package:http`
  /// ajouterait « ; charset=utf-8 », or MangaDex exige « exactly
  /// application/json » pour son signalement).
  ///
  /// Mêmes règles que les lectures : User-Agent, créneau par domaine (et
  /// [limite]), délai d'expiration, [ErreurSource] en cas d'échec, créneau du
  /// domaine repoussé après un 429.
  ///
  /// Nouvelles tentatives : **aucune par défaut**. Un `POST` n'est pas
  /// idempotent : après un délai dépassé ou une coupure, on ne sait pas si
  /// le serveur a déjà traité la requête, et la renvoyer pourrait la
  /// dupliquer. L'appelant qui sait que son envoi est sans risque peut
  /// passer [nouvellesTentatives] (plafonné à [nombreNouvellesTentatives]).
  /// Le signalement MangaDex@Home n'en a pas besoin : c'est une mesure
  /// statistique, une mesure perdue vaut mieux qu'une mesure comptée deux
  /// fois.
  Future<String> envoyerJson(
    Uri uri,
    Object? corps, {
    String? userAgent,
    Map<String, String> enTetes = const <String, String>{},
    LimiteRequetes? limite,
    int nouvellesTentatives = 0,
  }) async {
    final List<int> octetsCorps;
    try {
      octetsCorps = utf8.encode(jsonEncode(corps));
    } on JsonUnsupportedObjectError catch (erreur) {
      throw ErreurSource(
        uri.toString(),
        'Corps de requête impossible à encoder en JSON',
        cause: erreur,
      );
    }
    final (reponse, _) = await _executer(
      uri,
      referer: null,
      userAgent: userAgent,
      enTetes: <String, String>{
        ...enTetes,
        // Placé après [enTetes] : la valeur exacte ne peut pas être écrasée.
        'Content-Type': 'application/json',
      },
      limite: limite,
      nouvellesTentatives: _plafonnerTentatives(nouvellesTentatives),
      corpsPost: octetsCorps,
      // Signalements MangaDex@Home : un par image, même raison que pour
      // [recupererOctetsAvecDetails].
      niveauSucces: NiveauJournal.debogage,
    );
    try {
      return _decoderTexte(reponse);
    } on FormatException catch (erreur) {
      throw ErreurSource(
        uri.toString(),
        'Réponse illisible (encodage du texte)',
        cause: erreur,
        codeStatut: reponse.statusCode,
      );
    }
  }

  /// Envoie un formulaire par `POST` vers [uri] (corps
  /// `application/x-www-form-urlencoded` fait des [champs], vide si aucun)
  /// et renvoie le corps de la réponse décodé en texte.
  ///
  /// Sert aux requêtes de **lecture** publiques que les thèmes WordPress font
  /// en `POST` depuis leurs propres pages (liste des chapitres de Madara :
  /// `<titre>/ajax/chapters/` ou `admin-ajax.php`), exactement comme le
  /// navigateur d'un lecteur : l'en-tête `X-Requested-With: XMLHttpRequest`
  /// est celui qu'envoie jQuery.
  ///
  /// Mêmes règles que les autres requêtes (User-Agent, [referer], créneau par
  /// domaine, délai d'expiration, [ErreurSource] en cas d'échec).
  /// Nouvelles tentatives : aucune par défaut (un `POST` n'est en général
  /// pas idempotent, voir [envoyerJson]) ; l'appelant qui sait que la requête
  /// ne fait que lire passe [nouvellesTentatives] (plafonné à
  /// [nombreNouvellesTentatives]).
  Future<String> envoyerFormulaire(
    Uri uri, {
    Map<String, String> champs = const <String, String>{},
    String? referer,
    String? userAgent,
    Map<String, String> enTetes = const <String, String>{},
    LimiteRequetes? limite,
    int nouvellesTentatives = 0,
  }) async {
    // `Uri(queryParameters: …).query` encode les champs comme un formulaire
    // HTML (clé=valeur&…, caractères spéciaux échappés).
    final corps = champs.isEmpty
        ? const <int>[]
        : utf8.encode(Uri(queryParameters: champs).query);
    final (reponse, _) = await _executer(
      uri,
      referer: referer,
      userAgent: userAgent,
      enTetes: <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
        ...enTetes,
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      },
      limite: limite,
      nouvellesTentatives: _plafonnerTentatives(nouvellesTentatives),
      corpsPost: corps,
    );
    try {
      return _decoderTexte(reponse);
    } on FormatException catch (erreur) {
      throw ErreurSource(
        uri.toString(),
        'Réponse illisible (encodage du texte)',
        cause: erreur,
        codeStatut: reponse.statusCode,
      );
    }
  }

  /// Ferme le client HTTP sous-jacent (à appeler à la fermeture de l'app).
  void fermer() => _client.close();

  /// Ramène [demande] entre 0 et [nombreNouvellesTentatives] (`null` =
  /// valeur du client) : un appelant ne peut pas dépasser la règle du
  /// PLAYBOOK (2 nouvelles tentatives au maximum).
  int _plafonnerTentatives(int? demande) {
    if (demande == null || demande > nombreNouvellesTentatives) {
      return nombreNouvellesTentatives;
    }
    return demande < 0 ? 0 : demande;
  }

  /// Exécute la requête (GET, ou POST si [corpsPost] est fourni) avec les
  /// règles du client, et renvoie la réponse 2xx avec la durée de la
  /// tentative réussie.
  ///
  /// [niveauSucces] : niveau de la ligne de journal écrite pour une requête
  /// réussie. `info` pour les pages et l'API (une ligne par étape utile) ;
  /// `debogage` pour les requêtes répétées en masse (images de chapitre,
  /// signalements MangaDex@Home), qui sinon noieraient les rapports d'erreur
  /// (200 dernières lignes) et rempliraient le fichier de journal. Les
  /// échecs, nouveaux essais, 429 et pages anti-robot gardent leur niveau.
  Future<(http.Response, Duration)> _executer(
    Uri uri, {
    required String? referer,
    required String? userAgent,
    required Map<String, String> enTetes,
    required LimiteRequetes? limite,
    required int nouvellesTentatives,
    List<int>? corpsPost,
    NiveauJournal niveauSucces = NiveauJournal.info,
  }) async {
    final url = uri.toString();
    final methode = corpsPost == null ? 'GET' : 'POST';
    // URL masquée une seule fois : jetons de session MangaDex, `?token=`…
    // ne doivent jamais apparaître dans le journal.
    final urlJournal = masquerDonneesSensibles(url);
    // Seuls http et https ont un sens ici ; un hôte vide rendrait la règle
    // « 1 s par domaine » inopérante.
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      Journal.actuel.avertissement(
        CategorieJournal.reseau,
        '$methode $urlJournal : URL invalide (http:// ou https:// attendu)',
      );
      throw ErreurSource(url, 'URL invalide : http:// ou https:// attendu');
    }

    final entetesRequete = <String, String>{
      'User-Agent': userAgent ?? userAgentParDefaut,
      'Referer': ?referer,
      ...enTetes,
    };

    final hote = uri.host.toLowerCase();
    ErreurSource? derniereErreur;
    // Nombre d'essais réellement envoyés, pour la ligne finale du journal.
    var essais = 0;
    for (var tentative = 0; tentative <= nouvellesTentatives; tentative++) {
      if (tentative > 0) {
        Journal.actuel.avertissement(
          CategorieJournal.reseau,
          '$methode $urlJournal : nouvel essai '
          '${tentative + 1}/${nouvellesTentatives + 1} '
          '(${_causeCourte(derniereErreur)})',
        );
      }
      await _reserverCreneau(hote, limite);
      essais = tentative + 1;

      final attenteAvantNouvelleTentative =
          attenteBaseNouvelleTentative * (tentative + 1);
      // Après un 429, l'attente passe par le créneau du domaine (partagé par
      // toutes les requêtes) plutôt que par une attente propre à celle-ci.
      var attenteViaCreneau = false;
      // Chronomètre monotone : la durée mesurée sert au signalement
      // MangaDex@Home (« complete retrieval (not TTFB) ») ; `http.get` et
      // `http.post` ne rendent la main qu'une fois le corps entier reçu.
      final chrono = Stopwatch()..start();
      try {
        final envoi = corpsPost == null
            ? _client.get(uri, headers: entetesRequete)
            : _client.post(uri, headers: entetesRequete, body: corpsPost);
        final reponse = await envoi.timeout(delaiExpiration);
        chrono.stop();
        final code = reponse.statusCode;
        if (code >= 200 && code < 300) {
          // Une ligne par requête réussie : jamais le corps, seulement sa
          // taille (une page peut contenir des données personnelles).
          // `estActif` évite de construire le message d'une ligne de
          // débogage ignorée (une par image de chapitre).
          if (Journal.actuel.estActif(niveauSucces)) {
            Journal.actuel.journaliser(
              niveauSucces,
              CategorieJournal.reseau,
              '$methode $urlJournal : '
              '${_resume(code, reponse.bodyBytes.length, chrono.elapsed, essais)}',
            );
          }
          return (reponse, chrono.elapsed);
        }
        // Extrait nettoyé des données personnelles (une page d'erreur peut
        // afficher l'adresse IP ou un jeton) : il est cité dans le message
        // affiché et gardé à part pour le rapport d'erreur exportable.
        final extrait = _extrait(reponse);
        // Page de défi anti-robot : réessayer ne servirait à rien (la même
        // requête reçoit le même défi) et insister ressemblerait à une
        // attaque. On s'arrête tout de suite avec une erreur dédiée ;
        // aucune tentative de résoudre le défi (PLAYBOOK.md section 10).
        if (estReponseDefiAntiRobot(
          codeStatut: code,
          enTetes: reponse.headers,
          corps: utf8.decode(reponse.bodyBytes, allowMalformed: true),
        )) {
          Journal.actuel.erreur(
            CategorieJournal.reseau,
            '$methode $urlJournal : protection anti-robot détectée, '
            '${_resume(code, reponse.bodyBytes.length, chrono.elapsed, essais)}',
          );
          throw erreurProtectionAntiRobot(
            uri,
            codeStatut: code,
            octetsRecus: reponse.bodyBytes.length,
            duree: chrono.elapsed,
            extraitReponse: extrait,
          );
        }
        derniereErreur = ErreurSource(
          url,
          'Réponse HTTP $code${extrait == null ? '' : ' : $extrait'}',
          codeStatut: code,
          octetsRecus: reponse.bodyBytes.length,
          duree: chrono.elapsed,
          extraitReponse: extrait,
        );
        if (code == codeHttpTropDeRequetes) {
          // Le serveur dit combien de temps patienter : on lui obéit, sauf si
          // l'attente est déraisonnable (mieux vaut échouer et réessayer à la
          // prochaine vérification que bloquer toute la file).
          final demandee = _attenteDemandee(reponse);
          final attente = demandee ?? attenteAvantNouvelleTentative;
          Journal.actuel.avertissement(
            CategorieJournal.reseau,
            '$methode $urlJournal : HTTP 429 (trop de requêtes), attente '
            '${attente.inMilliseconds} ms'
            '${demandee == null ? '' : ' demandée par le serveur'}',
          );
          // Le 429 vaut pour tout le domaine (MangaDex : « HTTP 429 responses
          // for all requests to *.mangadex.org ») : on repousse le créneau du
          // domaine pour que TOUTES ses requêtes patientent, pas seulement
          // celle-ci. L'attente est plafonnée pour ne pas geler la file.
          _repousserCreneau(
            hote,
            attente > attenteMaxDemandeeParServeur
                ? attenteMaxDemandeeParServeur
                : attente,
          );
          if (attente > attenteMaxDemandeeParServeur) {
            Journal.actuel.erreur(
              CategorieJournal.reseau,
              '$methode $urlJournal : abandon, attente demandée trop longue, '
              '${_resume(code, reponse.bodyBytes.length, chrono.elapsed, essais)}',
            );
            throw derniereErreur;
          }
          attenteViaCreneau = true;
        } else if (code < 500) {
          // Une autre erreur 4xx (404, 403…) ne se corrigera pas en
          // réessayant : on échoue tout de suite. Avertissement seulement :
          // l'appelant peut avoir une solution de repli (autre adresse).
          Journal.actuel.avertissement(
            CategorieJournal.reseau,
            '$methode $urlJournal : échec, '
            '${_resume(code, reponse.bodyBytes.length, chrono.elapsed, essais)}',
          );
          throw derniereErreur;
        }
      } on TimeoutException catch (erreur) {
        chrono.stop();
        Journal.actuel.avertissement(
          CategorieJournal.reseau,
          '$methode $urlJournal : délai dépassé '
          '(${delaiExpiration.inSeconds} s, essai $essais)',
        );
        derniereErreur = ErreurSource(
          url,
          'Délai dépassé (${delaiExpiration.inSeconds} s)',
          cause: erreur,
          octetsRecus: 0,
          duree: chrono.elapsed,
        );
      } on ErreurSource {
        rethrow;
      } on Exception catch (erreur) {
        chrono.stop();
        // http.ClientException, SocketException, HandshakeException… : erreurs
        // réseau souvent passagères, qui justifient une nouvelle tentative.
        derniereErreur = ErreurSource(
          url,
          'Erreur réseau',
          cause: erreur,
          octetsRecus: 0,
          duree: chrono.elapsed,
        );
      }

      if (tentative < nouvellesTentatives && !attenteViaCreneau) {
        await _attendre(attenteAvantNouvelleTentative);
      }
    }
    final echec = derniereErreur!;
    // Échec final après toutes les tentatives : l'objet ErreurSource n'est
    // pas joint (son message peut citer le début de la réponse), seulement
    // la cause réseau d'origine si elle existe.
    Journal.actuel.erreur(
      CategorieJournal.reseau,
      '$methode $urlJournal : échec (${_causeCourte(echec)}), '
      '${_resume(echec.codeStatut, echec.octetsRecus, echec.duree, essais)}',
      erreur: echec.cause,
    );
    throw echec;
  }

  /// Résumé d'une requête pour le journal : code, taille reçue, durée et
  /// nombre d'essais (jamais le contenu de la réponse).
  static String _resume(int? code, int? octets, Duration? duree, int essais) {
    final morceaux = <String>[
      code == null ? 'sans réponse' : 'HTTP $code',
      '${octets ?? 0} o',
      if (duree != null) '${duree.inMilliseconds} ms',
      '$essais essai${essais > 1 ? 's' : ''}',
    ];
    return morceaux.join(', ');
  }

  /// Cause courte d'un échec pour le journal (`HTTP 503`, `délai dépassé`,
  /// `erreur réseau`), sans le début de la réponse que cite le message.
  static String _causeCourte(ErreurSource? erreur) {
    if (erreur == null) return 'inconnue';
    final code = erreur.codeStatut;
    if (code != null) return 'HTTP $code';
    if (erreur.cause is TimeoutException) return 'délai dépassé';
    return 'erreur réseau';
  }

  /// Réserve le prochain créneau libre pour le domaine [hote] (et pour
  /// [limite] si elle existe), puis attend qu'il arrive.
  ///
  /// Les deux clés sont réservées en une seule étape synchrone (aucun `await`
  /// avant la mise à jour de la table) : le début retenu est le plus tardif
  /// des créneaux libres, et il est enregistré pour les deux clés. Ainsi,
  /// même quand une [LimiteRequetes] retarde une requête, la requête suivante
  /// vers le domaine part au moins [delaiParDomaine] après elle.
  Future<void> _reserverCreneau(String hote, LimiteRequetes? limite) async {
    // LIMITE : `DateTime.now` n'est pas monotone : un recalage de l'horloge
    // système (NTP, changement manuel) pendant l'exécution peut allonger ou
    // raccourcir une attente. Acceptable pour des délais de l'ordre de la
    // seconde ; un `Stopwatch` serait monotone mais complique les tests.
    final maintenant = _maintenant();
    var debut = maintenant;
    final libreDomaine = _creneauxLibres[hote];
    if (libreDomaine != null && libreDomaine.isAfter(debut)) {
      debut = libreDomaine;
    }
    if (limite != null) {
      final libreLimite = _creneauxLibres[limite.cle];
      if (libreLimite != null && libreLimite.isAfter(debut)) {
        debut = libreLimite;
      }
      _creneauxLibres[limite.cle] = debut.add(limite.delaiMinimal);
    }
    _creneauxLibres[hote] = debut.add(delaiParDomaine);
    final attente = debut.difference(maintenant);
    if (attente > Duration.zero) {
      Journal.actuel.debogage(
        CategorieJournal.reseau,
        'Attente de politesse ${attente.inMilliseconds} ms pour $hote'
        '${limite == null ? '' : ' (limite ${limite.cle})'}',
      );
      await _attendre(attente);
    }
  }

  /// Interdit toute requête vers [hote] pendant [attente] à partir de
  /// maintenant (sans jamais avancer un créneau déjà plus tardif).
  void _repousserCreneau(String hote, Duration attente) {
    final libre = _maintenant().add(attente);
    final actuel = _creneauxLibres[hote];
    if (actuel == null || libre.isAfter(actuel)) {
      _creneauxLibres[hote] = libre;
    }
  }

  /// Lit l'attente demandée par le serveur après une réponse 429.
  ///
  /// - `Retry-After` (RFC 9110) en secondes ; LIMITE : la forme « date HTTP »
  ///   n'est pas gérée (on retombe alors sur l'attente par défaut).
  /// - `X-RateLimit-Retry-After`, horodatage UNIX documenté par MangaDex
  ///   (docs/2-limitations : « Timestamp of the end of the current time
  ///   period, as UNIX timestamp »).
  Duration? _attenteDemandee(http.Response reponse) {
    // `package:http` met les noms d'en-têtes en minuscules.
    final secondes = int.tryParse(reponse.headers['retry-after'] ?? '');
    if (secondes != null && secondes >= 0) {
      return Duration(seconds: secondes);
    }
    final finPeriode = int.tryParse(
      reponse.headers['x-ratelimit-retry-after'] ?? '',
    );
    if (finPeriode != null) {
      final fin = DateTime.fromMillisecondsSinceEpoch(
        finPeriode * 1000,
        isUtc: true,
      );
      final attente = fin.difference(_maintenant().toUtc());
      return attente.isNegative ? Duration.zero : attente;
    }
    return null;
  }

  /// Jeux de caractères occidentaux sur un octet, lus en latin-1.
  static const Set<String> _jeuxOccidentaux = <String>{
    'iso-8859-1',
    'latin1',
    'windows-1252',
    'cp1252',
  };

  String _decoderTexte(http.Response reponse) {
    final typeContenu = reponse.headers['content-type'];
    final jeu = typeContenu == null
        ? null
        : RegExp(
            r'charset\s*=\s*"?([^";\s]+)',
            caseSensitive: false,
          ).firstMatch(typeContenu)?.group(1);
    final nomJeu = jeu?.toLowerCase();
    if (nomJeu != null && _jeuxOccidentaux.contains(nomJeu)) {
      // `Encoding.getByName` ne connaît pas windows-1252, très répandu sur
      // les vieux sites : on le lit en latin-1, qui lui est presque identique.
      // LIMITE : les octets 0x80-0x9F (€, guillemets typographiques, œ…) sont
      // différents en windows-1252 et deviennent des caractères de contrôle
      // en latin-1 ; dart:convert ne fournit pas de décodeur windows-1252.
      return latin1.decode(reponse.bodyBytes);
    }
    final encodage = nomJeu == null ? null : Encoding.getByName(nomJeu);
    if (encodage == null || encodage == utf8) {
      return utf8.decode(reponse.bodyBytes, allowMalformed: true);
    }
    return encodage.decode(reponse.bodyBytes);
  }

  /// Lève une [ErreurSource] si [reponse] n'est pas une image (voir
  /// `exigerImage` dans [recupererOctetsAvecDetails]).
  void _verifierImage(Uri uri, http.Response reponse, Duration duree) {
    final octets = reponse.bodyBytes;
    if (detecterFormatImage(octets) != null) {
      return;
    }
    String? typeContenu;
    for (final entree in reponse.headers.entries) {
      if (entree.key.toLowerCase() == 'content-type') {
        typeContenu = entree.value;
      }
    }
    // Type MIME sans paramètres (« image/jpeg; charset=… » → image/jpeg),
    // insensible à la casse (RFC 9110 : les types ne le sont pas).
    final type = typeContenu?.split(';').first.trim().toLowerCase() ?? '';
    // Format sans signature connue (SVG, TIFF, JPEG XL…) annoncé comme
    // image : accepté, sauf si c'est en fait une page HTML (E10).
    // Un corps vide n'est jamais une image, même annoncé comme tel.
    if (octets.isNotEmpty &&
        type.startsWith('image/') &&
        !estContenuHtml(octets)) {
      return;
    }
    final extraitCourt = extraitTexteImprimable(octets);
    // Seulement le type détecté (« page HTML », « JSON »…) : pas d'extrait.
    Journal.actuel.erreur(
      CategorieJournal.reseau,
      'GET ${masquerDonneesSensibles(uri.toString())} : image refusée '
      '(Content-Type : ${type.isEmpty ? 'absent' : type} ; '
      'contenu : ${decrireContenuNonImage(octets)}, ${octets.length} o)',
    );
    throw ErreurSource(
      uri.toString(),
      "Réponse qui n'est pas une image "
      '(Content-Type : ${type.isEmpty ? 'absent' : type} ; '
      'contenu : ${decrireContenuNonImage(octets)})'
      '${extraitCourt == null ? '' : ' : $extraitCourt'}',
      codeStatut: reponse.statusCode,
      octetsRecus: octets.length,
      duree: duree,
      extraitReponse: _extrait(reponse),
    );
  }

  /// Début du corps de [reponse], nettoyé par `extraireDebutReponse`, ou
  /// `null` si le corps est binaire : des octets binaires décodés en texte
  /// rendraient le message illisible (retour du client sur la 0.2.1-test).
  String? _extrait(http.Response reponse) {
    if (!estContenuTexte(reponse.bodyBytes)) {
      return null;
    }
    return extraireDebutReponse(
      utf8.decode(reponse.bodyBytes, allowMalformed: true),
    );
  }
}
