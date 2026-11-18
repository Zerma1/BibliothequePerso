/// Journal de l'application écrit sur le disque, pour que le client puisse
/// joindre le fichier à ses retours de test.
///
/// ```
/// <dossier de l'application>/journaux/journal-2026-11-18.log
/// <dossier de l'application>/journaux/journal-2026-11-18.2.log   (> ~5 Mo)
/// ```
///
/// Une ligne par entrée :
///
/// ```
/// 2026-11-18T14:03:12.345 INFO   [app] reseau : GET https://… : 200
/// 2026-11-18T14:03:13.002 ERREUR [fond] telechargement : Chapitre 12 abandonné
///     erreur : SocketException: …
///     pile :
///       #0 …
/// ```
///
/// Le `<dossier de l'application>` est celui des rapports d'erreur et des
/// exports (`Documents/bibliotheque_perso/` par défaut), jamais le dossier
/// des chapitres (qui peut être un NAS éteint).
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:path/path.dart' as chemins;

import '../modeles/journal.dart';
import 'stockage_telechargements.dart'
    show cheminParDefautDossierTelechargements;

/// Nom du sous-dossier des journaux dans le dossier de l'application.
const String nomDossierJournaux = 'journaux';

/// Nombre de jours de journaux gardés, aujourd'hui compris : les fichiers
/// plus anciens sont supprimés à l'ouverture et au changement de jour.
const int joursConservationJournaux = 14;

/// Taille au-delà de laquelle on passe au fichier suivant du même jour
/// (`journal-AAAA-MM-JJ.2.log`) : 5 Mio. Un lot n'est jamais coupé, d'où un
/// plafond approximatif.
const int tailleMaxFichierJournal = 5 * 1024 * 1024;

/// Nombre maximal de fichiers pour un même jour (`.log`, `.2.log`…
/// `.10.log`).
///
/// Garde-fou contre une boucle qui journaliserait sans fin : au-delà (environ
/// 50 Mio dans la journée), les entrées du jour sont abandonnées plutôt que
/// de remplir le disque.
const int nombreMaxFichiersJournalParJour = 10;

/// Délai maximal avant l'écriture d'une entrée sur le disque.
///
/// Les entrées sont regroupées en lots pour ne pas ouvrir le fichier à
/// chaque ligne ; une erreur est écrite tout de suite (sans attendre ce
/// délai) pour ne pas être perdue si l'application s'arrête.
const Duration intervalleVidageJournal = Duration(seconds: 2);

/// Durée maximale d'attente du verrou du fichier pour un lot.
///
/// Au-delà (verrou tenu par un processus bloqué, système de fichiers sans
/// verrous), le lot est écrit sans verrou : mieux vaut un très rare
/// chevauchement de lignes qu'un journal figé.
const Duration delaiMaxVerrouJournal = Duration(seconds: 2);

/// Intervalle entre deux essais de prise du verrou du fichier.
const Duration intervalleEssaisVerrouJournal = Duration(milliseconds: 20);

/// Durée maximale pendant laquelle [JournalFichier.vider] fait attendre son
/// appelant (fermeture, mise en pause, export…).
///
/// L'écriture continue en arrière-plan au-delà ; seul l'appelant cesse
/// d'attendre. Un peu plus que [delaiMaxVerrouJournal] pour qu'un lot
/// retardé par le verrou ait le temps d'être écrit.
const Duration delaiMaxVidageJournal = Duration(seconds: 5);

/// Nombre d'entrées en attente qui déclenche une écriture immédiate.
const int seuilVidageImmediatJournal = 200;

/// Nombre maximal d'entrées gardées en mémoire en attendant l'écriture.
///
/// Si le disque est très lent, les plus anciennes sont abandonnées plutôt
/// que de remplir la mémoire.
const int nombreMaxEntreesEnAttenteJournal = 5000;

/// Longueur maximale (en caractères) d'un message ou du texte d'une erreur.
///
/// Empêche d'écrire une page HTML complète dans le journal (confidentialité
/// et taille des fichiers) : le reste est remplacé par un compteur.
const int longueurMaxMessageJournal = 2000;

/// Nombre maximal de lignes de pile écrites sous une erreur.
const int nombreMaxLignesPileJournal = 40;

