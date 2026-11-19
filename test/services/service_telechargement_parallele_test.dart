// Téléchargements simultanés (jusqu'à 32 chapitres en même temps, réglage du
// client) : base en mémoire, archives dans un dossier temporaire, faux site
// derrière un `MockClient` (aucun appel réseau). Le client HTTP garde sa
// vraie règle de politesse (délai réduit à quelques dizaines de
// millisecondes) pour vérifier l'écart entre deux requêtes d'un même domaine.
import 'dart:async';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/contenu_chapitre.dart';
import 'package:bibliotheque_perso/modeles/fiche_titre.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/telechargement.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/services/verrou_telechargement.dart';
import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:bibliotheque_perso/sources/source_site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

/// Écart minimal entre deux requêtes d'un même domaine pendant ces tests
/// (1 s en vrai) : assez long pour être mesuré, assez court pour des tests
/// rapides.
const Duration _delaiParDomaine = Duration(milliseconds: 40);

/// Tolérance de la mesure (voir `verifierPolitesse`) : sous Windows, un
/// minuteur peut se déclencher quelques millisecondes avant l'heure lue par
/// `DateTime.now`, et la première requête peut être notée en retard.
const Duration _tolerance = Duration(milliseconds: 20);

/// Pages de chaque chapitre du faux site.
const int _pagesParChapitre = 3;

/// Faux site : la page du chapitre est demandée au client (comme un vrai
/// adaptateur), puis [_pagesParChapitre] images sur le même domaine.
class _FausseSource implements SourceSite {
  _FausseSource(this._client, this._urlBase);

  final ClientHttpPoli _client;
  final String _urlBase;

  @override
  Future<List<Titre>> rechercher(String requete) async => const <Titre>[];

  @override
  Future<FicheTitre> recupererFiche(String urlTitre) =>
      throw UnimplementedError();

  @override
  Future<List<Chapitre>> recupererChapitres(String urlTitre) async =>
      const <Chapitre>[];

  @override
  Future<ContenuChapitre> recupererContenu(String urlChapitre) async {
    await _client.recupererTexte(Uri.parse(urlChapitre));
    final numero = Uri.parse(urlChapitre).pathSegments.last;
    return ContenuChapitre.images(<String>[
      for (var page = 1; page <= _pagesParChapitre; page++)
        '$_urlBase/img/$numero/$page.jpg',
    ]);
  }
}

/// Fabrique qui renvoie le faux site pour toute source.
class _FausseFabrique extends FabriqueSources {
  _FausseFabrique(this._clientSite) : super(_clientSite);

  final ClientHttpPoli _clientSite;

  @override
  SourceSite creer(Source source, {List<String>? niveauxContenuRecherche}) =>
      _FausseSource(_clientSite, source.urlBase);
}

/// Dépôt de la file qui note chaque réservation et le nombre de chapitres
/// en cours (réservés et pas encore terminés, échoués ou remis en attente).
class _DepotEspion extends DepotTelechargements {
  _DepotEspion(super.baseDeDonnees);

  /// Chapitres réservés, dans l'ordre.
  final List<int> reservations = <int>[];

  /// Chapitres en cours en ce moment.
  int actifs = 0;

  /// Plus grand nombre de chapitres en cours en même temps.
  int maximumActifs = 0;

  @override
  Future<Telechargement?> reserverProchain() async {
    final suivant = await super.reserverProchain();
    if (suivant != null) {
      reservations.add(suivant.idChapitre);
      actifs++;
      if (actifs > maximumActifs) maximumActifs = actifs;
    }
    return suivant;
  }

  @override
  Future<bool> enregistrerStatut(
    int id,
    StatutTelechargement statut, {
    String? messageErreur,
    String? nomArchive,
  }) async {
    final resultat = await super.enregistrerStatut(
      id,
      statut,
      messageErreur: messageErreur,
      nomArchive: nomArchive,
    );
    if (statut != StatutTelechargement.enCours) actifs--;
    return resultat;
  }
}

