/// Import d'un export JSON de la bibliothèque (tâche R8, retour du client
/// sur la 0.2.0-test) : les sites, titres, listes et réglages du fichier
/// sont **fusionnés** dans la base, sans jamais rien supprimer.
///
/// Aucune requête réseau : l'export contient tout ce qu'il faut pour créer
/// les lignes (format 2, voir `versionFormatExport`). Les chapitres des
/// titres ajoutés arrivent à la prochaine vérification des mises à jour.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

// Seul le type de l'exécuteur (la transaction de GestionnaireTransactions)
// est utilisé : aucune requête SQL n'est écrite dans ce service.
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../donnees/depot_categories.dart';
import '../donnees/depot_equivalences_categories.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_parametres.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../donnees/depot_titres_sources.dart';
import '../donnees/gestionnaire_transactions.dart';
import '../modeles/categorie.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/lien_titre_source.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../modeles/titre_alternatif.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'service_ajout_site.dart';
import 'service_bibliotheque.dart';
import 'service_parametres.dart';

// ------------------------------------------------------------ Contenu lu

/// Un site tel qu'il est décrit dans le fichier d'import.
class SourceImportee {
  /// Crée la ligne.
  const SourceImportee({
    required this.numero,
    required this.nom,
    required this.urlBase,
    required this.typeBrut,
    this.langues = const <String>[],
    this.estActive = true,
    this.configurationSelecteurs,
  });

  /// Position du site dans le fichier (1 pour le premier).
  final int numero;

  /// Nom affiché du site.
  final String nom;

  /// Adresse de base du site.
  final String urlBase;

  /// Type tel qu'écrit dans le fichier (`mangaDex`, `madara`…).
  final String typeBrut;

  /// Type reconnu, ou `null` si [typeBrut] est inconnu de cette version.
  TypeSource? get type {
    for (final type in TypeSource.values) {
      if (type.name == typeBrut) return type;
    }
    return null;
  }

  /// Langues du site (codes ISO 639-1), dans l'ordre de préférence.
  final List<String> langues;

  /// `false` si le site était désactivé.
  final bool estActive;

  /// Sélecteurs CSS d'un site générique (format 2), sinon `null`.
  final String? configurationSelecteurs;
}

/// Un site d'un titre tel qu'il est décrit dans le fichier d'import.
class SiteImporte {
  /// Crée la ligne.
  const SiteImporte({
    required this.url,
    this.nomSource,
    this.urlSource,
    this.estPrincipal = false,
    this.estLienSeul = false,
  });

  /// Adresse du titre sur ce site.
  final String url;

  /// Nom du site, si connu.
  final String? nomSource;

  /// Adresse de base du site, si connue.
  final String? urlSource;

  /// `true` pour le site principal du titre.
  final bool estPrincipal;

  /// `true` pour un lien seul (site seulement ouvert dans le navigateur).
  final bool estLienSeul;
}

/// Un titre tel qu'il est décrit dans le fichier d'import.
class TitreImporte {
  /// Crée la ligne.
  const TitreImporte({
    required this.numero,
    required this.nom,
    required this.sites,
    this.typeTitre = TypeTitre.autre,
    this.titresAlternatifs = const <TitreAlternatif>[],
    this.listes = const <String>[],
    this.categories = const <String>[],
    this.langues = const <String>[],
    this.niveauContenu,
    this.urlCouverture,
    this.couvertureChoisie,
    this.resume,
    this.auteur,
    this.statut,
    this.champsManuels = const <ChampTitre>{},
    this.descriptionPerso,
  });

  /// Description personnelle du client (format 5 ; `null` pour les formats
  /// 1 à 4 ou si aucune), sans espaces autour et bornée à
  /// `longueurMaxDescriptionPerso` caractères.
  final String? descriptionPerso;

  /// Champs modifiés à la main sur l'appareil d'origine (format 4 ; vide
  /// pour les formats 1 à 3). Noms inconnus de cette version ignorés.
  final Set<ChampTitre> champsManuels;

  /// Position du titre dans le fichier (1 pour le premier).
  final int numero;

  /// Nom principal du titre.
  final String nom;

  /// Sites du titre, le principal d'abord (jamais vide).
  final List<SiteImporte> sites;

  /// Nature du titre (`autre` si le type est inconnu).
  final TypeTitre typeTitre;

  /// Autres noms du titre.
  final List<TitreAlternatif> titresAlternatifs;

  /// Noms des listes qui contiennent le titre.
  final List<String> listes;

  /// Noms des catégories du titre.
  final List<String> categories;

  /// Langues propres au titre (vide : réglage général).
  final List<String> langues;

  /// Niveau de contenu indiqué par le site, si connu.
  final String? niveauContenu;

  /// Couverture du site, si connue.
  final String? urlCouverture;

  /// Couverture choisie par le client : seule une adresse du site est
  /// gardée (une image de l'appareil n'est exportée que par son nom de
  /// fichier, inutilisable ailleurs).
  final String? couvertureChoisie;

  /// Résumé (format 2), si connu.
  final String? resume;

  /// Auteur, si connu.
  final String? auteur;

  /// Statut affiché par le site, si connu.
  final String? statut;
}

/// Une liste telle qu'elle est décrite dans le fichier d'import.
class ListeImportee {
  /// Crée la ligne.
  const ListeImportee({required this.nom, this.estSysteme = false});

  /// Nom de la liste.
  final String nom;

  /// `true` pour une liste système (Favoris, Suivis, Planifié, En attente).
  final bool estSysteme;
}

/// Un regroupement de catégories tel qu'il est décrit dans le fichier
/// d'import (format 3), noms déjà normalisés (`Categorie.normaliserNom`).
class EquivalenceImportee {
  /// Crée la ligne.
  const EquivalenceImportee({
    required this.numero,
    required this.categorie,
    required this.reference,
  });

  /// Position du regroupement dans le fichier (1 pour le premier).
  final int numero;

  /// Nom de la catégorie à rattacher.
  final String categorie;

  /// Nom de sa catégorie de référence.
  final String reference;
}

/// Tout ce qu'un fichier d'import contient, déjà vérifié. Produit par
/// [ServiceImport.lireJson] (fonction pure, testable sans base).
class ContenuImport {
  /// Crée le contenu.
  const ContenuImport({
    required this.versionFormat,
    this.versionApplication,
    this.languesGenerales = const <String>[],
    this.niveauxContenu,
    this.listes = const <ListeImportee>[],
    this.sources = const <SourceImportee>[],
    this.titres = const <TitreImporte>[],
    this.equivalences = const <EquivalenceImportee>[],
    this.erreursLecture = const <ErreurLigneImport>[],
    this.archiveComplete,
  });

  /// Version du format du fichier (1 à 4).
  final int versionFormat;

  /// Réglage « Archive complète » (format 4), ou `null` s'il est absent du
  /// fichier.
  final bool? archiveComplete;

  /// Regroupements de catégories (format 3 ; vide pour les formats 1 et 2).
  final List<EquivalenceImportee> equivalences;

  /// Version de l'application qui a produit le fichier, si connue.
  final String? versionApplication;

  /// Langues de lecture générales (vide si absentes du fichier).
  final List<String> languesGenerales;

  /// Niveaux de contenu affichés, ou `null` s'ils sont absents du fichier.
  final List<String>? niveauxContenu;

  /// Listes, dans l'ordre d'affichage.
  final List<ListeImportee> listes;

  /// Sites configurés.
  final List<SourceImportee> sources;

  /// Titres lisibles.
  final List<TitreImporte> titres;

  /// Lignes illisibles (titre sans nom, site sans adresse…), écartées.
  final List<ErreurLigneImport> erreursLecture;
}

// ------------------------------------------------------------- Résultat

/// Partie du fichier concernée par une erreur d'import.
enum PartieImport {
  /// Un site de la section `sources`.
  site,

  /// Une liste de la section `listes`.
  liste,

  /// Un titre de la section `titres`.
  titre,

  /// Les réglages généraux.
  reglages,

  /// Un regroupement de catégories de la section `equivalences` (format 3).
  equivalence,
}

