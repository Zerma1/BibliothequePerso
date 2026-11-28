/// Règles pures de l'import de fichiers (CBZ, PDF, EPUB sans DRM) :
/// signatures, détection des protections, lecture de la structure d'un EPUB
/// (container.xml, OPF, table des matières) et préparation d'une section.
///
/// Aucun accès au disque ici : les octets sont fournis par l'appelant
/// (`ServiceFichiersImportes`), ce qui rend ces règles testables sans
/// fichier. La lecture XML est volontairement simple (expressions
/// régulières) : le projet ne dépend d'aucun analyseur XML, et seules
/// quelques balises bien connues sont lues.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as chemins;

import '../modeles/fichier_importe.dart';

/// Raison d'un refus décidé par l'analyse d'un fichier.
enum MotifRefusAnalyse {
  /// Contenu abîmé, incomplet ou qui ne correspond pas au format annoncé.
  illisible,

  /// Fichier protégé (DRM, chiffrement) : jamais importé ni contourné
  /// (PLAYBOOK.md section 10).
  protegeParDrm,
}

/// Refus levé par l'analyse d'un fichier, avec un message pour le client.
class RefusAnalyse implements Exception {
  /// Crée un refus de motif [motif].
  const RefusAnalyse(this.motif, this.message);

  /// Raison du refus.
  final MotifRefusAnalyse motif;

  /// Explication affichable telle quelle.
  final String message;

  @override
  String toString() => 'RefusAnalyse(${motif.name}) : $message';
}

/// Une section du *spine* d'un EPUB (un fichier XHTML), dans l'ordre de
/// lecture.
class SectionEpub {
  /// Crée une section.
  const SectionEpub({
    required this.index,
    required this.chemin,
    this.titre,
    this.estLineaire = true,
  });

  /// Index dans le spine, à partir de 0 (`PositionLecture.section`).
  final int index;

  /// Chemin exact de l'entrée dans l'archive (`OEBPS/chap1.xhtml`).
  final String chemin;

  /// Titre donné par la table des matières, ou `null` si la section n'y
  /// figure pas.
  final String? titre;

  /// `false` pour une section annexe (`linear="no"` : note, encart) que le
  /// lecteur peut sauter en lecture continue.
  final bool estLineaire;

  @override
  String toString() => 'SectionEpub($index, $chemin, $titre)';
}

/// Structure d'un EPUB : métadonnées et sections dans l'ordre de lecture.
class ContenuEpub {
  /// Crée la structure.
  const ContenuEpub({
    this.titre,
    this.auteur,
    this.langue,
    required this.sections,
    this.typesMedia = const <String, String>{},
  });

  /// Titre (`dc:title`), ou `null`.
  final String? titre;

  /// Auteur (`dc:creator`), ou `null`.
  final String? auteur;

  /// Langue principale (`dc:language`, sous-étiquette principale en
  /// minuscules : `fr`), ou `null`.
  final String? langue;

  /// Sections du spine, dans l'ordre (jamais vide pour un EPUB analysé).
  final List<SectionEpub> sections;

  /// Type de média de chaque ressource du manifeste, par chemin dans
  /// l'archive (sert aux adresses `data:` des images).
  final Map<String, String> typesMedia;
}

/// Lecture asynchrone d'une entrée d'archive par son chemin exact, ou
/// `null` si elle n'existe pas.
typedef LectureEntree = Future<Uint8List?> Function(String nomEntree);

/// Règles pures d'analyse des fichiers importés.
abstract final class AnalyseFichiersImportes {
  /// Signature d'une archive zip (CBZ, EPUB) : « PK\x03\x04 ».
  static const List<int> signatureZip = <int>[0x50, 0x4b, 0x03, 0x04];

  /// Signature d'un PDF : « %PDF- ».
  static const List<int> signaturePdf = <int>[0x25, 0x50, 0x44, 0x46, 0x2d];

  /// Nombre d'octets lus au début d'un fichier pour sa signature : la norme
  /// PDF tolère quelques octets avant « %PDF- ».
  static const int octetsSignature = 1024;

  /// Type de média obligatoire d'un EPUB (entrée `mimetype`).
  static const String typeMediaEpub = 'application/epub+zip';

