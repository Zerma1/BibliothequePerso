/// Choix des chapitres à garder téléchargés, selon les règles du client.
///
/// Calcul pur (aucune base, aucun réseau) : le service de téléchargement
/// l'applique ensuite (mise en file, suppression des archives en trop).
library;

import '../modeles/chapitre.dart';
import 'constantes_services.dart';

/// Limites réglables dans l'écran Paramètres.
///
/// Les valeurs sont gardées telles quelles ; la politique applique les
/// bornes au calcul (négatif ramené à 0, [suivisAvant] et [suivisApres] au
/// moins [minimumSuivisAvantApres]) et `ServiceParametres` les applique à
/// l'enregistrement.
class ReglagesTelechargement {
  /// Crée les réglages (valeurs par défaut choisies par le client).
  const ReglagesTelechargement({
    this.favorisLusConserves = favorisLusConservesParDefaut,
    this.suivisInitial = suivisInitialParDefaut,
    this.suivisAvant = suivisAvantParDefaut,
    this.suivisApres = suivisApresParDefaut,
  });

  /// Favoris : nombre de chapitres déjà lus gardés sur l'appareil (les plus
  /// récents). Tous les chapitres non lus sont téléchargés.
  final int favorisLusConserves;

  /// Suivis : nombre de chapitres téléchargés au départ (chapitres 1 à N tant
  /// que la lecture n'a pas dépassé cette fenêtre).
  final int suivisInitial;

  /// Suivis : nombre de chapitres gardés jusqu'au dernier lu (inclus).
  /// Ceux d'avant sont supprimés. Au moins [minimumSuivisAvantApres].
  final int suivisAvant;

  /// Suivis : nombre de chapitres téléchargés après le dernier lu. Au moins
  /// [minimumSuivisAvantApres].
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
/// Exception pour un favori : un numéro **déjà lu** dont une version (dans
/// les langues du client) est téléchargée garde cette version, sans
/// retéléchargement dans la langue préférée.
///
/// Langues : quand [languesPreferees] n'est pas vide, une version dans une
/// autre langue n'est **jamais** téléchargée par les règles (règle du
/// client : pas de russe ni de japonais s'il a choisi « fr,en »). Un numéro
/// sans version dans ces langues est ignoré (il ne compte pas dans les
/// positions), et une archive déjà présente dans une autre langue est à
/// supprimer. Une version sans langue connue (site d'une seule langue) est
/// acceptée. Une variante régionale de même langue de base est acceptée en
/// repli, après les langues exactes (voir [PolitiqueTelechargement.rangLangue]).
///
/// Chapitres hébergés sur un site externe (`Chapitre.estExterne`, R4) : ils
/// ne sont **jamais** à télécharger. Une version hébergée du même numéro
/// dans les langues du client passe toujours avant eux ; un numéro dont les
/// seules versions dans ces langues sont externes est ignoré comme un numéro
/// d'une autre langue (il ne compte pas dans les positions). Une archive
/// d'un chapitre devenu externe n'est jamais supprimée par les règles : elle
/// ne pourrait plus être retéléchargée.
///
/// Plusieurs sites pour un titre (étape 8) : un même numéro peut exister sur
/// chaque site. La version retenue est choisie dans cet ordre (décision de
/// l'orchestrateur) : langue préférée, puis version hébergée plutôt
/// qu'externe, puis version déjà téléchargée (pour ne pas retélécharger ce
/// qui est déjà sur l'appareil), puis site principal
/// ([idSourcePrincipale]), puis la plus ancienne. Les chapitres d'un site
/// retiré du titre (hors de [idsSourcesLiees]) ne sont jamais retenus ; leurs
/// archives sont à supprimer (suppression différée de 24 h côté service),
/// même pour un titre ni favori ni suivi.
class PolitiqueTelechargement {
  /// Crée la politique avec les [reglages] et les [languesPreferees] (codes
  /// ISO 639-1, par ordre de préférence).
  ///
  /// [idSourcePrincipale] : site principal du titre (départage deux versions
  /// équivalentes) ; [idsSourcesLiees] : sites encore liés au titre (`null`
  /// = tous les chapitres sont considérés comme venant d'un site lié).
  const PolitiqueTelechargement({
    this.reglages = const ReglagesTelechargement(),
    this.languesPreferees = const <String>[],
    this.idSourcePrincipale,
    this.idsSourcesLiees,
  });

