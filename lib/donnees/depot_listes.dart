/// Dépôt des listes de lecture (Favoris, Suivis, Planifié, En attente et
/// listes du client).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/liste_lecture.dart';
import 'gestionnaire_transactions.dart';

/// Accès aux tables `listes` et `titres_listes`.
///
/// Les listes système (`est_systeme = 1`) ne peuvent être ni renommées ni
/// supprimées : le dépôt lève une [ErreurBaseDeDonnees].
class DepotListes {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotListes(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Charge toutes les listes, dans l'ordre d'affichage.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<ListeLecture>> chargerListes({
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
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
  /// `null`. Pratique pour retrouver une liste système (« Favoris »,
  /// « Suivis », « Planifié », « En attente »).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<ListeLecture?> chargerListeParNom(
    String nom, {
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      'listes',
      where: 'nom = ? COLLATE NOCASE',
      whereArgs: <Object?>[nom.trim()],
      limit: 1,
    );
    return lignes.isEmpty ? null : ListeLecture.depuisMap(lignes.first);
  }

  /// Charge les listes qui contiennent un titre.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<ListeLecture>> chargerListesDuTitre(
    int idTitre, {
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).rawQuery(
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
  ///
  /// [executeur] : transaction ouverte par `GestionnaireTransactions` pour
  /// écrire avec d'autres dépôts ; `null` : transaction propre à cet appel.
  Future<ListeLecture> creerListe(
    String nom, {
    DatabaseExecutor? executeur,
  }) async {
    final nomPropre = _verifierNom(nom);
    try {
      return await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        (txn) async {
          // Calcul de l'ordre et insertion dans la même transaction pour que
          // deux créations rapprochées n'obtiennent pas la même position.
          final lignes = await txn.rawQuery(
            'SELECT COALESCE(MAX(ordre), ?) + 1 FROM listes',
            <Object?>[ordreListeEnAttente],
          );
          final ordre =
              Sqflite.firstIntValue(lignes) ?? ordreListeEnAttente + 1;
          final liste = ListeLecture(nom: nomPropre, ordre: ordre);
          final id = await txn.insert('listes', liste.versMap());
          return liste.copierAvec(id: id);
        },
      );
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

  /// Renomme une liste du client (dont « En attente (perso) », liste
  /// ordinaire créée par la migration 5).
  ///
  /// Lève une [ErreurBaseDeDonnees] si la liste n'existe pas, si c'est une
  /// liste système (Favoris, Suivis, Planifié, En attente), si le nom est
  /// vide ou déjà utilisé (sans tenir compte de la casse ASCII). Changer
  /// seulement la casse du nom d'une liste est accepté.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`) ;
  /// `null` : transaction propre à cet appel.
  Future<ListeLecture> renommerListe(
    int id,
    String nouveauNom, {
    DatabaseExecutor? executeur,
  }) async {
    final nomPropre = _verifierNom(nouveauNom);
    try {
      return await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        (txn) async {
          final liste = await _chargerListeModifiable(
            txn,
            id,
            _Action.renommer,
          );
          await txn.update(
            'listes',
            <String, Object?>{'nom': nomPropre},
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
          return liste.copierAvec(nom: nomPropre);
        },
      );
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
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`) ;
  /// `null` : transaction propre à cet appel.
  Future<void> supprimerListe(int id, {DatabaseExecutor? executeur}) async {
    await GestionnaireTransactions.executerAtomiquement(
      _baseDeDonnees,
      executeur,
      (txn) async {
        await _chargerListeModifiable(txn, id, _Action.supprimer);
        await txn.delete('listes', where: 'id = ?', whereArgs: <Object?>[id]);
      },
    );
  }

  /// Enregistre l'ordre d'affichage des listes : [idsDansLOrdre] reçoivent
  /// les positions 0, 1, 2… dans cet ordre. Les listes système peuvent être
  /// déplacées comme les autres (l'ordre n'est qu'un choix d'affichage).
  ///
  /// Une liste absente de [idsDansLOrdre] est placée après celles données,
  /// en gardant son ordre actuel : un appel avec une liste partielle (ou
  /// faite avant la création d'une liste) ne perd rien.
  ///
  /// Renvoie toutes les listes dans le nouvel ordre. Lève une
  /// [ErreurBaseDeDonnees], sans rien écrire, si un identifiant est répété
  /// ou ne correspond à aucune liste.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`) ;
  /// `null` : transaction propre à cet appel.
  Future<List<ListeLecture>> enregistrerOrdre(
    List<int> idsDansLOrdre, {
    DatabaseExecutor? executeur,
  }) async {
    if (idsDansLOrdre.toSet().length != idsDansLOrdre.length) {
      throw const ErreurBaseDeDonnees(
        'Ordre des listes invalide : une liste y apparaît plusieurs fois.',
      );
    }
    return GestionnaireTransactions.executerAtomiquement(
      _baseDeDonnees,
      executeur,
      (txn) async {
        final actuelles = await chargerListes(executeur: txn);
        final parId = <int, ListeLecture>{
          for (final liste in actuelles)
            if (liste.id case final int id) id: liste,
        };
        for (final id in idsDansLOrdre) {
          if (!parId.containsKey(id)) {
            throw ErreurBaseDeDonnees('La liste n°$id n\'existe pas.');
          }
        }
        final demandes = idsDansLOrdre.toSet();
        final ordonnees = <ListeLecture>[
          for (final id in idsDansLOrdre) parId[id]!,
          for (final liste in actuelles)
            if (!demandes.contains(liste.id)) liste,
        ];
        final resultat = <ListeLecture>[];
        for (var position = 0; position < ordonnees.length; position++) {
          final liste = ordonnees[position];
          if (liste.ordre != position) {
            await txn.update(
              'listes',
              <String, Object?>{'ordre': position},
              where: 'id = ?',
              whereArgs: <Object?>[liste.id],
            );
          }
          resultat.add(liste.copierAvec(ordre: position));
        }
        return resultat;
      },
    );
  }

  /// Ajoute un titre à une liste. Sans effet s'il y est déjà.
  ///
  /// Lève une [ErreurBaseDeDonnees] si la liste ou le titre n'existe pas.
  ///
  /// [executeur] : transaction ouverte par `GestionnaireTransactions` pour
  /// écrire avec d'autres dépôts ; `null` : transaction propre à cet appel.
  Future<void> ajouterTitre(
    int idListe,
    int idTitre, {
    DatabaseExecutor? executeur,
  }) async {
    try {
      await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        (txn) async {
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
        },
      );
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
    _Action action,
  ) async {
    final liste = await _chargerListeAvec(executeur, id);
    if (liste == null) {
      throw ErreurBaseDeDonnees('La liste n°$id n\'existe pas.');
    }
    if (liste.estSysteme) {
      final participe = switch (action) {
        _Action.renommer => 'renommée',
        _Action.supprimer => 'supprimée',
      };
      throw ErreurBaseDeDonnees(
        '« ${liste.nom} » est une liste système : elle ne peut pas être '
        '$participe.',
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

/// Action refusée sur une liste système (pour le message d'erreur).
enum _Action { renommer, supprimer }
