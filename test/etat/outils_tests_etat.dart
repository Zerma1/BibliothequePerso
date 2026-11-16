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
import 'package:bibliotheque_perso/etat/etat_mises_a_jour.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/etat/etat_telechargements.dart';
import 'package:bibliotheque_perso/main.dart';
import 'package:bibliotheque_perso/modeles/categorie.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/liste_lecture.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/planification_mises_a_jour.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_mises_a_jour.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/services/verrou_telechargement.dart';
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

  /// Langues du réglage général renvoyées par [chargerLanguesGenerales].
  List<String> languesGenerales = <String>['fr', 'en'];

  @override
  Future<List<String>> chargerLanguesGenerales() async =>
      List<String>.of(languesGenerales);

  @override
  Future<List<String>> languesPourTitre(Titre titre) async {
    final idSource = titre.idSource;
    final source = idSource == null
        ? null
        : sources.where((s) => s.id == idSource).firstOrNull;
    return ServiceBibliotheque.languesPreferees(
      source,
      general: languesGenerales,
      titre: titre,
    );
  }

  /// Appels reçus par [modifierLanguesTitre] (`null` : réglage général).
  final List<({int idTitre, List<String>? langues})> languesModifiees =
      <({int idTitre, List<String>? langues})>[];

  @override
  Future<void> modifierLanguesTitre(int idTitre, List<String>? langues) async {
    languesModifiees.add((idTitre: idTitre, langues: langues));
    enregistrerLanguesDeTest(idTitre, langues);
  }

  /// Enregistre les langues propres d'un titre comme le vrai service
  /// (codes nettoyés, liste vide ou `null` = retour au réglage général).
  void enregistrerLanguesDeTest(int idTitre, List<String>? langues) {
    final index = titres.indexWhere((titre) => titre.id == idTitre);
    if (index < 0) {
      throw const ErreurService("Ce titre n'existe plus.");
    }
    final propres = ServiceParametres.nettoyerLangues(
      langues ?? const <String>[],
    );
    titres[index] = propres.isEmpty
        ? titres[index].copierAvec(effacerLanguesPreferees: true)
        : titres[index].copierAvec(languesPreferees: propres.join(','));
  }

  @override
  Future<Chapitre?> chargerChapitre(int idChapitre) async {
    await _lire();
    for (final chapitres in chapitresParTitre.values) {
      for (final chapitre in chapitres) {
        if (chapitre.id == idChapitre) return chapitre;
      }
    }
    return null;
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
  Future<List<Titre>> rechercherSurSource(
    Source source,
    String requete,
  ) async => const <Titre>[];

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
          chapitre.id == idChapitre
              ? chapitre.copierAvec(estLu: estLu)
              : chapitre,
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

  /// Sources reçues par [modifierSource].
  final List<Source> sourcesModifiees = <Source>[];

  @override
  Future<Source> modifierSource(Source source) async {
    final erreur = erreurAjout;
    if (erreur != null) {
      throw erreur;
    }
    // Même normalisation que le vrai service.
    final modifiee = source.copierAvec(
      nom: source.nom.trim(),
      langueParDefaut: source.langueParDefaut
          .split(',')
          .map((code) => code.trim().toLowerCase())
          .where((code) => code.isNotEmpty)
          .join(','),
    );
    sourcesModifiees.add(modifiee);
    final index = bibliotheque.sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      bibliotheque.sources[index] = modifiee;
    }
    return modifiee;
  }

  @override
  Future<void> supprimerSource(int idSource) async {
    bibliotheque.sources.removeWhere((source) => source.id == idSource);
  }
}

/// Faux `ServiceTelechargement` en mémoire, relié à un
/// [FauxServiceBibliotheque] pour marquer les chapitres téléchargés.
class FauxServiceTelechargement implements ServiceTelechargement {
  /// Crée le faux service.
  FauxServiceTelechargement(this.bibliotheque);

  /// Faux service qui détient les chapitres.
  final FauxServiceBibliotheque bibliotheque;

  final StreamController<void> _changements =
      StreamController<void>.broadcast();

  /// File, dans l'ordre d'ajout.
  final List<Telechargement> file = <Telechargement>[];

