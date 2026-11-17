/// État de la fiche d'un titre : informations, listes, catégories et
/// chapitres.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../modeles/categorie.dart';
import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/liste_lecture.dart';
import '../modeles/source.dart';
import '../modeles/telechargement.dart';
import '../modeles/titre.dart';
import '../services/classement_listes.dart';
import '../services/service_bibliotheque.dart';
import '../services/service_telechargement.dart';
import 'constantes_etat.dart';
import 'description_erreur.dart';
import 'etat_lecteur.dart';
import 'outils_chapitres.dart';

// L'interface affiche les sites du titre sans importer les services.
export '../services/service_bibliotheque.dart'
    show DiagnosticLisibilite, SiteDuTitre;

/// Couverture proposée par le site, pour le choix du client.
///
/// Recopie de `CouvertureSite` (couche sources) : les états ne dépendent
/// que des services (PLAYBOOK.md section 4).
class CouvertureProposee {
  /// Crée la couverture proposée.
  const CouvertureProposee({
    required this.url,
    this.urlMiniature,
    this.volume,
    this.langue,
  });

  /// Adresse de l'image en taille réelle (celle qui sera retenue).
  final String url;

  /// Adresse d'une version réduite, plus légère pour la liste de choix.
  final String? urlMiniature;

  /// Volume illustré (« 1 », « 10.5 »…), ou `null`.
  final String? volume;

  /// Langue de l'édition, ou `null`.
  final String? langue;

  /// Image à afficher dans la liste de choix (miniature si possible).
  String get urlAffichee => urlMiniature ?? url;
}

/// Fiche d'un titre et actions sur ses chapitres et ses listes.
class EtatTitre extends EtatNotifiant {
  /// Crée l'état du titre [idTitre] ; appeler [charger] pour lire la base.
  ///
  /// Sans [serviceTelechargement], la fiche n'affiche pas l'état hors-ligne
  /// des chapitres (tests de l'étape 3).
  ///
  /// [maintenant] permet aux tests de fixer l'heure du compte à rebours des
  /// suppressions prévues.
  EtatTitre(
    this._service,
    this.idTitre, {
    ServiceTelechargement? serviceTelechargement,
    DateTime Function()? maintenant,
  }) : _serviceTelechargement = serviceTelechargement,
       _maintenant = maintenant ?? (() => DateTime.now().toUtc()) {
    // La file change à chaque page téléchargée : la fiche suit la
    // progression de ses chapitres sans que le client ne recharge.
    _abonnement = serviceTelechargement?.changements.listen(
      (_) => unawaited(_relireTelechargements()),
    );
  }

  final ServiceBibliotheque _service;
  final ServiceTelechargement? _serviceTelechargement;
  final DateTime Function() _maintenant;
  StreamSubscription<void>? _abonnement;

  /// Rafraîchit le compte à rebours des suppressions prévues ; actif
  /// seulement si un chapitre affiché en a une.
  Timer? _minuterieCompteARebours;

  /// Identifiant du titre affiché.
  final int idTitre;

  /// Langues appliquées à ce titre (propres au titre, sinon du site, sinon
  /// réglage général), la favorite d'abord.
  List<String> _langues = const <String>[];

  /// Langues du réglage général du client (« Mes langues »).
  List<String> _languesGenerales = const <String>[];

  /// Chapitres téléchargés en double (même numéro, même langue).
  Set<int> _idsDoublons = const <int>{};

  /// Heure actuelle (UTC) pour le compte à rebours des suppressions.
  DateTime get maintenant => _maintenant();

  /// Langues appliquées à ce titre, la favorite d'abord.
  List<String> get langues => _langues;

  /// Langues du réglage général (« Mes langues »).
  List<String> get languesGenerales => _languesGenerales;

  /// `true` si le client a choisi des langues propres à ce titre (sinon le
  /// titre suit le réglage général, ou l'ancien réglage de son site).
  bool get aLanguesPropres => _titre?.listeLanguesPreferees.isNotEmpty ?? false;

  /// `true` si [chapitre] est un doublon téléchargé.
  bool estDoublon(Chapitre chapitre) => _idsDoublons.contains(chapitre.id);

  /// Nombre de chapitres téléchargés en double.
  int get nombreDoublons => _idsDoublons.length;

  /// Nombre de chapitres dont la suppression automatique est prévue.
  int get nombreSuppressionsPrevues => _chapitres
      .where(
        (chapitre) =>
            chapitre.estTelecharge && chapitre.dateSuppressionPrevue != null,
      )
      .length;

  /// Lignes de la file de téléchargement des chapitres de ce titre.
  Map<int, Telechargement> _telechargements = const <int, Telechargement>{};

  /// Versions regroupées par numéro, du plus récent au plus ancien.
  List<GroupeChapitres> _groupes = const <GroupeChapitres>[];

  Titre? _titre;
  Source? _source;

  /// Sites du titre (étape 8), le principal d'abord.
  List<SiteDuTitre> _sites = const <SiteDuTitre>[];

  /// Site choisi dans le filtre des chapitres, `null` = tous les sites.
  int? _idSiteFiltre;

  /// Noms des sites qui n'ont pas répondu à la dernière actualisation.
  List<String> _sitesSansReponse = const <String>[];