/// Une ligne du fichier qui n'a pas pu être importée (en tout ou partie).
class ErreurLigneImport {
  /// Crée l'erreur.
  const ErreurLigneImport({
    required this.partie,
    required this.message,
    this.numero,
    this.nom,
  });

  /// Partie du fichier concernée.
  final PartieImport partie;

  /// Position de la ligne dans sa partie (1 pour la première), si connue.
  final int? numero;

  /// Nom du site, de la liste ou du titre, si connu.
  final String? nom;

  /// Explication en français, affichable telle quelle.
  final String message;

  /// Description complète : « Titre n°3 « Nom » : message ».
  String get description {
    final libelle = switch (partie) {
      PartieImport.site => 'Site',
      PartieImport.liste => 'Liste',
      PartieImport.titre => 'Titre',
      PartieImport.reglages => 'Réglages',
      PartieImport.equivalence => 'Regroupement de catégories',
    };
    final position = numero == null ? '' : ' n°$numero';
    final nomLisible = nom == null ? '' : ' « $nom »';
    return '$libelle$position$nomLisible : $message';
  }

  @override
  String toString() => description;
}

/// Bilan d'un import.
class ResultatImport {
  /// Crée le bilan.
  const ResultatImport({
    required this.versionFormat,
    this.titresAjoutes = 0,
    this.titresCompletes = 0,
    this.titresIgnores = 0,
    this.sitesAjoutes = 0,
    this.listesAjoutees = 0,
    this.reglagesGenerauxAppliques = false,
    this.erreurs = const <ErreurLigneImport>[],
    this.regroupementsAjoutes = 0,
    this.archiveCompleteActivee = false,
  });

  /// `true` si l'import a activé « Archive complète » (elle ne l'était pas
  /// sur l'appareil). Un import ne la désactive jamais. L'interface lance
  /// alors `ServiceTelechargement.appliquerReglesATous` pour mettre en file
  /// les chapitres de toute la bibliothèque.
  final bool archiveCompleteActivee;

  /// Regroupements de catégories (format 3) enregistrés par l'import.
  final int regroupementsAjoutes;

  /// Version du format du fichier importé.
  final int versionFormat;

  /// Titres absents de la base, créés par l'import.
  final int titresAjoutes;

  /// Titres déjà présents auxquels l'import a ajouté au moins un site, une
  /// liste, une catégorie, un nom ou un réglage.
  final int titresCompletes;

  /// Titres déjà présents et déjà complets : rien n'a été modifié.
  final int titresIgnores;

  /// Sites (sources) créés dans « Sources ».
  final int sitesAjoutes;

  /// Listes du client créées.
  final int listesAjoutees;

  /// `true` si les langues et niveaux de contenu généraux du fichier ont
  /// été enregistrés.
  final bool reglagesGenerauxAppliques;

  /// Lignes non importées (ou importées en partie), dans l'ordre du fichier.
  final List<ErreurLigneImport> erreurs;

  /// `true` si des titres ont été ajoutés : leurs chapitres ne sont pas dans
  /// le fichier et arriveront à la prochaine vérification des mises à jour.
  bool get chapitresALaProchaineVerification => titresAjoutes > 0;

  /// Bilan lisible en français, par exemple « 3 titres ajoutés, 1 titre
  /// complété, 2 titres déjà présents, 1 erreur. Les chapitres des titres
  /// ajoutés arriveront à la prochaine vérification des mises à jour. »
  String get resume {
    String pluriel(int n, String un, String plusieurs) =>
        '$n ${n > 1 ? plusieurs : un}';
    final parties = <String>[
      pluriel(titresAjoutes, 'titre ajouté', 'titres ajoutés'),
      pluriel(titresCompletes, 'titre complété', 'titres complétés'),
      pluriel(titresIgnores, 'titre déjà présent', 'titres déjà présents'),
      if (sitesAjoutes > 0)
        pluriel(sitesAjoutes, 'site ajouté', 'sites ajoutés'),
      if (listesAjoutees > 0)
        pluriel(listesAjoutees, 'liste créée', 'listes créées'),
      if (regroupementsAjoutes > 0)
        pluriel(
          regroupementsAjoutes,
          'catégorie regroupée',
          'catégories regroupées',
        ),
      if (erreurs.isNotEmpty) pluriel(erreurs.length, 'erreur', 'erreurs'),
    ];
    final tampon = StringBuffer('${parties.join(', ')}.');
    if (reglagesGenerauxAppliques) {
      tampon.write(' Langues et niveaux de contenu repris du fichier.');
    }
    if (archiveCompleteActivee) {
      tampon.write(
        ' « Archive complète » activée : tous les chapitres de la '
        'bibliothèque seront téléchargés (désactivable dans Paramètres).',
      );
    }
    if (chapitresALaProchaineVerification) {
      tampon.write(
        ' Les chapitres des titres ajoutés arriveront à la prochaine '
        'vérification des mises à jour ; les chapitres déjà lus ne sont pas '
        'repris.',
      );
    }
    return tampon.toString();
  }
}

// -------------------------------------------------------------- Service

/// Lit un export JSON (`ServiceExport`) et le fusionne dans la base.
///
/// Règles du client (retour 0.2.0-test) :
/// - rien n'est jamais supprimé ni remplacé : un site, une liste ou un
///   réglage déjà présent est gardé tel quel ;
/// - un titre déjà présent (une de ses adresses est déjà celle d'un site,
///   principal ou secondaire, d'un titre de la base) n'est pas dupliqué : on
///   complète seulement ses sites, listes, catégories, noms et réglages
///   manquants ;
/// - aucune requête réseau ; les chapitres arrivent à la prochaine
///   vérification ;
/// - une ligne illisible ou impossible à importer (site non configuré,
///   adresse déjà prise par un autre titre…) est notée dans le
///   [ResultatImport] sans arrêter les autres ; seul un fichier qui n'est
///   pas un export lève une [ErreurService], **avant** toute écriture.
///
/// **Tout ou rien (V2)** : avec un [GestionnaireTransactions], tout l'import
/// (sites, listes, réglages, titres, lectures comprises) se fait dans une
/// seule transaction SQLite. Une erreur de base inattendue (écriture
/// refusée, disque plein…) annule **tout** et lève une [ErreurService] :
/// rien n'est importé. Les erreurs « par ligne » ci-dessus sont des refus
/// décidés avant l'écriture concernée : elles n'annulent rien.
///
/// LIMITE : sans [GestionnaireTransactions] (anciens appelants, tests),
/// chaque écriture garde sa propre transaction et une erreur de base est
/// notée sur sa ligne ; un import interrompu peut alors être à moitié fait,
/// mais il est **idempotent** : le relancer termine le travail sans rien
/// dupliquer.
class ServiceImport {
  /// Crée le service.
  ///
  /// - [gestionnaireTransactions] rend l'import « tout ou rien » (à fournir
  ///   dans l'application).
  /// - Réglages généraux du fichier (langues, niveaux de contenu) : écrits
  ///   par [depotParametres] (dans la transaction de l'import), sinon par
  ///   [serviceParametres] (sans transaction seulement) ; sans l'un ni
  ///   l'autre, ils ne sont jamais appliqués. Les noms des clés et le
  ///   nettoyage des valeurs restent ceux de [ServiceParametres].
  ///
  /// Lève une [ArgumentError] si [gestionnaireTransactions] et
  /// [serviceParametres] sont fournis sans [depotParametres] :
  /// `ServiceParametres` écrit hors de la transaction, ce qui bloquerait
  /// l'import (verrou de sqflite).
  ServiceImport({
    required DepotSources depotSources,
    required DepotTitres depotTitres,
    required DepotTitresSources depotTitresSources,
    required DepotListes depotListes,
    required DepotCategories depotCategories,
    ServiceParametres? serviceParametres,
    DepotParametres? depotParametres,
    GestionnaireTransactions? gestionnaireTransactions,
    DepotEquivalencesCategories? depotEquivalences,
  }) : _depotEquivalences = depotEquivalences,
       _depotSources = depotSources,
       _depotTitres = depotTitres,
       _depotTitresSources = depotTitresSources,
       _depotListes = depotListes,
       _depotCategories = depotCategories,
       _serviceParametres = serviceParametres,
       _depotParametres = depotParametres,
       _gestionnaireTransactions = gestionnaireTransactions {
    if (gestionnaireTransactions != null &&
        serviceParametres != null &&
        depotParametres == null) {
      throw ArgumentError(
        "Import « tout ou rien » : passer depotParametres pour écrire les "
        'réglages dans la transaction.',
      );
    }
  }

