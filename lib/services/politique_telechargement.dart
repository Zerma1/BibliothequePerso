/// Choix des chapitres à garder téléchargés, selon les règles du client.
///
/// Calcul pur (aucune base, aucun réseau) : le service de téléchargement
/// l'applique ensuite (mise en file, suppression des archives en trop).
library;

import '../modeles/chapitre.dart';

/// Limites réglables dans l'écran Paramètres.
class ReglagesTelechargement {
  /// Crée les réglages (valeurs par défaut choisies par le client).
  const ReglagesTelechargement({
    this.favorisLusConserves = 10,
    this.suivisInitial = 10,
    this.suivisAvant = 5,
    this.suivisApres = 5,
  });

  /// Favoris : nombre de chapitres déjà lus gardés sur l'appareil (les plus
  /// récents). Tous les chapitres non lus sont téléchargés.
  final int favorisLusConserves;

  /// Suivis : nombre de chapitres téléchargés au départ (chapitres 1 à N tant
  /// que la lecture n'a pas dépassé cette fenêtre).
  final int suivisInitial;

  /// Suivis : nombre de chapitres gardés jusqu'au dernier lu (inclus).
  /// Ceux d'avant sont supprimés.
  final int suivisAvant;

  /// Suivis : nombre de chapitres téléchargés après le dernier lu.
  final int suivisApres;

