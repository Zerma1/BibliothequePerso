/// Journal de l'application vu par l'interface : dossier et fichiers des
/// journaux, « Exporter le journal » et réglage « Journal détaillé
/// (débogage) ».
///
/// L'écriture du journal elle-même est faite par `JournalFichier`
/// (`lib/donnees/journal_fichier.dart`), installé au démarrage dans
/// `Journal.actuel`.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:path/path.dart' as chemins;

import '../donnees/depot_parametres.dart';
import '../donnees/journal_fichier.dart';
import '../donnees/stockage_telechargements.dart'
    show cheminParDefautDossierTelechargements;
import '../modeles/journal.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'service_parametres.dart';
import 'service_rapports_erreur.dart' show ServiceRapportsErreur;

export '../donnees/journal_fichier.dart' show FichierJournal;

/// Accès au journal de l'application pour l'écran Paramètres.
///
/// Jamais d'exception pour la consultation ([listerFichiers],
/// [chargerJournalDetaille], [appliquerReglageJournal]) ; seul
/// [exporterJournal] lève une [ErreurService] au message clair (journal
/// vide, fichier impossible à écrire).
class ServiceJournal {
  /// Crée le service.
  ///
  /// - [dossierJournaux] : dossier lu par [listerFichiers] et
  ///   [exporterJournal] (celui du `JournalFichier` installé) ;
  /// - [dossierRapports] : dossier où [exporterJournal] écrit la copie (le
  ///   même que les rapports d'erreur, que le client sait déjà retrouver) ;
  /// - [depotParametres] : stockage du réglage [ServiceParametres.cleJournalDetaille]
  ///   (sans lui, le réglage n'est pas enregistré et vaut « désactivé ») ;
  /// - [horloge] : heure courante (les tests la fixent) ;
  /// - [delaiJournal] : délai maximal accordé au journal installé pour
  ///   écrire ses entrées en attente ([delaiMaxJournal] par défaut ; les
  ///   tests le raccourcissent).
  ServiceJournal({
    required this.dossierJournaux,
    required this.dossierRapports,
    DepotParametres? depotParametres,
    DateTime Function()? horloge,
    Duration delaiJournal = delaiMaxJournal,
  }) : _depotParametres = depotParametres,
       _horloge = horloge ?? DateTime.now,
       _delaiJournal = delaiJournal;

  /// Crée le service sur les dossiers par défaut de l'application :
  /// `<dossier documents>/bibliotheque_perso/journaux/` et `…/rapports/`.
  ///
  /// LIMITE : sur Android, ces dossiers sont dans le dossier **privé** de
  /// l'application (comme les rapports d'erreur, voir
  /// `ServiceRapportsErreur.parDefaut`) : le client ne peut pas y ouvrir le
  /// journal exporté sans un partage de fichier (paquet à proposer au
  /// client).
  static Future<ServiceJournal> parDefaut({
    DepotParametres? depotParametres,
  }) async {
    final racine = await cheminParDefautDossierTelechargements();
    return ServiceJournal(
      dossierJournaux: cheminDossierJournaux(racine),
      dossierRapports: chemins.join(racine, nomDossierRapports),
      depotParametres: depotParametres,
    );
  }

  /// Dossier des fichiers de journal (`…/journaux/`), à montrer au client.
  final String dossierJournaux;

  /// Dossier où les journaux exportés sont copiés (`…/rapports/`).
  final String dossierRapports;

  final DepotParametres? _depotParametres;
  final DateTime Function() _horloge;
  final Duration _delaiJournal;

  /// Export en cours : un double clic reçoit le même fichier au lieu d'en
  /// écrire un second.
  Future<String>? _exportEnCours;

  // -------------------------------------------------------------- Fichiers

  /// Fichiers de journal présents, du plus ancien au plus récent (vide si
  /// le dossier n'existe pas encore). Les entrées en attente du journal
  /// installé sont écrites d'abord, pour que le fichier du jour soit à
  /// jour. Ne lève jamais.
  Future<List<FichierJournal>> listerFichiers() async {
    await _viderJournal();
    return listerFichiersJournal(dossierJournaux);
  }

