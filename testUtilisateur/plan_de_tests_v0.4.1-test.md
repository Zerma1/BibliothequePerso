# Plan de tests — version 0.4.1-test (Windows)

Mise à jour par-dessus la 0.3.3 avec `bibliotheque_perso-0.4.1-test-installation.exe`
(choix « Mettre à jour »). La base passe en version 15 : ne revenez pas ensuite à la 0.3.3.

Notez **OK**, **KO** (avec ce qui s'est passé) ou **non testé**, dans
`testUtilisateur/retour/v0.4.1-test/` (avec le journal exporté si possible).

## T. Tickets

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| T1 | Paramètres → « Aide et retours » → « Mes tickets » | Écran vide avec un bouton « Nouveau ticket » | |
| T2 | Nouveau ticket : type, titre, description → « Continuer sur GitHub » | La page GitHub « New issue » s'ouvre, pré-remplie (titre préfixé [Bug]/[Suggestion]/[Question], ligne « Repère : BP-… » à la fin) | |
| T3 | Publier le ticket sur GitHub, revenir, « Actualiser » | Le ticket passe de « En attente de publication » à « Ouvert », avec son numéro | |
| T4 | Ajouter un commentaire sur GitHub, actualiser | Pastille / « Nouveau » ; le détail montre le commentaire | |
| T5 | Fermer le ticket sur GitHub, actualiser | État « Fermé : terminé » (ou « non retenu ») | |
| T6 | « Retirer de ma liste » | Le ticket disparaît de l'application ; il reste sur GitHub | |

## M. Mise à jour automatique

| # | Test | Attendu | Résultat |
|---|------|---------|----------|
| M1 | Paramètres → section mise à jour | Version actuelle 0.4.1, interrupteur « Vérifier les mises à jour chaque jour » activé, bouton « Vérifier maintenant » | |
| M2 | « Vérifier maintenant » | « Application à jour » (aucune version plus récente n'est encore publiée sur `main`) ou un message clair | |
| M3 | (plus tard, quand une version plus récente sera publiée sur `main`) | Bandeau « Version X disponible » ; « Mettre à jour » télécharge, installe et relance l'application | |

## Questions pour vous

- La section « Aide et retours » est-elle bien placée (après « Démarrage ») ?
- Type de ticket proposé par défaut : Bug, ça vous va ?
- Le point rouge sur l'onglet Paramètres quand un ticket a du nouveau : à garder ?

## Remarques libres

