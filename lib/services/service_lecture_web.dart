/// Lecture dans le navigateur intégré (tâche N3, décision du client du
/// 2026-11-19) : reconnaître le chapitre affiché, le marquer lu quand le
/// client passe au suivant, et enregistrer en archive les images qu'il a
/// sous les yeux.
///
/// Règles (PLAYBOOK.md section 10) : le navigateur n'est jamais utilisé de
/// façon cachée ni automatique pour lire une liste ou télécharger ; ce
/// service ne fait **aucune requête réseau**. Il ne reçoit que des images
/// ordinaires déjà affichées, fournies par l'interface à la demande du
/// client (« Enregistrer ce chapitre »), et refuse toute page en canvas ou
/// chiffrée : jamais de décodage ni de déchiffrement.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../donnees/depot_chapitres.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../donnees/depot_titres_sources.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/chapitre.dart';
import '../modeles/journal.dart';
import '../modeles/lien_titre_source.dart';
import '../modeles/source.dart';
import '../sources/constantes_sources.dart';
import '../sources/detection_image.dart';
import '../sources/erreur_source.dart';
import '../sources/outils_sources.dart';
import '../sources/source_generique.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'service_ajout_site.dart';
import 'service_bibliotheque.dart';
import 'service_telechargement.dart';

/// Espacement minimal entre deux requêtes d'image que l'interface refait
/// elle-même vers un même domaine, depuis la page du navigateur intégré,
/// pour obtenir les octets d'une image affichée.
///
/// L'interface lit d'abord le cache du navigateur
/// (`fetch(url, {cache: 'force-cache'})`) : l'image déjà affichée n'est
/// alors pas redemandée au site. Si le site doit tout de même être
/// interrogé, les requêtes vers un même domaine sont espacées d'au moins
/// cette durée : même règle que `ClientHttpPoli` (PLAYBOOK.md section 6).
const Duration delaiRequetesImagesNavigateur = delaiMinimalParDomaine;

/// Message affiché quand le site protège ses images (canvas, images
/// chiffrées ou brouillées) : elles ne sont jamais enregistrées.
const String messageImagesProtegees =
    'Ce site protège ses images : elles ne peuvent pas être enregistrées.';

/// Image d'une page de chapitre, telle que l'interface l'a récupérée dans le
/// navigateur intégré (octets décodés du base64), dans l'ordre de lecture.
class ImageRecue {
  /// Crée une image reçue.
  const ImageRecue(this.octets, {this.adresse, this.estProtegee = false});

  /// Octets de l'image, tels que servis par le site.
  final List<int> octets;

  /// Adresse de l'image dans la page, si connue (sert seulement au journal,
  /// réduite à son domaine).
  final String? adresse;

  /// `true` si l'interface a vu que cette page est dessinée dans un
  /// `canvas` ou chiffrée (pas une image ordinaire) : l'enregistrement est
  /// alors refusé ([messageImagesProtegees]).
  final bool estProtegee;
}

/// Résultat de [ServiceLectureWeb.reconnaitreChapitre] : soit un chapitre
/// déjà en base ([ChapitreConnu]), soit un chapitre que l'on peut
/// enregistrer depuis le web ([ChapitreWebPossible]).
sealed class ChapitreReconnu {
  const ChapitreReconnu();

  /// Titre de la bibliothèque auquel appartient le chapitre.
  int get idTitre;

  /// Numéro du chapitre (`10.5` pour un chapitre intermédiaire).
  double get numero;
}

/// Chapitre déjà enregistré, reconnu par son adresse (`url_chapitre` ou
/// `url_externe`, sans fragment ni `/` final).
final class ChapitreConnu extends ChapitreReconnu {
  /// Crée le résultat pour [chapitre] (lu en base, donc avec un `id`).
  const ChapitreConnu(this.chapitre);

  /// Chapitre tel qu'en base (état lu, archive…).
  final Chapitre chapitre;

  @override
  int get idTitre => chapitre.idTitre!;

  @override
  double get numero => chapitre.numero;

  @override
  String toString() => 'ChapitreConnu(${chapitre.id}, n°$numero)';
}

/// Chapitre pas encore en base, mais dont l'adresse appartient à un site lié
/// à un titre de la bibliothèque (lien seul compris) et contient un numéro
/// de chapitre : [ServiceLectureWeb.noterChapitreAffiche] peut l'enregistrer
/// (`OrigineChapitre.web`).
final class ChapitreWebPossible extends ChapitreReconnu {
  /// Crée le résultat.
  const ChapitreWebPossible({
    required this.idTitre,
    required this.idSource,
    required this.numero,
    required this.url,
    required this.estLienSeul,
  });

  @override
  final int idTitre;

  /// Site (source) du titre auquel appartient l'adresse.
  final int idSource;

  @override
  final double numero;

  /// Adresse du chapitre, normalisée ([normaliserUrlChapitre]).
  final String url;

  /// `true` si ce site est un « lien seul » du titre (l'application ne sait
  /// pas le lire) : c'est le cas où le chapitre web sert le plus.
  final bool estLienSeul;

  @override
  String toString() =>
      'ChapitreWebPossible(titre $idTitre, source $idSource, n°$numero)';
}

/// Lien d'un titre vers un site, avec la source correspondante.
typedef _LienAvecSource = ({LienTitreSource lien, Source source});

