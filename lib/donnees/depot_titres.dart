/// Dépôt des titres, de leurs titres alternatifs et de leurs catégories.
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/titre.dart';
import '../modeles/titre_alternatif.dart';
import 'depot_categories.dart';
import 'depot_equivalences_categories.dart';
import 'gestionnaire_transactions.dart';

/// Accès aux tables `titres`, `titres_alternatifs` et `titres_categories`.
///
/// Migration 10 : les champs modifiés à la main par le client
/// ([enregistrerModificationManuelle]) sont protégés contre l'actualisation
/// depuis le site ([enregistrerTitre]) jusqu'à [rendreChampsAuSite].
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
  /// Champs modifiés à la main (migration 10, [Titre.champsManuels] en
  /// base) : lors d'une mise à jour, les champs verrouillés (nom, noms
  /// alternatifs, résumé, auteur, statut, catégories, niveau de contenu)
  /// gardent leur valeur, quoi que contienne [titre] ; les champs manuels
  /// eux-mêmes ne changent pas (voir [enregistrerModificationManuelle] et
  /// [rendreChampsAuSite]). À l'insertion, [Titre.champsManuels] est écrit
  /// tel quel.
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
    final (id, verrous) = await _enregistrerLigneTitre(txn, titre);

    // Noms et catégories modifiés à la main : gardés tels quels (migration
    // 10), quoi que renvoie le site.
    if (!verrous.contains(ChampTitre.titresAlternatifs)) {
      await _remplacerTitresAlternatifs(txn, id, titre.titresAlternatifs);
    }
    if (categories != null && !verrous.contains(ChampTitre.categories)) {
      await _remplacerCategories(txn, id, categories);
    }
    return id;
  }

  /// Remplace les titres alternatifs du titre [idTitre] par [alternatifs]
  /// (noms vides ignorés, doublons fusionnés).
  static Future<void> _remplacerTitresAlternatifs(
    DatabaseExecutor txn,
    int idTitre,
    List<TitreAlternatif> alternatifs,
  ) async {
    await txn.delete(
      'titres_alternatifs',
      where: 'id_titre = ?',
      whereArgs: <Object?>[idTitre],
    );
    for (final alternatif in alternatifs) {
      if (alternatif.nom.trim().isEmpty) {
        continue;
      }
      final ligne = alternatif.versMap()
        ..remove('id')
        ..['id_titre'] = idTitre;
      // IGNORE : un nom en double (contrainte UNIQUE(id_titre, nom)) est
      // simplement fusionné avec le premier.
      await txn.insert(
        'titres_alternatifs',
        ligne,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Remplace les catégories du titre [idTitre] par [categories] (noms
  /// bruts, normalisés ; noms vides ignorés).
  static Future<void> _remplacerCategories(
    DatabaseExecutor txn,
    int idTitre,
    List<String> categories,
  ) async {
    await txn.delete(
      'titres_categories',
      where: 'id_titre = ?',
      whereArgs: <Object?>[idTitre],
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
        'id_titre': idTitre,
        'id_categorie': categorie.id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Colonne de la table `titres` de chaque champ verrouillable qui en a
  /// une (les noms alternatifs et les catégories vivent dans d'autres
  /// tables).
  static const Map<ChampTitre, String> _colonnesChampsManuels =
      <ChampTitre, String>{
        ChampTitre.nom: 'nom',
        ChampTitre.resume: 'resume',
        ChampTitre.auteur: 'auteur',
        ChampTitre.statut: 'statut',
        ChampTitre.niveauContenu: 'niveau_contenu',
      };

  /// Insère ou met à jour la ligne `titres` et renvoie son identifiant et
  /// ses champs manuels (verrouillés) tels qu'ils sont en base.
  ///
  /// On n'utilise pas `INSERT OR REPLACE` : il supprime puis recrée la ligne,
  /// ce qui déclencherait les `ON DELETE CASCADE` et effacerait les chapitres,
  /// l'état de lecture et l'appartenance aux listes.
  Future<(int, Set<ChampTitre>)> _enregistrerLigneTitre(
    DatabaseExecutor txn,
    Titre titre,
  ) async {
    var id = titre.id;
    final existants = await txn.query(
      'titres',
      columns: <String>['id', 'champs_manuels'],
      where: id == null ? 'url_titre = ?' : 'id = ?',
      whereArgs: <Object?>[id ?? titre.urlTitre],
      limit: 1,
    );
    if (id != null && existants.isEmpty) {
      throw ErreurBaseDeDonnees('Le titre n°$id n\'existe pas.');
    }
    if (existants.isNotEmpty) {
      id = existants.first['id'] as int?;
    }

    final ligne = titre.versMap()..remove('id');
    if (id == null) {
      // Insertion : les langues, la couverture choisie et les champs
      // manuels éventuellement fournis (import d'un export) sont gardés,
      // normalisés comme dans leurs méthodes.
      ligne['langues_preferees'] = normaliserLanguesPreferees(
        titre.languesPreferees,
      );
      ligne['couverture_choisie'] = _normaliserCouverture(
        titre.couvertureChoisie,
      );
      return (await txn.insert('titres', ligne), titre.champsManuels);
    }
    final verrous = Titre.decoderChampsManuels(
      existants.first['champs_manuels'] as String?,
    );
    // Mise à jour : la date de vérification, les langues préférées, la
    // couverture choisie et les champs manuels ont leur propre méthode. Un
    // Titre reconstruit par une source (valeurs à null) ne doit pas les
    // effacer : ce sont des choix du client.
    ligne
      ..remove('date_derniere_verification')
      ..remove('langues_preferees')
      ..remove('couverture_choisie')
      ..remove('champs_manuels');
    // Un site qui ne donne pas (ou plus, en cas d'erreur de lecture) le
    // niveau de contenu ne doit pas effacer celui déjà connu : un titre
    // `pornographic` réapparaîtrait sinon dans la bibliothèque filtrée.
    if (titre.niveauContenu == null) {
      ligne.remove('niveau_contenu');
    }
    // Champs modifiés à la main (migration 10) : jamais écrasés par le site.
    for (final champ in verrous) {
      final colonne = _colonnesChampsManuels[champ];
      if (colonne != null) {
        ligne.remove(colonne);
      }
    }
    await txn.update(
      'titres',
      ligne,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return (id, verrous);
  }

  /// Enregistre une modification faite à la main par le client : seuls les
  /// champs donnés (non `null`) sont écrits, et ils sont **verrouillés**
  /// (ajoutés à [Titre.champsManuels]) : l'actualisation depuis le site par
  /// [enregistrerTitre] ne les écrase plus, jusqu'à [rendreChampsAuSite].
  ///
  /// - [nom] : nettoyé des espaces ; vide refusé.
  /// - [resume], [auteur], [statut] : nettoyés ; un texte vide efface la
  ///   valeur (`NULL`), qui reste verrouillée (le site ne la remettra pas).
  /// - [niveauContenu] : une valeur de `niveauxContenu` (`constantes.dart`),
  ///   ou un texte vide pour « inconnu » ; toute autre valeur est refusée.
  /// - [titresAlternatifs] : remplacent tous les noms alternatifs (noms vides
  ///   ignorés, doublons fusionnés).
  /// - [categories] : noms bruts qui remplacent toutes les catégories
  ///   (normalisés, catégories existantes réutilisées ; liste vide = aucune).
  ///
  /// Aucun champ donné : rien n'est écrit, le titre est renvoyé tel quel.
  /// Renvoie le titre relu en base. Lève une [ErreurBaseDeDonnees] si le
  /// titre n'existe pas, si [nom] est vide ou si [niveauContenu] est
  /// inconnu ; rien n'est alors écrit (vérifications faites avant la
  /// première écriture).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`) ;
  /// `null` : transaction propre à cet appel.
  Future<Titre> enregistrerModificationManuelle(
    int idTitre, {
    String? nom,
    List<TitreAlternatif>? titresAlternatifs,
    String? resume,
    String? auteur,
    String? statut,
    List<String>? categories,
    String? niveauContenu,
    DatabaseExecutor? executeur,
  }) async {
    final colonnes = <String, Object?>{};
    final champs = <ChampTitre>{};
    if (nom != null) {
      final nomPropre = nom.trim();
      if (nomPropre.isEmpty) {
        throw const ErreurBaseDeDonnees(
          'Le nom d\'un titre ne peut pas être vide.',
        );
      }
      colonnes['nom'] = nomPropre;
      champs.add(ChampTitre.nom);
    }
    void texteOptionnel(String? valeur, ChampTitre champ) {
      if (valeur == null) {
        return;
      }
      final propre = valeur.trim();
      colonnes[_colonnesChampsManuels[champ]!] = propre.isEmpty ? null : propre;
      champs.add(champ);
    }

    texteOptionnel(resume, ChampTitre.resume);
    texteOptionnel(auteur, ChampTitre.auteur);
    texteOptionnel(statut, ChampTitre.statut);
    if (niveauContenu != null) {
      final niveau = niveauContenu.trim();
      if (niveau.isNotEmpty && !niveauxContenu.contains(niveau)) {
        throw ErreurBaseDeDonnees(
          'Niveau de contenu inconnu : « $niveau » (valeurs possibles : '
          '${niveauxContenu.join(', ')}).',
        );
      }
      colonnes['niveau_contenu'] = niveau.isEmpty ? null : niveau;
      champs.add(ChampTitre.niveauContenu);
    }
    if (titresAlternatifs != null) {
      champs.add(ChampTitre.titresAlternatifs);
    }
    if (categories != null) {
      champs.add(ChampTitre.categories);
    }

    try {
      await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        (txn) async {
          final lignes = await txn.query(
            'titres',
            columns: <String>['champs_manuels'],
            where: 'id = ?',
            whereArgs: <Object?>[idTitre],
            limit: 1,
          );
          if (lignes.isEmpty) {
            throw ErreurBaseDeDonnees('Le titre n°$idTitre n\'existe pas.');
          }
          if (champs.isEmpty) {
            return;
          }
          final verrous = <ChampTitre>{
            ...Titre.decoderChampsManuels(
              lignes.first['champs_manuels'] as String?,
            ),
            ...champs,
          };
          colonnes['champs_manuels'] = Titre.encoderChampsManuels(verrous);
          await txn.update(
            'titres',
            colonnes,
            where: 'id = ?',
            whereArgs: <Object?>[idTitre],
          );
          if (titresAlternatifs != null) {
            await _remplacerTitresAlternatifs(txn, idTitre, titresAlternatifs);
          }
          if (categories != null) {
            await _remplacerCategories(txn, idTitre, categories);
          }
        },
      );
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Impossible d\'enregistrer la modification du titre n°$idTitre.',
        cause: erreur,
      );
    }

    final relu = await chargerTitre(idTitre, executeur: executeur);
    if (relu == null) {
      throw ErreurBaseDeDonnees('Le titre n°$idTitre n\'existe pas.');
    }
    return relu;
  }

  /// « Rend au site » les [champs] d'un titre : leur verrou est retiré,
  /// sans toucher à leur valeur. La valeur du site reviendra à la prochaine
  /// actualisation par [enregistrerTitre] (pour les catégories : à la
  /// prochaine actualisation qui fournit des catégories).
  ///
  /// Un champ qui n'était pas verrouillé est ignoré. Renvoie `false` si le
  /// titre n'existe pas.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`) ;
  /// `null` : transaction propre à cet appel.
  Future<bool> rendreChampsAuSite(
    int idTitre,
    Set<ChampTitre> champs, {
    DatabaseExecutor? executeur,
  }) {
    return GestionnaireTransactions.executerAtomiquement(
      _baseDeDonnees,
      executeur,
      (txn) async {
        final lignes = await txn.query(
          'titres',
          columns: <String>['champs_manuels'],
          where: 'id = ?',
          whereArgs: <Object?>[idTitre],
          limit: 1,
        );
        if (lignes.isEmpty) {
          return false;
        }
        final verrous = Titre.decoderChampsManuels(
          lignes.first['champs_manuels'] as String?,
        ).difference(champs);
        await txn.update(
          'titres',
          <String, Object?>{
            'champs_manuels': Titre.encoderChampsManuels(verrous),
          },
          where: 'id = ?',
          whereArgs: <Object?>[idTitre],
        );
        return true;
      },
    );
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
  /// - [idsCategoriesIncluses] : uniquement les titres qui ont **toutes**
  ///   ces catégories (se cumule avec [idCategorie]) ;
  /// - [idsCategoriesExclues] : uniquement les titres qui n'ont **aucune**
  ///   de ces catégories ;
  /// - [suivreEquivalences] (`true` par défaut) : les filtres de catégorie
  ///   portent sur le **groupe** de la catégorie demandée (migration 9,
  ///   `DepotEquivalencesCategories`). Un filtre sur « survie » (référence)
  ///   trouve aussi les titres classés « survival » (rattachée), et
  ///   inversement : filtrer sur une catégorie rattachée revient à filtrer
  ///   sur tout son groupe. Une catégorie sans groupe se comporte comme
  ///   avant. `false` : correspondance exacte sur l'identifiant ;
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
    Set<int> idsCategoriesIncluses = const <int>{},
    Set<int> idsCategoriesExclues = const <int>{},
    bool suivreEquivalences = true,
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
    // Une condition EXISTS par catégorie incluse, NOT EXISTS par exclue.
    // LIMITE : deux paramètres par catégorie avec les équivalences ; la
    // limite de 999 paramètres de SQLite n'est pas atteignable avec les
    // quelques catégories choisies dans le panneau des filtres.
    void filtrerCategorie(int id, {required bool exclue}) {
      final prefixe = exclue ? 'NOT EXISTS' : 'EXISTS';
      if (suivreEquivalences) {
        // Le titre a une catégorie dont la catégorie effective (référence,
        // ou elle-même) est celle de [id]. La jointure passe par la clé
        // primaire de titres_categories et l'index UNIQUE de
        // categories_equivalences.id_categorie.
        conditions.add(
          '$prefixe (SELECT 1 FROM titres_categories tc '
          '${DepotEquivalencesCategories.jointureEquivalences} '
          'WHERE tc.id_titre = t.id '
          'AND ${DepotEquivalencesCategories.sqlIdEffectif} = '
          '${DepotEquivalencesCategories.sqlIdEffectifParametre})',
        );
        arguments
          ..add(id)
          ..add(id);
      } else {
        conditions.add(
          '$prefixe (SELECT 1 FROM titres_categories tc '
          'WHERE tc.id_titre = t.id AND tc.id_categorie = ?)',
        );
        arguments.add(id);
      }
    }

    for (final id in <int>{?idCategorie, ...idsCategoriesIncluses}) {
      filtrerCategorie(id, exclue: false);
    }
    for (final id in idsCategoriesExclues) {
      filtrerCategorie(id, exclue: true);
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

  /// Compte les titres de la bibliothèque (tous, sans filtre).
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<int> compterTitres({DatabaseExecutor? executeur}) async {
    final lignes = await (executeur ?? _baseDeDonnees).rawQuery(
      'SELECT COUNT(*) AS nombre FROM titres',
    );
    return Sqflite.firstIntValue(lignes) ?? 0;
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
