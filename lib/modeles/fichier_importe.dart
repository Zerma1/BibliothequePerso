/// Modèle `FichierImporte` : fichier sans DRM (CBZ, PDF, EPUB) importé par
/// le client et copié dans la bibliothèque (migration 15).
library;

import 'outils_modeles.dart';
import 'titre.dart';

/// Format d'un fichier importé.
///
/// Stocké en base sous `Enum.name` (colonne `fichiers_importes.format`) : ne
/// jamais renommer une valeur sans migration. Un format ajouté plus tard
/// (CBR, MOBI…) n'est qu'une nouvelle valeur : la colonne n'a pas de CHECK.
enum FormatFichierLocal {
  /// Bande dessinée en archive zip d'images (`.cbz`).
  cbz,

  /// Document PDF (`.pdf`).
  pdf,

  /// Livre numérique EPUB (`.epub`).
  epub;

  /// Extension du fichier, sans point et en minuscules (`cbz`).
  String get extension => name;

  /// Type de titre donné à l'import (modifiable ensuite) : manga pour un
  /// CBZ, livre pour un PDF ou un EPUB.
  TypeTitre get typeTitreParDefaut => switch (this) {
    FormatFichierLocal.cbz => TypeTitre.manga,
    FormatFichierLocal.pdf || FormatFichierLocal.epub => TypeTitre.livre,
  };

  /// `true` si la position de lecture se compte en pages (CBZ, PDF) ;
  /// `false` pour une position EPUB (section et fraction de défilement).
  bool get estPagine => this != FormatFichierLocal.epub;

  /// Format correspondant à l'extension d'un nom ou chemin de fichier
  /// (insensible à la casse : `Tome 1.CBZ` → [cbz]), ou `null` si le
  /// format n'est pas pris en charge.
  static FormatFichierLocal? depuisNomFichier(String nomFichier) {
    final point = nomFichier.lastIndexOf('.');
    if (point < 0 || point == nomFichier.length - 1) return null;
    final extension = nomFichier.substring(point + 1).toLowerCase();
    for (final format in FormatFichierLocal.values) {
      if (format.extension == extension) return format;
    }
    return null;
  }
}

/// Fichier importé : rattaché à l'unique chapitre du titre créé à l'import.
///
/// Le chemin du fichier copié est `Chapitre.nomArchive` (relatif au dossier
/// des chapitres, géré par `StockageTelechargements`) ; cette classe ne
/// garde que ce qui est propre à l'import.
class FichierImporte {
  /// Crée la description d'un fichier importé.
  const FichierImporte({
    required this.idChapitre,
    required this.format,
    required this.empreinteSha256,
    required this.taille,
    required this.nomOrigine,
    required this.dateImport,
  });

  static const String _entite = 'FichierImporte';

  /// Identifiant du chapitre qui pointe vers le fichier copié.
  final int idChapitre;

  /// Format du fichier.
  final FormatFichierLocal format;

  /// Empreinte SHA-256 du contenu, en hexadécimal minuscule (64 caractères) :
  /// sert à refuser l'import d'un fichier déjà présent, même renommé.
  final String empreinteSha256;

  /// Taille du fichier en octets.
  final int taille;

  /// Nom du fichier choisi par le client (sans dossier), pour l'affichage.
  final String nomOrigine;

  /// Date (UTC) de l'import.
  final DateTime dateImport;

  /// Convertit en ligne SQLite (colonnes en `snake_case`).
  Map<String, Object?> versMap() => <String, Object?>{
    'id_chapitre': idChapitre,
    'format': format.name,
    'empreinte_sha256': empreinteSha256,
    'taille': taille,
    'nom_origine': nomOrigine,
    'date_import': dateVersMillisecondes(dateImport),
  };

  /// Construit depuis une ligne SQLite. Lève une `ErreurBaseDeDonnees` si
  /// une colonne a un type ou une valeur inattendus.
  factory FichierImporte.depuisMap(Map<String, Object?> map) {
    return FichierImporte(
      idChapitre: map.lireEntier('id_chapitre', _entite),
      format: map.lireEnum('format', _entite, FormatFichierLocal.values),
      empreinteSha256: map.lireTexte('empreinte_sha256', _entite),
      taille: map.lireEntier('taille', _entite),
      nomOrigine: map.lireTexte('nom_origine', _entite),
      dateImport: DateTime.fromMillisecondsSinceEpoch(
        map.lireEntier('date_import', _entite),
        isUtc: true,
      ),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés (`null` = inchangé).
  FichierImporte copierAvec({
    int? idChapitre,
    FormatFichierLocal? format,
    String? empreinteSha256,
    int? taille,
    String? nomOrigine,
    DateTime? dateImport,
  }) {
    return FichierImporte(
      idChapitre: idChapitre ?? this.idChapitre,
      format: format ?? this.format,
      empreinteSha256: empreinteSha256 ?? this.empreinteSha256,
      taille: taille ?? this.taille,
      nomOrigine: nomOrigine ?? this.nomOrigine,
      dateImport: dateImport ?? this.dateImport,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FichierImporte &&
            other.idChapitre == idChapitre &&
            other.format == format &&
            other.empreinteSha256 == empreinteSha256 &&
            other.taille == taille &&
            other.nomOrigine == nomOrigine &&
            other.dateImport == dateImport;
  }

  @override
  int get hashCode => Object.hash(
    idChapitre,
    format,
    empreinteSha256,
    taille,
    nomOrigine,
    dateImport,
  );

  @override
  String toString() =>
      'FichierImporte(idChapitre: $idChapitre, format: ${format.name}, '
      'taille: $taille, nomOrigine: $nomOrigine)';
}
