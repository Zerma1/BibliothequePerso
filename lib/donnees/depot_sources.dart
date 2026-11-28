/// Dépôt des sources (sites configurés).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/constantes.dart';
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
      // Déclencheur de la migration 15 : la source « Fichiers locaux » ne
      // change ni d'adresse, ni de type, et n'est jamais activée.
      if (erreur.toString().contains('source fichiers locaux')) {
        throw ErreurBaseDeDonnees(
          'La source « $nomSourceFichiersLocaux » est une source système : '
          "seuls son nom et sa langue peuvent changer, elle n'est jamais "
          'activée.',
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
      // Source système « Fichiers locaux » (migration 15) : refus explicite,
      // le déclencheur de la migration reste en filet de sécurité.
      final systeme = await txn.query(
        'sources',
        columns: <String>['id'],
        where: 'id = ? AND url_base = ?',
        whereArgs: <Object?>[id, urlBaseFichiersLocaux],
        limit: 1,
      );
      if (systeme.isNotEmpty) {
        throw const ErreurBaseDeDonnees(
          'La source « $nomSourceFichiersLocaux » est une source système : '
          'elle ne peut pas être supprimée.',
        );
      }
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

  /// Supprime, en une seule transaction, toutes les sources dont plus rien
  /// ne dépend, et renvoie le nombre de sources supprimées (`supprimees`) et
  /// gardées (`gardees`).
  ///
  /// Sert à la désinstallation partielle (« supprimer les sources »). Une
  /// source est gardée tant qu'un titre l'utilise comme site principal
  /// (`titres.id_source`) ou secondaire (`titres_sources`), ou qu'un
  /// chapitre en vient (`chapitres.id_source`) : ces trois clés sont en `ON
  /// DELETE RESTRICT` et `titres.id_source` est `NOT NULL`, un titre ne peut
  /// donc pas rester sans source. Pour tout supprimer, appeler d'abord
  /// `DepotTitres.supprimerTousLesTitres` : après lui, `gardees` vaut 0, ou 1
  /// si la source système « Fichiers locaux » existe (créée au premier
  /// import, migration 15 : jamais supprimée).
  ///
  /// Les titres ne sont jamais touchés. Les sous-requêtes `NOT EXISTS` sont
  /// servies par `index_titres_id_source` et `index_titres_sources_id_source`
  /// ; celle sur `chapitres` parcourt la table (pas d'index avec `id_source`
  /// en tête, même LIMITE que [supprimerSource]) — opération rare.
  ///
  /// Lève une [ErreurBaseDeDonnees] si l'écriture échoue (rien n'est alors
  /// supprimé).
  Future<({int supprimees, int gardees})> supprimerSourcesInutilisees() async {
    try {
      return await _baseDeDonnees.transaction((txn) async {
        // Aucune valeur extérieure : la requête ne compare que des colonnes.
        // La source système « Fichiers locaux » (migration 15) n'est jamais
        // supprimée : son déclencheur ferait échouer toute la requête.
        final supprimees = await txn.rawDelete(
          'DELETE FROM sources WHERE url_base != ? '
          'AND NOT EXISTS (SELECT 1 FROM titres t WHERE t.id_source = sources.id) '
          'AND NOT EXISTS (SELECT 1 FROM titres_sources ts '
          'WHERE ts.id_source = sources.id) '
          'AND NOT EXISTS (SELECT 1 FROM chapitres c '
          'WHERE c.id_source = sources.id)',
          <Object?>[urlBaseFichiersLocaux],
        );
        final gardees =
            Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM sources'),
            ) ??
            0;
        return (supprimees: supprimees, gardees: gardees);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible de supprimer les sources.',
        cause: erreur,
      );
    }
  }
}