/// Nom d'isolat écrit sur les lignes de l'application.
const String nomIsolatApplication = 'app';

/// Nom d'isolat écrit sur les lignes de la tâche de fond Android.
const String nomIsolatFond = 'fond';

/// Retrait des lignes de suite d'une entrée (message sur plusieurs lignes,
/// erreur, pile) : une ligne qui ne commence pas par une date appartient à
/// l'entrée précédente.
const String _retrait = '    ';

/// `journal-AAAA-MM-JJ.log` ou `journal-AAAA-MM-JJ.<numero>.log`.
final RegExp _nomFichierJournal = RegExp(
  r'^journal-(\d{4})-(\d{2})-(\d{2})(?:\.(\d+))?\.log$',
);

/// Chemin du dossier des journaux dans le [dossierApplication].
String cheminDossierJournaux(String dossierApplication) =>
    chemins.join(dossierApplication, nomDossierJournaux);

/// Nom du fichier de journal du jour [cleJour] (`AAAA-MM-JJ`) : `numero` 1
/// donne `journal-AAAA-MM-JJ.log`, les suivants `journal-AAAA-MM-JJ.2.log`…
String nomFichierJournal(String cleJour, int numero) =>
    numero <= 1 ? 'journal-$cleJour.log' : 'journal-$cleJour.$numero.log';

/// Fichier de journal reconnu dans le dossier des journaux.
class FichierJournal {
  /// Crée la description d'un fichier de journal.
  const FichierJournal({
    required this.chemin,
    required this.jour,
    required this.numero,
  });

  /// Chemin complet du fichier.
  final String chemin;

  /// Jour couvert par le fichier (minuit, heure locale).
  final DateTime jour;

  /// Numéro du fichier dans la journée (1 pour `journal-AAAA-MM-JJ.log`).
  final int numero;

  /// Nom du fichier, sans le dossier.
  String get nom => chemins.basename(chemin);

  @override
  bool operator ==(Object other) =>
      other is FichierJournal &&
      other.chemin == chemin &&
      other.jour == jour &&
      other.numero == numero;

  @override
  int get hashCode => Object.hash(chemin, jour, numero);

  @override
  String toString() => 'FichierJournal($chemin)';
}

/// Liste les fichiers de journal du [dossierJournaux], du plus ancien au plus
/// récent (jour puis numéro).
///
/// Les autres fichiers du dossier sont ignorés. Renvoie une liste vide si le
/// dossier n'existe pas ou ne peut pas être lu (jamais d'exception).
Future<List<FichierJournal>> listerFichiersJournal(
  String dossierJournaux,
) async {
  final fichiers = <FichierJournal>[];
  try {
    final dossier = Directory(dossierJournaux);
    if (!await dossier.exists()) return fichiers;
    await for (final element in dossier.list(followLinks: false)) {
      if (element is! File) continue;
      final correspondance = _nomFichierJournal.firstMatch(
        chemins.basename(element.path),
      );
      if (correspondance == null) continue;
      fichiers.add(
        FichierJournal(
          chemin: element.path,
          jour: DateTime(
            int.parse(correspondance[1]!),
            int.parse(correspondance[2]!),
            int.parse(correspondance[3]!),
          ),
          numero: int.parse(correspondance[4] ?? '1'),
        ),
      );
    }
  } catch (_) {
    // Dossier illisible : on renvoie ce qui a pu être lu.
  }
  fichiers.sort((a, b) {
    final parJour = a.jour.compareTo(b.jour);
    return parJour != 0 ? parJour : a.numero.compareTo(b.numero);
  });
  return fichiers;
}

