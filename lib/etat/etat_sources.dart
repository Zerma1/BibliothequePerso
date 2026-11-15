/// État de l'écran Sources : sites configurés et ajout d'un site.
library;

import 'package:flutter/foundation.dart';

import '../modeles/source.dart';
import '../services/service_ajout_site.dart';
import '../services/service_bibliotheque.dart';
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

  /// Modifie le nom, les langues (« fr,en », par ordre de préférence) et
  /// l'activation d'un site.
  ///
  /// Si les langues changent, les règles de téléchargement sont
  /// réappliquées : la version retenue de chaque numéro peut changer.
  Future<ResultatAction<Source>> modifierSource(
    Source source, {
    required String nom,
    required String langues,
    required bool estActive,
  }) async {
    if (nom.trim().isEmpty) {
      return const ResultatAction<Source>.echec(
        DescriptionErreur(NatureErreur.nomVide),
      );
    }
    try {
      final modifiee = await _serviceAjoutSite.modifierSource(
        source.copierAvec(
          nom: nom,
          langueParDefaut: langues,
          estActive: estActive,
        ),
      );
      await charger();
      final service = _serviceTelechargement;
      if (service != null &&
          modifiee.langueParDefaut != source.langueParDefaut) {
        try {
          await service.appliquerReglesATous();
        } catch (erreur, pile) {
          debugPrint(
            'Règles non appliquées après modification : $erreur\n$pile',
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
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }
}
