/// Dépôt des fichiers importés (CBZ, PDF, EPUB : migration 15).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/fichier_importe.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import 'depot_titres.dart';
import 'gestionnaire_transactions.dart';

/// Résultat d'un import enregistré : le titre créé, son unique chapitre et
/// la description du fichier.
typedef ImportEnregistre = ({
  Titre titre,
  Chapitre chapitre,
  FichierImporte fichier,
});

/// Accès aux fichiers importés et à la source système « Fichiers locaux ».
///
/// Un fichier importé = un titre de la source « Fichiers locaux » + un
/// chapitre (numéro 1) dont `nom_archive` est le chemin relatif du fichier
/// copié par `StockageTelechargements.importerFichier` + une ligne de
/// `fichiers_importes`. Supprimer le titre (`DepotTitres.supprimerTitre`)
/// supprime le reste par cascade ; le fichier sur le disque est supprimé par
/// la couche services (`StockageTelechargements.supprimerFichierImporte`).
class DepotFichiersImportes {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotFichiersImportes(this._baseDeDonnees);

  final Database _baseDeDonnees;

  // Empreinte SHA-256 en hexadécimal minuscule.
  static final RegExp _empreinteValide = RegExp(r'^[0-9a-f]{64}$');

  /// Adresse du titre créé pour le fichier d'empreinte [empreinteSha256]
  /// (`local://fichiers-locaux/<empreinte>`) : unique, stable, jamais une
  /// adresse web.
  static String urlTitreImporte(String empreinteSha256) =>
      '$urlBaseFichiersLocaux/$empreinteSha256';

  /// Adresse du chapitre du fichier d'empreinte [empreinteSha256].
  static String urlChapitreImporte(String empreinteSha256) =>
      '${urlTitreImporte(empreinteSha256)}/fichier';

  /// Renvoie la source système « Fichiers locaux », créée (inactive) si
  /// elle n'existe pas encore.
  ///
  /// [executeur] : transaction en cours (voir `GestionnaireTransactions`).
  Future<Source> chargerOuCreerSourceFichiersLocaux({
    DatabaseExecutor? executeur,
  }) {
    return GestionnaireTransactions.executerAtomiquement(
      _baseDeDonnees,
      executeur,
      (txn) async {
        final lignes = await txn.query(
          'sources',
          where: 'url_base = ?',
          whereArgs: <Object?>[urlBaseFichiersLocaux],
          limit: 1,
        );
        if (lignes.isNotEmpty) return Source.depuisMap(lignes.first);
        // Type « generique » : simple valeur permise par le modèle ; la
        // source est reconnue à son adresse (Source.estFichiersLocaux).
        const source = Source(
          nom: nomSourceFichiersLocaux,
          urlBase: urlBaseFichiersLocaux,
          typeSource: TypeSource.generique,
          estActive: false,
        );
        final id = await txn.insert('sources', source.versMap());
        return source.copierAvec(id: id);
      },
    );
  }

  /// Fichier importé d'empreinte [empreinteSha256], ou `null` : à appeler
  /// **avant** la copie pour refuser un doublon (même contenu, même
  /// renommé). Servie par l'index UNIQUE de `empreinte_sha256`.
  Future<FichierImporte?> chargerParEmpreinte(
    String empreinteSha256, {
    DatabaseExecutor? executeur,
  }) async {
    final lignes = await (executeur ?? _baseDeDonnees).query(
      'fichiers_importes',
      where: 'empreinte_sha256 = ?',
      whereArgs: <Object?>[empreinteSha256.toLowerCase()],
      limit: 1,
    );
    return lignes.isEmpty ? null : FichierImporte.depuisMap(lignes.first);
  }

  /// Fichier importé du chapitre [idChapitre], ou `null` si ce chapitre
  /// n'est pas un fichier importé.
  Future<FichierImporte?> chargerFichierImporte(int idChapitre) async {
    final lignes = await _baseDeDonnees.query(
      'fichiers_importes',
      where: 'id_chapitre = ?',
      whereArgs: <Object?>[idChapitre],
      limit: 1,
    );
    return lignes.isEmpty ? null : FichierImporte.depuisMap(lignes.first);
  }