  /// Limites appliquées.
  final ReglagesTelechargement reglages;

  /// Langues du client, par ordre de préférence.
  final List<String> languesPreferees;

  /// Site principal du titre, ou `null` s'il n'est pas connu (aucune
  /// préférence de site).
  final int? idSourcePrincipale;

  /// Sites liés au titre, ou `null` pour ne pas filtrer par site.
  final Set<int>? idsSourcesLiees;

  /// `true` si [chapitre] vient d'un site qui n'est plus lié au titre
  /// (site secondaire retiré) : il n'est plus suivi, son archive éventuelle
  /// est à supprimer. Un chapitre sans site connu (`idSource` nul, lignes
  /// antérieures à l'étape 8) est considéré comme venant du site principal.
  bool estDeSiteRetire(Chapitre chapitre) {
    final liees = idsSourcesLiees;
    final idSource = chapitre.idSource;
    return liees != null && idSource != null && !liees.contains(idSource);
  }

  /// `true` si [chapitre] vient du site principal du titre (un chapitre sans
  /// site connu aussi, voir [estDeSiteRetire]). Toujours `false` si le site
  /// principal n'est pas connu.
  bool estDuSitePrincipal(Chapitre chapitre) {
    final principal = idSourcePrincipale;
    if (principal == null) return false;
    return chapitre.idSource == null || chapitre.idSource == principal;
  }

  /// Garde une version par numéro, triée par numéro croissant.
  ///
  /// Un numéro est considéré comme lu si **une** de ses versions est lue (le
  /// client a pu lire la version anglaise d'un chapitre aussi traduit en
  /// français).
  ///
  /// Les chapitres de numéro 0 (oneshots, chapitres sans numéro) ne sont pas
  /// regroupés : chacun est un chapitre distinct (décision du client), placé
  /// en tête dans l'ordre des identifiants.
  List<VersionRetenue> choisirVersions(List<Chapitre> chapitres) {
    final parNumero = <double, List<Chapitre>>{};
    final sansNumero = <Chapitre>[];
    for (final chapitre in chapitres) {
      if (chapitre.id == null) continue;
      if (chapitre.numero == 0) {
        sansNumero.add(chapitre);
      } else {
        parNumero
            .putIfAbsent(chapitre.numero, () => <Chapitre>[])
            .add(chapitre);
      }
    }
    sansNumero.sort((a, b) => a.id!.compareTo(b.id!));
    final numeros = parNumero.keys.toList()..sort();
    return <VersionRetenue>[
      for (final chapitre in sansNumero)
        VersionRetenue(chapitre: chapitre, versions: <Chapitre>[chapitre]),
      for (final numero in numeros)
        VersionRetenue(
          chapitre: _meilleureVersion(parNumero[numero]!),
          versions: parNumero[numero]!,
        ),
    ];
  }

  /// Langue normalisée d'un chapitre (minuscules, sans espaces), pour
  /// comparer deux versions.
  static String _langue(Chapitre chapitre) =>
      chapitre.langue.trim().toLowerCase();

