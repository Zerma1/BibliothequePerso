/// Dépôt des équivalences de catégories : regroupement des catégories de
/// même sens (« survival » / « survie », « comedy » / « comédie »).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/categorie.dart';
import '../modeles/equivalence_categorie.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/groupe_categories.dart';
import 'gestionnaire_transactions.dart';

/// Accès à la table `categories_equivalences` (migration 9).
///
/// Une catégorie peut être **rattachée** à une catégorie de **référence** :
/// elles forment alors un groupe, que les filtres de la bibliothèque
/// traitent comme une seule catégorie (voir `DepotTitres.chargerTitres`).
/// La **catégorie effective** d'une catégorie est sa référence si elle est
/// rattachée, elle-même sinon.
///
/// Un seul niveau : une référence n'est jamais rattachée, et une catégorie
/// rattachée n'est la référence d'aucune autre (pas de chaîne, pas de
/// cycle). Le dépôt le vérifie avant d'écrire, et deux déclencheurs SQL le
/// garantissent quel que soit le chemin d'écriture.
///
/// Les catégories enregistrées par les sites ne sont jamais modifiées : le
/// regroupement n'agit qu'à la lecture.
class DepotEquivalencesCategories {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotEquivalencesCategories(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Expression SQL de l'identifiant **effectif** de la catégorie
  /// `tc.id_categorie`, pour une requête qui joint `titres_categories tc` à
  /// `categories_equivalences ce` par [jointureEquivalences].
  ///
  /// Fragment constant, sans valeur extérieure.
  static const String sqlIdEffectif =
      'COALESCE(ce.id_reference, '
      'tc.id_categorie)';

  /// Jointure de `titres_categories tc` vers son rattachement éventuel
  /// (servie par l'index UNIQUE de `id_categorie`).
  static const String jointureEquivalences =
      'LEFT JOIN categories_equivalences ce '
      'ON ce.id_categorie = tc.id_categorie';

  /// Expression SQL de l'identifiant effectif de la catégorie passée en
  /// paramètre. Elle contient **deux** marqueurs `?`, qui reçoivent tous
  /// deux l'identifiant de la catégorie.
  static const String sqlIdEffectifParametre =
      'COALESCE((SELECT ce2.id_reference FROM categories_equivalences ce2 '
      'WHERE ce2.id_categorie = ?), ?)';

  /// Rattache [idCategorie] à la catégorie de référence [idReference] et
  /// renvoie le rattachement enregistré.
  ///
  /// Si [idCategorie] était déjà rattachée à une autre référence, elle
  /// change de groupe ; si elle l'était déjà à [idReference], rien ne
  /// change.
  ///
  /// Lève une [ErreurBaseDeDonnees] si :
  /// - les deux identifiants sont égaux ;
  /// - l'une des deux catégories n'existe pas ;
  /// - [idReference] est elle-même rattachée à une autre catégorie (il faut
  ///   choisir sa référence à la place) ;
  /// - [idCategorie] est la référence d'autres catégories (il faut d'abord
  ///   les détacher ou dissoudre son groupe).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  /// Sans exécuteur, la vérification et l'écriture se font dans une
  /// transaction propre à cet appel.
  Future<EquivalenceCategorie> rattacherCategorie(
    int idCategorie,
    int idReference, {
    DatabaseExecutor? executeur,
  }) async {
    if (idCategorie == idReference) {
      throw const ErreurBaseDeDonnees(
        'Une catégorie ne peut pas être sa propre référence.',
      );
    }
    final equivalence = EquivalenceCategorie(
      idCategorie: idCategorie,
      idReference: idReference,
    );
    try {
      await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        (txn) async {
          final noms = await _chargerNoms(txn, <int>[idCategorie, idReference]);
          for (final id in <int>[idCategorie, idReference]) {
            if (!noms.containsKey(id)) {
              throw ErreurBaseDeDonnees('La catégorie n°$id n\'existe pas.');
            }
          }
          final nomCategorie = noms[idCategorie];
          final nomReference = noms[idReference];

          final referenceDeLaReference = await _chargerIdReference(
            txn,
            idReference,
          );
          if (referenceDeLaReference != null) {
            throw ErreurBaseDeDonnees(
              '« $nomReference » est déjà rattachée à une autre catégorie : '
              'choisissez sa catégorie de référence à la place.',
            );
          }
          final rattachees = await txn.query(
            'categories_equivalences',
            columns: <String>['id_categorie'],
            where: 'id_reference = ?',
            whereArgs: <Object?>[idCategorie],
            limit: 1,
          );
          if (rattachees.isNotEmpty) {
            throw ErreurBaseDeDonnees(
              '« $nomCategorie » est la référence d\'autres catégories : '
              'détachez-les d\'abord.',
            );
          }

          final actuelle = await _chargerIdReference(txn, idCategorie);
          if (actuelle == idReference) {
            return;
          }
          if (actuelle == null) {
            await txn.insert('categories_equivalences', equivalence.versMap());
          } else {
            await txn.update(
              'categories_equivalences',
              <String, Object?>{'id_reference': idReference},
              where: 'id_categorie = ?',
              whereArgs: <Object?>[idCategorie],
            );
          }
        },
      );
    } on DatabaseException catch (erreur) {
      // Cas limite (écriture concurrente entre la vérification et
      // l'écriture) : refus par un déclencheur ou une clé étrangère.
      throw ErreurBaseDeDonnees(
        'Impossible de rattacher la catégorie n°$idCategorie à la catégorie '
        'n°$idReference.',
        cause: erreur,
      );
    }
    return equivalence;
  }

