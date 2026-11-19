/// Outils des tests du navigateur intégré : faux `ServiceLectureWeb` en
/// mémoire et fausse page web (scripts simulés). Aucun réseau, aucune vraie
/// vue web.
library;

import 'dart:convert';

import 'package:bibliotheque_perso/etat/etat_navigateur.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_lecture_web.dart';
import 'package:bibliotheque_perso/widgets/vue_web.dart';

/// Faux service : les chapitres sont reconnus d'après [chapitresParAdresse].
class FauxServiceLectureWeb implements ServiceLectureWeb {
  /// Chapitres connus, par adresse.
  final Map<String, Chapitre> chapitresParAdresse = <String, Chapitre>{};

  /// Appels à [quitterChapitre] (identifiants quitté → suivant).
  final List<String> sorties = <String>[];

  /// Appels à [reconnaitreChapitre] et [noterChapitreAffiche].
  final List<String> journal = <String>[];

  /// Derniers paramètres reçus par [enregistrerImagesChapitre].
  List<ImageRecue>? imagesRecues;

  /// Dernier « pages protégées » reçu.
  bool? pagesProtegeesRecues;

  /// Nombre d'appels à [enregistrerImagesChapitre].
  int nombreEnregistrements = 0;

  /// Erreur levée par [enregistrerImagesChapitre], si définie.
  Object? erreurEnregistrement;

  @override
  Future<ChapitreReconnu?> reconnaitreChapitre(
    String url, {
    int? idTitre,
  }) async {
    journal.add('reconnaitre:$url');
    final chapitre = chapitresParAdresse[url];
    return chapitre == null ? null : ChapitreConnu(chapitre);
  }

  @override
  Future<Chapitre?> noterChapitreAffiche(
    String url, {
    int? idTitre,
    String? nom,
  }) async {
    journal.add('noter:$url');
    return chapitresParAdresse[url];
  }

  @override
  Future<bool> quitterChapitre(
    Chapitre chapitreQuitte,
    Chapitre? chapitreSuivant,
  ) async {
    sorties.add('${chapitreQuitte.id}->${chapitreSuivant?.id}');
    return true;
  }

  @override
  Future<Chapitre> enregistrerImagesChapitre(
    Chapitre chapitre,
    List<ImageRecue> images, {
    bool pagesProtegees = false,
  }) async {
    nombreEnregistrements++;
    imagesRecues = images;
    pagesProtegeesRecues = pagesProtegees;
    if (pagesProtegees) {
      throw const ErreurService(messageImagesProtegees);
    }
    final erreur = erreurEnregistrement;
    if (erreur != null) throw erreur;
    return chapitre.copierAvec(estTelecharge: true);
  }
}

/// Chapitre de test.
Chapitre chapitreDeTest(int id, double numero, {bool estLu = false}) =>
    Chapitre(
      id: id,
      idTitre: 1,
      urlChapitre: 'https://site.test/manga/titre/chapitre-$id',
      nom: '',
      numero: numero,
      estLu: estLu,
    );

/// Fausse page : simule les scripts de `EtatNavigateur` à partir d'images
/// en mémoire, et les commandes de navigation.
class FaussePage implements ControleurVueWeb {
  /// Images de la page : adresse → octets.
  final Map<String, List<int>> images = <String, List<int>>{};

  /// Nombre d'images pas encore chargées annoncé par la page.
  int nonChargees = 0;

  /// Nombre de grands canvas annoncé par la page.
  int canvas = 0;

  /// Adresses d'images renvoyées comme venant du cache.
  final Set<String> enCache = <String>{};

  /// Adresses dont la lecture échoue (CORS…).
  final Set<String> refusees = <String>{};

  /// Adresses des images lues, dans l'ordre.
  final List<String> lues = <String>[];

  /// Action exécutée avant chaque lecture d'image (simuler un changement
  /// de page, une annulation…).
  void Function(String adresse)? avantLecture;

  /// Adresses chargées par [charger].
  final List<String> chargees = <String>[];

  /// Commandes reçues (reculer, avancer, recharger).
  final List<String> commandes = <String>[];

  final Map<String, String> _stock = <String, String>{};

  @override
  Future<Object?> executerScript(
    String corpsFonction, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    if (corpsFonction == EtatNavigateur.scriptListerImages) {
      return <String, Object?>{
        'adresses': images.keys.toList(),
        'nonChargees': nonChargees,
        'canvas': canvas,
      };
    }
    if (corpsFonction == EtatNavigateur.scriptLireImage) {
      final adresse = arguments['adresse']! as String;
      avantLecture?.call(adresse);
      lues.add(adresse);
      if (refusees.contains(adresse)) {
        throw const ErreurPageNavigateur('TypeError: Failed to fetch');
      }
      final base64 = base64Encode(images[adresse]!);
      _stock[arguments['cle']! as String] = base64;
      return <String, Object?>{
        'taille': base64.length,
        'depuisCache': enCache.contains(adresse),
      };
    }
    if (corpsFonction == EtatNavigateur.scriptLireBloc) {
      final texte = _stock[arguments['cle']! as String];
      if (texte == null) return null;
      final debut = arguments['debut']! as int;
      final fin = debut + (arguments['longueur']! as int);
      return texte.substring(debut, fin > texte.length ? texte.length : fin);
    }
    if (corpsFonction == EtatNavigateur.scriptLibererImage) {
      _stock.remove(arguments['cle']! as String);
      return true;
    }
    throw const ErreurPageNavigateur('script inconnu');
  }

  /// Nombre de copies d'images encore gardées dans la page.
  int get copiesRestantes => _stock.length;

  @override
  Future<void> charger(String adresse) async => chargees.add(adresse);

  @override
  Future<void> reculer() async => commandes.add('reculer');

  @override
  Future<void> avancer() async => commandes.add('avancer');

  @override
  Future<void> recharger() async => commandes.add('recharger');

  @override
  Future<bool> peutReculer() async => true;

  @override
  Future<bool> peutAvancer() async => false;
}

/// Octets d'un petit PNG (en-tête suffisant pour le faux service).
final List<int> octetsPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, //
];
