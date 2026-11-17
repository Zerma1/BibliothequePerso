/// Opérations sur la bibliothèque qui assemblent les sources et les données
/// (PLAYBOOK.md sections 4 et 7).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:io' show File, FileSystemException;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../donnees/constantes_donnees.dart' show tailleMaxCouverture;
import '../donnees/depot_categories.dart';
import '../donnees/depot_chapitres.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../donnees/depot_titres_sources.dart';
import '../donnees/erreur_stockage.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/categorie.dart';
import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/lien_titre_source.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../sources/client_http_poli.dart';
import '../sources/constantes_sources.dart';
import '../sources/couverture_site.dart';
import '../sources/detecteur_type_site.dart';
import '../sources/erreur_source.dart';
import '../sources/fabrique_sources.dart';
import '../sources/lisibilite_site.dart';
import '../sources/protection_anti_robot.dart' show messageProtectionAntiRobot;
import '../sources/source_mangadex.dart';
import '../sources/source_site.dart';
import '../sources/source_webtoons.dart';
import 'classement_listes.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'service_ajout_site.dart';
import 'service_parametres.dart';
import 'service_sources_par_defaut.dart';

// Type rendu par [ServiceBibliotheque.diagnostiquerSite] : réexporté pour
// que l'interface n'ait pas à importer `lib/sources` (sens des dépendances).
export '../sources/lisibilite_site.dart' show DiagnosticLisibilite;

/// Résultat de l'ajout (ou de l'actualisation) d'un titre.
class ResultatAjoutTitre {
  /// Crée le résultat.
  const ResultatAjoutTitre(
    this.titre,
    this.nombreNouveauxChapitres, {
    this.estEnAttente = false,
    this.estDejaPresent = false,
    this.erreursParSite = const <int, Object>{},
  });

  /// Titre tel qu'enregistré en base.
  final Titre titre;

  /// Nombre de chapitres qui n'étaient pas encore connus (tous sites
  /// confondus).
  final int nombreNouveauxChapitres;

  /// `true` si le titre a été placé (ou laissé) dans « En attente » : il
  /// n'a encore aucun chapitre dans les langues du client. L'interface peut
  /// le signaler à l'ajout.
  final bool estEnAttente;

  /// `true` quand l'adresse ajoutée était déjà celle d'un site secondaire
  /// d'un titre de la bibliothèque : ce titre est renvoyé tel quel (sans
  /// requête au site), au lieu d'être créé une seconde fois.
  final bool estDejaPresent;

  /// Erreurs des sites qui n'ont pas pu être lus pendant une actualisation,
  /// par identifiant de source (étape 8 : un site en panne n'empêche pas les
  /// autres). Vide si tous les sites ont répondu.
  final Map<int, Object> erreursParSite;

  /// `true` si au moins un site du titre n'a pas pu être lu.
  bool get aDesErreursDeSite => erreursParSite.isNotEmpty;
}

/// Un site d'un titre, pour la section « Sites » de la fiche (étape 8).
class SiteDuTitre {
  /// Crée la ligne.
  const SiteDuTitre({
    required this.lien,
    required this.nomSite,
    this.source,
    this.nombreChapitres = 0,
  });

  /// Lien enregistré (adresse du titre sur ce site, principal ou non).
  final LienTitreSource lien;

  /// Site configuré, ou `null` s'il n'existe plus (ne devrait pas arriver :
  /// la base refuse de supprimer un site encore lié à un titre).
  final Source? source;

  /// Nom affichable du site (nom de la source, sinon nom de domaine).
  final String nomSite;

  /// Nombre de chapitres connus venant de ce site.
  final int nombreChapitres;

  /// Identifiant de la source.
  int get idSource => lien.idSource;

  /// Adresse du titre sur ce site.
  String get urlTitre => lien.urlTitre;

  /// `true` pour le site principal (fiche, couverture, résumé).
  bool get estPrincipal => lien.estPrincipale;

  /// `true` pour un **lien seul** (tâche T4) : site seulement ouvert dans le
  /// navigateur, l'application n'y lit aucun chapitre.
  bool get estLienSeul => lien.estLienSeul;
}

/// Ligne de l'onglet « Mises à jour » : un titre et sa dernière parution
/// dans ses langues.
class ParutionTitre {
  /// Crée la ligne.
  const ParutionTitre({
    required this.titre,
    required this.langues,
    this.derniereParution,
    this.dernierChapitre,
    this.estEnAttente = false,
  });

  /// Titre concerné.
  final Titre titre;

  /// Langues retenues pour ce titre (`ServiceBibliotheque.languesPourTitre`).
  final List<String> langues;

  /// Date (UTC) de la dernière parution dans [langues] (publication, sinon
  /// détection), ou `null` si aucun chapitre n'y est encore paru.
  final DateTime? derniereParution;

  /// Dernier chapitre paru dans [langues], ou `null`.
  final Chapitre? dernierChapitre;

  /// `true` si le titre est dans la liste « En attente ».
  final bool estEnAttente;

  /// `true` si le dernier chapitre paru n'est pas encore lu (badge des
  /// nouveautés).
  bool get aNouveaute => dernierChapitre != null && !dernierChapitre!.estLu;
}

/// Point d'entrée de l'interface pour la bibliothèque : titres, listes,
/// catégories, chapitres et couvertures.
class ServiceBibliotheque {
  /// Crée le service.
  ///
  /// [stockage] (facultatif pour ne pas casser les appelants existants) sert
  /// aux couvertures enregistrées sur l'appareil ; sans lui, les couvertures
  /// ne sont que téléchargées pour la session.
  ServiceBibliotheque({
    required DepotSources depotSources,
    required DepotTitres depotTitres,
    required DepotChapitres depotChapitres,
    required DepotListes depotListes,
    required DepotCategories depotCategories,
    required FabriqueSources fabriqueSources,
    required ServiceAjoutSite serviceAjoutSite,
    required ClientHttpPoli client,
    ServiceParametres? serviceParametres,
    StockageTelechargements? stockage,
    DepotTitresSources? depotTitresSources,
  }) : _depotTitresSources = depotTitresSources,
       _depotSources = depotSources,
       _depotTitres = depotTitres,
       _depotChapitres = depotChapitres,
       _depotListes = depotListes,
       _depotCategories = depotCategories,
       _fabriqueSources = fabriqueSources,
       _serviceAjoutSite = serviceAjoutSite,
       _client = client,
       _serviceParametres = serviceParametres,
       _stockage = stockage;

  final DepotSources _depotSources;
  final DepotTitres _depotTitres;
  final DepotChapitres _depotChapitres;
  final DepotListes _depotListes;
  final DepotCategories _depotCategories;
  final FabriqueSources _fabriqueSources;
  final ServiceAjoutSite _serviceAjoutSite;
  final ClientHttpPoli _client;

  /// Réglages du client (langues de lecture, niveaux de contenu).
  /// Facultatif pour ne pas casser les appelants existants : sans lui, les
  /// valeurs par défaut s'appliquent.
  final ServiceParametres? _serviceParametres;

  /// Stockage des couvertures sur l'appareil (voir le constructeur).
  final StockageTelechargements? _stockage;

  /// Sites de chaque titre (étape 8). Facultatif pour ne pas casser les
  /// appelants existants : sans lui, un titre n'a que son site principal et
  /// l'ajout ou le retrait d'un site est refusé.
  final DepotTitresSources? _depotTitresSources;

  /// Langues de lecture par défaut (« fr,en »), tant que le client n'a rien
  /// choisi dans les réglages.
  ///
  /// Gardée pour l'interface existante ; le repli réel est désormais le
  /// réglage général (`ServiceParametres.chargerLangues`).
  static final String languesParDefaut = languesParDefautClient.join(',');

  /// Nom donné à la source MangaDex quand elle est ajoutée automatiquement.
  static const String nomSourceMangaDex = 'MangaDex';

  /// Couvertures déjà téléchargées pendant cette session, par URL, de la
  /// moins récemment demandée à la plus récente (l'ordre d'insertion d'une
  /// `Map` Dart sert de liste « LRU »).
  ///
  /// Évite de redemander la même image au site à chaque affichage de la
  /// grille (règle de charge des sites, PLAYBOOK.md section 10). Bornée par
  /// [tailleMaximaleCacheCouvertures] et [nombreMaximalCouverturesEnCache].
  // Sans borne, chaque originale ouverte (~1,5 Mo) et chaque image de
  // l'écran de choix resteraient en mémoire jusqu'à la fermeture.
  final Map<String, Future<Uint8List>> _cacheCouvertures =
      <String, Future<Uint8List>>{};

  /// Taille des couvertures arrivées de [_cacheCouvertures] (les demandes
  /// en cours n'y figurent pas encore).
  final Map<String, int> _taillesCouvertures = <String, int>{};

  /// Somme des valeurs de [_taillesCouvertures].
  int _tailleCacheCouvertures = 0;

  /// Couvertures dont le téléchargement a échoué pendant cette session : la
  /// grille ne les redemande pas à chaque affichage (charge des sites). Une
  /// actualisation du titre ou un choix explicite du client réessaie.
  final Set<String> _couverturesEnEchec = <String>{};

  // ---------------------------------------------------------------- Lecture

  /// Titres de la bibliothèque, avec les filtres de `DepotTitres.chargerTitres`.
  ///
  /// [niveauxContenu] : niveaux affichés (en général
  /// `ServiceParametres.chargerNiveauxContenu`) ; `null` = pas de filtre. Les
  /// titres sans niveau connu (sites autres que MangaDex) restent affichés si
  /// [inclureNiveauInconnu] vaut `true`.
  Future<List<Titre>> chargerTitres({
    String? recherche,
    int? idListe,
    int? idCategorie,
    List<String>? niveauxContenu,
    bool inclureNiveauInconnu = true,
  }) => _depotTitres.chargerTitres(
    recherche: recherche,
    idListe: idListe,
    idCategorie: idCategorie,
    niveauxContenu: niveauxContenu,
    inclureNiveauInconnu: inclureNiveauInconnu,
  );

  /// Un titre par son identifiant, ou `null`.
  Future<Titre?> chargerTitre(int idTitre) =>
      _depotTitres.chargerTitre(idTitre);

  /// Toutes les listes, système d'abord (ordre de la base).
  Future<List<ListeLecture>> chargerListes() => _depotListes.chargerListes();

  /// Listes qui contiennent le titre.
  Future<List<ListeLecture>> chargerListesDuTitre(int idTitre) =>
      _depotListes.chargerListesDuTitre(idTitre);

  /// Toutes les catégories connues.
  Future<List<Categorie>> chargerCategories() =>
      _depotCategories.chargerCategories();

  /// Catégories d'un titre.
  Future<List<Categorie>> chargerCategoriesDuTitre(int idTitre) =>
      _depotCategories.chargerCategoriesDuTitre(idTitre);

  /// Chapitres d'un titre, triés par numéro ; si [idSource] est donné,
  /// seulement ceux venant de ce site (filtre « site » de la fiche, étape 8).
  /// Chaque chapitre porte son site d'origine (`Chapitre.idSource`).
  Future<List<Chapitre>> chargerChapitres(int idTitre, {int? idSource}) =>
      _depotChapitres.chargerChapitres(idTitre, idSource: idSource);

  /// Un chapitre par son identifiant, ou `null` s'il n'existe plus (titre
  /// supprimé entre-temps, par exemple).
  Future<Chapitre?> chargerChapitre(int idChapitre) =>
      _depotChapitres.chargerChapitre(idChapitre);

