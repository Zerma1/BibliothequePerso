/// Dépôt des sites d'un titre (étape 8 : plusieurs sites pour un même titre).
library;

import 'package:sqflite/sqflite.dart';

import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/lien_titre_source.dart';
import '../modeles/titre.dart';
import 'depot_chapitres.dart';
import 'depot_titres.dart';

/// Accès à la table `titres_sources` (migration 7).
///
/// Chaque titre a un site **principal** (`est_principale = 1`), recopié dans
/// `titres.id_source` / `titres.url_titre`, et zéro ou plusieurs sites
/// **secondaires**. La ligne principale est créée et tenue à jour par des
/// déclencheurs SQL à chaque écriture dans `titres` : ce dépôt ne gère que
/// les sites secondaires et le changement de site principal.
class DepotTitresSources {
  /// Crée le dépôt sur une base déjà ouverte.
  const DepotTitresSources(this._baseDeDonnees);

  final Database _baseDeDonnees;

  /// Charge les sites d'un titre : le principal d'abord, puis les
  /// secondaires dans l'ordre d'ajout. Liste vide si le titre n'existe pas.
  ///
  /// Requête servie par l'index UNIQUE (id_titre, id_source).
  Future<List<LienTitreSource>> chargerLiensTitre(int idTitre) async {
    final lignes = await _baseDeDonnees.query(
      'titres_sources',
      where: 'id_titre = ?',
      whereArgs: <Object?>[idTitre],
      orderBy: 'est_principale DESC, date_ajout, id',
    );
    return lignes.map(LienTitreSource.depuisMap).toList();
  }

  /// Charge le site principal d'un titre, ou `null` si le titre n'existe
  /// pas.
  Future<LienTitreSource?> chargerLienPrincipal(int idTitre) async {
    final lignes = await _baseDeDonnees.query(
      'titres_sources',
      where: 'id_titre = ? AND est_principale = ?',
      whereArgs: <Object?>[idTitre, valeurSqlVrai],
      limit: 1,
    );
    return lignes.isEmpty ? null : LienTitreSource.depuisMap(lignes.first);
  }

  /// Charge le lien dont l'URL est [urlTitre] (site principal ou
  /// secondaire de n'importe quel titre), ou `null`.
  ///
  /// Comparaison exacte après retrait des espaces autour, comme à
  /// l'enregistrement. Requête servie par l'index UNIQUE de `url_titre`.
  Future<LienTitreSource?> chargerLienParUrl(String urlTitre) async {
    final lignes = await _baseDeDonnees.query(
      'titres_sources',
      where: 'url_titre = ?',
      whereArgs: <Object?>[urlTitre.trim()],
      limit: 1,
    );
    return lignes.isEmpty ? null : LienTitreSource.depuisMap(lignes.first);
  }

  /// Charge le titre dont l'un des sites (principal ou secondaire) a l'URL
  /// [urlTitre], ou `null`.
  ///
  /// `DepotTitres.chargerTitreParUrl` ne cherche que dans le site principal.
  Future<Titre?> chargerTitreParUrl(String urlTitre) async {
    final lien = await chargerLienParUrl(urlTitre);
    if (lien == null) {
      return null;
    }
    return DepotTitres(_baseDeDonnees).chargerTitre(lien.idTitre);
  }

