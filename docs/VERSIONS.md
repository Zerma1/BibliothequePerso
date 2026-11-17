# Journal des versions

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
