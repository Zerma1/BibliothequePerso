/// Dossier de la base SQLite (et du fichier `emplacements.json`) : choix
/// selon la plateforme, dossier choisi dans l'installateur Windows et
/// déplacement depuis l'ancien dossier des versions 0.3.2 et antérieures.
///
/// | Plateforme | Dossier de la base |
/// |------------|--------------------|
/// | Windows    | `dossierBase` de `installation.json` (chemin absolu), sinon `%APPDATA%\bibliotheque_perso` |
/// | Linux      | `getApplicationSupportDirectory()` (inchangé) |
/// | Android    | `getDatabasesPath()` de sqflite (inchangé) |
///
/// Jusqu'à la 0.3.2, la base Windows était dans
/// `%APPDATA%\io.github.zerma1\bibliotheque_perso`
/// (`getApplicationSupportDirectory()`). Au premier démarrage d'une version
/// plus récente, son contenu est déplacé dans le nouveau dossier
/// ([migrerAncienDossierBase]) avant l'ouverture de la base. Si la cible
/// est un dossier choisi à l'installation, une base déjà présente dans
/// `%APPDATA%\bibliotheque_perso` y est déplacée de la même façon, en
/// premier ([dossiersCandidatsMigrationWindows],
/// [migrerDossiersCandidatsBase]).
///
/// Point d'entrée : [preparerDossierBaseDeDonnees], appelé par
/// `cheminParDefautBaseDeDonnees` et `cheminParDefautFichierEmplacements`.
library;

import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:path/path.dart' as chemins;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../modeles/constantes.dart';
import '../modeles/journal.dart';
import 'constantes_donnees.dart';
import 'erreur_stockage.dart';

/// Règles de chemin Windows, quelle que soit la plateforme qui exécute le
/// code : la résolution du dossier Windows reste ainsi testable sous Linux.
final chemins.Context _cheminsWindows = chemins.Context(
  style: chemins.Style.windows,
);

/// Issue de [migrerAncienDossierBase].
enum IssueMigrationDossierBase {
  /// L'ancien dossier ne contient pas de base : rien à déplacer (cas
  /// normal après la première migration, ou nouvelle installation).
  aucuneAncienneBase,

  /// Le dossier cible contient déjà la base et l'ancien n'en a pas : rien à
  /// faire.
  baseDejaEnPlace,

  /// L'ancien dossier et le dossier cible sont le même dossier (par exemple
  /// choisi ainsi dans l'installateur) : rien à déplacer.
  memeDossier,

  /// Tout le contenu de l'ancien dossier a été déplacé et l'ancien dossier
  /// supprimé.
  deplacee,

  /// Le contenu a été copié et vérifié, la cible est utilisée, mais une
  /// partie de l'ancien dossier n'a pas pu être supprimée (journalisé).
  deplaceeAvecResidus,

  /// Les deux dossiers contiennent une base : la cible est gardée, rien
  /// n'est supprimé (avertissement journalisé).
  conflitDeuxBases,

  /// Un des deux dossiers est à l'intérieur de l'autre : rien n'est déplacé
  /// (vider l'ancien dossier effacerait la cible), l'ancien dossier est
  /// utilisé (avertissement journalisé).
  dossiersImbriques,

  /// L'ancienne base est ouverte par un autre processus (ancienne version
  /// encore lancée) : rien n'est déplacé, l'ancien dossier est utilisé
  /// cette fois-ci et la migration sera retentée au prochain démarrage.
  baseOccupee,

  /// Une copie ou une vérification a échoué : les copies sont effacées,
  /// l'ancien dossier, intact, est utilisé (erreur journalisée). La
  /// migration sera retentée au prochain démarrage.
  echec,
}

/// Résultat de [migrerAncienDossierBase].
class ResultatMigrationDossierBase {
  /// Crée un résultat.
  const ResultatMigrationDossierBase({
    required this.dossierUtilise,
    required this.issue,
    this.nombreFichiersDeplaces = 0,
  });

  /// Dossier où ouvrir la base : le dossier cible, ou l'ancien dossier si le
  /// déplacement n'a pas pu se faire ([IssueMigrationDossierBase.baseOccupee],
  /// [IssueMigrationDossierBase.echec]).
  final String dossierUtilise;

  /// Ce qui s'est passé.
  final IssueMigrationDossierBase issue;

