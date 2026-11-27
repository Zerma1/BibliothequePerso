/// Mode désinstallation : l'installateur Windows lance
/// `bibliotheque_perso.exe --desinstallation [--supprimer-sources]
/// [--supprimer-titres] [--chapitres-supprimes]` (sans fenêtre) avant de
/// retirer le programme, et lit le code de sortie (0 = réussi).
///
/// Trois niveaux, séparés pour être testables :
/// - [OptionsDesinstallation.depuisArguments] : analyse pure des arguments ;
/// - [ServiceDesinstallation] : écritures en base, sur des dépôts fournis ;
/// - [executerModeDesinstallation] : ouverture et fermeture de la base, code
///   de sortie, pour `main.dart`.
library;

import 'dart:io' show File;

import 'package:sqflite/sqflite.dart'
    show Database, DatabaseFactory, inMemoryDatabasePath;

import '../donnees/base_de_donnees.dart';
import '../donnees/depot_chapitres.dart';
import '../donnees/depot_parametres.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../modeles/journal.dart';
import 'constantes_services.dart';
import 'service_parametres.dart';

/// Préfixe des lignes du journal de ce mode (repérables d'un coup d'œil).
const String _prefixeJournal = 'Désinstallation';

/// Longueur maximale d'un argument inconnu recopié dans le journal : assez
/// pour reconnaître une option mal écrite, trop court pour un chemin entier.
const int _longueurMaxArgumentJournal = 40;

/// `true` si l'application est lancée en mode désinstallation
/// ([argumentDesinstallation] parmi les [arguments]).
bool estModeDesinstallation(List<String> arguments) =>
    arguments.contains(argumentDesinstallation);

/// Ce que l'installateur demande de modifier dans la base.
class OptionsDesinstallation {
  /// Crée les options. [supprimerSources] entraîne toujours la suppression
  /// des titres ([supprimerTitres] vaut alors `true`).
  const OptionsDesinstallation({
    this.supprimerSources = false,
    bool supprimerTitres = false,
    this.chapitresSupprimes = false,
    this.argumentsInconnus = const <String>[],
  }) : _titresDemandes = supprimerTitres;

  /// Supprimer toutes les sources ([argumentSupprimerSources]).
  final bool supprimerSources;

  final bool _titresDemandes;

  /// Les chapitres téléchargés vont être effacés par le désinstallateur
  /// ([argumentChapitresSupprimes]).
  final bool chapitresSupprimes;

  /// Arguments non reconnus, dans l'ordre reçu. S'il y en a, rien n'est
  /// modifié ([estValide] vaut `false`).
  final List<String> argumentsInconnus;

  /// Supprimer tous les titres ([argumentSupprimerTitres]), ou les sources :
  /// un titre ne peut pas exister sans son site principal
  /// (`titres.id_source` en `NOT NULL` et `ON DELETE RESTRICT`). Même si
  /// l'installateur oubliait l'option des titres, on ne laisse donc pas des
  /// sources impossibles à supprimer.
  bool get supprimerTitres => _titresDemandes || supprimerSources;

  /// `true` si tous les arguments sont reconnus.
  bool get estValide => argumentsInconnus.isEmpty;

  /// `true` si les chapitres doivent être marqués « non téléchargés ».
  /// Inutile quand les titres sont supprimés : leurs chapitres partent avec
  /// eux.
  bool get doitMarquerChapitres => chapitresSupprimes && !supprimerTitres;

  /// `true` si au moins une écriture en base est demandée.
  bool get aQuelqueChoseAFaire => supprimerTitres || doitMarquerChapitres;

  /// Analyse les arguments de la ligne de commande, sans effet de bord.
  ///
  /// Les options sont comparées exactement (l'installateur les écrit
  /// toujours ainsi) ; [argumentDesinstallation] et les doublons sont
  /// acceptés. Tout autre argument est rangé dans [argumentsInconnus] :
  /// mieux vaut refuser que deviner, une option mal lue pouvant effacer ce
  /// que le client voulait garder (ou garder ce qu'il voulait effacer).
  static OptionsDesinstallation depuisArguments(List<String> arguments) {
    var sources = false;
    var titres = false;
    var chapitres = false;
    final inconnus = <String>[];
    for (final argument in arguments) {
      switch (argument) {
        case argumentDesinstallation:
          break;
        case argumentSupprimerSources:
          sources = true;
        case argumentSupprimerTitres:
          titres = true;
        case argumentChapitresSupprimes:
          chapitres = true;
        default:
          inconnus.add(argument);
      }
    }
    return OptionsDesinstallation(
      supprimerSources: sources,
      supprimerTitres: titres,
      chapitresSupprimes: chapitres,
      argumentsInconnus: List<String>.unmodifiable(inconnus),
    );
  }

