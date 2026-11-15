/// Dépôt des listes de lecture (Favoris, Suivis et listes du client).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/liste_lecture.dart';

/// Accès aux tables `listes` et `titres_listes`.
///
/// Les listes système (`est_systeme = 1`) ne peuvent être ni renommées ni
/// supprimées : le dépôt lève une [ErreurBaseDeDonnees].
class DepotListes {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotListes(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Charge toutes les listes, dans l'ordre d'affichage.
  Future<List<ListeLecture>> chargerListes() async {
    final lignes = await _baseDeDonnees.query(
      'listes',
      orderBy: 'ordre, nom COLLATE NOCASE',
    );
    return lignes.map(ListeLecture.depuisMap).toList();
  }

  /// Charge une liste par son identifiant, ou `null`.
  Future<ListeLecture?> chargerListe(int id) {
    return _chargerListeAvec(_baseDeDonnees, id);
  }

  /// Charge une liste par son nom (sans tenir compte de la casse ASCII), ou
  /// `null`. Pratique pour retrouver « Favoris » ou « Suivis ».
  Future<ListeLecture?> chargerListeParNom(String nom) async {
    final lignes = await _baseDeDonnees.query(
      'listes',
      where: 'nom = ? COLLATE NOCASE',
      whereArgs: <Object?>[nom.trim()],
      limit: 1,
    );
    return lignes.isEmpty ? null : ListeLecture.depuisMap(lignes.first);
  }

  /// Charge les listes qui contiennent un titre.
  Future<List<ListeLecture>> chargerListesDuTitre(int idTitre) async {
    final lignes = await _baseDeDonnees.rawQuery(
      'SELECT l.* FROM listes l '
      'JOIN titres_listes tl ON tl.id_liste = l.id '
      'WHERE tl.id_titre = ? ORDER BY l.ordre, l.nom COLLATE NOCASE',
      <Object?>[idTitre],
    );
    return lignes.map(ListeLecture.depuisMap).toList();
  }

  /// Crée une liste du client, placée après les listes existantes.
  ///
  /// Lève une [ErreurBaseDeDonnees] si le nom est vide ou déjà utilisé.
  Future<ListeLecture> creerListe(String nom) async {
    final nomPropre = _verifierNom(nom);
    try {
      return await _baseDeDonnees.transaction((txn) async {
        // Calcul de l'ordre et insertion dans la même transaction pour que
        // deux créations rapprochées n'obtiennent pas la même position.
        final lignes = await txn.rawQuery(
          'SELECT COALESCE(MAX(ordre), ?) + 1 FROM listes',
          <Object?>[ordreListeSuivis],
        );
        final ordre = Sqflite.firstIntValue(lignes) ?? ordreListeSuivis + 1;
        final liste = ListeLecture(nom: nomPropre, ordre: ordre);
        final id = await txn.insert('listes', liste.versMap());
        return liste.copierAvec(id: id);
      });
    } on DatabaseException catch (erreur) {
      if (erreur.isUniqueConstraintError()) {
        throw ErreurBaseDeDonnees(
          'Une liste nommée « $nomPropre » existe déjà.',
          cause: erreur,
        );
      }
      rethrow;
    }
  }

  /// Renomme une liste du client.
  ///
  /// Lève une [ErreurBaseDeDonnees] si la liste n'existe pas, si c'est une
  /// liste système, si le nom est vide ou déjà utilisé.
  Future<ListeLecture> renommerListe(int id, String nouveauNom) async {
    final nomPropre = _verifierNom(nouveauNom);
    try {
      return await _baseDeDonnees.transaction((txn) async {
        final liste = await _chargerListeModifiable(txn, id, 'renommer');
        await txn.update(
          'listes',
          <String, Object?>{'nom': nomPropre},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        return liste.copierAvec(nom: nomPropre);
      });
    } on DatabaseException catch (erreur) {
      if (erreur.isUniqueConstraintError()) {
        throw ErreurBaseDeDonnees(
          'Une liste nommée « $nomPropre » existe déjà.',
          cause: erreur,
        );
      }
      rethrow;
    }
  }

  /// Supprime une liste du client. Les titres ne sont pas supprimés : seule
  /// leur appartenance à la liste disparaît (`ON DELETE CASCADE` sur
  /// `titres_listes`).
  ///
  /// Lève une [ErreurBaseDeDonnees] si la liste n'existe pas ou si c'est une
  /// liste système.
  Future<void> supprimerListe(int id) async {
    await _baseDeDonnees.transaction((txn) async {
      await _chargerListeModifiable(txn, id, 'supprimer');
      await txn.delete('listes', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }

  /// Ajoute un titre à une liste. Sans effet s'il y est déjà.
  ///
  /// Lève une [ErreurBaseDeDonnees] si la liste ou le titre n'existe pas.
  Future<void> ajouterTitre(int idListe, int idTitre) async {
    try {
      await _baseDeDonnees.transaction((txn) async {
        // Vérification explicite : sqflite ne permet pas de reconnaître
        // proprement une erreur de clé étrangère, et ce message est plus clair.
        if (await _chargerListeAvec(txn, idListe) == null) {
          throw ErreurBaseDeDonnees('La liste n°$idListe n\'existe pas.');
        }
        final titres = await txn.query(
          'titres',
          columns: <String>['id'],
          where: 'id = ?',
          whereArgs: <Object?>[idTitre],
          limit: 1,
        );
        if (titres.isEmpty) {
          throw ErreurBaseDeDonnees('Le titre n°$idTitre n\'existe pas.');
        }
        // IGNORE : la clé primaire (id_titre, id_liste) rend l'ajout
        // idempotent.
        await txn.insert('titres_listes', <String, Object?>{
          'id_titre': idTitre,
          'id_liste': idListe,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'ajouter le titre n°$idTitre à la liste n°$idListe.',
        cause: erreur,
      );
    }
  }

  /// Retire un titre d'une liste. Sans effet s'il n'y était pas.
  Future<void> retirerTitre(int idListe, int idTitre) async {
    await _baseDeDonnees.delete(
      'titres_listes',
      where: 'id_titre = ? AND id_liste = ?',
      whereArgs: <Object?>[idTitre, idListe],
    );
  }

  /// Vérifie et nettoie un nom de liste.
  String _verifierNom(String nom) {
    final nomPropre = nom.trim();
    if (nomPropre.isEmpty) {
      throw const ErreurBaseDeDonnees(
        'Le nom d\'une liste ne peut pas être vide.',
      );
    }
    return nomPropre;
  }

  /// Charge une liste et vérifie qu'elle peut être modifiée par le client.
  Future<ListeLecture> _chargerListeModifiable(
    DatabaseExecutor executeur,
    int id,
    String action,
  ) async {
    final liste = await _chargerListeAvec(executeur, id);
    if (liste == null) {
      throw ErreurBaseDeDonnees('La liste n°$id n\'existe pas.');
    }
    if (liste.estSysteme) {
      throw ErreurBaseDeDonnees(
        'Impossible de $action la liste système « ${liste.nom} ».',
      );
    }
    return liste;
  }

  Future<ListeLecture?> _chargerListeAvec(
    DatabaseExecutor executeur,
    int id,
  ) async {
    final lignes = await executeur.query(
      'listes',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return lignes.isEmpty ? null : ListeLecture.depuisMap(lignes.first);
  }
}