/// Logique métier du navigateur intégré : reconnaissance du chapitre
/// affiché, suivi de lecture et enregistrement des images affichées.
///
/// Ne fait aucune requête réseau : tout ce qu'il reçoit vient de la page
/// que le client a lui-même ouverte.
class ServiceLectureWeb {
  /// Crée le service.
  ///
  /// [serviceTelechargement] : règles de téléchargement appliquées au titre
  /// quand le client passe au chapitre suivant ([quitterChapitre]), comme
  /// dans le lecteur.
  ///
  /// [estRedemarrageNecessaire] : renvoie `true` si le dossier des chapitres
  /// a été changé pendant la session
  /// (`ServiceDossierChapitres.redemarrageNecessaire`) ; l'enregistrement
  /// d'images est alors refusé, comme la file de téléchargement est en
  /// pause (l'archive serait écrite dans l'ancien dossier). Facultatif et
  /// redondant : [serviceTelechargement] fait déjà ce contrôle (avec le
  /// changement en cours) dans `executerEnregistrementWeb` ; gardé pour
  /// les appelants existants.
  ServiceLectureWeb({
    required DepotChapitres depotChapitres,
    required DepotTitres depotTitres,
    required DepotTitresSources depotTitresSources,
    required DepotSources depotSources,
    required StockageTelechargements stockage,
    required ServiceTelechargement serviceTelechargement,
    bool Function()? estRedemarrageNecessaire,
  }) : _depotChapitres = depotChapitres,
       _depotTitres = depotTitres,
       _depotTitresSources = depotTitresSources,
       _depotSources = depotSources,
       _stockage = stockage,
       _serviceTelechargement = serviceTelechargement,
       _estRedemarrageNecessaire = estRedemarrageNecessaire;

  final DepotChapitres _depotChapitres;
  final DepotTitres _depotTitres;
  final DepotTitresSources _depotTitresSources;
  final DepotSources _depotSources;
  final StockageTelechargements _stockage;
  final ServiceTelechargement _serviceTelechargement;
  final bool Function()? _estRedemarrageNecessaire;

  /// Enregistrements de chapitres web en cours, par adresse (et titre) :
  /// la page peut signaler plusieurs fois la même adresse pendant son
  /// chargement ; un second appel reçoit le même résultat.
  final Map<String, Future<Chapitre?>> _notesEnCours =
      <String, Future<Chapitre?>>{};

  /// Marquages « lu » en cours, par chapitre quitté.
  final Map<int, Future<bool>> _sortiesEnCours = <int, Future<bool>>{};

  /// Enregistrements d'archives en cours, par chapitre (double clic sur
  /// « Enregistrer ce chapitre »).
  final Map<int, Future<Chapitre>> _enregistrementsEnCours =
      <int, Future<Chapitre>>{};

  // ---------------------------------------------------------------------
  // 1. Reconnaissance du chapitre affiché
  // ---------------------------------------------------------------------

