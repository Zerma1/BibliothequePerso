/// Reconnaissance d'une image par ses premiers octets (« nombres
/// magiques »), et extrait lisible d'une réponse qui n'en est pas une.
///
/// Sert quand un site sert ses images sans `Content-Type`, avec un type
/// générique (`application/octet-stream`) ou faux : seuls les octets disent
/// alors ce qu'est la réponse (retour du client sur la 0.2.1-test : une page
/// WEBP valide servie sans `Content-Type` était refusée).
library;

import 'dart:convert';

import 'rapport_erreur_source.dart';

/// Format d'image reconnu par ses octets ([detecterFormatImage]).
enum FormatImage {
  /// JPEG : `FF D8 FF`.
  jpeg('jpg', 'image/jpeg'),

  /// PNG : `89 50 4E 47 0D 0A 1A 0A`.
  png('png', 'image/png'),

  /// GIF : « GIF87a » ou « GIF89a ».
  gif('gif', 'image/gif'),

  /// WEBP : « RIFF » + taille sur 4 octets + « WEBP ».
  webp('webp', 'image/webp'),

  /// AVIF : boîte « ftyp » de marque `avif` / `avis` (ISO BMFF).
  avif('avif', 'image/avif'),

  /// HEIF / HEIC : boîte « ftyp » de marque `heic`, `heix`, `mif1`…
  heif('heic', 'image/heif'),

  /// BMP : « BM ».
  bmp('bmp', 'image/bmp');

  const FormatImage(this.extension, this.typeMime);

  /// Extension de fichier usuelle, sans point (`jpg`, `webp`…) : à utiliser
  /// pour nommer la page dans l'archive plutôt que l'extension de l'adresse,
  /// qui peut mentir (`.jpg` servi en WEBP).
  final String extension;

  /// Type MIME correspondant (`image/webp`…).
  final String typeMime;
}

/// Longueur maximale (en caractères) de l'extrait texte cité dans un message
/// d'erreur « n'est pas une image » : court, pour rester lisible dans la
/// file de téléchargement.
const int longueurMaxExtraitMessageImage = 80;

/// Nombre d'octets examinés pour décider si une réponse est du texte.
const int _tailleEchantillonTexte = 1024;

/// Part maximale de caractères illisibles (contrôle, octets UTF-8 invalides)
/// dans un texte : au-delà, la réponse est considérée comme binaire.
const double _partMaxCaracteresIllisibles = 0.1;

/// Marques ISO BMFF (boîte `ftyp`) d'une image AVIF.
const Set<String> _marquesAvif = <String>{'avif', 'avis'};

/// Marques ISO BMFF d'une image HEIF / HEIC. `mif1` et `msf1` sont les
/// marques génériques HEIF (une image AVIF peut aussi les porter : ses
/// marques compatibles sont alors examinées).
const Set<String> _marquesHeif = <String>{
  'heic',
  'heix',
  'hevc',
  'hevx',
  'heim',
  'heis',
  'mif1',
  'msf1',
};

