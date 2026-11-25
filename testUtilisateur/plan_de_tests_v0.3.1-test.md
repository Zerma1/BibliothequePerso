# Plan de tests — version 0.3.1-test (Windows)

Contient la 0.3.0-test (installateur, logo, thème, jauges, conservation) : si ce n'est pas fait,
suivez aussi `plan_de_tests_v0.3.0-test.md` avec cette version.

Avant de commencer : copiez le dossier `%APPDATA%\io.github.zerma1\bibliotheque_perso`
(sauvegarde). Installez avec `bibliotheque_perso-0.3.1-test-installation.exe` (mise à jour par-dessus
la 0.3.0 si elle est installée).

Notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé**. Joignez le journal exporté
(Paramètres → Journal) dans `testUtilisateur/retour/v0.3.1-test/`.

## Z. Icônes masquées et démarrage

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| Z1 | Lancer l'application, puis cliquer sur la croix | La fenêtre disparaît ; l'icône du logo est dans les icônes masquées (flèche ^ près de l'horloge) | |
| Z2 | Clic sur l'icône | La fenêtre réapparaît | |
| Z3 | Clic droit sur l'icône | Menu : Ouvrir / Rechercher les nouveaux chapitres / Quitter | |
| Z4 | « Rechercher les nouveaux chapitres » depuis le menu | La recherche se lance (onglet Mises à jour, journal) | |
| Z5 | Relancer l'application depuis le menu Démarrer alors qu'elle est cachée | La fenêtre existante revient (pas de deuxième application) | |
| Z6 | « Quitter » dans le menu de l'icône | L'application se ferme vraiment ; le journal finit par « Fermeture demandée » | |
| Z7 | Paramètres → Démarrage → « Icône masquée », puis redémarrer Windows | Au démarrage de Windows, l'application est dans les icônes masquées, fenêtre cachée | |
| Z8 | Démarrage → « Pleine fenêtre », redémarrer Windows | L'application s'ouvre en fenêtre | |
| Z9 | Démarrage → « Off », redémarrer Windows | L'application ne démarre pas toute seule | |

## T. Téléchargements

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| T1 | Onglet Téléchargements, avec des chapitres « à supprimer » (en rouge) | Bouton « Supprimer tous les chapitres à supprimer » | |
| T2 | Cliquer, confirmer | Message « N chapitre(s) supprimé(s) », la section rouge se vide | |

## U. Mise à jour et désinstallation

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| U1 | Application ouverte (ou cachée), relancer l'installateur | L'installateur propose de fermer l'application, puis met à jour | |
| U2 | (facultatif, en fin de tests) Désinstaller | Question « Supprimer aussi vos chapitres téléchargés ? » (Oui par défaut) ; base gardée ; plus de démarrage avec Windows | |

## Questions pour vous

- « Off » ou « Désactivé » pour le premier choix du démarrage ?
- La section « Démarrage » est-elle bien placée (après « Apparence ») ?

## Remarques libres