  /// Pages de chaque chapitre téléchargé (octets).
  final Map<int, List<Uint8List>> pages = <int, List<Uint8List>>{};

  /// Texte HTML des chapitres de roman téléchargés.
  final Map<int, String> textes = <int, String>{};

  /// Titres passés à [appliquerRegles], dans l'ordre.
  final List<int> reglesAppliquees = <int>[];

  /// Appels à [appliquerReglesATous].
  int nombreAppelsReglesATous = 0;

  /// Appels à [demarrer].
  int nombreDemarrages = 0;

  /// Journal des appels, pour vérifier leur ordre.
  final List<String> journal = <String>[];

  /// Erreur levée par [chargerFile], si définie.
  Object? erreurFile;

  /// Index de page qui lève une erreur à la lecture.
  final Set<int> pagesIllisibles = <int>{};

  int _prochainId = 1;

  /// Prévient les écouteurs (comme le vrai service à chaque changement).
  void signaler() => _changements.add(null);

  /// Ajoute un chapitre déjà téléchargé avec [nombrePages] pages.
  void ajouterChapitreTelecharge(int idChapitre, {int nombrePages = 3}) {
    pages[idChapitre] = <Uint8List>[
      for (var i = 0; i < nombrePages; i++) pngMinimal,
    ];
    _marquer(idChapitre, estTelecharge: true);
  }

  /// Change la ligne de file d'un chapitre (statut, progression, erreur).
  void modifierLigne(
    int idChapitre,
    StatutTelechargement statut, {
    int faites = 0,
    int total = 0,
    String? messageErreur,
  }) {
    final index = file.indexWhere((t) => t.idChapitre == idChapitre);
    final ligne = Telechargement(
      id: index >= 0 ? file[index].id : _prochainId++,
      idChapitre: idChapitre,
      statut: statut,
      nombrePagesFaites: faites,
      nombrePagesTotal: total,
      messageErreur: messageErreur,
    );
    if (index >= 0) {
      file[index] = ligne;
    } else {
      file.add(ligne);
    }
    if (statut == StatutTelechargement.termine) {
      pages.putIfAbsent(idChapitre, () => <Uint8List>[pngMinimal]);
      _marquer(idChapitre, estTelecharge: true);
    }
    signaler();
  }

  void _marquer(int idChapitre, {required bool estTelecharge}) {
    for (final chapitres in bibliotheque.chapitresParTitre.values) {
      for (var i = 0; i < chapitres.length; i++) {
        if (chapitres[i].id == idChapitre) {
          chapitres[i] = chapitres[i].copierAvec(estTelecharge: estTelecharge);
        }
      }
    }
  }

  @override
  Stream<void> get changements => _changements.stream;

  @override
  bool get estEnCours => false;

  @override
  Future<void> demarrer() async {
    nombreDemarrages++;
  }

  @override
  Future<void> fermer() => _changements.close();

  @override
  Future<void> appliquerReglesATous() async {
    nombreAppelsReglesATous++;
    journal.add('reglesATous');
  }

  @override
  Future<PlanTelechargement> appliquerRegles(int idTitre) async {
    reglesAppliquees.add(idTitre);
    journal.add('regles:$idTitre');
    return PlanTelechargement.vide;
  }

  /// Nombre de lectures de la file (regroupement des relectures).
  int nombreLecturesFile = 0;

  /// Si défini, [chargerFile] attend qu'il soit complété (lecture lente).
  Completer<void>? retenueFile;

  @override
  Future<List<Telechargement>> chargerFile() async {
    nombreLecturesFile++;
    final attente = retenueFile;
    if (attente != null) {
      await attente.future;
    }
    final erreur = erreurFile;
    if (erreur != null) {
      throw erreur;
    }
    return List<Telechargement>.of(file);
  }

  @override
  Future<void> telechargerChapitre(int idChapitre) async {
    journal.add('telecharger:$idChapitre');
    final existant = file.where((t) => t.idChapitre == idChapitre).firstOrNull;
    if (existant == null || existant.statut == StatutTelechargement.echec) {
      modifierLigne(idChapitre, StatutTelechargement.enAttente);
    }
  }

