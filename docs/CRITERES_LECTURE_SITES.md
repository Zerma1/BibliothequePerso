# Critères de lecture des sites

Ce document explique quand l'application peut lire un site (chapitres, images), quand elle ne le peut pas, et ce qu'elle vous propose dans ce cas.

## 1. Les types de sites reconnus

Quand vous ajoutez un site par son adresse, l'application cherche d'abord son « type ». Si le domaine ne suffit pas, elle télécharge la page d'accueil.

| Type | Comment il est reconnu | Comment il est lu |
|------|------------------------|-------------------|
| **MangaDex** | domaine `mangadex.org` | API publique officielle de MangaDex, car ses pages sont construites en JavaScript |
| **Scan-Manga** | domaine `scan-manga.com` | adaptateur dédié |
| **WEBTOON** | domaine `webtoons.com` (`www.` ou `m.`) | adaptateur dédié, jusqu'à 100 pages de la liste des épisodes |
| **Madara** (thème WordPress) | classes `wp-manga` ou scripts du thème « madara » dans la page | adaptateur dédié, jusqu'à 50 pages de la liste des chapitres |
| **MangaThemesia** (thème WordPress) | classe `bixbox` ou lecteur `ts_reader` dans la page | adaptateur dédié |
| **Générique** | tous les autres sites | règles automatiques, ou vos réglages avancés (section 6) |

Si la page contient seulement des liens en `/manga/` sans autre signe, le site est classé Madara, mais ce signe est faible. Vous pouvez corriger le type détecté dans le formulaire d'ajout.

## 2. Ce qu'il faut pour qu'un site générique soit lisible

Sans réglage, un site générique est lu s'il a des **liens explicites** :

- **Une page qui liste les chapitres.** Elle doit contenir au moins un lien de chapitre :
  - le lien mène **au même site** ;
  - son adresse ou son texte contient « chapter », « chapitre », « chap », « ch », « episode », « épisode » ou « ep », suivi du numéro (ex. `chapter-12`, `chapitre_3`, `episode/7`, « Chapitre 10,5 », « Ep. 3 ») ;
  - l'application garde le plus grand groupe de liens qui ont la même forme.
- **Des pages de chapitre en images en clair.** Ce sont des balises `<img>`, y compris en chargement différé (`data-src`, `data-lazy-src`…). Il faut **au moins 3 images dans un même conteneur**. En dessous, l'application y voit un logo, une bannière ou un bouton de dons.
- **La fiche du titre.** Elle est remplie automatiquement : le nom vient du titre principal de la page, la couverture de l'image de partage ou d'une image marquée « cover » ou « thumb ». Le résumé, l'auteur, le statut et les genres sont repris quand la page les affiche.

Vous pouvez coller :

- soit l'adresse de la page qui liste les chapitres ;
- soit l'adresse d'un chapitre. L'application remonte alors à la liste : lien « tous les chapitres », fil d'Ariane ou accueil du site. Elle essaie 3 pages au maximum.

Si l'accueil liste lui-même des chapitres, le site est considéré comme **dédié à une seule œuvre**.

## 3. Ce qui rend un site illisible

- **Protection anti-robot** (Cloudflare « Just a moment… », « Attention Required », « Un instant »…) : le site bloque les programmes automatiques. Elle est reconnue de deux façons :
  - une réponse 403, 429 ou 503 avec les marques d'une page de vérification ;
  - une page normale dont le titre est celui d'une page de vérification.
- **Contenu chargé en JavaScript** : la page reçue est une coquille vide, remplie ensuite par des scripts. Elle est jugée ainsi quand toutes ces conditions sont réunies :
  - **moins de 200 caractères** de texte visible ;
  - **moins de 3 liens** ;
  - aucun chapitre ni image ;
  - au moins un script.
- **Images protégées** :
  - images cachées derrière un **script brouillé** (`eval` combiné à `atob`, à `fromCharCode` ou au « packer » `function(p,a,c,k,e`) ;
  - pages **dessinées dans un `canvas`**, souvent chiffrées.
