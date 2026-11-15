# Playbook du projet « Bibliothèque perso »

Ce document est **la référence de logique de code** du projet. Tout agent (IA ou humain) qui
écrit du code doit le lire avant de commencer. En cas de conflit entre ce playbook et une
habitude personnelle, **le playbook gagne**. Pour le modifier, il faut passer par l'orchestrateur
et obtenir la validation du client.

Documents liés :
- [CONVENTIONS_NOMMAGE.md](CONVENTIONS_NOMMAGE.md) : règles de nommage détaillées
- [README.md](README.md) : présentation et installation
- `.claude/agents/` : fiches des agents spécialisés

---

## 1. Objectif produit

Une application unique (Windows, Linux, Android) qui regroupe les livres, mangas, manhwas,
etc. que le client lit sur **plusieurs sites différents** :

1. **Ajouter des sites** à partir d'une simple URL `http://` ou `https://`.
2. **Ajouter des titres** depuis ces sites et enregistrer leur fiche : couverture, résumé,
   auteur, statut, catégories et liste des chapitres.
3. **Ranger les titres dans des listes** : « Favoris » et « Suivis » existent par défaut et ne
   peuvent pas être supprimées ; le client peut créer d'autres listes.
4. **Trier et filtrer par catégorie**, en reprenant les genres affichés sur les sites.
5. **Rechercher les mises à jour** de chaque titre et signaler les nouveaux chapitres.
6. **Télécharger les chapitres** (images ou texte) pour les lire hors-ligne dans l'application.

---

## 2. Rôles

| Rôle | Qui | Responsabilité |
|------|-----|----------------|
| Client | L'utilisateur | Exprime les besoins, valide les livrables, arbitre les choix produit. |
| Orchestrateur | Claude (session principale) | Découpe le travail, délègue aux agents, intègre, garantit la cohérence, rend compte au client. |
| Agents spécialisés | `.claude/agents/*.md` | Exécutent une tâche **dans leur scope uniquement**. |

**Créer un nouvel agent** : l'orchestrateur le propose au client en précisant son **but** et son
**scope**. Il ne l'enregistre dans `.claude/agents/` qu'après validation.

### Cycle d'une tâche
1. Le client formule un besoin.
2. L'orchestrateur le découpe en tâches, chacune attribuée à un seul agent.
3. L'agent spécialiste réalise la tâche dans son scope.
4. `testeur-qualite` lance `flutter analyze` et `flutter test`, puis ajoute ou complète les tests.
5. `relecteur-code` vérifie la conformité au playbook.
6. L'orchestrateur intègre et présente le résultat au client.

Un agent qui doit modifier un fichier **hors de son scope** s'arrête et le signale à
l'orchestrateur. Il ne fait pas la modification lui-même.

**`lib/services/` et `test/services/` sont écrits par l'agent `developpeur-services`** (créé à la
demande du client), sous la supervision de l'orchestrateur.
Cette couche assemble les sources et les données ; elle doit donc rester cohérente avec les
deux scopes. Les autres agents la lisent sans la modifier.

---

## 3. Pile technique

| Besoin | Choix | Paquet pub.dev |
|--------|-------|----------------|
| Interface multiplateforme | Flutter (Dart) | SDK |
| Widgets Material (`MaterialApp`, `Scaffold`…) | imposé par le modèle Flutter 3.50 | `material_ui` |
| Requêtes HTTP | client HTTP officiel | `http` |
| Analyse HTML | parseur DOM avec sélecteurs CSS | `html` |
| Base de données | SQLite | `sqflite` (Android), `sqflite_common_ffi` (Windows, Linux) |
| Dossiers de l'application | répertoires système | `path_provider`, `path` |
| Archives des chapitres | fichiers `.zip` | `archive` |
| Gestion d'état | ChangeNotifier | `provider` |
| Tâche de fond Android | planification périodique | `workmanager` (Android uniquement) |
| Ouvrir le site dans le navigateur | lien externe | `url_launcher` |

