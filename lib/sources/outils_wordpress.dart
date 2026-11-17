/// Outils communs aux adaptateurs des thèmes WordPress de lecture en ligne
/// (`SourceMadara`, `SourceMangaThemesia`, tâche W2).
///
/// Ces thèmes sont installés sur des centaines de sites qui en modifient
/// chacun un peu le gabarit : les fonctions ci-dessous lisent les variantes
/// courantes (images chargées en différé, dates relatives, langue de la page)
/// sans rien supposer d'un site particulier.
library;

import 'package:html/dom.dart' show Document, Element, Text;

import '../modeles/source.dart';
import '../modeles/titre.dart';
import 'erreur_source.dart';
import 'outils_sources.dart';
import 'rapport_erreur_source.dart';

/// Fonctions d'analyse partagées par les adaptateurs de thèmes WordPress.
abstract final class OutilsWordPress {
  /// Attributs qui portent l'adresse réelle d'une image, par ordre de
  /// préférence. Les thèmes chargent leurs images en différé (lazysizes,
  /// WP Rocket, Cloudflare…) : `src` ne contient alors qu'une image d'attente
  /// et l'adresse réelle est dans un attribut `data-…`.
  static const List<String> _attributsImage = <String>[
    'data-src',
    'data-lazy-src',
    'data-cfsrc',
    'data-original',
    'src',
  ];

  /// Morceaux d'adresse des images d'attente connues (Madara :
  /// `themes/madara/images/dflazy.jpg` ; MangaThemesia :
  /// `assets/img/readerarea.svg`), jamais prises pour une vraie image.
  static const List<String> _imagesAttente = <String>[
    'dflazy.',
    'readerarea.svg',
  ];

  /// Regroupe les espaces (sauts de ligne compris) et retire ceux des bords.
  static String nettoyer(String texte) =>
      texte.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Texte propre de [element] : ses nœuds texte directs, sans le texte de
  /// ses éléments enfants (badges « HOT » / « NEW » d'un titre, icônes).
  static String texteDirect(Element element) {
    final tampon = StringBuffer();
    for (final noeud in element.nodes) {
      if (noeud is Text) {
        tampon.write(noeud.text);
      }
    }
    return tampon.toString();
  }

  /// Texte d'un bloc de résumé : un paragraphe `<p>` par ligne, ou le texte
  /// entier du bloc s'il n'a pas de paragraphe.
  static String texteParagraphes(Element bloc) {
    final paragraphes = bloc
        .querySelectorAll('p')
        .map((p) => nettoyer(p.text))
        .where((ligne) => ligne.isNotEmpty)
        .toList();
    return paragraphes.isEmpty ? nettoyer(bloc.text) : paragraphes.join('\n');
  }

