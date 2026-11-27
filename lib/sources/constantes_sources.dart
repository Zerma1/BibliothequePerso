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

/// User-Agent honnête de l'application, envoyé par défaut à **tous** les
/// sites (tâche T1 du 2026-11-17).
///
/// Auparavant, les sites autres que MangaDex recevaient le User-Agent d'un
/// navigateur. Or un client qui annonce un navigateur sans en avoir le
/// comportement (pas de JavaScript, empreinte réseau différente) est repéré
/// par les protections anti-robot (Cloudflare : page « Just a moment… » chez
/// le client sur Scan-Manga). La documentation MangaDex
/// (https://api.mangadex.org/docs/2-limitations/) exige de toute façon :
/// « The request MUST have a User-Agent header, and it must not be
/// spoofed ».
const String userAgentApplication = 'BibliothequePerso/0.1 (usage personnel)';

/// Codes HTTP par lesquels une protection anti-robot (Cloudflare…) sert sa
/// page de défi : 403 (accès refusé), 503 (« vérification en cours ») et 429
/// (trop de requêtes).
const Set<int> codesHttpDefiAntiRobot = <int>{403, 429, 503};

/// Marqueurs du corps d'une page de défi anti-robot (comparés en
/// minuscules) : titre « Just a moment... » de Cloudflare, dossier de ses
/// scripts de défi (`/cdn-cgi/challenge-platform/`) et préfixe de ses
/// paramètres (`cf-chl`, `__cf_chl_opt`).
const List<String> marqueursDefiAntiRobot = <String>[
  'just a moment',
  'challenge-platform',
  'cf-chl',
  'cf_chl',
];

/// Titres de page d'un défi anti-robot servi en 200 (comparés en
/// minuscules). Une page normale peut contenir `challenge-platform` (script
/// de détection injecté par Cloudflare sur les pages ordinaires, vu sur
/// Scan-Manga) : une réponse 200 n'est prise pour un défi que si son titre
/// en est aussi un.
const List<String> titresDefiAntiRobot = <String>[
  'just a moment',
  'attention required',
  'un instant',
];

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

/// Domaine de WEBTOON (sans `www.` ni `m.`), reconnu sans requête par
/// `DetecteurTypeSite.verifierDomaine`.
const String domaineWebtoons = 'webtoons.com';

/// Nombre maximal de pages de la liste des épisodes lues pour un titre
/// WEBTOON (une dizaine d'épisodes par page, 1 s entre deux pages) : au-delà,
/// les épisodes les plus anciens ne sont pas listés.
const int nombreMaxPagesListeWebtoons = 100;

/// Durée pendant laquelle `SourceWebtoons` réutilise la première page de la
/// liste d'un titre : la fiche et les épisodes en viennent tous deux.
const Duration dureeCachePageWebtoons = Duration(minutes: 1);

/// Durée pendant laquelle `SourceMadara` et `SourceMangaThemesia` réutilisent
/// la page d'un titre qu'ils viennent de télécharger : la fiche et la liste
/// des chapitres viennent de la même page.
const Duration dureeCachePageWordPress = Duration(minutes: 1);

/// Nombre maximal de pages de la liste des chapitres d'un titre Madara
/// (requêtes `ajax/chapters/?t=<n>`, 1 s entre deux pages) : au-delà, les
/// chapitres suivants ne sont pas listés.
const int nombreMaxPagesChapitresMadara = 50;

/// Codes HTTP par lesquels un site Madara signale qu'il n'a pas le point
/// d'accès `POST <fiche>ajax/chapters/` (400 Bad Request, 404 Not Found,
/// 405 Method Not Allowed) : `SourceMadara` passe alors à l'ancien appel
/// `admin-ajax.php`.
const Set<int> codesHttpSansAjaxChapitresMadara = <int>{400, 404, 405};

/// Durée pendant laquelle `SourceGenerique` réutilise une page qu'il vient
/// de télécharger : la fiche et la liste des chapitres viennent de la même
/// page, et une adresse de chapitre collée est résolue une seule fois.
const Duration dureeCachePageGenerique = Duration(minutes: 1);

/// Nombre minimal d'images d'un même conteneur pour que `SourceGenerique`
/// y voie la zone de lecture d'un chapitre : en dessous, il s'agit plutôt
/// d'un logo, d'une bannière ou d'un bouton de dons.
const int nombreMinImagesChapitreGenerique = 3;

/// Nombre minimal de pages distinctes, de même forme d'adresse, pour qu'un
/// groupe de liens reconnus par leur seul texte (« Chapitre 3 » sans numéro
/// dans l'adresse) soit pris par `SourceGenerique` pour une liste de
/// chapitres : un lien isolé d'un article (wiki, blog) n'en est pas une.
const int nombreMinLiensTexteGenerique = 2;