  /// Langues préférées d'un site (codes ISO 639-1, par ordre de préférence) :
  /// celles réglées pour [source], sinon [general] (le réglage général du
  /// client, `ServiceParametres.chargerLangues`), sinon [languesParDefaut].
  ///
  /// Même règle que les téléchargements automatiques : l'interface s'en sert
  /// pour mettre en avant la version d'un chapitre que le service télécharge.
  /// Fonction pure (pas de base ni de réseau), d'où le `static`.
  ///
  /// Avec [titre], ses langues propres (choisies par le client pour ce
  /// titre) passent avant tout le reste.
  ///
  /// [plusieursSites] : le titre a plusieurs sites (étape 8). Les langues
  /// propres de [source] sont alors ignorées : ordre = langues du titre,
  /// sinon [general].
  static List<String> languesPreferees(
    Source? source, {
    List<String>? general,
    Titre? titre,
    bool plusieursSites = false,
  }) {
    final propresAuTitre = ServiceParametres.nettoyerLangues(
      titre?.listeLanguesPreferees ?? const <String>[],
    );
    if (propresAuTitre.isNotEmpty) return propresAuTitre;
    // Relecture B1 : les langues d'un site ne décrivent que ce site. Pour un
    // titre à plusieurs sites, prendre celles du site principal ferait
    // dépendre ses langues de ce choix : passer de MangaDex à un site
    // français effacerait (24 h plus tard) toutes ses archives anglaises,
    // et un titre ajouté depuis un site français ne téléchargerait jamais
    // l'anglais de MangaDex.
    final langues = plusieursSites
        ? const <String>[]
        : SourceMangaDex.languesIsoDepuisPreference(
            source?.langueParDefaut ?? '',
          );
    if (langues.isNotEmpty) return langues;
    final propres = ServiceParametres.nettoyerLangues(general ?? const []);
    return propres.isNotEmpty
        ? propres
        : List<String>.of(languesParDefautClient);
  }

  /// Langues du réglage général du client.
  Future<List<String>> chargerLanguesGenerales() async =>
      await _serviceParametres?.chargerLangues() ??
      List<String>.of(languesParDefautClient);

  /// Langues à appliquer à [titre] (règles de téléchargement, version mise en
  /// avant), par ordre de préférence : langues propres au titre, sinon
  /// langues de sa source si elles sont réglées (ancien réglage par site,
  /// gardé pour compatibilité, et seulement pour un titre à un seul site),
  /// sinon réglage général.
  Future<List<String>> languesPourTitre(Titre titre) async {
    final idSource = titre.idSource;
    final source = idSource == null
        ? null
        : await _depotSources.chargerSource(idSource);
    return languesPreferees(
      source,
      general: await chargerLanguesGenerales(),
      titre: titre,
      plusieursSites: await _aPlusieursSites(titre.id),
    );
  }

  /// `true` si le titre [idTitre] a plus d'un site **lu** (sans dépôt des
  /// sites : un seul).
  Future<bool> _aPlusieursSites(int? idTitre) async {
    final depot = _depotTitresSources;
    if (depot == null || idTitre == null) return false;
    // Un lien seul ne fournit aucun chapitre : il ne change pas les langues
    // retenues pour le titre (tâche T4).
    final liens = await depot.chargerLiensTitre(idTitre);
    return liens.where((lien) => !lien.estLienSeul).length > 1;
  }

  /// Enregistre les langues propres à un titre ([langues] `null` ou vide :
  /// retour au réglage général). Les codes invalides sont ignorés. Le
  /// classement « En attente » du titre est ensuite recalculé.
  ///
  /// N'applique pas les règles de téléchargement : utiliser
  /// `ServiceTelechargement.modifierLanguesTitre`, qui enregistre de la même
  /// façon puis applique les règles (ce service ne dépend pas du service de
  /// téléchargement, qui lui dépend de celui-ci). Les chapitres d'une
  /// nouvelle langue n'apparaissent qu'à la prochaine actualisation du titre
  /// ([actualiserTitre]). Lève une [ErreurService] si le titre n'existe plus.
  Future<void> modifierLanguesTitre(int idTitre, List<String>? langues) async {
    await enregistrerLanguesTitre(_depotTitres, idTitre, langues);
    await _classerEnAttenteSansErreur(idTitre);
  }

  /// Écriture commune à [modifierLanguesTitre] et à
  /// `ServiceTelechargement.modifierLanguesTitre` : codes nettoyés, `null`
  /// ou liste vide = retour au réglage général. Lève une [ErreurService] si
  /// le titre n'existe plus.
  static Future<void> enregistrerLanguesTitre(
    DepotTitres depotTitres,
    int idTitre,
    List<String>? langues,
  ) async {
    final propres = ServiceParametres.nettoyerLangues(
      langues ?? const <String>[],
    );
    final bool modifie;
    try {
      modifie = await depotTitres.enregistrerLanguesPreferees(
        idTitre,
        propres.isEmpty ? null : propres.join(','),
      );
    } on ArgumentError {
      // Ne devrait pas arriver (codes déjà nettoyés), mais un code refusé par
      // le dépôt ne doit pas remonter comme une erreur de programmation.
      throw const ErreurService('Une des langues choisies est invalide.');
    }
    if (!modifie) {
      throw const ErreurService("Ce titre n'existe plus.");
    }
  }

  /// Nom lisible du site d'un chapitre externe (`Chapitre.urlExterne`), pour
  /// le bouton « Lire sur `site` » : « MANGA Plus », « VIZ », sinon le nom
  /// de domaine sans `www.`. Délègue à `SourceMangaDex.nomSiteExterne` :
  /// l'interface n'importe pas `lib/sources`. Fonction pure.
  static String nomSiteExterne(String urlExterne) =>
      SourceMangaDex.nomSiteExterne(urlExterne);

  /// Sites configurés.
  Future<List<Source>> chargerSources() => _depotSources.chargerSources();

  /// Source d'un titre, ou `null`.
  Future<Source?> chargerSource(int idSource) =>
      _depotSources.chargerSource(idSource);

  // ------------------------------------------------------- Ajout de titres

  /// Ajoute (ou actualise) le titre situé à [urlTitre] : fiche, catégories,
  /// chapitres et couverture (enregistrée sur l'appareil).
  ///
  /// Le site doit déjà être configuré, sauf MangaDex, reconnu par son domaine
  /// et ajouté automatiquement. Le titre est placé dans les listes
  /// [idsListes] (par exemple Favoris et Suivis), puis dans « En attente »
  /// s'il n'a aucun chapitre dans les langues du client.
  ///
  /// Si [urlTitre] est déjà l'adresse d'un **site secondaire** d'un titre de
  /// la bibliothèque (étape 8), ce titre est renvoyé sans requête au site
  /// (`ResultatAjoutTitre.estDejaPresent`), après l'avoir placé dans
  /// [idsListes] : il n'est jamais créé une seconde fois.
  ///
  /// Lève une [ErreurService] si aucun site ne correspond, sinon laisse
  /// passer `ErreurSource` (complétée du type du site, pour le rapport
  /// d'erreur) et `ErreurBaseDeDonnees`.
  Future<ResultatAjoutTitre> ajouterTitreDepuisUrl(
    String urlTitre, {
    List<int> idsListes = const <int>[],
  }) async {
    final existant = await _chargerTitreLieEnSecondaire(urlTitre.trim());
    if (existant != null) {
      return _renvoyerTitreExistant(existant, idsListes);
    }
    final source = await _trouverOuAjouterSource(urlTitre);
    return _enregistrerDepuisSource(
      source,
      urlTitre.trim(),
      idsListes: idsListes,
    );
  }

  /// Relit la fiche et les chapitres d'un titre déjà enregistré, sur **tous**
  /// ses sites (étape 8) : la fiche (nom, couverture, résumé, catégories)
  /// vient seulement du site principal, les chapitres de chaque site.
  ///
  /// Les sites sont interrogés l'un après l'autre (une requête par site,
  /// toujours avec le délai par domaine de `ClientHttpPoli`). Un site en
  /// panne n'empêche pas les autres : son erreur est rangée dans
  /// `ResultatAjoutTitre.erreursParSite`. Si **aucun** site n'a répondu, la
  /// première erreur est levée (comme avant l'étape 8). Les sites
  /// secondaires d'une source désactivée sont ignorés ; le site principal
  /// est toujours interrogé (actualisation demandée par le client). Les
  /// liens seuls (tâche T4) ne sont jamais interrogés.
  Future<ResultatAjoutTitre> actualiserTitre(Titre titre) async {
    final idTitre = titre.id;
    if (idTitre == null) {
      throw ErreurService("« ${titre.nom} » n'est pas enregistré.");
    }
    final liens = await chargerLiensDuTitre(titre);
    if (liens.isEmpty) {
      throw ErreurService('Le site de « ${titre.nom} » n\'existe plus.');
    }
    final erreurs = <int, Object>{};
    Object? premiereErreur;
    StackTrace? pileErreur;
    var nouveaux = 0;
    var reussis = 0;
    for (final lien in liens) {
      // Lien seul : le client l'a enregistré parce que l'application ne sait
      // pas lire ce site ; l'interroger ne ferait qu'une erreur de plus et
      // une requête inutile (PLAYBOOK.md section 10).
      if (lien.estLienSeul) continue;
      try {
        final source = await _depotSources.chargerSource(lien.idSource);
        if (source == null) {
          throw ErreurService(
            'Le site n°${lien.idSource} de « ${titre.nom} » n\'existe plus.',
          );
        }
        if (!lien.estPrincipale && !source.estActive) continue;
        final resultat = await _actualiserLien(
          titre,
          lien,
          source,
          classer: false,
        );
        nouveaux += resultat.nombreNouveauxChapitres;
        reussis++;
      } catch (erreur, pile) {
        // Une erreur de programmation ne doit pas passer pour un site en
        // panne : elle remonte telle quelle.
        if (erreur is Error) rethrow;
        erreurs[lien.idSource] = erreur;
        premiereErreur ??= erreur;
        pileErreur ??= pile;
      }
    }
    if (reussis == 0 && premiereErreur != null) {
      Error.throwWithStackTrace(premiereErreur, pileErreur!);
    }
    // Classement une seule fois, après les chapitres de tous les sites.
    final estEnAttente = await _classerEnAttenteSansErreur(idTitre);
    final relu = await _depotTitres.chargerTitre(idTitre) ?? titre;
    return ResultatAjoutTitre(
      relu,
      nouveaux,
      estEnAttente: estEnAttente,
      erreursParSite: erreurs,
    );
  }

  /// Actualise un seul site du titre : le principal (fiche et chapitres,
  /// comme [actualiserTitre] avant l'étape 8) ou un secondaire (chapitres
  /// seulement).
  ///
  /// Sert à `ServiceMisesAJour`, qui regroupe les requêtes par site pour
  /// n'interroger qu'un titre à la fois par site. Lève une [ErreurService] si
  /// ce site n'est pas lié au titre, et laisse passer `ErreurSource` (site
  /// injoignable) et `ErreurBaseDeDonnees`. Pour un lien seul (tâche T4),
  /// renvoie le titre tel quel, sans requête.
  Future<ResultatAjoutTitre> actualiserSiteDuTitre(
    Titre titre,
    int idSource,
  ) async {
    LienTitreSource? lien;
    for (final candidat in await chargerLiensDuTitre(titre)) {
      if (candidat.idSource == idSource) lien = candidat;
    }
    if (lien == null) {
      throw ErreurService("Ce site n'est plus lié à « ${titre.nom} ».");
    }
    if (lien.estLienSeul) return ResultatAjoutTitre(titre, 0);
    final source = await _depotSources.chargerSource(idSource);
    if (source == null) {
      throw ErreurService('Le site de « ${titre.nom} » n\'existe plus.');
    }
    return _actualiserLien(titre, lien, source);
  }

