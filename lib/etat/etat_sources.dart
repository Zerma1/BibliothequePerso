/// État de l'écran Sources : sites configurés et ajout d'un site.
library;

import '../modeles/erreur_base_de_donnees.dart';
import '../modeles/journal.dart';
import '../modeles/source.dart';
import '../services/erreur_service.dart';
import '../services/service_ajout_site.dart';
import '../services/service_bibliotheque.dart';

// Type du diagnostic rendu à l'écran d'ajout de site, sans que l'interface
// importe les services.
export '../services/service_bibliotheque.dart' show DiagnosticLisibilite;
import '../services/service_parametres.dart';
import '../services/service_telechargement.dart';
import 'description_erreur.dart';

/// Site obtenu après une demande d'ajout.
class SiteAjoute {
  /// Crée le résultat.
  const SiteAjoute(this.source, {required this.etaitDejaConfigure});

  /// Source enregistrée (ou déjà présente).
  final Source source;

  /// `true` si le site existait déjà : le service renvoie alors la source
  /// existante sans rien modifier.
  final bool etaitDejaConfigure;
}

/// Liste des sites configurés, ajout d'un site par URL, modification et
/// suppression.
class EtatSources extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire la base.
  ///
  /// [serviceTelechargement] sert à réappliquer les règles de téléchargement
  /// quand les langues d'un site changent.
  EtatSources(
    this._serviceBibliotheque,
    this._serviceAjoutSite, {
    this._serviceTelechargement,
  });

  final ServiceBibliotheque _serviceBibliotheque;
  final ServiceAjoutSite _serviceAjoutSite;
  final ServiceTelechargement? _serviceTelechargement;

  List<Source> _sources = const <Source>[];
  bool _estEnChargement = false;
  bool _estCharge = false;
  bool _estEnAjout = false;
  DescriptionErreur? _erreur;

  /// Sites configurés.
  List<Source> get sources => _sources;

  /// `true` pendant un chargement.
  bool get estEnChargement => _estEnChargement;

  /// `true` une fois qu'un chargement a abouti.
  bool get estCharge => _estCharge;

  /// `true` pendant l'ajout d'un site (détection en cours).
  bool get estEnAjout => _estEnAjout;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` si le chargement a abouti sans aucun site.
  bool get estVide => _estCharge && _erreur == null && _sources.isEmpty;

  /// Numéro du dernier chargement lancé : une réponse plus ancienne est
  /// ignorée.
  int _numeroChargement = 0;

  /// Charge les sites configurés.
  Future<void> charger() async {
    final numero = ++_numeroChargement;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final sources = await _serviceBibliotheque.chargerSources();
      if (numero != _numeroChargement) {
        return;
      }
      _sources = sources;
      _estCharge = true;
    } catch (erreur, pile) {
      if (numero != _numeroChargement) {
        return;
      }
      _erreur = DescriptionErreur.depuis(erreur, pile);
    }
    _estEnChargement = false;
    notifier();
  }

  /// `true` si [saisie] est vide ou une liste de codes de langue séparés par
  /// des virgules (« fr », « fr,en », variantes régionales comme « pt-br »),
  /// selon la même règle que le service des réglages.
  static bool languesValides(String saisie) {
    final codes = saisie
        .split(',')
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toList();
    return codes.every(
      (code) => ServiceParametres.nettoyerLangues(<String>[code]).isNotEmpty,
    );
  }

  /// Nom proposé pour le site à [url] (hôte sans `www.`), ou une chaîne vide
  /// si l'adresse n'est pas encore exploitable.
  String proposerNom(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) {
      return '';
    }
    return ServiceAjoutSite.proposerNom(uri);
  }

  /// Clés des réglages avancés d'un site générique (sélecteurs CSS), dans
  /// l'ordre du formulaire (`ServiceAjoutSite.clesReglagesGeneriques`).
  static List<String> get clesReglagesGeneriques =>
      ServiceAjoutSite.clesReglagesGeneriques;

  /// Libellé français du réglage avancé [cle] (fourni par le service).
  static String libelleReglageGenerique(String cle) =>
      ServiceAjoutSite.libelleReglageGenerique(cle);

  /// Réglages avancés enregistrés d'un site ([json] de
  /// `Source.configurationSelecteurs`), par clé, pour préremplir un
  /// formulaire ; vide s'il n'y en a pas ou s'ils sont illisibles.
  static Map<String, String> reglagesGeneriquesDepuisJson(String? json) =>
      ServiceAjoutSite.reglagesGeneriquesDepuisJson(json);

  /// Motif court (sans le libellé du champ, déjà affiché au-dessus) du refus
  /// du réglage [cle] valant [valeur], ou `null` s'il est vide ou valide.
  /// Vérifié par le service (même parseur que la lecture du site).
  static String? erreurReglageGenerique(String cle, String valeur) =>
      ServiceAjoutSite.erreurReglageGenerique(cle, valeur);

  /// Message d'erreur (qui nomme le champ fautif) des réglages avancés
  /// [reglages], ou `null` s'ils sont tous vides ou valides.
  static String? erreurReglagesGeneriques(Map<String, String> reglages) {
    try {
      ServiceAjoutSite.normaliserReglagesGeneriques(
        ServiceAjoutSite.reglagesGeneriquesVersJson(reglages),
      );
      return null;
    } on ErreurService catch (erreur) {
      return erreur.message;
    }
  }

  /// Ajoute le site désigné par [url].
  ///
  /// [nom] et [langueParDefaut] sont facultatifs ; [typeForce] remplace la
  /// détection automatique quand le client corrige le type.
  ///
  /// [reglagesGeneriques] : réglages avancés (sélecteurs CSS, par clé de
  /// [clesReglagesGeneriques]). Enregistrés dans
  /// `Source.configurationSelecteurs` seulement si le site retenu est de
  /// type générique et qu'au moins un réglage est rempli ; ils remplacent
  /// alors ceux d'un site déjà configuré. Ils sont vérifiés **avant**
  /// l'ajout : un réglage invalide est refusé (message qui nomme le champ)
  /// sans que le site soit ajouté.
  Future<ResultatAction<SiteAjoute>> ajouterSite(
    String url, {
    String? nom,
    String langueParDefaut = '',
    TypeSource? typeForce,
    Map<String, String> reglagesGeneriques = const <String, String>{},
  }) async {
    if (url.trim().isEmpty) {
      return const ResultatAction<SiteAjoute>.echec(
        DescriptionErreur(NatureErreur.adresseVide),
      );
    }
    // Réglages vérifiés avant tout ajout : un site ajouté avec des réglages
    // refusés ensuite resterait enregistré sans eux.
    final String? json;
    try {
      json = ServiceAjoutSite.normaliserReglagesGeneriques(
        ServiceAjoutSite.reglagesGeneriquesVersJson(reglagesGeneriques),
      );
    } catch (erreur, pile) {
      return ResultatAction<SiteAjoute>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
    _estEnAjout = true;
    notifier();
    try {
      var source = await _serviceAjoutSite.ajouterSite(
        url.trim(),
        nom: nom,
        langueParDefaut: langueParDefaut,
        typeForce: typeForce,
        // Une page générique est vérifiée avec les réglages que le client
        // s'apprête à enregistrer (sans eux, une page lisible grâce à ses
        // sélecteurs serait refusée).
        configurationSelecteurs: json,
      );
      if (json != null && source.typeSource == TypeSource.generique) {
        // Méthode existante de modification : elle garde le champ
        // `configurationSelecteurs` reçu.
        source = await _serviceAjoutSite.modifierSource(
          source.copierAvec(configurationSelecteurs: json),
        );
      }
      // Le service renvoie la source existante si le site est déjà connu :
      // on le signale au client plutôt que de laisser croire à un ajout.
      final dejaConnu = _sources.any((existante) => existante.id == source.id);
      _estEnAjout = false;
      await charger();
      return ResultatAction<SiteAjoute>.reussite(
        SiteAjoute(source, etaitDejaConfigure: dejaConnu),
      );
    } catch (erreur, pile) {
      _estEnAjout = false;
      notifier();
      return ResultatAction<SiteAjoute>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
  }

  /// Diagnostic de lisibilité de [url] (tâche T3, « Pourquoi ce site n'est
  /// pas lisible ? ») : une requête au plus, faite par le service.
  Future<ResultatAction<DiagnosticLisibilite>> diagnostiquerSite(
    String url,
  ) async {
    try {
      return ResultatAction<DiagnosticLisibilite>.reussite(
        await _serviceBibliotheque.diagnostiquerSite(url.trim()),
      );
    } catch (erreur, pile) {
      return ResultatAction<DiagnosticLisibilite>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
  }

  /// Motif du refus du type [type] pour le site d'adresse [urlBase], ou
  /// `null` s'il est cohérent (règle du service : les types reconnus par le
  /// domaine ne se changent pas et ne se donnent pas à un autre site).
  static String? erreurTypeSite(String urlBase, TypeSource type) =>
      ServiceAjoutSite.erreurTypeSite(urlBase, type);

  /// `true` si passer [source] au type [nouveauType] effacera ses réglages
  /// avancés (sélecteurs CSS) : seul le type générique les lit, le service
  /// les efface quand on le quitte.
  static bool changementTypeEffaceReglages(
    Source source,
    TypeSource nouveauType,
  ) =>
      source.typeSource == TypeSource.generique &&
      nouveauType != TypeSource.generique &&
      reglagesGeneriquesDepuisJson(source.configurationSelecteurs).isNotEmpty;

  /// Modifie le nom, les langues (« fr,en », par ordre de préférence),
  /// l'activation, le type et, pour un site générique, les réglages avancés
  /// d'un site.
  ///
  /// [typeSource] (tâche X5) : `null` garde le type actuel. Un type
  /// incohérent ([erreurTypeSite]) est refusé par le service sans rien
  /// écrire. Quitter le type générique efface les réglages avancés.
  ///
  /// [reglagesGeneriques] (par clé de [clesReglagesGeneriques]) : `null`
  /// laisse les réglages tels quels ; tous vides, ils sont effacés (retour
  /// aux heuristiques). Ignorés si le site (avec son nouveau type) n'est pas
  /// générique. Le service les vérifie et refuse un réglage invalide (rien
  /// n'est écrit).
  ///
  /// Si les langues changent, les règles de téléchargement sont
  /// réappliquées : la version retenue de chaque numéro peut changer.
  Future<ResultatAction<Source>> modifierSource(
    Source source, {
    required String nom,
    required String langues,
    required bool estActive,
    TypeSource? typeSource,
    Map<String, String>? reglagesGeneriques,
  }) async {
    if (nom.trim().isEmpty) {
      return const ResultatAction<Source>.echec(
        DescriptionErreur(NatureErreur.nomVide),
      );
    }
    final type = typeSource ?? source.typeSource;
    var aEnregistrer = source.copierAvec(
      nom: nom,
      langueParDefaut: langues,
      estActive: estActive,
      typeSource: type,
    );
    if (reglagesGeneriques != null && type == TypeSource.generique) {
      final json = ServiceAjoutSite.reglagesGeneriquesVersJson(
        reglagesGeneriques,
      );
      // Un site qui devient générique n'avait aucun réglage : tout réglage
      // saisi est nouveau.
      final avant = source.typeSource == TypeSource.generique
          ? ServiceAjoutSite.reglagesGeneriquesVersJson(
              reglagesGeneriquesDepuisJson(source.configurationSelecteurs),
            )
          : null;
      // Réglages inchangés : le champ enregistré est gardé tel quel (le
      // service ne revérifie pas un site enregistré avant la vérification).
      // Tout vidé : JSON vide, que le service traduit en effacement
      // (contrat de `ServiceAjoutSite.modifierSource`).
      if (json != avant) {
        aEnregistrer = aEnregistrer.copierAvec(
          configurationSelecteurs: json ?? '{}',
        );
      }
    }
    try {
      final modifiee = await _serviceAjoutSite.modifierSource(aEnregistrer);
      await charger();
      final service = _serviceTelechargement;
      if (service != null &&
          modifiee.langueParDefaut != source.langueParDefaut) {
        try {
          await service.appliquerReglesATous();
        } catch (erreur, pile) {
          Journal.actuel.avertissement(
            CategorieJournal.telechargement,
            'Règles non appliquées après modification du site',
            erreur: erreur,
            pile: pile,
          );
        }
      }
      return ResultatAction<Source>.reussite(modifiee);
    } catch (erreur, pile) {
      return ResultatAction<Source>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
  }

  /// Supprime un site.
  ///
  /// Refusé tant que des titres de la bibliothèque viennent de ce site : on
  /// le vérifie avant d'appeler le service pour afficher un message clair
  /// plutôt que l'erreur technique de la base.
  Future<ResultatAction<bool>> supprimerSource(Source source) async {
    final idSource = source.id;
    if (idSource == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      final titres = await _serviceBibliotheque.chargerTitres();
      final nombre = titres.where((titre) => titre.idSource == idSource).length;
      if (nombre > 0) {
        return ResultatAction<bool>.echec(
          DescriptionErreur(NatureErreur.siteAvecTitres, detail: '$nombre'),
        );
      }
      await _serviceAjoutSite.supprimerSource(idSource);
      await charger();
      return const ResultatAction<bool>.reussite(true);
    } on ErreurBaseDeDonnees catch (erreur) {
      // Refus de la base (site encore lié à un titre comme site secondaire,
      // chapitres gardés venant de lui) : son message est une consigne pour
      // le client, pas une panne à signaler.
      return ResultatAction<bool>.echec(
        DescriptionErreur(
          NatureErreur.refus,
          detail: erreur.message,
          cause: erreur,
        ),
      );
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }
}