- **Aucun lien de chapitre reconnu** sur la page (voir section 2).
- **Moins de 3 images** regroupées sur une page de chapitre.
- **Page de connexion** (un champ de mot de passe, sans chapitre ni image) : l'application ne lit pas les contenus réservés aux comptes.
- **Erreur du site** (code HTTP en dehors de 200 à 299).
- **Recherche par mot-clé** : impossible sur un site générique. Il faut coller l'adresse du titre.

## 4. Ce que l'application ne fera jamais

L'application sert à un **usage personnel**. Elle respecte les sites :

- elle se présente honnêtement (`BibliothequePerso/0.1 (usage personnel)`) et ne se fait pas passer pour un navigateur ;
- elle attend **au moins 1 seconde entre deux requêtes** vers un même site ;
- elle abandonne une requête après **20 secondes** ;
- elle refait **au plus 2 essais** après un échec.

Elle **ne contourne aucune protection** : protection anti-robot, connexion, contenu payant, DRM. Elle ne décode **jamais** un script brouillé, des images dans un canvas ou des pages chiffrées. Exemple : MANGA Plus chiffre volontairement ses pages. L'application en liste les chapitres et propose « Lire sur <site> » pour ouvrir la page officielle.

## 5. Ce que propose l'application quand un site n'est pas lisible

- **« Pourquoi ce site n'est pas lisible ? »** : l'application analyse la page avec **une seule requête au site**. Elle affiche :
  - les **raisons** du refus ;
  - des **remarques**, par exemple « adresse d'un chapitre : la liste sera cherchée ».

  Si la page respecte les critères, le problème vient peut-être d'une autre page (liste ou chapitre) ou du site lui-même. Exportez alors le rapport d'erreur.
- **« Ajouter quand même comme simple lien »** : le site est enregistré avec son titre, mais aucun chapitre n'est lu. Il apparaît avec la pastille « lien seul » et un bouton **« Ouvrir dans le navigateur »**.
  - **« Essayer de le lire »** relance la lecture plus tard.
  - **« Garder comme simple lien »** fait passer en lien seul un site déjà lu.

Le simple lien reste un **secours** : dès qu'un chapitre peut être téléchargé, il l'est.

## 6. Réglages avancés (sélecteurs CSS)

Ces réglages sont facultatifs et réservés aux sites de type **générique**. Un champ vide laisse l'application deviner. Un sélecteur CSS désigne un élément de la page, par exemple `h1.titre` ou `.liste-chapitres a`. Les exemples ci-dessous sont des illustrations.

| Clé | Libellé dans l'application | Rôle | Exemple |
|-----|----------------------------|------|---------|
| `selecteurTitre` | Nom du titre | élément dont le texte est le nom du titre | `h1.entry-title` |
| `selecteurCouverture` | Image de couverture | image (ou élément portant `content`, `href` ou `src`) | `.cover img` |
| `selecteurResume` | Résumé | bloc du résumé | `.synopsis` |
| `selecteurAuteur` | Auteur | élément(s) portant le nom de l'auteur ; plusieurs noms sont joints par des virgules | `.author a` |
| `selecteurCategories` | Catégories (une par élément) | chaque élément est un genre ou un tag | `.genres a` |
| `selecteurLiensChapitres` | Liens des chapitres | liens (ou blocs contenant un lien) vers les chapitres | `.liste-chapitres a` |
| `selecteurImagesChapitre` | Images d'un chapitre | images (ou blocs contenant une image), dans l'ordre de lecture ; le seuil de 3 images ne s'applique pas | `.images-container img` |
| `selecteurLienListeChapitres` | Lien vers la liste des chapitres (depuis un chapitre) | lien, sur une page de chapitre, vers la liste | `.breadcrumb a.serie` |
| `motifNumeroChapitre` | Numéro de chapitre (expression régulière) | trouve le numéro dans l'adresse, puis dans le texte (premier groupe entre parenthèses). Sans `selecteurLiensChapitres`, sert aussi à reconnaître les liens de chapitres | `numero-(\d+)` |

Points à savoir :

- Les majuscules et minuscules ne comptent pas dans le motif.
- Les clés inconnues et les valeurs vides sont ignorées.
- Un réglage est refusé, avec un message, si le motif n'est pas une expression régulière valide ou si un sélecteur CSS est invalide.