  /// Actualise le site [lien] du titre (voir [actualiserSiteDuTitre]) ;
  /// [classer] : recalculer « En attente » à la fin.
  Future<ResultatAjoutTitre> _actualiserLien(
    Titre titre,
    LienTitreSource lien,
    Source source, {
    bool classer = true,
  }) {
    if (lien.estPrincipale) {
      return _enregistrerDepuisSource(
        source,
        lien.urlTitre,
        titre: titre,
        classer: classer,
      );
    }
    return _enregistrerChapitresDuSite(
      titre,
      source,
      lien.urlTitre,
      classer: classer,
    );
  }

  /// Récupère les chapitres d'un site **secondaire** du titre et enregistre
  /// les nouveaux avec leur site d'origine. La fiche n'est jamais lue sur
  /// un site secondaire (elle vient du principal).
  Future<ResultatAjoutTitre> _enregistrerChapitresDuSite(
    Titre titre,
    Source source,
    String urlTitre, {
    bool classer = true,
  }) async {
    final idTitre = titre.id!;
    final idSource = source.id!;
    final adaptateur = await _creerAdaptateur(source, titre: titre);
    // Réseau d'abord : un site qui ne répond pas n'écrit rien.
    final List<Chapitre> chapitres;
    try {
      chapitres = await adaptateur.recupererChapitres(urlTitre);
    } on ErreurSource catch (erreur) {
      throw erreur.avecContexte(typeDetecte: source.typeSource);
    }
    final nouveaux = await _depotChapitres.enregistrerChapitres(<Chapitre>[
      for (final chapitre in chapitres) chapitre.copierAvec(idTitre: idTitre),
    ], idSource: idSource);
    await _depotTitres.enregistrerDateVerification(
      idTitre,
      DateTime.now().toUtc(),
    );
    final estEnAttente = classer
        ? await _classerEnAttenteSansErreur(idTitre)
        : false;
    final relu = await _depotTitres.chargerTitre(idTitre) ?? titre;
    return ResultatAjoutTitre(relu, nouveaux, estEnAttente: estEnAttente);
  }

  // ------------------------------------------- Sites d'un titre (étape 8)

  /// Sites du titre : le principal d'abord, puis les secondaires dans
  /// l'ordre d'ajout.
  ///
  /// Sans dépôt des sites (ancien assemblage), ou si la table ne connaît pas
  /// le titre, seul le site principal est renvoyé (reconstruit depuis
  /// `Titre.idSource` / `Titre.urlTitre`). Liste vide si le titre n'a aucun
  /// site connu.
  Future<List<LienTitreSource>> chargerLiensDuTitre(Titre titre) async {
    final idTitre = titre.id;
    final depot = _depotTitresSources;
    if (depot != null && idTitre != null) {
      final liens = await depot.chargerLiensTitre(idTitre);
      if (liens.isNotEmpty) return liens;
    }
    final idSource = titre.idSource;
    if (idTitre == null || idSource == null) return const <LienTitreSource>[];
    return <LienTitreSource>[
      LienTitreSource(
        idTitre: idTitre,
        idSource: idSource,
        urlTitre: titre.urlTitre,
        estPrincipale: true,
      ),
    ];
  }

  /// Sites du titre [idTitre] pour la section « Sites » de la fiche : nom du
  /// site et nombre de chapitres connus de chacun, principal d'abord. Liste
  /// vide si le titre n'existe plus. Base seulement.
  Future<List<SiteDuTitre>> chargerSitesDuTitre(int idTitre) async {
    final titre = await _depotTitres.chargerTitre(idTitre);
    if (titre == null) return const <SiteDuTitre>[];
    final liens = await chargerLiensDuTitre(titre);
    // Une seule lecture des chapitres, comptés par site (un chapitre sans
    // site connu vient du site principal).
    final parSite = <int, int>{};
    for (final chapitre in await _depotChapitres.chargerChapitres(idTitre)) {
      final idSource = chapitre.idSource ?? titre.idSource;
      if (idSource != null) parSite[idSource] = (parSite[idSource] ?? 0) + 1;
    }
    final sites = <SiteDuTitre>[];
    for (final lien in liens) {
      final source = await _depotSources.chargerSource(lien.idSource);
      sites.add(
        SiteDuTitre(
          lien: lien,
          source: source,
          nomSite: source?.nom ?? _nomDomaine(lien.urlTitre),
          nombreChapitres: parSite[lien.idSource] ?? 0,
        ),
      );
    }
    return sites;
  }

  /// Ajoute un autre site au titre [idTitre] : [urlTitre] est l'adresse du
  /// même titre sur ce site (bouton « Ajouter un autre site » de la fiche).
  /// Renvoie le titre relu et le nombre de chapitres ajoutés depuis ce site.
  ///
  /// Le site est retrouvé parmi les sites configurés par le domaine de
  /// l'adresse. S'il n'est pas configuré, il n'est ajouté automatiquement
  /// que s'il est reconnu par son domaine (MangaDex, Scan-Manga, WEBTOON) ;
  /// sinon le client doit d'abord l'ajouter dans « Sources ».
  ///
  /// Réseau d'abord : la fiche est demandée au site pour vérifier que
  /// l'adresse est bien celle d'un titre (une page d'accueil ou de chapitre
  /// échoue), puis ses chapitres. Rien n'est écrit si le site ne répond pas.
  /// L'adresse retenue est celle que le site donne pour ce titre (forme
  /// canonique), comme pour le site principal.
  ///
  /// [lienSeul] à `true` (tâche T4, « Ajouter quand même comme simple
  /// lien ») : **aucune requête** au site. L'adresse est enregistrée telle
  /// quelle comme lien seul (ouverte dans le navigateur, aucun chapitre lu).
  /// Le site est retrouvé parmi les sites configurés, sinon créé d'après le
  /// domaine (type reconnu par le domaine, à défaut générique). Renvoie le
  /// titre relu et 0 chapitre.
  ///
  /// Lève une [ErreurService] (adresse déjà liée à ce titre ou à un autre,
  /// site déjà lié, site non configuré ou réglages illisibles, titre
  /// disparu) ou une `ErreurSource` (adresse invalide, site injoignable,
  /// protection anti-robot, page qui n'est pas un titre ou sans chapitre).
  /// [peutAjouterCommeLienSeul] dit si l'interface peut alors proposer de
  /// réessayer avec [lienSeul].
  ///
  /// L'interface applique ensuite les règles de téléchargement du titre
  /// (`ServiceTelechargement.appliquerRegles`).
  Future<ResultatAjoutTitre> ajouterSiteAuTitre(
    int idTitre,
    String urlTitre, {
    bool lienSeul = false,
  }) async {
    final depot = _exigerDepotTitresSources();
    final uri = DetecteurTypeSite.validerUrl(urlTitre);
    final url = urlTitre.trim();
    final titre = await _exigerTitre(idTitre);
    await _refuserAdresseDejaLiee(depot, url, titre);
    final source = lienSeul
        ? await _trouverOuPreparerSourceLienSeul(url, uri)
        : await _trouverOuPreparerSource(url, uri);
    final liens = await depot.chargerLiensTitre(idTitre);
    if (source.id != null && liens.any((l) => l.idSource == source.id)) {
      throw ErreurService(
        "Le site « ${source.nom} » est déjà lié à « ${titre.nom} ». Pour "
        "changer d'adresse, retirez-le d'abord.",
      );
    }
    if (lienSeul) return _enregistrerLienSeul(depot, titre, source, url);

    final SourceSite adaptateur;
    try {
      adaptateur = await _creerAdaptateur(source, titre: titre);
    } on ErreurSource catch (erreur) {
      // Depuis l'adaptateur générique (T2), tous les types ont un
      // adaptateur : seule une configuration illisible (sélecteurs JSON d'un
      // site générique) peut encore échouer ici.
      throw ErreurService(
        "Les réglages du site « ${source.nom} » sont illisibles : "
        "corrigez-les dans « Sources ». (${erreur.message})",
        cause: erreur,
        ajoutLienSeulPossible: true,
      );
    }

    // Réseau d'abord : la fiche prouve que l'adresse est bien un titre.
    final FicheTitre fiche;
    final List<Chapitre> chapitres;
    try {
      fiche = await adaptateur.recupererFiche(url);
      chapitres = await adaptateur.recupererChapitres(url);
    } on ErreurSource catch (erreur) {
      throw erreur.avecContexte(typeDetecte: source.typeSource);
    }
    final urlSite = fiche.titre.urlTitre.trim();
    final urlRetenue = urlSite.isEmpty ? url : urlSite;
    if (urlRetenue != url) {
      await _refuserAdresseDejaLiee(depot, urlRetenue, titre);
    }

    // Base ensuite : site (s'il est nouveau), lien, puis chapitres.
    // LIMITE : trois écritures sans transaction commune (chaque dépôt ouvre
    // la sienne) ; si les chapitres échouent, le lien existe sans chapitres
    // et la prochaine actualisation les ajoute.
    try {
      final idSource =
          source.id ?? (await _depotSources.enregistrerSource(source)).id!;
      await depot.ajouterSourceSecondaire(idTitre, idSource, urlRetenue);
      final nouveaux = await _depotChapitres.enregistrerChapitres(<Chapitre>[
        for (final chapitre in chapitres) chapitre.copierAvec(idTitre: idTitre),
      ], idSource: idSource);
      final estEnAttente = await _classerEnAttenteSansErreur(idTitre);
      final relu = await _depotTitres.chargerTitre(idTitre) ?? titre;
      return ResultatAjoutTitre(relu, nouveaux, estEnAttente: estEnAttente);
    } on ErreurBaseDeDonnees catch (erreur) {
      // Messages du dépôt déjà clairs (adresse ou site déjà lié, ajouté
      // entre-temps par un autre écran).
      throw ErreurService(erreur.message, cause: erreur);
    }
  }

  /// Retire le site secondaire [idSource] du titre [idTitre] et renvoie le
  /// nombre de chapitres supprimés.
  ///
  /// Les chapitres non lus et non téléchargés de ce site disparaissent ; les
  /// chapitres lus restent (l'état de lecture n'est jamais perdu). Les
  /// archives déjà téléchargées depuis ce site suivent la règle des 24 h :
  /// leur suppression est prévue dans [delaiSuppressionDifferee] (sauf
  /// chapitre gardé par le client), et le client peut les garder entre-temps.
  ///
  /// Lève une [ErreurService] pour le site principal (en choisir d'abord un
  /// autre avec [definirSitePrincipal]) ou un site qui n'est pas lié au
  /// titre. L'interface applique ensuite les règles de téléchargement du
  /// titre (`ServiceTelechargement.appliquerRegles`).
  Future<int> retirerSiteDuTitre(int idTitre, int idSource) async {
    final depot = _exigerDepotTitresSources();
    final titre = await _exigerTitre(idTitre);
    if (titre.idSource == idSource) {
      throw const ErreurService(
        "Le site principal d'un titre ne peut pas être retiré : choisissez "
        "d'abord un autre site principal.",
      );
    }
    final int supprimes;
    try {
      supprimes = await depot.retirerSourceSecondaire(idTitre, idSource);
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService(erreur.message, cause: erreur);
    }
    // Après le retrait (un retrait refusé ne doit rien programmer).
    await _planifierSuppressionArchivesDuSite(idTitre, idSource);
    await _classerEnAttenteSansErreur(idTitre);
    return supprimes;
  }

