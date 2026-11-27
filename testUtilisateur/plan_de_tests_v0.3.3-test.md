# Plan de tests — version 0.3.3-test (Windows)

**Important — à lire avant de commencer :**
- Fermez l'application (clic droit sur l'icône → Quitter) et copiez le dossier
  `%APPDATA%\io.github.zerma1\bibliotheque_perso` (sauvegarde de votre base).
- Au premier démarrage, la 0.3.3 **déplace votre base** vers `%APPDATA%\bibliotheque_perso`
  (ou le dossier choisi à l'installation). Ensuite, **ne relancez plus une 0.3.2 ou plus
  ancienne** : elle ne trouverait plus la base et en créerait une vide.
- Votre installation 0.3.2-test semble se trouver dans le dossier du projet
  (`D:\Projet\Bibliotheque perso`). Le nouvel installateur refuse ce dossier : désinstallez-la
  d'abord (« Applications installées » → Bibliothèque perso, en gardant vos données), puis
  installez la 0.3.3 dans un dossier vide (proposé par défaut).

Notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé**. Joignez le journal exporté
(Paramètres → Journal) dans `testUtilisateur/retour/v0.3.3-test/`.

## I. Un seul .exe : installer

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| I1 | Lancer `bibliotheque_perso-0.3.3-test-installation.exe` (application non installée) | Première page « Que voulez-vous faire ? » : Installer / Tout supprimer | |
| I2 | Installer : choisir le dossier du programme | Un dossier non vide ou le dossier du projet est refusé avec un message clair | |
| I3 | Pages suivantes | Dossier des chapitres, puis **Dossier de la base** (proposé : `%APPDATA%\bibliotheque_perso`, ou le dossier où une base existe déjà, avec un texte qui le dit) | |
| I4 | Page « Prêt » | Récapitule programme, base, chapitres | |
| I5 | Premier démarrage | Vos sources, titres et listes sont là ; la base est dans le dossier choisi ; l'ancien dossier `io.github.zerma1` a disparu | |

## M. Mettre à jour

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| M1 | Relancer le même .exe (application installée, même ouverte) | Choix : Réinstaller / Désinstaller / Tout supprimer ; une page récapitule les 3 emplacements ; rien n'est redemandé | |

## P. Import : bouton « Parcourir… »

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| P1 | Paramètres → Exporter la bibliothèque | Un fichier .json est créé | |
| P2 | Paramètres → Importer → « Parcourir… » | L'explorateur s'ouvre (dossier des exports), seuls les .json sont proposés | |
| P3 | Choisir le fichier, puis « Importer » | Import fait ; « Annuler » dans l'explorateur ne change rien | |
| P4 | Paramètres → Démarrage | Premier choix : « Désactivé » | |

## D. Désinstaller (en fin de tests)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| D1 | .exe → Désinstaller | Trois cases : Chapitres téléchargés (cochée), Sources, Titres (non cochées) | |
| D2 | Cocher Sources | Titres se coche et se grise ; décocher Sources le libère | |
| D3 | Désinstaller avec les valeurs par défaut | Programme et chapitres supprimés ; sources et titres gardés | |
| D4 | Réinstaller | Les emplacements précédents sont proposés ; vos sources et titres sont retrouvés ; les chapitres apparaissent « non téléchargés » | |
| D5 | (facultatif) Désinstaller depuis « Applications installées » de Windows | Mêmes trois cases | |
| D6 | (facultatif, en tout dernier) Tout supprimer | Tout ce qui vient de l'application est supprimé, vos autres fichiers gardés | |

## Remarques libres

