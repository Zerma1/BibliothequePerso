/// Journal de l'application (log) : ce qui s'est passé pendant un essai du
/// client, pour qu'il puisse joindre le fichier à ses retours.
///
/// Ce fichier ne contient que l'**interface** : il est dans `modeles/` pour
/// que toutes les couches (sources, données, services, états, écrans) puissent
/// journaliser sans dépendre de `dart:io`. L'écriture sur disque est faite par
/// `JournalFichier` (`lib/donnees/journal_fichier.dart`), installé au
/// démarrage dans [Journal.actuel].
///
/// Utilisation, depuis n'importe quelle couche :
///
/// ```dart
/// Journal.actuel.info(CategorieJournal.reseau, 'GET $url : 200 (120 ms)');
/// Journal.actuel.erreur(
///   CategorieJournal.telechargement,
///   'Chapitre $id abandonné',
///   erreur: e,
///   pile: pile,
/// );
/// ```
///
/// Règles :
/// - un message court, sur une ligne, sans contenu de page complet (le
///   journal de fichier coupe de toute façon les messages trop longs) ;
/// - les données sensibles sont masquées à l'écriture
///   ([masquerDonneesSensibles]), mais mieux vaut ne pas les y mettre ;
/// - journaliser ne lève jamais d'exception et ne bloque jamais l'appelant.
library;

/// Niveau d'importance d'une entrée du journal, du moins au plus grave.
///
/// L'ordre de déclaration sert aux comparaisons ([estAuMoins]) : ne pas le
/// changer.
enum NiveauJournal {
  /// Détail utile seulement pour déboguer (désactivé par défaut).
  debogage('DEBUG'),

  /// Étape normale (démarrage, requête, téléchargement terminé…).
  info('INFO'),

  /// Problème sans gravité ou contourné (nouvel essai, site lent…).
  avertissement('AVERT'),

  /// Échec d'une opération (avec l'erreur et la pile si elles existent).
  erreur('ERREUR');

  const NiveauJournal(this.etiquette);

  /// Étiquette écrite dans le fichier (`INFO`, `ERREUR`…).
  final String etiquette;

  /// `true` si ce niveau est au moins aussi grave que [autre].
  bool estAuMoins(NiveauJournal autre) => index >= autre.index;

  /// Niveau dont le nom Dart (`info`) ou l'[etiquette] (`INFO`) vaut
  /// [texte], sans tenir compte de la casse ; `null` s'il n'existe pas.
  ///
  /// Sert à relire un réglage enregistré en texte.
  static NiveauJournal? depuisTexte(String? texte) {
    if (texte == null) return null;
    final cherche = texte.trim().toLowerCase();
    for (final niveau in values) {
      if (niveau.name.toLowerCase() == cherche ||
          niveau.etiquette.toLowerCase() == cherche) {
        return niveau;
      }
    }
    return null;
  }
}

/// Catégories courtes d'une entrée du journal (la partie de l'application
/// concernée).
///
/// Ce sont de simples textes : une couche peut en utiliser une autre si
/// aucune ne convient, mais on préfère celles-ci pour pouvoir filtrer le
/// fichier (`reseau`, `telechargement`…).
abstract final class CategorieJournal {
  /// Requêtes HTTP (`ClientHttpPoli`).
  static const String reseau = 'reseau';

  /// Lecture d'un site (adaptateurs de `lib/sources/`).
  static const String sources = 'sources';

  /// File de téléchargement et archives des chapitres.
  static const String telechargement = 'telechargement';

  /// Recherche des nouveaux chapitres (application et tâche de fond).
  static const String misesAJour = 'misesAJour';

  /// Titres, listes, catégories, ajout d'un titre ou d'un site.
  static const String bibliotheque = 'bibliotheque';

  /// Actions de l'utilisateur et erreurs affichées à l'écran.
  static const String interface = 'interface';

  /// Démarrage et arrêt de l'application ou de la tâche de fond.
  static const String demarrage = 'demarrage';

  /// Base SQLite (ouverture, migrations, transactions).
  static const String base = 'base';