  /// Fait du site [idSource], déjà lié au titre [idTitre], son site
  /// principal : la fiche (nom, couverture, résumé, catégories) est relue
  /// sur ce site, avec ses chapitres. L'ancien principal devient secondaire
  /// (ses chapitres restent).
  ///
  /// Réseau d'abord : si le nouveau site ne répond pas, rien ne change et
  /// l'`ErreurSource` est levée. Renvoie le titre relu (sans requête si ce
  /// site est déjà le principal). Lève une [ErreurService] si ce site n'est
  /// pas lié au titre.
  Future<ResultatAjoutTitre> definirSitePrincipal(
    int idTitre,
    int idSource,
  ) async {
    final depot = _exigerDepotTitresSources();
    final titre = await _exigerTitre(idTitre);
    LienTitreSource? lien;
    for (final candidat in await depot.chargerLiensTitre(idTitre)) {
      if (candidat.idSource == idSource) lien = candidat;
    }
    if (lien == null) {
      throw ErreurService("Ce site n'est pas lié à « ${titre.nom} ».");
    }
    if (lien.estPrincipale) return ResultatAjoutTitre(titre, 0);
    if (lien.estLienSeul) {
      // Refusé avant toute requête : le dépôt le refuserait aussi, mais
      // seulement après une lecture inutile d'un site qu'on sait illisible.
      throw const ErreurService(
        "Ce site est un simple lien : l'application ne sait pas le lire, il "
        'ne peut donc pas devenir le site principal.',
      );
    }
    final source = await _depotSources.chargerSource(idSource);
    if (source == null) {
      throw const ErreurService("Ce site n'existe plus.");
    }
    final (fiche, chapitres) = await _recupererDepuisSite(
      source,
      lien.urlTitre,
      titre: titre,
    );
    try {
      await depot.definirSourcePrincipale(idTitre, idSource);
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService(erreur.message, cause: erreur);
    }
    final apres = await _depotTitres.chargerTitre(idTitre) ?? titre;
    // LIMITE : la fiche du nouveau site principal peut changer le nom ou le
    // type du titre. Les nouvelles archives iront alors dans un autre
    // dossier que les anciennes ; celles d'avant la migration 4 (sans
    // `nom_archive` en base) seraient recherchées dans le nouveau dossier
    // et deviendraient introuvables.
    return _ecrireDepuisSite(
      source,
      lien.urlTitre,
      fiche,
      chapitres,
      titre: apres,
      ancien: titre,
    );
  }

  /// Dépôt des sites, ou [ErreurService] s'il n'a pas été fourni.
  DepotTitresSources _exigerDepotTitresSources() {
    final depot = _depotTitresSources;
    if (depot == null) {
      throw const ErreurService(
        "Les sites multiples ne sont pas disponibles dans cette version.",
      );
    }
    return depot;
  }

  /// Lève une [ErreurService] si [url] est déjà l'adresse d'un site d'un
  /// titre (celui-ci ou un autre).
  Future<void> _refuserAdresseDejaLiee(
    DepotTitresSources depot,
    String url,
    Titre titre,
  ) async {
    final lien = await depot.chargerLienParUrl(url);
    if (lien == null) return;
    if (lien.idTitre == titre.id) {
      throw ErreurService(
        "Cette adresse est déjà un site de « ${titre.nom} ».",
      );
    }
    final autre = await _depotTitres.chargerTitre(lien.idTitre);
    throw ErreurService(
      "Cette adresse est déjà celle du titre « ${autre?.nom ?? '?'} » dans "
      'votre bibliothèque.',
    );
  }

  /// Site configuré pour [url] ; sinon, pour un site reconnu par son domaine
  /// (MangaDex, Scan-Manga), une source **non enregistrée** (sans `id`),
  /// écrite seulement après la lecture réussie du titre. Lève une
  /// [ErreurService] pour un site inconnu.
  Future<Source> _trouverOuPreparerSource(String url, Uri uri) async {
    final existante = await _serviceAjoutSite.trouverSourcePourUrl(url);
    if (existante != null) return existante;
    final type = DetecteurTypeSite.verifierDomaine(uri);
    if (type == null) {
      // La détection d'un autre site demande de télécharger sa page
      // d'accueil et de laisser le client corriger le type : c'est le rôle
      // de l'écran d'ajout de site.
      throw const ErreurService(
        "Ce site n'est pas encore configuré : ajoutez-le d'abord dans "
        '« Sources », puis réessayez.',
        ajoutLienSeulPossible: true,
      );
    }
    return _preparerSourceParDomaine(uri, type);
  }

  /// Source **non enregistrée** pour le domaine de [uri] et le [type] : la
  /// source par défaut de ce type si elle existe (nom et adresse
  /// officiels), sinon une source nommée d'après le domaine.
  static Source _preparerSourceParDomaine(Uri uri, TypeSource type) {
    for (final parDefaut in sourcesParDefaut) {
      if (parDefaut.typeSource == type) return parDefaut.versSource();
    }
    return Source(
      nom: ServiceAjoutSite.proposerNom(uri),
      urlBase: ServiceAjoutSite.calculerUrlBase(uri),
      typeSource: type,
    );
  }

  /// Comme [_trouverOuPreparerSource], mais pour un lien seul (tâche T4) :
  /// un site inconnu n'est pas refusé. Son type ne peut pas être détecté
  /// sans requête (rien n'est demandé au site) : il est créé **générique**,
  /// type que le client peut corriger dans « Sources » le jour où il veut
  /// le lire.
  Future<Source> _trouverOuPreparerSourceLienSeul(String url, Uri uri) async {
    final existante = await _serviceAjoutSite.trouverSourcePourUrl(url);
    if (existante != null) return existante;
    return _preparerSourceParDomaine(
      uri,
      DetecteurTypeSite.verifierDomaine(uri) ?? TypeSource.generique,
    );
  }

  /// Écritures d'un lien seul (voir [ajouterSiteAuTitre]) : le site s'il est
  /// nouveau, puis le lien. Aucun chapitre, donc ni classement « En
  /// attente » à refaire ni règle de téléchargement concernée.
  Future<ResultatAjoutTitre> _enregistrerLienSeul(
    DepotTitresSources depot,
    Titre titre,
    Source source,
    String url,
  ) async {
    final idTitre = titre.id!;
    // LIMITE : deux écritures sans transaction commune (chaque dépôt ouvre
    // la sienne) ; si le lien échoue, le site créé reste dans « Sources »
    // sans titre, et le client peut le supprimer.
    try {
      final idSource =
          source.id ?? (await _depotSources.enregistrerSource(source)).id!;
      await depot.ajouterSourceSecondaire(
        idTitre,
        idSource,
        url,
        lienSeul: true,
      );
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService(erreur.message, cause: erreur);
    }
    final relu = await _depotTitres.chargerTitre(idTitre) ?? titre;
    return ResultatAjoutTitre(relu, 0);
  }

  /// `true` si l'échec [erreur] de [ajouterSiteAuTitre] permet de proposer
  /// au client « Ajouter quand même comme simple lien » (tâche T4) : site
  /// illisible (protection anti-robot, page sans chapitre, site injoignable,
  /// erreur HTTP), non configuré, ou aux réglages illisibles. `false` pour
  /// une adresse invalide ou un refus qui resterait vrai pour un lien seul
  /// (adresse ou site déjà lié, titre disparu). Fonction pure.
  static bool peutAjouterCommeLienSeul(Object erreur) {
    if (erreur is ErreurService) return erreur.ajoutLienSeulPossible;
    if (erreur is ErreurSource) {
      // Une adresse invalide lève aussi une ErreurSource : un lien seul ne
      // la rendrait pas plus valide. Toute autre ErreurSource vient de la
      // lecture du site, après validation de l'adresse.
      final uri = Uri.tryParse(erreur.url.trim());
      return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    }
    return false;
  }

  /// Passe le site secondaire [idSource] du titre [idTitre] en lien seul
  /// ([lienSeul] à `true`) ou de nouveau en site lu (`false`, par exemple
  /// quand un site redevient lisible). Renvoie le nombre de chapitres
  /// supprimés. Base seulement (aucune requête).
  ///
  /// Passage en lien seul : comme un retrait du site
  /// ([retirerSiteDuTitre]), ses chapitres non lus, non téléchargés et non
  /// gardés disparaissent, les lus restent, et ses archives suivent la règle
  /// des 24 h. Passage en site lu : aucun chapitre n'est touché ; ils
  /// arrivent à la prochaine actualisation ([actualiserTitre]).
  ///
  /// Lève une [ErreurService] pour le site principal (un lien seul ne peut
  /// pas l'être) ou un site qui n'est pas lié au titre. L'interface applique
  /// ensuite les règles de téléchargement du titre
  /// (`ServiceTelechargement.appliquerRegles`).
  Future<int> marquerLienSeul(int idTitre, int idSource, bool lienSeul) async {
    final depot = _exigerDepotTitresSources();
    await _exigerTitre(idTitre);
    final int supprimes;
    try {
      supprimes = await depot.marquerLienSeul(idTitre, idSource, lienSeul);
    } on ErreurBaseDeDonnees catch (erreur) {
      throw ErreurService(erreur.message, cause: erreur);
    }
    if (lienSeul) {
      await _planifierSuppressionArchivesDuSite(idTitre, idSource);
      await _classerEnAttenteSansErreur(idTitre);
    }
    return supprimes;
  }

  /// Programme dans [delaiSuppressionDifferee] la suppression des archives
  /// du site [idSource] du titre (site retiré ou devenu lien seul), sauf
  /// chapitre gardé par le client ou suppression déjà prévue.
  Future<void> _planifierSuppressionArchivesDuSite(
    int idTitre,
    int idSource,
  ) async {
    // LIMITE : hors de la transaction du dépôt ; si ces écritures échouent,
    // la prochaine application des règles de téléchargement les programme
    // (les chapitres d'un site retiré ou d'un lien seul y sont à supprimer).
    final echeance = DateTime.now().toUtc().add(delaiSuppressionDifferee);
    for (final chapitre in await _depotChapitres.chargerChapitres(
      idTitre,
      idSource: idSource,
    )) {
      final id = chapitre.id;
      if (id == null ||
          !chapitre.estTelecharge ||
          chapitre.estGarde ||
          chapitre.dateSuppressionPrevue != null) {
        continue;
      }
      await _depotChapitres.planifierSuppression(id, echeance);
    }
  }

