/// Constantes de la couche services (valeurs par défaut des règles du
/// client, nombres d'essais), regroupées pour ne pas laisser de valeurs
/// « magiques » dans le code.
library;

/// Langues de lecture du client tant qu'il n'en a pas choisi (français puis
/// anglais).
const List<String> languesParDefautClient = <String>['fr', 'en'];

/// Favoris : chapitres lus gardés sur l'appareil, par défaut (choix du
/// client).
const int favorisLusConservesParDefaut = 10;

/// Suivis : chapitres téléchargés au départ, par défaut (choix du client).
const int suivisInitialParDefaut = 10;

/// Suivis : chapitres gardés jusqu'au dernier lu, par défaut (choix du
/// client).
const int suivisAvantParDefaut = 5;

/// Suivis : chapitres téléchargés après le dernier lu, par défaut (choix du
/// client).
const int suivisApresParDefaut = 5;

/// Minimum pour « avant » et « après » des suivis : avec 0, le chapitre que
/// le client vient de lire (ou le suivant) ne serait jamais sur l'appareil.
const int minimumSuivisAvantApres = 1;

/// Extension donnée à une image dont l'adresse n'en indique pas : le JPEG est
/// le format le plus courant sur les sites de lecture.
const String extensionImageParDefaut = 'jpg';

/// Essais pour une page : le premier, puis un second après avoir redemandé
/// les adresses des images (adresse MangaDex expirée, serveur en panne).
const int nombreEssaisParPage = 2;

/// Délai avant la suppression d'une archive décidée par les règles de
/// conservation (décision du client du 2026-11-15) : le client a le temps de
/// la garder ou de la supprimer tout de suite.
///
/// Valeur par défaut du réglage « Durée de conservation avant suppression »
/// (`ServiceParametres.chargerDelaiSuppression`, demande du client du
/// 2026-11-25) ; sert aussi au repli quand le réglage ne peut pas être lu.
const Duration delaiSuppressionDifferee = Duration(hours: 24);

/// Plus petit délai de suppression accepté. Pas de suppression immédiate
/// (0 h) : une archive sortie des règles par erreur (mauvais réglage, liste
/// retirée par mégarde, site qui renvoie une liste de chapitres incomplète)
/// serait effacée avant que le client ait pu la voir en rouge et la garder.
/// Une heure laisse ce temps ; « Supprimer maintenant » reste disponible.
const Duration delaiSuppressionDiffereeMinimum = Duration(hours: 1);

/// Plus grand délai de suppression accepté (demande du client).
const Duration delaiSuppressionDiffereeMaximum = Duration(days: 30);

/// Crans proposés pour la jauge « Durée de conservation avant suppression »,
/// du plus court au plus long (bornes comprises, défaut parmi eux).
const List<Duration> delaisSuppressionDiffereeProposes = <Duration>[
  Duration(hours: 1),
  Duration(hours: 6),
  Duration(hours: 12),
  Duration(hours: 24),
  Duration(days: 2),
  Duration(days: 3),
  Duration(days: 7),
  Duration(days: 14),
  Duration(days: 30),
];

/// Délai dont est repoussée la suppression prévue d'un chapitre ouvert dans
/// le lecteur (`ServiceTelechargement.protegerChapitre`). Ce n'est pas le
/// réglage de conservation : c'est une protection pour la tâche de fond
/// Android, qui ne voit pas les chapitres ouverts. Il reste fixe pour qu'un
/// délai de conservation court (1 h) n'expose pas une lecture en cours, et
/// qu'un délai long (30 j) ne reporte pas d'un mois une suppression presque
/// échue simplement parce que le chapitre a été ouvert.
const Duration delaiProtectionLecture = Duration(hours: 24);

/// Échecs d'un même chapitre au-delà desquels les règles ne le relancent
/// plus automatiquement (le client peut toujours le relancer à la main) :
/// évite de solliciter sans fin un site qui refuse ce chapitre.
const int nombreMaximalEchecsAutomatiques = 3;

