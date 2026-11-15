/// Outils partagés par les tests de l'interface (`etat/`, `ecrans/`,
/// `widgets/`) : faux services en mémoire, vrais services sur une base en
/// mémoire avec un MockClient, et enveloppe de widgets. Aucun appel réseau.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/etat/etat_bibliotheque.dart';
import 'package:bibliotheque_perso/etat/etat_couvertures.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/main.dart';
import 'package:bibliotheque_perso/modeles/categorie.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/liste_lecture.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

// ---------------------------------------------------------------- Faux services

/// Faux `ServiceBibliotheque` entièrement en mémoire, pour les tests de
/// widgets (aucune base, aucun réseau, réponses immédiates ou retenues).
class FauxServiceBibliotheque implements ServiceBibliotheque {
  /// Titres de la bibliothèque.
  final List<Titre> titres = <Titre>[];

  /// Listes : Favoris, Suivis (système) et une liste du client.
  final List<ListeLecture> listes = <ListeLecture>[
    const ListeLecture(
      id: 1,
      nom: nomListeFavoris,
      estSysteme: true,
      ordre: ordreListeFavoris,
    ),
    const ListeLecture(
      id: 2,
      nom: nomListeSuivis,
      estSysteme: true,
      ordre: ordreListeSuivis,
    ),
    const ListeLecture(id: 3, nom: 'À lire plus tard', ordre: 2),
  ];

  /// Toutes les catégories.
  final List<Categorie> categories = <Categorie>[];

  /// Catégories par identifiant de titre.
  final Map<int, List<Categorie>> categoriesParTitre = <int, List<Categorie>>{};

  /// Identifiants des listes par identifiant de titre.
  final Map<int, Set<int>> listesParTitre = <int, Set<int>>{};

  /// Chapitres par identifiant de titre (ordre croissant, comme le dépôt).
  final Map<int, List<Chapitre>> chapitresParTitre = <int, List<Chapitre>>{};

  /// Sites configurés.
  final List<Source> sources = <Source>[];

  /// Erreur levée par toutes les lectures, si définie.
  Object? erreurLecture;

  /// Erreur levée par l'ajout et l'actualisation d'un titre, si définie.
  Object? erreurAjout;

  /// Si défini, les lectures attendent qu'il soit complété (état
  /// « chargement » visible).
  Completer<void>? retenue;

  /// Octets renvoyés pour les couvertures ; `null` : erreur réseau simulée.
  Uint8List? octetsCouverture;

  /// Nombre de nouveaux chapitres annoncé par l'ajout et l'actualisation.
  int nombreNouveaux = 3;

  /// URLs dont la couverture a été demandée.
  final List<String> couverturesDemandees = <String>[];

  /// Referers reçus avec les demandes de couverture.
  final List<String?> referersDemandes = <String?>[];

  /// Action exécutée au début de l'ajout et de l'actualisation d'un titre
  /// (simule ce que le vrai service écrit avant d'échouer).
  void Function()? avantAjout;

  Future<void> _lire() async {
    final attente = retenue;
    if (attente != null) {
      await attente.future;
    }
    final erreur = erreurLecture;
    if (erreur != null) {
      throw erreur;
    }
  }