  final DepotSources _depotSources;
  final DepotTitres _depotTitres;
  final DepotTitresSources _depotTitresSources;
  final DepotListes _depotListes;
  final DepotCategories _depotCategories;
  final ServiceParametres? _serviceParametres;
  final DepotParametres? _depotParametres;
  final GestionnaireTransactions? _gestionnaireTransactions;

  /// Regroupements de catégories (format 3) ; sans lui, les regroupements
  /// du fichier ne sont pas importés (une erreur le signale).
  final DepotEquivalencesCategories? _depotEquivalences;

  /// Import en cours : un second appel (double clic) reçoit le même
  /// résultat au lieu de lancer un second import en parallèle, dont les
  /// écritures se croiseraient avec celles du premier.
  Future<ResultatImport>? _enCours;

  /// Lit le fichier [chemin] (UTF-8) et l'importe : voir [importerTexte].
  ///
  /// Lève une [ErreurService] si le fichier est introuvable, illisible,
  /// démesuré ou n'est pas un export de l'application.
  Future<ResultatImport> importerFichier(
    String chemin, {
    bool? appliquerReglagesGeneraux,
  }) => _partager(() async {
    final String texte;
    try {
      final fichier = File(chemin);
      if (await fichier.length() > tailleMaximaleFichierImport) {
        throw const ErreurService(
          "Ce fichier est bien trop gros pour être un export de la "
          'bibliothèque.',
        );
      }
      texte = await fichier.readAsString(encoding: utf8);
    } on FileSystemException catch (erreur) {
      throw ErreurService("Le fichier n'a pas pu être lu.", cause: erreur);
    } on FormatException catch (erreur) {
      // Octets qui ne sont pas de l'UTF-8 : ce n'est pas un export.
      throw ErreurService(_messagePasUnExport, cause: erreur);
    }
    return _importer(
      lireJson(texte),
      appliquerReglagesGeneraux: appliquerReglagesGeneraux,
    );
  });

  /// Importe le texte JSON [texte] d'un export.
  ///
  /// [appliquerReglagesGeneraux] : `true` enregistre les langues et niveaux
  /// de contenu du fichier, `false` garde ceux de l'appareil ; `null` (par
  /// défaut) ne les applique que si la bibliothèque est vide avant l'import
  /// (restauration sur un nouvel appareil), pour ne jamais écraser en
  /// silence un choix du client.
  ///
  /// Un appel pendant un import en cours reçoit le résultat de celui-ci.
  /// Lève une [ErreurService] si le texte n'est pas un export lisible (rien
  /// n'est alors écrit). Les erreurs de base sur une ligne sont rendues dans
  /// [ResultatImport.erreurs].
  Future<ResultatImport> importerTexte(
    String texte, {
    bool? appliquerReglagesGeneraux,
  }) => _partager(
    () async => _importer(
      lireJson(texte),
      appliquerReglagesGeneraux: appliquerReglagesGeneraux,
    ),
  );

  Future<ResultatImport> _partager(Future<ResultatImport> Function() action) {
    final enCours = _enCours;
    if (enCours != null) return enCours;
    final nouveau = action();
    _enCours = nouveau;
    // Libéré après coup, réussite ou échec : un nouvel import reste possible.
    nouveau.then<void>(
      (_) => _enCours = null,
      onError: (Object _) => _enCours = null,
    );
    return nouveau;
  }

  // ---------------------------------------------------- Lecture (pure)

  static const String _messagePasUnExport =
      "Ce fichier n'est pas un export de Bibliothèque perso : choisissez le "
      'fichier .json créé par « Exporter ».';

  /// Vérifie et lit le texte d'un export. Fonction pure.
  ///
  /// Lève une [ErreurService] (message en français) si le texte n'est pas du
  /// JSON, n'est pas un export de l'application, vient d'un format plus
  /// récent ou n'a pas la structure attendue. Une ligne isolée illisible
  /// (titre sans nom, site sans adresse) n'est pas fatale : elle est
  /// rangée dans [ContenuImport.erreursLecture].
  static ContenuImport lireJson(String texte) {
    // Un fichier réenregistré par un éditeur de texte Windows peut commencer
    // par une marque d'ordre des octets, que jsonDecode refuse.
    final marque = String.fromCharCode(0xFEFF);
    final propre = texte.startsWith(marque) ? texte.substring(1) : texte;
    final Object? donnees;
    try {
      donnees = jsonDecode(propre);
    } on FormatException catch (erreur) {
      throw ErreurService(
        "Ce fichier n'est pas un export valide : son contenu JSON est "
        'illisible ou incomplet.',
        cause: erreur,
      );
    }
    if (donnees is! Map<String, Object?> ||
        donnees['format'] != identifiantFormatExport) {
      throw const ErreurService(_messagePasUnExport);
    }
    final version = donnees['version'];
    if (version is! int) {
      throw const ErreurService(_messagePasUnExport);
    }
    if (version > versionFormatExport) {
      throw ErreurService(
        'Cet export vient d\'une version plus récente de l\'application '
        '(format $version) : mettez l\'application à jour pour l\'importer.',
      );
    }
    if (version < versionFormatImportMinimale) {
      throw ErreurService(
        "Ce format d'export ($version) n'est pas pris en charge.",
      );
    }

    final titresBruts = _liste(donnees, 'titres', obligatoire: true);
    if (titresBruts.length > nombreMaximalTitresImport) {
      throw ErreurService(
        'Cet export contient trop de titres (${titresBruts.length}, au plus '
        '$nombreMaximalTitresImport).',
      );
    }
    final erreurs = <ErreurLigneImport>[];

    final sources = <SourceImportee>[];
    final sourcesBrutes = _liste(donnees, 'sources');
    for (var i = 0; i < sourcesBrutes.length; i++) {
      final ligne = _lireSource(sourcesBrutes[i], i + 1);
      switch (ligne) {
        case final SourceImportee source:
          sources.add(source);
        case final ErreurLigneImport erreur:
          erreurs.add(erreur);
      }
    }

    final listes = <ListeImportee>[
      for (final brute in _liste(donnees, 'listes'))
        if (brute is Map<String, Object?>)
          if (_texte(brute, 'nom') case final nom?)
            ListeImportee(
              nom: nom,
              estSysteme: _booleen(brute, 'systeme', defaut: false),
            ),
    ];

    final titres = <TitreImporte>[];
    for (var i = 0; i < titresBruts.length; i++) {
      final ligne = _lireTitre(titresBruts[i], i + 1);
      switch (ligne) {
        case final TitreImporte titre:
          titres.add(titre);
        case final ErreurLigneImport erreur:
          erreurs.add(erreur);
      }
    }

    // Format 3 : absents des formats 1 et 2 (liste vide).
    final equivalencesBrutes = _liste(donnees, 'equivalences');
    if (equivalencesBrutes.length > nombreMaximalEquivalencesImport) {
      throw ErreurService(
        'Cet export contient trop de regroupements de catégories '
        '(${equivalencesBrutes.length}, au plus '
        '$nombreMaximalEquivalencesImport).',
      );
    }
    final equivalences = <EquivalenceImportee>[];
    for (var i = 0; i < equivalencesBrutes.length; i++) {
      final ligne = _lireEquivalence(equivalencesBrutes[i], i + 1);
      switch (ligne) {
        case final EquivalenceImportee equivalence:
          equivalences.add(equivalence);
        case final ErreurLigneImport erreur:
          erreurs.add(erreur);
      }
    }

    final reglages = donnees['reglages'];
    final reglagesLus = reglages is Map<String, Object?> ? reglages : null;
    final niveaux = reglagesLus?['niveauxContenu'];
    final archiveComplete = reglagesLus?['archiveComplete'];
    return ContenuImport(
      // Absent (formats 1 à 3) ou d'un autre type : réglage de l'appareil
      // laissé tel quel.
      archiveComplete: archiveComplete is bool ? archiveComplete : null,
      versionFormat: version,
      versionApplication: _texte(donnees, 'versionApplication'),
      languesGenerales: reglagesLus == null
          ? const <String>[]
          : ServiceParametres.nettoyerLangues(_textes(reglagesLus, 'langues')),
      // Absent ≠ vide : une liste vide est un vrai choix du client (n'afficher
      // que les titres sans niveau connu).
      niveauxContenu: niveaux is List<Object?>
          ? ServiceParametres.nettoyerNiveauxContenu(
              niveaux.whereType<String>(),
            )
          : null,
      listes: listes,
      sources: sources,
      titres: titres,
      equivalences: equivalences,
      erreursLecture: erreurs,
    );
  }