  /// Doublons parmi les chapitres **téléchargés** : groupes d'au moins deux
  /// chapitres de même numéro et même langue (deux groupes de traduction,
  /// par exemple). Les oneshots (numéro 0) ne sont jamais des doublons
  /// entre eux. Les règles n'en suppriment aucun : c'est le client qui
  /// choisit.
  static List<List<Chapitre>> trouverDoublons(List<Chapitre> chapitres) {
    final groupes = <(double, String), List<Chapitre>>{};
    for (final chapitre in chapitres) {
      if (chapitre.id == null || !chapitre.estTelecharge) continue;
      if (chapitre.numero == 0) continue;
      groupes
          .putIfAbsent((chapitre.numero, _langue(chapitre)), () => <Chapitre>[])
          .add(chapitre);
    }
    final doublons =
        groupes.values.where((groupe) => groupe.length > 1).toList()
          ..sort((a, b) => a.first.numero.compareTo(b.first.numero));
    for (final groupe in doublons) {
      groupe.sort((a, b) => a.id!.compareTo(b.id!));
    }
    return doublons;
  }

  /// Rang de la langue de [chapitre] dans [languesPreferees] (0 = la
  /// préférée), ou `null` si elle n'en fait pas partie.
  ///
  /// Variantes régionales (tâche P3 : `pt-br`, `es-la`, `zh-hk`…), règle la
  /// plus prudente retenue :
  /// 1. **correspondance exacte** d'abord : un chapitre `pt-br` a le rang de
  ///    la préférence `pt-br`, un chapitre `pt` celui de la préférence `pt` ;
  /// 2. sinon, **même langue de base**, en repli : un chapitre `pt-br` pour
  ///    la préférence `pt` (comme le filtre des chapitres de MangaDex, qui
  ///    demande `pt` et `pt-br`), un chapitre `pt` pour la préférence
  ///    `pt-br`, un chapitre `es-la` pour la préférence `es`. Ce repli est
  ///    classé **après toutes les correspondances exactes**
  ///    (`languesPreferees.length` + rang de la préférence) : avec « pt-br,
  ///    en », une version anglaise passe avant une version `pt` du Portugal,
  ///    car le client a choisi exactement ces deux langues ;
  /// 3. une langue vide (inconnue : site d'une seule langue) ou une liste de
  ///    préférences vide est acceptée au tout dernier rang
  ///    (`2 × languesPreferees.length`).
  ///
  /// Une langue de base différente n'est jamais acceptée (pas de russe pour
  /// « fr,en »).
  int? rangLangue(Chapitre chapitre) {
    final langue = chapitre.langue.trim().toLowerCase();
    final nombre = languesPreferees.length;
    if (nombre == 0 || langue.isEmpty) {
      return 2 * nombre;
    }
    final exacte = languesPreferees.indexOf(langue);
    if (exacte >= 0) return exacte;
    final base = langueDeBase(langue);
    for (var i = 0; i < nombre; i++) {
      if (langueDeBase(languesPreferees[i]) == base) return nombre + i;
    }
    return null;
  }

  /// Langue de base d'un code de langue : `pt` pour `pt-br`, `es` pour
  /// `es-la`, le code lui-même (en minuscules, sans espaces) s'il n'a pas
  /// de variante régionale. Fonction pure.
  static String langueDeBase(String code) {
    final propre = code.trim().toLowerCase();
    final tiret = propre.indexOf('-');
    return tiret > 0 ? propre.substring(0, tiret) : propre;
  }

  /// `true` si les règles peuvent télécharger [chapitre] (langue choisie par
  /// le client, ou aucune langue choisie).
  bool estDansLesLangues(Chapitre chapitre) => rangLangue(chapitre) != null;

  /// `true` si les règles peuvent mettre [chapitre] en file : dans les
  /// langues du client ([estDansLesLangues]), hébergé par le site source
  /// (pas `Chapitre.estExterne`) et venant d'un site encore lié au titre
  /// ([estDeSiteRetire]).
  bool estTelechargeable(Chapitre chapitre) =>
      !chapitre.estExterne &&
      !estDeSiteRetire(chapitre) &&
      estDansLesLangues(chapitre);