  /// Nombre de fichiers copiés dans le dossier cible (0 sans déplacement).
  final int nombreFichiersDeplaces;

  @override
  bool operator ==(Object other) =>
      other is ResultatMigrationDossierBase &&
      other.dossierUtilise == dossierUtilise &&
      other.issue == issue &&
      other.nombreFichiersDeplaces == nombreFichiersDeplaces;

  @override
  int get hashCode =>
      Object.hash(dossierUtilise, issue, nombreFichiersDeplaces);

  @override
  String toString() =>
      'ResultatMigrationDossierBase(${issue.name}, $dossierUtilise, '
      '$nombreFichiersDeplaces fichier(s))';
}

/// `true` si [chemin] peut servir de dossier de la base sous Windows :
/// chemin absolu avec lecteur (`D:\Base`) ou partage réseau
/// (`\\nas\partage\Base`).
///
/// Sont refusés (même règle que l'installateur) :
/// - un texte vide, un chemin relatif (`Base`), relatif au lecteur courant
///   (`\Base`) ou au dossier courant d'un lecteur (`D:Base`) : ils
///   dépendraient du dossier depuis lequel l'application est lancée ;
/// - une racine (`D:\`, `\\nas\partage`) : la vider à la désinstallation
///   toucherait tout le disque ou le partage ;
/// - si [dossierAppData] est donné : un dossier à l'intérieur de
///   `%APPDATA%\bibliotheque_perso` ou qui le contient (sauf ce dossier
///   lui-même, le défaut), et un dossier à l'intérieur de
///   `%APPDATA%\io.github.zerma1`, égal à lui ou qui le contient : la
///   migration ([migrerAncienDossierBase]) viderait sinon un dossier qui
///   contient la cible, ou l'inverse.
bool verifierDossierBaseWindows(String chemin, {String? dossierAppData}) {
  final propre = chemin.trim();
  if (propre.isEmpty ||
      !_cheminsWindows.isAbsolute(propre) ||
      _cheminsWindows.isRootRelative(propre)) {
    return false;
  }
  final normalise = _cheminsWindows.normalize(propre);
  // Une racine n'a qu'un élément : `D:\` ou `\\nas\partage`.
  if (_cheminsWindows.split(normalise).length < 2) return false;
  if (dossierAppData == null) return true;
  bool imbrique(String a, String b) =>
      _cheminsWindows.isWithin(a, b) || _cheminsWindows.isWithin(b, a);
  final parDefaut = _cheminsWindows.join(dossierAppData, nomDossierBaseWindows);
  final ancienEditeur = _cheminsWindows.join(
    dossierAppData,
    nomAncienDossierEditeurWindows,
  );
  return !imbrique(normalise, parDefaut) &&
      !imbrique(normalise, ancienEditeur) &&
      !_cheminsWindows.equals(normalise, ancienEditeur);
}

/// Dossier de la base choisi dans l'installateur Windows (clé
/// [cleDossierBaseInstallation] de [nomFichierInstallationWindows]), ou
/// `null`.
///
/// Lit le fichier dans le dossier de l'exécutable ([cheminExecutable], par
/// défaut `Platform.resolvedExecutable` ; les tests passent un chemin dans
/// un dossier temporaire). Renvoie la valeur sans espaces autour, ou `null`
/// si le fichier est absent (lancement depuis IntelliJ, Linux, Android),
/// illisible, ou si la clé est absente, vide ou n'est pas un texte. Ne lève
/// jamais : un fichier illisible est seulement journalisé.
///
/// Ne valide pas le chemin : voir [verifierDossierBaseWindows].
Future<String?> chargerDossierBaseInstallation({
  String? cheminExecutable,
}) async {
  final fichier = File(
    chemins.join(
      chemins.dirname(cheminExecutable ?? Platform.resolvedExecutable),
      nomFichierInstallationWindows,
    ),
  );
  try {
    if (!await fichier.exists()) return null;
    var texte = await fichier.readAsString();
    // Fichier réenregistré avec un éditeur qui ajoute un BOM UTF-8 :
    // jsonDecode le refuserait.
    if (texte.isNotEmpty && texte.codeUnitAt(0) == 0xFEFF) {
      texte = texte.substring(1);
    }
    final Object? donnees = jsonDecode(texte);
    if (donnees is! Map<String, Object?>) return null;
    final valeur = donnees[cleDossierBaseInstallation];
    if (valeur is! String) return null;
    final propre = valeur.trim();
    return propre.isEmpty ? null : propre;
  } catch (erreur) {
    Journal.actuel.avertissement(
      CategorieJournal.base,
      'Fichier $nomFichierInstallationWindows illisible : dossier de la base '
      'par défaut',
      erreur: erreur,
    );
    return null;
  }
}

