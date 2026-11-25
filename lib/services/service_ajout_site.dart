/// Ajout d'un site de lecture à partir de son URL (PLAYBOOK.md section 7).
library;

import 'dart:convert';

import '../donnees/depot_sources.dart';
import '../modeles/journal.dart';
import '../modeles/source.dart';
import '../sources/client_http_poli.dart';
import '../sources/detecteur_type_site.dart';
import '../sources/erreur_source.dart';
import '../sources/lisibilite_site.dart';
import '../sources/rapport_erreur_source.dart' show extraireDebutReponse;
import '../sources/source_generique.dart' show ConfigurationGenerique;
import 'erreur_service.dart';
import 'service_bibliotheque.dart' show ServiceBibliotheque;

/// Valide une URL, détecte le type du site et enregistre la [Source].
class ServiceAjoutSite {
  /// Crée le service.
  ///
  /// [client] (facultatif pour ne pas casser les appelants existants) sert
  /// à vérifier, avant l'ajout d'un site générique, que la page collée par
  /// le client est lisible (voir [ajouterSite]). Il doit être le client
  /// unique de l'application (délai par domaine partagé). Sans lui, cette
  /// vérification n'est pas faite.
  const ServiceAjoutSite(
    this._depotSources,
    this._detecteur, {
    ClientHttpPoli? client,
    // Un paramètre nommé ne peut pas être privé en Dart : champ privé
    // initialisé dans la liste d'initialisation.
    // ignore: prefer_initializing_formals
  }) : _client = client;

  final DepotSources _depotSources;
  final DetecteurTypeSite _detecteur;
  final ClientHttpPoli? _client;

