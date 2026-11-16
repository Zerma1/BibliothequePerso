/// État du lecteur : pages d'un chapitre téléchargé (lues dans l'archive),
/// texte d'un chapitre de roman, navigation entre chapitres et marquage
/// « lu ».
library;

// Les paramètres nommés ne peuvent pas être privés en Dart : on garde des
// champs privés initialisés dans la liste d'initialisation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../modeles/chapitre.dart';
import '../modeles/source.dart';
import '../modeles/telechargement.dart';
import '../modeles/titre.dart';
import '../services/service_bibliotheque.dart';
import '../services/service_telechargement.dart';
import 'constantes_etat.dart';
import 'description_erreur.dart';
import 'outils_chapitres.dart';

/// Contenu du chapitre affiché.
enum NatureContenu {
  /// Chargement en cours.
  chargement,

  /// Pages (images) lues dans l'archive.
  images,

  /// Texte d'un roman.
  texte,

  /// Chapitre seulement listé : rien à lire hors-ligne.
  nonTelecharge,

  /// Chapitre hébergé sur un site externe : il se lit seulement sur ce site
  /// (PLAYBOOK.md section 10).
  externe,
}

/// Lecteur d'un titre, ouvert sur un chapitre.
class EtatLecteur extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour ouvrir le chapitre [idChapitre].
  EtatLecteur({
    required ServiceBibliotheque serviceBibliotheque,
    required ServiceTelechargement serviceTelechargement,
    required this.idTitre,
    required int idChapitre,
  }) : _serviceBibliotheque = serviceBibliotheque,
       _serviceTelechargement = serviceTelechargement,
       _idChapitreDemande = idChapitre {
    // Si le client lance le téléchargement du chapitre depuis le lecteur, la
    // lecture démarre d'elle-même à la fin.
    _abonnement = serviceTelechargement.changements.listen(
      (_) => unawaited(_demanderRelectureFile()),
    );
  }

  final ServiceBibliotheque _serviceBibliotheque;
  final ServiceTelechargement _serviceTelechargement;
  late final StreamSubscription<void> _abonnement;

  /// Titre lu.
  final int idTitre;

  int _idChapitreDemande;

  Titre? _titre;
  Source? _source;
  List<GroupeChapitres> _groupes = const <GroupeChapitres>[];
  Chapitre? _chapitre;
  NatureContenu _nature = NatureContenu.chargement;
  int _nombrePages = 0;
  int _pageCourante = 0;
  String _texte = '';
  DescriptionErreur? _erreur;
  Telechargement? _telechargement;

  /// Pages déjà demandées, par index. Seules les pages proches de la page
  /// courante ([margePagesEnMemoire] de chaque côté) sont gardées : les
  /// autres sont relues dans l'archive si le client revient en arrière.
  final Map<int, Future<Uint8List>> _pages = <int, Future<Uint8List>>{};

  /// Chapitre protégé auprès du service (pas de suppression automatique de
  /// son archive pendant la lecture), ou `null`.
  int? _idProtege;

  /// Relecture de la file en cours, et nouvelle relecture demandée pendant
  /// celle-ci : le service prévient à chaque page téléchargée, les demandes
  /// sont regroupées.
  Future<void>? _relectureFile;
  bool _relectureFileRedemandee = false;

  /// Numéro d'ouverture de chapitre : une lecture plus ancienne (le client
  /// enchaîne vite les chapitres) est ignorée.
  int _numeroOuverture = 0;

  /// Chapitres déjà marqués lus pendant cette lecture.
  final Set<int> _idsMarques = <int>{};

  /// Titre lu, ou `null` avant le chargement.
  Titre? get titre => _titre;

  /// Site du titre, si connu.
  Source? get source => _source;

  /// `true` si les données viennent de MangaDex (crédit obligatoire).
  bool get estMangaDex => _source?.typeSource == TypeSource.mangaDex;

  /// Chapitre affiché, ou `null` avant le chargement.
  Chapitre? get chapitre => _chapitre;

  /// Nature du contenu affiché.
  NatureContenu get nature => _nature;

  /// Nombre de pages du chapitre (0 pour un texte).
  int get nombrePages => _nombrePages;

  /// Page visible (à partir de 0).
  int get pageCourante => _pageCourante;

  /// Texte lisible d'un chapitre de roman.
  String get texte => _texte;

  /// Erreur de la dernière ouverture, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// État hors-ligne du chapitre affiché (utile quand il n'est pas encore
  /// téléchargé : en file, en cours…).
  EtatHorsLigne get etatHorsLigne {
    final chapitre = _chapitre;
    if (chapitre == null) return EtatHorsLigne.nonTelecharge;
    return EtatHorsLigne.depuis(chapitre, _telechargement);
  }

  /// Chapitre précédent (numéro inférieur), ou `null`.
  Chapitre? get chapitrePrecedent => _voisin(-1);

  /// Chapitre suivant (numéro supérieur), ou `null`.
  Chapitre? get chapitreSuivant => _voisin(1);

  /// Chapitres externes qui suivent immédiatement le chapitre affiché (avant
  /// le prochain chapitre lisible ici), dans l'ordre de lecture : le bouton
  /// « Chapitre suivant » les saute, la fin du chapitre propose leur lien.
  List<Chapitre> get chapitresExternesSuivants {
    final index = _indexCourant();
    if (index < 0) return const <Chapitre>[];
    final externes = <Chapitre>[];
    for (var i = index + 1; i < _groupes.length; i++) {
      if (_groupes[i].versionLisible != null) break;
      externes.add(_groupes[i].retenu);
    }
    return externes;
  }

  /// Nom du site où se lit [chapitre] s'il est externe, sinon `null`.
  String? nomSiteExterneDe(Chapitre chapitre) =>
      chapitre.estExterne ? nomSiteExterne(chapitre.urlExterne!) : null;

  /// Index du groupe du chapitre affiché, ou -1.
  int _indexCourant() {
    final chapitre = _chapitre;
    if (chapitre == null) return -1;
    // Recherche par identifiant et non par numéro : les oneshots partagent
    // le numéro 0 mais forment chacun leur propre groupe.
    return _groupes.indexWhere(
      (g) => g.versions.any((version) => version.id == chapitre.id),
    );
  }

  /// Premier chapitre lisible dans l'application dans la direction
  /// [decalage] : les numéros publiés seulement sur un site externe sont
  /// sautés (ils ne s'ouvrent jamais dans le lecteur).
  Chapitre? _voisin(int decalage) {
    final index = _indexCourant();
    if (index < 0) return null;
    for (
      var i = index + decalage;
      i >= 0 && i < _groupes.length;
      i += decalage
    ) {
      final lisible = _groupes[i].versionLisible;
      if (lisible != null) return lisible;
    }
    return null;
  }

  /// Charge le titre, ses chapitres et ouvre le chapitre demandé.
  Future<void> charger() async {
    _erreur = null;
    _nature = NatureContenu.chargement;
    notifier();
    try {
      await _lireTitre();
      final chapitre = _trouver(_idChapitreDemande);
      if (chapitre == null) {
        _erreur = const DescriptionErreur(NatureErreur.introuvable);
        notifier();
        return;
      }
      await _ouvrir(chapitre);
    } on _Introuvable {
      _erreur = const DescriptionErreur(NatureErreur.introuvable);
      notifier();
    } catch (erreur, pile) {
      _erreur = DescriptionErreur.depuis(erreur, pile);
      notifier();
    }
  }

  Future<void> _lireTitre() async {
    final titre = await _serviceBibliotheque.chargerTitre(idTitre);
    if (titre == null) {
      throw const _Introuvable();
    }
    final idSource = titre.idSource;
    _titre = titre;
    _source = idSource == null
        ? null
        : await _serviceBibliotheque.chargerSource(idSource);
    final chapitres = await _serviceBibliotheque.chargerChapitres(idTitre);
    // Langues de ce titre (propres au titre, sinon du site, sinon réglage
    // général) : même résolution que les téléchargements automatiques.
    final langues = await _serviceBibliotheque.languesPourTitre(titre);
    // Ordre de lecture : numéros croissants, une version par numéro (celle
    // que le service télécharge, ou une autre déjà sur l'appareil).
    _groupes = regrouperParNumero(chapitres, langues);
  }

  Chapitre? _trouver(int idChapitre) {
    for (final groupe in _groupes) {
      for (final chapitre in groupe.versions) {
        if (chapitre.id == idChapitre) return chapitre;
      }
    }
    return null;
  }

  Future<void> _ouvrir(Chapitre chapitre) async {
    final numero = ++_numeroOuverture;
    _chapitre = chapitre;
    _idChapitreDemande = chapitre.id!;
    _pages.clear();
    _telechargement = null;
    _nombrePages = 0;
    _pageCourante = 0;
    _texte = '';
    _erreur = null;
    if (chapitre.estExterne) {
      // Garde-fou : la fiche et la navigation n'ouvrent jamais un chapitre
      // externe, mais s'il arrive ici, le lecteur ne lit rien et propose
      // seulement le lien vers le site de l'éditeur.
      _nature = NatureContenu.externe;
      notifier();
      return;
    }
    _proteger(chapitre.id!);
    _nature = NatureContenu.chargement;
    notifier();
    try {
      final telechargement = await _chargerTelechargement(chapitre.id!);
      if (numero != _numeroOuverture) return;
      _telechargement = telechargement;
      if (!chapitre.estTelecharge) {
        // LIMITE : la lecture en ligne d'un chapitre non téléchargé demande
        // une méthode de service qui n'existe pas encore ; le lecteur propose
        // de le télécharger ou de l'ouvrir sur le site.
        if (numero == _numeroOuverture) {
          _nature = NatureContenu.nonTelecharge;
          notifier();
        }
        return;
      }
      final pages = await _serviceTelechargement.compterPages(chapitre.id!);
      if (pages > 0) {
        if (numero != _numeroOuverture) return;
        _nombrePages = pages;
        _nature = NatureContenu.images;
      } else {
        final html = await _serviceTelechargement.lireTexte(chapitre.id!);
        if (numero != _numeroOuverture) return;
        _texte = texteLisibleDepuisHtml(html ?? '');
        _nature = NatureContenu.texte;
      }
      notifier();
    } catch (erreur, pile) {
      if (numero != _numeroOuverture) return;
      _erreur = DescriptionErreur.depuis(erreur, pile);
      notifier();
    }
  }

  /// Ligne de file du chapitre [idChapitre], sans modifier l'état :
  /// l'appelant vérifie que la réponse n'est pas périmée avant de l'appliquer.
  Future<Telechargement?> _chargerTelechargement(int idChapitre) async {
    final file = await _serviceTelechargement.chargerFile();
    return file.where((t) => t.idChapitre == idChapitre).firstOrNull;
  }

  /// Protège [idChapitre] contre les suppressions automatiques et libère le
  /// chapitre protégé précédemment.
  void _proteger(int idChapitre) {
    final ancien = _idProtege;
    if (ancien == idChapitre) return;
    _serviceTelechargement.protegerChapitre(idChapitre);
    _idProtege = idChapitre;
    if (ancien != null) {
      _serviceTelechargement.libererChapitre(ancien);
    }
  }

  /// Octets de la page [index], lus une seule fois dans l'archive tant que
  /// la page reste proche de la page courante.
  Future<Uint8List> page(int index) {
    final id = _chapitre?.id;
    if (id == null) {
      return Future<Uint8List>.error(
        const DescriptionErreur(NatureErreur.introuvable),
      );
    }
    return _pages.putIfAbsent(index, () {
      final lecture = _serviceTelechargement.lirePage(id, index);
      // Une page illisible n'est pas gardée : « Réessayer » la relit. Le
      // test d'identité évite d'effacer la page d'un autre chapitre ouvert
      // entre-temps.
      unawaited(
        lecture.then<void>(
          (_) {},
          onError: (Object _) {
            if (identical(_pages[index], lecture)) {
              _pages.remove(index);
            }
          },
        ),
      );
      return lecture;
    });
  }

  /// Oublie les octets des pages éloignées de la page courante. Une page
  /// encore affichée garde les siens (son widget les tient) ; seule la
  /// prochaine demande relira l'archive.
  void _oublierPagesEloignees() {
    _pages.removeWhere(
      (index, _) => (index - _pageCourante).abs() > margePagesEnMemoire,
    );
  }

  /// Nombre de pages actuellement gardées en mémoire (tests).
  @visibleForTesting
  int get nombrePagesEnMemoire => _pages.length;

  /// Oublie une page en échec pour la relire.
  void relirePage(int index) {
    _pages.remove(index);
    notifier();
  }

  /// Le client voit la page [index] ; à la dernière page, le chapitre est
  /// marqué lu.
  void signalerPageVisible(int index) {
    if (_nature != NatureContenu.images) return;
    if (index != _pageCourante) {
      _pageCourante = index;
      _oublierPagesEloignees();
      notifier();
    }
    if (index >= _nombrePages - 1) {
      unawaited(marquerFinLecture());
    }
  }

  /// Le client a atteint la fin du chapitre (dernière page ou fin du texte) :
  /// le chapitre est marqué lu PUIS les règles sont appliquées, ce qui fait
  /// avancer la fenêtre de téléchargement des titres suivis.
  ///
  /// Un second appel pendant le marquage renvoie le même `Future` (la
  /// dernière page et le bouton « suivant » peuvent arriver ensemble).
  Future<void> marquerFinLecture() {
    final chapitre = _chapitre;
    final id = chapitre?.id;
    if (chapitre == null || id == null) return Future<void>.value();
    final enCours = _marquages[id];
    if (enCours != null) return enCours;
    if (_idsMarques.contains(id)) return Future<void>.value();
    _idsMarques.add(id);
    // Corps en bloc : `remove` renvoie ce même Future, que `whenComplete`
    // attendrait alors indéfiniment.
    final marquage = _marquer(chapitre, id).whenComplete(() {
      _marquages.remove(id);
    });
    _marquages[id] = marquage;
    return marquage;
  }

  /// Marquages « lu » en cours, par chapitre.
  final Map<int, Future<void>> _marquages = <int, Future<void>>{};

  Future<void> _marquer(Chapitre chapitre, int id) async {
    try {
      if (!chapitre.estLu) {
        await _serviceBibliotheque.marquerLu(id);
        if (_chapitre?.id == id) {
          _chapitre = chapitre.copierAvec(estLu: true);
        }
        _remplacerDansGroupes(chapitre.copierAvec(estLu: true));
        notifier();
      }
      await _serviceTelechargement.appliquerRegles(idTitre);
    } catch (erreur, pile) {
      // L'échec du marquage ne doit pas interrompre la lecture.
      _idsMarques.remove(id);
      debugPrint('Chapitre non marqué lu : $erreur\n$pile');
    }
  }

  void _remplacerDansGroupes(Chapitre modifie) {
    _groupes = <GroupeChapitres>[
      for (final groupe in _groupes)
        GroupeChapitres(
          retenu: groupe.retenu.id == modifie.id ? modifie : groupe.retenu,
          autres: <Chapitre>[
            for (final autre in groupe.autres)
              autre.id == modifie.id ? modifie : autre,
          ],
        ),
    ];
  }

  /// Passe au chapitre suivant ; le chapitre quitté est marqué lu.
  Future<void> allerAuSuivant() async {
    final suivant = chapitreSuivant;
    if (suivant == null) return;
    await marquerFinLecture();
    await _ouvrir(suivant);
  }

  /// Revient au chapitre précédent (sans rien marquer).
  Future<void> allerAuPrecedent() async {
    final precedent = chapitrePrecedent;
    if (precedent == null) return;
    await _ouvrir(precedent);
  }

  /// Relit le chapitre affiché (bouton « Réessayer »).
  Future<void> reessayer() => charger();

  /// Ajoute le chapitre affiché à la file de téléchargement.
  Future<ResultatAction<bool>> telechargerChapitre() async {
    final id = _chapitre?.id;
    if (id == null) {
      return const ResultatAction<bool>.echec(
        DescriptionErreur(NatureErreur.introuvable),
      );
    }
    try {
      await _serviceTelechargement.telechargerChapitre(id);
      await _demanderRelectureFile();
      return const ResultatAction<bool>.reussite(true);
    } catch (erreur, pile) {
      return ResultatAction<bool>.echec(DescriptionErreur.depuis(erreur, pile));
    }
  }

  /// Relit la ligne de file du chapitre affiché. Les demandes qui arrivent
  /// pendant une relecture sont regroupées en une seule relecture à la fin.
  Future<void> _demanderRelectureFile() {
    final enCours = _relectureFile;
    if (enCours != null) {
      _relectureFileRedemandee = true;
      return enCours;
    }
    final nouvelle = _relireFile().whenComplete(() => _relectureFile = null);
    _relectureFile = nouvelle;
    return nouvelle;
  }

  Future<void> _relireFile() async {
    do {
      _relectureFileRedemandee = false;
      if (estLibere || _nature != NatureContenu.nonTelecharge) return;
      final numero = _numeroOuverture;
      final id = _chapitre?.id;
      if (id == null) return;
      try {
        final telechargement = await _chargerTelechargement(id);
        // Un autre chapitre a été ouvert entre-temps : réponse périmée.
        if (numero != _numeroOuverture) continue;
        _telechargement = telechargement;
        if (telechargement?.statut == StatutTelechargement.termine) {
          await _lireTitre();
          if (numero != _numeroOuverture) continue;
          final chapitre = _trouver(_idChapitreDemande);
          if (chapitre != null && chapitre.estTelecharge) {
            await _ouvrir(chapitre);
            continue;
          }
        }
        notifier();
      } catch (erreur, pile) {
        debugPrint('Lecteur : file illisible : $erreur\n$pile');
      }
    } while (_relectureFileRedemandee);
  }

  @override
  void dispose() {
    unawaited(_abonnement.cancel());
    final protege = _idProtege;
    if (protege != null) {
      // Lecteur fermé : le chapitre redevient supprimable par les règles.
      _serviceTelechargement.libererChapitre(protege);
      _idProtege = null;
    }
    super.dispose();
  }
}

