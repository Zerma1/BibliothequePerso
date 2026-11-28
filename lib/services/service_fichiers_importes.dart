/// Service des fichiers importés (version 0.4.0, « formats de liseuse ») :
/// import de CBZ, PDF et EPUB **sans DRM** par glisser-déposer ou par
/// l'explorateur, lecture dans l'application et suppression.
///
/// Décisions du client : le fichier est copié dans la bibliothèque (celui
/// d'origine n'est jamais modifié) ; un fichier protégé est refusé, sans
/// aucune tentative de contournement (PLAYBOOK.md section 10). Les règles
/// pures (signatures, DRM, structure EPUB) sont dans
/// `analyse_fichiers_importes.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as chemins;

import '../donnees/depot_chapitres.dart';
import '../donnees/depot_fichiers_importes.dart';
import '../donnees/depot_positions_lecture.dart';
import '../donnees/depot_titres.dart';
import '../donnees/empreinte_sha256.dart';
import '../donnees/erreur_stockage.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/chapitre.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/fichier_importe.dart';
import '../modeles/journal.dart';
import '../modeles/position_lecture.dart';
import '../modeles/titre.dart';
import 'analyse_fichiers_importes.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';

export 'analyse_fichiers_importes.dart' show ContenuEpub, SectionEpub;

/// Issue de l'import d'un fichier.
enum StatutImportFichier {
  /// Fichier copié et titre créé.
  importe,

  /// Même contenu déjà dans la bibliothèque (même renommé).
  doublon,

  /// Extension autre que `.cbz`, `.pdf` ou `.epub`.
  formatNonPrisEnCharge,

  /// Fichier protégé (DRM, chiffrement) : refusé.
  protegeParDrm,

  /// Contenu vide, abîmé ou qui ne correspond pas à l'extension.
  illisible,

  /// Fichier plus gros que [tailleMaxFichierImporte].
  tropVolumineux,

  /// Erreur de lecture, de copie ou d'écriture en base.
  erreur,
}

/// Résultat de l'import d'un fichier (un par chemin demandé, dans l'ordre).
class ResultatImportFichier {
  /// Crée un résultat.
  const ResultatImportFichier({
    required this.nomFichier,
    required this.statut,
    required this.message,
    this.titre,
    this.chapitre,
  });

  /// Nom du fichier (sans dossier), pour l'affichage.
  final String nomFichier;

  /// Issue de l'import.
  final StatutImportFichier statut;

  /// Explication affichable telle quelle (en français).
  final String message;

  /// Titre créé ([StatutImportFichier.importe]) ou titre déjà présent
  /// ([StatutImportFichier.doublon], si retrouvé) ; `null` sinon.
  final Titre? titre;

  /// Chapitre créé (le fichier lui-même), pour un import réussi.
  final Chapitre? chapitre;

  /// `true` si le fichier a été importé.
  bool get estImporte => statut == StatutImportFichier.importe;

  @override
  String toString() => 'ResultatImportFichier($nomFichier, ${statut.name})';
}

/// Import, lecture et suppression des fichiers importés.
class ServiceFichiersImportes {
  /// Crée le service sur les dépôts et le stockage de l'application.
  ///
  /// [horloge] : date de l'import et des positions (tests).
  ServiceFichiersImportes({
    required DepotFichiersImportes depotFichiersImportes,
    required DepotPositionsLecture depotPositions,
    required DepotTitres depotTitres,
    required DepotChapitres depotChapitres,
    required StockageTelechargements stockage,
    DateTime Function()? horloge,
  }) : _depotFichiers = depotFichiersImportes,
       _positions = depotPositions,
       _titres = depotTitres,
       _chapitres = depotChapitres,
       _bibliotheque = stockage,
       _horloge = horloge ?? DateTime.now;

  final DepotFichiersImportes _depotFichiers;
  final DepotPositionsLecture _positions;
  final DepotTitres _titres;
  final DepotChapitres _chapitres;
  final StockageTelechargements _bibliotheque;
  final DateTime Function() _horloge;

  /// Dernier import demandé : un nouvel appel attend la fin du précédent
  /// (traitement toujours séquentiel, même avec deux glisser-déposer
  /// rapprochés), ce qui garde fiable le refus des doublons.
  Future<void> _dernierImport = Future<void>.value();