  /// Tous les fichiers importés, du plus récent au plus ancien.
  Future<List<FichierImporte>> chargerFichiersImportes() async {
    final lignes = await _baseDeDonnees.query(
      'fichiers_importes',
      orderBy: 'date_import DESC, id_chapitre DESC',
    );
    return lignes.map(FichierImporte.depuisMap).toList();
  }

  /// Identifiants des chapitres qui sont des fichiers importés : à exclure
  /// de toute règle de conservation, de tout retéléchargement et de toute
  /// suppression automatique (couche services).
  Future<Set<int>> chargerIdsChapitresImportes() async {
    final lignes = await _baseDeDonnees.query(
      'fichiers_importes',
      columns: <String>['id_chapitre'],
    );
    return <int>{for (final ligne in lignes) ligne['id_chapitre']! as int};
  }

  /// Enregistre, en une seule transaction, le titre, le chapitre et la
  /// description d'un fichier **déjà copié** dans la bibliothèque
  /// ([nomArchive] : valeur renvoyée par
  /// `StockageTelechargements.importerFichier`).
  ///
  /// Le titre est de type [typeTitre] (par défaut
  /// [FormatFichierLocal.typeTitreParDefaut]) et porte la source « Fichiers
  /// locaux » (créée au besoin). Le chapitre (numéro 1, nommé [nom]) est
  /// téléchargé (`est_telecharge = 1`) et gardé (`est_garde = 1`) : les
  /// règles de conservation l'ignorent, et un déclencheur de la migration
  /// 15 refuse toute suppression prévue sur lui.
  ///
  /// Lève une [ArgumentError] si [nom] est vide ou si [empreinteSha256]
  /// n'est pas 64 chiffres hexadécimaux, et une [ErreurBaseDeDonnees] si ce
  /// contenu est déjà importé ou si l'écriture échoue (rien n'est écrit ;
  /// l'appelant supprime alors le fichier copié).
  Future<ImportEnregistre> enregistrerImport({
    required String nom,
    required FormatFichierLocal format,
    required String empreinteSha256,
    required int taille,
    required String nomOrigine,
    required String nomArchive,
    TypeTitre? typeTitre,
    String langue = '',
    String? auteur,
    DateTime? dateImport,
  }) async {
    final nomPropre = nom.trim();
    if (nomPropre.isEmpty) {
      throw ArgumentError.value(nom, 'nom', 'ne doit pas être vide');
    }
    final empreinte = empreinteSha256.toLowerCase();
    if (!_empreinteValide.hasMatch(empreinte)) {
      throw ArgumentError.value(
        empreinteSha256,
        'empreinteSha256',
        'doit contenir 64 chiffres hexadécimaux',
      );
    }
    final date = (dateImport ?? DateTime.now()).toUtc();
    try {
      return await _baseDeDonnees.transaction((txn) async {
        final existant = await chargerParEmpreinte(empreinte, executeur: txn);
        if (existant != null) {
          throw ErreurBaseDeDonnees(
            'Ce fichier est déjà dans la bibliothèque (importé sous le nom '
            '« ${existant.nomOrigine} »).',
          );
        }
        final source = await chargerOuCreerSourceFichiersLocaux(executeur: txn);
        final titre = await DepotTitres(_baseDeDonnees).enregistrerTitre(
          Titre(
            idSource: source.id,
            urlTitre: urlTitreImporte(empreinte),
            nom: nomPropre,
            typeTitre: typeTitre ?? format.typeTitreParDefaut,
            auteur: auteur,
            dateDerniereVerification: date,
          ),
          executeur: txn,
        );
        final chapitre = Chapitre(
          idTitre: titre.id,
          idSource: source.id,
          urlChapitre: urlChapitreImporte(empreinte),
          nom: nomPropre,
          numero: 1,
          langue: langue,
          estTelecharge: true,
          dateDetection: date,
          nomArchive: nomArchive,
          estGarde: true,
        );
        final idChapitre = await txn.insert('chapitres', chapitre.versMap());
        final fichier = FichierImporte(
          idChapitre: idChapitre,
          format: format,
          empreinteSha256: empreinte,
          taille: taille,
          nomOrigine: nomOrigine,
          dateImport: date,
        );
        await txn.insert('fichiers_importes', fichier.versMap());
        return (
          titre: titre,
          chapitre: chapitre.copierAvec(id: idChapitre),
          fichier: fichier,
        );
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible d'enregistrer le fichier importé « $nomOrigine ».",
        cause: erreur,
      );
    }
  }
}
