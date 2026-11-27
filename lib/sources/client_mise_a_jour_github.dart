/// Mise à jour automatique de l'application (version 0.4.0) : lecture de la
/// dernière release publiée du dépôt public, puis téléchargement vérifié de
/// son installateur. API REST publique de GitHub, **sans jeton**.
///
/// Sources (relevées le 2026-11-27) :
/// - docs.github.com, « Get the latest release » :
///   `GET /repos/{owner}/{repo}/releases/latest`, « the most recent
///   non-prerelease, non-draft release, sorted by the created_at
///   attribute » ; 404 si le dépôt n'en a aucune (essai réel le 2026-11-27 :
///   404 sur ce dépôt, qui n'a encore aucune release) ;
/// - schéma « Release » : `tag_name`, `name`, `body`, `published_at`,
///   `html_url`, `assets[]` (`name`, `size`, `state` = `uploaded` ou `open`,
///   `browser_download_url`) ;
/// - essai réel d'un `browser_download_url` (2026-11-27) : `302 Found` vers
///   `https://release-assets.githubusercontent.com/…` (adresse signée,
///   valable environ une heure), suivie par `package:http` ;
/// - noms des fichiers : `docs/DEPLOIEMENT.md`, « Noms figés ».
library;

import 'dart:convert';
import 'dart:io';

import 'client_http_poli.dart';
import 'constantes_sources.dart';
import 'empreinte_sha256.dart';
import 'erreur_source.dart';
import 'lecture_json.dart';
import 'limite_github.dart';

/// Version de l'application au format `X.Y.Z` (entiers positifs ou nuls).
class VersionApplication implements Comparable<VersionApplication> {
  /// Crée la version `majeure.mineure.correctif`.
  const VersionApplication(this.majeure, this.mineure, this.correctif);

  /// Lit [texte] au format strict `X.Y.Z` (chiffres seulement, sans `v`,
  /// suffixe `-test` ni `+N`), ou renvoie `null`.
  static VersionApplication? analyser(String texte) {
    // 9 chiffres au plus par nombre : aucun dépassement d'entier possible.
    final correspondance = RegExp(r'^(\d{1,9})\.(\d{1,9})\.(\d{1,9})$')
        .firstMatch(texte);
    if (correspondance == null) {
      return null;
    }
    return VersionApplication(
      int.parse(correspondance.group(1)!),
      int.parse(correspondance.group(2)!),
      int.parse(correspondance.group(3)!),
    );
  }

  /// X : rupture.
  final int majeure;

  /// Y : nouvelle fonctionnalité.
  final int mineure;

  /// Z : correction.
  final int correctif;

  @override
  int compareTo(VersionApplication autre) {
    if (majeure != autre.majeure) return majeure.compareTo(autre.majeure);
    if (mineure != autre.mineure) return mineure.compareTo(autre.mineure);
    return correctif.compareTo(autre.correctif);
  }

  @override
  bool operator ==(Object other) =>
      other is VersionApplication && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(majeure, mineure, correctif);

  @override
  String toString() => '$majeure.$mineure.$correctif';
}

/// Compare deux versions `X.Y.Z` numériquement (`0.10.0` > `0.9.9`) :
/// négatif si [a] < [b], 0 si égales, positif si [a] > [b].
///
/// Lève une [FormatException] si l'une n'est pas au format strict `X.Y.Z`
/// (retirer avant un éventuel `+N` ou `-test`).
int comparerVersions(String a, String b) {
  final versionA = VersionApplication.analyser(a);
  final versionB = VersionApplication.analyser(b);
  if (versionA == null) {
    throw FormatException('Version invalide (X.Y.Z attendu)', a);
  }
  if (versionB == null) {
    throw FormatException('Version invalide (X.Y.Z attendu)', b);
  }
  return versionA.compareTo(versionB);
}

/// Fichier joint à une release (`assets[]`).
class FichierRelease {
  /// Crée la description d'un fichier joint.
  const FichierRelease({
    required this.nom,
    required this.url,
    required this.taille,
  });

