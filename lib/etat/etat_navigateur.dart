/// État du navigateur intégré (tâche N3) : adresse affichée, chapitre
/// reconnu, suivi de lecture et enregistrement des images affichées.
///
/// Règles (PLAYBOOK.md section 10) : rien n'est fait sans le client. Le
/// navigateur n'est jamais dirigé tout seul vers une autre page ; les images
/// ne sont lues dans la page qu'à la demande du client (« Enregistrer ce
/// chapitre »), d'abord dans le cache du navigateur, et jamais décodées ni
/// déchiffrées : une page dessinée dans un `canvas` est refusée.
library;

import 'dart:async';
import 'dart:convert';

import '../modeles/chapitre.dart';
import '../modeles/journal.dart';
import '../services/constantes_services.dart' show nombreMaxImagesChapitreWeb;
import '../services/service_bibliotheque.dart';
import '../services/service_lecture_web.dart';
import 'constantes_etat.dart';
import 'description_erreur.dart';

/// Page affichée par la vue web, vue depuis l'état : seul moyen de lire ce
/// que la page contient. Fournie par l'interface (vraie vue web, ou faux
/// dans les tests).
abstract interface class PageNavigateur {
  /// Exécute [corpsFonction] comme corps d'une fonction JavaScript
  /// asynchrone dans la page affichée ; chaque entrée de [arguments] y est
  /// une variable. Renvoie la valeur rendue par la fonction (nombres,
  /// textes, listes et objets JSON), ou lève une [ErreurPageNavigateur].
  Future<Object?> executerScript(
    String corpsFonction, {
    Map<String, Object?> arguments,
  });
}

/// Échec d'un script exécuté dans la page (erreur JavaScript, page fermée,
/// image refusée par le site…). Le [message] sert au journal ; le client
/// reçoit un message choisi par l'interface ([RefusEnregistrementWeb]).
class ErreurPageNavigateur implements Exception {
  /// Crée l'erreur.
  const ErreurPageNavigateur(this.message);

  /// Description technique (pour le journal).
  final String message;

  @override
  String toString() => 'ErreurPageNavigateur($message)';
}

/// Raison pour laquelle l'interface refuse d'elle-même un enregistrement
/// (avant tout appel au service, ou en cours de lecture des images). Les
/// refus du service (images protégées, image illisible…) arrivent eux dans
/// [ResultatEnregistrementWeb.erreur].
enum RefusEnregistrementWeb {
  /// La page n'est pas reconnue comme un chapitre de la bibliothèque.
  pageNonReconnue,

  /// Un enregistrement est déjà en cours.
  dejaEnCours,

  /// Des pages du chapitre ne sont pas encore chargées (chargement différé).
  pagesNonChargees,

  /// Aucune image de page trouvée.
  aucuneImage,

  /// Trop d'images pour un seul chapitre.
  tropDImages,

  /// Le site n'a pas laissé lire ses images depuis la page.
  imagesInaccessibles,

  /// Le client a changé de page pendant l'enregistrement.
  pageChangee,

  /// Le client a annulé.
  annule,
}

/// Résultat de [EtatNavigateur.enregistrerChapitre] : le chapitre enregistré,
/// un refus de l'interface ou une erreur du service. Rien n'est enregistré
/// sauf en cas de réussite.
class ResultatEnregistrementWeb {
  /// Réussite : [chapitre] tel qu'en base (téléchargé).
  const ResultatEnregistrementWeb.reussite(Chapitre this.chapitre)
    : refus = null,
      erreur = null;

  /// Refus de l'interface.
  const ResultatEnregistrementWeb.refus(RefusEnregistrementWeb this.refus)
    : chapitre = null,
      erreur = null;

  /// Erreur du service (refus clair ou erreur de base / disque).
  const ResultatEnregistrementWeb.erreur(DescriptionErreur this.erreur)
    : chapitre = null,
      refus = null;

  /// Chapitre enregistré, en cas de réussite.
  final Chapitre? chapitre;

  /// Refus de l'interface, ou `null`.
  final RefusEnregistrementWeb? refus;

