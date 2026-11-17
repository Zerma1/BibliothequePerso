/// Reconnaissance des pages de défi anti-robot (Cloudflare « Just a
/// moment… »…), tâche T1 du 2026-11-17.
///
/// Le but est seulement de **nommer** clairement l'échec : aucune
/// résolution de défi, aucun cookie récupéré, aucun changement d'empreinte
/// (PLAYBOOK.md section 10). Un site protégé se lit dans le navigateur.
library;

import 'constantes_sources.dart';
import 'erreur_source.dart';

/// Indique si une réponse d'erreur HTTP est une page de défi anti-robot.
///
/// Critères (tâche T1) : code [codeStatut] parmi [codesHttpDefiAntiRobot]
/// (403, 429, 503) **et** soit l'en-tête `cf-mitigated: challenge` (posé par
/// Cloudflare sur ses défis), soit l'un des [marqueursDefiAntiRobot] dans le
/// [corps] (« Just a moment », `challenge-platform`, `cf-chl`). Les noms
/// d'en-têtes de [enTetes] sont comparés sans tenir compte de la casse.
bool estReponseDefiAntiRobot({
  required int codeStatut,
  required Map<String, String> enTetes,
  required String corps,
}) {
  if (!codesHttpDefiAntiRobot.contains(codeStatut)) {
    return false;
  }
  for (final entree in enTetes.entries) {
    if (entree.key.toLowerCase() == 'cf-mitigated' &&
        entree.value.toLowerCase().contains('challenge')) {
      return true;
    }
  }
  final minuscules = corps.toLowerCase();
  return marqueursDefiAntiRobot.any(minuscules.contains);
}

/// Indique si une page reçue **avec succès** (code 200) est en réalité une
/// page de défi anti-robot.
///
/// Plus strict que [estReponseDefiAntiRobot] : Cloudflare injecte son script
/// `challenge-platform` dans des pages ordinaires (relevé sur Scan-Manga),
/// donc il faut aussi un titre de défi ([titresDefiAntiRobot]) dans la
/// balise `<title>`.
bool estPageDefiAntiRobot(String corps) {
  final minuscules = corps.toLowerCase();
  final titre = RegExp(r'<title[^>]*>([^<]*)</title>')
      .firstMatch(minuscules)
      ?.group(1);
  if (titre == null || !titresDefiAntiRobot.any(titre.contains)) {
    return false;
  }
  return marqueursDefiAntiRobot.any(minuscules.contains);
}

/// Message affiché quand le site [domaine] sert une page de défi
/// anti-robot.
String messageProtectionAntiRobot(String domaine) =>
    'Le site $domaine a activé une protection anti-robot : impossible de le '
    'lire automatiquement';

/// Erreur dédiée à une protection anti-robot sur [uri] :
/// [ErreurSource.protectionAntiRobot] vaut `true`.
ErreurSource erreurProtectionAntiRobot(
  Uri uri, {
  int? codeStatut,
  int? octetsRecus,
  Duration? duree,
  String? extraitReponse,
}) {
  return ErreurSource(
    uri.toString(),
    messageProtectionAntiRobot(uri.host),
    codeStatut: codeStatut,
    octetsRecus: octetsRecus,
    duree: duree,
    extraitReponse: extraitReponse,
    protectionAntiRobot: true,
  );
}
