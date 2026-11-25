# Plan de tests — version 0.2.3-test (Windows)

Cette version contient **toute la 0.2.2-test** plus le journal. Faites les deux plans avec cette
version :
1. `testUtilisateur/plan_de_tests_v0.2.2-test.md` (dépôt du retour : `retour/v0.2.2-test/`) ;
2. ce plan-ci (dépôt du retour : `retour/v0.2.3-test/`).

Avant de commencer : **sauvegardez votre base** (copie du dossier
`%APPDATA%\io.github.zerma1\bibliotheque_perso`) et faites un export. Au premier lancement, la
base passe en version 12.

Pour noter **OK**, **KO** (avec ce qui s'est passé) ou **non testé** dans la colonne « Résultat ».
**Joignez le journal exporté (test J4) à vos retours** : il montre exactement ce qui s'est passé.

## J. Journal

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| J1 | Lancer l'application | « v0.2.3 » en bas de la colonne | |
| J2 | Paramètres → déplier « Journal » | Texte d'explication, chemin `…\Documents\bibliotheque_perso\journaux`, au moins un fichier du jour (date, taille) | |
| J3 | « Ouvrir le dossier » | L'Explorateur s'ouvre sur le dossier des journaux | |
| J4 | Faire quelques actions (ouvrir une fiche, lire un chapitre, « Rechercher les nouveaux chapitres »), puis « Exporter le journal du jour » | Message avec le chemin du fichier exporté (dans `rapports\`) | |
| J5 | Ouvrir ce fichier avec le Bloc-notes | Lignes datées : démarrage, requêtes vers les sites, fiche ouverte, chapitre lu, bilan de la vérification ; aucun mot de passe ni contenu de page | |
| J6 | Activer « Journal détaillé », télécharger un chapitre, puis le désactiver | Le résumé de la section rappelle de le désactiver ; avec le détail, une ligne par image | |
| J7 | Provoquer une erreur (ex. ajouter le site `https://exemple.invalid`) → « Exporter le rapport d'erreur » | Le rapport contient une section « Dernières lignes du journal », sans votre nom d'utilisateur Windows | |
| J8 | Fermer la fenêtre de l'application, puis rouvrir le journal du jour | Dernière ligne : « Fermeture demandée » (ou « Arrêt ») | |

## Questions pour vous

- Le journal contient-il ce qu'il vous faut pour décrire un problème, ou trop de lignes ?
- Les changements d'onglet sont notés : utile ou superflu ?

## Remarques libres

