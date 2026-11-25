# Journal des versions

> **Note sur la numérotation (2026-11-17)** : la 0.1.0 a été publiée sur `main` le 2026-11-16.
> Les versions de test suivantes, appelées par erreur « 0.1.0-test.2 » à « 0.1.0-test.4 »,
> apportaient de nouvelles fonctionnalités et préparaient donc la **0.2.0**. Leurs étiquettes
> restent telles quelles ; la prochaine version de test est la **0.2.0-test** (règle du client :
> chaque version de test a son propre numéro `X.Y.Z-test`, Z+1 à chaque nouvelle itération).

## 0.2.5-test — correctif urgent, Windows (2026-11-25)

- **Corrigé : l'application ne s'ouvrait plus** (« table titres_sources already exists »). La
  base avait été ouverte par une ancienne version (0.1.0), qui l'avait marquée comme ancienne
  sans rien supprimer. Au démarrage, l'application lit maintenant la structure réelle de la base,
  se recale dessus et ne recrée que ce qui manque ; vos données sont gardées.
- Une version plus ancienne de l'application refuse désormais d'ouvrir une base plus récente
  (message clair) au lieu de la marquer comme ancienne. Ne relancez plus la 0.1.0 ni les
  anciennes versions de test.
- Corrigé : la fermeture de la fenêtre est bien notée dans le journal (« Fermeture demandée »)
  et les dernières lignes sont enregistrées.

## 0.2.4-test — version de test, Windows seulement (2026-11-19)

Contient tout ce qu'apportent les 0.2.2-test et 0.2.3-test, plus :
- **Navigateur intégré** (Windows, moteur WebView2) : « Lire dans l'application » sur un site en
  simple lien, « Lire sur … » d'un chapitre externe, « Lire en ligne » d'un chapitre non
  téléchargé. Barre : retour, avant, recharger, adresse, navigateur externe.
- **Chapitre reconnu** d'après l'adresse affichée (« Chapitre N de <titre> (lu / non lu) ») ;
  passer au chapitre suivant marque le chapitre quitté comme lu. Sur un site en simple lien
  (ex. comix.to), les chapitres lus s'ajoutent à la fiche.
- **« Enregistrer ce chapitre »** : range les images affichées dans une archive (lecture hors
  ligne). Images dessinées dans un canvas, déchiffrées par le site (MANGA Plus) ou refusées par le
  site : la tentative échoue avec un message, rien n'est enregistré.
- **Téléchargements simultanés** : jauge de 1 à 32 (3 par défaut) dans Paramètres →
  Téléchargements ; un même site reçoit toujours au plus une requête par seconde.
- Corrigé : les images des sites autres que MangaDex étaient signalées à tort à MangaDex@Home ;
  un téléchargement demandé à la fin de la file pouvait attendre.
- Les versions de test ne livrent plus que Windows (décision du client).

## 0.2.3-test — version de test (2026-11-18)