  /// Nom du fichier (`name`).
  final String nom;

  /// Adresse de téléchargement (`browser_download_url`), toujours sur
  /// `https://github.com/<propriétaire>/<dépôt>/releases/download/`.
  final Uri url;

  /// Taille en octets (`size`).
  final int taille;
}

/// Dernière release publiée du dépôt (résultat de
/// [ClientMiseAJourGithub.recupererDerniereVersion]).
class ReleaseApplication {
  /// Crée la description d'une release.
  const ReleaseApplication({
    required this.etiquette,
    required this.version,
    required this.nom,
    required this.notes,
    required this.datePublication,
    required this.urlPage,
    required this.installateur,
    required this.fichierEmpreinte,
  });

  /// Étiquette git (`tag_name`), toujours `vX.Y.Z`.
  final String etiquette;

  /// Version lue dans l'étiquette.
  final VersionApplication version;

  /// Titre de la release (`name`), ou `null` s'il est vide.
  final String? nom;

  /// Notes de version (`body`, Markdown brut), vide si absentes.
  final String notes;

  /// Date de publication (`published_at`, UTC), ou `null` si absente.
  final DateTime? datePublication;

  /// Page de la release sur github.com (`html_url`).
  final String urlPage;

  /// Installateur `bibliotheque_perso-X.Y.Z-installation.exe`, ou `null`
  /// (releases antérieures à 0.4.0, ou envoi pas encore terminé).
  final FichierRelease? installateur;

  /// Empreinte `bibliotheque_perso-X.Y.Z-installation.exe.sha256`, ou
  /// `null`.
  final FichierRelease? fichierEmpreinte;

  /// `true` si l'installateur **et** son empreinte sont présents : sans
  /// empreinte, le téléchargement ne peut pas être vérifié et ne doit pas
  /// être proposé.
  bool get estTelechargeable =>
      installateur != null && fichierEmpreinte != null;
}

/// L'installateur téléchargé n'a pas l'empreinte SHA-256 attendue (fichier
/// abîmé ou remplacé) : le fichier a été supprimé.
class ErreurEmpreinteInstallateur extends ErreurSource {
  /// Crée l'erreur pour [url].
  const ErreurEmpreinteInstallateur(
    super.url,
    super.message, {
    required this.empreinteAttendue,
    required this.empreinteObtenue,
  });

  /// Empreinte annoncée par le fichier `.sha256` (minuscules).
  final String empreinteAttendue;

  /// Empreinte calculée sur les octets reçus (minuscules).
  final String empreinteObtenue;
}

/// Progression d'un téléchargement : octets reçus et taille totale (annoncée
/// par le serveur ou par la release), `null` si inconnue.
typedef ProgressionTelechargement = void Function(int recus, int? total);

/// Client de mise à jour : dernière release du dépôt
/// [proprietaireDepotTickets]/[nomDepotTickets] et téléchargement vérifié
/// de l'installateur. Toutes les requêtes passent par [ClientHttpPoli].
class ClientMiseAJourGithub {
  /// Crée le client.
  ///
  /// [limite] : suivi de la limite GitHub, à partager avec
  /// `ClientTicketsGithub` (60 requêtes par heure pour toute l'adresse IP) ;
  /// à défaut, un suivi propre à ce client.
  ClientMiseAJourGithub(this._client, {SuiviLimiteGithub? limite})
    : _limite = limite ?? SuiviLimiteGithub();

  final ClientHttpPoli _client;
  final SuiviLimiteGithub _limite;

  /// En-têtes envoyés à l'API (en plus du User-Agent de [ClientHttpPoli]).
  static const Map<String, String> _enTetesApi = <String, String>{
    'Accept': typeMediaApiGithub,
    'X-GitHub-Api-Version': versionApiGithub,
  };