  /// Copie le journal des [jours] derniers jours (aujourd'hui compris, 1 par
  /// défaut : le fichier du jour) dans un seul fichier
  /// `journal_export_AAAAMMJJ_HHMMSS.log` (heure locale, celle des lignes du
  /// journal) du [dossierRapports], et renvoie son chemin complet.
  ///
  /// [jours] est ramené entre 1 et [joursJournalExportesMaximum]. Les
  /// fichiers sont mis bout à bout dans l'ordre chronologique ; le texte est
  /// déjà masqué des données sensibles à l'écriture du journal. Au plus
  /// [nombreMaximalJournauxExportes] exports sont gardés (les plus anciens
  /// sont effacés).
  ///
  /// Lève une [ErreurService] si le journal de ces jours est vide ou si la
  /// copie ne peut pas être écrite (aucun fichier n'est alors laissé à
  /// moitié).
  Future<String> exporterJournal({int jours = joursJournalExportesParDefaut}) {
    final enCours = _exportEnCours;
    if (enCours != null) return enCours;
    final nouveau = _exporter(jours);
    _exportEnCours = nouveau;
    // Libéré après coup, réussite ou échec : un nouvel export reste possible.
    nouveau.then<void>(
      (_) => _exportEnCours = null,
      onError: (Object _) => _exportEnCours = null,
    );
    return nouveau;
  }