  /// Détache [idCategorie] de sa référence : elle redevient une catégorie
  /// indépendante. Renvoie `false` si elle n'était rattachée à rien.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<bool> detacherCategorie(
    int idCategorie, {
    DatabaseExecutor? executeur,
  }) async {
    final supprimees = await (executeur ?? _baseDeDonnees).delete(
      'categories_equivalences',
      where: 'id_categorie = ?',
      whereArgs: <Object?>[idCategorie],
    );
    return supprimees > 0;
  }

  /// Dissout le groupe de la référence [idReference] : toutes les
  /// catégories qui lui sont rattachées redeviennent indépendantes.
  /// Renvoie le nombre de catégories détachées.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<int> dissoudreGroupe(int idReference, {DatabaseExecutor? executeur}) {
    return (executeur ?? _baseDeDonnees).delete(
      'categories_equivalences',
      where: 'id_reference = ?',
      whereArgs: <Object?>[idReference],
    );
  }

  /// Charge tous les rattachements, triés par catégorie (pour un export,
  /// par exemple).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<EquivalenceCategorie>> chargerEquivalences({
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      'categories_equivalences',
      orderBy: 'id_categorie',
    );
    return lignes.map(EquivalenceCategorie.depuisMap).toList();
  }

  /// Charge les groupes (références qui ont au moins une catégorie
  /// rattachée), triés par nom de référence ; dans chaque groupe, les
  /// catégories rattachées sont triées par nom.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<GroupeCategories>> chargerGroupes({
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).rawQuery(
      'SELECT r.id AS id_reference, r.nom AS nom_reference, '
      'c.id AS id_categorie, c.nom AS nom_categorie '
      'FROM categories_equivalences ce '
      'JOIN categories r ON r.id = ce.id_reference '
      'JOIN categories c ON c.id = ce.id_categorie '
      'ORDER BY r.nom, r.id, c.nom, c.id',
    );
    final references = <int, Categorie>{};
    final rattachees = <int, List<Categorie>>{};
    for (final ligne in lignes) {
      final reference = Categorie.depuisMap(<String, Object?>{
        'id': ligne['id_reference'],
        'nom': ligne['nom_reference'],
      });
      final categorie = Categorie.depuisMap(<String, Object?>{
        'id': ligne['id_categorie'],
        'nom': ligne['nom_categorie'],
      });
      final idReference = reference.id!;
      references[idReference] = reference;
      (rattachees[idReference] ??= <Categorie>[]).add(categorie);
    }
    // Map littérale : l'ordre d'insertion (celui de la requête) est gardé.
    return <GroupeCategories>[
      for (final MapEntry(key: id, value: reference) in references.entries)
        GroupeCategories(reference: reference, rattachees: rattachees[id]!),
    ];
  }

  /// Charge la catégorie effective de [idCategorie] : sa référence si elle
  /// est rattachée, elle-même sinon ; `null` si elle n'existe pas.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<Categorie?> chargerCategorieEffective(
    int idCategorie, {
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).rawQuery(
      'SELECT c.id, c.nom FROM categories c '
      'WHERE c.id = $sqlIdEffectifParametre',
      <Object?>[idCategorie, idCategorie],
    );
    if (lignes.isEmpty) {
      return null;
    }
    return Categorie.depuisMap(lignes.first);
  }

  /// Charge les catégories à proposer dans les filtres : toutes les
  /// catégories qui ne sont rattachées à aucune autre (références de
  /// groupes et catégories indépendantes), triées par nom.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<Categorie>> chargerCategoriesEffectives({
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).rawQuery(
      'SELECT c.id, c.nom FROM categories c '
      'WHERE NOT EXISTS (SELECT 1 FROM categories_equivalences ce '
      'WHERE ce.id_categorie = c.id) '
      'ORDER BY c.nom',
    );
    return lignes.map(Categorie.depuisMap).toList();
  }

  /// Charge les catégories effectives d'un titre : ses catégories ramenées
  /// à leur référence, sans doublon, triées par nom. Un titre classé
  /// « survival » et « survie » n'affiche donc que « survie ».
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<Categorie>> chargerCategoriesEffectivesDuTitre(
    int idTitre, {
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).rawQuery(
      'SELECT DISTINCT c.id, c.nom FROM titres_categories tc '
      '$jointureEquivalences '
      'JOIN categories c ON c.id = $sqlIdEffectif '
      'WHERE tc.id_titre = ? ORDER BY c.nom',
      <Object?>[idTitre],
    );
    return lignes.map(Categorie.depuisMap).toList();
  }

  /// Identifiant de la référence de [idCategorie], `null` si elle n'est
  /// rattachée à rien.
  static Future<int?> _chargerIdReference(
    DatabaseExecutor executeur,
    int idCategorie,
  ) async {
    final lignes = await executeur.query(
      'categories_equivalences',
      columns: <String>['id_reference'],
      where: 'id_categorie = ?',
      whereArgs: <Object?>[idCategorie],
      limit: 1,
    );
    if (lignes.isEmpty) {
      return null;
    }
    return EquivalenceCategorie.depuisMap(<String, Object?>{
      'id_categorie': idCategorie,
      ...lignes.first,
    }).idReference;
  }

  /// Noms des catégories existantes parmi [ids], par identifiant.
  static Future<Map<int, String>> _chargerNoms(
    DatabaseExecutor executeur,
    List<int> ids,
  ) async {
    final marqueurs = List<String>.filled(ids.length, '?').join(', ');
    final lignes = await executeur.rawQuery(
      'SELECT id, nom FROM categories WHERE id IN ($marqueurs)',
      ids,
    );
    return <int, String>{
      for (final categorie in lignes.map(Categorie.depuisMap))
        categorie.id!: categorie.nom,
    };
  }
}