  /// Description pour le journal (noms des options seulement).
  String decrire() {
    final parties = <String>[
      if (supprimerSources) 'sources',
      if (supprimerTitres) 'titres',
      if (chapitresSupprimes) 'chapitres effacés',
    ];
    return parties.isEmpty ? 'aucune option' : parties.join(', ');
  }
}

/// Étape de la désinstallation qui a échoué.
enum EtapeDesinstallation {
  /// Arguments non reconnus : rien n'a été modifié.
  arguments,

  /// Base impossible à ouvrir : rien n'a été modifié.
  ouvertureBase,

  /// Chapitres non remis à « non téléchargé ».
  chapitres,

  /// Titres non supprimés.
  titres,

  /// Sources non supprimées (ou pas toutes).
  sources,

  /// Erreur imprévue hors des étapes précédentes.
  inattendue,
}

/// Résultat d'une désinstallation (comptes et éventuelle étape en échec).
class ResultatDesinstallation {
  /// Crée le résultat.
  const ResultatDesinstallation({
    this.etapeEchouee,
    this.chapitresMarques = 0,
    this.telechargementsRetires = 0,
    this.titresSupprimes = 0,
    this.sourcesSupprimees = 0,
    this.sourcesGardees = 0,
    this.reglagesSupprimes = 0,
  });

  /// Étape en échec, ou `null` si tout a réussi. Les étapes suivantes n'ont
  /// pas été tentées.
  final EtapeDesinstallation? etapeEchouee;

  /// Chapitres remis à « non téléchargé ».
  final int chapitresMarques;

  /// Lignes retirées de la file de téléchargement.
  final int telechargementsRetires;

  /// Titres supprimés.
  final int titresSupprimes;

  /// Sources supprimées.
  final int sourcesSupprimees;

  /// Sources restées en base (0 attendu quand les sources sont demandées).
  final int sourcesGardees;

  /// Réglages devenus incohérents et supprimés.
  final int reglagesSupprimes;

  /// `true` si toutes les étapes demandées ont réussi.
  bool get estReussi => etapeEchouee == null;

  /// Code de sortie attendu par l'installateur.
  int get codeSortie => estReussi
      ? codeSortieDesinstallationReussie
      : codeSortieDesinstallationEchec;

  /// Copie avec l'étape en échec [etape] (comptes déjà obtenus gardés).
  ResultatDesinstallation echouerA(EtapeDesinstallation etape) =>
      ResultatDesinstallation(
        etapeEchouee: etape,
        chapitresMarques: chapitresMarques,
        telechargementsRetires: telechargementsRetires,
        titresSupprimes: titresSupprimes,
        sourcesSupprimees: sourcesSupprimees,
        sourcesGardees: sourcesGardees,
        reglagesSupprimes: reglagesSupprimes,
      );
}

/// Modifie la base comme demandé par l'installateur : chapitres, titres,
/// sources, puis les réglages qui en dépendent.
class ServiceDesinstallation {
  /// Crée le service sur des dépôts déjà construits.
  const ServiceDesinstallation({
    required DepotTitres depotTitres,
    required DepotSources depotSources,
    required DepotChapitres depotChapitres,
    required DepotParametres depotParametres,
  }) : _titres = depotTitres,
       _sources = depotSources,
       _chapitres = depotChapitres,
       _parametres = depotParametres;

  /// Crée le service et ses dépôts sur une base déjà ouverte.
  factory ServiceDesinstallation.surBase(Database base) =>
      ServiceDesinstallation(
        depotTitres: DepotTitres(base),
        depotSources: DepotSources(base),
        depotChapitres: DepotChapitres(base),
        depotParametres: DepotParametres(base),
      );

