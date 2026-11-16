/// Dépôt des chapitres et de l'état de lecture.
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/outils_modeles.dart';

/// Enregistre le chemin relatif de l'archive d'un chapitre dans [executeur]
/// (une transaction) ; partagé par `DepotChapitres.enregistrerArchive` et
/// `DepotTelechargements.enregistrerStatut` (statut terminé).
///
/// - [nomArchive] non nul : `nom_archive` = [nomArchive] et
///   `est_telecharge` = 1. Si un **autre** chapitre portait déjà ce chemin,
///   il est remis à « non téléchargé » (chemin, suppression prévue effacés) :
///   `StockageTelechargements` ne donne un nom que s'il est libre sur le
///   disque, donc l'archive de cet autre chapitre n'existait plus (base
///   restée incohérente). Sans cela, l'index UNIQUE de la migration 4
///   ferait échouer l'enregistrement d'un téléchargement réussi.
/// - [nomArchive] nul : `nom_archive` et `date_suppression_prevue` à NULL,
///   `est_telecharge` = 0.
///
/// Renvoie `false` si le chapitre n'existe pas. Lève une [ArgumentError] si
/// [nomArchive] est vide.
Future<bool> enregistrerArchiveChapitre(
  DatabaseExecutor executeur,
  int idChapitre,
  String? nomArchive,
) async {
  if (nomArchive != null && nomArchive.trim().isEmpty) {
    throw ArgumentError.value(
      nomArchive,
      'nomArchive',
      'ne doit pas être vide',
    );
  }
  if (nomArchive != null) {
    await executeur.update(
      'chapitres',
      <String, Object?>{
        'nom_archive': null,
        'date_suppression_prevue': null,
        'est_telecharge': valeurSqlFaux,
      },
      where: 'nom_archive = ? AND id != ?',
      whereArgs: <Object?>[nomArchive, idChapitre],
    );
  }
  final modifiees = await executeur.update(
    'chapitres',
    <String, Object?>{
      'nom_archive': nomArchive,
      'est_telecharge': nomArchive == null ? valeurSqlFaux : valeurSqlVrai,
      if (nomArchive == null) 'date_suppression_prevue': null,
    },
    where: 'id = ?',
    whereArgs: <Object?>[idChapitre],
  );
  return modifiees > 0;
}

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

  /// Charge les chapitres marqués téléchargés (`est_telecharge = 1`), triés
  /// par titre puis par numéro ; si [idTitre] est donné, seulement ceux de
  /// ce titre.
  ///
  /// Sert au contrôle de cohérence au démarrage : le service vérifie que
  /// l'archive de chacun existe sur le disque et, sinon, le remet à « non
  /// téléchargé » avec [marquerTelecharge]. Chaque [Chapitre] porte son
  /// `idTitre`, de quoi charger le titre et calculer le chemin.
  ///
  /// Pas d'index sur `est_telecharge` : la requête ne sert qu'au démarrage,
  /// et un index sur une colonne à deux valeurs aiderait peu tout en
  /// ralentissant chaque écriture de chapitre (et exigerait une migration).
  Future<List<Chapitre>> chargerChapitresTelecharges({int? idTitre}) async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      where: idTitre == null
          ? 'est_telecharge = ?'
          : 'est_telecharge = ? AND id_titre = ?',
      whereArgs: <Object?>[valeurSqlVrai, ?idTitre],
      orderBy: 'id_titre, numero, id',
    );
    return lignes.map(Chapitre.depuisMap).toList();
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
  ///
  /// Avec `estTelecharge: false`, le chemin enregistré (`nom_archive`) et la
  /// suppression prévue sont aussi effacés : un chapitre non téléchargé n'a
  /// ni archive ni suppression à faire. Pour enregistrer le chemin d'une
  /// nouvelle archive, utiliser plutôt [enregistrerArchive].
  Future<void> marquerTelecharge(
    int idChapitre, {
    bool estTelecharge = true,
  }) async {
    if (!estTelecharge) {
      await enregistrerArchive(idChapitre, null);
      return;
    }
    await _baseDeDonnees.update(
      'chapitres',
      <String, Object?>{'est_telecharge': valeurSqlVrai},
      where: 'id = ?',
      whereArgs: <Object?>[idChapitre],
    );
  }

  /// Enregistre le chemin relatif de l'archive hors-ligne d'un chapitre
  /// (`EcritureChapitre.nomArchive`) et met `est_telecharge` en cohérence.
  ///
  /// - [nomArchive] non nul : `nom_archive` = [nomArchive] et
  ///   `est_telecharge` = 1.
  /// - [nomArchive] nul (« plus téléchargé ») : `nom_archive`,
  ///   `date_suppression_prevue` à NULL et `est_telecharge` = 0.
  ///
  /// Voir [enregistrerArchiveChapitre] pour le cas d'un chemin déjà attribué
  /// à un autre chapitre. Renvoie `false` si le chapitre n'existe pas. Lève
  /// une [ArgumentError] si [nomArchive] est vide.
  Future<bool> enregistrerArchive(int idChapitre, String? nomArchive) async {
    try {
      return await _baseDeDonnees.transaction(
        (txn) => enregistrerArchiveChapitre(txn, idChapitre, nomArchive),
      );
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible d'enregistrer l'archive du chapitre n°$idChapitre.",
        cause: erreur,
      );
    }
  }

  /// Planifie la suppression automatique de l'archive d'un chapitre à
  /// [date], ou l'annule si [date] est `null`.
  ///
  /// Renvoie `false` si le chapitre n'existe pas.
  Future<bool> planifierSuppression(int idChapitre, DateTime? date) async {
    final modifiees = await _baseDeDonnees.update(
      'chapitres',
      <String, Object?>{'date_suppression_prevue': dateVersMillisecondes(date)},
      where: 'id = ?',
      whereArgs: <Object?>[idChapitre],
    );
    return modifiees > 0;
  }

  /// Charge les chapitres dont la suppression prévue est échue
  /// (`date_suppression_prevue <= maintenant`), la plus ancienne d'abord.
  ///
  /// Le service supprime leur archive puis appelle
  /// [enregistrerArchive]`(id, null)`, qui efface aussi la date. La
  /// recherche utilise l'index partiel `index_chapitres_suppression_prevue`
  /// (migration 4).
  Future<List<Chapitre>> chargerSuppressionsEchues(DateTime maintenant) async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      where: 'date_suppression_prevue <= ?',
      whereArgs: <Object?>[dateVersMillisecondes(maintenant)],
      orderBy: 'date_suppression_prevue, id',
    );
    return lignes.map(Chapitre.depuisMap).toList();
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