  /// Diagnostic de lisibilité de la page [url] (tâche T3, aide « critères
  /// de lecture ») : protection anti-robot, raisons pour lesquelles la page
  /// ne serait pas lue, remarques.
  ///
  /// **Une requête au plus** (via `ClientHttpPoli`, délai par domaine
  /// compris) ; aucune pour une adresse invalide ou un site reconnu par son
  /// domaine (MangaDex, Scan-Manga, WEBTOON : adaptateur dédié). Les
  /// critères appliqués sont ceux de l'adaptateur générique ; pour un site
  /// Madara ou MangaThemesia (configuré ou reconnu dans la page), seules la
  /// protection et les erreurs HTTP comptent. Ne lève jamais : un site
  /// injoignable donne un diagnostic avec la raison « injoignable ».
  Future<DiagnosticLisibilite> diagnostiquerSite(String url) async {
    final Uri uri;
    try {
      uri = DetecteurTypeSite.validerUrl(url);
    } on ErreurSource catch (erreur) {
      return DiagnosticLisibilite(raisons: <String>[erreur.message]);
    }
    Source? source;
    try {
      source = await _serviceAjoutSite.trouverSourcePourUrl(url);
    } catch (erreur) {
      // Base illisible : le diagnostic se fait sans les réglages du site.
      debugPrint('Diagnostic de $url : site configuré illisible : $erreur');
    }
    final type = source?.typeSource ?? DetecteurTypeSite.verifierDomaine(uri);
    if (type != null && estTypeAAdaptateurParDomaine(type)) {
      return DiagnosticLisibilite(
        raisons: const <String>[],
        remarques: <String>[
          'Site reconnu (${nomTypeSource(type)}) : il est lu par un '
              'adaptateur dédié, les critères des sites génériques ne '
              "s'appliquent pas.",
        ],
      );
    }
    final String html;
    try {
      html = await _client.recupererTexte(uri);
    } on ErreurSource catch (erreur) {
      return diagnosticDepuisErreur(erreur, uri);
    } catch (erreur) {
      if (erreur is Error) rethrow;
      return DiagnosticLisibilite(
        raisons: <String>['Le site est injoignable : $erreur'],
      );
    }
    final typeLu = type ?? DetecteurTypeSite.detecterDepuisHtml(html);
    if (typeLu != TypeSource.generique) {
      // Madara / MangaThemesia : leurs listes de chapitres ne suivent pas
      // les critères génériques (chargées à part chez Madara) ; la page a
      // été reçue sans défi ni erreur, c'est tout ce qu'on peut vérifier.
      return DiagnosticLisibilite(
        raisons: const <String>[],
        remarques: <String>[
          'Site de type ${nomTypeSource(typeLu)} : il est lu par un '
              'adaptateur dédié, les critères des sites génériques ne '
              "s'appliquent pas.",
        ],
      );
    }
    return verifierLisibilite(
      html,
      uri,
      configurationSelecteurs: source?.configurationSelecteurs,
    );
  }

  /// Diagnostic d'une page qui n'a pas pu être récupérée ([erreur] du
  /// client HTTP) : protection anti-robot, erreur HTTP ou site injoignable.
  /// Fonction pure, exposée pour les tests.
  @visibleForTesting
  static DiagnosticLisibilite diagnosticDepuisErreur(
    ErreurSource erreur,
    Uri uri,
  ) {
    if (erreur.protectionAntiRobot) {
      return DiagnosticLisibilite(
        raisons: <String>[
          "${messageProtectionAntiRobot(uri.host)}. L'application ne "
              'contourne pas ces protections : lisez ce site dans le '
              'navigateur.',
        ],
        protectionAntiRobot: true,
      );
    }
    final code = erreur.codeStatut;
    if (code != null) {
      // Même formulation que le diagnostic d'une page reçue.
      return verifierLisibilite('', uri, codeStatut: code);
    }
    return DiagnosticLisibilite(
      raisons: <String>['Le site est injoignable : ${erreur.message}.'],
    );
  }

  /// `true` si le [type] désigne un site reconnu par son domaine, lu par un
  /// adaptateur dédié sans analyse de sa page (MangaDex, Scan-Manga,
  /// WEBTOON). Fonction pure.
  static bool estTypeAAdaptateurParDomaine(TypeSource type) =>
      type == TypeSource.mangaDex ||
      type == TypeSource.scanManga ||
      type == TypeSource.webtoons;

  /// Nom lisible d'un type de site (messages du diagnostic). Fonction pure.
  static String nomTypeSource(TypeSource type) => switch (type) {
    TypeSource.mangaDex => 'MangaDex',
    TypeSource.scanManga => 'Scan-Manga',
    TypeSource.webtoons => 'WEBTOON',
    TypeSource.madara => 'WordPress Madara',
    TypeSource.mangaThemesia => 'WordPress MangaThemesia',
    TypeSource.generique => 'générique',
  };

  /// Nom de domaine d'une adresse, sans `www.` (repli d'affichage).
  static String _nomDomaine(String url) {
    final uri = Uri.tryParse(url);
    return uri == null || uri.host.isEmpty
        ? url
        : ServiceAjoutSite.proposerNom(uri);
  }

  /// Titre dont [url] est l'adresse d'un site **secondaire**, ou `null`
  /// (adresse inconnue, site principal, ou dépôt des sites absent).
  Future<Titre?> _chargerTitreLieEnSecondaire(String url) async {
    final lien = await _depotTitresSources?.chargerLienParUrl(url);
    if (lien == null || lien.estPrincipale) return null;
    return _depotTitres.chargerTitre(lien.idTitre);
  }

  /// Ajout d'un titre déjà présent par l'un de ses sites secondaires : il
  /// est placé dans [idsListes] et renvoyé tel quel, sans requête au site.
  Future<ResultatAjoutTitre> _renvoyerTitreExistant(
    Titre titre,
    List<int> idsListes,
  ) async {
    final idTitre = titre.id!;
    for (final idListe in idsListes) {
      await _depotListes.ajouterTitre(idListe, idTitre);
    }
    final estEnAttente = await _classerEnAttenteSansErreur(idTitre);
    final relu = await _depotTitres.chargerTitre(idTitre) ?? titre;
    return ResultatAjoutTitre(
      relu,
      0,
      estEnAttente: estEnAttente,
      estDejaPresent: true,
    );
  }

  /// Recherche des titres sur un site configuré (résultats non enregistrés).
  ///
  /// Les niveaux de contenu demandés au site sont ceux du réglage du client
  /// (`ServiceParametres.chargerNiveauxContenu`, par défaut tout sauf
  /// `pornographic`).
  Future<List<Titre>> rechercherSurSource(Source source, String requete) async {
    final niveaux = await _serviceParametres?.chargerNiveauxContenu();
    try {
      return await _fabriqueSources
          .creer(source, niveauxContenuRecherche: niveaux)
          .rechercher(requete);
    } on ErreurSource catch (erreur) {
      throw erreur.avecContexte(typeDetecte: source.typeSource);
    }
  }

  Future<Source> _trouverOuAjouterSource(String urlTitre) async {
    final existante = await _serviceAjoutSite.trouverSourcePourUrl(urlTitre);
    if (existante != null) {
      return existante;
    }
    final uri = Uri.parse(urlTitre.trim());
    if (SourceMangaDex.estHoteMangaDex(uri.host)) {
      // MangaDex est reconnu par son domaine sans téléchargement : on peut
      // l'ajouter sans demander d'étape supplémentaire au client. Sans
      // langues propres : il suit le réglage général du client, même si
      // celui-ci change plus tard.
      return _serviceAjoutSite.ajouterSite(urlTitre, nom: nomSourceMangaDex);
    }
    throw const ErreurService(
      'Ce site n\'est pas encore configuré : ajoutez-le d\'abord dans « Sources ».',
    );
  }

  /// Adaptateur du site [source], réglé sur les langues utiles.
  ///
  /// Langues demandées au site : celles propres au titre (actualisation),
  /// celles de la source (si réglées) puis celles du réglage général. Un
  /// site sans langues recevrait sinon les chapitres de toutes les langues
  /// (russe, japonais…). FabriqueSources lit les langues dans
  /// `Source.langueParDefaut` : on lui passe une copie. Lève une
  /// `ErreurSource` si le type du site n'a pas encore d'adaptateur.
  Future<SourceSite> _creerAdaptateur(Source source, {Titre? titre}) async {
    final general = await chargerLanguesGenerales();
    final langues = <String>{
      ...languesPreferees(source, general: general, titre: titre),
      ...languesPreferees(source, general: general),
      ...general,
    }.join(',');
    return _fabriqueSources.creer(source.copierAvec(langueParDefaut: langues));
  }

  /// Fiche et chapitres de [urlTitre] sur [source] (réseau seulement).
  Future<(FicheTitre, List<Chapitre>)> _recupererDepuisSite(
    Source source,
    String urlTitre, {
    Titre? titre,
  }) async {
    try {
      final adaptateur = await _creerAdaptateur(source, titre: titre);
      final fiche = await adaptateur.recupererFiche(urlTitre);
      final chapitres = await adaptateur.recupererChapitres(urlTitre);
      return (fiche, chapitres);
    } on ErreurSource catch (erreur) {
      // Le type du site sert au rapport d'erreur exportable (étape 6).
      throw erreur.avecContexte(typeDetecte: source.typeSource);
    }
  }

  /// Ajout ou actualisation depuis le site **principal** : fiche et
  /// chapitres. [classer] : recalculer « En attente » à la fin.
  Future<ResultatAjoutTitre> _enregistrerDepuisSource(
    Source source,
    String urlTitre, {
    List<int> idsListes = const <int>[],
    Titre? titre,
    bool classer = true,
  }) async {
    if (source.id == null) {
      throw ErreurService('Le site « ${source.nom} » n\'est pas enregistré.');
    }
    // Réseau d'abord, base ensuite : si le site ne répond pas, rien n'est
    // écrit.
    final (fiche, chapitres) = await _recupererDepuisSite(
      source,
      urlTitre,
      titre: titre,
    );
    if (titre == null) {
      // Ajout : l'adresse canonique donnée par le site peut être celle d'un
      // site secondaire d'un titre existant (adresse collée sous une autre
      // forme) ; le recréer échouerait sur l'unicité des adresses.
      final existant = await _chargerTitreLieEnSecondaire(
        fiche.titre.urlTitre.trim(),
      );
      if (existant != null) return _renvoyerTitreExistant(existant, idsListes);
    }
    return _ecrireDepuisSite(
      source,
      urlTitre,
      fiche,
      chapitres,
      idsListes: idsListes,
      titre: titre,
      classer: classer,
    );
  }

  /// Écrit en base ce qui a été lu sur le site principal [source].
  ///
  /// [titre] : titre déjà enregistré (actualisation, changement de site
  /// principal), mis à jour par son identifiant sans changer son adresse ;
  /// `null` pour un ajout. [ancien] : état d'avant, pour savoir si la
  /// couverture du site a changé (par défaut [titre]).
  Future<ResultatAjoutTitre> _ecrireDepuisSite(
    Source source,
    String urlTitre,
    FicheTitre fiche,
    List<Chapitre> chapitres, {
    List<int> idsListes = const <int>[],
    Titre? titre,
    Titre? ancien,
    bool classer = true,
  }) async {
    final idSource = source.id!;
    // Côté base, les écritures se font dans l'ordre d'importance pour le
    // client : le titre, puis ses listes (pour qu'un titre ajouté soit
    // toujours visible dans Favoris / Suivis), puis les chapitres. La date de
    // vérification n'est écrite qu'en dernier : si une étape échoue, la
    // prochaine actualisation reprendra les chapitres manquants.
    // LIMITE : ces écritures ne forment pas une seule transaction (les dépôts
    // ouvrent chacun la leur) ; un échec au milieu laisse un titre sans
    // chapitres, rattrapé à l'actualisation suivante.

    // État avant l'écriture : sert à savoir si la couverture du site a
    // changé (pour ne pas la retélécharger à chaque actualisation).
    final avant =
        ancien ?? titre ?? await _depotTitres.chargerTitreParUrl(urlTitre);

    // Le niveau de contenu vient de la fiche (MangaDex : `contentRating`) ;
    // `enregistrerTitre` l'écrit avec le reste de la fiche. Pour un titre
    // connu, l'identifiant et l'adresse enregistrés sont imposés : une
    // adresse donnée sous une autre forme par le site ne doit ni créer un
    // second titre, ni déplacer le site principal.
    final enregistre = await _depotTitres.enregistrerTitre(
      titre == null
          ? fiche.titre.copierAvec(idSource: idSource)
          : fiche.titre.copierAvec(
              id: titre.id,
              idSource: idSource,
              urlTitre: urlTitre,
            ),
      categories: fiche.categories,
    );
    final idTitre = enregistre.id!;
    for (final idListe in idsListes) {
      await _depotListes.ajouterTitre(idListe, idTitre);
    }
    final nouveaux = await _depotChapitres.enregistrerChapitres(
      chapitres
          .map((chapitre) => chapitre.copierAvec(idTitre: idTitre))
          .toList(),
      idSource: idSource,
    );
    await _depotTitres.enregistrerDateVerification(
      idTitre,
      DateTime.now().toUtc(),
    );
    // Classement et couverture après les écritures essentielles, sans
    // jamais faire échouer l'ajout : le classement est refait à chaque
    // vérification, et la couverture à l'affichage suivant.
    final estEnAttente = classer
        ? await _classerEnAttenteSansErreur(idTitre)
        : false;
    final relu = await _depotTitres.chargerTitre(idTitre) ?? enregistre;
    await _mettreAJourCouvertureLocale(avant, relu, source);
    return ResultatAjoutTitre(relu, nouveaux, estEnAttente: estEnAttente);
  }