/// Dossier de la base sous Windows, sans rien lire ni écrire sur le disque :
/// [dossierBaseInstallation] (valeur lue par [chargerDossierBaseInstallation])
/// s'il est valide ([verifierDossierBaseWindows]), sinon
/// `<dossierAppData>\bibliotheque_perso` ([nomDossierBaseWindows]).
///
/// [dossierAppData] : valeur de `%APPDATA%`. Le chemin renvoyé est
/// normalisé (séparateurs `\`, sans `..` ni `\` final). Une valeur
/// d'installation invalide est journalisée (avertissement).
String resoudreDossierBaseWindows({
  required String? dossierBaseInstallation,
  required String dossierAppData,
}) {
  if (dossierBaseInstallation != null) {
    if (verifierDossierBaseWindows(
      dossierBaseInstallation,
      dossierAppData: dossierAppData,
    )) {
      return _cheminsWindows.normalize(dossierBaseInstallation.trim());
    }
    Journal.actuel.avertissement(
      CategorieJournal.base,
      "Dossier de la base choisi à l'installation ignoré (chemin relatif, "
      'racine ou imbriqué avec le dossier par défaut ou ancien) : '
      '« $dossierBaseInstallation »',
    );
  }
  return _cheminsWindows.normalize(
    _cheminsWindows.join(dossierAppData, nomDossierBaseWindows),
  );
}

/// Ancien dossier de la base sous Windows (versions 0.3.2 et antérieures) :
/// `<dossierAppData>\io.github.zerma1\bibliotheque_perso`.
String cheminAncienDossierBaseWindows(String dossierAppData) =>
    _cheminsWindows.normalize(
      _cheminsWindows.join(
        dossierAppData,
        nomAncienDossierEditeurWindows,
        nomAncienDossierBaseWindows,
      ),
    );

