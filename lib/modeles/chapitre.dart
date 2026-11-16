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
    this.nomArchive,
    this.dateSuppressionPrevue,
    this.estGarde = false,
    this.urlExterne,
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

  /// Chemin de l'archive hors-ligne **relatif** au dossier racine des
  /// téléchargements, avec `/` comme séparateur
  /// (`manga/One Punch Man/ch1.en.zip`), ou `null` si le chapitre n'est pas
  /// téléchargé (ou l'a été avant que ce chemin soit enregistré).
  ///
  /// Enregistré à la fin du téléchargement : le chemin reste valable même si
  /// le titre est renommé ou si la langue par défaut de la source change.
  final String? nomArchive;

  /// Date (UTC) à laquelle l'archive hors-ligne doit être supprimée
  /// automatiquement, ou `null` si aucune suppression n'est prévue.
  final DateTime? dateSuppressionPrevue;

  /// `true` si le client a choisi « Garder » ce chapitre téléchargé : les
  /// règles de conservation ne le suppriment jamais automatiquement.
  ///
  /// Remis à `false` quand l'archive est supprimée (un chapitre retéléchargé
  /// suit de nouveau les règles).
  final bool estGarde;

  /// Lien vers le site de l'éditeur quand le chapitre n'est pas hébergé par
  /// le site source (ex. MangaDex renvoie vers le site officiel), ou `null`
  /// pour un chapitre hébergé (cas normal).
  ///
  /// Un chapitre externe se lit sur ce site (« Lire sur `site` ») et n'est
  /// jamais téléchargeable.
  final String? urlExterne;

  /// `true` si le chapitre est hébergé sur un site externe ([urlExterne]
  /// non vide) : il n'a ni pages à lire dans l'application ni archive.
  bool get estExterne {
    final url = urlExterne;
    return url != null && url.trim().isNotEmpty;
  }

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
      'nom_archive': nomArchive,
      'date_suppression_prevue': dateVersMillisecondes(dateSuppressionPrevue),
      'est_garde': booleenVersEntier(estGarde),
      'url_externe': urlExterne,
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
      nomArchive: map.lireTexteOptionnel('nom_archive', _entite),
      dateSuppressionPrevue: map.lireDateOptionnelle(
        'date_suppression_prevue',
        _entite,
      ),
      // Colonne absente (ligne construite à la main ou requête partielle) :
      // non gardé, comme la valeur par défaut de la migration 5.
      estGarde: map.containsKey('est_garde')
          ? map.lireBooleen('est_garde', _entite)
          : false,
      // Colonne absente (requête partielle) : chapitre hébergé, comme les
      // lignes antérieures à la migration 6.
      urlExterne: map.lireTexteOptionnel('url_externe', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode (un argument `null` signifie « inchangé »), sauf :
  /// - [nomArchive] : `effacerNomArchive: true` le remet à `null` ;
  /// - [dateSuppressionPrevue] : `effacerDateSuppressionPrevue: true` le
  ///   remet à `null` (suppression annulée) ;
  /// - [urlExterne] : `effacerUrlExterne: true` le remet à `null` (chapitre
  ///   de nouveau hébergé par le site source).
  ///
  /// Un indicateur `effacer…` l'emporte sur la valeur donnée pour le même
  /// champ. En base, l'effacement se fait par `DepotChapitres`
  /// (`enregistrerArchive(id, null)`, `planifierSuppression(id, null)`,
  /// `enregistrerChapitres` pour le lien externe).
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
    String? nomArchive,
    DateTime? dateSuppressionPrevue,
    bool? estGarde,
    String? urlExterne,
    bool effacerNomArchive = false,
    bool effacerDateSuppressionPrevue = false,
    bool effacerUrlExterne = false,
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
      nomArchive: effacerNomArchive ? null : nomArchive ?? this.nomArchive,
      dateSuppressionPrevue: effacerDateSuppressionPrevue
          ? null
          : dateSuppressionPrevue ?? this.dateSuppressionPrevue,
      estGarde: estGarde ?? this.estGarde,
      urlExterne: effacerUrlExterne ? null : urlExterne ?? this.urlExterne,
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
            other.dateDetection == dateDetection &&
            other.nomArchive == nomArchive &&
            other.dateSuppressionPrevue == dateSuppressionPrevue &&
            other.estGarde == estGarde &&
            other.urlExterne == urlExterne;
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
    nomArchive,
    dateSuppressionPrevue,
    estGarde,
    urlExterne,
  );

  @override
  String toString() =>
      'Chapitre(id: $id, idTitre: $idTitre, numero: $numero, nom: $nom, '
      'langue: $langue, estLu: $estLu, estTelecharge: $estTelecharge, '
      'nomArchive: $nomArchive, estGarde: $estGarde, '
      'urlExterne: $urlExterne)';
}
