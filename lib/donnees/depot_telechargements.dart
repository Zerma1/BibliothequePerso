/// Dépôt de la file de téléchargement hors-ligne (table `telechargements`).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/outils_modeles.dart';
import '../modeles/telechargement.dart';
import 'depot_chapitres.dart' show enregistrerArchiveChapitre;

/// Fonction qui renvoie l'heure courante ; injectable pour les tests.
typedef Horloge = DateTime Function();

DateTime _maintenantUtc() => DateTime.now().toUtc();

/// Accès à la table `telechargements` : file persistante, reprise après
/// interruption et progression.
///
/// Le dépôt n'écrit aucun fichier : les archives sont gérées par
/// `StockageTelechargements`, et c'est le service qui coordonne les deux.
class DepotTelechargements {
  /// Crée le dépôt sur une base déjà ouverte. [horloge] fournit les dates
  /// `date_ajout` et `date_maj` (par défaut : maintenant, en UTC).
  const DepotTelechargements(
    this._baseDeDonnees, {
    this._horloge = _maintenantUtc,
  });

  final Database _baseDeDonnees;
  final Horloge _horloge;

  static const String _table = 'telechargements';

  // Ordre de la file : le plus ancien d'abord, puis l'ordre d'insertion
  // (deux ajouts dans la même milliseconde gardent leur ordre).
  static const String _ordreFile = 'date_ajout, id';

  int _maintenant() => dateVersMillisecondes(_horloge())!;

  /// Ajoute un chapitre en fin de file (statut « en attente ») et renvoie son
  /// téléchargement.
  ///
  /// Sans doublon : si le chapitre est déjà dans la file, la ligne existante
  /// est renvoyée **sans modification**, quel que soit son statut (pour
  /// relancer un échec, utiliser [enregistrerStatut]).
  ///
  /// Lève une [ErreurBaseDeDonnees] si le chapitre n'existe pas.
  Future<Telechargement> ajouterEnFile(int idChapitre) async {
    try {
      return await _baseDeDonnees.transaction((txn) async {
        await _verifierChapitre(txn, idChapitre);
        await _insererSiAbsent(txn, idChapitre, _maintenant());
        final lignes = await txn.query(
          _table,
          where: 'id_chapitre = ?',
          whereArgs: <Object?>[idChapitre],
          limit: 1,
        );
        return Telechargement.depuisMap(lignes.first);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'ajouter le chapitre n°$idChapitre à la file.',
        cause: erreur,
      );
    }
  }

  /// Ajoute plusieurs chapitres en fin de file, dans l'ordre donné, et
  /// renvoie le nombre de chapitres **nouvellement** ajoutés.
  ///
  /// Même règle sans doublon que [ajouterEnFile]. Tout ou rien : si un
  /// chapitre n'existe pas, une [ErreurBaseDeDonnees] est levée et rien n'est
  /// ajouté.
  Future<int> ajouterPlusieursEnFile(List<int> idsChapitres) async {
    if (idsChapitres.isEmpty) {
      return 0;
    }
    final date = _maintenant();
    try {
      return await _baseDeDonnees.transaction((txn) async {
        var ajoutes = 0;
        for (final idChapitre in idsChapitres) {
          await _verifierChapitre(txn, idChapitre);
          if (await _insererSiAbsent(txn, idChapitre, date)) {
            ajoutes++;
          }
        }
        return ajoutes;
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'ajouter les chapitres à la file.',
        cause: erreur,
      );
    }
  }

  /// Vérifie que le chapitre existe : message plus clair qu'une erreur de clé
  /// étrangère, que sqflite ne permet pas de reconnaître proprement.
  Future<void> _verifierChapitre(Transaction txn, int idChapitre) async {
    final lignes = await txn.query(
      'chapitres',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[idChapitre],
      limit: 1,
    );
    if (lignes.isEmpty) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'ajouter à la file : le chapitre n°$idChapitre '
        'n\'existe pas.',
      );
    }
  }