/// Déplace le contenu de [ancienDossier] vers [dossierCible] si
/// [ancienDossier] contient la base ([nomFichierBaseDeDonnees]) et que
/// [dossierCible] ne la contient pas, puis renvoie le dossier à utiliser.
///
/// À appeler **avant** d'ouvrir la base. Règles, dans l'ordre :
/// 1. Même dossier : [IssueMigrationDossierBase.memeDossier].
/// 2. Les deux dossiers ont une base : la cible est gardée, rien n'est
///    supprimé, avertissement ([IssueMigrationDossierBase.conflitDeuxBases]).
/// 3. Seule la cible a une base ([IssueMigrationDossierBase.baseDejaEnPlace])
///    ou aucune base dans l'ancien dossier
///    ([IssueMigrationDossierBase.aucuneAncienneBase]) : rien à faire.
/// 4. Un dossier est à l'intérieur de l'autre : rien n'est déplacé,
///    l'ancien dossier est utilisé
///    ([IssueMigrationDossierBase.dossiersImbriques]). Même chose si
///    l'ancienne base est ouverte par un autre processus
///    ([IssueMigrationDossierBase.baseOccupee]).
/// 5. Sinon, chaque fichier (sous-dossiers compris) est copié dans
///    `<nom>`[suffixeCopieMigrationBase], comparé octet par octet à
///    l'original, puis renommé sous son nom ; la base est copiée **en
///    dernier**, si bien qu'une coupure en cours de route laisse une cible
///    sans base (la migration recommence au démarrage suivant). Un fichier
///    de même nom déjà présent dans la cible est remplacé ; les fichiers
///    annexes SQLite (`-wal`, `-shm`, `-journal`) de la cible qui n'ont pas
///    d'équivalent dans l'ancien dossier sont supprimés.
///    - Si une copie échoue : les copies déjà faites sont effacées, l'ancien
///      dossier n'est pas touché et il est utilisé
///      ([IssueMigrationDossierBase.echec], erreur journalisée).
///    - Si tout est copié : l'ancien dossier est vidé (la base d'abord ; si
///      elle ne peut pas être supprimée, rien d'autre ne l'est), puis
///      supprimé, ainsi que [dossierParentAncien] (s'il est donné) s'il est
///      vide. Un fichier
///      qui ne peut pas être supprimé est journalisé et la cible est
///      utilisée quand même ([IssueMigrationDossierBase.deplaceeAvecResidus]).
///
/// Lève une [ErreurStockage] seulement si l'ancienne base, renommée un
/// instant pour vérifier qu'elle est libre, ne peut pas reprendre son nom
/// (cas extrême) : ouvrir l'ancien dossier créerait alors une base vide.
Future<ResultatMigrationDossierBase> migrerAncienDossierBase({
  required String ancienDossier,
  required String dossierCible,
  String? dossierParentAncien,
}) async {
  final baseAncienne = File(
    chemins.join(ancienDossier, nomFichierBaseDeDonnees),
  );
  final baseCible = File(chemins.join(dossierCible, nomFichierBaseDeDonnees));
  // Base restée renommée par un test d'occupation interrompu : la remettre
  // avant de regarder qui a une base.
  await restaurerBaseEnVerification(ancienDossier);
  await restaurerBaseEnVerification(dossierCible);

  if (_memeChemin(ancienDossier, dossierCible)) {
    return ResultatMigrationDossierBase(
      dossierUtilise: dossierCible,
      issue: IssueMigrationDossierBase.memeDossier,
    );
  }
  final ancienneExiste = await baseAncienne.exists();
  if (await baseCible.exists()) {
    if (!ancienneExiste) {
      return ResultatMigrationDossierBase(
        dossierUtilise: dossierCible,
        issue: IssueMigrationDossierBase.baseDejaEnPlace,
      );
    }
    Journal.actuel.avertissement(
      CategorieJournal.base,
      'Deux bases trouvées : celle de $dossierCible est utilisée, '
      "l'ancienne ($ancienDossier) est laissée telle quelle. Supprimez-la "
      'vous-même si elle ne sert plus.',
    );
    return ResultatMigrationDossierBase(
      dossierUtilise: dossierCible,
      issue: IssueMigrationDossierBase.conflitDeuxBases,
    );
  }
  if (!ancienneExiste) {
    return ResultatMigrationDossierBase(
      dossierUtilise: dossierCible,
      issue: IssueMigrationDossierBase.aucuneAncienneBase,
    );
  }

  if (chemins.isWithin(ancienDossier, dossierCible) ||
      chemins.isWithin(dossierCible, ancienDossier)) {
    Journal.actuel.avertissement(
      CategorieJournal.base,
      "Dossier de la base $dossierCible imbriqué avec l'ancien dossier "
      '$ancienDossier : la base reste dans $ancienDossier. Choisissez un '
      "dossier distinct à l'installation.",
    );
    return ResultatMigrationDossierBase(
      dossierUtilise: ancienDossier,
      issue: IssueMigrationDossierBase.dossiersImbriques,
    );
  }

  if (!await _verifierBaseLibre(baseAncienne)) {
    Journal.actuel.avertissement(
      CategorieJournal.base,
      'Base de $ancienDossier ouverte par un autre programme (ancienne '
      'version encore lancée ?) : elle reste à sa place pour cette fois, le '
      'déplacement vers $dossierCible sera retenté au prochain démarrage.',
    );
    return ResultatMigrationDossierBase(
      dossierUtilise: ancienDossier,
      issue: IssueMigrationDossierBase.baseOccupee,
    );
  }

  // Inventaire : fichiers seulement (les dossiers sont recréés au besoin),
  // la base en dernier.
  final fichiers = <File>[];
  try {
    await for (final element in Directory(
      ancienDossier,
    ).list(recursive: true, followLinks: false)) {
      if (element is File && !_memeChemin(element.path, baseAncienne.path)) {
        fichiers.add(element);
      }
    }
  } on FileSystemException catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.base,
      'Contenu de $ancienDossier illisible : la base reste dans ce dossier',
      erreur: erreur,
      pile: pile,
    );
    return ResultatMigrationDossierBase(
      dossierUtilise: ancienDossier,
      issue: IssueMigrationDossierBase.echec,
    );
  }
  fichiers.add(baseAncienne);

  // Copie vérifiée de chaque fichier.
  final ecrits = <File>[];
  File? copieEnCours;
  try {
    await Directory(dossierCible).create(recursive: true);
    for (final suffixe in suffixesFichiersAnnexesSqlite) {
      final annexeCible = File('${baseCible.path}$suffixe');
      if (await annexeCible.exists() &&
          !await File('${baseAncienne.path}$suffixe').exists()) {
        await annexeCible.delete();
      }
    }
    for (final fichier in fichiers) {
      final relatif = chemins.relative(fichier.path, from: ancienDossier);
      final destination = File(chemins.join(dossierCible, relatif));
      await destination.parent.create(recursive: true);
      final copie = File('${destination.path}$suffixeCopieMigrationBase');
      copieEnCours = copie;
      await fichier.copy(copie.path);
      if (!await _fichiersIdentiques(fichier, copie)) {
        throw FileSystemException("copie différente de l'original", copie.path);
      }
      // Sous Windows comme sous Linux, rename remplace un fichier existant.
      await copie.rename(destination.path);
      copieEnCours = null;
      ecrits.add(destination);
    }
  } catch (erreur, pile) {
    await _supprimerSansErreur(<File>[?copieEnCours, ...ecrits]);
    Journal.actuel.erreur(
      CategorieJournal.base,
      'Déplacement de la base de $ancienDossier vers $dossierCible '
      "impossible : copies effacées, l'ancien dossier (intact) est utilisé. "
      'Nouvel essai au prochain démarrage.',
      erreur: erreur,
      pile: pile,
    );
    return ResultatMigrationDossierBase(
      dossierUtilise: ancienDossier,
      issue: IssueMigrationDossierBase.echec,
    );
  }

  // Tout est copié et vérifié : la cible fait foi. Suppression de l'ancien
  // dossier, la base d'abord : si elle reste, rien d'autre n'est supprimé
  // (au prochain démarrage, deux bases complètes : conflit sans perte).
  final residus = <String>[];
  try {
    await baseAncienne.delete();
    for (final fichier in fichiers) {
      if (identical(fichier, baseAncienne)) continue;
      try {
        await fichier.delete();
      } on FileSystemException {
        residus.add(fichier.path);
      }
    }
    await _supprimerDossiersVides(ancienDossier);
    if (dossierParentAncien != null) {
      await _supprimerDossierSiVide(Directory(dossierParentAncien));
    }
  } on FileSystemException {
    residus.add(baseAncienne.path);
  }

  if (residus.isNotEmpty) {
    Journal.actuel.avertissement(
      CategorieJournal.base,
      'Base déplacée de $ancienDossier vers $dossierCible, mais '
      "${residus.length} fichier(s) de l'ancien dossier n'ont pas pu être "
      'supprimés : ${residus.join(', ')}',
    );
    return ResultatMigrationDossierBase(
      dossierUtilise: dossierCible,
      issue: IssueMigrationDossierBase.deplaceeAvecResidus,
      nombreFichiersDeplaces: ecrits.length,
    );
  }
  Journal.actuel.info(
    CategorieJournal.base,
    'Base déplacée de $ancienDossier vers $dossierCible '
    '(${ecrits.length} fichier(s))',
  );
  return ResultatMigrationDossierBase(
    dossierUtilise: dossierCible,
    issue: IssueMigrationDossierBase.deplacee,
    nombreFichiersDeplaces: ecrits.length,
  );
}

