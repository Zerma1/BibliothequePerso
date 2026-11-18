/// Règles des listes système de l'étape 6 (« Planifié » et « En attente »)
/// et de « Terminés » (migration 11).
///
/// Calcul pur (aucune base, aucun réseau) : `ServiceBibliotheque` et
/// `ServiceMisesAJour` l'appliquent ensuite.
library;

import '../modeles/chapitre.dart';
import '../modeles/constantes.dart';
import 'politique_telechargement.dart';

/// Classement automatique et annonces des mises à jour.
abstract final class ClassementListes {
  /// Listes qui rendent un titre « surveillé » : seuls leurs titres peuvent
  /// passer dans « En attente » (décision de l'étape 6).
  static const Set<String> listesSurveillees = <String>{
    nomListeFavoris,
    nomListeSuivis,
    nomListePlanifie,
  };

  /// Listes dont les nouveautés sont annoncées dans les bilans et
  /// notifications. « Planifié » n'en fait pas partie : le client prévoit de
  /// lire ces titres plus tard et ne veut pas en être averti.
  static const Set<String> listesAnnoncees = <String>{
    nomListeFavoris,
    nomListeSuivis,
  };

  /// Listes dont les titres sont vérifiés par la vérification complète
  /// (hors « Archive complète », qui vérifie toute la bibliothèque) :
  /// listes surveillées, « En attente » et « Terminés ».
  ///
  /// « Favoris » est indispensable : un titre peut n'être que favori (sans
  /// être aussi suivi) et doit quand même recevoir ses nouveaux chapitres.
  ///
  /// « Terminés » (décision de l'orchestrateur du 2026-11-18) est vérifiée
  /// comme « Planifié », en silence : ni annoncée ([listesAnnoncees]), ni
  /// téléchargée automatiquement (seuls favoris et suivis le sont, hors
  /// archive complète), ni dans « En attente » (absente de
  /// [listesSurveillees] : un titre terminé n'a rien à attendre). Le client
  /// garde ainsi la fiche à jour d'un titre fini.
  static const List<String> listesVerifiees = <String>[
    nomListeFavoris,
    nomListeSuivis,
    nomListePlanifie,
    nomListeEnAttente,
    nomListeTermines,
  ];

  /// Listes que le client ne peut pas modifier à la main : « En attente »
  /// est entièrement tenue par l'application.
  ///
  /// « Terminés » n'en fait pas partie : le client y range ses titres
  /// lui-même, et y ajouter un titre ne le retire d'aucune autre liste (un
  /// titre à la fois « Suivis » et « Terminés » reste annoncé et téléchargé
  /// comme un suivi : c'est au client de le retirer de « Suivis »).
  static const Set<String> listesAutomatiques = <String>{nomListeEnAttente};

  /// `true` si au moins un des [chapitres] est lisible dans les [langues] du
  /// client (même règle que les téléchargements : variante régionale
  /// acceptée, langue vide d'un site d'une seule langue acceptée).
  ///
  /// Un chapitre hébergé sur un site externe (`Chapitre.estExterne`) compte :
  /// il est paru et le client peut le lire chez l'éditeur, le titre n'est
  /// donc pas « en attente » même s'il n'a rien à télécharger (R4).
  static bool aChapitreDansLesLangues(
    Iterable<Chapitre> chapitres,
    List<String> langues,
  ) {
    final politique = PolitiqueTelechargement(languesPreferees: langues);
    // `estDansLesLangues` et non `estTelechargeable` : voir ci-dessus.
    return chapitres.any(politique.estDansLesLangues);
  }

  /// `true` si un titre des listes [nomsListes] doit être dans « En
  /// attente » : il est favori, suivi ou planifié, et n'a encore aucun
  /// chapitre dans les langues du client ([aChapitreDansLesLangues]).
  static bool doitEtreEnAttente({
    required Set<String> nomsListes,
    required bool aChapitreDansLesLangues,
  }) => !aChapitreDansLesLangues && nomsListes.any(listesSurveillees.contains);

  /// `true` si les nouveautés d'un titre des listes [nomsListes] sont
  /// annoncées (favori ou suivi). Un titre seulement planifié (même « En
  /// attente ») est vérifié en silence.
  static bool estAnnonce(Set<String> nomsListes) =>
      nomsListes.any(listesAnnoncees.contains);
}