  /// Ajoute un titre de test et le renvoie.
  Titre ajouterTitreDeTest(
    String nom, {
    int? idSource,
    List<String> nomsCategories = const <String>[],
    Set<int> idsListes = const <int>{},
    List<Chapitre> chapitres = const <Chapitre>[],
    String? urlCouverture,
  }) {
    final id = titres.length + 1;
    final titre = Titre(
      id: id,
      idSource: idSource,
      urlTitre: 'https://mangadex.org/title/titre-$id',
      nom: nom,
      urlCouverture: urlCouverture,
      typeTitre: TypeTitre.manga,
      nombreChapitresNonLus: chapitres
          .where((chapitre) => !chapitre.estLu)
          .length,
    );
    titres.add(titre);
    final categoriesDuTitre = <Categorie>[];
    for (final nomCategorie in nomsCategories) {
      var categorie = categories
          .where((existante) => existante.nom == nomCategorie)
          .firstOrNull;
      if (categorie == null) {
        categorie = Categorie(id: categories.length + 1, nom: nomCategorie);
        categories.add(categorie);
      }
      categoriesDuTitre.add(categorie);
    }
    categoriesParTitre[id] = categoriesDuTitre;
    listesParTitre[id] = <int>{...idsListes};
    chapitresParTitre[id] = <Chapitre>[
      for (final chapitre in chapitres) chapitre.copierAvec(idTitre: id),
    ];
    return titre;
  }

  Titre _avecNonLus(Titre titre) => titre.copierAvec(
    nombreChapitresNonLus: (chapitresParTitre[titre.id] ?? const <Chapitre>[])
        .where((chapitre) => !chapitre.estLu)
        .length,
  );

  @override
  Future<List<Titre>> chargerTitres({
    String? recherche,
    int? idListe,
    int? idCategorie,
  }) async {
    await _lire();
    final texte = recherche?.toLowerCase();
    return <Titre>[
      for (final titre in titres)
        if ((texte == null || titre.nom.toLowerCase().contains(texte)) &&
            (idListe == null ||
                (listesParTitre[titre.id] ?? const <int>{}).contains(
                  idListe,
                )) &&
            (idCategorie == null ||
                (categoriesParTitre[titre.id] ?? const <Categorie>[]).any(
                  (categorie) => categorie.id == idCategorie,
                )))
          _avecNonLus(titre),
    ];
  }

  @override
  Future<Titre?> chargerTitre(int idTitre) async {
    await _lire();
    final titre = titres.where((titre) => titre.id == idTitre).firstOrNull;
    return titre == null ? null : _avecNonLus(titre);
  }

  @override
  Future<List<ListeLecture>> chargerListes() async {
    await _lire();
    return List<ListeLecture>.of(listes);
  }

  @override
  Future<List<ListeLecture>> chargerListesDuTitre(int idTitre) async {
    await _lire();
    final ids = listesParTitre[idTitre] ?? const <int>{};
    return listes.where((liste) => ids.contains(liste.id)).toList();
  }

  @override
  Future<List<Categorie>> chargerCategories() async {
    await _lire();
    return List<Categorie>.of(categories);
  }

  @override
  Future<List<Categorie>> chargerCategoriesDuTitre(int idTitre) async {
    await _lire();
    return List<Categorie>.of(
      categoriesParTitre[idTitre] ?? const <Categorie>[],
    );
  }

  @override
  Future<List<Chapitre>> chargerChapitres(int idTitre) async {
    await _lire();
    return List<Chapitre>.of(chapitresParTitre[idTitre] ?? const <Chapitre>[]);
  }

  @override
  Future<List<Source>> chargerSources() async {
    await _lire();
    return List<Source>.of(sources);
  }

  @override
  Future<Source?> chargerSource(int idSource) async {
    await _lire();
    return sources.where((source) => source.id == idSource).firstOrNull;
  }

  @override
  Future<ResultatAjoutTitre> ajouterTitreDepuisUrl(
    String urlTitre, {
    List<int> idsListes = const <int>[],
  }) async {
    avantAjout?.call();
    final erreur = erreurAjout;
    if (erreur != null) {
      throw erreur;
    }
    final titre = ajouterTitreDeTest(
      'Titre ajouté ${titres.length + 1}',
      idsListes: idsListes.toSet(),
    );
    return ResultatAjoutTitre(titre, nombreNouveaux);
  }

  @override
  Future<ResultatAjoutTitre> actualiserTitre(Titre titre) async {
    avantAjout?.call();
    final erreur = erreurAjout;
    if (erreur != null) {
      throw erreur;
    }
    return ResultatAjoutTitre(titre, nombreNouveaux);
  }

