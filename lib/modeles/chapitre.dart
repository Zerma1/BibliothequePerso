/// Modèle `Chapitre` : une unité de lecture d'un titre.
library;

import 'outils_modeles.dart';

/// Un chapitre d'un titre.
class Chapitre {
  /// Crée un chapitre. [id] vaut `null` tant qu'il n'est pas enregistré.
  const Chapitre({
    this.id,
    this.idTitre,
    required this.urlChapitre,
    required this.nom,
    required this.numero,
    this.langue = '',
    this.datePublication,
    this.estLu = false,
    this.estTelecharge = false,
    this.dateDetection,
  });

  static const String _entite = 'Chapitre';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Identifiant du titre parent.
  ///
  /// `null` tant que le chapitre n'est connu que de l'adaptateur de site ;
  /// `DepotChapitres` exige une valeur pour l'enregistrer.
  final int? idTitre;

  /// URL du chapitre sur le site (unique en base : sert à détecter les doublons).
  final String urlChapitre;

  /// Nom affiché du chapitre.
  final String nom;

  /// Numéro du chapitre (`10.5` pour un chapitre intermédiaire) ; sert au tri.
  final double numero;

  /// Langue du chapitre (code ISO 639-1), vide si inconnue.
  final String langue;

  /// Date de publication (UTC) indiquée par le site, si connue.
  final DateTime? datePublication;

  /// `true` si le client a lu ce chapitre.
  final bool estLu;

  /// `true` si l'archive hors-ligne du chapitre est complète sur le disque.
  final bool estTelecharge;

  /// Date (UTC) à laquelle l'application a découvert ce chapitre.
  ///
  /// Remplie par `DepotChapitres` à l'insertion si elle est absente ; sert à
  /// signaler les nouveaux chapitres.
  final DateTime? dateDetection;

  /// Convertit le chapitre en ligne SQLite (colonnes en `snake_case`).
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'id_titre': idTitre,
      'url_chapitre': urlChapitre,
      'nom': nom,
      'numero': numero,
      'langue': langue,
      'date_publication': dateVersMillisecondes(datePublication),
      'est_lu': booleenVersEntier(estLu),
      'est_telecharge': booleenVersEntier(estTelecharge),
      'date_detection': dateVersMillisecondes(dateDetection),
    };
  }

  /// Construit un chapitre depuis une ligne SQLite.
  ///
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  factory Chapitre.depuisMap(Map<String, Object?> map) {
    return Chapitre(
      id: map.lireEntierOptionnel('id', _entite),
      idTitre: map.lireEntierOptionnel('id_titre', _entite),
      urlChapitre: map.lireTexte('url_chapitre', _entite),
      nom: map.lireTexte('nom', _entite),
      numero: map.lireDouble('numero', _entite),
      langue: map.lireTexteOptionnel('langue', _entite) ?? '',
      datePublication: map.lireDateOptionnelle('date_publication', _entite),
      estLu: map.lireBooleen('est_lu', _entite),
      estTelecharge: map.lireBooleen('est_telecharge', _entite),
      dateDetection: map.lireDateOptionnelle('date_detection', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode.
  Chapitre copierAvec({
    int? id,
    int? idTitre,
    String? urlChapitre,
    String? nom,
    double? numero,
    String? langue,
    DateTime? datePublication,
    bool? estLu,
    bool? estTelecharge,
    DateTime? dateDetection,
  }) {
    return Chapitre(
      id: id ?? this.id,
      idTitre: idTitre ?? this.idTitre,
      urlChapitre: urlChapitre ?? this.urlChapitre,
      nom: nom ?? this.nom,
      numero: numero ?? this.numero,
      langue: langue ?? this.langue,
      datePublication: datePublication ?? this.datePublication,
      estLu: estLu ?? this.estLu,
      estTelecharge: estTelecharge ?? this.estTelecharge,
      dateDetection: dateDetection ?? this.dateDetection,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Chapitre &&
            other.id == id &&
            other.idTitre == idTitre &&
            other.urlChapitre == urlChapitre &&
            other.nom == nom &&
            other.numero == numero &&
            other.langue == langue &&
            other.datePublication == datePublication &&
            other.estLu == estLu &&
            other.estTelecharge == estTelecharge &&
            other.dateDetection == dateDetection;
  }

  @override
  int get hashCode => Object.hash(
    id,
    idTitre,
    urlChapitre,
    nom,
    numero,
    langue,
    datePublication,
    estLu,
    estTelecharge,
    dateDetection,
  );

  @override
  String toString() =>
      'Chapitre(id: $id, idTitre: $idTitre, numero: $numero, nom: $nom, '
      'langue: $langue, estLu: $estLu, estTelecharge: $estTelecharge)';
}
