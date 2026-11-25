// Tests du modèle Chapitre pour la migration 13 : origine du chapitre (site
// ou navigateur intégré) et normalisation des adresses.
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/erreur_base_de_donnees.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chapitre = Chapitre(
    id: 3,
    idTitre: 1,
    urlChapitre: 'https://comix.to/title/ruri/chapter-12',
    nom: 'Chapitre 12',
    numero: 12,
  );

  test("l'origine vaut « site » par défaut", () {
    expect(chapitre.origine, OrigineChapitre.site);
    expect(chapitre.estWeb, isFalse);
    expect(chapitre.versMap()['origine'], 'site');
  });

  test('origine : aller-retour, copierAvec, == et hashCode', () {
    final web = chapitre.copierAvec(origine: OrigineChapitre.web);
    expect(web.estWeb, isTrue);
    expect(web.versMap()['origine'], 'web');
    expect(Chapitre.depuisMap(web.versMap()), web);
    expect(web, isNot(chapitre));
    expect(web.copierAvec(), web);
    expect(web.copierAvec().hashCode, web.hashCode);
    expect(web.toString(), contains('origine: web'));
  });

  test('colonne absente ou NULL : origine « site »', () {
    final sansColonne = chapitre.versMap()..remove('origine');
    expect(Chapitre.depuisMap(sansColonne).origine, OrigineChapitre.site);
    final nulle = chapitre.versMap()..['origine'] = null;
    expect(Chapitre.depuisMap(nulle).origine, OrigineChapitre.site);
  });

  test('origine inconnue : ErreurBaseDeDonnees', () {
    final map = chapitre.versMap()..['origine'] = 'autre';
    expect(() => Chapitre.depuisMap(map), throwsA(isA<ErreurBaseDeDonnees>()));
  });

  test('normaliserUrlChapitre retire espaces, fragment et / finaux', () {
    expect(
      normaliserUrlChapitre('  https://comix.to/ch/12/#page-3 '),
      'https://comix.to/ch/12',
    );
    expect(
      normaliserUrlChapitre('https://comix.to/ch/12//'),
      'https://comix.to/ch/12',
    );
    expect(
      normaliserUrlChapitre('https://comix.to/ch?p=2#x'),
      'https://comix.to/ch?p=2',
    );
    // La casse du chemin est gardée.
    expect(
      normaliserUrlChapitre('https://a.example/Ch'),
      'https://a.example/Ch',
    );
    expect(normaliserUrlChapitre(' #/ '), '');
  });
}