/// Charge les [nombre] dernières lignes des journaux du [dossierJournaux],
/// dans l'ordre chronologique, en remontant sur les fichiers précédents si
/// le dernier ne suffit pas.
///
/// Sert à joindre la fin du journal à un rapport d'erreur. Les octets
/// invalides en UTF-8 sont remplacés ; un fichier illisible est sauté.
/// Jamais d'exception.
Future<List<String>> chargerDernieresLignesJournal(
  String dossierJournaux,
  int nombre,
) async {
  if (nombre <= 0) return const [];
  final fichiers = await listerFichiersJournal(dossierJournaux);
  final resultat = <String>[];
  for (final fichier in fichiers.reversed) {
    List<String> lignes;
    try {
      final octets = await File(fichier.chemin).readAsBytes();
      lignes = utf8.decode(octets, allowMalformed: true).split('\n');
    } catch (_) {
      continue;
    }
    // Fin de fichier : la dernière ligne vide après le dernier `\n`.
    if (lignes.isNotEmpty && lignes.last.isEmpty) lignes.removeLast();
    final manquantes = nombre - resultat.length;
    final debut = lignes.length > manquantes ? lignes.length - manquantes : 0;
    resultat.insertAll(
      0,
      lignes.sublist(debut).map((ligne) => ligne.replaceAll('\r', '')),
    );
    if (resultat.length >= nombre) break;
  }
  return resultat;
}

/// Clé `AAAA-MM-JJ` du jour local de [instant].
String _cleJour(DateTime instant) =>
    '${_chiffres(instant.year, 4)}-${_chiffres(instant.month, 2)}-'
    '${_chiffres(instant.day, 2)}';

/// [valeur] complétée par des zéros à gauche jusqu'à [largeur] chiffres.
String _chiffres(int valeur, int largeur) =>
    valeur.toString().padLeft(largeur, '0');

/// Horodatage local ISO 8601 à la milliseconde : `2026-11-18T14:03:12.345`.
String formaterHorodatageJournal(DateTime instant) {
  final local = instant.toLocal();
  return '${_cleJour(local)}T${_chiffres(local.hour, 2)}:'
      '${_chiffres(local.minute, 2)}:${_chiffres(local.second, 2)}.'
      '${_chiffres(local.millisecond, 3)}';
}

/// [texte] coupé à [longueurMaxMessageJournal] caractères, avec le nombre de
/// caractères retirés.
String _couper(String texte) {
  if (texte.length <= longueurMaxMessageJournal) return texte;
  final retires = texte.length - longueurMaxMessageJournal;
  return '${texte.substring(0, longueurMaxMessageJournal)}'
      ' … ($retires caractères coupés)';
}

/// [texte] coupé puis masqué ([masquerDonneesSensibles]).
String _nettoyer(String texte) => masquerDonneesSensibles(_couper(texte));

/// Lignes de [texte] (séparateurs `\n`, `\r\n` ou `\r`).
List<String> _lignes(String texte) => texte.split(RegExp(r'\r\n|\r|\n'));

/// Texte complet (avec `\n` final) d'une entrée du journal.
///
/// - première ligne : horodatage, niveau, `[isolat]`, catégorie, message ;
/// - lignes suivantes, en retrait : suite du message, `erreur : …`, pile
///   (au plus [nombreMaxLignesPileJournal] lignes).
///
/// Le message et l'erreur sont coupés à [longueurMaxMessageJournal]
/// caractères puis masqués ([masquerDonneesSensibles]).
String formaterEntreeJournal({
  required DateTime instant,
  required NiveauJournal niveau,
  required String categorie,
  required String message,
  required String nomIsolat,
  Object? erreur,
  StackTrace? pile,
}) {
  final tampon = StringBuffer()
    ..write(formaterHorodatageJournal(instant))
    ..write(' ')
    ..write(niveau.etiquette.padRight(6))
    ..write(' [')
    ..write(nomIsolat)
    ..write('] ')
    ..write(categorie)
    ..write(' : ');
  final lignesMessage = _lignes(_nettoyer(message));
  tampon.writeln(lignesMessage.first);
  for (final ligne in lignesMessage.skip(1)) {
    tampon.writeln('$_retrait$ligne');
  }
  if (erreur != null) {
    String texteErreur;
    try {
      texteErreur = erreur.toString();
    } catch (_) {
      texteErreur = '(${erreur.runtimeType} illisible)';
    }
    final lignesErreur = _lignes(_nettoyer(texteErreur));
    tampon.writeln('${_retrait}erreur : ${lignesErreur.first}');
    for (final ligne in lignesErreur.skip(1)) {
      tampon.writeln('$_retrait  $ligne');
    }
  }
  if (pile != null) {
    final lignesPile = _lignes(pile.toString())
        .where((ligne) => ligne.trim().isNotEmpty)
        .toList();
    if (lignesPile.isNotEmpty) {
      tampon.writeln('${_retrait}pile :');
      for (final ligne in lignesPile.take(nombreMaxLignesPileJournal)) {
        tampon.writeln('$_retrait  ${masquerDonneesSensibles(ligne)}');
      }
      final restantes = lignesPile.length - nombreMaxLignesPileJournal;
      if (restantes > 0) {
        tampon.writeln('$_retrait  … ($restantes lignes coupées)');
      }
    }
  }
  return tampon.toString();
}