/// Dossier dont la base peut être déplacée vers le dossier cible :
/// [dossier], et [parent] à supprimer ensuite s'il est vide (ou `null`).
typedef DossierCandidatBase = ({String dossier, String? parent});

/// Dossiers d'où déplacer la base sous Windows, dans l'ordre d'essai, pour
/// le dossier cible [dossierCible] :
/// 1. `%APPDATA%\bibliotheque_perso` (défaut depuis la 0.3.3), seulement
///    s'il diffère de la cible (cible choisie à l'installation) ;
/// 2. l'ancien `%APPDATA%\io.github.zerma1\bibliotheque_perso`, avec
///    `%APPDATA%\io.github.zerma1` comme parent à supprimer s'il est vide.
///
/// Calcul pur (aucun accès au disque), règles de chemin Windows : casse
/// ignorée.
List<DossierCandidatBase> dossiersCandidatsMigrationWindows({
  required String dossierCible,
  required String dossierAppData,
}) {
  final parDefaut = _cheminsWindows.normalize(
    _cheminsWindows.join(dossierAppData, nomDossierBaseWindows),
  );
  return <DossierCandidatBase>[
    if (!_cheminsWindows.equals(parDefaut, dossierCible))
      (dossier: parDefaut, parent: null),
    (
      dossier: cheminAncienDossierBaseWindows(dossierAppData),
      parent: _cheminsWindows.normalize(
        _cheminsWindows.join(dossierAppData, nomAncienDossierEditeurWindows),
      ),
    ),
  ];
}