  /// Ajoute un site secondaire au titre [idTitre] : la source [idSource], où
  /// le titre se trouve à l'adresse [urlTitre]. Renvoie le lien enregistré.
  ///
  /// [dateAjout] vaut maintenant par défaut. Lève une [ArgumentError] si
  /// [urlTitre] est vide, et une [ErreurBaseDeDonnees] au message clair si :
  /// - le titre ou la source n'existe pas ;
  /// - l'adresse est déjà celle d'un site d'un **autre** titre ;
  /// - l'adresse ou le site est déjà lié à **ce** titre.
  ///
  /// Aucune requête réseau : vérifier que l'adresse est bien un titre du
  /// site est le rôle de la couche services.
  Future<LienTitreSource> ajouterSourceSecondaire(
    int idTitre,
    int idSource,
    String urlTitre, {
    DateTime? dateAjout,
  }) async {
    final url = urlTitre.trim();
    if (url.isEmpty) {
      throw ArgumentError.value(urlTitre, 'urlTitre', 'ne doit pas être vide');
    }
    final lien = LienTitreSource(
      idTitre: idTitre,
      idSource: idSource,
      urlTitre: url,
      dateAjout: (dateAjout ?? DateTime.now()).toUtc(),
    );
    try {
      return await _baseDeDonnees.transaction((txn) async {
        final nomTitre = await _chargerNomTitre(txn, idTitre);
        if (nomTitre == null) {
          throw ErreurBaseDeDonnees(
            "Impossible d'ajouter un site : le titre n°$idTitre n'existe pas.",
          );
        }
        final nomSource = await _chargerNomSource(txn, idSource);
        if (nomSource == null) {
          throw ErreurBaseDeDonnees(
            "Impossible d'ajouter un site : la source n°$idSource n'existe "
            'pas.',
          );
        }

        // Vérifications explicites avant l'insertion : les contraintes
        // UNIQUE restent le filet de sécurité, mais sqflite ne dit pas
        // laquelle a échoué.
        final memeUrl = await txn.rawQuery(
          'SELECT ts.id_titre, t.nom FROM titres_sources ts '
          'JOIN titres t ON t.id = ts.id_titre '
          'WHERE ts.url_titre = ? LIMIT 1',
          <Object?>[url],
        );
        if (memeUrl.isNotEmpty) {
          final idAutre = memeUrl.first['id_titre'];
          if (idAutre == idTitre) {
            throw ErreurBaseDeDonnees(
              "L'adresse « $url » est déjà un site du titre « $nomTitre ».",
            );
          }
          throw ErreurBaseDeDonnees(
            "L'adresse « $url » est déjà utilisée par un autre titre : "
            "« ${memeUrl.first['nom']} ».",
          );
        }
        final memeSource = await txn.query(
          'titres_sources',
          columns: <String>['url_titre'],
          where: 'id_titre = ? AND id_source = ?',
          whereArgs: <Object?>[idTitre, idSource],
          limit: 1,
        );
        if (memeSource.isNotEmpty) {
          throw ErreurBaseDeDonnees(
            "Le site « $nomSource » est déjà lié au titre « $nomTitre » "
            "(adresse « ${memeSource.first['url_titre']} »).",
          );
        }

        final ligne = lien.versMap()..remove('id');
        final id = await txn.insert('titres_sources', ligne);
        return lien.copierAvec(id: id);
      });
    } on DatabaseException catch (erreur) {
      if (erreur.isUniqueConstraintError()) {
        throw ErreurBaseDeDonnees(
          "L'adresse « $url » ou ce site est déjà lié à un titre.",
          cause: erreur,
        );
      }
      throw ErreurBaseDeDonnees(
        "Impossible d'ajouter le site n°$idSource au titre n°$idTitre.",
        cause: erreur,
      );
    }
  }

