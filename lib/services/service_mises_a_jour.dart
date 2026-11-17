/// Recherche des nouveaux chapitres des titres suivis (PLAYBOOK.md section 7).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../modeles/constantes.dart';
import '../modeles/titre.dart';
import 'planification_mises_a_jour.dart';
import 'service_bibliotheque.dart';
import 'service_parametres.dart';

/// Résultat de la vérification d'un titre.
class ResultatVerificationTitre {
  /// Crée le résultat.
  const ResultatVerificationTitre({
    required this.titre,
    this.nombreNouveauxChapitres = 0,
    this.erreur,
    this.estAnnonce = true,
    this.erreursParSite = const <int, Object>{},
  });

  /// Titre vérifié.
  final Titre titre;

  /// Chapitres trouvés qui n'étaient pas encore connus (tous sites
  /// confondus).
  final int nombreNouveauxChapitres;

  /// Erreur rencontrée (site injoignable…), `null` si tout s'est bien passé.
  ///
  /// Étape 8 : si **un** des sites du titre a échoué, c'est son erreur (celle
  /// du site principal en priorité), même si d'autres sites ont répondu et
  /// apporté des nouveautés ([nombreNouveauxChapitres]) : le client doit
  /// savoir qu'un site ne répond plus.
  final Object? erreur;

  /// Erreur de chaque site en échec, par identifiant de source (vide si
  /// tous les sites ont répondu).
  final Map<int, Object> erreursParSite;

  /// `false` pour un titre vérifié en silence : seulement planifié (liste
  /// « Planifié », éventuellement « En attente »), ni favori ni suivi. Ses
  /// nouveautés n'apparaissent jamais dans les bilans ni les notifications
  /// (décision de l'étape 6).
  final bool estAnnonce;

  /// `true` si la vérification a échoué.
  bool get aEchoue => erreur != null;
}

/// Bilan d'une recherche de mises à jour.
///
/// Les compteurs et listes du bilan ([nombreNouveauxChapitres],
/// [titresAvecNouveautes], [echecs]) ne portent que sur les titres annoncés
/// ([ResultatVerificationTitre.estAnnonce]) ; [resultats] les contient
/// tous.
class RapportMisesAJour {
  /// Crée le bilan.
  const RapportMisesAJour({
    required this.debut,
    required this.fin,
    required this.resultats,
    this.estEnAttenteSeulement = false,
  });

  /// Début de la vérification (UTC).
  final DateTime debut;

  /// Fin de la vérification (UTC).
  final DateTime fin;

  /// Un résultat par titre vérifié, annoncé ou non.
  final List<ResultatVerificationTitre> resultats;

  /// `true` pour une vérification limitée aux titres « En attente »
  /// (surveillance horaire).
  final bool estEnAttenteSeulement;

  /// Résultats des titres annoncés (favoris et suivis).
  List<ResultatVerificationTitre> get resultatsAnnonces =>
      resultats.where((resultat) => resultat.estAnnonce).toList();

  /// Nombre total de nouveaux chapitres des titres annoncés.
  int get nombreNouveauxChapitres => resultatsAnnonces.fold<int>(
    0,
    (total, resultat) => total + resultat.nombreNouveauxChapitres,
  );

  /// Titres annoncés qui ont au moins un nouveau chapitre.
  List<ResultatVerificationTitre> get titresAvecNouveautes => resultatsAnnonces
      .where((resultat) => resultat.nombreNouveauxChapitres > 0)
      .toList();

  /// Vérifications en échec des titres annoncés.
  List<ResultatVerificationTitre> get echecs =>
      resultatsAnnonces.where((resultat) => resultat.aEchoue).toList();
}

/// Vérifie les titres des listes « Suivis », « Planifié » et « En attente »
/// et enregistre leurs nouveaux chapitres.
///
/// Règles du PLAYBOOK : au plus [maximumSourcesEnParallele] sources vérifiées
/// en même temps, et un seul titre à la fois par source (les délais par
/// domaine de `ClientHttpPoli` s'appliquent en plus). Une erreur sur un titre
/// est enregistrée dans le rapport et n'interrompt pas les autres.
///
/// Les titres « En attente » (aucun chapitre dans les langues du client)
/// sont en plus vérifiés seuls, plus souvent ([verifierTitresEnAttente],
/// toutes les N heures pleines selon le réglage).
class ServiceMisesAJour {
  /// Crée le service.
  ServiceMisesAJour({
    required DepotTitres depotTitres,
    required DepotListes depotListes,
    required DepotSources depotSources,
    required ServiceBibliotheque serviceBibliotheque,
    ServiceParametres? serviceParametres,
    DateTime Function()? maintenant,
  }) : _depotTitres = depotTitres,
       _depotListes = depotListes,
       _depotSources = depotSources,
       _serviceBibliotheque = serviceBibliotheque,
       _serviceParametres = serviceParametres,
       _maintenant = maintenant ?? (() => DateTime.now().toUtc());