void main() {
  late Database base;
  late Directory dossier;
  late DepotChapitres depotChapitres;
  late DepotTitres depotTitres;
  late DepotSources depotSources;
  late _DepotEspion depot;
  late ServiceParametres parametres;
  late ClientHttpPoli client;
  late ServiceTelechargement service;
  // Début de chaque requête reçue, par domaine.
  late Map<String, List<DateTime>> debutsParHote;
  // Porte fermée : la première image de chaque chapitre attend son
  // ouverture (chapitre « en cours » qui ne finit pas).
  Completer<void>? porte;
  late int premieresImagesBloquees;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('telechargements_paral');
    debutsParHote = <String, List<DateTime>>{};
    porte = null;
    premieresImagesBloquees = 0;
    client = ClientHttpPoli(
      client: MockClient((http.Request requete) async {
        debutsParHote
            .putIfAbsent(requete.url.host, () => <DateTime>[])
            .add(DateTime.now());
        final segments = requete.url.pathSegments;
        if (segments.first == 'img') {
          final attente = porte;
          if (attente != null && segments.last == '1.jpg') {
            premieresImagesBloquees++;
            await attente.future;
          }
          return http.Response.bytes(
            <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3],
            200,
            headers: <String, String>{'content-type': 'image/jpeg'},
          );
        }
        return http.Response(
          '<html><body>chapitre</body></html>',
          200,
          headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
        );
      }),
      delaiParDomaine: _delaiParDomaine,
    );
    depotSources = DepotSources(base);
    depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    depot = _DepotEspion(base);
    parametres = ServiceParametres(DepotParametres(base));
  });

  tearDown(() async {
    await service.fermer();
    await base.close();
    await dossier.delete(recursive: true);
  });

  /// Crée le service (après les réglages du test).
  ServiceTelechargement creerService({Duration? dureeVerrou}) =>
      service = ServiceTelechargement(
        depotTelechargements: depot,
        depotChapitres: depotChapitres,
        depotTitres: depotTitres,
        depotListes: DepotListes(base),
        depotSources: depotSources,
        stockage: StockageTelechargements(dossier.path),
        fabriqueSources: _FausseFabrique(client),
        client: client,
        serviceParametres: parametres,
        identifiantVerrou: 'application',
        dureeVerrou: dureeVerrou ?? ServiceTelechargement.dureeVerrouParDefaut,
      );

  /// Crée un site et un titre de [nombre] chapitres, les met en file (dans
  /// l'ordre) et renvoie leurs identifiants.
  Future<List<int>> mettreEnFile(String hote, int nombre) async {
    final source = await depotSources.enregistrerSource(
      Source(
        nom: 'Site $hote',
        urlBase: 'https://$hote',
        typeSource: TypeSource.madara,
        langueParDefaut: 'fr',
      ),
    );
    final titre = await depotTitres.enregistrerTitre(
      Titre(
        idSource: source.id,
        urlTitre: 'https://$hote/titre',
        nom: 'Titre de $hote',
      ),
    );
    await depotChapitres.enregistrerChapitres(<Chapitre>[
      for (var n = 1; n <= nombre; n++)
        Chapitre(
          idTitre: titre.id,
          urlChapitre: 'https://$hote/chapitre/$n',
          nom: 'Chapitre $n',
          numero: n.toDouble(),
          langue: 'fr',
        ),
    ]);
    final ids = <int>[];
    for (final chapitre in await depotChapitres.chargerChapitres(titre.id!)) {
      ids.add(chapitre.id!);
    }
    ids.sort();
    for (final id in ids) {
      await depot.ajouterEnFile(id);
    }
    return ids;
  }

  Future<StatutTelechargement> statut(int idChapitre) async =>
      (await depot.chargerParChapitre(idChapitre))!.statut;

  /// Attend (au plus 10 s, machine chargée comprise) que [condition] soit
  /// vraie.
  Future<void> attendreQue(FutureOr<bool> Function() condition) async {
    for (var essai = 0; essai < 1000; essai++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail("La condition attendue ne s'est jamais réalisée.");
  }

  /// Archives `.zip` complètes du dossier.
  Future<List<String>> archives() async => <String>[
    await for (final entite in dossier.list(recursive: true))
      if (entite is File && entite.path.endsWith('.zip')) entite.path,
  ];

  /// Vérifie le rythme des requêtes vers chaque domaine : n requêtes
  /// s'étalent sur au moins (n - 1) × [_delaiParDomaine].
  ///
  /// Mesure sur l'ensemble plutôt qu'écart par écart : l'heure notée par le
  /// faux serveur arrive un peu après le départ réel de la requête, avec un
  /// retard variable quand la machine est chargée (suite complète lancée en
  /// parallèle), ce qui rend un écart isolé trompeur. Sur l'ensemble, ce
  /// retard ne joue qu'aux deux bouts. Sans politesse, les requêtes d'un
  /// chapitre partiraient presque ensemble et la durée serait bien plus
  /// courte.
  void verifierPolitesse() {
    for (final MapEntry(key: hote, value: debuts) in debutsParHote.entries) {
      final tries = List<DateTime>.of(debuts)..sort();
      final etendue = tries.last.difference(tries.first);
      expect(
        etendue,
        greaterThanOrEqualTo(
          _delaiParDomaine * (tries.length - 1) - _tolerance,
        ),
        reason: '${tries.length} requêtes vers $hote trop rapprochées',
      );
    }
  }

  test('avec un seul téléchargement à la fois, la file se comporte comme '
      'avant : un chapitre après l\'autre, dans l\'ordre', () async {
    final journal = JournalMemoire();
    Journal.actuel = journal;
    addTearDown(() => Journal.actuel = const JournalSilencieux());
    await parametres.enregistrerTelechargementsSimultanes(1);
    final ids = await mettreEnFile('site-a.test', 4);
    creerService();

    await service.lancerTraitement();

    expect(depot.reservations, ids);
    expect(depot.maximumActifs, 1);
    // Images d'un site qui n'est pas MangaDex : aucun signalement
    // MangaDex@Home (api.mangadex.network), seulement le site lui-même.
    expect(debutsParHote.keys, <String>['site-a.test']);
    for (final id in ids) {
      expect(await statut(id), StatutTelechargement.termine);
    }
    expect(await archives(), hasLength(4));
    final messages = journal.entrees.map((e) => e.message).toList();
    expect(
      messages,
      contains(
        "File de téléchargement : début, jusqu'à 1 chapitre(s) en "
        'même temps',
      ),
    );
    verifierPolitesse();
  });

  test('avec 4, quatre chapitres sont en cours en même temps, jamais un '
      'cinquième, et chacun n\'est réservé qu\'une fois', () async {
    final journal = JournalMemoire();
    Journal.actuel = journal;
    addTearDown(() => Journal.actuel = const JournalSilencieux());
    await parametres.enregistrerTelechargementsSimultanes(4);
    final ids = await mettreEnFile('site-a.test', 6);
    creerService();
    final ouverture = porte = Completer<void>();

    final traitement = service.lancerTraitement();
    await attendreQue(() => premieresImagesBloquees == 4);
    // Laisse le temps à un éventuel cinquième chapitre de commencer.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(premieresImagesBloquees, 4);
    final enCours = await depot.chargerFile(
      statuts: <StatutTelechargement>{StatutTelechargement.enCours},
    );
    expect(enCours.map((t) => t.idChapitre), ids.take(4));
    expect(await statut(ids[4]), StatutTelechargement.enAttente);
    expect(await statut(ids[5]), StatutTelechargement.enAttente);

    ouverture.complete();
    await traitement;

    expect(depot.maximumActifs, 4);
    expect(depot.reservations, hasLength(6));
    expect(depot.reservations.toSet(), ids.toSet());
    for (final id in ids) {
      expect(await statut(id), StatutTelechargement.termine);
    }
    // Une archive par chapitre, aucune écrite deux fois.
    final noms = await archives();
    expect(noms, hasLength(6));
    expect(noms.toSet(), hasLength(6));
    expect(
      journal.entrees.map((e) => e.message),
      contains(contains("jusqu'à 4 chapitre(s)")),
    );
    // Même avec quatre chapitres d'un même site, une requête à la fois.
    verifierPolitesse();
  });

  test('deux sites avancent en même temps, chacun au rythme de 1 requête par '
      'délai de politesse', () async {
    await parametres.enregistrerTelechargementsSimultanes(8);
    final idsA = await mettreEnFile('site-a.test', 4);
    final idsB = await mettreEnFile('site-b.test', 4);
    creerService();

    await service.lancerTraitement();

    for (final id in <int>[...idsA, ...idsB]) {
      expect(await statut(id), StatutTelechargement.termine);
    }
    expect(depot.maximumActifs, 8);
    verifierPolitesse();
    // Les deux sites ont été sollicités en même temps : le site B a reçu sa
    // première requête avant la dernière du site A.
    final debutsA = debutsParHote['site-a.test']!..sort();
    final debutsB = debutsParHote['site-b.test']!..sort();
    expect(debutsB.first.isBefore(debutsA.last), isTrue);
    // 4 chapitres × (1 page HTML + 3 images) par site.
    expect(debutsA, hasLength(4 * (1 + _pagesParChapitre)));
    expect(debutsB, hasLength(4 * (1 + _pagesParChapitre)));
  });

  test('un réglage augmenté pendant le traitement est appliqué dès la relance '
      'de la file, sans attendre la fin des chapitres en cours', () async {
    await parametres.enregistrerTelechargementsSimultanes(1);
    final ids = await mettreEnFile('site-a.test', 5);
    creerService();
    final ouverture = porte = Completer<void>();

    final traitement = service.lancerTraitement();
    await attendreQue(() => premieresImagesBloquees == 1);

    await parametres.enregistrerTelechargementsSimultanes(3);
    // Même traitement (partagé), réveillé pour relire le réglage.
    expect(identical(service.lancerTraitement(), traitement), isTrue);
    await attendreQue(() => premieresImagesBloquees == 3);
    expect(await statut(ids[3]), StatutTelechargement.enAttente);

    ouverture.complete();
    await traitement;
    expect(depot.maximumActifs, 3);
    for (final id in ids) {
      expect(await statut(id), StatutTelechargement.termine);
    }
  });

  test('un verrou repris par l\'autre isolat arrête tous les chapitres en '
      'cours et n\'en commence aucun autre', () async {
    await parametres.enregistrerTelechargementsSimultanes(3);
    final ids = await mettreEnFile('site-a.test', 5);
    // Verrou court : chaque page le revérifie (un tiers de sa durée).
    creerService(dureeVerrou: const Duration(milliseconds: 30));
    final ouverture = porte = Completer<void>();

    final traitement = service.lancerTraitement();
    await attendreQue(() => premieresImagesBloquees == 3);
    await parametres.enregistrerVerrouTelechargement(
      VerrouTelechargement(
        proprietaire: 'tache-de-fond',
        expiration: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      ),
    );
    ouverture.complete();
    await traitement;

    // Les trois chapitres commencés sont abandonnés sans toucher leur ligne
    // (l'autre isolat les reprendra comme interrompus), sans archive.
    for (final id in ids.take(3)) {
      expect(await statut(id), StatutTelechargement.enCours);
    }
    expect(await statut(ids[3]), StatutTelechargement.enAttente);
    expect(await statut(ids[4]), StatutTelechargement.enAttente);
    expect(depot.reservations, ids.take(3));
    expect(await archives(), isEmpty);
    // Le verrou de l'autre isolat n'est pas effacé en partant.
    final verrou = await parametres.chargerVerrouTelechargement();
    expect(verrou!.proprietaire, 'tache-de-fond');
  });

  test('un plafond imposé (tâche de fond Android) l\'emporte sur un réglage '
      'plus haut', () async {
    await parametres.enregistrerTelechargementsSimultanes(32);
    final ids = await mettreEnFile('site-a.test', 6);
    service = ServiceTelechargement(
      depotTelechargements: depot,
      depotChapitres: depotChapitres,
      depotTitres: depotTitres,
      depotListes: DepotListes(base),
      depotSources: depotSources,
      stockage: StockageTelechargements(dossier.path),
      fabriqueSources: _FausseFabrique(client),
      client: client,
      serviceParametres: parametres,
      identifiantVerrou: 'tache-de-fond',
      plafondTelechargementsSimultanes: 2,
    );
    final ouverture = porte = Completer<void>();

    final traitement = service.lancerTraitement();
    await attendreQue(() => premieresImagesBloquees == 2);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(premieresImagesBloquees, 2);

    ouverture.complete();
    await traitement;
    expect(depot.maximumActifs, 2);
    for (final id in ids) {
      expect(await statut(id), StatutTelechargement.termine);
    }
  });
}
