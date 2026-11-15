/// Téléchargement des chapitres pour la lecture hors-ligne (PLAYBOOK.md
/// sections 5 et 7) et application des règles de conservation du client.
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../donnees/depot_chapitres.dart';
import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_telechargements.dart';
import '../donnees/depot_titres.dart';
import '../donnees/stockage_telechargements.dart';
import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/source.dart';
import '../modeles/telechargement.dart';
import '../modeles/titre.dart';
import '../sources/client_http_poli.dart';
import '../sources/constantes_sources.dart';
import '../sources/erreur_source.dart';
import '../sources/fabrique_sources.dart';
import '../sources/signalement_mangadex.dart';
import '../sources/source_mangadex.dart';
import '../sources/source_site.dart';
import 'erreur_service.dart';
import 'politique_telechargement.dart';
import 'service_bibliotheque.dart';
import 'service_parametres.dart';

/// Chapitre avec son titre et sa source, tels qu'il faut les passer au
/// stockage (la langue vide est remplacée par la langue de la source pour que
/// le nom de l'archive soit toujours le même).
class _ContexteChapitre {
  const _ContexteChapitre(this.chapitre, this.titre, this.source);

  final Chapitre chapitre;
  final Titre titre;
  final Source source;
}

/// File de téléchargement persistante, lecture des archives et règles de
/// conservation (favoris / suivis).
///
/// Un seul chapitre est téléchargé à la fois : les images d'un chapitre
/// viennent du même serveur, et le délai par domaine de `ClientHttpPoli`
/// rendrait de toute façon le parallélisme inutile.
class ServiceTelechargement {
  /// Crée le service.
  ServiceTelechargement({
    required DepotTelechargements depotTelechargements,
    required DepotChapitres depotChapitres,
    required DepotTitres depotTitres,
    required DepotListes depotListes,
    required DepotSources depotSources,
    required StockageTelechargements stockage,
    required FabriqueSources fabriqueSources,
    required ClientHttpPoli client,
    required ServiceParametres serviceParametres,
    SignalementMangaDex? signalement,
  }) : _depotTelechargements = depotTelechargements,
       _depotChapitres = depotChapitres,
       _depotTitres = depotTitres,
       _depotListes = depotListes,
       _depotSources = depotSources,
       _stockage = stockage,
       _fabriqueSources = fabriqueSources,
       _client = client,
       _serviceParametres = serviceParametres,
       _signalement = signalement ?? SignalementMangaDex(client);

  final DepotTelechargements _depotTelechargements;
  final DepotChapitres _depotChapitres;
  final DepotTitres _depotTitres;
  final DepotListes _depotListes;
  final DepotSources _depotSources;
  final StockageTelechargements _stockage;
  final FabriqueSources _fabriqueSources;
  final ClientHttpPoli _client;
  final ServiceParametres _serviceParametres;
  final SignalementMangaDex _signalement;

  final StreamController<void> _changements =
      StreamController<void>.broadcast();

  /// Traitement de la file en cours, partagé si on le redemande.
  Future<void>? _traitement;

  /// Prévient l'interface à chaque changement de la file (ajout,
  /// progression, fin, suppression).
  Stream<void> get changements => _changements.stream;

  /// `true` pendant que la file est traitée.
  bool get estEnCours => _traitement != null;

  void _signaler() {
    if (!_changements.isClosed) {
      _changements.add(null);
    }
  }

  // ------------------------------------------------------------ Démarrage

  /// À appeler au démarrage : reprend les téléchargements interrompus, efface
  /// les archives partielles, applique les règles puis traite la file.
  Future<void> demarrer() async {
    await _depotTelechargements.reprendreApresInterruption();
    await _stockage.nettoyerFichiersPartiels();
    await appliquerReglesATous();
  }

  /// Libère le service.
  Future<void> fermer() => _changements.close();

  // ------------------------------------------------- Règles de conservation

  /// Applique les règles à tous les titres favoris et suivis, puis lance le
  /// traitement de la file (sans l'attendre).
  Future<void> appliquerReglesATous() async {
    final ids = <int>{};
    for (final nomListe in <String>[nomListeFavoris, nomListeSuivis]) {
      final liste = await _depotListes.chargerListeParNom(nomListe);
      if (liste?.id == null) continue;
      final titres = await _depotTitres.chargerTitres(idListe: liste!.id);
      ids.addAll(titres.map((titre) => titre.id).whereType<int>());
    }
    for (final idTitre in ids) {
      await _appliquerRegles(idTitre);
    }
    lancerTraitement();
  }

