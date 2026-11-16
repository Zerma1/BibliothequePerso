/// Outils partagés par les états qui affichent des chapitres : regroupement
/// des versions par numéro et état hors-ligne d'un chapitre.
///
/// Les langues à appliquer viennent du service
/// (`ServiceBibliotheque.languesPourTitre` : titre, puis site, puis réglage
/// général), pour que l'interface mette en avant la version que le service
/// télécharge.
library;

import '../modeles/chapitre.dart';
import '../modeles/telechargement.dart';
import '../services/politique_telechargement.dart';

/// Toutes les versions d'un même numéro de chapitre (un oneshot forme
/// toujours son propre groupe).
class GroupeChapitres {
  /// Crée le groupe.
  const GroupeChapitres({required this.retenu, required this.autres});

  /// Version mise en avant : celle que le service télécharge (langue
  /// préférée du site).
  final Chapitre retenu;

  /// Autres versions du même numéro (autres langues, autres groupes).
  final List<Chapitre> autres;

  /// Numéro commun aux versions.
  double get numero => retenu.numero;

  /// Toutes les versions, la version retenue d'abord.
  List<Chapitre> get versions => <Chapitre>[retenu, ...autres];

  /// `true` si une des versions est lue (même règle que le service).
  bool get estLu => versions.any((chapitre) => chapitre.estLu);

  /// Première version téléchargée (la retenue si elle l'est), ou `null`.
  Chapitre? get versionTelechargee {
    for (final chapitre in versions) {
      if (chapitre.estTelecharge) return chapitre;
    }
    return null;
  }

  /// Version à ouvrir dans le lecteur : une version téléchargée si possible,
  /// sinon la version retenue.
  Chapitre get versionALire => versionTelechargee ?? retenu;

  /// `true` si toutes les versions sont hébergées sur un site externe :
  /// ce numéro ne se lit pas dans l'application (PLAYBOOK.md section 10).
  bool get estExterne => versions.every((chapitre) => chapitre.estExterne);

  /// Version que le lecteur peut ouvrir : une version téléchargée, sinon la
  /// retenue si elle est hébergée par le site source, sinon une autre
  /// version hébergée ; `null` si toutes sont externes.
  Chapitre? get versionLisible {
    final telechargee = versionTelechargee;
    if (telechargee != null && !telechargee.estExterne) return telechargee;
    for (final chapitre in versions) {
      if (!chapitre.estExterne) return chapitre;
    }
    return null;
  }
}

/// Regroupe [chapitres] par numéro, du plus petit au plus grand.
///
/// La version retenue est choisie par `PolitiqueTelechargement` (même règle
/// que les téléchargements automatiques) ; les autres versions suivent, la
/// plus récemment enregistrée d'abord.
List<GroupeChapitres> regrouperParNumero(
  List<Chapitre> chapitres,
  List<String> langues,
) {
  final politique = PolitiqueTelechargement(languesPreferees: langues);
  return <GroupeChapitres>[
    for (final version in politique.choisirVersions(chapitres))
      GroupeChapitres(
        retenu: version.chapitre,
        autres:
            version.versions
                .where((chapitre) => chapitre.id != version.chapitre.id)
                .toList()
              ..sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0)),
      ),
  ];
}

/// État hors-ligne d'un chapitre, tel que montré au client.
enum StatutHorsLigne {
  /// Archive présente sur l'appareil : le lecteur peut l'ouvrir.
  telecharge,

  /// Dans la file, pas encore commencé.
  enFile,

  /// Téléchargement en cours (voir la progression).
  enCours,

  /// Le dernier téléchargement a échoué.
  echec,

  /// Seulement listé : rien sur l'appareil.
  nonTelecharge,

  /// Hébergé sur un site externe (site de l'éditeur) : jamais téléchargé,
  /// il se lit sur ce site.
  externe,
}

/// État hors-ligne d'un chapitre et progression éventuelle.
class EtatHorsLigne {
  /// Crée l'état.
  const EtatHorsLigne(
    this.statut, {
    this.progression,
    this.messageErreur,
    this.dateSuppressionPrevue,
    this.estDoublon = false,
  });

  /// Chapitre seulement listé.
  static const EtatHorsLigne nonTelecharge = EtatHorsLigne(
    StatutHorsLigne.nonTelecharge,
  );

  /// Chapitre hébergé sur un site externe.
  static const EtatHorsLigne externe = EtatHorsLigne(StatutHorsLigne.externe);

  /// Statut affiché.
  final StatutHorsLigne statut;

  /// Progression entre 0 et 1 pendant un téléchargement, `null` si inconnue.
  final double? progression;

  /// Cause de l'échec, si [statut] vaut [StatutHorsLigne.echec].
  final String? messageErreur;

  /// Date (UTC) à laquelle les règles de conservation supprimeront
  /// l'archive (suppression différée de 24 heures), ou `null`.
  final DateTime? dateSuppressionPrevue;

  /// `true` si l'archive est un doublon (même numéro et même langue qu'une
  /// autre archive du titre) : le client choisit laquelle garder.
  final bool estDoublon;

  /// `true` si une suppression automatique est prévue pour l'archive.
  bool get aSuppressionPrevue =>
      statut == StatutHorsLigne.telecharge && dateSuppressionPrevue != null;

  /// Temps restant avant la suppression prévue à l'instant [maintenant]
  /// (jamais négatif), ou `null` si aucune suppression n'est prévue.
  Duration? tempsAvantSuppression(DateTime maintenant) {
    final date = dateSuppressionPrevue;
    if (!aSuppressionPrevue || date == null) return null;
    final reste = date.difference(maintenant);
    return reste.isNegative ? Duration.zero : reste;
  }

  /// Calcule l'état d'un [chapitre] à partir de sa ligne de file
  /// [telechargement] (ou `null` s'il n'est pas dans la file).
  /// [estDoublon] vient de `ServiceTelechargement.chargerDoublons`.
  factory EtatHorsLigne.depuis(
    Chapitre chapitre,
    Telechargement? telechargement, {
    bool estDoublon = false,
  }) {
    // Un chapitre externe n'a ni archive ni file : il passe avant tout le
    // reste pour que l'interface ne propose jamais de le télécharger.
    if (chapitre.estExterne) return externe;
    if (chapitre.estTelecharge) {
      return EtatHorsLigne(
        StatutHorsLigne.telecharge,
        dateSuppressionPrevue: chapitre.dateSuppressionPrevue,
        estDoublon: estDoublon,
      );
    }
    switch (telechargement?.statut) {
      case null:
        return nonTelecharge;
      case StatutTelechargement.enAttente:
        return const EtatHorsLigne(StatutHorsLigne.enFile);
      case StatutTelechargement.enCours:
        return EtatHorsLigne(
          StatutHorsLigne.enCours,
          progression: telechargement!.progression,
        );
      case StatutTelechargement.echec:
        return EtatHorsLigne(
          StatutHorsLigne.echec,
          messageErreur: telechargement!.messageErreur,
        );
      case StatutTelechargement.termine:
        // La base marque le chapitre téléchargé dans la même transaction :
        // ce cas ne se voit que le temps de relire les chapitres.
        return const EtatHorsLigne(StatutHorsLigne.telecharge);
    }
  }
}