  /// Erreur du service, ou `null`.
  final DescriptionErreur? erreur;

  /// `true` si le chapitre a été enregistré.
  bool get estReussi => chapitre != null;
}

/// Crée les états du navigateur intégré : fournie à l'interface (via
/// `provider`) pour que les écrans n'aient pas accès aux services
/// (PLAYBOOK.md section 4).
class FabriqueEtatNavigateur {
  /// Crée la fabrique. [serviceBibliotheque] sert seulement au nom du titre
  /// affiché dans le repère « Chapitre N de … » (sans lui, le nom est omis).
  FabriqueEtatNavigateur(this._serviceLectureWeb, {this._serviceBibliotheque});

  final ServiceLectureWeb _serviceLectureWeb;
  final ServiceBibliotheque? _serviceBibliotheque;

  /// État d'un navigateur ouvert sur [adresse], depuis la fiche du titre
  /// [idTitre] si connue.
  EtatNavigateur creer({required String adresse, int? idTitre}) =>
      EtatNavigateur(
        _serviceLectureWeb,
        adresseInitiale: adresse,
        idTitre: idTitre,
        serviceBibliotheque: _serviceBibliotheque,
      );
}

/// État d'un navigateur intégré ouvert.
///
/// La vue web signale ses événements (adresse, chargement, titre, erreur) ;
/// l'état reconnaît le chapitre affiché, le note en base, marque lu le
/// chapitre quitté pour le suivant, et enregistre les images de la page à la
/// demande du client.
class EtatNavigateur extends EtatNotifiant {
  /// Crée l'état d'un navigateur ouvert sur [adresseInitiale].
  ///
  /// [attendre] et [maintenant] permettent aux tests de ne pas attendre
  /// réellement le délai entre deux requêtes d'image.
  EtatNavigateur(
    this._service, {
    required this.adresseInitiale,
    this.idTitre,
    this._serviceBibliotheque,
    Future<void> Function(Duration duree)? attendre,
    DateTime Function()? maintenant,
  }) : _attendre = attendre ?? ((duree) => Future<void>.delayed(duree)),
       _maintenant = maintenant ?? DateTime.now,
       _adresse = adresseInitiale;

  final ServiceLectureWeb _service;
  final ServiceBibliotheque? _serviceBibliotheque;
  final Future<void> Function(Duration duree) _attendre;
  final DateTime Function() _maintenant;

  /// Adresse ouverte au départ.
  final String adresseInitiale;

  /// Titre depuis lequel le navigateur a été ouvert (ses chapitres sont
  /// reconnus en priorité), ou `null`.
  final int? idTitre;

  // ---------------------------------------------------------------- Page

  String _adresse;
  String? _titrePage;
  int _progression = 0;
  bool _peutReculer = false;
  bool _peutAvancer = false;
  String? _erreurChargement;

  /// Adresse de la page affichée.
  String get adresse => _adresse;

  /// Titre de la page affichée, ou `null`.
  String? get titrePage => _titrePage;

  /// Avancement du chargement de la page (0 à 100).
  int get progression => _progression;

  /// `true` pendant le chargement de la page.
  bool get estEnChargement => _progression < 100;

  /// `true` si la page précédente de l'historique existe.
  bool get peutReculer => _peutReculer;

  /// `true` si la page suivante de l'historique existe.
  bool get peutAvancer => _peutAvancer;

  /// Description de l'échec du chargement de la page, ou `null`.
  String? get erreurChargement => _erreurChargement;

  /// La vue web commence à charger une page.
  void signalerDebutChargement(String? adresse) {
    if (adresse != null && adresse.isNotEmpty) {
      if (_sansFragment(adresse) != _sansFragment(_adresse)) {
        // Nouvelle page : le chapitre de l'ancienne n'est plus affiché, et un
        // examen en cours de l'ancienne adresse ne compte plus.
        _oublierChapitreAffiche();
        _adresseExaminee = null;
        _numeroExamen++;
      }
      _adresse = adresse;
    }
    _progression = 0;
    _erreurChargement = null;
    notifier();
  }

