/// Fichiers hors-ligne : une archive `.zip` par chapitre (PLAYBOOK.md
/// section 5).
///
/// ```
/// <dossier racine>/<type>/<nom du titre>/ch<numero>.<langue>.zip
///     img1.jpg, img2.jpg, img3.webp, …   (chapitre en images)
///     contenu.html                        (chapitre texte)
/// ```
///
/// API du paquet `archive` 4.7.1 utilisées (vérifiées dans le code et la
/// documentation du paquet installé, `doc/creating-archives.md` et
/// `doc/streaming.md`) :
/// - écriture incrémentale : `ZipEncoder.startEncode(output)`,
///   `ZipEncoder.add(entry)`, `ZipEncoder.endEncode()` sur un
///   `OutputFileStream(chemin, bufferSize: …)` ;
/// - entrée stockée sans recompression : `ArchiveFile.noCompress(nom, taille,
///   octets)` (fixe `compression = CompressionType.none`) ;
/// - lecture sans extraction : `ZipDecoder().decodeStream(InputFileStream(…))`
///   lit seulement le répertoire central ; `ArchiveFile.readBytes()` ne lit
///   que l'entrée demandée.
library;

import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as chemins;
import 'package:path_provider/path_provider.dart';

import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/titre.dart';
import 'constantes_donnees.dart';
import 'erreur_stockage.dart';

/// Calcule le dossier racine par défaut des téléchargements :
/// `<dossier documents de l'app>/bibliotheque_perso/`.
///
/// `getApplicationDocumentsDirectory()` renvoie le dossier « Documents » de
/// l'utilisateur sur Windows et Linux, et un dossier privé de l'application
/// sur Android. Le dossier n'est pas créé ici : il l'est à la première
/// écriture. `WidgetsFlutterBinding.ensureInitialized()` doit avoir été appelé
/// (exigence de `path_provider`).
Future<String> cheminParDefautDossierTelechargements() async {
  final documents = await getApplicationDocumentsDirectory();
  return chemins.join(documents.path, nomDossierRacineTelechargements);
}

/// Seule classe qui construit les chemins des fichiers hors-ligne, crée les
/// archives des chapitres et les lit.
///
/// Elle ne fait aucun appel réseau : elle écrit des octets déjà récupérés par
/// le service de téléchargement.
///
/// Toutes les méthodes qui désignent un chapitre prennent le même trio
/// `(titre, chapitre, {nomSource})` que [cheminChapitre] : c'est au service
/// de décider si le suffixe de source est nécessaire (collision de noms entre
/// deux sources), et il doit passer la même valeur à chaque appel.
///
/// LIMITE : la lecture et l'écriture des archives sont **synchrones** dans le
/// paquet `archive` (seule la fermeture et le renommage sont asynchrones).
/// Une page fait en général moins de quelques Mio, ce qui reste rapide ; si
/// l'interface saccade, l'appelant peut exécuter la lecture dans
/// `Isolate.run`.
class StockageTelechargements {
  /// Crée le stockage sur le [dossierRacine] donné.
  ///
  /// Les tests passent un dossier temporaire ; l'application passe le dossier
  /// réglé dans les paramètres ou [cheminParDefautDossierTelechargements].
  StockageTelechargements(this.dossierRacine);

  /// Crée le stockage sur le dossier racine par défaut
  /// ([cheminParDefautDossierTelechargements]).
  static Future<StockageTelechargements> parDefaut() async {
    return StockageTelechargements(
      await cheminParDefautDossierTelechargements(),
    );
  }

  /// Dossier racine de tous les fichiers hors-ligne.
  final String dossierRacine;

  /// Chemins des `.zip.part` en cours d'écriture par cette instance.
  ///
  /// Sert à refuser deux écritures simultanées du même chapitre et à ne pas
  /// supprimer une archive en cours dans [nettoyerFichiersPartiels].
  final Set<String> _ecrituresOuvertes = <String>{};

  // Caractères interdits par le playbook (interdits sous Windows) et
  // caractères de contrôle U+0000 à U+001F (également refusés par Windows).
  static final RegExp _caracteresInterdits = RegExp(
    r'[<>:"/\\|?*\u0000-\u001F]',
  );

