// Suppressions refusées par le service pendant un déplacement des chapitres :
// chaque état renvoie un échec « refus » qui garde le message du service
// tel quel (aucun plantage, aucun message générique).
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_bibliotheque.dart';
import 'package:bibliotheque_perso/etat/etat_telechargements.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

/// Message du vrai service (`ServiceTelechargement`) pendant un déplacement.
const String _messageDeplacement =
    'Les chapitres sont en cours de déplacement vers un autre dossier : '
    'terminez (ou abandonnez) ce déplacement dans les Paramètres avant de '
    'supprimer des chapitres téléchargés.';

void main() {
  late FauxServiceBibliotheque bibliotheque;
  late FauxServiceTelechargement telechargement;
  const chapitre = Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1);

  setUp(() {
    bibliotheque = FauxServiceBibliotheque()
      ..ajouterTitreDeTest('Titre', chapitres: const <Chapitre>[chapitre]);
    telechargement = FauxServiceTelechargement(bibliotheque)
      ..ajouterChapitreTelecharge(1)
      ..erreurSuppression = const ErreurService(_messageDeplacement);
  });

  void verifierRefus(ResultatAction<Object?> resultat) {
    expect(resultat.estReussi, isFalse);
    expect(resultat.erreur?.nature, NatureErreur.refus);
    // Texte affiché par l'interface : la phrase du service, sans ajout.
    expect(Textes.messageErreur(resultat.erreur!), _messageDeplacement);
  }

  test('fiche du titre : supprimerTelechargement', () async {
    final etat = EtatTitre(
      bibliotheque,
      1,
      serviceTelechargement: telechargement,
    );
    addTearDown(etat.dispose);
    await etat.charger();

    verifierRefus(await etat.supprimerTelechargement(chapitre));
    // L'archive est toujours là.
    expect(telechargement.pages.containsKey(1), isTrue);
  });

  test('fiche du titre : supprimerMaintenant', () async {
    final etat = EtatTitre(
      bibliotheque,
      1,
      serviceTelechargement: telechargement,
    );
    addTearDown(etat.dispose);
    await etat.charger();

    verifierRefus(await etat.supprimerMaintenant(chapitre));
  });

  test('écran Téléchargements : supprimer et supprimerMaintenant', () async {
    final etat = EtatTelechargements(telechargement, bibliotheque);
    addTearDown(etat.dispose);
    await etat.charger();

    verifierRefus(await etat.supprimer(1));
    verifierRefus(await etat.supprimerMaintenant(1));
  });

  test('bibliothèque : supprimerTitre garde le titre', () async {
    final etat = EtatBibliotheque(
      bibliotheque,
      serviceTelechargement: telechargement,
    );
    addTearDown(etat.dispose);
    await etat.charger();

    verifierRefus(await etat.supprimerTitre(1));
    expect(etat.titres, hasLength(1));
  });
}