  final DepotTitres _depotTitres;
  final DepotListes _depotListes;
  final DepotSources _depotSources;
  final ServiceBibliotheque _serviceBibliotheque;
  final DateTime Function() _maintenant;

  /// Réglages : horaires des vérifications et date de la dernière. `null`
  /// dans les tests qui n'en ont pas besoin.
  final ServiceParametres? _serviceParametres;

  /// Nombre maximal de sources vérifiées en même temps (PLAYBOOK.md section 7).
  static const int maximumSourcesEnParallele = 3;

  /// Listes dont les titres sont vérifiés par la vérification complète.
  /// « Planifié » est vérifié (en silence) ; « En attente » regroupe des
  /// favoris, suivis et planifiés sans chapitre dans les langues du client.
  // « Favoris » est indispensable : un titre peut n'être que favori (sans
  // être aussi suivi) et doit quand même recevoir ses nouveaux chapitres.
  static const List<String> listesVerifiees = <String>[
    nomListeFavoris,
    nomListeSuivis,
    nomListePlanifie,
    nomListeEnAttente,
  ];

  /// Vérification en cours, partagée si on la redemande avant la fin.
  Future<RapportMisesAJour>? _enCours;

  /// `true` si [_enCours] est une vérification complète (et non « En
  /// attente » seulement).
  bool _enCoursEstComplete = false;

  /// Vérification complète demandée pendant une vérification « En attente » :
  /// elle démarre juste après, et est partagée si on la redemande.
  Future<RapportMisesAJour>? _completeDemandee;

  /// `true` pendant une vérification (ou si une est prévue juste après).
  bool get estEnCours => _enCours != null || _completeDemandee != null;