  @override
  Future<List<Titre>> rechercherSurSource(Source source, String requete) async =>
      const <Titre>[];

  @override
  Future<void> ajouterTitreALaListe(int idListe, int idTitre) async {
    (listesParTitre[idTitre] ??= <int>{}).add(idListe);
  }

  @override
  Future<void> retirerTitreDeLaListe(int idListe, int idTitre) async {
    listesParTitre[idTitre]?.remove(idListe);
  }

  @override
  Future<ListeLecture> creerListe(String nom) async {
    final liste = ListeLecture(id: listes.length + 1, nom: nom);
    listes.add(liste);
    return liste;
  }

  @override
  Future<void> supprimerListe(int idListe) async {
    listes.removeWhere((liste) => liste.id == idListe);
  }

  @override
  Future<void> supprimerTitre(int idTitre) async {
    titres.removeWhere((titre) => titre.id == idTitre);
  }

  @override
  Future<void> marquerLu(int idChapitre, {bool estLu = true}) async {
    for (final entree in chapitresParTitre.entries) {
      entree.value.replaceRange(0, entree.value.length, <Chapitre>[
        for (final chapitre in entree.value)
          chapitre.id == idChapitre ? chapitre.copierAvec(estLu: estLu) : chapitre,
      ]);
    }
  }

  @override
  Future<void> marquerTousLus(int idTitre, {bool estLu = true}) async {
    final chapitres = chapitresParTitre[idTitre];
    if (chapitres != null) {
      chapitres.replaceRange(0, chapitres.length, <Chapitre>[
        for (final chapitre in chapitres) chapitre.copierAvec(estLu: estLu),
      ]);
    }
  }

  @override
  Future<Uint8List> recupererCouverture(
    String urlCouverture, {
    String? referer,
  }) async {
    couverturesDemandees.add(urlCouverture);
    referersDemandes.add(referer);
    final octets = octetsCouverture;
    if (octets == null) {
      throw ErreurSource(urlCouverture, 'Pas de réseau dans les tests');
    }
    return octets;
  }
}

/// Faux `ServiceAjoutSite` qui enregistre les sites dans un
/// [FauxServiceBibliotheque].
class FauxServiceAjoutSite implements ServiceAjoutSite {
  /// Crée le faux service relié à [bibliotheque].
  FauxServiceAjoutSite(this.bibliotheque);

  /// Faux service qui détient la liste des sources.
  final FauxServiceBibliotheque bibliotheque;

  /// Erreur levée par l'ajout, si définie.
  Object? erreurAjout;

  /// Si défini, l'ajout attend qu'il soit complété.
  Completer<void>? retenue;

  /// Derniers paramètres reçus par [ajouterSite].
  ({String url, String? nom, String langue, TypeSource? type})? dernierAppel;

  @override
  Future<Source> ajouterSite(
    String url, {
    String? nom,
    String langueParDefaut = '',
    TypeSource? typeForce,
  }) async {
    dernierAppel = (
      url: url,
      nom: nom,
      langue: langueParDefaut,
      type: typeForce,
    );
    final attente = retenue;
    if (attente != null) {
      await attente.future;
    }
    final erreur = erreurAjout;
    if (erreur != null) {
      throw erreur;
    }
    final uri = DetecteurTypeSite.validerUrl(url);
    final urlBase = ServiceAjoutSite.calculerUrlBase(uri);
    final existante = bibliotheque.sources
        .where((source) => source.urlBase == urlBase)
        .firstOrNull;
    if (existante != null) {
      return existante;
    }
    final source = Source(
      id: bibliotheque.sources.length + 1,
      nom: (nom == null || nom.trim().isEmpty)
          ? ServiceAjoutSite.proposerNom(uri)
          : nom.trim(),
      urlBase: urlBase,
      typeSource: typeForce ?? TypeSource.generique,
      langueParDefaut: langueParDefaut,
    );
    bibliotheque.sources.add(source);
    return source;
  }