**Règle anti-hallucination** : n'utiliser que des API réellement documentées sur pub.dev ou
api.flutter.dev. En cas de doute, écrire une implémentation explicite ou signaler la limite
dans un commentaire `// LIMITE :`. **Ne jamais inventer une méthode.**

Pour ajouter un paquet, il faut l'accord de l'orchestrateur. C'est l'agent
`integrateur-plateformes` qui modifie `pubspec.yaml`.

---

## 4. Architecture en couches

```
lib/
├── main.dart            Point d'entrée : initialise la base et les fournisseurs (providers)
├── modeles/             Classes de données pures (aucune dépendance Flutter ni réseau)
├── donnees/             SQLite, dépôts (repositories), stockage des fichiers téléchargés
├── sources/             Lecture des sites : interface commune + adaptateurs
├── services/            Logique métier : mises à jour, file de téléchargement, ajout de site
├── etat/                ChangeNotifier exposés à l'interface
├── ecrans/              Pages complètes
└── widgets/             Composants réutilisables
test/                    Même arborescence que lib/
```

### Sens des dépendances (strict)

```
ecrans / widgets  →  etat  →  services  →  donnees, sources  →  modeles
```

- Une couche importe **uniquement les couches à sa droite**.
- `ecrans` ne fait **jamais** d'appel HTTP ni de requête SQL directe.
- `sources` ne touche **jamais** la base de données : elle renvoie des objets `modeles`.
- `donnees` ne fait **jamais** d'appel réseau, sauf `StockageTelechargements`, qui écrit sur
  disque des octets déjà récupérés par un service.
- `modeles` ne dépend de rien, à part `dart:core`.

---

## 5. Modèle de données

### Entités (`lib/modeles/`)

| Classe | Champs principaux |
|--------|-------------------|
| `Source` | `id`, `nom`, `urlBase`, `typeSource` (`mangaDex`, `madara`, `mangaThemesia`, `generique`), `langueParDefaut` (code ISO 639-1), `configurationSelecteurs` (JSON, uniquement pour le type générique), `estActive` |
| `Titre` | `id`, `idSource`, `urlTitre`, `nom`, `typeTitre` (`manga`, `manhwa`, `manhua`, `roman`, `livre`, `autre`), `urlCouverture`, `resume`, `auteur`, `statut`, `titresAlternatifs` (liste de `TitreAlternatif`), `dateDerniereVerification`, `nombreChapitresNonLus` |
| `TitreAlternatif` | `id`, `idTitre`, `nom`, `langue` (code ISO 639-1, peut être vide) |
| `Chapitre` | `id`, `idTitre`, `urlChapitre`, `nom`, `numero` (double), `langue` (code ISO 639-1), `datePublication`, `estLu`, `estTelecharge` |
| `ListeLecture` | `id`, `nom`, `estSysteme` (true pour Favoris et Suivis), `ordre` |
| `Categorie` | `id`, `nom` (normalisé : minuscules, sans espaces autour). Deux sites qui donnent le même genre partagent la même catégorie. |

### Tables SQLite

```
sources(id, nom, url_base UNIQUE, type_source, langue_par_defaut, configuration_selecteurs,
        est_active)
titres(id, id_source → sources, url_titre UNIQUE, nom, type_titre, url_couverture, resume,
       auteur, statut, date_derniere_verification)
chapitres(id, id_titre → titres ON DELETE CASCADE, url_chapitre UNIQUE, nom, numero, langue,
          date_publication, est_lu, est_telecharge, date_detection)
titres_alternatifs(id, id_titre → titres ON DELETE CASCADE, nom, langue,
                   UNIQUE(id_titre, nom))
listes(id, nom UNIQUE, est_systeme, ordre)
titres_listes(id_titre, id_liste)            -- relation plusieurs-à-plusieurs
categories(id, nom UNIQUE)
titres_categories(id_titre, id_categorie)    -- relation plusieurs-à-plusieurs
```

