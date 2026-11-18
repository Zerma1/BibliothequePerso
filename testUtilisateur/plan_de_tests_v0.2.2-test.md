# Plan de tests — version 0.2.2-test (Windows)

Pour chaque test : notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé** dans la colonne
« Résultat ». Déposez votre retour dans `testUtilisateur/retour/v0.2.2-test/`.

Avant de commencer : **sauvegardez votre base** (copie du dossier
`%APPDATA%\io.github.zerma1\bibliotheque_perso`) et faites un export (Paramètres → Sauvegarde et
export). La base passe en version 11 au premier lancement (catégories regroupées, champs modifiés
à la main, liste « Terminés ») ; vos titres, listes et téléchargements sont gardés.

## A. Vos retours de la 0.2.1-test

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| A1 | Lancer l'application | « v0.2.2 » en bas de la colonne ; puce « Terminés » dans les listes | |
| A2 | Bibliothèque → ajouter un titre | Case **Favoris décochée**, Suivis cochée | |
| A3 | Ruri Dragon : télécharger le chapitre 47 (ou « Réessayer » dans Téléchargements) | Téléchargé ; plus de message avec des caractères illisibles | |
| A4 | Sources → Ajouter un site → `https://fr.wikipedia.org/wiki/Ruri_Dragon` | **Refusé**, bouton « Pourquoi ce site n'est pas lisible ? » | |
| A5 | Appuyer sur « Pourquoi ce site n'est pas lisible ? » | Liste de raisons (ex. aucun lien de chapitre) | |
| A6 | Dans le même écran, déplier « Réglages avancés (sélecteurs CSS) » | La section se déplie (rien à remplir) | |

## B. Listes personnelles

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| B1 | Bibliothèque → « + » au bout des puces de listes → « À relire » | La liste apparaît | |
| B2 | Appui long (ou clic droit) sur « À relire » → Renommer | Nouveau nom affiché | |
| B3 | Appui long sur « Favoris » | Renommer / Supprimer grisés (liste système) | |
| B4 | « Gérer les listes » → faire glisser une liste | L'ordre des puces suit | |
| B5 | Fiche d'un titre → cocher « À relire » et « Terminés » | Le titre apparaît dans ces listes | |
| B6 | Supprimer « À relire » (confirmation) | La liste disparaît, le titre reste dans la bibliothèque | |

## C. Sites et titres

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| C1 | Onglet Sources → toucher un site | Dialogue de modification (nom, type, langues…) et bouton « Supprimer » | |
| C2 | Changer le nom d'un site → Enregistrer | Nouveau nom affiché | |
| C3 | Fiche d'un titre → « Modifier la fiche » → changer le nom et une catégorie | Fiche mise à jour, repère « Modifié à la main : nom, catégories » | |
| C4 | « Rechercher les nouveaux chapitres » | Le nom et la catégorie modifiés **restent** | |
| C5 | « Rendre au site » sur ces champs, puis rechercher les nouveaux chapitres | Les valeurs du site reviennent | |
| C6 | Ajouter un titre → onglet « Rechercher » → chercher « Ruri » | Résultats MangaDex ; on peut en ajouter un | |
| C7 | **(D4 de la 0.2.1)** Exporter, supprimer un titre, puis importer l'export | Le titre revient avec ses listes et ses sites ; ses chapitres arrivent après la recherche des nouveaux chapitres | |

## D. Chapitres lus en lot

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| D1 | Fiche d'un titre → appui long sur un chapitre | Mode sélection (cases, barre d'actions en haut) | |
| D2 | Maintenir et glisser sur plusieurs chapitres | Ils sont tous sélectionnés | |
| D3 | « Marquer lus » | Chapitres marqués lus, sortie du mode sélection | |
| D4 | Menu ⋮ d'un chapitre → « Marquer lus jusqu'ici » | Tous les chapitres jusqu'à celui-ci sont lus | |

## E. Catégories regroupées

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| E1 | Paramètres → « Catégories regroupées » → Suggestions | Propositions du type « Comédie ← Comedy » | |
| E2 | « Regrouper » sur une suggestion | Dans l'entonnoir de la bibliothèque, une seule puce pour le groupe | |
| E3 | Filtrer sur cette catégorie | Les titres des deux noms apparaissent | |
| E4 | Fiche d'un titre qui avait les deux noms | Une seule catégorie affichée | |

## F. Dossier des chapitres et archive complète (NAS)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| F1 | Paramètres → « Dossier des chapitres » → Changer de dossier → un dossier de test (ex. `D:\essai_chapitres`), « Déplacer » coché | Barre de progression, puis « Redémarrez l'application » (bandeau en haut) | |
| F2 | Redémarrer l'application, ouvrir un chapitre téléchargé | Il s'ouvre ; les fichiers sont dans le nouveau dossier | |
| F3 | (si NAS) Choisir un dossier du NAS, puis éteindre le NAS ou débrancher le réseau | Bandeau rouge « dossier inaccessible » ; aucun chapitre ne repasse en « non téléchargé » | |
| F4 | Revenir au dossier par défaut (même dialogue) puis redémarrer | Retour à `Documents\bibliotheque_perso` | |
| F5 | Paramètres → Téléchargements → activer « Archive complète » | Confirmation ; les chapitres de tous les titres partent en file (onglet Téléchargements) | |
| F6 | Désactiver « Archive complète » | Les téléchargements automatiques des titres hors Favoris/Suivis sont retirés de la file | |

## G. Non-régression rapide

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| G1 | Onglet Mises à jour | « Nouveau » pendant 30 jours | |
| G2 | Lire un chapitre puis « Chapitre suivant » | Le chapitre quitté passe en lu | |
| G3 | Scan-Manga sur l'autre PC | Comme avant | |

## Questions pour vous

- Le menu des listes s'ouvre par appui long / clic droit sur une puce : pratique ?
- Sur téléphone, « + » et « Gérer les listes » sont au bout de la ligne des listes (défilement) :
  faut-il les mettre ailleurs ?
- Faut-il plus tard un vrai sélecteur de dossier (nouveau paquet) au lieu de coller le chemin ?

## Remarques libres