  /// Expression d'une empreinte : 64 hexadécimaux.
  static final RegExp _expressionEmpreinte = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Lit la dernière release publiée (ni brouillon ni *pre-release*).
  ///
  /// Renvoie `null` si le dépôt n'a aucune release (404 ; LIMITE : GitHub
  /// répond aussi 404 pour un dépôt privé ou supprimé, indiscernable).
  /// Lève [ErreurLimiteGithub] si la limite de requêtes est atteinte, une
  /// [ErreurSource] si l'étiquette n'est pas `vX.Y.Z`, si une adresse de
  /// fichier ne pointe pas vers les releases du dépôt, ou si le JSON est
  /// inattendu (ou réseau absent).
  Future<ReleaseApplication?> recupererDerniereVersion() async {
    final uri = Uri(
      scheme: 'https',
      host: hoteApiGithub,
      path: '/repos/$proprietaireDepotTickets/$nomDepotTickets/releases/latest',
    );
    final url = uri.toString();
    _limite.verifierAvantRequete(url);
    final ReponseOctets reponse;
    try {
      reponse = await _client.recupererOctetsAvecDetails(
        uri,
        enTetes: _enTetesApi,
      );
    } on ErreurSource catch (erreur) {
      final limite = _limite.traduireLimite(erreur, url);
      if (limite != null) {
        throw limite;
      }
      if (erreur.codeStatut == 404) {
        return null;
      }
      rethrow;
    }
    _limite.noterReponse(reponse.enTetes);

    final Object? valeur;
    try {
      valeur = jsonDecode(utf8.decode(reponse.octets));
    } on FormatException catch (erreur) {
      throw ErreurSource(
        url,
        'JSON invalide',
        cause: erreur,
        codeStatut: reponse.codeStatut,
      );
    }
    if (valeur is! Map<String, Object?>) {
      throw ErreurSource(
        url,
        'JSON inattendu : un objet était attendu',
        codeStatut: reponse.codeStatut,
      );
    }
    return _lireRelease(valeur, url);
  }

  ReleaseApplication _lireRelease(Map<String, Object?> objet, String url) {
    final etiquette = objet.lireTexte('tag_name', url);
    // Seules les releases `vX.Y.Z` (publiées depuis `main`) sont des mises à
    // jour ; une étiquette de test publiée par erreur sans « pre-release »
    // ne doit pas être proposée.
    final version = etiquette.startsWith('v')
        ? VersionApplication.analyser(etiquette.substring(1))
        : null;
    if (version == null) {
      throw ErreurSource(
        url,
        "Dernière release inattendue : étiquette « $etiquette » au lieu de "
        'vX.Y.Z',
      );
    }
    final nomInstallateur =
        '$prefixeNomInstallateur$version$suffixeNomInstallateur';
    final nomEmpreinte = '$nomInstallateur$extensionFichierEmpreinte';
    FichierRelease? installateur;
    FichierRelease? empreinte;
    for (final fichier in objet.lireListeObjets('assets', url)) {
      final nom = fichier.lireTexte('name', url);
      if (nom != nomInstallateur && nom != nomEmpreinte) {
        continue;
      }
      // `open` : envoi du fichier pas encore terminé, il n'est pas
      // téléchargeable (on retentera à la prochaine vérification).
      final etat = fichier.lireTexteOptionnel('state', url);
      if (etat != null && etat != 'uploaded') {
        continue;
      }
      final lu = FichierRelease(
        nom: nom,
        url: _lireUrlFichier(fichier, url),
        taille: fichier.lireEntier('size', url),
      );
      if (nom == nomInstallateur) {
        installateur = lu;
      } else {
        empreinte = lu;
      }
    }
    final nom = objet.lireTexteOptionnel('name', url);
    final datePublication = objet.lireTexteOptionnel('published_at', url);
    return ReleaseApplication(
      etiquette: etiquette,
      version: version,
      nom: nom == null || nom.trim().isEmpty ? null : nom,
      notes: objet.lireTexteOptionnel('body', url) ?? '',
      datePublication: datePublication == null
          ? null
          : DateTime.tryParse(datePublication)?.toUtc(),
      urlPage: objet.lireTexte('html_url', url),
      installateur: installateur,
      fichierEmpreinte: empreinte,
    );
  }

