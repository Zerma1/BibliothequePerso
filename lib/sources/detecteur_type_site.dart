/// Détection du type technique d'un site ajouté par URL (PLAYBOOK.md
/// section 6, « Ajout d'un site par URL »).
library;

import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' show parse;

import '../modeles/source.dart';
import 'client_http_poli.dart';
import 'erreur_source.dart';
import 'source_mangadex.dart';

/// Détermine le [TypeSource] d'un site : d'abord par le domaine, puis en
/// analysant le HTML de la page d'accueil.
class DetecteurTypeSite {
  /// Crée un détecteur qui télécharge les pages avec [_client].
  DetecteurTypeSite(this._client);

  final ClientHttpPoli _client;

  /// Valide une URL saisie : schéma `http` ou `https` et hôte non vide.
  ///
  /// Renvoie l'URL analysée ou lève une [ErreurSource].
  static Uri validerUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ErreurSource(
        url,
        'Adresse invalide : elle doit commencer par http:// ou https:// et '
        'contenir un nom de domaine',
      );
    }
    return uri;
  }

  /// Type déduit du seul domaine, sans requête réseau ; `null` si le domaine
  /// ne suffit pas.
  ///
  /// `mangadex.org` (et `www.mangadex.org`) → [TypeSource.mangaDex] : le HTML
  /// de MangaDex est construit en JavaScript, l'analyser n'apprendrait rien.
  static TypeSource? verifierDomaine(Uri uri) {
    if (SourceMangaDex.estHoteMangaDex(uri.host)) {
      return TypeSource.mangaDex;
    }
    return null;
  }

  /// Détecte le type du site à l'adresse [url].
  ///
  /// Valide l'URL, regarde le domaine puis, si nécessaire, télécharge la page
  /// d'accueil via `ClientHttpPoli`. Lève une [ErreurSource] si l'URL est
  /// invalide ou si la page ne peut pas être lue.
  Future<TypeSource> detecter(String url) async {
    final uri = validerUrl(url);
    final parDomaine = verifierDomaine(uri);
    if (parDomaine != null) {
      return parDomaine;
    }
    final html = await _client.recupererTexte(uri);
    return detecterDepuisHtml(html);
  }

  /// Détecte le type à partir du [html] de la page d'accueil (sans réseau).
  ///
  /// Ordre des marqueurs (PLAYBOOK.md section 6) : Madara, puis
  /// MangaThemesia, puis générique. Précision : le chemin `/manga/` est un
  /// indice faible (beaucoup de sites MangaThemesia l'utilisent aussi) ; il
  /// ne désigne Madara que si aucun marqueur MangaThemesia n'est présent.
  static TypeSource detecterDepuisHtml(String html) {
    final document = parse(html);

    // Madara est un thème WordPress dont l'extension « WP Manga » préfixe ses
    // classes CSS par « wp-manga » (wp-manga-chapter, wp-manga-section…) :
    // une sous-chaîne de l'attribut class suffit à la repérer.
    final aClasseWpManga =
        document.querySelector('[class*="wp-manga"]') != null;
    // Les fichiers du thème sont servis depuis un dossier « madara »
    // (wp-content/themes/madara/…) : on cherche ce nom dans les scripts.
    final aScriptMadara =
        document.querySelector('script[src*="madara"]') != null ||
        _scriptEnLigneContient(document.querySelectorAll('script'), 'madara');
    if (aClasseWpManga || aScriptMadara) {
      return TypeSource.madara;
    }

    // MangaThemesia : « bixbox » est la classe des blocs de contenu du thème,
    // et « ts_reader » l'objet JavaScript de son lecteur.
    final aBixbox = document.querySelector('.bixbox') != null;
    final aTsReader = _scriptEnLigneContient(
      document.querySelectorAll('script'),
      'ts_reader',
    );
    if (aBixbox || aTsReader) {
      return TypeSource.mangaThemesia;
    }

    // Indice faible de Madara : liens vers des fiches sous /manga/.
    if (document.querySelector('a[href*="/manga/"]') != null) {
      return TypeSource.madara;
    }
    return TypeSource.generique;
  }

  static bool _scriptEnLigneContient(List<Element> scripts, String motif) {
    for (final script in scripts) {
      if (script.text.contains(motif)) {
        return true;
      }
    }
    return false;
  }
}
