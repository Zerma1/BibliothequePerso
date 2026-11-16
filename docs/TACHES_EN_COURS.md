# Tâches en cours

Liste tenue par l'orchestrateur pour que le travail survive aux interruptions (limite
d'utilisation, fin de session). Chaque agent lit ce fichier, fait les tâches de **son** scope
qui ne sont pas cochées, vérifie dans le code ce qui est déjà fait (un agent précédent a pu
s'arrêter au milieu), puis indique dans son rapport ce qu'il a terminé. Seul l'orchestrateur
coche les cases.

Rappels : lire `CLAUDE.md` et `docs/JOURNAL_ERREURS.md` avant de commencer ; écrire les fichiers
au fur et à mesure ; ne pas commiter ; `flutter analyze` à 0 sur son périmètre avant le rapport.

## Étape 5 — corrections de la relecture et décisions du client (2026-11-15)

### developpeur-donnees (`lib/modeles/`, `lib/donnees/`)
- [ ] D1. `DepotTelechargements.reserverProchain()` atomique ; `reprendreApresInterruption({ancienneteMinimale})` ; `StockageTelechargements.nettoyerFichiersPartiels({ancienneteMinimale})` ; `DepotChapitres.chargerChapitresTelecharges({idTitre})`. (Probablement fait : vérifier et tester.)
- [ ] D2. Migration 4 (ne pas modifier 1 à 3) : `chapitres.nom_archive TEXT NULL`, `chapitres.date_suppression_prevue INTEGER NULL`, `titres.langues_preferees TEXT NULL`. Champs `Chapitre.nomArchive`, `Chapitre.dateSuppressionPrevue`, `Titre.languesPreferees` (avec un moyen explicite de remettre à null dans `copierAvec`).
- [ ] D3. `DepotChapitres.enregistrerArchive(id, String? nomArchive)`, `planifierSuppression(id, DateTime?)`, `chargerSuppressionsEchues(DateTime maintenant)` ; `DepotTitres.enregistrerLanguesPreferees(idTitre, String?)` (une actualisation du titre depuis le site ne l'écrase pas).
- [ ] D4. Noms d'archive uniques : `ch<numero>.<langue>.zip`, et seulement en cas de collision `ch1.fr.2.zip`, `ch1.fr.3.zip`… ; `ouvrirEcriture` renvoie le chemin relatif retenu ; lecture / suppression par `nomArchive` (repli sur l'ancien calcul si null). Deux oneshots → deux archives.

### developpeur-services (`lib/services/`)
- [ ] S1. Corriger les erreurs de compilation (`service_bibliotheque.dart` ~289 : `titre` utilisé avant sa déclaration).
- [ ] S2. Langues : jamais de version dans une langue non choisie ; un numéro sans version dans les langues choisies est ignoré ; archives d'autres langues → suppression différée.
- [ ] S3. Verrou de la file entre isolats (`verrou_telechargement.dart`) + `reserverProchain` ; reprise et nettoyage seulement des éléments anciens au démarrage ; `enregistrerProgression` à chaque page.
- [ ] S4. Chapitre ouvert dans le lecteur protégé (`protegerChapitre` / `libererChapitre` / `estProtege`).
- [ ] S5. Relecture : C1 annulation pendant un téléchargement + `supprimerTitre(idTitre)` qui supprime les archives ; C3 `appliquerReglesATous` robuste (try/catch par titre, `lancerTraitement` en finally, mise en file avant suppression) ; C4 tout `_telecharger` dans le try, erreurs journalisées ; C5 pas de relance infinie des échecs (3 au plus) ; C6 `finInitiale = initial - 1` ; C9 ne relancer que les échecs ; C10 retirer un titre de Favoris/Suivis retire ses lignes en attente ; C13 constantes (`constantes_services.dart`) ; C14 redemander le contenu après un 403 pour toute adresse MangaDex ; `suivisAvant` et `suivisApres` ≥ 1 ; `ServiceBibliotheque.chargerChapitre`.
- [ ] S6. Décision client : **suppression différée de 24 h** (`dateSuppressionPrevue`), annulée si le chapitre redevient voulu ; `supprimerMaintenant(id)`, `annulerSuppression(id)` ; suppression des échéances passées au démarrage, à l'application des règles et en fin de file. Suppression demandée par le client : immédiate.
- [ ] S7. Décision client : **doublons** jamais supprimés automatiquement ; `chargerDoublons(idTitre)` ; oneshots non regroupés.
- [ ] S8. `nomArchive` enregistré en fin de téléchargement et utilisé pour lire/supprimer ; au démarrage, contrôle que chaque chapitre marqué téléchargé a son archive.
- [ ] S9. Langues de l'utilisateur : `ServiceParametres.chargerLangues/enregistrerLangues` (défaut fr, en ; la première = favorite) ; `languesPourTitre(Titre)` = titre > source > réglage général ; `ServiceBibliotheque.modifierLanguesTitre(idTitre, List<String>?)` qui relance les règles ; flux de chapitres couvrant toutes les langues utiles (si `lib/sources` doit changer, le décrire dans le rapport).

### developpeur-interface (`lib/etat/`, `lib/ecrans/`, `lib/widgets/`, tests)
- [ ] I1. Faux services des tests (`test/etat/outils_tests_etat.dart`) à jour avec toutes les nouvelles méthodes des services.
- [ ] I2. Relecture : C7 mémoire du lecteur (pages ± 5, `cacheWidth`) ; C8 contrôle toutes les 15 min + retour au premier plan pour les échéances ; C11 import de `sources/` isolé dans `description_erreur.dart` ; S2 relectures de la file regroupées ; confirmation avant suppression dans Téléchargements.
- [ ] I3. Lecteur : `protegerChapitre` / `libererChapitre` ; suppression d'un titre par `ServiceTelechargement.supprimerTitre`.
- [ ] I4. Décision client : chapitre à supprimer **en rouge avec compte à rebours 24 h**, boutons « Garder » / « Supprimer maintenant » ; **doublons en orange**, le client choisit ; légende ; oneshots distincts.
- [ ] I5. Paramètres « Mes langues » (ajout depuis une liste de langues en français, retrait, ordre, « Choisir comme favorite » = première) ; réglage par site présenté comme avancé ; fiche du titre : langues de ce titre (réglage général / personnalisées / retour au général).

## Ensuite (orchestrateur)
- [ ] Relecture complète, essai réel contre MangaDex, essai de l'application à l'écran, proposition de la version 0.1.0 au client.
- [ ] Étapes 6 à 9 du PLAYBOOK.
