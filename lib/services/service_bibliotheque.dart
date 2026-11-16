/// Opérations sur la bibliothèque qui assemblent les sources et les données
/// (PLAYBOOK.md sections 4 et 7).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:io' show File, FileSystemException;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../donnees/constantes_donnees.dart' show tailleMaxCouverture;
import '../donnees/depot_categories.dart';
import '../donnees/depot_chapitres.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../donnees/erreur_stockage.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/categorie.dart';
import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../sources/client_http_poli.dart';
import '../sources/constantes_sources.dart';
import '../sources/couverture_site.dart';
import '../sources/erreur_source.dart';
import '../sources/fabrique_sources.dart';
import '../sources/source_mangadex.dart';
import 'classement_listes.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'service_ajout_site.dart';
import 'service_parametres.dart';

/// Résultat de l'ajout (ou de l'actualisation) d'un titre.
class ResultatAjoutTitre {
  /// Crée le résultat.
  const ResultatAjoutTitre(
    this.titre,
    this.nombreNouveauxChapitres, {
    this.estEnAttente = false,
  });

  /// Titre tel qu'enregistré en base.
  final Titre titre;

  /// Nombre de chapitres qui n'étaient pas encore connus.
  final int nombreNouveauxChapitres;

  /// `true` si le titre a été placé (ou laissé) dans « En attente » : il
  /// n'a encore aucun chapitre dans les langues du client. L'interface peut
  /// le signaler à l'ajout.
  final bool estEnAttente;
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
  }) : _depotSources = depotSources,
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

  /// Langues de lecture par défaut (« fr,en »), tant que le client n'a rien
  /// choisi dans les réglages.
  ///
  /// Gardée pour l'interface existante ; le repli réel est désormais le
  /// réglage général (`ServiceParametres.chargerLangues`).
  static final String languesParDefaut = languesParDefautClient.join(',');

  /// Nom donné à la source MangaDex quand elle est ajoutée automatiquement.
  static const String nomSourceMangaDex = 'MangaDex';

  /// Couvertures déjà téléchargées pendant cette session, par URL.
  ///
  /// Évite de redemander la même image au site à chaque affichage de la
  /// grille (règle de charge des sites, PLAYBOOK.md section 10).
  final Map<String, Future<Uint8List>> _cacheCouvertures =
      <String, Future<Uint8List>>{};

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

  /// Chapitres d'un titre.
  Future<List<Chapitre>> chargerChapitres(int idTitre) =>
      _depotChapitres.chargerChapitres(idTitre);

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
  static List<String> languesPreferees(
    Source? source, {
    List<String>? general,
    Titre? titre,
  }) {
    final propresAuTitre = ServiceParametres.nettoyerLangues(
      titre?.listeLanguesPreferees ?? const <String>[],
    );
    if (propresAuTitre.isNotEmpty) return propresAuTitre;
    final langues = SourceMangaDex.languesIsoDepuisPreference(
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
  /// gardé pour compatibilité), sinon réglage général.
  Future<List<String>> languesPourTitre(Titre titre) async {
    final idSource = titre.idSource;
    final source = idSource == null
        ? null
        : await _depotSources.chargerSource(idSource);
    return languesPreferees(
      source,
      general: await chargerLanguesGenerales(),
      titre: titre,
    );
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
  /// Lève une [ErreurService] si aucun site ne correspond, sinon laisse
  /// passer `ErreurSource` (complétée du type du site, pour le rapport
  /// d'erreur) et `ErreurBaseDeDonnees`.
  Future<ResultatAjoutTitre> ajouterTitreDepuisUrl(
    String urlTitre, {
    List<int> idsListes = const <int>[],
  }) async {
    final source = await _trouverOuAjouterSource(urlTitre);
    return _enregistrerDepuisSource(
      source,
      urlTitre.trim(),
      idsListes: idsListes,
    );
  }

  /// Relit la fiche et les chapitres d'un titre déjà enregistré.
  Future<ResultatAjoutTitre> actualiserTitre(Titre titre) async {
    final idSource = titre.idSource;
    final source = idSource == null
        ? null
        : await _depotSources.chargerSource(idSource);
    if (source == null) {
      throw ErreurService('Le site de « ${titre.nom} » n\'existe plus.');
    }
    return _enregistrerDepuisSource(source, titre.urlTitre, titre: titre);
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

  Future<ResultatAjoutTitre> _enregistrerDepuisSource(
    Source source,
    String urlTitre, {
    List<int> idsListes = const <int>[],
    Titre? titre,
  }) async {
    final idSource = source.id;
    if (idSource == null) {
      throw ErreurService('Le site « ${source.nom} » n\'est pas enregistré.');
    }
    // Langues demandées au site : celles propres au titre (actualisation),
    // celles de la source (si réglées) puis celles du réglage général. Un
    // site sans langues recevrait sinon les chapitres de toutes les langues
    // (russe, japonais…). FabriqueSources lit les langues dans
    // `Source.langueParDefaut` : on lui passe une copie.
    final general = await chargerLanguesGenerales();
    final langues = <String>{
      ...languesPreferees(source, general: general, titre: titre),
      ...languesPreferees(source, general: general),
      ...general,
    }.join(',');
    final adaptateur = _fabriqueSources.creer(
      source.copierAvec(langueParDefaut: langues),
    );

    // Réseau d'abord, base ensuite : si le site ne répond pas, rien n'est
    // écrit. Côté base, les écritures se font dans l'ordre d'importance pour le
    // client : le titre, puis ses listes (pour qu'un titre ajouté soit
    // toujours visible dans Favoris / Suivis), puis les chapitres. La date de
    // vérification n'est écrite qu'en dernier : si une étape échoue, la
    // prochaine actualisation reprendra les chapitres manquants.
    // LIMITE : ces écritures ne forment pas une seule transaction (les dépôts
    // ouvrent chacun la leur) ; un échec au milieu laisse un titre sans
    // chapitres, rattrapé à l'actualisation suivante.
    final FicheTitre fiche;
    final List<Chapitre> chapitres;
    try {
      fiche = await adaptateur.recupererFiche(urlTitre);
      chapitres = await adaptateur.recupererChapitres(urlTitre);
    } on ErreurSource catch (erreur) {
      // Le type du site sert au rapport d'erreur exportable (étape 6).
      throw erreur.avecContexte(typeDetecte: source.typeSource);
    }

    // État avant l'écriture : sert à savoir si la couverture du site a
    // changé (pour ne pas la retélécharger à chaque actualisation).
    final ancien = titre ?? await _depotTitres.chargerTitreParUrl(urlTitre);

    // Le niveau de contenu vient de la fiche (MangaDex : `contentRating`) ;
    // `enregistrerTitre` l'écrit avec le reste de la fiche.
    final enregistre = await _depotTitres.enregistrerTitre(
      fiche.titre.copierAvec(idSource: idSource),
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
    );
    await _depotTitres.enregistrerDateVerification(
      idTitre,
      DateTime.now().toUtc(),
    );
    // Classement et couverture après les écritures essentielles, sans
    // jamais faire échouer l'ajout : le classement est refait à chaque
    // vérification, et la couverture à l'affichage suivant.
    final estEnAttente = await _classerEnAttenteSansErreur(idTitre);
    final relu = await _depotTitres.chargerTitre(idTitre) ?? enregistre;
    await _mettreAJourCouvertureLocale(ancien, relu, source);
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
    final noms = (await _depotListes.chargerListesDuTitre(
      idTitre,
    )).map((liste) => liste.nom).toSet();
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
      debugPrint('Classement « En attente » du titre n°$idTitre : $erreur\n$pile');
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
  /// `Image.network`, pour respecter le délai par domaine. Les serveurs de
  /// MangaDex exigent un User-Agent honnête. [referer] (en général l'URL de
  /// base de la source) est envoyé car beaucoup de sites refusent les images
  /// demandées sans lui (PLAYBOOK.md section 6).
  Future<Uint8List> recupererCouverture(
    String urlCouverture, {
    String? referer,
  }) {
    return _cacheCouvertures.putIfAbsent(urlCouverture, () async {
      try {
        final uri = Uri.parse(urlCouverture);
        final estMangaDex = SourceMangaDex.estHoteMangaDex(uri.host);
        return await _client.recupererOctets(
          uri,
          referer: referer,
          userAgent: estMangaDex ? userAgentApplication : null,
        );
      } catch (_) {
        // Un échec ne doit pas rester en cache : on pourra réessayer.
        _cacheCouvertures.remove(urlCouverture);
        rethrow;
      }
    });
  }

  /// `true` si [couverture] (valeur de `Titre.couvertureChoisie`) désigne une
  /// image de l'appareil plutôt qu'une adresse du site.
  static bool estCouvertureLocale(String couverture) {
    final uri = Uri.tryParse(couverture.trim());
    return uri == null || (uri.scheme != 'http' && uri.scheme != 'https');
  }

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

  /// Couverture du titre pour l'affichage : celle enregistrée sur l'appareil
  /// (lisible hors-ligne), sinon la couverture voulue
  /// (`Titre.couvertureAffichee`) téléchargée puis enregistrée sur
  /// l'appareil. Renvoie `null` si aucune n'est disponible.
  ///
  /// Ne lève jamais : un échec est journalisé, et la même adresse n'est plus
  /// redemandée au site pendant cette session (la grille peut appeler cette
  /// méthode à chaque affichage sans solliciter le site).
  Future<Uint8List?> chargerCouverture(Titre titre) async {
    try {
      final locale = await _stockage?.chargerCouverture(titre);
      if (locale != null) return locale;
    } on ErreurStockage catch (erreur) {
      debugPrint('Couverture locale de « ${titre.nom} » illisible : $erreur');
    }
    final voulue = titre.couvertureAffichee;
    if (voulue == null || _couverturesEnEchec.contains(voulue)) return null;
    try {
      final source = titre.idSource == null
          ? null
          : await _depotSources.chargerSource(titre.idSource!);
      final octets = await _octetsCouverture(voulue, source);
      await _enregistrerCouvertureSurAppareil(titre, octets, voulue);
      return octets;
    } catch (erreur) {
      _couverturesEnEchec.add(voulue);
      debugPrint('Couverture de « ${titre.nom} » indisponible : $erreur');
      return null;
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
    _couverturesEnEchec.remove(url);
    final octets = await _octetsCouverture(url, source);
    return _retenirCouverture(titre, octets, url, choix: url);
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
  /// répond pas (rien n'est alors modifié).
  Future<Titre> retablirCouvertureDuSite(int idTitre) async {
    final titre = await _exigerTitre(idTitre);
    final url = titre.urlCouverture;
    if (url == null) {
      await _stockage?.supprimerCouverture(titre);
      await _depotTitres.enregistrerCouvertureChoisie(idTitre, null);
      return await _depotTitres.chargerTitre(idTitre) ?? titre;
    }
    final source = await _exigerSource(titre);
    _couverturesEnEchec.remove(url);
    final octets = await _octetsCouverture(url, source);
    return _retenirCouverture(titre, octets, url, choix: null);
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
      final dejaEnregistree = await stockage.cheminCouverture(titre) != null;
      final siteAChange =
          titre.couvertureChoisie == null &&
          ancien != null &&
          ancien.urlCouverture != titre.urlCouverture;
      if (dejaEnregistree && !siteAChange) return;
      _couverturesEnEchec.remove(voulue);
      final octets = await _octetsCouverture(voulue, source);
      await _enregistrerCouvertureSurAppareil(titre, octets, voulue);
    } catch (erreur) {
      // La couverture n'est qu'un confort : le titre est bien ajouté, et
      // l'affichage réessaiera ([chargerCouverture]).
      debugPrint('Couverture de « ${titre.nom} » non enregistrée : $erreur');
    }
  }

  /// Octets d'une couverture : image de l'appareil, ou téléchargement par
  /// [recupererCouverture] (référent : le site du titre).
  Future<Uint8List> _octetsCouverture(String couverture, Source? source) {
    if (estCouvertureLocale(couverture)) {
      return _lireImageLocale(couverture);
    }
    return recupererCouverture(couverture, referer: source?.urlBase);
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
        ? StockageTelechargements.extensionDepuisUrl(Uri.file(origine).toString())
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