  @override
  Future<Source?> trouverSourcePourUrl(String url) async => null;
}

// ------------------------------------------------------------- Vrais services

/// Vrais services branchés sur une base SQLite en mémoire et sur un
/// MockClient qui sert les réponses MangaDex enregistrées.
class ServicesDeTest {
  ServicesDeTest._(this.base, this.bibliotheque, this.ajoutSite, this.requetes);

  /// Base en mémoire (à fermer avec [fermer]).
  final Database base;

  /// Service de la bibliothèque.
  final ServiceBibliotheque bibliotheque;

  /// Service d'ajout de site.
  final ServiceAjoutSite ajoutSite;

  /// Requêtes reçues par le MockClient.
  final List<Uri> requetes;

  /// Si `true`, le faux site MangaDex répond 404 à toutes les requêtes.
  bool siteEnPanne = false;

  /// Ferme la base.
  Future<void> fermer() => base.close();
}

/// Réponse du flux réduite à une seule page (pas de pagination à simuler).
String _fluxUnePage() {
  final flux = lireJsonExemple('manga_flux_page1.json');
  final donnees = flux['data']! as List<Object?>;
  return jsonEncode(<String, Object?>{...flux, 'total': donnees.length});
}

/// Crée les vrais services sur une base neuve en mémoire.
Future<ServicesDeTest> creerServicesReels() async {
  final base = await ouvrirBaseDeTest();
  final requetes = <Uri>[];
  final fiche = lireExemple('exemples_json/manga_fiche.json');
  final flux = _fluxUnePage();
  late final ServicesDeTest services;
  final client = creerClientTest((http.Request requete) async {
    requetes.add(requete.url);
    final chemin = requete.url.path;
    if (services.siteEnPanne) {
      return http.Response('introuvable', 404);
    }
    if (chemin.endsWith('/feed')) {
      return reponseJson(flux);
    }
    if (chemin.startsWith('/manga/')) {
      return reponseJson(fiche);
    }
    return http.Response('introuvable', 404);
  }, HorlogeFactice());

  final depotSources = DepotSources(base);
  final ajoutSite = ServiceAjoutSite(depotSources, DetecteurTypeSite(client));
  final bibliotheque = ServiceBibliotheque(
    depotSources: depotSources,
    depotTitres: DepotTitres(base),
    depotChapitres: DepotChapitres(base),
    depotListes: DepotListes(base),
    depotCategories: DepotCategories(base),
    fabriqueSources: FabriqueSources(client),
    serviceAjoutSite: ajoutSite,
    client: client,
  );
  services = ServicesDeTest._(base, bibliotheque, ajoutSite, requetes);
  return services;
}

// ------------------------------------------------------------------ Widgets

/// Enveloppe [enfant] dans les fournisseurs de l'application et un
/// MaterialApp, branchés sur les faux services.
Widget envelopper(
  Widget enfant, {
  required FauxServiceBibliotheque bibliotheque,
  FauxServiceAjoutSite? ajoutSite,
}) {
  return MultiProvider(
    providers: [
      Provider<EtatCouvertures>(create: (_) => EtatCouvertures(bibliotheque)),
      ChangeNotifierProvider<EtatBibliotheque>(
        create: (_) => EtatBibliotheque(bibliotheque)..charger(),
      ),
      ChangeNotifierProvider<EtatSources>(
        create: (_) => EtatSources(
          bibliotheque,
          ajoutSite ?? FauxServiceAjoutSite(bibliotheque),
        )..charger(),
      ),
    ],
    child: BibliothequePersoApp(accueil: enfant),
  );
}

/// Image PNG valide de 1 × 1 pixel (pour les couvertures).
final Uint8List pngMinimal = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);
