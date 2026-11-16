# Tâches en cours

Liste tenue par l'orchestrateur pour que le travail survive aux interruptions (limite
d'utilisation, fin de session). Chaque agent lit ce fichier, fait les tâches de **son** scope
qui ne sont pas cochées, vérifie dans le code ce qui est déjà fait (un agent précédent a pu
s'arrêter au milieu), puis indique dans son rapport ce qu'il a terminé. Seul l'orchestrateur
coche les cases.

Rappels : lire `CLAUDE.md` et `docs/JOURNAL_ERREURS.md` avant de commencer ; écrire les fichiers
au fur et à mesure ; ne pas commiter ; `flutter analyze` à 0 sur son périmètre avant le rapport.

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
- [ ] Relecture complète, essai réel contre MangaDex, essai de l'application à l'écran, proposition de la version 0.1.0 au client.
- [ ] Étapes 6 à 9 du PLAYBOOK.

## Plus tard (proposé par developpeur-services)
- [ ] P1. Migration 5 : colonne `chapitres.est_garde` pour le bouton « Garder » (aujourd'hui mémorisé dans `parametres`, avec une petite course possible entre isolats) — developpeur-donnees puis developpeur-services.
- [ ] P2. `ServiceTelechargement.chargerSuppressionsPrevues()` (tous titres) pour lister les chapitres en rouge dans l'onglet Téléchargements, et un repère visuel « gardé » — developpeur-services puis developpeur-interface.
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
- [ ] R5. **Ajouter un autre site à un titre** (bouton sur la fiche) : priorité avancée — l'étape 8 (plusieurs sources par titre) passe juste après l'étape 6.
- [x] R6. Listes obligatoires manquantes : déjà couvertes par l'étape 6 (« Planifié », « En attente »).
- [x] R7. **Export des liens** (demande du client, 2026-11-16) : exporter dans un fichier les sites configurés et chaque titre (nom, lien du titre sur chaque site, listes, catégories, langues propres, couverture choisie, dernier chapitre lu). Deux formats : JSON (complet, réimportable plus tard) et Markdown lisible (titres groupés par liste, liens cliquables). Fichiers dans `<dossier racine>/exports/`, nom daté. developpeur-services (`ServiceExport`), puis bouton dans Paramètres et partage du fichier (developpeur-interface). L'import du JSON suivra (R8).
- [x] R8. **Scan-Manga** (demande du client, 2026-11-16) : adaptateur `SourceScanManga` (type `scanManga`, reconnu par le domaine scan-manga.com). Les pages de titre sont du HTML lisible (titre, couverture, résumé, auteur, catégories, liste des chapitres) ; les pages de chapitre cachent leurs images derrière un script brouillé (atob + eval) : **aucun décodage** (PLAYBOOK §10), chaque chapitre est enregistré avec `urlExterne` = sa page de lecture (« Lire sur Scan-Manga »), jamais téléchargé. Recherche par le moteur du site si une page de résultats HTML existe.
- [x] R9. **Sources par défaut** : MangaDex et Scan-Manga présents dès le premier lancement (et ajoutés s'ils manquent), sans écraser les réglages du client.