  /// Ramène une URL quelconque du site à son URL de base (`schéma://hôte`).
  ///
  /// Le client peut coller l'adresse d'un titre ou d'un chapitre : on ne garde
  /// que la racine, pour qu'un même site ne soit enregistré qu'une fois.
  static String calculerUrlBase(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host.toLowerCase()}$port';
  }

  /// Propose un nom affichable à partir de l'hôte (`www.` et `m.` retirés).
  ///
  /// Sert aussi à reconnaître un site déjà configuré : la version mobile d'un
  /// site (`m.webtoons.com`) est le même site que `www.webtoons.com`.
  static String proposerNom(Uri uri) {
    final hote = uri.host.toLowerCase();
    for (final prefixe in const <String>['www.', 'm.']) {
      if (hote.startsWith(prefixe)) {
        return hote.substring(prefixe.length);
      }
    }
    return hote;
  }

  /// Ajoute le site désigné par [url] et renvoie la source enregistrée.
  ///
  /// Si le site est déjà configuré, la source existante est renvoyée sans
  /// nouvelle détection. [nom] et [langueParDefaut] sont facultatifs ;
  /// [typeForce] permet au client de corriger un type mal détecté.
  ///
  /// **Site générique** (retour C2 de la 0.2.1-test : une page Wikipédia
  /// était acceptée) : quand le type détecté (non forcé) est générique, la
  /// page collée est récupérée (une requête de plus, avec le délai par
  /// domaine) et passée à `verifierLisibilite`, avec les réglages
  /// [configurationSelecteurs] que le client s'apprête à enregistrer.
  /// - page précise (au moins deux segments de chemin, voir
  ///   [estPageAccueil]) : refusée si elle n'est pas lisible ;
  /// - accueil (racine, un seul segment, paramètres seuls) : refusé
  ///   seulement pour un refus sûr ([raisonRefusSur] : anti-robot,
  ///   connexion, page en JavaScript), car un accueil à plusieurs œuvres ne
  ///   liste pas de chapitres.
  ///
  /// En cas de refus, **rien n'est enregistré** et une `ErreurSource` porte
  /// la raison (l'interface propose alors « Pourquoi ce site n'est pas
  /// lisible ? »). Vérification faite seulement si le service a reçu le
  /// client HTTP.
  ///
  /// Lève une `ErreurSource` (URL invalide, site injoignable, page
  /// illisible), une [ErreurService] ([typeForce] incohérent avec le site,
  /// voir [erreurTypeSite]) ou une `ErreurBaseDeDonnees`.
  Future<Source> ajouterSite(
    String url, {
    String? nom,
    String langueParDefaut = '',
    TypeSource? typeForce,
    String? configurationSelecteurs,
  }) async {
    // Seule la racine du site est journalisée : l'adresse collée peut
    // contenir des paramètres personnels.
    final hote = Uri.tryParse(url.trim())?.host ?? '';
    try {
      final source = await _ajouterSite(
        url,
        nom: nom,
        langueParDefaut: langueParDefaut,
        typeForce: typeForce,
        configurationSelecteurs: configurationSelecteurs,
      );
      Journal.actuel.info(
        CategorieJournal.bibliotheque,
        'Site ajouté ou déjà configuré : ${source.urlBase} (n°${source.id}, '
        'type ${source.typeSource.name})',
      );
      return source;
    } catch (erreur) {
      // Refus attendu (site illisible, type incohérent) : un avertissement
      // avec la raison, sans pile (le rapport d'erreur la donne au besoin).
      Journal.actuel.avertissement(
        CategorieJournal.bibliotheque,
        'Ajout du site « $hote » refusé',
        erreur: erreur,
      );
      rethrow;
    }
  }

  /// Corps de [ajouterSite], sans journalisation.
  Future<Source> _ajouterSite(
    String url, {
    String? nom,
    String langueParDefaut = '',
    TypeSource? typeForce,
    String? configurationSelecteurs,
  }) async {
    final uri = DetecteurTypeSite.validerUrl(url);
    final urlBase = calculerUrlBase(uri);

    // Recherche par hôte normalisé (www. et m. retirés) plutôt que par URL de
    // base exacte : sinon coller une adresse mobile (m.webtoons.com) d'un site
    // déjà configuré en www. créerait un doublon.
    final existante = await trouverSourcePourUrl(url);
    if (existante != null) {
      return existante;
    }

    // Type corrigé par le client : refusé avant toute requête s'il ne peut
    // pas lire ce site (MangaDex forcé sur un autre domaine…).
    if (typeForce != null) {
      final refus = erreurTypeSite(urlBase, typeForce);
      if (refus != null) throw ErreurService(refus);
    }
    // Une ErreurSource du détecteur remonte telle quelle : le type n'est pas
    // encore connu à ce stade (le rapport d'erreur indiquera « inconnu »).
    final type = typeForce ?? await _detecteur.detecter(urlBase);
    if (typeForce == null && type == TypeSource.generique) {
      // Réseau d'abord : un refus ici n'a encore rien écrit.
      await _verifierPageCollee(uri, configurationSelecteurs);
    }
    final nomFinal = (nom == null || nom.trim().isEmpty)
        ? proposerNom(uri)
        : nom.trim();

    return _depotSources.enregistrerSource(
      Source(
        nom: nomFinal,
        urlBase: urlBase,
        typeSource: type,
        langueParDefaut: langueParDefaut.trim().toLowerCase(),
      ),
    );
  }

  /// `true` si [uri] désigne une page d'accueil : chemin de moins de deux
  /// segments non vides (`/`, `/fr/`, `/index.php`, `/home`, `/manga/`),
  /// paramètres compris (`/?lang=fr`). Fonction pure.
  ///
  /// Règle du client (relecture C2) : seule une adresse d'au moins deux
  /// segments (`/wiki/Ruri_Dragon`, `/manga/titre/`) désigne une page
  /// précise dont on exige des chapitres ; un accueil, une page de langue ou
  /// un catalogue ne listent pas eux-mêmes de chapitres et étaient refusés à
  /// tort.
  static bool estPageAccueil(Uri uri) =>
      uri.pathSegments.where((segment) => segment.isNotEmpty).length < 2;

  /// Vérification C2 de [ajouterSite] sur la page collée [uri].
  ///
  /// Toute page est récupérée (une requête) : un défi anti-robot, une page
  /// de connexion ou une page construite en JavaScript sont refusés partout
  /// (refus sûrs : l'application ne pourra jamais lire ce site). Une page
  /// précise (voir [estPageAccueil]) doit en plus être lisible (liens de
  /// chapitres ou images). Lève une `ErreurSource` sinon.
  Future<void> _verifierPageCollee(
    Uri uri,
    String? configurationSelecteurs,
  ) async {
    final client = _client;
    if (client == null) return;
    final String html;
    try {
      // Une seule requête : la page n'est lue qu'une fois, sans suivre ses
      // liens (charge des sites, PLAYBOOK.md section 10).
      html = await client.recupererTexte(uri);
    } on ErreurSource catch (erreur) {
      throw erreur.avecContexte(typeDetecte: TypeSource.generique);
    }
    final diagnostic = verifierLisibilite(
      html,
      uri,
      configurationSelecteurs: configurationSelecteurs,
    );
    if (diagnostic.estLisible) return;
    final String raison;
    if (estPageAccueil(uri)) {
      // Accueil : seuls les refus sûrs comptent (l'absence de chapitres y est
      // normale).
      final sure = raisonRefusSur(diagnostic);
      if (sure == null) return;
      raison = sure;
    } else {
      raison = diagnostic.raisons.first;
    }
    throw ErreurSource(
      uri.toString(),
      raison,
      typeDetecte: TypeSource.generique,
      protectionAntiRobot: diagnostic.protectionAntiRobot,
      // Début de la page (déjà nettoyé des données personnelles) pour le
      // rapport d'erreur exportable.
      extraitReponse: extraireDebutReponse(html),
    );
  }

  /// Raison d'un refus sûr du [diagnostic] (défi anti-robot, page de
  /// connexion, page construite en JavaScript), ou `null` s'il n'y en a pas
  /// (page lisible, ou seulement sans chapitre ni image). Fonction pure.
  ///
  /// LIMITE : `DiagnosticLisibilite` ne donne un indicateur que pour le défi
  /// anti-robot ; la connexion et la page en JavaScript sont reconnues à
  /// leur message (`verifierLisibilite`, lib/sources/lisibilite_site.dart).
  /// Si ces messages changent, les tests de `service_ajout_site` échouent
  /// (ils passent par le vrai diagnostic). Un indicateur par refus dans le
  /// diagnostic serait plus solide (demande à `developpeur-sources`).
  static String? raisonRefusSur(DiagnosticLisibilite diagnostic) {
    if (diagnostic.estLisible) return null;
    if (diagnostic.protectionAntiRobot) return diagnostic.raisons.first;
    for (final raison in diagnostic.raisons) {
      if (raison.contains('demande une connexion') ||
          raison.contains('construite par des scripts')) {
        return raison;
      }
    }
    return null;
  }

  /// Motif du refus du type [type] pour le site d'adresse [urlBase], ou
  /// `null` s'il est cohérent. Fonction pure.
  ///
  /// Les sites reconnus par leur domaine (MangaDex, Scan-Manga, WEBTOON) ne
  /// sont lus que par leur adaptateur dédié : leur type ne peut pas changer,
  /// et ces types ne peuvent pas être donnés à un autre site (l'adaptateur
  /// n'y comprendrait rien). Les types Madara, MangaThemesia et générique
  /// sont libres pour tout autre site : le détecteur peut se tromper, et le
  /// client corrige.
  static String? erreurTypeSite(String urlBase, TypeSource type) {
    final uri = Uri.tryParse(urlBase.trim());
    final parDomaine = uri == null
        ? null
        : DetecteurTypeSite.verifierDomaine(uri);
    if (parDomaine != null && type != parDomaine) {
      return "Ce site est lu par son adaptateur dédié "
          "(${ServiceBibliotheque.nomTypeSource(parDomaine)}) : son type ne "
          'peut pas être changé.';
    }
    if (parDomaine == null &&
        ServiceBibliotheque.estTypeAAdaptateurParDomaine(type)) {
      return 'Le type ${ServiceBibliotheque.nomTypeSource(type)} est réservé '
          'au site officiel ; choisissez WordPress Madara, WordPress '
          'MangaThemesia ou générique.';
    }
    return null;
  }

  /// Modifie une source existante (nom, langues, type, activation, réglages
  /// d'un site générique).
  ///
  /// **Changement de type** (tâche X5) : accepté s'il est cohérent
  /// ([erreurTypeSite], sinon [ErreurService] et rien n'est écrit). Le type
  /// n'est vérifié que s'il change : un site enregistré avant cette règle
  /// peut toujours être renommé. L'adaptateur suit le nouveau type dès la
  /// lecture suivante (il est recréé à chaque lecture). Quitter le type
  /// générique **efface** ses réglages avancés (sélecteurs CSS), qui ne
  /// servent qu'à lui. Les adresses des titres et chapitres déjà
  /// enregistrés ne changent pas : la prochaine actualisation les relit
  /// avec le nouvel adaptateur.
  ///
  /// Les langues sont des codes ISO 639-1 séparés par des virgules, par ordre
  /// de préférence (« fr,en ») ; elles sont mises en minuscules et les
  /// espaces retirés. L'URL de base ne change pas.
  ///
  /// Réglages (`Source.configurationSelecteurs`, V2) : nettoyés par
  /// [normaliserReglagesGeneriques] (valeurs vides retirées) ; des réglages
  /// vides **effacent** ceux du site (retour aux heuristiques). Des réglages
  /// modifiés sont vérifiés avant tout enregistrement : une [ErreurService]
  /// nomme le champ fautif et rien n'est écrit. Des réglages inchangés ne
  /// sont pas revérifiés, pour qu'un site enregistré avant cette
  /// vérification puisse toujours être renommé.
  Future<Source> modifierSource(Source source) async {
    final langues = source.langueParDefaut
        .split(',')
        .map((code) => code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .join(',');
    final brut = source.configurationSelecteurs;
    final id = source.id;
    final ancienne = id == null ? null : await _depotSources.chargerSource(id);
    if (ancienne == null || ancienne.typeSource != source.typeSource) {
      final refus = erreurTypeSite(
        ancienne?.urlBase ?? source.urlBase,
        source.typeSource,
      );
      if (refus != null) throw ErreurService(refus);
    }
    final avant = ancienne?.configurationSelecteurs;
    final String? reglages;
    if (source.typeSource != TypeSource.generique) {
      // Réglages propres au type générique : inutiles (et trompeurs dans le
      // formulaire) pour un autre type.
      reglages = null;
    } else if (brut != null && brut == avant) {
      reglages = brut;
    } else {
      reglages = normaliserReglagesGeneriques(brut);
    }
    final enregistree = await _depotSources.enregistrerSource(
      source.copierAvec(
        nom: source.nom.trim(),
        langueParDefaut: langues,
        configurationSelecteurs: reglages,
        effacerConfigurationSelecteurs: reglages == null,
      ),
    );
    Journal.actuel.info(
      CategorieJournal.bibliotheque,
      'Site n°${enregistree.id} modifié (type ${enregistree.typeSource.name}, '
      '${enregistree.estActive ? 'actif' : 'inactif'})',
    );
    return enregistree;
  }

  // ------------------------------------------- Réglages d'un site générique

  /// Clés des réglages d'un site générique, dans l'ordre du formulaire
  /// (celles que lit l'adaptateur générique : `ConfigurationGenerique.cles`).
  /// L'interface s'en sert au lieu d'en garder une copie.
  static const List<String> clesReglagesGeneriques =
      ConfigurationGenerique.cles;

  /// Clé du seul réglage qui est une expression régulière (les autres sont
  /// des sélecteurs CSS).
  static const String cleMotifNumeroChapitre = 'motifNumeroChapitre';

  /// Libellé français de chaque réglage, par clé (formulaire et messages
  /// d'erreur).
  static const Map<String, String> libellesReglagesGeneriques =
      ConfigurationGenerique.libelles;

  /// Libellé français du réglage [cle] (la clé elle-même si elle est
  /// inconnue).
  static String libelleReglageGenerique(String cle) =>
      libellesReglagesGeneriques[cle] ?? cle;

  /// JSON des réglages [reglages] (par clé de [clesReglagesGeneriques],
  /// valeurs vides retirées, clés inconnues ignorées), ou `null` si aucun
  /// n'est renseigné. Ne vérifie rien : voir [normaliserReglagesGeneriques].
  static String? reglagesGeneriquesVersJson(Map<String, String> reglages) {
    final remplis = <String, String>{
      for (final cle in clesReglagesGeneriques)
        if ((reglages[cle] ?? '').trim().isNotEmpty) cle: reglages[cle]!.trim(),
    };
    return remplis.isEmpty ? null : jsonEncode(remplis);
  }

  /// Réglages enregistrés [json] par clé (pour préremplir le formulaire) ;
  /// vide si [json] est vide ou illisible.
  static Map<String, String> reglagesGeneriquesDepuisJson(String? json) {
    final texte = json?.trim() ?? '';
    if (texte.isEmpty) return const <String, String>{};
    try {
      final valeur = jsonDecode(texte);
      if (valeur is! Map<String, Object?>) return const <String, String>{};
      return <String, String>{
        for (final cle in clesReglagesGeneriques)
          if (valeur[cle] case final String texteReglage
              when texteReglage.trim().isNotEmpty)
            cle: texteReglage.trim(),
      };
    } on FormatException {
      return const <String, String>{};
    }
  }

  /// Motif court (en français, sans préfixe) du refus de la valeur
  /// [valeur] pour le réglage [cle], ou `null` si elle est acceptée ou vide
  /// (un réglage vide revient à l'heuristique). Fonction pure, pour afficher
  /// l'erreur sous le champ du formulaire.
  ///
  /// - [cleMotifNumeroChapitre] : « expression régulière invalide » ;
  /// - autre clé (sélecteur CSS) : motif de
  ///   `ConfigurationGenerique.erreurSelecteur`, même parseur que la lecture
  ///   du site (« syntaxe CSS invalide », « non pris en charge par
  ///   l'application ») ; LIMITE : ce parseur est tolérant (voir sa
  ///   documentation).
  static String? erreurReglageGenerique(String cle, String valeur) {
    final propre = valeur.trim();
    if (propre.isEmpty) return null;
    if (cle == cleMotifNumeroChapitre) {
      try {
        RegExp(propre);
        return null;
      } on FormatException {
        return 'expression régulière invalide';
      }
    }
    return ConfigurationGenerique.erreurSelecteur(propre);
  }

  /// Vérifie et nettoie des réglages de site générique (JSON de
  /// `Source.configurationSelecteurs`). Fonction pure.
  ///
  /// Renvoie le JSON nettoyé (valeurs vides et clés inconnues retirées,
  /// ordre de [clesReglagesGeneriques]), ou `null` si [json] est vide ou ne
  /// contient aucun réglage. Lève une [ErreurService] qui nomme le champ
  /// fautif (« Numéro de chapitre (expression régulière) : … ») si le JSON
  /// est illisible, si une valeur n'est pas un texte ou si le motif n'est
  /// pas une expression régulière valide. La lecture finale passe par
  /// `ConfigurationGenerique.depuisJson`, celle de l'adaptateur générique.
  ///
  /// Les sélecteurs CSS sont vérifiés par `ConfigurationGenerique.depuisJson`
  /// (même parseur que la lecture du site) : un sélecteur refusé lève une
  /// [ErreurService] qui nomme le réglage. LIMITE : le parseur est tolérant
  /// (voir `ConfigurationGenerique.erreurSelecteur`).
  static String? normaliserReglagesGeneriques(String? json) {
    final texte = json?.trim() ?? '';
    if (texte.isEmpty) return null;
    final Object? valeur;
    try {
      valeur = jsonDecode(texte);
    } on FormatException catch (erreur) {
      throw ErreurService(
        'Les réglages avancés de ce site sont illisibles (JSON invalide).',
        cause: erreur,
      );
    }
    if (valeur is! Map<String, Object?>) {
      throw const ErreurService(
        'Les réglages avancés de ce site sont illisibles (objet JSON '
        'attendu).',
      );
    }
    final remplis = <String, String>{};
    for (final cle in clesReglagesGeneriques) {
      final brut = valeur[cle];
      if (brut == null) continue;
      if (brut is! String) {
        throw ErreurService(
          '${libelleReglageGenerique(cle)} : un texte est attendu.',
        );
      }
      final propre = brut.trim();
      if (propre.isEmpty) continue;
      final refus = erreurReglageGenerique(cle, propre);
      if (refus != null) {
        throw ErreurService(
          '${libelleReglageGenerique(cle)} : « $propre » refusé ($refus).',
        );
      }
      remplis[cle] = propre;
    }
    if (remplis.isEmpty) return null;
    final resultat = jsonEncode(remplis);
    // Même lecture que l'adaptateur générique : ce qui est enregistré ici
    // sera lisible par lui (filet de sécurité si ses règles évoluent).
    try {
      ConfigurationGenerique.depuisJson(resultat);
    } on ErreurSource catch (erreur) {
      throw ErreurService(
        'Les réglages avancés de ce site sont refusés : ${erreur.message}.',
        cause: erreur,
      );
    }
    return resultat;
  }

  /// Supprime une source. Refusé (ErreurBaseDeDonnees) tant qu'elle a des
  /// titres, pour ne jamais effacer une partie de la bibliothèque.
  Future<void> supprimerSource(int idSource) async {
    await _depotSources.supprimerSource(idSource);
    Journal.actuel.info(
      CategorieJournal.bibliotheque,
      'Site n°$idSource supprimé',
    );
  }

  /// Renvoie la source configurée qui correspond à l'hôte de [url], ou `null`.
  ///
  /// La comparaison se fait sur [proposerNom] (préfixes `www.` et `m.`
  /// retirés) : une source `https://www.webtoons.com` reconnaît aussi
  /// `https://m.webtoons.com/…`, et `https://mangadex.org` reconnaît
  /// `https://www.mangadex.org/title/…`. Le schéma et le port sont ignorés.
  ///
  /// Lève une `ErreurSource` si [url] est invalide.
  Future<Source?> trouverSourcePourUrl(String url) async {
    final uri = DetecteurTypeSite.validerUrl(url);
    final hote = proposerNom(uri);
    final sources = await _depotSources.chargerSources();
    for (final source in sources) {
      final uriSource = Uri.tryParse(source.urlBase);
      if (uriSource != null && proposerNom(uriSource) == hote) {
        return source;
      }
    }
    return null;
  }
}