/// Entrée formatée, en attente d'écriture.
class _EntreeEnAttente {
  const _EntreeEnAttente(this.cleJour, this.texte);

  /// Jour du fichier qui recevra l'entrée (`AAAA-MM-JJ`).
  final String cleJour;

  /// Texte complet de l'entrée.
  final String texte;
}

/// Journal écrit dans des fichiers `journal-AAAA-MM-JJ.log` (un par jour).
///
/// - **Jamais bloquant** : [journaliser] formate l'entrée et la met en file ;
///   l'écriture se fait plus tard, par lots ([intervalleVidageJournal], tout
///   de suite pour une erreur).
/// - **Jamais d'exception** : une écriture qui échoue (disque plein, dossier
///   supprimé, droits) est ignorée et le lot est perdu.
/// - **Plusieurs isolats** (application et tâche de fond Android) peuvent
///   écrire dans le même fichier : chaque lot ouvre le fichier en ajout,
///   prend un verrou exclusif (attendu au plus [delaiMaxVerrouJournal],
///   sinon écriture sans verrou), se place à la fin, écrit en un seul appel
///   et ferme le fichier.
/// - **Jamais figé** : [vider] fait attendre son appelant au plus
///   [delaiMaxVidageJournal]. LIMITE : si une écriture ne se termine jamais
///   (disque figé), plus rien n'est écrit pendant cette session, mais la
///   mémoire reste bornée (entrées en attente plafonnées, un seul vidage).
/// - **Rotation** : un fichier par jour, [joursConservationJournaux] jours
///   gardés, fichier suivant du même jour au-delà de
///   [tailleMaxFichierJournal].
///
/// LIMITE : sur Android et Linux, le verrou de fichier (`fcntl`) appartient
/// au processus, pas à l'isolat : il ne départage donc pas l'application et
/// la tâche de fond Android, qui tournent dans le même processus. Il reste
/// une très courte fenêtre (entre « se placer à la fin » et « écrire ») où
/// deux lots simultanés pourraient se chevaucher ; au pire, quelques lignes
/// d'un lot seraient écrasées. Sur Windows, le verrou est propre à chaque
/// ouverture du fichier et départage aussi les isolats.
class JournalFichier extends Journal {
  /// Crée un journal qui écrit dans [dossier] (créé à la première écriture).
  ///
  /// - [niveauMinimal] : entrées moins graves ignorées (info par défaut,
  ///   débogage désactivé) ;
  /// - [nomIsolat] : écrit sur chaque ligne ([nomIsolatApplication] ou
  ///   [nomIsolatFond]) ;
  /// - [horloge] : heure courante (les tests la fixent) ;
  /// - [intervalleVidage], [tailleMaxFichier] et [joursConservation] :
  ///   réglages de la rotation (les tests les réduisent) ;
  /// - [delaiMaxVerrou] et [delaiMaxVidage] : attentes maximales du verrou
  ///   du fichier et de [vider] (les tests les réduisent) ;
  /// - [ecrivain] : remplace l'ajout d'un lot à un fichier (les tests
  ///   simulent ainsi une écriture qui ne se termine jamais).
  JournalFichier(
    this.dossier, {
    this.niveauMinimal = NiveauJournal.info,
    this.nomIsolat = nomIsolatApplication,
    DateTime Function()? horloge,
    this.intervalleVidage = intervalleVidageJournal,
    this.tailleMaxFichier = tailleMaxFichierJournal,
    this.joursConservation = joursConservationJournaux,
    this.delaiMaxVerrou = delaiMaxVerrouJournal,
    this.delaiMaxVidage = delaiMaxVidageJournal,
    this.ecrivain,
  }) : _horloge = horloge ?? DateTime.now;

