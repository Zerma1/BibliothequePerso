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

/// Onglet Mises à jour : un dernier chapitre non lu ne porte le badge
/// « Nouveau » que s'il est paru (ou, faute de date de publication, a été
/// découvert par l'application) depuis moins de cette durée. Sans cette
/// limite, un titre dont le dernier chapitre date de plusieurs années restait
/// « Nouveau » tant qu'il n'était pas lu (retour du client sur la
/// 0.2.0-test).
const Duration dureeNouveaute = Duration(days: 7);
