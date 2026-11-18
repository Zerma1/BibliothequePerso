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
const Duration delaiSuppressionDifferee = Duration(hours: 24);

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