  /// Avancement du chargement (0 à 100).
  void signalerProgression(int progression) {
    final bornee = progression.clamp(0, 100);
    if (bornee == _progression) return;
    _progression = bornee;
    notifier();
  }

  /// Titre de la page.
  void signalerTitrePage(String? titre) {
    _titrePage = titre;
    notifier();
  }

  /// Boutons « page précédente » et « page suivante ».
  void signalerHistorique({
    required bool peutReculer,
    required bool peutAvancer,
  }) {
    if (peutReculer == _peutReculer && peutAvancer == _peutAvancer) return;
    _peutReculer = peutReculer;
    _peutAvancer = peutAvancer;
    notifier();
  }

  /// La page principale n'a pas pu être chargée ([description] : message du
  /// moteur web).
  void signalerErreurChargement(String description) {
    _erreurChargement = description;
    _progression = 100;
    notifier();
  }

  /// Adresse saisie par le client, complétée (`https://` ajouté s'il manque)
  /// et vérifiée ; `null` si elle n'est pas une adresse web valable.
  static String? adresseDepuisSaisie(String texte) {
    final propre = texte.trim();
    if (propre.isEmpty || propre.contains(' ')) return null;
    final avecSchema = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(propre)
        ? propre
        : 'https://$propre';
    final uri = Uri.tryParse(avecSchema);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  // ---------------------------------------------------- Chapitre affiché

  ChapitreReconnu? _reconnu;
  Chapitre? _chapitre;

  /// Adresse (sans fragment) de la page pour laquelle [_chapitre] a été
  /// reconnu : « Enregistrer ce chapitre » n'est possible que si la page
  /// affichée est toujours celle-là.
  String? _adresseChapitre;

  /// Dernier chapitre affiché de chaque titre, par identifiant de titre
  /// (même si d'autres pages ont été vues depuis) : c'est lui qui est
  /// « quitté » au chapitre suivant du même titre.
  final Map<int, Chapitre> _derniersChapitres = <int, Chapitre>{};

  /// Adresse (sans fragment) déjà examinée : la vue web signale souvent deux
  /// fois la même page (historique puis fin de chargement).
  String? _adresseExaminee;

  /// Numéro d'examen : un examen plus ancien (le client enchaîne vite les
  /// pages) est ignoré.
  int _numeroExamen = 0;

  /// Noms des titres déjà lus, par identifiant.
  final Map<int, String> _nomsTitres = <int, String>{};

  /// Chapitre reconnu par son adresse, avant son enregistrement en base
  /// (sert au repère pendant l'enregistrement), ou `null`.
  ChapitreReconnu? get chapitreReconnu => _reconnu;

  /// Chapitre affiché, tel qu'en base, ou `null` si la page n'en est pas un
  /// (ou pendant la reconnaissance d'une nouvelle page).
  Chapitre? get chapitre => _chapitreDeLaPage;

  /// Nom du titre du chapitre affiché, s'il est connu.
  String? get nomTitreChapitre {
    final id = _chapitre?.idTitre ?? _reconnu?.idTitre;
    return id == null ? null : _nomsTitres[id];
  }

  /// `true` si « Enregistrer ce chapitre » est possible (page affichée
  /// reconnue, aucun enregistrement en cours).
  bool get peutEnregistrer =>
      _chapitreDeLaPage != null && !_estEnEnregistrement;

  /// Chapitre reconnu pour la page affichée maintenant, ou `null` (page non
  /// reconnue, ou reconnaissance de la nouvelle page pas encore finie).
  Chapitre? get _chapitreDeLaPage {
    final chapitre = _chapitre;
    if (chapitre == null) return null;
    if (_adresseChapitre != _sansFragment(_adresse)) return null;
    return chapitre;
  }

  /// La page affichée change : son chapitre (et le repère) sont oubliés
  /// avant tout examen de la nouvelle page.
  void _oublierChapitreAffiche() {
    _chapitre = null;
    _reconnu = null;
    _adresseChapitre = null;
  }

  /// La vue web affiche [url] (changement d'historique ou fin de
  /// chargement) : reconnaît le chapitre, le note en base, et marque lu le
  /// chapitre précédent s'il s'agit du suivant du même titre.
  ///
  /// Ne lève jamais d'erreur (le service ne le fait pas non plus).
  Future<void> signalerAdresse(String url) async {
    if (url.isEmpty) return;
    final cle = _sansFragment(url);
    if (url != _adresse) {
      // Nouvelle page (hors simple fragment) : le chapitre de l'ancienne est
      // oublié AVANT tout `await`, sinon « Enregistrer ce chapitre » resterait
      // actif sur l'ancien chapitre pendant la reconnaissance.
      if (cle != _sansFragment(_adresse)) _oublierChapitreAffiche();
      _adresse = url;
      notifier();
    }
    if (cle == _adresseExaminee) return;
    _adresseExaminee = cle;
    final numero = ++_numeroExamen;

    final reconnu = await _service.reconnaitreChapitre(url, idTitre: idTitre);
    if (numero != _numeroExamen || estLibere) return;
    _reconnu = reconnu;
    if (reconnu == null) {
      _chapitre = null;
      _adresseChapitre = null;
      notifier();
      return;
    }
    notifier();
    final chapitre = await _service.noterChapitreAffiche(url, idTitre: idTitre);
    if (numero != _numeroExamen || estLibere) return;
    _chapitre = chapitre;
    _adresseChapitre = chapitre == null ? null : cle;
    final idTitreChapitre = chapitre?.idTitre;
    if (chapitre != null && idTitreChapitre != null) {
      // Suivi par titre : A ch. 3 → B ch. 10 → A ch. 4 marque bien A ch. 3
      // lu (et B ch. 10 n'est pas « quitté » pour un chapitre d'un autre
      // titre).
      final precedent = _derniersChapitres[idTitreChapitre];
      if (precedent != null && precedent.id != chapitre.id) {
        // Sans attendre : le marquage (et les règles de téléchargement qui
        // suivent) ne retardent pas le repère du nouveau chapitre.
        unawaited(_service.quitterChapitre(precedent, chapitre));
      }
      _derniersChapitres[idTitreChapitre] = chapitre;
    }
    notifier();
    await _chargerNomTitre(chapitre?.idTitre ?? reconnu.idTitre);
  }

  Future<void> _chargerNomTitre(int idTitre) async {
    final service = _serviceBibliotheque;
    if (service == null || _nomsTitres.containsKey(idTitre)) return;
    try {
      final titre = await service.chargerTitre(idTitre);
      if (titre == null || estLibere) return;
      _nomsTitres[idTitre] = titre.nom;
      notifier();
    } catch (erreur, pile) {
      // Le repère s'affiche sans le nom : rien de bloquant.
      Journal.actuel.avertissement(
        CategorieJournal.interface,
        'Navigateur : nom du titre n°$idTitre illisible',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  static String _sansFragment(String url) {
    final diese = url.indexOf('#');
    return diese < 0 ? url : url.substring(0, diese);
  }

  // ------------------------------------------- Enregistrement du chapitre

  bool _estEnEnregistrement = false;
  int _pagesFaites = 0;
  int _pagesTotal = 0;
  bool _annulationDemandee = false;
  Completer<void>? _signalAnnulation;

  /// Dernière requête d'image (hors cache) vers chaque domaine.
  final Map<String, DateTime> _dernieresRequetes = <String, DateTime>{};

  /// `true` pendant « Enregistrer ce chapitre ».
  bool get estEnEnregistrement => _estEnEnregistrement;

  /// Pages déjà récupérées dans la page.
  int get pagesFaites => _pagesFaites;

  /// Nombre de pages à récupérer (0 tant que la page n'a pas été examinée).
  int get pagesTotal => _pagesTotal;

  /// Annule l'enregistrement en cours (rien n'est enregistré).
  void annulerEnregistrement() {
    if (!_estEnEnregistrement) return;
    _annulationDemandee = true;
    final signal = _signalAnnulation;
    if (signal != null && !signal.isCompleted) signal.complete();
    notifier();
  }

  /// « Enregistrer ce chapitre » : lit dans [page] les images affichées du
  /// chapitre (dans l'ordre du document), récupère leurs octets (cache du
  /// navigateur d'abord), puis les confie au service qui écrit l'archive.
  ///
  /// Refusé (rien d'enregistré) si la page n'est pas reconnue, si des pages
  /// ne sont pas encore chargées, si le site dessine ses pages dans un
  /// `canvas` (images protégées), si une image ne peut pas être lue, si le
  /// client change de page ou annule.
  Future<ResultatEnregistrementWeb> enregistrerChapitre(
    PageNavigateur page,
  ) async {
    // Seul le chapitre reconnu pour la page affichée MAINTENANT compte : un
    // chapitre resté d'une page précédente recevrait les images d'un autre.
    final chapitre = _chapitreDeLaPage;
    if (chapitre == null) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.pageNonReconnue,
      );
    }
    if (_estEnEnregistrement) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.dejaEnCours,
      );
    }
    _estEnEnregistrement = true;
    _annulationDemandee = false;
    _signalAnnulation = Completer<void>();
    _pagesFaites = 0;
    _pagesTotal = 0;
    notifier();
    // Égale à _adresseChapitre (vérifié par _chapitreDeLaPage).
    final adresseDepart = _sansFragment(_adresse);
    try {
      final resultat = await _enregistrer(page, chapitre, adresseDepart);
      final enregistre = resultat.chapitre;
      if (enregistre != null && !estLibere) {
        // La page affiche toujours ce chapitre : le repère passe à
        // « téléchargé ».
        if (_chapitre?.id == enregistre.id) _chapitre = enregistre;
        final idTitreEnregistre = enregistre.idTitre;
        if (idTitreEnregistre != null &&
            _derniersChapitres[idTitreEnregistre]?.id == enregistre.id) {
          _derniersChapitres[idTitreEnregistre] = enregistre;
        }
      }
      return resultat;
    } finally {
      _estEnEnregistrement = false;
      _annulationDemandee = false;
      _signalAnnulation = null;
      notifier();
    }
  }