- Les noms de colonnes sont en `snake_case`, alors que les champs Dart sont en `lowerCamelCase`.
  La conversion se fait **uniquement** dans les méthodes `versMap()` et `depuisMap()` du modèle.
- Toute évolution du schéma passe par une **migration versionnée** dans
  `lib/donnees/migrations.dart`. On ne modifie jamais une migration déjà livrée.
- Les listes « Favoris » et « Suivis » sont créées par la migration 1, avec `est_systeme = 1`.
- La recherche dans la bibliothèque porte sur `titres.nom` **et** sur `titres_alternatifs.nom`
  (insensible à la casse) : chercher « Death's Daughter » retrouve un titre enregistré sous son
  nom japonais.

### Fichiers hors-ligne : une archive `.zip` par chapitre (idée du client)

```
<dossier racine>/<type>/<nom du titre>/ch<numero>.<langue>.zip
    img1.jpg, img2.jpg, img3.webp, …   (pages d'un chapitre en images)
    contenu.html                        (chapitre texte, pour les romans)
```

Exemple : `manga/One Punch Man/ch1.en.zip`, `manhwa/Solo Leveling/ch10.5.fr.zip`.

- **`<dossier racine>`** se règle dans les paramètres. Par défaut :
  `<dossier documents de l'app>/bibliotheque_perso/`.
- **`<type>`** est la valeur de `Titre.typeTitre` : `manga`, `manhwa`, `manhua`, `roman`,
  `livre` ou `autre`.
- **`<nom du titre>`** est le nom nettoyé pour le système de fichiers : on retire les caractères
  `< > : " / \ | ? *` et les points ou espaces en fin de nom. Si deux titres de sources
  différentes donnent le même nom, on ajoute ` (<nom de la source>)`.
- **`<numero>`** est le numéro du chapitre sans zéros inutiles (`1`, `10.5`). Dans l'application,
  le tri se fait sur `Chapitre.numero` (un double), pas sur le nom du fichier.
- **`<langue>`** est le code ISO 639-1 (`fr`, `en`…) de `Chapitre.langue`. Par défaut, c'est la
  langue de la source.
- Les images sont numérotées dans l'ordre de lecture (`img1`, `img2`…) et gardent leur
  extension d'origine.
- L'archive est créée **sans recompression** (mode *store*) : les images sont déjà compressées, ce
  qui rend l'écriture et la lecture plus rapides. On utilise le paquet `archive`.
- On écrit d'abord un fichier `.zip.part`, renommé en `.zip` une fois complet : une archive
  interrompue n'est donc jamais prise pour un chapitre téléchargé.
- Le lecteur lit les images **directement dans l'archive**, sans l'extraire sur le disque.

`StockageTelechargements` est la seule classe qui construit ces chemins, crée les archives et les
lit.

---

## 6. Moteur de sources (`lib/sources/`)

### Interface commune

```dart
abstract class SourceSite {
  Future<List<Titre>> rechercher(String requete);
  Future<FicheTitre> recupererFiche(String urlTitre);       // fiche + catégories
  Future<List<Chapitre>> recupererChapitres(String urlTitre);
  Future<ContenuChapitre> recupererContenu(String urlChapitre); // URLs d'images ou texte
}
```

### Ajout d'un site par URL
`DetecteurTypeSite` regarde d'abord le domaine, puis télécharge la page d'accueil :
0. Si le domaine est `mangadex.org`, le type est `mangaDex` (voir ci-dessous), sans analyser le
   HTML.
1. Si l'on trouve des marqueurs Madara forts (classes `wp-manga`, script `madara`), le type
   est `madara`.
2. Si l'on trouve des marqueurs MangaThemesia (`ts_reader`, classe `bixbox`), le type est
   `mangaThemesia`.
2 bis. Sinon, des liens en `/manga/` ne sont qu'un indice faible de Madara (beaucoup de sites
   MangaThemesia les utilisent aussi). Le formulaire d'ajout permet de corriger le type détecté.