  /// Retire le site secondaire [idSource] du titre [idTitre] et supprime, dans
  /// la même transaction, ses chapitres non lus, non téléchargés, non gardés
  /// et sans téléchargement en cours (voir
  /// [supprimerChapitresNonConservesSource]). Renvoie le nombre de
  /// chapitres supprimés.
  ///
  /// Les chapitres lus ou téléchargés de ce site restent, avec leur
  /// `id_source` ; la suppression des archives (règle des 24 h) est le rôle
  /// de la couche services.
  ///
  /// Lève une [ErreurBaseDeDonnees] si ce site n'est pas lié au titre, ou
  /// s'il est son site principal (définir d'abord un autre site principal
  /// avec [definirSourcePrincipale]).
  Future<int> retirerSourceSecondaire(int idTitre, int idSource) async {
    try {
      return await _baseDeDonnees.transaction((txn) async {
        final lien = await _chargerLien(txn, idTitre, idSource);
        if (lien == null) {
          throw ErreurBaseDeDonnees(
            "La source n°$idSource n'est pas un site du titre n°$idTitre.",
          );
        }
        if (lien.estPrincipale) {
          throw const ErreurBaseDeDonnees(
            "Le site principal d'un titre ne peut pas être retiré : "
            "choisissez d'abord un autre site principal.",
          );
        }
        await txn.delete(
          'titres_sources',
          where: 'id = ?',
          whereArgs: <Object?>[lien.id],
        );
        return supprimerChapitresNonConservesSource(txn, idTitre, idSource);
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible de retirer le site n°$idSource du titre n°$idTitre.",
        cause: erreur,
      );
    }
  }

  /// Fait du site [idSource], déjà lié au titre [idTitre], son site
  /// principal ; l'ancien principal devient secondaire.
  ///
  /// `titres.id_source` et `titres.url_titre` sont mis à jour dans la même
  /// transaction (le déclencheur de la migration 7 garde alors
  /// `titres_sources` en accord). Les chapitres gardent leur site d'origine.
  /// Ne fait rien si ce site est déjà le principal. Lève une
  /// [ErreurBaseDeDonnees] si ce site n'est pas lié au titre.
  ///
  /// La fiche (nom, couverture, résumé…) n'est pas modifiée ici : la couche
  /// services la récupère depuis le nouveau site principal si besoin.
  Future<void> definirSourcePrincipale(int idTitre, int idSource) async {
    try {
      await _baseDeDonnees.transaction((txn) async {
        final lien = await _chargerLien(txn, idTitre, idSource);
        if (lien == null) {
          throw ErreurBaseDeDonnees(
            "La source n°$idSource n'est pas un site du titre n°$idTitre.",
          );
        }
        if (lien.estPrincipale) {
          return;
        }
        // Ordre imposé par l'index UNIQUE partiel (un seul principal) :
        // l'ancien principal est d'abord rétrogradé.
        await txn.update(
          'titres_sources',
          <String, Object?>{'est_principale': valeurSqlFaux},
          where: 'id_titre = ? AND est_principale = ?',
          whereArgs: <Object?>[idTitre, valeurSqlVrai],
        );
        await txn.update(
          'titres_sources',
          <String, Object?>{'est_principale': valeurSqlVrai},
          where: 'id = ?',
          whereArgs: <Object?>[lien.id],
        );
        await txn.update(
          'titres',
          <String, Object?>{
            'id_source': lien.idSource,
            'url_titre': lien.urlTitre,
          },
          where: 'id = ?',
          whereArgs: <Object?>[idTitre],
        );
      });
    } on DatabaseException catch (erreur) {
      throw ErreurBaseDeDonnees(
        "Impossible de définir le site n°$idSource comme site principal du "
        'titre n°$idTitre.',
        cause: erreur,
      );
    }
  }

  /// Lien (titre, source) lu dans [executeur], ou `null`.
  static Future<LienTitreSource?> _chargerLien(
    DatabaseExecutor executeur,
    int idTitre,
    int idSource,
  ) async {
    final lignes = await executeur.query(
      'titres_sources',
      where: 'id_titre = ? AND id_source = ?',
      whereArgs: <Object?>[idTitre, idSource],
      limit: 1,
    );
    return lignes.isEmpty ? null : LienTitreSource.depuisMap(lignes.first);
  }

  /// Nom du titre [idTitre], ou `null` s'il n'existe pas.
  static Future<String?> _chargerNomTitre(
    DatabaseExecutor executeur,
    int idTitre,
  ) async {
    final lignes = await executeur.query(
      'titres',
      columns: <String>['nom'],
      where: 'id = ?',
      whereArgs: <Object?>[idTitre],
      limit: 1,
    );
    return lignes.isEmpty ? null : lignes.first['nom'] as String?;
  }

  /// Nom de la source [idSource], ou `null` si elle n'existe pas.
  static Future<String?> _chargerNomSource(
    DatabaseExecutor executeur,
    int idSource,
  ) async {
    final lignes = await executeur.query(
      'sources',
      columns: <String>['nom'],
      where: 'id = ?',
      whereArgs: <Object?>[idSource],
      limit: 1,
    );
    return lignes.isEmpty ? null : lignes.first['nom'] as String?;
  }
}