  /// `browser_download_url` vérifiée : seulement en https sur github.com,
  /// sous `/Zerma1/BibliothequePerso/releases/download/` (jamais un autre
  /// hôte, pour ne pas exécuter un fichier venu d'ailleurs).
  static Uri _lireUrlFichier(Map<String, Object?> fichier, String url) {
    final texte = fichier.lireTexte('browser_download_url', url);
    final adresse = Uri.tryParse(texte);
    final prefixe =
        '/$proprietaireDepotTickets/$nomDepotTickets/releases/download/';
    if (adresse == null ||
        adresse.scheme != 'https' ||
        adresse.host != hoteSiteGithub ||
        !adresse.path.startsWith(prefixe)) {
      throw ErreurSource(
        url,
        'JSON inattendu : adresse de fichier hors des releases du dépôt '
        '($texte)',
      );
    }
    return adresse;
  }

  /// Télécharge le fichier `.sha256` [url] et renvoie l'empreinte (64
  /// hexadécimaux, en minuscules).
  ///
  /// Format attendu (« Noms figés ») : 64 hexadécimaux, deux espaces, puis
  /// le nom du `.exe`, sur une ligne. Le nom lu doit valoir [nomFichierAttendu] ; à défaut, le dernier
  /// segment de [url] sans `.sha256`. Lève une [ErreurSource] si le fichier
  /// dépasse [tailleMaxFichierEmpreinte] octets, n'a pas ce format ou porte
  /// un autre nom.
  Future<String> recupererEmpreinteAttendue(
    Uri url, {
    String? nomFichierAttendu,
  }) async {
    final adresse = url.toString();
    var attendu = nomFichierAttendu;
    if (attendu == null) {
      final dernier = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
      if (!dernier.endsWith(extensionFichierEmpreinte)) {
        throw ErreurSource(
          adresse,
          "Adresse d'empreinte inattendue (.sha256 attendu)",
        );
      }
      attendu = dernier.substring(
        0,
        dernier.length - extensionFichierEmpreinte.length,
      );
    }
    final reponse = await _client.recupererOctetsAvecDetails(url);
    if (reponse.octets.length > tailleMaxFichierEmpreinte) {
      throw ErreurSource(
        adresse,
        "Fichier d'empreinte trop gros (${reponse.octets.length} o)",
        codeStatut: reponse.codeStatut,
      );
    }
    var texte = utf8.decode(reponse.octets, allowMalformed: true);
    // BOM toléré (un fichier écrit à la main sous Windows peut en avoir).
    if (texte.isNotEmpty && texte.codeUnitAt(0) == 0xFEFF) {
      texte = texte.substring(1);
    }
    final lignes = texte
        .split(RegExp(r'\r?\n'))
        .where((ligne) => ligne.trim().isNotEmpty)
        .toList(growable: false);
    // Format `sha256sum` : empreinte, un espace, puis un espace (mode texte)
    // ou `*` (mode binaire), puis le nom ; un seul espace est toléré.
    final correspondance = lignes.length == 1
        ? RegExp(r'^([0-9a-fA-F]{64}) [ *]?(\S.*)$')
              .firstMatch(lignes.single.trim())
        : null;
    if (correspondance == null) {
      throw ErreurSource(
        adresse,
        "Fichier d'empreinte illisible (une ligne « empreinte  nom » "
        'attendue)',
        codeStatut: reponse.codeStatut,
      );
    }
    final nomLu = correspondance.group(2)!.trim();
    if (nomLu != attendu) {
      throw ErreurSource(
        adresse,
        "Fichier d'empreinte pour « $nomLu » au lieu de « $attendu »",
        codeStatut: reponse.codeStatut,
      );
    }
    return correspondance.group(1)!.toLowerCase();
  }

