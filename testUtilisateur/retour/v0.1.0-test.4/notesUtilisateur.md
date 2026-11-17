je ne peut pas encor tester la vertion android et ne me concentre que sur la vertion windows

Les lien externe sont bien afficher

manga tester pour l'ajout de lien : Potion-danomi de Ikinobimasu!
ce que l'utilisateur a fait : 
1. ouvrire l'application
2. trouver le titre desiré (Potion-danomi de Ikinobimasu!)
3. verifier el lien présent (https://mangadex.org/title/8fe5cbe9-c968-4e89-bc5b-b16a4420c70c)
4. verifier la presence de ce titre sur le site https://www.scan-manga.com (lien du titre sur le sit scan manga : https://www.scan-manga.com/6678/Potion-danomi-de-Ikinobimasu.html)
5. dans l'aplication, cliquer sur "ajouter un autre site"
6. coller le lien puis ajouter -> rapport_20261117_082051

teste réitérer avec le titre Ruri Dragon
1. ouvrire l'application
2. trouver le titre desiré (Ruri Dragon) 
3. verifier el lien présent (https://mangadex.org/title/141609b6-cf86-4266-904c-6648f389cdc9)
4. trouver un autre site sur le web (https://ruri-dragon.online/)
5. ouvire le chapitre 1 pour verifier le lien (https://ruri-dragon.online/comic/ruri-dragon-chapter-1/)
6. ajouter le sit au source : 
   1. Adresse du site : https://ruri-dragon.online*
   2. nom : vide (laissé par défaut)
   3. langue par défaut : vide (laissé par défaut)
   4. type de site : détéction atomatique
   5. ajouter
7. verifier la presence dans les source : présent en Générique (selecteurs CSS)
8. retour a la bibliotheque
9. selectioner le titre (Ruri Dragon)
10. cliquer sur "ajouter un autre site"
11. coler le lien https://ruri-dragon.online pui ajouter -> rapport_20261117_081649
12. etape 10 et 11 en changeant le lien par celui du chapitre 1 (https://ruri-dragon.online/comic/ruri-dragon-chapter-1/) -> rapport_20261117_083616

il faudrais donner les criter de lecture des site car, dans le cas d'exemple Ruri Dragon
j'ai trouver ce site web au lien parfaitement explicite https://ruri-dragon.online/comic/ruri-dragon-chapter-1/ et ne
comprend pas le rejet du lien quand je veut l'ajouter en lien de manga rapport_20261117_081649

ajouter un type de format de source pour les lien explicites serait une bonne idée

---

dans la branche teste
génère moi une liste de teste a effectuer que je te face mon retour

---
Rappel : vos décisions en attente.
| décisions en attente | décisions Utilisateur |
| --- | --- |
| La clé de signature Android : sans elle, les APK compilés par GitHub ne pourront pas mettre à jour celui de votre téléphone. En attendant, utilisez celui de livraisons/. | pas de moyen de tester sur androide, tache reste en attente | 
| Le paquet ``webview_flutter``, pour lire MANGA Plus dans une vue web officielle intégrée. | oui integre pour pouvoir lire tout lien externe directement dans l'aplication en passant par le navigateur par defaut |
| Le paquet file_selector, pour choisir l’image de couverture dans une fenêtre de sélection. | ce qui est en place dans la v0.1.0-teste4 me convien deja|
| Le paquet share_plus, pour partager l’export et les rapports d’erreur sur Android. |  pas de moyen de tester sur androide, tache reste en attente|
| Le bouton « Contenu » : à garder dans la bibliothèque ou à déplacer dans Paramètres. |  garder dans la bibliothèque|