  final DepotTitres _titres;
  final DepotSources _sources;
  final DepotChapitres _chapitres;
  final DepotParametres _parametres;

  /// Réglages qui désignent des chapitres téléchargés : sans objet une fois
  /// les archives effacées (ou les titres supprimés).
  ///
  /// - [ServiceParametres.cleChapitresGardes] : ancien stockage des
  ///   chapitres gardés, par identifiant (des identifiants qui ne désignent
  ///   plus rien, ou plus une archive).
  /// - [ServiceParametres.cleDeplacementDossierEnCours] : déplacement des
  ///   archives resté inachevé. Gardé, il arrêterait la file de
  ///   téléchargement à la réinstallation pour un déplacement d'archives qui
  ///   n'existent plus.
  static const List<String> clesLieesAuxChapitres = <String>[
    ServiceParametres.cleChapitresGardes,
    ServiceParametres.cleDeplacementDossierEnCours,
  ];

  /// Exécute les étapes demandées, dans l'ordre : chapitres (seulement si
  /// les titres sont gardés), titres, sources, et nettoie les réglages
  /// devenus incohérents. Ne lève jamais : une erreur arrête les étapes
  /// suivantes et est rendue dans le résultat (et le journal).
  ///
  /// Des [options] non valides ([OptionsDesinstallation.estValide])
  /// n'écrivent rien.
  // LIMITE : chaque étape est une transaction à elle seule (les dépôts
  // ouvrent la leur) ; l'ensemble n'est pas atomique. Si les sources
  // échouent après la suppression des titres, les titres restent supprimés
  // et le résultat est un échec (étape `sources`).
  Future<ResultatDesinstallation> executer(
    OptionsDesinstallation options,
  ) async {
    if (!options.estValide) {
      _journaliserArgumentsInconnus(options.argumentsInconnus);
      return const ResultatDesinstallation(
        etapeEchouee: EtapeDesinstallation.arguments,
      );
    }
    Journal.actuel.info(
      CategorieJournal.base,
      '$_prefixeJournal : début (${options.decrire()})',
    );
    var resultat = const ResultatDesinstallation();
    var etape = EtapeDesinstallation.inattendue;
    try {
      var chapitresTouches = false;
      if (options.doitMarquerChapitres) {
        etape = EtapeDesinstallation.chapitres;
        final comptes = await _chapitres.marquerTousNonTelecharges();
        chapitresTouches = true;
        resultat = _avec(
          resultat,
          chapitresMarques: comptes.chapitres,
          telechargementsRetires: comptes.telechargements,
        );
        Journal.actuel.info(
          CategorieJournal.base,
          '$_prefixeJournal : ${comptes.chapitres} chapitre(s) marqué(s) non '
          'téléchargé(s), ${comptes.telechargements} retiré(s) de la file',
        );
      }
      if (options.supprimerTitres) {
        etape = EtapeDesinstallation.titres;
        final titres = await _titres.supprimerTousLesTitres();
        chapitresTouches = true;
        resultat = _avec(resultat, titresSupprimes: titres);
        Journal.actuel.info(
          CategorieJournal.base,
          '$_prefixeJournal : $titres titre(s) supprimé(s)',
        );
      }
      if (chapitresTouches) {
        resultat = _avec(
          resultat,
          reglagesSupprimes: await _supprimerReglages(clesLieesAuxChapitres),
        );
      }
      if (options.supprimerSources) {
        etape = EtapeDesinstallation.sources;
        final sources = await _sources.supprimerSourcesInutilisees();
        resultat = _avec(
          resultat,
          sourcesSupprimees: sources.supprimees,
          sourcesGardees: sources.gardees,
        );
        Journal.actuel.info(
          CategorieJournal.base,
          '$_prefixeJournal : ${sources.supprimees} source(s) supprimée(s), '
          '${sources.gardees} restante(s)',
        );
        if (sources.gardees > 0) {
          // Impossible après la suppression de tous les titres, sauf base
          // incohérente : le client a demandé « toutes les sources », ce
          // n'est donc pas un succès.
          Journal.actuel.erreur(
            CategorieJournal.base,
            '$_prefixeJournal : des sources restent en base après la '
            'suppression des titres',
          );
          return _terminer(resultat.echouerA(EtapeDesinstallation.sources));
        }
        // Comme une installation neuve : MangaDex et Scan-Manga seront
        // recréés au prochain démarrage (ServiceSourcesParDefaut). Le repère
        // « déjà proposées » ne sert qu'à respecter une source supprimée une
        // à une par le client dans l'application ; « supprimer les sources »
        // à la désinstallation est une remise à zéro, pas ce choix-là.
        resultat = _avec(
          resultat,
          reglagesSupprimes:
              resultat.reglagesSupprimes +
              await _supprimerReglages(const <String>[
                ServiceParametres.cleSourcesParDefautProposees,
              ]),
        );
      }
      return _terminer(resultat);
    } catch (erreur, pile) {
      Journal.actuel.erreur(
        CategorieJournal.base,
        "$_prefixeJournal : échec à l'étape « ${etape.name} »",
        erreur: erreur,
        pile: pile,
      );
      return _terminer(resultat.echouerA(etape));
    }
  }