Contient tout ce qu'apporte la 0.2.2-test, plus :
- **Journal de l'application** : un fichier par jour dans
  `Documents\bibliotheque_perso\journaux\` (14 jours gardés, jamais sur le NAS) : requêtes vers
  les sites, ajouts, vérifications, téléchargements, import/export, réglages, plantages, tâche de
  fond Android. Mots de passe, jetons, cookies et contenu des pages jamais écrits.
- **Paramètres → Journal** : dossier, fichiers, « Exporter le journal du jour / des 7 derniers
  jours », interrupteur « Journal détaillé » (diagnostic).
- Les **rapports d'erreur** contiennent les 200 dernières lignes du journal (sans nom
  d'utilisateur, adresse IP ni courriel).

## 0.2.2-test — version de test (2026-11-18)

Suite aux retours sur la 0.2.1-test :
- **Listes personnelles** : « + » et « Gérer les listes » au bout des puces de listes ; appui long
  ou clic droit sur une liste pour la renommer ou la supprimer ; glisser-déposer pour réordonner.
  Nouvelle liste système **« Terminés »** (vérifiée sans notification, pas de téléchargement
  automatique sauf archive complète).
- **Sites** : dans l'onglet Sources, toucher un site pour le modifier (nom, langues, **type**,
  réglages) ou le supprimer.
- **Titres** : la fiche reste celle du site (décision du client) ; bloc **« Ma description »**
  pour ajouter vos notes, jamais remplacées par le site (exportées et réimportées). Ajout d'un
  titre par **recherche sur MangaDex**.
- **Chapitres lus en lot** : appui long sur un chapitre puis glisser pour sélectionner ; « Marquer
  lus / non lus » ; « Marquer lus jusqu'ici » (menu ⋮ d'un chapitre ou barre de sélection).
- **Archive complète** (Paramètres → Téléchargements) : tous les chapitres de tous les titres,
  jamais supprimés automatiquement (conseillé avec un NAS).
- Case **Favoris décochée** par défaut à l'ajout d'un titre.
- Corrigé : images **WEBP** sans type (échec de Ruri Dragon ch. 47) ; plus jamais d'octets
  illisibles dans un message ; une page **Wikipédia** n'est plus acceptée comme site lisible.

Nouveau :
- **Catégories regroupées** (Paramètres → « Catégories regroupées ») : « Survival » et
  « Survie » ne font plus qu'une catégorie dans les filtres et sur la fiche ; suggestions
  automatiques (dictionnaire anglais → français) à valider une par une. Exportées et importées.
- **Dossier des chapitres au choix** (Paramètres → « Dossier des chapitres ») : disque local,
  lecteur réseau ou NAS (`\\nas\partage\…`). Déplacement des chapitres déjà téléchargés avec
  barre de progression ; aucun fichier existant n'est jamais écrasé (conflits signalés et
  chapitres retéléchargés sous un autre nom). Pris en compte au redémarrage. Si le NAS ne
  répond pas : bandeau en haut, téléchargements en attente, aucun chapitre perdu. Rapports
  d'erreur et exports restent sur l'appareil.
- **Réglages avancés (sélecteurs CSS)** modifiables et effaçables dans « Modifier le site »,
  vérifiés avant l'enregistrement.
- Document `docs/CRITERES_LECTURE_SITES.md` : quand un site est lisible, et pourquoi pas.

Changé :
- Badge « Nouveau » pendant **30 jours** (décision du client).
- Import d'un export **tout ou rien** (rien n'est écrit s'il échoue) ; les chapitres d'un titre
  importé ne sont plus annoncés comme nouveaux.
- Langues : variantes régionales acceptées (`pt-br`…), la langue exacte passe avant la variante.
- Messages d'erreur affichés 10 s, avec une croix pour les fermer.

Corrigé :
- Une section pliable des Paramètres en erreur pouvait faire planter l'écran.

## 0.2.1-test — version de test (2026-11-17)

Suite aux retours sur la 0.2.0-test.

Nouveau :
- **Importer un export** (Paramètres → Sauvegarde et export) : relit un fichier JSON exporté et
  ajoute à la bibliothèque les sites, titres, listes et catégories manquants, sans doublon et
  sans rien supprimer. Les chapitres arrivent à la vérification suivante ; l'avancement de
  lecture n'est pas repris. L'export passe au format 2 (sélecteurs CSS des sites, résumés) ;
  les exports de la 0.2.0 restent importables.
- **Paramètres en sections pliables** ; la section « Sites » d'un titre est pliable.

Corrigé :
- Badge « Nouveau » : seulement pour un chapitre non lu sorti depuis moins de 7 jours (avant :
  tout dernier chapitre non lu, même de 2023). Les chapitres sans date reçus à l'ajout d'un
  titre ou d'un site ne sont plus des nouveautés.
- Lecteur : plus de sauts vers le bas en remontant dans un chapitre.
- Le numéro de version est en bas de la colonne de navigation.

## 0.2.0-test — version de test (2026-11-17)

Reprend tout ce qu'apportaient les versions 0.1.0-test.2 à 0.1.0-test.4, plus :

Nouveau :
- **Site en « simple lien »** : quand un site ne peut pas être lu, « Ajouter quand même comme
  simple lien » l'ajoute au titre pour l'ouvrir dans le navigateur (aucun chapitre lu ni
  téléchargé, jamais vérifié). Sur un site lu : « Garder comme simple lien » ; sur un simple
  lien : « Essayer de le lire » (il redevient simple lien si le site reste illisible).
- **« Pourquoi ce site n'est pas lisible ? »** : diagnostic d'un site à la demande (une seule
  requête), avec les raisons.
- **Critères de lecture** (aide repliable sous l'adresse d'un site) et **réglages avancés
  (sélecteurs CSS)** pour les sites génériques.
- **Sites génériques à liens explicites** : un site dont les pages listent simplement les
  chapitres par des liens peut être lu sans réglage.
- Version affichée : **v0.2.0**.

Changé :
- L'application s'annonce honnêtement (« BibliothequePerso/0.1 (usage personnel) ») auprès de
  tous les sites. Un site qui bloque les programmes automatiques (protection anti-robot) est
  reconnu et signalé clairement ; l'application ne contourne jamais ces protections.
- Windows : les liens « Lire sur … » s'ouvrent toujours dans le navigateur par défaut.
- Après **chaque** vérification des nouveaux chapitres (même sans nouveauté), les
  téléchargements prévus par vos règles sont relancés et les chapitres en échec retentés
  (un site qui bloquait peut de nouveau répondre), toujours dans les limites réglées.
- Compilation automatique : les étiquettes `vX.Y.Z-test` sont publiées en pre-release.

## 0.1.0-test.4 — version de test (2026-11-17)

Nouveau :
- **WEBTOON** (webtoons.com) : suivi des séries et de tous leurs épisodes (dates, nouveaux
  épisodes) avec « Lire sur WEBTOON ». Les images du site sont protégées : les épisodes ne sont
  pas téléchargés et les couvertures ne sont pas récupérées (choisissez une image de l'appareil
  si vous le souhaitez). Les épisodes réservés à l'application mobile WEBTOON n'apparaissent pas.
- **Sites WordPress « Madara » et « MangaThemesia »** (thèmes utilisés par beaucoup de sites de
  scans) : recherche, fiche, chapitres et **téléchargement** des chapitres en clair ; les
  chapitres réservés ou protégés renvoient vers le site.
- **Compilation automatique** Android, Windows et Linux sur GitHub à chaque version de test
  (première exécution avec cette version : à surveiller dans l'onglet « Actions » du dépôt).

Corrigé :
- Une adresse mobile (m.webtoons.com) ne crée plus un deuxième site.
- Dates de chapitres impossibles ou démesurées ignorées au lieu de bloquer un titre.

## 0.1.0-test.3 — version de test (2026-11-17)

Nouveau :
- **Plusieurs sites pour un même titre** : section « Sites » sur la fiche, bouton « Ajouter un
  autre site » (adresse du même titre sur l'autre site), « Retirer » (les chapitres non lus de
  ce site sont retirés, les chapitres téléchargés passent au rouge 24 h), « Définir comme site
  principal ». Nom du site sous chaque chapitre et filtre par site. Une seule version par
  numéro : votre langue préférée, puis une version téléchargeable, puis le site principal.
- **Scan-Manga** : suivi des titres (fiche, catégories, couverture, tous les chapitres) ; les
  chapitres se lisent sur le site (« Lire sur Scan-Manga »), le site cachant volontairement ses
  images. Pas de recherche dans l'application : collez l'adresse du titre.
- **Sources par défaut** : MangaDex et Scan-Manga présents dès le premier lancement (une source
  que vous supprimez n'est pas recréée).
- Ajout d'un titre déjà présent (même par un autre site) : sa fiche s'ouvre au lieu d'un doublon.

Corrigé :
- Changer de site principal ne change plus vos langues et ne programme aucune suppression.
- Le menu du type de site ne déborde plus sur un écran de téléphone.

Mise à jour d'une base existante : automatique (migration 7), aucune donnée perdue.

## 0.1.0-test.2 — version de test (2026-11-16)

Corrections de vos retours sur la 0.1.0-test.1 et étape 6.

Corrigé :
- **Couvertures** : elles s'affichent enfin (MangaDex renvoyait une page anti-robot) ; les fausses
  couvertures enregistrées par la test.1 sont remplacées automatiquement. Vignettes légères
  (512 px) dans la bibliothèque, image d'origine sur la fiche.
- **Téléchargement automatique** : dès l'ajout d'un titre et après chaque actualisation.
- **Langues** : plus aucun chapitre dans une langue non choisie.
- Les titres seulement « Favoris » sont bien vérifiés à chaque recherche de mises à jour.
- Titre de la fenêtre Windows (« Bibliothèque perso »).

Nouveau :
- Listes système **Planifié** (vérifié mais jamais annoncé) et **En attente** (automatique :
  titres sans chapitre dans vos langues, vérifiés toutes les heures, réglable).
- Onglet **Mises à jour** : vos titres triés par dernière parution dans vos langues.
- **Filtre des catégories** : entonnoir, chaque catégorie incluse ou exclue ; filtre de
  **niveau de contenu** (par défaut tout sauf pornographique).
- **Chapitres hébergés chez l'éditeur** (ex. Ruri Dragon sur MANGA Plus) : listés avec
  « Lire sur MANGA Plus », jamais téléchargés.
- **Couverture au choix** (couvertures du site, ou image de l'appareil par son chemin).
- **Export** de vos titres et sites (JSON complet + Markdown lisible) dans Paramètres.
- **Rapport d'erreur** exportable quand l'ajout d'un site ou d'un titre échoue.
- Suppressions prévues visibles dans l'onglet Téléchargements, repère « Gardé ».
- Mes langues, langues par titre, vérifications 1 à 24 fois par jour (00:00 / 12:00 UTC par défaut).

Mise à jour d'une base existante : automatique au premier lancement (listes, titres, lectures et
téléchargements conservés). Une liste à vous nommée « En attente » devient « En attente (perso) ».

Limites connues : seul MangaDex est lisible ; export et rapports dans un dossier privé sur
Android ; APK signé avec la clé de développement ; version Linux à construire sous Linux.

## 0.1.0-test.1 — version de test (2026-11-16)

Première version utilisable, à essayer avant publication.

- Ajout d'un manga MangaDex par son adresse (le site MangaDex est ajouté automatiquement) ;
  fiche complète : titres alternatifs, catégories, auteur, couverture, résumé.
- Bibliothèque : listes Favoris et Suivis, filtre par catégorie, recherche y compris dans les
  titres alternatifs.
- Téléchargement hors-ligne (une archive `.zip` par chapitre) avec vos règles :
  - Favoris : tous les chapitres non lus, et les 10 derniers lus gardés ;
  - Suivis : 10 chapitres au départ, puis une « vague » de 5 chapitres jusqu'au dernier lu et
    5 après ;
  - suppression automatique différée de 24 h (chapitre en rouge, boutons Garder / Supprimer
    maintenant) ; doublons en orange, à trier vous-même.
- Langues : vos langues par ordre de préférence (français puis anglais par défaut), langues
  propres à un titre ; une seule version par chapitre, l'anglais remplacé par le français à sa
  sortie.
- Lecteur intégré : défilement continu, zoom, chapitre suivant ; fin de chapitre = chapitre lu.
- Recherche des nouveaux chapitres à heures fixes : 00:00 et 12:00 UTC par défaut, réglable de
  1 à 24 fois par jour ; tâche de fond sur Android.
- Paramètres : limites de téléchargement, langues, sites, numéro de version.

Limites connues : seul MangaDex est lisible ; pas de notification Android ; APK signé avec la
clé de développement ; version Linux à construire sous Linux.
