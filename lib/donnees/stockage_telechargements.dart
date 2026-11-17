/// Fichiers hors-ligne : une archive `.zip` par chapitre (PLAYBOOK.md
/// section 5).
///
/// ```
/// <dossier racine>/<type>/<nom du titre>/ch<numero>.<langue>.zip
///     img1.jpg, img2.jpg, img3.webp, …   (chapitre en images)
///     contenu.html                        (chapitre texte)
/// <dossier racine>/<type>/<nom du titre>/couverture.<ext>
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
  /// Crée le stockage sur le [dossierRacine] donné, créé au besoin à la
  /// première écriture (dossier par défaut, dossiers temporaires des tests).
  StockageTelechargements(this.dossierRacine) : estPersonnalise = false;

  /// Crée le stockage sur un dossier **choisi par le client** (chemin local,
  /// lecteur réseau `Z:\…`, chemin UNC `\\nas\partage\…`, dossier monté sous
  /// Linux ou Android), déjà accepté par [validerDossier].
  ///
  /// Ce dossier n'est jamais recréé en silence : s'il est absent ou s'il ne
  /// contient plus le fichier repère [nomFichierMarqueurRacine] (NAS éteint,
  /// partage démonté), les écritures, lectures et suppressions lèvent une
  /// [ErreurStockage] dont [ErreurStockage.estDossierInaccessible] vaut
  /// `true`, et aucun dossier n'est créé. La base n'est pas touchée : les
  /// chapitres redeviennent lisibles quand le dossier revient.
  StockageTelechargements.personnalise(this.dossierRacine)
    : estPersonnalise = true;

  /// Crée le stockage sur le dossier racine par défaut
  /// ([cheminParDefautDossierTelechargements]).
  static Future<StockageTelechargements> parDefaut() async {
    return StockageTelechargements(
      await cheminParDefautDossierTelechargements(),
    );
  }

  /// Crée le stockage à partir du réglage du client : [dossierChoisi] vide
  /// ou `null` donne le dossier par défaut ([parDefaut]), sinon un stockage
  /// [StockageTelechargements.personnalise].
  ///
  /// Ne touche pas au disque (sauf `path_provider` pour le dossier par
  /// défaut) et ne lève donc pas d'erreur si le dossier choisi est
  /// injoignable : appeler ensuite [estDossierRacineAccessible] pour
  /// prévenir le client.
  static Future<StockageTelechargements> depuisReglage(
    String? dossierChoisi,
  ) async {
    final choisi = dossierChoisi?.trim() ?? '';
    if (choisi.isEmpty) {
      return parDefaut();
    }
    return StockageTelechargements.personnalise(choisi);
  }

  /// Dossier racine de tous les fichiers hors-ligne.
  final String dossierRacine;

  /// `true` si le dossier racine a été choisi par le client
  /// ([StockageTelechargements.personnalise]) : il doit alors exister et
  /// contenir le fichier repère, sinon il est considéré comme inaccessible.
  final bool estPersonnalise;

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

  // Fichier de couverture : `couverture.<ext>`.
  static final RegExp _nomCouverture = RegExp(
    '^$nomFichierCouverture\\.[a-z0-9]{1,$longueurMaxExtensionPage}\$',
  );

  // Couverture en cours d'écriture : `couverture.<ext>.part`.
  static final RegExp _nomCouverturePartielle = RegExp(
    '^$nomFichierCouverture\\.[a-z0-9]{1,$longueurMaxExtensionPage}'
    '${RegExp.escape(suffixeArchivePartielle)}\$',
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
  // Dossier racine choisi par le client (disque local, NAS, partage)
  // ---------------------------------------------------------------------

  /// Vérifie qu'un dossier candidat peut servir de dossier racine et renvoie
  /// son chemin normalisé (à enregistrer dans les paramètres).
  ///
  /// Étapes : le chemin doit être complet (absolu) et ne pas désigner un
  /// fichier ; le dossier est créé s'il n'existe pas ; un fichier d'essai
  /// ([prefixeFichierEssaiEcriture]) est écrit, relu (taille) puis supprimé ;
  /// enfin le fichier repère [nomFichierMarqueurRacine] est écrit s'il
  /// manque (voir [StockageTelechargements.personnalise]).
  ///
  /// Accepte un chemin local, un lecteur réseau (`Z:\Mangas`), un chemin UNC
  /// (`\\nas\partage\Mangas`) ou un dossier monté (`/mnt/nas/mangas`).
  ///
  /// Lève une [ErreurStockage] au message clair, avec sa
  /// [ErreurStockage.nature] : [NatureErreurStockage.cheminInvalide],
  /// [NatureErreurStockage.dossierInaccessible],
  /// [NatureErreurStockage.reseauIndisponible],
  /// [NatureErreurStockage.accesRefuse] ou
  /// [NatureErreurStockage.espaceInsuffisant].
  ///
  /// LIMITE : un partage réseau éteint peut mettre plusieurs secondes à
  /// répondre (délai du système) ; l'appelant affiche une attente.
  static Future<String> validerDossier(String chemin) async {
    final dossier = _normaliserCandidat(chemin);
    try {
      final type = await FileSystemEntity.type(dossier);
      if (type == FileSystemEntityType.file) {
        throw ErreurStockage(
          'Ce chemin désigne un fichier et non un dossier.',
          chemin: dossier,
          nature: NatureErreurStockage.cheminInvalide,
        );
      }
      if (type == FileSystemEntityType.notFound) {
        await Directory(dossier).create(recursive: true);
      }
      await _essayerEcriture(dossier);
      await _ecrireMarqueur(dossier);
      return dossier;
    } on FileSystemException catch (erreur) {
      throw erreurDisque(
        'Ce dossier ne peut pas recevoir les téléchargements',
        erreur,
        chemin: dossier,
      );
    }
  }

  /// Nettoie un chemin candidat (espaces, `..`, séparateurs) et vérifie qu'il
  /// est complet. Lève une [ErreurStockage] sinon.
  static String _normaliserCandidat(String chemin) {
    final brut = chemin.trim();
    if (brut.isEmpty || !chemins.isAbsolute(brut)) {
      throw ErreurStockage(
        'Choisissez un chemin complet : dossier du disque, lecteur réseau, '
        'partage réseau ou dossier monté.',
        chemin: chemin,
        nature: NatureErreurStockage.cheminInvalide,
      );
    }
    return chemins.normalize(brut);
  }

  /// Écrit un petit fichier d'essai dans [dossier], vérifie sa taille puis le
  /// supprime (même en cas d'échec).
  static Future<void> _essayerEcriture(String dossier) async {
    final essai = File(
      chemins.join(
        dossier,
        '$prefixeFichierEssaiEcriture'
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final octets = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));
    try {
      await essai.writeAsBytes(octets, flush: true);
      final relus = await essai.length();
      if (relus != octets.length) {
        throw ErreurStockage(
          "Le fichier d'essai a été mal écrit ($relus octets sur "
          '${octets.length}) : ce dossier n\'est pas fiable.',
          chemin: essai.path,
        );
      }
    } finally {
      await _supprimerSansErreur(essai);
    }
  }

  /// Écrit le fichier repère dans [dossier] s'il n'existe pas encore.
  static Future<void> _ecrireMarqueur(String dossier) async {
    final marqueur = File(chemins.join(dossier, nomFichierMarqueurRacine));
    if (!await marqueur.exists()) {
      await marqueur.writeAsString(contenuMarqueurRacine, flush: true);
    }
  }

  /// `true` si le dossier racine est joignable : il existe et, pour un
  /// dossier [estPersonnalise], contient le fichier repère.
  ///
  /// Pour le dossier par défaut, `false` signifie seulement qu'aucun fichier
  /// n'a encore été écrit (il sera créé à la première écriture) ou que le
  /// support est absent. Ne lève jamais d'erreur.
  ///
  /// À appeler au démarrage pour prévenir le client, et **avant** tout
  /// contrôle qui remettrait des chapitres à « non téléchargé » : si le
  /// dossier est injoignable, toutes les archives sembleraient perdues.
  Future<bool> estDossierRacineAccessible() async {
    try {
      if (!await Directory(dossierRacine).exists()) {
        return false;
      }
      if (estPersonnalise) {
        return await File(chemins.join(dossierRacine, nomFichierMarqueurRacine))
            .exists();
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Lève une [ErreurStockage] ([ErreurStockage.estDossierInaccessible])
  /// si le dossier [estPersonnalise] est injoignable ; sans effet pour le
  /// dossier par défaut (créé à la première écriture).
  ///
  /// Appelée par toutes les écritures, suppressions et lectures d'archive :
  /// un dossier choisi par le client n'est jamais recréé ailleurs en silence.
  Future<void> verifierDossierRacine() async {
    if (!estPersonnalise || await estDossierRacineAccessible()) {
      return;
    }
    throw ErreurStockage(
      'Le dossier des téléchargements est inaccessible : '
      '${NatureErreurStockage.dossierInaccessible.explication} Les chapitres '
      'téléchargés redeviendront lisibles quand il sera de nouveau '
      'accessible.',
      chemin: dossierRacine,
      nature: NatureErreurStockage.dossierInaccessible,
    );
  }

  /// Déplace les archives (`<type>/<titre>/*.zip`) et les couvertures
  /// (`<type>/<titre>/couverture.<ext>`) du dossier racine actuel vers
  /// [nouveauDossier], et renvoie le bilan.
  ///
  /// [nouveauDossier] est d'abord accepté par [validerDossier] (création,
  /// essai d'écriture, fichier repère). Puis, fichier par fichier :
  /// 1. une cible existante n'est **jamais** remplacée ni modifiée ;
  /// 2. si elle a la même taille et le même contenu (comparaison octet par
  ///    octet), le fichier est « déjà présent » (reprise d'un déplacement
  ///    interrompu) : l'ancien est supprimé sans recopie ;
  /// 3. si elle diffère (taille ou contenu), c'est un **conflit** (par
  ///    exemple une autre bibliothèque sur un NAS partagé) : l'ancien fichier
  ///    reste dans l'ancien dossier, la cible reste intacte, le chemin
  ///    relatif est ajouté à [BilanDeplacement.cheminsEnConflit] et le
  ///    déplacement continue avec les fichiers suivants. Décider du sort de
  ///    ces fichiers revient à l'appelant (service) ;
  /// 4. si la cible est absente, le fichier est copié dans un `.part` à côté
  ///    de la cible, sa taille est vérifiée, puis il est renommé : une copie
  ///    interrompue n'est jamais prise pour une archive complète ; l'ancien
  ///    fichier n'est supprimé qu'après le renommage.
  ///
  /// Les `.zip.part`, le fichier repère et tout ce qui n'est pas dans un
  /// dossier de type (`exports/`, `rapports/`…) restent en place. L'ancien
  /// dossier racine n'est jamais supprimé ; seuls les dossiers de titre et de
  /// type devenus vides le sont. Les chemins enregistrés en base
  /// (`nom_archive`) sont relatifs : la base n'a pas à changer, il suffit
  /// ensuite d'enregistrer le nouveau dossier et de créer un
  /// [StockageTelechargements.personnalise] dessus.
  ///
  /// [surProgression] reçoit `(faits, total)` : d'abord `(0, total)`, puis
  /// après chaque fichier.
  ///
  /// Lève une [ErreurStockage] si un téléchargement est en cours dans cette
  /// instance (les mettre en pause avant), si le dossier actuel est
  /// inaccessible, si le nouveau dossier est l'actuel, est contenu dans
  /// l'actuel ou le contient ([NatureErreurStockage.cheminInvalide]), ou si
  /// une copie échoue (disque plein, accès refusé, réseau absent : voir
  /// [ErreurStockage.nature]). Les fichiers déjà déplacés restent dans le
  /// nouveau dossier ; relancer la méthode reprend où elle s'est arrêtée.
  ///
  /// LIMITE : `dart:io` ne donne pas l'espace libre d'un disque : un disque
  /// plein n'est détecté qu'à la copie. Deux chemins différents désignant le
  /// même dossier (lecteur mappé et chemin UNC du même partage, lien
  /// symbolique) ne sont pas reconnus comme identiques.
  Future<BilanDeplacement> deplacerArchivesVers(
    String nouveauDossier, {
    void Function(int faits, int total)? surProgression,
  }) async {
    if (_ecrituresOuvertes.isNotEmpty || _chapitresEnEcriture.isNotEmpty) {
      throw ErreurStockage(
        'Des téléchargements sont en cours : mettez-les en pause avant de '
        'déplacer les archives.',
        chemin: dossierRacine,
      );
    }
    final candidat = _normaliserCandidat(nouveauDossier);
    final source = chemins.normalize(chemins.absolute(dossierRacine));
    if (chemins.equals(source, candidat) ||
        chemins.isWithin(source, candidat) ||
        chemins.isWithin(candidat, source)) {
      throw ErreurStockage(
        "Le nouveau dossier ne doit être ni l'actuel, ni un dossier qu'il "
        'contient, ni un dossier qui le contient.',
        chemin: candidat,
        nature: NatureErreurStockage.cheminInvalide,
      );
    }
    await verifierDossierRacine();
    final destination = await validerDossier(candidat);
    final fichiers = await _listerFichiersADeplacer(source);
    final total = fichiers.length;
    surProgression?.call(0, total);
    var copies = 0;
    var dejaPresents = 0;
    var octets = 0;
    final conflits = <String>[];
    final dossiersTouches = <String>{};
    for (var i = 0; i < total; i++) {
      final relatif = fichiers[i];
      final ancien = File(chemins.joinAll(<String>[source, ...relatif]));
      final cible = chemins.joinAll(<String>[destination, ...relatif]);
      final (issue, copie) = await _deplacerFichier(ancien, cible, relatif);
      switch (issue) {
        case _IssueDeplacement.copie:
          copies++;
          octets += copie;
        case _IssueDeplacement.dejaPresent:
          dejaPresents++;
        case _IssueDeplacement.conflit:
          conflits.add(relatif.join(separateurNomArchive));
      }
      dossiersTouches.add(chemins.dirname(ancien.path));
      surProgression?.call(i + 1, total);
    }
    await _retirerDossiersVides(dossiersTouches);
    return BilanDeplacement(
      nombreFichiers: total,
      nombreCopies: copies,
      nombreDejaPresents: dejaPresents,
      octetsCopies: octets,
      cheminsEnConflit: List<String>.unmodifiable(conflits),
    );
  }

  /// Chemins relatifs (`[type, titre, fichier]`) des archives et couvertures
  /// à déplacer depuis [source], triés pour un ordre stable.
  ///
  /// Seuls les dossiers de type connus ([TypeTitre]) sont parcourus : les
  /// dossiers `exports/`, `rapports/` ou tout fichier du client à la racine
  /// ne sont jamais touchés.
  Future<List<List<String>>> _listerFichiersADeplacer(String source) async {
    final resultat = <List<String>>[];
    try {
      for (final type in TypeTitre.values) {
        final dossierType = Directory(chemins.join(source, type.name));
        if (!await dossierType.exists()) {
          continue;
        }
        await for (final titre in dossierType.list(followLinks: false)) {
          if (titre is! Directory) {
            continue;
          }
          await for (final entite in titre.list(followLinks: false)) {
            if (entite is! File) {
              continue;
            }
            final nom = chemins.basename(entite.path);
            // `.zip` exclut d'office les `.zip.part` (écritures interrompues).
            final estArchive =
                nom.endsWith(extensionArchiveChapitre) &&
                nom.length > extensionArchiveChapitre.length;
            if (estArchive || _nomCouverture.hasMatch(nom)) {
              resultat.add(<String>[
                type.name,
                chemins.basename(titre.path),
                nom,
              ]);
            }
          }
        }
      }
    } on FileSystemException catch (erreur) {
      throw erreurDisque(
        'Impossible de lister les archives à déplacer',
        erreur,
        chemin: source,
      );
    }
    resultat.sort((a, b) => a.join('/').compareTo(b.join('/')));
    return resultat;
  }

  /// Déplace [ancien] vers [cible] sans jamais remplacer un fichier existant.
  ///
  /// - Cible absente : copie dans un `.part` à côté de la cible, vérification
  ///   de la taille, renommage, puis suppression de [ancien]
  ///   ([_IssueDeplacement.copie]).
  /// - Cible présente avec la même taille et le même contenu (comparaison
  ///   octet par octet, en flux) : rien n'est écrit, [ancien] est supprimé
  ///   ([_IssueDeplacement.dejaPresent]) ; c'est la reprise d'un déplacement
  ///   interrompu juste avant la suppression.
  /// - Cible présente mais différente (taille ou contenu) : conflit
  ///   ([_IssueDeplacement.conflit]). La cible n'est pas touchée (elle peut
  ///   appartenir à une autre bibliothèque sur un NAS partagé) et [ancien]
  ///   reste dans l'ancien dossier.
  ///
  /// Une copie interrompue reste dans le `.part` (jamais sous le nom final) :
  /// une cible existante n'est donc jamais une copie tronquée de ce
  /// déplacement, et une taille différente signale bien un autre fichier.
  ///
  /// Renvoie l'issue et le nombre d'octets copiés (0 sans copie).
  Future<(_IssueDeplacement, int)> _deplacerFichier(
    File ancien,
    String cible,
    List<String> relatif,
  ) async {
    final nomLisible = relatif.join(separateurNomArchive);
    final partiel = File('$cible$suffixeArchivePartielle');
    try {
      final fichierCible = File(cible);
      if (await fichierCible.exists()) {
        return await _traiterCibleExistante(ancien, fichierCible);
      }
      final taille = await ancien.length();
      await Directory(chemins.dirname(cible)).create(recursive: true);
      await ancien.copy(partiel.path);
      final tailleCopiee = await partiel.length();
      if (tailleCopiee != taille) {
        await _supprimerSansErreur(partiel);
        throw ErreurStockage(
          'La copie de « $nomLisible » est incomplète ($tailleCopiee octets '
          "sur $taille) ; l'ancien fichier est conservé. Relancez le "
          'déplacement pour reprendre.',
          chemin: cible,
        );
      }
      // La cible a pu apparaître pendant la copie (autre appareil écrivant
      // sur le même NAS) : `rename` la remplacerait, on revérifie donc juste
      // avant.
      // LIMITE : `dart:io` n'offre pas de renommage « sans remplacement » ;
      // il reste une fenêtre très courte entre cette vérification et le
      // renommage.
      if (await fichierCible.exists()) {
        await _supprimerSansErreur(partiel);
        return await _traiterCibleExistante(ancien, fichierCible);
      }
      // Renommage dans le même dossier : la cible n'apparaît que complète.
      await partiel.rename(cible);
      await ancien.delete();
      return (_IssueDeplacement.copie, taille);
    } on FileSystemException catch (erreur) {
      await _supprimerSansErreur(partiel);
      throw erreurDisque(
        'Impossible de déplacer « $nomLisible ». Les fichiers déjà déplacés '
        'restent dans le nouveau dossier ; relancez le déplacement pour '
        'reprendre',
        erreur,
        chemin: erreur.path ?? cible,
      );
    }
  }

  /// Cas d'une [cible] déjà présente : si elle est identique à [ancien],
  /// [ancien] est supprimé (déjà présent) ; sinon rien ne bouge (conflit).
  Future<(_IssueDeplacement, int)> _traiterCibleExistante(
    File ancien,
    File cible,
  ) async {
    if (!await _fichiersIdentiques(ancien, cible)) {
      return (_IssueDeplacement.conflit, 0);
    }
    await ancien.delete();
    return (_IssueDeplacement.dejaPresent, 0);
  }

  /// Taille des blocs lus pour comparer deux fichiers (64 Kio) : assez grand
  /// pour limiter les allers-retours sur un NAS, assez petit pour ne jamais
  /// charger une archive entière en mémoire.
  static const int _tailleBlocComparaison = 64 * 1024;

  /// Vrai si [a] et [b] ont la même taille et le même contenu, comparés
  /// octet par octet par blocs de [_tailleBlocComparaison].
  static Future<bool> _fichiersIdentiques(File a, File b) async {
    final taille = await a.length();
    if (await b.length() != taille) {
      return false;
    }
    final lecteurA = await a.open();
    try {
      final lecteurB = await b.open();
      try {
        final blocA = Uint8List(_tailleBlocComparaison);
        final blocB = Uint8List(_tailleBlocComparaison);
        var restant = taille;
        while (restant > 0) {
          final aLire = restant < _tailleBlocComparaison
              ? restant
              : _tailleBlocComparaison;
          final luA = await _lireBloc(lecteurA, blocA, aLire);
          final luB = await _lireBloc(lecteurB, blocB, aLire);
          if (luA != aLire || luB != aLire) {
            // Fichier raccourci pendant la lecture : différent.
            return false;
          }
          for (var i = 0; i < aLire; i++) {
            if (blocA[i] != blocB[i]) {
              return false;
            }
          }
          restant -= aLire;
        }
        return true;
      } finally {
        await lecteurB.close();
      }
    } finally {
      await lecteurA.close();
    }
  }

  /// Lit exactement [nombre] octets dans [bloc] (sauf fin de fichier) et
  /// renvoie le nombre lu : `readInto` peut rendre moins que demandé.
  static Future<int> _lireBloc(
    RandomAccessFile lecteur,
    Uint8List bloc,
    int nombre,
  ) async {
    var lu = 0;
    while (lu < nombre) {
      final n = await lecteur.readInto(bloc, lu, nombre);
      if (n <= 0) {
        break;
      }
      lu += n;
    }
    return lu;
  }

  /// Supprime les dossiers de titre de [dossiers] devenus vides, puis leurs
  /// dossiers de type s'ils sont vides à leur tour. Jamais le dossier racine.
  /// Les erreurs sont ignorées : un dossier vide restant est sans gravité.
  Future<void> _retirerDossiersVides(Set<String> dossiers) async {
    final types = <String>{};
    for (final dossier in dossiers) {
      try {
        await _supprimerDossierSiVide(Directory(dossier));
      } on FileSystemException {
        // Dossier encore utilisé ou verrouillé : on le laisse.
      }
      types.add(chemins.dirname(dossier));
    }
    for (final type in types) {
      try {
        await _supprimerDossierSiVide(Directory(type));
      } on FileSystemException {
        // Idem.
      }
    }
  }

  /// Construit une [ErreurStockage] à partir d'une erreur du système de
  /// fichiers : `<debut> : <explication de la nature>`, avec la nature
  /// déduite de [natureDepuisErreurFichier].
  static ErreurStockage erreurDisque(
    String debut,
    FileSystemException erreur, {
    String? chemin,
  }) {
    final nature = natureDepuisErreurFichier(erreur);
    final explication = nature == NatureErreurStockage.autre
        ? (erreur.osError?.message.trim().isNotEmpty ?? false)
              ? '${erreur.osError!.message.trim()}.'
              : '${erreur.message}.'
        : nature.explication;
    return ErreurStockage(
      '$debut : $explication',
      chemin: chemin ?? erreur.path,
      cause: erreur,
      nature: nature,
    );
  }

  /// Déduit la nature d'une erreur du système de fichiers à partir de son
  /// type et du code d'erreur du système.
  ///
  /// Les codes diffèrent selon le système (5 = accès refusé sous Windows,
  /// erreur d'entrée-sortie sous Linux) : [surWindows] force le système
  /// (tests), sinon `Platform.isWindows`. Codes Windows : `winerror.h` ;
  /// codes Linux et Android : `errno.h`.
  static NatureErreurStockage natureDepuisErreurFichier(
    FileSystemException erreur, {
    bool? surWindows,
  }) {
    final code = erreur.osError?.errorCode;
    if (code != null) {
      final nature = (surWindows ?? Platform.isWindows)
          ? _codesWindows[code]
          : _codesPosix[code];
      if (nature != null) {
        return nature;
      }
    }
    if (erreur is PathAccessException) {
      return NatureErreurStockage.accesRefuse;
    }
    if (erreur is PathNotFoundException) {
      return NatureErreurStockage.dossierInaccessible;
    }
    return NatureErreurStockage.autre;
  }

  /// Codes d'erreur Windows (`winerror.h`) reconnus.
  static const Map<int, NatureErreurStockage> _codesWindows =
      <int, NatureErreurStockage>{
        2: NatureErreurStockage.dossierInaccessible, // FILE_NOT_FOUND
        3: NatureErreurStockage.dossierInaccessible, // PATH_NOT_FOUND
        5: NatureErreurStockage.accesRefuse, // ACCESS_DENIED
        15: NatureErreurStockage.dossierInaccessible, // INVALID_DRIVE
        19: NatureErreurStockage.accesRefuse, // WRITE_PROTECT
        21: NatureErreurStockage.dossierInaccessible, // NOT_READY
        39: NatureErreurStockage.espaceInsuffisant, // HANDLE_DISK_FULL
        51: NatureErreurStockage.reseauIndisponible, // REM_NOT_LIST
        53: NatureErreurStockage.reseauIndisponible, // BAD_NETPATH
        54: NatureErreurStockage.reseauIndisponible, // NETWORK_BUSY
        59: NatureErreurStockage.reseauIndisponible, // UNEXP_NET_ERR
        64: NatureErreurStockage.reseauIndisponible, // NETNAME_DELETED
        65: NatureErreurStockage.accesRefuse, // NETWORK_ACCESS_DENIED
        67: NatureErreurStockage.reseauIndisponible, // BAD_NET_NAME
        112: NatureErreurStockage.espaceInsuffisant, // DISK_FULL
        121: NatureErreurStockage.reseauIndisponible, // SEM_TIMEOUT
        123: NatureErreurStockage.cheminInvalide, // INVALID_NAME
        161: NatureErreurStockage.cheminInvalide, // BAD_PATHNAME
        206: NatureErreurStockage.cheminInvalide, // FILENAME_EXCED_RANGE
        1222: NatureErreurStockage.reseauIndisponible, // NO_NETWORK
        1231: NatureErreurStockage.reseauIndisponible, // NETWORK_UNREACHABLE
        1326: NatureErreurStockage.accesRefuse, // LOGON_FAILURE
        2250: NatureErreurStockage.reseauIndisponible, // NOT_CONNECTED
      };

  /// Codes d'erreur Linux et Android (`errno.h`) reconnus.
  static const Map<int, NatureErreurStockage> _codesPosix =
      <int, NatureErreurStockage>{
        1: NatureErreurStockage.accesRefuse, // EPERM
        2: NatureErreurStockage.dossierInaccessible, // ENOENT
        5: NatureErreurStockage.dossierInaccessible, // EIO (support retiré)
        6: NatureErreurStockage.dossierInaccessible, // ENXIO
        13: NatureErreurStockage.accesRefuse, // EACCES
        19: NatureErreurStockage.dossierInaccessible, // ENODEV
        20: NatureErreurStockage.cheminInvalide, // ENOTDIR
        28: NatureErreurStockage.espaceInsuffisant, // ENOSPC
        30: NatureErreurStockage.accesRefuse, // EROFS
        36: NatureErreurStockage.cheminInvalide, // ENAMETOOLONG
        100: NatureErreurStockage.reseauIndisponible, // ENETDOWN
        101: NatureErreurStockage.reseauIndisponible, // ENETUNREACH
        103: NatureErreurStockage.reseauIndisponible, // ECONNABORTED
        104: NatureErreurStockage.reseauIndisponible, // ECONNRESET
        107: NatureErreurStockage.reseauIndisponible, // ENOTCONN
        110: NatureErreurStockage.reseauIndisponible, // ETIMEDOUT
        112: NatureErreurStockage.reseauIndisponible, // EHOSTDOWN
        113: NatureErreurStockage.reseauIndisponible, // EHOSTUNREACH
        116: NatureErreurStockage.reseauIndisponible, // ESTALE
        122: NatureErreurStockage.espaceInsuffisant, // EDQUOT
      };

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
      // Dossier choisi injoignable (NAS éteint) : refus, sans rien créer.
      await verifierDossierRacine();
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
      throw erreurDisque("Impossible de créer l'archive du chapitre", erreur);
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
  ///
  /// Pour un dossier [estPersonnalise] injoignable, lève une [ErreurStockage]
  /// ([ErreurStockage.estDossierInaccessible]) au lieu de répondre `false` :
  /// l'archive n'est pas perdue, le chapitre ne doit pas être remis à « non
  /// téléchargé ».
  Future<bool> existeArchive(String nomArchive) async {
    final chemin = cheminDepuisNomArchive(nomArchive);
    if (await File(chemin).exists()) {
      return true;
    }
    await verifierDossierRacine();
    return false;
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
      // Dossier choisi injoignable : erreur « inaccessible », plus utile au
      // client que « pas téléchargé ».
      await verifierDossierRacine();
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
  // Couvertures
  // ---------------------------------------------------------------------

  /// Nom du fichier de couverture pour une extension d'image :
  /// `couverture.<ext>` (`couverture.jpg`).
  ///
  /// Lève une [ArgumentError] si l'extension est invalide (voir
  /// [normaliserExtension]).
  static String nomFichierCouvertureAvec(String extension) {
    return '$nomFichierCouverture.${normaliserExtension(extension)}';
  }

  /// Enregistre l'image de couverture d'un titre dans le dossier du titre
  /// (`<racine>/<type>/<nom du titre>/couverture.<ext>`), pour qu'elle reste
  /// lisible hors-ligne, et renvoie son chemin complet.
  ///
  /// [octets] sont déjà récupérés par le service (couverture du site, autre
  /// couverture choisie ou image de l'appareil) ; [extension] est celle
  /// d'origine (`jpg`, `.png`…, voir [extensionDepuisUrl]). Comme les
  /// archives, l'image est écrite dans un `.part` puis renommée : une
  /// écriture interrompue ne remplace jamais une couverture valide. Une
  /// couverture précédente d'une autre extension est ensuite supprimée.
  ///
  /// [nomSource] : même valeur que pour les chapitres du titre (voir
  /// [nomDossierTitre]).
  ///
  /// LIMITE : le dossier dépend du nom du titre ; si le site renomme le
  /// titre, la couverture reste dans l'ancien dossier jusqu'au prochain
  /// enregistrement (le service la réenregistre à l'actualisation).
  ///
  /// Lève une [ArgumentError] si l'extension est invalide, une
  /// [ErreurStockage] si [octets] est vide ou dépasse
  /// [tailleMaxCouverture], ou si le disque refuse l'écriture.
  Future<String> enregistrerCouverture(
    Titre titre,
    List<int> octets,
    String extension, {
    String? nomSource,
  }) async {
    final nomFichier = nomFichierCouvertureAvec(extension);
    final dossier = cheminDossierTitre(titre, nomSource: nomSource);
    final cheminFinal = chemins.join(dossier, nomFichier);
    if (octets.isEmpty) {
      throw ErreurStockage('La couverture est vide.', chemin: cheminFinal);
    }
    if (octets.length > tailleMaxCouverture) {
      throw ErreurStockage(
        'La couverture est trop volumineuse '
        '(${octets.length} octets, au plus $tailleMaxCouverture).',
        chemin: cheminFinal,
      );
    }
    await verifierDossierRacine();
    final cheminPartiel = '$cheminFinal$suffixeArchivePartielle';
    final cle = chemins.normalize(cheminPartiel);
    if (!_ecrituresOuvertes.add(cle)) {
      throw ErreurStockage(
        "Cette couverture est déjà en cours d'écriture.",
        chemin: cheminFinal,
      );
    }
    try {
      await Directory(dossier).create(recursive: true);
      await File(cheminPartiel).writeAsBytes(octets, flush: true);
      // Renommage dans le même dossier : atomique, remplace l'ancienne
      // couverture de même extension.
      await File(cheminPartiel).rename(cheminFinal);
      for (final autre in await _fichiersCouverture(Directory(dossier))) {
        if (chemins.basename(autre.path) != nomFichier) {
          await _supprimerSansErreur(autre);
        }
      }
      return cheminFinal;
    } on FileSystemException catch (erreur) {
      await _supprimerSansErreur(File(cheminPartiel));
      throw erreurDisque(
        "Impossible d'enregistrer la couverture",
        erreur,
        chemin: cheminFinal,
      );
    } finally {
      _ecrituresOuvertes.remove(cle);
    }
  }

  /// Chemin complet de la couverture enregistrée d'un titre, ou `null` si
  /// aucune n'est enregistrée.
  ///
  /// Pratique pour l'affichage (`Image.file`), qui lit le fichier sans tout
  /// charger en mémoire à l'avance.
  Future<String?> cheminCouverture(Titre titre, {String? nomSource}) async {
    final fichiers = await _fichiersCouvertureDuTitre(titre, nomSource);
    return fichiers.isEmpty ? null : fichiers.first.path;
  }

  /// Octets de la couverture enregistrée d'un titre, ou `null` si aucune
  /// n'est enregistrée.
  ///
  /// Lève une [ErreurStockage] si le fichier existe mais ne peut pas être
  /// lu.
  Future<Uint8List?> chargerCouverture(Titre titre, {String? nomSource}) async {
    final fichiers = await _fichiersCouvertureDuTitre(titre, nomSource);
    if (fichiers.isEmpty) {
      return null;
    }
    try {
      return await fichiers.first.readAsBytes();
    } on PathNotFoundException {
      // Supprimée entre la recherche et la lecture.
      return null;
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible de lire la couverture.',
        chemin: fichiers.first.path,
        cause: erreur,
      );
    }
  }

  /// Supprime la couverture enregistrée d'un titre (toutes extensions, et un
  /// éventuel `.part` qui n'est pas en cours d'écriture), puis le dossier du
  /// titre s'il est devenu vide. Renvoie `true` si une couverture a été
  /// supprimée.
  ///
  /// À appeler à la suppression du titre, **après** ses archives : le
  /// dossier n'est retiré que s'il ne contient plus rien.
  ///
  /// Lève une [ErreurStockage] si le disque refuse la suppression.
  Future<bool> supprimerCouverture(Titre titre, {String? nomSource}) async {
    final dossier = Directory(cheminDossierTitre(titre, nomSource: nomSource));
    try {
      if (!await dossier.exists()) {
        return false;
      }
      var supprimee = false;
      await for (final entite in dossier.list(followLinks: false)) {
        if (entite is! File) {
          continue;
        }
        final nom = chemins.basename(entite.path);
        final estCouverture = _nomCouverture.hasMatch(nom);
        final estPartielle =
            _nomCouverturePartielle.hasMatch(nom) &&
            !_ecrituresOuvertes.contains(chemins.normalize(entite.path));
        if (!estCouverture && !estPartielle) {
          continue;
        }
        try {
          await entite.delete();
          supprimee = supprimee || estCouverture;
        } on PathNotFoundException {
          // Déjà supprimée par un autre isolat.
        }
      }
      await _supprimerDossierSiVide(dossier);
      return supprimee;
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible de supprimer la couverture.',
        chemin: dossier.path,
        cause: erreur,
      );
    }
  }

  /// Fichiers de couverture (`couverture.<ext>`, sans les `.part`) du
  /// dossier d'un titre, le plus récent d'abord.
  Future<List<File>> _fichiersCouvertureDuTitre(
    Titre titre,
    String? nomSource,
  ) async {
    try {
      return await _fichiersCouverture(
        Directory(cheminDossierTitre(titre, nomSource: nomSource)),
      );
    } on FileSystemException catch (erreur) {
      throw ErreurStockage(
        'Impossible de chercher la couverture.',
        chemin: cheminDossierTitre(titre, nomSource: nomSource),
        cause: erreur,
      );
    }
  }

  /// Fichiers `couverture.<ext>` de [dossier], le plus récent d'abord (en
  /// principe un seul : [enregistrerCouverture] retire les autres).
  static Future<List<File>> _fichiersCouverture(Directory dossier) async {
    if (!await dossier.exists()) {
      return <File>[];
    }
    final trouves = <(DateTime, File)>[];
    await for (final entite in dossier.list(followLinks: false)) {
      if (entite is File &&
          _nomCouverture.hasMatch(chemins.basename(entite.path))) {
        try {
          trouves.add((await entite.lastModified(), entite));
        } on PathNotFoundException {
          // Remplacée ou supprimée pendant la recherche.
        }
      }
    }
    trouves.sort((a, b) => b.$1.compareTo(a.$1));
    return trouves.map((trouve) => trouve.$2).toList();
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
  /// Lève une [ErreurStockage] si [nomArchive] est invalide, si le disque
  /// refuse la suppression ou si le dossier [estPersonnalise] est injoignable
  /// ([ErreurStockage.estDossierInaccessible] : l'archive resterait sinon
  /// orpheline sur le NAS alors que la base la croirait supprimée).
  Future<bool> supprimerArchive(String nomArchive) async {
    final chemin = cheminDepuisNomArchive(nomArchive);
    final cheminPartiel = '$chemin$suffixeArchivePartielle';
    await verifierDossierRacine();
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
      throw erreurDisque(
        "Impossible de supprimer l'archive du chapitre",
        erreur,
        chemin: chemin,
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

  /// Supprime les `.zip.part` (et `couverture.<ext>.part`) laissés par des
  /// écritures interrompues (application fermée ou tuée pendant un
  /// téléchargement) et renvoie leur nombre.
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
    // Dossier choisi injoignable : rien à nettoyer (et surtout pas un point
    // de montage vide sur le disque local).
    if (!await estDossierRacineAccessible()) {
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
            !(entite.path.endsWith(suffixe) ||
                _nomCouverturePartielle.hasMatch(
                  chemins.basename(entite.path),
                )) ||
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

/// Bilan d'un déplacement des archives vers un autre dossier racine
/// ([StockageTelechargements.deplacerArchivesVers]).
class BilanDeplacement {
  /// Crée un bilan.
  const BilanDeplacement({
    required this.nombreFichiers,
    required this.nombreCopies,
    required this.nombreDejaPresents,
    required this.octetsCopies,
    this.cheminsEnConflit = const <String>[],
  });

  /// Nombre de fichiers (archives et couvertures) traités, conflits compris :
  /// `nombreCopies + nombreDejaPresents + nombreConflits`.
  final int nombreFichiers;

  /// Nombre de fichiers réellement copiés.
  final int nombreCopies;

  /// Nombre de fichiers déjà présents dans le nouveau dossier, identiques
  /// octet pour octet (déplacement repris après une interruption) : non
  /// recopiés, l'ancien exemplaire a été supprimé.
  final int nombreDejaPresents;

  /// Nombre total d'octets copiés.
  final int octetsCopies;

  /// Chemins relatifs à la racine (`type/titre/fichier`, séparateur `/`
  /// comme `nom_archive`) des fichiers en conflit : la cible existait déjà
  /// avec une taille ou un contenu différent.
  ///
  /// Pour chacun, rien n'a été écrit dans le nouveau dossier (la cible est
  /// intacte) et le fichier est **resté dans l'ancien dossier** (son dossier
  /// de titre n'est donc pas retiré). Le service décide de la suite
  /// (garder l'ancien dossier, signaler au client…). Triés dans l'ordre de
  /// traitement.
  final List<String> cheminsEnConflit;

  /// Nombre de fichiers en conflit (longueur de [cheminsEnConflit]) : 0 si
  /// le déplacement est complet.
  int get nombreConflits => cheminsEnConflit.length;

  /// Vrai si au moins un fichier est resté dans l'ancien dossier.
  bool get aDesConflits => cheminsEnConflit.isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! BilanDeplacement ||
        other.nombreFichiers != nombreFichiers ||
        other.nombreCopies != nombreCopies ||
        other.nombreDejaPresents != nombreDejaPresents ||
        other.octetsCopies != octetsCopies ||
        other.cheminsEnConflit.length != cheminsEnConflit.length) {
      return false;
    }
    for (var i = 0; i < cheminsEnConflit.length; i++) {
      if (other.cheminsEnConflit[i] != cheminsEnConflit[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    nombreFichiers,
    nombreCopies,
    nombreDejaPresents,
    octetsCopies,
    Object.hashAll(cheminsEnConflit),
  );

  @override
  String toString() =>
      'BilanDeplacement($nombreFichiers fichiers, $nombreCopies copiés, '
      '$nombreDejaPresents déjà présents, $nombreConflits en conflit, '
      '$octetsCopies octets)';
}

/// Issue du déplacement d'un fichier
/// ([StockageTelechargements.deplacerArchivesVers]).
enum _IssueDeplacement {
  /// Fichier copié puis ancien exemplaire supprimé.
  copie,

  /// Cible identique déjà présente : ancien exemplaire supprimé.
  dejaPresent,

  /// Cible différente déjà présente : rien n'a bougé.
  conflit,
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
