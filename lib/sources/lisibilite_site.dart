/// Diagnostic « pourquoi cette page n'est pas lisible ? » (tâche T2), pour
/// l'aide « critères de lecture » de l'interface et les messages de refus.
///
/// Sans réseau : on lui passe une page déjà reçue (HTML, code HTTP,
/// en-têtes). Les critères sont ceux de `SourceGenerique` (sites à liens
/// explicites) ; rien n'est contourné (PLAYBOOK.md section 10).
library;

import 'package:html/parser.dart' show parse;

import 'erreur_source.dart';
import 'protection_anti_robot.dart';
import 'source_generique.dart';

/// Résultat de [verifierLisibilite] : la page est-elle lisible par
/// l'application, et sinon pourquoi.
class DiagnosticLisibilite {
  /// Crée un diagnostic.
  const DiagnosticLisibilite({
    required this.raisons,
    this.remarques = const <String>[],
    this.protectionAntiRobot = false,
    this.estPageChapitre = false,
    this.nombreLiensChapitres = 0,
    this.nombreImages = 0,
    this.estOeuvreUnique = false,
  });

  /// Raisons, en français clair, pour lesquelles la page n'est pas lisible
  /// (vide si elle l'est).
  final List<String> raisons;

  /// Informations utiles qui n'empêchent pas la lecture (« adresse d'un
  /// chapitre : la page du titre sera cherchée »…).
  final List<String> remarques;

  /// `true` si la page est un défi anti-robot.
  final bool protectionAntiRobot;

  /// `true` si l'adresse est celle d'un chapitre (`chapter-12`…).
  final bool estPageChapitre;

  /// Nombre de liens de chapitres reconnus dans la page.
  final int nombreLiensChapitres;

  /// Nombre d'images reconnues dans la zone de lecture (page de chapitre).
  final int nombreImages;

  /// `true` si l'accueil du site liste lui-même des chapitres : site dédié
  /// à une seule œuvre (comme ruri-dragon.online).
  final bool estOeuvreUnique;

  /// `true` si aucune raison n'empêche la lecture.
  bool get estLisible => raisons.isEmpty;

  @override
  String toString() =>
      'DiagnosticLisibilite(lisible: $estLisible, chapitres: '
      '$nombreLiensChapitres, images: $nombreImages, raisons: $raisons)';
}

/// Explique si la page [html] reçue de [adresse] est lisible par
/// l'application, et sinon pourquoi.
///
/// - [codeStatut] / [enTetes] : réponse HTTP reçue (défi anti-robot
///   403/429/503, erreur HTTP) ; `null` pour une page reçue normalement.
/// - [configurationSelecteurs] : JSON des réglages du site générique.
///
/// Critères : pas de défi anti-robot ni de page de connexion ; page de
/// titre → au moins un lien de chapitre du même site (« chapter-12 »,
/// « Chapitre 3 »…) ; page de chapitre → au moins quelques images en clair
/// dans un même conteneur, sans script brouillé ni canvas.
DiagnosticLisibilite verifierLisibilite(
  String html,
  Uri adresse, {
  int? codeStatut,
  Map<String, String> enTetes = const <String, String>{},
  String? configurationSelecteurs,
}) {
  final raisons = <String>[];
  final remarques = <String>[];

  final defi =
      (codeStatut != null &&
          estReponseDefiAntiRobot(
            codeStatut: codeStatut,
            enTetes: enTetes,
            corps: html,
          )) ||
      estPageDefiAntiRobot(html);
  if (defi) {
    return DiagnosticLisibilite(
      raisons: <String>[
        "${messageProtectionAntiRobot(adresse.host)}. L'application ne "
            'contourne pas ces protections : lisez ce site dans le '
            'navigateur.',
      ],
      protectionAntiRobot: true,
    );
  }
  if (codeStatut != null && (codeStatut < 200 || codeStatut >= 300)) {
    raisons.add(
      'Le site a répondu par une erreur HTTP $codeStatut : la page '
      "n'a pas pu être lue.",
    );
    return DiagnosticLisibilite(raisons: raisons);
  }

  final ConfigurationGenerique configuration;
  try {
    configuration = ConfigurationGenerique.depuisJson(
      configurationSelecteurs,
      url: adresse.toString(),
    );
  } on ErreurSource catch (erreur) {
    return DiagnosticLisibilite(raisons: <String>[erreur.message]);
  }

  final document = parse(html);
  final estChapitre = SourceGenerique.estAdresseChapitre(
    adresse,
    configuration: configuration,
  );
  final int nombreLiens;
  var nombreImages = 0;
  try {
    nombreLiens = SourceGenerique.compterLiensChapitres(
      document,
      adresse,
      configuration,
    );
    if (estChapitre) {
      nombreImages = SourceGenerique.imagesChapitre(
        document,
        adresse,
        configuration,
      ).length;
    }
  } on ErreurSource catch (erreur) {
    // Sélecteur CSS réglé invalide.
    return DiagnosticLisibilite(raisons: <String>[erreur.message]);
  }

  // Page de connexion : un champ de mot de passe sans aucun chapitre.
  if (nombreLiens == 0 &&
      nombreImages == 0 &&
      document.querySelector('input[type="password"]') != null) {
    raisons.add(
      "La page demande une connexion : l'application ne lit pas les "
      'contenus réservés aux comptes.',
    );
  }

  // Page construite en JavaScript : presque aucun texte ni lien dans le
  // HTML reçu (le navigateur la remplit ensuite par des scripts). Une page
  // de chapitre au script brouillé ou au canvas a sa raison plus précise,
  // donnée plus bas.
  final texte = (document.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ');
  final nombreLiensPage = document.querySelectorAll('a[href]').length;
  final raisonImages = estChapitre
      ? SourceGenerique.raisonSansImage(document)
      : null;
  if (raisons.isEmpty &&
      raisonImages == null &&
      nombreLiens == 0 &&
      nombreImages == 0 &&
      texte.trim().length < 200 &&
      nombreLiensPage < 3 &&
      document.querySelectorAll('script').isNotEmpty) {
    raisons.add(
      'La page est construite par des scripts (JavaScript) : son HTML ne '
      "contient pas les données, que l'application ne peut donc pas lire.",
    );
  }

  if (estChapitre) {
    remarques.add(
      "Cette adresse est celle d'un chapitre : l'application cherchera la "
      'page qui liste les chapitres (lien « tous les chapitres », fil '
      "d'Ariane ou accueil du site).",
    );
    if (raisons.isEmpty && nombreImages == 0) {
      raisons.add(
        raisonImages ??
            'Aucune image de chapitre trouvée : les pages doivent être des '
                'images en clair (balises <img>) regroupées dans la page.',
      );
    }
  } else if (raisons.isEmpty && nombreLiens == 0) {
    raisons.add(
      'Aucun lien de chapitre trouvé : les liens doivent mener au même site '
      'et contenir « chapter », « chapitre », « episode », « ch » ou « ep » '
      'suivi du numéro, dans leur adresse ou leur texte.',
    );
  }

  final estAccueil = adresse.path.isEmpty || adresse.path == '/';
  final estOeuvreUnique = estAccueil && nombreLiens > 0;
  if (estOeuvreUnique) {
    remarques.add(
      "L'accueil du site liste des chapitres : site dédié à une seule œuvre.",
    );
  }

  return DiagnosticLisibilite(
    raisons: raisons,
    remarques: remarques,
    estPageChapitre: estChapitre,
    nombreLiensChapitres: nombreLiens,
    nombreImages: nombreImages,
    estOeuvreUnique: estOeuvreUnique,
  );
}