3. Sinon, le type est `generique` : le client renseigne les sélecteurs CSS dans un formulaire
   (titre, couverture, liste des chapitres, images d'un chapitre, catégories).

### Cas particulier : MangaDex (`SourceMangaDex`)
Les pages de MangaDex sont construites en JavaScript : le HTML téléchargé ne contient pas les
données. `SourceMangaDex` utilise donc l'**API publique officielle** `https://api.mangadex.org`
(réponses JSON lues avec `dart:convert`), toujours via `ClientHttpPoli`.

- L'identifiant d'un titre est l'UUID présent dans l'URL
  `https://mangadex.org/title/<uuid>/<nom-lisible>` ; celui d'un chapitre, l'UUID de
  `https://mangadex.org/chapter/<uuid>`.
- Le titre principal, les titres alternatifs, les tags (catégories), la couverture et les
  chapitres par langue viennent de l'API.
- Les points d'accès exacts, les paramètres et les limites de requêtes sont **vérifiés dans la
  documentation officielle** (`https://api.mangadex.org/docs/`) avant d'être codés, puis cités en
  commentaire. Aucun point d'accès n'est écrit de mémoire.
- Les tests utilisent des **réponses JSON enregistrées** dans `test/sources/exemples_json/`.
- Règles d'usage de MangaDex (documentation officielle, relevées le 2026-11-15) :
  - User-Agent honnête obligatoire ; environ 5 requêtes/s par IP (notre délai de 1 s est plus
    strict) ; `/at-home/server` limité à 40 requêtes/min (1,5 s entre deux appels) ;
  - en cas de 429, respecter `Retry-After` : insister mène à un bannissement temporaire ;
  - pagination plafonnée à `offset + limit ≤ 10 000` ;
  - l'adresse du serveur d'images (`baseUrl`) n'est valable que 15 minutes : on télécharge juste
    après l'avoir obtenue, et on la redemande en cas d'erreur 403 ;
  - chaque image chargée depuis un serveur MangaDex@Home doit être signalée à
    `POST https://api.mangadex.network/report` (étape 5) ;
  - l'interface crédite MangaDex et les groupes de traduction, et l'application ne contient
    aucune publicité.
- Titre de référence pour les tests : *Shinigami ni Sodaterareta Shoujo wa Shikkoku no Tsurugi
  wo Mune ni Idaku* (`12e28a8a-cbfe-4e12-bab8-b6fb0b9a59b4`), avec 6 titres alternatifs et les
  tags Gore, Action, Comedy, Survival, Magic, Military, Fantasy, Supernatural, Adaptation.

Pour ajouter un nouveau type de thème, on crée une nouvelle classe qui implémente `SourceSite`
et on l'enregistre dans `FabriqueSources`. **On ne modifie pas les adaptateurs existants pour
gérer un cas particulier.**

### Règles réseau (obligatoires)
- Toutes les requêtes passent par **`ClientHttpPoli`**, la seule classe autorisée à appeler
  `package:http`. Elle s'occupe de :
  - l'en-tête `User-Agent` d'un navigateur courant par défaut ; **sauf si le site exige un
    User-Agent honnête** (cas de l'API MangaDex, qui interdit d'usurper un navigateur) : on
    envoie alors `BibliothequePerso/<version> (usage personnel)` ;
  - l'en-tête `Referer` pour les images, que beaucoup de sites exigent ;
  - un délai minimal de **1 seconde entre deux requêtes vers un même domaine** ;
  - un délai d'expiration de 20 secondes et 2 nouvelles tentatives au maximum.
- Une erreur de lecture d'un site lève une `ErreurSource` (avec l'URL et la cause). Elle ne doit
  **jamais** faire planter l'interface : le service l'attrape et l'enregistre.
- Les URLs relatives sont toujours résolues avec `Uri.parse(urlBase).resolve(lien)`.