  /// Regroupement lu dans [brut], ou l'erreur qui l'écarte (ligne
  /// illisible, nom absent, catégorie identique à sa référence).
  static Object _lireEquivalence(Object? brut, int numero) {
    if (brut is! Map<String, Object?>) {
      return ErreurLigneImport(
        partie: PartieImport.equivalence,
        numero: numero,
        message: 'ligne illisible.',
      );
    }
    final categorie = Categorie.normaliserNom(_texte(brut, 'categorie') ?? '');
    final reference = Categorie.normaliserNom(_texte(brut, 'reference') ?? '');
    if (categorie.isEmpty || reference.isEmpty) {
      return ErreurLigneImport(
        partie: PartieImport.equivalence,
        numero: numero,
        nom: categorie.isEmpty ? null : categorie,
        message: 'catégorie ou catégorie de référence absente.',
      );
    }
    if (categorie == reference) {
      return ErreurLigneImport(
        partie: PartieImport.equivalence,
        numero: numero,
        nom: categorie,
        message: 'une catégorie ne peut pas être sa propre référence.',
      );
    }
    return EquivalenceImportee(
      numero: numero,
      categorie: categorie,
      reference: reference,
    );
  }

  /// Site lu dans [brut], ou l'erreur qui l'écarte.
  static Object _lireSource(Object? brut, int numero) {
    if (brut is! Map<String, Object?>) {
      return ErreurLigneImport(
        partie: PartieImport.site,
        numero: numero,
        message: 'ligne illisible.',
      );
    }
    final nom = _texte(brut, 'nom');
    final urlBase = _texte(brut, 'urlBase');
    if (urlBase == null || !_estAdresseWeb(urlBase)) {
      return ErreurLigneImport(
        partie: PartieImport.site,
        numero: numero,
        nom: nom,
        message: 'adresse du site absente ou invalide.',
      );
    }
    return SourceImportee(
      numero: numero,
      nom: nom ?? ServiceAjoutSite.proposerNom(Uri.parse(urlBase)),
      urlBase: urlBase,
      typeBrut: _texte(brut, 'type') ?? '',
      langues: ServiceParametres.nettoyerLangues(_textes(brut, 'langues')),
      estActive: _booleen(brut, 'active', defaut: true),
      configurationSelecteurs: _texte(brut, 'configurationSelecteurs'),
    );
  }

  /// Titre lu dans [brut], ou l'erreur qui l'écarte.
  static Object _lireTitre(Object? brut, int numero) {
    if (brut is! Map<String, Object?>) {
      return ErreurLigneImport(
        partie: PartieImport.titre,
        numero: numero,
        message: 'ligne illisible.',
      );
    }
    final nom = _texte(brut, 'nom');
    if (nom == null) {
      return ErreurLigneImport(
        partie: PartieImport.titre,
        numero: numero,
        message: 'titre sans nom.',
      );
    }
    final sites = <SiteImporte>[];
    // Format 1 sans le champ `sites` (avant l'étape 8) : seul le site
    // principal est décrit, par `url` / `source` / `urlSource`.
    final sitesBruts = brut['sites'];
    if (sitesBruts is List<Object?> && sitesBruts.isNotEmpty) {
      for (final site in sitesBruts) {
        if (site is! Map<String, Object?>) continue;
        final url = _texte(site, 'url');
        if (url == null || !_estAdresseWeb(url)) continue;
        sites.add(
          SiteImporte(
            url: url,
            nomSource: _texte(site, 'source'),
            urlSource: _texte(site, 'urlSource'),
            estPrincipal: _booleen(site, 'principal', defaut: false),
            estLienSeul: _booleen(site, 'lienSeul', defaut: false),
          ),
        );
      }
    } else if (_texte(brut, 'url') case final url? when _estAdresseWeb(url)) {
      sites.add(
        SiteImporte(
          url: url,
          nomSource: _texte(brut, 'source'),
          urlSource: _texte(brut, 'urlSource'),
          estPrincipal: true,
        ),
      );
    }
    if (sites.isEmpty) {
      return ErreurLigneImport(
        partie: PartieImport.titre,
        numero: numero,
        nom: nom,
        message: 'aucune adresse valide.',
      );
    }
    // Le site principal d'abord : c'est lui qui crée le titre.
    sites.sort(
      (a, b) => (b.estPrincipal ? 1 : 0).compareTo(a.estPrincipal ? 1 : 0),
    );

    final typeBrut = _texte(brut, 'type');
    final couverture = _texte(brut, 'couvertureChoisie');
    return TitreImporte(
      numero: numero,
      nom: nom,
      sites: sites,
      typeTitre: TypeTitre.values.firstWhere(
        (type) => type.name == typeBrut,
        orElse: () => TypeTitre.autre,
      ),
      titresAlternatifs: <TitreAlternatif>[
        for (final alternatif in _liste(brut, 'titresAlternatifs'))
          if (alternatif is Map<String, Object?>)
            if (_texte(alternatif, 'nom') case final nomAlternatif?)
              TitreAlternatif(
                nom: nomAlternatif,
                langue: _texte(alternatif, 'langue') ?? '',
              ),
      ],
      listes: _textes(brut, 'listes'),
      categories: _textes(brut, 'categories'),
      langues: ServiceParametres.nettoyerLangues(_textes(brut, 'langues')),
      niveauContenu: _texte(brut, 'niveauContenu'),
      urlCouverture: _texte(brut, 'urlCouverture'),
      // Une image de l'appareil n'est exportée que par son nom de fichier
      // (vie privée) : inutilisable ici, la couverture du site s'affichera.
      couvertureChoisie:
          couverture != null &&
              !ServiceBibliotheque.estCouvertureLocale(couverture)
          ? couverture
          : null,
      resume: _texte(brut, 'resume'),
      auteur: _texte(brut, 'auteur'),
      statut: _texte(brut, 'statut'),
      // Format 4 : même décodage que la base (noms inconnus ignorés).
      champsManuels: <ChampTitre>{
        for (final nomChamp in _textes(brut, 'champsManuels'))
          for (final champ in ChampTitre.values)
            if (champ.name == nomChamp) champ,
      },
      descriptionPerso: _descriptionPerso(brut),
    );
  }

  /// Description personnelle (format 5) d'un titre du fichier : sans espaces
  /// autour, `null` si absente ou vide. Un texte plus long que
  /// [longueurMaxDescriptionPerso] (fichier modifié à la main : l'application
  /// n'en écrit jamais) est coupé plutôt que refusé, pour ne pas perdre tout
  /// le texte du client.
  static String? _descriptionPerso(Map<String, Object?> brut) {
    final texte = _texte(brut, 'descriptionPerso');
    if (texte == null || texte.length <= longueurMaxDescriptionPerso) {
      return texte;
    }
    return texte.substring(0, longueurMaxDescriptionPerso).trimRight();
  }

