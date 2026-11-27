/// Modèle `Ticket` : un ticket (issue GitHub du dépôt public de
/// l'application) créé par l'utilisateur depuis l'application, et son
/// avancée relevée sur GitHub.
///
/// Le ticket est d'abord enregistré localement avec un [Ticket.repere]
/// unique (`BP-` + 12 caractères hexadécimaux) écrit dans le texte de
/// l'issue ; ce repère permet ensuite de retrouver l'issue par l'API
/// publique. Les informations GitHub restent `null` tant que l'issue n'est
/// pas retrouvée.
library;

import 'dart:convert';

import 'erreur_base_de_donnees.dart';
import 'outils_modeles.dart';

/// Nature d'un ticket, choisie par l'utilisateur à la création.
///
/// Stockée en base sous son nom (`Enum.name`, colonne
/// `tickets.type_ticket`, contrôlée par un CHECK) : ne jamais renommer une
/// valeur existante sans migration.
enum TypeTicket {
  /// Anomalie constatée dans l'application.
  bug,

  /// Idée d'amélioration ou de nouvelle fonctionnalité.
  suggestion,

  /// Question sur l'utilisation.
  question,
}

/// État d'une issue GitHub.
///
/// Stocké en base sous [valeurSql] (colonne `tickets.etat`, contrôlée par un
/// CHECK) : ne jamais modifier une valeur SQL existante sans migration.
enum EtatTicket {
  /// Issue ouverte (`state = open`).
  ouvert('ouvert'),

  /// Issue fermée (`state = closed`).
  ferme('ferme');

  const EtatTicket(this.valeurSql);

  /// Valeur stockée dans la colonne `tickets.etat`.
  final String valeurSql;

  /// Retrouve un état depuis sa valeur SQL ; `null` pour `null`.
  ///
  /// Lève une [ErreurBaseDeDonnees] si la valeur est inconnue.
  static EtatTicket? depuisValeurSql(String? valeur) =>
      _depuisValeurSql(valeur, values, (e) => e.valeurSql, 'etat');
}

/// Raison de fermeture d'une issue, quand GitHub la fournit
/// (`state_reason`).
///
/// Stockée en base sous [valeurSql] (colonne `tickets.raison_fermeture`,
/// contrôlée par un CHECK) : ne jamais modifier une valeur SQL existante
/// sans migration.
enum RaisonFermetureTicket {
  /// Demande traitée (`completed`).
  termine('termine'),

  /// Demande non retenue (`not_planned`).
  nonRetenu('non_retenu');

  const RaisonFermetureTicket(this.valeurSql);

  /// Valeur stockée dans la colonne `tickets.raison_fermeture`.
  final String valeurSql;

  /// Retrouve une raison depuis sa valeur SQL ; `null` pour `null`.
  ///
  /// Lève une [ErreurBaseDeDonnees] si la valeur est inconnue.
  static RaisonFermetureTicket? depuisValeurSql(String? valeur) =>
      _depuisValeurSql(valeur, values, (r) => r.valeurSql, 'raison_fermeture');
}

/// Recherche commune aux énumérations stockées sous une valeur SQL.
T? _depuisValeurSql<T>(
  String? valeur,
  List<T> valeurs,
  String Function(T) valeurSql,
  String colonne,
) {
  if (valeur == null) {
    return null;
  }
  for (final element in valeurs) {
    if (valeurSql(element) == valeur) {
      return element;
    }
  }
  throw ErreurBaseDeDonnees(
    'Donnée invalide pour Ticket : la colonne « $colonne » contient '
    '« $valeur », qui ne fait pas partie des valeurs autorisées '
    '(${valeurs.map(valeurSql).join(', ')}).',
  );
}

/// Un ticket créé depuis l'application, avec les informations relevées sur
/// l'issue GitHub correspondante.
class Ticket {
  /// Crée un ticket. [id] vaut `null` tant qu'il n'est pas enregistré ; les
  /// informations GitHub ([numero] à [dateDernierReleve]) restent vides tant
  /// que l'issue n'est pas retrouvée.
  const Ticket({
    this.id,
    required this.repere,
    required this.titre,
    required this.type,
    required this.dateCreation,
    this.numero,
    this.etat,
    this.raisonFermeture,
    this.etiquettes = const <String>[],
    this.nombreCommentaires,
    this.dateMajGithub,
    this.dateDernierReleve,
    this.dateConsultation,
  });

