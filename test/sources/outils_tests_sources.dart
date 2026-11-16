import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/sources/client_http_poli.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Lit un fichier d'exemple enregistré sous `test/sources/` (les tests sont
/// lancés depuis la racine du projet).
String lireExemple(String cheminRelatif) =>
    File('test/sources/$cheminRelatif').readAsStringSync();

/// Lit un fichier JSON d'exemple de `test/sources/exemples_json/`.
Map<String, Object?> lireJsonExemple(String nomFichier) =>
    jsonDecode(lireExemple('exemples_json/$nomFichier'))
        as Map<String, Object?>;

/// Horloge simulée : `attendre` avance le temps au lieu de dormir, et chaque
/// attente est notée pour être vérifiée.
class HorlogeFactice {
  /// Heure simulée courante.
  DateTime maintenant = DateTime.utc(2026, 11, 15, 12);

  /// Attentes demandées par le client, dans l'ordre.
  final List<Duration> attentes = <Duration>[];

  /// Remplace `DateTime.now`.
  DateTime lire() => maintenant;

  /// Remplace `Future.delayed` : avance l'horloge sans attendre réellement.
  Future<void> attendre(Duration duree) async {
    attentes.add(duree);
    maintenant = maintenant.add(duree);
  }

  /// Fait passer le temps sans requête (entre deux actions de l'utilisateur).
  void avancer(Duration duree) {
    maintenant = maintenant.add(duree);
  }
}

/// Crée un `ClientHttpPoli` branché sur [gestionnaire] (aucun appel réseau)
/// et sur [horloge].
ClientHttpPoli creerClientTest(
  Future<http.Response> Function(http.Request requete) gestionnaire,
  HorlogeFactice horloge, {
  Duration delaiExpiration = const Duration(seconds: 20),
}) {
  return ClientHttpPoli(
    client: MockClient(gestionnaire),
    maintenant: horloge.lire,
    attendre: horloge.attendre,
    delaiExpiration: delaiExpiration,
  );
}

/// Réponse JSON UTF-8 (comme l'API MangaDex).
http.Response reponseJson(String corps, {int statut = 200}) {
  return http.Response.bytes(
    utf8.encode(corps),
    statut,
    headers: <String, String>{'content-type': 'application/json'},
  );
}