  @override
  Future<void> supprimerTelechargement(
    int idChapitre, {
    bool signalerChangement = true,
  }) async {
    journal.add('supprimer:$idChapitre');
    file.removeWhere((t) => t.idChapitre == idChapitre);
    pages.remove(idChapitre);
    textes.remove(idChapitre);
    _marquer(idChapitre, estTelecharge: false);
    if (signalerChangement) signaler();
  }

  @override
  Future<int> viderTermines() async {
    final avant = file.length;
    file.removeWhere((t) => t.statut == StatutTelechargement.termine);
    signaler();
    return avant - file.length;
  }

  @override
  Future<int> compterPages(int idChapitre) async {
    if (!pages.containsKey(idChapitre) && !textes.containsKey(idChapitre)) {
      throw ErreurService('Archive absente pour $idChapitre');
    }
    return pages[idChapitre]?.length ?? 0;
  }

  @override
  Future<Uint8List> lirePage(int idChapitre, int index) async {
    if (pagesIllisibles.contains(index)) {
      throw ErreurService('Page $index illisible');
    }
    return pages[idChapitre]![index];
  }

  @override
  Future<String?> lireTexte(int idChapitre) async => textes[idChapitre];

  @override
  Future<void> lancerTraitement() async {}

  /// Protections posées par le lecteur, par chapitre (compteur).
  final Map<int, int> protections = <int, int>{};