  Future<String> _exporter(int jours) async {
    final nombreJours = jours.clamp(1, joursJournalExportesMaximum);
    final maintenant = _horloge().toLocal();
    // Noté avant la copie : la ligne figure ainsi dans le fichier exporté et
    // montre au lecteur quand l'export a été fait.
    Journal.actuel.info(
      CategorieJournal.interface,
      'Export du journal ($nombreJours jour(s)) demandé',
    );
    await _viderJournal();
    final limite = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day - (nombreJours - 1),
    );
    final aCopier = <FichierJournal>[
      for (final fichier in await listerFichiersJournal(dossierJournaux))
        if (!fichier.jour.isBefore(limite)) fichier,
    ];
    if (aCopier.isEmpty) {
      throw const ErreurService(
        "Le journal est vide : rien n'a encore été noté pour ces jours.",
      );
    }
    final dossier = Directory(dossierRapports);
    File? partiel;
    try {
      await dossier.create(recursive: true);
      final cible = await _reserverFichier(dossier, maintenant);
      // Copie dans un `.part` renommé à la fin : un export interrompu ne
      // laisse jamais un fichier tronqué qui passerait pour complet.
      partiel = File('${cible.path}.part');
      final sortie = partiel.openWrite();
      try {
        for (final fichier in aCopier) {
          try {
            await sortie.addStream(File(fichier.chemin).openRead());
          } on FileSystemException {
            // Fichier effacé par la rotation entre la liste et la copie : les
            // autres jours restent utiles.
          }
        }
      } finally {
        await sortie.close();
      }
      await partiel.rename(cible.path);
      partiel = null;
      await _supprimerAnciensExports(dossier);
      Journal.actuel.info(
        CategorieJournal.interface,
        'Journal exporté : ${chemins.basename(cible.path)} '
        '(${aCopier.length} fichier(s))',
      );
      return cible.path;
    } on FileSystemException catch (erreur) {
      try {
        if (partiel != null && await partiel.exists()) await partiel.delete();
      } on FileSystemException {
        // Un `.part` restant n'est qu'un fichier en trop.
      }
      Journal.actuel.erreur(
        CategorieJournal.interface,
        'Export du journal impossible',
        erreur: erreur,
      );
      throw ErreurService("Le journal n'a pas pu être exporté.", cause: erreur);
    }
  }

  /// Nom libre pour un export de [date] : `journal_export_20261118_143000.log`,
  /// puis `…_2.log`, `…_3.log` dans la même seconde.
  Future<File> _reserverFichier(Directory dossier, DateTime date) async {
    final horodatage = horodatageExport(date);
    // Borné : la borne évite toute boucle sans fin.
    for (var numero = 1; numero <= nombreMaximalJournauxExportes; numero++) {
      final suffixe = numero == 1 ? '' : '_$numero';
      final fichier = File(
        chemins.join(
          dossier.path,
          '$prefixeFichierJournalExporte$horodatage$suffixe.'
          '$extensionFichierJournalExporte',
        ),
      );
      if (!await fichier.exists()) return fichier;
    }
    throw FileSystemException(
      'Trop de journaux exportés dans la même seconde',
      dossier.path,
    );
  }

  /// Horodatage du nom d'un journal exporté : `AAAAMMJJ_HHMMSS` ([date]
  /// telle quelle). Fonction pure.
  static String horodatageExport(DateTime date) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}${deux(date.month)}'
        '${deux(date.day)}_${deux(date.hour)}${deux(date.minute)}'
        '${deux(date.second)}';
  }

  /// Efface les journaux exportés les plus anciens au-delà de
  /// [nombreMaximalJournauxExportes] (l'horodatage du nom donne l'ordre).
  /// Les rapports d'erreur du même dossier ne sont pas touchés.
  Future<void> _supprimerAnciensExports(Directory dossier) async {
    final exports = <File>[];
    await for (final entite in dossier.list(followLinks: false)) {
      final nom = chemins.basename(entite.path);
      if (entite is File &&
          nom.startsWith(prefixeFichierJournalExporte) &&
          nom.endsWith('.$extensionFichierJournalExporte')) {
        exports.add(entite);
      }
    }
    exports.sort((a, b) => a.path.compareTo(b.path));
    final enTrop = exports.length - nombreMaximalJournauxExportes;
    for (var i = 0; i < enTrop; i++) {
      try {
        await exports[i].delete();
      } on FileSystemException {
        // Un ancien export impossible à effacer n'empêche pas le nouveau.
      }
    }
  }

  /// Écrit les entrées en attente du journal installé, au plus pendant le
  /// délai du service : un journal bloqué (disque plein, fichier verrouillé)
  /// n'empêche jamais la liste ni l'export, qui se font alors sans ces
  /// entrées. Ne lève jamais.
  Future<void> _viderJournal() =>
      ServiceRapportsErreur.viderJournalBorne(Journal.actuel, _delaiJournal);

  // -------------------------------------------------------------- Réglage

  /// Réglage « Journal détaillé (débogage) » tant que le client n'a rien
  /// choisi : désactivé (le journal détaillé grossit vite et n'est utile
  /// que pour chercher un problème précis).
  static const bool journalDetailleParDefaut = false;

  /// `true` si le client a activé le journal détaillé
  /// ([ServiceParametres.cleJournalDetaille]). Une valeur illisible, une
  /// base en erreur ou l'absence de dépôt valent
  /// [journalDetailleParDefaut]. Ne lève jamais.
  Future<bool> chargerJournalDetaille() async {
    final depot = _depotParametres;
    if (depot == null) return journalDetailleParDefaut;
    try {
      final valeur = await depot.chargerEntier(
        ServiceParametres.cleJournalDetaille,
      );
      // Seules 0 et 1 sont acceptées : une valeur écrite à la main ne doit
      // pas activer le débogage par surprise.
      if (valeur == 1) return true;
      if (valeur == 0) return false;
    } catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.parametres,
        'Réglage « Journal détaillé » illisible',
        erreur: erreur,
      );
    }
    return journalDetailleParDefaut;
  }

  /// Enregistre le réglage « Journal détaillé » puis l'applique au journal
  /// installé ([appliquerNiveau]).
  ///
  /// Lève une [ErreurService] si le réglage ne peut pas être enregistré (il
  /// est alors appliqué quand même pour cette session : le client voit
  /// l'effet qu'il a demandé).
  Future<void> enregistrerJournalDetaille(bool actif) async {
    // Appliqué avant l'écriture : la ligne ci-dessous (et ce qui suit) suit
    // déjà le nouveau niveau.
    appliquerNiveau(actif);
    Journal.actuel.info(
      CategorieJournal.parametres,
      'Réglage journal détaillé ${actif ? 'activé' : 'désactivé'}',
    );
    final depot = _depotParametres;
    if (depot == null) return;
    try {
      await depot.enregistrerEntier(
        ServiceParametres.cleJournalDetaille,
        actif ? 1 : 0,
      );
    } catch (erreur) {
      throw ErreurService(
        "Le réglage du journal n'a pas pu être enregistré.",
        cause: erreur,
      );
    }
  }

  /// Lit le réglage enregistré et l'applique au journal installé : à
  /// appeler au démarrage, une fois le `JournalFichier` installé et la base
  /// ouverte. Renvoie le réglage lu. Ne lève jamais.
  Future<bool> appliquerReglageJournal() async {
    final actif = await chargerJournalDetaille();
    appliquerNiveau(actif);
    return actif;
  }

  /// Règle le niveau minimal du journal installé : débogage si [detaille],
  /// information sinon. Renvoie `false` (sans rien changer) si
  /// `Journal.actuel` n'est pas un `JournalFichier` (journal silencieux des
  /// tests, journal pas encore installé).
  static bool appliquerNiveau(bool detaille) {
    final journal = Journal.actuel;
    if (journal is! JournalFichier) return false;
    journal.niveauMinimal = detaille
        ? NiveauJournal.debogage
        : NiveauJournal.info;
    return true;
  }
}