  /// Applique les règles à un titre (après une lecture, un changement de
  /// liste ou de réglages), puis lance le traitement de la file.
  Future<PlanTelechargement> appliquerRegles(int idTitre) async {
    final plan = await _appliquerRegles(idTitre);
    lancerTraitement();
    return plan;
  }

  Future<PlanTelechargement> _appliquerRegles(int idTitre) async {
    final titre = await _depotTitres.chargerTitre(idTitre);
    final idSource = titre?.idSource;
    if (titre == null || idSource == null) {
      return PlanTelechargement.vide;
    }
    final source = await _depotSources.chargerSource(idSource);
    final listes = await _depotListes.chargerListesDuTitre(idTitre);
    final noms = listes.map((liste) => liste.nom).toSet();
    final politique = PolitiqueTelechargement(
      reglages: await _serviceParametres.chargerReglagesTelechargement(),
      languesPreferees: _languesPreferees(source),
    );
    final chapitres = await _depotChapitres.chargerChapitres(idTitre);
    final plan = politique.calculer(
      chapitres,
      estFavori: noms.contains(nomListeFavoris),
      estSuivi: noms.contains(nomListeSuivis),
    );

    for (final idChapitre in plan.idsASupprimer) {
      await supprimerTelechargement(idChapitre, signalerChangement: false);
    }
    // Un chapitre voulu dont le téléchargement avait échoué est relancé.
    for (final idChapitre in plan.idsATelecharger) {
      final existant = await _depotTelechargements.chargerParChapitre(
        idChapitre,
      );
      if (existant == null) {
        await _depotTelechargements.ajouterEnFile(idChapitre);
      } else if (existant.statut == StatutTelechargement.echec ||
          existant.statut == StatutTelechargement.termine) {
        // « terminé » alors que le chapitre n'est pas marqué téléchargé :
        // l'archive a disparu, on la refait.
        await _depotTelechargements.enregistrerStatut(
          existant.id!,
          StatutTelechargement.enAttente,
        );
      }
    }
    // Les téléchargements en attente qui ne sont plus voulus (lecture qui a
    // avancé entre-temps) sont retirés de la file.
    final idsChapitres = chapitres.map((c) => c.id).whereType<int>().toSet();
    final file = await _depotTelechargements.chargerFile(
      statuts: <StatutTelechargement>{StatutTelechargement.enAttente},
    );
    for (final telechargement in file) {
      if (idsChapitres.contains(telechargement.idChapitre) &&
          !plan.idsVoulus.contains(telechargement.idChapitre) &&
          (noms.contains(nomListeFavoris) || noms.contains(nomListeSuivis))) {
        await _depotTelechargements.supprimerTelechargement(telechargement.id!);
      }
    }
    _signaler();
    return plan;
  }

  static List<String> _languesPreferees(Source? source) {
    final langues = SourceMangaDex.languesIsoDepuisPreference(
      source?.langueParDefaut ?? '',
    );
    return langues.isEmpty
        ? SourceMangaDex.languesIsoDepuisPreference(
            ServiceBibliotheque.languesParDefaut,
          )
        : langues;
  }

  // ------------------------------------------------- Actions du client

  /// File de téléchargement (tous statuts), dans l'ordre d'ajout.
  Future<List<Telechargement>> chargerFile() =>
      _depotTelechargements.chargerFile();

  /// Ajoute un chapitre à la file (téléchargement manuel) et lance la file.
  Future<void> telechargerChapitre(int idChapitre) async {
    final existant = await _depotTelechargements.chargerParChapitre(idChapitre);
    if (existant == null) {
      await _depotTelechargements.ajouterEnFile(idChapitre);
    } else if (existant.statut == StatutTelechargement.echec) {
      await _depotTelechargements.enregistrerStatut(
        existant.id!,
        StatutTelechargement.enAttente,
      );
    }
    _signaler();
    lancerTraitement();
  }