  /// Algorithmes de `META-INF/encryption.xml` qui ne protègent que des
  /// **polices** (obfuscation IDPF et Adobe) : le texte et les images
  /// restent lisibles, le livre n'est pas protégé par DRM.
  static const Set<String> algorithmesPolicesObfusquees = <String>{
    'http://www.idpf.org/2008/embedding',
    'http://ns.adobe.com/pdf/enc#RC',
  };

  /// Entrées qui signalent un EPUB protégé (Adobe ADEPT : `rights.xml` ;
  /// Readium LCP : `license.lcpl`).
  static const List<String> entreesDrm = <String>[
    'META-INF/rights.xml',
    'META-INF/license.lcpl',
  ];

  /// Extensions reconnues comme pages d'un CBZ (mêmes règles que
  /// `StockageTelechargements.lirePageCbz`).
  static const Set<String> extensionsImages = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'avif',
    'bmp',
  };

  /// Types de média des images, par extension (repli si le manifeste de
  /// l'EPUB n'en donne pas).
  static const Map<String, String> typesMediaImages = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'avif': 'image/avif',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
  };

  // ------------------------------------------------------------ Signatures

  /// Position de [motif] dans [octets] à partir de [debut], ou -1.
  static int indexOctets(List<int> octets, List<int> motif, [int debut = 0]) {
    if (motif.isEmpty) return debut;
    final fin = octets.length - motif.length;
    for (var i = debut < 0 ? 0 : debut; i <= fin; i++) {
      var trouve = true;
      for (var j = 0; j < motif.length; j++) {
        if (octets[i + j] != motif[j]) {
          trouve = false;
          break;
        }
      }
      if (trouve) return i;
    }
    return -1;
  }

  /// `true` si [debut] (premiers octets du fichier) porte la signature du
  /// [format] : zip au tout début pour CBZ et EPUB, « %PDF- » dans les
  /// [octetsSignature] premiers octets pour un PDF.
  static bool aSignatureAttendue(FormatFichierLocal format, List<int> debut) {
    return switch (format) {
      FormatFichierLocal.cbz || FormatFichierLocal.epub =>
        debut.length >= signatureZip.length &&
            indexOctets(debut.sublist(0, signatureZip.length), signatureZip) ==
                0,
      FormatFichierLocal.pdf =>
        indexOctets(
              debut.length > octetsSignature
                  ? debut.sublist(0, octetsSignature)
                  : debut,
              signaturePdf,
            ) >=
            0,
    };
  }

  /// `true` si [octets] (début ou fin d'un PDF) contiennent la clé
  /// `/Encrypt` d'un dictionnaire de chiffrement.
  ///
  /// LIMITE : simple recherche d'octets, sans analyser la structure du PDF.
  /// La clé est toujours écrite en clair dans le trailer ou dans le
  /// dictionnaire de la table des références (jamais dans un flux
  /// compressé), d'où une détection fiable des PDF chiffrés ; un PDF qui
  /// contiendrait le texte « /Encrypt » en clair ailleurs serait refusé à
  /// tort (cas très rare, préféré à l'import d'un fichier protégé).
  static bool contientChiffrementPdf(List<int> octets) {
    const motif = <int>[0x2f, 0x45, 0x6e, 0x63, 0x72, 0x79, 0x70, 0x74];
    var debut = 0;
    while (true) {
      final index = indexOctets(octets, motif, debut);
      if (index < 0) return false;
      final suivant = index + motif.length;
      // `/EncryptMetadata` n'existe que dans un dictionnaire /Encrypt : on
      // exige que la clé se termine ici (délimiteur ou fin des octets).
      if (suivant >= octets.length || !_estLettre(octets[suivant])) {
        return true;
      }
      debut = index + 1;
    }
  }

  static bool _estLettre(int octet) =>
      (octet >= 0x41 && octet <= 0x5a) || (octet >= 0x61 && octet <= 0x7a);

  // ------------------------------------------------------------------ CBZ

  /// `true` si [nomEntree] est une page d'un CBZ : image reconnue par son
  /// extension, hors dossiers `__MACOSX` et fichiers cachés (`.…`).
  static bool estPageCbz(String nomEntree) {
    final elements = nomEntree.split('/');
    if (elements.any((e) => e.startsWith('.') || e == '__MACOSX')) {
      return false;
    }
    final point = nomEntree.lastIndexOf('.');
    return point > 0 &&
        extensionsImages.contains(nomEntree.substring(point + 1).toLowerCase());
  }

  // ----------------------------------------------------------------- EPUB

  /// `true` si `META-INF/encryption.xml` ([xml]) chiffre des contenus
  /// autres que des polices obfusquées ([algorithmesPolicesObfusquees]).
  ///
  /// Une donnée chiffrée sans algorithme lisible compte comme chiffrée :
  /// dans le doute, le fichier est refusé plutôt que contourné.
  static bool chiffreDesContenus(String xml) {
    final blocs = RegExp(
      r'<(?:[\w-]+:)?EncryptedData\b(.*?)</(?:[\w-]+:)?EncryptedData\s*>',
      dotAll: true,
    ).allMatches(xml);
    for (final bloc in blocs) {
      final methode = RegExp(r'<(?:[\w-]+:)?EncryptionMethod\b([^>]*)>')
          .firstMatch(bloc.group(1)!);
      final algorithme = methode == null
          ? null
          : attributs(methode.group(1)!)['Algorithm']?.trim();
      if (algorithme == null ||
          !algorithmesPolicesObfusquees.contains(algorithme)) {
        return true;
      }
    }
    // Une donnée chiffrée écrite sans balise fermante (`<EncryptedData/>`)
    // n'est pas lisible ici : prudence.
    return RegExp(r'<(?:[\w-]+:)?EncryptedData\b[^>]*/>').hasMatch(xml);
  }

  /// Chemin de l'OPF (paquet) déclaré par `META-INF/container.xml`, ou
  /// `null` s'il n'y en a pas.
  static String? cheminOpf(String containerXml) {
    String? premier;
    for (final balise in RegExp(
      r'<(?:[\w-]+:)?rootfile\b([^>]*)>',
    ).allMatches(containerXml)) {
      final attributsBalise = attributs(balise.group(1)!);
      final chemin = attributsBalise['full-path']?.trim();
      if (chemin == null || chemin.isEmpty) continue;
      final type = attributsBalise['media-type'];
      if (type == 'application/oebps-package+xml') return chemin;
      premier ??= chemin;
    }
    return premier;
  }

  /// Analyse un EPUB entrée par entrée ([lire]) et renvoie sa structure.
  ///
  /// Contrôles, dans l'ordre : entrée `mimetype` = [typeMediaEpub],
  /// `META-INF/container.xml` et OPF lisibles ; puis refus d'un livre
  /// protégé ([entreesDrm], `META-INF/encryption.xml` qui chiffre des
  /// contenus) ; enfin spine non vide. Lève un [RefusAnalyse] sinon.
  static Future<ContenuEpub> analyserEpub(LectureEntree lire) async {
    final mimetype = await lire('mimetype');
    if (mimetype == null ||
        utf8.decode(mimetype, allowMalformed: true).trim() != typeMediaEpub) {
      throw const RefusAnalyse(
        MotifRefusAnalyse.illisible,
        "Ce fichier n'est pas un EPUB valide (type de document absent).",
      );
    }
    final container = await lire('META-INF/container.xml');
    final chemin = container == null ? null : cheminOpf(_texte(container));
    if (chemin == null) {
      throw const RefusAnalyse(
        MotifRefusAnalyse.illisible,
        "Ce fichier n'est pas un EPUB valide (container.xml absent ou vide).",
      );
    }
    // DRM avant toute lecture du contenu : un livre protégé est refusé tel
    // quel, sans chercher à le lire (PLAYBOOK.md section 10).
    for (final entree in entreesDrm) {
      if (await lire(entree) != null) {
        throw const RefusAnalyse(
          MotifRefusAnalyse.protegeParDrm,
          'Ce livre est protégé par un DRM : il ne peut pas être importé.',
        );
      }
    }
    final chiffrement = await lire('META-INF/encryption.xml');
    if (chiffrement != null && chiffreDesContenus(_texte(chiffrement))) {
      throw const RefusAnalyse(
        MotifRefusAnalyse.protegeParDrm,
        'Ce livre est chiffré (DRM) : il ne peut pas être importé.',
      );
    }
    final opf = await lire(chemin);
    if (opf == null) {
      throw const RefusAnalyse(
        MotifRefusAnalyse.illisible,
        "Ce fichier n'est pas un EPUB valide (description du livre absente).",
      );
    }
    final paquet = lirePaquet(_texte(opf), chemin);
    if (paquet.spine.isEmpty) {
      throw const RefusAnalyse(
        MotifRefusAnalyse.illisible,
        "Ce livre ne contient aucune section lisible.",
      );
    }
    // Table des matières : EPUB 3 (document nav) d'abord, sinon EPUB 2
    // (toc.ncx). Une table absente ou illisible n'empêche pas la lecture.
    var titres = const <String, String>{};
    final nav = paquet.cheminNav;
    final ncx = paquet.cheminNcx;
    if (nav != null) {
      final octets = await lire(nav);
      if (octets != null) titres = lireTableNav(_texte(octets), nav);
    }
    if (titres.isEmpty && ncx != null) {
      final octets = await lire(ncx);
      if (octets != null) titres = lireTableNcx(_texte(octets), ncx);
    }
    return ContenuEpub(
      titre: paquet.titre,
      auteur: paquet.auteur,
      langue: paquet.langue,
      typesMedia: paquet.typesMedia,
      sections: <SectionEpub>[
        for (var i = 0; i < paquet.spine.length; i++)
          SectionEpub(
            index: i,
            chemin: paquet.spine[i].chemin,
            titre: titres[paquet.spine[i].chemin],
            estLineaire: paquet.spine[i].estLineaire,
          ),
      ],
    );
  }

  /// Lit l'OPF [xml] (situé à [cheminOpf] dans l'archive) : métadonnées,
  /// manifeste, spine et emplacement de la table des matières.
  static PaquetEpub lirePaquet(String xml, String cheminOpf) {
    final metadonnees =
        RegExp(
          r'<(?:[\w-]+:)?metadata\b.*?</(?:[\w-]+:)?metadata\s*>',
          dotAll: true,
        ).firstMatch(xml)?.group(0) ??
        xml;
    String? element(String nom) {
      final trouve = RegExp(
        '<(?:[\\w-]+:)?$nom\\b[^>]*>(.*?)</(?:[\\w-]+:)?$nom\\s*>',
        dotAll: true,
      ).firstMatch(metadonnees);
      final texte = trouve == null ? '' : texteBrut(trouve.group(1)!);
      return texte.isEmpty ? null : texte;
    }

    final manifeste = <String, ({String chemin, String type, String props})>{};
    for (final item in RegExp(r'<(?:[\w-]+:)?item\b([^>]*)>').allMatches(xml)) {
      final a = attributs(item.group(1)!);
      final id = a['id'];
      final href = a['href'];
      if (id == null || href == null) continue;
      manifeste[id] = (
        chemin: resoudreChemin(cheminOpf, href),
        type: a['media-type'] ?? '',
        props: a['properties'] ?? '',
      );
    }
    final spineBalise = RegExp(r'<(?:[\w-]+:)?spine\b([^>]*)>').firstMatch(xml);
    final idToc = spineBalise == null
        ? null
        : attributs(spineBalise.group(1)!)['toc'];
    final spine = <({String chemin, bool estLineaire})>[];
    for (final reference in RegExp(
      r'<(?:[\w-]+:)?itemref\b([^>]*)>',
    ).allMatches(xml)) {
      final a = attributs(reference.group(1)!);
      final item = manifeste[a['idref']];
      if (item == null) continue;
      spine.add((chemin: item.chemin, estLineaire: a['linear'] != 'no'));
    }
    String? cheminNav;
    String? cheminNcx = idToc == null ? null : manifeste[idToc]?.chemin;
    for (final item in manifeste.values) {
      if (cheminNav == null &&
          item.props.split(RegExp(r'\s+')).contains('nav')) {
        cheminNav = item.chemin;
      }
      if (cheminNcx == null && item.type == 'application/x-dtbncx+xml') {
        cheminNcx = item.chemin;
      }
    }
    final langue = element('language')
        ?.split(RegExp('[-_]'))
        .first
        .toLowerCase();
    return PaquetEpub(
      titre: element('title'),
      auteur: element('creator'),
      langue: langue != null && RegExp(r'^[a-z]{2,3}$').hasMatch(langue)
          ? langue
          : null,
      spine: spine,
      cheminNav: cheminNav,
      cheminNcx: cheminNcx,
      typesMedia: <String, String>{
        for (final item in manifeste.values)
          if (item.type.isNotEmpty) item.chemin: item.type,
      },
    );
  }

  /// Titres de la table des matières EPUB 3 ([xhtml], document nav situé à
  /// [cheminNav]), par chemin de section (premier titre trouvé).
  static Map<String, String> lireTableNav(String xhtml, String cheminNav) {
    final toc =
        RegExp(
          r'''<(?:[\w-]+:)?nav\b[^>]*epub:type\s*=\s*["'][^"']*\btoc\b[^"']*["'][^>]*>(.*?)</(?:[\w-]+:)?nav\s*>''',
          dotAll: true,
        ).firstMatch(xhtml)?.group(1) ??
        xhtml;
    final titres = <String, String>{};
    for (final lien in RegExp(
      r'''<(?:[\w-]+:)?a\b[^>]*\bhref\s*=\s*(["'])(.*?)\1[^>]*>(.*?)</(?:[\w-]+:)?a\s*>''',
      dotAll: true,
    ).allMatches(toc)) {
      final titre = texteBrut(lien.group(3)!);
      if (titre.isEmpty) continue;
      titres.putIfAbsent(
        resoudreChemin(cheminNav, lien.group(2)!),
        () => titre,
      );
    }
    return titres;
  }

  /// Titres de la table des matières EPUB 2 ([xml], `toc.ncx` situé à
  /// [cheminNcx]), par chemin de section (premier titre trouvé).
  static Map<String, String> lireTableNcx(String xml, String cheminNcx) {
    final titres = <String, String>{};
    for (final point in RegExp(
      r'''<(?:[\w-]+:)?navPoint\b.*?<(?:[\w-]+:)?text\b[^>]*>(.*?)</(?:[\w-]+:)?text\s*>.*?<(?:[\w-]+:)?content\b[^>]*\bsrc\s*=\s*(["'])(.*?)\2''',
      dotAll: true,
    ).allMatches(xml)) {
      final titre = texteBrut(point.group(1)!);
      if (titre.isEmpty) continue;
      titres.putIfAbsent(
        resoudreChemin(cheminNcx, point.group(3)!),
        () => titre,
      );
    }
    return titres;
  }

  /// Chemin dans l'archive de la ressource [href], relative au document
  /// [cheminDocument] : décodage des `%20`, fragment (`#…`) et requête
  /// retirés, `..` résolus.
  static String resoudreChemin(String cheminDocument, String href) {
    var cible = href.trim();
    final diese = cible.indexOf('#');
    if (diese >= 0) cible = cible.substring(0, diese);
    final question = cible.indexOf('?');
    if (question >= 0) cible = cible.substring(0, question);
    try {
      cible = Uri.decodeComponent(cible);
    } on ArgumentError {
      // Encodage invalide : on garde le texte tel quel.
    }
    if (cible.isEmpty) return cheminDocument;
    if (cible.startsWith('/')) {
      return chemins.posix.normalize(cible.substring(1));
    }
    final dossier = chemins.posix.dirname(cheminDocument);
    return chemins.posix.normalize(
      dossier == '.' ? cible : chemins.posix.join(dossier, cible),
    );
  }

  // ------------------------------------------------- Préparation d'une section

  // Attribut source d'une image (`<img src>`, `<image xlink:href>` en SVG).
  static final RegExp _sourceImage = RegExp(
    r'''(<(?:[\w-]+:)?(?:img|image)\b[^>]*?\s(?:src|xlink:href|href)\s*=\s*)(["'])([^"']*)\2''',
    caseSensitive: false,
  );

  // Scripts d'un livre : jamais exécutés dans le lecteur (contenu reçu d'un
  // fichier, aucune raison d'y faire tourner du code).
  static final RegExp _scripts = RegExp(
    r'<script\b[^>]*?(?:/>|>.*?</script\s*>)',
    caseSensitive: false,
    dotAll: true,
  );

  /// Chemins (dans l'archive) des images locales de la section [html]
  /// située à [cheminSection], sans doublon, au plus [maximum]. Les
  /// adresses `data:` et web sont ignorées.
  static List<String> imagesDeSection(
    String html,
    String cheminSection, {
    int maximum = 1000,
  }) {
    final resultat = <String>{};
    for (final image in _sourceImage.allMatches(html)) {
      if (resultat.length >= maximum) break;
      final source = image.group(3)!;
      if (_estAdresseExterne(source)) continue;
      resultat.add(resoudreChemin(cheminSection, source));
    }
    return resultat.toList();
  }

  /// Prépare la section [html] (située à [cheminSection]) pour le lecteur :
  /// scripts retirés, et chaque image locale remplacée par son adresse
  /// `data:` donnée par [adressesData] (chemin → `data:…`). Une image
  /// absente de [adressesData] garde son adresse d'origine.
  ///
  /// LIMITE : les feuilles de style (`<link rel="stylesheet">`) ne sont pas
  /// intégrées ; le lecteur applique sa propre mise en page.
  static String preparerSection(
    String html,
    String cheminSection,
    Map<String, String> adressesData,
  ) {
    return html.replaceAll(_scripts, '').replaceAllMapped(_sourceImage, (m) {
      final source = m.group(3)!;
      if (_estAdresseExterne(source)) return m.group(0)!;
      final data = adressesData[resoudreChemin(cheminSection, source)];
      return data == null
          ? m.group(0)!
          : '${m.group(1)}${m.group(2)}$data${m.group(2)}';
    });
  }

  /// Adresse `data:` de l'image [octets] ([typeMedia], ou type déduit de
  /// l'extension de [chemin]).
  static String adresseData(
    String chemin,
    Uint8List octets, {
    String? typeMedia,
  }) {
    final point = chemin.lastIndexOf('.');
    final extension = point < 0
        ? ''
        : chemin.substring(point + 1).toLowerCase();
    final type = (typeMedia != null && typeMedia.startsWith('image/'))
        ? typeMedia
        : typesMediaImages[extension] ?? 'application/octet-stream';
    return 'data:$type;base64,${base64Encode(octets)}';
  }

  static bool _estAdresseExterne(String source) {
    final s = source.trim().toLowerCase();
    return s.isEmpty ||
        s.startsWith('data:') ||
        s.startsWith('http:') ||
        s.startsWith('https:') ||
        s.startsWith('//');
  }

  // --------------------------------------------------------------- Outils XML

  /// Attributs d'une balise ([texte] = tout ce qui suit son nom), par nom
  /// exact. Les entités (`&amp;`…) des valeurs sont décodées.
  static Map<String, String> attributs(String texte) {
    return <String, String>{
      for (final a in RegExp(
        r'''([\w:.-]+)\s*=\s*(["'])(.*?)\2''',
        dotAll: true,
      ).allMatches(texte))
        a.group(1)!: decoderEntites(a.group(3)!),
    };
  }

  /// Texte d'un fragment XML : balises retirées, entités décodées, espaces
  /// regroupés.
  static String texteBrut(String fragment) {
    final sansBalises = fragment
        .replaceAllMapped(
          RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true),
          (m) => m.group(1)!,
        )
        .replaceAll(RegExp(r'<[^>]*>'), ' ');
    return decoderEntites(sansBalises).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Décode les entités XML prédéfinies et numériques.
  static String decoderEntites(String texte) {
    return texte.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);'),
      (m) {
        final code = m.group(1)!;
        switch (code) {
          case 'amp':
            return '&';
          case 'lt':
            return '<';
          case 'gt':
            return '>';
          case 'quot':
            return '"';
          case 'apos':
            return "'";
        }
        final valeur = code.startsWith('#x')
            ? int.tryParse(code.substring(2), radix: 16)
            : int.tryParse(code.substring(1));
        if (valeur == null || valeur <= 0 || valeur > 0x10ffff) {
          return m.group(0)!;
        }
        return String.fromCharCode(valeur);
      },
    );
  }

  static String _texte(Uint8List octets) =>
      utf8.decode(octets, allowMalformed: true);
}

/// Contenu lu dans l'OPF d'un EPUB ([AnalyseFichiersImportes.lirePaquet]).
class PaquetEpub {
  /// Crée le contenu lu.
  const PaquetEpub({
    this.titre,
    this.auteur,
    this.langue,
    required this.spine,
    this.cheminNav,
    this.cheminNcx,
    this.typesMedia = const <String, String>{},
  });

  /// Titre (`dc:title`), ou `null`.
  final String? titre;

  /// Auteur (`dc:creator`), ou `null`.
  final String? auteur;

  /// Langue (`dc:language`, sous-étiquette principale), ou `null`.
  final String? langue;

  /// Sections dans l'ordre de lecture (chemins résolus dans l'archive).
  final List<({String chemin, bool estLineaire})> spine;

  /// Chemin du document nav (EPUB 3), ou `null`.
  final String? cheminNav;

  /// Chemin de `toc.ncx` (EPUB 2), ou `null`.
  final String? cheminNcx;

  /// Type de média de chaque ressource du manifeste, par chemin.
  final Map<String, String> typesMedia;
}
