// Tests de ServiceMisesAJour : base en mémoire, actualisation simulée.
import 'dart:async';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/services/service_bibliotheque.dart';
import 'package:bibliotheque_perso/services/service_mises_a_jour.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
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
        depotTitresSources: DepotTitresSources(base),
      );

  static final _client = creerClientTest(
    (http.Request requete) async => http.Response('', 404),
    HorlogeFactice(),
  );

  final Map<String, int> nouveauxParTitre = <String, int>{};
  final Set<String> titresEnErreur = <String>{};

  /// Sites en panne (identifiants de source), tous titres confondus.
  final Set<int> sitesEnErreur = <int>{};
  final List<String> ordreAppels = <String>[];

  /// Appels par site : « nom du titre@idSource ».
  final List<String> appelsParSite = <String>[];
  final Map<int, int> enCoursParSource = <int, int>{};
  int enCoursTotal = 0;
  int maximumObserveTotal = 0;
  int maximumObserveParSource = 0;
  Completer<void>? verrou;

  @override
  Future<ResultatAjoutTitre> actualiserSiteDuTitre(
    Titre titre,
    int idSource,
  ) async {
    // Le nom n'est noté qu'une fois par titre (site principal ou unique).
    if (idSource == titre.idSource) ordreAppels.add(titre.nom);
    appelsParSite.add('${titre.nom}@$idSource');
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
    if (titresEnErreur.contains(titre.nom) ||
        sitesEnErreur.contains(idSource)) {
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

  test(
    'note le début, le bilan et chaque titre en échec dans le journal',
    () async {
      final journal = JournalMemoire();
      Journal.actuel = journal;
      addTearDown(() => Journal.actuel = const JournalSilencieux());
      final source = await creerSource('a.test');
      await creerTitre(source, 'un');
      await creerTitre(source, 'deux');
      bibliotheque.nouveauxParTitre['un'] = 2;
      bibliotheque.titresEnErreur.add('deux');

      await service.verifierTitresSuivis();

      final messages = journal.entrees
          .where((e) => e.categorie == CategorieJournal.misesAJour)
          .map((e) => e.message)
          .toList();
      expect(messages.first, contains('début'));
      expect(
        messages,
        contains(
          allOf(
            contains('2 titre(s)'),
            contains('2 nouveau(x)'),
            contains('1 en échec'),
          ),
        ),
      );
      final echec = journal.entrees.singleWhere(
        (e) =>
            e.niveau == NiveauJournal.avertissement &&
            e.categorie == CategorieJournal.misesAJour,
      );
      expect(echec.message, contains('« deux »'));
      expect(echec.erreur, isA<ErreurSource>());
    },
  );

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

  test('vérifie un titre seulement favori et annonce ses nouveautés', () async {
    final source = await creerSource('a.test');
    final favori = await creerTitre(source, 'favori', suivi: false);
    final idFavoris = (await depotListes.chargerListeParNom(nomListeFavoris))!
        .id!;
    await depotListes.ajouterTitre(idFavoris, favori.id!);
    bibliotheque.nouveauxParTitre['favori'] = 3;

    final rapport = await service.verifierTitresSuivis();

    expect(bibliotheque.ordreAppels, <String>['favori']);
    expect(rapport.titresAvecNouveautes.single.titre.nom, 'favori');
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

  group('plusieurs sites pour un titre (étape 8)', () {
    test('chaque site du titre est vérifié et les nouveautés sont '
        'additionnées', () async {
      final principal = await creerSource('a.test');
      final secondaire = await creerSource('b.test');
      final titre = await creerTitre(principal, 'double');
      await DepotTitresSources(
        base,
      ).ajouterSourceSecondaire(titre.id!, secondaire, 'https://b.test/double');
      bibliotheque.nouveauxParTitre['double'] = 2;

      final rapport = await service.verifierTitresSuivis();

      expect(
        bibliotheque.appelsParSite,
        unorderedEquals(<String>['double@$principal', 'double@$secondaire']),
      );
      expect(rapport.resultats, hasLength(1));
      expect(rapport.nombreNouveauxChapitres, 4);
    });

    test("un site en panne n'empêche pas les autres et son erreur est "
        'gardée', () async {
      final principal = await creerSource('a.test');
      final secondaire = await creerSource('b.test');
      final titre = await creerTitre(principal, 'double');
      await DepotTitresSources(
        base,
      ).ajouterSourceSecondaire(titre.id!, secondaire, 'https://b.test/double');
      bibliotheque.nouveauxParTitre['double'] = 3;
      bibliotheque.sitesEnErreur.add(secondaire);

      final rapport = await service.verifierTitresSuivis();
      final resultat = rapport.resultats.single;

      expect(resultat.nombreNouveauxChapitres, 3);
      expect(resultat.erreursParSite.keys, <int>[secondaire]);
      expect(resultat.erreur, isA<ErreurSource>());
    });

    test("un site secondaire désactivé n'est pas interrogé", () async {
      final principal = await creerSource('a.test');
      final inactif = await creerSource('b.test', estActive: false);
      final titre = await creerTitre(principal, 'double');
      await DepotTitresSources(base)
          .ajouterSourceSecondaire(titre.id!, inactif, 'https://b.test/double');

      await service.verifierTitresSuivis();

      expect(bibliotheque.appelsParSite, <String>['double@$principal']);
    });

    test('un seul titre à la fois par site, même partagé entre deux '
        'titres', () async {
      final a = await creerSource('a.test');
      final b = await creerSource('b.test');
      final depotLiens = DepotTitresSources(base);
      for (var i = 0; i < 3; i++) {
        final titre = await creerTitre(a, 't$i');
        await depotLiens.ajouterSourceSecondaire(
          titre.id!,
          b,
          'https://b.test/t$i',
        );
      }

      final rapport = await service.verifierTitresSuivis();

      expect(bibliotheque.appelsParSite, hasLength(6));
      expect(bibliotheque.maximumObserveParSource, 1);
      expect(rapport.resultats, hasLength(3));
    });
  });

  group('listes Planifié et En attente', () {
    Future<void> ajouterChapitreFr(Titre titre) =>
        DepotChapitres(base).enregistrerChapitres(<Chapitre>[
          Chapitre(
            idTitre: titre.id,
            urlChapitre: '${titre.urlTitre}/ch1',
            nom: 'Chapitre 1',
            numero: 1,
            langue: 'fr',
          ),
        ]);

    test("un titre seulement planifié est vérifié mais n'apparaît pas dans "
        'le bilan', () async {
      final source = await creerSource('a.test');
      final planifie = await creerTitre(source, 'planifié', suivi: false);
      await ajouterChapitreFr(planifie);
      final idPlanifie = (await depotListes.chargerListeParNom(
        nomListePlanifie,
      ))!.id!;
      await depotListes.ajouterTitre(idPlanifie, planifie.id!);
      final suivi = await creerTitre(source, 'suivi');
      await ajouterChapitreFr(suivi);
      bibliotheque.nouveauxParTitre.addAll(<String, int>{
        'planifié': 4,
        'suivi': 1,
      });

      final rapport = await service.verifierTitresSuivis();

      expect(
        bibliotheque.ordreAppels,
        unorderedEquals(<String>['planifié', 'suivi']),
      );
      expect(rapport.resultats, hasLength(2));
      expect(rapport.nombreNouveauxChapitres, 1);
      expect(rapport.titresAvecNouveautes.single.titre.nom, 'suivi');
    });

    test('la vérification « En attente » ne vérifie que les titres sans '
        'chapitre dans les langues du client', () async {
      final source = await creerSource('a.test');
      final lisible = await creerTitre(source, 'lisible');
      await ajouterChapitreFr(lisible);
      await creerTitre(source, 'en attente');

      final rapport = await service.verifierTitresEnAttente();

      expect(rapport.estEnAttenteSeulement, isTrue);
      expect(bibliotheque.ordreAppels, <String>['en attente']);
    });

    test("à l'heure pleine, seule la vérification « En attente » est due "
        'après une vérification complète', () async {
      final parametres = ServiceParametres(DepotParametres(base));
      var maintenant = DateTime.utc(2026, 11, 16, 12, 10);
      final avecReglages = ServiceMisesAJour(
        depotTitres: depotTitres,
        depotListes: depotListes,
        depotSources: depotSources,
        serviceBibliotheque: bibliotheque,
        serviceParametres: parametres,
        maintenant: () => maintenant,
      );
      final source = await creerSource('a.test');
      final lisible = await creerTitre(source, 'lisible');
      await ajouterChapitreFr(lisible);
      await creerTitre(source, 'en attente');

      final complete = await avecReglages.verifierSiEcheancePassee();
      expect(complete!.estEnAttenteSeulement, isFalse);
      expect(await avecReglages.verifierSiEcheancePassee(), isNull);
      expect(
        await avecReglages.chargerProchaineEcheance(maintenant),
        DateTime.utc(2026, 11, 16, 13),
      );

      bibliotheque.ordreAppels.clear();
      maintenant = DateTime.utc(2026, 11, 16, 13, 1);
      final enAttente = await avecReglages.verifierSiEcheancePassee();
      expect(enAttente!.estEnAttenteSeulement, isTrue);
      expect(bibliotheque.ordreAppels, <String>['en attente']);
    });

    test("après une mise en veille, l'échéance manquée est rattrapée une "
        "seule fois d'après l'heure réelle", () async {
      // Application cachée dans la zone de notification, ordinateur endormi
      // de 11:00 à 14:00 : aucun minuteur ne s'est déclenché à 12:00. Le
      // service compare la dernière vérification enregistrée à la dernière
      // échéance passée, sans rien attendre de l'interface.
      final parametres = ServiceParametres(DepotParametres(base));
      var maintenant = DateTime.utc(2026, 11, 16, 11);
      final avecReglages = ServiceMisesAJour(
        depotTitres: depotTitres,
        depotListes: depotListes,
        depotSources: depotSources,
        serviceBibliotheque: bibliotheque,
        serviceParametres: parametres,
        maintenant: () => maintenant,
      );
      final source = await creerSource('a.test');
      final lisible = await creerTitre(source, 'lisible');
      await ajouterChapitreFr(lisible);
      await parametres.enregistrerDerniereVerification(maintenant);
      await parametres.enregistrerDerniereVerificationEnAttente(maintenant);
      expect(await avecReglages.verifierSiEcheancePassee(), isNull);

      maintenant = DateTime.utc(2026, 11, 16, 14);
      final rattrapage = await avecReglages.verifierSiEcheancePassee();
      expect(rattrapage!.estEnAttenteSeulement, isFalse);
      expect(bibliotheque.ordreAppels, <String>['lisible']);

      // Un second contrôle (minuteur, retour au premier plan) ne refait rien.
      expect(await avecReglages.verifierSiEcheancePassee(), isNull);
      expect(bibliotheque.ordreAppels, <String>['lisible']);
      expect(
        await avecReglages.chargerProchaineEcheance(maintenant),
        DateTime.utc(2026, 11, 17),
      );
    });

    test('une vérification complète demandée pendant une vérification « En '
        'attente » démarre juste après', () async {
      final source = await creerSource('a.test');
      final lisible = await creerTitre(source, 'lisible');
      await ajouterChapitreFr(lisible);
      await creerTitre(source, 'en attente');
      bibliotheque.verrou = Completer<void>();

      final enAttente = service.verifierTitresEnAttente();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final complete = service.verifierTitresSuivis();
      bibliotheque.verrou!.complete();

      expect((await enAttente).estEnAttenteSeulement, isTrue);
      expect((await complete).estEnAttenteSeulement, isFalse);
      expect(bibliotheque.ordreAppels.first, 'en attente');
      expect(
        bibliotheque.ordreAppels.skip(1),
        unorderedEquals(<String>['lisible', 'en attente']),
      );
    });
  });

  group('liste Terminés et archive complète', () {
    late ServiceParametres parametres;
    late ServiceMisesAJour avecReglages;

    setUp(() {
      parametres = ServiceParametres(DepotParametres(base));
      avecReglages = ServiceMisesAJour(
        depotTitres: depotTitres,
        depotListes: depotListes,
        depotSources: depotSources,
        serviceBibliotheque: bibliotheque,
        serviceParametres: parametres,
        maintenant: () => DateTime.utc(2026, 11, 18, 12, 5),
      );
    });

    Future<void> ranger(Titre titre, String nomListe) async {
      final liste = await depotListes.chargerListeParNom(nomListe);
      await depotListes.ajouterTitre(liste!.id!, titre.id!);
    }

    test('un titre seulement terminé est vérifié en silence et ne passe pas '
        'dans « En attente »', () async {
      final source = await creerSource('a.test');
      final termine = await creerTitre(source, 'terminé', suivi: false);
      await ranger(termine, nomListeTermines);
      bibliotheque.nouveauxParTitre['terminé'] = 2;

      final rapport = await service.verifierTitresSuivis();

      expect(bibliotheque.ordreAppels, <String>['terminé']);
      expect(rapport.resultats.single.estAnnonce, isFalse);
      expect(rapport.nombreNouveauxChapitres, 0);
      // Aucun chapitre dans les langues du client, mais rien à attendre.
      final noms = (await depotListes.chargerListesDuTitre(termine.id!))
          .map((liste) => liste.nom);
      expect(noms, isNot(contains(nomListeEnAttente)));
    });

    test('un titre suivi et terminé reste annoncé (le client choisit ses '
        'listes)', () async {
      final source = await creerSource('a.test');
      final titre = await creerTitre(source, 'suivi fini');
      await ranger(titre, nomListeTermines);
      bibliotheque.nouveauxParTitre['suivi fini'] = 1;

      final rapport = await service.verifierTitresSuivis();

      expect(rapport.titresAvecNouveautes.single.titre.nom, 'suivi fini');
    });

    test("sans archive complète, un titre sans liste ou d'une liste du "
        "client n'est pas vérifié", () async {
      final source = await creerSource('a.test');
      await creerTitre(source, 'sans liste', suivi: false);
      final perso = await depotListes.creerListe('À relire');
      final relire = await creerTitre(source, 'à relire', suivi: false);
      await depotListes.ajouterTitre(perso.id!, relire.id!);

      final rapport = await avecReglages.verifierTitresSuivis();

      expect(rapport.resultats, isEmpty);
      expect(bibliotheque.ordreAppels, isEmpty);
    });

    test('avec archive complète, toute la bibliothèque est vérifiée et seuls '
        'favoris et suivis sont annoncés', () async {
      await parametres.enregistrerArchiveComplete(true);
      final source = await creerSource('a.test');
      final inactive = await creerSource('b.test', estActive: false);
      await creerTitre(source, 'sans liste', suivi: false);
      final perso = await depotListes.creerListe('À relire');
      final relire = await creerTitre(source, 'à relire', suivi: false);
      await depotListes.ajouterTitre(perso.id!, relire.id!);
      await creerTitre(source, 'suivi');
      await creerTitre(inactive, 'site désactivé', suivi: false);
      bibliotheque.nouveauxParTitre.addAll(<String, int>{
        'sans liste': 3,
        'à relire': 2,
        'suivi': 1,
      });

      final rapport = await avecReglages.verifierTitresSuivis();

      // Un site désactivé reste ignoré, même en archive complète.
      expect(
        bibliotheque.ordreAppels,
        unorderedEquals(<String>['sans liste', 'à relire', 'suivi']),
      );
      expect(rapport.resultats, hasLength(3));
      expect(rapport.nombreNouveauxChapitres, 1);
      expect(rapport.titresAvecNouveautes.single.titre.nom, 'suivi');
      // Toujours un seul titre à la fois par source.
      expect(bibliotheque.maximumObserveParSource, 1);
    });

    test('avec archive complète, la vérification « En attente » reste '
        'limitée à sa liste', () async {
      await parametres.enregistrerArchiveComplete(true);
      final source = await creerSource('a.test');
      await creerTitre(source, 'sans liste', suivi: false);
      await creerTitre(source, 'en attente');

      final rapport = await avecReglages.verifierTitresEnAttente();

      expect(rapport.estEnAttenteSeulement, isTrue);
      expect(bibliotheque.ordreAppels, <String>['en attente']);
    });
  });
}