  static const String _entite = 'Ticket';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Repère unique écrit dans le texte de l'issue (ex. `BP-0123456789ab`),
  /// qui permet de la retrouver par l'API publique.
  final String repere;

  /// Titre saisi par l'utilisateur à la création.
  final String titre;

  /// Nature du ticket.
  final TypeTicket type;

  /// Date (UTC) de création du ticket dans l'application.
  final DateTime dateCreation;

  /// Numéro de l'issue sur GitHub ; `null` tant qu'elle n'est pas
  /// retrouvée.
  final int? numero;

  /// État de l'issue ; `null` tant qu'elle n'est pas retrouvée.
  final EtatTicket? etat;

  /// Raison de fermeture si l'issue est fermée et que GitHub la fournit.
  final RaisonFermetureTicket? raisonFermeture;

  /// Noms des étiquettes (labels) de l'issue, dans l'ordre de GitHub ; vide
  /// tant que l'issue n'est pas retrouvée.
  final List<String> etiquettes;

  /// Nombre de commentaires de l'issue ; `null` tant qu'elle n'est pas
  /// retrouvée.
  final int? nombreCommentaires;

  /// Date (UTC) de dernière mise à jour de l'issue sur GitHub
  /// (`updated_at`).
  final DateTime? dateMajGithub;

  /// Date (UTC) du dernier relevé sur GitHub (réussi ou non).
  final DateTime? dateDernierReleve;

  /// Date (UTC) de la dernière consultation du ticket par l'utilisateur.
  final DateTime? dateConsultation;

  /// `true` si l'issue a été retrouvée sur GitHub.
  bool get estRetrouve => numero != null;

  /// `true` si l'issue a changé sur GitHub depuis la dernière consultation
  /// (à signaler « nouveau »). Faux tant que l'issue n'est pas relevée ou
  /// que le ticket n'a aucune date de consultation.
  bool get aDesNouveautes {
    final majGithub = dateMajGithub;
    final consultation = dateConsultation;
    return majGithub != null &&
        consultation != null &&
        majGithub.isAfter(consultation);
  }