  /// Insère le chapitre s'il n'est pas déjà dans la file ; renvoie `true` s'il
  /// a été inséré.
  ///
  /// On lit d'abord plutôt que de se fier à la valeur renvoyée par `insert`
  /// avec IGNORE, qui varie selon l'implémentation (plugin Android ou FFI).
  Future<bool> _insererSiAbsent(
    Transaction txn,
    int idChapitre,
    int date,
  ) async {
    final existant = await txn.query(
      _table,
      columns: <String>['id'],
      where: 'id_chapitre = ?',
      whereArgs: <Object?>[idChapitre],
      limit: 1,
    );
    if (existant.isNotEmpty) {
      return false;
    }
    await txn.insert(_table, <String, Object?>{
      'id_chapitre': idChapitre,
      'statut': StatutTelechargement.enAttente.valeurSql,
      'nombre_pages_total': 0,
      'nombre_pages_faites': 0,
      'date_ajout': date,
      'date_maj': date,
    });
    return true;
  }

  /// Charge la file dans son ordre (plus ancien ajout d'abord).
  ///
  /// Si [statuts] est donné, seuls ces statuts sont renvoyés.
  Future<List<Telechargement>> chargerFile({
    Set<StatutTelechargement>? statuts,
  }) async {
    if (statuts != null && statuts.isEmpty) {
      return <Telechargement>[];
    }
    final valeurs = statuts?.map((s) => s.valeurSql).toList();
    final lignes = await _baseDeDonnees.query(
      _table,
      where: valeurs == null
          ? null
          : 'statut IN (${List<String>.filled(valeurs.length, '?').join(', ')})',
      whereArgs: valeurs,
      orderBy: _ordreFile,
    );
    return lignes.map(Telechargement.depuisMap).toList();
  }

  /// Charge un téléchargement par son identifiant, ou `null`.
  Future<Telechargement?> chargerTelechargement(int id) async {
    final lignes = await _baseDeDonnees.query(
      _table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return lignes.isEmpty ? null : Telechargement.depuisMap(lignes.first);
  }

  /// Charge le téléchargement d'un chapitre, ou `null` s'il n'est pas dans la
  /// file.
  Future<Telechargement?> chargerParChapitre(int idChapitre) async {
    final lignes = await _baseDeDonnees.query(
      _table,
      where: 'id_chapitre = ?',
      whereArgs: <Object?>[idChapitre],
      limit: 1,
    );
    return lignes.isEmpty ? null : Telechargement.depuisMap(lignes.first);
  }

  /// Charge le prochain téléchargement à lancer : le plus ancien « en
  /// attente », ou `null` si la file est vide.
  Future<Telechargement?> chargerProchainEnAttente() async {
    final lignes = await _baseDeDonnees.query(
      _table,
      where: 'statut = ?',
      whereArgs: <Object?>[StatutTelechargement.enAttente.valeurSql],
      orderBy: _ordreFile,
      limit: 1,
    );
    return lignes.isEmpty ? null : Telechargement.depuisMap(lignes.first);
  }

  /// Réserve le prochain téléchargement à lancer : prend le plus ancien « en
  /// attente », le passe « en cours » (avec `date_maj` à maintenant) et le
  /// renvoie ; `null` s'il n'y a plus rien en attente.
  ///
  /// Sûr entre plusieurs isolats ou connexions qui traitent la même file
  /// (sur Android : l'application et la tâche de fond). La réservation est un
  /// `UPDATE … WHERE id = ? AND statut = 'en_attente'` : SQLite l'exécute de
  /// façon atomique, donc un seul appelant obtient « 1 ligne modifiée » pour
  /// un même téléchargement. Si un autre appelant l'a pris entre la lecture
  /// et la mise à jour (0 ligne modifiée), on passe au suivant. La boucle se
  /// termine toujours : une ligne perdue n'est plus « en attente » et ne
  /// revient pas dans la lecture suivante.
  ///
  /// Pas de transaction : une transaction différée (`BEGIN`) entre deux
  /// connexions peut échouer en « base verrouillée » au moment d'écrire,
  /// alors que l'UPDATE conditionnel seul suffit à garantir l'exclusivité.
  /// `UPDATE … RETURNING` n'est pas utilisé : il exige SQLite 3.35, absent
  /// des anciennes versions d'Android.
  Future<Telechargement?> reserverProchain() async {
    try {
      while (true) {
        final candidat = await chargerProchainEnAttente();
        if (candidat == null) {
          return null;
        }
        final modifiees = await _baseDeDonnees.update(
          _table,
          <String, Object?>{
            'statut': StatutTelechargement.enCours.valeurSql,
            'message_erreur': null,
            'date_maj': _maintenant(),
          },
          where: 'id = ? AND statut = ?',
          whereArgs: <Object?>[
            candidat.id,
            StatutTelechargement.enAttente.valeurSql,
          ],
        );
        if (modifiees == 1) {
          // Relecture : renvoie l'état réellement enregistré (date_maj).
          return await chargerTelechargement(candidat.id!);
        }
      }
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible de réserver le prochain téléchargement.",
        cause: erreur,
      );
    }
  }

