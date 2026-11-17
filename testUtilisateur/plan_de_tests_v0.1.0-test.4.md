# Plan de tests — version 0.1.0-test.4 (Windows)

Pour chaque test : notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé** dans la colonne
« Résultat », et joignez le rapport d'erreur exporté s'il y en a un. Déposez votre retour dans
`testUtilisateur/retour/v0.1.0-test.4/` comme la dernière fois.

Avant de commencer : sauvegardez votre base (copie du dossier
`%APPDATA%\io.github.zerma1\bibliotheque_perso`).

Déjà vu par vous dans la test.4 : les liens externes s'affichent bien ; l'ajout d'un 2e site
échoue pour Scan-Manga (protection anti-robot) et pour ruri-dragon.online (site « générique »
pas encore lisible). Ces deux points sont en cours de correction pour la test.5 : inutile de les
retester ici.

## A. Démarrage et bibliothèque

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| A1 | Lancer l'application | Titre de fenêtre « Bibliothèque perso », version v0.1.0 sous le menu, vos titres présents | |
| A2 | Onglet Sources | MangaDex et Scan-Manga présents (ajoutés automatiquement) | |
| A3 | Bibliothèque : puces de listes | Tous, Favoris, Suivis, Planifié, En attente (sablier) | |
| A4 | Rechercher « death » (ou un titre alternatif d'un de vos titres) | Le titre est trouvé par son titre alternatif | |
| A5 | Couvertures dans la grille | Images visibles (plus d'icône vide pour MangaDex) | |

## B. Filtres

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| B1 | Entonnoir → inclure une catégorie (1 appui) → Appliquer | Seuls les titres de cette catégorie | |
| B2 | Entonnoir → exclure une catégorie (2 appuis, en rouge) → Appliquer | Les titres de cette catégorie disparaissent | |
| B3 | Entonnoir → rechercher « fant » dans la fenêtre | « Fantasy » trouvé sans tenir compte des accents ni majuscules | |
| B4 | Bouton « Contenu » : décocher « Suggestif » | Les titres suggestifs disparaissent de la grille | |

## C. Fiche d'un titre (MangaDex)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| C1 | Ouvrir un titre | Couverture nette (vignette puis image d'origine), légende des colonnes | |
| C2 | « Changer la couverture » → couverture d'un autre volume | La nouvelle couverture s'affiche dans la fiche et la grille | |
| C3 | « Changer la couverture » → chemin d'une image du PC | Image affichée ; « Revenir à la couverture du site » fonctionne | |
| C4 | Langues de ce titre → Personnalisées → « en » seulement | Les chapitres anglais deviennent la version retenue | |
| C5 | Revenir au réglage général | Retour à vos langues (FR puis EN) | |
| C6 | Ruri Dragon : chapitres MANGA Plus | Icône lien, « Publié sur MANGA Plus », appui → « Lire sur MANGA Plus » ouvre le navigateur | |

## D. Plusieurs sites (MangaDex + un site lisible)

Pour ces tests, utilisez un titre que vous trouvez aussi sur un site **Madara** ou
**MangaThemesia** (beaucoup de sites de scans « wordpress »).

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| D1 | Sources → Ajouter un site → adresse du site → détection automatique | Type Madara ou MangaThemesia reconnu | |
| D2 | Fiche du titre → « Ajouter un autre site » → adresse du titre sur ce site | Le site apparaît dans « Sites » avec son nombre de chapitres | |
| D3 | Liste des chapitres | Le nom du site sous chaque chapitre, filtre « Tous les sites / site » | |
| D4 | « Définir comme site principal » (confirmation) | La fiche se met à jour, aucun chapitre ne passe au rouge | |
| D5 | « Retirer » le site secondaire | Le nombre annoncé de chapitres retirés correspond à ce qui disparaît | |
| D6 | Ajouter un titre par une adresse déjà liée comme site secondaire | « Ce titre est déjà dans votre bibliothèque », sa fiche s'ouvre | |

## E. WEBTOON

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| E1 | Ajouter https://www.webtoons.com/fr/romance/the-gangster-daughter-of-the-henchman-dukes-family/list?title_no=11499 | Titre ajouté, type WEBTOON, épisodes listés avec « Lire sur WEBTOON » | |
| E2 | Couverture du titre WEBTOON | Couverture vide (non récupérée volontairement) ; une image du PC peut être choisie | |
| E3 | Ajouter la même série avec l'adresse `m.webtoons.com/...` | Pas de deuxième site WEBTOON | |

## F. Téléchargements et lecture

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| F1 | Mettre un titre MangaDex en Favoris | Ses chapitres non lus se téléchargent tout seuls (onglet Téléchargements) | |
| F2 | Mettre un autre titre seulement en Suivis | Les 10 premiers chapitres se téléchargent | |
| F3 | Ouvrir un chapitre téléchargé | Lecteur : pages en défilement, « page X / N », zoom − / + | |
| F4 | Lire jusqu'à la dernière page puis chapitre suivant | Chapitre marqué lu, le suivant s'ouvre | |
| F5 | Suivis : lire jusqu'au 6e chapitre | Le chapitre 1 passe **en rouge** avec un compte à rebours de 24 h, le 11e se télécharge | |
| F6 | Sur un chapitre rouge : « Garder » | Il redevient normal, repère « Gardé » | |
| F7 | Onglet Téléchargements | Section « Suppressions prévues » avec compte à rebours | |
| F8 | Fichiers dans `Documents\bibliotheque_perso\manga\<titre>\` | Archives `ch<N>.fr.zip` / `ch<N>.en.zip`, aucune autre langue | |

## G. Mises à jour et paramètres

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| G1 | Onglet Mises à jour | Titres triés par dernière parution dans vos langues, badge « Nouveau » | |
| G2 | Bouton « Rechercher les nouveaux chapitres » | Bilan affiché en bas de l'écran | |
| G3 | Paramètres → vérifications par jour : passer à 4 | Horaires affichés en UTC et en heure locale | |
| G4 | Paramètres → Mes langues : ajouter « espagnol », le remettre en dernier, puis le retirer | La liste suit, la favorite est la première | |
| G5 | Paramètres → « Exporter mes titres et mes sites » | Deux fichiers (JSON et Markdown) ; le Markdown liste vos titres par liste avec liens | |
| G6 | Ajouter une adresse de site invalide (ex. `https://exemple.invalid`) | Message clair + bouton « Exporter le rapport d'erreur » | |