  /// Liste [cle] de [objet] ; vide si absente. Lève une [ErreurService] si
  /// elle a un autre type, ou si elle est absente et [obligatoire].
  static List<Object?> _liste(
    Map<String, Object?> objet,
    String cle, {
    bool obligatoire = false,
  }) {
    final valeur = objet[cle];
    if (valeur is List<Object?>) return valeur;
    if (valeur == null && !obligatoire) return const <Object?>[];
    throw ErreurService(
      'Cet export est incomplet ou abîmé (partie « $cle » illisible).',
    );
  }

  /// Texte [cle] sans espaces autour, `null` s'il est absent, vide ou d'un
  /// autre type.
  static String? _texte(Map<String, Object?> objet, String cle) {
    final valeur = objet[cle];
    if (valeur is! String) return null;
    final propre = valeur.trim();
    return propre.isEmpty ? null : propre;
  }

  /// Textes non vides de la liste [cle] (les autres valeurs sont ignorées).
  static List<String> _textes(Map<String, Object?> objet, String cle) {
    final valeur = objet[cle];
    if (valeur is! List<Object?>) return const <String>[];
    return <String>[
      for (final element in valeur)
        if (element is String && element.trim().isNotEmpty) element.trim(),
    ];
  }

  static bool _booleen(
    Map<String, Object?> objet,
    String cle, {
    required bool defaut,
  }) {
    final valeur = objet[cle];
    return valeur is bool ? valeur : defaut;
  }

  /// `true` pour une adresse `http`/`https` avec un hôte.
  static bool _estAdresseWeb(String texte) {
    final uri = Uri.tryParse(texte);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Hôte d'une adresse sans `www.` ni `m.` (comme
  /// `ServiceAjoutSite.trouverSourcePourUrl`), ou `null`.
  static String? _hote(String? adresse) {
    if (adresse == null) return null;
    final uri = Uri.tryParse(adresse);
    if (uri == null || uri.host.isEmpty) return null;
    return ServiceAjoutSite.proposerNom(uri);
  }

  // ------------------------------------------------------------ Écriture

  Future<ResultatImport> _importer(
    ContenuImport contenu, {
    bool? appliquerReglagesGeneraux,
  }) async {
    final gestionnaire = _gestionnaireTransactions;
    if (gestionnaire == null) {
      return _importerAvec(
        contenu,
        null,
        appliquerReglagesGeneraux: appliquerReglagesGeneraux,
      );
    }
    try {
      return await gestionnaire.executerEnTransaction(
        (transaction) => _importerAvec(
          contenu,
          transaction,
          appliquerReglagesGeneraux: appliquerReglagesGeneraux,
        ),
      );
    } on ErreurService {
      rethrow;
    } on Exception catch (erreur) {
      throw _importAnnule(erreur);
    } on ArgumentError catch (erreur) {
      // Valeur refusée par un dépôt (relancée en mode tout ou rien) : même
      // annulation qu'une erreur de base, jamais une erreur brute à
      // l'interface.
      throw _importAnnule(erreur);
    }
  }

  /// Erreur rendue quand l'import « tout ou rien » a été annulé par
  /// [erreur] (la transaction est déjà annulée : rien n'a été écrit).
  static ErreurService _importAnnule(Object erreur) {
    final detail = switch (erreur) {
      ErreurBaseDeDonnees(:final message) => ' ($message)',
      ArgumentError(:final message) => ' ($message)',
      _ => '',
    };
    return ErreurService(
      "L'import a échoué et a été entièrement annulé : rien n'a été "
      'ajouté à la bibliothèque$detail.',
      cause: erreur,
    );
  }

  /// Import proprement dit. [executeur] : transaction de l'import « tout ou
  /// rien », passée à **chaque** appel des dépôts (lectures comprises : un
  /// appel sans elle attendrait la fin de la transaction et bloquerait
  /// l'import) ; `null` sans gestionnaire de transactions.
  Future<ResultatImport> _importerAvec(
    ContenuImport contenu,
    DatabaseExecutor? executeur, {
    bool? appliquerReglagesGeneraux,
  }) async {
    // LIMITE : pendant l'import « tout ou rien », la transaction tient la
    // base : les autres lectures de l'application (bibliothèque, mises à
    // jour, téléchargements) attendent sa fin. Un import de quelques
    // centaines de titres ne dure que quelques secondes (aucun réseau).
    final ecriture = _Ecriture(this, contenu, executeur);
    // Lu avant toute écriture : « bibliothèque vide » décrit l'appareil tel
    // que le client l'avait avant l'import. Simple comptage (aucun titre
    // chargé).
    final bibliothequeVide =
        await _depotTitres.compterTitres(executeur: executeur) == 0;
    await ecriture.chargerEtat();
    await ecriture.importerSources();
    await ecriture.importerListes();
    final appliquer = appliquerReglagesGeneraux ?? bibliothequeVide;
    final reglagesAppliques = appliquer && await ecriture.importerReglages();
    for (final titre in contenu.titres) {
      await ecriture.importerTitre(titre);
    }
    // Après les titres : leurs catégories existent alors en base, et seules
    // les catégories d'un regroupement sans aucun titre restent à créer.
    await ecriture.importerEquivalences();
    return ResultatImport(
      versionFormat: contenu.versionFormat,
      titresAjoutes: ecriture.titresAjoutes,
      titresCompletes: ecriture.titresCompletes,
      titresIgnores: ecriture.titresIgnores,
      sitesAjoutes: ecriture.sitesAjoutes,
      listesAjoutees: ecriture.listesAjoutees,
      reglagesGenerauxAppliques: reglagesAppliques,
      archiveCompleteActivee: ecriture.archiveCompleteActivee,
      regroupementsAjoutes: ecriture.regroupementsAjoutes,
      erreurs: <ErreurLigneImport>[
        ...contenu.erreursLecture,
        ...ecriture.erreurs,
      ],
    );
  }
}

/// État d'un import en cours d'écriture : sites et listes connus, compteurs
/// et erreurs. Une instance par import.
class _Ecriture {
  _Ecriture(this._service, this._contenu, this._executeur);

  final ServiceImport _service;
  final ContenuImport _contenu;

  /// Transaction de l'import « tout ou rien », ou `null`. Passée à tous les
  /// appels des dépôts.
  final DatabaseExecutor? _executeur;

  /// `true` dans une transaction : une erreur de base n'est plus notée sur
  /// sa ligne mais relancée, pour que toute la transaction soit annulée
  /// (une écriture rattrapée resterait sinon à moitié faite).
  bool get _toutOuRien => _executeur != null;

  /// Sites connus par adresse de base exacte, puis par hôte (sans `www.` ni
  /// `m.`) : un site `https://www.exemple.com` de la base reconnaît
  /// `https://exemple.com` du fichier.
  final Map<String, Source> _sourcesParUrl = <String, Source>{};
  final Map<String, Source> _sourcesParHote = <String, Source>{};

  /// Listes connues, par nom en minuscules.
  final Map<String, ListeLecture> _listesParNom = <String, ListeLecture>{};

  int titresAjoutes = 0;
  int titresCompletes = 0;
  int titresIgnores = 0;
  int sitesAjoutes = 0;
  int listesAjoutees = 0;
  int regroupementsAjoutes = 0;

  /// `true` si l'import a activé « Archive complète » (elle ne l'était pas).
  bool archiveCompleteActivee = false;
  final List<ErreurLigneImport> erreurs = <ErreurLigneImport>[];

  Future<void> chargerEtat() async {
    for (final source in await _service._depotSources.chargerSources(
      executeur: _executeur,
    )) {
      _retenirSource(source);
    }
    for (final liste in await _service._depotListes.chargerListes(
      executeur: _executeur,
    )) {
      _listesParNom[liste.nom.toLowerCase()] = liste;
    }
  }

  void _retenirSource(Source source) {
    _sourcesParUrl[source.urlBase] = source;
    final hote = ServiceImport._hote(source.urlBase);
    // putIfAbsent : si deux sites de la base partagent un hôte, le premier
    // (ordre alphabétique) reste la référence, comme dans « Sources ».
    if (hote != null) _sourcesParHote.putIfAbsent(hote, () => source);
  }