  /// Crée le journal dans `<dossierApplication>/journaux/` et supprime les
  /// fichiers de plus de [joursConservationJournaux] jours.
  ///
  /// Sans [dossierApplication] : dossier par défaut de l'application
  /// (`cheminParDefautDossierTelechargements()`, le même que les rapports
  /// d'erreur et les exports). Renvoie `null` si ce dossier ne peut pas être
  /// déterminé (jamais d'exception) : l'application démarre alors sans
  /// journal de fichier.
  static Future<JournalFichier?> ouvrir({
    String? dossierApplication,
    NiveauJournal niveauMinimal = NiveauJournal.info,
    String nomIsolat = nomIsolatApplication,
  }) async {
    try {
      final racine =
          dossierApplication ?? await cheminParDefautDossierTelechargements();
      final journal = JournalFichier(
        cheminDossierJournaux(racine),
        niveauMinimal: niveauMinimal,
        nomIsolat: nomIsolat,
      );
      await journal.supprimerAnciensJournaux();
      return journal;
    } catch (_) {
      return null;
    }
  }

  /// [ouvrir] puis installe le journal dans [Journal.actuel] (pour l'isolat
  /// courant).
  ///
  /// Si le journal ne peut pas être ouvert, [Journal.actuel] reste inchangé
  /// et `null` est renvoyé.
  static Future<JournalFichier?> installer({
    String? dossierApplication,
    NiveauJournal niveauMinimal = NiveauJournal.info,
    String nomIsolat = nomIsolatApplication,
  }) async {
    final journal = await ouvrir(
      dossierApplication: dossierApplication,
      niveauMinimal: niveauMinimal,
      nomIsolat: nomIsolat,
    );
    if (journal != null) Journal.actuel = journal;
    return journal;
  }

  /// Dossier des fichiers de journal.
  final String dossier;

  /// Niveau minimal des entrées écrites ; modifiable à tout moment (par
  /// exemple pour activer le débogage depuis les réglages).
  NiveauJournal niveauMinimal;

  /// Nom de l'isolat écrit sur chaque ligne (`app`, `fond`).
  final String nomIsolat;

  /// Délai maximal avant l'écriture d'une entrée qui n'est pas une erreur.
  final Duration intervalleVidage;

  /// Taille au-delà de laquelle on passe au fichier suivant du même jour.
  final int tailleMaxFichier;

  /// Nombre de jours de fichiers gardés, aujourd'hui compris.
  final int joursConservation;

  /// Attente maximale du verrou du fichier pour un lot (au-delà : écriture
  /// sans verrou).
  final Duration delaiMaxVerrou;

  /// Attente maximale de l'appelant de [vider].
  final Duration delaiMaxVidage;

  /// Écriture de [octets] à la fin du fichier [chemin], à la place de
  /// l'écriture réelle (ouverture en ajout, verrou, écriture, fermeture).
  /// `null` hors tests.
  final Future<void> Function(String chemin, List<int> octets)? ecrivain;

  final DateTime Function() _horloge;

  /// Entrées formatées, pas encore écrites.
  final List<_EntreeEnAttente> _enAttente = [];

  /// Minuterie du prochain vidage, s'il est planifié.
  Timer? _minuterie;

  /// Boucle d'écriture en cours, ou `null` : un seul vidage à la fois pour
  /// ce journal.
  Future<void>? _vidageEnCours;

  /// Un vidage a été demandé pendant la boucle en cours : elle fait un tour
  /// de plus. Un simple drapeau plutôt qu'une chaîne de `Future` : si une
  /// écriture ne se termine jamais, les demandes suivantes ne s'accumulent
  /// pas (les entrées en attente restent plafonnées par
  /// [nombreMaxEntreesEnAttenteJournal]).
  bool _vidageDemande = false;

  /// Numéro du fichier en cours pour chaque jour (cache : évite de tester
  /// les fichiers 1, 2… à chaque lot).
  final Map<String, int> _numeroParJour = {};

  /// Jour du dernier nettoyage des vieux fichiers.
  String? _jourDernierNettoyage;

  bool _estFerme = false;

