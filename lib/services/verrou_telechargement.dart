/// Verrou de la file de téléchargement partagé entre isolats (application
/// ouverte et tâche de fond Android) : règles pures, sans base ni horloge.
library;

/// Propriétaire du traitement de la file et date à laquelle son verrou
/// expire s'il n'est pas renouvelé.
///
/// Stocké en base sous forme de texte (`ServiceParametres`) : c'est le seul
/// endroit commun aux deux isolats, qui n'ont pas de mémoire partagée.
class VerrouTelechargement {
  /// Crée le verrou.
  const VerrouTelechargement({
    required this.proprietaire,
    required this.expiration,
  });

  /// Identifiant aléatoire du service qui traite la file (un par instance de
  /// `ServiceTelechargement`, donc un par isolat).
  final String proprietaire;

  /// Date (UTC) après laquelle le verrou est considéré comme abandonné
  /// (application tuée pendant un téléchargement).
  final DateTime expiration;

  /// Séparateur entre le propriétaire et la date dans le texte stocké.
  static const String _separateur = '|';

  /// `true` si [demandeur] peut prendre (ou garder) le verrou à l'instant
  /// [maintenant] : il en est déjà le propriétaire, ou le verrou a expiré.
  bool estLibrePour(String demandeur, DateTime maintenant) =>
      proprietaire == demandeur || !maintenant.toUtc().isBefore(expiration);

  /// Texte enregistré en base.
  String versTexte() =>
      '$proprietaire$_separateur${expiration.toUtc().toIso8601String()}';

  /// Relit un verrou enregistré, ou `null` si le texte est illisible (un
  /// verrou abîmé est traité comme libre : mieux vaut un éventuel double
  /// traitement qu'une file bloquée pour toujours).
  static VerrouTelechargement? depuisTexte(String? texte) {
    if (texte == null) return null;
    final position = texte.lastIndexOf(_separateur);
    if (position <= 0) return null;
    final expiration = DateTime.tryParse(texte.substring(position + 1));
    if (expiration == null) return null;
    return VerrouTelechargement(
      proprietaire: texte.substring(0, position),
      expiration: expiration.toUtc(),
    );
  }
}
