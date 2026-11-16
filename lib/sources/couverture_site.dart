/// Couvertures proposées par un site, pour le choix du client (tâche SO1 de
/// l'étape 6).
///
/// LIMITE : `lib/modeles/` n'a pas de modèle « couverture » et ce dossier est
/// hors du scope de `developpeur-sources`. Cette classe de valeur reste donc
/// dans `sources/` ; elle n'est jamais enregistrée en base (le choix du client
/// est rangé dans `Titre.couvertureChoisie`, une simple URL).
library;

/// Une couverture disponible sur le site.
class CouvertureSite {
  /// Crée une couverture.
  const CouvertureSite({
    required this.url,
    this.urlMiniature,
    this.volume,
    this.langue,
  });

  /// URL de l'image en taille réelle (celle à enregistrer comme couverture).
  final String url;

  /// URL d'une version réduite, plus légère pour afficher la liste de choix ;
  /// `null` si le site n'en fournit pas.
  final String? urlMiniature;

  /// Volume illustré, tel que le site l'écrit (« 1 », « 10.5 »…), ou `null`.
  final String? volume;

  /// Langue de l'édition (code du site, par exemple `ja`, `en`, `pt-br`), ou
  /// `null`.
  final String? langue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CouvertureSite &&
          other.url == url &&
          other.urlMiniature == urlMiniature &&
          other.volume == volume &&
          other.langue == langue;

  @override
  int get hashCode => Object.hash(url, urlMiniature, volume, langue);

  @override
  String toString() =>
      'CouvertureSite(volume: $volume, langue: $langue, '
      'url: $url)';
}

/// Capacité facultative d'un adaptateur : lister toutes les couvertures d'un
/// titre. Le service teste `adaptateur is SourceAvecCouvertures` ; les sites
/// qui n'en ont qu'une n'implémentent pas cette interface.
abstract interface class SourceAvecCouvertures {
  /// Récupère toutes les couvertures de [urlTitre], dans l'ordre du site.
  ///
  /// Lève une `ErreurSource` en cas d'échec ; une liste vide signifie que le
  /// site n'a vraiment aucune couverture pour ce titre.
  Future<List<CouvertureSite>> recupererCouvertures(String urlTitre);
}
