# Plan de tests — version 0.2.0-test (Windows, Android en option)

Pour chaque test : notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé** dans la colonne
« Résultat », et joignez le rapport d'erreur exporté s'il y en a un. Déposez votre retour dans
`testUtilisateur/retour/v0.2.0-test/`.

Avant de commencer : sauvegardez votre base (copie du dossier
`%APPDATA%\io.github.zerma1\bibliotheque_perso`). La base passe en version 8 au premier
lancement (ajout des sites « simple lien ») ; vos titres, listes et téléchargements sont gardés.

Nouveautés de cette version : sections **A** et **B** (priorité). Sections **C** à **E** :
vérification que le reste fonctionne toujours (en particulier sur votre autre PC, qui recevait
une erreur 403 de Scan-Manga).

## A. Sites illisibles et « simple lien » (nouveau)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| A1 | Lancer l'application | Version **v0.2.0** sous le menu, vos titres présents | ok|
| A2 | Fiche de Ruri Dragon → « Ajouter un autre site » → `ruri-dragon.online` (adresse du titre) | Le site est lu (chapitres listés) **ou** un message explique pourquoi il ne l'est pas, avec le bouton « Ajouter quand même comme simple lien » | ok|
| A3 | Si A2 refuse : « Ajouter quand même comme simple lien » | Le site apparaît dans « Sites » marqué « Secondaire · lien seul », aucun chapitre ajouté | |
| A4 | Sur ce simple lien : « Ouvrir dans le navigateur » | Le navigateur par défaut s'ouvre sur la page du titre | |
| A5 | Sur ce simple lien : « Essayer de le lire » | Soit les chapitres apparaissent, soit il reste simple lien avec un message clair | |
| A6 | Sur un site secondaire **lu** : « Garder comme simple lien » | Confirmation annonçant le nombre de chapitres non lus retirés ; après accord, les lus restent, les téléchargés passent au rouge 24 h | |
| A7 | « Rechercher les nouveaux chapitres » | Aucun chapitre n'est cherché ni téléchargé pour les simples liens, pas d'erreur à leur sujet | |
| A8 | Ajouter un titre Scan-Manga **sur l'autre PC** (celui qui avait l'erreur 403) | Soit ça marche, soit message « le site bloque les programmes automatiques » (plus d'erreur incompréhensible) ; dans ce cas « simple lien » proposé | Scan manga : redirection conforme |

## B. Diagnostic et critères de lecture (nouveau)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| B1 | Sources → Ajouter un site → déplier « Critères de lecture » | Aide lisible : ce qu'il faut pour qu'un site soit lisible | |
| B2 | Ajouter un site qui échoue → « Pourquoi ce site n'est pas lisible ? » | Liste des raisons (une seule requête au site) | |
| B3 | Type « générique » (ou détection automatique) → déplier « Réglages avancés (sélecteurs CSS) » | Une ligne par réglage ; un motif de numéro invalide est refusé avec un message | |
| B4 | Un site de scans « à liens simples » (page du titre qui liste les chapitres) | Lu sans réglage en type générique | |
| B5 | Fiche d'un titre → « Lire sur … » d'un chapitre externe | S'ouvre dans le **navigateur par défaut** (pas dans l'application) | |

## C. Bibliothèque et fiche (non-régression)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| C1 | Grille de la bibliothèque | Couvertures visibles, puces Tous / Favoris / Suivis / Planifié / En attente | ok|
| C2 | Entonnoir → inclure puis exclure une catégorie | Le filtre suit | ok|
| C3 | Ouvrir un titre MangaDex | Couverture nette, légende, chapitres dans vos langues | ok|
| C4 | Fiche d'un titre à plusieurs sites | Filtre par site affiché seulement pour les sites qui ont des chapitres | ok|
| C5 | « Définir comme site principal » puis « Retirer » un site secondaire | Fonctionne comme dans la 0.1.0-test.4 | ok|

## D. Téléchargements et lecture (non-régression)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| D1 | Titre en Favoris | Chapitres non lus téléchargés automatiquement | ok|
| D2 | Titre en Suivis | 10 premiers chapitres téléchargés, puis vague de 5 avant / 5 après le dernier lu | ok|
| D3 | Lire un chapitre jusqu'au bout | Marqué lu, le suivant s'ouvre | ok|
| D4 | Chapitre rouge → « Garder » / « Supprimer maintenant » | Fonctionne, compte à rebours visible | ok|
| D5 | Dossier `Documents\bibliotheque_perso\manga\<titre>\` | Seulement vos langues, aucun chapitre de simple lien | ok|

## E. Mises à jour, paramètres, export

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| E1 | Onglet Mises à jour | Titres triés, badge « Nouveau » | ok|
| E2 | Paramètres → vérifications par jour | Horaires en UTC et heure locale | ok|
| E3 | Paramètres → « Exporter mes titres et mes sites » | JSON + Markdown ; les simples liens y figurent | ok|
| E4 | Une erreur → « Exporter le rapport d'erreur » | Fichier créé, à joindre au retour | ok|

pas de possibilitée de réimporter les exports

## F. Android (facultatif)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| F1 | Installer l'APK de `livraisons/0.2.0-test/` | L'application s'ouvre, v0.2.0 | |
| F2 | Ajouter un titre MangaDex, le mettre en Favoris | Chapitres téléchargés | |

## Remarques libres

(Ce qui vous a gêné, ce qui manque, idées.)

À valider par vous en particulier :
- « Essayer de le lire » qui remet automatiquement le site en simple lien s'il reste illisible.
- Le libellé « Garder comme simple lien ».
- Les réglages avancés aussi visibles en détection automatique.
- Des réglages saisis pour un site déjà configuré remplacent les siens.
- Pas encore de modification des sélecteurs dans « Modifier le site » (à prévoir si utile).
