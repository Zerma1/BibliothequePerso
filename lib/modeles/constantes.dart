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
