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
