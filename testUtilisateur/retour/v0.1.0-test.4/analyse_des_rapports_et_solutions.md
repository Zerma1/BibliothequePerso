# Analyse des Retours Utilisateurs et Solutions Techniques

Ce document synthétise l'analyse des rapports d'erreur générés sur la branche de test (`v0.1.0-test.4`) et propose un plan d'action strictement aligné avec le **Playbook** du projet (extraction pour lecture native et hors-ligne, respect des conventions de nommage en français, architecture en couches et règles d'usage responsable).

---

## 1. Analyse des Problèmes Remontés

### A. Le rejet du site "Ruri Dragon" (`ruri-dragon.online`)

* **Rapports associés :** `rapport_20261117_081649.txt` et `rapport_20261117_083616.txt`
* **Symptôme :** L'application détecte correctement le site comme étant de type `generique`, mais bloque l'ajout au titre avec le message : *« Aucun adaptateur disponible pour le type « generique » (sélecteurs CSS : prévu à l'étape 7) »*.
* **Causes profondes (dans le code et le parcours) :**
  1. **Avancement de la feuille de route :** La version actuelle (`0.1.0-test.4`) couvre les étapes 1 à 6 ainsi que l'étape 8 (liaison de plusieurs sources à un même titre). Or, dans `FabriqueSources`, le cas `TypeSource.generique` n'est pas encore branché sur un adaptateur concret puisque l'étape 7 n'est pas commencée.
  2. **Absence de critères explicites dans l'interface :** Lorsqu'un site est détecté en `generique` lors de l'ajout aux sources (`EcranAjoutSite`), sa colonne `configuration_selecteurs` est laissée vide. L'utilisateur n'est pas informé des critères dont l'application a besoin pour lire ce site (comment trouver la fiche, la liste des chapitres et les images).
  3. **Confusion entre URL de fiche et URL de chapitre :** Au second test (`083616`), l'utilisateur a collé l'URL directe du chapitre 1 (`.../comic/ruri-dragon-chapter-1/`) dans le dialogue « Ajouter un autre site ». Or, la méthode `recupererFiche(String urlTitre)` et `recupererChapitres(String urlTitre)` de l'interface `SourceSite` attendent l'URL de la page principale de l'œuvre (qui liste tous les chapitres), à moins de concevoir un mode spécifique pour les sites dédiés à une seule œuvre.

### B. L'erreur HTTP 403 sur "Scan-Manga" (`www.scan-manga.com`)

* **Rapport associé :** `rapport_20261117_082051.txt`
* **Symptôme :** Lors de l'ajout du lien `https://www.scan-manga.com/6678/Potion-danomi-de-Ikinobimasu.html`, le type `scanManga` est bien reconnu, mais l'opération échoue avec un `Code HTTP : 403` et un corps HTML commençant par `<title>Just a moment...</title>`.
* **Cause profonde :**
  * Il s'agit de la page de défi anti-robot de **Cloudflare**. Le client HTTP Dart (`ClientHttpPoli`, qui repose sur `package:http`) n'exécute pas le JavaScript et possède une empreinte réseau TLS différente d'un navigateur complet. Cloudflare rejette donc la requête avant même d'atteindre le serveur de Scan-Manga.
  * **Contrainte stricte du Playbook (Section 10 - Usage responsable) :** *« L'application respecte la charge des sites grâce aux délais de `ClientHttpPoli` et ne contourne aucune protection d'accès »*. Il est donc **exclu** d'intégrer des systèmes de contournement automatisés de pare-feu (type proxy externe ou extraction forcée de jetons de sécurité).

---

## 2. Solutions Techniques Conformes au Playbook

L'objectif du produit est de regrouper les œuvres dans une interface unique, de les lire dans le lecteur natif (`EcranLecteur`) et de pouvoir télécharger les chapitres en archives `.zip` (`StockageTelechargements`) — tout en gérant proprement en externe les sites qui bloquent l'extraction automatique.

### Chantier 1 : Implémenter `SourceGenerique` et l'extraction par motifs / sélecteurs (Étape 7)

Pour que des sites au format explicite comme `ruri-dragon.online` puissent être lus nativement et téléchargés en `.zip` :

1. **Création de `SourceGenerique` (Agent : `developpeur-sources`) :**
   * Créer `lib/sources/source_generique.dart` implémentant `SourceSite`.
   * Exploiter le champ JSON `configurationSelecteurs` du modèle `Source` avec `package:html` (`querySelector` / `querySelectorAll`) pour extraire :
     * `selecteurTitre`, `selecteurCouverture`, `selecteurResume`, `selecteurAuteur`, `selecteurCategories` (pour `recupererFiche`).
     * `selecteurLiensChapitres` (pour `recupererChapitres`).
     * `selecteurImagesChapitre` (pour `recupererContenu`).
   * **Heuristiques pour « liens explicites » (valeurs par défaut) :** Si l'utilisateur laisse les sélecteurs vides sur un site simple (comme un site dédié à un seul manga où la page d'accueil liste directement les liens `/comic/...-chapter-X/` et où la page de chapitre contient directement les balises `<img>` des planches), `SourceGenerique` peut appliquer des sélecteurs par défaut intelligents (ex. chercher les liens contenant `chapter` ou `chapitre`, et les images dans le conteneur principal de lecture) et résoudre les URLs relatives via `Uri.parse(urlBase).resolve(lien)`.
   * Brancher `SourceGenerique` dans `FabriqueSources`.