/// Nombre de blocs aléatoires de l'identifiant d'un service dans le verrou
/// de la file : 4 × 32 bits rendent une collision entre deux isolats
/// impossible en pratique.
const int nombreBlocsIdentifiantVerrou = 4;

/// Borne (exclue) d'un bloc aléatoire de l'identifiant : 2^32, la plus grande
/// valeur acceptée par `Random.nextInt`.
const int borneBlocIdentifiantVerrou = 1 << 32;

/// Base d'écriture d'un bloc de l'identifiant (hexadécimal, plus court).
const int baseBlocIdentifiantVerrou = 16;

/// Largeur d'un bloc de l'identifiant : 8 chiffres hexadécimaux pour 32 bits,
/// complétés par des zéros pour que tous les identifiants aient la même
/// longueur.
const int largeurBlocIdentifiantVerrou = 8;

/// Le verrou de la file est renouvelé pendant un chapitre au plus une fois
/// par tiers de sa durée : assez souvent pour qu'il n'expire jamais entre
/// deux pages, sans écrire en base à chaque page.
const int fractionRenouvellementVerrou = 3;

/// Téléchargements de chapitres simultanés tant que le client n'a rien
/// choisi (Paramètres). Trois chapitres avancent en même temps : de quoi
/// profiter de plusieurs sites à la fois sans multiplier les archives
/// partielles en cas d'interruption.
const int telechargementsSimultanesParDefaut = 3;

/// Minimum du réglage des téléchargements simultanés : un chapitre à la fois
/// (comportement des versions précédentes).
const int telechargementsSimultanesMinimum = 1;

/// Maximum du réglage des téléchargements simultanés (demande du client).
/// Le rythme des requêtes vers un même site ne change pas pour autant :
/// `ClientHttpPoli` garde 1 s entre deux requêtes **par domaine**, partagé
/// par tous les chapitres en cours. Le parallélisme ne fait gagner du temps
/// que lorsque les chapitres viennent de sites différents.
const int telechargementsSimultanesMaximum = 32;

/// Plafond des téléchargements simultanés dans la tâche de fond Android
/// (décision du 2026-11-19). Android l'interrompt au bout d'environ
/// 10 minutes : chaque chapitre coupé laisse une archive partielle et une
/// ligne « en cours », reprises de zéro une durée de verrou plus tard. Avec
/// 32 chapitres ouverts, une interruption gâcherait jusqu'à 32 chapitres de
/// requêtes déjà faites (PLAYBOOK.md section 10) ; 4 limite cette perte tout
/// en avançant sur plusieurs sites à la fois.
const int telechargementsSimultanesTacheDeFond = 4;

/// Marge ajoutée à l'expiration d'un verrou avant un nouvel essai : on
/// réessaie juste **après** l'expiration, pas pile dessus (sinon le verrou
/// serait encore considéré comme pris).
const Duration margeNouvelEssaiVerrou = Duration(seconds: 1);

/// Attente minimale avant un nouvel essai de la file : évite de relire la
/// base en boucle si le verrou de l'autre isolat expire tout de suite.
const Duration attenteMinimaleNouvelEssai = Duration(seconds: 5);

/// Attente avant de réessayer la file quand le dossier des chapitres est
/// inaccessible (NAS éteint, lecteur réseau déconnecté) : un seul essai
/// prévu à la fois, qui ne fait qu'un contrôle sur le disque (aucune
/// requête vers les sites). Assez court pour reprendre vite quand le NAS
/// revient, assez long pour ne pas attendre sans cesse un partage réseau
/// qui met plusieurs secondes à répondre.
const Duration attenteNouvelEssaiDossierInaccessible = Duration(minutes: 2);

