/// Dépôt des positions de lecture (migration 15).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/position_lecture.dart';

/// Accès à la table `positions_lecture` : une position par chapitre, pour
/// tout chapitre lisible dans l'application (archive `.zip`, CBZ, PDF,
/// EPUB).
class DepotPositionsLecture {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotPositionsLecture(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Position enregistrée du chapitre [idChapitre], ou `null`.
  Future<PositionLecture?> chargerPosition(int idChapitre) async {
    final lignes = await _baseDeDonnees.query(
      'positions_lecture',
      where: 'id_chapitre = ?',
      whereArgs: <Object?>[idChapitre],
      limit: 1,
    );
    return lignes.isEmpty ? null : PositionLecture.depuisMap(lignes.first);
  }

  /// Positions des chapitres du titre [idTitre], par identifiant de
  /// chapitre (affichage de la progression dans la fiche du titre).
  Future<Map<int, PositionLecture>> chargerPositionsDuTitre(int idTitre) async {
    final lignes = await _baseDeDonnees.rawQuery(
      'SELECT p.* FROM positions_lecture p '
      'JOIN chapitres c ON c.id = p.id_chapitre WHERE c.id_titre = ?',
      <Object?>[idTitre],
    );
    return <int, PositionLecture>{
      for (final position in lignes.map(PositionLecture.depuisMap))
        position.idChapitre: position,
    };
  }

  /// Enregistre [position] (remplace la précédente du même chapitre).
  ///
  /// Lève une [ErreurBaseDeDonnees] si le chapitre n'existe pas ou si
  /// l'écriture échoue.
  Future<void> enregistrerPosition(PositionLecture position) async {
    try {
      // INSERT OR REPLACE sur id_chapitre UNIQUE : une seule ligne par
      // chapitre, écrite en une instruction.
      await _baseDeDonnees.insert(
        'positions_lecture',
        position.versMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer la position de lecture du chapitre '
        'n°${position.idChapitre}.',
        cause: erreur,
      );
    }
  }

  /// Efface la position du chapitre [idChapitre] (chapitre relu depuis le
  /// début) ; renvoie `true` si une position existait.
  Future<bool> effacerPosition(int idChapitre) async {
    final supprimees = await _baseDeDonnees.delete(
      'positions_lecture',
      where: 'id_chapitre = ?',
      whereArgs: <Object?>[idChapitre],
    );
    return supprimees > 0;
  }
}
