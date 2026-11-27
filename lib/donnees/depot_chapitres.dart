/// Dépôt des chapitres et de l'état de lecture.
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/outils_modeles.dart';
import '../modeles/telechargement.dart';
import 'gestionnaire_transactions.dart';

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

/// Supprime, dans [executeur] (une transaction), les chapitres du titre
/// [idTitre] venant de la source [idSource] que rien ne justifie de garder,
/// et renvoie leur nombre ; partagé par
/// `DepotChapitres.supprimerChapitresNonConserves` et
/// `DepotTitresSources.retirerSourceSecondaire`.
///
/// Sont supprimés les chapitres **non lus**, **non téléchargés** (ni
/// `est_telecharge`, ni archive enregistrée) et **non gardés**, sans
/// téléchargement en cours (`telechargements.statut = 'en_cours'` : le
/// service écrirait sinon une archive pour un chapitre disparu). Leur
/// éventuelle entrée en attente dans la file disparaît par `ON DELETE
/// CASCADE`. Les chapitres lus ou téléchargés restent, avec leur
/// `id_source` : l'état de lecture n'est jamais perdu, et les archives
/// suivent la règle des 24 h (couche services).
///
/// [garderChapitresWeb] à `true` (passage d'un site en lien seul) : les
/// chapitres enregistrés depuis le navigateur intégré
/// ([OrigineChapitre.web]) sont aussi gardés, même non lus ; c'est
/// justement sur un lien seul qu'ils servent. À `false` (retrait du site),
/// ils suivent la même règle que les autres.
///
/// Requête servie par l'index `index_chapitres_titre_source` (migration 7).
Future<int> supprimerChapitresNonConservesSource(
  DatabaseExecutor executeur,
  int idTitre,
  int idSource, {
  bool garderChapitresWeb = false,
}) {
  return executeur.rawDelete(
    'DELETE FROM chapitres '
    'WHERE id_titre = ? AND id_source = ? '
    'AND est_lu = ? AND est_telecharge = ? AND nom_archive IS NULL '
    'AND est_garde = ? '
    '${garderChapitresWeb ? 'AND origine != ? ' : ''}'
    'AND NOT EXISTS (SELECT 1 FROM telechargements d '
    'WHERE d.id_chapitre = chapitres.id AND d.statut = ?)',
    <Object?>[
      idTitre,
      idSource,
      valeurSqlFaux,
      valeurSqlFaux,
      valeurSqlFaux,
      if (garderChapitresWeb) OrigineChapitre.web.name,
      StatutTelechargement.enCours.valeurSql,
    ],
  );
}

/// Expression SQL qui normalise l'adresse contenue dans [colonne] comme
/// [normaliserUrlChapitre] : espaces autour, fragment (`#…`) et `/` finaux
/// retirés. NULL reste NULL.
///
/// [colonne] est toujours un nom de colonne écrit en dur dans ce fichier,
/// jamais une valeur : la requête reste paramétrée.
String _sqlUrlNormalisee(String colonne) =>
    "rtrim(CASE WHEN instr(trim($colonne), '#') > 0 "
    "THEN substr(trim($colonne), 1, instr(trim($colonne), '#') - 1) "
    "ELSE trim($colonne) END, '/')";

