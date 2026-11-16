/// Constantes partagées par toutes les couches (PLAYBOOK.md section 9 : pas de
/// valeur magique dans le code).
library;

/// Nom de la liste système « Favoris », créée par la migration 1.
///
/// ATTENTION : la migration 1 écrit cette valeur en dur. La modifier ici ne
/// renomme pas la liste en base : un renommage passe par une nouvelle
/// migration (et la mise à jour de cette constante).
const String nomListeFavoris = 'Favoris';

/// Nom de la liste système « Suivis », créée par la migration 1.
///
/// Même contrainte que [nomListeFavoris].
const String nomListeSuivis = 'Suivis';

/// Position d'affichage de la liste « Favoris » (la première).
const int ordreListeFavoris = 0;

/// Position d'affichage de la liste « Suivis » (juste après « Favoris »).
const int ordreListeSuivis = 1;

/// Nom de la liste système « Planifié » (titres que le client prévoit de
/// lire), créée par la migration 5.
///
/// Ses titres sont vérifiés comme les autres, mais n'apparaissent jamais
/// dans les bilans ni les notifications de mises à jour. Même contrainte que
/// [nomListeFavoris] : la migration 5 écrit cette valeur en dur.
const String nomListePlanifie = 'Planifié';

/// Nom de la liste système automatique « En attente », créée par la
/// migration 5 : titres suivis, favoris ou planifiés qui n'ont encore aucun
/// chapitre dans les langues du client.
///
/// Même contrainte que [nomListeFavoris].
const String nomListeEnAttente = 'En attente';

/// Position d'affichage de la liste « Planifié » (après « Suivis »).
const int ordreListePlanifie = 2;

/// Position d'affichage de la liste « En attente » (après « Planifié »).
const int ordreListeEnAttente = 3;

/// Niveau de contenu MangaDex « safe » (tous publics).
///
/// Les niveaux sont stockés tels que MangaDex les nomme (`contentRating`,
/// colonne `titres.niveau_contenu`) : ce sont des valeurs d'une API externe,
/// pas des identifiants du projet.
const String niveauContenuTousPublics = 'safe';

/// Niveau de contenu MangaDex « suggestive » (suggestif).
const String niveauContenuSuggestif = 'suggestive';

/// Niveau de contenu MangaDex « erotica » (érotique).
const String niveauContenuErotique = 'erotica';

/// Niveau de contenu MangaDex « pornographic » (pornographique).
const String niveauContenuPornographique = 'pornographic';

/// Tous les niveaux de contenu connus, du plus sage au plus explicite.
const List<String> niveauxContenu = <String>[
  niveauContenuTousPublics,
  niveauContenuSuggestif,
  niveauContenuErotique,
  niveauContenuPornographique,
];

/// Niveaux affichés par défaut dans la bibliothèque (décision du
/// 2026-11-15) : tout sauf [niveauContenuPornographique].
const List<String> niveauxContenuParDefaut = <String>[
  niveauContenuTousPublics,
  niveauContenuSuggestif,
  niveauContenuErotique,
];

/// Nom du fichier SQLite de l'application.
const String nomFichierBaseDeDonnees = 'bibliotheque_perso.db';

/// Nom du dossier racine par défaut des téléchargements, placé dans le dossier
/// documents de l'application (PLAYBOOK.md section 5).
const String nomDossierRacineTelechargements = 'bibliotheque_perso';

/// Valeur entière qui représente `true` dans une colonne booléenne SQLite.
const int valeurSqlVrai = 1;

/// Valeur entière qui représente `false` dans une colonne booléenne SQLite.
const int valeurSqlFaux = 0;

/// Nombre maximal de paramètres `?` utilisés dans une seule requête `IN (…)`.
///
/// Les anciennes versions de SQLite (encore présentes sur certains Android)
/// limitent une requête à 999 paramètres : on découpe donc les listes longues.
const int tailleMaxLotParametresSql = 500;
