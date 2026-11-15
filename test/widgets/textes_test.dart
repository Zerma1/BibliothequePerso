// Tests des textes calculés de l'interface.
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/widgets/textes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formate les dates en jj/mm/aaaa', () {
    expect(Textes.formaterDate(DateTime(2026, 3, 7)), '07/03/2026');
  });

  test('formate les numéros sans zéros inutiles', () {
    expect(Textes.formaterNumero(1), '1');
    expect(Textes.formaterNumero(10.5), '10.5');
    expect(Textes.nomChapitre('', 4), 'Chapitre 4');
    expect(Textes.nomChapitre('Le début', 1), 'Le début');
  });

  test('accorde le nombre de nouveaux chapitres', () {
    expect(Textes.nouveauxChapitres(0), 'aucun nouveau chapitre');
    expect(Textes.nouveauxChapitres(1), '1 nouveau chapitre');
    expect(Textes.nouveauxChapitres(4), '4 nouveaux chapitres');
    expect(Textes.actualisationTerminee(0), 'Aucun nouveau chapitre.');
  });

  test('accorde le bilan des mises à jour', () {
    String bilan(int chapitres, int titres, int sites) =>
        Textes.bilanMisesAJour(
          nombreChapitres: chapitres,
          nombreTitres: titres,
          nombreSitesEnEchec: sites,
        );
    expect(bilan(0, 0, 0), 'Aucun nouveau chapitre.');
    expect(bilan(1, 1, 0), '1 nouveau chapitre pour 1 titre.');
    expect(bilan(5, 2, 0), '5 nouveaux chapitres pour 2 titres.');
    expect(bilan(0, 0, 1), 'Aucun nouveau chapitre. 1 site n\'a pas répondu.');
    expect(
      bilan(3, 2, 4),
      '3 nouveaux chapitres pour 2 titres. 4 sites n\'ont pas répondu.',
    );
  });

  test('construit un message pour chaque nature d\'erreur', () {
    for (final nature in NatureErreur.values) {
      final message = Textes.messageErreur(
        DescriptionErreur(nature, detail: 'précision'),
      );
      expect(message, isNotEmpty);
    }
    expect(
      Textes.messageErreur(
        const DescriptionErreur(NatureErreur.site, detail: 'HTTP 404'),
      ),
      '${Textes.erreurSite}\nHTTP 404',
    );
    expect(
      Textes.messageErreur(
        const DescriptionErreur(NatureErreur.refus, detail: 'Refusé.'),
      ),
      'Refusé.',
    );
  });

  test('décrit une source avec son type et sa langue', () {
    const source = Source(
      nom: 'MangaDex',
      urlBase: 'https://mangadex.org',
      typeSource: TypeSource.mangaDex,
      langueParDefaut: 'fr',
    );
    final description = Textes.descriptionSource(source);
    expect(description, contains('https://mangadex.org'));
    expect(description, contains('FR'));
    expect(description, contains('MangaDex'));
  });

  test('le bilan sépare les sites en panne des autres échecs', () {
    expect(
      Textes.bilanMisesAJour(
        nombreChapitres: 0,
        nombreTitres: 0,
        nombreSitesEnEchec: 1,
        nombreAutresEchecs: 2,
      ),
      "Aucun nouveau chapitre. 1 site n'a pas répondu. "
      "2 titres n'ont pas pu être vérifiés.",
    );
  });
}
