# Plan de tests — version 0.3.2-test (Windows)

Contient la 0.3.1-test. Avant de commencer : copiez le dossier
`%APPDATA%\io.github.zerma1\bibliotheque_perso` (sauvegarde de votre base).

Installez avec `bibliotheque_perso-0.3.2-test-installation.exe` (mise à jour par-dessus la 0.3.1).

Notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé**. Joignez le journal exporté
(Paramètres → Journal) dans `testUtilisateur/retour/v0.3.2-test/`.

## Q. Quitter (correction de Z6)

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| Q1 | Clic droit sur l'icône (près de l'horloge) → « Quitter » | L'icône disparaît | ok|
| Q2 | Gestionnaire des tâches, 10 s après | Plus aucun « bibliotheque_perso.exe » | ok|
| Q3 | Même chose après avoir ouvert le navigateur intégré (lecture web) | Pareil : plus aucun processus | ok|
| Q4 | Relancer l'application | Démarre normalement ; le journal précédent finit par « Fermeture demandée » | |

## E. Dossier des chapitres connu de la désinstallation

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| E1 | Lancer l'application une fois, puis ouvrir `%APPDATA%\io.github.zerma1\bibliotheque_perso` | Un fichier `emplacements.json` contient le dossier de vos chapitres | ok|
| E2 | (facultatif) Changer le dossier des chapitres dans Paramètres | `emplacements.json` indique le nouveau dossier | |

## D. Désinstalleur complet — À FAIRE EN DERNIER (supprime tout, irréversible)

Seulement si vous voulez vraiment repartir de zéro. **Gardez la copie de la base faite au début**
si vous voulez la remettre ensuite.

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| D1 | Lancer `bibliotheque_perso-0.3.2-test-desinstallation.exe` | Une page liste ce qui sera supprimé, avec les chemins (programme, base, dossiers de chapitres, démarrage avec Windows) | ok|
| D2 | Cliquer « Tout supprimer » | Question Oui/Non, **Non** sélectionné par défaut ; Non = rien n'est supprimé | ok|
| D3 | Relancer, puis Oui | L'application est fermée si elle tournait (même cachée) ; page « Résultat » qui résume ce qui a été supprimé | ok|
| D4 | Vérifier | Plus d'application dans le menu Démarrer ni dans « Applications installées » ; plus de dossier `%APPDATA%\io.github.zerma1` ; dossiers des chapitres vidés de ce qui vient de l'application, **vos autres fichiers gardés** ; plus de démarrage avec Windows | ok|

## Questions pour vous (toujours en attente)

- « Off » ou « Désactivé » pour le premier choix du démarrage ? Désactivé
- La section « Démarrage » est-elle bien placée (après « Apparence ») ? oui

## Remarques libres

- la desinstalation a supprimer la liste de source
- la desinstalation a supprimer la liste de manga
- il faudrait que le .exe permete de choisir d'instaler, desinstaler, metre a jours
- le .exe devrais enregistrer ou sont enregistrer l'application, la bibliotheque et les fichier de sauvegarde
- changer le `%APPDATA%\io.github.zerma1\bibliotheque_perso` pour `%APPDATA%\bibliotheque_perso`  
- ajouter un bouton pour rechercher le fichier (explorateur de fichier) pour importer un export de la bibliotheque