  /// Change le statut d'un téléchargement et met à jour `date_maj`.
  ///
  /// - [StatutTelechargement.echec] : [messageErreur] est enregistré.
  /// - autre statut : le message d'erreur est effacé.
  /// - [StatutTelechargement.enAttente] (relance) : la progression repart de
  ///   0, car une archive interrompue est réécrite depuis le début.
  /// - [StatutTelechargement.termine] : `chapitres.est_telecharge` passe aussi
  ///   à 1, dans la même transaction, pour que la base ne dise jamais
  ///   « terminé » sans que le chapitre soit marqué téléchargé. Si
  ///   [nomArchive] est donné (`EcritureChapitre.nomArchive`), il est
  ///   enregistré dans `chapitres.nom_archive` dans la même transaction
  ///   (voir `enregistrerArchiveChapitre`) ; il est ignoré pour les autres
  ///   statuts.
  ///
  /// Renvoie `false` si le téléchargement n'existe pas.
  Future<bool> enregistrerStatut(
    int id,
    StatutTelechargement statut, {
    String? messageErreur,
    String? nomArchive,
  }) async {
    final valeurs = <String, Object?>{
      'statut': statut.valeurSql,
      'message_erreur': statut == StatutTelechargement.echec
          ? messageErreur
          : null,
      'date_maj': _maintenant(),
      if (statut == StatutTelechargement.enAttente) 'nombre_pages_faites': 0,
    };
    try {
      return await _baseDeDonnees.transaction((txn) async {
        final modifiees = await txn.update(
          _table,
          valeurs,
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        if (modifiees == 0) {
          return false;
        }
        if (statut == StatutTelechargement.termine && nomArchive != null) {
          final lignes = await txn.query(
            _table,
            columns: <String>['id_chapitre'],
            where: 'id = ?',
            whereArgs: <Object?>[id],
            limit: 1,
          );
          await enregistrerArchiveChapitre(
            txn,
            lignes.first.lireEntier('id_chapitre', 'Telechargement'),
            nomArchive,
          );
        } else if (statut == StatutTelechargement.termine) {
          await txn.rawUpdate(
            'UPDATE chapitres SET est_telecharge = ? WHERE id = '
            '(SELECT id_chapitre FROM telechargements WHERE id = ?)',
            <Object?>[valeurSqlVrai, id],
          );
        }
        return true;
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer le statut du téléchargement n°$id.',
        cause: erreur,
      );
    }
  }

  /// Enregistre la progression d'un téléchargement (pages écrites et, si
  /// connu, nombre total de pages) et met à jour `date_maj`.
  ///
  /// Lève une [ArgumentError] si un nombre est négatif. Renvoie `false` si le
  /// téléchargement n'existe pas.
  Future<bool> enregistrerProgression(
    int id, {
    required int nombrePagesFaites,
    int? nombrePagesTotal,
  }) async {
    if (nombrePagesFaites < 0) {
      throw ArgumentError.value(nombrePagesFaites, 'nombrePagesFaites');
    }
    if (nombrePagesTotal != null && nombrePagesTotal < 0) {
      throw ArgumentError.value(nombrePagesTotal, 'nombrePagesTotal');
    }
    final modifiees = await _baseDeDonnees.update(
      _table,
      <String, Object?>{
        'nombre_pages_faites': nombrePagesFaites,
        'nombre_pages_total': ?nombrePagesTotal,
        'date_maj': _maintenant(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return modifiees > 0;
  }

  /// Reprise après interruption : remet les téléchargements « en cours » en
  /// « en attente », progression à 0, et renvoie leur nombre.
  ///
  /// - Sans [ancienneteMinimale] : **tous** les « en cours » sont repris
  ///   (cas d'un seul processus : au démarrage, un « en cours » signifie que
  ///   l'application a été fermée pendant le téléchargement).
  /// - Avec [ancienneteMinimale] : seuls ceux dont `date_maj` est plus
  ///   ancienne que maintenant moins ce délai (strictement) sont repris.
  ///   Sur Android, un autre isolat (application ou tâche de fond) peut être
  ///   en train de télécharger : son `date_maj` est rafraîchi à chaque page
  ///   par [enregistrerProgression], il n'est donc pas « vieux » et n'est
  ///   pas volé. Le délai doit dépasser largement le temps d'une page.
  ///
  /// Les `.zip.part` correspondants sont à supprimer avec
  /// `StockageTelechargements.nettoyerFichiersPartiels()`, avec le même
  /// délai.
  Future<int> reprendreApresInterruption({Duration? ancienneteMinimale}) {
    if (ancienneteMinimale != null && ancienneteMinimale.isNegative) {
      throw ArgumentError.value(ancienneteMinimale, 'ancienneteMinimale');
    }
    final maintenant = _horloge();
    final valeurs = <String, Object?>{
      'statut': StatutTelechargement.enAttente.valeurSql,
      'nombre_pages_faites': 0,
      'message_erreur': null,
      'date_maj': dateVersMillisecondes(maintenant),
    };
    if (ancienneteMinimale == null) {
      return _baseDeDonnees.update(
        _table,
        valeurs,
        where: 'statut = ?',
        whereArgs: <Object?>[StatutTelechargement.enCours.valeurSql],
      );
    }
    final limite = dateVersMillisecondes(
      maintenant.subtract(ancienneteMinimale),
    );
    return _baseDeDonnees.update(
      _table,
      valeurs,
      where: 'statut = ? AND date_maj < ?',
      whereArgs: <Object?>[StatutTelechargement.enCours.valeurSql, limite],
    );
  }

  /// Retire un téléchargement de la file. Renvoie `true` s'il existait.
  ///
  /// L'état `chapitres.est_telecharge` et l'archive ne sont pas touchés :
  /// retirer un téléchargement terminé de la liste ne supprime pas le
  /// chapitre hors-ligne.
  Future<bool> supprimerTelechargement(int id) async {
    final supprimees = await _baseDeDonnees.delete(
      _table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return supprimees > 0;
  }

  /// Retire de la file tous les téléchargements terminés et renvoie leur
  /// nombre (même règle que [supprimerTelechargement]).
  Future<int> supprimerTermines() {
    return _baseDeDonnees.delete(
      _table,
      where: 'statut = ?',
      whereArgs: <Object?>[StatutTelechargement.termine.valeurSql],
    );
  }
}
