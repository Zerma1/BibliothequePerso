# Plan de tests — version 0.2.4-test (Windows)

Cette version contient **les 0.2.2-test et 0.2.3-test** plus le navigateur intégré. Si vous ne
les avez pas encore testées, utilisez cette version pour leurs plans
(`plan_de_tests_v0.2.2-test.md`, `plan_de_tests_v0.2.3-test.md`), puis celui-ci.

Avant de commencer : **sauvegardez votre base** (copie du dossier
`%APPDATA%\io.github.zerma1\bibliotheque_perso`). Au premier lancement, la base passe en
version 13. Fermez toute ancienne version de l'application avant d'installer celle-ci.

Notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé**. Joignez le **journal exporté**
(Paramètres → Journal → « Exporter le journal du jour ») à vos retours, dans
`testUtilisateur/retour/v0.2.4-test/`.

## N. Navigateur intégré

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| N1 | Lancer l'application | « v0.2.4 » en bas de la colonne | |
| N2 | Fiche d'un titre qui a comix.to en simple lien (sinon : « Ajouter un autre site » → adresse comix.to du titre → « Ajouter quand même comme simple lien ») → section Sites → « Lire dans l'application » | Le site s'ouvre **dans l'application** (barre avec retour, avant, recharger, adresse) | |
| N3 | Ouvrir le chapitre 1 sur comix.to | Barre du bas : « Chapitre 1 de <titre> (non lu) » | |
| N4 | Passer au chapitre 2 (lien « suivant » du site) | Repère « Chapitre 2… » ; en revenant sur la fiche, le chapitre 1 est **lu** et les chapitres 1 et 2 apparaissent | |
| N5 | Sur le chapitre 2 : faire défiler jusqu'à la dernière page, puis « Enregistrer ce chapitre » | Progression « page n sur N », puis succès **ou** message clair (ex. « Ce site ne laisse pas récupérer ses images ») | |
| N6 | Si N5 a réussi : fiche → ouvrir le chapitre 2 | Il s'ouvre dans le lecteur de l'application, hors ligne | |
| N7 | Ruri Dragon → un chapitre MANGA Plus → « Lire sur MANGA Plus » | Ouvert dans l'application ; menu « Ouvrir dans le navigateur externe » disponible | |
| N8 | Sur ce chapitre MANGA Plus : « Enregistrer ce chapitre » | Message « Ce site protège ses images : elles ne peuvent pas être enregistrées. », rien enregistré | |
| N9 | Fiche d'un titre MangaDex → menu d'un chapitre non téléchargé → « Lire en ligne » | La page du chapitre s'ouvre dans l'application | |
| N10 | Bouton « Ouvrir dans le navigateur externe » | La même page s'ouvre dans votre navigateur habituel | |
| N11 | Pendant N5, changer de page avant la fin | L'enregistrement s'arrête avec un message, rien n'est enregistré dans un autre chapitre | |

## T. Téléchargements simultanés

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| T1 | Paramètres → Téléchargements → jauge « Téléchargements simultanés » | Valeur 3 par défaut, de 1 à 32, phrase sur la limite d'une requête par seconde par site | |
| T2 | Mettre 8, puis mettre un titre en Favoris (beaucoup de chapitres) | Onglet Téléchargements : plusieurs chapitres en cours en même temps | |
| T3 | Remettre 1 | Un seul chapitre à la fois ensuite | |

## Questions pour vous

- Le repère du chapitre disparaît un court instant pendant le chargement d'une page : gênant ?
- Sur une page non reconnue comme chapitre, « Enregistrer » est grisé avec une explication :
  faut-il pouvoir choisir le titre et le numéro à la main ?
- Sur quels sites l'enregistrement a-t-il marché / échoué ? (le journal le dira aussi)

## Remarques libres

