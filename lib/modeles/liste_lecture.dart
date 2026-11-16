/// Modèle `ListeLecture` : regroupement de titres (Favoris, Suivis, ou liste
/// créée par le client).
library;

import 'outils_modeles.dart';

/// Une liste de lecture.
///
/// Les listes système (« Favoris » et « Suivis ») ne peuvent être ni renommées
/// ni supprimées : `DepotListes` lève une erreur.
class ListeLecture {
  /// Crée une liste. [id] vaut `null` tant qu'elle n'est pas enregistrée.
  const ListeLecture({
    this.id,
    required this.nom,
    this.estSysteme = false,
    this.ordre = 0,
  });

  static const String _entite = 'ListeLecture';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Nom affiché de la liste (unique, sans tenir compte de la casse).
  final String nom;

  /// `true` pour « Favoris » et « Suivis ».
  final bool estSysteme;

  /// Position d'affichage (croissante).
  final int ordre;

  /// Convertit la liste en ligne de la table `listes`.
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'nom': nom,
      'est_systeme': booleenVersEntier(estSysteme),
      'ordre': ordre,
    };
  }

  /// Construit une liste depuis une ligne SQLite.
  ///
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  factory ListeLecture.depuisMap(Map<String, Object?> map) {
    return ListeLecture(
      id: map.lireEntierOptionnel('id', _entite),
      nom: map.lireTexte('nom', _entite),
      estSysteme: map.lireBooleen('est_systeme', _entite),
      ordre: map.lireEntier('ordre', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ListeLecture copierAvec({
    int? id,
    String? nom,
    bool? estSysteme,
    int? ordre,
  }) {
    return ListeLecture(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      estSysteme: estSysteme ?? this.estSysteme,
      ordre: ordre ?? this.ordre,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ListeLecture &&
            other.id == id &&
            other.nom == nom &&
            other.estSysteme == estSysteme &&
            other.ordre == ordre;
  }

  @override
  int get hashCode => Object.hash(id, nom, estSysteme, ordre);

  @override
  String toString() =>
      'ListeLecture(id: $id, nom: $nom, estSysteme: $estSysteme, '
      'ordre: $ordre)';
}
