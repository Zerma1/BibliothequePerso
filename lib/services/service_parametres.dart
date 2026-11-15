/// Réglages du client (écran Paramètres) : noms des clés et valeurs par
/// défaut. Le stockage est assuré par `DepotParametres`.
library;

import '../donnees/depot_parametres.dart';
import 'politique_telechargement.dart';

/// Lecture et écriture des réglages, avec leurs valeurs par défaut.
class ServiceParametres {
  /// Crée le service.
  const ServiceParametres(this._depot);

  final DepotParametres _depot;

  /// Clé : chapitres lus gardés pour un favori.
  static const String cleFavorisLusConserves =
      'telechargement.favoris.lus_conserves';

  /// Clé : chapitres téléchargés au départ pour un titre suivi.
  static const String cleSuivisInitial = 'telechargement.suivis.initial';

  /// Clé : chapitres gardés jusqu'au dernier lu pour un titre suivi.
  static const String cleSuivisAvant = 'telechargement.suivis.avant';

  /// Clé : chapitres téléchargés après le dernier lu pour un titre suivi.
  static const String cleSuivisApres = 'telechargement.suivis.apres';

  /// Valeur maximale acceptée pour une limite, pour éviter qu'une faute de
  /// frappe (1000 au lieu de 10) ne lance des centaines de téléchargements.
  static const int limiteMaximale = 500;

  /// Réglages de téléchargement (valeurs par défaut si rien n'est enregistré
  /// ou si une valeur est illisible).
  Future<ReglagesTelechargement> chargerReglagesTelechargement() async {
    const defaut = ReglagesTelechargement();
    Future<int> lire(String cle, int valeurParDefaut) async {
      final valeur = await _depot.chargerEntier(cle);
      if (valeur == null || valeur < 0 || valeur > limiteMaximale) {
        return valeurParDefaut;
      }
      return valeur;
    }

    return ReglagesTelechargement(
      favorisLusConserves: await lire(
        cleFavorisLusConserves,
        defaut.favorisLusConserves,
      ),
      suivisInitial: await lire(cleSuivisInitial, defaut.suivisInitial),
      suivisAvant: await lire(cleSuivisAvant, defaut.suivisAvant),
      suivisApres: await lire(cleSuivisApres, defaut.suivisApres),
    );
  }

  /// Enregistre les réglages de téléchargement. Les valeurs sont ramenées
  /// entre 0 et [limiteMaximale].
  Future<void> enregistrerReglagesTelechargement(
    ReglagesTelechargement reglages,
  ) async {
    int borner(int valeur) => valeur.clamp(0, limiteMaximale);
    await _depot.enregistrerEntier(
      cleFavorisLusConserves,
      borner(reglages.favorisLusConserves),
    );
    await _depot.enregistrerEntier(
      cleSuivisInitial,
      borner(reglages.suivisInitial),
    );
    await _depot.enregistrerEntier(
      cleSuivisAvant,
      borner(reglages.suivisAvant),
    );
    await _depot.enregistrerEntier(
      cleSuivisApres,
      borner(reglages.suivisApres),
    );
  }

  /// Remet les réglages de téléchargement à leurs valeurs par défaut.
  Future<void> reinitialiserReglagesTelechargement() async {
    for (final cle in <String>[
      cleFavorisLusConserves,
      cleSuivisInitial,
      cleSuivisAvant,
      cleSuivisApres,
    ]) {
      await _depot.supprimer(cle);
    }
  }
}
