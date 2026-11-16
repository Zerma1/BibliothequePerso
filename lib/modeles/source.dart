/// Modèle `Source` : un site configuré dans l'application.
library;

import 'outils_modeles.dart';

/// Famille technique d'un site, qui détermine l'adaptateur utilisé pour le lire
/// (PLAYBOOK.md section 6).
///
/// La valeur est stockée en base sous son nom (`Enum.name`) : ne jamais
/// renommer une valeur existante sans migration.
enum TypeSource {
  /// MangaDex, lu via son API publique officielle.
  mangaDex,

  /// Site WordPress utilisant le thème Madara.
  madara,

  /// Site WordPress utilisant le thème MangaThemesia.
  mangaThemesia,

  /// Site quelconque décrit par des sélecteurs CSS saisis par le client.
  generique,

  /// Scan-Manga (`scan-manga.com`) : fiches et listes de chapitres lues dans
  /// le HTML ; les chapitres ne se lisent que sur le site (lien externe,
  /// jamais téléchargés, PLAYBOOK.md section 10).
  scanManga,
}

/// Un site configuré dans l'application.
class Source {
  /// Crée une source. [id] vaut `null` tant qu'elle n'est pas enregistrée.
  const Source({
    this.id,
    required this.nom,
    required this.urlBase,
    required this.typeSource,
    this.langueParDefaut = '',
    this.configurationSelecteurs,
    this.estActive = true,
  });

  /// Nom de l'entité dans les messages d'erreur.
  static const String _entite = 'Source';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Nom affiché du site.
  final String nom;

  /// URL de base du site (unique en base).
  final String urlBase;

  /// Famille technique du site.
  final TypeSource typeSource;

  /// Langue par défaut des chapitres (code ISO 639-1, peut être vide).
  final String langueParDefaut;

  /// Sélecteurs CSS au format JSON, uniquement pour [TypeSource.generique].
  ///
  /// Le JSON est stocké tel quel : son interprétation appartient à `sources/`.
  final String? configurationSelecteurs;

  /// `false` si le client a désactivé la vérification de ce site.
  final bool estActive;

  /// Convertit la source en ligne SQLite (colonnes en `snake_case`).
  ///
  /// La colonne `id` n'est présente que si [id] est connu, pour laisser SQLite
  /// l'attribuer lors d'une insertion.
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'nom': nom,
      'url_base': urlBase,
      'type_source': typeSource.name,
      'langue_par_defaut': langueParDefaut,
      'configuration_selecteurs': configurationSelecteurs,
      'est_active': booleenVersEntier(estActive),
    };
  }

  /// Construit une source depuis une ligne SQLite.
  ///
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  factory Source.depuisMap(Map<String, Object?> map) {
    return Source(
      id: map.lireEntierOptionnel('id', _entite),
      nom: map.lireTexte('nom', _entite),
      urlBase: map.lireTexte('url_base', _entite),
      typeSource: map.lireEnum('type_source', _entite, TypeSource.values),
      langueParDefaut:
          map.lireTexteOptionnel('langue_par_defaut', _entite) ?? '',
      configurationSelecteurs: map.lireTexteOptionnel(
        'configuration_selecteurs',
        _entite,
      ),
      estActive: map.lireBooleen('est_active', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode (un argument `null` signifie « inchangé »).
  Source copierAvec({
    int? id,
    String? nom,
    String? urlBase,
    TypeSource? typeSource,
    String? langueParDefaut,
    String? configurationSelecteurs,
    bool? estActive,
  }) {
    return Source(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      urlBase: urlBase ?? this.urlBase,
      typeSource: typeSource ?? this.typeSource,
      langueParDefaut: langueParDefaut ?? this.langueParDefaut,
      configurationSelecteurs:
          configurationSelecteurs ?? this.configurationSelecteurs,
      estActive: estActive ?? this.estActive,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Source &&
            other.id == id &&
            other.nom == nom &&
            other.urlBase == urlBase &&
            other.typeSource == typeSource &&
            other.langueParDefaut == langueParDefaut &&
            other.configurationSelecteurs == configurationSelecteurs &&
            other.estActive == estActive;
  }

  @override
  int get hashCode => Object.hash(
    id,
    nom,
    urlBase,
    typeSource,
    langueParDefaut,
    configurationSelecteurs,
    estActive,
  );

  @override
  String toString() =>
      'Source(id: $id, nom: $nom, urlBase: $urlBase, '
      'typeSource: ${typeSource.name}, langueParDefaut: $langueParDefaut, '
      'estActive: $estActive)';
}