/// Numéro de chapitre sans zéros inutiles (`12`, `10.5`), pour le nom par
/// défaut d'un chapitre enregistré depuis le web.
String _texteNumero(double numero) => numero == numero.truncateToDouble()
    ? numero.toInt().toString()
    : numero.toString();

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
  /// Site d'origine (étape 8) : si [idSource] est donné, il s'applique aux
  /// chapitres qui n'ont pas leur propre [Chapitre.idSource] ; un chapitre
  /// resté sans source reçoit la source principale de son titre (déclencheur
  /// de la migration 7). Un chapitre déjà connu garde sa source d'origine.
  ///
  /// Lève une [ErreurBaseDeDonnees] si un chapitre n'a pas de
  /// [Chapitre.idTitre], si ce titre n'existe pas, ou si sa source n'est pas
  /// l'un des sites du titre (`titres_sources`) ou est un lien seul
  /// (migration 8) pour un chapitre d'origine [OrigineChapitre.site] ; rien
  /// n'est alors écrit.
  ///
  /// Chapitres enregistrés depuis le web ([OrigineChapitre.web], voir
  /// [enregistrerChapitreWeb]) : l'actualisation ne les supprime jamais (elle
  /// ne supprime rien) et ne les modifie jamais (une adresse déjà connue est
  /// ignorée, et le lien externe d'un chapitre web n'est pas réécrit).
  Future<int> enregistrerChapitres(
    List<Chapitre> chapitres, {
    DateTime? dateDetection,
    int? idSource,
  }) async {
    if (chapitres.isEmpty) {
      return 0;
    }
    final detection = dateDetection ?? DateTime.now().toUtc();
    final aEnregistrer = idSource == null
        ? chapitres
        : <Chapitre>[
            for (final chapitre in chapitres)
              chapitre.idSource == null
                  ? chapitre.copierAvec(idSource: idSource)
                  : chapitre,
          ];

    final idsTitres = <int>{};
    // Couples (titre, source) explicites, à vérifier dans titres_sources.
    final sitesAVerifier = <(int, int)>{};
    // Couples ayant au moins un chapitre d'origine 'site' : ceux-là seuls
    // sont refusés sur un lien seul (migration 13).
    final sitesAvecChapitresSite = <(int, int)>{};
    for (final chapitre in aEnregistrer) {
      final idTitre = chapitre.idTitre;
      if (idTitre == null) {
        throw ErreurBaseDeDonnees(
          'Le chapitre « ${chapitre.nom} » (${chapitre.urlChapitre}) n\'a pas '
          'de titre : idTitre est requis pour l\'enregistrer.',
        );
      }
      idsTitres.add(idTitre);
      final idSourceChapitre = chapitre.idSource;
      if (idSourceChapitre != null) {
        sitesAVerifier.add((idTitre, idSourceChapitre));
        if (chapitre.origine == OrigineChapitre.site) {
          sitesAvecChapitresSite.add((idTitre, idSourceChapitre));
        }
      }
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
        // Un chapitre ne peut venir que d'un site lié au titre : sinon il
        // ne serait ni affiché avec un site connu, ni supprimé au retrait
        // du site. Recherche servie par l'index UNIQUE (id_titre, id_source).
        for (final (idTitre, idSourceChapitre) in sitesAVerifier) {
          final liens = await txn.query(
            'titres_sources',
            columns: <String>['lien_seul'],
            where: 'id_titre = ? AND id_source = ?',
            whereArgs: <Object?>[idTitre, idSourceChapitre],
            limit: 1,
          );
          if (liens.isEmpty) {
            throw ErreurBaseDeDonnees(
              "Impossible d'enregistrer les chapitres : la source "
              "n°$idSourceChapitre n'est pas un site du titre n°$idTitre.",
            );
          }
          // Un lien seul (migration 8) n'est jamais lu : aucun chapitre
          // d'origine 'site' ne peut en venir (les chapitres 'web' le
          // peuvent, migration 13).
          if (liens.first['lien_seul'] == valeurSqlVrai &&
              sitesAvecChapitresSite.contains((idTitre, idSourceChapitre))) {
            throw ErreurBaseDeDonnees(
              "Impossible d'enregistrer les chapitres : la source "
              "n°$idSourceChapitre est un lien seul pour le titre n°$idTitre "
              "(l'application n'y lit aucun chapitre).",
            );
          }
        }
        final nouveaux = await _insererChapitres(txn, aEnregistrer, detection);
        await _mettreAJourUrlsExternes(txn, aEnregistrer);
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
  /// Un chapitre enregistré depuis le web ([OrigineChapitre.web]) n'est
  /// jamais modifié par l'actualisation d'un site.
  Future<void> _mettreAJourUrlsExternes(
    Transaction txn,
    List<Chapitre> chapitres,
  ) async {
    for (final chapitre in chapitres) {
      final urlExterne = _normaliserUrlExterne(chapitre.urlExterne);
      await txn.rawUpdate(
        'UPDATE chapitres SET url_externe = ? '
        'WHERE url_chapitre = ? AND id_titre = ? AND url_externe IS NOT ? '
        'AND origine != ?',
        <Object?>[
          urlExterne,
          chapitre.urlChapitre,
          chapitre.idTitre,
          urlExterne,
          OrigineChapitre.web.name,
        ],
      );
    }
  }

  /// Enregistre le chapitre que le client lit dans le navigateur intégré sur
  /// le site [idSource] du titre [idTitre], et le renvoie (tel qu'en base).
  ///
  /// Sert surtout aux sites en « lien seul », que l'application ne sait pas
  /// lire : le chapitre est enregistré avec [OrigineChapitre.web], accepté
  /// sur un lien seul (migration 13) et jamais supprimé ni modifié par une
  /// actualisation depuis le site. Le site doit être lié au titre
  /// (`titres_sources`), en lien seul ou non.
  ///
  /// Idempotent : si le titre a déjà, pour ce site, un chapitre de même
  /// adresse (`url_chapitre` ou `url_externe`, comparées après
  /// [normaliserUrlChapitre]) ou, à défaut, de même [numero], ce chapitre
  /// est renvoyé **sans modification** (quelle que soit son origine), et
  /// rien n'est écrit. Le marquer lu ou enregistrer son archive se fait
  /// ensuite avec [marquerLu] et [enregistrerArchive].
  ///
  /// Valeurs enregistrées pour un nouveau chapitre :
  /// - `url_chapitre` : [url] sans espaces autour ni fragment (`#…`) ;
  /// - `nom` : [titre] s'il n'est pas vide, sinon « Chapitre `numero` » ;
  /// - `langue` : [langue] si elle n'est pas vide, sinon la langue par
  ///   défaut de la source (PLAYBOOK.md section 5) ;
  /// - `date_detection` : [dateDetection], par défaut maintenant.
  ///
  /// Lève une [ArgumentError] si [url] est vide ou si [numero] n'est pas un
  /// nombre fini, une [ErreurBaseDeDonnees] si le titre n'existe pas, si le
  /// site n'est pas lié au titre, si cette adresse est déjà celle d'un
  /// chapitre d'un **autre** titre (`url_chapitre` est UNIQUE), ou si
  /// l'écriture échoue.
  Future<Chapitre> enregistrerChapitreWeb(
    int idTitre,
    int idSource, {
    required double numero,
    required String url,
    String? titre,
    String? langue,
    DateTime? dateDetection,
  }) async {
    if (!numero.isFinite) {
      throw ArgumentError.value(numero, 'numero', 'doit être un nombre fini');
    }
    final adresseNormalisee = normaliserUrlChapitre(url);
    if (adresseNormalisee.isEmpty) {
      throw ArgumentError.value(url, 'url', 'ne doit pas être vide');
    }
    var adresse = url.trim();
    final diese = adresse.indexOf('#');
    if (diese >= 0) {
      adresse = adresse.substring(0, diese);
    }
    final detection = dateDetection ?? DateTime.now().toUtc();

    try {
      return await _baseDeDonnees.transaction((txn) async {
        final titres = await txn.query(
          'titres',
          columns: <String>['id'],
          where: 'id = ?',
          whereArgs: <Object?>[idTitre],
          limit: 1,
        );
        if (titres.isEmpty) {
          throw ErreurBaseDeDonnees(
            "Impossible d'enregistrer le chapitre : le titre n°$idTitre "
            "n'existe pas.",
          );
        }
        // Recherche servie par l'index UNIQUE (id_titre, id_source).
        final liens = await txn.query(
          'titres_sources',
          columns: <String>['id'],
          where: 'id_titre = ? AND id_source = ?',
          whereArgs: <Object?>[idTitre, idSource],
          limit: 1,
        );
        if (liens.isEmpty) {
          throw ErreurBaseDeDonnees(
            "Impossible d'enregistrer le chapitre : la source n°$idSource "
            "n'est pas un site du titre n°$idTitre.",
          );
        }

        // 1. Même adresse exacte, tous titres confondus (index UNIQUE de
        //    url_chapitre) : un même chapitre, ou un conflit avec un autre
        //    titre que la contrainte UNIQUE refuserait.
        final memeAdresse = await txn.query(
          'chapitres',
          where: 'url_chapitre = ?',
          whereArgs: <Object?>[adresse],
          limit: 1,
        );
        if (memeAdresse.isNotEmpty) {
          final existant = Chapitre.depuisMap(memeAdresse.first);
          if (existant.idTitre == idTitre) {
            return existant;
          }
          throw ErreurBaseDeDonnees(
            "Impossible d'enregistrer le chapitre : l'adresse « $adresse » "
            'est déjà celle d\'un chapitre du titre n°${existant.idTitre}.',
          );
        }

        // 2. Même adresse normalisée, ou à défaut même numéro, parmi les
        //    chapitres de ce site pour ce titre (index
        //    index_chapitres_titre_source) ; l'adresse l'emporte sur le
        //    numéro, puis le plus ancien.
        final connus = await txn.rawQuery(
          'SELECT * FROM chapitres '
          'WHERE id_titre = ? AND id_source = ? '
          'AND (${_sqlUrlNormalisee('url_chapitre')} = ? '
          'OR ${_sqlUrlNormalisee('url_externe')} = ? OR numero = ?) '
          'ORDER BY CASE WHEN ${_sqlUrlNormalisee('url_chapitre')} = ? '
          'OR ${_sqlUrlNormalisee('url_externe')} = ? '
          'THEN 0 ELSE 1 END, id '
          'LIMIT 1',
          <Object?>[
            idTitre,
            idSource,
            adresseNormalisee,
            adresseNormalisee,
            numero,
            adresseNormalisee,
            adresseNormalisee,
          ],
        );
        if (connus.isNotEmpty) {
          return Chapitre.depuisMap(connus.first);
        }

        // 3. Nouveau chapitre.
        var langueChapitre = langue?.trim() ?? '';
        if (langueChapitre.isEmpty) {
          final sources = await txn.query(
            'sources',
            columns: <String>['langue_par_defaut'],
            where: 'id = ?',
            whereArgs: <Object?>[idSource],
            limit: 1,
          );
          final defaut = sources.isEmpty
              ? null
              : sources.first['langue_par_defaut'];
          langueChapitre = defaut is String ? defaut.trim() : '';
        }
        final nomSaisi = titre?.trim() ?? '';
        final chapitre = Chapitre(
          idTitre: idTitre,
          idSource: idSource,
          urlChapitre: adresse,
          nom: nomSaisi.isEmpty ? 'Chapitre ${_texteNumero(numero)}' : nomSaisi,
          numero: numero,
          langue: langueChapitre,
          dateDetection: detection,
          origine: OrigineChapitre.web,
        );
        final id = await txn.insert(
          'chapitres',
          chapitre.versMap()..remove('id'),
        );
        // Relu en base : les dates y sont arrondies à la milliseconde, le
        // chapitre renvoyé est donc égal à celui que chargerChapitre donnera.
        final lignes = await txn.query(
          'chapitres',
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        return Chapitre.depuisMap(lignes.single);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible d'enregistrer le chapitre ${_texteNumero(numero)} lu sur "
        'le web pour le titre n°$idTitre.',
        cause: erreur,
      );
    }
  }

  /// Charge le chapitre dont l'adresse correspond à [url], ou `null` ; si
  /// [idTitre] est donné, seulement parmi les chapitres de ce titre.
  ///
  /// Sert au navigateur intégré à reconnaître un chapitre déjà connu
  /// (état lu, archive) à partir de la page affichée. Sont comparées
  /// `url_chapitre` et `url_externe`, après [normaliserUrlChapitre] des deux
  /// côtés (sans fragment, sans `/` final). Si plusieurs chapitres
  /// correspondent, le plus ancien (plus petit `id`) est renvoyé.
  ///
  /// Une première recherche exacte (adresse normalisée, avec ou sans `/`
  /// final) passe par l'index UNIQUE de `url_chapitre`. Sinon, la
  /// comparaison normalisée parcourt les chapitres du titre (index
  /// `index_chapitres_titre_lu`) ou, sans [idTitre], toute la table
  /// (LIMITE : acceptable pour une recherche faite à chaque page, la table
  /// restant de l'ordre de quelques dizaines de milliers de lignes).
  Future<Chapitre?> chargerChapitreParUrl(String url, {int? idTitre}) async {
    final adresse = normaliserUrlChapitre(url);
    if (adresse.isEmpty) {
      return null;
    }
    final filtreTitre = idTitre == null ? '' : ' AND id_titre = ?';
    final exacts = await _baseDeDonnees.query(
      'chapitres',
      where: 'url_chapitre IN (?, ?)$filtreTitre',
      whereArgs: <Object?>[adresse, '$adresse/', ?idTitre],
      orderBy: 'id',
      limit: 1,
    );
    if (exacts.isNotEmpty) {
      return Chapitre.depuisMap(exacts.first);
    }
    final lignes = await _baseDeDonnees.rawQuery(
      'SELECT * FROM chapitres '
      'WHERE (${_sqlUrlNormalisee('url_chapitre')} = ? '
      'OR ${_sqlUrlNormalisee('url_externe')} = ?)$filtreTitre '
      'ORDER BY id LIMIT 1',
      <Object?>[adresse, adresse, ?idTitre],
    );
    return lignes.isEmpty ? null : Chapitre.depuisMap(lignes.first);
  }

  /// Lien externe sans espaces autour, ou `null` s'il est absent ou vide
  /// (un lien vide signifie « hébergé par le site source »).
  static String? _normaliserUrlExterne(String? urlExterne) {
    final url = urlExterne?.trim();
    return url == null || url.isEmpty ? null : url;
  }

  /// Charge les chapitres d'un titre, triés par numéro croissant ; si
  /// [idSource] est donné, seulement ceux venant de ce site.
  ///
  /// Chaque chapitre porte son site d'origine ([Chapitre.idSource]) : un
  /// même numéro peut donc apparaître une fois par site. À numéro égal,
  /// l'ordre est celui d'insertion. Sans filtre, la requête est servie par
  /// `index_chapitres_titre_lu` ; avec filtre, par
  /// `index_chapitres_titre_source` (migration 7).
  Future<List<Chapitre>> chargerChapitres(int idTitre, {int? idSource}) async {
    final lignes = await _baseDeDonnees.query(
      'chapitres',
      where: idSource == null
          ? 'id_titre = ?'
          : 'id_titre = ? AND id_source = ?',
      whereArgs: <Object?>[idTitre, ?idSource],
      orderBy: 'numero, id',
    );
    return lignes.map(Chapitre.depuisMap).toList();
  }

  /// Supprime les chapitres du titre [idTitre] venant de la source
  /// [idSource] qui ne sont ni lus, ni téléchargés, ni gardés, ni en cours
  /// de téléchargement, et renvoie leur nombre (voir
  /// [supprimerChapitresNonConservesSource]).
  ///
  /// Sert au retrait d'un site secondaire ; `DepotTitresSources
  /// .retirerSourceSecondaire` l'appelle déjà dans sa transaction.
  Future<int> supprimerChapitresNonConserves(int idTitre, int idSource) async {
    try {
      return await _baseDeDonnees.transaction(
        (txn) => supprimerChapitresNonConservesSource(txn, idTitre, idSource),
      );
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible de supprimer les chapitres de la source n°$idSource "
        'pour le titre n°$idTitre.',
        cause: erreur,
      );
    }
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

  /// Marque les chapitres [idsChapitres] comme lus (ou non lus si [lu] vaut
  /// `false`), en une transaction, et renvoie le nombre de chapitres dont
  /// l'état a **changé**.
  ///
  /// Comme [marquerLu], seule la colonne `est_lu` est écrite (le schéma ne
  /// garde pas de date de lecture). Les chapitres déjà dans l'état demandé
  /// ne sont pas réécrits (`est_lu != ?`) et ne sont pas comptés ; les
  /// identifiants inconnus et les doublons sont ignorés. Les identifiants
  /// sont découpés en lots de [tailleMaxLotParametresSql] paramètres (limite
  /// de 999 paramètres des anciens SQLite d'Android) ; la recherche passe
  /// par la clé primaire.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`) ;
  /// `null` : transaction propre à cet appel. Lève une
  /// [ErreurBaseDeDonnees] si l'écriture échoue (rien n'est alors écrit
  /// sans transaction extérieure).
  Future<int> marquerLus(
    Iterable<int> idsChapitres, {
    bool lu = true,
    DatabaseExecutor? executeur,
  }) async {
    final ids = idsChapitres.toSet().toList();
    if (ids.isEmpty) {
      return 0;
    }
    final valeur = booleenVersEntier(lu);
    try {
      return await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        (txn) async {
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
            // Seuls des `?` sont générés ; les identifiants sont des
            // paramètres.
            final marqueurs = List<String>.filled(lot.length, '?').join(', ');
            nombre += await txn.rawUpdate(
              'UPDATE chapitres SET est_lu = ? '
              'WHERE id IN ($marqueurs) AND est_lu != ?',
              <Object?>[valeur, ...lot, valeur],
            );
          }
          return nombre;
        },
      );
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible d'enregistrer l'état de lecture de ${ids.length} "
        'chapitre(s).',
        cause: erreur,
      );
    }
  }

  /// Marque comme lus (ou non lus si [lu] vaut `false`) tous les chapitres
  /// du titre [idTitre] dont le numéro est inférieur ou égal à [numero], et
  /// renvoie le nombre de chapitres dont l'état a **changé**.
  ///
  /// Les chapitres de numéro 0 (oneshots, chapitres sans numéro) ne sont
  /// concernés que si [numero] vaut 0 : « jusqu'au chapitre 5 » ne marque pas
  /// un oneshot.
  ///
  /// Toutes les langues et tous les sites du titre sont concernés, chapitres
  /// externes ([Chapitre.urlExterne]) compris. Comme [marquerLus], seule la
  /// colonne `est_lu` est écrite, et les chapitres déjà dans l'état demandé
  /// ne sont ni réécrits ni comptés. Une seule requête `UPDATE … WHERE`,
  /// servie par `index_chapitres_titre_lu` (id_titre, est_lu) ; la
  /// comparaison du numéro est faite sur les lignes du titre seulement.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`) ;
  /// `null` : transaction propre à cet appel. Lève une
  /// [ErreurBaseDeDonnees] si l'écriture échoue, une [ArgumentError] si
  /// [numero] n'est pas un nombre fini.
  Future<int> marquerLusJusqua(
    int idTitre,
    double numero, {
    bool lu = true,
    DatabaseExecutor? executeur,
  }) async {
    if (!numero.isFinite) {
      throw ArgumentError.value(numero, 'numero', 'doit être un nombre fini');
    }
    final valeur = booleenVersEntier(lu);
    try {
      return await GestionnaireTransactions.executerAtomiquement(
        _baseDeDonnees,
        executeur,
        // Numéro 0 = oneshot ou chapitre sans numéro : il n'est pas « avant »
        // le chapitre 1, donc exclu quand numero > 0. Avec numero == 0 (ou
        // négatif), la borne basse 0 n'exclut rien de plus que `numero <= ?`.
        (txn) => txn.rawUpdate(
          'UPDATE chapitres SET est_lu = ? '
          'WHERE id_titre = ? AND est_lu != ? AND numero <= ? '
          'AND (? <= 0 OR numero > 0)',
          <Object?>[valeur, idTitre, valeur, numero, numero],
        ),
      );
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible d'enregistrer l'état de lecture des chapitres du titre "
        'n°$idTitre.',
        cause: erreur,
      );
    }
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

  /// Remet **tous** les chapitres à « non téléchargé », en une seule
  /// transaction, et renvoie le nombre de chapitres modifiés (`chapitres`)
  /// et de lignes retirées de la file (`telechargements`).
  ///
  /// Sert à la désinstallation partielle (« supprimer les chapitres
  /// téléchargés »), une fois les archives effacées par le désinstalleur.
  /// Comme [enregistrerArchive] avec `null` : `est_telecharge` = 0,
  /// `nom_archive` et `date_suppression_prevue` à NULL, `est_garde` = 0 (un
  /// chapitre sans archive n'a rien à garder). L'état de lecture (`est_lu`)
  /// et les chapitres eux-mêmes ne sont pas touchés. Seules les lignes à
  /// changer sont réécrites (et comptées).
  ///
  /// [viderFile] (vrai par défaut) : la file `telechargements` est aussi
  /// vidée, tous statuts confondus. Sinon, la reprise au démarrage
  /// retéléchargerait les chapitres en attente, et les lignes « terminé »
  /// désigneraient des archives effacées.
  ///
  /// Pas d'index sur ces colonnes (voir [chargerChapitresTelecharges]) : la
  /// requête parcourt la table, opération rare. Lève une
  /// [ErreurBaseDeDonnees] si l'écriture échoue (rien n'est alors modifié).
  Future<({int chapitres, int telechargements})> marquerTousNonTelecharges({
    bool viderFile = true,
  }) async {
    try {
      return await _baseDeDonnees.transaction((txn) async {
        final chapitres = await txn.rawUpdate(
          'UPDATE chapitres SET est_telecharge = ?, nom_archive = NULL, '
          'date_suppression_prevue = NULL, est_garde = ? '
          'WHERE est_telecharge != ? OR nom_archive IS NOT NULL '
          'OR date_suppression_prevue IS NOT NULL OR est_garde != ?',
          <Object?>[valeurSqlFaux, valeurSqlFaux, valeurSqlFaux, valeurSqlFaux],
        );
        final telechargements = viderFile
            ? await txn.delete('telechargements')
            : 0;
        return (chapitres: chapitres, telechargements: telechargements);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible de remettre à zéro l'état téléchargé des chapitres.",
        cause: erreur,
      );
    }
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