  /// Adresse absolue de l'image [image] (résolue depuis [base]), ou `null`.
  ///
  /// Lit d'abord les attributs de chargement différé ([_attributsImage]),
  /// puis le premier candidat de `data-srcset` / `srcset`. Les adresses
  /// `data:` (image d'attente en ligne) et les images d'attente connues sont
  /// ignorées. Les espaces autour de l'adresse sont retirés : Madara écrit
  /// `data-src=" https://…"`.
  static String? adresseImage(Element image, Uri base) {
    final candidats = <String?>[
      for (final attribut in _attributsImage) image.attributes[attribut],
      _premierDeSrcset(image.attributes['data-srcset']),
      _premierDeSrcset(image.attributes['srcset']),
    ];
    for (final candidat in candidats) {
      final lien = candidat?.trim() ?? '';
      if (lien.isEmpty || lien.startsWith('data:')) {
        continue;
      }
      if (_imagesAttente.any(lien.contains)) {
        continue;
      }
      try {
        return base.resolve(lien).toString();
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// Premier candidat d'un attribut `srcset` (`"url 193w, url2 125w"`).
  static String? _premierDeSrcset(String? srcset) {
    final premier = srcset?.split(',').first.trim() ?? '';
    if (premier.isEmpty) {
      return null;
    }
    return premier.split(RegExp(r'\s+')).first;
  }

  /// Contenu de la balise meta [selecteur] (`content`), ou `null`.
  static String? meta(Document document, String selecteur) {
    final valeur = document.querySelector(selecteur)?.attributes['content'];
    final propre = valeur?.trim() ?? '';
    return propre.isEmpty ? null : propre;
  }

  /// Nom du titre lu dans la balise `<title>` (« Nom – Site » ou
  /// « Nom | Site ») quand le gabarit n'a pas de titre reconnu.
  static String nomDepuisTitrePage(Document document) {
    final titre = nettoyer(document.querySelector('title')?.text ?? '');
    for (final separateur in <String>[' – ', ' - ', ' | ']) {
      final fin = titre.lastIndexOf(separateur);
      if (fin > 0) {
        return titre.substring(0, fin).trim();
      }
    }
    return titre;
  }

  /// Langue des chapitres d'un site : l'attribut `lang` de la page
  /// (`<html lang="en-US">` → `en`), que WordPress règle d'après la langue
  /// du site. À défaut, la première langue de [preference] (« fr,en » →
  /// `fr`), puis une chaîne vide (langue inconnue).
  ///
  /// LIMITE : un site qui publie dans une autre langue que celle réglée dans
  /// WordPress (traductions anglaises sur un WordPress en indonésien…) a des
  /// chapitres mal étiquetés ; le réglage de langue du site dans
  /// l'application ne change pas cette valeur.
  static String langueDepuisPage(Document document, String preference) {
    final lang = (document.querySelector('html')?.attributes['lang'] ?? '')
        .trim()
        .toLowerCase();
    final code = RegExp(r'^([a-z]{2})(?:[-_]|$)').firstMatch(lang)?.group(1);
    if (code != null) {
      return code;
    }
    for (final morceau in preference.split(',')) {
      final propre = morceau.trim().toLowerCase();
      if (RegExp(r'^[a-z]{2}').hasMatch(propre)) {
        return propre.substring(0, 2);
      }
    }
    return '';
  }

  /// Type du titre d'après un texte du site (« Manhwa », « Manga »,
  /// « Light Novel », « Comic »…) ; [TypeTitre.autre] si aucun mot connu.
  static TypeTitre typeDepuisTexte(String? texte) {
    final t = (texte ?? '').toLowerCase();
    if (t.contains('manhwa')) {
      return TypeTitre.manhwa;
    }
    if (t.contains('manhua')) {
      return TypeTitre.manhua;
    }
    if (t.contains('novel') || t.contains('roman')) {
      return TypeTitre.roman;
    }
    if (RegExp(r'\bmanga\b').hasMatch(t)) {
      return TypeTitre.manga;
    }
    return TypeTitre.autre;
  }

  /// Sépare une liste de noms (titres alternatifs, auteurs) écrite sur une
  /// ligne : virgules, points-virgules, barres verticales ou « / » entourée
  /// d'espaces. Les noms vides, « - » et « N/A » sont écartés.
  static List<String> separerNoms(String texte) {
    final noms = <String>[];
    for (final morceau in texte.split(RegExp(r'[,;|\n]|\s/\s'))) {
      final propre = nettoyer(morceau);
      if (propre.isEmpty ||
          propre == '-' ||
          propre.toLowerCase() == 'n/a' ||
          noms.contains(propre)) {
        continue;
      }
      noms.add(propre);
    }
    return noms;
  }

  /// Numéro d'un chapitre : d'abord après « Chapter », « Chapitre », « Ch. »,
  /// « Episode »… dans son [nom], puis le premier nombre du nom, puis
  /// « chapter-12-5 » dans son [adresse] ; 0 si aucun (oneshot, prologue).
  static double numeroChapitre(String nom, Uri adresse) {
    final dansNom = RegExp(
      r'(?:chap(?:ter|itre)?|ch|episode|[ée]pisode|ep)\.?\s*(\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    ).firstMatch(nom);
    if (dansNom != null) {
      return OutilsSources.convertirNumero(dansNom.group(1));
    }
    if (RegExp(r'\d').hasMatch(nom)) {
      return OutilsSources.convertirNumero(nom);
    }
    final segments = adresse.pathSegments.where((s) => s.isNotEmpty);
    final dernier = segments.isEmpty ? '' : segments.last;
    final dansAdresse = RegExp(
      r'chap[a-z]*[-_](\d+)(?:[-_.](\d+))?(?=[-_]|$)',
      caseSensitive: false,
    ).firstMatch(dernier);
    if (dansAdresse != null) {
      final decimale = dansAdresse.group(2);
      return OutilsSources.convertirNumero(
        decimale == null
            ? dansAdresse.group(1)
            : '${dansAdresse.group(1)}.$decimale',
      );
    }
    return 0;
  }

  /// Unités des dates relatives (« 2 days ago », « il y a 3 heures »).
  static const Map<String, Duration> _unitesRelatives = <String, Duration>{
    'sec': Duration(seconds: 1),
    'second': Duration(seconds: 1),
    'seconde': Duration(seconds: 1),
    'min': Duration(minutes: 1),
    'minute': Duration(minutes: 1),
    'mins': Duration(minutes: 1),
    'hour': Duration(hours: 1),
    'heure': Duration(hours: 1),
    'h': Duration(hours: 1),
    'day': Duration(days: 1),
    'jour': Duration(days: 1),
    'week': Duration(days: 7),
    'semaine': Duration(days: 7),
    'month': Duration(days: 30),
    'mois': Duration(days: 30),
    'year': Duration(days: 365),
    'an': Duration(days: 365),
    'année': Duration(days: 365),
  };

  /// Date de parution d'un chapitre telle qu'affichée par le thème, ou
  /// `null` si le format n'est pas reconnu.
  ///
  /// Formats lus : « October 11, 2017 » / « 13 nov. 2026 » (voir
  /// `OutilsSources.convertirDateAvecMois`), « 2017-10-11 », « 11/10/2017 »
  /// (jour d'abord), et les dates relatives des chapitres récents (« 2 days
  /// ago », « il y a 3 heures », « yesterday », « hier »), calculées depuis
  /// [maintenant]. Une date relative est approchée (un mois = 30 jours).
  ///
  /// Une date qui n'existe pas (31/02) ou une date relative de plus de
  /// [_plafondDateRelative] (« 300000 years ago », texte abîmé) donne `null`
  /// et ne lève jamais d'exception.
  ///
  /// LIMITE : les noms de mois et les dates relatives ne sont lus qu'en
  /// anglais et en français.
  static DateTime? convertirDate(String texte, DateTime maintenant) {
    final propre = nettoyer(texte).toLowerCase();
    if (propre.isEmpty) {
      return null;
    }
    final absolue = OutilsSources.convertirDateAvecMois(propre);
    if (absolue != null) {
      return absolue;
    }
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(propre);
    if (iso != null) {
      return OutilsSources.dateValide(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final barres = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(propre);
    if (barres != null) {
      return OutilsSources.dateValide(
        int.parse(barres.group(3)!),
        int.parse(barres.group(2)!),
        int.parse(barres.group(1)!),
      );
    }
    if (propre == 'yesterday' || propre == 'hier') {
      return maintenant.toUtc().subtract(const Duration(days: 1));
    }
    if (propre == 'today' || propre == "aujourd'hui" || propre == 'just now') {
      return maintenant.toUtc();
    }
    final relative = RegExp(
      r'^(?:il y a\s+)?(\d+|an?|une?)\s+([a-zé]+?)s?\.?(?:\s+ago)?$',
    ).firstMatch(propre);
    if (relative != null &&
        (propre.endsWith('ago') || propre.startsWith('il y a'))) {
      // Le motif est paresseux : « mois » arrive en « moi » + « s ».
      final mot = relative.group(2)!;
      final unite = _unitesRelatives[mot] ?? _unitesRelatives['${mot}s'];
      final nombre = relative.group(1)!;
      final estChiffre = RegExp(r'^\d+$').hasMatch(nombre);
      // « a day ago », « une heure » : quantité 1. Un nombre trop long pour
      // un int (`tryParse` → null) n'est pas pris pour 1.
      final quantite = estChiffre ? int.tryParse(nombre) : 1;
      if (unite != null && quantite != null) {
        // Plafond comparé en secondes AVANT la multiplication : un
        // `Duration` trop grand déborde, et `subtract` lève une
        // ArgumentError hors de la plage de `DateTime`.
        final maximum = _plafondDateRelative.inSeconds ~/ unite.inSeconds;
        if (quantite > maximum) {
          return null;
        }
        return maintenant.toUtc().subtract(unite * quantite);
      }
    }
    return null;
  }

  /// Ancienneté maximale acceptée pour une date relative : au-delà, le texte
  /// est jugé abîmé et la date est ignorée.
  static const Duration _plafondDateRelative = Duration(days: 365 * 100);

  /// Valide l'adresse [url] d'une page d'un site WordPress (titre ou
  /// chapitre) : `http`/`https`, un hôte et au moins un segment de chemin.
  /// Le fragment (`#…`) est retiré. Lève une [ErreurSource] portant [type]
  /// sinon.
  static Uri validerUrlPage(String url, TypeSource type, String attendu) {
    final uri = Uri.tryParse(url.trim());
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.pathSegments.any((s) => s.isNotEmpty)) {
      return uri.removeFragment();
    }
    throw ErreurSource(url, 'Adresse invalide : $attendu', typeDetecte: type);
  }

  /// Racine du site de [adresse] (`https://hote/`), envoyée comme `Referer`
  /// des images : c'est ce que fait le navigateur d'un lecteur du site.
  static String racineSite(Uri adresse) => Uri(
    scheme: adresse.scheme,
    host: adresse.host,
    port: adresse.hasPort ? adresse.port : null,
    path: '/',
  ).toString();

  /// Exécute l'analyse [action] et ajoute à toute [ErreurSource] le début
  /// nettoyé de la page reçue ([html]), pour le rapport d'erreur.
  static T avecExtrait<T>(String html, T Function() action) {
    try {
      return action();
    } on ErreurSource catch (erreur, pile) {
      Error.throwWithStackTrace(
        erreur.avecContexte(extraitReponse: extraireDebutReponse(html)),
        pile,
      );
    }
  }

  /// Exécute [action] et complète toute [ErreurSource] levée avec le [type]
  /// de site, sans perdre la pile d'appels d'origine.
  static Future<T> avecType<T>(
    TypeSource type,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ErreurSource catch (erreur, pile) {
      Error.throwWithStackTrace(erreur.avecContexte(typeDetecte: type), pile);
    }
  }
}
