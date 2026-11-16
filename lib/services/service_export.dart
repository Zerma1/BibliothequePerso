/// Export des liens de la bibliothèque (tâche R7, demande du client du
/// 2026-11-16) : sites configurés et titres suivis, dans un fichier JSON
/// complet (réimportable plus tard, R8) et un fichier Markdown lisible.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as chemins;

import '../donnees/depot_categories.dart';
import '../donnees/depot_chapitres.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/chapitre.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../sources/source_mangadex.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'service_bibliotheque.dart';
import 'service_parametres.dart';

/// Résultat d'un export : les deux fichiers écrits et ce qu'ils contiennent.
class ResultatExport {
  /// Crée le résultat.
  const ResultatExport({
    required this.cheminJson,
    required this.cheminMarkdown,
    required this.nombreTitres,
    required this.nombreSites,
  });

  /// Chemin complet du fichier JSON (complet, réimportable).
  final String cheminJson;

  /// Chemin complet du fichier Markdown (lisible, liens cliquables).
  final String cheminMarkdown;

  /// Nombre de titres exportés.
  final int nombreTitres;

  /// Nombre de sites exportés.
  final int nombreSites;
}

/// Un titre tel qu'il est exporté : le titre et ce qui vient d'autres tables.
class TitreExporte {
  /// Crée la ligne d'export.
  const TitreExporte({
    required this.titre,
    this.source,
    this.listes = const <String>[],
    this.categories = const <String>[],
    this.dernierChapitreLu,
    this.nombreChapitres = 0,
  });

  /// Titre enregistré.
  final Titre titre;

  /// Site du titre, ou `null` s'il n'existe plus.
  final Source? source;

  /// Noms des listes qui contiennent le titre (ordre d'affichage).
  final List<String> listes;

  /// Noms des catégories du titre.
  final List<String> categories;

  /// Chapitre lu de plus grand numéro, ou `null` si aucun n'est lu.
  final Chapitre? dernierChapitreLu;

  /// Nombre de chapitres connus du titre.
  final int nombreChapitres;
}

/// Tout ce qu'un export contient, lu dans la base. Séparé de l'écriture des
/// fichiers pour que la mise en forme ([ServiceExport.produireJson],
/// [ServiceExport.produireMarkdown]) soit testable sans base ni disque.
class ContenuExport {
  /// Crée le contenu.
  const ContenuExport({
    required this.date,
    this.versionApplication,
    this.sources = const <Source>[],
    this.titres = const <TitreExporte>[],
    this.listes = const <ListeLecture>[],
    this.languesGenerales = const <String>[],
    this.niveauxContenu = const <String>[],
  });

  /// Date de l'export (heure locale pour le Markdown, UTC dans le JSON).
  final DateTime date;

  /// Version de l'application qui a produit l'export, si connue.
  final String? versionApplication;

  /// Sites configurés.
  final List<Source> sources;

  /// Titres de la bibliothèque, triés par nom.
  final List<TitreExporte> titres;

  /// Listes, dans l'ordre d'affichage.
  final List<ListeLecture> listes;

  /// Langues de lecture générales du client.
  final List<String> languesGenerales;

  /// Niveaux de contenu affichés par le client.
  final List<String> niveauxContenu;
}

/// Écrit l'export de la bibliothèque dans `<dossier racine>/exports/`.
///
/// Le dossier est passé au constructeur (comme pour `ServiceRapportsErreur`)
/// plutôt que demandé à `StockageTelechargements`, qui ne gère que les
/// archives et les couvertures : voir [cheminDossierExports].
///
/// Aucun chemin local n'est exporté (il contiendrait le nom d'utilisateur de
/// l'appareil) : une couverture choisie sur l'appareil est réduite à son nom
/// de fichier.
class ServiceExport {
  /// Crée le service. [dossierExports] : dossier où les fichiers sont écrits
  /// (dossier temporaire dans les tests). [horloge] donne la date par
  /// défaut d'un export.
  ServiceExport({
    required DepotSources depotSources,
    required DepotTitres depotTitres,
    required DepotChapitres depotChapitres,
    required DepotListes depotListes,
    required DepotCategories depotCategories,
    required this.dossierExports,
    ServiceParametres? serviceParametres,
    String? versionApplication,
    DateTime Function()? horloge,
  }) : _depotSources = depotSources,
       _depotTitres = depotTitres,
       _depotChapitres = depotChapitres,
       _depotListes = depotListes,
       _depotCategories = depotCategories,
       _serviceParametres = serviceParametres,
       _versionApplication = versionApplication,
       _horloge = horloge ?? DateTime.now;

