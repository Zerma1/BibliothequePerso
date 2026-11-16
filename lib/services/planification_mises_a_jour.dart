/// Horaires des recherches de mises à jour : N vérifications par jour,
/// réparties régulièrement à partir de 00:00 UTC (choix du client).
///
/// Par défaut 2 par jour : 00:00 et 12:00 UTC. Peu de requêtes vers les
/// sites (PLAYBOOK.md section 10), et des horaires identiques sur tous les
/// appareils.
library;

/// Calcul pur des échéances (aucun minuteur, aucune base).
class PlanificationMisesAJour {
  /// Crée la planification pour [verificationsParJour] (ramené entre
  /// [minimumParJour] et [maximumParJour]).
  PlanificationMisesAJour(int verificationsParJour)
    : verificationsParJour = verificationsParJour.clamp(
        minimumParJour,
        maximumParJour,
      );

  /// Valeur par défaut choisie par le client : 00:00 et 12:00 UTC.
  static const int parDefautParJour = 2;

  /// Au moins une vérification par jour.
  static const int minimumParJour = 1;

  /// Au plus une par heure, pour ménager les sites.
  static const int maximumParJour = 24;

  /// Nombre de vérifications par jour retenu.
  final int verificationsParJour;

  /// Écart entre deux vérifications (24 h / N, à la minute près).
  Duration get intervalle =>
      Duration(minutes: Duration.minutesPerDay ~/ verificationsParJour);

  /// Dernière échéance passée ou égale à [maintenant] (UTC).
  DateTime derniereEcheance(DateTime maintenant) {
    final utc = maintenant.toUtc();
    final minuit = DateTime.utc(utc.year, utc.month, utc.day);
    final minutesEcoulees = utc.difference(minuit).inMinutes;
    final pas = intervalle.inMinutes;
    // Les échéances repartent de 00:00 chaque jour : avec un pas qui ne
    // divise pas 24 h (5 par jour = toutes les 4 h 48), la dernière de la
    // journée est suivie de minuit.
    final indice = minutesEcoulees ~/ pas;
    final derniere = indice.clamp(0, verificationsParJour - 1);
    return minuit.add(Duration(minutes: derniere * pas));
  }

  /// Prochaine échéance strictement après [maintenant] (UTC).
  DateTime prochaineEcheance(DateTime maintenant) {
    final derniere = derniereEcheance(maintenant);
    final minuit = DateTime.utc(derniere.year, derniere.month, derniere.day);
    final indice =
        derniere.difference(minuit).inMinutes ~/ intervalle.inMinutes;
    if (indice + 1 >= verificationsParJour) {
      return minuit.add(const Duration(days: 1));
    }
    return derniere.add(intervalle);
  }

  /// `true` si aucune vérification n'a eu lieu depuis la dernière échéance
  /// (application fermée à l'heure prévue, première ouverture…).
  bool estEnRetard(DateTime? derniereVerification, DateTime maintenant) {
    if (derniereVerification == null) return true;
    return derniereVerification.toUtc().isBefore(derniereEcheance(maintenant));
  }

  /// Horaires de la journée, pour l'affichage (« 00:00, 12:00 UTC »).
  List<Duration> horairesDuJour() => <Duration>[
    for (var i = 0; i < verificationsParJour; i++) intervalle * i,
  ];
}
