/// Dépôt des tickets créés depuis l'application (table `tickets`,
/// migration 14).
///
/// Le dépôt ne fait aucun appel réseau : les informations GitHub lui sont
/// données par le service qui interroge l'API publique.
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/outils_modeles.dart';
import '../modeles/ticket.dart';

DateTime _maintenantUtc() => DateTime.now().toUtc();

/// Accès à la table `tickets` : création, liste, relevés GitHub,
/// consultation et retrait.
///
/// Retirer un ticket ne le supprime que de l'application, jamais sur GitHub.
class DepotTickets {
  /// Crée le dépôt sur une base déjà ouverte. [horloge] fournit les dates de
  /// relevé et de consultation (par défaut : maintenant, en UTC).
  const DepotTickets(this._baseDeDonnees, {this._horloge = _maintenantUtc});

  final Database _baseDeDonnees;
  final DateTime Function() _horloge;

  static const String _table = 'tickets';

  // Plus récents d'abord ; l'identifiant départage deux tickets créés dans
  // la même milliseconde (le dernier inséré d'abord).
  static const String _ordreListe = 'date_creation DESC, id DESC';

  /// Enregistre un nouveau [ticket] et le renvoie avec son identifiant.
  ///
  /// L'identifiant éventuel de [ticket] est ignoré (toujours une création).
  /// Lève une [ErreurBaseDeDonnees] si son repère (ou son numéro GitHub) est
  /// déjà utilisé.
  Future<Ticket> enregistrer(Ticket ticket) async {
    final ligne = ticket.versMap()..remove('id');
    try {
      final id = await _baseDeDonnees.insert(
        _table,
        ligne,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return Ticket.depuisMap(<String, Object?>{...ligne, 'id': id});
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer le ticket « ${ticket.repere} »'
        '${erreur.isUniqueConstraintError() ? ' : ce repère est déjà utilisé' : ''}.',
        cause: erreur,
      );
    }
  }

  /// Charge tous les tickets, les plus récents d'abord.
  Future<List<Ticket>> chargerTous() async {
    try {
      final lignes = await _baseDeDonnees.query(_table, orderBy: _ordreListe);
      return lignes.map(Ticket.depuisMap).toList();
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible de charger les tickets.',
        cause: erreur,
      );
    }
  }

  /// Charge le ticket de repère [repere], ou `null` s'il n'existe pas.
  Future<Ticket?> chargerParRepere(String repere) async {
    try {
      final lignes = await _baseDeDonnees.query(
        _table,
        where: 'repere = ?',
        whereArgs: <Object?>[repere],
        limit: 1,
      );
      return lignes.isEmpty ? null : Ticket.depuisMap(lignes.first);
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible de charger le ticket « $repere ».',
        cause: erreur,
      );
    }
  }

  /// Enregistre le relevé GitHub de l'issue du ticket [idTicket] et renvoie
  /// le ticket à jour.
  ///
  /// Toutes les informations GitHub sont remplacées ([raisonFermeture] est
  /// effacée si elle vaut `null`, par exemple après une réouverture) et la
  /// date du dernier relevé vaut maintenant.
  ///
  /// Premier relevé (ticket sans date de consultation) : la consultation est
  /// fixée à [dateMajGithub]. L'utilisateur vient d'écrire l'issue ; elle
  /// n'est donc signalée « nouveau » qu'à partir du changement suivant.
  ///
  /// Lève une [ErreurBaseDeDonnees] si le ticket n'existe pas ou si
  /// [numero] est déjà associé à un autre ticket.
  Future<Ticket> enregistrerReleve(
    int idTicket, {
    required int numero,
    required EtatTicket etat,
    RaisonFermetureTicket? raisonFermeture,
    required List<String> etiquettes,
    required int nombreCommentaires,
    required DateTime dateMajGithub,
  }) async {
    final majGithub = dateVersMillisecondes(dateMajGithub);
    try {
      return await _baseDeDonnees.transaction((txn) async {
        final modifiees = await txn.rawUpdate(
          'UPDATE $_table SET numero = ?, etat = ?, raison_fermeture = ?, '
          'etiquettes = ?, nombre_commentaires = ?, date_maj_github = ?, '
          'date_dernier_releve = ?, '
          'date_consultation = COALESCE(date_consultation, ?) '
          'WHERE id = ?',
          <Object?>[
            numero,
            etat.valeurSql,
            raisonFermeture?.valeurSql,
            Ticket.encoderEtiquettes(etiquettes),
            nombreCommentaires,
            majGithub,
            dateVersMillisecondes(_horloge()),
            majGithub,
            idTicket,
          ],
        );
        if (modifiees == 0) {
          throw ErreurBaseDeDonnees('Ticket n°$idTicket introuvable.');
        }
        return _chargerParId(txn, idTicket);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer le relevé GitHub du ticket n°$idTicket'
        '${erreur.isUniqueConstraintError() ? ' : l\'issue n°$numero est déjà associée à un autre ticket' : ''}.',
        cause: erreur,
      );
    }
  }

  /// Note un relevé GitHub qui n'a pas retrouvé l'issue du ticket
  /// [idTicket] : seule la date du dernier relevé change.
  ///
  /// Renvoie `false` si le ticket n'existe pas.
  Future<bool> enregistrerReleveSansResultat(int idTicket) =>
      _modifierDate(idTicket, 'date_dernier_releve');

  /// Marque le ticket [idTicket] comme consulté maintenant (il n'est plus
  /// signalé « nouveau »).
  ///
  /// Renvoie `false` si le ticket n'existe pas.
  Future<bool> marquerConsulte(int idTicket) =>
      _modifierDate(idTicket, 'date_consultation');

  /// Retire le ticket [idTicket] de l'application (rien n'est supprimé sur
  /// GitHub). Renvoie `false` s'il n'existait pas.
  Future<bool> supprimer(int idTicket) async {
    try {
      final supprimees = await _baseDeDonnees.delete(
        _table,
        where: 'id = ?',
        whereArgs: <Object?>[idTicket],
      );
      return supprimees > 0;
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible de retirer le ticket n°$idTicket.',
        cause: erreur,
      );
    }
  }

  /// Écrit maintenant dans la colonne de date [colonne] (nom constant
  /// choisi dans ce fichier, jamais une donnée extérieure).
  Future<bool> _modifierDate(int idTicket, String colonne) async {
    try {
      final modifiees = await _baseDeDonnees.update(
        _table,
        <String, Object?>{colonne: dateVersMillisecondes(_horloge())},
        where: 'id = ?',
        whereArgs: <Object?>[idTicket],
      );
      return modifiees > 0;
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible de mettre à jour le ticket n°$idTicket.',
        cause: erreur,
      );
    }
  }

  Future<Ticket> _chargerParId(DatabaseExecutor executeur, int id) async {
    final lignes = await executeur.query(
      _table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (lignes.isEmpty) {
      throw ErreurBaseDeDonnees('Ticket n°$id introuvable.');
    }
    return Ticket.depuisMap(lignes.first);
  }
}
