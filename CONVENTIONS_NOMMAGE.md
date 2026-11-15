# Conventions de nommage

Règle générale : **le code métier est nommé en français ; la syntaxe du langage et les API
externes restent dans leur langue d'origine.** Ce contraste permet de voir immédiatement ce
qui appartient au projet et ce qui vient de Dart, de Flutter ou d'un paquet.

## 1. Pas d'accents dans les identifiants

En Dart, un identifiant ne peut contenir que des lettres ASCII, des chiffres, `_` et `$`.
On retire donc les accents : `categorie`, `resume`, `numero`, `telecharger`, `etat`.
Les accents restent autorisés dans les **commentaires** et les **textes affichés**.

## 2. Casse (conventions officielles de Dart)

| Élément | Style | Exemple |
|---------|-------|---------|
| Classe, enum, typedef, extension | `UpperCamelCase` | `DepotTitres`, `TypeSource` |
| Variable, paramètre, méthode, champ | `lowerCamelCase` | `listeTitres`, `recupererChapitres()` |
| Constante | `lowerCamelCase` | `delaiEntreRequetes` |
| Fichier, dossier | `snake_case` | `depot_titres.dart`, `ecrans/` |
| Membre privé | préfixe `_` | `_baseDeDonnees` |
| Colonne et table SQLite | `snake_case` | `date_derniere_verification` |

## 3. Préfixes et suffixes par rôle

| Rôle | Forme | Exemples |
|------|-------|----------|
| Écran | `Ecran<Nom>` | `EcranBibliotheque`, `EcranLecteur` |
| Widget réutilisable | nom descriptif | `CarteTitre`, `PastilleCategorie` |
| État (ChangeNotifier) | `Etat<Nom>` | `EtatBibliotheque` |
| Service | `Service<Nom>` | `ServiceMisesAJour` |
| Dépôt (accès base) | `Depot<Nom>` | `DepotChapitres` |
| Adaptateur de site | `Source<Theme>` | `SourceMadara`, `SourceGenerique` |
| Exception | `Erreur<Nom>` | `ErreurSource`, `ErreurBaseDeDonnees` |
| Test | `<fichier>_test.dart` | `source_madara_test.dart` |

## 4. Verbes des méthodes

| Verbe | Sens |
|-------|------|
| `recuperer…` | Lire depuis le réseau (sources) |
| `charger…` | Lire depuis la base ou le disque |
| `enregistrer…` | Insérer ou mettre à jour en base |
| `supprimer…` | Effacer |
| `verifier…` | Contrôle qui renvoie un résultat, sans effet de bord |
| `telecharger…` | Récupérer un fichier et l'écrire sur disque |
| `est…` / `a…` | Booléen (`estLu`, `aDesNouveautes`) |
| `depuis…` / `vers…` | Conversion (`depuisMap`, `versMap`) |
| `creer…` | Créer un nouvel élément choisi par l'utilisateur (`creerListe`) |
| `renommer…` | Changer le nom d'un élément existant |
| `ajouter…` / `retirer…` | Ajouter ou enlever un lien entre deux éléments, sans supprimer ni l'un ni l'autre (`ajouterTitre` à une liste) |
| `marquer…` | Changer un état booléen (`marquerLu`, `marquerTelecharge`) |
| `compter…` | Renvoyer un nombre sans effet de bord (`compterNonLus`) |

## 5. Vocabulaire du domaine (à respecter partout)

| Terme | Signification |
|-------|---------------|
| `Source` | Un site configuré dans l'application |
| `Titre` | Une œuvre : manga, livre, webtoon… |
| `Chapitre` | Une unité de lecture d'un titre |
| `ListeLecture` | Un regroupement de titres créé par l'utilisateur ou par le système |
| `Categorie` | Un genre ou un tag repris des sites |
| `Fiche` | Les métadonnées complètes d'un titre |
| `Contenu` | Les pages (URLs d'images) ou le texte d'un chapitre |

Avant d'utiliser un synonyme (« œuvre », « série », « livre » dans le code), on vérifie qu'un
terme de cette table n'existe pas déjà.

## 6. Exceptions autorisées à l'anglais

- Les mots-clés et types Dart : `class`, `Future`, `List`, `String`…
- Les méthodes surchargées d'un framework : `build`, `initState`, `dispose`, `toString`, `==`,
  `hashCode`.
- Les API externes appelées telles quelles : `http.get`, `querySelectorAll`, `openDatabase`.
- Les noms imposés par un outil : `main.dart`, `pubspec.yaml`, `analysis_options.yaml`.