  // Points et espaces en fin de nom : Windows les retire silencieusement, ce
  // qui ferait diverger le nom sur le disque du nom calculé.
  static final RegExp _finInterdite = RegExp(r'[. ]+$');

  // Noms de périphériques réservés par Windows, même suivis d'une extension.
  // On les traite sur toutes les plateformes pour que les chemins soient
  // identiques partout (une bibliothèque copiée d'un Linux vers un Windows
  // reste lisible).
  static final RegExp _nomsReserves = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
    caseSensitive: false,
  );

  // Une langue ne garde que les lettres, chiffres et tirets (`pt-br`).
  static final RegExp _caracteresLangueInterdits = RegExp(r'[^a-z0-9-]');

  // Extension d'une image : lettres minuscules et chiffres seulement.
  static final RegExp _extensionValide = RegExp(
    '^[a-z0-9]{1,$longueurMaxExtensionPage}\$',
  );

  // Nom d'une page dans une archive : `img<n>.<extension>`, n ≥ 1.
  static final RegExp _nomPage = RegExp(
    '^$prefixePageArchive([1-9][0-9]*)\\.([a-z0-9]+)\$',
  );

  // ---------------------------------------------------------------------
  // Chemins
  // ---------------------------------------------------------------------

  /// Nettoie un nom pour en faire un nom de dossier valide sur Windows, Linux
  /// et Android.
  ///
  /// Règle du playbook : retrait des caractères `< > : " / \ | ? *` et des
  /// points ou espaces en fin de nom. En complément (nécessaire sous
  /// Windows) : retrait des caractères de contrôle, des espaces en début de
  /// nom, troncature à [longueurMaxNomDossierTitre] unités UTF-16, ajout d'un
  /// `_` après un nom réservé (`CON`, `NUL`…), et [nomDossierDeRepli] si le
  /// résultat est vide. Le retrait des points finaux empêche aussi tout `..`
  /// (sortie du dossier racine).
  static String nettoyerNom(String nom) {
    var resultat = nom.replaceAll(_caracteresInterdits, '').trimLeft();
    resultat = resultat.replaceFirst(_finInterdite, '');
    if (resultat.length > longueurMaxNomDossierTitre) {
      resultat = _tronquer(resultat, longueurMaxNomDossierTitre);
      resultat = resultat.replaceFirst(_finInterdite, '');
    }
    if (resultat.isEmpty) {
      return nomDossierDeRepli;
    }
    if (_nomsReserves.hasMatch(resultat)) {
      return '${resultat}_';
    }
    return resultat;
  }

  /// Tronque [texte] à [longueurMax] unités UTF-16 sans couper un caractère
  /// hors du plan de base (emoji, idéogramme rare) en deux.
  static String _tronquer(String texte, int longueurMax) {
    final buffer = StringBuffer();
    var longueur = 0;
    for (final rune in texte.runes) {
      final caractere = String.fromCharCode(rune);
      if (longueur + caractere.length > longueurMax) {
        break;
      }
      buffer.write(caractere);
      longueur += caractere.length;
    }
    return buffer.toString();
  }

  /// Nom du dossier d'un titre : nom nettoyé, suivi de ` (<nom de la
  /// source>)` si [nomSource] est donné et non vide.
  ///
  /// Le suffixe sert quand deux titres de sources différentes donnent le même
  /// nom nettoyé ; c'est le service qui détecte la collision et décide de le
  /// demander. Le nom de la source est nettoyé séparément, pour que la
  /// troncature d'un long nom de titre ne fasse pas disparaître le suffixe.
  static String nomDossierTitre(String nomTitre, {String? nomSource}) {
    final base = nettoyerNom(nomTitre);
    final source = nomSource?.trim() ?? '';
    if (source.isEmpty) {
      return base;
    }
    return '$base (${nettoyerNom(source)})';
  }

  /// Formate un numéro de chapitre sans zéros inutiles : `1.0` → `1`,
  /// `10.5` → `10.5`, `10.50` → `10.5`.
  ///
  /// Lève une [ArgumentError] si le numéro n'est pas fini (NaN, infini).
  static String formaterNumero(double numero) {
    if (numero.isNaN || numero.isInfinite) {
      throw ArgumentError.value(numero, 'numero', 'doit être un nombre fini');
    }
    // Au-delà de 1e15, toInt() reste exact mais un double n'a plus de
    // décimales significatives : toString() suffit (cas absurde en pratique).
    if (numero == numero.truncateToDouble() && numero.abs() < 1e15) {
      return numero.toInt().toString();
    }
    return numero.toString();
  }

  /// Normalise un code de langue pour un nom de fichier : minuscules, sans
  /// espaces, uniquement lettres, chiffres et tirets (`pt-BR` → `pt-br`).
  static String normaliserLangue(String langue) {
    return langue.trim().toLowerCase().replaceAll(
      _caracteresLangueInterdits,
      '',
    );
  }

  /// Nom du fichier d'un chapitre : `ch<numero>.<langue>.zip`.
  ///
  /// Repli quand la langue est vide (ou vide après normalisation) :
  /// `ch<numero>.zip`. Ce nom ne peut pas entrer en collision avec un nom
  /// avec langue, et reste lisible. Pour appliquer la règle du playbook « par
  /// défaut, la langue de la source », le service passe un chapitre dont la
  /// langue a été complétée (`chapitre.copierAvec(langue: …)`).
  static String nomFichierChapitre(Chapitre chapitre) {
    final numero = formaterNumero(chapitre.numero);
    final langue = normaliserLangue(chapitre.langue);
    if (langue.isEmpty) {
      return '$prefixeFichierChapitre$numero$extensionArchiveChapitre';
    }
    return '$prefixeFichierChapitre$numero.$langue$extensionArchiveChapitre';
  }

  /// Dossier d'un titre : `<racine>/<type>/<nom du titre>`.
  String cheminDossierTitre(Titre titre, {String? nomSource}) {
    return chemins.join(
      dossierRacine,
      titre.typeTitre.name,
      nomDossierTitre(titre.nom, nomSource: nomSource),
    );
  }

  /// Chemin complet de l'archive d'un chapitre :
  /// `<racine>/<type>/<nom du titre>/ch<numero>.<langue>.zip`.
  ///
  /// Voir [nomDossierTitre] pour [nomSource] et [nomFichierChapitre] pour le
  /// nom du fichier.
  String cheminChapitre(Titre titre, Chapitre chapitre, {String? nomSource}) {
    return chemins.join(
      cheminDossierTitre(titre, nomSource: nomSource),
      nomFichierChapitre(chapitre),
    );
  }

  // ---------------------------------------------------------------------
  // Écriture
  // ---------------------------------------------------------------------

  /// Normalise l'extension d'une page (`.JPG` → `jpg`).
  ///
  /// Lève une [ArgumentError] si l'extension ne contient pas uniquement de 1
  /// à [longueurMaxExtensionPage] lettres ou chiffres.
  static String normaliserExtension(String extension) {
    var resultat = extension.trim().toLowerCase();
    if (resultat.startsWith('.')) {
      resultat = resultat.substring(1);
    }
    if (!_extensionValide.hasMatch(resultat)) {
      throw ArgumentError.value(
        extension,
        'extension',
        'doit contenir de 1 à $longueurMaxExtensionPage lettres ou chiffres',
      );
    }
    return resultat;
  }

  /// Extrait l'extension d'origine d'une URL d'image
  /// (`https://…/data/abc/x1-0f3.webp?t=1` → `webp`), ou `null` si elle est
  /// absente ou invalide.
  ///
  /// Outil pour le service, qui doit garder l'extension d'origine des images.
  static String? extensionDepuisUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return null;
    }
    final extension = chemins.url.extension(uri.path);
    if (extension.isEmpty) {
      return null;
    }
    try {
      return normaliserExtension(extension);
    } on ArgumentError {
      return null;
    }
  }

  /// Ouvre l'écriture de l'archive d'un chapitre dans un fichier `.zip.part`.
  ///
  /// Les pages sont ensuite ajoutées une par une
  /// ([EcritureChapitre.ajouterPage]) ou le texte en une fois
  /// ([EcritureChapitre.ajouterTexte]), puis l'archive est finalisée
  /// ([EcritureChapitre.finaliser]) ou abandonnée
  /// ([EcritureChapitre.abandonner]).
  ///
  /// Un `.zip.part` laissé par une interruption précédente est écrasé. Une
  /// archive `.zip` déjà complète n'est remplacée qu'à la finalisation.
  ///
  /// Lève une [ErreurStockage] si ce chapitre est déjà en cours d'écriture
  /// ou si le fichier ne peut pas être créé.
  Future<EcritureChapitre> ouvrirEcriture(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    final cheminFinal = cheminChapitre(titre, chapitre, nomSource: nomSource);
    final cheminPartiel = '$cheminFinal$suffixeArchivePartielle';
    final cle = chemins.normalize(cheminPartiel);
    if (_ecrituresOuvertes.contains(cle)) {
      throw ErreurStockage(
        'Ce chapitre est déjà en cours d\'écriture.',
        chemin: cheminPartiel,
      );
    }
    try {
      await Directory(chemins.dirname(cheminFinal)).create(recursive: true);
      // FileAccess.write ouvre le fichier en FileMode.write : un ancien
      // .zip.part est tronqué.
      final sortie = OutputFileStream(
        cheminPartiel,
        bufferSize: tailleTamponEcritureArchive,
      );
      final encodeur = ZipEncoder()..startEncode(sortie);
      _ecrituresOuvertes.add(cle);
      return EcritureChapitre._(
        cheminFinal: cheminFinal,
        cheminPartiel: cheminPartiel,
        sortie: sortie,
        encodeur: encodeur,
        surFermeture: () => _ecrituresOuvertes.remove(cle),
      );
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible de créer l\'archive du chapitre.',
        chemin: cheminPartiel,
        cause: erreur,
      );
    }
  }

  // ---------------------------------------------------------------------
  // Lecture
  // ---------------------------------------------------------------------

  /// `true` si l'archive complète (`.zip`) du chapitre existe.
  ///
  /// Un `.zip.part` (écriture interrompue ou en cours) ne compte jamais.
  Future<bool> estTelecharge(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) {
    return File(cheminChapitre(titre, chapitre, nomSource: nomSource)).exists();
  }

  /// Nombre de pages (`img<n>.<ext>`) de l'archive du chapitre.
  ///
  /// Lève une [ErreurStockage] si l'archive est absente ou illisible.
  Future<int> compterPages(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    final chemin = cheminChapitre(titre, chapitre, nomSource: nomSource);
    return _lireArchive(chemin, (archive) => _pagesTriees(archive).length);
  }

  /// Octets de la page d'indice [index] (**à partir de 0**, dans l'ordre de
  /// lecture : `img1` est l'indice 0), lus directement dans l'archive sans
  /// extraction sur le disque.
  ///
  /// Lève une [ErreurStockage] si l'archive est absente ou abîmée, ou si
  /// l'indice est hors limites.
  Future<Uint8List> lirePage(
    Titre titre,
    Chapitre chapitre,
    int index, {
    String? nomSource,
  }) async {
    final chemin = cheminChapitre(titre, chapitre, nomSource: nomSource);
    return _lireArchive(chemin, (archive) {
      final pages = _pagesTriees(archive);
      if (index < 0 || index >= pages.length) {
        throw ErreurStockage(
          'La page ${index + 1} n\'existe pas (le chapitre en compte '
          '${pages.length}).',
          chemin: chemin,
        );
      }
      return _lireEntree(pages[index], chemin);
    });
  }

  /// Texte (`contenu.html`) d'un chapitre de roman, ou `null` si l'archive
  /// ne contient que des images.
  ///
  /// Lève une [ErreurStockage] si l'archive est absente ou abîmée.
  Future<String?> lireTexte(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    final chemin = cheminChapitre(titre, chapitre, nomSource: nomSource);
    return _lireArchive(chemin, (archive) {
      final entree = archive.find(nomEntreeContenuTexte);
      if (entree == null) {
        return null;
      }
      return utf8.decode(_lireEntree(entree, chemin), allowMalformed: true);
    });
  }

  /// Pages de l'archive triées par numéro (`img2` avant `img10`).
  ///
  /// L'ordre des entrées dans le zip n'est pas utilisé : on se fie au numéro,
  /// seul garant de l'ordre de lecture.
  static List<ArchiveFile> _pagesTriees(Archive archive) {
    final pages = <(int, ArchiveFile)>[];
    for (final entree in archive) {
      if (!entree.isFile) {
        continue;
      }
      final correspondance = _nomPage.firstMatch(entree.name);
      if (correspondance != null) {
        pages.add((int.parse(correspondance.group(1)!), entree));
      }
    }
    pages.sort((a, b) => a.$1.compareTo(b.$1));
    return pages.map((page) => page.$2).toList();
  }

  /// Lit le contenu d'une entrée et en renvoie une copie indépendante.
  static Uint8List _lireEntree(ArchiveFile entree, String chemin) {
    final octets = entree.readBytes();
    if (octets == null) {
      throw ErreurStockage(
        'L\'entrée « ${entree.name} » de l\'archive est vide.',
        chemin: chemin,
      );
    }
    // Copie : pour une entrée stockée, les octets peuvent être une vue sur le
    // tampon de lecture du fichier, qui est fermé juste après.
    return Uint8List.fromList(octets);
  }

  /// Ouvre l'archive [chemin], applique [lecture] puis ferme le fichier.
  ///
  /// `decodeStream` sur un `InputFileStream` ne lit que le répertoire central
  /// (fin du fichier) ; le contenu d'une entrée n'est lu qu'à la demande.
  /// `verify: true` vérifie le CRC des entrées lues et lève une erreur si
  /// l'archive est tronquée ou abîmée (au lieu de renvoyer des données
  /// partielles).
  ///
  /// LIMITE : l'archive est rouverte à chaque appel (pas de cache). Le
  /// répertoire central ne fait que quelques Kio ; si un jour la lecture
  /// devient trop lente, un lecteur pourra garder l'archive ouverte.
  Future<T> _lireArchive<T>(
    String chemin,
    T Function(Archive archive) lecture,
  ) async {
    if (!await File(chemin).exists()) {
      throw ErreurStockage(
        'Le chapitre n\'est pas téléchargé.',
        chemin: chemin,
      );
    }
    InputFileStream? entree;
    try {
      entree = InputFileStream(chemin);
      final archive = ZipDecoder().decodeStream(entree, verify: true);
      return lecture(archive);
    } on ErreurStockage {
      rethrow;
    } on ArchiveException catch (erreur) {
      throw ErreurStockage(
        'L\'archive du chapitre est abîmée ou incomplète.',
        chemin: chemin,
        cause: erreur,
      );
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible de lire l\'archive du chapitre.',
        chemin: chemin,
        cause: erreur,
      );
    } finally {
      await entree?.close();
    }
  }

  // ---------------------------------------------------------------------
  // Suppression et nettoyage
  // ---------------------------------------------------------------------

  /// Supprime l'archive du chapitre (et un éventuel `.zip.part` qui n'est pas
  /// en cours d'écriture), puis le dossier du titre s'il est devenu vide.
  ///
  /// Renvoie `true` si une archive complète a été supprimée.
  Future<bool> supprimerChapitre(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    final chemin = cheminChapitre(titre, chapitre, nomSource: nomSource);
    final cheminPartiel = '$chemin$suffixeArchivePartielle';
    try {
      final archive = File(chemin);
      final existait = await archive.exists();
      if (existait) {
        await archive.delete();
      }
      final partielle = File(cheminPartiel);
      if (!_ecrituresOuvertes.contains(chemins.normalize(cheminPartiel)) &&
          await partielle.exists()) {
        await partielle.delete();
      }
      await _supprimerDossierSiVide(Directory(chemins.dirname(chemin)));
      return existait;
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible de supprimer l\'archive du chapitre.',
        chemin: chemin,
        cause: erreur,
      );
    }
  }

  /// Supprime [dossier] s'il existe et est vide (le dossier d'un titre dont
  /// on a supprimé le dernier chapitre).
  Future<void> _supprimerDossierSiVide(Directory dossier) async {
    if (!await dossier.exists()) {
      return;
    }
    if (await dossier.list().isEmpty) {
      await dossier.delete();
    }
  }

  /// Supprime tous les `.zip.part` laissés par des écritures interrompues
  /// (application fermée ou tuée pendant un téléchargement) et renvoie leur
  /// nombre.
  ///
  /// À appeler au démarrage, avant de relancer la file. Les écritures en
  /// cours dans cette instance sont épargnées.
  Future<int> nettoyerFichiersPartiels() async {
    final racine = Directory(dossierRacine);
    if (!await racine.exists()) {
      return 0;
    }
    var nombre = 0;
    final suffixe = '$extensionArchiveChapitre$suffixeArchivePartielle';
    try {
      await for (final entite in racine.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entite is File &&
            entite.path.endsWith(suffixe) &&
            !_ecrituresOuvertes.contains(chemins.normalize(entite.path))) {
          await entite.delete();
          nombre++;
        }
      }
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible de nettoyer les téléchargements interrompus.',
        chemin: dossierRacine,
        cause: erreur,
      );
    }
    return nombre;
  }
}