  /// Dossier des exports pour un dossier racine des téléchargements
  /// (`StockageTelechargements.dossierRacine`) : `<racine>/exports`.
  // LIMITE : sur Android, le dossier racine vient de
  // `getApplicationDocumentsDirectory()`, c'est-à-dire le dossier **privé**
  // de l'application (`/data/data/<paquet>/app_flutter`) : le fichier exporté
  // y est bien écrit, mais le client ne peut ni l'ouvrir ni le copier depuis
  // un gestionnaire de fichiers. Le rendre accessible demande un partage de
  // fichier (paquet du type `share_plus`) ou un dossier public choisi par le
  // client (`file_picker`) : paquet à proposer au client avant ajout.
  // Windows et Linux ne sont pas concernés (dossier « Documents » visible).
  static String cheminDossierExports(String dossierRacine) =>
      chemins.join(dossierRacine, nomDossierExports);

  /// Dossier où les fichiers sont écrits.
  final String dossierExports;

  final DepotSources _depotSources;
  final DepotTitres _depotTitres;
  final DepotChapitres _depotChapitres;
  final DepotListes _depotListes;
  final DepotCategories _depotCategories;

  /// Réglages du client (langues, niveaux de contenu) ; sans lui, les
  /// valeurs par défaut sont exportées.
  final ServiceParametres? _serviceParametres;
  final String? _versionApplication;
  final DateTime Function() _horloge;

  /// Export en cours : un second appel pendant l'écriture reçoit le même
  /// résultat au lieu d'écrire une seconde paire de fichiers (double clic).
  Future<ResultatExport>? _enCours;

  /// Titre de la section Markdown des titres qui ne sont dans aucune liste.
  static const String titreSectionSansListe = 'Sans liste';

  // ---------------------------------------------------------------- Export

  /// Lit la bibliothèque et écrit deux fichiers dans [dossierExports] :
  /// `bibliotheque_perso-export-AAAA-MM-JJ_HHMM.json` et `.md` ([date] :
  /// maintenant par défaut, heure locale). Si ces noms sont déjà pris (deux
  /// exports dans la même minute), `_2`, `_3`… est ajouté aux deux.
  ///
  /// Un appel pendant un export en cours reçoit le résultat de celui-ci.
  /// Lève une [ErreurService] si un fichier ne peut pas être écrit (aucun
  /// fichier n'est alors laissé à moitié), et laisse passer
  /// `ErreurBaseDeDonnees` si la base est illisible.
  Future<ResultatExport> exporter({DateTime? date}) {
    final enCours = _enCours;
    if (enCours != null) return enCours;
    final nouveau = _exporter(date ?? _horloge());
    _enCours = nouveau;
    // Libéré après coup, réussite ou échec : un nouvel export reste possible.
    nouveau.then<void>(
      (_) => _enCours = null,
      onError: (Object _) => _enCours = null,
    );
    return nouveau;
  }

  Future<ResultatExport> _exporter(DateTime date) async {
    final contenu = await chargerContenu(date: date);
    final json = produireJson(contenu);
    final markdown = produireMarkdown(contenu);
    try {
      final dossier = Directory(dossierExports);
      await dossier.create(recursive: true);
      final base = await _reserverNomDeBase(dossier, date);
      final cheminJson = '$base.json';
      final cheminMarkdown = '$base.md';
      await _ecrireLesDeux(<String, String>{
        cheminJson: json,
        cheminMarkdown: markdown,
      });
      return ResultatExport(
        cheminJson: cheminJson,
        cheminMarkdown: cheminMarkdown,
        nombreTitres: contenu.titres.length,
        nombreSites: contenu.sources.length,
      );
    } on FileSystemException catch (erreur) {
      throw ErreurService(
        "L'export n'a pas pu être enregistré.",
        cause: erreur,
      );
    }
  }

  /// Écrit chaque texte dans un `.part`, puis renomme : un export interrompu
  /// ne laisse jamais un fichier tronqué qui passerait pour complet (l'import
  /// R8 le lirait). En cas d'erreur, les `.part` sont effacés.
  ///
  /// LIMITE : les deux renommages ne sont pas atomiques ensemble ; si le
  /// second échoue, le JSON (déjà renommé) reste seul. Il est complet et
  /// lisible : on le garde plutôt que de perdre l'export.
  Future<void> _ecrireLesDeux(Map<String, String> fichiers) async {
    final partiels = <String>[];
    try {
      for (final MapEntry(key: chemin, value: texte) in fichiers.entries) {
        final partiel = '$chemin.part';
        partiels.add(partiel);
        // UTF-8 explicite : accents, apostrophes typographiques et titres
        // japonais doivent se relire à l'identique sur toutes les plateformes.
        await File(partiel).writeAsString(texte, encoding: utf8, flush: true);
      }
      for (final chemin in fichiers.keys) {
        await File('$chemin.part').rename(chemin);
      }
    } on FileSystemException {
      for (final partiel in partiels) {
        try {
          final fichier = File(partiel);
          if (await fichier.exists()) await fichier.delete();
        } on FileSystemException {
          // Un .part restant n'est qu'un fichier en trop, sans conséquence.
        }
      }
      rethrow;
    }
  }

