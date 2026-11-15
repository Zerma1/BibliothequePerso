/// Dépôt des catégories (genres et tags repris des sites).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/categorie.dart';
import '../modeles/erreur_base_de_donnees.dart';

/// Accès à la table `categories` et à la relation `titres_categories`.
class DepotCategories {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotCategories(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Enregistre une catégorie à partir d'un nom brut venant d'un site.
  ///
  /// Le nom est normalisé (minuscules, trim). Si une catégorie de même nom
  /// existe déjà, elle est réutilisée. Lève une [ErreurBaseDeDonnees] si le nom
  /// est vide après normalisation.
  Future<Categorie> enregistrerCategorie(String nomBrut) {
    return enregistrerCategorieAvec(_baseDeDonnees, nomBrut);
  }

  /// Variante de [enregistrerCategorie] utilisable dans une transaction
  /// ouverte par un autre dépôt (par exemple `DepotTitres`).
  static Future<Categorie> enregistrerCategorieAvec(
    DatabaseExecutor executeur,
    String nomBrut,
  ) async {
    final nom = Categorie.normaliserNom(nomBrut);
    if (nom.isEmpty) {
      throw const ErreurBaseDeDonnees(
        'Le nom d\'une catégorie ne peut pas être vide.',
      );
    }
    // INSERT OR IGNORE puis SELECT : la contrainte UNIQUE sur `nom` garantit
    // qu'il n'existe jamais deux lignes pour le même genre, même si deux
    // enregistrements se suivent de près.
    await executeur.insert('categories', <String, Object?>{
      'nom': nom,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final lignes = await executeur.query(
      'categories',
      where: 'nom = ?',
      whereArgs: <Object?>[nom],
      limit: 1,
    );
    if (lignes.isEmpty) {
      throw ErreurBaseDeDonnees(
        'La catégorie « $nom » n\'a pas pu être enregistrée.',
      );
    }
    return Categorie.depuisMap(lignes.first);
  }

  /// Charge toutes les catégories, triées par nom.
  Future<List<Categorie>> chargerCategories() async {
    final lignes = await _baseDeDonnees.query('categories', orderBy: 'nom');
    return lignes.map(Categorie.depuisMap).toList();
  }

  /// Charge les catégories d'un titre, triées par nom.
  Future<List<Categorie>> chargerCategoriesDuTitre(int idTitre) async {
    final lignes = await _baseDeDonnees.rawQuery(
      'SELECT c.id, c.nom FROM categories c '
      'JOIN titres_categories tc ON tc.id_categorie = c.id '
      'WHERE tc.id_titre = ? ORDER BY c.nom',
      <Object?>[idTitre],
    );
    return lignes.map(Categorie.depuisMap).toList();
  }

  /// Supprime les catégories qui ne sont plus utilisées par aucun titre et
  /// renvoie le nombre de lignes supprimées.
  Future<int> supprimerCategoriesInutilisees() {
    return _baseDeDonnees.delete(
      'categories',
      where: 'id NOT IN (SELECT id_categorie FROM titres_categories)',
    );
  }
}
