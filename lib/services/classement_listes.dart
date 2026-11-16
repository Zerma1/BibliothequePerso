/// Règles des listes système de l'étape 6 (« Planifié » et « En attente »).
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

  /// Listes que le client ne peut pas modifier à la main : « En attente »
  /// est entièrement tenue par l'application.
  static const Set<String> listesAutomatiques = <String>{nomListeEnAttente};

  /// `true` si au moins un des [chapitres] est lisible dans les [langues] du
  /// client (même règle que les téléchargements : variante régionale
  /// acceptée, langue vide d'un site d'une seule langue acceptée).
  static bool aChapitreDansLesLangues(
    Iterable<Chapitre> chapitres,
    List<String> langues,
  ) {
    final politique = PolitiqueTelechargement(languesPreferees: langues);
    return chapitres.any(politique.estDansLesLangues);
  }

  /// `true` si un titre des listes [nomsListes] doit être dans « En
  /// attente » : il est favori, suivi ou planifié, et n'a encore aucun
  /// chapitre dans les langues du client ([aChapitreDansLesLangues]).
  static bool doitEtreEnAttente({
    required Set<String> nomsListes,
    required bool aChapitreDansLesLangues,
  }) =>
      !aChapitreDansLesLangues &&
      nomsListes.any(listesSurveillees.contains);

  /// `true` si les nouveautés d'un titre des listes [nomsListes] sont
  /// annoncées (favori ou suivi). Un titre seulement planifié (même « En
  /// attente ») est vérifié en silence.
  static bool estAnnonce(Set<String> nomsListes) =>
      nomsListes.any(listesAnnoncees.contains);
}
