/// Modèle `PositionLecture` : endroit où le client s'est arrêté dans un
/// chapitre (migration 15).
library;

import 'erreur_base_de_donnees.dart';
import 'outils_modeles.dart';

/// Position de lecture d'un chapitre, adaptée à son format :
/// - chapitre en pages (archive `.zip`, CBZ, PDF) : [page] (index à partir
///   de 0) et, si connu, [nombrePages] ;
/// - EPUB : [section] (index dans le *spine*, à partir de 0) et [fraction]
///   de défilement dans cette section (0 = début, 1 = fin).
///
/// Une position a toujours au moins une [page] ou une [section]. Elle ne
/// remplace pas `Chapitre.estLu`, qui reste la seule marque « lu ».
class PositionLecture {
  /// Crée une position. Lève une [ArgumentError] si elle est vide ou hors
  /// bornes (index négatif, fraction hors de 0–1, nombre de pages ≤ 0).
  PositionLecture({
    required this.idChapitre,
    this.page,
    this.nombrePages,
    this.section,
    this.fraction,
    required this.dateMaj,
  }) {
    if (page == null && section == null) {
      throw ArgumentError(
        'Une position de lecture demande une page ou une '
        'section.',
      );
    }
    if ((page ?? 0) < 0 || (section ?? 0) < 0) {
      throw ArgumentError('Index de page ou de section négatif.');
    }
    final valeur = fraction;
    if (valeur != null && !(valeur >= 0 && valeur <= 1)) {
      throw ArgumentError.value(valeur, 'fraction', 'doit être entre 0 et 1');
    }
    if (nombrePages != null && nombrePages! <= 0) {
      throw ArgumentError.value(nombrePages, 'nombrePages', 'doit être > 0');
    }
  }

  /// Position paginée (archive `.zip`, CBZ, PDF) à la page d'index [page].
  factory PositionLecture.page({
    required int idChapitre,
    required int page,
    int? nombrePages,
    required DateTime dateMaj,
  }) => PositionLecture(
    idChapitre: idChapitre,
    page: page,
    nombrePages: nombrePages,
    dateMaj: dateMaj,
  );

  /// Position EPUB : section [section] du spine, [fraction] de défilement.
  factory PositionLecture.epub({
    required int idChapitre,
    required int section,
    double fraction = 0,
    required DateTime dateMaj,
  }) => PositionLecture(
    idChapitre: idChapitre,
    section: section,
    fraction: fraction,
    dateMaj: dateMaj,
  );

  static const String _entite = 'PositionLecture';

  /// Identifiant du chapitre.
  final int idChapitre;

  /// Index de la page (à partir de 0), ou `null` pour une position EPUB.
  final int? page;

  /// Nombre de pages du chapitre au moment de l'enregistrement, si connu
  /// (affichage « page X / N » ou d'un pourcentage sans rouvrir le fichier).
  final int? nombrePages;

  /// Index de la section dans le spine EPUB (à partir de 0), ou `null`.
  final int? section;

  /// Fraction de défilement dans la [section] (0 à 1), ou `null`.
  final double? fraction;

  /// Date (UTC) du dernier enregistrement.
  final DateTime dateMaj;

  /// Convertit en ligne SQLite (colonnes en `snake_case`).
  Map<String, Object?> versMap() => <String, Object?>{
    'id_chapitre': idChapitre,
    'page': page,
    'nombre_pages': nombrePages,
    'section': section,
    'fraction': fraction,
    'date_maj': dateVersMillisecondes(dateMaj),
  };

  /// Construit depuis une ligne SQLite. Lève une [ErreurBaseDeDonnees] si
  /// une colonne a un type inattendu ou si la position est invalide.
  factory PositionLecture.depuisMap(Map<String, Object?> map) {
    final fraction = map['fraction'];
    if (fraction != null && fraction is! num) {
      throw const ErreurBaseDeDonnees(
        'Donnée invalide pour $_entite : la colonne « fraction » doit être un '
        'nombre ou NULL.',
      );
    }
    try {
      return PositionLecture(
        idChapitre: map.lireEntier('id_chapitre', _entite),
        page: map.lireEntierOptionnel('page', _entite),
        nombrePages: map.lireEntierOptionnel('nombre_pages', _entite),
        section: map.lireEntierOptionnel('section', _entite),
        fraction: (fraction as num?)?.toDouble(),
        dateMaj: DateTime.fromMillisecondsSinceEpoch(
          map.lireEntier('date_maj', _entite),
          isUtc: true,
        ),
      );
    } on ArgumentError catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Donnée invalide pour $_entite : ${erreur.message}',
      );
    }
  }

  /// Renvoie une copie avec les champs donnés remplacés (`null` =
  /// inchangé). LIMITE : un champ ne peut pas être remis à `null`.
  PositionLecture copierAvec({
    int? idChapitre,
    int? page,
    int? nombrePages,
    int? section,
    double? fraction,
    DateTime? dateMaj,
  }) {
    return PositionLecture(
      idChapitre: idChapitre ?? this.idChapitre,
      page: page ?? this.page,
      nombrePages: nombrePages ?? this.nombrePages,
      section: section ?? this.section,
      fraction: fraction ?? this.fraction,
      dateMaj: dateMaj ?? this.dateMaj,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PositionLecture &&
            other.idChapitre == idChapitre &&
            other.page == page &&
            other.nombrePages == nombrePages &&
            other.section == section &&
            other.fraction == fraction &&
            other.dateMaj == dateMaj;
  }

  @override
  int get hashCode =>
      Object.hash(idChapitre, page, nombrePages, section, fraction, dateMaj);

  @override
  String toString() =>
      'PositionLecture(idChapitre: $idChapitre, page: $page, '
      'nombrePages: $nombrePages, section: $section, fraction: $fraction)';
}