### Tests des adaptateurs
Chaque adaptateur est testé avec des **pages HTML enregistrées** dans
`test/sources/exemples_html/`. Les tests ne font jamais d'appel réseau réel.

---

## 7. Services

| Service | Rôle |
|---------|------|
| `ServiceAjoutSite` | Valide l'URL (`http`/`https`), détecte le type et enregistre la `Source`. |
| `ServiceMisesAJour` | Pour chaque titre suivi, récupère les chapitres, insère les nouveaux et met à jour `date_derniere_verification`. Vérifie au maximum 3 sources en parallèle, et un seul titre à la fois par source. |
| `ServiceTelechargement` | File d'attente persistante. Récupère le contenu, télécharge les images avec `ClientHttpPoli` et les écrit via `StockageTelechargements`. Peut reprendre après une interruption. |

**Planification des mises à jour**
- Android : `workmanager`, tâche périodique (intervalle réglable, 1 heure au minimum).
- Windows et Linux : `Timer.periodic` tant que l'application est ouverte, plus une vérification
  au démarrage.

---

## 8. Interface

- Écrans : `EcranBibliotheque` (grille de couvertures, filtres par liste et par catégorie),
  `EcranTitre` (fiche et chapitres), `EcranLecteur`, `EcranSources`, `EcranAjoutSite`,
  `EcranRecherche`, `EcranTelechargements`, `EcranParametres`.
- **Responsive** : une barre de navigation en bas sous 600 px de large, et un `NavigationRail`
  au-delà.
- Un widget ne contient pas de logique métier : il lit un `ChangeNotifier` de `lib/etat/` et
  appelle ses méthodes.
- Tout texte affiché est en français. Il est regroupé dans `lib/widgets/textes.dart` pour
  faciliter une traduction future.

---

## 9. Qualité

- `flutter analyze` doit renvoyer **0 erreur et 0 avertissement** avant toute livraison.
- Toute classe publique a un commentaire de documentation `///`. Tout bloc non évident a un
  commentaire `//` qui explique **pourquoi**, pas seulement **quoi**.
- Pas de `print` : on utilise `debugPrint` ou le journal applicatif `Journal`.
- Pas de `dynamic` implicite. On utilise `as` avec vérification sur les données venant du HTML
  ou de SQLite.
- Pas de valeur magique : les constantes partagées vont dans `lib/modeles/constantes.dart` ;
  celles propres à une couche vont dans le fichier de constantes de cette couche (par exemple
  `lib/sources/constantes_sources.dart`).

---

## 10. Usage responsable

L'application est destinée à un **usage personnel**. Elle respecte la charge des sites grâce aux
délais de `ClientHttpPoli` et ne contourne aucune protection d'accès (connexion, paywall, DRM).

---

## 11. Feuille de route

| Étape | Contenu | Agents |
|-------|---------|--------|
| 0 | Créer le projet Flutter (`flutter create`), ajouter les dépendances, cibles Windows, Linux et Android | integrateur-plateformes |
| 1 | Modèles, base SQLite, migrations, dépôts | developpeur-donnees, testeur-qualite |
| 2 | `ClientHttpPoli`, `DetecteurTypeSite`, adaptateur MangaDex (site réel du client) | developpeur-sources, testeur-qualite |
| 3 | Écrans Bibliothèque, Sources, Ajout de site, Titre | developpeur-interface |
| 4 | Mises à jour (service et planification) | orchestrateur (services), integrateur-plateformes |
| 5 | Téléchargement hors-ligne, règles de conservation (favoris / suivis), lecteur, Paramètres, numéro de version | orchestrateur (services), developpeur-donnees, developpeur-interface |
| 6 | **Retours du client (test du 2026-11-15)** : listes système « Planifié » (pas de notification de mise à jour) et « En attente » (aucun chapitre dans les langues du client, surveillance plus fréquente) ; onglet « Mises à jour » trié par dernière parution dans les langues du client ; filtre par catégories pensé pour de nombreuses catégories / tags ; filtre par niveau de contenu (sûr, suggestif, érotique, pornographique) ; export d'un rapport d'erreur lors d'un échec d'ajout de site | orchestrateur, developpeur-donnees, developpeur-sources, developpeur-interface |
| 7 | Autres sites : adaptateurs Madara, MangaThemesia, générique CSS ; diagnostic de scan-manga.com et webtoons.com (signalés illisibles par le client) ; sites proposés par défaut | developpeur-sources |
| 8 | **Plusieurs sources pour un même titre** (ex. un titre présent sur MangaDex et scan-manga) pour un meilleur suivi des mises à jour : évolution du modèle (titre ↔ sources) | orchestrateur, developpeur-donnees, developpeur-sources, developpeur-interface |
| 9 | Compilation et livraison **simultanées** sur Android, Windows et Linux (intégration continue GitHub Actions, la version Linux ne pouvant pas se compiler sous Windows) | integrateur-plateformes |

