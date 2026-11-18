/// Export des rapports d'erreur dans des fichiers texte (tâche SE5 de
/// l'étape 6) : quand l'ajout d'un site ou d'un titre échoue, le client peut
/// envoyer le rapport pour faire diagnostiquer le site.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:path/path.dart' as chemins;

import '../donnees/journal_fichier.dart';
import '../donnees/stockage_telechargements.dart'
    show cheminParDefautDossierTelechargements;
import '../modeles/journal.dart';
import '../modeles/source.dart';
import '../sources/rapport_erreur_source.dart';
import '../sources/erreur_source.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';

/// Écrit les rapports d'erreur dans `Documents/bibliotheque_perso/rapports/`
/// (ou le dossier donné) et renvoie leur chemin à l'interface.
///
/// Le texte ne contient aucune donnée personnelle : tout ce qui vient du
/// réseau ou d'une exception passe par `masquerDonneesPersonnelles`.
class ServiceRapportsErreur {
  /// Crée le service sur [dossierRapports] (dossier temporaire dans les
  /// tests). [versionApplication] et [systeme] sont recopiés dans chaque
  /// rapport (système : celui de l'appareil par défaut).
  ///
  /// [dossierJournaux] : dossier des journaux de l'application, lu pour
  /// joindre au rapport la fin du journal quand [Journal.actuel] n'est pas
  /// un [JournalFichier] (par exemple dans les tests). Avec un
  /// [JournalFichier] installé, c'est lui qui est lu (entrées en attente
  /// écrites d'abord).
  ServiceRapportsErreur(
    this.dossierRapports, {
    String? versionApplication,
    String? systeme,
    DateTime Function()? horloge,
    String? dossierJournaux,
  }) : _versionApplication = versionApplication,
       _systeme = systeme ?? Platform.operatingSystem,
       _horloge = horloge ?? DateTime.now,
       _dossierJournaux = dossierJournaux;

  /// Crée le service sur le dossier par défaut :
  /// `<dossier documents>/bibliotheque_perso/rapports/`.
  // LIMITE : sur Android, ce dossier (comme celui de `main.dart`, calculé de
  // la même façon à partir de `StockageTelechargements.dossierRacine`) est
  // le dossier **privé** de l'application renvoyé par
  // `getApplicationDocumentsDirectory()` : le rapport est écrit mais le
  // client ne peut pas l'ouvrir ni l'envoyer depuis un gestionnaire de
  // fichiers. Il faudra un partage de fichier (paquet du type `share_plus`)
  // ou un dossier public choisi par le client : paquet à proposer au client
  // avant ajout. Windows et Linux ne sont pas concernés.
  static Future<ServiceRapportsErreur> parDefaut({
    String? versionApplication,
  }) async {
    final racine = await cheminParDefautDossierTelechargements();
    return ServiceRapportsErreur(
      chemins.join(racine, nomDossierRapports),
      versionApplication: versionApplication,
      dossierJournaux: cheminDossierJournaux(racine),
    );
  }

  /// Dossier où les rapports sont écrits.
  final String dossierRapports;

  final String? _versionApplication;
  final String _systeme;
  final DateTime Function() _horloge;
  final String? _dossierJournaux;

  /// Titre de la section du rapport qui recopie la fin du journal.
  static const String titreSectionJournal = 'Dernières lignes du journal';

  /// Ajoute à [texte] la section [titreSectionJournal] avec [lignes]
  /// (fonction pure). [texte] est renvoyé tel quel si [lignes] est vide.
  ///
  /// Les lignes sont déjà masquées à l'écriture du journal
  /// (`masquerDonneesSensibles`) ; elles le sont une seconde fois ici, au
  /// cas où un fichier ancien ou copié à la main serait lu.
  static String ajouterLignesJournal(String texte, List<String> lignes) {
    if (lignes.isEmpty) return texte;
    final tampon = StringBuffer(texte);
    if (!texte.endsWith('\n')) tampon.writeln();
    tampon
      ..writeln()
      ..writeln('--- $titreSectionJournal (${lignes.length}) ---');
    for (final ligne in lignes) {
      tampon.writeln(masquerDonneesSensibles(ligne));
    }
    return tampon.toString();
  }

  /// Les [nombreLignesJournalRapport] dernières lignes du journal, ou une
  /// liste vide s'il n'y en a pas (journal silencieux sans dossier connu,
  /// fichier illisible). Ne lève jamais : un rapport sans journal vaut mieux
  /// que pas de rapport.
  Future<List<String>> _chargerLignesJournal() async {
    try {
      final journal = Journal.actuel;
      if (journal is JournalFichier) {
        return await journal.chargerDernieresLignes(nombreLignesJournalRapport);
      }
      final dossier = _dossierJournaux;
      if (dossier == null) return const <String>[];
      return await chargerDernieresLignesJournal(
        dossier,
        nombreLignesJournalRapport,
      );
    } catch (_) {
      return const <String>[];
    }
  }

  /// Longueur maximale du message d'une erreur qui ne vient pas d'un site
  /// (une pile ou un message énorme ne doit pas remplir le rapport).
  static const int longueurMaxMessage = 2000;

