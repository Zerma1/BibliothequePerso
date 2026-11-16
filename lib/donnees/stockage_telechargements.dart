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
/// Chemin enregistré (migration 4) : si `chapitre.nomArchive` est connu, il
/// est **toujours** utilisé (il reste valable si le titre est renommé ou si
/// la langue de la source change) ; le calcul `<type>/<titre>/ch….zip`
/// n'est qu'un repli pour les chapitres téléchargés avant la migration. Les
/// méthodes `…Archive(nomArchive)` travaillent directement à partir de ce
/// chemin, sans titre.
///
/// Noms uniques (décision du client) : à l'écriture d'un nouveau chapitre,
/// le nom reste `ch<numero>.<langue>.zip` ; **seulement** si ce nom est déjà
/// pris (archive existante ou écriture en cours d'un autre chapitre), un
/// numéro est ajouté : `ch1.fr.2.zip`, `ch1.fr.3.zip`… (`ch1_2.zip` sans
/// langue). Deux oneshots (numéro 0) ou deux scans d'un même chapitre ont
/// ainsi chacun leur archive.
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

  /// URL des chapitres en cours d'écriture dans cette instance.
  ///
  /// Un chapitre est reconnu par son URL (unique en base) : deux écritures
  /// du **même** chapitre sont refusées, alors qu'un **autre** chapitre au
  /// nom identique reçoit un nom numéroté.
  final Set<String> _chapitresEnEcriture = <String>{};

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

  /// Nom du fichier d'un chapitre avec un numéro d'homonyme : 1 donne
  /// [nomFichierChapitre] (`ch1.fr.zip`), 2 donne `ch1.fr.2.zip`, 3
  /// `ch1.fr.3.zip`… Sans langue : `ch1.zip`, `ch1_2.zip`… (voir
  /// [separateurNumeroArchiveSansLangue]).
  ///
  /// Lève une [ArgumentError] si [numeroHomonyme] est inférieur à 1.
  static String nomFichierNumerote(Chapitre chapitre, int numeroHomonyme) {
    if (numeroHomonyme < 1) {
      throw ArgumentError.value(
        numeroHomonyme,
        'numeroHomonyme',
        'doit être ≥ 1',
      );
    }
    if (numeroHomonyme == 1) {
      return nomFichierChapitre(chapitre);
    }
    final numero = formaterNumero(chapitre.numero);
    final langue = normaliserLangue(chapitre.langue);
    if (langue.isEmpty) {
      return '$prefixeFichierChapitre$numero'
          '$separateurNumeroArchiveSansLangue$numeroHomonyme'
          '$extensionArchiveChapitre';
    }
    return '$prefixeFichierChapitre$numero.$langue.$numeroHomonyme'
        '$extensionArchiveChapitre';
  }

  /// Chemin relatif **calculé** de l'archive d'un chapitre (sans numéro
  /// d'homonyme) : `<type>/<nom du titre>/ch<numero>.<langue>.zip`, avec
  /// [separateurNomArchive].
  ///
  /// Repli pour les chapitres sans `nomArchive` enregistré.
  static String nomArchiveCalcule(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) {
    return <String>[
      titre.typeTitre.name,
      nomDossierTitre(titre.nom, nomSource: nomSource),
      nomFichierChapitre(chapitre),
    ].join(separateurNomArchive);
  }

  /// Chemin relatif effectif de l'archive d'un chapitre : le `nomArchive`
  /// enregistré s'il existe, sinon [nomArchiveCalcule].
  static String nomArchiveDuChapitre(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) {
    return chapitre.nomArchive ??
        nomArchiveCalcule(titre, chapitre, nomSource: nomSource);
  }

  /// `true` si [nomArchive] est un chemin relatif d'archive acceptable :
  /// exactement trois éléments `<type>/<dossier>/<fichier>.zip` séparés par
  /// [separateurNomArchive], aucun élément vide, `.` ou `..`, aucun caractère
  /// interdit (dont `\` et `:`, donc ni lecteur ni chemin absolu), ni point
  /// ou espace final.
  ///
  /// Une valeur lue en base est ainsi vérifiée avant tout accès au disque :
  /// elle ne peut pas sortir du dossier racine.
  static bool estNomArchiveValide(String nomArchive) {
    final elements = nomArchive.split(separateurNomArchive);
    if (elements.length != 3) {
      return false;
    }
    for (final element in elements) {
      if (element.isEmpty ||
          _caracteresInterdits.hasMatch(element) ||
          _finInterdite.hasMatch(element)) {
        return false;
      }
    }
    final fichier = elements.last;
    return fichier.endsWith(extensionArchiveChapitre) &&
        fichier.length > extensionArchiveChapitre.length;
  }

  /// Chemin complet (du système) d'une archive à partir de son chemin
  /// relatif enregistré.
  ///
  /// Lève une [ErreurStockage] si [nomArchive] n'est pas valide
  /// ([estNomArchiveValide]).
  String cheminDepuisNomArchive(String nomArchive) {
    if (!estNomArchiveValide(nomArchive)) {
      throw ErreurStockage(
        "Le chemin enregistré de l'archive est invalide.",
        chemin: nomArchive,
      );
    }
    return chemins.joinAll(<String>[
      dossierRacine,
      ...nomArchive.split(separateurNomArchive),
    ]);
  }

  /// Chemin complet de l'archive d'un chapitre : celui du `nomArchive`
  /// enregistré s'il existe, sinon le chemin calculé
  /// `<racine>/<type>/<nom du titre>/ch<numero>.<langue>.zip`.
  ///
  /// Voir [nomDossierTitre] pour [nomSource] et [nomFichierChapitre] pour le
  /// nom du fichier. Lève une [ErreurStockage] si le `nomArchive` enregistré
  /// est invalide.
  String cheminChapitre(Titre titre, Chapitre chapitre, {String? nomSource}) {
    return cheminDepuisNomArchive(
      nomArchiveDuChapitre(titre, chapitre, nomSource: nomSource),
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
  /// Choix du nom de l'archive :
  /// - le chapitre a un `nomArchive` enregistré (re-téléchargement) : ce nom
  ///   est réutilisé, l'ancienne archive est remplacée à la finalisation ;
  /// - le chapitre est marqué téléchargé sans `nomArchive` (téléchargé avant
  ///   la migration 4) : le nom calculé est réutilisé de la même façon ;
  /// - sinon : premier nom libre parmi `ch1.fr.zip`, `ch1.fr.2.zip`… (voir
  ///   [nomFichierNumerote]). Un nom est libre s'il n'existe ni archive
  ///   `.zip` ni `.zip.part` à ce nom (un `.zip.part` peut être l'écriture
  ///   d'un autre isolat). Le `.zip.part` est créé en mode exclusif (atomique
  ///   sur le disque), puis l'absence du `.zip` est revérifiée : deux isolats
  ///   ne peuvent pas obtenir le même nom.
  ///
  /// Le nom retenu est [EcritureChapitre.nomArchive] (chemin relatif) : le
  /// service l'enregistre en base à la fin du téléchargement
  /// (`DepotTelechargements.enregistrerStatut(…, nomArchive:)` ou
  /// `DepotChapitres.enregistrerArchive`). Une archive `.zip` déjà complète
  /// n'est remplacée qu'à la finalisation.
  ///
  /// LIMITE : un `.zip.part` orphelin (interruption) au nom calculé fait
  /// passer au numéro suivant tant qu'il n'est pas nettoyé par
  /// [nettoyerFichiersPartiels] ; cela ne fait que décaler la numérotation.
  ///
  /// Lève une [ErreurStockage] si ce chapitre est déjà en cours d'écriture
  /// dans cette instance, si aucun nom n'est libre ou si le fichier ne peut
  /// pas être créé.
  Future<EcritureChapitre> ouvrirEcriture(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    final identite = chapitre.urlChapitre;
    // Ajout synchrone (avant tout await) : deux appels simultanés pour le
    // même chapitre ne peuvent pas passer tous les deux.
    if (!_chapitresEnEcriture.add(identite)) {
      throw ErreurStockage(
        "Ce chapitre est déjà en cours d'écriture.",
        chemin: nomArchiveDuChapitre(titre, chapitre, nomSource: nomSource),
      );
    }
    String? cle;
    var reussi = false;
    try {
      final nomImpose =
          chapitre.nomArchive ??
          (chapitre.estTelecharge
              ? nomArchiveCalcule(titre, chapitre, nomSource: nomSource)
              : null);
      final (nomArchive, cheminFinal) = nomImpose != null
          ? await _preparerNomImpose(nomImpose)
          : await _reserverNomLibre(titre, chapitre, nomSource);
      final cheminPartiel = '$cheminFinal$suffixeArchivePartielle';
      cle = chemins.normalize(cheminPartiel);
      // FileAccess.write ouvre le fichier en FileMode.write : un ancien
      // .zip.part (ou celui créé vide par la réservation) est tronqué.
      final sortie = OutputFileStream(
        cheminPartiel,
        bufferSize: tailleTamponEcritureArchive,
      );
      final encodeur = ZipEncoder()..startEncode(sortie);
      final cleOuverte = cle;
      final ecriture = EcritureChapitre._(
        nomArchive: nomArchive,
        cheminFinal: cheminFinal,
        cheminPartiel: cheminPartiel,
        sortie: sortie,
        encodeur: encodeur,
        surFermeture: () {
          _ecrituresOuvertes.remove(cleOuverte);
          _chapitresEnEcriture.remove(identite);
        },
      );
      reussi = true;
      return ecriture;
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        "Impossible de créer l'archive du chapitre.",
        chemin: erreur.path,
        cause: erreur,
      );
    } finally {
      if (!reussi) {
        _chapitresEnEcriture.remove(identite);
        if (cle != null) {
          _ecrituresOuvertes.remove(cle);
        }
      }
    }
  }

  /// Prépare l'écriture sous un nom imposé (re-téléchargement) : vérifie le
  /// nom, crée le dossier et réserve le `.zip.part` dans cette instance.
  /// Renvoie `(nomArchive, cheminFinal)`.
  Future<(String, String)> _preparerNomImpose(String nomArchive) async {
    final cheminFinal = cheminDepuisNomArchive(nomArchive);
    final cle = chemins.normalize('$cheminFinal$suffixeArchivePartielle');
    if (!_ecrituresOuvertes.add(cle)) {
      throw ErreurStockage(
        "Cette archive est déjà en cours d'écriture.",
        chemin: cheminFinal,
      );
    }
    try {
      await Directory(chemins.dirname(cheminFinal)).create(recursive: true);
    } on FileSystemException {
      _ecrituresOuvertes.remove(cle);
      rethrow;
    }
    return (nomArchive, cheminFinal);
  }

  /// Trouve et réserve le premier nom d'archive libre pour un chapitre qui
  /// n'en a pas encore (voir [ouvrirEcriture]) : le `.zip.part` est créé
  /// (vide) et ajouté à [_ecrituresOuvertes]. Renvoie
  /// `(nomArchive, cheminFinal)`.
  Future<(String, String)> _reserverNomLibre(
    Titre titre,
    Chapitre chapitre,
    String? nomSource,
  ) async {
    final dossier = cheminDossierTitre(titre, nomSource: nomSource);
    await Directory(dossier).create(recursive: true);
    final prefixeNom = <String>[
      titre.typeTitre.name,
      nomDossierTitre(titre.nom, nomSource: nomSource),
    ].join(separateurNomArchive);
    for (var numero = 1; numero <= nombreMaxArchivesHomonymes; numero++) {
      final fichier = nomFichierNumerote(chapitre, numero);
      final cheminFinal = chemins.join(dossier, fichier);
      final cheminPartiel = '$cheminFinal$suffixeArchivePartielle';
      final cle = chemins.normalize(cheminPartiel);
      if (_ecrituresOuvertes.contains(cle) ||
          await File(cheminFinal).exists()) {
        continue;
      }
      try {
        // Création exclusive : échoue si le .part existe déjà (écriture d'un
        // autre isolat ou orphelin), de façon atomique sur le disque.
        await File(cheminPartiel).create(exclusive: true);
      } on FileSystemException {
        if (await File(cheminPartiel).exists()) {
          continue;
        }
        rethrow;
      }
      _ecrituresOuvertes.add(cle);
      // Seconde vérification : un autre isolat a pu renommer son .part en
      // .zip entre la première vérification et la création ci-dessus.
      if (await File(cheminFinal).exists()) {
        _ecrituresOuvertes.remove(cle);
        await _supprimerSansErreur(File(cheminPartiel));
        continue;
      }
      return ('$prefixeNom$separateurNomArchive$fichier', cheminFinal);
    }
    throw ErreurStockage(
      "Aucun nom d'archive libre pour ce chapitre.",
      chemin: dossier,
    );
  }

  /// Supprime [fichier] en ignorant les erreurs (chemin d'abandon).
  static Future<void> _supprimerSansErreur(File fichier) async {
    try {
      if (await fichier.exists()) {
        await fichier.delete();
      }
    } on FileSystemException {
      // Le .part restant sera retiré par nettoyerFichiersPartiels().
    }
  }

  // ---------------------------------------------------------------------
  // Lecture
  // ---------------------------------------------------------------------

  /// `true` si l'archive complète (`.zip`) du chapitre existe (chemin
  /// enregistré ou, à défaut, calculé : voir [cheminChapitre]).
  ///
  /// Un `.zip.part` (écriture interrompue ou en cours) ne compte jamais.
  Future<bool> estTelecharge(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    return existeArchive(
      nomArchiveDuChapitre(titre, chapitre, nomSource: nomSource),
    );
  }

  /// `true` si l'archive complète désignée par son chemin relatif
  /// enregistré existe. Sert au contrôle de cohérence au démarrage.
  ///
  /// Lève une [ErreurStockage] si [nomArchive] est invalide.
  Future<bool> existeArchive(String nomArchive) async {
    return File(cheminDepuisNomArchive(nomArchive)).exists();
  }

  /// Nombre de pages (`img<n>.<ext>`) de l'archive du chapitre.
  ///
  /// Lève une [ErreurStockage] si l'archive est absente ou illisible.
  Future<int> compterPages(
    Titre titre,
    Chapitre chapitre, {
    String? nomSource,
  }) async {
    return compterPagesArchive(
      nomArchiveDuChapitre(titre, chapitre, nomSource: nomSource),
    );
  }

  /// Comme [compterPages], à partir du chemin relatif enregistré.
  Future<int> compterPagesArchive(String nomArchive) async {
    final chemin = cheminDepuisNomArchive(nomArchive);
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
    return lirePageArchive(
      nomArchiveDuChapitre(titre, chapitre, nomSource: nomSource),
      index,
    );
  }

  /// Comme [lirePage], à partir du chemin relatif enregistré.
  Future<Uint8List> lirePageArchive(String nomArchive, int index) async {
    final chemin = cheminDepuisNomArchive(nomArchive);
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
    return lireTexteArchive(
      nomArchiveDuChapitre(titre, chapitre, nomSource: nomSource),
    );
  }

  /// Comme [lireTexte], à partir du chemin relatif enregistré.
  Future<String?> lireTexteArchive(String nomArchive) async {
    final chemin = cheminDepuisNomArchive(nomArchive);
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
    return supprimerArchive(
      nomArchiveDuChapitre(titre, chapitre, nomSource: nomSource),
    );
  }

  /// Comme [supprimerChapitre], à partir du chemin relatif enregistré.
  ///
  /// Lève une [ErreurStockage] si [nomArchive] est invalide ou si le disque
  /// refuse la suppression.
  Future<bool> supprimerArchive(String nomArchive) async {
    final chemin = cheminDepuisNomArchive(nomArchive);
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

  /// Supprime les `.zip.part` laissés par des écritures interrompues
  /// (application fermée ou tuée pendant un téléchargement) et renvoie leur
  /// nombre.
  ///
  /// À appeler au démarrage, avant de relancer la file. Les écritures en
  /// cours dans cette instance sont toujours épargnées.
  ///
  /// - Sans [ancienneteMinimale] : tous les autres `.zip.part` sont effacés.
  /// - Avec [ancienneteMinimale] : seuls ceux dont la date de modification
  ///   est plus ancienne que maintenant moins ce délai (strictement). Sur
  ///   Android, un autre isolat peut être en train d'écrire un `.zip.part`
  ///   que cette instance ne connaît pas ; il est vidé sur le disque à
  ///   chaque page, donc sa date reste récente et il est épargné. Utiliser le
  ///   même délai que `DepotTelechargements.reprendreApresInterruption`.
  ///
  /// LIMITE : la date de modification vient du système de fichiers, dont la
  /// précision varie (jusqu'à 2 s sur FAT) ; le délai doit rester large.
  Future<int> nettoyerFichiersPartiels({Duration? ancienneteMinimale}) async {
    if (ancienneteMinimale != null && ancienneteMinimale.isNegative) {
      throw ArgumentError.value(ancienneteMinimale, 'ancienneteMinimale');
    }
    final racine = Directory(dossierRacine);
    if (!await racine.exists()) {
      return 0;
    }
    final limite = ancienneteMinimale == null
        ? null
        : DateTime.now().subtract(ancienneteMinimale);
    var nombre = 0;
    final suffixe = '$extensionArchiveChapitre$suffixeArchivePartielle';
    try {
      await for (final entite in racine.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entite is! File ||
            !entite.path.endsWith(suffixe) ||
            _ecrituresOuvertes.contains(chemins.normalize(entite.path))) {
          continue;
        }
        try {
          if (limite != null) {
            final modification = await entite.lastModified();
            if (!modification.isBefore(limite)) {
              continue;
            }
          }
          await entite.delete();
          nombre++;
        } on PathNotFoundException {
          // Fichier disparu entre la liste et la suppression (finalisé ou
          // abandonné par un autre isolat) : rien à nettoyer.
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
    required this.nomArchive,
    required this.cheminFinal,
    required this.cheminPartiel,
    required this._sortie,
    required this._encodeur,
    required this._surFermeture,
  });

  /// Chemin de l'archive retenue, **relatif** au dossier racine, avec `/`
  /// comme séparateur (`manga/One Punch Man/ch1.fr.2.zip`).
  ///
  /// C'est la valeur à enregistrer en base (`chapitres.nom_archive`) après
  /// [finaliser], pour retrouver l'archive même si le titre est renommé.
  final String nomArchive;

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