  /// Télécharge l'installateur [url] vers [cheminDestination] en vérifiant
  /// son empreinte SHA-256, et renvoie le fichier final.
  ///
  /// Le corps est écrit au fil de l'eau dans `<cheminDestination>.part`
  /// (jamais tout en mémoire), l'empreinte calculée pendant l'écriture ; le
  /// fichier n'est renommé en [cheminDestination] (remplacé s'il existe)
  /// qu'après vérification. [tailleAttendue] (taille de la release, si
  /// connue) est aussi vérifiée. [progression] est appelé après chaque
  /// morceau reçu.
  ///
  /// En cas d'échec, le fichier `.part` est supprimé et l'erreur levée :
  /// [ErreurEmpreinteInstallateur] si l'empreinte diffère, [ErreurSource]
  /// sinon (taille dépassant [tailleMax], taille différente, réseau, disque).
  Future<File> telechargerInstallateur(
    Uri url,
    String cheminDestination, {
    required String empreinteAttendue,
    int? tailleAttendue,
    int tailleMax = tailleMaxInstallateur,
    ProgressionTelechargement? progression,
  }) async {
    final adresse = url.toString();
    if (!_expressionEmpreinte.hasMatch(empreinteAttendue)) {
      throw ErreurSource(adresse, 'Empreinte attendue invalide');
    }
    final attendue = empreinteAttendue.toLowerCase();
    if (tailleAttendue != null && tailleAttendue > tailleMax) {
      throw ErreurSource(
        adresse,
        'Installateur trop gros ($tailleAttendue o, maximum $tailleMax o)',
      );
    }
    final partiel = File('$cheminDestination.part');
    RandomAccessFile? fichier;
    var termine = false;
    try {
      final reponse = await _client.recupererFlux(url);
      final annoncee = reponse.tailleAnnoncee;
      if (annoncee != null && annoncee > tailleMax) {
        // Écouter puis annuler le flux ferme la connexion.
        await reponse.flux.listen(null).cancel();
        throw ErreurSource(
          adresse,
          'Installateur trop gros ($annoncee o, maximum $tailleMax o)',
          codeStatut: reponse.codeStatut,
        );
      }
      await partiel.parent.create(recursive: true);
      fichier = await partiel.open(mode: FileMode.write);
      final calcul = CalculEmpreinteSha256();
      final total = tailleAttendue ?? annoncee;
      var recus = 0;
      // `await for` + écriture attendue : pas de lecture plus rapide que le
      // disque, donc jamais tout le fichier en mémoire. Sortir de la boucle
      // par une exception annule l'écoute (connexion fermée).
      await for (final morceau in reponse.flux) {
        recus += morceau.length;
        if (recus > tailleMax) {
          throw ErreurSource(
            adresse,
            'Installateur trop gros (plus de $tailleMax o)',
            codeStatut: reponse.codeStatut,
          );
        }
        calcul.ajouter(morceau);
        await fichier.writeFrom(morceau);
        progression?.call(recus, total);
      }
      await fichier.close();
      fichier = null;
      if (tailleAttendue != null && recus != tailleAttendue) {
        throw ErreurSource(
          adresse,
          'Installateur incomplet ($recus o reçus, $tailleAttendue o '
          'attendus)',
          codeStatut: reponse.codeStatut,
          octetsRecus: recus,
        );
      }
      final obtenue = calcul.terminer();
      if (obtenue != attendue) {
        throw ErreurEmpreinteInstallateur(
          adresse,
          "Installateur refusé : son empreinte SHA-256 ne correspond pas à "
          'celle de la release (fichier abîmé ou remplacé)',
          empreinteAttendue: attendue,
          empreinteObtenue: obtenue,
        );
      }
      final destination = await partiel.rename(cheminDestination);
      termine = true;
      return destination;
    } on FileSystemException catch (erreur) {
      throw ErreurSource(
        adresse,
        "Écriture de l'installateur impossible (${erreur.path ?? ''})",
        cause: erreur,
      );
    } finally {
      if (!termine) {
        try {
          await fichier?.close();
        } on FileSystemException {
          // Déjà fermé ou disque retiré : la suppression ci-dessous suffit.
        }
        try {
          if (await partiel.exists()) {
            await partiel.delete();
          }
        } on FileSystemException {
          // LIMITE : fichier verrouillé (antivirus) ; il sera remplacé au
          // prochain téléchargement (`FileMode.write` le vide).
        }
      }
    }
  }
}
