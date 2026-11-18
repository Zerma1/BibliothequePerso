/// Transactions partagées entre plusieurs dépôts (import « tout ou rien »).
library;

import 'package:sqflite/sqflite.dart';

/// Ouvre une transaction SQLite dans laquelle plusieurs dépôts écrivent.
///
/// Les méthodes de dépôt qui l'acceptent ont un paramètre nommé facultatif
/// `DatabaseExecutor? executeur` : on leur passe la [Transaction] reçue par
/// [executerEnTransaction]. Sans exécuteur, chaque méthode garde son
/// comportement d'origine (sa propre transaction si elle en ouvrait une).
///
/// Exemple :
/// ```dart
/// await gestionnaire.executerEnTransaction((txn) async {
///   final source = await depotSources.enregistrerSource(s, executeur: txn);
///   await depotTitres.enregistrerTitre(t, executeur: txn);
/// });
/// ```
///
/// Règles (verrou non réentrant de sqflite) :
/// - pendant l'action, **tous** les appels à la base passent par la
///   transaction reçue, lectures comprises : un appel sans exécuteur attend
///   la fin de la transaction et bloque donc l'action pour toujours ;
/// - ne jamais rappeler [executerEnTransaction] depuis l'action.
///
/// Si l'action lève une exception, toute la transaction est annulée (rien
/// n'est écrit) et l'exception est relancée telle quelle.
class GestionnaireTransactions {
  /// Crée le gestionnaire sur une base déjà ouverte (la même que celle des
  /// dépôts).
  const GestionnaireTransactions(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Exécute [action] dans une seule transaction et renvoie son résultat.
  ///
  /// Validée si [action] se termine normalement, annulée sinon.
  Future<T> executerEnTransaction<T>(
    Future<T> Function(Transaction executeur) action,
  ) {
    return _baseDeDonnees.transaction<T>(action);
  }

  /// Outil des dépôts : exécute [action] dans la transaction extérieure
  /// [executeur] si elle est fournie, sinon dans une nouvelle transaction de
  /// [baseDeDonnees] (comportement d'origine des méthodes concernées).
  ///
  /// On n'ouvre jamais de transaction imbriquée : sqflite ne les accepte pas
  /// (verrou non réentrant, l'appel bloquerait).
  ///
  /// LIMITE : dans une transaction extérieure, une erreur levée par [action]
  /// n'annule pas les écritures qu'elle a déjà faites (pas de point de
  /// sauvegarde : `ROLLBACK TO SAVEPOINT` serait pris par sqflite pour la
  /// fin de la transaction). Les méthodes concernées vérifient tout avant
  /// leur première écriture, et leur seule écriture susceptible d'échouer
  /// (contrainte UNIQUE) est la première ; c'est l'appelant qui décide
  /// d'annuler toute la transaction en relançant l'erreur.
  static Future<T> executerAtomiquement<T>(
    Database baseDeDonnees,
    DatabaseExecutor? executeur,
    Future<T> Function(DatabaseExecutor executeur) action,
  ) {
    return switch (executeur) {
      Transaction() => action(executeur),
      Database() => executeur.transaction<T>(action),
      _ => baseDeDonnees.transaction<T>(action),
    };
  }
}
