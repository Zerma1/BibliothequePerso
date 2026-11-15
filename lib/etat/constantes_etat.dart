/// Constantes propres à la couche `etat/` (PLAYBOOK.md section 9 : pas de
/// valeur magique).
library;

/// Délai entre la dernière frappe dans la recherche et le rechargement : on
/// évite une requête par lettre tapée.
const Duration delaiAvantRecherche = Duration(milliseconds: 300);