  /// Reconnaît le chapitre affiché à l'adresse [url], ou renvoie `null`.
  ///
  /// 1. Chapitre déjà en base dont l'adresse correspond (sans fragment ni
  ///    `/` final) : [ChapitreConnu]. Avec [idTitre] (navigateur ouvert
  ///    depuis la fiche d'un titre), les chapitres de ce titre sont cherchés
  ///    d'abord, puis tous les autres.
  /// 2. Sinon, si l'adresse appartient à un site lié à un titre de la
  ///    bibliothèque (lien seul compris) et contient un numéro de chapitre
  ///    ([extraireNumeroChapitre]) : [ChapitreWebPossible].
  ///
  /// Attribution à un titre (étape 2) : un site peut porter plusieurs titres
  /// de la bibliothèque. L'adresse est attribuée au titre dont l'adresse
  /// sur ce site la « contient » ([evaluerCorrespondanceTitre] : même début
  /// de chemin, ou identifiant lisible `solo-leveling` présent). Avec
  /// [idTitre], ce titre est retenu si l'adresse ne désigne pas clairement
  /// un **autre** titre du même site ; sans [idTitre], il faut un seul titre
  /// qui corresponde clairement, sinon `null` (mieux vaut ne rien noter que
  /// noter un chapitre sous la mauvaise œuvre).
  ///
  /// Ne lève jamais d'erreur (appelé à chaque page) : une erreur de base est
  /// journalisée et donne `null`.
  Future<ChapitreReconnu?> reconnaitreChapitre(
    String url, {
    int? idTitre,
  }) async {
    try {
      return await _reconnaitre(url, idTitre: idTitre);
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.bibliotheque,
        'Navigateur : reconnaissance du chapitre impossible '
        '(${_hoteJournal(url)})',
        erreur: erreur,
        pile: pile,
      );
      return null;
    }
  }

  Future<ChapitreReconnu?> _reconnaitre(String url, {int? idTitre}) async {
    final adresse = normaliserUrlChapitre(url);
    final uri = Uri.tryParse(adresse);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }

    // 1. Chapitre déjà connu par son adresse.
    var connu = idTitre == null
        ? null
        : await _depotChapitres.chargerChapitreParUrl(
            adresse,
            idTitre: idTitre,
          );
    connu ??= await _depotChapitres.chargerChapitreParUrl(adresse);
    if (connu != null && connu.id != null && connu.idTitre != null) {
      return ChapitreConnu(connu);
    }

    // 2. Site d'un titre de la bibliothèque.
    final hote = ServiceAjoutSite.proposerNom(uri);
    final sources = <int, Source>{
      for (final source in await _depotSources.chargerSources())
        if (source.id != null) source.id!: source,
    };
    // Aucun site configuré sur ce domaine : inutile de parcourir les titres.
    final sitesDuDomaine = <int>{
      for (final source in sources.values)
        if (_hoteComparable(source.urlBase) == hote) source.id!,
    };
    if (sitesDuDomaine.isEmpty) {
      return null;
    }
    bool estDuSite(LienTitreSource lien) =>
        sitesDuDomaine.contains(lien.idSource) ||
        _hoteComparable(lien.urlTitre) == hote;

    final retenu = await _choisirLien(
      adresse,
      idTitre: idTitre,
      sources: sources,
      estDuSite: estDuSite,
    );
    if (retenu == null) {
      return null;
    }
    final numero = extraireNumeroChapitre(
      adresse,
      motifNumeroChapitre: _motifDuSite(retenu.source),
    );
    if (numero == null) {
      return null;
    }
    return ChapitreWebPossible(
      idTitre: retenu.lien.idTitre,
      idSource: retenu.lien.idSource,
      numero: numero,
      url: adresse,
      estLienSeul: retenu.lien.estLienSeul,
    );
  }

  /// Choisit le lien titre ↔ site auquel attribuer [adresse] (voir
  /// [reconnaitreChapitre]), ou `null`.
  Future<_LienAvecSource?> _choisirLien(
    String adresse, {
    required int? idTitre,
    required Map<int, Source> sources,
    required bool Function(LienTitreSource) estDuSite,
  }) async {
    _LienAvecSource? avecSource(LienTitreSource lien) {
      final source = sources[lien.idSource];
      return source == null ? null : (lien: lien, source: source);
    }

    // Page de la fiche d'un titre : ce n'est pas un chapitre.
    bool estFiche(LienTitreSource lien) =>
        normaliserUrlChapitre(lien.urlTitre) == adresse;

    if (idTitre != null) {
      final liensTitre = <LienTitreSource>[
        for (final lien in await _depotTitresSources.chargerLiensTitre(idTitre))
          if (estDuSite(lien)) lien,
      ];
      if (liensTitre.any(estFiche)) {
        return null;
      }
      if (liensTitre.isNotEmpty) {
        // Correspondance claire avec ce titre : retenu sans chercher plus.
        for (final lien in liensTitre) {
          if (evaluerCorrespondanceTitre(adresse, lien.urlTitre) > 0) {
            return avecSource(lien);
          }
        }
        // Sinon, l'adresse désigne peut-être une autre œuvre du même site
        // (le client a suivi un lien dans la page) : elle est attribuée à
        // cette œuvre si elle seule correspond clairement.
        final autre = await _meilleurLienDuSite(
          adresse,
          estDuSite: estDuSite,
          exclureTitre: idTitre,
        );
        if (autre != null) {
          return avecSource(autre);
        }
        // Repli sur le titre depuis lequel le navigateur a été ouvert
        // seulement si l'adresse ne nomme aucune œuvre (`/chapter/4815162`).
        // Une adresse qui en nomme une autre (`/manga/one-piece/chapter-3`,
        // œuvre absente de la bibliothèque) n'est pas notée : le chapitre
        // serait sinon marqué lu sous la mauvaise œuvre.
        // LIMITE : une autre œuvre de ce site dont l'adresse ne contient
        // aucun nom lisible serait encore notée sous ce titre.
        final identifiants = <String>{
          for (final lien in liensTitre)
            ?_identifiantLisibleTitre(lien.urlTitre),
        };
        final autresMorceaux = morceauxLisiblesChemin(adresse)
            .where((morceau) => !identifiants.contains(morceau));
        if (autresMorceaux.isNotEmpty) {
          return null;
        }
        return avecSource(liensTitre.first);
      }
      // Ce titre n'a pas ce site : recherche parmi tous les titres.
    }
    final lien = await _meilleurLienDuSite(adresse, estDuSite: estDuSite);
    return lien == null ? null : avecSource(lien);
  }

  /// Lien (d'un titre de la bibliothèque, sur ce site) qui correspond le
  /// mieux à [adresse], s'il est le seul à ce niveau ; `null` si aucun ne
  /// correspond, si plusieurs titres sont à égalité, ou si [adresse] est la
  /// fiche d'un titre.
  ///
  /// LIMITE : `DepotTitresSources` n'offre pas de lecture des liens par
  /// site ; les liens de chaque titre sont donc lus un par un (une requête
  /// par titre, quelques centaines au plus). Fait seulement quand un site
  /// configuré porte ce domaine.
  Future<LienTitreSource?> _meilleurLienDuSite(
    String adresse, {
    required bool Function(LienTitreSource) estDuSite,
    int? exclureTitre,
  }) async {
    var meilleurScore = 0;
    final meilleurs = <LienTitreSource>[];
    for (final titre in await _depotTitres.chargerTitres()) {
      final id = titre.id;
      if (id == null || id == exclureTitre) continue;
      for (final lien in await _depotTitresSources.chargerLiensTitre(id)) {
        if (!estDuSite(lien)) continue;
        if (normaliserUrlChapitre(lien.urlTitre) == adresse) {
          return null;
        }
        final score = evaluerCorrespondanceTitre(adresse, lien.urlTitre);
        if (score == 0 || score < meilleurScore) continue;
        if (score > meilleurScore) {
          meilleurScore = score;
          meilleurs.clear();
        }
        meilleurs.add(lien);
      }
    }
    final titres = meilleurs.map((l) => l.idTitre).toSet();
    return titres.length == 1 ? meilleurs.first : null;
  }

  /// Motif du numéro de chapitre réglé pour [source] (site générique), ou
  /// `null`. Des réglages illisibles sont ignorés (motif par défaut).
  static String? _motifDuSite(Source source) {
    if (source.typeSource != TypeSource.generique) {
      return null;
    }
    try {
      return ConfigurationGenerique.depuisJson(
        source.configurationSelecteurs,
        url: source.urlBase,
      ).motifNumeroChapitre;
    } on ErreurSource {
      return null;
    }
  }

  /// Motif par défaut du numéro de chapitre dans une adresse : un mot-clé
  /// (`chapitre`, `chapter`, `chap`, `ch`, `episode`, `ep`, au singulier ou
  /// au pluriel), un séparateur facultatif (`-`, `_`, `.`, `/`, `=`, espace)
  /// puis un nombre décimal (`12`, `10.5`, `10,5`). Le mot-clé ne doit pas
  /// être la fin d'un autre mot (`march-12` n'est pas un chapitre).
  ///
  /// Forme `chapter-10-5` (fréquente sur les thèmes WordPress) : un ou deux
  /// chiffres après un `-` ou `_`, en fin de morceau, sont la partie
  /// décimale (10.5) ; un nombre plus long (`chapter-3-1234567`, identifiant)
  /// est ignoré.
  static final RegExp _motifNumeroParDefaut = RegExp(
    r'(?<![a-z])(?:chapitres?|chapters?|chap|ch|[eé]pisodes?|ep)'
    r'[-_./=\s]?(\d+(?:[.,]\d+)?)(?:[-_](\d{1,2}))?(?![a-z\d])',
    caseSensitive: false,
  );

  /// Numéro de chapitre tiré de l'adresse [url], ou `null`.
  ///
  /// Le chemin (décodé) est examiné d'abord, puis les paramètres
  /// (`?chapter=12`) ; la **dernière** correspondance l'emporte (le numéro
  /// suit le nom de l'œuvre : `/kaiju-8/chapter-3`).
  ///
  /// [motifNumeroChapitre] (réglage d'un site générique) est essayé avant le
  /// motif par défaut : son premier groupe, ou tout le texte reconnu, doit
  /// contenir un nombre. Un numéro négatif, non fini ou supérieur à
  /// [numeroMaxChapitreWeb] (identifiant interne plutôt que numéro) est
  /// refusé.
  ///
  /// Fonction pure (ni base ni réseau).
  static double? extraireNumeroChapitre(
    String url, {
    String? motifNumeroChapitre,
  }) {
    final uri = Uri.tryParse(normaliserUrlChapitre(url));
    if (uri == null) {
      return null;
    }
    final morceaux = <String>[_decoder(uri.path), _decoder(uri.query)];
    final motifs = <RegExp>[
      if (motifNumeroChapitre != null && motifNumeroChapitre.trim().isNotEmpty)
        ?_compiler(motifNumeroChapitre),
      _motifNumeroParDefaut,
    ];
    for (final motif in motifs) {
      for (final morceau in morceaux) {
        if (morceau.isEmpty) continue;
        final correspondances = motif.allMatches(morceau).toList();
        if (correspondances.isEmpty) continue;
        final numero = identical(motif, _motifNumeroParDefaut)
            ? _numeroParDefaut(correspondances.last)
            : _numeroMotifRegle(correspondances.last);
        if (numero != null) {
          return numero;
        }
      }
    }
    return null;
  }

  static RegExp? _compiler(String motif) {
    try {
      return RegExp(motif, caseSensitive: false);
    } on FormatException {
      // Réglage invalide : le motif par défaut prend le relais.
      return null;
    }
  }

  static double? _numeroParDefaut(RegExpMatch m) {
    final entier = m.group(1);
    if (entier == null) return null;
    final decimale = m.group(2);
    return _borner(
      OutilsSources.convertirNumero(
        decimale == null ? entier : '$entier.$decimale',
      ),
    );
  }

  static double? _numeroMotifRegle(RegExpMatch m) {
    // `group(1)` lève une RangeError si le motif n'a pas de groupe.
    final texte = (m.groupCount >= 1 ? m.group(1) : null) ?? m.group(0) ?? '';
    // convertirNumero donne 0 sans chiffre : on exige un nombre réel.
    if (!RegExp(r'\d').hasMatch(texte)) {
      return null;
    }
    return _borner(OutilsSources.convertirNumero(texte));
  }

  static double? _borner(double numero) =>
      numero.isFinite && numero >= 0 && numero <= numeroMaxChapitreWeb
      ? numero
      : null;

  /// Degré de correspondance entre l'adresse d'un chapitre [urlChapitre] et
  /// l'adresse d'un titre sur le même site [urlTitre] :
  /// - 2 : le chemin du chapitre commence par celui du titre
  ///   (`/manga/solo-leveling/chapter-3` pour `/manga/solo-leveling/`) ;
  /// - 1 : le chemin du chapitre contient l'identifiant lisible du titre
  ///   (`/solo-leveling-chapter-3/`), c'est-à-dire le plus long morceau du
  ///   chemin du titre qui contient une lettre, fait au moins
  ///   [longueurMinIdentifiantTitreWeb] caractères et n'est pas générique
  ///   ([segmentsGeneriquesAdresseTitre]) ;
  /// - 0 : aucun indice (ou adresse identique à celle du titre).
  ///
  /// Comparaison sans tenir compte de la casse, sur les chemins décodés.
  /// Fonction pure (ni base ni réseau).
  static int evaluerCorrespondanceTitre(String urlChapitre, String urlTitre) {
    final chapitre = Uri.tryParse(normaliserUrlChapitre(urlChapitre));
    final titre = Uri.tryParse(normaliserUrlChapitre(urlTitre));
    if (chapitre == null || titre == null) {
      return 0;
    }
    final cheminChapitre = _decoder(chapitre.path).toLowerCase();
    final cheminTitre = _cheminTitre(titre);
    final segments = _segmentsPropresTitre(cheminTitre);
    if (segments.isEmpty) {
      // Fiche sans morceau propre (`/manga/`, ou paramètres seuls) : aucun
      // indice fiable.
      return 0;
    }
    if (cheminChapitre.startsWith('$cheminTitre/')) {
      return 2;
    }
    final identifiant = _identifiantDesSegments(segments);
    if (identifiant != null && cheminChapitre.contains(identifiant)) {
      return 1;
    }
    return 0;
  }

  /// Chemin décodé, en minuscules et sans `/` final, de l'adresse d'un
  /// titre.
  static String _cheminTitre(Uri titre) {
    var chemin = _decoder(titre.path).toLowerCase();
    while (chemin.endsWith('/')) {
      chemin = chemin.substring(0, chemin.length - 1);
    }
    return chemin;
  }

  /// Morceaux du chemin d'un titre qui ne sont pas génériques
  /// ([segmentsGeneriquesAdresseTitre]).
  static List<String> _segmentsPropresTitre(String cheminTitre) => cheminTitre
      .split('/')
      .where((s) => s.isNotEmpty && !segmentsGeneriquesAdresseTitre.contains(s))
      .toList();

  /// Plus long des [segments] qui contient une lettre et fait au moins
  /// [longueurMinIdentifiantTitreWeb] caractères, ou `null`.
  static String? _identifiantDesSegments(List<String> segments) {
    String? identifiant;
    for (final segment in segments) {
      if (segment.length >= longueurMinIdentifiantTitreWeb &&
          _lettre.hasMatch(segment) &&
          (identifiant == null || segment.length > identifiant.length)) {
        identifiant = segment;
      }
    }
    return identifiant;
  }

  /// Identifiant lisible du titre d'adresse [urlTitre] (voir
  /// [evaluerCorrespondanceTitre]), ou `null`.
  static String? _identifiantLisibleTitre(String urlTitre) {
    final titre = Uri.tryParse(normaliserUrlChapitre(urlTitre));
    if (titre == null) return null;
    return _identifiantDesSegments(_segmentsPropresTitre(_cheminTitre(titre)));
  }

  static final RegExp _lettre = RegExp(r'\p{L}', unicode: true);

  /// Au moins trois lettres de suite : distingue un nom (`one-piece`,
  /// `kaiju-n8`) d'un identifiant interne (`a1b2c3d4`).
  static final RegExp _troisLettres = RegExp(r'\p{L}{3,}', unicode: true);

  /// Identifiant hexadécimal ou UUID (`ef4aae9e-eea8-4931-…`) : jamais un
  /// nom d'œuvre, même s'il contient trois lettres de suite (`eea`).
  static final RegExp _identifiantHexadecimal = RegExp(
    r'^(?=.*\d)[0-9a-f]+(?:[-_][0-9a-f]+)*$',
  );

  /// Extension finale d'un morceau d'adresse (`chapter-3.html`).
  static final RegExp _extensionFinale = RegExp(r'\.(?:html?|php|aspx?|jsp)$');

  /// Séparateurs en début ou en fin d'un morceau, une fois le numéro de
  /// chapitre retiré (`solo-leveling-` → `solo-leveling`).
  static final RegExp _separateursBords = RegExp(r'^[-_.\s]+|[-_.\s]+$');

  /// Mots-clés de chapitre seuls (`/chapter/4815162`) : jamais un nom
  /// d'œuvre.
  static const Set<String> _motsClesChapitre = <String>{
    'chapitre',
    'chapitres',
    'chapter',
    'chapters',
    'chap',
    'episode',
    'episodes',
    'épisode',
    'épisodes',
  };

  /// Morceaux « lisibles » du chemin de [url] : ceux qui peuvent nommer une
  /// œuvre (`one-piece` dans `/manga/one-piece/chapter-3`).
  ///
  /// Pour chaque morceau du chemin (décodé, en minuscules), l'extension
  /// finale (`.html`) et le numéro de chapitre (`chapter-3`,
  /// `solo-leveling-ch-3` → `solo-leveling`) sont retirés ; ce qui reste est
  /// lisible s'il fait au moins [longueurMinIdentifiantTitreWeb] caractères,
  /// contient au moins trois lettres de suite, n'est ni générique
  /// ([segmentsGeneriquesAdresseTitre]), ni un mot-clé de chapitre, ni un
  /// identifiant hexadécimal (UUID).
  ///
  /// Sert à [reconnaitreChapitre] : une adresse sans indice du titre ouvert
  /// ne lui est attribuée que si elle ne nomme aucune autre œuvre. Fonction
  /// pure (ni base ni réseau).
  static List<String> morceauxLisiblesChemin(String url) {
    final uri = Uri.tryParse(normaliserUrlChapitre(url));
    if (uri == null) return const <String>[];
    final morceaux = <String>[];
    for (final segment in _decoder(uri.path).toLowerCase().split('/')) {
      final reste = segment
          .replaceFirst(_extensionFinale, '')
          .replaceAll(_motifNumeroParDefaut, ' ')
          .replaceAll(_separateursBords, '');
      if (reste.length < longueurMinIdentifiantTitreWeb ||
          !_troisLettres.hasMatch(reste) ||
          segmentsGeneriquesAdresseTitre.contains(reste) ||
          _motsClesChapitre.contains(reste) ||
          _identifiantHexadecimal.hasMatch(reste)) {
        continue;
      }
      morceaux.add(reste);
    }
    return morceaux;
  }

  // ---------------------------------------------------------------------
  // 2. Suivi de lecture
  // ---------------------------------------------------------------------

  /// À appeler quand le client arrive sur une page du navigateur intégré :
  /// renvoie le chapitre affiché, en l'enregistrant d'abord comme chapitre
  /// web (`DepotChapitres.enregistrerChapitreWeb`) s'il n'est pas encore en
  /// base ; `null` si la page n'est pas un chapitre reconnu
  /// ([reconnaitreChapitre]).
  ///
  /// [nom] : nom du chapitre si l'interface en connaît un (sinon
  /// « Chapitre 12 »). L'enregistrement est idempotent : un chapitre de même
  /// adresse ou, sur ce site, de même numéro est renvoyé sans modification.
  /// Rien n'est marqué lu ici (voir [quitterChapitre]).
  ///
  /// Un appel répété pour la même adresse pendant l'enregistrement reçoit le
  /// même résultat. Ne lève jamais d'erreur (appelé à chaque page) : une
  /// erreur est journalisée et donne `null`.
  Future<Chapitre?> noterChapitreAffiche(
    String url, {
    int? idTitre,
    String? nom,
  }) {
    final cle = '${idTitre ?? ''}|${normaliserUrlChapitre(url)}';
    final enCours = _notesEnCours[cle];
    if (enCours != null) return enCours;
    final note = _noter(url, idTitre: idTitre, nom: nom).whenComplete(() {
      _notesEnCours.remove(cle);
    });
    _notesEnCours[cle] = note;
    return note;
  }

  Future<Chapitre?> _noter(String url, {int? idTitre, String? nom}) async {
    try {
      final reconnu = await _reconnaitre(url, idTitre: idTitre);
      switch (reconnu) {
        case null:
          return null;
        case ChapitreConnu(:final chapitre):
          return chapitre;
        case final ChapitreWebPossible possible:
          final chapitre = await _depotChapitres.enregistrerChapitreWeb(
            possible.idTitre,
            possible.idSource,
            numero: possible.numero,
            url: possible.url,
            titre: nom,
          );
          Journal.actuel.info(
            CategorieJournal.bibliotheque,
            'Navigateur : chapitre ${_formaterNumero(chapitre.numero)} du '
            'titre n°${possible.idTitre} noté (chapitre n°${chapitre.id}, '
            '${_hoteJournal(url)}'
            '${possible.estLienSeul ? ', lien seul' : ''})',
          );
          return chapitre;
      }
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.bibliotheque,
        'Navigateur : chapitre affiché non noté (${_hoteJournal(url)})',
        erreur: erreur,
        pile: pile,
      );
      return null;
    }
  }

  /// À appeler quand le client quitte [chapitreQuitte] pour
  /// [chapitreSuivant] (le chapitre affiché ensuite, `null` s'il n'en est
  /// pas un).
  ///
  /// Même règle que le lecteur : passer au chapitre de numéro **supérieur**
  /// du **même titre** marque le chapitre quitté comme lu, puis les règles de
  /// téléchargement du titre sont appliquées
  /// (`ServiceTelechargement.appliquerRegles` : la fenêtre des suivis
  /// avance). Revenir en arrière, rester sur le même numéro ou changer de
  /// titre ne marque rien.
  ///
  /// Renvoie `true` si le chapitre quitté est (désormais) lu. Ne lève
  /// jamais d'erreur : un échec est journalisé et donne `false` ; un échec
  /// des règles seules ne change pas le résultat (le marquage est fait).
  Future<bool> quitterChapitre(
    Chapitre chapitreQuitte,
    Chapitre? chapitreSuivant,
  ) {
    final id = chapitreQuitte.id;
    final idTitre = chapitreQuitte.idTitre;
    if (id == null ||
        idTitre == null ||
        chapitreSuivant == null ||
        chapitreSuivant.idTitre != idTitre ||
        chapitreSuivant.id == id ||
        !(chapitreSuivant.numero > chapitreQuitte.numero)) {
      return Future<bool>.value(false);
    }
    final enCours = _sortiesEnCours[id];
    if (enCours != null) return enCours;
    final sortie = _marquerQuitte(id, idTitre).whenComplete(() {
      _sortiesEnCours.remove(id);
    });
    _sortiesEnCours[id] = sortie;
    return sortie;
  }

  Future<bool> _marquerQuitte(int id, int idTitre) async {
    try {
      // Écriture faite même si l'objet reçu dit « lu » : il peut être
      // ancien (le client l'a remis à non lu entre-temps).
      await _depotChapitres.marquerLu(id);
      Journal.actuel.info(
        CategorieJournal.bibliotheque,
        'Navigateur : chapitre n°$id marqué lu (passage au suivant)',
      );
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.bibliotheque,
        'Navigateur : chapitre n°$id non marqué lu',
        erreur: erreur,
        pile: pile,
      );
      return false;
    }
    try {
      await _serviceTelechargement.appliquerRegles(idTitre);
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Navigateur : règles de téléchargement du titre n°$idTitre non '
        'appliquées',
        erreur: erreur,
        pile: pile,
      );
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // 3. Enregistrement des images affichées
  // ---------------------------------------------------------------------

  /// Contrôle les [images] reçues de la page et renvoie le format de
  /// chacune, dans l'ordre ; lève une [ErreurService] au message clair si
  /// l'enregistrement doit être refusé :
  /// - aucune image ;
  /// - [pagesProtegees] (l'interface a vu des pages en `canvas` ou
  ///   chiffrées), une image marquée [ImageRecue.estProtegee], une image
  ///   d'adresse `blob:` ou `data:` (produite par un script de la page, le
  ///   plus souvent une page déchiffrée par l'éditeur) ou servie par un
  ///   domaine de [domainesImagesProtegees] : [messageImagesProtegees] ;
  /// - plus de [nombreMaxImagesChapitreWeb] images ;
  /// - une image vide, plus grande que [tailleMaxImageChapitreWeb], ou qui
  ///   n'est pas une image reconnue par ses octets (`detecterFormatImage` :
  ///   JPEG, PNG, GIF, WEBP, AVIF, HEIF, BMP) ;
  /// - un total au-delà de [tailleMaxTotaleChapitreWeb].
  ///
  /// Aucun décodage : seuls les premiers octets sont examinés. Fonction pure.
  static List<FormatImage> validerImagesChapitre(
    List<ImageRecue> images, {
    bool pagesProtegees = false,
  }) {
    if (pagesProtegees ||
        images.any(
          (image) => image.estProtegee || _estAdresseImageProtegee(image),
        )) {
      throw const ErreurService(messageImagesProtegees);
    }
    if (images.isEmpty) {
      throw const ErreurService(
        "Aucune image n'a été trouvée sur cette page : rien à enregistrer.",
      );
    }
    if (images.length > nombreMaxImagesChapitreWeb) {
      throw ErreurService(
        'Cette page contient ${images.length} images, au plus '
        '$nombreMaxImagesChapitreWeb par chapitre : ce n\'est sans doute pas '
        'un seul chapitre.',
      );
    }
    final formats = <FormatImage>[];
    var total = 0;
    for (var index = 0; index < images.length; index++) {
      final octets = images[index].octets;
      final page = index + 1;
      if (octets.isEmpty) {
        throw ErreurService("L'image de la page $page est vide.");
      }
      if (octets.length > tailleMaxImageChapitreWeb) {
        throw ErreurService(
          "L'image de la page $page est trop grande "
          '(${_formaterMo(octets.length)}, au plus '
          '${_formaterMo(tailleMaxImageChapitreWeb)}).',
        );
      }
      final format = detecterFormatImage(octets);
      if (format == null) {
        throw ErreurService(
          "La page $page n'est pas une image reconnue "
          '(${decrireContenuNonImage(octets)}) : le chapitre ne peut pas être '
          'enregistré.',
        );
      }
      total += octets.length;
      if (total > tailleMaxTotaleChapitreWeb) {
        throw ErreurService(
          'Les images de ce chapitre sont trop lourdes (plus de '
          '${_formaterMo(tailleMaxTotaleChapitreWeb)}).',
        );
      }
      formats.add(format);
    }
    return formats;
  }

  /// Enregistre les [images] affichées du [chapitre] (dans l'ordre de
  /// lecture) en archive `.zip`, puis le marque téléchargé ; renvoie le
  /// chapitre tel qu'en base.
  ///
  /// Geste manuel du client (« Enregistrer ce chapitre »), toujours
  /// proposé : les images sont d'abord contrôlées ([validerImagesChapitre])
  /// et rien n'est écrit si l'une est refusée. Un site dont les images sont
  /// connues pour être brouillées ([domainesImagesProtegees], par exemple
  /// MANGA Plus), pour le chapitre ou pour l'une des images, est refusé
  /// même si les octets ressemblent à des images.
  ///
  /// Refusé aussi pendant un changement du dossier des chapitres (en cours,
  /// file en pause pour lui, déplacement inachevé) et jusqu'au redémarrage
  /// qui suit un changement : voir
  /// `ServiceTelechargement.executerEnregistrementWeb`. Pendant l'écriture,
  /// un changement de dossier avec déplacement est refusé à son tour.
  ///
  /// L'archive a le même format et le même nom que celles de la file de
  /// téléchargement (`StockageTelechargements.ouvrirEcriture` : pages
  /// `img1.jpg`…, extension d'après les octets, `ch12.fr.2.zip` en cas de
  /// doublon) ; une archive déjà enregistrée pour ce chapitre est remplacée.
  /// Une langue vide est remplacée par la première langue du site, comme
  /// dans la file. Si le chapitre attendait dans la file de téléchargement,
  /// cette ligne « en attente » est retirée
  /// (`ServiceTelechargement.retirerAttenteApresEnregistrementWeb`).
  ///
  /// Un second appel pour le même chapitre pendant l'enregistrement reçoit
  /// le même résultat (double clic). Lève une [ErreurService] (refus,
  /// chapitre disparu, dossier des chapitres changé), une `ErreurStockage`
  /// (disque) ou une `ErreurBaseDeDonnees` ; ces erreurs sont journalisées.
  Future<Chapitre> enregistrerImagesChapitre(
    Chapitre chapitre,
    List<ImageRecue> images, {
    bool pagesProtegees = false,
  }) {
    final id = chapitre.id;
    if (id == null) {
      return Future<Chapitre>.error(
        const ErreurService("Ce chapitre n'est pas enregistré."),
      );
    }
    final enCours = _enregistrementsEnCours[id];
    if (enCours != null) return enCours;
    final enregistrement =
        _enregistrer(id, images, pagesProtegees: pagesProtegees).whenComplete(
          () {
            _enregistrementsEnCours.remove(id);
          },
        );
    _enregistrementsEnCours[id] = enregistrement;
    return enregistrement;
  }

  Future<Chapitre> _enregistrer(
    int id,
    List<ImageRecue> images, {
    required bool pagesProtegees,
  }) async {
    final chrono = Stopwatch()..start();
    try {
      // 1. Contrôles, sans rien écrire.
      final formats = validerImagesChapitre(
        images,
        pagesProtegees: pagesProtegees,
      );
      if (_estRedemarrageNecessaire?.call() ?? false) {
        throw const ErreurService(
          'Le dossier des chapitres vient de changer : redémarrez '
          "l'application avant d'enregistrer un chapitre.",
        );
      }
      // Lectures et écritures comptées par le service de téléchargement :
      // refusées pendant un changement du dossier des chapitres, et un
      // changement demandé pendant l'écriture est refusé à son tour.
      final enregistre = await _serviceTelechargement.executerEnregistrementWeb(
        () => _ecrireArchive(id, images, formats, chrono),
      );
      // Le chapitre est téléchargé : sa ligne « en attente » de la file ne
      // ferait que le retélécharger. Un échec ici ne remet pas en cause
      // l'archive écrite (la file la réécrirait au pire sous le même nom).
      try {
        await _serviceTelechargement.retirerAttenteApresEnregistrementWeb(id);
      } catch (erreur, pile) {
        Journal.actuel.avertissement(
          CategorieJournal.telechargement,
          'Navigateur : chapitre n°$id laissé dans la file de téléchargement',
          erreur: erreur,
          pile: pile,
        );
      }
      return enregistre;
    } on ErreurService catch (erreur) {
      Journal.actuel.avertissement(
        CategorieJournal.telechargement,
        'Navigateur : enregistrement du chapitre n°$id refusé : '
        '${erreur.message}',
      );
      rethrow;
    } catch (erreur, pile) {
      Journal.actuel.erreur(
        CategorieJournal.telechargement,
        'Navigateur : enregistrement du chapitre n°$id en échec',
        erreur: erreur,
        pile: pile,
      );
      rethrow;
    }
  }

  /// Écrit l'archive des [images] déjà contrôlées (de formats [formats]) du
  /// chapitre [id], puis l'enregistre en base ; renvoie le chapitre relu.
  /// Pour [_enregistrer], dans `executerEnregistrementWeb`.
  Future<Chapitre> _ecrireArchive(
    int id,
    List<ImageRecue> images,
    List<FormatImage> formats,
    Stopwatch chrono,
  ) async {
    // Relu en base : nom d'archive et état « téléchargé » à jour.
    final chapitre = await _depotChapitres.chargerChapitre(id);
    final idTitre = chapitre?.idTitre;
    final titre = idTitre == null
        ? null
        : await _depotTitres.chargerTitre(idTitre);
    if (chapitre == null || titre == null) {
      throw const ErreurService("Ce chapitre n'existe plus.");
    }
    if (_estSiteProtege(chapitre, images)) {
      throw const ErreurService(messageImagesProtegees);
    }
    final idSource = chapitre.idSource ?? titre.idSource;
    final source = idSource == null
        ? null
        : await _depotSources.chargerSource(idSource);
    // Même nom calculé que la file (ServiceTelechargement) : langue vide
    // remplacée par la première langue du site.
    final langues = ServiceBibliotheque.languesPreferees(source);
    final chapitrePourChemin = chapitre.langue.isEmpty && langues.isNotEmpty
        ? chapitre.copierAvec(langue: langues.first)
        : chapitre;

    // 2. Archive sur le disque (.zip.part puis .zip).
    final ecriture = await _stockage.ouvrirEcriture(titre, chapitrePourChemin);
    final String nomArchive;
    try {
      for (var index = 0; index < images.length; index++) {
        await ecriture.ajouterPage(
          images[index].octets,
          extension: formats[index].extension,
        );
      }
      nomArchive = ecriture.nomArchive;
      await ecriture.finaliser();
    } catch (_) {
      await ecriture.abandonner();
      rethrow;
    }

    // 3. Base. LIMITE : le disque et la base ne peuvent pas être écrits
    // atomiquement ensemble ; si la base refuse, une archive neuve est
    // effacée (sinon aucun chapitre ne la désignerait), une archive
    // remplacée reste désignée par son chapitre.
    final estArchiveNeuve =
        chapitre.nomArchive == null && !chapitre.estTelecharge;
    try {
      if (!await _depotChapitres.enregistrerArchive(id, nomArchive)) {
        throw const ErreurService("Ce chapitre n'existe plus.");
      }
    } catch (_) {
      if (estArchiveNeuve) {
        await _supprimerArchiveSansErreur(nomArchive);
      }
      rethrow;
    }
    final enregistre = await _depotChapitres.chargerChapitre(id);
    if (enregistre == null) {
      throw const ErreurService("Ce chapitre n'existe plus.");
    }
    Journal.actuel.info(
      CategorieJournal.telechargement,
      'Navigateur : chapitre n°$id (« ${titre.nom} » ch. '
      '${_formaterNumero(chapitre.numero)}) enregistré depuis la page, '
      '${images.length} image(s) (${_domainesImages(images)}) en '
      '${chrono.elapsedMilliseconds} ms : $nomArchive',
    );
    return enregistre;
  }

  /// `true` si le chapitre se lit sur un site dont les images sont
  /// brouillées par l'éditeur ([domainesImagesProtegees]), ou si l'une des
  /// [images] est protégée ([_estAdresseImageProtegee]).
  static bool _estSiteProtege(Chapitre chapitre, List<ImageRecue> images) {
    for (final adresse in <String?>[
      chapitre.urlChapitre,
      chapitre.urlExterne,
    ]) {
      if (adresse != null && _estDomaineProtege(adresse)) {
        return true;
      }
    }
    return images.any(_estAdresseImageProtegee);
  }

  /// `true` si l'adresse de [image] montre une page protégée :
  /// - `blob:` ou `data:` : l'image n'a pas été servie telle quelle par le
  ///   site mais fabriquée par un script de la page, typiquement après
  ///   déchiffrement par le lecteur de l'éditeur (PLAYBOOK.md section 10 :
  ///   jamais de contournement) ;
  /// - domaine (ou sous-domaine) de [domainesImagesProtegees].
  ///
  /// Une image sans adresse connue n'est jugée que par ses octets.
  static bool _estAdresseImageProtegee(ImageRecue image) {
    final adresse = image.adresse?.trim().toLowerCase();
    if (adresse == null || adresse.isEmpty) return false;
    if (adresse.startsWith('blob:') || adresse.startsWith('data:')) {
      return true;
    }
    return _estDomaineProtege(adresse);
  }

  /// `true` si l'hôte de [adresse] est un domaine de
  /// [domainesImagesProtegees] ou l'un de ses sous-domaines (serveurs
  /// d'images de l'éditeur).
  static bool _estDomaineProtege(String adresse) {
    final hote = Uri.tryParse(adresse.trim())?.host.toLowerCase() ?? '';
    if (hote.isEmpty) return false;
    return domainesImagesProtegees.any(
      (domaine) => hote == domaine || hote.endsWith('.$domaine'),
    );
  }

  Future<void> _supprimerArchiveSansErreur(String nomArchive) async {
    try {
      await _stockage.supprimerArchive(nomArchive);
    } catch (erreur) {
      // LIMITE : l'archive reste sur le disque sans chapitre associé ; elle
      // sera remplacée si ce chapitre est enregistré de nouveau.
      Journal.actuel.avertissement(
        CategorieJournal.stockage,
        'Archive orpheline $nomArchive non effacée',
        erreur: erreur,
      );
    }
  }

  // ---------------------------------------------------------------------
  // Outils
  // ---------------------------------------------------------------------

  /// Hôte comparable de [url] (`www.` et `m.` retirés, comme
  /// `ServiceAjoutSite.proposerNom`), ou `null` si l'adresse n'en a pas.
  static String? _hoteComparable(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return ServiceAjoutSite.proposerNom(uri);
  }

  /// Hôte de [url] pour le journal : l'adresse complète peut contenir des
  /// paramètres personnels.
  static String _hoteJournal(String url) {
    final hote = Uri.tryParse(url.trim())?.host ?? '';
    return hote.isEmpty ? '?' : hote;
  }

  /// Domaines des images reçues, pour le journal (sans les adresses).
  static String _domainesImages(List<ImageRecue> images) {
    final domaines = <String>{
      for (final image in images)
        if (image.adresse case final String adresse) _hoteJournal(adresse),
    }..remove('?');
    return domaines.isEmpty ? 'domaine inconnu' : domaines.join(', ');
  }

  static String _decoder(String texte) {
    try {
      return Uri.decodeFull(texte);
    } on ArgumentError {
      return texte;
    }
  }

  static String _formaterNumero(double numero) =>
      numero == numero.truncateToDouble()
      ? numero.toInt().toString()
      : numero.toString();

  static String _formaterMo(int octets) =>
      '${(octets / (1024 * 1024)).toStringAsFixed(0)} Mo';
}