/// Contrôle des archives manquantes sur un dossier choisi par le client
/// (lecteur réseau, NAS) : au-delà de ce nombre d'archives manquantes
/// d'affilée, le contrôle s'arrête sans rien remettre à « non téléchargé ».
/// Un partage instable (qui répond « fichier absent » par moments) ferait
/// sinon retélécharger toute la bibliothèque ; une vraie suppression de plus
/// de 20 chapitres de suite est rare et reste visible (lecture impossible).
const int nombreMaximalArchivesManquantesDAffilee = 20;

/// Titres « En attente » : vérifiés toutes les N heures pleines, par défaut
/// à chaque heure (décision de l'étape 6 : surveillance accrue des titres
/// qui n'ont encore aucun chapitre dans les langues du client).
const int heuresEnAttenteParDefaut = 1;

/// Nom du sous-dossier des rapports d'erreur exportés, dans le dossier
/// racine de l'application (`Documents/bibliotheque_perso/rapports/`).
const String nomDossierRapports = 'rapports';

/// Nombre maximal de rapports d'erreur gardés sur l'appareil : les plus
/// anciens sont effacés au-delà, pour que le dossier ne grossisse pas sans
/// fin.
const int nombreMaximalRapports = 50;

/// Nombre de lignes de la fin du journal jointes à un rapport d'erreur :
/// assez pour voir ce qui a précédé l'erreur (requêtes, étapes), assez peu
/// pour que le rapport reste lisible.
const int nombreLignesJournalRapport = 200;

/// Délai maximal accordé au journal pour écrire ses entrées en attente puis
/// être relu, avant un export du journal ou un rapport d'erreur. Écrire un
/// lot prend quelques millisecondes : au-delà de quelques secondes, le
/// journal est bloqué (disque plein, fichier verrouillé) et l'export ou le
/// rapport continue sans les entrées en attente plutôt que d'attendre sans
/// fin.
const Duration delaiMaxJournal = Duration(seconds: 3);

/// Préfixe du nom d'un journal exporté
/// (`journal_export_20261118_143000.log`), dans le dossier des rapports.
const String prefixeFichierJournalExporte = 'journal_export_';

/// Nombre de jours de journaux copiés par « Exporter le journal », par
/// défaut (aujourd'hui seulement).
const int joursJournalExportesParDefaut = 1;

/// Nombre maximal de journaux exportés gardés dans le dossier des rapports :
/// les plus anciens sont effacés au-delà (chaque export peut peser
/// plusieurs Mo).
const int nombreMaximalJournauxExportes = 20;

/// Extension d'un journal exporté.
const String extensionFichierJournalExporte = 'log';

/// Nombre maximal de jours copiés par « Exporter le journal » : le dossier
/// n'en garde de toute façon que 14 (`joursConservationJournaux`).
const int joursJournalExportesMaximum = 14;

/// Nombre minimal de jours copiés par « Exporter le journal » (aujourd'hui).
const int joursJournalExportesMinimum = 1;

/// Préfixe du nom d'un rapport d'erreur (`rapport_20261116_143000.txt`).
const String prefixeFichierRapport = 'rapport_';

/// Extension des rapports d'erreur exportés.
const String extensionFichierRapport = 'txt';

/// Nom du sous-dossier des exports de la bibliothèque (tâche R7), dans le
/// dossier racine des téléchargements (`Documents/bibliotheque_perso/exports/`).
const String nomDossierExports = 'exports';

/// Préfixe du nom d'un export (`bibliotheque_perso-export-2026-11-16_1430.json`).
const String prefixeFichierExport = 'bibliotheque_perso-export-';

/// Valeur du champ `format` du JSON exporté : permet à l'import (R8) de
/// reconnaître un fichier de l'application avant de le lire.
const String identifiantFormatExport = 'bibliotheque_perso-export';