  /// Supprime l'archive d'un chapitre et sa ligne de file.
  Future<void> supprimerTelechargement(
    int idChapitre, {
    bool signalerChangement = true,
  }) async {
    final contexte = await _chargerContexte(idChapitre);
    if (contexte != null) {
      await _stockage.supprimerChapitre(contexte.titre, contexte.chapitre);
    }
    await _depotChapitres.marquerTelecharge(idChapitre, estTelecharge: false);
    final ligne = await _depotTelechargements.chargerParChapitre(idChapitre);
    if (ligne?.id != null) {
      await _depotTelechargements.supprimerTelechargement(ligne!.id!);
    }
    if (signalerChangement) {
      _signaler();
    }
  }

  /// Retire de la file les téléchargements terminés (l'archive reste).
  Future<int> viderTermines() async {
    final nombre = await _depotTelechargements.supprimerTermines();
    _signaler();
    return nombre;
  }

  // ---------------------------------------------------------------- Lecture

  /// Nombre de pages d'un chapitre téléchargé (0 pour un chapitre texte).
  Future<int> compterPages(int idChapitre) async {
    final contexte = await _exigerContexte(idChapitre);
    return _stockage.compterPages(contexte.titre, contexte.chapitre);
  }

  /// Octets de la page [index] (à partir de 0), lus dans l'archive.
  Future<Uint8List> lirePage(int idChapitre, int index) async {
    final contexte = await _exigerContexte(idChapitre);
    return _stockage.lirePage(contexte.titre, contexte.chapitre, index);
  }

  /// Texte HTML d'un chapitre de roman, ou `null` s'il s'agit d'images.
  Future<String?> lireTexte(int idChapitre) async {
    final contexte = await _exigerContexte(idChapitre);
    return _stockage.lireTexte(contexte.titre, contexte.chapitre);
  }

  Future<_ContexteChapitre> _exigerContexte(int idChapitre) async {
    final contexte = await _chargerContexte(idChapitre);
    if (contexte == null) {
      throw const ErreurService('Ce chapitre n\'existe plus.');
    }
    return contexte;
  }

  Future<_ContexteChapitre?> _chargerContexte(int idChapitre) async {
    final chapitre = await _depotChapitres.chargerChapitre(idChapitre);
    final idTitre = chapitre?.idTitre;
    if (chapitre == null || idTitre == null) return null;
    final titre = await _depotTitres.chargerTitre(idTitre);
    final idSource = titre?.idSource;
    if (titre == null || idSource == null) return null;
    final source = await _depotSources.chargerSource(idSource);
    if (source == null) return null;
    // Même nom d'archive à l'écriture et à la lecture : une langue vide est
    // remplacée par la première langue de la source (PLAYBOOK.md section 5).
    final langues = SourceMangaDex.languesIsoDepuisPreference(
      source.langueParDefaut,
    );
    final chapitrePourChemin = chapitre.langue.isEmpty && langues.isNotEmpty
        ? chapitre.copierAvec(langue: langues.first)
        : chapitre;
    // LIMITE : le suffixe « (nom de la source) » prévu par le playbook en cas
    // de titres homonymes de sources différentes n'est pas encore appliqué.
    return _ContexteChapitre(chapitrePourChemin, titre, source);
  }

  // ------------------------------------------------------ Traitement file

  /// Lance le traitement de la file s'il n'est pas déjà en cours. Renvoie le
  /// traitement (déjà en cours ou nouveau) : les tests peuvent l'attendre.
  Future<void> lancerTraitement() {
    final enCours = _traitement;
    if (enCours != null) {
      return enCours;
    }
    final nouveau = _traiterFile().whenComplete(() {
      _traitement = null;
      _signaler();
    });
    _traitement = nouveau;
    return nouveau;
  }

  Future<void> _traiterFile() async {
    // Rend la main avant de commencer : `_traitement` est affecté avant
    // qu'une fin immédiate ne le remette à null.
    await Future<void>.value();
    while (!_changements.isClosed) {
      final suivant = await _depotTelechargements.chargerProchainEnAttente();
      if (suivant == null) {
        return;
      }
      await _telecharger(suivant);
    }
  }

