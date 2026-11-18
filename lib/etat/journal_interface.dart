/// Notes de l'interface dans le journal de l'application.
///
/// Les écrans et widgets n'importent que `lib/etat/` (PLAYBOOK.md
/// section 4) : ces deux fonctions leur donnent accès au journal
/// (`Journal.actuel`, défini dans `lib/modeles/journal.dart`).
///
/// L'interface n'écrit que ce que les services ne voient pas : navigation,
/// ouverture d'une fiche ou du lecteur, lien externe impossible à ouvrir.
/// Les ajouts, suppressions et réglages sont déjà notés par les services.
library;

import '../modeles/journal.dart';

/// Note une action du client que les services ne voient pas (changement
/// d'onglet…). Ne lève jamais d'exception.
void noterActionInterface(String message) {
  Journal.actuel.info(CategorieJournal.interface, message);
}

/// Note un problème sans gravité survenu dans l'interface (lien externe
/// impossible à ouvrir…), avec l'[erreur] d'origine si elle existe. Ne lève
/// jamais d'exception.
void noterProblemeInterface(String message, {Object? erreur}) {
  Journal.actuel.avertissement(
    CategorieJournal.interface,
    message,
    erreur: erreur,
  );
}