  /// `true` une fois [fermer] appelée.
  bool get estFerme => _estFerme;

  @override
  bool estActif(NiveauJournal niveau) =>
      !_estFerme && niveau.estAuMoins(niveauMinimal);

  @override
  void journaliser(
    NiveauJournal niveau,
    String categorie,
    String message, {
    Object? erreur,
    StackTrace? pile,
  }) {
    try {
      if (!estActif(niveau)) return;
      final instant = _horloge();
      _enAttente.add(
        _EntreeEnAttente(
          _cleJour(instant.toLocal()),
          formaterEntreeJournal(
            instant: instant,
            niveau: niveau,
            categorie: categorie,
            message: message,
            nomIsolat: nomIsolat,
            erreur: erreur,
            pile: pile,
          ),
        ),
      );
      if (_enAttente.length > nombreMaxEntreesEnAttenteJournal) {
        _enAttente.removeRange(
          0,
          _enAttente.length - nombreMaxEntreesEnAttenteJournal,
        );
      }
      if (niveau == NiveauJournal.erreur ||
          _enAttente.length >= seuilVidageImmediatJournal) {
        unawaited(vider());
      } else {
        _minuterie ??= Timer(intervalleVidage, () {
          _minuterie = null;
          unawaited(vider());
        });
      }
    } catch (_) {
      // Journaliser ne doit jamais faire échouer l'appelant.
    }
  }

  /// Écrit les entrées en attente.
  ///
  /// Un seul vidage tourne à la fois : un appel pendant un vidage demande
  /// un tour de plus à la boucle en cours (les entrées arrivées entre-temps
  /// sont écrites par ce tour).
  ///
  /// Ne fait jamais attendre l'appelant plus de [delaiMaxVidage] : si
  /// l'écriture est bloquée (disque figé), le `Future` se termine quand même
  /// et l'écriture continue en arrière-plan. Ne lève jamais d'exception.
  @override
  Future<void> vider() {
    try {
      _minuterie?.cancel();
      _minuterie = null;
      final enCours = _vidageEnCours;
      final Future<void> attente;
      if (enCours != null) {
        _vidageDemande = true;
        attente = enCours;
      } else {
        attente = _vidageEnCours = _boucleVidage();
      }
      return attente
          .timeout(delaiMaxVidage, onTimeout: () {})
          .catchError((Object _) {});
    } catch (_) {
      return Future<void>.value();
    }
  }

  /// Écrit les lots tant que de nouveaux vidages sont demandés.
  Future<void> _boucleVidage() async {
    try {
      do {
        _vidageDemande = false;
        try {
          await _ecrireLot();
        } catch (_) {
          // Écriture impossible : le lot est perdu, sans conséquence.
        }
      } while (_vidageDemande);
    } finally {
      _vidageEnCours = null;
    }
  }

  @override
  Future<void> fermer() async {
    if (_estFerme) return;
    _estFerme = true;
    await vider();
  }

  /// Liste les fichiers de ce journal, du plus ancien au plus récent.
  Future<List<FichierJournal>> listerFichiers() async {
    await vider();
    return listerFichiersJournal(dossier);
  }

  /// Charge les [nombre] dernières lignes du journal (après avoir écrit les
  /// entrées en attente), dans l'ordre chronologique.
  Future<List<String>> chargerDernieresLignes(int nombre) async {
    await vider();
    return chargerDernieresLignesJournal(dossier, nombre);
  }

  /// Supprime les fichiers antérieurs aux [joursConservation] derniers
  /// jours (aujourd'hui compris). Jamais d'exception.
  Future<void> supprimerAnciensJournaux() async {
    try {
      final maintenant = _horloge().toLocal();
      _jourDernierNettoyage = _cleJour(maintenant);
      final limite = DateTime(
        maintenant.year,
        maintenant.month,
        maintenant.day - (joursConservation - 1),
      );
      for (final fichier in await listerFichiersJournal(dossier)) {
        if (!fichier.jour.isBefore(limite)) continue;
        try {
          await File(fichier.chemin).delete();
        } catch (_) {
          // Fichier ouvert ailleurs ou déjà supprimé : nouvel essai plus tard.
        }
      }
    } catch (_) {
      // Rien à nettoyer ou dossier illisible.
    }
  }