  /// Copie avec certaines valeurs changées.
  ReglagesTelechargement copierAvec({
    int? favorisLusConserves,
    int? suivisInitial,
    int? suivisAvant,
    int? suivisApres,
  }) {
    return ReglagesTelechargement(
      favorisLusConserves: favorisLusConserves ?? this.favorisLusConserves,
      suivisInitial: suivisInitial ?? this.suivisInitial,
      suivisAvant: suivisAvant ?? this.suivisAvant,
      suivisApres: suivisApres ?? this.suivisApres,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReglagesTelechargement &&
      other.favorisLusConserves == favorisLusConserves &&
      other.suivisInitial == suivisInitial &&
      other.suivisAvant == suivisAvant &&
      other.suivisApres == suivisApres;

  @override
  int get hashCode =>
      Object.hash(favorisLusConserves, suivisInitial, suivisAvant, suivisApres);

  @override
  String toString() =>
      'ReglagesTelechargement(favorisLus: $favorisLusConserves, '
      'suivisInitial: $suivisInitial, suivisAvant: $suivisAvant, '
      'suivisApres: $suivisApres)';
}

/// Ce qu'il faut faire pour un titre : chapitres à télécharger et
/// chapitres téléchargés à supprimer.
class PlanTelechargement {
  /// Crée le plan.
  const PlanTelechargement({
    required this.idsVoulus,
    required this.idsATelecharger,
    required this.idsASupprimer,
  });

  /// Plan vide : rien à faire.
  static const PlanTelechargement vide = PlanTelechargement(
    idsVoulus: <int>{},
    idsATelecharger: <int>[],
    idsASupprimer: <int>[],
  );

  /// Chapitres qui doivent être sur l'appareil.
  final Set<int> idsVoulus;

  /// Chapitres voulus mais pas encore téléchargés, dans l'ordre de lecture.
  final List<int> idsATelecharger;

  /// Chapitres téléchargés qui ne sont plus voulus.
  final List<int> idsASupprimer;
}

/// Applique les règles du client :
///
/// - **Favoris** : tous les chapitres non lus, plus les
///   [ReglagesTelechargement.favorisLusConserves] derniers lus.
/// - **Suivis seulement** : une fenêtre glissante. Au départ, les chapitres 1
///   à [ReglagesTelechargement.suivisInitial] ; dès que la lecture avance,
///   on garde les [ReglagesTelechargement.suivisAvant] derniers chapitres
///   jusqu'au dernier lu, et on télécharge les
///   [ReglagesTelechargement.suivisApres] suivants.
/// - Ni favori ni suivi : aucun téléchargement automatique, rien n'est
///   supprimé (les téléchargements manuels sont conservés).
///
/// Les positions se comptent en **chapitres** et non en numéros : un
/// chapitre 10.5 compte pour un. Pour chaque numéro, une seule version est
/// gardée : la langue préférée du client (ordre de [languesPreferees]), puis
/// la plus ancienne publication. Ainsi un chapitre traduit à la fois en
/// français et en anglais n'est téléchargé qu'une fois, en français.
class PolitiqueTelechargement {
  /// Crée la politique avec les [reglages] et les [languesPreferees] (codes
  /// ISO 639-1, par ordre de préférence).
  const PolitiqueTelechargement({
    this.reglages = const ReglagesTelechargement(),
    this.languesPreferees = const <String>[],
  });

  /// Limites appliquées.
  final ReglagesTelechargement reglages;

  /// Langues du client, par ordre de préférence.
  final List<String> languesPreferees;

  /// Garde une version par numéro, triée par numéro croissant.
  ///
  /// Un numéro est considéré comme lu si **une** de ses versions est lue (le
  /// client a pu lire la version anglaise d'un chapitre aussi traduit en
  /// français).
  List<VersionRetenue> choisirVersions(List<Chapitre> chapitres) {
    final parNumero = <double, List<Chapitre>>{};
    for (final chapitre in chapitres) {
      if (chapitre.id != null) {
        parNumero
            .putIfAbsent(chapitre.numero, () => <Chapitre>[])
            .add(chapitre);
      }
    }
    final numeros = parNumero.keys.toList()..sort();
    return <VersionRetenue>[
      for (final numero in numeros)
        VersionRetenue(
          chapitre: _meilleureVersion(parNumero[numero]!),
          versions: parNumero[numero]!,
        ),
    ];
  }

  Chapitre _meilleureVersion(List<Chapitre> versions) {
    int rangLangue(Chapitre chapitre) {
      final rang = languesPreferees.indexOf(chapitre.langue.toLowerCase());
      return rang < 0 ? languesPreferees.length : rang;
    }

    final triees = List<Chapitre>.of(versions)
      ..sort((a, b) {
        final parLangue = rangLangue(a).compareTo(rangLangue(b));
        if (parLangue != 0) return parLangue;
        // Une version déjà téléchargée est préférée : inutile de la
        // remplacer par une autre traduction équivalente.
        if (a.estTelecharge != b.estTelecharge) return a.estTelecharge ? -1 : 1;
        final dateA = a.datePublication;
        final dateB = b.datePublication;
        if (dateA != null && dateB != null && dateA != dateB) {
          return dateA.compareTo(dateB);
        }
        return a.id!.compareTo(b.id!);
      });
    return triees.first;
  }

  /// Calcule le plan d'un titre.
  PlanTelechargement calculer(
    List<Chapitre> chapitres, {
    required bool estFavori,
    required bool estSuivi,
  }) {
    if (!estFavori && !estSuivi) {
      return PlanTelechargement.vide;
    }
    final versions = choisirVersions(chapitres);
    final indexDernierLu = versions.lastIndexWhere((v) => v.estLu);

    final voulus = <int>{};
    if (estFavori) {
      // Tous les non lus + les N derniers lus.
      var lusGardes = 0;
      for (var i = versions.length - 1; i >= 0; i--) {
        final version = versions[i];
        if (!version.estLu) {
          voulus.add(version.chapitre.id!);
        } else if (lusGardes < _positif(reglages.favorisLusConserves)) {
          voulus.add(version.chapitre.id!);
          lusGardes++;
        }
      }
    } else {
      final avant = _positif(reglages.suivisAvant);
      final apres = _positif(reglages.suivisApres);
      final initial = _positif(reglages.suivisInitial);
      // Fenêtre [debut, fin] en positions de chapitres (0 = premier).
      // Sans lecture : les `initial` premiers. Ensuite, la fenêtre glisse
      // dès que « dernier lu + après » dépasse la fenêtre initiale.
      final debut = indexDernierLu < 0
          ? 0
          : (indexDernierLu - avant + 1).clamp(0, versions.length);
      final finGlissante = indexDernierLu + apres;
      final finInitiale = debut + initial - 1;
      final fin = indexDernierLu < 0 || finInitiale > finGlissante
          ? finInitiale
          : finGlissante;
      for (var i = debut; i <= fin && i < versions.length; i++) {
        voulus.add(versions[i].chapitre.id!);
      }
    }

    final aTelecharger = <int>[
      for (final version in versions)
        if (voulus.contains(version.chapitre.id) &&
            !version.chapitre.estTelecharge)
          version.chapitre.id!,
    ];
    final aSupprimer = <int>[
      for (final chapitre in chapitres)
        if (chapitre.id != null &&
            chapitre.estTelecharge &&
            !voulus.contains(chapitre.id))
          chapitre.id!,
    ];
    return PlanTelechargement(
      idsVoulus: voulus,
      idsATelecharger: aTelecharger,
      idsASupprimer: aSupprimer,
    );
  }

  static int _positif(int valeur) => valeur < 0 ? 0 : valeur;
}

/// Version gardée pour un numéro de chapitre.
class VersionRetenue {
  /// Crée la version retenue.
  const VersionRetenue({required this.chapitre, required this.versions});

  /// Version choisie (langue préférée).
  final Chapitre chapitre;

  /// Toutes les versions de ce numéro (langues, groupes).
  final List<Chapitre> versions;

  /// `true` si une des versions de ce numéro a été lue.
  bool get estLu => versions.any((version) => version.estLu);
}