  /// Convertit le ticket en ligne SQLite (colonnes en `snake_case`).
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'repere': repere,
      'titre': titre,
      'type_ticket': type.name,
      'date_creation': dateVersMillisecondes(dateCreation),
      'numero': numero,
      'etat': etat?.valeurSql,
      'raison_fermeture': raisonFermeture?.valeurSql,
      'etiquettes': encoderEtiquettes(etiquettes),
      'nombre_commentaires': nombreCommentaires,
      'date_maj_github': dateVersMillisecondes(dateMajGithub),
      'date_dernier_releve': dateVersMillisecondes(dateDernierReleve),
      'date_consultation': dateVersMillisecondes(dateConsultation),
    };
  }

  /// Convertit des étiquettes en texte JSON (tableau de textes) pour la
  /// colonne `tickets.etiquettes`.
  static String encoderEtiquettes(List<String> etiquettes) =>
      jsonEncode(etiquettes);

  /// Lit le texte JSON de la colonne `tickets.etiquettes`.
  ///
  /// `null` ou un texte vide donne une liste vide. Lève une
  /// [ErreurBaseDeDonnees] si le texte n'est pas un tableau JSON de textes.
  static List<String> decoderEtiquettes(String? texte) {
    if (texte == null || texte.isEmpty) {
      return const <String>[];
    }
    final Object? decode;
    try {
      decode = jsonDecode(texte);
    } on FormatException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Donnée invalide pour $_entite : la colonne « etiquettes » n'est pas "
        'du JSON valide ($texte).',
        cause: erreur,
      );
    }
    if (decode is! List<Object?> || decode.any((e) => e is! String)) {
      throw ErreurBaseDeDonnees(
        'Donnée invalide pour $_entite : la colonne « etiquettes » doit être '
        'un tableau JSON de textes, reçu « $texte ».',
      );
    }
    return List<String>.unmodifiable(decode.cast<String>());
  }

  /// Construit un ticket depuis une ligne SQLite.
  ///
  /// Lève une [ErreurBaseDeDonnees] si une colonne a un type ou une valeur
  /// inattendus.
  factory Ticket.depuisMap(Map<String, Object?> map) {
    final dateCreation = map.lireDateOptionnelle('date_creation', _entite);
    if (dateCreation == null) {
      throw const ErreurBaseDeDonnees(
        'Donnée invalide pour Ticket : la colonne « date_creation » doit être '
        'un entier, reçu NULL ou absente.',
      );
    }
    return Ticket(
      id: map.lireEntierOptionnel('id', _entite),
      repere: map.lireTexte('repere', _entite),
      titre: map.lireTexte('titre', _entite),
      type: map.lireEnum('type_ticket', _entite, TypeTicket.values),
      dateCreation: dateCreation,
      numero: map.lireEntierOptionnel('numero', _entite),
      etat: EtatTicket.depuisValeurSql(map.lireTexteOptionnel('etat', _entite)),
      raisonFermeture: RaisonFermetureTicket.depuisValeurSql(
        map.lireTexteOptionnel('raison_fermeture', _entite),
      ),
      etiquettes: decoderEtiquettes(
        map.lireTexteOptionnel('etiquettes', _entite),
      ),
      nombreCommentaires: map.lireEntierOptionnel(
        'nombre_commentaires',
        _entite,
      ),
      dateMajGithub: map.lireDateOptionnelle('date_maj_github', _entite),
      dateDernierReleve: map.lireDateOptionnelle(
        'date_dernier_releve',
        _entite,
      ),
      dateConsultation: map.lireDateOptionnelle('date_consultation', _entite),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode (utiliser le constructeur, par exemple pour effacer
  /// [raisonFermeture] après une réouverture).
  Ticket copierAvec({
    int? id,
    String? repere,
    String? titre,
    TypeTicket? type,
    DateTime? dateCreation,
    int? numero,
    EtatTicket? etat,
    RaisonFermetureTicket? raisonFermeture,
    List<String>? etiquettes,
    int? nombreCommentaires,
    DateTime? dateMajGithub,
    DateTime? dateDernierReleve,
    DateTime? dateConsultation,
  }) {
    return Ticket(
      id: id ?? this.id,
      repere: repere ?? this.repere,
      titre: titre ?? this.titre,
      type: type ?? this.type,
      dateCreation: dateCreation ?? this.dateCreation,
      numero: numero ?? this.numero,
      etat: etat ?? this.etat,
      raisonFermeture: raisonFermeture ?? this.raisonFermeture,
      etiquettes: etiquettes ?? this.etiquettes,
      nombreCommentaires: nombreCommentaires ?? this.nombreCommentaires,
      dateMajGithub: dateMajGithub ?? this.dateMajGithub,
      dateDernierReleve: dateDernierReleve ?? this.dateDernierReleve,
      dateConsultation: dateConsultation ?? this.dateConsultation,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Ticket &&
            other.id == id &&
            other.repere == repere &&
            other.titre == titre &&
            other.type == type &&
            other.dateCreation == dateCreation &&
            other.numero == numero &&
            other.etat == etat &&
            other.raisonFermeture == raisonFermeture &&
            listesEgales(other.etiquettes, etiquettes) &&
            other.nombreCommentaires == nombreCommentaires &&
            other.dateMajGithub == dateMajGithub &&
            other.dateDernierReleve == dateDernierReleve &&
            other.dateConsultation == dateConsultation;
  }

  @override
  int get hashCode => Object.hash(
    id,
    repere,
    titre,
    type,
    dateCreation,
    numero,
    etat,
    raisonFermeture,
    Object.hashAll(etiquettes),
    nombreCommentaires,
    dateMajGithub,
    dateDernierReleve,
    dateConsultation,
  );

  @override
  String toString() =>
      'Ticket(id: $id, repere: $repere, type: ${type.name}, '
      'numero: $numero, etat: ${etat?.valeurSql})';
}
