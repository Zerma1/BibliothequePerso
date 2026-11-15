/// État de l'écran Sources : sites configurés et ajout d'un site.
library;

import '../modeles/source.dart';
import '../services/service_ajout_site.dart';
import '../services/service_bibliotheque.dart';
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

/// Liste des sites configurés et ajout d'un site par URL.
class EtatSources extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire la base.
  EtatSources(this._serviceBibliotheque, this._serviceAjoutSite);

  final ServiceBibliotheque _serviceBibliotheque;
  final ServiceAjoutSite _serviceAjoutSite;

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

  /// Nom proposé pour le site à [url] (hôte sans `www.`), ou une chaîne vide
  /// si l'adresse n'est pas encore exploitable.
  String proposerNom(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) {
      return '';
    }
    return ServiceAjoutSite.proposerNom(uri);
  }

  /// Ajoute le site désigné par [url].
  ///
  /// [nom] et [langueParDefaut] sont facultatifs ; [typeForce] remplace la
  /// détection automatique quand le client corrige le type.
  Future<ResultatAction<SiteAjoute>> ajouterSite(
    String url, {
    String? nom,
    String langueParDefaut = '',
    TypeSource? typeForce,
  }) async {
    if (url.trim().isEmpty) {
      return const ResultatAction<SiteAjoute>.echec(
        DescriptionErreur(NatureErreur.adresseVide),
      );
    }
    _estEnAjout = true;
    notifier();
    try {
      final source = await _serviceAjoutSite.ajouterSite(
        url.trim(),
        nom: nom,
        langueParDefaut: langueParDefaut,
        typeForce: typeForce,
      );
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
}
