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
import 'package:bibliotheque_perso/etat/etat_export.dart';
import 'package:bibliotheque_perso/etat/etat_mises_a_jour.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_parutions.dart';
import 'package:bibliotheque_perso/etat/etat_rapports_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/etat/etat_telechargements.dart';
import 'package:bibliotheque_perso/main.dart';
import 'package:bibliotheque_perso/modeles/categorie.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/lien_titre_source.dart';
import 'package:bibliotheque_perso/modeles/liste_lecture.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/planification_mises_a_jour.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_export.dart';
import 'package:bibliotheque_perso/services/service_import.dart';
import 'package:bibliotheque_perso/services/service_mises_a_jour.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_rapports_erreur.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/services/verrou_telechargement.dart';
import 'package:bibliotheque_perso/sources/couverture_site.dart';
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

/// Identifiant de la liste système « Planifié » dans les faux services.
const int idListePlanifie = 4;

/// Identifiant de la liste système « En attente » dans les faux services.
const int idListeEnAttente = 5;

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
    // Même ordre que la base : listes système d'abord.
    const ListeLecture(
      id: idListePlanifie,
      nom: nomListePlanifie,
      estSysteme: true,
      ordre: ordreListePlanifie,
    ),
    const ListeLecture(
      id: idListeEnAttente,
      nom: nomListeEnAttente,
      estSysteme: true,
      ordre: ordreListeEnAttente,
    ),
    const ListeLecture(id: 3, nom: 'À lire plus tard', ordre: 4),
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

  /// Derniers niveaux de contenu reçus par [chargerTitres] (`null` : pas de
  /// filtre).
  List<String>? derniersNiveauxDemandes;

  @override
  Future<List<Titre>> chargerTitres({
    String? recherche,
    int? idListe,
    int? idCategorie,
    List<String>? niveauxContenu,
    bool inclureNiveauInconnu = true,
  }) async {
    await _lire();
    derniersNiveauxDemandes = niveauxContenu;
    final texte = recherche?.toLowerCase();
    bool niveauAccepte(Titre titre) {
      if (niveauxContenu == null) return true;
      final niveau = titre.niveauContenu;
      if (niveau == null) return inclureNiveauInconnu;
      return niveauxContenu.contains(niveau);
    }

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
                )) &&
            niveauAccepte(titre))
          _avecNonLus(titre),
    ];
  }

  /// Remplace un titre de test (niveau de contenu, couverture choisie…).
  void remplacerTitreDeTest(Titre titre) {
    final index = titres.indexWhere((existant) => existant.id == titre.id);
    if (index >= 0) titres[index] = titre;
  }

  // ------------------------------------------------- Étape 6 : En attente

  /// Appels à [classerTousEnAttente].
  int nombreClassements = 0;

  @override
  Future<bool> classerEnAttente(int idTitre) async =>
      (listesParTitre[idTitre] ?? const <int>{}).contains(idListeEnAttente);

  @override
  Future<int> classerTousEnAttente() async {
    nombreClassements++;
    return listesParTitre.values
        .where((ids) => ids.contains(idListeEnAttente))
        .length;
  }

  // ------------------------------------------------ Étape 6 : Mises à jour

  /// Lignes renvoyées par [chargerDernieresParutions].
  List<ParutionTitre> parutions = <ParutionTitre>[];

  /// Nombre d'appels à [chargerDernieresParutions].
  int nombreLecturesParutions = 0;

  @override
  Future<List<ParutionTitre>> chargerDernieresParutions() async {
    nombreLecturesParutions++;
    await _lire();
    return List<ParutionTitre>.of(parutions);
  }

  // -------------------------------------------------- Étape 6 : Couvertures

  /// Chemins des couvertures enregistrées sur l'appareil, par titre.
  final Map<int, String> cheminsCouvertures = <int, String>{};

  /// Titres dont la couverture a été demandée par [chargerCouverture].
  final List<int> couverturesChargees = <int>[];

  /// Couvertures proposées par le site ([recupererCouverturesDuSite]).
  List<CouvertureSite> couverturesSite = <CouvertureSite>[];

  /// Erreur levée par [recupererCouverturesDuSite] et les choix de
  /// couverture, si définie.
  Object? erreurCouvertures;

  @override
  Future<String?> cheminCouvertureLocale(Titre titre) async =>
      cheminsCouvertures[titre.id];

  @override
  Future<Uint8List?> chargerCouverture(Titre titre) async {
    if (titre.id != null) couverturesChargees.add(titre.id!);
    return octetsCouverture;
  }

  /// Titres dont la couverture en pleine taille a été demandée par
  /// [chargerCouvertureOriginale].
  final List<int> couverturesOriginalesChargees = <int>[];

  /// Octets renvoyés par [chargerCouvertureOriginale] ; `null` : les mêmes
  /// que [chargerCouverture] (comme le vrai service hors MangaDex).
  Uint8List? octetsCouvertureOriginale;

  @override
  Future<Uint8List?> chargerCouvertureOriginale(Titre titre) async {
    if (titre.id != null) couverturesOriginalesChargees.add(titre.id!);
    return octetsCouvertureOriginale ?? octetsCouverture;
  }

  /// URLs dont la vignette a été demandée par [recupererVignette] (elles
  /// figurent aussi dans [couverturesDemandees]).
  final List<String> vignettesDemandees = <String>[];

  // Méthode réservée aux tests du service réel : le faux service n'a pas de cache.
  @override
  bool estCouvertureEnCache(String urlCouverture) => false;

  @override
  Future<Uint8List> recupererVignette(String urlCouverture, {String? referer}) {
    vignettesDemandees.add(urlCouverture);
    return recupererCouverture(urlCouverture, referer: referer);
  }

  @override
  Future<List<CouvertureSite>> recupererCouverturesDuSite(Titre titre) async {
    final erreur = erreurCouvertures;
    if (erreur != null) throw erreur;
    return List<CouvertureSite>.of(couverturesSite);
  }

  Titre _changerCouverture(int idTitre, String? choix) {
    final erreur = erreurCouvertures;
    if (erreur != null) throw erreur;
    final index = titres.indexWhere((titre) => titre.id == idTitre);
    if (index < 0) throw const ErreurService("Ce titre n'existe plus.");
    titres[index] = choix == null
        ? titres[index].copierAvec(effacerCouvertureChoisie: true)
        : titres[index].copierAvec(couvertureChoisie: choix);
    return titres[index];
  }

  @override
  Future<Titre> choisirCouverture(int idTitre, String urlCouverture) async =>
      _changerCouverture(idTitre, urlCouverture);

  @override
  Future<Titre> choisirCouvertureLocale(
    int idTitre,
    String cheminImage,
  ) async => _changerCouverture(idTitre, cheminImage);

  @override
  Future<Titre> retablirCouvertureDuSite(int idTitre) async =>
      _changerCouverture(idTitre, null);

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

  /// Derniers filtres de site reçus par [chargerChapitres].
  final List<int?> filtresSiteDemandes = <int?>[];

  @override
  Future<List<Chapitre>> chargerChapitres(int idTitre, {int? idSource}) async {
    await _lire();
    filtresSiteDemandes.add(idSource);
    final titre = titres.where((t) => t.id == idTitre).firstOrNull;
    return <Chapitre>[
      for (final chapitre in chapitresParTitre[idTitre] ?? const <Chapitre>[])
        // Même règle que le dépôt : un chapitre sans site connu vient du site
        // principal.
        if (idSource == null ||
            (chapitre.idSource ?? titre?.idSource) == idSource)
          chapitre,
    ];
  }

  // ------------------------------------------- Étape 8 : sites d'un titre

  /// Sites secondaires par identifiant de titre (le principal vient de
  /// `Titre.idSource` / `Titre.urlTitre`).
  final Map<int, List<LienTitreSource>> sitesSecondaires =
      <int, List<LienTitreSource>>{};

  /// Erreur levée par [ajouterSiteAuTitre], [retirerSiteDuTitre] et
  /// [definirSitePrincipal], si définie.
  Object? erreurSites;

  /// Chapitres ajoutés par [ajouterSiteAuTitre] (recopiés avec le titre et
  /// le site ajouté).
  List<Chapitre> chapitresSiteAjoute = <Chapitre>[];

  /// Erreurs par site renvoyées par [actualiserTitre].
  Map<int, Object> erreursParSiteActualisation = <int, Object>{};

  /// Si défini, [ajouterTitreDepuisUrl] renvoie ce titre comme déjà présent
  /// (adresse d'un site secondaire).
  int? idTitreDejaPresent;

  /// Journal des appels aux méthodes des sites (« ajouter:1:url »…).
  final List<String> journalSites = <String>[];

  /// Ajoute un site secondaire de test au titre [idTitre].
  void ajouterSiteDeTest(int idTitre, int idSource, String url) {
    (sitesSecondaires[idTitre] ??= <LienTitreSource>[]).add(
      LienTitreSource(idTitre: idTitre, idSource: idSource, urlTitre: url),
    );
  }

  Titre? _titreParId(int idTitre) =>
      titres.where((t) => t.id == idTitre).firstOrNull;

  @override
  Future<List<LienTitreSource>> chargerLiensDuTitre(Titre titre) async {
    final idTitre = titre.id;
    final actuel = idTitre == null ? null : _titreParId(idTitre);
    final idSource = actuel?.idSource ?? titre.idSource;
    if (idTitre == null || idSource == null) {
      return const <LienTitreSource>[];
    }
    return <LienTitreSource>[
      LienTitreSource(
        idTitre: idTitre,
        idSource: idSource,
        urlTitre: actuel?.urlTitre ?? titre.urlTitre,
        estPrincipale: true,
      ),
      ...?sitesSecondaires[idTitre],
    ];
  }

  @override
  Future<List<SiteDuTitre>> chargerSitesDuTitre(int idTitre) async {
    await _lire();
    final titre = _titreParId(idTitre);
    if (titre == null) return const <SiteDuTitre>[];
    final chapitres = chapitresParTitre[idTitre] ?? const <Chapitre>[];
    return <SiteDuTitre>[
      for (final lien in await chargerLiensDuTitre(titre))
        SiteDuTitre(
          lien: lien,
          source: sources.where((s) => s.id == lien.idSource).firstOrNull,
          nomSite:
              sources.where((s) => s.id == lien.idSource).firstOrNull?.nom ??
              Uri.parse(lien.urlTitre).host,
          nombreChapitres: chapitres
              .where((c) => (c.idSource ?? titre.idSource) == lien.idSource)
              .length,
        ),
    ];
  }

  @override
  Future<ResultatAjoutTitre> ajouterSiteAuTitre(
    int idTitre,
    String urlTitre, {
    bool lienSeul = false,
  }) async {
    journalSites.add('${lienSeul ? 'lienSeul' : 'ajouter'}:$idTitre:$urlTitre');
    // Un lien seul ne lit pas le site : l'erreur de lecture ne le concerne
    // pas (comme le vrai service).
    final erreur = lienSeul ? null : erreurSites;
    if (erreur != null) throw erreur;
    final titre = _titreParId(idTitre);
    if (titre == null) throw const ErreurService("Ce titre n'existe plus.");
    final uri = Uri.parse(urlTitre.trim());
    var source = sources.where((s) => s.urlBase.contains(uri.host)).firstOrNull;
    if (source == null) {
      source = Source(
        id: sources.length + 100,
        nom: uri.host,
        urlBase: 'https://${uri.host}',
        typeSource: TypeSource.generique,
      );
      sources.add(source);
    }
    if (lienSeul) {
      (sitesSecondaires[idTitre] ??= <LienTitreSource>[]).add(
        LienTitreSource(
          idTitre: idTitre,
          idSource: source.id!,
          urlTitre: urlTitre.trim(),
          estLienSeul: true,
        ),
      );
      return ResultatAjoutTitre(titre, 0);
    }
    ajouterSiteDeTest(idTitre, source.id!, urlTitre.trim());
    final ajoutes = <Chapitre>[
      for (final chapitre in chapitresSiteAjoute)
        chapitre.copierAvec(idTitre: idTitre, idSource: source.id),
    ];
    (chapitresParTitre[idTitre] ??= <Chapitre>[]).addAll(ajoutes);
    return ResultatAjoutTitre(titre, ajoutes.length);
  }

  @override
  Future<int> retirerSiteDuTitre(int idTitre, int idSource) async {
    journalSites.add('retirer:$idTitre:$idSource');
    final erreur = erreurSites;
    if (erreur != null) throw erreur;
    final titre = _titreParId(idTitre);
    if (titre?.idSource == idSource) {
      throw const ErreurService(
        "Le site principal d'un titre ne peut pas être retiré.",
      );
    }
    sitesSecondaires[idTitre]?.removeWhere((l) => l.idSource == idSource);
    final chapitres = chapitresParTitre[idTitre];
    if (chapitres == null) return 0;
    final avant = chapitres.length;
    chapitres.removeWhere(
      (c) => c.idSource == idSource && !c.estLu && !c.estTelecharge,
    );
    return avant - chapitres.length;
  }

  @override
  Future<ResultatAjoutTitre> definirSitePrincipal(
    int idTitre,
    int idSource,
  ) async {
    journalSites.add('principal:$idTitre:$idSource');
    final erreur = erreurSites;
    if (erreur != null) throw erreur;
    final index = titres.indexWhere((t) => t.id == idTitre);
    if (index < 0) throw const ErreurService("Ce titre n'existe plus.");
    final ancien = titres[index];
    final secondaires = sitesSecondaires[idTitre] ?? <LienTitreSource>[];
    final lien = secondaires.where((l) => l.idSource == idSource).firstOrNull;
    if (lien == null) {
      throw const ErreurService("Ce site n'est pas lié à ce titre.");
    }
    secondaires
      ..remove(lien)
      ..add(
        LienTitreSource(
          idTitre: idTitre,
          idSource: ancien.idSource!,
          urlTitre: ancien.urlTitre,
        ),
      );
    titres[index] = ancien.copierAvec(
      idSource: idSource,
      urlTitre: lien.urlTitre,
    );
    return ResultatAjoutTitre(titres[index], 0);
  }

  @override
  Future<int> marquerLienSeul(int idTitre, int idSource, bool lienSeul) async {
    journalSites.add('marquerLienSeul:$idTitre:$idSource:$lienSeul');
    final erreur = erreurSites;
    if (erreur != null) throw erreur;
    final titre = _titreParId(idTitre);
    if (titre == null) throw const ErreurService("Ce titre n'existe plus.");
    if (titre.idSource == idSource) {
      throw const ErreurService(
        "Le site principal d'un titre ne peut pas être un simple lien.",
      );
    }
    final secondaires = sitesSecondaires[idTitre] ?? <LienTitreSource>[];
    final index = secondaires.indexWhere((l) => l.idSource == idSource);
    if (index < 0) {
      throw const ErreurService("Ce site n'est pas lié à ce titre.");
    }
    secondaires[index] = secondaires[index].copierAvec(estLienSeul: lienSeul);
    if (!lienSeul) return 0;
    final chapitres = chapitresParTitre[idTitre];
    if (chapitres == null) return 0;
    final avant = chapitres.length;
    chapitres.removeWhere(
      (c) => c.idSource == idSource && !c.estLu && !c.estTelecharge,
    );
    return avant - chapitres.length;
  }

  /// Diagnostic renvoyé par [diagnostiquerSite] (lisible par défaut).
  DiagnosticLisibilite diagnosticSite = const DiagnosticLisibilite(
    raisons: <String>[],
  );

  /// Adresses reçues par [diagnostiquerSite].
  final List<String> sitesDiagnostiques = <String>[];

  @override
  Future<DiagnosticLisibilite> diagnostiquerSite(String url) async {
    await _lire();
    sitesDiagnostiques.add(url);
    return diagnosticSite;
  }

  /// Erreur levée par [actualiserSiteDuTitre], si définie.
  Object? erreurActualisationSite;

  @override
  Future<ResultatAjoutTitre> actualiserSiteDuTitre(
    Titre titre,
    int idSource,
  ) async {
    journalSites.add('actualiserSite:${titre.id}:$idSource');
    final erreur = erreurActualisationSite;
    if (erreur != null) throw erreur;
    return ResultatAjoutTitre(titre, 0);
  }

  @override
  Future<ResultatAjoutTitre> essayerDeLireLienSeul(
    int idTitre,
    int idSource,
  ) async {
    journalSites.add('essayerDeLireLienSeul:$idTitre:$idSource');
    final titre = _titreParId(idTitre);
    if (titre == null) throw const ErreurService("Ce titre n'existe plus.");
    // Comme le vrai service : en cas d'échec, rien n'est écrit (le site
    // reste lien seul).
    final erreur = erreurActualisationSite;
    if (erreur != null) throw erreur;
    final secondaires = sitesSecondaires[idTitre] ?? <LienTitreSource>[];
    final index = secondaires.indexWhere((l) => l.idSource == idSource);
    if (index < 0) {
      throw const ErreurService("Ce site n'est pas lié à ce titre.");
    }
    secondaires[index] = secondaires[index].copierAvec(estLienSeul: false);
    return ResultatAjoutTitre(titre, 0);
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
    final dejaPresent = idTitreDejaPresent;
    if (dejaPresent != null) {
      for (final idListe in idsListes) {
        (listesParTitre[dejaPresent] ??= <int>{}).add(idListe);
      }
      return ResultatAjoutTitre(
        _titreParId(dejaPresent)!,
        0,
        estDejaPresent: true,
      );
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
    return ResultatAjoutTitre(
      titre,
      nombreNouveaux,
      erreursParSite: Map<int, Object>.of(erreursParSiteActualisation),
    );
  }

  @override
  Future<List<Titre>> rechercherSurSource(
    Source source,
    String requete,
  ) async => const <Titre>[];

  @override
  Future<void> ajouterTitreALaListe(int idListe, int idTitre) async {
    _refuserEnAttente(idListe);
    (listesParTitre[idTitre] ??= <int>{}).add(idListe);
  }

  @override
  Future<void> retirerTitreDeLaListe(int idListe, int idTitre) async {
    _refuserEnAttente(idListe);
    listesParTitre[idTitre]?.remove(idListe);
  }

  /// Même refus que le vrai service : « En attente » est automatique.
  void _refuserEnAttente(int idListe) {
    if (idListe == idListeEnAttente) {
      throw const ErreurService('La liste « En attente » est automatique.');
    }
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
    // Même normalisation que le vrai service (réglages vérifiés s'ils ont
    // changé, effacés s'ils sont vides).
    final brut = source.configurationSelecteurs;
    final avant = bibliotheque.sources
        .where((s) => s.id == source.id)
        .firstOrNull
        ?.configurationSelecteurs;
    final reglages = brut != null && brut == avant
        ? brut
        : ServiceAjoutSite.normaliserReglagesGeneriques(brut);
    final modifiee = source.copierAvec(
      nom: source.nom.trim(),
      langueParDefaut: source.langueParDefaut
          .split(',')
          .map((code) => code.trim().toLowerCase())
          .where((code) => code.isNotEmpty)
          .join(','),
      configurationSelecteurs: reglages,
      effacerConfigurationSelecteurs: reglages == null,
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

  /// Erreur levée par [appliquerRegles] (après l'avoir noté), si définie.
  Object? erreurRegles;

  @override
  Future<PlanTelechargement> appliquerRegles(int idTitre) async {
    reglesAppliquees.add(idTitre);
    journal.add('regles:$idTitre');
    final erreur = erreurRegles;
    if (erreur != null) throw erreur;
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
    _marquerGarde(idChapitre, estGarde: true);
    signaler();
  }

  @override
  Future<void> retirerGarde(int idChapitre) async {
    journal.add('retirerGarde:$idChapitre');
    gardes.remove(idChapitre);
    _marquerGarde(idChapitre, estGarde: false);
    signaler();
  }

  void _marquerGarde(int idChapitre, {required bool estGarde}) {
    for (final chapitres in bibliotheque.chapitresParTitre.values) {
      for (var i = 0; i < chapitres.length; i++) {
        if (chapitres[i].id == idChapitre) {
          chapitres[i] = chapitres[i].copierAvec(estGarde: estGarde);
        }
      }
    }
  }

  @override
  Future<List<Chapitre>> chargerSuppressionsPrevues({int? idTitre}) async {
    final prevues = <Chapitre>[
      for (final MapEntry(key: id, value: chapitres)
          in bibliotheque.chapitresParTitre.entries)
        if (idTitre == null || id == idTitre)
          for (final chapitre in chapitres)
            if (chapitre.dateSuppressionPrevue != null &&
                chapitre.estTelecharge &&
                !gardes.contains(chapitre.id))
              chapitre,
    ];
    prevues.sort(
      (a, b) => a.dateSuppressionPrevue!.compareTo(b.dateSuppressionPrevue!),
    );
    return prevues;
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

  /// Sources par défaut déjà proposées.
  Set<String> sourcesParDefautProposees = <String>{};

  @override
  Future<Set<String>> chargerSourcesParDefautProposees() async =>
      Set<String>.of(sourcesParDefautProposees);

  @override
  Future<void> enregistrerSourcesParDefautProposees(
    Iterable<String> identifiants,
  ) async {
    sourcesParDefautProposees = identifiants.toSet();
  }

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

  @override
  Future<void> supprimerChapitresGardes() async {
    chapitresGardes = <int>{};
  }

  // ------------------------------------------------------------ Étape 6

  /// Écart « enregistré » des vérifications des titres en attente (`null` :
  /// valeur par défaut).
  int? heuresEnAttente;

  /// Date de la dernière vérification des titres en attente.
  DateTime? derniereVerificationEnAttente;

  /// Niveaux de contenu « enregistrés » (`null` : valeur par défaut).
  List<String>? niveaux;

  @override
  Future<int> chargerHeuresEnAttente() async {
    final maximum = ServiceParametres.maximumHeuresEnAttente(
      verificationsParJour,
    );
    final valeur = heuresEnAttente ?? 1;
    return valeur.clamp(1, maximum);
  }

  @override
  Future<void> enregistrerHeuresEnAttente(int heures) async {
    heuresEnAttente = heures.clamp(
      1,
      ServiceParametres.maximumHeuresEnAttente(verificationsParJour),
    );
  }

  @override
  Future<PlanificationMisesAJour> chargerPlanificationEnAttente() async =>
      PlanificationMisesAJour.toutesLesHeures(await chargerHeuresEnAttente());

  @override
  Future<DateTime?> chargerDerniereVerificationEnAttente() async =>
      derniereVerificationEnAttente;

  @override
  Future<void> enregistrerDerniereVerificationEnAttente(DateTime date) async {
    derniereVerificationEnAttente = date.toUtc();
  }

  @override
  Future<List<String>> chargerNiveauxContenu() async =>
      List<String>.of(niveaux ?? niveauxContenuParDefaut);

  @override
  Future<void> enregistrerNiveauxContenu(Iterable<String> nouveaux) async {
    niveaux = ServiceParametres.nettoyerNiveauxContenu(nouveaux);
  }

  @override
  Future<void> reinitialiserNiveauxContenu() async {
    niveaux = null;
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

  /// Prochaine échéance imposée à [chargerProchaineEcheance] ; `null` : elle
  /// est calculée comme le vrai service, à partir de [parametres].
  DateTime? prochaineEcheance;

  /// Réglages lus par [chargerProchaineEcheance] (comme le vrai service) ;
  /// `null` : planification par défaut (00:00 et 12:00 UTC).
  FauxServiceParametres? parametres;

  /// `true` si la liste « En attente » contient des titres (leur
  /// surveillance horaire compte alors dans la prochaine échéance).
  bool aDesTitresEnAttente = false;

  @override
  Future<DateTime> chargerProchaineEcheance(DateTime maintenant) async {
    final imposee = prochaineEcheance;
    if (imposee != null) return imposee;
    final reglages = parametres;
    final normale = PlanificationMisesAJour(
      reglages?.verificationsParJour ??
          PlanificationMisesAJour.parDefautParJour,
    ).prochaineEcheance(maintenant);
    if (reglages == null || !aDesTitresEnAttente) return normale;
    final enAttente = (await reglages.chargerPlanificationEnAttente())
        .prochaineEcheance(maintenant);
    return enAttente.isBefore(normale) ? enAttente : normale;
  }

  /// Nombre d'appels à [verifierTitresEnAttente].
  int nombreVerificationsEnAttente = 0;

  @override
  Future<RapportMisesAJour> verifierTitresEnAttente() async {
    nombreVerificationsEnAttente++;
    final date = DateTime.utc(2026, 11, 15, 12);
    return RapportMisesAJour(
      debut: date,
      fin: date,
      resultats: const <ResultatVerificationTitre>[],
      estEnAttenteSeulement: true,
    );
  }

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

/// Faux `ServiceRapportsErreur` : n'écrit aucun fichier, garde les erreurs
/// reçues et renvoie un chemin fictif.
class FauxServiceRapportsErreur implements ServiceRapportsErreur {
  /// Erreurs exportées, avec l'action décrite.
  final List<({Object erreur, String? action})> exportes =
      <({Object erreur, String? action})>[];

  /// Erreur levée par l'export, si définie.
  Object? erreurExport;

  @override
  String get dossierRapports => 'C:/rapports';

  @override
  Future<String> exporterRapport(
    Object erreur, {
    String? action,
    TypeSource? typeDetecte,
  }) async {
    final panne = erreurExport;
    if (panne != null) throw panne;
    exportes.add((erreur: erreur, action: action));
    return 'C:/rapports/rapport_${exportes.length}.txt';
  }
}

/// Faux `ServiceExport` : n'écrit aucun fichier, renvoie des chemins fictifs.
class FauxServiceExport implements ServiceExport {
  /// Nombre d'appels à [exporter].
  int nombreExports = 0;

  /// Erreur levée par [exporter], si définie.
  Object? erreur;

  /// Si défini, [exporter] attend qu'il soit complété (export en cours).
  Completer<void>? retenue;

  /// Nombres annoncés par le résultat.
  int nombreTitres = 12;

  /// Nombres annoncés par le résultat.
  int nombreSites = 2;

  /// Exports JSON renvoyés par [listerExportsJson].
  List<String> exportsJson = <String>[];

  @override
  Future<List<String>> listerExportsJson() async =>
      List<String>.of(exportsJson);

  @override
  String get dossierExports => 'C:/exports';

  @override
  Future<ResultatExport> exporter({DateTime? date}) async {
    nombreExports++;
    final attente = retenue;
    if (attente != null) await attente.future;
    final panne = erreur;
    if (panne != null) throw panne;
    return ResultatExport(
      cheminJson: 'C:/exports/export.json',
      cheminMarkdown: 'C:/exports/export.md',
      nombreTitres: nombreTitres,
      nombreSites: nombreSites,
    );
  }

  @override
  Future<ContenuExport> chargerContenu({DateTime? date}) async =>
      ContenuExport(date: date ?? DateTime.utc(2026, 11, 16));
}

/// Faux service d'import (U1) : renvoie [resultat] ou lève [erreur], et note
/// les chemins importés.
class FauxServiceImport implements ServiceImport {
  /// Chemins reçus par [importerFichier].
  final List<String> chemins = <String>[];

  /// Erreur levée par l'import, si définie.
  Object? erreur;

  /// Si défini, l'import attend qu'il soit complété (import en cours).
  Completer<void>? retenue;

  /// Résultat renvoyé.
  ResultatImport resultat = const ResultatImport(
    versionFormat: 1,
    titresAjoutes: 2,
    titresIgnores: 1,
  );

  @override
  Future<ResultatImport> importerFichier(
    String chemin, {
    bool? appliquerReglagesGeneraux,
  }) async {
    chemins.add(chemin);
    final attente = retenue;
    if (attente != null) await attente.future;
    final panne = erreur;
    if (panne != null) throw panne;
    return resultat;
  }

  @override
  Future<ResultatImport> importerTexte(
    String texte, {
    bool? appliquerReglagesGeneraux,
  }) => importerFichier('<texte>');
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
  FauxServiceRapportsErreur? rapports,
  FauxServiceExport? export,
  FauxServiceImport? importation,
  Future<List<String>> Function()? listerExports,
  bool verifierMisesAJourAuDemarrage = false,
  DateTime Function()? maintenant,
}) {
  final serviceTelechargement =
      telechargement ?? FauxServiceTelechargement(bibliotheque);
  final serviceParametres = parametres ?? FauxServiceParametres();
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
      Provider<EtatRapportsErreur>(
        create: (_) =>
            EtatRapportsErreur(rapports ?? FauxServiceRapportsErreur()),
      ),
      // Section « Sauvegarde et export » seulement si un faux service est
      // fourni (comme l'application sans service).
      if (export != null)
        ChangeNotifierProvider<EtatExport>(
          create: (_) => EtatExport(
            export,
            serviceImport: importation,
            listerExports: listerExports,
          ),
        ),
      ChangeNotifierProvider<EtatBibliotheque>(
        create: (_) => EtatBibliotheque(
          bibliotheque,
          serviceTelechargement: serviceTelechargement,
          serviceParametres: serviceParametres,
        )..charger(),
      ),
      ChangeNotifierProvider<EtatParutions>(
        create: (_) =>
            EtatParutions(bibliotheque, maintenant: maintenant)..charger(),
      ),
      ChangeNotifierProvider<EtatSources>(
        create: (_) => EtatSources(
          bibliotheque,
          ajoutSite ?? FauxServiceAjoutSite(bibliotheque),
          serviceTelechargement: serviceTelechargement,
        )..charger(),
      ),
      ChangeNotifierProvider<EtatTelechargements>(
        create: (_) => EtatTelechargements(
          serviceTelechargement,
          bibliotheque,
          maintenant: maintenant == null ? null : () => maintenant().toUtc(),
        )..charger(),
      ),
      ChangeNotifierProvider<EtatParametres>(
        create: (_) => EtatParametres(
          serviceParametres,
          serviceTelechargement,
          serviceBibliotheque: bibliotheque,
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
