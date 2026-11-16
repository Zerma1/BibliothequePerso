// Tests des horaires de vérification (N par jour à partir de 00:00 UTC).
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/services/planification_mises_a_jour.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_mises_a_jour.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

DateTime _utc(int jour, int heure, [int minute = 0]) =>
    DateTime.utc(2026, 11, jour, heure, minute);

void main() {
  group('PlanificationMisesAJour', () {
    final deuxParJour = PlanificationMisesAJour(2);

    test('par défaut : 00:00 et 12:00 UTC', () {
      expect(PlanificationMisesAJour.parDefautParJour, 2);
      expect(deuxParJour.horairesDuJour(), <Duration>[
        Duration.zero,
        const Duration(hours: 12),
      ]);
    });

    test('dernière et prochaine échéance', () {
      expect(deuxParJour.derniereEcheance(_utc(15, 9, 30)), _utc(15, 0));
      expect(deuxParJour.prochaineEcheance(_utc(15, 9, 30)), _utc(15, 12));
      expect(deuxParJour.derniereEcheance(_utc(15, 12)), _utc(15, 12));
      expect(deuxParJour.prochaineEcheance(_utc(15, 12)), _utc(16, 0));
      expect(deuxParJour.prochaineEcheance(_utc(15, 23, 59)), _utc(16, 0));
    });

    test('une heure locale est convertie en UTC', () {
      final local = _utc(15, 13).toLocal();
      expect(deuxParJour.derniereEcheance(local), _utc(15, 12));
    });

    test('en retard si rien depuis la dernière échéance', () {
      expect(deuxParJour.estEnRetard(null, _utc(15, 9)), isTrue);
      expect(deuxParJour.estEnRetard(_utc(14, 23), _utc(15, 9)), isTrue);
      expect(deuxParJour.estEnRetard(_utc(15, 0, 5), _utc(15, 9)), isFalse);
      expect(deuxParJour.estEnRetard(_utc(15, 0, 5), _utc(15, 12, 1)), isTrue);
    });

    test('1 par jour et 24 par jour', () {
      final une = PlanificationMisesAJour(1);
      expect(une.prochaineEcheance(_utc(15, 0)), _utc(16, 0));
      final vingtQuatre = PlanificationMisesAJour(24);
      expect(vingtQuatre.prochaineEcheance(_utc(15, 7, 10)), _utc(15, 8));
    });

    test('un nombre qui ne divise pas 24 h repart de minuit', () {
      final cinq = PlanificationMisesAJour(5);
      expect(cinq.intervalle, const Duration(hours: 4, minutes: 48));
      expect(cinq.derniereEcheance(_utc(15, 23)), _utc(15, 19, 12));
      expect(cinq.prochaineEcheance(_utc(15, 23)), _utc(16, 0));
    });

    test('les valeurs hors limites sont ramenées entre 1 et 24', () {
      expect(PlanificationMisesAJour(0).verificationsParJour, 1);
      expect(PlanificationMisesAJour(100).verificationsParJour, 24);
    });
  });

  group('ServiceMisesAJour.verifierSiEcheancePassee', () {
    test('vérifie si en retard, puis attend l\'échéance suivante', () async {
      final base = await ouvrirBaseDeTest();
      addTearDown(base.close);
      var maintenant = _utc(15, 9);
      final client = creerClientTest(
        (http.Request requete) async => http.Response('', 404),
        HorlogeFactice(),
      );
      final depotSources = DepotSources(base);
      final parametres = ServiceParametres(DepotParametres(base));
      final service = ServiceMisesAJour(
        depotTitres: DepotTitres(base),
        depotListes: DepotListes(base),
        depotSources: depotSources,
        serviceParametres: parametres,
        maintenant: () => maintenant,
        serviceBibliotheque: ServiceBibliotheque(
          depotSources: depotSources,
          depotTitres: DepotTitres(base),
          depotChapitres: DepotChapitres(base),
          depotListes: DepotListes(base),
          depotCategories: DepotCategories(base),
          fabriqueSources: FabriqueSources(client),
          serviceAjoutSite: ServiceAjoutSite(
            depotSources,
            DetecteurTypeSite(client),
          ),
          client: client,
        ),
      );

      expect(await service.verifierSiEcheancePassee(), isNotNull);
      expect(await parametres.chargerDerniereVerification(), _utc(15, 9));

      maintenant = _utc(15, 11, 59);
      expect(await service.verifierSiEcheancePassee(), isNull);

      maintenant = _utc(15, 12, 1);
      expect(await service.verifierSiEcheancePassee(), isNotNull);

      await parametres.enregistrerVerificationsParJour(24);
      maintenant = _utc(15, 13, 0);
      expect(await service.verifierSiEcheancePassee(), isNotNull);
    });
  });
}
