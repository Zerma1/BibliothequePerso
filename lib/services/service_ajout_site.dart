/// Ajout d'un site de lecture à partir de son URL (PLAYBOOK.md section 7).
library;

import 'dart:convert';

import '../donnees/depot_sources.dart';
import '../modeles/source.dart';
import '../sources/detecteur_type_site.dart';
import '../sources/erreur_source.dart';
import '../sources/source_generique.dart' show ConfigurationGenerique;
import 'erreur_service.dart';

/// Valide une URL, détecte le type du site et enregistre la [Source].
class ServiceAjoutSite {
  /// Crée le service.
  const ServiceAjoutSite(this._depotSources, this._detecteur);

  final DepotSources _depotSources;
  final DetecteurTypeSite _detecteur;

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
  /// Lève une `ErreurSource` (URL invalide, site injoignable) ou une
  /// `ErreurBaseDeDonnees`.
  Future<Source> ajouterSite(
    String url, {
    String? nom,
    String langueParDefaut = '',
    TypeSource? typeForce,
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

    // Une ErreurSource du détecteur remonte telle quelle : le type n'est pas
    // encore connu à ce stade (le rapport d'erreur indiquera « inconnu »).
    final type = typeForce ?? await _detecteur.detecter(urlBase);
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

  /// Modifie une source existante (nom, langues, type, activation, réglages
  /// d'un site générique).
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
    final avant = id == null
        ? null
        : (await _depotSources.chargerSource(id))?.configurationSelecteurs;
    final String? reglages;
    if (brut != null && brut == avant) {
      reglages = brut;
    } else {
      reglages = normaliserReglagesGeneriques(brut);
    }
    return _depotSources.enregistrerSource(
      source.copierAvec(
        nom: source.nom.trim(),
        langueParDefaut: langues,
        configurationSelecteurs: reglages,
        effacerConfigurationSelecteurs: reglages == null,
      ),
    );
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
      <String, String>{
        'selecteurTitre': 'Nom du titre',
        'selecteurCouverture': 'Image de couverture',
        'selecteurResume': 'Résumé',
        'selecteurAuteur': 'Auteur',
        'selecteurCategories': 'Catégories (une par élément)',
        'selecteurLiensChapitres': 'Liens des chapitres',
        'selecteurImagesChapitre': "Images d'un chapitre",
        'selecteurLienListeChapitres':
            'Lien vers la liste des chapitres (depuis un chapitre)',
        'motifNumeroChapitre': 'Numéro de chapitre (expression régulière)',
      };

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
  /// LIMITE : les sélecteurs CSS ne sont pas encore analysés ici. Le
  /// parseur de l'adaptateur (`package:html`, appelé par une méthode privée
  /// de `SourceGenerique`) n'est exposé par aucune fonction publique de
  /// `lib/sources`, et les services n'importent pas `package:html`. Un
  /// sélecteur invalide est donc signalé à la première lecture du site
  /// (`ErreurSource` qui nomme le réglage). Besoin signalé : une fonction
  /// publique de vérification d'un sélecteur dans `lib/sources`.
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
      if (cle == cleMotifNumeroChapitre) {
        try {
          RegExp(propre);
        } on FormatException catch (erreur) {
          throw ErreurService(
            '${libelleReglageGenerique(cle)} : « $propre » n\'est pas une '
            'expression régulière valide.',
            cause: erreur,
          );
        }
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
  Future<void> supprimerSource(int idSource) =>
      _depotSources.supprimerSource(idSource);

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
