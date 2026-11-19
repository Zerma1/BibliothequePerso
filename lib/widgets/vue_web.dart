/// Vue web du navigateur intégré (paquet `flutter_inappwebview`) derrière
/// une petite interface, remplaçable par un faux dans les tests.
///
/// Windows d'abord (décision du client) : la vue web n'est créée que sous
/// Windows et Android ([estNavigateurIntegrePossible]). Sous Linux, le
/// paquet natif est remplacé par un paquet vide : ne jamais y créer
/// d'`InAppWebView`, les liens s'ouvrent dans le navigateur du système.
library;

import 'dart:io' show Platform;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

import '../etat/etat_navigateur.dart';
import 'textes.dart';

/// Remplace le test de plateforme de [estNavigateurIntegrePossible] (tests
/// seulement : simuler Linux sur un poste Windows).
@visibleForTesting
bool? forcerNavigateurIntegrePossible;

/// `true` si le navigateur intégré peut être créé sur ce système (Windows
/// ou Android).
bool get estNavigateurIntegrePossible =>
    forcerNavigateurIntegrePossible ??
    (Platform.isWindows || Platform.isAndroid);

/// Commandes de la vue web, données à l'écran à sa création.
abstract interface class ControleurVueWeb implements PageNavigateur {
  /// Ouvre [adresse].
  Future<void> charger(String adresse);

  /// Page précédente de l'historique.
  Future<void> reculer();

  /// Page suivante de l'historique.
  Future<void> avancer();

  /// Recharge la page.
  Future<void> recharger();

  /// `true` si une page précédente existe.
  Future<bool> peutReculer();

  /// `true` si une page suivante existe.
  Future<bool> peutAvancer();
}

/// Adresse de départ et événements de la vue web, transmis à l'écran.
class ParametresVueWeb {
  /// Crée les paramètres.
  const ParametresVueWeb({
    required this.adresseInitiale,
    required this.surCreation,
    required this.surDebutChargement,
    required this.surAdresse,
    required this.surFinChargement,
    required this.surTitre,
    required this.surProgression,
    required this.surErreur,
  });

  /// Page ouverte au départ.
  final String adresseInitiale;

  /// Vue web prête : ses commandes.
  final void Function(ControleurVueWeb controleur) surCreation;

  /// Début du chargement d'une page.
  final void Function(String? adresse) surDebutChargement;

  /// Changement d'adresse dans l'historique (y compris sans rechargement).
  final void Function(String adresse) surAdresse;

  /// Fin du chargement d'une page.
  final void Function(String adresse) surFinChargement;

  /// Titre de la page.
  final void Function(String? titre) surTitre;

  /// Avancement du chargement (0 à 100).
  final void Function(int progression) surProgression;

  /// Échec du chargement de la page principale.
  final void Function(String description) surErreur;
}

/// Construit la vue web à partir de ses paramètres.
typedef ConstructeurVueWeb = Widget Function(ParametresVueWeb parametres);

/// Vue web réelle (`InAppWebView`).
///
/// User-Agent : celui du moteur (WebView2 sous Windows), jamais modifié :
/// c'est le client qui navigue, comme dans son propre navigateur.
Widget construireVueWeb(ParametresVueWeb parametres) {
  // Garde-fou : l'écran ne s'ouvre pas sur un autre système, mais une vue
  // web ne doit en aucun cas être créée sous Linux.
  if (!estNavigateurIntegrePossible) {
    return const Center(child: Text(Textes.navigateurIndisponible));
  }
  return InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(parametres.adresseInitiale)),
    initialSettings: InAppWebViewSettings(),
    onWebViewCreated: (controleur) =>
        parametres.surCreation(_ControleurInAppWebView(controleur)),
    onLoadStart: (_, adresse) =>
        parametres.surDebutChargement(adresse?.toString()),
    onLoadStop: (_, adresse) {
      if (adresse != null) parametres.surFinChargement(adresse.toString());
    },
    onUpdateVisitedHistory: (_, adresse, _) {
      if (adresse != null) parametres.surAdresse(adresse.toString());
    },
    onTitleChanged: (_, titre) => parametres.surTitre(titre),
    onProgressChanged: (_, progression) =>
        parametres.surProgression(progression),
    onReceivedError: (_, requete, erreur) {
      // Seule la page principale compte (une image ou une publicité en
      // échec n'empêche pas la lecture) ; une navigation interrompue par le
      // client lui-même n'est pas une erreur.
      if ((requete.isForMainFrame ?? true) &&
          erreur.type != WebResourceErrorType.CANCELLED) {
        parametres.surErreur(erreur.description);
      }
    },
  );
}

/// [ControleurVueWeb] branché sur un `InAppWebViewController`. Méthodes
/// vérifiées dans flutter_inappwebview_windows 0.7.0-beta.3.
class _ControleurInAppWebView implements ControleurVueWeb {
  _ControleurInAppWebView(this._controleur);

  final InAppWebViewController _controleur;

  @override
  Future<void> charger(String adresse) =>
      _controleur.loadUrl(urlRequest: URLRequest(url: WebUri(adresse)));

  @override
  Future<void> reculer() => _controleur.goBack();

  @override
  Future<void> avancer() => _controleur.goForward();

  @override
  Future<void> recharger() => _controleur.reload();

  @override
  Future<bool> peutReculer() => _controleur.canGoBack();

  @override
  Future<bool> peutAvancer() => _controleur.canGoForward();

  @override
  Future<Object?> executerScript(
    String corpsFonction, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    final CallAsyncJavaScriptResult? resultat;
    try {
      resultat = await _controleur.callAsyncJavaScript(
        functionBody: corpsFonction,
        arguments: arguments,
      );
    } catch (erreur) {
      throw ErreurPageNavigateur('$erreur');
    }
    if (resultat == null) {
      throw const ErreurPageNavigateur('aucune réponse de la page');
    }
    final erreur = resultat.error;
    if (erreur != null) throw ErreurPageNavigateur(erreur);
    return resultat.value;
  }
}
