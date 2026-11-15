/// Dépôt des réglages de l'application (table `parametres`).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/erreur_base_de_donnees.dart';

/// Accès clé-valeur à la table `parametres`.
///
/// Ce dépôt ne connaît ni les noms des clés ni les valeurs par défaut : c'est
/// la couche services qui les définit. Toutes les valeurs sont stockées en
/// texte ; les entiers sont convertis à la lecture et à l'écriture.
class DepotParametres {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotParametres(this._baseDeDonnees);

  final Database _baseDeDonnees;

  static const String _table = 'parametres';

  /// Charge la valeur texte de [cle], ou `null` si elle est absente.
  Future<String?> chargerTexte(String cle) async {
    final lignes = await _baseDeDonnees.query(
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
  Future<int?> chargerEntier(String cle) async {
    final texte = await chargerTexte(cle);
    return texte == null ? null : int.tryParse(texte.trim());
  }

  /// Enregistre [valeur] pour [cle] (insère ou remplace).
  Future<void> enregistrerTexte(String cle, String valeur) async {
    try {
      // REPLACE sur la clé primaire : un seul réglage par clé.
      await _baseDeDonnees.insert(_table, <String, Object?>{
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
  Future<void> enregistrerEntier(String cle, int valeur) {
    return enregistrerTexte(cle, valeur.toString());
  }

  /// Supprime le réglage [cle] ; renvoie `true` s'il existait.
  Future<bool> supprimer(String cle) async {
    final supprimees = await _baseDeDonnees.delete(
      _table,
      where: 'cle = ?',
      whereArgs: <Object?>[cle],
    );
    return supprimees > 0;
  }

  /// Charge tous les réglages enregistrés, triés par clé.
  Future<Map<String, String>> chargerTout() async {
    final lignes = await _baseDeDonnees.query(_table, orderBy: 'cle');
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