/// Écriture en cours de l'archive d'un chapitre, ouverte par
/// [StockageTelechargements.ouvrirEcriture].
///
/// Chaque page est écrite dans le `.zip.part` dès son ajout, puis libérée :
/// seule la page courante est en mémoire (plus un tampon de
/// [tailleTamponEcritureArchive]). Le `ZipEncoder` ne garde que les en-têtes
/// des entrées, nécessaires au répertoire central écrit à la fin.
///
/// LIMITE : une archive `.zip.part` interrompue ne peut pas être complétée
/// (son répertoire central n'est écrit qu'à la finalisation, et `archive`
/// n'offre pas d'ajout à un zip existant) : après une interruption, le
/// chapitre est réécrit depuis la première page.
class EcritureChapitre {
  EcritureChapitre._({
    required this.cheminFinal,
    required this.cheminPartiel,
    required this._sortie,
    required this._encodeur,
    required this._surFermeture,
  });

  /// Chemin de l'archive complète (`….zip`), créée par [finaliser].
  final String cheminFinal;

  /// Chemin du fichier en cours d'écriture (`….zip.part`).
  final String cheminPartiel;

  final OutputFileStream _sortie;
  final ZipEncoder _encodeur;
  final void Function() _surFermeture;

  int _nombrePages = 0;
  bool _aDuTexte = false;
  bool _estFermee = false;

