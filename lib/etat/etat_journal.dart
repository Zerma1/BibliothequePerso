/// Journal de l'application vu par l'écran Paramètres (section « Journal ») :
/// dossier et fichiers des journaux, export pour les retours de test et
/// réglage « Journal détaillé ».
library;

import '../services/constantes_services.dart'
    show joursJournalExportesParDefaut;
import '../services/service_journal.dart';
import 'constantes_etat.dart';
import 'description_erreur.dart';

// Les écrans n'importent que les états (PLAYBOOK.md section 4) : la
// description d'un fichier de journal leur est fournie par cet état.
export '../services/service_journal.dart' show FichierJournal;

/// Un fichier de journal affiché dans la liste : le fichier et sa taille.
class LigneJournal {
  /// Crée une ligne.
  const LigneJournal(this.fichier, {this.taille});

  /// Fichier décrit par le service.
  final FichierJournal fichier;

  /// Taille en octets, ou `null` si elle n'a pas pu être lue (ou si
  /// l'application ne sait pas la mesurer).
  final int? taille;

  /// Jour couvert par le fichier (minuit, heure locale).
  DateTime get jour => fichier.jour;

  /// Numéro du fichier dans la journée (1 pour le premier).
  int get numero => fichier.numero;

  /// Nom du fichier, sans le dossier.
  String get nom => fichier.nom;
}

/// État de la section « Journal » des paramètres.
///
/// Le service ne lève jamais pour la consultation ; seuls l'export (journal
/// vide, fichier impossible à écrire) et l'enregistrement du réglage peuvent
/// échouer : l'erreur est alors renvoyée dans un [ResultatAction].
class EtatJournal extends EtatNotifiant {
  /// Crée l'état sur [_service].
  ///
  /// [mesurerTaille] : taille en octets du fichier dont on donne le chemin.
  /// Sans elle, la taille des fichiers n'est pas affichée.
  ///
  /// LIMITE : `FichierJournal` ne porte pas sa taille et `ServiceJournal`
  /// n'a pas de méthode pour la lire ; l'état ne touche pas lui-même au
  /// disque (PLAYBOOK.md section 4) : la fonction est fournie à
  /// l'assemblage (`lib/main.dart`).
  EtatJournal(this._service, {this._mesurerTaille});

  final ServiceJournal _service;
  final Future<int> Function(String chemin)? _mesurerTaille;

  List<LigneJournal> _fichiers = const <LigneJournal>[];
  bool _estCharge = false;
  bool _estEnChargement = false;
  bool _journalDetaille = ServiceJournal.journalDetailleParDefaut;
  bool _estEnEnregistrementReglage = false;
  int? _joursEnExport;
  DescriptionErreur? _erreur;

  /// Numéro du dernier chargement : une réponse plus ancienne (chargement
  /// relancé après un export) est ignorée.
  int _numeroChargement = 0;

  /// Nombre de jours copiés par « Exporter le journal du jour ».
  static const int joursExportJour = joursJournalExportesParDefaut;

  /// Nombre de jours copiés par « Exporter les 7 derniers jours ».
  static const int joursExportSemaine = joursExportJournalSemaine;

  /// Dossier des fichiers de journal (affiché au client, bouton « Ouvrir le
  /// dossier »).
  String get dossierJournaux => _service.dossierJournaux;

  /// Dossier où les journaux exportés sont copiés.
  String get dossierExports => _service.dossierRapports;

  /// Fichiers de journal, du plus récent au plus ancien.
  List<LigneJournal> get fichiers => _fichiers;

  /// `true` une fois la liste et le réglage lus au moins une fois.
  bool get estCharge => _estCharge;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` pendant la lecture de la liste et du réglage.
  bool get estEnChargement => _estEnChargement;

  /// Réglage « Journal détaillé ».
  bool get journalDetaille => _journalDetaille;

  /// `true` pendant l'enregistrement du réglage (interrupteur désactivé).
  bool get estEnEnregistrementReglage => _estEnEnregistrementReglage;

  /// `true` pendant un export (boutons désactivés).
  bool get estEnExport => _joursEnExport != null;

  /// Nombre de jours de l'export en cours (pour placer l'indicateur sur le
  /// bon bouton), ou `null`.
  int? get joursEnExport => _joursEnExport;

  /// Lit la liste des fichiers et le réglage « Journal détaillé ». Ne lève
  /// jamais : une taille illisible est simplement absente.
  Future<void> charger() async {
    final numero = ++_numeroChargement;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final fichiers = await _service.listerFichiers();
      final detaille = await _service.chargerJournalDetaille();
      final lignes = <LigneJournal>[
        // Le plus récent d'abord : c'est celui que le client cherche.
        for (final fichier in fichiers.reversed)
          LigneJournal(fichier, taille: await _taille(fichier.chemin)),
      ];
      if (numero != _numeroChargement) return;
      _fichiers = lignes;
      // Pendant un enregistrement, la valeur affichée est celle demandée.
      if (!_estEnEnregistrementReglage) _journalDetaille = detaille;
      _estCharge = true;
    } catch (exception, pile) {
      // Le service ne lève jamais ici ; par prudence, l'écran propose
      // « Réessayer » plutôt que de rester en chargement.
      if (numero != _numeroChargement) return;
      _erreur = DescriptionErreur.depuis(exception, pile);
    }
    _estEnChargement = false;
    notifier();
  }

  Future<int?> _taille(String chemin) async {
    final mesurer = _mesurerTaille;
    if (mesurer == null) return null;
    try {
      return await mesurer(chemin);
    } catch (_) {
      // Fichier effacé par la rotation entre la liste et la mesure : la
      // ligne reste affichée, sans taille.
      return null;
    }
  }

  /// Exporte le journal des [jours] derniers jours et renvoie le chemin du
  /// fichier écrit. Un journal vide ou une écriture impossible
  /// (`ErreurService`) devient un message lisible. La liste est relue
  /// ensuite (le fichier du jour a grossi).
  Future<ResultatAction<String>> exporter({int jours = joursExportJour}) async {
    if (_joursEnExport != null) {
      // Double clic : le second appel est ignoré (le service ne ferait de
      // toute façon qu'un seul fichier).
      return const ResultatAction<String>.echec(
        DescriptionErreur(
          NatureErreur.refus,
          detail: 'Un export du journal est déjà en cours.',
        ),
      );
    }
    _joursEnExport = jours;
    notifier();
    try {
      final chemin = await _service.exporterJournal(jours: jours);
      return ResultatAction<String>.reussite(chemin);
    } catch (exception, pile) {
      return ResultatAction<String>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    } finally {
      _joursEnExport = null;
      notifier();
      await charger();
    }
  }

  /// Active ou désactive le journal détaillé. L'interrupteur suit tout de
  /// suite ; si le réglage ne peut pas être enregistré, il est appliqué
  /// pour cette session seulement (voir `ServiceJournal`) et l'erreur est
  /// renvoyée.
  Future<ResultatAction<bool>> modifierJournalDetaille(bool actif) async {
    _journalDetaille = actif;
    _estEnEnregistrementReglage = true;
    notifier();
    try {
      await _service.enregistrerJournalDetaille(actif);
      return ResultatAction<bool>.reussite(actif);
    } catch (exception, pile) {
      return ResultatAction<bool>.echec(
        DescriptionErreur.depuis(exception, pile),
      );
    } finally {
      _estEnEnregistrementReglage = false;
      notifier();
    }
  }
}