/// Format d'image reconnu d'après les premiers [octets], ou `null` si ce
/// n'est aucun des formats de [FormatImage].
///
/// Ne lit que l'en-tête : une image tronquée mais bien commencée est
/// reconnue (le décodage reste l'affaire de l'afficheur).
FormatImage? detecterFormatImage(List<int> octets) {
  bool commencePar(List<int> signature, [int decalage = 0]) {
    if (octets.length < decalage + signature.length) {
      return false;
    }
    for (var i = 0; i < signature.length; i++) {
      if (octets[decalage + i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  if (commencePar(const <int>[0xFF, 0xD8, 0xFF])) {
    return FormatImage.jpeg;
  }
  if (commencePar(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return FormatImage.png;
  }
  if (commencePar(ascii.encode('GIF87a')) ||
      commencePar(ascii.encode('GIF89a'))) {
    return FormatImage.gif;
  }
  if (commencePar(ascii.encode('RIFF')) &&
      commencePar(ascii.encode('WEBP'), 8)) {
    return FormatImage.webp;
  }
  if (commencePar(ascii.encode('ftyp'), 4) && octets.length >= 12) {
    final marque = _texteAscii(octets, 8, 4);
    // Marques compatibles : de l'octet 16 à la fin de la boîte `ftyp`
    // (taille sur 4 octets gros-boutiste au début), par blocs de 4.
    final tailleBoite =
        (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
    final fin = tailleBoite < octets.length ? tailleBoite : octets.length;
    final compatibles = <String>{
      for (var i = 16; i + 4 <= fin; i += 4) _texteAscii(octets, i, 4),
    };
    if (_marquesAvif.contains(marque) ||
        ((marque == 'mif1' || marque == 'msf1') &&
            compatibles.any(_marquesAvif.contains))) {
      return FormatImage.avif;
    }
    if (_marquesHeif.contains(marque)) {
      return FormatImage.heif;
    }
    return null;
  }
  // « BM » seul est court : on exige aussi un en-tête DIB plausible (taille
  // 12, 40, 52, 56, 64, 108 ou 124 à l'octet 14) pour ne pas prendre un
  // texte qui commence par « BM » pour une image.
  if (commencePar(ascii.encode('BM')) && octets.length >= 18) {
    final tailleDib =
        octets[14] |
        (octets[15] << 8) |
        (octets[16] << 16) |
        (octets[17] << 24);
    if (const <int>{12, 40, 52, 56, 64, 108, 124}.contains(tailleDib)) {
      return FormatImage.bmp;
    }
  }
  return null;
}

/// `true` si les premiers [octets] ressemblent à du texte (HTML, JSON,
/// message d'erreur) plutôt qu'à des données binaires : aucun octet nul, et
/// au plus 10 % de caractères de contrôle ou d'octets UTF-8 invalides.
bool estContenuTexte(List<int> octets) {
  final echantillon = octets.length > _tailleEchantillonTexte
      ? octets.sublist(0, _tailleEchantillonTexte)
      : octets;
  if (echantillon.isEmpty) {
    return true;
  }
  if (echantillon.contains(0)) {
    return false;
  }
  // L'échantillon peut couper un caractère UTF-8 à la fin : au plus un
  // caractère de remplacement de trop, sans effet sur la proportion.
  final texte = utf8.decode(echantillon, allowMalformed: true);
  var illisibles = 0;
  for (final code in texte.runes) {
    if (!_estCaractereLisible(code) &&
        code != 0x09 &&
        code != 0x0A &&
        code != 0x0D &&
        code != 0x0C) {
      illisibles++;
    }
  }
  return illisibles <= texte.runes.length * _partMaxCaracteresIllisibles;
}

/// `true` si les premiers [octets] sont une page HTML (`<!doctype html`,
/// `<html`, `<head` ou `<body` au début, espaces et BOM ignorés) : page
/// anti-robot ou d'erreur servie à la place d'une image (journal des
/// erreurs, E10).
bool estContenuHtml(List<int> octets) {
  if (!estContenuTexte(octets)) {
    return false;
  }
  final echantillon = octets.length > _tailleEchantillonTexte
      ? octets.sublist(0, _tailleEchantillonTexte)
      : octets;
  final debut = utf8
      .decode(echantillon, allowMalformed: true)
      // Marque d'ordre des octets (BOM, U+FEFF) en tête de page.
      .replaceFirst(String.fromCharCode(0xFEFF), '')
      .trimLeft()
      .toLowerCase();
  return debut.startsWith('<!doctype html') ||
      debut.startsWith('<html') ||
      debut.startsWith('<head') ||
      debut.startsWith('<body') ||
      // Commentaire ou balise <meta> avant <html> : on cherche la balise
      // dans le début de la page.
      (debut.startsWith('<') && debut.contains('<html'));
}

/// Extrait court et lisible du début de [octets] pour un message d'erreur :
/// au plus [longueur] caractères imprimables, données personnelles masquées
/// (`extraireDebutReponse`). `null` si la réponse est binaire ou vide :
/// des octets binaires ne doivent jamais apparaître dans un message.
String? extraitTexteImprimable(
  List<int> octets, {
  int longueur = longueurMaxExtraitMessageImage,
}) {
  if (octets.isEmpty || !estContenuTexte(octets)) {
    return null;
  }
  final echantillon = octets.length > _tailleEchantillonTexte
      ? octets.sublist(0, _tailleEchantillonTexte)
      : octets;
  final texte = utf8.decode(echantillon, allowMalformed: true);
  // Filet de sécurité : les rares caractères de contrôle ou de remplacement
  // tolérés par [estContenuTexte] sont retirés avant la citation.
  final propre = String.fromCharCodes(texte.runes.where(_estCaractereLisible));
  final extrait = extraireDebutReponse(propre, longueur: longueur);
  return extrait.isEmpty ? null : extrait;
}

/// Description courte, en français, d'un contenu qui n'est pas une image
/// reconnue : « page HTML », « texte » ou « données binaires non
/// reconnues ».
String decrireContenuNonImage(List<int> octets) {
  if (octets.isEmpty) {
    return 'réponse vide';
  }
  if (estContenuHtml(octets)) {
    return 'page HTML';
  }
  if (estContenuTexte(octets)) {
    return 'texte';
  }
  return 'données binaires non reconnues';
}

/// `true` si [code] est un caractère imprimable (espace compris) : ni
/// contrôle C0/C1, ni DEL,
/// ni caractère de remplacement (octets UTF-8 invalides).
bool _estCaractereLisible(int code) =>
    code >= 0x20 &&
    code != 0x7F &&
    !(code >= 0x80 && code <= 0x9F) &&
    code != 0xFFFD;

/// Texte ASCII de [longueur] octets à partir de [debut] (les octets non
/// ASCII deviennent « ? », sans risque d'exception).
String _texteAscii(List<int> octets, int debut, int longueur) =>
    String.fromCharCodes(
      octets.sublist(debut, debut + longueur).map((o) => o < 0x80 ? o : 0x3F),
    );