  // ------------------------------------------------------ Listes, lecture

  /// Ajoute le titre à la liste, puis recalcule son classement « En
  /// attente ».
  ///
  /// Lève une [ErreurService] pour « En attente », tenue automatiquement
  /// par l'application.
  Future<void> ajouterTitreALaListe(int idListe, int idTitre) async {
    await _refuserListeAutomatique(idListe);
    await _depotListes.ajouterTitre(idListe, idTitre);
    await _classerEnAttenteSansErreur(idTitre);
  }

  /// Retire le titre de la liste (le titre reste dans la bibliothèque), puis
  /// recalcule son classement « En attente » (un titre qui n'est plus ni
  /// favori, ni suivi, ni planifié en sort).
  ///
  /// Lève une [ErreurService] pour « En attente », tenue automatiquement
  /// par l'application.
  Future<void> retirerTitreDeLaListe(int idListe, int idTitre) async {
    await _refuserListeAutomatique(idListe);
    await _depotListes.retirerTitre(idListe, idTitre);
    await _classerEnAttenteSansErreur(idTitre);
  }

  Future<void> _refuserListeAutomatique(int idListe) async {
    final liste = await _depotListes.chargerListe(idListe);
    if (liste != null &&
        ClassementListes.listesAutomatiques.contains(liste.nom)) {
      throw ErreurService(
        "La liste « ${liste.nom} » est tenue automatiquement : un titre y "
        "entre quand il n'a aucun chapitre dans vos langues, et en sort dès "
        "qu'un chapitre paraît.",
      );
    }
  }

  /// Crée une liste personnelle.
  Future<ListeLecture> creerListe(String nom) => _depotListes.creerListe(nom);

  /// Supprime une liste personnelle (refusé pour les listes système).
  Future<void> supprimerListe(int idListe) =>
      _depotListes.supprimerListe(idListe);

  /// Supprime un titre, ses chapitres et sa couverture enregistrée.
  ///
  /// Les archives des chapitres ne sont pas effacées : utiliser
  /// `ServiceTelechargement.supprimerTitre`.
  Future<void> supprimerTitre(int idTitre) async {
    final titre = await _depotTitres.chargerTitre(idTitre);
    if (titre != null) {
      try {
        await _stockage?.supprimerCouverture(titre);
      } on ErreurStockage catch (erreur) {
        // Une image restée sur le disque ne doit pas empêcher la suppression
        // demandée par le client.
        debugPrint('Couverture de « ${titre.nom} » non supprimée : $erreur');
      }
    }
    await _depotTitres.supprimerTitre(idTitre);
  }

  /// Marque un chapitre lu ou non lu.
  Future<void> marquerLu(int idChapitre, {bool estLu = true}) =>
      _depotChapitres.marquerLu(idChapitre, estLu: estLu);

  /// Marque tous les chapitres d'un titre lus ou non lus.
  Future<void> marquerTousLus(int idTitre, {bool estLu = true}) =>
      _depotChapitres.marquerTousLus(idTitre, estLu: estLu);

  // -------------------------------------------------- Liste « En attente »

  /// Place le titre dans « En attente » ou l'en retire, selon la règle de
  /// l'étape 6 ([ClassementListes.doitEtreEnAttente]) : favori, suivi ou
  /// planifié sans aucun chapitre dans ses langues ([languesPourTitre]).
  /// Renvoie `true` si le titre est dans « En attente » après l'appel.
  ///
  /// Base seulement (aucun réseau). Sans effet si la liste n'existe pas
  /// (base antérieure à la migration 5) ou si le titre n'existe plus.
  Future<bool> classerEnAttente(int idTitre) async {
    final enAttente = await _depotListes.chargerListeParNom(nomListeEnAttente);
    final idEnAttente = enAttente?.id;
    final titre = await _depotTitres.chargerTitre(idTitre);
    if (idEnAttente == null || titre == null) return false;
    final noms = (await _depotListes.chargerListesDuTitre(idTitre))
        .map((liste) => liste.nom)
        .toSet();
    final langues = await languesPourTitre(titre);
    final doit = ClassementListes.doitEtreEnAttente(
      nomsListes: noms,
      aChapitreDansLesLangues: ClassementListes.aChapitreDansLesLangues(
        await _depotChapitres.chargerChapitres(idTitre),
        langues,
      ),
    );
    final estDedans = noms.contains(nomListeEnAttente);
    if (doit && !estDedans) {
      await _depotListes.ajouterTitre(idEnAttente, idTitre);
    } else if (!doit && estDedans) {
      await _depotListes.retirerTitre(idEnAttente, idTitre);
    }
    return doit;
  }

  /// Recalcule le classement « En attente » de tous les titres favoris,
  /// suivis, planifiés ou déjà en attente, et renvoie le nombre de titres en
  /// attente.
  ///
  /// À appeler après un changement des langues générales du client
  /// (`ServiceParametres.enregistrerLangues`) ; `ServiceMisesAJour` l'appelle
  /// aussi avant chaque vérification. Un titre en erreur est journalisé et
  /// n'empêche pas les autres.
  Future<int> classerTousEnAttente() async {
    final ids = <int>{};
    for (final nom in <String>{
      ...ClassementListes.listesSurveillees,
      nomListeEnAttente,
    }) {
      final liste = await _depotListes.chargerListeParNom(nom);
      if (liste?.id == null) continue;
      final titres = await _depotTitres.chargerTitres(idListe: liste!.id);
      ids.addAll(titres.map((titre) => titre.id).whereType<int>());
    }
    var nombre = 0;
    for (final idTitre in ids) {
      if (await _classerEnAttenteSansErreur(idTitre)) nombre++;
    }
    return nombre;
  }

  /// Comme [classerEnAttente], sans jamais lever (appel en fin d'ajout ou
  /// de changement de liste, qui ne doivent pas échouer pour si peu).
  Future<bool> _classerEnAttenteSansErreur(int idTitre) async {
    try {
      return await classerEnAttente(idTitre);
    } catch (erreur, pile) {
      debugPrint(
        'Classement « En attente » du titre n°$idTitre : $erreur\n$pile',
      );
      return false;
    }
  }

  // ------------------------------------------------- Onglet Mises à jour

  /// Titres suivis, favoris et en attente, triés par dernière parution dans
  /// leurs langues ([languesPourTitre]), la plus récente d'abord, avec le
  /// dernier chapitre paru. Les titres sans parution dans leurs langues
  /// viennent ensuite, par nom.
  ///
  /// Base seulement (aucun réseau) : une requête de dates par jeu de langues
  /// distinct, puis une requête par titre pour son dernier chapitre.
  Future<List<ParutionTitre>> chargerDernieresParutions() async {
    final titres = <int, Titre>{};
    final enAttente = <int>{};
    for (final nom in <String>[
      nomListeSuivis,
      nomListeFavoris,
      nomListeEnAttente,
    ]) {
      final liste = await _depotListes.chargerListeParNom(nom);
      if (liste?.id == null) continue;
      for (final titre in await _depotTitres.chargerTitres(
        idListe: liste!.id,
      )) {
        final id = titre.id;
        if (id == null) continue;
        titres[id] = titre;
        if (nom == nomListeEnAttente) enAttente.add(id);
      }
    }
    if (titres.isEmpty) return const <ParutionTitre>[];

    // Sources et réglage général lus une fois pour tous les titres.
    final sources = <int, Source>{
      for (final source in await _depotSources.chargerSources())
        if (source.id != null) source.id!: source,
    };
    final general = await chargerLanguesGenerales();
    final languesParTitre = <int, List<String>>{
      for (final MapEntry(key: id, value: titre) in titres.entries)
        id: languesPreferees(
          sources[titre.idSource],
          general: general,
          titre: titre,
          // Une requête de base par titre : le dépôt des sites n'a pas de
          // lecture groupée, et l'onglet ne compte que les titres suivis.
          plusieursSites: await _aPlusieursSites(id),
        ),
    };
    // Les titres n'ont pas tous les mêmes langues : une requête par jeu.
    final dates = <int, DateTime>{};
    final parJeu = <String, List<int>>{};
    for (final MapEntry(key: id, value: langues) in languesParTitre.entries) {
      parJeu.putIfAbsent(langues.join(','), () => <int>[]).add(id);
    }
    for (final MapEntry(key: jeu, value: ids) in parJeu.entries) {
      final parutions = await _depotChapitres.chargerDernieresParutions(
        jeu.split(','),
      );
      for (final id in ids) {
        final date = parutions[id];
        if (date != null) dates[id] = date;
      }
    }

    final lignes = <ParutionTitre>[];
    for (final MapEntry(key: id, value: titre) in titres.entries) {
      final langues = languesParTitre[id]!;
      final date = dates[id];
      lignes.add(
        ParutionTitre(
          titre: titre,
          langues: langues,
          derniereParution: date,
          dernierChapitre: date == null
              ? null
              : await _depotChapitres.chargerDernierChapitreParu(id, langues),
          estEnAttente: enAttente.contains(id),
        ),
      );
    }
    lignes.sort(comparerParutions);
    return lignes;
  }

  /// Ordre de l'onglet Mises à jour : dernière parution la plus récente
  /// d'abord, titres sans parution à la fin ; à égalité, par nom (sans
  /// tenir compte de la casse). Fonction pure, exposée pour les tests.
  static int comparerParutions(ParutionTitre a, ParutionTitre b) {
    final dateA = a.derniereParution;
    final dateB = b.derniereParution;
    if (dateA != null && dateB != null && dateA != dateB) {
      return dateB.compareTo(dateA);
    }
    if ((dateA == null) != (dateB == null)) return dateA == null ? 1 : -1;
    return a.titre.nom.toLowerCase().compareTo(b.titre.nom.toLowerCase());
  }

  // ------------------------------------------------------------ Couvertures