  /// Nombre de pages déjà écrites.
  int get nombrePages => _nombrePages;

  /// `true` après [finaliser] ou [abandonner].
  bool get estFermee => _estFermee;

  /// Ajoute la page suivante (`img<n>.<extension>`), stockée sans
  /// recompression, et l'écrit immédiatement sur le disque.
  ///
  /// [extension] est l'extension d'origine de l'image (`jpg`, `.webp`…), voir
  /// [StockageTelechargements.extensionDepuisUrl].
  ///
  /// Lève une [ArgumentError] si l'extension est invalide, une
  /// [ErreurStockage] si l'écriture est fermée, si [octets] est vide, si le
  /// chapitre contient déjà du texte ou si le disque refuse l'écriture. En cas
  /// d'erreur, l'appelant doit appeler [abandonner].
  Future<void> ajouterPage(
    List<int> octets, {
    required String extension,
  }) async {
    _verifierOuverte();
    final extensionNormalisee = StockageTelechargements.normaliserExtension(
      extension,
    );
    if (_aDuTexte) {
      throw ErreurStockage(
        'Un chapitre ne peut pas contenir à la fois du texte et des images.',
        chemin: cheminPartiel,
      );
    }
    if (octets.isEmpty) {
      throw ErreurStockage(
        'La page ${_nombrePages + 1} est vide.',
        chemin: cheminPartiel,
      );
    }
    final numero = _nombrePages + 1;
    _ajouterEntree('$prefixePageArchive$numero.$extensionNormalisee', octets);
    _nombrePages = numero;
  }