  /// Structure du dernier EPUB ouvert (le lecteur demande les sections une
  /// à une : inutile de relire l'OPF à chaque page).
  ({String nomArchive, ContenuEpub contenu})? _dernierEpub;

  // ------------------------------------------------------------------ Import

  /// Importe les fichiers [chemins] (glisser-déposer ou explorateur), un par
  /// un, et renvoie un résultat par chemin, dans le même ordre.
  ///
  /// Pour chaque fichier : format reconnu à l'extension **et** vérifié dans
  /// le contenu (signature, structure EPUB, au moins une image pour un CBZ),
  /// refus d'un fichier protégé, empreinte SHA-256 et refus d'un doublon,
  /// copie dans la bibliothèque puis enregistrement du titre. Si
  /// l'enregistrement échoue, la copie est effacée. Ne lève jamais : une
  /// erreur d'un fichier est rangée dans son résultat et n'arrête pas les
  /// suivants. Au-delà de [nombreMaxFichiersParImport] fichiers, les
  /// suivants sont refusés (« trop de fichiers »).
  Future<List<ResultatImportFichier>> importer(List<String> cheminsFichiers) {
    final copie = List<String>.of(cheminsFichiers);
    final suite = _dernierImport.then((_) => _importerTous(copie));
    _dernierImport = suite.then<void>((_) {}, onError: (Object _) {});
    return suite;
  }

  Future<List<ResultatImportFichier>> _importerTous(
    List<String> cheminsFichiers,
  ) async {
    final resultats = <ResultatImportFichier>[];
    for (var i = 0; i < cheminsFichiers.length; i++) {
      final nom = chemins.basename(cheminsFichiers[i]);
      if (i >= nombreMaxFichiersParImport) {
        resultats.add(
          ResultatImportFichier(
            nomFichier: nom,
            statut: StatutImportFichier.erreur,
            message:
                'Trop de fichiers à la fois ($nombreMaxFichiersParImport au '
                'plus) : importez celui-ci ensuite.',
          ),
        );
        continue;
      }
      resultats.add(await _importerUn(cheminsFichiers[i]));
    }
    final importes = resultats.where((r) => r.estImporte).length;
    Journal.actuel.info(
      CategorieJournal.bibliotheque,
      'Import de fichiers : $importes importé(s) sur '
      '${cheminsFichiers.length}',
    );
    return resultats;
  }