  /// Site de la base pour un site du fichier ; `null` s'il est inconnu.
  ///
  /// Adresses exactes d'abord : l'adresse de base [urlSource] donnée par le
  /// fichier, puis la racine (`schéma://hôte`) de l'adresse du titre
  /// [urlTitre]. La recherche par hôte (sans `www.` ni `m.`) ne sert qu'en
  /// dernier recours, pour reconnaître un site enregistré sous une autre
  /// forme (`https://www.exemple.com` pour `https://exemple.com`).
  ///
  /// LIMITE : si la base contient deux sites sur le même domaine (par
  /// exemple `http://` et `https://`, ou avec et sans `www.`) et qu'aucune
  /// adresse exacte ne correspond, le premier par ordre alphabétique du nom
  /// est retenu ; le client peut ensuite déplacer le titre vers l'autre
  /// site depuis sa fiche.
  Source? _trouverSource(String? urlSource, String urlTitre) {
    if (urlSource != null) {
      final exacte = _sourcesParUrl[urlSource];
      if (exacte != null) return exacte;
    }
    final uriTitre = Uri.tryParse(urlTitre);
    if (uriTitre != null && uriTitre.host.isNotEmpty) {
      final racine = _sourcesParUrl[ServiceAjoutSite.calculerUrlBase(uriTitre)];
      if (racine != null) return racine;
    }
    if (urlSource != null) {
      final parHote = _sourcesParHote[ServiceImport._hote(urlSource)];
      if (parHote != null) return parHote;
    }
    return _sourcesParHote[ServiceImport._hote(urlTitre)];
  }

  // ---------------------------------------------------------------- Sites

  /// Crée les sites du fichier absents de la base ; un site présent (même
  /// adresse ou même hôte) est gardé tel quel, réglages du client compris.
  Future<void> importerSources() async {
    for (final importee in _contenu.sources) {
      if (_trouverSource(importee.urlBase, importee.urlBase) != null) continue;
      final type = importee.type;
      if (type == null) {
        erreurs.add(
          ErreurLigneImport(
            partie: PartieImport.site,
            numero: importee.numero,
            nom: importee.nom,
            message:
                'type de site inconnu (« ${importee.typeBrut} ») : '
                'ajoutez ce site à la main dans « Sources ».',
          ),
        );
        continue;
      }
      final reglages = _reglagesVerifies(importee, type);
      try {
        final source = await _service._depotSources.enregistrerSource(
          Source(
            nom: importee.nom,
            urlBase: importee.urlBase,
            typeSource: type,
            langueParDefaut: importee.langues.join(','),
            configurationSelecteurs: reglages,
            estActive: importee.estActive,
          ),
          executeur: _executeur,
        );
        _retenirSource(source);
        sitesAjoutes++;
      } on ErreurBaseDeDonnees catch (erreur) {
        if (_toutOuRien) rethrow;
        erreurs.add(
          ErreurLigneImport(
            partie: PartieImport.site,
            numero: importee.numero,
            nom: importee.nom,
            message: erreur.message,
          ),
        );
      }
    }
  }

  /// Réglages du site [importee] à enregistrer, vérifiés comme dans
  /// « Sources » (`ServiceAjoutSite.normaliserReglagesGeneriques`) :
  /// seulement pour un site générique (les autres types n'en lisent pas),
  /// sinon `null`. Des réglages refusés ne bloquent pas le site : il est
  /// importé **sans réglages** (l'adaptateur devine alors), et le refus est
  /// noté sur sa ligne pour que le client les corrige dans « Sources ». Ce
  /// refus est décidé avant l'écriture : il n'annule rien.
  String? _reglagesVerifies(SourceImportee importee, TypeSource type) {
    if (type != TypeSource.generique) return null;
    try {
      return ServiceAjoutSite.normaliserReglagesGeneriques(
        importee.configurationSelecteurs,
      );
    } on ErreurService catch (erreur) {
      erreurs.add(
        ErreurLigneImport(
          partie: PartieImport.site,
          numero: importee.numero,
          nom: importee.nom,
          message:
              'importé sans ses réglages avancés, refusés : '
              '${erreur.message}',
        ),
      );
      return null;
    }
  }

  // --------------------------------------------------------------- Listes

  /// Crée les listes du client absentes de la base, dans l'ordre du fichier
  /// (elles gardent ainsi leur ordre d'affichage relatif).
  Future<void> importerListes() async {
    for (final importee in _contenu.listes) {
      await _liste(importee.nom);
    }
  }

  /// Liste nommée [nom], créée si besoin ; `null` (erreur notée) si elle ne
  /// peut pas l'être.
  Future<ListeLecture?> _liste(String nom) async {
    final connue = _listesParNom[nom.toLowerCase()];
    if (connue != null) return connue;
    try {
      // Les listes système (Favoris…) sont créées par les migrations : elles
      // sont toujours déjà connues ici. Seules les listes du client peuvent
      // manquer.
      final creee = await _service._depotListes.creerListe(
        nom,
        executeur: _executeur,
      );
      _listesParNom[creee.nom.toLowerCase()] = creee;
      listesAjoutees++;
      return creee;
    } on ErreurBaseDeDonnees catch (erreur) {
      if (_toutOuRien) rethrow;
      erreurs.add(
        ErreurLigneImport(
          partie: PartieImport.liste,
          nom: nom,
          message: erreur.message,
        ),
      );
      return null;
    }
  }

  // ------------------------------------------------------------- Réglages

  /// Enregistre les langues, les niveaux de contenu et (format 4) le réglage
  /// « Archive complète » du fichier (seulement pour l'activer, voir
  /// [archiveCompleteActivee]). Renvoie `true` si les langues ou les
  /// niveaux ont été écrits.
  Future<bool> importerReglages() async {
    final depot = _service._depotParametres;
    final parametres = _service._serviceParametres;
    // ServiceParametres écrit sans exécuteur : interdit dans la transaction
    // (le constructeur l'empêche déjà, ceci est un filet de sécurité).
    if (depot == null && (parametres == null || _toutOuRien)) return false;
    // Valeurs déjà nettoyées à la lecture par ServiceParametres.nettoyer… :
    // mêmes règles que l'écran Paramètres.
    final langues = _contenu.languesGenerales;
    final niveaux = _contenu.niveauxContenu;
    var applique = false;
    try {
      if (langues.isNotEmpty) {
        if (depot != null) {
          await depot.enregistrerTexte(
            ServiceParametres.cleLangues,
            langues.join(','),
            executeur: _executeur,
          );
        } else {
          await parametres!.enregistrerLangues(langues);
        }
        applique = true;
      }
      if (niveaux != null) {
        if (depot != null) {
          await depot.enregistrerTexte(
            ServiceParametres.cleNiveauxContenu,
            niveaux.join(','),
            executeur: _executeur,
          );
        } else {
          await parametres!.enregistrerNiveauxContenu(niveaux);
        }
        applique = true;
      }
      // Format 4 : « Archive complète » suit les autres réglages généraux
      // (restauration sur un nouvel appareil, ou choix explicite du client).
      // Règle du client (relecture) : un import peut seulement l'ACTIVER,
      // jamais la couper (rien n'est retiré par un import). Les
      // téléchargements correspondants commencent à la prochaine application
      // des règles (démarrage, ou appel de l'interface).
      if (_contenu.archiveComplete == true) {
        // Déjà activée : rien à écrire ni à annoncer dans le bilan.
        final dejaActive = depot != null
            ? await depot.chargerEntier(
                    ServiceParametres.cleArchiveComplete,
                    executeur: _executeur,
                  ) ==
                  1
            : await parametres!.chargerArchiveComplete();
        if (!dejaActive) {
          if (depot != null) {
            await depot.enregistrerEntier(
              ServiceParametres.cleArchiveComplete,
              1,
              executeur: _executeur,
            );
          } else {
            await parametres!.enregistrerArchiveComplete(true);
          }
          archiveCompleteActivee = true;
        }
      }
    } on Exception catch (erreur) {
      if (_toutOuRien) rethrow;
      erreurs.add(
        ErreurLigneImport(
          partie: PartieImport.reglages,
          message: _messageDe(erreur),
        ),
      );
    }
    return applique;
  }

