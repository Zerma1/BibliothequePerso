/// Constantes propres à la couche `etat/` (PLAYBOOK.md section 9 : pas de
/// valeur magique).
library;

/// Délai entre la dernière frappe dans la recherche et le rechargement : on
/// évite une requête par lettre tapée.
const Duration delaiAvantRecherche = Duration(milliseconds: 300);

/// Lecteur : nombre de pages gardées en mémoire de part et d'autre de la page
/// courante. Au-delà, les octets sont oubliés (et relus dans l'archive si le
/// client revient en arrière) : un long chapitre ne remplit pas la mémoire.
const int margePagesEnMemoire = 5;

/// Ordinateur : intervalle du contrôle « une vérification est-elle due ? ».
/// Un `Timer` ne compte pas le temps passé en veille ; ce contrôle court
/// rattrape une échéance manquée peu après le réveil.
const Duration intervalleControleEcheance = Duration(minutes: 15);

/// Fiche d'un titre : rafraîchissement du compte à rebours des suppressions
/// prévues (affiché à la minute près).
const Duration intervalleCompteARebours = Duration(minutes: 1);

/// Paramètres, section « Journal » : nombre de jours du bouton « Exporter
/// les 7 derniers jours » (le bouton « du jour » en copie 1).
const int joursExportJournalSemaine = 7;

/// Navigateur intégré : nombre de caractères base64 rapatriés de la page par
/// appel de script. Une image de plusieurs Mo est ainsi transmise en
/// plusieurs fois, sans message géant entre la page et l'application.
const int tailleBlocBase64Navigateur = 1000000;

/// Navigateur intégré : largeur (en pixels de l'image) au-dessous de
/// laquelle une `<img>` n'est pas une page de chapitre (logo, icône,
/// bannière étroite).
const int largeurMinPageNavigateur = 300;

/// Navigateur intégré : hauteur (en pixels de l'image) au-dessous de
/// laquelle une `<img>` n'est pas une page de chapitre (bandeau, publicité).
const int hauteurMinPageNavigateur = 150;

/// Navigateur intégré : une image n'est retenue comme page que si sa largeur
/// atteint cette fraction de la plus large des pages (les pages d'un même
/// chapitre ont des largeurs voisines ; les miniatures sont écartées).
const double fractionLargeurPageNavigateur = 0.6;

/// Navigateur intégré : largeur affichée (pixels CSS) à partir de laquelle
/// une image pas encore chargée (chargement différé) est vue comme une page
/// manquante : l'enregistrement est alors refusé plutôt que d'enregistrer un
/// chapitre incomplet.
const double largeurAfficheeMinPageNavigateur = 200;