  /// Supprime les réglages [cles] et renvoie le nombre de réglages qui
  /// existaient. Au mieux : une erreur est seulement journalisée, car les
  /// données demandées sont déjà supprimées et un réglage resté n'empêche
  /// pas l'application de démarrer.
  Future<int> _supprimerReglages(List<String> cles) async {
    var supprimes = 0;
    for (final cle in cles) {
      try {
        if (await _parametres.supprimer(cle)) supprimes++;
      } catch (erreur) {
        Journal.actuel.avertissement(
          CategorieJournal.parametres,
          '$_prefixeJournal : réglage « $cle » non supprimé',
          erreur: erreur,
        );
      }
    }
    if (supprimes > 0) {
      Journal.actuel.info(
        CategorieJournal.parametres,
        '$_prefixeJournal : $supprimes réglage(s) devenu(s) sans objet '
        'supprimé(s)',
      );
    }
    return supprimes;
  }

  /// Journalise la fin et renvoie [resultat].
  static ResultatDesinstallation _terminer(ResultatDesinstallation resultat) {
    if (resultat.estReussi) {
      Journal.actuel.info(CategorieJournal.base, '$_prefixeJournal : réussie');
    } else {
      Journal.actuel.erreur(
        CategorieJournal.base,
        '$_prefixeJournal : échec (étape « ${resultat.etapeEchouee!.name} »)',
      );
    }
    return resultat;
  }

  /// Copie de [r] avec les comptes donnés.
  static ResultatDesinstallation _avec(
    ResultatDesinstallation r, {
    int? chapitresMarques,
    int? telechargementsRetires,
    int? titresSupprimes,
    int? sourcesSupprimees,
    int? sourcesGardees,
    int? reglagesSupprimes,
  }) => ResultatDesinstallation(
    etapeEchouee: r.etapeEchouee,
    chapitresMarques: chapitresMarques ?? r.chapitresMarques,
    telechargementsRetires: telechargementsRetires ?? r.telechargementsRetires,
    titresSupprimes: titresSupprimes ?? r.titresSupprimes,
    sourcesSupprimees: sourcesSupprimees ?? r.sourcesSupprimees,
    sourcesGardees: sourcesGardees ?? r.sourcesGardees,
    reglagesSupprimes: reglagesSupprimes ?? r.reglagesSupprimes,
  );
}

