import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:bibliotheque_perso/sources/constantes_sources.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/signalement_mangadex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

void main() {
  // URL d'une page servie par un nœud MangaDex@Home (forme de l'exemple de
  // api.yaml : https://abcdef.xyz123.mangadex.network:12345/<jeton>).
  const urlAtHome =
      'https://abcdef.xyz123.mangadex.network:12345/jeton/data/'
      'd9786b687bc5f3fe1d4ae05ff05e0eb5/x1-b765e86d.png';
  // URL d'une page servie par MangaDex lui-même (exemple de la doc).
  const urlUploads =
      'https://uploads.mangadex.org/data/3303dd03ac8d27452cce3f2a882e94b2/'
      '1-f7a76de1.png';

  late HorlogeFactice horloge;
  late List<http.Request> requetes;

  setUp(() {
    horloge = HorlogeFactice();
    requetes = <http.Request>[];
  });

  SignalementMangaDex signalementAvec(
    Future<http.Response> Function(http.Request requete) gestionnaire,
  ) {
    return SignalementMangaDex(
      creerClientTest((requete) {
        requetes.add(requete);
        return gestionnaire(requete);
      }, horloge),
    );
  }

  group('estServeurMangaDexAtHome', () {
    test('un nœud mangadex.network est MangaDex@Home', () {
      expect(SignalementMangaDex.estServeurMangaDexAtHome(urlAtHome), isTrue);
      expect(
        SignalementMangaDex.estServeurMangaDexAtHome(
          'https://foo.bar:5678/abcdef/1a2b3c4d/data/h/2.png',
        ),
        isTrue,
      );
    });

    test('uploads.mangadex.org (base url contenant mangadex.org) ne l\'est '
        'pas', () {
      expect(SignalementMangaDex.estServeurMangaDexAtHome(urlUploads), isFalse);
      expect(
        SignalementMangaDex.estServeurMangaDexAtHome(
          'https://Uploads.MangaDex.org/data-saver/h/1.jpg',
        ),
        isFalse,
      );
    });

    test('une URL vide ou non http(s) ne l\'est pas', () {
      expect(SignalementMangaDex.estServeurMangaDexAtHome(''), isFalse);
      expect(
        SignalementMangaDex.estServeurMangaDexAtHome('/data/h/1.png'),
        isFalse,
      );
      expect(
        SignalementMangaDex.estServeurMangaDexAtHome('file:///c/1.png'),
        isFalse,
      );
    });
  });

  group('estEnCache', () {
    test('vrai seulement si X-Cache commence par HIT', () {
      expect(
        SignalementMangaDex.estEnCache(const <String, String>{
          'x-cache': 'HIT',
        }),
        isTrue,
      );
      expect(
        SignalementMangaDex.estEnCache(const <String, String>{
          'X-Cache': 'HIT from noeud',
        }),
        isTrue,
      );
      expect(
        SignalementMangaDex.estEnCache(const <String, String>{
          'x-cache': 'MISS',
        }),
        isFalse,
      );
      expect(SignalementMangaDex.estEnCache(const <String, String>{}), isFalse);
    });
  });

  group('signaler', () {
    test('envoie le rapport documenté pour une image MangaDex@Home', () async {
      final signalement = signalementAvec(
        (requete) async => http.Response('', 200),
      );
      final resultat = await signalement.signaler(
        urlImage: urlAtHome,
        succes: true,
        enCache: true,
        octets: 674687,
        duree: const Duration(milliseconds: 235),
      );
      expect(resultat, ResultatSignalement.envoye);
      final requete = requetes.single;
      expect(requete.method, 'POST');
      expect(requete.url.toString(), urlSignalementMangaDexAtHome);
      expect(requete.url.host, 'api.mangadex.network');
      expect(requete.headers['content-type'], 'application/json');
      expect(requete.headers['user-agent'], userAgentApplication);
      expect(requete.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(requete.body), <String, Object>{
        'url': urlAtHome,
        'success': true,
        'bytes': 674687,
        'duration': 235,
        'cached': true,
      });
    });

    test('n\'envoie rien pour uploads.mangadex.org', () async {
      final signalement = signalementAvec(
        (requete) async => http.Response('', 200),
      );
      final resultat = await signalement.signaler(
        urlImage: urlUploads,
        succes: true,
        enCache: false,
        octets: 10,
        duree: const Duration(milliseconds: 5),
      );
      expect(resultat, ResultatSignalement.nonRequis);
      expect(requetes, isEmpty);
    });

    test('un échec d\'envoi est avalé, sans nouvelle tentative', () async {
      final signalement = signalementAvec(
        (requete) async => http.Response('panne', 503),
      );
      final resultat = await signalement.signaler(
        urlImage: urlAtHome,
        succes: true,
        enCache: false,
        octets: 1,
        duree: Duration.zero,
      );
      expect(resultat, ResultatSignalement.echec);
      expect(requetes, hasLength(1));
    });

    test('une erreur réseau pendant l\'envoi est avalée', () async {
      final signalement = signalementAvec((requete) async {
        throw http.ClientException('coupure', requete.url);
      });
      expect(
        await signalement.signaler(
          urlImage: urlAtHome,
          succes: false,
          enCache: false,
          octets: 0,
          duree: Duration.zero,
        ),
        ResultatSignalement.echec,
      );
    });
  });

  group('signalerReussite / signalerEchec', () {
    test('signalerReussite reprend octets, durée et X-Cache', () async {
      final signalement = signalementAvec(
        (requete) async => http.Response('', 200),
      );
      await signalement.signalerReussite(
        urlAtHome,
        ReponseOctets(
          octets: Uint8List.fromList(<int>[1, 2, 3, 4]),
          enTetes: const <String, String>{'x-cache': 'MISS'},
          duree: const Duration(milliseconds: 42),
          codeStatut: 200,
        ),
      );
      expect(jsonDecode(requetes.single.body), <String, Object>{
        'url': urlAtHome,
        'success': true,
        'bytes': 4,
        'duration': 42,
        'cached': false,
      });
    });

    test('signalerEchec reprend la taille et la durée de l\'erreur', () async {
      final signalement = signalementAvec(
        (requete) async => http.Response('', 200),
      );
      await signalement.signalerEchec(
        urlAtHome,
        const ErreurSource(
          urlAtHome,
          'Réponse HTTP 502',
          codeStatut: 502,
          octetsRecus: 25,
          duree: Duration(milliseconds: 235),
        ),
      );
      expect(jsonDecode(requetes.single.body), <String, Object>{
        'url': urlAtHome,
        'success': false,
        'bytes': 25,
        'duration': 235,
        'cached': false,
      });
    });

    test('signalerEchec sans réponse : 0 octet et durée par défaut', () async {
      final signalement = signalementAvec(
        (requete) async => http.Response('', 200),
      );
      await signalement.signalerEchec(
        urlAtHome,
        const ErreurSource(urlAtHome, 'Erreur réseau'),
        dureeParDefaut: const Duration(milliseconds: 12),
      );
      final corps = jsonDecode(requetes.single.body) as Map<String, Object?>;
      expect(corps['bytes'], 0);
      expect(corps['duration'], 12);
      expect(corps['success'], false);
    });

    test('chaîne complète : téléchargement réussi puis signalement', () async {
      final client = creerClientTest((requete) async {
        requetes.add(requete);
        if (requete.url.host == 'api.mangadex.network') {
          return http.Response('', 200);
        }
        return http.Response.bytes(
          <int>[1, 2, 3],
          200,
          headers: <String, String>{'x-cache': 'HIT'},
        );
      }, horloge);
      final reponse = await client.recupererOctetsAvecDetails(
        Uri.parse(urlAtHome),
        userAgent: userAgentApplication,
        nouvellesTentatives: 0,
      );
      final resultat = await SignalementMangaDex(client)
          .signalerReussite(urlAtHome, reponse);
      expect(resultat, ResultatSignalement.envoye);
      final corps = jsonDecode(requetes.last.body) as Map<String, Object?>;
      expect(corps['bytes'], 3);
      expect(corps['cached'], true);
    });

    test('chaîne complète : 403 (baseUrl expirée) signalé en échec', () async {
      final client = creerClientTest((requete) async {
        requetes.add(requete);
        if (requete.url.host == 'api.mangadex.network') {
          return http.Response('', 200);
        }
        return http.Response('expire', 403);
      }, horloge);
      ErreurSource? erreur;
      try {
        await client.recupererOctetsAvecDetails(
          Uri.parse(urlAtHome),
          nouvellesTentatives: 0,
        );
      } on ErreurSource catch (e) {
        erreur = e;
      }
      expect(erreur?.codeStatut, 403);
      await SignalementMangaDex(client).signalerEchec(urlAtHome, erreur!);
      final corps = jsonDecode(requetes.last.body) as Map<String, Object?>;
      expect(corps['success'], false);
      expect(corps['bytes'], 6);
    });
  });
}
