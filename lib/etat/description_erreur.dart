/// Classement des erreurs pour l'interface, et résultat d'une action.
///
/// Une erreur d'un site, de la base ou du service ne doit jamais faire planter
/// l'interface (PLAYBOOK.md section 6) : les états l'attrapent et la
/// transforment en [DescriptionErreur]. Le texte affiché est construit par
/// `Textes.messageErreur` (lib/widgets/textes.dart), seul endroit qui contient
/// les textes de l'interface.
library;

import 'package:flutter/foundation.dart';

import '../modeles/erreur_base_de_donnees.dart';
import '../services/erreur_service.dart';
// EXCEPTION À LA RÈGLE DES COUCHES (etat → services seulement) : l'état doit
// reconnaître l'erreur levée par les sites, qui traverse les services sans
// être convertie (voir ServiceBibliotheque.ajouterTitreDepuisUrl et le
// rapport de ServiceMisesAJour). Ce fichier est le SEUL de lib/etat/ à
// importer lib/sources/ ; les autres états passent par [DescriptionErreur]
// ou [estErreurDeSite]. À retirer quand les services exposeront eux-mêmes
// un indicateur « erreur du site ».
import '../sources/erreur_source.dart';

/// Famille d'une erreur, qui détermine le message affiché.
enum NatureErreur {
  /// Le site n'a pas pu être lu (réseau, code HTTP, adresse invalide…).
  site,

  /// La base de données locale a refusé l'opération.
  baseDeDonnees,

  /// Refus métier du service (site non configuré…), message déjà lisible.
  refus,

  /// Le client n'a pas saisi d'adresse.
  adresseVide,

  /// L'élément demandé n'existe plus dans la bibliothèque.
  introuvable,

  /// Le client n'a pas saisi de nom (modification d'un site).
  nomVide,

  /// Suppression d'un site refusée : des titres en viennent encore. Le
  /// [DescriptionErreur.detail] contient leur nombre.
  siteAvecTitres,

  /// Erreur imprévue (bogue) : affichée sans faire planter l'application.
  inattendue,
}

/// Erreur prête à être affichée : sa [nature] et le [detail] en français
/// fourni par la couche qui l'a levée.
class DescriptionErreur {
  /// Crée une description.
  const DescriptionErreur(this.nature, {this.detail = ''});

  /// Classe une erreur attrapée par un état.
  ///
  /// Les erreurs du projet portent déjà un message en français : on le garde
  /// comme [detail]. Une erreur inconnue est journalisée avec sa [pile] pour
  /// pouvoir la corriger, puis affichée sans planter.
  factory DescriptionErreur.depuis(Object erreur, [StackTrace? pile]) {
    if (erreur is ErreurSource) {
      return DescriptionErreur(NatureErreur.site, detail: erreur.message);
    }
    if (erreur is ErreurBaseDeDonnees) {
      return DescriptionErreur(
        NatureErreur.baseDeDonnees,
        detail: erreur.message,
      );
    }
    if (erreur is ErreurService) {
      return DescriptionErreur(NatureErreur.refus, detail: erreur.message);
    }
    debugPrint("Erreur inattendue dans l'interface : $erreur\n$pile");
    return DescriptionErreur(
      NatureErreur.inattendue,
      detail: erreur.toString(),
    );
  }

  /// Famille de l'erreur.
  final NatureErreur nature;

  /// Précision en français venant de la couche d'origine (peut être vide).
  final String detail;

  @override
  String toString() => 'DescriptionErreur(${nature.name}, $detail)';
}

/// `true` si [erreur] vient d'un site (réseau, code HTTP, page illisible),
/// et non de la base ou d'un refus du service.
///
/// Seul point de lib/etat/ qui connaît `ErreurSource` (voir l'exception
/// documentée sur les imports de ce fichier).
bool estErreurDeSite(Object? erreur) => erreur is ErreurSource;

/// Résultat d'une action déclenchée par le client (ajout, actualisation…).
///
/// Une action réussie porte sa [donnee] ; une action échouée, son [erreur].
class ResultatAction<T> {
  /// Action réussie.
  const ResultatAction.reussite(T this.donnee) : erreur = null;

  /// Action échouée.
  const ResultatAction.echec(DescriptionErreur this.erreur) : donnee = null;

  /// Valeur produite par l'action réussie.
  final T? donnee;

  /// Erreur de l'action échouée.
  final DescriptionErreur? erreur;

  /// `true` si l'action a réussi.
  bool get estReussi => erreur == null;
}

/// Base commune des états : ignore les notifications après `dispose`.
///
/// Une requête lente (réseau, base) peut se terminer après la fermeture de
/// l'écran ; notifier un ChangeNotifier libéré lèverait une erreur.
abstract class EtatNotifiant extends ChangeNotifier {
  bool _estLibere = false;

  /// `true` après `dispose`.
  bool get estLibere => _estLibere;

  /// Notifie les écouteurs si l'état est encore utilisé.
  @protected
  void notifier() {
    if (!_estLibere) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _estLibere = true;
    super.dispose();
  }
}