  /// Octets de la couverture du titre, téléchargés une fois par session.
  ///
  /// Passe par `ClientHttpPoli` (seul accès réseau autorisé) plutôt que par
  /// `Image.network`, pour respecter le délai par domaine. Tous les serveurs
  /// de MangaDex (`uploads.mangadex.org` compris) exigent un User-Agent
  /// honnête. [referer] (en général l'URL de base de la source) est envoyé
  /// car beaucoup de sites refusent les images demandées sans lui
  /// (PLAYBOOK.md section 6).
  ///
  /// Lève une `ErreurSource` si le site ne répond pas ou si la réponse n'est
  /// pas une image (`Content-Type` autre que `image/*`) ; un échec n'est pas
  /// gardé en cache. Si [referer] est WEBTOON, aucune requête n'est faite et
  /// une `ErreurSource` est levée (voir [estSiteSansCouverture]).
  Future<Uint8List> recupererCouverture(
    String urlCouverture, {
    String? referer,
  }) {
    // Appel sans titre (miniatures avec seulement l'adresse et le référent) :
    // seul le référent dit de quel site vient l'image. Erreur plutôt que
    // `null` pour garder le type de retour ; le widget affiche alors un
    // espace réservé, comme pour un échec réseau.
    final uriReferent = referer == null ? null : Uri.tryParse(referer);
    if (uriReferent != null &&
        SourceWebtoons.estHoteWebtoons(uriReferent.host)) {
      return Future<Uint8List>.error(
        ErreurSource(
          urlCouverture,
          "Les couvertures de WEBTOON ne sont pas téléchargées : choisissez "
          "une image de l'appareil.",
          typeDetecte: TypeSource.webtoons,
        ),
      );
    }
    // Retirée puis remise : passe en dernière position (la plus récente).
    final dejaDemandee = _cacheCouvertures.remove(urlCouverture);
    if (dejaDemandee != null) {
      _cacheCouvertures[urlCouverture] = dejaDemandee;
      return dejaDemandee;
    }
    final demande = _telechargerCouverture(urlCouverture, referer);
    _cacheCouvertures[urlCouverture] = demande;
    _limiterCacheCouvertures();
    // Un échec (réseau, adresse invalide ou réponse qui n'est pas une image)
    // ne doit pas rester en cache : on pourra réessayer. Retiré après coup
    // (et non dans la fonction de téléchargement) pour couvrir aussi une
    // erreur levée avant que la demande ne soit mise en cache. Le futur
    // dérivé ignore l'erreur : c'est l'appelant qui la reçoit. Le test
    // `identical` écarte une demande déjà oubliée (ou remplacée) entre-temps.
    demande.then<void>(
      (octets) {
        if (!identical(_cacheCouvertures[urlCouverture], demande)) return;
        _taillesCouvertures[urlCouverture] = octets.length;
        _tailleCacheCouvertures += octets.length;
        _limiterCacheCouvertures();
      },
      onError: (Object _) {
        if (identical(_cacheCouvertures[urlCouverture], demande)) {
          _oublierCouverture(urlCouverture);
        }
      },
    );
    return demande;
  }

  /// `true` si la couverture [urlCouverture] est gardée en mémoire pour la
  /// session (téléchargée ou en cours). Exposé pour les tests.
  @visibleForTesting
  bool estCouvertureEnCache(String urlCouverture) =>
      _cacheCouvertures.containsKey(urlCouverture);

  /// Oublie les couvertures les moins récemment demandées tant que le cache
  /// dépasse ses bornes (la plus récente peut elle-même être oubliée si elle
  /// dépasse à elle seule la taille maximale : l'appelant la reçoit quand
  /// même).
  void _limiterCacheCouvertures() {
    while (_cacheCouvertures.isNotEmpty &&
        (_tailleCacheCouvertures > tailleMaximaleCacheCouvertures ||
            _cacheCouvertures.length > nombreMaximalCouverturesEnCache)) {
      _oublierCouverture(_cacheCouvertures.keys.first);
    }
  }

  void _oublierCouverture(String urlCouverture) {
    _cacheCouvertures.remove(urlCouverture);
    final taille = _taillesCouvertures.remove(urlCouverture);
    if (taille != null) _tailleCacheCouvertures -= taille;
  }

  /// Téléchargement réel d'une couverture (voir [recupererCouverture]).
  Future<Uint8List> _telechargerCouverture(
    String urlCouverture,
    String? referer,
  ) async {
    final uri = Uri.parse(urlCouverture);
    // Sous-domaines compris : avec le User-Agent de navigateur,
    // `uploads.mangadex.org` renvoie une page anti-robot HTML en 200
    // (journal des erreurs, E10).
    final estMangaDex = SourceMangaDex.estServeurMangaDex(uri.host);
    return _client.recupererOctets(
      uri,
      referer: referer,
      userAgent: estMangaDex ? userAgentApplication : null,
      // Une page HTML (défi anti-robot, erreur) servie en 200 ne doit pas
      // passer pour une image ni être enregistrée sur l'appareil.
      exigerImage: true,
    );
  }

