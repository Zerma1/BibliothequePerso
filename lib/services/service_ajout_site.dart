/// Ajout d'un site de lecture à partir de son URL (PLAYBOOK.md section 7).
library;

import '../donnees/depot_sources.dart';
import '../modeles/source.dart';
import '../sources/detecteur_type_site.dart';

/// Valide une URL, détecte le type du site et enregistre la [Source].
class ServiceAjoutSite {
  /// Crée le service.
  const ServiceAjoutSite(this._depotSources, this._detecteur);

  final DepotSources _depotSources;
  final DetecteurTypeSite _detecteur;

  /// Ramène une URL quelconque du site à son URL de base (`schéma://hôte`).
  ///
  /// Le client peut coller l'adresse d'un titre ou d'un chapitre : on ne garde
  /// que la racine, pour qu'un même site ne soit enregistré qu'une fois.
  static String calculerUrlBase(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host.toLowerCase()}$port';
  }

  /// Propose un nom affichable à partir de l'hôte (`www.` retiré).
  static String proposerNom(Uri uri) {
    final hote = uri.host.toLowerCase();
    return hote.startsWith('www.') ? hote.substring(4) : hote;
  }

  /// Ajoute le site désigné par [url] et renvoie la source enregistrée.
  ///
  /// Si le site est déjà configuré, la source existante est renvoyée sans
  /// nouvelle détection. [nom] et [langueParDefaut] sont facultatifs ;
  /// [typeForce] permet au client de corriger un type mal détecté.
  ///
  /// Lève une `ErreurSource` (URL invalide, site injoignable) ou une
  /// `ErreurBaseDeDonnees`.
  Future<Source> ajouterSite(
    String url, {
    String? nom,
    String langueParDefaut = '',
    TypeSource? typeForce,
  }) async {
    final uri = DetecteurTypeSite.validerUrl(url);
    final urlBase = calculerUrlBase(uri);

    final existante = await _depotSources.chargerSourceParUrl(urlBase);
    if (existante != null) {
      return existante;
    }

    // Une ErreurSource du détecteur remonte telle quelle : le type n'est pas
    // encore connu à ce stade (le rapport d'erreur indiquera « inconnu »).
    final type = typeForce ?? await _detecteur.detecter(urlBase);
    final nomFinal = (nom == null || nom.trim().isEmpty)
        ? proposerNom(uri)
        : nom.trim();

    return _depotSources.enregistrerSource(
      Source(
        nom: nomFinal,
        urlBase: urlBase,
        typeSource: type,
        langueParDefaut: langueParDefaut.trim().toLowerCase(),
      ),
    );
  }

  /// Modifie une source existante (nom, langues, type, activation).
  ///
  /// Les langues sont des codes ISO 639-1 séparés par des virgules, par ordre
  /// de préférence (« fr,en ») ; elles sont mises en minuscules et les
  /// espaces retirés. L'URL de base ne change pas.
  Future<Source> modifierSource(Source source) {
    final langues = source.langueParDefaut
        .split(',')
        .map((code) => code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .join(',');
    return _depotSources.enregistrerSource(
      source.copierAvec(nom: source.nom.trim(), langueParDefaut: langues),
    );
  }

  /// Supprime une source. Refusé (ErreurBaseDeDonnees) tant qu'elle a des
  /// titres, pour ne jamais effacer une partie de la bibliothèque.
  Future<void> supprimerSource(int idSource) =>
      _depotSources.supprimerSource(idSource);

  /// Renvoie la source configurée qui correspond à l'hôte de [url], ou `null`.
  ///
  /// La comparaison ignore `www.` pour qu'une source `https://mangadex.org`
  /// reconnaisse aussi `https://www.mangadex.org/title/…`.
  Future<Source?> trouverSourcePourUrl(String url) async {
    final uri = DetecteurTypeSite.validerUrl(url);
    final hote = proposerNom(uri);
    final sources = await _depotSources.chargerSources();
    for (final source in sources) {
      final uriSource = Uri.tryParse(source.urlBase);
      if (uriSource != null && proposerNom(uriSource) == hote) {
        return source;
      }
    }
    return null;
  }
}