  /// Produit le texte du rapport de [erreur] (fonction pure, sans fichier).
  ///
  /// - [ErreurSource] (ou [ErreurService] qui en enveloppe une) : rapport
  ///   complet de `RapportErreurSource` (adresse, code HTTP, type du site,
  ///   début de la réponse) ;
  /// - autre erreur : type et message, nettoyés des données personnelles.
  ///
  /// [action] décrit ce que faisait le client (« Ajout d'un site ») ;
  /// [typeDetecte] complète le type du site s'il est connu de l'appelant.
  static String produireTexte(
    Object erreur, {
    String? action,
    TypeSource? typeDetecte,
    DateTime? date,
    String? versionApplication,
    String? systeme,
  }) {
    final erreurSource = switch (erreur) {
      ErreurSource() => erreur,
      ErreurService(cause: final ErreurSource cause) => cause,
      _ => null,
    };
    if (erreurSource != null) {
      final texte = RapportErreurSource(
        erreurSource,
        action: action,
        typeDetecte: typeDetecte,
        date: date,
        versionApplication: versionApplication,
        systeme: systeme,
      ).versTexte();
      if (erreur is ErreurService) {
        return '$texte'
            "Message de l'application : "
            '${masquerDonneesPersonnelles(erreur.message)}\n';
      }
      return texte;
    }
    final tampon = StringBuffer()
      ..writeln("Rapport d'erreur — Bibliothèque perso")
      ..writeln(
        'Date (UTC) : ${(date ?? DateTime.now()).toUtc().toIso8601String()}',
      );
    void ligne(String libelle, Object? valeur) {
      if (valeur != null && '$valeur'.trim().isNotEmpty) {
        tampon.writeln('$libelle : $valeur');
      }
    }

    ligne('Action', action == null ? null : masquerDonneesPersonnelles(action));
    ligne('Version', versionApplication);
    ligne('Système', systeme);
    ligne('Type de site détecté', typeDetecte?.name);
    ligne("Type d'erreur", erreur.runtimeType);
    final message = erreur is ErreurService ? erreur.message : '$erreur';
    ligne(
      'Message',
      extraireDebutReponse(message, longueur: longueurMaxMessage),
    );
    if (erreur is ErreurService && erreur.cause != null) {
      ligne(
        'Cause',
        extraireDebutReponse('${erreur.cause}', longueur: longueurMaxMessage),
      );
    }
    return tampon.toString();
  }

  /// Écrit le rapport de [erreur] dans un nouveau fichier
  /// `rapport_AAAAMMJJ_HHMMSS.txt` (UTC) et renvoie son chemin complet, à
  /// montrer au client ou à ouvrir.
  ///
  /// Au plus [nombreMaximalRapports] rapports sont gardés : les plus anciens
  /// sont effacés. Lève une [ErreurService] si le fichier ne peut pas être
  /// écrit.
  Future<String> exporterRapport(
    Object erreur, {
    String? action,
    TypeSource? typeDetecte,
  }) async {
    final date = _horloge().toUtc();
    // Noté avant la lecture du journal : la fin jointe au rapport montre
    // ainsi l'erreur elle-même.
    Journal.actuel.erreur(
      CategorieJournal.interface,
      "Rapport d'erreur demandé${action == null ? '' : ' ($action)'}",
      erreur: erreur,
    );
    final texte = ajouterLignesJournal(
      produireTexte(
        erreur,
        action: action,
        typeDetecte: typeDetecte,
        date: date,
        versionApplication: _versionApplication,
        systeme: _systeme,
      ),
      await _chargerLignesJournal(),
    );
    try {
      final dossier = Directory(dossierRapports);
      await dossier.create(recursive: true);
      final fichier = await _reserverFichier(dossier, date);
      await fichier.writeAsString(texte, flush: true);
      await _supprimerAnciens(dossier);
      return fichier.path;
    } on FileSystemException catch (erreurFichier) {
      throw ErreurService(
        "Le rapport d'erreur n'a pas pu être enregistré.",
        cause: erreurFichier,
      );
    }
  }

  /// Nom libre pour un rapport de [date] : `rapport_20261116_143000.txt`,
  /// puis `…_2.txt`, `…_3.txt` si plusieurs rapports tombent dans la même
  /// seconde.
  Future<File> _reserverFichier(Directory dossier, DateTime date) async {
    String deux(int n) => n.toString().padLeft(2, '0');
    final horodatage =
        '${date.year}${deux(date.month)}${deux(date.day)}_'
        '${deux(date.hour)}${deux(date.minute)}${deux(date.second)}';
    // Borné : au-delà de quelques essais, la même seconde n'a pas autant de
    // rapports ; la borne évite toute boucle sans fin.
    for (var numero = 1; numero <= nombreMaximalRapports; numero++) {
      final suffixe = numero == 1 ? '' : '_$numero';
      final fichier = File(
        chemins.join(
          dossier.path,
          '$prefixeFichierRapport$horodatage$suffixe.$extensionFichierRapport',
        ),
      );
      if (!await fichier.exists()) return fichier;
    }
    throw FileSystemException(
      'Trop de rapports dans la même seconde',
      dossier.path,
    );
  }

  /// Efface les rapports les plus anciens au-delà de
  /// [nombreMaximalRapports] (l'horodatage du nom donne l'ordre).
  Future<void> _supprimerAnciens(Directory dossier) async {
    final rapports = <File>[];
    await for (final entite in dossier.list(followLinks: false)) {
      if (entite is File &&
          chemins.basename(entite.path).startsWith(prefixeFichierRapport) &&
          entite.path.endsWith('.$extensionFichierRapport')) {
        rapports.add(entite);
      }
    }
    rapports.sort((a, b) => a.path.compareTo(b.path));
    final enTrop = rapports.length - nombreMaximalRapports;
    for (var i = 0; i < enTrop; i++) {
      try {
        await rapports[i].delete();
      } on FileSystemException {
        // Un ancien rapport impossible à effacer n'empêche pas l'export.
      }
    }
  }
}