2. **Afficher les critères de lecture et configurer les sélecteurs (Agent : `developpeur-interface`) :**
   * Dans `EcranAjoutSite` et `EcranSources`, lorsque le type est `generique`, afficher un formulaire clair permettant de renseigner ou tester les sélecteurs CSS, accompagné d'une aide expliquant les critères attendus par l'application (différence entre l'adresse de la fiche du titre qui liste les chapitres et l'adresse d'un chapitre isolé).

### Chantier 2 : Gestion propre de Scan-Manga et des sites protégés (Section 10 du Playbook)

Puisque le Playbook interdit le contournement de protections d'accès (Section 10) et que l'utilisateur a validé l'usage d'une vue web intégrée ou du navigateur pour les liens externes :

1. **Diagnostic et bascule en mode « Lecture externe / Vue Web » (Agents : `developpeur-sources` & `developpeur-services`) :**
   * Lorsqu'un site (comme `scan-manga.com` ou un site sous protection Cloudflare) renvoie une erreur HTTP 403 avec le marqueur `<title>Just a moment...</title>`, `ClientHttpPoli` / `ErreurSource` doit qualifier précisément ce refus comme une **protection d'accès active** (et non comme un simple bug réseau).
   * Conformément à la décision du client sur `webview_flutter` et à la section 10 du Playbook : si le site ne peut pas être lu par `package:http` mais que l'utilisateur souhaite tout de même associer le lien externe à sa fiche (ex. *Potion-danomi* déjà créé via MangaDex), l'application doit permettre d'enregistrer ce lien comme **lien externe de lecture**.

2. **Intégration de `webview_flutter` (Agents : `integrateur-plateformes` & `developpeur-interface`) :**
   * Après validation par l'orchestrateur, `integrateur-plateformes` ajoute `webview_flutter` dans `pubspec.yaml`.
   * Sur `EcranTitre`, les sites ou chapitres marqués comme protégés / externes proposent le bouton **« Lire sur <nom du site> »**, qui ouvre la page soit dans la vue web intégrée (`webview_flutter`), soit dans le navigateur par défaut (`url_launcher` sur les plateformes où la WebView n'est pas disponible), tout en permettant à l'utilisateur de marquer manuellement les chapitres comme lus dans sa bibliothèque.

---

## 3. Décisions Utilisateur Actées (Issues du rapport)

Ces décisions issues du tableau de retour peuvent être intégrées au suivi (`docs/TACHES_EN_COURS.md`) :

* **Paquet `webview_flutter` :** **Validé** par le client (*« oui intègre pour pouvoir lire tout lien externe directement dans l'application en passant par le navigateur par défaut »*).
* **Paquet `file_selector` :** **Non nécessaire** (*« ce qui est en place dans la v0.1.0-test.4 me convient déjà »*).
* **Bouton « Contenu » :** **Maintenu à sa place actuelle** (*« garder dans la bibliothèque »*).
* **Clé de signature Android & `share_plus` :** **En attente** (pas d'appareil Android disponible pour tester actuellement, priorité Windows).

---

## 4. Liste de Tests à Effectuer sur la Branche `test` (Windows)

En attendant le développement de l'étape 7 (`SourceGenerique`, `Madara`, `MangaThemesia`) sur `dev`, voici la liste des tests que l'utilisateur peut effectuer sur la version actuelle (`v0.1.0-test.4`) sous Windows pour valider les étapes 6 et 8 :

### Test 1 : Listes système « Planifié » et « En attente » (Étape 6)
1. Ouvrir la bibliothèque et vérifier la présence des listes **Favoris**, **Suivis**, **Planifié** et **En attente**.
2. Placer un titre dans **Planifié** et lancer une vérification des mises à jour : vérifier qu'aucune notification de nouveau chapitre n'est générée pour ce titre.
3. Ajouter un titre MangaDex qui n'a aucun chapitre traduit dans les langues configurées par le client : vérifier son comportement avec la liste **En attente**.

### Test 2 : Onglet « Mises à jour » et tri par parution (Étape 6)
1. Ouvrir l'onglet **Mises à jour**.
2. Vérifier que les titres sont bien triés par date de dernière parution d'un chapitre **dans les langues sélectionnées par l'utilisateur** (et non selon la date de sortie dans une langue étrangère non lue).

### Test 3 : Filtres par catégories et par niveau de contenu (Étape 6)
1. Dans la bibliothèque, tester le bouton **« Contenu »** (confirmé dans la bibliothèque) : filtrer successivement par *Sûr*, *Suggestif*, *Érotique*, *Pornographique* et vérifier que la grille se met à jour immédiatement.
2. Ouvrir le filtre par **Catégories / Tags** : tester la recherche ou la sélection parmi un grand nombre de tags (ex. *Action*, *Fantasy*, *Comedy*) et vérifier le cumul des filtres.

### Test 4 : Couvertures hors-ligne et changement de couverture (Étape 6)
1. Ouvrir la fiche d'un titre MangaDex possédant plusieurs volumes (`EcranTitre`).
2. Ouvrir l'outil de changement de couverture :
   * Tester la sélection d'une autre couverture de volume proposée par MangaDex.
   * Tester la sélection d'une image locale depuis le PC Windows.
3. Couper la connexion réseau (ou passer en mode hors-ligne) et relancer l'application : vérifier que toutes les couvertures de la bibliothèque s'affichent toujours.

### Test 5 : Téléchargement `.zip`, doublons et suppression différée (Étape 5/6)
1. Télécharger un chapitre depuis MangaDex et vérifier la création de l'archive `<dossier racine>/manga/<Nom>/ch<N>.<langue>.zip`.
2. Lire le chapitre hors-ligne dans `EcranLecteur`.
3. Si un chapitre existe en plusieurs versions dans la même langue (deux groupes de scantrad), télécharger les deux : vérifier que le second se nomme `ch<N>.<langue>.2.zip` et que les doublons apparaissent **en orange**.
4. Tester le marquage d'un chapitre lu soumis aux règles de conservation : vérifier qu'il passe **en rouge avec un compte à rebours de 24h** et tester l'action « Garder » ou « Supprimer maintenant ».