  Chapitre _meilleureVersion(List<Chapitre> versions) {
    // Les langues absentes des préférences passent en dernier : cet ordre
    // sert à l'affichage (toutes les versions restent visibles) ; les règles
    // de téléchargement les écartent avant (voir [calculer]).
    // Au-delà du dernier rang accepté (`2 × languesPreferees.length`, voir
    // [rangLangue]).
    int rangLangue(Chapitre chapitre) =>
        this.rangLangue(chapitre) ?? 2 * languesPreferees.length + 1;
    // Groupe avant la langue : une version hébergée dans les langues du
    // client passe avant une version externe, même dans une langue préférée
    // (R4 : la version externe ne se lit pas dans l'application). Une
    // version externe dans ses langues passe encore avant une autre langue.
    // Un site retiré du titre passe en dernier, comme une autre langue : sa
    // version n'est plus suivie.
    int groupe(Chapitre chapitre) {
      if (this.rangLangue(chapitre) == null || estDeSiteRetire(chapitre)) {
        return 2;
      }
      return chapitre.estExterne ? 1 : 0;
    }

    final triees = List<Chapitre>.of(versions)
      ..sort((a, b) {
        final parGroupe = groupe(a).compareTo(groupe(b));
        if (parGroupe != 0) return parGroupe;
        final parLangue = rangLangue(a).compareTo(rangLangue(b));
        if (parLangue != 0) return parLangue;
        // Une version déjà téléchargée est préférée : inutile de la
        // remplacer par une autre traduction équivalente. Placé avant le
        // site principal : une version d'un site secondaire déjà sur
        // l'appareil n'est pas retéléchargée depuis le principal (elle
        // resterait sinon en double, affichée en orange).
        if (a.estTelecharge != b.estTelecharge) return a.estTelecharge ? -1 : 1;
        // Étape 8 : à égalité, la version du site principal (celui que le
        // client a choisi comme référence pour ce titre).
        final principalA = estDuSitePrincipal(a);
        if (principalA != estDuSitePrincipal(b)) return principalA ? -1 : 1;
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
      // Les téléchargements manuels sont conservés, sauf ceux d'un site
      // retiré du titre : le client a décidé de ne plus suivre ce site.
      final retires = _archivesDeSitesRetires(chapitres);
      return retires.isEmpty
          ? PlanTelechargement.vide
          : PlanTelechargement(
              idsVoulus: const <int>{},
              idsATelecharger: const <int>[],
              idsASupprimer: retires,
            );
    }
    // Toutes les versions servent à savoir ce qui est lu (le client a pu
    // lire en ligne un chapitre en russe) ; seules celles dans ses langues
    // et hébergées par le site peuvent être retenues (un numéro seulement
    // externe est ignoré, R4).
    final toutes = choisirVersions(chapitres);
    final versions = <VersionRetenue>[
      for (final numero in toutes)
        if (numero.versions.any(estTelechargeable))
          VersionRetenue(
            chapitre: _meilleureVersion(
              _candidates(numero, estFavori: estFavori),
            ),
            versions: numero.versions,
          ),
    ];
    // Dernier lu en numéro de chapitre, ramené aux positions retenues : lire
    // un numéro ignoré (autre langue) fait quand même avancer la fenêtre.
    double? numeroDernierLu;
    for (final numero in toutes) {
      if (numero.estLu) numeroDernierLu = numero.chapitre.numero;
    }
    final indexDernierLu = numeroDernierLu == null
        ? -1
        : versions.lastIndexWhere((v) => v.chapitre.numero <= numeroDernierLu!);

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
      final avant = _auMoins(reglages.suivisAvant, minimumSuivisAvantApres);
      final apres = _auMoins(reglages.suivisApres, minimumSuivisAvantApres);
      final initial = _positif(reglages.suivisInitial);
      // Fenêtre [debut, fin] en positions de chapitres (0 = premier).
      // Sans lecture : les `initial` premiers. Ensuite, la fenêtre glisse
      // dès que « dernier lu + après » dépasse la fenêtre initiale.
      final debut = indexDernierLu < 0
          ? 0
          : (indexDernierLu - avant + 1).clamp(0, versions.length);
      final finGlissante = indexDernierLu + apres;
      // Position absolue : la fenêtre initiale couvre toujours les chapitres
      // 1 à `initial`, elle ne se décale pas avec le début de la fenêtre.
      final finInitiale = initial - 1;
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
    // Numéros dont la version retenue est voulue mais pas encore sur
    // l'appareil : une autre version déjà téléchargée de ce numéro (par
    // exemple l'anglais, en attendant le français) est gardée jusqu'à ce que
    // la version retenue soit téléchargée, pour ne jamais laisser de trou.
    // Une version dans une langue non choisie n'est jamais gardée, même en
    // remplacement : le client ne veut pas la voir sur l'appareil.
    // Doublons : une autre version téléchargée de même langue qu'une version
    // retenue voulue (deux groupes de traduction) n'est jamais supprimée
    // automatiquement ; le client choisit laquelle garder.
    final gardes = <int>{};
    for (final version in versions) {
      if (!voulus.contains(version.chapitre.id)) continue;
      for (final autre in version.versions) {
        // Une version d'un site retiré n'est jamais gardée en remplacement
        // ni comme doublon : sa suppression suit la règle des 24 h.
        if (autre.id == version.chapitre.id ||
            !autre.estTelecharge ||
            !estDansLesLangues(autre) ||
            estDeSiteRetire(autre)) {
          continue;
        }
        if (!version.chapitre.estTelecharge ||
            _langue(autre) == _langue(version.chapitre)) {
          gardes.add(autre.id!);
        }
      }
    }
    // Un chapitre téléchargé puis devenu externe (l'éditeur a repris ses
    // droits) garde son archive : elle ne pourrait plus être retéléchargée.
    // Exception : un site retiré du titre par le client (étape 8).
    final aSupprimer = <int>[
      for (final chapitre in chapitres)
        if (chapitre.id != null &&
            chapitre.estTelecharge &&
            (!chapitre.estExterne || estDeSiteRetire(chapitre)) &&
            !voulus.contains(chapitre.id) &&
            !gardes.contains(chapitre.id))
          chapitre.id!,
    ];
    return PlanTelechargement(
      idsVoulus: voulus,
      idsATelecharger: aTelecharger,
      idsASupprimer: aSupprimer,
    );
  }

  /// Versions d'un numéro parmi lesquelles choisir la version retenue :
  /// celles dans les langues du client et hébergées par le site
  /// ([estTelechargeable]).
  ///
  /// Favori déjà lu : si une de ces versions est déjà téléchargée, seules
  /// les versions téléchargées sont candidates. Le client a fini ce
  /// chapitre : retélécharger le français pour remplacer l'anglais qu'il a
  /// déjà sur l'appareil (et lu) solliciterait le site pour rien.
  List<Chapitre> _candidates(VersionRetenue numero, {required bool estFavori}) {
    final dansLesLangues = numero.versions.where(estTelechargeable).toList();
    if (estFavori && numero.estLu) {
      final telechargees = dansLesLangues
          .where((version) => version.estTelecharge)
          .toList();
      if (telechargees.isNotEmpty) return telechargees;
    }
    return dansLesLangues;
  }

  /// Chapitres téléchargés venant d'un site retiré du titre.
  List<int> _archivesDeSitesRetires(List<Chapitre> chapitres) => <int>[
    for (final chapitre in chapitres)
      if (chapitre.id != null &&
          chapitre.estTelecharge &&
          estDeSiteRetire(chapitre))
        chapitre.id!,
  ];

  static int _positif(int valeur) => valeur < 0 ? 0 : valeur;

  static int _auMoins(int valeur, int minimum) =>
      valeur < minimum ? minimum : valeur;
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
