/// Journalisation commune des adaptateurs de `lib/sources/` : une ligne
/// courte par opération principale (recherche, fiche, chapitres, contenu).
///
/// Les requêtes elles-mêmes sont journalisées par `ClientHttpPoli`
/// (catégorie `reseau`) ; ici, on dit ce que l'adaptateur en a tiré
/// (catégorie `sources`). Jamais de contenu de page : seulement des nombres,
/// le nom du titre et l'adresse masquée.
library;

import '../modeles/chapitre.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/journal.dart';
import '../modeles/titre.dart';
import 'erreur_source.dart';

/// Longueur maximale d'un motif d'échec cité dans le journal.
const int longueurMaxMotifJournalSources = 160;

/// Fonctions de journalisation partagées par les adaptateurs de sites.
abstract final class JournalSources {
  /// Exécute [action] (opération [operation] de l'adaptateur [site] sur
  /// [url]) et journalise son résultat.
  ///
  /// Succès : une ligne `info` adaptée au type du résultat (nombre de
  /// résultats, nom du titre, nombre de chapitres, nombre d'images), plus un
  /// `avertissement` si des chapitres ne sont lisibles que sur un autre site.
  /// Échec par [ErreurSource] : un `avertissement` court (le service décide
  /// de la gravité), puis l'erreur est relancée telle quelle.
  static Future<T> operation<T>(
    String site,
    String operation,
    String url,
    Future<T> Function() action,
  ) async {
    final T resultat;
    try {
      resultat = await action();
    } on ErreurSource catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.sources,
        '$site, $operation ${masquerDonneesSensibles(url)} : échec '
        '(${motifEchec(erreur)})',
      );
      rethrow;
    }
    _journaliserResultat(site, operation, url, resultat);
    return resultat;
  }

  /// Avertissement pour un cas dégradé de l'adaptateur [site] (liste
  /// incomplète, chapitre externe…) : [message] court, sans contenu de page.
  static void avertir(String site, String message) {
    Journal.actuel.avertissement(
      CategorieJournal.sources,
      '$site : ${masquerDonneesSensibles(message)}',
    );
  }

  /// Motif court d'un échec : le code HTTP quand l'échec vient d'une réponse
  /// (son message peut citer le début de la page, à ne pas journaliser),
  /// sinon le message de l'adaptateur, tronqué.
  static String motifEchec(ErreurSource erreur) {
    if (erreur.protectionAntiRobot) {
      return 'protection anti-robot';
    }
    final code = erreur.codeStatut;
    if (code != null) {
      return 'HTTP $code';
    }
    final message = erreur.message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (message.length <= longueurMaxMotifJournalSources) {
      return masquerDonneesSensibles(message);
    }
    return '${masquerDonneesSensibles(message.substring(0, longueurMaxMotifJournalSources))}…';
  }

  static void _journaliserResultat(
    String site,
    String operation,
    String url,
    Object? resultat,
  ) {
    final adresse = masquerDonneesSensibles(url);
    final String detail;
    switch (resultat) {
      case FicheTitre(:final titre, :final categories):
        detail =
            'fiche lue « ${titre.nom} » (${categories.length} '
            'catégorie${categories.length > 1 ? 's' : ''})';
      case ContenuChapitre(:final urlsImages, :final texteHtml):
        detail = urlsImages.isNotEmpty || texteHtml == null
            ? '${urlsImages.length} image${urlsImages.length > 1 ? 's' : ''}'
            : 'texte (${texteHtml.length} caractères)';
      case List<Chapitre>():
        detail = '${resultat.length} chapitre${resultat.length > 1 ? 's' : ''}';
        final externes = resultat.where((c) => c.urlExterne != null).length;
        if (externes > 0) {
          avertir(
            site,
            '$externes chapitre${externes > 1 ? 's' : ''} lisible'
            '${externes > 1 ? 's' : ''} seulement sur un autre site ou '
            'réservé${externes > 1 ? 's' : ''} ($adresse)',
          );
        }
      case List<Titre>():
        detail = '${resultat.length} résultat${resultat.length > 1 ? 's' : ''}';
      default:
        detail = 'terminé';
    }
    Journal.actuel.info(
      CategorieJournal.sources,
      '$site, $operation $adresse : $detail',
    );
  }
}
