/// Suivi de la limite de requêtes de l'API REST publique de GitHub, partagé
/// par les clients sans jeton (tickets, mise à jour de l'application).
///
/// Source : docs.github.com, « Rate limits for the REST API » (relevé le
/// 2026-11-27) : 60 requêtes par heure sans jeton **par adresse IP** ;
/// limite dépassée = 403 ou 429, avec `x-ratelimit-remaining` à 0 et
/// `x-ratelimit-reset` (secondes UNIX) ou `retry-after` (secondes). La
/// limite étant commune à toute l'application, une seule instance doit être
/// partagée entre les clients.
library;

import 'constantes_sources.dart';
import 'erreur_source.dart';

/// Fonction qui donne l'heure courante (remplaçable dans les tests).
typedef HorlogeLimiteGithub = DateTime Function();

/// Limite de requêtes de l'API GitHub atteinte (403 ou 429 avec
/// `x-ratelimit-remaining` à 0, `retry-after`, ou limite secondaire).
///
/// Aucune requête n'est envoyée à GitHub avant [heureReprise] : la
/// documentation prévient que « continuing to make requests while you are
/// rate limited may result in the banning of your integration ».
class ErreurLimiteGithub extends ErreurSource {
  /// Crée l'erreur pour [url], avec l'heure (UTC) où réessayer.
  const ErreurLimiteGithub(
    super.url,
    super.message, {
    required this.heureReprise,
    super.cause,
    super.codeStatut,
    super.enTetesReponse,
  });

  /// Heure (UTC) à partir de laquelle GitHub accepte de nouveau les
  /// requêtes.
  final DateTime heureReprise;
}

/// État de la limite de requêtes GitHub : requêtes restantes et heure de
/// reprise après une limite atteinte.
class SuiviLimiteGithub {
  /// Crée le suivi ; [maintenant] remplace `DateTime.now` dans les tests.
  SuiviLimiteGithub({HorlogeLimiteGithub? maintenant})
    : _maintenant = maintenant ?? DateTime.now;

  final HorlogeLimiteGithub _maintenant;
  DateTime? _heureReprise;
  int? _requetesRestantes;

  /// Requêtes restantes dans la fenêtre courante selon la dernière réponse
  /// (`x-ratelimit-remaining`), ou `null` si inconnu.
  int? get requetesRestantes => _requetesRestantes;

  /// Heure (UTC) avant laquelle aucune requête n'est envoyée, après une
  /// limite atteinte, ou `null`.
  DateTime? get heureReprise => _heureReprise;

  /// Heure courante selon l'horloge du suivi.
  DateTime maintenant() => _maintenant();

  /// Lève [ErreurLimiteGithub] pour [url] si la limite est encore en cours :
  /// insister peut faire bannir l'application (« Exceeding the rate limit »).
  void verifierAvantRequete(String url) {
    final reprise = _heureReprise;
    if (reprise != null && _maintenant().toUtc().isBefore(reprise)) {
      throw ErreurLimiteGithub(
        url,
        _messageLimite(reprise),
        heureReprise: reprise,
      );
    }
  }

  /// Retient `x-ratelimit-remaining` d'une réponse réussie et, s'il vaut 0,
  /// l'heure de reprise (`x-ratelimit-reset`) pour ne plus rien envoyer d'ici
  /// là. [enTetes] : noms en minuscules.
  void noterReponse(Map<String, String> enTetes) {
    final restantes = int.tryParse(enTetes['x-ratelimit-remaining'] ?? '');
    if (restantes == null) {
      return;
    }
    _requetesRestantes = restantes;
    if (restantes == 0) {
      _heureReprise = _repriseDepuisEnTetes(enTetes);
    }
  }

  /// Renvoie une [ErreurLimiteGithub] si [erreur] (levée par
  /// `ClientHttpPoli`) est une limite atteinte (403/429 de limite), en
  /// retenant l'heure de reprise ; sinon `null`.
  ErreurLimiteGithub? traduireLimite(ErreurSource erreur, String url) {
    final code = erreur.codeStatut;
    if (code != 403 && code != 429) {
      return null;
    }
    final enTetes = erreur.enTetesReponse ?? const <String, String>{};
    final estLimite =
        code == 429 ||
        enTetes['x-ratelimit-remaining'] == '0' ||
        enTetes.containsKey('retry-after') ||
        // Limite secondaire : « an error message that indicates that you
        // exceeded a secondary rate limit ».
        erreur.message.toLowerCase().contains('rate limit');
    if (!estLimite) {
      return null;
    }
    final reprise =
        _repriseDepuisEnTetes(enTetes) ??
        _maintenant().toUtc().add(attenteMinLimiteGithub);
    _heureReprise = reprise;
    _requetesRestantes = 0;
    return ErreurLimiteGithub(
      url,
      _messageLimite(reprise),
      heureReprise: reprise,
      cause: erreur,
      codeStatut: code,
      enTetesReponse: erreur.enTetesReponse,
    );
  }

  /// Heure de reprise (UTC) lue dans `retry-after` (secondes) ou, si
  /// `x-ratelimit-remaining` vaut 0, dans `x-ratelimit-reset` (secondes
  /// UNIX), ou `null` si aucun en-tête ne la donne.
  DateTime? _repriseDepuisEnTetes(Map<String, String> enTetes) {
    final secondes = int.tryParse(enTetes['retry-after'] ?? '');
    if (secondes != null && secondes >= 0) {
      return _maintenant().toUtc().add(Duration(seconds: secondes));
    }
    if (enTetes['x-ratelimit-remaining'] == '0') {
      final fin = int.tryParse(enTetes['x-ratelimit-reset'] ?? '');
      if (fin != null) {
        return DateTime.fromMillisecondsSinceEpoch(fin * 1000, isUtc: true);
      }
    }
    return null;
  }

  static String _messageLimite(DateTime reprise) {
    final locale = reprise.toLocal();
    String deuxChiffres(int n) => n.toString().padLeft(2, '0');
    return 'Limite de requêtes GitHub atteinte : nouvel essai possible à '
        '${deuxChiffres(locale.hour)}:${deuxChiffres(locale.minute)}';
  }
}
