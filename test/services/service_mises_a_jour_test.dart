// Tests de ServiceMisesAJour : base en mémoire, actualisation simulée.
import 'dart:async';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_mises_a_jour.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Service dont l'actualisation est simulée : renvoie un nombre de nouveaux
/// chapitres par titre, ou lève une erreur, et mesure la concurrence.
class _ServiceSimule extends ServiceBibliotheque {
  _ServiceSimule(Database base, DepotSources depotSources)
    : super(
        depotSources: depotSources,
        depotTitres: DepotTitres(base),
        depotChapitres: DepotChapitres(base),
        depotListes: DepotListes(base),
        depotCategories: DepotCategories(base),
        fabriqueSources: FabriqueSources(_client),
        serviceAjoutSite: ServiceAjoutSite(
          depotSources,
          DetecteurTypeSite(_client),
        ),
        client: _client,
      );

  static final _client = creerClientTest(
    (http.Request requete) async => http.Response('', 404),
    HorlogeFactice(),
  );

  final Map<String, int> nouveauxParTitre = <String, int>{};
  final Set<String> titresEnErreur = <String>{};
  final List<String> ordreAppels = <String>[];
  final Map<int, int> enCoursParSource = <int, int>{};
  int enCoursTotal = 0;
  int maximumObserveTotal = 0;
  int maximumObserveParSource = 0;
  Completer<void>? verrou;

  @override
  Future<ResultatAjoutTitre> actualiserTitre(Titre titre) async {
    ordreAppels.add(titre.nom);
    final idSource = titre.idSource!;
    enCoursTotal++;
    enCoursParSource[idSource] = (enCoursParSource[idSource] ?? 0) + 1;
    if (enCoursTotal > maximumObserveTotal) maximumObserveTotal = enCoursTotal;
    if (enCoursParSource[idSource]! > maximumObserveParSource) {
      maximumObserveParSource = enCoursParSource[idSource]!;
    }
    await (verrou?.future ?? Future<void>.delayed(Duration.zero));
    await Future<void>.delayed(Duration.zero);
    enCoursTotal--;
    enCoursParSource[idSource] = enCoursParSource[idSource]! - 1;
    if (titresEnErreur.contains(titre.nom)) {
      throw ErreurSource(titre.urlTitre, 'site injoignable');
    }
    return ResultatAjoutTitre(titre, nouveauxParTitre[titre.nom] ?? 0);
  }
}

void main() {
  late Database base;
  late DepotSources depotSources;
  late DepotTitres depotTitres;
  late DepotListes depotListes;
  late _ServiceSimule bibliotheque;
  late ServiceMisesAJour service;
  late int idSuivis;

  Future<int> creerSource(String hote, {bool estActive = true}) async {
    final source = await depotSources.enregistrerSource(
      Source(
        nom: hote,
        urlBase: 'https://$hote',
        typeSource: TypeSource.mangaDex,
        estActive: estActive,
      ),
    );
    return source.id!;
  }

  Future<Titre> creerTitre(
    int idSource,
    String nom, {
    bool suivi = true,
  }) async {
    final titre = await depotTitres.enregistrerTitre(
      Titre(
        idSource: idSource,
        urlTitre: 'https://site$idSource.test/$nom',
        nom: nom,
      ),
    );
    if (suivi) {
      await depotListes.ajouterTitre(idSuivis, titre.id!);
    }
    return titre;
  }

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotListes = DepotListes(base);
    bibliotheque = _ServiceSimule(base, depotSources);
    service = ServiceMisesAJour(
      depotTitres: depotTitres,
      depotListes: depotListes,
      depotSources: depotSources,
      serviceBibliotheque: bibliotheque,
    );
    idSuivis = (await depotListes.chargerListeParNom(nomListeSuivis))!.id!;
  });

  tearDown(() => base.close());

  test('renvoie un rapport vide quand aucun titre n\'est suivi', () async {
    final source = await creerSource('a.test');
    await creerTitre(source, 'non suivi', suivi: false);

    final rapport = await service.verifierTitresSuivis();

    expect(rapport.resultats, isEmpty);
    expect(rapport.nombreNouveauxChapitres, 0);
  });

  test('vérifie seulement les titres suivis des sources actives', () async {
    final active = await creerSource('a.test');
    final inactive = await creerSource('b.test', estActive: false);
    await creerTitre(active, 'suivi actif');
    await creerTitre(active, 'pas suivi', suivi: false);
    await creerTitre(inactive, 'suivi inactif');

    await service.verifierTitresSuivis();

    expect(bibliotheque.ordreAppels, <String>['suivi actif']);
  });

  test(
    'additionne les nouveautés et garde les erreurs sans s\'arrêter',
    () async {
      final source = await creerSource('a.test');
      await creerTitre(source, 'un');
      await creerTitre(source, 'deux');
      await creerTitre(source, 'trois');
      bibliotheque.nouveauxParTitre.addAll(<String, int>{'un': 2, 'trois': 5});
      bibliotheque.titresEnErreur.add('deux');

      final rapport = await service.verifierTitresSuivis();

      expect(rapport.resultats, hasLength(3));
      expect(rapport.nombreNouveauxChapitres, 7);
      expect(
        rapport.titresAvecNouveautes.map((r) => r.titre.nom),
        unorderedEquals(<String>['un', 'trois']),
      );
      expect(rapport.echecs.single.titre.nom, 'deux');
      expect(rapport.echecs.single.erreur, isA<ErreurSource>());
    },
  );

  test(
    'limite à 3 sources en parallèle et 1 titre à la fois par source',
    () async {
      for (var i = 0; i < 5; i++) {
        final source = await creerSource('s$i.test');
        await creerTitre(source, 's$i-a');
        await creerTitre(source, 's$i-b');
      }

      final rapport = await service.verifierTitresSuivis();

      expect(rapport.resultats, hasLength(10));
      expect(bibliotheque.maximumObserveTotal, 3);
      expect(bibliotheque.maximumObserveParSource, 1);
    },
  );

  test(
    'une deuxième demande pendant la vérification partage le même rapport',
    () async {
      final source = await creerSource('a.test');
      await creerTitre(source, 'un');
      bibliotheque.verrou = Completer<void>();

      final premiere = service.verifierTitresSuivis();
      final seconde = service.verifierTitresSuivis();
      expect(service.estEnCours, isTrue);
      bibliotheque.verrou!.complete();

      expect(identical(await premiere, await seconde), isTrue);
      expect(bibliotheque.ordreAppels, <String>['un']);
      expect(service.estEnCours, isFalse);
    },
  );
}
