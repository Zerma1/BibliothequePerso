/// Constantes propres à la couche `etat/` (PLAYBOOK.md section 9 : pas de
/// valeur magique).
library;

/// Délai entre la dernière frappe dans la recherche et le rechargement : on
/// évite une requête par lettre tapée.
const Duration delaiAvantRecherche = Duration(milliseconds: 300);

/// Intervalle entre deux recherches automatiques de nouveaux chapitres sur
/// Windows et Linux, tant que l'application est ouverte (PLAYBOOK.md
/// section 7). Sur Android, c'est workmanager qui planifie la tâche.
const Duration intervalleMisesAJourBureau = Duration(hours: 6);
