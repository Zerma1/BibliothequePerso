/// Recherche des nouveaux chapitres des titres suivis (PLAYBOOK.md section 7).
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../donnees/depot_listes.dart';
import '../donnees/depot_sources.dart';
import '../donnees/depot_titres.dart';
import '../modeles/constantes.dart';
import '../modeles/titre.dart';
import 'service_bibliotheque.dart';
import 'service_parametres.dart';

/// Résultat de la vérification d'un titre.
class ResultatVerificationTitre {
  /// Crée le résultat.
  const ResultatVerificationTitre({
    required this.titre,
    this.nombreNouveauxChapitres = 0,
    this.erreur,
  });

  /// Titre vérifié.
  final Titre titre;

  /// Chapitres trouvés qui n'étaient pas encore connus.
  final int nombreNouveauxChapitres;

  /// Erreur rencontrée (site injoignable…), `null` si tout s'est bien passé.
  final Object? erreur;

  /// `true` si la vérification a échoué.
  bool get aEchoue => erreur != null;
}

/// Bilan d'une recherche de mises à jour.
class RapportMisesAJour {
  /// Crée le bilan.
  const RapportMisesAJour({
    required this.debut,
    required this.fin,
    required this.resultats,
  });

  /// Début de la vérification (UTC).
  final DateTime debut;

  /// Fin de la vérification (UTC).
  final DateTime fin;

  /// Un résultat par titre vérifié.
  final List<ResultatVerificationTitre> resultats;

  /// Nombre total de nouveaux chapitres.
  int get nombreNouveauxChapitres => resultats.fold<int>(
    0,
    (total, resultat) => total + resultat.nombreNouveauxChapitres,
  );

  /// Titres qui ont au moins un nouveau chapitre.
  List<ResultatVerificationTitre> get titresAvecNouveautes => resultats
      .where((resultat) => resultat.nombreNouveauxChapitres > 0)
      .toList();

  /// Vérifications en échec.
  List<ResultatVerificationTitre> get echecs =>
      resultats.where((resultat) => resultat.aEchoue).toList();
}

/// Vérifie les titres de la liste « Suivis » et enregistre leurs nouveaux
/// chapitres.
///
/// Règles du PLAYBOOK : au plus [maximumSourcesEnParallele] sources vérifiées
/// en même temps, et un seul titre à la fois par source (les délais par
/// domaine de `ClientHttpPoli` s'appliquent en plus). Une erreur sur un titre
/// est enregistrée dans le rapport et n'interrompt pas les autres.
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

  /// Vérification en cours, partagée si on la redemande avant la fin.
  Future<RapportMisesAJour>? _enCours;

  /// `true` pendant une vérification.
  bool get estEnCours => _enCours != null;

  /// Lance la vérification des titres suivis, ou renvoie celle en cours.
  ///
  /// Une deuxième demande pendant une vérification (minuterie + bouton, par
  /// exemple) ne relance pas de requêtes : elle reçoit le même rapport.
  Future<RapportMisesAJour> verifierTitresSuivis() {
    final enCours = _enCours;
    if (enCours != null) {
      return enCours;
    }
    final nouvelle = _verifier().whenComplete(() => _enCours = null);
    _enCours = nouvelle;
    return nouvelle;
  }

  Future<RapportMisesAJour> _verifier() async {
    final debut = _maintenant();
    final titres = await _chargerTitresAVerifier();

    // Regroupement par source : chaque groupe est traité titre par titre.
    final parSource = <int, List<Titre>>{};
    for (final titre in titres) {
      final idSource = titre.idSource;
      if (idSource != null) {
        parSource.putIfAbsent(idSource, () => <Titre>[]).add(titre);
      }
    }

    final resultats = <ResultatVerificationTitre>[];
    final groupes = parSource.values.toList();
    var prochainGroupe = 0;

    // Petit « pool » de travailleurs : chacun prend la source suivante dès
    // qu'il a fini la sienne. Dart est mono-thread : l'incrément de
    // `prochainGroupe` entre deux `await` ne peut pas être concurrent.
    Future<void> travailleur() async {
      while (prochainGroupe < groupes.length) {
        final groupe = groupes[prochainGroupe++];
        for (final titre in groupe) {
          resultats.add(await _verifierTitre(titre));
        }
      }
    }

    final nombreTravailleurs = groupes.length < maximumSourcesEnParallele
        ? groupes.length
        : maximumSourcesEnParallele;
    await Future.wait(
      List<Future<void>>.generate(nombreTravailleurs, (_) => travailleur()),
    );

    final fin = _maintenant();
    // La date est enregistrée en base (et non en mémoire) pour être partagée
    // par l'application et la tâche de fond Android : l'une ne refait pas
    // la vérification que l'autre vient de faire.
    await _serviceParametres?.enregistrerDerniereVerification(fin);
    return RapportMisesAJour(debut: debut, fin: fin, resultats: resultats);
  }

  /// Lance la vérification seulement si une échéance prévue (00:00, 12:00
  /// UTC… selon le réglage) est passée depuis la dernière vérification.
  ///
  /// Sert au démarrage de l'application, aux minuteurs et à la tâche de fond :
  /// une application ouverte à 12:05 vérifie, une réouverture à 12:30 non.
  /// Renvoie `null` si rien n'était dû.
  Future<RapportMisesAJour?> verifierSiEcheancePassee() async {
    final parametres = _serviceParametres;
    if (parametres != null) {
      final planification = await parametres.chargerPlanification();
      final derniere = await parametres.chargerDerniereVerification();
      if (!planification.estEnRetard(derniere, _maintenant())) {
        return null;
      }
    }
    return verifierTitresSuivis();
  }

  /// Titres de la liste « Suivis » dont la source est active.
  Future<List<Titre>> _chargerTitresAVerifier() async {
    final suivis = await _depotListes.chargerListeParNom(nomListeSuivis);
    if (suivis?.id == null) {
      return const <Titre>[];
    }
    final titres = await _depotTitres.chargerTitres(idListe: suivis!.id);
    final sources = await _depotSources.chargerSources();
    final idsActifs = sources
        .where((source) => source.estActive && source.id != null)
        .map((source) => source.id!)
        .toSet();
    return titres.where((titre) => idsActifs.contains(titre.idSource)).toList();
  }

  Future<ResultatVerificationTitre> _verifierTitre(Titre titre) async {
    try {
      final resultat = await _serviceBibliotheque.actualiserTitre(titre);
      return ResultatVerificationTitre(
        titre: resultat.titre,
        nombreNouveauxChapitres: resultat.nombreNouveauxChapitres,
      );
    } catch (erreur) {
      // Un site en panne ne doit pas bloquer la vérification des autres
      // titres : l'erreur est gardée dans le rapport (PLAYBOOK.md section 6).
      return ResultatVerificationTitre(titre: titre, erreur: erreur);
    }
  }
}