  // --------------------------------------------------------------- Titres

  /// Ajoute ou complète un titre. Une erreur est notée sans arrêter les
  /// titres suivants.
  ///
  /// Dans une transaction ([_toutOuRien]), une erreur de base est relancée :
  /// tout l'import est annulé. Sans transaction (LIMITE), le titre, puis
  /// ses sites, puis ses listes sont écrits l'un après l'autre ; un échec au
  /// milieu laisse un titre incomplet, que le même import relancé complète.
  Future<void> importerTitre(TitreImporte importe) async {
    try {
      final existant = await _titreExistant(importe);
      if (existant == null) {
        await _ajouterTitre(importe);
      } else if (await _completerTitre(existant, importe)) {
        titresCompletes++;
      } else {
        titresIgnores++;
      }
    } on Exception catch (erreur) {
      if (_toutOuRien) rethrow;
      _noterErreurTitre(importe, _messageDe(erreur));
    } on ArgumentError catch (erreur) {
      if (_toutOuRien) rethrow;
      // Valeur refusée par un dépôt (code de langue…) : propre à cette
      // ligne, elle ne doit pas arrêter l'import des suivantes.
      _noterErreurTitre(importe, '${erreur.message}');
    }
  }

  void _noterErreurTitre(TitreImporte importe, String message) {
    erreurs.add(
      ErreurLigneImport(
        partie: PartieImport.titre,
        numero: importe.numero,
        nom: importe.nom,
        message: message,
      ),
    );
  }

  /// Titre de la base dont un site (principal ou secondaire) a l'une des
  /// adresses du titre importé, ou `null`. Le site principal est regardé
  /// d'abord.
  Future<Titre?> _titreExistant(TitreImporte importe) async {
    for (final site in importe.sites) {
      final titre = await _service._depotTitresSources.chargerTitreParUrl(
        site.url,
        executeur: _executeur,
      );
      if (titre != null) return titre;
    }
    return null;
  }

  Future<void> _ajouterTitre(TitreImporte importe) async {
    // Site principal : celui du fichier s'il est configuré, sinon le
    // premier site lisible configuré (un lien seul ne peut pas être
    // principal : l'application ne sait pas le lire).
    SiteImporte? principal;
    Source? sourcePrincipale;
    for (final site in importe.sites) {
      if (site.estLienSeul) continue;
      final source = _trouverSource(site.urlSource, site.url);
      if (source != null) {
        principal = site;
        sourcePrincipale = source;
        break;
      }
    }
    if (principal == null || sourcePrincipale == null) {
      final premier = importe.sites.first;
      _noterErreurTitre(
        importe,
        'site « ${premier.nomSource ?? ServiceImport._hote(premier.url)} » '
        'non configuré : ajoutez-le dans « Sources », puis importez de '
        'nouveau ce fichier.',
      );
      return;
    }

    final enregistre = await _service._depotTitres.enregistrerTitre(
      Titre(
        idSource: sourcePrincipale.id,
        urlTitre: principal.url,
        nom: importe.nom,
        typeTitre: importe.typeTitre,
        urlCouverture: importe.urlCouverture,
        resume: importe.resume,
        auteur: importe.auteur,
        statut: importe.statut,
        titresAlternatifs: importe.titresAlternatifs,
        languesPreferees: importe.langues.isEmpty
            ? null
            : importe.langues.join(','),
        niveauContenu: importe.niveauContenu,
        couvertureChoisie: importe.couvertureChoisie,
        // Format 4 : les champs modifiés à la main restent protégés sur ce
        // nouvel appareil (sinon la première actualisation les écraserait).
        champsManuels: importe.champsManuels,
        // Format 5 : la description personnelle suit le titre ajouté.
        descriptionPerso: importe.descriptionPerso,
        // Date de vérification laissée vide : la prochaine vérification
        // traite ce titre comme jamais vérifié et récupère ses chapitres.
      ),
      categories: importe.categories,
      executeur: _executeur,
    );
    titresAjoutes++;
    final idTitre = enregistre.id!;
    final liens = await _service._depotTitresSources.chargerLiensTitre(
      idTitre,
      executeur: _executeur,
    );
    await _ajouterSitesManquants(importe, idTitre, liens);
    await _ajouterListesManquantes(importe, idTitre);
  }

  /// Complète un titre déjà présent. Renvoie `true` si quelque chose a été
  /// ajouté. Rien n'est remplacé : nom, fiche, site principal et choix déjà
  /// faits par le client restent tels quels.
  Future<bool> _completerTitre(Titre existant, TitreImporte importe) async {
    final idTitre = existant.id!;
    var complete = false;

    final liens = await _service._depotTitresSources.chargerLiensTitre(
      idTitre,
      executeur: _executeur,
    );
    if (await _ajouterSitesManquants(importe, idTitre, liens)) complete = true;
    if (await _ajouterListesManquantes(importe, idTitre)) complete = true;

    // Catégories et noms : union de l'existant et du fichier.
    final categoriesActuelles = <String>[
      for (final categorie
          in await _service._depotCategories.chargerCategoriesDuTitre(
            idTitre,
            executeur: _executeur,
          ))
        categorie.nom,
    ];
    // Champs modifiés à la main sur cet appareil (migration 10) : choix du
    // client, jamais complétés par l'import (`enregistrerTitre` les
    // ignorerait de toute façon ; les écarter ici garde le bilan juste).
    // Les champs protégés du fichier ne sont repris que pour un titre
    // ajouté : rien n'est remplacé sur un titre existant.
    final categoriesManquantes = <String>{
      if (!existant.estManuel(ChampTitre.categories))
        for (final brute in importe.categories)
          if (Categorie.normaliserNom(brute) case final nom
              when nom.isNotEmpty && !categoriesActuelles.contains(nom))
            nom,
    };
    final nomsActuels = <String>{
      existant.nom,
      for (final alternatif in existant.titresAlternatifs) alternatif.nom,
    };
    final alternatifsManquants = <TitreAlternatif>[
      if (!existant.estManuel(ChampTitre.titresAlternatifs))
        for (final alternatif in importe.titresAlternatifs)
          if (!nomsActuels.contains(alternatif.nom)) alternatif,
    ];
    final niveauManquant =
        !existant.estManuel(ChampTitre.niveauContenu) &&
        existant.niveauContenu == null &&
        importe.niveauContenu != null;
    if (categoriesManquantes.isNotEmpty ||
        alternatifsManquants.isNotEmpty ||
        niveauManquant) {
      // enregistrerTitre remplace les noms et (si fournies) les catégories :
      // on lui passe l'existant augmenté. La fiche est réécrite à l'identique.
      await _service._depotTitres.enregistrerTitre(
        existant.copierAvec(
          titresAlternatifs: <TitreAlternatif>[
            ...existant.titresAlternatifs,
            ...alternatifsManquants,
          ],
          niveauContenu: niveauManquant ? importe.niveauContenu : null,
        ),
        categories: categoriesManquantes.isEmpty
            ? null
            : <String>[...categoriesActuelles, ...categoriesManquantes],
        executeur: _executeur,
      );
      complete = true;
    }

    // Choix du client : seulement s'il n'en a pas encore fait sur cet
    // appareil.
    if (existant.languesPreferees == null && importe.langues.isNotEmpty) {
      await _service._depotTitres.enregistrerLanguesPreferees(
        idTitre,
        importe.langues.join(','),
        executeur: _executeur,
      );
      complete = true;
    }
    final couverture = importe.couvertureChoisie;
    if (existant.couvertureChoisie == null && couverture != null) {
      await _service._depotTitres.enregistrerCouvertureChoisie(
        idTitre,
        couverture,
        executeur: _executeur,
      );
      complete = true;
    }
    // Description personnelle (format 5) : écrite seulement si ce titre n'en
    // a pas encore sur cet appareil ; celle du client n'est jamais remplacée.
    final description = importe.descriptionPerso;
    if (existant.descriptionPerso == null && description != null) {
      await _service._depotTitres.enregistrerDescriptionPerso(
        idTitre,
        description,
        executeur: _executeur,
      );
      complete = true;
    }
    return complete;
  }

