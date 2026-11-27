# Tâches en cours

Liste tenue par l'orchestrateur pour que le travail survive aux interruptions (limite
d'utilisation, fin de session). Chaque agent lit ce fichier, fait les tâches de **son** scope
qui ne sont pas cochées, vérifie dans le code ce qui est déjà fait (un agent précédent a pu
s'arrêter au milieu), puis indique dans son rapport ce qu'il a terminé. Seul l'orchestrateur
coche les cases.

Rappels : lire `CLAUDE.md` et `docs/JOURNAL_ERREURS.md` avant de commencer ; écrire les fichiers
au fur et à mesure ; ne pas commiter ; `flutter analyze` à 0 sur son périmètre avant le rapport.

## Version 0.4.0 — suggestions d'utilisateurs (2026-11-27)

### E1. Tickets GitHub (en cours)
Décisions du client : création par la page « New issue » pré-remplie du dépôt public
Zerma1/BibliothequePerso (aucun jeton dans l'application) ; suivi dans l'application
(écran « Mes tickets » : état, étiquettes, commentaires) par lecture publique de l'API,
grâce à un repère unique `BP-…` dans le texte du ticket.
- [x] Données : modèle `Ticket`, migration 14, `DepotTickets` (developpeur-donnees)
- [x] Réseau : lecture des issues et commentaires, URL de création (developpeur-sources)
- [x] Service tickets (developpeur-services)
- [x] Écran « Mes tickets » + création + assemblage (developpeur-interface, orchestrateur)
- [ ] À faire valider par le client : section « Aide et retours » entre Démarrage et Journal ;
  point sur l'onglet Paramètres ; bouton « Continuer sur GitHub » ; type par défaut Bug ;
  commentaires en texte brut (Markdown non mis en forme)

### E3. Mise à jour automatique (demande du client, 2026-11-27)
Une fois par jour, l'application consulte la dernière release GitHub publiée depuis `main`
(non *pre-release*, API publique sans jeton) ; si la version est plus récente, un bandeau
propose « Mettre à jour » : téléchargement de l'installateur, vérification d'une somme SHA-256
publiée avec la release, puis lancement de la mise à jour (`/ACTION=METTREAJOUR`).
- [x] CI : construire l'installateur Inno Setup et sa somme SHA-256 dans la release (integrateur ;
  noms figés dans docs/DEPLOIEMENT.md ; jamais exécuté sur GitHub à ce stade)
- [ ] Réseau : dernière release + téléchargement (developpeur-sources)
- [ ] Service : vérification quotidienne, réglage activé par défaut (developpeur-services)
- [ ] Interface : bandeau, progression, notes de version (developpeur-interface)

### E2. Lecture des formats de liseuse (à faire après E1)
Décisions du client : **CBZ, PDF, EPUB d'abord** (CBR, MOBI/AZW3 ensuite si une bibliothèque
sûre existe ; KFX non prévu) ; fichiers **sans DRM** seulement (aucun contournement) ; import
par **glisser-déposer** ou **explorateur de fichiers** ; le fichier est copié dans la
bibliothèque (titre de la source « Fichiers locaux », progression de lecture) ; paquets
choisis par l'orchestrateur (annoncés dans le rapport).
- [x] Choix des paquets (2026-11-27, laissé à l'orchestrateur par le client) : PDF `pdfrx` 3.2.0
  (MIT ; PDFium embarqué à la compilation, à épingler après un essai de build Windows) ;
  glisser-déposer `desktop_drop` 0.9.2 (Apache-2.0 ; Windows/Linux, file_picker sur Android) ;
  EPUB : lecture maison (archive + xml + html déjà présents : container.xml → .opf → spine)
  et rendu `flutter_widget_from_html_core` 0.17.4 (MIT, fonctionne aussi sous Linux) ;
  CBZ : lecteur .zip existant. Plus tard : CBR (aucune bibliothèque Windows/Linux fiable),
  MOBI/AZW3 (`kindle_unpack`, licence GPL-3.0 : accord du client nécessaire).
- [ ] Conception (données : titres « Fichiers locaux », progression par format)
- [ ] Données, services, interface, tests

## Étape 5 — corrections de la relecture et décisions du client (2026-11-15)

### developpeur-donnees (`lib/modeles/`, `lib/donnees/`)
- [x] D1. `DepotTelechargements.reserverProchain()` atomique ; `reprendreApresInterruption({ancienneteMinimale})` ; `StockageTelechargements.nettoyerFichiersPartiels({ancienneteMinimale})` ; `DepotChapitres.chargerChapitresTelecharges({idTitre})`. (Probablement fait : vérifier et tester.)
- [x] D2. Migration 4 (ne pas modifier 1 à 3) : `chapitres.nom_archive TEXT NULL`, `chapitres.date_suppression_prevue INTEGER NULL`, `titres.langues_preferees TEXT NULL`. Champs `Chapitre.nomArchive`, `Chapitre.dateSuppressionPrevue`, `Titre.languesPreferees` (avec un moyen explicite de remettre à null dans `copierAvec`).
- [x] D3. `DepotChapitres.enregistrerArchive(id, String? nomArchive)`, `planifierSuppression(id, DateTime?)`, `chargerSuppressionsEchues(DateTime maintenant)` ; `DepotTitres.enregistrerLanguesPreferees(idTitre, String?)` (une actualisation du titre depuis le site ne l'écrase pas).
- [x] D4. Noms d'archive uniques : `ch<numero>.<langue>.zip`, et seulement en cas de collision `ch1.fr.2.zip`, `ch1.fr.3.zip`… ; `ouvrirEcriture` renvoie le chemin relatif retenu ; lecture / suppression par `nomArchive` (repli sur l'ancien calcul si null). Deux oneshots → deux archives.

### developpeur-services (`lib/services/`)
- [x] S1. Corriger les erreurs de compilation (`service_bibliotheque.dart` ~289 : `titre` utilisé avant sa déclaration).
- [x] S2. Langues : jamais de version dans une langue non choisie ; un numéro sans version dans les langues choisies est ignoré ; archives d'autres langues → suppression différée.
- [x] S3. Verrou de la file entre isolats (`verrou_telechargement.dart`) + `reserverProchain` ; reprise et nettoyage seulement des éléments anciens au démarrage ; `enregistrerProgression` à chaque page.
- [x] S4. Chapitre ouvert dans le lecteur protégé (`protegerChapitre` / `libererChapitre` / `estProtege`).
- [x] S5. Relecture : C1 annulation pendant un téléchargement + `supprimerTitre(idTitre)` qui supprime les archives ; C3 `appliquerReglesATous` robuste (try/catch par titre, `lancerTraitement` en finally, mise en file avant suppression) ; C4 tout `_telecharger` dans le try, erreurs journalisées ; C5 pas de relance infinie des échecs (3 au plus) ; C6 `finInitiale = initial - 1` ; C9 ne relancer que les échecs ; C10 retirer un titre de Favoris/Suivis retire ses lignes en attente ; C13 constantes (`constantes_services.dart`) ; C14 redemander le contenu après un 403 pour toute adresse MangaDex ; `suivisAvant` et `suivisApres` ≥ 1 ; `ServiceBibliotheque.chargerChapitre`.
- [x] S6. Décision client : **suppression différée de 24 h** (`dateSuppressionPrevue`), annulée si le chapitre redevient voulu ; `supprimerMaintenant(id)`, `annulerSuppression(id)` ; suppression des échéances passées au démarrage, à l'application des règles et en fin de file. Suppression demandée par le client : immédiate.
- [x] S7. Décision client : **doublons** jamais supprimés automatiquement ; `chargerDoublons(idTitre)` ; oneshots non regroupés.
- [x] S8. `nomArchive` enregistré en fin de téléchargement et utilisé pour lire/supprimer ; au démarrage, contrôle que chaque chapitre marqué téléchargé a son archive.
- [x] S9. Langues de l'utilisateur : `ServiceParametres.chargerLangues/enregistrerLangues` (défaut fr, en ; la première = favorite) ; `languesPourTitre(Titre)` = titre > source > réglage général ; `ServiceBibliotheque.modifierLanguesTitre(idTitre, List<String>?)` qui relance les règles ; flux de chapitres couvrant toutes les langues utiles (si `lib/sources` doit changer, le décrire dans le rapport).

### developpeur-interface (`lib/etat/`, `lib/ecrans/`, `lib/widgets/`, tests)
- [x] I1. Faux services des tests (`test/etat/outils_tests_etat.dart`) à jour avec toutes les nouvelles méthodes des services.
- [x] I2. Relecture : C7 mémoire du lecteur (pages ± 5, `cacheWidth`) ; C8 contrôle toutes les 15 min + retour au premier plan pour les échéances ; C11 import de `sources/` isolé dans `description_erreur.dart` ; S2 relectures de la file regroupées ; confirmation avant suppression dans Téléchargements.
- [x] I3. Lecteur : `protegerChapitre` / `libererChapitre` ; suppression d'un titre par `ServiceTelechargement.supprimerTitre`.
- [x] I4. Décision client : chapitre à supprimer **en rouge avec compte à rebours 24 h**, boutons « Garder » / « Supprimer maintenant » ; **doublons en orange**, le client choisit ; légende ; oneshots distincts.
- [x] I5. Paramètres « Mes langues » (ajout depuis une liste de langues en français, retrait, ordre, « Choisir comme favorite » = première) ; réglage par site présenté comme avancé ; fiche du titre : langues de ce titre (réglage général / personnalisées / retour au général).

## Ensuite (orchestrateur)
- [x] Relecture complète, essai réel contre MangaDex, essai de l'application à l'écran, proposition de la version 0.1.0 au client.
- [x] Étapes 6 à 9 du PLAYBOOK.

## Plus tard (proposé par developpeur-services)
- [x] P1. Migration 5 : colonne `chapitres.est_garde` pour le bouton « Garder » (aujourd'hui mémorisé dans `parametres`, avec une petite course possible entre isolats) — developpeur-donnees puis developpeur-services.
- [x] P2. `ServiceTelechargement.chargerSuppressionsPrevues()` (tous titres) pour lister les chapitres en rouge dans l'onglet Téléchargements, et un repère visuel « gardé » — developpeur-services puis developpeur-interface.
- [ ] P3. Réglage avancé des langues d'un site : accepter les variantes régionales (`pt-br`).

## Étape 6 — retours du client après le premier test (2026-11-15)

Décisions de l'orchestrateur (autonomie accordée par le client jusqu'au vendredi 20/11 17h) :
- « Planifié de lecture » et « En attente » sont des **listes système** (comme Favoris / Suivis),
  non supprimables. « Planifié » : le titre est vérifié mais n'apparaît jamais dans les bilans /
  notifications de mises à jour. « En attente » : liste **automatique** — un titre suivi, favori
  ou planifié qui n'a **aucun chapitre dans les langues du client** y est ajouté, et en est retiré
  dès qu'un chapitre paraît ; ses titres sont vérifiés à **chaque heure pleine** (surveillance
  accrue, réglable dans Paramètres, entre 1 h et l'intervalle normal).
- Niveau de contenu MangaDex (`safe`, `suggestive`, `erotica`, `pornographic`) enregistré par
  titre ; filtre dans la bibliothèque (par défaut : tout afficher sauf `pornographic`, réglable).
- Couverture : enregistrée sur l'appareil (lisible hors-ligne) par `StockageTelechargements` ;
  le client peut choisir une autre couverture du site (MangaDex : une par volume) ou une image
  de l'appareil.

### developpeur-donnees
- [x] D5. Migration 5 : `chapitres.est_garde INTEGER NOT NULL DEFAULT 0` (bouton « Garder », remplace le stockage dans `parametres` — prévoir la reprise des identifiants déjà gardés côté service) ; `titres.niveau_contenu TEXT NULL` ; `titres.couverture_choisie TEXT NULL` (URL du site ou chemin d'une image locale) ; listes système « Planifié » et « En attente » (`est_systeme = 1`, ordres 2 et 3). Modèles, dépôts, tests (migration 4→5 sur base fichier avec données).
- [x] D6. Requête « dernière parution dans des langues données » par titre (`DepotChapitres.chargerDernieresParutions(List<String> langues)` → idTitre → date) pour l'onglet Mises à jour ; `DepotTitres.chargerTitres(niveauxContenu: …)` ; `DepotChapitres.repousserSuppressionPrevue(id, date)` (UPDATE … WHERE date_suppression_prevue IS NOT NULL).
- [x] D7. Couvertures sur l'appareil : `StockageTelechargements.enregistrerCouverture(titre, octets, extension)`, `chargerCouverture(titre)`, suppression avec le titre ; dossier `<type>/<titre>/couverture.<ext>`.

### developpeur-sources
- [x] SO1. `SourceMangaDex` : niveau de contenu (`contentRating`) dans la fiche ; liste des couvertures d'un titre (`GET /cover` — vérifier la doc) pour le choix du client ; recherche avec filtre de niveau de contenu.
- [x] SO2. Rapport d'erreur exportable : quand l'ajout d'un site ou la lecture d'un titre échoue, `ErreurSource` garde ce qu'il faut pour un rapport (URL, code HTTP, type détecté, extrait du début de la réponse sans données personnelles) ; fonction qui produit le texte du rapport.

### developpeur-services
- [x] SE1. Listes « Planifié » / « En attente » : classement automatique « En attente », exclusion de « Planifié » des bilans, vérification horaire des titres en attente (`PlanificationMisesAJour` ou équivalent), réglage de l'intervalle.
- [x] SE2. Service de l'onglet Mises à jour : titres suivis / favoris / en attente triés par dernière parution dans leurs langues (`languesPourTitre`), avec le dernier chapitre paru.
- [x] SE3. Couvertures : téléchargement et enregistrement sur l'appareil à l'ajout et à l'actualisation ; choix d'une couverture (liste du site, image locale) ; `est_garde` utilisé à la place de `parametres` (reprise des anciens) ; `chargerSuppressionsPrevues()` (P2) ; `repousserSuppressionPrevue` dans `protegerChapitre`.
- [x] SE4. Niveau de contenu : enregistré à l'ajout / actualisation ; réglage du filtre (par défaut tout sauf `pornographic`).
- [x] SE5. Export du rapport d'erreur dans un fichier texte (`Documents/bibliotheque_perso/rapports/`), chemin renvoyé à l'interface.

### developpeur-interface
- [x] IN1. Onglet « Mises à jour » (liste triée par dernière parution, badge des nouveautés).
- [x] IN2. Bibliothèque : filtre par catégories pensé pour beaucoup de tags (panneau / feuille avec recherche, sélection multiple, regroupement), filtre par niveau de contenu, listes Planifié / En attente.
- [x] IN3. Couvertures : affichage depuis l'appareil ; choix de la couverture sur la fiche d'un titre.
- [x] IN4. Bouton « Exporter le rapport d'erreur » quand l'ajout d'un site ou d'un titre échoue.
- [x] IN5. Onglet Téléchargements : section des suppressions prévues (rouge, compte à rebours) ; repère « gardé ». Réglage avancé des langues d'un site : accepter `pt-br` (P3). Bouton central « Ajouter un titre » en double avec le bouton flottant sur la bibliothèque vide : n'en garder qu'un.

## Retours du client sur la 0.1.0-test.1 (2026-11-16)
- [x] R1. BUG : couvertures / vignettes jamais affichées (diagnostic confié à analyste-erreurs, E10).
- [x] R2. BUG : chapitres non téléchargés automatiquement à l'ajout d'un titre ou d'un nouveau chapitre (diagnostic confié à analyste-erreurs, E11).
- [x] R3. Filtre des catégories : « Toutes » + entonnoir ouvrant une fenêtre avec toutes les catégories, chacune incluse / exclue (transmis à developpeur-interface avec IN2).
- [x] R4. **Chapitres hébergés sur un site externe** (ex. Ruri Dragon : MangaDex renvoie vers le site de l'éditeur) : les lister dans l'application avec un lien « Lire sur <site> », non téléchargeables. developpeur-sources (`includeExternalUrl=1`, champ `externalUrl` — vérifier la doc), developpeur-donnees (colonne `chapitres.url_externe`, migration 6), developpeur-services (exclus des règles de téléchargement), developpeur-interface (icône lien externe + légende).
- [x] R5. **Ajouter un autre site à un titre** (bouton sur la fiche) : priorité avancée — l'étape 8 (plusieurs sources par titre) passe juste après l'étape 6.
- [x] R6. Listes obligatoires manquantes : déjà couvertes par l'étape 6 (« Planifié », « En attente »).
- [x] R7. **Export des liens** (demande du client, 2026-11-16) : exporter dans un fichier les sites configurés et chaque titre (nom, lien du titre sur chaque site, listes, catégories, langues propres, couverture choisie, dernier chapitre lu). Deux formats : JSON (complet, réimportable plus tard) et Markdown lisible (titres groupés par liste, liens cliquables). Fichiers dans `<dossier racine>/exports/`, nom daté. developpeur-services (`ServiceExport`), puis bouton dans Paramètres et partage du fichier (developpeur-interface). L'import du JSON suivra (R8).
- [x] R8. **Scan-Manga** (demande du client, 2026-11-16) : adaptateur `SourceScanManga` (type `scanManga`, reconnu par le domaine scan-manga.com). Les pages de titre sont du HTML lisible (titre, couverture, résumé, auteur, catégories, liste des chapitres) ; les pages de chapitre cachent leurs images derrière un script brouillé (atob + eval) : **aucun décodage** (PLAYBOOK §10), chaque chapitre est enregistré avec `urlExterne` = sa page de lecture (« Lire sur Scan-Manga »), jamais téléchargé. Recherche par le moteur du site si une page de résultats HTML existe.
- [x] R9. **Sources par défaut** : MangaDex et Scan-Manga présents dès le premier lancement (et ajoutés s'ils manquent), sans écraser les réglages du client.

## Étape 8 — plusieurs sites pour un même titre (R5, priorité du client)

Décisions de l'orchestrateur :
- Un titre garde **un site principal** (celui d'ajout : fiche, couverture, résumé) et peut avoir
  des **sites secondaires** (bouton « Ajouter un autre site » sur la fiche, adresse du même titre
  sur l'autre site ; plus tard, proposition automatique par titres alternatifs).
- Les chapitres de chaque site sont enregistrés avec leur site d'origine ; un même numéro peut
  donc exister sur plusieurs sites. La politique de téléchargement choisit **une version par
  numéro** : langue préférée d'abord, puis version **téléchargeable** (hébergée) plutôt que
  « lecture sur le site », puis site principal, puis la plus ancienne.
- Les mises à jour vérifient tous les sites d'un titre (une requête par site, toujours 1 s par
  domaine) ; un site en panne n'empêche pas les autres.
- Retirer un site secondaire supprime ses chapitres non lus et non téléchargés ; les archives
  déjà téléchargées suivent la règle des 24 h.

- [x] M1. developpeur-donnees : migration 7 — table `titres_sources(id, id_titre → titres CASCADE, id_source → sources, url_titre, est_principale, date_ajout, UNIQUE(id_titre, id_source), UNIQUE(url_titre))` remplie depuis `titres.id_source/url_titre` pour les titres existants ; colonne `chapitres.id_source` (NULL = site principal pour les anciennes lignes, remplie par la migration) ; dépôt `DepotTitresSources` ; `DepotChapitres` filtre par source.
- [x] M2. developpeur-services : ajout / retrait d'un site à un titre (vérifie que l'adresse est bien un titre du site, sans le dupliquer ailleurs), actualisation sur tous les sites, politique multi-sites (ordre ci-dessus), mises à jour multi-sites, export (tous les liens).
- [x] M3. developpeur-interface : fiche — section « Sites » (principal + secondaires, ajouter, retirer, définir comme principal), chapitres avec le nom du site, légende ; filtre « site » dans la liste des chapitres.

## Étape 7 — autres sites

- [x] W1. **webtoons.com** (signalé par le client : https://www.webtoons.com/fr/romance/the-gangster-daughter-of-the-henchman-dukes-family/list?title_no=11499) : diagnostic (HTML lisible ? pagination de la liste des épisodes ? images protégées ?), puis adaptateur `SourceWebtoons` sur le modèle de Scan-Manga : fiche + tous les épisodes, chaque épisode avec `urlExterne` = sa page (« Lire sur WEBTOON ») tant que la récupération des images n'est pas clairement autorisée sans contournement. Langue d'après l'adresse (/fr/, /en/…).
- [x] W2. Adaptateurs Madara et MangaThemesia (thèmes WordPress courants).
- [x] W3. Adaptateur générique par sélecteurs CSS (formulaire de sélecteurs dans « Ajouter un site »).

## Retours du client sur la 0.1.0-test.4 (2026-11-17) — `testUtilisateur/retour/v0.1.0-test.4/`

Décisions du client : `webview_flutter` **validé** (lire les liens externes dans l'application,
navigateur par défaut en repli) ; `file_selector` non nécessaire ; bouton « Contenu » gardé dans
la bibliothèque ; clé de signature Android et `share_plus` en attente (pas d'Android à tester).
Analyse de Gemini lue : juste sur le fond, mais écrite sur un état ancien (Madara, MangaThemesia
et WEBTOON sont déjà dans la test.4 ; seul le générique manque).

- [x] T1. **Scan-Manga 403 « Just a moment… » (Cloudflare)** chez le client, alors que le site
  répond 200 depuis le PC de développement avec un User-Agent honnête comme navigateur.
  Hypothèse : un User-Agent de navigateur envoyé par un client qui n'est pas un navigateur est
  repéré par Cloudflare. Correction : User-Agent **honnête de l'application par défaut pour tous
  les sites** (le playbook §6 sera mis à jour), et reconnaissance d'une page de défi anti-robot
  (403/503 + « Just a moment » / challenge-platform) comme une erreur dédiée « protection
  anti-robot » avec un message clair. Aucun contournement.
- [x] T2. **Adaptateur générique** (W3) avec **heuristiques pour les sites à liens explicites**
  (ex. https://ruri-dragon.online : un site dédié à une œuvre, chapitres en
  `/comic/<titre>-chapter-<n>/`) : sans réglage, trouver les liens de chapitres (motifs
  chapter/chapitre/episode + numéro), le titre, la couverture, et les images de la page de
  chapitre ; accepter qu'on colle l'adresse d'un chapitre (remonter à la page qui liste les
  chapitres) ; sinon sélecteurs CSS réglables. Détection automatique d'un site « œuvre unique ».
- [x] T3. **Critères de lecture des sites** (demande du client) : document clair
  `docs/CRITERES_LECTURE_SITES.md` + aide dans l'écran d'ajout de site et dans les messages de
  refus (« pourquoi ce site n'est pas lisible »).
- [x] T4. **Ajouter quand même comme simple lien** : quand un site ne peut pas être lu
  (protection, adaptateur absent), proposer d'enregistrer l'adresse comme site du titre en
  « lien seul » (ouverture dans la vue web / le navigateur, pas de lecture des chapitres).
- [ ] T5. (Décision du client : sous **Windows, navigateur par défaut seulement**, pas de `webview_windows` ; `webview_flutter` pour Android uniquement, le jour où il pourra tester.) **Vue web intégrée** pour les liens externes et les « liens seuls » : `webview_flutter`
  (Android) ; **Windows : `webview_flutter` ne fonctionne pas sous Windows**, il faut le paquet
  `webview_windows` (moteur WebView2 de Windows 11) ; Linux : navigateur par défaut. Bouton
  « Ouvrir dans le navigateur » toujours présent.
- [x] T6. Plan de tests pour le client sur la branche `test` (fait par l'orchestrateur).

- [x] T7. Prochaine version de test : **0.2.0-test** (règle du client : X.Y.Z-test, Z+1 à chaque itération de corrections ; `version: 0.2.0+5`) avec son plan de tests `testUtilisateur/plan_de_tests_v0.2.0-test.md`, `versionApplication = '0.2.0'` (erreur de numérotation des test.2 à test.4, voir docs/VERSIONS.md).

## Retours 0.2.0-test (2026-11-17) → 0.2.1-test

- [x] U1. Réimporter les exports (JSON) : fusion sans doublon, sans réseau (services + bouton Paramètres)
- [x] U2. Numéro de version en bas de la colonne de navigation
- [x] U3. Paramètres en sections pliables
- [x] U4. Section « Sites » d'un titre pliable
- [x] U5. Badge « Nouveau » : titres marqués nouveaux depuis le 30/10/2023 (bug)
- [x] U6. Plan de tests 0.2.1-test : expliquer la section B (non comprise) et les tests A3–A7 (à faire avec un site illisible)
- Décidé : ouvrir un chapitre depuis la fiche ne marque pas les précédents comme lus (laisser ainsi).
- [x] U7. Première vérification d'un titre importé : le bilan compte tous ses chapitres comme nouveaux (nombreNouveauxChapitres, notifications) — à corriger dans la 0.2.2
- [x] U1–U6 faits (0.2.1-test)
- Décisions du client (2026-11-17) : « Nouveau » 30 jours ; section Sites et Paramètres repliés : OK ; import sans avancement de lecture. Prochaine version : 0.2.2-test, après le rapport du client sur la 0.2.1-test.

## Suite autonome (2026-11-17, pour la 0.2.2-test)

- [x] V1. Données : `Source.copierAvec` peut vider `configurationSelecteurs` ; exécution en une transaction pour l'import (exécuteur facultatif dans les dépôts + `executerEnTransaction`)
- [x] V2. Services : import tout-ou-rien (une transaction) ; validation des sélecteurs CSS avant enregistrement ; liste des clés de réglages génériques exposée
- [x] V3. Interface : modifier les sélecteurs CSS dans « Modifier le site » (et pouvoir les vider) ; clés lues depuis les services
- [x] V4. `docs/CRITERES_LECTURE_SITES.md` (critères de lecture expliqués au client)
- Reste possible : `DepotTitres.compterTitres` (import : savoir si la bibliothèque est vide sans tout charger) ; validation CSS plus stricte que le parseur (décision client).

## Retours 0.2.1-test (2026-11-18) → 0.2.2-test

- [x] X1. Téléchargement : image WEBP sans Content-Type refusée, message avec octets illisibles (sources)
- [x] X2. Wikipédia acceptée comme site générique lisible (heuristique trop large)
- [x] X3. Case Favoris décochée par défaut à l'ajout d'un titre
- [x] X4. Listes personnelles : créer, renommer, supprimer, réordonner (+ « En attente (perso) » gérable)
- [x] X5. CRUD sources : modifier/supprimer depuis l'onglet Sources, type modifiable
- [x] X6. CRUD titres : modifier nom, alternatifs, résumé, auteur, catégories, niveau de contenu (protégés de l'actualisation) ; ajout par recherche
- [x] X7. Archive complète (NAS) : tout télécharger, ne jamais supprimer automatiquement
- [x] X8. Plan de tests 0.2.2-test : reprendre D4 (import d'un titre retiré)
- [x] X9. Liste système « Terminés » (titres terminés) : pas de notification ni de téléchargement automatique (sauf archive complète)
- [x] X10. Marquer lus en lot : sélection de chapitres (appui long + glisser, ou cases) et « Marquer lus jusqu'ici » depuis un chapitre

## Navigateur intégré (2026-11-19, demande du client) → 0.2.4-test

- [ ] N1. Paquet flutter_inappwebview (Windows WebView2, Android ; Linux : navigateur externe)
- [ ] N2. Données : chapitres d'origine « web » acceptés sur un site en simple lien (migration 13)
- [ ] N3. Services : reconnaître le chapitre affiché (adresse), le marquer lu en passant au suivant ; enregistrer les images affichées en archive .zip
- [ ] N4. Interface : écran navigateur (lire sur le web, simples liens, chapitres externes), bouton « Enregistrer ce chapitre », repère du chapitre reconnu
- Limite : jamais d'usage caché ou automatique du navigateur ; jamais de canvas ni d'images chiffrées.
- [ ] N5. « Enregistrer ce chapitre » toujours cliquable ; si les images sont en canvas ou chiffrées, la tentative échoue avec un message clair (jamais de décodage)
- [ ] N6. Téléchargements simultanés : 1 à 32, jauge dans Paramètres (politesse 1 s par domaine inchangée)

**Décision du client (2026-11-19)** : Windows seul jusqu'à validation, puis Android, puis Linux. Les versions de test ne livrent plus que le .zip Windows.
- [x] N1–N6 faits (0.2.4-test)
- [x] Fermeture Windows journalisée (fenêtre cachée de WebView2 : canal bibliotheque_perso/fenetre) → dans la 0.2.5-test

## Notes du client (2026-11-25) → après la 0.2.6-test

- [x] Logo validé par le client.
- [x] D1. Désinstallation : supprimer aussi les chapitres téléchargés (la base reste ; à confirmer : case cochée par défaut dans le désinstalleur).
- [ ] D2. (REPORTÉ par le client le 2026-11-25 : pas de NAS pour l'instant, à revoir dans une version ultérieure ; conception dans docs/CONCEPTION_NAS.md) NAS = nœud actif (programme sur le NAS) : synchronise titres et sources avec les appareils, télécharge lui-même les chapitres possibles (jamais les « web only »), récupère les chapitres téléchargés sur un appareil (navigateur intégré…), source prioritaire quand configuré ; liste des titres/sites partagée entre appareils ; plus tard : lectures synchronisées. Le client n'a pas de NAS : prévoir un NAS simulé sur le PC pour tester. Commencer par un document de conception à valider (protocole, sécurité, déploiement Docker ?).
- [x] D3. Téléchargements : bouton « Supprimer tous les chapitres à supprimer » (suppressions prévues).
- [x] D4. Fermer la fenêtre = réduire dans la zone de notification (icône masquée), surveillance et téléchargements continuent ; menu de l'icône (ouvrir, quitter).
- [x] D5. Démarrage avec Windows : Off / Pleine fenêtre / Icône masquée (réglage).
- Version : la 0.2.5 est sur main (2026-11-25) ; la version en cours devient la 0.3.0-test.
- **À la reprise, en premier** : publier la version en cours (0.2.6-test, déjà prête sur dev) avant tout nouveau travail (note du client du 2026-11-25 : « publie la version avant le logo »).
- D2 (sécurité, note du client « notes perso ») : connexion au NAS — pas de SSH ouvert ; défense en profondeur (authentification forte, chiffrement TLS, accès réseau local/VPN seulement, moindre privilège, journalisation, mises à jour) à inclure dans le document de conception.
