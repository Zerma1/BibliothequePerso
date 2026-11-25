# Plan de tests — version 0.2.5-test (Windows, correctif urgent)

Correctif de la base qui empêchait l'application de s'ouvrir. **Ne relancez plus la 0.1.0 ni
une ancienne version de test** sur cette base.

Avant de commencer : copiez le dossier `%APPDATA%\io.github.zerma1\bibliotheque_perso` vers un
autre endroit (sauvegarde). Fermez toute ancienne version de l'application.

Notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé**. Joignez le journal exporté
(Paramètres → Journal → « Exporter le journal du jour ») dans
`testUtilisateur/retour/v0.2.5-test/`.

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| R1 | Lancer la 0.2.5-test | L'application s'ouvre, « v0.2.5 » en bas de la colonne | |
| R2 | Bibliothèque | Tous vos titres, listes et chapitres sont là | |
| R3 | Paramètres → Journal → Exporter le journal du jour, l'ouvrir | Une ligne « réparation » de la base (version enregistrée / réelle, éléments recréés) | |
| R4 | Fermer puis relancer l'application | Elle s'ouvre directement, sans nouvelle réparation dans le journal | |
| R5 | Fermer la fenêtre, puis ouvrir le journal du jour | Dernière ligne : « Fermeture demandée » | |
| R6 | Reprendre ensuite le plan de la 0.2.4-test (navigateur intégré, téléchargements simultanés) avec cette version | Voir `plan_de_tests_v0.2.4-test.md` | |

## Remarques libres