  /// Lie au titre les sites du fichier qu'il n'a pas encore, comme sites
  /// secondaires (le site principal d'un titre présent n'est jamais
  /// changé). Renvoie `true` si au moins un site a été lié.
  Future<bool> _ajouterSitesManquants(
    TitreImporte importe,
    int idTitre,
    List<LienTitreSource> liens,
  ) async {
    final adresses = <String>{for (final lien in liens) lien.urlTitre};
    final sourcesLiees = <int>{for (final lien in liens) lien.idSource};
    var ajoute = false;
    for (final site in importe.sites) {
      if (adresses.contains(site.url)) continue;
      final source = _trouverSource(site.urlSource, site.url);
      final nomSite = site.nomSource ?? ServiceImport._hote(site.url);
      if (source == null) {
        _noterErreurTitre(
          importe,
          'site « $nomSite » non configuré : son adresse ${site.url} n\'a pas '
          'été ajoutée.',
        );
        continue;
      }
      final idSource = source.id!;
      // Un titre n'a qu'une adresse par site (contrainte de la base) : une
      // autre adresse sur un site déjà lié n'est pas imposée au client.
      if (sourcesLiees.contains(idSource)) {
        _noterErreurTitre(
          importe,
          'le site « ${source.nom} » est déjà lié à ce titre avec une autre '
          'adresse ; ${site.url} n\'a pas été ajoutée.',
        );
        continue;
      }
      final autre = await _service._depotTitresSources.chargerTitreParUrl(
        site.url,
        executeur: _executeur,
      );
      if (autre != null) {
        _noterErreurTitre(
          importe,
          "l'adresse ${site.url} appartient déjà au titre « ${autre.nom} ».",
        );
        continue;
      }
      try {
        await _service._depotTitresSources.ajouterSourceSecondaire(
          idTitre,
          idSource,
          site.url,
          lienSeul: site.estLienSeul,
          executeur: _executeur,
        );
        adresses.add(site.url);
        sourcesLiees.add(idSource);
        ajoute = true;
      } on ErreurBaseDeDonnees catch (erreur) {
        if (_toutOuRien) rethrow;
        _noterErreurTitre(importe, erreur.message);
      }
    }
    return ajoute;
  }

  /// Ajoute le titre aux listes du fichier dont il ne fait pas encore
  /// partie (aucune n'est retirée). Renvoie `true` si au moins une a été
  /// ajoutée.
  ///
  /// « En attente » est reprise telle qu'exportée, sans le refus réservé au
  /// client (`ServiceBibliotheque.ajouterTitreALaListe`) : c'était l'état
  /// calculé par l'application, recalculé à la prochaine vérification.
  Future<bool> _ajouterListesManquantes(
    TitreImporte importe,
    int idTitre,
  ) async {
    final actuelles = <int>{
      for (final liste in await _service._depotListes.chargerListesDuTitre(
        idTitre,
        executeur: _executeur,
      ))
        ?liste.id,
    };
    var ajoute = false;
    for (final nom in importe.listes) {
      final liste = await _liste(nom);
      final idListe = liste?.id;
      if (idListe == null || actuelles.contains(idListe)) continue;
      await _service._depotListes.ajouterTitre(
        idListe,
        idTitre,
        executeur: _executeur,
      );
      actuelles.add(idListe);
      ajoute = true;
    }
    return ajoute;
  }

  // ------------------------------------------------------ Regroupements

  /// Enregistre les regroupements de catégories du fichier (format 3).
  ///
  /// Mêmes règles que le reste de l'import : rien n'est remplacé. Chaque
  /// ligne est vérifiée **avant** d'écrire, contre l'état de la base et les
  /// lignes déjà importées ; une ligne incohérente est refusée et notée
  /// sans arrêter les autres :
  /// - catégorie déjà rattachée à une autre référence sur cet appareil
  ///   (choix du client gardé) ;
  /// - référence elle-même rattachée à une autre catégorie (un seul
  ///   niveau) ;
  /// - catégorie qui est déjà la référence d'un autre groupe.
  /// Un regroupement déjà présent est ignoré sans erreur. Une catégorie
  /// absente de la base (regroupement sans titre) est créée.
  Future<void> importerEquivalences() async {
    final lignes = _contenu.equivalences;
    if (lignes.isEmpty) return;
    final depot = _service._depotEquivalences;
    if (depot == null) {
      erreurs.add(
        const ErreurLigneImport(
          partie: PartieImport.equivalence,
          message:
              "regroupements de catégories non importés (fonction absente de "
              'cet assemblage).',
        ),
      );
      return;
    }
    // État courant, tenu à jour ligne après ligne : par nom de catégorie,
    // son identifiant ; par identifiant, sa référence éventuelle.
    final idsParNom = <String, int>{
      for (final categorie in await _service._depotCategories.chargerCategories(
        executeur: _executeur,
      ))
        if (categorie.id != null) categorie.nom: categorie.id!,
    };
    final nomsParId = <int, String>{
      for (final MapEntry(key: nom, value: id) in idsParNom.entries) id: nom,
    };
    final referenceDe = <int, int>{
      for (final equivalence in await depot.chargerEquivalences(
        executeur: _executeur,
      ))
        equivalence.idCategorie: equivalence.idReference,
    };

    for (final ligne in lignes) {
      void refuser(String message) => erreurs.add(
        ErreurLigneImport(
          partie: PartieImport.equivalence,
          numero: ligne.numero,
          nom: ligne.categorie,
          message: message,
        ),
      );

      final idCategorie = idsParNom[ligne.categorie];
      final idReference = idsParNom[ligne.reference];
      final referenceActuelle = idCategorie == null
          ? null
          : referenceDe[idCategorie];
      if (referenceActuelle != null) {
        if (referenceActuelle != idReference) {
          refuser(
            'déjà regroupée avec « ${nomsParId[referenceActuelle]} » sur cet '
            'appareil : ce regroupement est gardé.',
          );
        }
        // Sinon : regroupement déjà présent, rien à faire.
        continue;
      }
      final referenceDeLaReference = idReference == null
          ? null
          : referenceDe[idReference];
      if (referenceDeLaReference != null) {
        refuser(
          '« ${ligne.reference} » est déjà regroupée avec '
          '« ${nomsParId[referenceDeLaReference]} » sur cet appareil : elle ne '
          'peut pas servir de référence.',
        );
        continue;
      }
      if (idCategorie != null && referenceDe.containsValue(idCategorie)) {
        refuser(
          'elle est déjà la référence d\'un autre groupe sur cet appareil.',
        );
        continue;
      }

      try {
        for (final nom in <String>[ligne.categorie, ligne.reference]) {
          if (idsParNom.containsKey(nom)) continue;
          final creee = await _service._depotCategories.enregistrerCategorie(
            nom,
            executeur: _executeur,
          );
          idsParNom[creee.nom] = creee.id!;
          nomsParId[creee.id!] = creee.nom;
        }
        final idC = idsParNom[ligne.categorie]!;
        final idR = idsParNom[ligne.reference]!;
        await depot.rattacherCategorie(idC, idR, executeur: _executeur);
        referenceDe[idC] = idR;
        regroupementsAjoutes++;
      } on ErreurBaseDeDonnees catch (erreur) {
        // Les refus prévisibles sont décidés ci-dessus : une erreur ici est
        // une vraie erreur de base, qui annule tout l'import « tout ou
        // rien ».
        if (_toutOuRien) rethrow;
        refuser(erreur.message);
      }
    }
  }

  /// Message lisible d'une erreur attrapée pendant l'import.
  static String _messageDe(Object erreur) => switch (erreur) {
    ErreurService(:final message) => message,
    ErreurBaseDeDonnees(:final message) => message,
    _ => "erreur inattendue lors de l'enregistrement ($erreur).",
  };
}