  Future<ResultatImportFichier> _importerUn(String chemin) async {
    final nomFichier = chemins.basename(chemin);
    ResultatImportFichier refus(StatutImportFichier statut, String message) =>
        ResultatImportFichier(
          nomFichier: nomFichier,
          statut: statut,
          message: message,
        );

    final format = FormatFichierLocal.depuisNomFichier(nomFichier);
    if (format == null) {
      return refus(
        StatutImportFichier.formatNonPrisEnCharge,
        'Format non pris en charge : seuls les fichiers CBZ, PDF et EPUB '
        'sans DRM peuvent être importés.',
      );
    }
    String? nomArchive;
    try {
      final fichier = File(chemin);
      if (!await fichier.exists()) {
        return refus(StatutImportFichier.erreur, 'Fichier introuvable.');
      }
      final taille = await fichier.length();
      if (taille > tailleMaxFichierImporte) {
        return refus(
          StatutImportFichier.tropVolumineux,
          'Fichier trop volumineux (2 Go au plus).',
        );
      }
      if (taille == 0) {
        return refus(StatutImportFichier.illisible, 'Le fichier est vide.');
      }
      final debut = await _lirePlage(
        fichier,
        0,
        AnalyseFichiersImportes.octetsSignature,
      );
      if (!AnalyseFichiersImportes.aSignatureAttendue(format, debut)) {
        return refus(
          StatutImportFichier.illisible,
          "Le contenu ne correspond pas à un fichier "
          "${format.extension.toUpperCase()}.",
        );
      }
      final analyse = await _analyser(fichier, format, taille);

      // LIMITE : le fichier d'origine pourrait changer entre l'analyse, le
      // calcul de l'empreinte et la copie (autre programme qui l'écrit) ;
      // cas improbable pour un fichier choisi par le client, accepté pour
      // ne pas copier 2 Go avant de savoir s'il s'agit d'un doublon.
      final empreinte = await calculerEmpreinteSha256Fichier(chemin);
      final existant = await _depotFichiers.chargerParEmpreinte(empreinte);
      if (existant != null) {
        final chapitre = await _chapitres.chargerChapitre(existant.idChapitre);
        final idTitre = chapitre?.idTitre;
        _journaliser(format, taille, StatutImportFichier.doublon);
        return ResultatImportFichier(
          nomFichier: nomFichier,
          statut: StatutImportFichier.doublon,
          message:
              'Ce fichier est déjà dans la bibliothèque (importé sous le nom '
              '« ${existant.nomOrigine} »).',
          titre: idTitre == null ? null : await _titres.chargerTitre(idTitre),
        );
      }
      final nomTitre = _nomTitre(analyse.titre, nomFichier);
      nomArchive = await _bibliotheque.importerFichier(
        chemin,
        typeTitre: format.typeTitreParDefaut,
        nomTitre: nomTitre,
        format: format,
      );
      final enregistre = await _depotFichiers.enregistrerImport(
        nom: nomTitre,
        format: format,
        empreinteSha256: empreinte,
        taille: taille,
        nomOrigine: nomFichier,
        nomArchive: nomArchive,
        auteur: analyse.auteur,
        langue: analyse.langue ?? '',
        dateImport: _horloge(),
      );
      nomArchive = null;
      _journaliser(format, taille, StatutImportFichier.importe);
      return ResultatImportFichier(
        nomFichier: nomFichier,
        statut: StatutImportFichier.importe,
        message: '« ${enregistre.titre.nom} » a été ajouté à la bibliothèque.',
        titre: enregistre.titre,
        chapitre: enregistre.chapitre,
      );
    } on RefusAnalyse catch (refusAnalyse) {
      final statut = refusAnalyse.motif == MotifRefusAnalyse.protegeParDrm
          ? StatutImportFichier.protegeParDrm
          : StatutImportFichier.illisible;
      _journaliser(format, null, statut);
      return refus(statut, refusAnalyse.message);
    } catch (erreur, pile) {
      // Tout le reste (disque plein, accès refusé, base) : le fichier est
      // compté en erreur et les suivants sont traités. Jamais de chemin
      // dans le journal (il contient le nom de l'utilisateur).
      Journal.actuel.avertissement(
        CategorieJournal.bibliotheque,
        'Import d\'un fichier ${format.name} impossible',
        erreur: erreur is ErreurStockage ? erreur.message : erreur.runtimeType,
        pile: erreur is Error ? pile : null,
      );
      return refus(StatutImportFichier.erreur, _messageErreur(erreur));
    } finally {
      // Copie faite mais titre non enregistré : la copie est effacée pour ne
      // pas laisser un fichier inconnu de la bibliothèque.
      final copie = nomArchive;
      if (copie != null) await _supprimerCopieSansErreur(copie);
    }
  }

  /// Message affichable pour une erreur inattendue de l'import.
  static String _messageErreur(Object erreur) {
    if (erreur is ErreurStockage) return erreur.message;
    if (erreur is ErreurBaseDeDonnees) return erreur.message;
    if (erreur is FileSystemException) {
      return 'Impossible de lire le fichier.';
    }
    return "L'import de ce fichier a échoué.";
  }

  /// Nom du titre : titre de l'EPUB s'il existe, sinon nom du fichier sans
  /// extension (le nom complet si celui-ci est vide, `.cbz` par exemple).
  static String _nomTitre(String? titreLu, String nomFichier) {
    final titre = titreLu?.trim() ?? '';
    if (titre.isNotEmpty) return titre;
    final sansExtension = chemins.basenameWithoutExtension(nomFichier).trim();
    return sansExtension.isNotEmpty ? sansExtension : nomFichier;
  }

  void _journaliser(
    FormatFichierLocal format,
    int? taille,
    StatutImportFichier statut,
  ) {
    // Ni nom ni chemin : seulement le format, la taille et l'issue.
    Journal.actuel.info(
      CategorieJournal.bibliotheque,
      'Import ${format.name}${taille == null ? '' : ' ($taille octets)'} : '
      '${statut.name}',
    );
  }