  Future<void> _telecharger(Telechargement telechargement) async {
    final id = telechargement.id!;
    await _depotTelechargements.enregistrerStatut(
      id,
      StatutTelechargement.enCours,
    );
    _signaler();

    final contexte = await _chargerContexte(telechargement.idChapitre);
    if (contexte == null) {
      await _depotTelechargements.supprimerTelechargement(id);
      return;
    }

    EcritureChapitre? ecriture;
    try {
      final adaptateur = _fabriqueSources.creer(contexte.source);
      var contenu = await adaptateur.recupererContenu(
        contexte.chapitre.urlChapitre,
      );
      ecriture = await _stockage.ouvrirEcriture(
        contexte.titre,
        contexte.chapitre,
      );

      final texte = contenu.texteHtml;
      if (contenu.estTexte && texte != null) {
        await ecriture.ajouterTexte(texte);
      } else {
        final total = contenu.urlsImages.length;
        await _depotTelechargements.enregistrerProgression(
          id,
          nombrePagesFaites: 0,
          nombrePagesTotal: total,
        );
        for (var index = 0; index < total; index++) {
          final (octets, url, contenuAJour) = await _telechargerPage(
            contenu,
            index,
            adaptateur,
            contexte,
          );
          contenu = contenuAJour;
          await ecriture.ajouterPage(
            octets,
            extension: StockageTelechargements.extensionDepuisUrl(url) ?? 'jpg',
          );
          await _depotTelechargements.enregistrerProgression(
            id,
            nombrePagesFaites: index + 1,
          );
          _signaler();
        }
      }
      await ecriture.finaliser();
      ecriture = null;
      await _depotTelechargements.enregistrerStatut(
        id,
        StatutTelechargement.termine,
      );
    } catch (erreur, pile) {
      debugPrint('Téléchargement n°$id en échec : $erreur\n$pile');
      try {
        await ecriture?.abandonner();
      } catch (_) {
        // L'archive partielle sera effacée au prochain démarrage.
      }
      await _depotTelechargements.enregistrerStatut(
        id,
        StatutTelechargement.echec,
        messageErreur: _messageErreur(erreur),
      );
    }
    _signaler();
  }

  /// Télécharge une page. Sur MangaDex, une adresse d'images expirée (403
  /// après 15 minutes) ou un nœud MangaDex@Home en panne est remplacée une
  /// fois en redemandant le contenu du chapitre (règle de la documentation).
  Future<(Uint8List, String, ContenuChapitre)> _telechargerPage(
    ContenuChapitre contenu,
    int index,
    SourceSite adaptateur,
    _ContexteChapitre contexte,
  ) async {
    var contenuCourant = contenu;
    for (var essai = 0; essai < 2; essai++) {
      final url = contenuCourant.urlsImages[index];
      try {
        final octets = await _recupererImage(url, contenuCourant, contexte);
        return (octets, url, contenuCourant);
      } on ErreurSource catch (erreur) {
        final peutRenouveler =
            essai == 0 && SignalementMangaDex.estServeurMangaDexAtHome(url);
        if (!peutRenouveler) rethrow;
        contenuCourant = await adaptateur.recupererContenu(
          contexte.chapitre.urlChapitre,
        );
        if (contenuCourant.urlsImages.length <= index) {
          throw ErreurSource(
            url,
            'Le chapitre a changé pendant le téléchargement.',
            cause: erreur,
          );
        }
      }
    }
    // Inatteignable : la boucle renvoie ou relance toujours.
    throw StateError('Téléchargement de page interrompu');
  }

  Future<Uint8List> _recupererImage(
    String url,
    ContenuChapitre contenu,
    _ContexteChapitre contexte,
  ) async {
    final uri = Uri.parse(url);
    if (SignalementMangaDex.estServeurMangaDexAtHome(url)) {
      // Une seule tentative : chaque échec doit être signalé, puis on change
      // de serveur plutôt que d'insister (documentation MangaDex).
      try {
        final reponse = await _client.recupererOctetsAvecDetails(
          uri,
          userAgent: userAgentApplication,
          nouvellesTentatives: 0,
        );
        unawaited(_signalement.signalerReussite(url, reponse));
        return reponse.octets;
      } on ErreurSource catch (erreur) {
        unawaited(_signalement.signalerEchec(url, erreur));
        rethrow;
      }
    }
    final estMangaDex = SourceMangaDex.estHoteMangaDex(uri.host);
    return _client.recupererOctets(
      uri,
      referer: contenu.urlReferer ?? contexte.source.urlBase,
      userAgent: estMangaDex ? userAgentApplication : null,
    );
  }

  static String _messageErreur(Object erreur) {
    if (erreur is ErreurSource) return erreur.message;
    if (erreur is ErreurService) return erreur.message;
    return erreur.toString();
  }
}