  /// Adresse de la vignette d'une couverture : pour une couverture MangaDex
  /// (`https://uploads.mangadex.org/covers/<id>/<fichier>`), la version de
  /// 512 px obtenue en ajoutant [suffixeVignetteMangaDex] (documentation
  /// MangaDex, « covers » ; environ 160 Ko au lieu de 1,5 Mo). Toute autre
  /// adresse (autre site, déjà une vignette, adresse illisible) est renvoyée
  /// telle quelle. Fonction pure.
  static String adresseVignette(String urlCouverture) {
    final texte = urlCouverture.trim();
    final uri = Uri.tryParse(texte);
    if (uri == null ||
        !SourceMangaDex.estServeurMangaDex(uri.host) ||
        !uri.path.startsWith('/covers/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return texte;
    }
    final chemin = uri.path.toLowerCase();
    // Déjà une vignette (512 ou 256 px) : ne pas empiler les suffixes.
    if (chemin.endsWith(suffixeVignetteMangaDex) ||
        chemin.endsWith(suffixePetiteVignetteMangaDex)) {
      return texte;
    }
    return uri.replace(path: '${uri.path}$suffixeVignetteMangaDex').toString();
  }

  /// Comme [recupererCouverture], mais pour la vignette de la couverture
  /// ([adresseVignette]) : grille de la bibliothèque, cartes, onglet Mises
  /// à jour. Hors MangaDex, c'est l'image d'origine.
  ///
  /// Si le site n'a pas de vignette pour cette couverture (404), l'image
  /// d'origine est demandée à la place. Lève une `ErreurSource` sinon.
  Future<Uint8List> recupererVignette(
    String urlCouverture, {
    String? referer,
  }) async =>
      (await _recupererVignetteAvecAdresse(urlCouverture, referer: referer)).$1;

  /// Vignette et adresse réellement téléchargée (pour l'extension du
  /// fichier enregistré : la vignette MangaDex est toujours un JPEG).
  Future<(Uint8List, String)> _recupererVignetteAvecAdresse(
    String urlCouverture, {
    String? referer,
  }) async {
    final vignette = adresseVignette(urlCouverture);
    if (vignette == urlCouverture.trim()) {
      return (
        await recupererCouverture(urlCouverture, referer: referer),
        urlCouverture,
      );
    }
    try {
      return (await recupererCouverture(vignette, referer: referer), vignette);
    } on ErreurSource catch (erreur) {
      // Seule une vignette absente justifie une seconde requête : un site en
      // panne ne doit pas être sollicité deux fois (PLAYBOOK.md section 10).
      if (erreur.codeStatut != 404) rethrow;
      return (
        await recupererCouverture(urlCouverture, referer: referer),
        urlCouverture,
      );
    }
  }

  /// `true` si [octets] ressemblent à une page web (HTML, XML) plutôt qu'à
  /// une image : premier caractère visible `<`. Sert à écarter une
  /// couverture enregistrée avant le contrôle du type de contenu (E10).
  ///
  /// Volontairement étroit : aucun format d'image ne commence par `<`, alors
  /// qu'une liste de signatures d'images refuserait un format rare mais
  /// valide. Fonction pure.
  static bool ressembleAUnePageWeb(List<int> octets) {
    // BOM UTF-8 éventuel, puis blancs (espace, tabulation, retours).
    var index = 0;
    if (octets.length >= 3 &&
        octets[0] == 0xEF &&
        octets[1] == 0xBB &&
        octets[2] == 0xBF) {
      index = 3;
    }
    while (index < octets.length &&
        (octets[index] == 0x20 ||
            octets[index] == 0x09 ||
            octets[index] == 0x0A ||
            octets[index] == 0x0D)) {
      index++;
    }
    return index < octets.length && octets[index] == 0x3C;
  }

  /// `true` si [couverture] (valeur de `Titre.couvertureChoisie`) désigne une
  /// image de l'appareil plutôt qu'une adresse du site.
  static bool estCouvertureLocale(String couverture) {
    final uri = Uri.tryParse(couverture.trim());
    return uri == null || (uri.scheme != 'http' && uri.scheme != 'https');
  }

  /// `true` si les couvertures du site [source] ne sont jamais téléchargées
  /// (PLAYBOOK.md section 10) : WEBTOON, dont le serveur d'images
  /// (`pstatic.net`) refuse les demandes sans `Referer` du site. Le titre
  /// s'affiche alors sans couverture, sauf image choisie sur l'appareil.
  /// Fonction pure.
  static bool estSiteSansCouverture(Source? source) =>
      source?.typeSource == TypeSource.webtoons;

  /// Chemin de la couverture enregistrée sur l'appareil (pour `Image.file`),
  /// ou `null` si aucune n'est enregistrée. Ne lève jamais.
  Future<String?> cheminCouvertureLocale(Titre titre) async {
    try {
      return await _stockage?.cheminCouverture(titre);
    } on ErreurStockage catch (erreur) {
      debugPrint('Couverture de « ${titre.nom} » introuvable : $erreur');
      return null;
    }
  }

  /// Couverture du titre pour la grille, les cartes et l'onglet Mises à
  /// jour : celle enregistrée sur l'appareil (lisible hors-ligne), sinon la
  /// **vignette** de la couverture voulue (`Titre.couvertureAffichee`,
  /// [adresseVignette]) téléchargée puis enregistrée sur l'appareil. Renvoie
  /// `null` si aucune n'est disponible.
  ///
  /// Ne lève jamais : un échec est journalisé, et la même adresse n'est plus
  /// redemandée au site pendant cette session (la grille peut appeler cette
  /// méthode à chaque affichage sans solliciter le site).
  ///
  /// Pour la fiche d'un titre, utiliser [chargerCouvertureOriginale].
  Future<Uint8List?> chargerCouverture(Titre titre) async {
    try {
      final locale = await _stockage?.chargerCouverture(titre);
      if (locale != null) {
        if (!ressembleAUnePageWeb(locale)) return locale;
        // Page anti-robot enregistrée par une version précédente (journal
        // des erreurs, E10) : elle ne s'afficherait jamais. On l'efface pour
        // retélécharger la vraie image ci-dessous.
        await _stockage?.supprimerCouverture(titre);
      }
    } on ErreurStockage catch (erreur) {
      debugPrint('Couverture locale de « ${titre.nom} » illisible : $erreur');
    }
    final voulue = titre.couvertureAffichee;
    if (voulue == null || _couverturesEnEchec.contains(voulue)) return null;
    try {
      final source = titre.idSource == null
          ? null
          : await _depotSources.chargerSource(titre.idSource!);
      // WEBTOON : aucune requête, couverture vide (sauf image de l'appareil,
      // qui ne sollicite pas le site).
      if (!estCouvertureLocale(voulue) && estSiteSansCouverture(source)) {
        return null;
      }
      final (octets, adresse) = await _octetsVignette(voulue, source);
      await _enregistrerCouvertureSurAppareil(titre, octets, adresse);
      return octets;
    } catch (erreur) {
      _couverturesEnEchec.add(voulue);
      debugPrint('Couverture de « ${titre.nom} » indisponible : $erreur');
      return null;
    }
  }

  /// Originales MangaDex dont le téléchargement a échoué pendant cette
  /// session (voir [chargerCouvertureOriginale]).
  final Set<String> _originalesEnEchec = <String>{};

  /// Couverture du titre en pleine taille, pour la fiche d'un titre
  /// (chargée à son ouverture).
  ///
  /// Seules les couvertures MangaDex ont une vignette distincte : leur image
  /// d'origine est téléchargée (gardée pour la session, pas enregistrée sur
  /// l'appareil, qui ne garde que la vignette). Pour les autres sites et les
  /// images de l'appareil, c'est la même image que [chargerCouverture]. En
  /// cas d'échec (hors-ligne…), la vignette est renvoyée à la place.
  ///
  /// Ne lève jamais ; renvoie `null` si aucune image n'est disponible.
  Future<Uint8List?> chargerCouvertureOriginale(Titre titre) async {
    final voulue = titre.couvertureAffichee;
    if (voulue == null ||
        estCouvertureLocale(voulue) ||
        adresseVignette(voulue) == voulue.trim() ||
        _originalesEnEchec.contains(voulue)) {
      return chargerCouverture(titre);
    }
    try {
      final source = titre.idSource == null
          ? null
          : await _depotSources.chargerSource(titre.idSource!);
      if (estSiteSansCouverture(source)) return await chargerCouverture(titre);
      return await recupererCouverture(voulue, referer: source?.urlBase);
    } catch (erreur) {
      // Une seule tentative par session : la fiche rouverte affiche
      // directement la vignette, sans solliciter le site.
      _originalesEnEchec.add(voulue);
      debugPrint('Couverture originale de « ${titre.nom} » : $erreur');
      return chargerCouverture(titre);
    }
  }

  /// Couvertures proposées par le site du titre (MangaDex : une par volume),
  /// pour le choix du client. Liste vide si le site n'en propose qu'une (ses
  /// adaptateurs n'implémentent pas `SourceAvecCouvertures`).
  ///
  /// Lève une `ErreurSource` si le site ne répond pas, une [ErreurService]
  /// si le titre ou son site n'existe plus.
  Future<List<CouvertureSite>> recupererCouverturesDuSite(Titre titre) async {
    final source = await _exigerSource(titre);
    final adaptateur = _fabriqueSources.creer(source);
    if (adaptateur is! SourceAvecCouvertures) {
      return const <CouvertureSite>[];
    }
    final avecCouvertures = adaptateur as SourceAvecCouvertures;
    try {
      return await avecCouvertures.recupererCouvertures(titre.urlTitre);
    } on ErreurSource catch (erreur) {
      throw erreur.avecContexte(typeDetecte: source.typeSource);
    }
  }

  /// Choisit une autre couverture du site ([urlCouverture], en général
  /// `CouvertureSite.url`) : téléchargée, enregistrée sur l'appareil, puis
  /// retenue pour le titre. Renvoie le titre à jour.
  ///
  /// Réseau d'abord : si l'image ne peut pas être téléchargée, rien ne
  /// change. Lève une `ErreurSource` (site injoignable) ou une
  /// [ErreurService].
  Future<Titre> choisirCouverture(int idTitre, String urlCouverture) async {
    final url = urlCouverture.trim();
    if (estCouvertureLocale(url)) {
      throw const ErreurService("L'adresse de la couverture est invalide.");
    }
    final titre = await _exigerTitre(idTitre);
    final source = await _exigerSource(titre);
    if (estSiteSansCouverture(source)) {
      throw const ErreurService(
        "Les couvertures de WEBTOON ne peuvent pas être téléchargées : "
        "choisissez une image de l'appareil.",
      );
    }
    _couverturesEnEchec.remove(url);
    _originalesEnEchec.remove(url);
    // L'appareil garde la vignette ; l'originale reste en cache de session
    // si l'écran de choix l'a déjà affichée.
    final (octets, adresse) = await _octetsVignette(url, source);
    return _retenirCouverture(titre, octets, adresse, choix: url);
  }

  /// Choisit une image de l'appareil ([cheminImage]) comme couverture : une
  /// copie est enregistrée avec le titre (elle reste lisible si l'original
  /// est déplacé), et le chemin d'origine est retenu. Renvoie le titre à
  /// jour.
  ///
  /// Lève une [ErreurService] si le fichier est illisible, vide, trop
  /// volumineux ou d'un format sans extension reconnue.
  Future<Titre> choisirCouvertureLocale(int idTitre, String cheminImage) async {
    final chemin = cheminImage.trim();
    if (chemin.isEmpty || !estCouvertureLocale(chemin)) {
      throw const ErreurService("Le chemin de l'image est invalide.");
    }
    final titre = await _exigerTitre(idTitre);
    final octets = await _lireImageLocale(chemin);
    return _retenirCouverture(titre, octets, chemin, choix: chemin);
  }

  /// Revient à la couverture fournie par le site (`Titre.urlCouverture`) :
  /// elle est retéléchargée et enregistrée sur l'appareil, puis le choix du
  /// client est effacé. Renvoie le titre à jour.
  ///
  /// Si le site ne donne aucune couverture, seul le choix est effacé (et
  /// l'image enregistrée supprimée). Lève une `ErreurSource` si le site ne
  /// répond pas (rien n'est alors modifié). Pour WEBTOON (couvertures jamais
  /// téléchargées, [estSiteSansCouverture]), c'est comme si le site n'en
  /// donnait aucune.
  Future<Titre> retablirCouvertureDuSite(int idTitre) async {
    final titre = await _exigerTitre(idTitre);
    final url = titre.urlCouverture;
    final source = url == null ? null : await _exigerSource(titre);
    if (url == null || estSiteSansCouverture(source)) {
      // LIMITE : fichier puis base, sans transaction commune (comme
      // [_retenirCouverture]).
      await _stockage?.supprimerCouverture(titre);
      await _depotTitres.enregistrerCouvertureChoisie(idTitre, null);
      return await _depotTitres.chargerTitre(idTitre) ?? titre;
    }
    _couverturesEnEchec.remove(url);
    _originalesEnEchec.remove(url);
    final (octets, adresse) = await _octetsVignette(url, source);
    return _retenirCouverture(titre, octets, adresse, choix: null);
  }

  /// Enregistre [octets] comme couverture sur l'appareil puis le [choix] en
  /// base, et relit le titre.
  Future<Titre> _retenirCouverture(
    Titre titre,
    Uint8List octets,
    String origine, {
    required String? choix,
  }) async {
    await _enregistrerCouvertureSurAppareil(titre, octets, origine);
    // LIMITE : fichier puis base, sans transaction commune ; si l'écriture
    // en base échoue, l'image affichée est déjà la nouvelle mais le choix
    // n'est pas retenu : la prochaine actualisation la remplacera par la
    // couverture précédemment choisie.
    await _depotTitres.enregistrerCouvertureChoisie(titre.id!, choix);
    return await _depotTitres.chargerTitre(titre.id!) ?? titre;
  }

  /// Après un ajout ou une actualisation : enregistre la couverture sur
  /// l'appareil si aucune ne l'est encore, ou si la couverture du site a
  /// changé (et que le client n'en a pas choisi une autre). Ne lève jamais.
  ///
  /// Une couverture déjà enregistrée et inchangée n'est pas retéléchargée :
  /// une actualisation par jour de chaque titre ne coûte ainsi aucune image
  /// au site (PLAYBOOK.md section 10).
  Future<void> _mettreAJourCouvertureLocale(
    Titre? ancien,
    Titre titre,
    Source source,
  ) async {
    final stockage = _stockage;
    if (stockage == null) return;
    final voulue = titre.couvertureAffichee;
    try {
      // Titre renommé ou changé de type par le site : son dossier change ;
      // l'ancienne image est retirée de l'ancien dossier.
      if (ancien != null &&
          (ancien.nom != titre.nom || ancien.typeTitre != titre.typeTitre)) {
        await stockage.supprimerCouverture(ancien);
      }
      if (voulue == null) return;
      // WEBTOON : aucune requête d'image (une image de l'appareil reste
      // enregistrée normalement).
      if (!estCouvertureLocale(voulue) && estSiteSansCouverture(source)) {
        return;
      }
      final dejaEnregistree = await stockage.cheminCouverture(titre) != null;
      final siteAChange =
          titre.couvertureChoisie == null &&
          ancien != null &&
          ancien.urlCouverture != titre.urlCouverture;
      if (dejaEnregistree && !siteAChange) return;
      _couverturesEnEchec.remove(voulue);
      final (octets, adresse) = await _octetsVignette(voulue, source);
      await _enregistrerCouvertureSurAppareil(titre, octets, adresse);
    } catch (erreur) {
      // La couverture n'est qu'un confort : le titre est bien ajouté, et
      // l'affichage réessaiera ([chargerCouverture]).
      debugPrint('Couverture de « ${titre.nom} » non enregistrée : $erreur');
    }
  }

  /// Octets à enregistrer sur l'appareil pour une couverture, avec leur
  /// origine (pour l'extension du fichier) : image de l'appareil telle
  /// quelle, sinon la vignette téléchargée par [recupererVignette] (référent :
  /// le site du titre). L'appareil ne garde que la vignette : 10 fois plus
  /// légère pour la grille (décision du client).
  Future<(Uint8List, String)> _octetsVignette(
    String couverture,
    Source? source,
  ) async {
    if (estCouvertureLocale(couverture)) {
      return (await _lireImageLocale(couverture), couverture);
    }
    // Garde-fou : les appelants écartent déjà WEBTOON ; aucune requête même
    // si l'un d'eux l'oubliait.
    if (estSiteSansCouverture(source)) {
      throw const ErreurService(
        "Les couvertures de WEBTOON ne peuvent pas être téléchargées.",
      );
    }
    return _recupererVignetteAvecAdresse(couverture, referer: source?.urlBase);
  }

  /// Écrit la couverture dans le dossier du titre (sans stockage : rien).
  /// L'extension vient de [origine] (adresse ou chemin), `jpg` à défaut.
  Future<void> _enregistrerCouvertureSurAppareil(
    Titre titre,
    Uint8List octets,
    String origine,
  ) async {
    final stockage = _stockage;
    if (stockage == null) return;
    final extension = estCouvertureLocale(origine)
        ? StockageTelechargements.extensionDepuisUrl(
            Uri.file(origine).toString(),
          )
        : StockageTelechargements.extensionDepuisUrl(origine);
    try {
      await stockage.enregistrerCouverture(
        titre,
        octets,
        extension ?? extensionImageParDefaut,
      );
    } on ErreurStockage catch (erreur) {
      throw ErreurService(
        "La couverture n'a pas pu être enregistrée sur l'appareil.",
        cause: erreur,
      );
    }
  }

  /// Lit une image de l'appareil choisie par le client, en refusant les
  /// fichiers vides ou plus gros que la limite du stockage (avant de les
  /// charger en mémoire).
  Future<Uint8List> _lireImageLocale(String chemin) async {
    final fichier = File(chemin);
    try {
      final taille = await fichier.length();
      if (taille == 0) {
        throw const ErreurService("L'image choisie est vide.");
      }
      if (taille > tailleMaxCouverture) {
        throw const ErreurService("L'image choisie est trop volumineuse.");
      }
      return await fichier.readAsBytes();
    } on FileSystemException catch (erreur) {
      throw ErreurService("L'image choisie est illisible.", cause: erreur);
    }
  }

  Future<Titre> _exigerTitre(int idTitre) async {
    final titre = await _depotTitres.chargerTitre(idTitre);
    if (titre == null) throw const ErreurService("Ce titre n'existe plus.");
    return titre;
  }

  Future<Source> _exigerSource(Titre titre) async {
    final idSource = titre.idSource;
    final source = idSource == null
        ? null
        : await _depotSources.chargerSource(idSource);
    if (source == null) {
      throw ErreurService('Le site de « ${titre.nom} » n\'existe plus.');
    }
    return source;
  }
}