  @override
  void protegerChapitre(int idChapitre) {
    journal.add('proteger:$idChapitre');
    protections.update(idChapitre, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  void libererChapitre(int idChapitre) {
    journal.add('liberer:$idChapitre');
    final nombre = protections[idChapitre];
    if (nombre == null) return;
    if (nombre <= 1) {
      protections.remove(idChapitre);
    } else {
      protections[idChapitre] = nombre - 1;
    }
  }

  @override
  bool estProtege(int idChapitre) => protections.containsKey(idChapitre);

  @override
  String get identifiantVerrou => 'faux-service';

  @override
  Future<List<List<Chapitre>>> chargerDoublons(int idTitre) async =>
      PolitiqueTelechargement.trouverDoublons(
        bibliotheque.chapitresParTitre[idTitre] ?? const <Chapitre>[],
      );

  /// Titres passés à [supprimerTitre].
  final List<int> titresSupprimes = <int>[];

  @override
  Future<void> supprimerTitre(int idTitre) async {
    journal.add('supprimerTitre:$idTitre');
    titresSupprimes.add(idTitre);
    for (final chapitre
        in bibliotheque.chapitresParTitre[idTitre] ?? const <Chapitre>[]) {
      final id = chapitre.id;
      if (id == null) continue;
      file.removeWhere((t) => t.idChapitre == id);
      pages.remove(id);
      textes.remove(id);
    }
    await bibliotheque.supprimerTitre(idTitre);
    bibliotheque.chapitresParTitre.remove(idTitre);
    signaler();
  }

  /// Chapitres gardés par le client (bouton « Garder »).
  final Set<int> gardes = <int>{};

  /// Appels à [supprimerArchivesEchues].
  int nombreControlesEcheances = 0;

  /// Date « actuelle » utilisée pour les échéances (par défaut l'heure
  /// réelle).
  DateTime Function() horloge = DateTime.now;

  /// Programme la suppression d'un chapitre téléchargé à [date].
  void planifierSuppressionDeTest(int idChapitre, DateTime? date) {
    for (final chapitres in bibliotheque.chapitresParTitre.values) {
      for (var i = 0; i < chapitres.length; i++) {
        if (chapitres[i].id == idChapitre) {
          chapitres[i] = date == null
              ? chapitres[i].copierAvec(effacerDateSuppressionPrevue: true)
              : chapitres[i].copierAvec(dateSuppressionPrevue: date);
        }
      }
    }
  }

  @override
  Future<int> supprimerArchivesEchues() async {
    nombreControlesEcheances++;
    journal.add('echeances');
    final maintenant = horloge();
    final echus = <int>[
      for (final chapitres in bibliotheque.chapitresParTitre.values)
        for (final chapitre in chapitres)
          if (chapitre.id != null &&
              chapitre.dateSuppressionPrevue != null &&
              !chapitre.dateSuppressionPrevue!.isAfter(maintenant) &&
              !estProtege(chapitre.id!) &&
              !gardes.contains(chapitre.id))
            chapitre.id!,
    ];
    for (final id in echus) {
      await supprimerTelechargement(id, signalerChangement: false);
      planifierSuppressionDeTest(id, null);
    }
    if (echus.isNotEmpty) signaler();
    return echus.length;
  }

  @override
  Future<void> supprimerMaintenant(int idChapitre) async {
    journal.add('supprimerMaintenant:$idChapitre');
    await supprimerTelechargement(idChapitre, signalerChangement: false);
    planifierSuppressionDeTest(idChapitre, null);
    gardes.remove(idChapitre);
    signaler();
  }

  @override
  Future<void> annulerSuppression(int idChapitre) async {
    journal.add('garder:$idChapitre');
    gardes.add(idChapitre);
    planifierSuppressionDeTest(idChapitre, null);
    signaler();
  }

  @override
  Future<Set<int>> chargerChapitresGardes() async => Set<int>.of(gardes);

  @override
  Future<PlanTelechargement> modifierLanguesTitre(
    int idTitre,
    List<String>? langues,
  ) async {
    journal.add('langues:$idTitre:${langues?.join(',')}');
    bibliotheque.enregistrerLanguesDeTest(idTitre, langues);
    return appliquerRegles(idTitre);
  }

  /// Nombre renvoyé par [reparerArchivesManquantes].
  int archivesReparees = 0;

  @override
  Future<int> reparerArchivesManquantes() async => archivesReparees;
}

/// Faux `ServiceParametres` : réglages gardés en mémoire.
class FauxServiceParametres implements ServiceParametres {
  /// Réglages « enregistrés ».
  ReglagesTelechargement reglages = const ReglagesTelechargement();

  /// Erreur levée par la lecture, si définie.
  Object? erreurLecture;

  /// Nombre d'enregistrements.
  int nombreEnregistrements = 0;

  @override
  Future<ReglagesTelechargement> chargerReglagesTelechargement() async {
    final erreur = erreurLecture;
    if (erreur != null) {
      throw erreur;
    }
    return reglages;
  }

  @override
  Future<void> enregistrerReglagesTelechargement(
    ReglagesTelechargement nouveaux,
  ) async {
    nombreEnregistrements++;
    reglages = nouveaux;
  }

  @override
  Future<void> reinitialiserReglagesTelechargement() async {
    reglages = const ReglagesTelechargement();
  }

  /// Nombre de recherches par jour « enregistré ».
  int verificationsParJour = PlanificationMisesAJour.parDefautParJour;

  /// Date de la dernière recherche « enregistrée ».
  DateTime? derniereVerification;

  @override
  Future<int> chargerVerificationsParJour() async => verificationsParJour;

  @override
  Future<void> enregistrerVerificationsParJour(int nombre) async {
    verificationsParJour = nombre.clamp(
      PlanificationMisesAJour.minimumParJour,
      PlanificationMisesAJour.maximumParJour,
    );
  }

  @override
  Future<PlanificationMisesAJour> chargerPlanification() async =>
      PlanificationMisesAJour(verificationsParJour);

  @override
  Future<DateTime?> chargerDerniereVerification() async => derniereVerification;

  @override
  Future<void> enregistrerDerniereVerification(DateTime date) async {
    derniereVerification = date.toUtc();
  }

  /// Langues de lecture « enregistrées » (la première est la favorite).
  List<String> langues = <String>['fr', 'en'];

  @override
  Future<List<String>> chargerLangues() async => List<String>.of(langues);

  @override
  Future<void> enregistrerLangues(List<String> nouvelles) async {
    final propres = ServiceParametres.nettoyerLangues(nouvelles);
    if (propres.isEmpty) {
      throw const ErreurService('Choisissez au moins une langue de lecture.');
    }
    langues = propres;
  }

  /// Chapitres gardés « enregistrés ».
  Set<int> chapitresGardes = <int>{};

  @override
  Future<Set<int>> chargerChapitresGardes() async =>
      Set<int>.of(chapitresGardes);

  @override
  Future<void> enregistrerChapitresGardes(Iterable<int> ids) async {
    chapitresGardes = ids.toSet();
  }

  /// Verrou de la file « enregistré ».
  VerrouTelechargement? verrou;

  @override
  Future<VerrouTelechargement?> chargerVerrouTelechargement() async => verrou;

  @override
  Future<void> enregistrerVerrouTelechargement(
    VerrouTelechargement nouveau,
  ) async {
    verrou = nouveau;
  }

  @override
  Future<void> supprimerVerrouTelechargement() async {
    verrou = null;
  }
}

/// Faux `ServiceMisesAJour` : renvoie un rapport préparé, sans base ni
/// réseau. Il implémente l'interface du vrai service (le constructeur de
/// celui-ci exige des dépôts branchés sur une base).
class FauxServiceMisesAJour implements ServiceMisesAJour {
  /// Résultats du prochain rapport.
  List<ResultatVerificationTitre> resultats = <ResultatVerificationTitre>[];

  /// Erreur globale levée par la vérification, si définie.
  Object? erreur;

  /// Si défini, la vérification attend qu'il soit complété.
  Completer<void>? retenue;

  /// Action exécutée pendant la vérification (simule l'enregistrement des
  /// nouveaux chapitres dans la base).
  void Function()? pendantVerification;

  /// Nombre d'appels à [verifierTitresSuivis].
  int nombreAppels = 0;

  /// Nombre d'appels à [verifierSiEcheancePassee].
  int nombreControlesEcheance = 0;

  /// Si `false`, [verifierSiEcheancePassee] ne vérifie pas (aucune échéance
  /// passée depuis la dernière vérification).
  bool echeancePassee = true;

  @override
  Future<RapportMisesAJour?> verifierSiEcheancePassee() async {
    nombreControlesEcheance++;
    if (!echeancePassee) return null;
    return verifierTitresSuivis();
  }

  bool _estEnCours = false;

  @override
  bool get estEnCours => _estEnCours;

  @override
  Future<RapportMisesAJour> verifierTitresSuivis() async {
    nombreAppels++;
    _estEnCours = true;
    try {
      final attente = retenue;
      if (attente != null) {
        await attente.future;
      }
      final panne = erreur;
      if (panne != null) {
        throw panne;
      }
      pendantVerification?.call();
      final date = DateTime.utc(2026, 11, 15, 12);
      return RapportMisesAJour(
        debut: date,
        fin: date,
        resultats: List<ResultatVerificationTitre>.of(resultats),
      );
    } finally {
      _estEnCours = false;
    }
  }
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
  FauxServiceMisesAJour? misesAJour,
  FauxServiceTelechargement? telechargement,
  FauxServiceParametres? parametres,
  bool verifierMisesAJourAuDemarrage = false,
}) {
  final serviceTelechargement =
      telechargement ?? FauxServiceTelechargement(bibliotheque);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<EtatMisesAJour>(
        create: (_) => EtatMisesAJour(
          misesAJour ?? FauxServiceMisesAJour(),
          planifier: verifierMisesAJourAuDemarrage,
          serviceTelechargement: serviceTelechargement,
        )..demarrer(),
      ),
      Provider<EtatCouvertures>(create: (_) => EtatCouvertures(bibliotheque)),
      ChangeNotifierProvider<EtatBibliotheque>(
        create: (_) => EtatBibliotheque(
          bibliotheque,
          serviceTelechargement: serviceTelechargement,
        )..charger(),
      ),
      ChangeNotifierProvider<EtatSources>(
        create: (_) => EtatSources(
          bibliotheque,
          ajoutSite ?? FauxServiceAjoutSite(bibliotheque),
          serviceTelechargement: serviceTelechargement,
        )..charger(),
      ),
      ChangeNotifierProvider<EtatTelechargements>(
        create: (_) =>
            EtatTelechargements(serviceTelechargement, bibliotheque)..charger(),
      ),
      ChangeNotifierProvider<EtatParametres>(
        create: (_) => EtatParametres(
          parametres ?? FauxServiceParametres(),
          serviceTelechargement,
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