  Future<ResultatEnregistrementWeb> _enregistrer(
    PageNavigateur page,
    Chapitre chapitre,
    String adresseDepart,
  ) async {
    // 1. Images de la page.
    final _ListeImages liste;
    try {
      liste = _ListeImages.depuis(
        await page.executerScript(
          scriptListerImages,
          arguments: <String, Object?>{
            'largeurMin': largeurMinPageNavigateur,
            'hauteurMin': hauteurMinPageNavigateur,
            'fraction': fractionLargeurPageNavigateur,
            'largeurAfficheeMin': largeurAfficheeMinPageNavigateur,
          },
        ),
      );
    } catch (erreur) {
      _journaliserEchec('liste des images impossible', erreur);
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.imagesInaccessibles,
      );
    }
    final refus = _verifierArret(adresseDepart);
    if (refus != null) return refus;

    // Pages dessinées dans un canvas : le service refuse avec son message
    // (jamais de capture ni de décodage du dessin).
    if (liste.nombreCanvas > 0) {
      return _confierAuService(
        chapitre,
        const <ImageRecue>[],
        adresseDepart,
        pagesProtegees: true,
      );
    }
    // Images `blob:` ou `data:` : typiquement des pages déchiffrées par le
    // script de l'éditeur. Jamais lues ni enregistrées : elles sont confiées
    // au service marquées protégées (sans octets), qui refuse avec son
    // message des images protégées.
    if (liste.adresses.any(_estImageEnMemoire)) {
      return _confierAuService(
        chapitre,
        <ImageRecue>[
          for (final adresseImage in liste.adresses)
            ImageRecue(
              const <int>[],
              adresse: adresseImage,
              estProtegee: _estImageEnMemoire(adresseImage),
            ),
        ],
        adresseDepart,
        pagesProtegees: false,
      );
    }
    if (liste.nombreNonChargees > 0) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.pagesNonChargees,
      );
    }
    if (liste.adresses.isEmpty) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.aucuneImage,
      );
    }
    if (liste.adresses.length > nombreMaxImagesChapitreWeb) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.tropDImages,
      );
    }
    _pagesTotal = liste.adresses.length;
    notifier();

    // 2. Octets de chaque image, une à une, dans l'ordre de lecture.
    final images = <ImageRecue>[];
    for (var index = 0; index < liste.adresses.length; index++) {
      final adresseImage = liste.adresses[index];
      final List<int> octets;
      try {
        final lu = await _lireImage(page, adresseImage, index, adresseDepart);
        if (lu == null) {
          return ResultatEnregistrementWeb.refus(
            _verifierArret(adresseDepart)?.refus ??
                RefusEnregistrementWeb.annule,
          );
        }
        octets = lu;
      } catch (erreur) {
        _journaliserEchec(
          'image ${index + 1} illisible (${_hote(adresseImage) ?? '?'})',
          erreur,
        );
        return const ResultatEnregistrementWeb.refus(
          RefusEnregistrementWeb.imagesInaccessibles,
        );
      }
      images.add(ImageRecue(octets, adresse: adresseImage));
      _pagesFaites = index + 1;
      notifier();
    }
    final arret = _verifierArret(adresseDepart);
    if (arret != null) return arret;

    // 3. Contrôle et écriture de l'archive par le service.
    return _confierAuService(
      chapitre,
      images,
      adresseDepart,
      pagesProtegees: false,
    );
  }

  /// `true` pour une image déjà en mémoire dans la page (`blob:`, `data:`),
  /// considérée comme protégée.
  static bool _estImageEnMemoire(String adresse) {
    final debut = adresse.trimLeft().toLowerCase();
    return debut.startsWith('blob:') || debut.startsWith('data:');
  }

  Future<ResultatEnregistrementWeb> _confierAuService(
    Chapitre chapitre,
    List<ImageRecue> images,
    String adresseDepart, {
    required bool pagesProtegees,
  }) async {
    // Dernière vérification avant l'écriture : la page affichée est toujours
    // celle du chapitre (sinon les images iraient dans une autre archive).
    final arret = _verifierArret(adresseDepart);
    if (arret != null) return arret;
    if (_chapitreDeLaPage?.id != chapitre.id ||
        _adresseChapitre != adresseDepart) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.pageChangee,
      );
    }
    try {
      final enregistre = await _service.enregistrerImagesChapitre(
        chapitre,
        images,
        pagesProtegees: pagesProtegees,
      );
      return ResultatEnregistrementWeb.reussite(enregistre);
    } catch (erreur, pile) {
      return ResultatEnregistrementWeb.erreur(
        DescriptionErreur.depuis(erreur, pile),
      );
    }
  }

  /// Refus si le client a annulé ou changé de page, sinon `null`.
  ResultatEnregistrementWeb? _verifierArret(String adresseDepart) {
    if (_annulationDemandee || estLibere) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.annule,
      );
    }
    if (_sansFragment(_adresse) != adresseDepart) {
      return const ResultatEnregistrementWeb.refus(
        RefusEnregistrementWeb.pageChangee,
      );
    }
    return null;
  }

  /// Octets de l'image [adresseImage], ou `null` si le client a annulé ou
  /// changé de page entre-temps. Lève une erreur si la page ne peut pas la
  /// fournir.
  Future<List<int>?> _lireImage(
    PageNavigateur page,
    String adresseImage,
    int index,
    String adresseDepart,
  ) async {
    final hote = _hote(adresseImage);
    if (hote != null) {
      // Délai par domaine, compté depuis la dernière requête qui a pu
      // atteindre le site (une image servie par le cache n'en est pas
      // une) : même règle que ClientHttpPoli.
      final derniere = _dernieresRequetes[hote];
      if (derniere != null) {
        final reste = derniere
            .add(delaiRequetesImagesNavigateur)
            .difference(_maintenant());
        if (reste > Duration.zero) {
          await Future.any<void>(<Future<void>>[
            _attendre(reste),
            if (_signalAnnulation case final signal?) signal.future,
          ]);
        }
      }
    }
    if (_verifierArret(adresseDepart) != null) return null;

    final cle = 'image$index';
    final debutRequete = _maintenant();
    var depuisCache = false;
    try {
      final reponse = await page.executerScript(
        scriptLireImage,
        arguments: <String, Object?>{'adresse': adresseImage, 'cle': cle},
      );
      if (reponse is! Map) {
        throw const ErreurPageNavigateur('réponse illisible');
      }
      final erreur = reponse['erreur'];
      if (erreur != null) throw ErreurPageNavigateur('$erreur');
      depuisCache = reponse['depuisCache'] == true;
      final taille = reponse['taille'];
      if (taille is! num || taille <= 0) {
        throw const ErreurPageNavigateur('image vide');
      }
      final base64 = StringBuffer();
      for (
        var debut = 0;
        debut < taille.toInt();
        debut += tailleBlocBase64Navigateur
      ) {
        if (_verifierArret(adresseDepart) != null) return null;
        final bloc = await page.executerScript(
          scriptLireBloc,
          arguments: <String, Object?>{
            'cle': cle,
            'debut': debut,
            'longueur': tailleBlocBase64Navigateur,
          },
        );
        if (bloc is! String) {
          throw const ErreurPageNavigateur('bloc illisible');
        }
        base64.write(bloc);
      }
      try {
        return base64Decode(base64.toString());
      } on FormatException {
        throw const ErreurPageNavigateur('base64 invalide');
      }
    } finally {
      if (hote != null && !depuisCache) {
        _dernieresRequetes[hote] = debutRequete;
      }
      // Copie de l'image libérée dans la page, même en cas d'échec.
      try {
        await page.executerScript(
          scriptLibererImage,
          arguments: <String, Object?>{'cle': cle},
        );
      } catch (_) {
        // Page fermée ou changée : la copie disparaît avec elle.
      }
    }
  }

  /// Domaine d'une adresse d'image `http(s)`, ou `null` (autre schéma :
  /// aucune requête vers un site ; les images `data:` et `blob:` sont de
  /// toute façon refusées avant d'être lues).
  static String? _hote(String adresse) {
    final uri = Uri.tryParse(adresse);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.host.isEmpty ? null : uri.host.toLowerCase();
  }

  void _journaliserEchec(String detail, Object erreur) {
    Journal.actuel.avertissement(
      CategorieJournal.interface,
      'Navigateur : enregistrement de la page impossible ($detail, '
      '${_hote(_adresse) ?? '?'})',
      erreur: erreur is ErreurPageNavigateur ? erreur.message : erreur,
    );
  }

  @override
  void dispose() {
    // Fermeture du navigateur pendant un enregistrement : il s'arrête à la
    // prochaine étape, sans rien écrire.
    _annulationDemandee = true;
    final signal = _signalAnnulation;
    if (signal != null && !signal.isCompleted) signal.complete();
    super.dispose();
  }

  // ------------------------------------------------------------- Scripts

  /// Script : adresses des images de pages affichées, dans l'ordre du
  /// document (`currentSrc`), nombre d'images de pages pas encore chargées
  /// et nombre de grands `canvas` visibles (pages protégées).
  ///
  /// Variables : `largeurMin`, `hauteurMin`, `fraction`,
  /// `largeurAfficheeMin` (voir constantes_etat.dart).
  static const String scriptListerImages = r'''
const visibles = [];
for (const img of Array.from(document.images)) {
  const style = window.getComputedStyle(img);
  if (style.display === "none" || style.visibility === "hidden") continue;
  const rect = img.getBoundingClientRect();
  visibles.push({
    adresse: img.currentSrc || img.src || "",
    largeur: img.naturalWidth,
    hauteur: img.naturalHeight,
    largeurAffichee: rect.width,
    chargee: img.complete && img.naturalWidth > 0
  });
}
const grandes = visibles.filter(function (i) {
  return i.chargee && i.adresse && i.largeur >= largeurMin && i.hauteur >= hauteurMin;
});
let largeurMax = 0;
for (const i of grandes) largeurMax = Math.max(largeurMax, i.largeur);
const pages = grandes.filter(function (i) { return i.largeur >= largeurMax * fraction; });
let afficheeMax = 0;
for (const i of pages) afficheeMax = Math.max(afficheeMax, i.largeurAffichee);
const seuilAffiche = Math.max(afficheeMax * fraction, largeurAfficheeMin);
const nonChargees = visibles.filter(function (i) {
  return (!i.chargee || i.largeur < largeurMin) && i.largeurAffichee >= seuilAffiche;
}).length;
let canvas = 0;
for (const c of Array.from(document.querySelectorAll("canvas"))) {
  const rect = c.getBoundingClientRect();
  if (c.width >= largeurMin && c.height >= hauteurMin && rect.width > 0 && rect.height > 0) canvas++;
}
return { adresses: pages.map(function (i) { return i.adresse; }), nonChargees: nonChargees, canvas: canvas };
''';

  // LIMITE : `fetch` depuis la page est soumis à CORS. Si les images sont
  // servies par un autre domaine (CDN) sans en-tête
  // `Access-Control-Allow-Origin`, la récupération échoue (« Failed to
  // fetch ») même si l'image est affichée et en cache : l'enregistrement est
  // alors refusé avec « Ce site ne laisse pas récupérer ses images »
  // (RefusEnregistrementWeb.imagesInaccessibles). Aucun contournement
  // (pas de mode `no-cors`, dont la réponse est opaque et vide).

  /// Script : récupère l'image `adresse` (cache du navigateur d'abord),
  /// garde son contenu base64 dans la page sous `cle`, et renvoie sa taille
  /// et si elle venait du cache (`{taille, depuisCache}`), ou `{erreur}`.
  static const String scriptLireImage = r'''
const stock = (window.__bibliothequePerso = window.__bibliothequePerso || {});
const debut = performance.now();
const reponse = await fetch(adresse, { cache: "force-cache" });
if (!reponse.ok) return { erreur: "HTTP " + reponse.status };
const blob = await reponse.blob();
const base64 = await new Promise(function (ok, ko) {
  const lecteur = new FileReader();
  lecteur.onload = function () { ok(String(lecteur.result).split(",")[1] || ""); };
  lecteur.onerror = function () { ko(lecteur.error); };
  lecteur.readAsDataURL(blob);
});
let depuisCache = false;
try {
  const entrees = performance.getEntriesByName(reponse.url || adresse);
  const entree = entrees[entrees.length - 1];
  depuisCache = !!entree && entree.startTime >= debut - 1 &&
    entree.transferSize === 0 && entree.decodedBodySize > 0;
} catch (e) {}
stock[cle] = base64;
return { taille: base64.length, depuisCache: depuisCache };
''';

  /// Script : morceau `[debut, debut + longueur[` du contenu base64 gardé
  /// sous `cle`, ou `null`.
  static const String scriptLireBloc = r'''
const stock = window.__bibliothequePerso || {};
const texte = stock[cle];
if (typeof texte !== "string") return null;
return texte.substring(debut, debut + longueur);
''';

  /// Script : oublie le contenu gardé sous `cle`.
  static const String scriptLibererImage = r'''
if (window.__bibliothequePerso) delete window.__bibliothequePerso[cle];
return true;
''';
}

/// Résultat de [EtatNavigateur.scriptListerImages], vérifié.
class _ListeImages {
  const _ListeImages(this.adresses, this.nombreNonChargees, this.nombreCanvas);

  /// Lit la réponse du script ; lève une [ErreurPageNavigateur] si elle n'a
  /// pas la forme attendue.
  factory _ListeImages.depuis(Object? reponse) {
    if (reponse is! Map) {
      throw const ErreurPageNavigateur('liste des images illisible');
    }
    final adresses = reponse['adresses'];
    final nonChargees = reponse['nonChargees'];
    final canvas = reponse['canvas'];
    if (adresses is! List || nonChargees is! num || canvas is! num) {
      throw const ErreurPageNavigateur('liste des images illisible');
    }
    return _ListeImages(
      <String>[
        for (final adresse in adresses)
          if (adresse is String && adresse.isNotEmpty) adresse,
      ],
      nonChargees.toInt(),
      canvas.toInt(),
    );
  }

  final List<String> adresses;
  final int nombreNonChargees;
  final int nombreCanvas;
}