/// Applique [migrerAncienDossierBase] à chaque dossier de [candidats], dans
/// l'ordre, vers [dossierCible], et renvoie le résultat qui décide du
/// dossier à utiliser.
///
/// On passe au candidat suivant tant que rien n'a été tenté : candidat sans
/// base, même dossier que la cible, base déjà dans la cible ou conflit
/// (deux bases : rien supprimé, avertissement pour chaque candidat
/// concerné). Dès qu'un déplacement est tenté ou refusé (déplacé, résidus,
/// échec, base occupée, dossiers imbriqués), son résultat est renvoyé : les
/// candidats suivants ne sont pas regardés (au démarrage suivant, la cible
/// aura une base et ils seront signalés en conflit s'ils en ont une). Sans
/// candidat, ou si aucun n'a rien déplacé, renvoie le résultat du dernier
/// (ou [IssueMigrationDossierBase.aucuneAncienneBase]) : la cible est
/// utilisée.
///
/// Un dossier `%APPDATA%\bibliotheque_perso` vidé n'est supprimé que s'il
/// est vide (suppression non récursive, comme tous les dossiers vidés).
///
/// [cibleChoisieAInstallation] : la cible vient de `dossierBase`
/// (`installation.json`). Si ce dossier n'existe pas (lecteur débranché,
/// NAS éteint), un avertissement explicite est journalisé avant le
/// comportement habituel (la cible sera créée, avec une base vide si aucun
/// candidat n'en a).
Future<ResultatMigrationDossierBase> migrerDossiersCandidatsBase({
  required String dossierCible,
  required List<DossierCandidatBase> candidats,
  bool cibleChoisieAInstallation = false,
}) async {
  if (cibleChoisieAInstallation && !await Directory(dossierCible).exists()) {
    Journal.actuel.avertissement(
      CategorieJournal.base,
      "Base attendue absente : le dossier choisi à l'installation "
      "($dossierCible) n'existe pas (lecteur débranché ou NAS éteint ?). "
      'Il va être créé si possible, avec une base vide si aucune ancienne '
      "base n'est trouvée.",
    );
  }
  await restaurerBaseEnVerification(dossierCible);
  var resultat = ResultatMigrationDossierBase(
    dossierUtilise: dossierCible,
    issue: IssueMigrationDossierBase.aucuneAncienneBase,
  );
  for (final candidat in candidats) {
    resultat = await migrerAncienDossierBase(
      ancienDossier: candidat.dossier,
      dossierCible: dossierCible,
      dossierParentAncien: candidat.parent,
    );
    switch (resultat.issue) {
      case IssueMigrationDossierBase.aucuneAncienneBase:
      case IssueMigrationDossierBase.memeDossier:
      case IssueMigrationDossierBase.baseDejaEnPlace:
      case IssueMigrationDossierBase.conflitDeuxBases:
        continue;
      case IssueMigrationDossierBase.deplacee:
      case IssueMigrationDossierBase.deplaceeAvecResidus:
      case IssueMigrationDossierBase.dossiersImbriques:
      case IssueMigrationDossierBase.baseOccupee:
      case IssueMigrationDossierBase.echec:
        return resultat;
    }
  }
  return resultat;
}

/// Préparation en cours ou terminée de [preparerDossierBaseDeDonnees]
/// (une par isolat).
Future<String>? _preparation;

/// Dossier de la base de données de cette plateforme, créé au besoin, après
/// le déplacement éventuel de l'ancien dossier Windows (voir l'en-tête du
/// fichier). Le calcul n'est fait qu'une fois par isolat ; les appels
/// suivants renvoient le même dossier (la base et `emplacements.json`
/// restent ainsi toujours ensemble, même si le déplacement a échoué). Après
/// une erreur, l'appel suivant recommence.
///
/// Peut lever l'erreur de `path_provider` ou de sqflite (Linux, Android),
/// une [FileSystemException] si le dossier ne peut pas être créé, ou une
/// [ErreurStockage] (voir [migrerAncienDossierBase]). Lève une [StateError]
/// dans les tests (`flutter test`) : ils ne doivent jamais lire ni déplacer
/// la vraie base du poste ; ils passent leurs propres chemins.
Future<String> preparerDossierBaseDeDonnees() {
  return _preparation ??= _preparerDossier().then(
    (dossier) => dossier,
    onError: (Object erreur, StackTrace pile) {
      _preparation = null;
      Error.throwWithStackTrace(erreur, pile);
    },
  );
}

