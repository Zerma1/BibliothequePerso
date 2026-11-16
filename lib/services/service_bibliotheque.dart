/// Opérations sur la bibliothèque qui assemblent les sources et les données
/// (PLAYBOOK.md sections 4 et 7).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import '../donnees/depot_categories.dart';
import '../donnees/depot_chapitres.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../modeles/categorie.dart';
import '../modeles/chapitre.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';
import '../sources/client_http_poli.dart';
import '../sources/constantes_sources.dart';
import '../sources/fabrique_sources.dart';
import '../sources/source_mangadex.dart';
import 'constantes_services.dart';
import 'erreur_service.dart';
import 'service_ajout_site.dart';
import 'service_parametres.dart';

/// Résultat de l'ajout (ou de l'actualisation) d'un titre.
class ResultatAjoutTitre {
  /// Crée le résultat.
  const ResultatAjoutTitre(this.titre, this.nombreNouveauxChapitres);

  /// Titre tel qu'enregistré en base.
  final Titre titre;

  /// Nombre de chapitres qui n'étaient pas encore connus.
  final int nombreNouveauxChapitres;
}

/// Point d'entrée de l'interface pour la bibliothèque : titres, listes,
/// catégories, chapitres et couvertures.
class ServiceBibliotheque {
  /// Crée le service.
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
  }) : _depotSources = depotSources,
       _depotTitres = depotTitres,
       _depotChapitres = depotChapitres,
       _depotListes = depotListes,
       _depotCategories = depotCategories,
       _fabriqueSources = fabriqueSources,
       _serviceAjoutSite = serviceAjoutSite,
       _client = client,
       _serviceParametres = serviceParametres;

  final DepotSources _depotSources;
  final DepotTitres _depotTitres;
  final DepotChapitres _depotChapitres;
  final DepotListes _depotListes;
  final DepotCategories _depotCategories;
  final FabriqueSources _fabriqueSources;
  final ServiceAjoutSite _serviceAjoutSite;
  final ClientHttpPoli _client;

  /// Réglages du client (langues de lecture). Facultatif pour ne pas casser
  /// les appelants existants : sans lui, les langues par défaut s'appliquent.
  final ServiceParametres? _serviceParametres;

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

  // ---------------------------------------------------------------- Lecture

  /// Titres de la bibliothèque, avec les filtres de `DepotTitres.chargerTitres`.
  Future<List<Titre>> chargerTitres({
    String? recherche,
    int? idListe,
    int? idCategorie,
  }) => _depotTitres.chargerTitres(
    recherche: recherche,
    idListe: idListe,
    idCategorie: idCategorie,
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
  /// retour au réglage général). Les codes invalides sont ignorés.
  ///
  /// N'applique pas les règles de téléchargement : utiliser
  /// `ServiceTelechargement.modifierLanguesTitre`, qui enregistre de la même
  /// façon puis applique les règles (ce service ne dépend pas du service de
  /// téléchargement, qui lui dépend de celui-ci). Les chapitres d'une
  /// nouvelle langue n'apparaissent qu'à la prochaine actualisation du titre
  /// ([actualiserTitre]). Lève une [ErreurService] si le titre n'existe plus.
  Future<void> modifierLanguesTitre(int idTitre, List<String>? langues) =>
      enregistrerLanguesTitre(_depotTitres, idTitre, langues);

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

  /// Ajoute (ou actualise) le titre situé à [urlTitre] : fiche, catégories et
  /// chapitres.
  ///
  /// Le site doit déjà être configuré, sauf MangaDex, reconnu par son domaine
  /// et ajouté automatiquement. Le titre est placé dans les listes
  /// [idsListes] (par exemple Favoris et Suivis).
  ///
  /// Lève une [ErreurService] si aucun site ne correspond, sinon laisse
  /// passer `ErreurSource` et `ErreurBaseDeDonnees`.
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
  Future<List<Titre>> rechercherSurSource(Source source, String requete) =>
      _fabriqueSources.creer(source).rechercher(requete);

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
    final fiche = await adaptateur.recupererFiche(urlTitre);
    final chapitres = await adaptateur.recupererChapitres(urlTitre);

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
    final relu = await _depotTitres.chargerTitre(idTitre);
    return ResultatAjoutTitre(relu ?? enregistre, nouveaux);
  }

  // ------------------------------------------------------ Listes, lecture

  /// Ajoute le titre à la liste.
  Future<void> ajouterTitreALaListe(int idListe, int idTitre) =>
      _depotListes.ajouterTitre(idListe, idTitre);

  /// Retire le titre de la liste (le titre reste dans la bibliothèque).
  Future<void> retirerTitreDeLaListe(int idListe, int idTitre) =>
      _depotListes.retirerTitre(idListe, idTitre);

  /// Crée une liste personnelle.
  Future<ListeLecture> creerListe(String nom) => _depotListes.creerListe(nom);

  /// Supprime une liste personnelle (refusé pour Favoris et Suivis).
  Future<void> supprimerListe(int idListe) =>
      _depotListes.supprimerListe(idListe);

  /// Supprime un titre et ses chapitres.
  Future<void> supprimerTitre(int idTitre) =>
      _depotTitres.supprimerTitre(idTitre);

  /// Marque un chapitre lu ou non lu.
  Future<void> marquerLu(int idChapitre, {bool estLu = true}) =>
      _depotChapitres.marquerLu(idChapitre, estLu: estLu);

  /// Marque tous les chapitres d'un titre lus ou non lus.
  Future<void> marquerTousLus(int idTitre, {bool estLu = true}) =>
      _depotChapitres.marquerTousLus(idTitre, estLu: estLu);

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
}
