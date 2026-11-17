/// Constantes de la couche `sources/` (règles réseau et API MangaDex).
///
/// LIMITE : PLAYBOOK.md section 9 range les constantes dans
/// `lib/modeles/constantes.dart`, hors du scope de `developpeur-sources`.
/// Elles sont regroupées ici en attendant une décision de l'orchestrateur.
library;

/// Délai minimal entre deux requêtes vers un même domaine (PLAYBOOK.md
/// section 6).
const Duration delaiMinimalParDomaine = Duration(seconds: 1);

/// Délai d'expiration d'une requête (PLAYBOOK.md section 6).
const Duration delaiExpirationRequete = Duration(seconds: 20);

/// Nombre maximal de nouvelles tentatives après un premier échec
/// (PLAYBOOK.md section 6).
const int nombreMaxNouvellesTentatives = 2;

/// Attente de base avant une nouvelle tentative ; multipliée par le numéro de
/// la tentative (2 s, puis 4 s) pour laisser le serveur se rétablir.
const Duration attenteBaseNouvelleTentative = Duration(seconds: 2);

/// Attente maximale acceptée quand un serveur demande de patienter
/// (`Retry-After`) : au-delà, on abandonne plutôt que de bloquer la file.
const Duration attenteMaxDemandeeParServeur = Duration(seconds: 60);

/// Code HTTP « Too Many Requests », le seul 4xx qui justifie une nouvelle
/// tentative.
const int codeHttpTropDeRequetes = 429;

/// Longueur maximale d'un extrait de corps de réponse cité dans une erreur.
const int longueurMaxExtraitReponse = 300;

/// User-Agent d'un navigateur courant, envoyé par défaut (PLAYBOOK.md
/// section 6) aux sites qui refusent les clients non navigateurs.
const String userAgentNavigateur =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// User-Agent honnête de l'application, utilisé pour l'API MangaDex.
///
/// La documentation MangaDex (https://api.mangadex.org/docs/2-limitations/)
/// exige : « The request MUST have a User-Agent header, and it must not be
/// spoofed ». On n'y envoie donc pas le User-Agent d'un navigateur.
const String userAgentApplication = 'BibliothequePerso/0.1 (usage personnel)';

/// Domaine du site public MangaDex (URLs des titres et des chapitres).
const String domaineMangaDex = 'mangadex.org';

/// Domaine de l'API publique officielle MangaDex.
const String domaineApiMangaDex = 'api.mangadex.org';

/// Domaine des couvertures MangaDex (« Retrieving Covers » :
/// `https://uploads.mangadex.org/covers/:manga-id/:cover-filename`).
const String domaineCouverturesMangaDex = 'uploads.mangadex.org';

/// Taille de page maximale de `GET /manga/{id}/feed` (api.yaml :
/// `limit` « maximum: 500 »).
const int taillePageMaxFluxMangaDex = 500;

/// Nombre de résultats demandés pour une recherche (api.yaml, `GET /manga` :
/// `limit` « maximum: 100 »).
const int taillePageRechercheMangaDex = 20;

/// Taille de page de `GET /cover` (api.yaml, operationId `get-cover` :
/// `limit` « default: 10, maximum: 100 »).
const int taillePageCouverturesMangaDex = 100;

/// Largeur (en pixels) de la miniature de couverture utilisée pour le choix
/// du client. docs/03-manga/covers : « two premade thumbnail sizes for each
/// cover, with respective widths of 256 and 512 pixels »,
/// `…/:cover-filename.{256, 512}.jpg`.
const int largeurMiniatureCouvertureMangaDex = 512;

/// Plafond `offset + limit` des collections MangaDex (docs/2-limitations :
/// « Requests where offset + size > 10.000 will be rejected »).
const int plafondOffsetMangaDex = 10000;

/// Délai minimal entre deux appels à `GET /at-home/server/{id}`.
///
/// docs/2-limitations : « GET /at-home/server/{id} : 40 requêtes par
/// minute », soit une toutes les 1,5 s (plus strict que la règle d'1 s).
const Duration delaiMinimalAtHomeMangaDex = Duration(milliseconds: 1500);

/// Point d'accès du signalement MangaDex@Home
/// (docs/04-chapter/retrieving-chapter : « It is a POST request to
/// https://api.mangadex.network/report (note that it's api.mangadex.network,
/// not api.mangadex.org) »).
const String urlSignalementMangaDexAtHome =
    'https://api.mangadex.network/report';

/// Domaine de Scan-Manga (sans `www.`), reconnu sans requête par
/// `DetecteurTypeSite.verifierDomaine`.
const String domaineScanManga = 'scan-manga.com';

/// Durée pendant laquelle `SourceScanManga` réutilise la page d'un titre
/// qu'il vient de télécharger : la fiche et la liste des chapitres viennent
/// de la même page, inutile de la demander deux fois de suite au site.
const Duration dureeCachePageScanManga = Duration(minutes: 1);

/// Texte dont la présence dans l'URL de base désigne un serveur MangaDex
/// (docs/04-chapter/retrieving-chapter : signaler chaque image chargée
/// « from a base url that doesn't contain mangadex.org »).
const String marqueurServeurOfficielMangaDex = 'mangadex.org';
