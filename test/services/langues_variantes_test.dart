// Tâche P3 : variantes régionales des langues (pt-br, es-la, zh-hk…).
// Calculs purs : ni base, ni réseau.
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/services/classement_listes.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:flutter_test/flutter_test.dart';

Chapitre _chapitre(int id, double numero, String langue) => Chapitre(
  id: id,
  idTitre: 1,
  urlChapitre: 'https://exemple.org/chapitre/$id',
  nom: 'Chapitre $numero',
  numero: numero,
  langue: langue,
);

void main() {
  group('nettoyerLangues', () {
    test('accepte les variantes régionales, distinctes de leur langue', () {
      expect(
        ServiceParametres.nettoyerLangues(<String>[
          'PT-BR',
          'pt',
          ' es-la ',
          'zh-HK',
          'pt-br',
        ]),
        <String>['pt-br', 'pt', 'es-la', 'zh-hk'],
      );
    });

    test('la forme pt_BR devient pt-br, les codes invalides sont écartés', () {
      expect(
        ServiceParametres.nettoyerLangues(<String>['pt_BR', 'pt-', 'x', 'fr-']),
        <String>['pt-br'],
      );
    });
  });

  group('rangLangue : exacte d\'abord, langue de base en repli', () {
    test('la préférence exacte pt-br prend le chapitre pt-br à son rang', () {
      const politique = PolitiqueTelechargement(
        languesPreferees: <String>['pt-br', 'en'],
      );
      expect(politique.rangLangue(_chapitre(1, 1, 'pt-br')), 0);
      expect(politique.rangLangue(_chapitre(2, 1, 'PT-BR')), 0);
      expect(politique.rangLangue(_chapitre(3, 1, 'en')), 1);
      // Repli : le portugais du Portugal, après toutes les langues exactes.
      expect(politique.rangLangue(_chapitre(4, 1, 'pt')), 2);
      // Langue inconnue : tout dernier rang accepté.
      expect(politique.rangLangue(_chapitre(5, 1, '')), 4);
      expect(politique.rangLangue(_chapitre(6, 1, 'ru')), isNull);
    });

    test('une préférence pt accepte pt-br en repli, après les exactes', () {
      const politique = PolitiqueTelechargement(
        languesPreferees: <String>['pt', 'en'],
      );
      expect(politique.rangLangue(_chapitre(1, 1, 'pt')), 0);
      expect(politique.rangLangue(_chapitre(2, 1, 'en')), 1);
      expect(politique.rangLangue(_chapitre(3, 1, 'pt-br')), 2);
      expect(politique.rangLangue(_chapitre(4, 1, 'es-la')), isNull);
    });

    test('pour un même numéro, la version exacte passe avant la variante', () {
      const politique = PolitiqueTelechargement(
        languesPreferees: <String>['pt-br', 'en'],
      );
      final versions = politique.choisirVersions(<Chapitre>[
        _chapitre(1, 1, 'pt'),
        _chapitre(2, 1, 'en'),
        _chapitre(3, 1, 'pt-br'),
        _chapitre(4, 2, 'pt'),
        _chapitre(5, 2, 'en'),
        _chapitre(6, 3, 'pt'),
      ]);
      expect(versions.map((v) => v.chapitre.id), <int>[3, 5, 6]);
    });

    test('une variante seule suffit à sortir un titre de « En attente »', () {
      expect(
        ClassementListes.aChapitreDansLesLangues(
          <Chapitre>[_chapitre(1, 1, 'es-la')],
          <String>['es'],
        ),
        isTrue,
      );
      expect(
        ClassementListes.aChapitreDansLesLangues(
          <Chapitre>[_chapitre(1, 1, 'es-la')],
          <String>['fr', 'en'],
        ),
        isFalse,
      );
    });

    test('les règles téléchargent la variante quand elle est la seule', () {
      const politique = PolitiqueTelechargement(
        languesPreferees: <String>['zh'],
      );
      final plan = politique.calculer(
        <Chapitre>[_chapitre(1, 1, 'zh-hk'), _chapitre(2, 2, 'ko')],
        estFavori: true,
        estSuivi: false,
      );
      expect(plan.idsVoulus, <int>{1});
    });
  });

  group('languesEtVariantes (onglet Mises à jour)', () {
    test('ajoute la langue de base et les variantes connues, sans doublon', () {
      expect(
        ServiceBibliotheque.languesEtVariantes(<String>['pt', 'en']),
        <String>['pt', 'pt-br', 'en'],
      );
      expect(
        ServiceBibliotheque.languesEtVariantes(<String>['pt-br']),
        <String>['pt-br', 'pt'],
      );
      expect(
        ServiceBibliotheque.languesEtVariantes(<String>['es-la', 'ES', 'fr']),
        <String>['es-la', 'es', 'fr'],
      );
      expect(
        ServiceBibliotheque.languesEtVariantes(<String>['', ' ']),
        isEmpty,
      );
    });
  });
}