  Future<void> _supprimerCopieSansErreur(String nomArchive) async {
    try {
      await _bibliotheque.supprimerFichierImporte(nomArchive);
    } catch (erreur) {
      // LIMITE : copie restée sur le disque sans titre (disque qui refuse
      // l'effacement) ; elle ne gêne pas la bibliothèque, seulement la place.
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        "Copie d'un import abandonné non effacée",
        erreur: erreur.runtimeType,
      );
    }
  }

  /// Vérifie le contenu du fichier selon son [format] et renvoie les
  /// métadonnées utiles ; lève un [RefusAnalyse] sinon.
  Future<({String? titre, String? auteur, String? langue})> _analyser(
    File fichier,
    FormatFichierLocal format,
    int taille,
  ) async {
    switch (format) {
      case FormatFichierLocal.pdf:
        // Début (PDF linéarisé : premier trailer en tête) et fin (trailer,
        // dictionnaire de la table des références) : voir
        // AnalyseFichiersImportes.contientChiffrementPdf.
        final debut = await _lirePlage(fichier, 0, octetsRecherchePdfChiffre);
        final fin = taille > octetsRecherchePdfChiffre
            ? await _lirePlage(
                fichier,
                taille - octetsRecherchePdfChiffre,
                octetsRecherchePdfChiffre,
              )
            : const <int>[];
        if (AnalyseFichiersImportes.contientChiffrementPdf(debut) ||
            AnalyseFichiersImportes.contientChiffrementPdf(fin)) {
          throw const RefusAnalyse(
            MotifRefusAnalyse.protegeParDrm,
            'Ce PDF est chiffré (protégé) : il ne peut pas être importé.',
          );
        }
        return (titre: null, auteur: null, langue: null);
      case FormatFichierLocal.cbz:
        final aUneImage = await _lireZip(
          fichier.path,
          (archive) async => archive.any(
            (e) => e.isFile && AnalyseFichiersImportes.estPageCbz(e.name),
          ),
        );
        if (!aUneImage) {
          throw const RefusAnalyse(
            MotifRefusAnalyse.illisible,
            'Ce fichier CBZ ne contient aucune image.',
          );
        }
        return (titre: null, auteur: null, langue: null);
      case FormatFichierLocal.epub:
        final contenu = await _lireZip(
          fichier.path,
          (archive) => AnalyseFichiersImportes.analyserEpub((nom) async {
            final entree = archive.find(nom);
            if (entree == null || !entree.isFile) return null;
            return entree.readBytes();
          }),
        );
        return (
          titre: contenu.titre,
          auteur: contenu.auteur,
          langue: contenu.langue,
        );
    }
  }

  /// Ouvre le zip [chemin] (fichier choisi par le client, avant copie) sans
  /// le charger en mémoire, et le passe à [lecture]. Une archive abîmée
  /// devient un refus « illisible ».
  static Future<T> _lireZip<T>(
    String chemin,
    Future<T> Function(Archive archive) lecture,
  ) async {
    final flux = InputFileStream(chemin);
    try {
      return await lecture(ZipDecoder().decodeStream(flux));
    } on RefusAnalyse {
      rethrow;
    } on FileSystemException {
      rethrow;
    } on Exception {
      // ArchiveException, FormatException… : zip abîmé ou incomplet.
      throw const RefusAnalyse(
        MotifRefusAnalyse.illisible,
        'Cette archive est abîmée ou incomplète.',
      );
    } on RangeError {
      // Répertoire central tronqué : lecture hors des limites du fichier.
      throw const RefusAnalyse(
        MotifRefusAnalyse.illisible,
        'Cette archive est abîmée ou incomplète.',
      );
    } finally {
      await flux.close();
    }
  }

  /// Lit au plus [longueur] octets de [fichier] à partir de [debut].
  static Future<Uint8List> _lirePlage(
    File fichier,
    int debut,
    int longueur,
  ) async {
    final acces = await fichier.open();
    try {
      await acces.setPosition(debut);
      return await acces.read(longueur);
    } finally {
      await acces.close();
    }
  }

  // ----------------------------------------------------------------- Lecture

  /// Format du fichier importé porté par [chapitre], ou `null` si ce n'est
  /// pas un fichier importé (chapitre téléchargé d'un site).
  static FormatFichierLocal? formatDuChapitre(Chapitre chapitre) {
    final nomArchive = chapitre.nomArchive;
    return nomArchive == null
        ? null
        : StockageTelechargements.formatFichierImporte(nomArchive);
  }

  /// Chemin relatif du fichier importé de [chapitre], vérifié au [format]
  /// attendu ; lève une [ErreurService] sinon.
  static String _exigerFichier(Chapitre chapitre, FormatFichierLocal format) {
    final nomArchive = chapitre.nomArchive;
    if (nomArchive == null || formatDuChapitre(chapitre) != format) {
      throw ErreurService(
        "« ${chapitre.nom} » n'est pas un fichier "
        "${format.extension.toUpperCase()} importé.",
      );
    }
    return nomArchive;
  }

  /// Structure de l'EPUB importé [chapitre] : métadonnées et sections du
  /// spine dans l'ordre, avec leur titre de table des matières si connu.
  ///
  /// Lève une [ErreurService] si le chapitre n'est pas un EPUB importé ou si
  /// le livre est illisible, une `ErreurStockage` si le fichier est absent.
  Future<ContenuEpub> contenuEpub(Chapitre chapitre) async {
    final nomArchive = _exigerFichier(chapitre, FormatFichierLocal.epub);
    final dernier = _dernierEpub;
    if (dernier != null && dernier.nomArchive == nomArchive) {
      return dernier.contenu;
    }
    try {
      final contenu = await AnalyseFichiersImportes.analyserEpub(
        (nom) => _bibliotheque.lireEntreeFichierImporte(nomArchive, nom),
      );
      _dernierEpub = (nomArchive: nomArchive, contenu: contenu);
      return contenu;
    } on RefusAnalyse catch (refus) {
      throw ErreurService(refus.message, cause: refus);
    }
  }

  /// HTML de la section [index] (spine, à partir de 0) de l'EPUB importé
  /// [chapitre], prêt pour le lecteur : scripts retirés et images du livre
  /// intégrées en adresses `data:` (aucun accès au fichier depuis la vue).
  ///
  /// Lève une [ErreurService] si l'index est hors limites ou si la section
  /// est absente du fichier, une `ErreurStockage` si le fichier est absent.
  Future<String> sectionEpub(Chapitre chapitre, int index) async {
    final contenu = await contenuEpub(chapitre);
    if (index < 0 || index >= contenu.sections.length) {
      throw ErreurService(
        "La section ${index + 1} n'existe pas "
        "(${contenu.sections.length} sections).",
      );
    }
    final nomArchive = chapitre.nomArchive!;
    final section = contenu.sections[index];
    final octets = await _bibliotheque.lireEntreeFichierImporte(
      nomArchive,
      section.chemin,
    );
    if (octets == null) {
      throw ErreurService(
        'La section ${index + 1} est absente du livre (fichier abîmé).',
      );
    }
    final html = _decoderUtf8(octets);
    final adresses = <String, String>{};
    for (final image in AnalyseFichiersImportes.imagesDeSection(
      html,
      section.chemin,
      maximum: nombreMaxImagesSectionEpub,
    )) {
      final donnees = await _bibliotheque.lireEntreeFichierImporte(
        nomArchive,
        image,
      );
      if (donnees == null) continue;
      adresses[image] = AnalyseFichiersImportes.adresseData(
        image,
        donnees,
        typeMedia: contenu.typesMedia[image],
      );
    }
    return AnalyseFichiersImportes.preparerSection(
      html,
      section.chemin,
      adresses,
    );
  }

  static String _decoderUtf8(Uint8List octets) {
    // BOM UTF-8 éventuel retiré : il s'afficherait sinon en tête de page.
    final debut =
        octets.length >= 3 &&
            octets[0] == 0xef &&
            octets[1] == 0xbb &&
            octets[2] == 0xbf
        ? 3
        : 0;
    return const Utf8Decoder(allowMalformed: true).convert(octets, debut);
  }

  /// Chemin complet du PDF importé [chapitre], à ouvrir par le lecteur PDF.
  ///
  /// Lève une [ErreurService] si le chapitre n'est pas un PDF importé ou si
  /// le fichier est absent.
  Future<String> cheminPdf(Chapitre chapitre) async {
    final nomArchive = _exigerFichier(chapitre, FormatFichierLocal.pdf);
    final chemin = _bibliotheque.cheminFichierImporte(nomArchive);
    if (!await File(chemin).exists()) {
      throw const ErreurService(
        "Le fichier PDF est introuvable (dossier des chapitres déplacé ou "
        "inaccessible ?).",
      );
    }
    return chemin;
  }

  /// Nombre de pages (images) du CBZ importé [chapitre].
  ///
  /// Lève une [ErreurService] si ce n'est pas un CBZ importé, une
  /// `ErreurStockage` si le fichier est absent ou abîmé.
  Future<int> nombrePagesCbz(Chapitre chapitre) => _bibliotheque
      .compterPagesCbz(_exigerFichier(chapitre, FormatFichierLocal.cbz));

  /// Image de la page [index] (à partir de 0) du CBZ importé [chapitre].
  ///
  /// Mêmes erreurs que [nombrePagesCbz], plus un index hors limites.
  Future<Uint8List> pageCbz(Chapitre chapitre, int index) => _bibliotheque
      .lirePageCbz(_exigerFichier(chapitre, FormatFichierLocal.cbz), index);

  /// Position de lecture enregistrée du chapitre [idChapitre], ou `null`.
  Future<PositionLecture?> chargerPosition(int idChapitre) =>
      _positions.chargerPosition(idChapitre);

  /// Enregistre [position] (remplace la précédente du même chapitre).
  /// Lève une [ErreurBaseDeDonnees] si l'écriture échoue.
  Future<void> enregistrerPosition(PositionLecture position) =>
      _positions.enregistrerPosition(position);

  /// Enregistre la page [page] d'un chapitre paginé (CBZ, PDF), datée
  /// maintenant.
  Future<void> enregistrerPage(int idChapitre, int page, {int? nombrePages}) {
    return enregistrerPosition(
      PositionLecture.page(
        idChapitre: idChapitre,
        page: page,
        nombrePages: nombrePages,
        dateMaj: _horloge().toUtc(),
      ),
    );
  }

  /// Enregistre la [section] et la [fraction] de défilement d'un EPUB,
  /// datées maintenant ([fraction] ramenée entre 0 et 1).
  Future<void> enregistrerSection(
    int idChapitre,
    int section, {
    double fraction = 0,
  }) {
    final bornee = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return enregistrerPosition(
      PositionLecture.epub(
        idChapitre: idChapitre,
        section: section,
        fraction: bornee,
        dateMaj: _horloge().toUtc(),
      ),
    );
  }

  // ------------------------------------------------------------- Suppression

  /// Supprime le titre importé [titre] de la bibliothèque, puis son fichier
  /// copié (demande explicite du client : seul cas où le fichier est
  /// effacé). Renvoie `true` si le fichier a bien été effacé.
  ///
  /// La base d'abord : si l'effacement du fichier échoue, la bibliothèque
  /// reste cohérente (le titre a disparu) et l'erreur est journalisée.
  /// LIMITE : le fichier reste alors sur le disque, sans titre.
  ///
  /// Lève une [ErreurService] si [titre] n'est pas enregistré ou n'est pas
  /// un fichier importé (un titre d'un site se supprime par
  /// `ServiceTelechargement.supprimerTitre`).
  Future<bool> supprimerImport(Titre titre) async {
    final idTitre = titre.id;
    if (idTitre == null) {
      throw ErreurService("« ${titre.nom} » n'est pas enregistré.");
    }
    final fichiers = <String>[
      for (final chapitre in await _chapitres.chargerChapitres(idTitre))
        if (formatDuChapitre(chapitre) != null) chapitre.nomArchive!,
    ];
    if (fichiers.isEmpty) {
      throw ErreurService("« ${titre.nom} » n'est pas un fichier importé.");
    }
    await _titres.supprimerTitre(idTitre);
    if (_dernierEpub != null && fichiers.contains(_dernierEpub!.nomArchive)) {
      _dernierEpub = null;
    }
    var efface = true;
    for (final nomArchive in fichiers) {
      try {
        await _bibliotheque.supprimerFichierImporte(nomArchive);
      } catch (erreur) {
        efface = false;
        Journal.actuel.avertissement(
          CategorieJournal.stockage,
          'Fichier du titre importé n°$idTitre non effacé',
          erreur: erreur is ErreurStockage
              ? erreur.message
              : erreur.runtimeType,
        );
      }
    }
    Journal.actuel.info(
      CategorieJournal.bibliotheque,
      'Titre importé n°$idTitre supprimé',
    );
    return efface;
  }
}