/// Nombre maximal de pages essayées par `SourceGenerique` pour remonter
/// d'une adresse de chapitre à la page qui liste les chapitres (une requête
/// chacune, 1 s entre deux).
const int nombreMaxCandidatsPageListe = 3;

/// Longueur minimale (en caractères) d'un bloc de texte pour être pris pour
/// le résumé d'un titre par `SourceGenerique`.
const int longueurMinResumeGenerique = 40;

/// Longueur maximale (en caractères) d'un nom de genre lu par
/// `SourceGenerique` : un genre est un mot ou deux ; un texte plus long est
/// un bloc entier (description, menu), pas un tag.
const int longueurMaxGenreGenerique = 40;

/// Longueur maximale (en caractères) de la valeur d'une ligne
/// « Libellé : valeur » lue par `SourceGenerique` (auteur, statut, type) :
/// au-delà, le texte capturé est un paragraphe entier, pas une valeur.
const int longueurMaxValeurLibelleGenerique = 200;

/// Longueur maximale (en caractères) du texte visible d'une page pour que
/// `verifierLisibilite` la juge construite par des scripts : une page
/// lisible en contient bien davantage.
const int longueurMaxTextePageScripts = 200;

/// Nombre de liens (`a[href]`) à partir duquel une page n'est plus jugée
/// construite par des scripts par `verifierLisibilite` : en dessous,
/// le HTML reçu n'est qu'une coquille vide remplie ensuite en JavaScript.
const int nombreMinLiensPageLisible = 3;

/// Propriétaire du dépôt GitHub public qui reçoit les tickets de
/// l'application (`ClientTicketsGithub`).
const String proprietaireDepotTickets = 'Zerma1';

/// Nom du dépôt GitHub public qui reçoit les tickets de l'application.
const String nomDepotTickets = 'BibliothequePerso';

/// Hôte de l'API REST de GitHub.
const String hoteApiGithub = 'api.github.com';

/// Hôte du site web de GitHub (page de création d'un ticket).
const String hoteSiteGithub = 'github.com';

/// Type de média demandé à l'API GitHub (en-tête `Accept`) : « Setting to
/// application/vnd.github+json is recommended » (docs.github.com, « List
/// repository issues »). Le corps reçu est alors le Markdown brut (`body`).
const String typeMediaApiGithub = 'application/vnd.github+json';

/// Version de l'API REST de GitHub (en-tête `X-GitHub-Api-Version`).
///
/// docs.github.com, « API Versions » (relevé le 2026-11-27) : versions
/// prises en charge `2026-03-10` et `2022-11-28` (fin de prise en charge le
/// 10 mars 2028). Les changements de rupture de `2026-03-10` (« Breaking
/// changes ») ne touchent aucun champ lu ici (`number`, `title`, `state`,
/// `state_reason`, `labels`, `comments`, `updated_at`, `html_url`, `body`,
/// `pull_request`, `user.login`, `created_at`).
const String versionApiGithub = '2026-03-10';

/// Taille de page des listes de l'API GitHub (`per_page` : « The number of
/// results per page (max 100) »).
const int taillePageApiGithub = 100;

/// Nombre maximal de pages lues par liste (tickets ou commentaires) : chaque
/// page coûte une requête sur les 60 par heure autorisées sans jeton.
const int nombreMaxPagesApiGithub = 5;

/// Attente minimale après une limite secondaire GitHub sans en-tête de
/// reprise (« Otherwise, wait for at least one minute before retrying »).
const Duration attenteMinLimiteGithub = Duration(minutes: 1);

/// Longueur maximale (en caractères) de l'adresse de création d'un ticket
/// pré-remplie.
///
/// LIMITE : GitHub ne publie pas sa limite ; sa documentation (« Creating an
/// issue », « Creating an issue from a URL query ») dit seulement qu'une URL
/// trop longue renvoie « 414 URI Too Long ». 8 000 caractères restent sous
/// les limites courantes des serveurs (8 Kio de ligne de requête) et des
/// navigateurs.
const int longueurMaxUrlCreationTicket = 8000;

/// Mention ajoutée à la fin d'un corps de ticket tronqué pour tenir dans
/// [longueurMaxUrlCreationTicket].
const String mentionCorpsTicketTronque =
    "[…] (texte tronqué : trop long pour l'adresse de création du ticket)";

/// Texte dont la présence dans l'URL de base désigne un serveur MangaDex
/// (docs/04-chapter/retrieving-chapter : signaler chaque image chargée
/// « from a base url that doesn't contain mangadex.org »).
const String marqueurServeurOfficielMangaDex = 'mangadex.org';