  /// Ajoute le texte d'un chapitre de roman (`contenu.html`, en UTF-8).
  ///
  /// Lève une [ErreurStockage] si l'écriture est fermée, si le texte a déjà
  /// été ajouté ou si le chapitre contient déjà des images.
  Future<void> ajouterTexte(String html) async {
    _verifierOuverte();
    if (_aDuTexte || _nombrePages > 0) {
      throw ErreurStockage(
        'Le texte ne peut être ajouté qu\'une fois, dans un chapitre sans '
        'images.',
        chemin: cheminPartiel,
      );
    }
    _ajouterEntree(nomEntreeContenuTexte, utf8.encode(html));
    _aDuTexte = true;
  }

  /// Écrit une entrée stockée (sans compression) et la vide sur le disque.
  void _ajouterEntree(String nom, List<int> octets) {
    try {
      // noCompress : les images sont déjà compressées, les recompresser
      // ralentirait l'écriture et la lecture sans gain de place.
      _encodeur.add(ArchiveFile.noCompress(nom, octets.length, octets));
      // Vidage immédiat : le .part reflète la progression et le tampon ne
      // retient pas la page.
      _sortie.flush();
    } on ArchiveException catch (erreur) {
      throw ErreurStockage(
        'Impossible d\'ajouter « $nom » à l\'archive.',
        chemin: cheminPartiel,
        cause: erreur,
      );
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible d\'écrire « $nom » sur le disque.',
        chemin: cheminPartiel,
        cause: erreur,
      );
    }
  }

  /// Termine l'archive (répertoire central), ferme le fichier et renomme le
  /// `.zip.part` en `.zip` ; renvoie le chemin final.
  ///
  /// Une archive `.zip` existante pour ce chapitre est remplacée. Une archive
  /// sans page ni texte n'est jamais finalisée : elle est abandonnée et une
  /// [ErreurStockage] est levée. En cas d'erreur, le `.zip.part` est supprimé.
  Future<String> finaliser() async {
    _verifierOuverte();
    if (_nombrePages == 0 && !_aDuTexte) {
      await abandonner();
      throw ErreurStockage(
        'Impossible de finaliser un chapitre vide.',
        chemin: cheminFinal,
      );
    }
    try {
      _encodeur.endEncode();
      await _sortie.close();
      // Renommage dans le même dossier : opération atomique sur le même
      // disque. dart:io remplace la cible si elle existe déjà.
      await File(cheminPartiel).rename(cheminFinal);
    } on Exception catch (erreur) {
      await _supprimerPartiel();
      _fermer();
      throw ErreurStockage(
        'Impossible de finaliser l\'archive du chapitre.',
        chemin: cheminFinal,
        cause: erreur,
      );
    }
    _fermer();
    return cheminFinal;
  }

  /// Abandonne l'écriture : ferme et supprime le `.zip.part`.
  ///
  /// Sans effet si l'écriture est déjà fermée ; ne lève pas d'erreur.
  Future<void> abandonner() async {
    if (_estFermee) {
      return;
    }
    await _supprimerPartiel();
    _fermer();
  }

  /// Ferme le fichier (si besoin) et supprime le `.zip.part`, en ignorant les
  /// erreurs : on est déjà dans un chemin d'échec.
  Future<void> _supprimerPartiel() async {
    try {
      await _sortie.close();
    } on Exception {
      // Fichier déjà fermé ou disque indisponible : la suppression ci-dessous
      // reste tentée.
    }
    try {
      final partiel = File(cheminPartiel);
      if (await partiel.exists()) {
        await partiel.delete();
      }
    } on FileSystemException {
      // Le .part restant sera retiré par nettoyerFichiersPartiels().
    }
  }

  void _fermer() {
    _estFermee = true;
    _surFermeture();
  }

  void _verifierOuverte() {
    if (_estFermee) {
      throw ErreurStockage(
        'L\'écriture de ce chapitre est déjà terminée.',
        chemin: cheminPartiel,
      );
    }
  }
}
