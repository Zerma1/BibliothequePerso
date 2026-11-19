// Partie de la bibliothèque `service_telechargement.dart` : les
// enregistrements faits depuis le navigateur intégré écrivent des archives
// dans le même dossier que la file, et doivent respecter la même pause
// pendant un changement du dossier des chapitres.
part of 'service_telechargement.dart';

/// Enregistrements de chapitres depuis le navigateur intégré
/// (`ServiceLectureWeb.enregistrerImagesChapitre`), coordonnés avec la file
/// de téléchargement et le changement du dossier des chapitres.
///
/// Extension plutôt que méthodes de [ServiceTelechargement] : les faux
/// services des tests de l'interface (`implements ServiceTelechargement`)
/// restent valables sans changement.
extension EnregistrementsWebTelechargement on ServiceTelechargement {
  /// Nombre d'enregistrements depuis le navigateur en cours d'écriture
  /// ([executerEnregistrementWeb]). Tant qu'il n'est pas nul,
  /// `ServiceDossierChapitres.changerDossierChapitres` (avec déplacement)
  /// est refusé, comme pendant un téléchargement.
  int get nombreEnregistrementsWebEnCours => _enregistrementsWebEnCours;

  /// Exécute [ecrire] (écriture d'une archive puis de la base) en le
  /// comptant dans [nombreEnregistrementsWebEnCours], et renvoie son
  /// résultat.
  ///
  /// Lève une [ErreurService] au message clair, **sans appeler** [ecrire] :
  /// - changement du dossier des chapitres en cours, ou file en pause pour
  ///   ce changement (l'archive serait écrite pendant la copie, ou dans un
  ///   dossier qui va être quitté) ;
  /// - dossier changé pendant cette session (redémarrage nécessaire) ;
  /// - déplacement des archives resté inachevé.
  ///
  /// Le contrôle et le comptage sont faits sans `await` entre eux : un
  /// changement de dossier demandé ensuite voit forcément cet
  /// enregistrement.
  Future<T> executerEnregistrementWeb<T>(Future<T> Function() ecrire) async {
    _verifierEnregistrementWebPossible();
    // Lecture en base (repère posé par cet isolat ou par l'autre) : même
    // contrôle que la file avant chaque chapitre.
    if (await _deplacementInacheve()) {
      throw const ErreurService(
        'Un déplacement des chapitres vers un autre dossier est resté '
        'inachevé : reprenez-le ou abandonnez-le dans les Paramètres avant '
        "d'enregistrer un chapitre.",
      );
    }
    // Redit après l'`await` : un changement a pu commencer entre-temps.
    _verifierEnregistrementWebPossible();
    _enregistrementsWebEnCours++;
    try {
      return await ecrire();
    } finally {
      _enregistrementsWebEnCours--;
    }
  }

  void _verifierEnregistrementWebPossible() {
    if (_dossierChange) {
      throw const ErreurService(
        'Le dossier des chapitres vient de changer : redémarrez '
        "l'application avant d'enregistrer un chapitre.",
      );
    }
    if (_changementDossierEnCours || _enPause) {
      throw const ErreurService(
        'Le dossier des chapitres est en train de changer : enregistrez ce '
        'chapitre une fois le changement terminé.',
      );
    }
  }

  /// Après un enregistrement réussi depuis le navigateur : retire de la file
  /// la ligne « en attente » de ce chapitre (il est déjà téléchargé, la
  /// file le retéléchargerait pour rien sous le même nom d'archive).
  ///
  /// Une ligne d'un autre statut n'est pas touchée : « en cours » se
  /// termine (ou s'arrête) normalement, « terminé » et « échec » restent
  /// visibles dans l'onglet Téléchargements. Renvoie `true` si une ligne a
  /// été retirée. Peut lever une erreur de base.
  ///
  /// LIMITE : `DepotTelechargements` n'offre pas de suppression
  /// conditionnelle (`… AND statut = 'en_attente'`). Si la file réserve
  /// cette ligne entre la lecture et la suppression (quelques
  /// millisecondes), ce téléchargement est annulé comme si le client
  /// l'avait retiré de la file (arrêt à la page suivante, archive partielle
  /// effacée). Une suppression conditionnelle dans le dépôt fermerait
  /// cette fenêtre.
  Future<bool> retirerAttenteApresEnregistrementWeb(int idChapitre) async {
    final ligne = await _depotTelechargements.chargerParChapitre(idChapitre);
    final id = ligne?.id;
    if (ligne == null ||
        id == null ||
        ligne.statut != StatutTelechargement.enAttente) {
      return false;
    }
    final retiree = await _depotTelechargements.supprimerTelechargement(id);
    if (retiree) {
      Journal.actuel.info(
        CategorieJournal.telechargement,
        'Chapitre n°$idChapitre retiré de la file (enregistré depuis le '
        'navigateur)',
      );
      _signaler();
    }
    return retiree;
  }
}
