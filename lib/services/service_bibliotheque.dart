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
import 'erreur_service.dart';
import 'service_ajout_site.dart';

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
  }) : _depotSources = depotSources,
       _depotTitres = depotTitres,
       _depotChapitres = depotChapitres,
       _depotListes = depotListes,
       _depotCategories = depotCategories,
       _fabriqueSources = fabriqueSources,
       _serviceAjoutSite = serviceAjoutSite,
       _client = client;

  final DepotSources _depotSources;
  final DepotTitres _depotTitres;
  final DepotChapitres _depotChapitres;
  final DepotListes _depotListes;
  final DepotCategories _depotCategories;
  final FabriqueSources _fabriqueSources;
  final ServiceAjoutSite _serviceAjoutSite;
  final ClientHttpPoli _client;

  /// Langues de lecture du client, par ordre de préférence (codes ISO 639-1
  /// séparés par des virgules), données aux sources ajoutées automatiquement.
  static const String languesParDefaut = 'fr,en';

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
    return _enregistrerDepuisSource(source, titre.urlTitre);
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
      // l'ajouter sans demander d'étape supplémentaire au client.
      return _serviceAjoutSite.ajouterSite(
        urlTitre,
        nom: nomSourceMangaDex,
        langueParDefaut: languesParDefaut,
      );
    }
    throw const ErreurService(
      'Ce site n\'est pas encore configuré : ajoutez-le d\'abord dans « Sources ».',
    );
  }

  Future<ResultatAjoutTitre> _enregistrerDepuisSource(
    Source source,
    String urlTitre, {
    List<int> idsListes = const <int>[],
  }) async {
    final idSource = source.id;
    if (idSource == null) {
      throw ErreurService('Le site « ${source.nom} » n\'est pas enregistré.');
    }
    final adaptateur = _fabriqueSources.creer(source);

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

    final titre = await _depotTitres.enregistrerTitre(
      fiche.titre.copierAvec(idSource: idSource),
      categories: fiche.categories,
    );
    final idTitre = titre.id!;
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
    return ResultatAjoutTitre(relu ?? titre, nouveaux);
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
