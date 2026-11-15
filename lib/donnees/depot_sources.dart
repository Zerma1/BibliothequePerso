/// Dépôt des sources (sites configurés).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/source.dart';

/// Accès à la table `sources`.
class DepotSources {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotSources(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Enregistre une source : insertion si [Source.id] est `null`, mise à jour
  /// sinon. Renvoie la source avec son identifiant.
  ///
  /// Lève une [ErreurBaseDeDonnees] si l'URL de base est déjà utilisée par une
  /// autre source, ou si la source à mettre à jour n'existe pas.
  Future<Source> enregistrerSource(Source source) async {
    try {
      final id = source.id;
      if (id == null) {
        final nouvelId = await _baseDeDonnees.insert(
          'sources',
          source.versMap(),
        );
        return source.copierAvec(id: nouvelId);
      }
      final modifiees = await _baseDeDonnees.update(
        'sources',
        source.versMap(),
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (modifiees == 0) {
        throw ErreurBaseDeDonnees('La source n°$id n\'existe pas.');
      }
      return source;
    } on DatabaseException catch (erreur) {
      if (erreur.isUniqueConstraintError()) {
        throw ErreurBaseDeDonnees(
          'Une source avec l\'URL « ${source.urlBase} » existe déjà.',
          cause: erreur,
        );
      }
      rethrow;
    }
  }

  /// Charge toutes les sources, triées par nom.
  Future<List<Source>> chargerSources() async {
    final lignes = await _baseDeDonnees.query(
      'sources',
      orderBy: 'nom COLLATE NOCASE',
    );
    return lignes.map(Source.depuisMap).toList();
  }

  /// Charge une source par son identifiant, ou `null` si elle n'existe pas.
  Future<Source?> chargerSource(int id) async {
    final lignes = await _baseDeDonnees.query(
      'sources',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return lignes.isEmpty ? null : Source.depuisMap(lignes.first);
  }

  /// Charge une source par son URL de base exacte, ou `null`.
  Future<Source?> chargerSourceParUrl(String urlBase) async {
    final lignes = await _baseDeDonnees.query(
      'sources',
      where: 'url_base = ?',
      whereArgs: <Object?>[urlBase],
      limit: 1,
    );
    return lignes.isEmpty ? null : Source.depuisMap(lignes.first);
  }

  /// Supprime une source.
  ///
  /// Lève une [ErreurBaseDeDonnees] si des titres en dépendent encore : la
  /// clé étrangère `titres.id_source` est en `ON DELETE RESTRICT` pour ne
  /// jamais effacer une partie de la bibliothèque par accident.
  Future<void> supprimerSource(int id) async {
    // Vérification explicite dans la même transaction que la suppression :
    // le message d'erreur est clair, et la contrainte RESTRICT reste en
    // filet de sécurité.
    await _baseDeDonnees.transaction((txn) async {
      final nombreTitres =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM titres WHERE id_source = ?',
              <Object?>[id],
            ),
          ) ??
          0;
      if (nombreTitres > 0) {
        throw ErreurBaseDeDonnees(
          'Impossible de supprimer la source n°$id : $nombreTitres titre(s) en '
          'dépendent encore. Supprimez d\'abord ces titres.',
        );
      }
      await txn.delete('sources', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }
}