/// Exécute le mode désinstallation de bout en bout et renvoie le code de
/// sortie du processus ([codeSortieDesinstallationReussie] ou
/// [codeSortieDesinstallationEchec]). Ne lève jamais.
///
/// Ordre : analyse des [arguments] (refus sans rien ouvrir s'ils ne sont
/// pas tous reconnus), puis, s'il y a quelque chose à faire, ouverture de la
/// base (avec la migration de son dossier), [ServiceDesinstallation.executer]
/// et fermeture de la base. Le journal est vidé à la fin ; son installation
/// et sa fermeture restent à l'appelant.
///
/// [chemin] et [fabrique] : comme `ouvrirBaseDeDonnees` (les tests passent
/// une base en mémoire ou un fichier temporaire) ; sans [chemin], la base
/// de l'application. Une base absente n'est pas créée : il n'y a rien à
/// supprimer, c'est un succès.
///
/// Avec le chemin par défaut, `WidgetsFlutterBinding.ensureInitialized()`
/// doit avoir été appelé (exigence de `path_provider`).
Future<int> executerModeDesinstallation(
  List<String> arguments, {
  String? chemin,
  DatabaseFactory? fabrique,
}) async {
  var code = codeSortieDesinstallationEchec;
  try {
    code = await _executerModeDesinstallation(arguments, chemin, fabrique);
  } catch (erreur, pile) {
    // Filet de sécurité : l'installateur attend un code, jamais un
    // plantage (qui le laisserait attendre jusqu'à son délai maximal).
    Journal.actuel.erreur(
      CategorieJournal.base,
      '$_prefixeJournal : erreur imprévue',
      erreur: erreur,
      pile: pile,
    );
  }
  Journal.actuel.info(
    CategorieJournal.demarrage,
    '$_prefixeJournal : code de sortie $code',
  );
  await Journal.actuel.vider();
  return code;
}

/// Corps de [executerModeDesinstallation] (peut lever : rattrapé par
/// l'appelant).
Future<int> _executerModeDesinstallation(
  List<String> arguments,
  String? chemin,
  DatabaseFactory? fabrique,
) async {
  final options = OptionsDesinstallation.depuisArguments(arguments);
  if (!options.estValide) {
    // Refus avant d'ouvrir la base : rien ne doit être modifié.
    _journaliserArgumentsInconnus(options.argumentsInconnus);
    return codeSortieDesinstallationEchec;
  }
  if (!options.aQuelqueChoseAFaire) {
    Journal.actuel.info(
      CategorieJournal.base,
      '$_prefixeJournal : rien à modifier dans la base',
    );
    return codeSortieDesinstallationReussie;
  }
  final String cheminBase;
  try {
    cheminBase = chemin ?? await cheminParDefautBaseDeDonnees();
  } catch (erreur, pile) {
    Journal.actuel.erreur(
      CategorieJournal.base,
      '$_prefixeJournal : dossier de la base introuvable',
      erreur: erreur,
      pile: pile,
    );
    return codeSortieDesinstallationEchec;
  }
  // Ouvrir une base absente la créerait (avec toutes les migrations) juste
  // avant la désinstallation : rien à supprimer, donc rien à créer.
  if (cheminBase != inMemoryDatabasePath && !await File(cheminBase).exists()) {
    Journal.actuel.info(
      CategorieJournal.base,
      '$_prefixeJournal : aucune base, rien à modifier',
    );
    return codeSortieDesinstallationReussie;
  }
  final Database base;
  try {
    base = await ouvrirBaseDeDonnees(chemin: cheminBase, fabrique: fabrique);
  } catch (erreur, pile) {
    // Application encore ouverte (fichier verrouillé), base d'une version
    // plus récente… : rien n'est modifié.
    Journal.actuel.erreur(
      CategorieJournal.base,
      '$_prefixeJournal : base impossible à ouvrir',
      erreur: erreur,
      pile: pile,
    );
    return codeSortieDesinstallationEchec;
  }
  try {
    final resultat = await ServiceDesinstallation.surBase(base)
        .executer(options);
    return resultat.codeSortie;
  } finally {
    try {
      await base.close();
    } catch (erreur) {
      // Les écritures sont déjà validées (une transaction par étape) : une
      // fermeture manquée ne change pas le résultat.
      Journal.actuel.avertissement(
        CategorieJournal.base,
        '$_prefixeJournal : fermeture de la base impossible',
        erreur: erreur,
      );
    }
  }
}

/// Note des arguments refusés, sans recopier un éventuel chemin entier.
void _journaliserArgumentsInconnus(List<String> inconnus) {
  final apercu = inconnus
      .map(
        (argument) => argument.length > _longueurMaxArgumentJournal
            ? '${argument.substring(0, _longueurMaxArgumentJournal)}…'
            : argument,
      )
      .join(' ');
  Journal.actuel.erreur(
    CategorieJournal.base,
    '$_prefixeJournal : ${inconnus.length} argument(s) non reconnu(s) '
    "($apercu) : rien n'est modifié",
  );
}
