/// Dépôt des chapitres et de l'état de lecture.
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/outils_modeles.dart';

/// Accès à la table `chapitres`.
class DepotChapitres {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotChapitres(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Insère les chapitres qui ne sont pas encore connus et renvoie le nombre
  /// de **nouveaux** chapitres.
  ///
  /// Un chapitre est reconnu par son `url_chapitre` (contrainte UNIQUE) : un
  /// chapitre déjà présent n'est pas modifié, ce qui conserve son état de lecture
  /// et de téléchargement. Les chapitres sans [Chapitre.dateDetection] reçoivent
  /// [dateDetection] (par défaut : maintenant).
  ///
  /// Lève une [ErreurBaseDeDonnees] si un chapitre n'a pas de
  /// [Chapitre.idTitre] ou si ce titre n'existe pas ; rien n'est alors écrit.
  Future<int> enregistrerChapitres(
    List<Chapitre> chapitres, {
    DateTime? dateDetection,
  }) async {
    if (chapitres.isEmpty) {
      return 0;
    }
    final detection = dateDetection ?? DateTime.now().toUtc();

    final idsTitres = <int>{};
    for (final chapitre in chapitres) {
      final idTitre = chapitre.idTitre;
      if (idTitre == null) {
        throw ErreurBaseDeDonnees(
          'Le chapitre « ${chapitre.nom} » (${chapitre.urlChapitre}) n\'a pas '
          'de titre : idTitre est requis pour l\'enregistrer.',
        );
      }
      idsTitres.add(idTitre);
    }

    try {
      return await _baseDeDonnees.transaction((txn) async {
        // Vérification explicite des titres parents : sqflite ne permet pas de
        // reconnaître proprement une erreur de clé étrangère, et ce message
        // est plus clair. La transaction annule tout si un titre manque.
        for (final idTitre in idsTitres) {
          final titres = await txn.query(
            'titres',
            columns: <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[idTitre],
            limit: 1,
          );
          if (titres.isEmpty) {
            throw ErreurBaseDeDonnees(
              'Impossible d\'enregistrer les chapitres : le titre n°$idTitre '
              'n\'existe pas.',
            );
          }
        }
        return _insererChapitres(txn, chapitres, detection);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer les chapitres.',
        cause: erreur,
      );
    }
  }

  /// Insère les chapitres inconnus dans [txn] et renvoie le nombre de lignes
  /// ajoutées.
  Future<int> _insererChapitres(
    Transaction txn,
    List<Chapitre> chapitres,
    DateTime detection,
  ) async {
    // On compte les lignes avant et après plutôt que de se fier à la valeur
    // renvoyée par `insert` en cas d'IGNORE, dont le comportement varie selon
    // l'implémentation (plugin Android ou FFI). Dans une transaction, le
    // résultat est exact.
    final avant = await _compterTout(txn);
    for (final chapitre in chapitres) {
      final ligne = chapitre.versMap()..remove('id');
      ligne['date_detection'] ??= dateVersMillisecondes(detection);
      await txn.insert(
        'chapitres',
        ligne,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    final apres = await _compterTout(txn);
    return apres - avant;
  }

  /// Charge les chapitres d'un titre, triés par numéro croissant.
  Future<List<Chapitre>> chargerChapitres(int idTitre) async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      where: 'id_titre = ?',
      whereArgs: <Object?>[idTitre],
      orderBy: 'numero, id',
    );
    return lignes.map(Chapitre.depuisMap).toList();
  }

  /// Charge un chapitre par son identifiant, ou `null`.
  Future<Chapitre?> chargerChapitre(int id) async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return lignes.isEmpty ? null : Chapitre.depuisMap(lignes.first);
  }

  /// Marque un chapitre comme lu (ou non lu si [estLu] vaut `false`).
  Future<void> marquerLu(int idChapitre, {bool estLu = true}) async {
    await _baseDeDonnees.update(
      'chapitres',
      <String, Object?>{'est_lu': booleenVersEntier(estLu)},
      where: 'id = ?',
      whereArgs: <Object?>[idChapitre],
    );
  }

  /// Marque tous les chapitres d'un titre comme lus (ou non lus).
  Future<void> marquerTousLus(int idTitre, {bool estLu = true}) async {
    await _baseDeDonnees.update(
      'chapitres',
      <String, Object?>{'est_lu': booleenVersEntier(estLu)},
      where: 'id_titre = ?',
      whereArgs: <Object?>[idTitre],
    );
  }

  /// Enregistre si l'archive hors-ligne d'un chapitre est complète.
  Future<void> marquerTelecharge(
    int idChapitre, {
    bool estTelecharge = true,
  }) async {
    await _baseDeDonnees.update(
      'chapitres',
      <String, Object?>{'est_telecharge': booleenVersEntier(estTelecharge)},
      where: 'id = ?',
      whereArgs: <Object?>[idChapitre],
    );
  }

  /// Compte les chapitres non lus d'un titre.
  Future<int> compterNonLus(int idTitre) async {
    final lignes = await _baseDeDonnees.rawQuery(
      'SELECT COUNT(*) FROM chapitres WHERE id_titre = ? AND est_lu = ?',
      <Object?>[idTitre, valeurSqlFaux],
    );
    return Sqflite.firstIntValue(lignes) ?? 0;
  }

  /// Nombre total de chapitres en base (utilisé pour compter les insertions).
  Future<int> _compterTout(DatabaseExecutor executeur) async {
    final lignes = await executeur.rawQuery('SELECT COUNT(*) FROM chapitres');
    return Sqflite.firstIntValue(lignes) ?? 0;
  }
}
