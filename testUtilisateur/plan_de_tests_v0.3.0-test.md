# Plan de tests — version 0.3.0-test (Windows)

Contient la 0.2.5-test (réparation de la base) : si ce n'est pas fait, commencez par son plan
(`plan_de_tests_v0.2.5-test.md`), puis celui de la 0.2.4-test (navigateur intégré) avec cette
version.

Avant de commencer : copiez le dossier `%APPDATA%\io.github.zerma1\bibliotheque_perso`
(sauvegarde). Fermez l'application si elle est ouverte.

Notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé**. Joignez le journal exporté
(Paramètres → Journal) dans `testUtilisateur/retour/v0.3.0-test/`.

## I. Installateur

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| I1 | Lancer `bibliotheque_perso-0.3.0-test-installation.exe` | Assistant en français, icône du nouveau logo | |
| I2 | Page « Dossier d'installation » | Proposé : `…\AppData\Local\Programs\Bibliotheque perso`, modifiable | |
| I3 | Page « Dossier de votre bibliothèque » | Proposé : `Documents\bibliotheque_perso`, modifiable (NAS possible) ; un dossier placé dans le dossier d'installation est refusé | |
| I4 | Terminer, lancer depuis le menu Démarrer | L'application s'ouvre, « v0.3.0 », icône du logo dans la barre des tâches | |
| I5 | Si vous avez choisi en I3 un autre dossier que `Documents\bibliotheque_perso` alors que vos chapitres y sont déjà | Bandeau : « Déplacer mes chapitres » / « Ignorer » | |
| I6 | « Déplacer mes chapitres » (ou « Ignorer », au choix) | Déplacement avec progression puis « Redémarrez » (ou le bandeau disparaît) | |
| I7 | Relancer l'installateur (mise à jour) | La page du dossier de bibliothèque n'apparaît pas ; message « bibliothèque non touchée » | |
| I8 | (facultatif) Désinstaller depuis Windows | Le programme est retiré ; votre base et vos chapitres restent | |

## P. Paramètres

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| P1 | Paramètres → Apparence → Sombre | Toute l'application passe en sombre ; fiche, téléchargements, lecteur lisibles | |
| P2 | Fermer puis relancer | Le thème sombre est là dès l'ouverture | |
| P3 | Apparence → Système | Suit le thème de Windows | |
| P4 | Téléchargements → jauge « Durée avant suppression » → 7 jours | Valeur « 7 jours » ; nouvelles suppressions prévues dans 7 j (compte à rebours « 6 j … ») | |
| P5 | Toutes les jauges (limites Favoris/Suivis, vérifications par jour, « En attente », téléchargements simultanés) | Curseur à crans + boutons − / + ; valeurs enregistrées | |

## Questions pour vous

- Le logo vous convient-il ?
- Section « Apparence » : la voulez-vous plus haut dans les Paramètres ?
- Les crans des jauges de limites (0–10, puis 12, 15, 20… 500) sont-ils pratiques ?

## Remarques libres

