/// Valeurs échangées avec l'interface au sujet du dossier des chapitres
/// téléchargés (dossier choisi par le client : disque local, lecteur réseau,
/// NAS) : état d'accès pour le bandeau « dossier inaccessible » et résultat
/// d'un changement de dossier.
library;

import '../donnees/erreur_stockage.dart';
import '../donnees/stockage_telechargements.dart';

/// État d'accès au dossier des chapitres, pour le bandeau d'interface.
///
/// Un dossier inaccessible (NAS éteint, lecteur réseau déconnecté, support
/// débranché) ne veut **pas** dire que les archives sont perdues : la base
/// n'est pas modifiée et la file de téléchargement attend son retour.
class AccesDossierChapitres {
  /// Dossier joignable.
  const AccesDossierChapitres.accessible(
    this.chemin, {
    required this.estPersonnalise,
  }) : estAccessible = true,
       nature = null;

  /// Dossier injoignable, avec la [nature] du problème
  /// ([NatureErreurStockage.dossierInaccessible] si elle est inconnue).
  const AccesDossierChapitres.inaccessible(
    this.chemin, {
    required this.estPersonnalise,
    NatureErreurStockage this.nature = NatureErreurStockage.dossierInaccessible,
  }) : estAccessible = false;

  /// `true` si le dossier est joignable (aucun bandeau à afficher).
  final bool estAccessible;

  /// Chemin du dossier des chapitres utilisé pendant cette session.
  final String chemin;

  /// `true` si le dossier a été choisi par le client (sinon dossier par
  /// défaut de l'application).
  final bool estPersonnalise;

  /// Nature du problème si le dossier est inaccessible, sinon `null`.
  final NatureErreurStockage? nature;

  /// Message à afficher dans le bandeau, ou `null` si le dossier est
  /// accessible.
  String? get message {
    final probleme = nature;
    if (estAccessible || probleme == null) return null;
    // L'explication de la nature commence par une minuscule et finit par un
    // point : elle se lit à la suite de « inaccessible : ».
    final explication = probleme == NatureErreurStockage.autre
        ? NatureErreurStockage.dossierInaccessible.explication
        : probleme.explication;
    return 'Le dossier des chapitres ($chemin) est inaccessible : '
        '$explication Les chapitres déjà téléchargés ne sont pas perdus : '
        'ils redeviendront lisibles, et les téléchargements reprendront, dès '
        "qu'il sera de nouveau accessible.";
  }

  @override
  bool operator ==(Object other) =>
      other is AccesDossierChapitres &&
      other.estAccessible == estAccessible &&
      other.chemin == chemin &&
      other.estPersonnalise == estPersonnalise &&
      other.nature == nature;

  @override
  int get hashCode =>
      Object.hash(estAccessible, chemin, estPersonnalise, nature);

  @override
  String toString() => estAccessible
      ? 'AccesDossierChapitres(accessible, $chemin)'
      : 'AccesDossierChapitres(inaccessible : ${nature?.name}, $chemin)';
}

/// Résultat d'un changement du dossier des chapitres
/// (`ServiceDossierChapitres.changerDossierChapitres`).
///
/// Le nouveau dossier ne s'applique qu'**au prochain démarrage** de
/// l'application : d'ici là, la file de téléchargement reste en pause (les
/// services de cette session écrivent encore dans l'ancien dossier).
class ResultatChangementDossier {
  /// Crée le résultat.
  const ResultatChangementDossier({
    required this.dossierChoisi,
    required this.cheminDossier,
    this.bilan,
  });

  /// Dossier enregistré dans les réglages, ou `null` pour le dossier par
  /// défaut de l'application.
  final String? dossierChoisi;

  /// Chemin complet du dossier qui sera utilisé au prochain démarrage.
  final String cheminDossier;

  /// Bilan du déplacement des archives, ou `null` si le client a choisi de
  /// ne pas déplacer les chapitres déjà téléchargés.
  final BilanDeplacement? bilan;

  /// `true` si les archives ont été déplacées vers le nouveau dossier.
  bool get archivesDeplacees => bilan != null;

  /// Toujours `true` : le nouveau dossier ne s'applique qu'au prochain
  /// démarrage de l'application (plus simple et plus sûr que de
  /// reconstruire les services pendant qu'ils tournent).
  bool get redemarrageNecessaire => true;

  /// Message de confirmation à afficher au client.
  String get message {
    final deplacement = bilan;
    final debut = deplacement == null
        ? 'Le dossier des chapitres sera « $cheminDossier ». Les chapitres '
              "déjà téléchargés restent dans l'ancien dossier : ceux que vos "
              'règles demandent seront retéléchargés dans le nouveau.'
        : 'Chapitres déplacés vers « $cheminDossier » '
              '(${deplacement.nombreFichiers} fichier(s)).';
    return '$debut Redémarrez l\'application pour utiliser ce dossier ; '
        "d'ici là, les téléchargements sont en pause.";
  }

  @override
  String toString() =>
      'ResultatChangementDossier($cheminDossier, choisi : $dossierChoisi, '
      'bilan : $bilan)';
}
