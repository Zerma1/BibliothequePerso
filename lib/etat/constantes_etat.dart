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
