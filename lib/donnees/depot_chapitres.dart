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
///   `est_telecharge` = 0 et `est_garde` = 0 (un chapitre sans archive n'a
///   rien à garder ; retéléchargé, il suit de nouveau les règles).
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
        'est_garde': valeurSqlFaux,
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
      if (nomArchive == null) 'est_garde': valeurSqlFaux,
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
  /// et de téléchargement. Seule exception : son lien externe
  /// ([Chapitre.urlExterne]) est mis à jour s'il a changé, y compris remis à
  /// NULL quand le chapitre devient hébergé par le site source ; aucune autre
  /// colonne n'est touchée. Un lien vide ou fait d'espaces est enregistré
  /// comme NULL. Les chapitres sans [Chapitre.dateDetection] reçoivent
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
        final nouveaux = await _insererChapitres(txn, chapitres, detection);
        await _mettreAJourUrlsExternes(txn, chapitres);
        return nouveaux;
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
      ligne['url_externe'] = _normaliserUrlExterne(chapitre.urlExterne);
      await txn.insert(
        'chapitres',
        ligne,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    final apres = await _compterTout(txn);
    return apres - avant;
  }

  /// Aligne le lien externe des chapitres **déjà connus** sur celui donné par
  /// le site, dans [txn].
  ///
  /// Une seule colonne est écrite (`url_externe`) : l'état de lecture, de
  /// téléchargement, la suppression prévue et le choix « Garder » restent
  /// intacts. `IS NOT ?` compare aussi les NULL (contrairement à `!=`) : la
  /// ligne n'est écrite que si la valeur change réellement, et un chapitre
  /// qui vient d'être inséré, déjà à jour, n'est pas réécrit. La recherche
  /// passe par l'index UNIQUE de `url_chapitre` ; le filtre sur `id_titre`
  /// évite de modifier le chapitre d'un autre titre qui partagerait l'URL.
  Future<void> _mettreAJourUrlsExternes(
    Transaction txn,
    List<Chapitre> chapitres,
  ) async {
    for (final chapitre in chapitres) {
      final urlExterne = _normaliserUrlExterne(chapitre.urlExterne);
      await txn.rawUpdate(
        'UPDATE chapitres SET url_externe = ? '
        'WHERE url_chapitre = ? AND id_titre = ? AND url_externe IS NOT ?',
        <Object?>[
          urlExterne,
          chapitre.urlChapitre,
          chapitre.idTitre,
          urlExterne,
        ],
      );
    }
  }

  /// Lien externe sans espaces autour, ou `null` s'il est absent ou vide
  /// (un lien vide signifie « hébergé par le site source »).
  static String? _normaliserUrlExterne(String? urlExterne) {
    final url = urlExterne?.trim();
    return url == null || url.isEmpty ? null : url;
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
  /// Avec `estTelecharge: false`, le chemin enregistré (`nom_archive`), la
  /// suppression prévue et le choix « Garder » sont aussi effacés : un
  /// chapitre non téléchargé n'a ni archive ni suppression à faire. Pour enregistrer le chemin d'une
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
  ///   `date_suppression_prevue` à NULL, `est_telecharge` = 0 et
  ///   `est_garde` = 0.
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
  /// Les chapitres gardés (`est_garde = 1`) sont exclus : le choix
  /// « Garder » du client l'emporte toujours sur une date restée en base.
  ///
  /// Le service supprime leur archive puis appelle
  /// [enregistrerArchive]`(id, null)`, qui efface aussi la date. La
  /// recherche utilise l'index partiel `index_chapitres_suppression_prevue`
  /// (migration 4).
  Future<List<Chapitre>> chargerSuppressionsEchues(DateTime maintenant) async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      where: 'date_suppression_prevue <= ? AND est_garde = ?',
      whereArgs: <Object?>[dateVersMillisecondes(maintenant), valeurSqlFaux],
      orderBy: 'date_suppression_prevue, id',
    );
    return lignes.map(Chapitre.depuisMap).toList();
  }

  /// Charge tous les chapitres qui ont une suppression prévue (échue ou
  /// non), la plus proche d'abord ; si [idTitre] est donné, seulement ceux
  /// de ce titre.
  ///
  /// Sert à l'onglet Téléchargements (chapitres affichés en rouge avec leur
  /// compte à rebours). Utilise l'index partiel
  /// `index_chapitres_suppression_prevue` (migration 4).
  Future<List<Chapitre>> chargerSuppressionsPrevues({int? idTitre}) async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      where: idTitre == null
          ? 'date_suppression_prevue IS NOT NULL'
          : 'date_suppression_prevue IS NOT NULL AND id_titre = ?',
      whereArgs: <Object?>[?idTitre],
      orderBy: 'date_suppression_prevue, id',
    );
    return lignes.map(Chapitre.depuisMap).toList();
  }

  /// Repousse à [date] la suppression prévue d'un chapitre, **seulement** si
  /// une suppression est déjà prévue et plus tôt que [date].
  ///
  /// Sert à protéger le chapitre ouvert dans le lecteur : la suppression
  /// n'est jamais créée (un chapitre sans date reste sans date) ni avancée.
  /// Le test et l'écriture se font en une seule requête `UPDATE … WHERE`,
  /// donc sans course avec un autre isolat. Renvoie `true` si la date a été
  /// modifiée.
  Future<bool> repousserSuppressionPrevue(int idChapitre, DateTime date) async {
    final modifiees = await _baseDeDonnees.rawUpdate(
      'UPDATE chapitres SET date_suppression_prevue = ? '
      'WHERE id = ? AND date_suppression_prevue IS NOT NULL '
      'AND date_suppression_prevue < ?',
      <Object?>[
        dateVersMillisecondes(date),
        idChapitre,
        dateVersMillisecondes(date),
      ],
    );
    return modifiees > 0;
  }

  /// Marque un chapitre comme gardé par le client (bouton « Garder »), ou
  /// retire ce choix si [estGarde] vaut `false`.
  ///
  /// Garder un chapitre annule aussi sa suppression prévue
  /// (`date_suppression_prevue` à NULL), dans la même requête : le chapitre
  /// ne peut pas être supprimé entre les deux écritures. Renvoie `false` si
  /// le chapitre n'existe pas.
  Future<bool> marquerGarde(int idChapitre, {bool estGarde = true}) async {
    final modifiees = await _baseDeDonnees.update(
      'chapitres',
      <String, Object?>{
        'est_garde': booleenVersEntier(estGarde),
        if (estGarde) 'date_suppression_prevue': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[idChapitre],
    );
    return modifiees > 0;
  }

  /// Marque plusieurs chapitres comme gardés en une transaction et renvoie
  /// le nombre de chapitres trouvés.
  ///
  /// Sert à la reprise des identifiants gardés que la couche services
  /// mémorisait dans `parametres` avant la migration 5 : les identifiants
  /// de chapitres disparus sont ignorés. Comme [marquerGarde], annule leur
  /// suppression prévue.
  Future<int> marquerGardes(Iterable<int> idsChapitres) async {
    final ids = idsChapitres.toSet().toList();
    if (ids.isEmpty) {
      return 0;
    }
    return _baseDeDonnees.transaction((txn) async {
      var nombre = 0;
      for (
        var debut = 0;
        debut < ids.length;
        debut += tailleMaxLotParametresSql
      ) {
        final fin = debut + tailleMaxLotParametresSql < ids.length
            ? debut + tailleMaxLotParametresSql
            : ids.length;
        final lot = ids.sublist(debut, fin);
        // Seuls des `?` sont générés ; les identifiants sont des paramètres.
        final marqueurs = List<String>.filled(lot.length, '?').join(', ');
        nombre += await txn.rawUpdate(
          'UPDATE chapitres SET est_garde = ?, date_suppression_prevue = NULL '
          'WHERE id IN ($marqueurs)',
          <Object?>[valeurSqlVrai, ...lot],
        );
      }
      return nombre;
    });
  }

  /// Identifiants des chapitres gardés par le client.
  ///
  /// Requête servie par l'index partiel `index_chapitres_gardes`
  /// (migration 5).
  Future<Set<int>> chargerIdsChapitresGardes() async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      columns: <String>['id'],
      where: 'est_garde = ?',
      whereArgs: <Object?>[valeurSqlVrai],
    );
    return <int>{
      for (final ligne in lignes)
        if (ligne['id'] case final int id) id,
    };
  }

  /// Date de la dernière parution, par titre, parmi les chapitres dans l'une
  /// des [langues] données (idTitre → date UTC), pour l'onglet Mises à jour.
  ///
  /// La date d'un chapitre est sa date de publication, ou à défaut sa date
  /// de détection (sites qui ne donnent pas de date). Les titres sans aucun
  /// chapitre daté dans ces langues sont absents du résultat. Les langues
  /// sont comparées sans tenir compte de la casse (`pt-BR` = `pt-br`) ; une
  /// liste vide donne un résultat vide.
  ///
  /// Les titres n'ayant pas tous les mêmes langues (`languesPourTitre`), le
  /// service appelle cette méthode une fois par jeu de langues et ne garde
  /// que les titres concernés.
  ///
  /// LIMITE : la requête parcourt toute la table `chapitres` (pas d'index
  /// sur `lower(langue)`) ; elle n'est faite qu'à l'ouverture de l'onglet,
  /// ce qui reste rapide pour quelques dizaines de milliers de chapitres.
  Future<Map<int, DateTime>> chargerDernieresParutions(
    List<String> langues,
  ) async {
    final codes = _normaliserLangues(langues);
    if (codes.isEmpty) {
      return <int, DateTime>{};
    }
    final marqueurs = List<String>.filled(codes.length, '?').join(', ');
    final lignes = await _baseDeDonnees.rawQuery(
      'SELECT id_titre, MAX(COALESCE(date_publication, date_detection)) '
      'AS derniere_parution FROM chapitres '
      'WHERE lower(langue) IN ($marqueurs) '
      'GROUP BY id_titre',
      codes,
    );
    final resultat = <int, DateTime>{};
    for (final ligne in lignes) {
      final idTitre = ligne['id_titre'];
      final date = ligne['derniere_parution'];
      if (idTitre is int && date is int) {
        resultat[idTitre] = DateTime.fromMillisecondsSinceEpoch(
          date,
          isUtc: true,
        );
      }
    }
    return resultat;
  }

  /// Dernier chapitre paru d'un titre dans l'une des [langues] données (même
  /// date que [chargerDernieresParutions]), ou `null` s'il n'y en a pas.
  ///
  /// À égalité de date, le plus grand numéro l'emporte. Requête servie par
  /// l'index `index_chapitres_titre_lu` (filtre sur `id_titre`).
  Future<Chapitre?> chargerDernierChapitreParu(
    int idTitre,
    List<String> langues,
  ) async {
    final codes = _normaliserLangues(langues);
    if (codes.isEmpty) {
      return null;
    }
    final marqueurs = List<String>.filled(codes.length, '?').join(', ');
    final lignes = await _baseDeDonnees.rawQuery(
      'SELECT * FROM chapitres '
      'WHERE id_titre = ? AND lower(langue) IN ($marqueurs) '
      'AND COALESCE(date_publication, date_detection) IS NOT NULL '
      'ORDER BY COALESCE(date_publication, date_detection) DESC, '
      'numero DESC, id DESC LIMIT 1',
      <Object?>[idTitre, ...codes],
    );
    return lignes.isEmpty ? null : Chapitre.depuisMap(lignes.first);
  }

  /// Codes de langue en minuscules, sans espaces, vides et doublons retirés,
  /// au plus [tailleMaxLotParametresSql] (une personne lit bien moins de
  /// langues que cela).
  static List<String> _normaliserLangues(List<String> langues) {
    final codes = <String>{
      for (final langue in langues)
        if (langue.trim().isNotEmpty) langue.trim().toLowerCase(),
    }.toList();
    return codes.length > tailleMaxLotParametresSql
        ? codes.sublist(0, tailleMaxLotParametresSql)
        : codes;
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
