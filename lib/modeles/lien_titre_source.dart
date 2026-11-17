/// Modèle `LienTitreSource` : un site (source) sur lequel un titre est suivi
/// (étape 8, plusieurs sites pour un même titre).
///
/// Nom choisi plutôt que `SourceTitre` : le préfixe `Source` est réservé aux
/// adaptateurs de site (CONVENTIONS_NOMMAGE.md, section 3).
library;

import 'outils_modeles.dart';

/// Lien entre un titre et l'une des sources où il est publié (ligne de la
/// table `titres_sources`).
///
/// Chaque titre a exactement un lien **principal** ([estPrincipale]) : le
/// site d'ajout, qui fournit la fiche (couverture, résumé…), et dont l'URL
/// et la source sont aussi recopiées dans `titres.url_titre` et
/// `titres.id_source`. Les autres liens sont des sites **secondaires**,
/// consultés pour leurs chapitres.
///
/// Un site secondaire peut être un **lien seul** ([estLienSeul], migration
/// 8) : site que l'application ne sait pas lire (protection anti-robot,
/// adaptateur incapable), gardé seulement pour être ouvert dans le
/// navigateur. Aucun chapitre n'y est lu. Le site principal n'est jamais un
/// lien seul.
class LienTitreSource {
  /// Crée un lien. [id] vaut `null` tant qu'il n'est pas enregistré.
  const LienTitreSource({
    this.id,
    required this.idTitre,
    required this.idSource,
    required this.urlTitre,
    this.estPrincipale = false,
    this.estLienSeul = false,
    this.dateAjout,
  });

  static const String _entite = 'LienTitreSource';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Identifiant du titre.
  final int idTitre;

  /// Identifiant de la source (site) du lien.
  final int idSource;

  /// URL de la fiche du titre sur ce site (unique en base, tous titres et
  /// sites confondus).
  final String urlTitre;

  /// `true` pour le site principal du titre (un seul par titre).
  final bool estPrincipale;

  /// `true` si le site est un **lien seul** : il est seulement ouvert dans
  /// le navigateur, l'application n'y lit aucun chapitre. Toujours `false`
  /// pour le site principal.
  final bool estLienSeul;

  /// Date (UTC) à laquelle le site a été lié au titre, si connue.
  final DateTime? dateAjout;

  /// Convertit en ligne de la table `titres_sources` (colonnes en
  /// `snake_case`).
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'id_titre': idTitre,
      'id_source': idSource,
      'url_titre': urlTitre,
      'est_principale': booleenVersEntier(estPrincipale),
      'lien_seul': booleenVersEntier(estLienSeul),
      'date_ajout': dateVersMillisecondes(dateAjout),
    };
  }

  /// Construit depuis une ligne SQLite.
  ///
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  /// Colonne `lien_seul` absente (base antérieure à la migration 8) :
  /// `false`.
  factory LienTitreSource.depuisMap(Map<String, Object?> map) {
    return LienTitreSource(
      id: map.lireEntierOptionnel('id', _entite),
      idTitre: map.lireEntier('id_titre', _entite),
      idSource: map.lireEntier('id_source', _entite),
      urlTitre: map.lireTexte('url_titre', _entite),
      estPrincipale: map.lireBooleen('est_principale', _entite),
      estLienSeul:
          map.containsKey('lien_seul') && map.lireBooleen('lien_seul', _entite),
      dateAjout: map.lireDateOptionnelle('date_ajout', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode (un argument `null` signifie « inchangé »).
  LienTitreSource copierAvec({
    int? id,
    int? idTitre,
    int? idSource,
    String? urlTitre,
    bool? estPrincipale,
    bool? estLienSeul,
    DateTime? dateAjout,
  }) {
    return LienTitreSource(
      id: id ?? this.id,
      idTitre: idTitre ?? this.idTitre,
      idSource: idSource ?? this.idSource,
      urlTitre: urlTitre ?? this.urlTitre,
      estPrincipale: estPrincipale ?? this.estPrincipale,
      estLienSeul: estLienSeul ?? this.estLienSeul,
      dateAjout: dateAjout ?? this.dateAjout,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LienTitreSource &&
            other.id == id &&
            other.idTitre == idTitre &&
            other.idSource == idSource &&
            other.urlTitre == urlTitre &&
            other.estPrincipale == estPrincipale &&
            other.estLienSeul == estLienSeul &&
            other.dateAjout == dateAjout;
  }

  @override
  int get hashCode => Object.hash(
    id,
    idTitre,
    idSource,
    urlTitre,
    estPrincipale,
    estLienSeul,
    dateAjout,
  );

  @override
  String toString() =>
      'LienTitreSource(id: $id, idTitre: $idTitre, idSource: $idSource, '
      'urlTitre: $urlTitre, estPrincipale: $estPrincipale, '
      'estLienSeul: $estLienSeul)';
}