  bool _estEnModificationSites = false;
  List<Categorie> _categories = const <Categorie>[];
  List<ListeLecture> _listes = const <ListeLecture>[];
  Set<int> _idsListesDuTitre = const <int>{};
  List<Chapitre> _chapitres = const <Chapitre>[];
  bool _estEnChargement = false;
  bool _estEnActualisation = false;
  DescriptionErreur? _erreur;

  /// Titre chargé, ou `null` avant le chargement ou en cas d'erreur.
  Titre? get titre => _titre;

  /// Site d'où vient le titre, si connu.
  Source? get source => _source;

  /// Catégories du titre.
  List<Categorie> get categories => _categories;

  /// Toutes les listes, pour les puces cochables.
  List<ListeLecture> get listes => _listes;

  /// Identifiants des listes qui contiennent le titre.
  Set<int> get idsListesDuTitre => _idsListesDuTitre;

  /// Chapitres triés par numéro décroissant (le plus récent en haut).
  List<Chapitre> get chapitres => _chapitres;

  /// `true` pendant le chargement initial.
  bool get estEnChargement => _estEnChargement;

  /// `true` pendant la relecture du site.
  bool get estEnActualisation => _estEnActualisation;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` si les données viennent de MangaDex, qui doit être crédité
  /// (PLAYBOOK.md section 6, règles d'usage).
  bool get estMangaDex => _source?.typeSource == TypeSource.mangaDex;

  /// Nombre de chapitres non lus.
  int get nombreNonLus =>
      _chapitres.where((chapitre) => !chapitre.estLu).length;

  /// `true` si les téléchargements sont disponibles (service branché).
  bool get gereTelechargements => _serviceTelechargement != null;

  /// Chapitres regroupés par numéro (une ligne par numéro, la version
  /// téléchargée par le service en premier), du plus récent au plus ancien.
  List<GroupeChapitres> get groupes => _groupes;

  /// Nombre de numéros distincts.
  int get nombreNumeros => _groupes.length;

  /// Nombre de numéros dont aucune version n'est lue.
  int get nombreNumerosNonLus =>
      _groupes.where((groupe) => !groupe.estLu).length;

  /// Nom du site où se lit [chapitre] s'il est externe (« Lire sur … »),
  /// ou `null` pour un chapitre hébergé par le site source.
  String? nomSiteExterneDe(Chapitre chapitre) => chapitre.estExterne
      ? ServiceBibliotheque.nomSiteExterne(chapitre.urlExterne!)
      : null;

  // ------------------------------------------- Sites du titre (étape 8)

  /// Sites du titre, le principal d'abord (section « Sites » de la fiche).
  List<SiteDuTitre> get sites => _sites;

  /// Sites qui fournissent des chapitres : les sites lus, et les liens seuls
  /// qui gardent des chapitres lus d'avant leur passage en lien seul (filtre
  /// des chapitres par site).
  List<SiteDuTitre> get sitesAvecChapitres => <SiteDuTitre>[
    for (final site in _sites)
      if (!site.estLienSeul || site.nombreChapitres > 0) site,
  ];

  /// `true` si les chapitres du titre viennent de plus d'un site : chaque
  /// chapitre affiche alors le nom de son site, et le filtre par site
  /// apparaît. Un lien seul sans chapitre ne compte pas (tâche T4).
  bool get aPlusieursSites => sitesAvecChapitres.length > 1;

  /// Site choisi dans le filtre des chapitres, `null` = tous les sites.
  int? get idSiteFiltre => _idSiteFiltre;

  /// `true` pendant l'ajout, le retrait ou le changement de site principal.
  bool get estEnModificationSites => _estEnModificationSites;

  /// Noms des sites qui n'ont pas répondu à la dernière actualisation (vide
  /// si tous ont répondu).
  List<String> get sitesSansReponse => _sitesSansReponse;

  /// Identifiant du site d'où vient [chapitre] : un chapitre sans site connu
  /// (enregistré avant l'étape 8) vient du site principal.
  int? idSiteDe(Chapitre chapitre) => chapitre.idSource ?? _titre?.idSource;

  /// Nom du site d'où vient [chapitre], ou `null` s'il est inconnu.
  String? nomSiteDe(Chapitre chapitre) {
    final idSource = idSiteDe(chapitre);
    for (final site in _sites) {
      if (site.idSource == idSource) return site.nomSite;
    }
    return null;
  }

  /// Nombre de chapitres du site [idSource] que le retrait de ce site
  /// supprime.
  ///
  /// Même filtre que `supprimerChapitresNonConservesSource` (couche
  /// données) : sont épargnés les chapitres lus, téléchargés (marqueur ou
  /// archive enregistrée), gardés et ceux dont le téléchargement est en
  /// cours. Le site est lu sur `idSource` seul (pas de repli sur le site
  /// principal, comme la requête) : l'annonce n'est jamais supérieure à la
  /// réalité.
  int nombreChapitresRetiresAvecSite(int idSource) => _chapitres
      .where(
        (chapitre) =>
            chapitre.idSource == idSource &&
            !chapitre.estLu &&
            !chapitre.estTelecharge &&
            chapitre.nomArchive == null &&
            !chapitre.estGarde &&
            !_estEnTelechargement(chapitre),
      )
      .length;

  /// `true` si le téléchargement de [chapitre] est en cours dans la file
  /// connue de la fiche.
  bool _estEnTelechargement(Chapitre chapitre) {
    final id = chapitre.id;
    return id != null &&
        _telechargements[id]?.statut == StatutTelechargement.enCours;
  }

  /// Nombre de chapitres téléchargés du site [idSource] : leur archive sera
  /// supprimée 24 heures après le retrait de ce site (sauf si le client la
  /// garde).
  int nombreTelechargesDuSite(int idSource) => _chapitres
      .where(
        (chapitre) => idSiteDe(chapitre) == idSource && chapitre.estTelecharge,
      )
      .length;

  /// Filtre la liste des chapitres sur le site [idSource] (`null` = tous les
  /// sites). Local : aucune lecture de la base.
  void filtrerParSite(int? idSource) {
    if (_idSiteFiltre == idSource) return;
    _idSiteFiltre = idSource;
    _regrouper();
    notifier();
  }

  /// Ajoute un autre site au titre : [url] est l'adresse du même titre sur
  /// ce site. Renvoie le nombre de chapitres trouvés sur ce site.
  ///
  /// Les règles de téléchargement sont ensuite appliquées (une version
  /// hébergée peut remplacer une version « lecture sur le site »), puis la
  /// fiche est relue.
  Future<ResultatAction<int>> ajouterSite(String url) async {
    if (url.trim().isEmpty) {
      return const ResultatAction<int>.echec(
        DescriptionErreur(NatureErreur.adresseVide),
      );
    }
    return _modifierSites(() async {
      final resultat = await _service.ajouterSiteAuTitre(idTitre, url.trim());
      return resultat.nombreNouveauxChapitres;
    });
  }

  /// `true` si l'échec [erreur] d'un ajout de site permet de proposer
  /// « Ajouter quand même comme simple lien » (tâche T4) : site illisible,
  /// injoignable ou non configuré, mais adresse valide et pas déjà liée.
  static bool peutAjouterCommeLienSeul(DescriptionErreur erreur) {
    final cause = erreur.cause;
    return cause != null && ServiceBibliotheque.peutAjouterCommeLienSeul(cause);
  }

  /// Enregistre [url] comme **lien seul** du titre (tâche T4) : aucune
  /// requête au site, aucun chapitre lu ; le client l'ouvre dans son
  /// navigateur.
  Future<ResultatAction<int>> ajouterLienSeul(String url) async {
    if (url.trim().isEmpty) {
      return const ResultatAction<int>.echec(
        DescriptionErreur(NatureErreur.adresseVide),
      );
    }
    return _modifierSites(() async {
      final resultat = await _service.ajouterSiteAuTitre(
        idTitre,
        url.trim(),
        lienSeul: true,
      );
      return resultat.nombreNouveauxChapitres;
    });
  }

  /// Passe le site secondaire [idSource] en lien seul ; renvoie le nombre
  /// de chapitres supprimés (non lus, non téléchargés). Ses archives passent
  /// en suppression prévue (24 h), comme pour un retrait.
  Future<ResultatAction<int>> passerEnLienSeul(int idSource) =>
      _modifierSites(() => _service.marquerLienSeul(idTitre, idSource, true));

  /// Essaie de lire le lien seul [idSource] : il redevient un site lu, puis
  /// **ce site seulement** est relu (une requête, pas tout le titre).
  /// Renvoie le nombre de chapitres trouvés.
  ///
  /// Si le site reste illisible, il repasse en lien seul (le client n'a pas
  /// à le faire lui-même) et l'erreur de lecture est renvoyée.
  Future<ResultatAction<int>> essayerDeLire(int idSource) => _modifierSites(
    () async {
      await _service.marquerLienSeul(idTitre, idSource, false);
      try {
        final titre = await _service.chargerTitre(idTitre);
        if (titre == null) throw const _TitreIntrouvable();
        final resultat = await _service.actualiserSiteDuTitre(titre, idSource);
        return resultat.nombreNouveauxChapitres;
      } catch (erreur) {
        try {
          await _service.marquerLienSeul(idTitre, idSource, true);
        } catch (erreurRetour, pile) {
          // Le site reste « lu » : la prochaine actualisation signalera
          // qu'il ne répond pas, et le client pourra le repasser en lien
          // seul lui-même.
          debugPrint('Retour en lien seul impossible : $erreurRetour\n$pile');
        }
        rethrow;
      }
    },
  );

  /// Diagnostic de lisibilité de [url] (tâche T3, « Pourquoi ce site n'est
  /// pas lisible ? ») : une requête au plus, faite par le service.
  Future<ResultatAction<DiagnosticLisibilite>> diagnostiquerSite(
    String url,
  ) async {
    try {
      return ResultatAction<DiagnosticLisibilite>.reussite(
        await _service.diagnostiquerSite(url.trim()),
      );
    } catch (erreur, pile) {
      return ResultatAction<DiagnosticLisibilite>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
  }

  /// Retire le site secondaire [idSource] ; renvoie le nombre de chapitres
  /// supprimés. Les archives de ce site passent en suppression prévue (24 h).
  Future<ResultatAction<int>> retirerSite(int idSource) =>
      _modifierSites(() => _service.retirerSiteDuTitre(idTitre, idSource));

  /// Fait du site [idSource] le site principal (fiche, couverture, résumé
  /// relus sur ce site).
  Future<ResultatAction<int>> definirSitePrincipal(int idSource) =>
      _modifierSites(() async {
        final resultat = await _service.definirSitePrincipal(idTitre, idSource);
        return resultat.nombreNouveauxChapitres;
      });

  /// Déroulement commun aux actions sur les sites : action du service,
  /// règles de téléchargement du titre, puis relecture de la fiche (sites,
  /// chapitres, file et suppressions prévues à jour d'un coup).
  Future<ResultatAction<int>> _modifierSites(
    Future<int> Function() action,
  ) async {
    _estEnModificationSites = true;
    notifier();
    try {
      final nombre = await action();
      final service = _serviceTelechargement;
      if (service != null) {
        try {
          await service.appliquerRegles(idTitre);
        } catch (erreur, pile) {
          // L'action du client est faite ; les règles seront réappliquées
          // plus tard (démarrage, mises à jour).
          debugPrint(
            'Règles de téléchargement non appliquées : $erreur\n$pile',
          );
        }
      }
      final numero = ++_numeroLecture;
      final donnees = await _lireBase();
      if (numero == _numeroLecture) _appliquer(donnees);
      return ResultatAction<int>.reussite(nombre);
    } on _TitreIntrouvable {
      _signalerIntrouvable();
      return const ResultatAction<int>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    } catch (erreur, pile) {
      return ResultatAction<int>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnModificationSites = false;
      notifier();
    }
  }

  /// État hors-ligne d'un chapitre (téléchargé, en file, en cours…).
  EtatHorsLigne etatHorsLigne(Chapitre chapitre) {
    final id = chapitre.id;
    return EtatHorsLigne.depuis(
      chapitre,
      id == null ? null : _telechargements[id],
      estDoublon: estDoublon(chapitre),
    );
  }

  /// Numéro de la dernière lecture de la base : une réponse plus ancienne
  /// (chargement relancé, actualisation terminée entre-temps) est ignorée.
  int _numeroLecture = 0;

  /// Charge la fiche complète depuis la base.
  Future<void> charger() async {
    final numero = ++_numeroLecture;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final donnees = await _lireBase();
      if (numero != _numeroLecture) {
        return;
      }
      _appliquer(donnees);
    } on _TitreIntrouvable {
      if (numero != _numeroLecture) {
        return;
      }
      _signalerIntrouvable();
    } catch (erreur, pile) {
      if (numero != _numeroLecture) {
        return;
      }
      _erreur = DescriptionErreur.depuis(erreur, pile);
    }
    _estEnChargement = false;
    notifier();
  }

  /// Relit la fiche et les chapitres sur le site, et renvoie le nombre de
  /// nouveaux chapitres.
  Future<ResultatAction<int>> actualiser() async {
    final titre = _titre;
    if (titre == null) {
      return const ResultatAction<int>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    _estEnActualisation = true;
    _sitesSansReponse = const <String>[];
    notifier();
    try {
      final resultat = await _service.actualiserTitre(titre);
      // Étape 8 : un site en panne n'empêche pas les autres ; l'écran dit
      // lesquels n'ont pas répondu.
      _sitesSansReponse = <String>[
        for (final idSource in resultat.erreursParSite.keys)
          ?_sites
              .where((site) => site.idSource == idSource)
              .firstOrNull
              ?.nomSite,
      ];
      // Nouvelle génération : un chargement plus ancien encore en cours ne
      // doit pas écraser les données relues après l'actualisation.
      final numero = ++_numeroLecture;
      final donnees = await _lireBase();
      if (numero == _numeroLecture) {
        _appliquer(donnees);
      }
      // E11 : les nouveaux chapitres d'un titre favori ou suivi entrent dans
      // la file tout de suite, sans attendre la prochaine recherche de mises
      // à jour (erreur journalisée par `_appliquerRegles`).
      if (resultat.nombreNouveauxChapitres > 0) {
        await _appliquerRegles();
      }
      return ResultatAction<int>.reussite(resultat.nombreNouveauxChapitres);
    } on _TitreIntrouvable {
      // Sans erreur définie, l'écran attendrait un titre qui ne viendra
      // jamais (chargement infini).
      _signalerIntrouvable();
      return const ResultatAction<int>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    } catch (erreur, pile) {
      return ResultatAction<int>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnActualisation = false;
      notifier();
    }
  }

  /// Marque [chapitre] lu (ou non lu si [estLu] vaut `false`).
  Future<ResultatAction<bool>> marquerLu(
    Chapitre chapitre, {
    bool estLu = true,
  }) async {
    final idChapitre = chapitre.id;
    if (idChapitre == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await _service.marquerLu(idChapitre, estLu: estLu);
      // Mise à jour locale plutôt qu'un rechargement complet : la liste ne
      // saute pas et l'action reste instantanée sur un long titre.
      _chapitres = <Chapitre>[
        for (final existant in _chapitres)
          existant.id == idChapitre
              ? existant.copierAvec(estLu: estLu)
              : existant,
      ];
      _mettreAJourNonLus();
      _regrouper();
      notifier();
      // La lecture fait avancer la fenêtre des titres suivis (et change les
      // lus gardés des favoris) : le service met la file à jour.
      await _appliquerRegles();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Marque toutes les versions du [groupe] lues (ou non lues) : pour le
  /// client, un numéro est lu ou ne l'est pas, quelle que soit la langue.
  Future<ResultatAction<bool>> marquerGroupeLu(
    GroupeChapitres groupe, {
    bool estLu = true,
  }) async {
    try {
      final ids = <int>{
        for (final chapitre in groupe.versions)
          if (chapitre.id != null && chapitre.estLu != estLu) chapitre.id!,
      };
      for (final id in ids) {
        await _service.marquerLu(id, estLu: estLu);
      }
      _chapitres = <Chapitre>[
        for (final existant in _chapitres)
          ids.contains(existant.id)
              ? existant.copierAvec(estLu: estLu)
              : existant,
      ];
      _mettreAJourNonLus();
      _regrouper();
      notifier();
      await _appliquerRegles();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Marque tous les chapitres lus (ou non lus si [estLu] vaut `false`).
  Future<ResultatAction<bool>> marquerTousLus({bool estLu = true}) async {
    try {
      await _service.marquerTousLus(idTitre, estLu: estLu);
      _chapitres = <Chapitre>[
        for (final existant in _chapitres) existant.copierAvec(estLu: estLu),
      ];
      _mettreAJourNonLus();
      _regrouper();
      notifier();
      await _appliquerRegles();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Ajoute le titre à la liste [idListe].
  Future<ResultatAction<bool>> ajouterALaListe(int idListe) async {
    try {
      await _service.ajouterTitreALaListe(idListe, idTitre);
      _idsListesDuTitre = <int>{..._idsListesDuTitre, idListe};
      notifier();
      await _relireListesDuTitre();
      await _appliquerReglesSiSysteme(idListe);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Retire le titre de la liste [idListe] (le titre reste dans la
  /// bibliothèque).
  Future<ResultatAction<bool>> retirerDeLaListe(int idListe) async {
    try {
      await _service.retirerTitreDeLaListe(idListe, idTitre);
      _idsListesDuTitre = <int>{
        for (final id in _idsListesDuTitre)
          if (id != idListe) id,
      };
      notifier();
      await _relireListesDuTitre();
      await _appliquerReglesSiSysteme(idListe);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// `true` si [liste] est tenue automatiquement par l'application (« En
  /// attente ») : sa puce est affichée sans pouvoir être cochée.
  bool estListeAutomatique(ListeLecture liste) =>
      ClassementListes.listesAutomatiques.contains(liste.nom);

  /// Relit les listes du titre : le service a pu le placer dans « En
  /// attente » ou l'en retirer après un changement de liste.
  Future<void> _relireListesDuTitre() async {
    try {
      final listes = await _service.chargerListesDuTitre(idTitre);
      _idsListesDuTitre = <int>{
        for (final liste in listes)
          if (liste.id != null) liste.id!,
      };
      notifier();
    } catch (erreur, pile) {
      // L'action du client est faite ; seule la puce « En attente » peut
      // rester en retard jusqu'au prochain chargement.
      debugPrint('Listes du titre illisibles : $erreur\n$pile');
    }
  }

  // ------------------------------------------------------------ Couvertures

  /// `true` si le client a choisi une couverture (du site ou de l'appareil)
  /// à la place de celle fournie par le site.
  bool get aCouvertureChoisie => _titre?.couvertureChoisie != null;

  /// Couvertures proposées par le site (MangaDex : une par volume) ; liste
  /// vide si le site n'en propose qu'une. Lecture réseau.
  Future<ResultatAction<List<CouvertureProposee>>>
  recupererCouverturesDuSite() async {
    final titre = _titre;
    if (titre == null) {
      return const ResultatAction<List<CouvertureProposee>>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      final couvertures = await _service.recupererCouverturesDuSite(titre);
      return ResultatAction<List<CouvertureProposee>>.reussite(
        <CouvertureProposee>[
          for (final couverture in couvertures)
            CouvertureProposee(
              url: couverture.url,
              urlMiniature: couverture.urlMiniature,
              volume: couverture.volume,
              langue: couverture.langue,
            ),
        ],
      );
    } catch (erreur, pile) {
      return ResultatAction<List<CouvertureProposee>>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
  }

  /// Retient la couverture du site à [url] (téléchargée et enregistrée sur
  /// l'appareil).
  Future<ResultatAction<bool>> choisirCouverture(String url) =>
      _changerCouverture(() => _service.choisirCouverture(idTitre, url));

  /// Retient l'image de l'appareil à [chemin] comme couverture (une copie
  /// est gardée avec le titre).
  Future<ResultatAction<bool>> choisirCouvertureLocale(String chemin) =>
      _changerCouverture(
        () => _service.choisirCouvertureLocale(idTitre, chemin),
      );

  /// Revient à la couverture fournie par le site.
  Future<ResultatAction<bool>> retablirCouvertureDuSite() =>
      _changerCouverture(() => _service.retablirCouvertureDuSite(idTitre));

  bool _estEnChangementCouverture = false;

  /// `true` pendant le téléchargement ou l'enregistrement d'une couverture.
  bool get estEnChangementCouverture => _estEnChangementCouverture;

  Future<ResultatAction<bool>> _changerCouverture(
    Future<Titre> Function() action,
  ) async {
    _estEnChangementCouverture = true;
    notifier();
    try {
      final titre = await action();
      // Le nombre de non-lus n'est pas relu par le service : on garde le
      // compte local.
      _titre = titre.copierAvec(nombreChapitresNonLus: nombreNonLus);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    } finally {
      _estEnChangementCouverture = false;
      notifier();
    }
  }

  // ------------------------------------------------------- Téléchargements

  /// Ajoute [chapitre] à la file de téléchargement (ou relance un échec).
  ///
  /// Refusé pour un chapitre externe (jamais téléchargé).
  Future<ResultatAction<bool>> telecharger(Chapitre chapitre) async {
    final service = _serviceTelechargement;
    final id = chapitre.id;
    if (service == null || id == null || chapitre.estExterne) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await service.telechargerChapitre(id);
      await _relireTelechargements();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Supprime l'archive de [chapitre] (ou le retire de la file).
  ///
  /// LIMITE : pour un titre favori ou suivi, les règles automatiques peuvent
  /// le télécharger de nouveau plus tard s'il fait encore partie des
  /// chapitres voulus.
  Future<ResultatAction<bool>> supprimerTelechargement(
    Chapitre chapitre,
  ) async {
    final service = _serviceTelechargement;
    final id = chapitre.id;
    if (service == null || id == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await service.supprimerTelechargement(id);
      await _relireTelechargements(relireChapitres: true);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Bouton « Garder » d'une suppression prévue : l'archive de [chapitre]
  /// n'est plus jamais supprimée automatiquement (le client peut toujours
  /// la supprimer lui-même).
  Future<ResultatAction<bool>> garder(Chapitre chapitre) => _agirSurArchive(
    chapitre,
    (service, id) => service.annulerSuppression(id),
  );

  /// « Ne plus garder » : [chapitre] suit de nouveau les règles (sa
  /// suppression peut être prévue dans 24 heures s'il n'est plus voulu).
  Future<ResultatAction<bool>> nePlusGarder(Chapitre chapitre) =>
      _agirSurArchive(chapitre, (service, id) => service.retirerGarde(id));

  /// Bouton « Supprimer maintenant » d'une suppression prévue (ou choix
  /// d'un doublon à retirer) : l'archive est effacée tout de suite.
  Future<ResultatAction<bool>> supprimerMaintenant(Chapitre chapitre) =>
      _agirSurArchive(
        chapitre,
        (service, id) => service.supprimerMaintenant(id),
      );

  Future<ResultatAction<bool>> _agirSurArchive(
    Chapitre chapitre,
    Future<void> Function(ServiceTelechargement service, int idChapitre) action,
  ) async {
    final service = _serviceTelechargement;
    final id = chapitre.id;
    if (service == null || id == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await action(service, id);
      await _relireTelechargements(relireChapitres: true);
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Change les langues de ce titre : [langues] par ordre de préférence (la
  /// première est la favorite), ou `null` pour revenir au réglage général.
  ///
  /// Les règles de téléchargement sont réappliquées (une archive dans une
  /// langue retirée passe en suppression prévue dans 24 heures). Si une
  /// langue est ajoutée, le site est relu pour connaître les chapitres dans
  /// cette langue, puis les règles sont réappliquées.
  ///
  /// Renvoie le nombre de nouveaux chapitres trouvés, ou une réussite sans
  /// valeur (`null`) si les langues sont enregistrées mais que le site n'a
  /// pas pu être relu (la prochaine actualisation le fera).
  Future<ResultatAction<int?>> modifierLangues(List<String>? langues) async {
    final anciennes = _langues.toSet();
    try {
      final service = _serviceTelechargement;
      if (service != null) {
        // Enregistre et applique les règles de ce titre.
        await service.modifierLanguesTitre(idTitre, langues);
      } else {
        await _service.modifierLanguesTitre(idTitre, langues);
      }
      final numero = ++_numeroLecture;
      final donnees = await _lireBase();
      if (numero == _numeroLecture) _appliquer(donnees);
      notifier();
    } on _TitreIntrouvable {
      _signalerIntrouvable();
      notifier();
      return const ResultatAction<int?>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    } catch (erreur, pile) {
      return ResultatAction<int?>.echec(DescriptionErreur.depuis(erreur, pile));
    }
    final ajoutees = _langues.where((langue) => !anciennes.contains(langue));
    if (ajoutees.isEmpty) {
      return const ResultatAction<int?>.reussite(0);
    }
    // Une langue ajoutée : ses chapitres ne sont connus qu'après une
    // relecture du site (le service ne demande au site que les langues
    // utiles). Les langues restent enregistrées même si le site ne répond
    // pas.
    final resultat = await actualiser();
    if (!resultat.estReussi) {
      return const ResultatAction<int?>.reussite(null);
    }
    // `actualiser` applique déjà les règles quand il trouve des chapitres :
    // inutile de relancer le calcul une seconde fois.
    if ((resultat.donnee ?? 0) == 0) {
      await _appliquerRegles();
    }
    return ResultatAction<int?>.reussite(resultat.donnee);
  }

  /// Crée l'état du lecteur ouvert sur [chapitre], ou `null` si les
  /// téléchargements ne sont pas disponibles.
  ///
  /// Toujours `null` pour un chapitre externe : il ne se lit que sur le site
  /// de l'éditeur (PLAYBOOK.md section 10).
  EtatLecteur? creerEtatLecteur(Chapitre chapitre) {
    final service = _serviceTelechargement;
    final id = chapitre.id;
    if (service == null || id == null || chapitre.estExterne) return null;
    return EtatLecteur(
      serviceBibliotheque: _service,
      serviceTelechargement: service,
      idTitre: idTitre,
      idChapitre: id,
    );
  }

  /// Applique les règles de conservation si [idListe] est Favoris ou Suivis
  /// (les seules listes qui déclenchent des téléchargements).
  Future<void> _appliquerReglesSiSysteme(int idListe) async {
    final liste = _listes.where((liste) => liste.id == idListe).firstOrNull;
    if (liste == null ||
        liste.nom == nomListeFavoris ||
        liste.nom == nomListeSuivis) {
      await _appliquerRegles();
    }
  }

  /// Demande au service d'appliquer les règles de conservation à ce titre.
  ///
  /// Une erreur ici n'annule pas l'action du client (déjà enregistrée) : elle
  /// est seulement journalisée, les règles seront réappliquées plus tard.
  Future<void> _appliquerRegles() async {
    final service = _serviceTelechargement;
    if (service == null) return;
    try {
      await service.appliquerRegles(idTitre);
    } catch (erreur, pile) {
      debugPrint('Règles de téléchargement non appliquées : $erreur\n$pile');
    }
    await _relireTelechargements(relireChapitres: true);
  }

  /// Relecture de la file en cours, nouvelle relecture demandée pendant
  /// celle-ci, et relecture des chapitres demandée par l'une des demandes
  /// regroupées.
  Future<void>? _relecture;
  bool _relectureRedemandee = false;
  bool _relireChapitresDemande = false;

  /// Relit la file pour les chapitres de ce titre ; relit aussi les
  /// chapitres si un téléchargement s'est terminé ou a été retiré (le
  /// marqueur « téléchargé » a changé en base).
  ///
  /// Pendant un téléchargement, le service prévient à chaque page : les
  /// demandes qui arrivent pendant une relecture sont regroupées en une
  /// seule relecture à la fin (comme dans `EtatTelechargements`).
  Future<void> _relireTelechargements({bool relireChapitres = false}) {
    if (_serviceTelechargement == null || estLibere) {
      return Future<void>.value();
    }
    if (relireChapitres) _relireChapitresDemande = true;
    final enCours = _relecture;
    if (enCours != null) {
      _relectureRedemandee = true;
      return enCours;
    }
    final nouvelle = _relireEnBoucle().whenComplete(() => _relecture = null);
    _relecture = nouvelle;
    return nouvelle;
  }

  Future<void> _relireEnBoucle() async {
    final service = _serviceTelechargement!;
    do {
      _relectureRedemandee = false;
      final relireChapitres = _relireChapitresDemande;
      _relireChapitresDemande = false;
      if (estLibere) return;
      // Un chargement ou une actualisation lancé pendant la relecture lit
      // déjà la base : sa réponse est plus récente que la nôtre.
      final numero = _numeroLecture;
      try {
        final idsChapitres = <int>{
          for (final chapitre in _chapitres)
            if (chapitre.id != null) chapitre.id!,
        };
        final file = await service.chargerFile();
        if (numero != _numeroLecture) continue;
        final nouveaux = <int, Telechargement>{
          for (final telechargement in file)
            if (idsChapitres.contains(telechargement.idChapitre))
              telechargement.idChapitre: telechargement,
        };
        final anciens = _telechargements;
        final statutsChanges =
            anciens.length != nouveaux.length ||
            nouveaux.entries.any(
              (entree) => anciens[entree.key]?.statut != entree.value.statut,
            );
        // Les chapitres sont aussi relus quand la file n'est pas en cours de
        // traitement : le changement signalé vient alors d'une suppression
        // prévue posée ou annulée, d'un doublon supprimé… (pendant un
        // téléchargement, le service prévient à chaque page : on ne relit
        // les chapitres qu'à un changement de statut).
        if ((relireChapitres || statutsChanges || !service.estEnCours) &&
            _titre != null) {
          final chapitres = await _service.chargerChapitres(idTitre);
          final doublons = await service.chargerDoublons(idTitre);
          if (numero != _numeroLecture) continue;
          _chapitres = _trier(chapitres);
          _idsDoublons = _idsDepuisDoublons(doublons);
          _mettreAJourNonLus();
          _regrouper();
        }
        _telechargements = nouveaux;
        notifier();
      } catch (erreur, pile) {
        // Un échec de lecture de la file ne doit pas masquer la fiche.
        debugPrint('File de téléchargement illisible : $erreur\n$pile');
      }
    } while (_relectureRedemandee);
  }

  /// Lit toutes les données du titre sans modifier l'état ; lève une erreur
  /// en cas d'échec. L'appelant décide d'appliquer ou non le résultat.
  Future<_DonneesTitre> _lireBase() async {
    final titre = await _service.chargerTitre(idTitre);
    if (titre == null) {
      throw const _TitreIntrouvable();
    }
    final idSource = titre.idSource;
    final source = idSource == null
        ? null
        : await _service.chargerSource(idSource);
    final categories = await _service.chargerCategoriesDuTitre(idTitre);
    final listes = await _service.chargerListes();
    final listesDuTitre = await _service.chargerListesDuTitre(idTitre);
    final chapitres = await _service.chargerChapitres(idTitre);
    final tries = _trier(chapitres);
    final service = _serviceTelechargement;
    final idsChapitres = <int>{
      for (final chapitre in tries)
        if (chapitre.id != null) chapitre.id!,
    };
    final telechargements = service == null
        ? const <int, Telechargement>{}
        : <int, Telechargement>{
            for (final telechargement in await service.chargerFile())
              if (idsChapitres.contains(telechargement.idChapitre))
                telechargement.idChapitre: telechargement,
          };
    final doublons = service == null
        ? const <List<Chapitre>>[]
        : await service.chargerDoublons(idTitre);

    final sites = await _service.chargerSitesDuTitre(idTitre);

    return (
      titre: titre,
      source: source,
      sites: sites,
      categories: categories,
      listes: listes,
      idsListesDuTitre: <int>{
        for (final liste in listesDuTitre)
          if (liste.id != null) liste.id!,
      },
      chapitres: tries,
      telechargements: telechargements,
      langues: await _service.languesPourTitre(titre),
      languesGenerales: await _service.chargerLanguesGenerales(),
      idsDoublons: _idsDepuisDoublons(doublons),
    );
  }

  static Set<int> _idsDepuisDoublons(List<List<Chapitre>> doublons) => <int>{
    for (final groupe in doublons)
      for (final chapitre in groupe)
        if (chapitre.id != null) chapitre.id!,
  };

  /// Le dépôt trie par numéro croissant ; la fiche montre le plus récent en
  /// haut. À numéro égal (plusieurs langues), le plus récemment enregistré
  /// passe d'abord.
  static List<Chapitre> _trier(List<Chapitre> chapitres) {
    return List<Chapitre>.of(chapitres)..sort((a, b) {
      final parNumero = b.numero.compareTo(a.numero);
      return parNumero != 0 ? parNumero : (b.id ?? 0).compareTo(a.id ?? 0);
    });
  }

  void _appliquer(_DonneesTitre donnees) {
    _titre = donnees.titre;
    _source = donnees.source;
    _sites = donnees.sites;
    // Un site retiré entre-temps ne peut plus servir de filtre.
    if (_idSiteFiltre != null &&
        !_sites.any((site) => site.idSource == _idSiteFiltre)) {
      _idSiteFiltre = null;
    }
    _categories = donnees.categories;
    _listes = donnees.listes;
    _idsListesDuTitre = donnees.idsListesDuTitre;
    _chapitres = donnees.chapitres;
    _telechargements = donnees.telechargements;
    _langues = donnees.langues;
    _languesGenerales = donnees.languesGenerales;
    _idsDoublons = donnees.idsDoublons;
    _regrouper();
  }

  /// Une ligne par numéro (chaque oneshot à part), la plus récente en haut.
  ///
  /// Avec un filtre de site, seuls les chapitres de ce site sont regroupés.
  /// La politique reçoit le site principal et les sites liés, comme dans
  /// `ServiceTelechargement` : la version mise en avant est celle qu'il
  /// télécharge.
  void _regrouper() {
    final filtre = _idSiteFiltre;
    final chapitres = filtre == null
        ? _chapitres
        : _chapitres.where((chapitre) => idSiteDe(chapitre) == filtre).toList();
    final idPrincipal = _titre?.idSource;
    _groupes = regrouperParNumero(
      chapitres,
      _langues,
      idSourcePrincipale: idPrincipal,
      idsSourcesLiees: _sites.isEmpty
          ? null
          : <int>{?idPrincipal, for (final site in _sites) site.idSource},
    ).reversed.toList();
    _mettreAJourCompteARebours();
  }

  /// Lance (ou arrête) le rafraîchissement du compte à rebours selon qu'un
  /// chapitre a une suppression prévue.
  void _mettreAJourCompteARebours() {
    if (estLibere) return;
    if (nombreSuppressionsPrevues == 0) {
      _minuterieCompteARebours?.cancel();
      _minuterieCompteARebours = null;
    } else {
      _minuterieCompteARebours ??= Timer.periodic(
        intervalleCompteARebours,
        (_) => notifier(),
      );
    }
  }

  @override
  void dispose() {
    _minuterieCompteARebours?.cancel();
    _minuterieCompteARebours = null;
    unawaited(_abonnement?.cancel());
    super.dispose();
  }

  void _signalerIntrouvable() {
    _titre = null;
    _erreur = const DescriptionErreur(NatureErreur.introuvable);
  }

  void _mettreAJourNonLus() {
    final titre = _titre;
    if (titre != null) {
      _titre = titre.copierAvec(nombreChapitresNonLus: nombreNonLus);
    }
  }
}

/// Données d'un titre lues en une fois dans la base.
typedef _DonneesTitre = ({
  Titre titre,
  Source? source,
  List<SiteDuTitre> sites,
  List<Categorie> categories,
  List<ListeLecture> listes,
  Set<int> idsListesDuTitre,
  List<Chapitre> chapitres,
  Map<int, Telechargement> telechargements,
  List<String> langues,
  List<String> languesGenerales,
  Set<int> idsDoublons,
});

/// Signal interne : le titre n'existe plus en base.
class _TitreIntrouvable implements Exception {
  const _TitreIntrouvable();
}