/// Signal interne : le titre n'existe plus.
class _Introuvable implements Exception {
  const _Introuvable();
}

/// Convertit le HTML d'un chapitre de roman en texte lisible : paragraphes
/// séparés par une ligne vide, entités courantes décodées, balises retirées.
///
/// LIMITE : conversion volontairement simple, sans paquet HTML (règle du
/// client) : la mise en forme (gras, italique, images, tableaux) est perdue
/// et seules les entités les plus courantes sont décodées.
String texteLisibleDepuisHtml(String html) {
  var texte = html
      .replaceAll(RegExp(r'\r\n?'), '\n')
      // Le contenu des scripts et des styles n'est pas du texte à lire.
      .replaceAll(
        RegExp(
          r'<(script|style)[^>]*>.*?</\1\s*>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      // Les retours à la ligne du HTML ne comptent pas : seules les balises
      // de bloc créent des paragraphes.
      .replaceAll(RegExp(r'\s*\n\s*'), ' ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(
        RegExp(
          r'</?(p|div|h[1-6]|blockquote|ul|ol|section|article|hr)[^>]*>',
          caseSensitive: false,
        ),
        '\n\n',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '');
  texte = _decoderEntites(texte);
  final lignes = texte
      .split('\n')
      .map((ligne) => ligne.replaceAll(RegExp(r'[ \t ]+'), ' ').trim())
      .join('\n');
  return lignes.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _decoderEntites(String texte) {
  const nommees = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'laquo': '«',
    'raquo': '»',
    'rsquo': '’',
    'lsquo': '‘',
    'rdquo': '”',
    'ldquo': '“',
  };
  return texte.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'),
    (correspondance) {
      final code = correspondance.group(1)!;
      int? point;
      if (code.startsWith('#x') || code.startsWith('#X')) {
        point = int.tryParse(code.substring(2), radix: 16);
      } else if (code.startsWith('#')) {
        point = int.tryParse(code.substring(1));
      } else {
        return nommees[code.toLowerCase()] ?? correspondance.group(0)!;
      }
      if (point == null || point <= 0 || point > 0x10FFFF) {
        return correspondance.group(0)!;
      }
      return String.fromCharCode(point);
    },
  );
}
