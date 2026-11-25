/// Dépôt des réglages de l'application (table `parametres`).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/erreur_base_de_donnees.dart';

/// Accès clé-valeur à la table `parametres`.
///
/// Ce dépôt ne connaît ni les noms des clés ni les valeurs par défaut : c'est
/// la couche services qui les définit. Toutes les valeurs sont stockées en
/// texte ; les entiers sont convertis à la lecture et à l'écriture.
///
/// Chaque méthode accepte un `executeur` facultatif : la transaction ouverte
/// par `GestionnaireTransactions` quand le réglage est écrit avec d'autres
/// dépôts (import « tout ou rien ») ; `null` utilise directement la base.
class DepotParametres {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotParametres(this._baseDeDonnees);

  final Database _baseDeDonnees;

  static const String _table = 'parametres';

  /// Charge la valeur texte de [cle], ou `null` si elle est absente.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<String?> chargerTexte(
    String cle, {
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      _table,
      columns: <String>['valeur'],
      where: 'cle = ?',
      whereArgs: <Object?>[cle],
      limit: 1,
    );
    if (lignes.isEmpty) {
      return null;
    }
    final valeur = lignes.first['valeur'];
    if (valeur is! String) {
      throw ErreurBaseDeDonnees(
        'Donnée invalide pour le paramètre « $cle » : texte attendu, reçu '
        '${valeur.runtimeType}.',
      );
    }
    return valeur;
  }

  /// Charge la valeur entière de [cle], ou `null` si elle est absente ou ne
  /// représente pas un entier (valeur illisible : le service retombe alors
  /// sur sa valeur par défaut).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<int?> chargerEntier(String cle, {DatabaseExecutor? executeur}) async {
    final texte = await chargerTexte(cle, executeur: executeur);
    return texte == null ? null : int.tryParse(texte.trim());
  }

  /// Enregistre [valeur] pour [cle] (insère ou remplace).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<void> enregistrerTexte(
    String cle,
    String valeur, {
    DatabaseExecutor? executeur,
  }) async {
    try {
      // REPLACE sur la clé primaire : un seul réglage par clé.
      await (executeur ?? _baseDeDonnees).insert(_table, <String, Object?>{
        'cle': cle,
        'valeur': valeur,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer le paramètre « $cle ».',
        cause: erreur,
      );
    }
  }

  /// Enregistre l'entier [valeur] pour [cle] (insère ou remplace).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<void> enregistrerEntier(
    String cle,
    int valeur, {
    DatabaseExecutor? executeur,
  }) {
    return enregistrerTexte(cle, valeur.toString(), executeur: executeur);
  }

  /// Supprime le réglage [cle] ; renvoie `true` s'il existait.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<bool> supprimer(String cle, {DatabaseExecutor? executeur}) async {
    final supprimees = await (executeur ?? _baseDeDonnees).delete(
      _table,
      where: 'cle = ?',
      whereArgs: <Object?>[cle],
    );
    return supprimees > 0;
  }

  /// Charge tous les réglages enregistrés, triés par clé.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<Map<String, String>> chargerTout({DatabaseExecutor? executeur}) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      _table,
      orderBy: 'cle',
    );
    final resultat = <String, String>{};
    for (final ligne in lignes) {
      final cle = ligne['cle'];
      final valeur = ligne['valeur'];
      if (cle is! String || valeur is! String) {
        throw const ErreurBaseDeDonnees(
          'Donnée invalide dans la table parametres : texte attendu.',
        );
      }
      resultat[cle] = valeur;
    }
    return resultat;
  }
}