  /// Fichiers sur le disque (dossier des chapitres, NAS, couvertures).
  static const String stockage = 'stockage';

  /// Réglages du client.
  static const String parametres = 'parametres';

  /// Export et import des sauvegardes.
  static const String export = 'export';
}

/// Journal de l'application : interface commune à toutes les
/// implémentations.
///
/// Une implémentation ne redéfinit que [journaliser] (et, si besoin,
/// [estActif], [vider] et [fermer]) ; les raccourcis [debogage], [info],
/// [avertissement] et [erreur] passent tous par [journaliser].
///
/// Contrat : aucune méthode ne lève d'exception ni ne bloque l'appelant (une
/// écriture qui échoue est ignorée).
abstract class Journal {
  /// Constructeur constant, pour les implémentations sans état
  /// ([JournalSilencieux]).
  const Journal();

  /// Journal utilisé par toute l'application.
  ///
  /// Silencieux par défaut (rien n'est écrit) : les tests et le code lancé
  /// avant l'installation du journal de fichier n'ont rien à faire. Remplacé
  /// une seule fois au démarrage de chaque isolat (application, tâche de
  /// fond Android) ; un test peut y mettre un [JournalMemoire] puis remettre
  /// un [JournalSilencieux] dans son `tearDown`.
  ///
  /// Chaque isolat a sa propre copie de cette variable : la tâche de fond
  /// Android doit installer son propre journal.
  static Journal actuel = const JournalSilencieux();

  /// Ajoute une entrée de [niveau] dans la [categorie] donnée.
  ///
  /// [erreur] et [pile] complètent le [message] quand une exception est à
  /// l'origine de l'entrée. Ne lève jamais d'exception.
  void journaliser(
    NiveauJournal niveau,
    String categorie,
    String message, {
    Object? erreur,
    StackTrace? pile,
  });

  /// `true` si une entrée de [niveau] serait réellement écrite.
  ///
  /// Permet d'éviter de construire un message coûteux qui serait ignoré
  /// (`if (Journal.actuel.estActif(NiveauJournal.debogage)) …`).
  bool estActif(NiveauJournal niveau) => true;

  /// Entrée de débogage : détail utile seulement pour chercher un problème.
  void debogage(String categorie, String message) =>
      journaliser(NiveauJournal.debogage, categorie, message);

  /// Entrée d'information : étape normale du fonctionnement.
  void info(String categorie, String message) =>
      journaliser(NiveauJournal.info, categorie, message);

  /// Avertissement : problème sans gravité ou contourné.
  void avertissement(
    String categorie,
    String message, {
    Object? erreur,
    StackTrace? pile,
  }) => journaliser(
    NiveauJournal.avertissement,
    categorie,
    message,
    erreur: erreur,
    pile: pile,
  );

  /// Erreur : une opération a échoué. [erreur] et [pile] sont écrites sous
  /// le message.
  void erreur(
    String categorie,
    String message, {
    Object? erreur,
    StackTrace? pile,
  }) => journaliser(
    NiveauJournal.erreur,
    categorie,
    message,
    erreur: erreur,
    pile: pile,
  );

  /// Attend que les entrées déjà reçues soient écrites (rien à faire par
  /// défaut). Ne lève jamais d'exception.
  Future<void> vider() async {}

  /// Écrit les entrées en attente puis libère les ressources (rien à faire
  /// par défaut). Les entrées reçues ensuite sont ignorées.
  Future<void> fermer() async {}
}

/// Journal qui n'écrit rien : valeur par défaut de [Journal.actuel].
class JournalSilencieux extends Journal {
  /// Crée un journal silencieux.
  const JournalSilencieux();

  @override
  void journaliser(
    NiveauJournal niveau,
    String categorie,
    String message, {
    Object? erreur,
    StackTrace? pile,
  }) {}

  @override
  bool estActif(NiveauJournal niveau) => false;
}

/// Une entrée reçue par un [JournalMemoire].
class EntreeJournal {
  /// Crée une entrée.
  const EntreeJournal({
    required this.niveau,
    required this.categorie,
    required this.message,
    this.erreur,
    this.pile,
  });