  /// Chemin sans extension d'un nouvel export de [date], libre pour le
  /// `.json` comme pour le `.md`.
  Future<String> _reserverNomDeBase(Directory dossier, DateTime date) async {
    final horodatage = horodatageFichier(date);
    // Borné : plusieurs dizaines d'exports dans la même minute n'ont pas de
    // sens ; la borne évite toute boucle sans fin.
    for (var numero = 1; numero <= nombreMaximalExportsMemeMinute; numero++) {
      final suffixe = numero == 1 ? '' : '_$numero';
      final base = chemins.join(
        dossier.path,
        '$prefixeFichierExport$horodatage$suffixe',
      );
      if (!await File('$base.json').exists() &&
          !await File('$base.md').exists()) {
        return base;
      }
    }
    throw FileSystemException(
      'Trop d\'exports dans la même minute',
      dossier.path,
    );
  }

  /// Horodatage du nom de fichier : `AAAA-MM-JJ_HHMM` ([date] telle quelle,
  /// en général l'heure locale, celle que le client lit). Fonction pure.
  static String horodatageFichier(DateTime date) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${deux(date.month)}-'
        '${deux(date.day)}_${deux(date.hour)}${deux(date.minute)}';
  }

  // ------------------------------------------------------- Lecture en base

  /// Lit tout ce qu'un export contient (base seulement, aucun réseau).
  ///
  /// Une requête par titre pour ses listes, ses catégories et ses
  /// chapitres : suffisant pour une bibliothèque personnelle de quelques
  /// centaines de titres.
  Future<ContenuExport> chargerContenu({DateTime? date}) async {
    final sources = await _depotSources.chargerSources();
    final sourcesParId = <int, Source>{
      for (final source in sources)
        if (source.id != null) source.id!: source,
    };
    final titres = <TitreExporte>[];
    // Aucun filtre : l'export contient toute la bibliothèque, y compris les
    // titres masqués par le filtre de niveau de contenu.
    for (final titre in await _depotTitres.chargerTitres()) {
      final id = titre.id;
      if (id == null) continue;
      final chapitres = await _depotChapitres.chargerChapitres(id);
      titres.add(
        TitreExporte(
          titre: titre,
          source: sourcesParId[titre.idSource],
          listes: <String>[
            for (final liste in await _depotListes.chargerListesDuTitre(id))
              liste.nom,
          ],
          categories: <String>[
            for (final categorie
                in await _depotCategories.chargerCategoriesDuTitre(id))
              categorie.nom,
          ],
          dernierChapitreLu: dernierChapitreLu(chapitres),
          nombreChapitres: chapitres.length,
        ),
      );
    }
    titres.sort(
      (a, b) => a.titre.nom.toLowerCase().compareTo(b.titre.nom.toLowerCase()),
    );
    final parametres = _serviceParametres;
    return ContenuExport(
      date: date ?? _horloge(),
      versionApplication: _versionApplication,
      sources: sources,
      titres: titres,
      listes: await _depotListes.chargerListes(),
      languesGenerales: parametres == null
          ? List<String>.of(languesParDefautClient)
          : await parametres.chargerLangues(),
      niveauxContenu: parametres == null
          ? const <String>[]
          : await parametres.chargerNiveauxContenu(),
    );
  }

  /// Chapitre lu de plus grand numéro (à égalité, le plus récemment publié),
  /// ou `null` si aucun n'est lu. Fonction pure.
  ///
  /// Le plus grand numéro plutôt que le dernier ouvert : la base ne garde pas
  /// la date de lecture, et c'est ce numéro que le client cherche pour
  /// reprendre sa lecture ailleurs.
  static Chapitre? dernierChapitreLu(Iterable<Chapitre> chapitres) {
    Chapitre? meilleur;
    for (final chapitre in chapitres) {
      if (!chapitre.estLu) continue;
      final actuel = meilleur;
      if (actuel == null ||
          chapitre.numero > actuel.numero ||
          (chapitre.numero == actuel.numero &&
              _plusRecent(chapitre.datePublication, actuel.datePublication))) {
        meilleur = chapitre;
      }
    }
    return meilleur;
  }

  static bool _plusRecent(DateTime? a, DateTime? b) =>
      a != null && (b == null || a.isAfter(b));

  // ------------------------------------------------------------------ JSON

  /// Couverture choisie telle qu'exportée : une adresse du site est gardée,
  /// un chemin de l'appareil est réduit à son nom de fichier (le chemin
  /// complet contiendrait le nom d'utilisateur). Fonction pure.
  static String? couvertureExportee(String? couvertureChoisie) {
    final valeur = couvertureChoisie?.trim();
    if (valeur == null || valeur.isEmpty) return null;
    if (!ServiceBibliotheque.estCouvertureLocale(valeur)) return valeur;
    // Séparateurs Windows et Unix (et `file:///…`) : le fichier a pu être
    // choisi sur un autre système que celui qui exporte.
    final morceaux = valeur
        .split(RegExp(r'[\\/]'))
        .where((morceau) => morceau.isNotEmpty)
        .toList();
    return morceaux.isEmpty ? null : morceaux.last;
  }

  /// Contenu du fichier JSON (indenté, UTF-8 sans échappement des accents).
  /// Fonction pure.
  ///
  /// Format `versionFormatExport` (1) : `format`, `version`, `dateExport`
  /// (UTC, ISO 8601), `versionApplication`, `reglages` (`langues`,
  /// `niveauxContenu`), `listes`, `sources`, `titres`. Les titres désignent
  /// leur site par son nom **et** son `urlBase` (unique), pour que l'import
  /// retrouve le bon site même si deux sites portent le même nom.
  static String produireJson(ContenuExport contenu) {
    Map<String, Object?> versSource(Source source) => <String, Object?>{
      'nom': source.nom,
      'urlBase': source.urlBase,
      'type': source.typeSource.name,
      'langues': SourceMangaDex.languesIsoDepuisPreference(
        source.langueParDefaut,
      ),
      'active': source.estActive,
    };

    Map<String, Object?>? versChapitre(Chapitre? chapitre) => chapitre == null
        ? null
        : <String, Object?>{
            'numero': chapitre.numero,
            'nom': chapitre.nom,
            'langue': chapitre.langue,
            // LIMITE : la base ne garde pas la date de lecture ; seule la
            // date de publication du chapitre est connue.
            'datePublication': chapitre.datePublication
                ?.toUtc()
                .toIso8601String(),
          };

    Map<String, Object?> versTitre(TitreExporte exporte) {
      final titre = exporte.titre;
      return <String, Object?>{
        'nom': titre.nom,
        'titresAlternatifs': <Map<String, Object?>>[
          for (final alternatif in titre.titresAlternatifs)
            <String, Object?>{
              'nom': alternatif.nom,
              'langue': alternatif.langue,
            },
        ],
        'type': titre.typeTitre.name,
        'url': titre.urlTitre,
        'source': exporte.source?.nom,
        'urlSource': exporte.source?.urlBase,
        'listes': exporte.listes,
        'categories': exporte.categories,
        'langues': titre.listeLanguesPreferees,
        'niveauContenu': titre.niveauContenu,
        'urlCouverture': titre.urlCouverture,
        'couvertureChoisie': couvertureExportee(titre.couvertureChoisie),
        'auteur': titre.auteur,
        'statut': titre.statut,
        'dernierChapitreLu': versChapitre(exporte.dernierChapitreLu),
        'nombreChapitres': exporte.nombreChapitres,
      };
    }

    final donnees = <String, Object?>{
      'format': identifiantFormatExport,
      'version': versionFormatExport,
      'dateExport': contenu.date.toUtc().toIso8601String(),
      'versionApplication': contenu.versionApplication,
      'reglages': <String, Object?>{
        'langues': contenu.languesGenerales,
        'niveauxContenu': contenu.niveauxContenu,
      },
      'listes': <Map<String, Object?>>[
        for (final liste in contenu.listes)
          <String, Object?>{
            'nom': liste.nom,
            'systeme': liste.estSysteme,
            'ordre': liste.ordre,
          },
      ],
      'sources': contenu.sources.map(versSource).toList(),
      'titres': contenu.titres.map(versTitre).toList(),
    };
    return '${const JsonEncoder.withIndent('  ').convert(donnees)}\n';
  }

  // -------------------------------------------------------------- Markdown

  /// Contenu du fichier Markdown, lisible en français. Fonction pure.
  ///
  /// Une section par liste, dans l'ordre d'affichage (Favoris, Suivis,
  /// Planifié, En attente, puis les listes du client), puis « Sans liste »
  /// si des titres n'appartiennent à aucune liste, puis les sites. Chaque
  /// titre est un lien `[Nom](url)` suivi de son site, de ses catégories et
  /// du dernier chapitre lu. Un titre présent dans plusieurs listes apparaît
  /// dans chacune.
  static String produireMarkdown(ContenuExport contenu) {
    final tampon = StringBuffer();
    final date = contenu.date;
    String deux(int n) => n.toString().padLeft(2, '0');
    tampon
      ..writeln('# Bibliothèque perso — export')
      ..writeln()
      ..writeln(
        'Export du ${deux(date.day)}/${deux(date.month)}/${date.year} à '
        '${deux(date.hour)}:${deux(date.minute)} : '
        '${_pluriel(contenu.titres.length, 'titre', 'titres')}, '
        '${_pluriel(contenu.sources.length, 'site', 'sites')}.',
      );

    void section(String nom, List<TitreExporte> titres) {
      tampon
        ..writeln()
        ..writeln('## ${echapperMarkdown(nom)}')
        ..writeln();
      if (titres.isEmpty) {
        tampon.writeln('_Aucun titre._');
        return;
      }
      for (final exporte in titres) {
        tampon.writeln(_ligneTitre(exporte));
      }
    }

    for (final liste in contenu.listes) {
      section(liste.nom, <TitreExporte>[
        for (final exporte in contenu.titres)
          if (exporte.listes.contains(liste.nom)) exporte,
      ]);
    }
    final sansListe = <TitreExporte>[
      for (final exporte in contenu.titres)
        if (exporte.listes.isEmpty) exporte,
    ];
    if (sansListe.isNotEmpty) section(titreSectionSansListe, sansListe);

    tampon
      ..writeln()
      ..writeln('## Sites')
      ..writeln();
    if (contenu.sources.isEmpty) {
      tampon.writeln('_Aucun site configuré._');
    }
    for (final source in contenu.sources) {
      final details = <String>[
        source.typeSource.name,
        if (source.langueParDefaut.trim().isNotEmpty)
          'langues : ${SourceMangaDex.languesIsoDepuisPreference(source.langueParDefaut).join(', ')}',
        if (!source.estActive) 'désactivé',
      ];
      tampon.writeln(
        '- ${_lien(source.nom, source.urlBase)} — ${details.join(' · ')}',
      );
    }
    return tampon.toString();
  }

  static String _ligneTitre(TitreExporte exporte) {
    final details = <String>[
      exporte.source == null
          ? 'site inconnu'
          : echapperMarkdown(exporte.source!.nom),
      if (exporte.categories.isNotEmpty)
        'catégories : ${echapperMarkdown(exporte.categories.join(', '))}',
      if (exporte.dernierChapitreLu case final chapitre?)
        'dernier chapitre lu : '
            '${_numeroLisible(chapitre.numero)}'
            '${chapitre.langue.isEmpty ? '' : ' (${chapitre.langue})'}'
      else
        'aucun chapitre lu',
    ];
    return '- ${_lien(exporte.titre.nom, exporte.titre.urlTitre)} — '
        '${details.join(' · ')}';
  }

  static String _numeroLisible(double numero) {
    try {
      return StockageTelechargements.formaterNumero(numero);
    } on ArgumentError {
      return '?';
    }
  }

  static String _pluriel(int nombre, String singulier, String pluriel) =>
      '$nombre ${nombre > 1 ? pluriel : singulier}';

  /// Lien Markdown `[texte](adresse)` : texte échappé, et caractères qui
  /// couperaient le lien (espaces, parenthèses, chevrons) encodés dans
  /// l'adresse.
  static String _lien(String texte, String adresse) {
    final cible = adresse
        .trim()
        .replaceAll(' ', '%20')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29')
        .replaceAll('<', '%3C')
        .replaceAll('>', '%3E');
    return '[${echapperMarkdown(texte)}]($cible)';
  }

  /// Échappe les caractères qui changeraient la mise en forme Markdown d'un
  /// nom (`[`, `]`, `*`, `_`, `` ` ``, `\`, `#`, `<`, `>`, `|`) ; les
  /// apostrophes et accents restent tels quels. Fonction pure.
  static String echapperMarkdown(String texte) => texte.replaceAllMapped(
    RegExp(r'[\\`*_\[\]#<>|]'),
    (correspondance) => '\\${correspondance[0]}',
  );
}
