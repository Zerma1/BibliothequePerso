# Journal des versions

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