/// Calcul réel de [preparerDossierBaseDeDonnees].
Future<String> _preparerDossier() async {
  // Variable posée par `flutter test` : garde-fou contre un test qui
  // oublierait de passer son propre chemin.
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    throw StateError(
      'Dossier réel de la base interdit dans les tests : passer un chemin.',
    );
  }
  if (Platform.isAndroid) {
    return getDatabasesPath();
  }
  if (!Platform.isWindows) {
    final dossier = await getApplicationSupportDirectory();
    // SQLite crée le fichier mais pas les dossiers parents.
    await dossier.create(recursive: true);
    return dossier.path;
  }
  final appData = Platform.environment['APPDATA']?.trim() ?? '';
  if (appData.isEmpty) {
    // Ne devrait pas arriver sous Windows : dossier d'avant la 0.3.3.
    final dossier = await getApplicationSupportDirectory();
    Journal.actuel.avertissement(
      CategorieJournal.base,
      'Variable APPDATA absente : base dans ${dossier.path}',
    );
    await dossier.create(recursive: true);
    return dossier.path;
  }
  final installation = await chargerDossierBaseInstallation();
  final cible = resoudreDossierBaseWindows(
    dossierBaseInstallation: installation,
    dossierAppData: appData,
  );
  final resultat = await migrerDossiersCandidatsBase(
    dossierCible: cible,
    cibleChoisieAInstallation:
        installation != null &&
        verifierDossierBaseWindows(installation, dossierAppData: appData),
    candidats: dossiersCandidatsMigrationWindows(
      dossierCible: cible,
      dossierAppData: appData,
    ),
  );
  await Directory(resultat.dossierUtilise).create(recursive: true);
  Journal.actuel.info(
    CategorieJournal.base,
    'Dossier de la base : ${resultat.dossierUtilise} '
    '(${resultat.issue.name})',
  );
  return resultat.dossierUtilise;
}

/// `true` si [a] et [b] désignent le même chemin (casse ignorée sous
/// Windows, `..` et séparateurs normalisés).
bool _memeChemin(String a, String b) =>
    chemins.canonicalize(a) == chemins.canonicalize(b);

/// Remet sous son nom une base de [dossier] restée renommée en
/// `<base>`[suffixeVerificationBaseLibre] (arrêt brutal pendant
/// [_verifierBaseLibre] : installateur qui tue le processus, coupure de
/// courant). Renvoie `true` si la base a été restaurée.
///
/// Appelée avant tout examen d'un dossier ([migrerAncienDossierBase] pour
/// l'ancien dossier et la cible, [migrerDossiersCandidatsBase] pour la
/// cible) : sans elle, SQLite créerait une base vide à côté. Si la base et
/// le fichier renommé existent tous les deux, rien n'est touché
/// (avertissement) : on ne sait pas lequel est le bon. Ne lève jamais : un
/// échec est journalisé.
Future<bool> restaurerBaseEnVerification(String dossier) async {
  final base = File(chemins.join(dossier, nomFichierBaseDeDonnees));
  final renommee = File('${base.path}$suffixeVerificationBaseLibre');
  try {
    if (!await renommee.exists()) return false;
    if (await base.exists()) {
      Journal.actuel.avertissement(
        CategorieJournal.base,
        'Fichier ${renommee.path} laissé tel quel : la base '
        '${base.path} existe aussi.',
      );
      return false;
    }
    await renommee.rename(base.path);
    Journal.actuel.avertissement(
      CategorieJournal.base,
      'Base restée renommée après un arrêt brutal : ${renommee.path} '
      'remise sous son nom.',
    );
    return true;
  } on FileSystemException catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.base,
      'Base restée renommée (${renommee.path}) : restauration impossible',
      erreur: erreur,
      pile: pile,
    );
    return false;
  }
}

