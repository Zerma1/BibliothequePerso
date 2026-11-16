/// Modèle `Telechargement` : un chapitre dans la file de téléchargement
/// hors-ligne.
library;

import 'erreur_base_de_donnees.dart';
import 'outils_modeles.dart';

/// État d'un téléchargement dans la file.
///
/// Chaque valeur est stockée en base sous [valeurSql] (en `snake_case`, comme
/// les colonnes) et non sous `Enum.name` : ne jamais modifier une valeur SQL
/// existante sans migration (la contrainte CHECK de la table la vérifie).
enum StatutTelechargement {
  /// Dans la file, pas encore commencé.
  enAttente('en_attente'),

  /// En cours de téléchargement. Remis en attente au démarrage de
  /// l'application (reprise après interruption).
  enCours('en_cours'),

  /// Archive complète écrite sur le disque.
  termine('termine'),

  /// Échec : voir `Telechargement.messageErreur`.
  echec('echec');

  const StatutTelechargement(this.valeurSql);

  /// Valeur stockée dans la colonne `telechargements.statut`.
  final String valeurSql;

  /// Retrouve un statut depuis sa valeur SQL.
  ///
  /// Lève une [ErreurBaseDeDonnees] si la valeur est inconnue.
  static StatutTelechargement depuisValeurSql(String valeur) {
    for (final statut in values) {
      if (statut.valeurSql == valeur) {
        return statut;
      }
    }
    throw ErreurBaseDeDonnees(
      'Donnée invalide pour Telechargement : la colonne « statut » contient '
      '« $valeur », qui ne fait pas partie des valeurs autorisées '
      '(${values.map((s) => s.valeurSql).join(', ')}).',
    );
  }
}

/// Un chapitre placé dans la file de téléchargement, avec sa progression.
///
/// Il y a au plus un téléchargement par chapitre (contrainte UNIQUE sur
/// `id_chapitre`).
class Telechargement {
  /// Crée un téléchargement. [id] vaut `null` tant qu'il n'est pas enregistré.
  const Telechargement({
    this.id,
    required this.idChapitre,
    this.statut = StatutTelechargement.enAttente,
    this.nombrePagesTotal = 0,
    this.nombrePagesFaites = 0,
    this.messageErreur,
    this.dateAjout,
    this.dateMaj,
  });

  static const String _entite = 'Telechargement';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Identifiant du chapitre à télécharger.
  final int idChapitre;

  /// État du téléchargement.
  final StatutTelechargement statut;

  /// Nombre total de pages du chapitre ; `0` tant qu'il n'est pas connu
  /// (avant la récupération du contenu) et pour un chapitre texte.
  final int nombrePagesTotal;

  /// Nombre de pages déjà écrites dans l'archive.
  final int nombrePagesFaites;

  /// Cause lisible du dernier échec ; `null` si le statut n'est pas
  /// [StatutTelechargement.echec].
  final String? messageErreur;

  /// Date (UTC) d'ajout dans la file ; sert à l'ordre de la file.
  ///
  /// Remplie par `DepotTelechargements` à l'insertion.
  final DateTime? dateAjout;

  /// Date (UTC) de la dernière modification (statut ou progression).
  final DateTime? dateMaj;

  /// Progression entre 0 et 1, ou `null` si le nombre total de pages est
  /// inconnu.
  double? get progression {
    if (nombrePagesTotal <= 0) {
      return null;
    }
    final valeur = nombrePagesFaites / nombrePagesTotal;
    return valeur > 1 ? 1 : valeur;
  }

  /// Convertit le téléchargement en ligne SQLite (colonnes en `snake_case`).
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'id_chapitre': idChapitre,
      'statut': statut.valeurSql,
      'nombre_pages_total': nombrePagesTotal,
      'nombre_pages_faites': nombrePagesFaites,
      'message_erreur': messageErreur,
      'date_ajout': dateVersMillisecondes(dateAjout),
      'date_maj': dateVersMillisecondes(dateMaj),
    };
  }

  /// Construit un téléchargement depuis une ligne SQLite.
  ///
  /// Lève une [ErreurBaseDeDonnees] si une colonne a un type ou une valeur
  /// inattendus.
  factory Telechargement.depuisMap(Map<String, Object?> map) {
    return Telechargement(
      id: map.lireEntierOptionnel('id', _entite),
      idChapitre: map.lireEntier('id_chapitre', _entite),
      statut: StatutTelechargement.depuisValeurSql(
        map.lireTexte('statut', _entite),
      ),
      nombrePagesTotal:
          map.lireEntierOptionnel('nombre_pages_total', _entite) ?? 0,
      nombrePagesFaites:
          map.lireEntierOptionnel('nombre_pages_faites', _entite) ?? 0,
      messageErreur: map.lireTexteOptionnel('message_erreur', _entite),
      dateAjout: map.lireDateOptionnelle('date_ajout', _entite),
      dateMaj: map.lireDateOptionnelle('date_maj', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode (utiliser le constructeur pour effacer [messageErreur]).
  Telechargement copierAvec({
    int? id,
    int? idChapitre,
    StatutTelechargement? statut,
    int? nombrePagesTotal,
    int? nombrePagesFaites,
    String? messageErreur,
    DateTime? dateAjout,
    DateTime? dateMaj,
  }) {
    return Telechargement(
      id: id ?? this.id,
      idChapitre: idChapitre ?? this.idChapitre,
      statut: statut ?? this.statut,
      nombrePagesTotal: nombrePagesTotal ?? this.nombrePagesTotal,
      nombrePagesFaites: nombrePagesFaites ?? this.nombrePagesFaites,
      messageErreur: messageErreur ?? this.messageErreur,
      dateAjout: dateAjout ?? this.dateAjout,
      dateMaj: dateMaj ?? this.dateMaj,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Telechargement &&
            other.id == id &&
            other.idChapitre == idChapitre &&
            other.statut == statut &&
            other.nombrePagesTotal == nombrePagesTotal &&
            other.nombrePagesFaites == nombrePagesFaites &&
            other.messageErreur == messageErreur &&
            other.dateAjout == dateAjout &&
            other.dateMaj == dateMaj;
  }

  @override
  int get hashCode => Object.hash(
    id,
    idChapitre,
    statut,
    nombrePagesTotal,
    nombrePagesFaites,
    messageErreur,
    dateAjout,
    dateMaj,
  );

  @override
  String toString() =>
      'Telechargement(id: $id, idChapitre: $idChapitre, statut: '
      '${statut.valeurSql}, pages: $nombrePagesFaites/$nombrePagesTotal'
      '${messageErreur == null ? '' : ', erreur: $messageErreur'})';
}