/// Version du format JSON exporté : l'import (R8) s'en sert pour lire les
/// anciens fichiers et refuser ceux d'une version plus récente.
///
/// - 1 : format de la tâche R7.
/// - 2 : ajout compatible de `sources[].configurationSelecteurs` et
///   `titres[].resume`, nécessaires pour recréer un site générique et une
///   fiche complète sans requête réseau. Augmentée malgré la compatibilité
///   pour que l'import sache si un champ absent est vide ou seulement
///   inconnu de l'ancien format.
/// - 3 : ajout compatible de `equivalences` (regroupements de catégories de
///   même sens, migration 9 : `categorie` et `reference`, par nom). Les
///   formats 1 et 2 restent lisibles (aucun regroupement importé).
/// - 4 : ajouts compatibles de `titres[].champsManuels` (champs modifiés à
///   la main, migration 10 : noms de `ChampTitre`) et de
///   `reglages.archiveComplete` (booléen). Les formats 1 à 3 restent
///   lisibles (aucun champ verrouillé, réglage absent).
/// - 5 : ajout compatible de `titres[].descriptionPerso` (description
///   personnelle du client, migration 12). Les formats 1 à 4 restent
///   lisibles (aucune description importée).
const int versionFormatExport = 5;

/// Longueur maximale (en caractères) du nom d'une liste du client : assez
/// pour un nom parlant, assez court pour tenir dans un onglet ou un menu.
const int longueurMaxNomListe = 60;

/// Longueur maximale (en caractères) de la description personnelle d'un
/// titre : quelques paragraphes d'avis ou de notes tiennent largement ; la
/// borne protège d'un collage accidentel d'un texte entier.
const int longueurMaxDescriptionPerso = 5000;

/// Durée pendant laquelle un chapitre non lu porte le badge « Nouveau »
/// dans l'onglet Mises à jour, comptée depuis sa publication, sinon depuis
/// sa découverte (voir `ParutionTitre.estNouveaute`). 30 jours : décision du
/// client après la 0.2.1-test (7 jours auparavant).
const Duration dureeNouveaute = Duration(days: 30);

/// Marge après l'ajout d'un site à un titre pendant laquelle les chapitres
/// découverts sont ceux reçus **lors de l'ajout** (lecture du site, puis
/// enregistrement), donc jamais des nouveautés. Une heure couvre largement
/// un ajout lent, et une vérification planifiée a rarement lieu dans
/// l'heure qui suit un ajout.
const Duration margeDecouverteApresAjout = Duration(hours: 1);

/// Plus ancienne version du format JSON que l'import sait lire.
const int versionFormatImportMinimale = 1;

/// Nombre maximal de titres lus dans un fichier d'import : borne la durée de
/// l'import (une bibliothèque personnelle compte quelques centaines de
/// titres) et protège d'un fichier corrompu démesuré.
const int nombreMaximalTitresImport = 20000;

/// Nombre maximal de regroupements de catégories lus dans un fichier
/// d'import (format 3) : une bibliothèque en compte quelques dizaines ; la
/// borne protège d'un fichier corrompu démesuré.
const int nombreMaximalEquivalencesImport = 5000;

/// Taille maximale (en octets) d'un fichier d'import : bien au-delà d'un
/// export réel (quelques centaines de Ko), pour refuser clairement un
/// fichier qui n'en est pas un au lieu de le charger en mémoire.
const int tailleMaximaleFichierImport = 50 * 1024 * 1024;

/// Suffixe de la vignette 512 px d'une couverture MangaDex (documentation
/// MangaDex, « covers ») : environ 160 Ko au lieu de 1,5 Mo.
const String suffixeVignetteMangaDex = '.512.jpg';

/// Suffixe de la petite vignette 256 px d'une couverture MangaDex : une
/// adresse qui le porte est déjà une vignette (pas de suffixe ajouté).
const String suffixePetiteVignetteMangaDex = '.256.jpg';