  /// Écrit toutes les entrées en attente, regroupées par jour.
  Future<void> _ecrireLot() async {
    if (_enAttente.isEmpty) return;
    final lot = List<_EntreeEnAttente>.of(_enAttente);
    _enAttente.clear();
    // Ordre d'insertion conservé : les jours restent dans l'ordre.
    final parJour = <String, StringBuffer>{};
    for (final entree in lot) {
      (parJour[entree.cleJour] ??= StringBuffer()).write(entree.texte);
    }
    try {
      await Directory(dossier).create(recursive: true);
    } catch (_) {
      return;
    }
    for (final MapEntry(key: cleJour, value: contenu) in parJour.entries) {
      try {
        await _ajouterAuFichier(cleJour, contenu.toString());
      } catch (_) {
        // Lot de ce jour perdu ; on essaie quand même les autres jours.
      }
    }
    if (_jourDernierNettoyage != _cleJour(_horloge().toLocal())) {
      await supprimerAnciensJournaux();
    }
  }

  /// Ajoute [contenu] à la fin du fichier en cours du jour [cleJour], en
  /// passant au fichier suivant si celui-ci dépasse [tailleMaxFichier].
  Future<void> _ajouterAuFichier(String cleJour, String contenu) async {
    final octets = utf8.encode(contenu);
    var numero = _numeroParJour[cleJour] ?? 1;
    File fichier;
    while (true) {
      if (numero > nombreMaxFichiersJournalParJour) {
        // Plafond du jour atteint : on abandonne ce lot.
        _numeroParJour[cleJour] = numero;
        return;
      }
      fichier = File(chemins.join(dossier, nomFichierJournal(cleJour, numero)));
      final taille = await fichier.exists() ? await fichier.length() : 0;
      // Un fichier vide reçoit toujours le lot, même s'il est gros : sinon
      // un lot plus grand que le plafond ne serait jamais écrit.
      if (taille > 0 && taille + octets.length > tailleMaxFichier) {
        numero++;
        continue;
      }
      break;
    }
    _numeroParJour[cleJour] = numero;
    final ecrivainTest = ecrivain;
    if (ecrivainTest != null) {
      await ecrivainTest(fichier.path, octets);
      return;
    }
    final acces = await fichier.open(mode: FileMode.append);
    try {
      // Verrou exclusif : un autre isolat ou processus attend la fin de
      // cette écriture (voir la LIMITE de la classe pour Android et Linux).
      // Au-delà de [delaiMaxVerrou], on écrit sans verrou.
      await _prendreVerrou(acces);
      // Fin réelle du fichier, une fois le verrou obtenu : un autre isolat a
      // pu écrire depuis l'ouverture.
      await acces.setPosition(await acces.length());
      await acces.writeFrom(octets);
    } finally {
      // La fermeture libère aussi le verrou.
      await acces.close();
    }
  }

  /// Essaie de prendre le verrou exclusif de [acces] pendant au plus
  /// [delaiMaxVerrou] ; renvoie `true` s'il est pris.
  ///
  /// Essais non bloquants répétés plutôt qu'un `lock` bloquant coupé par un
  /// `timeout` : un `RandomAccessFile` refuse toute autre opération tant
  /// qu'un appel est en cours, et un verrou bloquant abandonné laisserait le
  /// fichier inutilisable (impossible d'écrire sans verrou ensuite). Un
  /// échec (verrou tenu ailleurs, ou verrous indisponibles sur un système de
  /// fichiers réseau) est réessayé jusqu'au délai.
  ///
  /// LIMITE : sur Windows, une écriture sans verrou dans une zone verrouillée
  /// par une autre ouverture est refusée par le système ; le lot est alors
  /// perdu, mais le journal n'est pas figé.
  Future<bool> _prendreVerrou(RandomAccessFile acces) async {
    final chrono = Stopwatch()..start();
    while (true) {
      try {
        await acces.lock(FileLock.exclusive);
        return true;
      } catch (_) {
        if (chrono.elapsed >= delaiMaxVerrou) return false;
        await Future<void>.delayed(intervalleEssaisVerrouJournal);
      }
    }
  }
}