  /// Niveau de l'entrée.
  final NiveauJournal niveau;

  /// Catégorie courte ([CategorieJournal]).
  final String categorie;

  /// Message tel que reçu (non masqué).
  final String message;

  /// Erreur jointe, si elle existe.
  final Object? erreur;

  /// Pile jointe, si elle existe.
  final StackTrace? pile;

  @override
  bool operator ==(Object other) =>
      other is EntreeJournal &&
      other.niveau == niveau &&
      other.categorie == categorie &&
      other.message == message &&
      other.erreur == erreur &&
      other.pile == pile;

  @override
  int get hashCode => Object.hash(niveau, categorie, message, erreur, pile);

  @override
  String toString() => '${niveau.etiquette} $categorie : $message';
}

/// Journal qui garde les entrées en mémoire, pour les tests des autres
/// couches (« tel appel a bien journalisé telle erreur »).
class JournalMemoire extends Journal {
  /// Crée un journal en mémoire qui garde les entrées d'au moins
  /// [niveauMinimal] (toutes par défaut).
  JournalMemoire({this.niveauMinimal = NiveauJournal.debogage});

  /// Niveau minimal des entrées gardées.
  NiveauJournal niveauMinimal;

  /// Entrées reçues, dans l'ordre.
  final List<EntreeJournal> entrees = [];

  @override
  bool estActif(NiveauJournal niveau) => niveau.estAuMoins(niveauMinimal);

  @override
  void journaliser(
    NiveauJournal niveau,
    String categorie,
    String message, {
    Object? erreur,
    StackTrace? pile,
  }) {
    if (!estActif(niveau)) return;
    entrees.add(
      EntreeJournal(
        niveau: niveau,
        categorie: categorie,
        message: message,
        erreur: erreur,
        pile: pile,
      ),
    );
  }
}

/// Texte de remplacement d'une valeur sensible masquée.
const String valeurMasqueeJournal = '***';

/// Mots qui rendent sensible un paramètre de requête ou un champ JSON dont le
/// nom les contient (sans tenir compte de la casse) : `token`,
/// `access_token`, `apiKey`, `password`, `PHPSESSID`, `auth_code`…
///
/// `auth` seul n'y est pas : il masquerait aussi `author` / `authors[]`
/// (filtres MangaDex), utiles pour comprendre une requête. `sid` non plus :
/// il masquerait `side` ou `inside` ; il est traité à part
/// ([motsSeparesSensiblesJournal]).
const List<String> motsSensiblesJournal = [
  'token',
  'key',
  'pass',
  'pwd',
  'secret',
  'session',
  'sessid',
  'auth_',
  '_auth',
  'authorization',
  'signature',
  'cookie',
  'csrf',
];

/// En-têtes HTTP dont la valeur est toujours masquée.
const List<String> enTetesSensiblesJournal = [
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'x-auth-token',
  'x-csrf-token',
];

/// Mots sensibles seulement quand ils forment le nom entier ou un morceau
/// séparé du nom (`sid`, `connect.sid`, `user_sid`, mais pas `side`,
/// `inside` ni `consider`).
const List<String> motsSeparesSensiblesJournal = ['sid'];

/// Motif des noms sensibles : un mot de [motsSensiblesJournal] n'importe
/// où, ou un mot de [motsSeparesSensiblesJournal] sans lettre ni chiffre
/// collé avant et sans lettre collée après.
final String _motifMots = [
  ...motsSensiblesJournal.map(RegExp.escape),
  for (final mot in motsSeparesSensiblesJournal)
    '(?<![a-z0-9])${RegExp.escape(mot)}(?![a-z])',
].join('|');

/// `?token=abc` ou `&api_key=abc` (le nom du paramètre contient un mot
/// sensible) : on garde le nom, on masque la valeur.
final RegExp _parametreSensible = RegExp(
  '([?&;][^=&#\\s"\']*(?:$_motifMots)[^=&#\\s"\']*=)[^&#\\s"\']*',
  caseSensitive: false,
);