/// `true` si aucun autre processus n'a ouvert [base] : on la renomme un
/// instant puis on lui rend son nom.
///
/// Pourquoi un renommage : c'est le seul test fiable avec les API de Dart.
/// Sous Windows, SQLite ouvre ses fichiers avec le partage lecture et
/// écriture mais **sans** le partage suppression : un renommage échoue tant
/// qu'une autre instance les a ouverts. Une ouverture par Dart
/// (`File.open`, même en ajout) réussit alors quand même (partage
/// lecture/écriture accordé), et `RandomAccessFile.lock` ne voit que les
/// verrous d'octets que SQLite ne pose que pendant une transaction : une
/// base ouverte mais inactive passerait pour libre. Le risque du
/// renommage (arrêt brutal entre les deux renommages, quelques
/// millisecondes) est couvert par [restaurerBaseEnVerification], appelée
/// au démarrage suivant avant tout examen du dossier.
///
/// Sous Linux, le test ne détecte rien (le renommage d'un fichier ouvert y
/// est permis), mais la migration n'y est jamais appelée par
/// [preparerDossierBaseDeDonnees].
Future<bool> _verifierBaseLibre(File base) async {
  final cheminVerification = '${base.path}$suffixeVerificationBaseLibre';
  final File renommee;
  try {
    renommee = await base.rename(cheminVerification);
  } on FileSystemException {
    return false;
  }
  FileSystemException? derniere;
  for (var essai = 0; essai < nombreEssaisRestaurationBase; essai++) {
    try {
      await renommee.rename(base.path);
      return true;
    } on FileSystemException catch (erreur) {
      derniere = erreur;
      await Future<void>.delayed(delaiEntreEssaisRestaurationBase);
    }
  }
  throw ErreurStockage(
    'La base a été renommée en « $cheminVerification » pour vérifier '
    "qu'elle était libre, mais elle n'a pas pu reprendre son nom. "
    'Renommez-la en « ${chemins.basename(base.path)} » avant de relancer '
    "l'application.",
    chemin: cheminVerification,
    cause: derniere,
  );
}

/// `true` si [a] et [b] ont exactement les mêmes octets (lecture par blocs
/// de [tailleBlocComparaisonFichiers], sans tout charger en mémoire).
Future<bool> _fichiersIdentiques(File a, File b) async {
  if (await a.length() != await b.length()) return false;
  final lecteurA = await a.open();
  try {
    final lecteurB = await b.open();
    try {
      while (true) {
        final blocA = await lecteurA.read(tailleBlocComparaisonFichiers);
        final blocB = await lecteurB.read(tailleBlocComparaisonFichiers);
        if (blocA.length != blocB.length) return false;
        if (blocA.isEmpty) return true;
        for (var i = 0; i < blocA.length; i++) {
          if (blocA[i] != blocB[i]) return false;
        }
      }
    } finally {
      await lecteurB.close();
    }
  } finally {
    await lecteurA.close();
  }
}

/// Supprime les [fichiers] qui existent, en ignorant les échecs (nettoyage
/// après un déplacement manqué).
Future<void> _supprimerSansErreur(List<File> fichiers) async {
  for (final fichier in fichiers) {
    try {
      if (await fichier.exists()) await fichier.delete();
    } on FileSystemException {
      // Copie restée : remplacée au prochain essai.
    }
  }
}

/// Supprime [racine] et ses sous-dossiers **vides**, des plus profonds aux
/// moins profonds. Un dossier non vide (fichier resté) est laissé.
Future<void> _supprimerDossiersVides(String racine) async {
  final dossiers = <Directory>[];
  try {
    await for (final element in Directory(
      racine,
    ).list(recursive: true, followLinks: false)) {
      if (element is Directory) dossiers.add(element);
    }
  } on FileSystemException {
    return;
  }
  dossiers.sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final dossier in dossiers) {
    await _supprimerDossierSiVide(dossier);
  }
  await _supprimerDossierSiVide(Directory(racine));
}

/// Supprime [dossier] s'il existe et est vide ; ne fait rien sinon.
///
/// Suppression non récursive : le système refuse de supprimer un dossier
/// qui contient encore quelque chose, rien ne peut donc être perdu.
Future<void> _supprimerDossierSiVide(Directory dossier) async {
  try {
    if (await dossier.exists()) await dossier.delete();
  } on FileSystemException {
    // Non vide ou verrouillé : laissé tel quel.
  }
}
