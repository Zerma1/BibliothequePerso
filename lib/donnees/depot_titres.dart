/// Dépôt des titres, de leurs titres alternatifs et de leurs catégories.
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/titre.dart';
import '../modeles/titre_alternatif.dart';
import 'depot_categories.dart';
import 'gestionnaire_transactions.dart';

/// Accès aux tables `titres`, `titres_alternatifs` et `titres_categories`.
///
/// Étape 8 : `titres.id_source` et `titres.url_titre` désignent le site
/// **principal** du titre ; ils sont redondants avec la ligne principale de
/// `titres_sources`, tenue à jour par les déclencheurs de la migration 7.
/// Les sites secondaires sont gérés par `DepotTitresSources` ;
/// [chargerTitreParUrl] et le filtre `idSource` de [chargerTitres] ne
/// regardent que le site principal.
class DepotTitres {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotTitres(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Colonnes lues pour un titre, avec le nombre de chapitres non lus calculé
  /// par une sous-requête (servie par l'index `index_chapitres_titre_lu`).
  ///
  /// `valeurSqlFaux` est une constante de compilation, pas une valeur venant
  /// de l'utilisateur : l'insérer dans le texte SQL ne crée pas de risque.
  static const String _selectionTitre =
      'SELECT t.*, '
      '(SELECT COUNT(*) FROM chapitres c '
      'WHERE c.id_titre = t.id AND c.est_lu = $valeurSqlFaux) '
      'AS nombre_chapitres_non_lus '
      'FROM titres t';

  /// Enregistre un titre, ses titres alternatifs et, si [categories] est
  /// fourni, ses catégories. Renvoie le titre tel qu'il est relu en base.
  ///
  /// - Si [Titre.id] est connu, la ligne correspondante est mise à jour.
  /// - Sinon, si un titre de même `url_titre` existe, il est mis à jour (pas
  ///   de doublon quand on ajoute deux fois le même titre).
  /// - Sinon, le titre est inséré.
  ///
  /// Les titres alternatifs enregistrés sont remplacés par ceux de [titre]
  /// (noms vides ignorés, doublons fusionnés). Les [categories] sont des noms
  /// bruts venant du site : ils sont normalisés et les catégories existantes
  /// sont réutilisées. `null` laisse les catégories actuelles inchangées ; une
  /// liste vide les retire toutes.
  ///
  /// Lors d'une mise à jour, `date_derniere_verification`,
  /// `langues_preferees` et `couverture_choisie` ne sont pas modifiées :
  /// elles ne sont écrites que par [enregistrerDateVerification],
  /// [enregistrerLanguesPreferees] et [enregistrerCouvertureChoisie]. Un
  /// [Titre.niveauContenu] `null` laisse aussi le niveau enregistré
  /// inchangé.
  ///
  /// Tout se fait dans une seule transaction : en cas d'erreur, rien n'est
  /// écrit. Lève une [ErreurBaseDeDonnees] si [Titre.idSource] est absent ou
  /// ne correspond à aucune source, ou si l'URL est déjà celle d'un autre
  /// titre.
  ///
  /// [executeur] : transaction ouverte par `GestionnaireTransactions` pour
  /// écrire avec d'autres dépôts. Le titre y est écrit puis relu sans ouvrir
  /// de nouvelle transaction ; il ne sera définitif qu'à la validation de
  /// celle-ci. `null` : transaction propre à cet appel (comportement
  /// d'origine).
  Future<Titre> enregistrerTitre(
    Titre titre, {
    List<String>? categories,
    DatabaseExecutor? executeur,
  }) async {
    final idSource = titre.idSource;
    if (idSource == null) {
      throw ErreurBaseDeDonnees(
        'Le titre « ${titre.nom} » n\'a pas de source : idSource est requis '
        'pour l\'enregistrer.',
      );
    }
    final int idTitre;
    try {
      idTitre = await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        (txn) async {
          // Vérification explicite : sqflite ne permet pas de reconnaître
          // proprement une erreur de clé étrangère, et le message est plus clair.
          final sources = await txn.query(
            'sources',
            columns: <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[idSource],
            limit: 1,
          );
          if (sources.isEmpty) {
            throw ErreurBaseDeDonnees(
              'Impossible d\'enregistrer « ${titre.nom} » : la source '
              'n°$idSource n\'existe pas.',
            );
          }
          return _enregistrerTitreDansTransaction(txn, titre, categories);
        },
      );
    } on DatabaseException catch (erreur) {
      if (erreur.isUniqueConstraintError()) {
        throw ErreurBaseDeDonnees(
          'Un autre titre utilise déjà l\'URL « ${titre.urlTitre} ».',
          cause: erreur,
        );
      }
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer le titre « ${titre.nom} ».',
        cause: erreur,
      );
    }

