// Tests du classement des erreurs pour l'interface.
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classe chaque erreur du projet et garde son message', () {
    final site = DescriptionErreur.depuis(
      const ErreurSource('https://x.test', 'Réponse HTTP 404'),
    );
    final base = DescriptionErreur.depuis(
      const ErreurBaseDeDonnees('Disque plein'),
    );
    final refus = DescriptionErreur.depuis(
      const ErreurService('Site non configuré'),
    );

    expect(site.nature, NatureErreur.site);
    expect(site.detail, 'Réponse HTTP 404');
    expect(base.nature, NatureErreur.baseDeDonnees);
    expect(base.detail, 'Disque plein');
    expect(refus.nature, NatureErreur.refus);
    expect(refus.detail, 'Site non configuré');
  });

  test('une erreur inconnue est classée inattendue', () {
    final inconnue = DescriptionErreur.depuis(StateError('bogue'));
    expect(inconnue.nature, NatureErreur.inattendue);
    expect(inconnue.detail, contains('bogue'));
  });

  test('ResultatAction distingue réussite et échec', () {
    const reussite = ResultatAction<int>.reussite(3);
    const echec = ResultatAction<int>.echec(
      DescriptionErreur(NatureErreur.adresseVide),
    );
    expect(reussite.estReussi, isTrue);
    expect(reussite.donnee, 3);
    expect(echec.estReussi, isFalse);
    expect(echec.donnee, isNull);
  });
}
