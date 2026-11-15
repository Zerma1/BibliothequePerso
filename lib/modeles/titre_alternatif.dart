/// Modèle `TitreAlternatif` : autre nom connu d'un titre (traduction,
/// romanisation, nom original…).
library;

import 'outils_modeles.dart';

/// Autre nom d'un titre, utilisé notamment par la recherche dans la
/// bibliothèque (PLAYBOOK.md section 5).
class TitreAlternatif {
  /// Crée un titre alternatif. [id] et [idTitre] valent `null` tant que le
  /// titre parent n'est pas enregistré.
  const TitreAlternatif({
    this.id,
    this.idTitre,
    required this.nom,
    this.langue = '',
  });

  static const String _entite = 'TitreAlternatif';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Identifiant du titre parent, `null` avant son enregistrement.
  final int? idTitre;

  /// Nom alternatif tel qu'affiché par le site.
  final String nom;

  /// Langue du nom (code ISO 639-1), vide si inconnue.
  final String langue;

  /// Convertit en ligne SQLite (colonnes en `snake_case`).
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'id_titre': idTitre,
      'nom': nom,
      'langue': langue,
    };
  }

  /// Construit depuis une ligne SQLite.
  ///
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  factory TitreAlternatif.depuisMap(Map<String, Object?> map) {
    return TitreAlternatif(
      id: map.lireEntierOptionnel('id', _entite),
      idTitre: map.lireEntierOptionnel('id_titre', _entite),
      nom: map.lireTexte('nom', _entite),
      langue: map.lireTexteOptionnel('langue', _entite) ?? '',
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode.
  TitreAlternatif copierAvec({
    int? id,
    int? idTitre,
    String? nom,
    String? langue,
  }) {
    return TitreAlternatif(
      id: id ?? this.id,
      idTitre: idTitre ?? this.idTitre,
      nom: nom ?? this.nom,
      langue: langue ?? this.langue,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TitreAlternatif &&
            other.id == id &&
            other.idTitre == idTitre &&
            other.nom == nom &&
            other.langue == langue;
  }

  @override
  int get hashCode => Object.hash(id, idTitre, nom, langue);

  @override
  String toString() =>
      'TitreAlternatif(id: $id, idTitre: $idTitre, nom: $nom, langue: $langue)';
}