    final relu = await chargerTitre(idTitre, executeur: executeur);
    if (relu == null) {
      throw ErreurBaseDeDonnees(
        'Le titre « ${titre.nom} » est introuvable après son enregistrement.',
      );
    }
    return relu;
  }

  /// Écrit le titre, ses titres alternatifs et ses catégories dans [txn], puis
  /// renvoie l'identifiant du titre.
  Future<int> _enregistrerTitreDansTransaction(
    DatabaseExecutor txn,
    Titre titre,
    List<String>? categories,
  ) async {
    final id = await _enregistrerLigneTitre(txn, titre);

    await txn.delete(
      'titres_alternatifs',
      where: 'id_titre = ?',
      whereArgs: <Object?>[id],
    );
    for (final alternatif in titre.titresAlternatifs) {
      if (alternatif.nom.trim().isEmpty) {
        continue;
      }
      final ligne = alternatif.versMap()
        ..remove('id')
        ..['id_titre'] = id;
      // IGNORE : un nom en double (contrainte UNIQUE(id_titre, nom)) est
      // simplement fusionné avec le premier.
      await txn.insert(
        'titres_alternatifs',
        ligne,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (categories != null) {
      await txn.delete(
        'titres_categories',
        where: 'id_titre = ?',
        whereArgs: <Object?>[id],
      );
      for (final nomBrut in categories) {
        if (nomBrut.trim().isEmpty) {
          continue;
        }
        final categorie = await DepotCategories.enregistrerCategorieAvec(
          txn,
          nomBrut,
        );
        await txn.insert('titres_categories', <String, Object?>{
          'id_titre': id,
          'id_categorie': categorie.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    return id;
  }

  /// Insère ou met à jour la ligne `titres` et renvoie son identifiant.
  ///
  /// On n'utilise pas `INSERT OR REPLACE` : il supprime puis recrée la ligne,
  /// ce qui déclencherait les `ON DELETE CASCADE` et effacerait les chapitres,
  /// l'état de lecture et l'appartenance aux listes.
  Future<int> _enregistrerLigneTitre(DatabaseExecutor txn, Titre titre) async {
    var id = titre.id;
    if (id == null) {
      final existants = await txn.query(
        'titres',
        columns: <String>['id'],
        where: 'url_titre = ?',
        whereArgs: <Object?>[titre.urlTitre],
        limit: 1,
      );
      if (existants.isNotEmpty) {
        id = existants.first['id'] as int?;
      }
    }

    final ligne = titre.versMap()..remove('id');
    if (id == null) {
      // Insertion : les langues et la couverture choisie éventuellement
      // fournies sont gardées, normalisées comme dans leurs méthodes.
      ligne['langues_preferees'] = normaliserLanguesPreferees(
        titre.languesPreferees,
      );
      ligne['couverture_choisie'] = _normaliserCouverture(
        titre.couvertureChoisie,
      );
      return txn.insert('titres', ligne);
    }
    // Mise à jour : la date de vérification, les langues préférées et la
    // couverture choisie ont leur propre méthode. Un Titre reconstruit par
    // une source (valeurs à null) ne doit pas les effacer : ce sont des
    // choix du client.
    ligne
      ..remove('date_derniere_verification')
      ..remove('langues_preferees')
      ..remove('couverture_choisie');
    // Un site qui ne donne pas (ou plus, en cas d'erreur de lecture) le
    // niveau de contenu ne doit pas effacer celui déjà connu : un titre
    // `pornographic` réapparaîtrait sinon dans la bibliothèque filtrée.
    if (titre.niveauContenu == null) {
      ligne.remove('niveau_contenu');
    }
    final modifiees = await txn.update(
      'titres',
      ligne,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (modifiees == 0) {
      throw ErreurBaseDeDonnees('Le titre n°$id n\'existe pas.');
    }
    return id;
  }

  /// Charge un titre complet (avec titres alternatifs et nombre de non-lus),
  /// ou `null` s'il n'existe pas.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<Titre?> chargerTitre(int id, {DatabaseExecutor? executeur}) async {
    final titres = await _chargerAvecConditions(
      executeur ?? _baseDeDonnees,
      't.id = ?',
      <Object?>[id],
    );
    return titres.isEmpty ? null : titres.first;
  }

  /// Charge un titre par son URL exacte, ou `null`.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<Titre?> chargerTitreParUrl(
    String urlTitre, {
    DatabaseExecutor? executeur,
  }) async {
    final titres = await _chargerAvecConditions(
      executeur ?? _baseDeDonnees,
      't.url_titre = ?',
      <Object?>[urlTitre],
    );
    return titres.isEmpty ? null : titres.first;
  }

  /// Charge les titres de la bibliothèque, triés par nom.
  ///
  /// Les filtres se cumulent (ET logique) :
  /// - [recherche] : texte cherché dans le nom **et** dans les titres
  ///   alternatifs, sans tenir compte de la casse ;
  /// - [idListe] : uniquement les titres de cette liste ;
  /// - [idCategorie] : uniquement les titres de cette catégorie ;
  /// - [idSource] : uniquement les titres de cette source ;
  /// - [niveauxContenu] : uniquement les titres dont le niveau de contenu
  ///   fait partie de cette liste (`niveauxContenuParDefaut` pour le filtre
  ///   par défaut). Les titres sans niveau connu (sites autres que MangaDex)
  ///   sont gardés si [inclureNiveauInconnu] vaut `true` (par défaut). `null`
  ///   = pas de filtre ; une liste vide ne garde que les niveaux inconnus
  ///   (ou rien). Comparaison exacte : les niveaux sont stockés tels que
  ///   MangaDex les donne.
  ///
  /// LIMITE : `LIKE` et `lower()` de SQLite (sans extension ICU, absente sur
  /// Android) ne replient que les lettres ASCII. « death » trouve « Death »,
  /// « Élise » trouve « Élise », mais « élise » ne trouve pas « Élise ». Les
  /// écritures sans casse (japonais, coréen, chinois) ne sont pas concernées.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<List<Titre>> chargerTitres({
    String? recherche,
    int? idListe,
    int? idCategorie,
    int? idSource,
    List<String>? niveauxContenu,
    bool inclureNiveauInconnu = true,
    DatabaseExecutor? executeur,
  }) {
    // Seuls des fragments SQL constants sont assemblés ; toutes les valeurs
    // passent par des paramètres `?`.
    final conditions = <String>[];
    final arguments = <Object?>[];

    final texte = recherche?.trim() ?? '';
    if (texte.isNotEmpty) {
      // Le motif n'est PAS mis en minuscules côté Dart : `toLowerCase()`
      // replie aussi les lettres accentuées (É → é), alors que `lower()` de
      // SQLite ne replie que l'ASCII. Les deux côtés passent donc par le même
      // `lower()` SQLite, sinon « Élise » ne trouverait plus « Élise ».
      final motif = '%${_echapperMotifLike(texte)}%';
      // EXISTS plutôt qu'une jointure : un titre qui a plusieurs noms
      // alternatifs correspondants n'apparaît qu'une fois.
      conditions.add(
        "(lower(t.nom) LIKE lower(?) ESCAPE '\\' OR EXISTS ("
        'SELECT 1 FROM titres_alternatifs ta WHERE ta.id_titre = t.id '
        "AND lower(ta.nom) LIKE lower(?) ESCAPE '\\'))",
      );
      arguments
        ..add(motif)
        ..add(motif);
    }
    if (idListe != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM titres_listes tl '
        'WHERE tl.id_titre = t.id AND tl.id_liste = ?)',
      );
      arguments.add(idListe);
    }
    if (idCategorie != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM titres_categories tc '
        'WHERE tc.id_titre = t.id AND tc.id_categorie = ?)',
      );
      arguments.add(idCategorie);
    }
    if (idSource != null) {
      conditions.add('t.id_source = ?');
      arguments.add(idSource);
    }
    if (niveauxContenu != null) {
      // Dédoublonnés et bornés : la liste ne contient en pratique que les
      // quatre niveaux MangaDex.
      final niveaux = niveauxContenu.toSet().take(tailleMaxLotParametresSql);
      final alternatives = <String>[
        if (niveaux.isNotEmpty)
          't.niveau_contenu IN '
              '(${List<String>.filled(niveaux.length, '?').join(', ')})',
        if (inclureNiveauInconnu) 't.niveau_contenu IS NULL',
      ];
      // Aucune alternative : aucun titre ne peut correspondre.
      conditions.add(
        alternatives.isEmpty ? '0' : '(${alternatives.join(' OR ')})',
      );
      arguments.addAll(niveaux);
    }

    return _chargerAvecConditions(
      executeur ?? _baseDeDonnees,
      conditions.isEmpty ? null : conditions.join(' AND '),
      arguments,
    );
  }

  /// Enregistre la date de la dernière recherche de nouveaux chapitres.
  Future<void> enregistrerDateVerification(int idTitre, DateTime date) async {
    await _baseDeDonnees.update(
      'titres',
      <String, Object?>{
        'date_derniere_verification': date.toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[idTitre],
    );
  }

  /// Enregistre les langues favorites propres à un titre, sans toucher aux
  /// autres colonnes ; `null` (ou une liste vide après nettoyage) revient au
  /// réglage général.
  ///
  /// La valeur est normalisée par [normaliserLanguesPreferees] (`" FR, en,fr"`
  /// → `"fr,en"`). Renvoie `false` si le titre n'existe pas. Lève une
  /// [ArgumentError] si un code contient autre chose que des lettres, des
  /// chiffres ou des tirets.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<bool> enregistrerLanguesPreferees(
    int idTitre,
    String? langues, {
    DatabaseExecutor? executeur,
  }) async {
    final modifiees = await (executeur ?? _baseDeDonnees).update(
      'titres',
      <String, Object?>{
        'langues_preferees': normaliserLanguesPreferees(langues),
      },
      where: 'id = ?',
      whereArgs: <Object?>[idTitre],
    );
    return modifiees > 0;
  }

  /// Enregistre la couverture choisie par le client (URL d'une autre
  /// couverture du site ou chemin d'une image de l'appareil), sans toucher
  /// aux autres colonnes ; `null` ou un texte vide revient à la couverture
  /// du site.
  ///
  /// Renvoie `false` si le titre n'existe pas. Une ré-actualisation du titre
  /// par [enregistrerTitre] ne modifie jamais ce choix.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<bool> enregistrerCouvertureChoisie(
    int idTitre,
    String? couverture, {
    DatabaseExecutor? executeur,
  }) async {
    final modifiees = await (executeur ?? _baseDeDonnees).update(
      'titres',
      <String, Object?>{
        'couverture_choisie': _normaliserCouverture(couverture),
      },
      where: 'id = ?',
      whereArgs: <Object?>[idTitre],
    );
    return modifiees > 0;
  }

  /// Couverture choisie sans espaces autour, `null` si vide.
  static String? _normaliserCouverture(String? couverture) {
    final valeur = couverture?.trim() ?? '';
    return valeur.isEmpty ? null : valeur;
  }

  // Un code de langue : lettres minuscules, chiffres et tirets (`pt-br`).
  static final RegExp _codeLangue = RegExp(r'^[a-z0-9-]+$');

  /// Normalise une liste de langues séparées par des virgules : espaces
  /// retirés, minuscules, éléments vides et doublons supprimés (le premier
  /// gardé, l'ordre de préférence est conservé). Renvoie `null` si rien ne
  /// reste.
  ///
  /// Lève une [ArgumentError] si un code contient autre chose que des
  /// lettres, des chiffres ou des tirets.
  static String? normaliserLanguesPreferees(String? langues) {
    if (langues == null) {
      return null;
    }
    final codes = <String>{};
    for (final brut in langues.split(',')) {
      final code = brut.trim().toLowerCase();
      if (code.isEmpty) {
        continue;
      }
      if (!_codeLangue.hasMatch(code)) {
        throw ArgumentError.value(
          langues,
          'langues',
          'code de langue invalide : « $code »',
        );
      }
      codes.add(code);
    }
    return codes.isEmpty ? null : codes.join(',');
  }

  /// Supprime un titre. Ses chapitres, titres alternatifs, appartenances aux
  /// listes et liens de catégories disparaissent par `ON DELETE CASCADE`.
  Future<void> supprimerTitre(int id) async {
    await _baseDeDonnees.delete(
      'titres',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Exécute la requête de titres avec une clause `WHERE` facultative, puis
  /// charge les titres alternatifs de tous les résultats.
  Future<List<Titre>> _chargerAvecConditions(
    DatabaseExecutor base,
    String? clauseWhere,
    List<Object?> arguments,
  ) async {
    final sql = StringBuffer(_selectionTitre);
    if (clauseWhere != null) {
      sql.write(' WHERE $clauseWhere');
    }
    sql.write(' ORDER BY t.nom COLLATE NOCASE, t.id');

    final lignes = await base.rawQuery(sql.toString(), arguments);
    if (lignes.isEmpty) {
      return <Titre>[];
    }

    final ids = <int>[
      for (final ligne in lignes)
        if (ligne['id'] case final int id) id,
    ];
    final alternatifsParTitre = await _chargerTitresAlternatifs(base, ids);

    return <Titre>[
      for (final ligne in lignes)
        Titre.depuisMap(
          ligne,
          titresAlternatifs:
              alternatifsParTitre[ligne['id']] ?? const <TitreAlternatif>[],
        ),
    ];
  }

  /// Charge les titres alternatifs de plusieurs titres en peu de requêtes,
  /// regroupés par identifiant de titre.
  Future<Map<int, List<TitreAlternatif>>> _chargerTitresAlternatifs(
    DatabaseExecutor base,
    List<int> idsTitres,
  ) async {
    final resultat = <int, List<TitreAlternatif>>{};
    // Découpage en lots : la limite de paramètres de SQLite peut être de 999
    // sur les anciens Android.
    for (
      var debut = 0;
      debut < idsTitres.length;
      debut += tailleMaxLotParametresSql
    ) {
      final fin = (debut + tailleMaxLotParametresSql < idsTitres.length)
          ? debut + tailleMaxLotParametresSql
          : idsTitres.length;
      final lot = idsTitres.sublist(debut, fin);
      // Seuls des `?` sont générés ; les identifiants sont passés en paramètres.
      final marqueurs = List<String>.filled(lot.length, '?').join(', ');
      final lignes = await base.rawQuery(
        'SELECT * FROM titres_alternatifs WHERE id_titre IN ($marqueurs) '
        'ORDER BY id',
        lot,
      );
      for (final ligne in lignes) {
        final alternatif = TitreAlternatif.depuisMap(ligne);
        final idTitre = alternatif.idTitre;
        if (idTitre != null) {
          (resultat[idTitre] ??= <TitreAlternatif>[]).add(alternatif);
        }
      }
    }
    return resultat;
  }

  /// Échappe les caractères spéciaux de `LIKE` (`%`, `_` et le caractère
  /// d'échappement lui-même) pour qu'ils soient cherchés littéralement.
  static String _echapperMotifLike(String texte) {
    return texte
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }
}
