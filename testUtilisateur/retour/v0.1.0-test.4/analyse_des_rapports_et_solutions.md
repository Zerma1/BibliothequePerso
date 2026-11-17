# Analyse des Retours Utilisateurs et Solutions Techniques

Ce document synthétise l'analyse des rapports d'erreur générés sur la branche de test (v0.1.0-test.4) et propose des solutions techniques pour implémenter de nouvelles fonctionnalités dans la base de code Flutter.

---

## 1. Analyse des Problèmes Remontés

### A. Le rejet du site "Ruri Dragon" (ruri-dragon.online)
**Le problème :** Lors de l'ajout de l'URL `https://ruri-dragon.online` (ou de son chapitre), l'application rejette le lien avec le message : *Aucun adaptateur disponible pour le type « generique » (sélecteurs CSS : prévu à l'étape 7)*.

**L'explication :** 
Le détecteur de l'application (`detecteur_type_site.dart`) reconnaît que ce site n'est ni MangaDex ni Scan-Manga, et le classe comme "générique". Cependant, comme indiqué dans le message, la logique d'extraction par sélecteurs CSS n'est pas encore codée (prévue pour l'étape 7). L'application refuse donc d'aller plus loin car elle ne sait pas comment en extraire les images de manière native.

### B. L'erreur HTTP 403 sur "Scan-Manga"
**Le problème :** L'ajout d'un lien Scan-Manga génère une erreur `HTTP 403 Forbidden` avec un corps HTML contenant `<title>Just a moment...</title>`.

**L'explication :** 
Ce message est la signature typique du pare-feu applicatif de **Cloudflare**. Il intercepte la requête du client HTTP Dart de l'application car il ne le reconnaît pas comme un navigateur humain valide. Le défi JavaScript (le "Just a moment...") ne peut pas être résolu par un simple appel HTTP classique.

---

## 2. Solutions Techniques et Implémentation dans le Code

Pour pallier ces deux problèmes, voici comment adapter l'architecture actuelle du code.

### Chantier 1 : Implémenter le "Lien Web Simple" (Fallback Universel)
Cette solution permet d'ajouter n'importe quel site web (comme *Ruri Dragon*) et de le lire via la WebView intégrée, sans chercher à en parser le HTML.

**Modifications à prévoir :**
1. **`lib/sources/constantes_sources.dart` :** 
   Ajouter un nouveau type dans l'énumération des sources, par exemple `TypeSource.lienExplicite` ou `TypeSource.webView`.
2. **`lib/sources/detecteur_type_site.dart` :**
   Modifier la logique de détection. Au lieu de lever une exception ou de rejeter un site "générique" non supporté, le détecteur doit désormais renvoyer ce nouveau type `lienExplicite` comme solution de repli (fallback).
3. **`lib/sources/fabrique_sources.dart` :**
   Créer un nouvel adaptateur basique (ex: `SourceLienExplicite`). Cet adaptateur ne télécharge pas d'images. Sa méthode de récupération de chapitre se contente de renvoyer l'URL d'origine fournie par l'utilisateur.
4. **`lib/ecrans/ecran_lecteur.dart` :**
   Mettre en place un affichage conditionnel. 
   - Si la source est native (ex: MangaDex), utiliser la `ListView` d'images habituelle.
   - Si la source est `lienExplicite`, instancier directement le `WebViewWidget` (via le paquet `webview_flutter`) pour charger la page web complète.

### Chantier 2 : Contourner Cloudflare (Pour Scan-Manga et consorts)
Pour continuer à extraire nativement les images des sites protégés, le client HTTP doit prouver qu'il est légitime. Deux approches sont possibles :

**Approche A : Côté Client (Invisible WebView)**
- **Le concept :** Utiliser `webview_flutter` en arrière-plan pour charger l'URL protégée. Le moteur web natif du téléphone résout le challenge JavaScript de Cloudflare.
- **L'implémentation :** Une fois la page chargée et le challenge passé dans la WebView, on extrait les cookies de session (notamment `cf_clearance`) et le `User-Agent` du navigateur mobile.
- **L'intégration :** Dans `lib/sources/client_http_poli.dart`, on injecte ces cookies et ce User-Agent dans les en-têtes (headers) de toutes les futures requêtes HTTP (`http.get`).

**Approche B : Côté Serveur (FlareSolverr)**
- **Le concept :** Déléguer la résolution du challenge à un serveur externe.
- **L'implémentation :** Déployer une instance Docker de **FlareSolverr**. 
- **L'intégration :** Au lieu d'attaquer directement Scan-Manga dans `client_http_poli.dart`, l'application envoie une requête POST à l'API de FlareSolverr avec l'URL cible. FlareSolverr utilise un navigateur *headless*, passe le défi Cloudflare, et renvoie le code HTML propre à l'application Flutter. (Très stable, mais nécessite une infrastructure serveur).

---

## 3. Prochaines Étapes
1. **Valider l'approche pour Cloudflare :** Choisir entre la méthode Client (WebView) ou Serveur (FlareSolverr).
2. **Développer le "Lien Web Simple" :** C'est la fonctionnalité la plus rapide à mettre en place (modification de l'écran lecteur et du détecteur) et elle garantit qu'aucun lien ne sera plus jamais rejeté par l'application.