/// `Authorization: Bearer abc` ou `cookie=a=b; c=d` dans un texte ou dans
/// l'affichage d'une `Map` d'en-têtes (`{Cookie: a=b, Accept: …}`) : la
/// valeur s'arrête à la fin de ligne, à une virgule ou à une accolade.
final RegExp _enTeteSensible = RegExp(
  '\\b(${enTetesSensiblesJournal.map(RegExp.escape).join('|')})'
  '(["\']?\\s*[:=]\\s*)[^,\\r\\n}]+',
  caseSensitive: false,
);

/// `"password": "abc"` dans un JSON (le nom contient un mot sensible).
final RegExp _champJsonSensible = RegExp(
  '("[^"]*(?:$_motifMots)[^"]*"\\s*:\\s*)"(?:[^"\\\\]|\\\\.)*"',
  caseSensitive: false,
);

/// `Bearer abc…` isolé (sans le nom de l'en-tête, déjà traité par
/// [_enTeteSensible]) : masqué seulement si la valeur fait au moins 20
/// caractères, longueur d'un vrai jeton. Un texte ordinaire comme
/// « Basic Instinct » (titre d'œuvre) reste lisible.
final RegExp _jetonPorteur = RegExp(
  r'\b(Bearer|Basic)\s+[A-Za-z0-9\-._~+/]{20,}=*',
  caseSensitive: false,
);

/// Jeton de session MangaDex placé dans le chemin des images, avec ou sans
/// port : `https://xyz.mangadex.network:44300/<jeton>/data/<hash>/<page>`.
final RegExp _jetonCheminMangaDex = RegExp(
  r'(\.mangadex\.network(?::\d+)?/)[^/\s]+(/data(?:-saver)?/)',
  caseSensitive: false,
);

/// Identifiants placés dans une URL : `https://utilisateur:motdepasse@hote`.
/// Le schéma est gardé ; l'utilisateur et le mot de passe sont masqués
/// ensemble. Une adresse sans `:` avant le `@` n'est pas touchée.
final RegExp _identifiantsUrl = RegExp(
  r'(\b[a-z][a-z0-9+.\-]*://)[^/?#\s:@]*:[^/?#\s@]*@',
  caseSensitive: false,
);

/// Renvoie [texte] où les données sensibles sont remplacées par
/// [valeurMasqueeJournal].
///
/// Masque :
/// - la valeur des paramètres de requête dont le nom contient un mot de
///   [motsSensiblesJournal] ou de [motsSeparesSensiblesJournal]
///   (`?token=***`, `&api_key=***`, `&sid=***`) ;
/// - la valeur des en-têtes de [enTetesSensiblesJournal]
///   (`Authorization: ***`, `Cookie: ***`) ;
/// - les champs JSON sensibles (`"password": "***"`) ;
/// - les jetons `Bearer …` et `Basic …` isolés d'au moins 20 caractères ;
/// - les identifiants d'une URL (`https://***@hote`) ;
/// - le jeton de session MangaDex dans le chemin des images.
///
/// Le reste du texte est inchangé. Pure et sans exception : utilisable par
/// toutes les couches.
String masquerDonneesSensibles(String texte) {
  if (texte.isEmpty) return texte;
  var resultat = texte;
  resultat = resultat.replaceAllMapped(
    _enTeteSensible,
    (m) => '${m[1]}${m[2]}$valeurMasqueeJournal',
  );
  resultat = resultat.replaceAllMapped(
    _jetonPorteur,
    (m) => '${m[1]} $valeurMasqueeJournal',
  );
  resultat = resultat.replaceAllMapped(
    _champJsonSensible,
    (m) => '${m[1]}"$valeurMasqueeJournal"',
  );
  resultat = resultat.replaceAllMapped(
    _parametreSensible,
    (m) => '${m[1]}$valeurMasqueeJournal',
  );
  resultat = resultat.replaceAllMapped(
    _identifiantsUrl,
    (m) => '${m[1]}$valeurMasqueeJournal@',
  );
  resultat = resultat.replaceAllMapped(
    _jetonCheminMangaDex,
    (m) => '${m[1]}$valeurMasqueeJournal${m[2]}',
  );
  return resultat;
}
