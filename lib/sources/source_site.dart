/// Interface commune des adaptateurs de sites (PLAYBOOK.md section 6).
library;

import '../modeles/chapitre.dart';
import '../modeles/contenu_chapitre.dart';
import '../modeles/fiche_titre.dart';
import '../modeles/titre.dart';

/// Lecture d'un site de lecture : recherche, fiche, chapitres et contenu.
///
/// Chaque thème de site (MangaDex, Madara…) a son implémentation, enregistrée
/// dans `FabriqueSources`. Les objets renvoyés ont `id`, `idSource` et
/// `idTitre` à `null` : c'est le service qui les complète avant
/// l'enregistrement. Toute erreur lève une `ErreurSource` ; une liste vide
/// signifie « vraiment aucun résultat », jamais « échec ».
abstract class SourceSite {
  /// Recherche des titres sur le site à partir du texte [requete].
  Future<List<Titre>> rechercher(String requete);

  /// Récupère la fiche complète (titre et catégories) de [urlTitre].
  Future<FicheTitre> recupererFiche(String urlTitre);

  /// Récupère la liste de tous les chapitres de [urlTitre].
  Future<List<Chapitre>> recupererChapitres(String urlTitre);

  /// Récupère le contenu (URLs d'images ou texte) de [urlChapitre].
  Future<ContenuChapitre> recupererContenu(String urlChapitre);
}
