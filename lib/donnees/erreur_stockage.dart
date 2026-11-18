/// Erreur levée par `StockageTelechargements` (fichiers hors-ligne).
library;

/// Nature d'une [ErreurStockage] : permet à l'appelant (service, interface)
/// de réagir sans analyser le texte du message (bandeau « dossier
/// inaccessible », proposition de choisir un autre dossier…).
enum NatureErreurStockage {
  /// Autre problème (archive abîmée, page introuvable, écriture en cours…).
  autre(''),

  /// Dossier racine ou lecteur introuvable : support débranché, lecteur
  /// réseau déconnecté, partage monté absent, NAS éteint.
  dossierInaccessible(
    'le dossier est introuvable (support débranché, lecteur réseau '
    'déconnecté ou NAS éteint).',
  ),

  /// Droits insuffisants (lecture seule, compte sans accès au partage).
  accesRefuse(
    "accès refusé : l'application n'a pas le droit d'écrire dans ce dossier.",
  ),

  /// Plus de place sur le disque (ou quota du partage atteint).
  espaceInsuffisant(
    'le disque est plein (ou le quota du partage est atteint).',
  ),

  /// Le partage réseau ne répond pas (réseau absent, serveur injoignable).
  reseauIndisponible(
    'le partage réseau ne répond pas (réseau absent ou NAS injoignable).',
  ),

  /// Chemin refusé : relatif, désigne un fichier, trop long, caractères
  /// invalides, ou incompatible avec le dossier actuel.
  cheminInvalide("le chemin choisi n'est pas valide.");

  const NatureErreurStockage(this.explication);

  /// Explication courte, en français, ajoutée à la fin des messages
  /// d'erreur (vide pour [autre]).
  final String explication;
}

/// Erreur de lecture ou d'écriture d'une archive de chapitre sur le disque.
///
/// Exemples : archive absente ou abîmée, page introuvable, disque plein,
/// chapitre déjà en cours d'écriture, dossier racine inaccessible.
class ErreurStockage implements Exception {
  /// Crée une erreur avec un [message] lisible, le [chemin] concerné, sa
  /// [cause] si elle existe et sa [nature] ([NatureErreurStockage.autre] par
  /// défaut).
  const ErreurStockage(
    this.message, {
    this.chemin,
    this.cause,
    this.nature = NatureErreurStockage.autre,
  });

  /// Description claire du problème, en français.
  final String message;

  /// Chemin du fichier concerné, s'il est connu.
  final String? chemin;

  /// Erreur d'origine (`FileSystemException`, `ArchiveException`…), si elle
  /// existe.
  final Object? cause;

  /// Nature du problème, pour que l'appelant puisse y réagir.
  final NatureErreurStockage nature;

  /// `true` si le dossier racine (ou le partage qui le contient) est
  /// injoignable : les archives ne sont pas perdues, elles reviendront avec
  /// le support. L'appelant ne doit alors rien modifier en base.
  bool get estDossierInaccessible =>
      nature == NatureErreurStockage.dossierInaccessible ||
      nature == NatureErreurStockage.reseauIndisponible;

  @override
  String toString() {
    final buffer = StringBuffer('ErreurStockage : $message');
    if (chemin != null) {
      buffer.write(' [$chemin]');
    }
    if (cause != null) {
      buffer.write(' (cause : $cause)');
    }
    return buffer.toString();
  }
}
