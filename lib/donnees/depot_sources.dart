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
  ///
  /// [executeur] : transaction ouverte par `GestionnaireTransactions` pour
  /// écrire avec d'autres dépôts ; `null` écrit directement dans la base.
  Future<Source> enregistrerSource(
    Source source, {
    DatabaseExecutor? executeur,
  }) async {
    final base = executeur ?? _baseDeDonnees;
    try {
      final id = source.id;
      if (id == null) {
        final nouvelId = await base.insert('sources', source.versMap());
        return source.copierAvec(id: nouvelId);
      }
      final modifiees = await base.update(
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
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<Source>> chargerSources({DatabaseExecutor? executeur}) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      'sources',
      orderBy: 'nom COLLATE NOCASE',
    );
    return lignes.map(Source.depuisMap).toList();
  }

  /// Charge une source par son identifiant, ou `null` si elle n'existe pas.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<Source?> chargerSource(int id, {DatabaseExecutor? executeur}) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      'sources',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return lignes.isEmpty ? null : Source.depuisMap(lignes.first);
  }

  /// Charge une source par son URL de base exacte, ou `null`.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<Source?> chargerSourceParUrl(
    String urlBase, {
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      'sources',
      where: 'url_base = ?',
      whereArgs: <Object?>[urlBase],
      limit: 1,
    );
    return lignes.isEmpty ? null : Source.depuisMap(lignes.first);
  }

  /// Supprime une source.
  ///
  /// Lève une [ErreurBaseDeDonnees] si des titres en dépendent encore (comme
  /// site principal ou secondaire), ou si des chapitres venant de ce site
  /// sont encore enregistrés (chapitres lus ou téléchargés gardés après le
  /// retrait du site d'un titre) : les clés étrangères `titres.id_source`,
  /// `titres_sources.id_source` et `chapitres.id_source` sont en `ON DELETE
  /// RESTRICT` pour ne jamais effacer une partie de la bibliothèque par
  /// accident.
  Future<void> supprimerSource(int id) async {
    // Vérification explicite dans la même transaction que la suppression :
    // le message d'erreur est clair, et la contrainte RESTRICT reste en
    // filet de sécurité.
    await _baseDeDonnees.transaction((txn) async {
      // titres_sources contient aussi le site principal de chaque titre
      // (migration 7) : un seul comptage couvre les deux cas. Servi par
      // l'index index_titres_sources_id_source.
      final nombreTitres =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(DISTINCT id_titre) FROM titres_sources '
              'WHERE id_source = ?',
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
      // LIMITE : pas d'index avec id_source en tête sur chapitres, la
      // requête parcourt la table ; la suppression d'un site est rare.
      final nombreChapitres =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM chapitres WHERE id_source = ?',
              <Object?>[id],
            ),
          ) ??
          0;
      if (nombreChapitres > 0) {
        throw ErreurBaseDeDonnees(
          'Impossible de supprimer la source n°$id : $nombreChapitres '
          'chapitre(s) lus ou téléchargés viennent encore de ce site.',
        );
      }
      await txn.delete('sources', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }
}