/// Taille totale maximale (en octets) des couvertures gardées en mémoire
/// pendant la session : 16 Mo, soit une dizaine d'originales MangaDex
/// (~1,5 Mo) ou une centaine de vignettes (~160 Ko). Au-delà, les moins
/// récemment demandées sont oubliées (elles restent sur l'appareil quand
/// elles y ont été enregistrées).
const int tailleMaximaleCacheCouvertures = 16 * 1024 * 1024;

/// Nombre maximal de couvertures gardées en mémoire pendant la session,
/// quelle que soit leur taille : borne aussi les demandes en cours.
const int nombreMaximalCouverturesEnCache = 100;

/// Nombre maximal d'exports dans la même minute (`…_1430.json`,
/// `…_1430_2.json`…) : borne la recherche d'un nom libre.
const int nombreMaximalExportsMemeMinute = 50;

/// Navigateur intégré : nombre maximal d'images enregistrées pour un même
/// chapitre (`ServiceLectureWeb.enregistrerImagesChapitre`). Un chapitre
/// réel en compte rarement plus de 200 ; au-delà, la page affichée n'est
/// sans doute pas un chapitre (galerie, défilement infini de plusieurs
/// chapitres) et l'archive serait fausse.
const int nombreMaxImagesChapitreWeb = 500;

/// Navigateur intégré : taille maximale (en octets) d'une image enregistrée.
/// 30 Mo couvrent les longues bandes verticales des webtoons (quelques Mo)
/// avec une large marge ; au-delà, ce n'est pas une page de chapitre.
const int tailleMaxImageChapitreWeb = 30 * 1024 * 1024;

/// Navigateur intégré : taille totale maximale (en octets) des images d'un
/// chapitre enregistré. 300 Mo laissent une large marge à un long chapitre
/// de webtoon (souvent 20 à 80 Mo) sans écrire d'archive démesurée.
// LIMITE : toutes les images sont en mémoire avant l'écriture (reçues de la
// page en base64 puis décodées, puis passées en bloc au service) ; la
// mémoire réellement prise dépasse donc ce plafond pendant l'échange avec
// la page. Plafond gardé bas pour les téléphones Android modestes.
const int tailleMaxTotaleChapitreWeb = 300 * 1024 * 1024;

/// Navigateur intégré : plus grand numéro de chapitre accepté quand il est
/// tiré d'une adresse. Au-delà, le « numéro » est presque toujours un
/// identifiant interne du site (`/chapter/4815162`), pas un numéro de
/// chapitre.
const double numeroMaxChapitreWeb = 100000;

/// Navigateur intégré : longueur minimale du morceau d'adresse d'un titre
/// (son « identifiant lisible », `solo-leveling`) cherché dans l'adresse
/// d'un chapitre pour l'attribuer à ce titre. Plus court, il se
/// retrouverait par hasard dans l'adresse d'une autre œuvre.
const int longueurMinIdentifiantTitreWeb = 4;

/// Navigateur intégré : morceaux d'adresse trop courants pour désigner un
/// titre (`/manga/`, `/series/`…). Ils ne servent jamais d'identifiant
/// lisible d'un titre.
const Set<String> segmentsGeneriquesAdresseTitre = <String>{
  'manga',
  'mangas',
  'manhwa',
  'manhua',
  'webtoon',
  'webtoons',
  'comic',
  'comics',
  'series',
  'serie',
  'title',
  'titles',
  'titre',
  'titres',
  'novel',
  'novels',
  'book',
  'books',
  'read',
  'lecture',
  'oeuvre',
  'oeuvres',
  'detail',
  'details',
  'index.php',
};

/// Navigateur intégré : domaines (sans `www.`) dont les images de chapitre
/// sont chiffrées ou brouillées par l'éditeur (PLAYBOOK.md section 10 :
/// MANGA Plus de Shueisha). Leurs images peuvent avoir un en-tête d'image
/// valide alors que le contenu est brouillé : elles ne sont jamais
/// enregistrées, quel que soit le contrôle des octets.
const Set<String> domainesImagesProtegees = <String>{
  'mangaplus.shueisha.co.jp',
};