  /// Lance la vérification complète (titres suivis, planifiés et en
  /// attente), ou renvoie celle en cours.
  ///
  /// Une deuxième demande pendant une vérification (minuterie + bouton, par
  /// exemple) ne relance pas de requêtes : elle reçoit le même rapport. Si
  /// seule une vérification « En attente » est en cours, la complète démarre
  /// juste après elle.
  Future<RapportMisesAJour> verifierTitresSuivis() {
    final enCours = _enCours;
    if (enCours == null) return _lancer(complete: true);
    if (_enCoursEstComplete) return enCours;
    return _completeDemandee ??= enCours
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) {
          _completeDemandee = null;
          return verifierTitresSuivis();
        });
  }

  /// Vérifie seulement les titres de la liste « En attente » (surveillance
  /// accrue), ou renvoie la vérification en cours : une vérification
  /// complète les couvre déjà.
  Future<RapportMisesAJour> verifierTitresEnAttente() {
    final enCours = _enCours ?? _completeDemandee;
    if (enCours != null) return enCours;
    return _lancer(complete: false);
  }

  Future<RapportMisesAJour> _lancer({required bool complete}) {
    final nouvelle = _verifier(complete: complete).whenComplete(() {
      _enCours = null;
    });
    _enCours = nouvelle;
    _enCoursEstComplete = complete;
    return nouvelle;
  }

  Future<RapportMisesAJour> _verifier({required bool complete}) async {
    final debut = _maintenant();
    // Classement « En attente » recalculé d'abord (base seulement) : les
    // langues du client ont pu changer depuis la dernière fois.
    try {
      await _serviceBibliotheque.classerTousEnAttente();
    } catch (erreur) {
      debugPrint('Classement « En attente » impossible : $erreur');
    }
    final (titres, idsAnnonces, idsActifs) = await _chargerTitresAVerifier(
      complete: complete,
    );

    // Étape 8 : une tâche par site d'un titre (principal et secondaires),
    // regroupées par site : chaque groupe est traité tâche par tâche, ce qui
    // garde « un seul titre à la fois par source » même quand un titre a
    // plusieurs sites. Seuls les sites actifs sont interrogés.
    final parSource = <int, List<(_CumulTitre, int)>>{};
    final cumuls = <_CumulTitre>[];
    for (final titre in titres) {
      final cumul = _CumulTitre(titre);
      try {
        for (final lien in await _serviceBibliotheque.chargerLiensDuTitre(
          titre,
        )) {
          // Lien seul (tâche T4) : site que l'application ne sait pas lire,
          // jamais interrogé.
          if (lien.estLienSeul || !idsActifs.contains(lien.idSource)) continue;
          if (lien.estPrincipale) cumul.idSourcePrincipale = lien.idSource;
          cumul.nombreSites++;
          parSource
              .putIfAbsent(lien.idSource, () => <(_CumulTitre, int)>[])
              .add((cumul, lien.idSource));
        }
      } catch (erreur) {
        // Base illisible pour ce titre : noté dans le rapport, les autres
        // titres continuent.
        cumul.erreurs[titre.idSource ?? 0] = erreur;
        cumuls.add(cumul);
        continue;
      }
      if (cumul.nombreSites > 0) cumuls.add(cumul);
    }

    final groupes = parSource.values.toList();
    var prochainGroupe = 0;

    // Petit « pool » de travailleurs : chacun prend la source suivante dès
    // qu'il a fini la sienne. Dart est mono-thread : l'incrément de
    // `prochainGroupe` entre deux `await` ne peut pas être concurrent.
    Future<void> travailleur() async {
      while (prochainGroupe < groupes.length) {
        final groupe = groupes[prochainGroupe++];
        for (final (cumul, idSource) in groupe) {
          await _verifierSite(cumul, idSource);
        }
      }
    }

    final nombreTravailleurs = groupes.length < maximumSourcesEnParallele
        ? groupes.length
        : maximumSourcesEnParallele;
    await Future.wait(
      List<Future<void>>.generate(nombreTravailleurs, (_) => travailleur()),
    );
    final resultats = <ResultatVerificationTitre>[
      for (final cumul in cumuls)
        cumul.versResultat(estAnnonce: idsAnnonces.contains(cumul.titre.id)),
    ];

    final fin = _maintenant();
    // Les dates sont enregistrées en base (et non en mémoire) pour être
    // partagées par l'application et la tâche de fond Android : l'une ne
    // refait pas la vérification que l'autre vient de faire. La complète
    // couvre aussi les titres « En attente ».
    final parametres = _serviceParametres;
    if (parametres != null) {
      if (complete) await parametres.enregistrerDerniereVerification(fin);
      await parametres.enregistrerDerniereVerificationEnAttente(fin);
    }
    return RapportMisesAJour(
      debut: debut,
      fin: fin,
      resultats: resultats,
      estEnAttenteSeulement: !complete,
    );
  }

  /// Lance la vérification complète si une échéance prévue (00:00, 12:00
  /// UTC… selon le réglage) est passée depuis la dernière ; sinon la
  /// vérification des titres « En attente » si leur échéance (toutes les N
  /// heures pleines) est passée.
  ///
  /// Sert au démarrage de l'application, aux minuteurs et à la tâche de fond :
  /// une application ouverte à 12:05 vérifie, une réouverture à 12:30 non.
  /// Renvoie `null` si rien n'était dû.
  Future<RapportMisesAJour?> verifierSiEcheancePassee() async {
    final parametres = _serviceParametres;
    if (parametres == null) return verifierTitresSuivis();
    final maintenant = _maintenant();
    final planification = await parametres.chargerPlanification();
    final derniere = await parametres.chargerDerniereVerification();
    if (planification.estEnRetard(derniere, maintenant)) {
      return verifierTitresSuivis();
    }
    final planificationEnAttente = await parametres
        .chargerPlanificationEnAttente();
    final derniereEnAttente = await parametres
        .chargerDerniereVerificationEnAttente();
    if (planificationEnAttente.estEnRetard(derniereEnAttente, maintenant) &&
        await _aDesTitresEnAttente()) {
      return verifierTitresEnAttente();
    }
    return null;
  }

  /// Prochaine échéance (UTC) après [maintenant], toutes vérifications
  /// confondues : la plus proche entre la planification normale et celle
  /// des titres « En attente » (si la liste n'est pas vide). Sert aux
  /// minuteurs de l'interface et à la tâche de fond Android.
  Future<DateTime> chargerProchaineEcheance(DateTime maintenant) async {
    final parametres = _serviceParametres;
    if (parametres == null) {
      // Sans réglages : planification par défaut (00:00 et 12:00 UTC).
      return PlanificationMisesAJour(PlanificationMisesAJour.parDefautParJour)
          .prochaineEcheance(maintenant);
    }
    final normale = (await parametres.chargerPlanification()).prochaineEcheance(
      maintenant,
    );
    if (!await _aDesTitresEnAttente()) return normale;
    final enAttente = (await parametres.chargerPlanificationEnAttente())
        .prochaineEcheance(maintenant);
    return enAttente.isBefore(normale) ? enAttente : normale;
  }

  Future<bool> _aDesTitresEnAttente() async {
    final liste = await _depotListes.chargerListeParNom(nomListeEnAttente);
    if (liste?.id == null) return false;
    return (await _depotTitres.chargerTitres(idListe: liste!.id)).isNotEmpty;
  }

  /// Titres à vérifier (listes [listesVerifiees], ou « En attente »
  /// seulement), identifiants des titres annoncés (favoris ou suivis) et
  /// identifiants des sources actives (seuls leurs sites sont interrogés).
  Future<(List<Titre>, Set<int>, Set<int>)> _chargerTitresAVerifier({
    required bool complete,
  }) async {
    Future<List<Titre>> titresDe(String nom) async {
      final liste = await _depotListes.chargerListeParNom(nom);
      if (liste?.id == null) return const <Titre>[];
      return _depotTitres.chargerTitres(idListe: liste!.id);
    }

    final parId = <int, Titre>{};
    for (final nom
        in complete ? listesVerifiees : <String>[nomListeEnAttente]) {
      for (final titre in await titresDe(nom)) {
        if (titre.id != null) parId[titre.id!] = titre;
      }
    }
    final idsAnnonces = <int>{
      for (final nom in <String>[nomListeFavoris, nomListeSuivis])
        ...(await titresDe(nom)).map((titre) => titre.id).whereType<int>(),
    };
    final sources = await _depotSources.chargerSources();
    final idsActifs = sources
        .where((source) => source.estActive && source.id != null)
        .map((source) => source.id!)
        .toSet();
    // Un titre dont aucun site n'est actif est écarté plus tard (ses sites
    // ne sont connus qu'à ce moment-là).
    return (parId.values.toList(), idsAnnonces, idsActifs);
  }

  /// Vérifie le site [idSource] du titre de [cumul] et ajoute le résultat
  /// au cumul du titre.
  Future<void> _verifierSite(_CumulTitre cumul, int idSource) async {
    try {
      final resultat = await _serviceBibliotheque.actualiserSiteDuTitre(
        cumul.titre,
        idSource,
      );
      cumul.nombreNouveaux += resultat.nombreNouveauxChapitres;
      // Le titre relu après le site principal porte la fiche à jour ; sinon
      // le dernier relu.
      if (idSource == cumul.idSourcePrincipale || cumul.titreRelu == null) {
        cumul.titreRelu = resultat.titre;
      }
    } catch (erreur) {
      // Un site en panne ne doit bloquer ni les autres sites du titre, ni
      // les autres titres : l'erreur est gardée dans le rapport (PLAYBOOK.md
      // section 6).
      cumul.erreurs[idSource] = erreur;
    }
  }
}

/// Résultats des sites d'un même titre pendant une vérification.
class _CumulTitre {
  _CumulTitre(this.titre);

  /// Titre tel que chargé avant la vérification.
  final Titre titre;

  /// Site principal du titre parmi les sites interrogés, s'il est actif.
  int? idSourcePrincipale;

  /// Nombre de sites interrogés.
  int nombreSites = 0;

  /// Nouveaux chapitres, tous sites confondus.
  int nombreNouveaux = 0;

  /// Titre relu après une actualisation réussie.
  Titre? titreRelu;

  /// Erreurs par site.
  final Map<int, Object> erreurs = <int, Object>{};

  ResultatVerificationTitre versResultat({required bool estAnnonce}) {
    final erreurPrincipale = erreurs[idSourcePrincipale];
    return ResultatVerificationTitre(
      titre: titreRelu ?? titre,
      nombreNouveauxChapitres: nombreNouveaux,
      erreur: erreurPrincipale ?? erreurs.values.firstOrNull,
      erreursParSite: Map<int, Object>.unmodifiable(erreurs),
      estAnnonce: estAnnonce,
    );
  }
}