Chaque étape se termine par une relecture (`relecteur-code`) et une validation du client.

### Idées pour des versions futures (à prévoir, pas à implémenter maintenant)

Demandées par le client le 2026-11-15. Le code actuel ne doit pas les fermer :

| Idée | Ce qu'il faut préserver dès maintenant |
|------|----------------------------------------|
| **Stockage des chapitres sur un NAS ou un serveur personnel** | `StockageTelechargements` reste le **seul** point d'accès aux archives : aucune autre classe ne lit ni n'écrit de fichier de chapitre. On pourra alors en faire une interface avec plusieurs implémentations (disque local, partage réseau, serveur WebDAV…). |
| **Publicité dans l'application** | ⚠️ Incompatible avec les conditions d'utilisation de MangaDex, qui interdisent toute publicité dans une application utilisant son API (section 6). À trancher par le client avant toute implémentation : publicité absente quand MangaDex est utilisé, ou abandon de l'idée. Garder l'interface découpée en écrans et widgets réutilisables pour pouvoir y réserver un emplacement. |
| **Regroupement des catégories de même sens** (« Survival » / « Survie », « Comedy » / « Comédie ») | Les catégories restent normalisées dans une seule table et liées aux titres par `titres_categories`. On pourra ajouter une table d'équivalences (catégorie → catégorie de référence) et un dictionnaire de traductions, sans toucher aux adaptateurs de sites. |


---

## 12. Branches et versions

### Branches Git
| Branche | Rôle |
|---------|------|
| `dev` | **Tout le développement se fait ici.** On y code, on y teste en local (`flutter analyze`, `flutter test`, lancement de l'application). |
| `main` | **Réservée au déploiement des versions.** On n'y code jamais directement. |

- Aucun agent ne commite sur `main`.
- Une version passe de `dev` à `main` seulement quand le client l'a validée et que
  `flutter analyze` et `flutter test` ne signalent aucun problème.
- La fusion vers `main` est suivie d'une étiquette Git `vX.Y.Z` (exemple : `v1.4.2`).

### Numéro de version : `X.Y.Z`
| Partie | Quand l'augmenter | Exemple |
|--------|-------------------|---------|
| **X** (majeure) | Changement incompatible avec les versions précédentes : le fonctionnement global change et les habitudes ou les données doivent être adaptées. Y et Z repartent à 0. | `1.4.2` → `2.0.0` |
| **Y** (mineure) | Nouvelle fonctionnalité qui ne casse rien de l'existant. Z repart à 0. | `1.4.2` → `1.5.0` |
| **Z** (corrective) | Correction d'un bug ou d'une faille, sans nouveauté ni rupture. | `1.4.2` → `1.4.3` |

- La version est écrite dans `pubspec.yaml` sous la forme `version: X.Y.Z+N`, où `N` est le
  numéro de build. Flutter l'exige, et Android a besoin qu'il augmente à chaque version publiée.
- Tant que l'application n'a pas eu de première version stable, on reste en `0.Y.Z`.
