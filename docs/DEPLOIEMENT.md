# Procédure de déploiement

Trois branches, trois rôles :

| Branche | Rôle | Qui y écrit |
|---------|------|-------------|
| `dev` | Développement quotidien : tout le code est écrit et testé ici. | Les agents et l'orchestrateur |
| `test` | **Versions de test** à essayer par le client avant publication. On n'y code jamais : on y fait seulement avancer une version de `dev` qui a passé les vérifications. | L'orchestrateur |
| `main` | **Versions publiées**, validées par le client après essai de la version de test. | L'orchestrateur, avec l'accord du client |

Le chemin d'une version est toujours : `dev` → `test` (essai par le client) → `main`.

## Numéros de version

Format `X.Y.Z` (voir PLAYBOOK.md section 12). Une version de test porte le numéro de la version
visée suivi de `-test.N` : `0.1.0-test.1`, puis `0.1.0-test.2` si une correction est
nécessaire, puis `0.1.0` sur `main` une fois validée.

- Dans `pubspec.yaml` : `version: 0.1.0+N` (Flutter n'accepte pas `-test` dans le numéro de
  build Android ; le `+N` augmente à chaque version de test).
- Étiquettes Git : `v0.1.0-test.1` sur `test`, `v0.1.0` sur `main`.

### Choisir le numéro de la version suivante

Après chaque publication sur `main` (version `X.Y.Z`), la version suivante prend :
- **`X.(Y+1).0`** dès qu'elle apporte une nouveauté (fonctionnalité, nouveau site, nouvel écran),
  même accompagnée de corrections ;
- **`X.Y.(Z+1)`** si elle ne contient **que** des corrections de bugs de `X.Y.Z` ;
- **`(X+1).0.0`** si elle casse l'existant (données à refaire, habitudes à changer).

**Versions de test (règle du client, 2026-11-17)** : une version publiée sur `test` s'appelle
**`X.Y.Z-test`** (ex. `0.2.0-test`). Le suffixe « -test » signale seulement qu'elle est sur la
branche `test` et attend les retours de l'équipe de test. Une nouvelle itération de corrections
pendant les tests augmente **Z** (`0.2.1-test`, `0.2.2-test`…). Une fois validée, la version
passe sur `main` sous le même numéro sans « -test » (`0.2.1`).
**Deux versions de test n'ont jamais le même numéro** : chaque nouvelle publication sur
`test` augmente au moins Z, même s'il ne s'agit que de tests (`0.2.0-test`, `0.2.1-test`,
`0.2.2-test`…). Une étiquette déjà publiée n'est jamais réutilisée ni déplacée.
**Chaque version de test contient sa liste de tests à effectuer** :
`testUtilisateur/plan_de_tests_vX.Y.Z-test.md`, et les retours vont dans
`testUtilisateur/retour/vX.Y.Z-test/`.
Le numéro de build `+N` de `pubspec.yaml` augmente toujours, quelle que soit la version.

## 1. Préparer une version de test (sur `dev`)

```powershell
git switch dev
git pull
flutter analyze            # doit afficher : No issues found!
flutter test               # doit afficher : All tests passed!
```

Ensuite :
- vérifier que `docs/TACHES_EN_COURS.md` ne contient aucune tâche bloquante ouverte ;
- relecture complète par `relecteur-code` : aucun point bloquant ;
- mettre à jour `version` dans `pubspec.yaml` (+N) et `versionApplication` dans
  `lib/widgets/constantes_interface.dart` (le test `constantes_interface_test.dart` vérifie
  qu'ils correspondent) ;
- noter les nouveautés dans `docs/VERSIONS.md` (journal des versions, en français, pour le
  client).

## 2. Publier sur la branche `test`

```powershell
git switch test
git merge --no-ff -X theirs dev -m "Version de test X.Y.Z-test"
git diff --quiet dev -- lib test pubspec.yaml docs .github   # doit être vrai : code identique à dev
git tag -a vX.Y.Z-test -m "Version de test X.Y.Z-test"
git push origin test --follow-tags
git switch dev
```

`test` contient des commits propres (les fichiers de `livraisons/`) que `dev` n'a pas : une
avance rapide est donc impossible, on **fusionne** en donnant la priorité à `dev`
(`-X theirs`), puis on vérifie que le code est identique à celui de `dev`. Sans pouvoir
changer de branche dans le dossier de travail (agents en cours), on fait la même chose dans un
dossier séparé : `git worktree add <dossier> test`.

## 3. Construire les fichiers à installer

Depuis la branche `test` (ou `main` pour une version publiée), sous Windows :

```powershell
git switch test
flutter clean
flutter pub get
flutter build windows --release
flutter build apk --release
git switch dev
```

| Plateforme | Fichier produit | À livrer |
|------------|-----------------|----------|
| Windows | `build\windows\x64\runner\Release\` | **tout le dossier** compressé en `.zip` (l'exe a besoin de `data\` et des `.dll`) |
| Android | `build\app\outputs\flutter-apk\app-release.apk` | le fichier `.apk` |
| Linux | `build/linux/x64/release/bundle/` | **à construire sous Linux ou WSL2** : `flutter build linux --release`, puis compresser le dossier `bundle` |

Nommer les fichiers avec la version : `bibliotheque_perso-0.1.0-test.1-windows.zip`,
`bibliotheque_perso-0.1.0-test.1-android.apk`, `bibliotheque_perso-0.1.0-test.1-linux.tar.gz`.

Limites actuelles :
- l'APK est signé avec la **clé de développement** de Flutter : il s'installe, mais une future
  version signée avec une vraie clé demandera de désinstaller l'ancienne ;
- la version Linux ne se construit pas sous Windows : utiliser la compilation automatique
  ci-dessous, qui construit les trois plateformes en même temps.

## 3 bis. Compilation automatique (GitHub Actions)

Le workflow `.github/workflows/compilation.yml` construit **Windows, Linux et Android en même
temps** sur les machines de GitHub.

### Quand il se lance

| Événement | Ce qui est fait |
|-----------|-----------------|
| Push sur la branche `test` | analyse + tests, puis les trois compilations ; fichiers en **artefacts** |
| Étiquette `v*` poussée (`v0.1.0-test.4`, `v0.1.0`…) | idem, puis **release GitHub** avec les cinq fichiers (section « Où trouver les fichiers ») : *pre-release* si l'étiquette contient `-test.`, release normale sinon |
| Lancement manuel | onglet **Actions** → « Compilation » → « Run workflow » (choisir la branche ou l'étiquette) |
| Push sur `dev` ou `main` | **rien** (économie de minutes) |
| Push sur `test` ne touchant que `livraisons/` (section 4) | **rien** (`paths-ignore`) |

Le filtre `paths-ignore: livraisons/**` ne concerne que les push de branche : d'après la
documentation GitHub (« Workflow syntax », `on.push.paths`), *« Path filters are not
evaluated for pushes of tags »*. Une étiquette `v*` déclenche donc toujours la compilation.

`git push origin test --follow-tags` (section 2) envoie la branche et l'étiquette ensemble :
GitHub lance alors deux exécutions, mais celle de la branche voit que le commit porte une
étiquette `v*` et s'arrête après la préparation ; seule celle de l'étiquette compile.

### Étapes

1. **Préparation** : calcule la version des fichiers. Pour une étiquette, c'est l'étiquette
   sans le `v` (`0.1.0-test.4`) ; le workflow échoue si elle ne commence pas par le `X.Y.Z`
   de `pubspec.yaml`. Sans étiquette : `X.Y.Z-build.N` lu dans `pubspec.yaml`
   (ex. `0.1.0-build.3`).
2. **Analyse et tests** : `flutter analyze` puis `flutter test` (sous Linux). En cas d'échec,
   rien n'est compilé.
3. **En parallèle** (Flutter 3.50.0, révision `ab2912035e`, vérifiée à chaque job) :
   - Windows (`windows-latest`) : `flutter build windows --release`, dossier
     `build\windows\x64\runner\Release` compressé ; puis installation d'**Inno Setup 6.7.3**
     (installateur officiel `innosetup-6.7.3.exe` des releases GitHub `jrsoftware/issrc`,
     vérifié avant exécution par son empreinte SHA-256 épinglée dans le workflow et par sa
     signature Authenticode « Pyrsys B.V. »), et construction de l'installateur par
     `outils\construire_installateur.ps1 -SansCompilation -CheminIscc <ISCC.exe>` (même
     script que sur le PC) ; enfin calcul de son empreinte SHA-256 ;
   - Linux (`ubuntu-latest`) : paquets `clang cmake ninja-build pkg-config libgtk-3-dev`, puis
     `flutter build linux --release`, dossier `bundle` compressé (il se décompresse dans un
     dossier `bibliotheque_perso-<version>/`) ;
   - Android (`ubuntu-latest`, Java 17) : `flutter build apk --release`.
4. **Release GitHub** (étiquettes seulement) : créée avec le seul `GITHUB_TOKEN` fourni par
   GitHub, **aucun secret à créer**. Si la release existe déjà (relance du workflow), ses
   fichiers sont remplacés.

### Où trouver les fichiers

- `bibliotheque_perso-<version>-windows.zip`, `bibliotheque_perso-<version>-installation.exe`,
  `bibliotheque_perso-<version>-installation.exe.sha256`,
  `bibliotheque_perso-<version>-linux.tar.gz`, `bibliotheque_perso-<version>-android.apk`.
  `<version>` est l'étiquette sans le `v` (`0.4.0`, `0.4.0-test`) ou `X.Y.Z-build.N` sans
  étiquette. L'installateur est renommé avec cette version (Inno Setup le produit sous le
  nom `bibliotheque_perso-X.Y.Z-installation.exe`, sans suffixe) ; la version affichée par
  l'installateur reste `X.Y.Z` de `pubspec.yaml`.

#### Noms figés (mise à jour automatique de l'application, 0.4.0)

L'application consulte la **dernière release publiée** (étiquette `vX.Y.Z`, ni brouillon ni
*pre-release*) et télécharge l'installateur. Elle se fie à ces noms exacts ; **ils ne
doivent plus changer** (sinon les versions déjà installées ne trouvent plus la mise à jour) :

| Fichier de la release `vX.Y.Z` | Contenu |
|--------------------------------|---------|
| `bibliotheque_perso-X.Y.Z-installation.exe` | installateur Inno Setup (installer / mettre à jour) |
| `bibliotheque_perso-X.Y.Z-installation.exe.sha256` | une seule ligne au format `sha256sum` : 64 caractères hexadécimaux **minuscules**, **deux espaces**, le nom du fichier `.exe`, puis un saut de ligne LF ; encodage ASCII sans BOM |

Exemple de contenu du `.sha256` :
`574f2a4ac49af7d2700d5a80f40da2b6768b16618f57f1d5c0024321e3421372  bibliotheque_perso-0.3.3-installation.exe`

Les releases de test (`vX.Y.Z-test`, *pre-release*) contiennent les mêmes fichiers nommés
`bibliotheque_perso-X.Y.Z-test-installation.exe` et `.exe.sha256`. Les releases antérieures
à 0.4.0 n'ont pas d'installateur. Vérification à la main sous Windows :
`(Get-FileHash bibliotheque_perso-X.Y.Z-installation.exe -Algorithm SHA256).Hash`
(majuscules : comparer sans tenir compte de la casse) ; sous Linux : `sha256sum -c <fichier>.sha256`.
- **Artefacts** (toutes les exécutions) : https://github.com/Zerma1/BibliothequePerso/actions
  → cliquer l'exécution → bas de la page, « Artifacts ». Il faut être connecté à GitHub ; ils
  sont **effacés au bout de 30 jours**.
- **Release** (étiquettes `v*`) : https://github.com/Zerma1/BibliothequePerso/releases. Les
  fichiers y restent ; c'est le lien à donner pour installer. Le texte de la release est
  générique : on peut le compléter à la main avec la section de `docs/VERSIONS.md`.

Avec la compilation automatique, les étapes 3 et 4 manuelles (build sous Windows, release
créée à la main) ne sont plus nécessaires ; elles restent valables en secours.

### Signature de l'APK

Aucune clé de signature n'est utilisée : l'APK est signé avec la **clé de développement**
(`signingConfig "debug"` dans `android/app/build.gradle.kts`), comme les builds faits à la
main. Attention : cette clé est **propre à chaque machine** (`~/.android/debug.keystore`),
et les machines de GitHub sont neuves à chaque exécution : la clé change donc très
probablement **à chaque compilation**. Conséquence : un APK compilé par GitHub ne peut sans
doute pas s'installer par-dessus une version précédente (ni celle du PC, ni une autre de
GitHub) ; Android refuse la mise à jour et il faut désinstaller l'application, ce qui efface
ses données. Tant que ce point n'est pas réglé, pour mettre à jour un téléphone qui garde ses
données, utiliser l'APK compilé sur le PC (section 3). Solution prévue : une vraie clé de
publication stockée dans un secret GitHub (décision du client).

### Coût

Si le dépôt est **privé**, chaque exécution consomme des **minutes GitHub Actions** du compte
(quota gratuit mensuel limité ; les minutes Windows comptent double). Ordre de grandeur par
exécution complète : plusieurs dizaines de minutes facturées (préparation, tests, trois
compilations, release). C'est pourquoi rien n'est lancé sur `dev`. Pour un dépôt public, les
minutes des machines standard sont gratuites.

## 4. Mettre les fichiers à disposition

### Sur la branche `test` : les fichiers sont dans Git (choix du client)

Pour que le client puisse récupérer une version de test **depuis n'importe où en téléchargeant
simplement le dépôt**, les fichiers à installer de l'étape 3 sont commités sur la branche
`test`, dans `livraisons/<version>/` :

```
livraisons/0.1.0-test.1/
    bibliotheque_perso-0.1.0-test.1-windows.zip
    bibliotheque_perso-0.1.0-test.1-android.apk
    LISEZMOI.md          (comment installer)
```

```powershell
git switch test
git add -f livraisons/0.1.0-test.1     # -f : le dossier est ignoré sur dev
git commit -m "Fichiers à installer de la version 0.1.0-test.1"
git push origin test
git switch dev
```

Règles :
- seulement les fichiers prêts à installer, **jamais** le dossier `build/` complet (plusieurs
  Go de fichiers intermédiaires) ;
- jamais sur `dev` ni sur `main` (le dossier `livraisons/` y reste ignoré) ;
- un fichier ne doit pas dépasser 100 Mo (limite de GitHub) ;
- on peut retirer les livraisons des anciennes versions de test pour garder un dépôt léger
  (elles restent dans l'historique et dans leur étiquette).

Pour récupérer la version de test sans Git : sur GitHub, choisir la branche `test`, puis
« Code » → « Download ZIP », et ouvrir `livraisons/<version>/`. Ce commit de `livraisons/`
ne relance pas la compilation automatique (`paths-ignore`, section 3 bis).

### « Release » GitHub : créée par le workflow

Pour **chaque étiquette** `v*` poussée (`v0.1.0-test.N` sur `test`, `v0.1.0` sur `main`), la
release GitHub est désormais **créée automatiquement** par le workflow de compilation
(section 3 bis), avec les cinq fichiers (zip Windows, installateur et son empreinte
`.sha256`, tar.gz Linux, apk) ; *pre-release* pour une version de test. Les noms de
l'installateur et de son empreinte sont **figés** (section 3 bis, « Noms figés »). Les
fichiers de `livraisons/` sur `test` restent le moyen du client pour télécharger en
déplacement (téléchargement du dépôt), la release étant l'autre accès.

En secours seulement (workflow en échec), la release se crée à la main :

1. Sur https://github.com/Zerma1/BibliothequePerso/releases, « Draft a new release ».
2. Choisir l'étiquette `v0.1.0-test.1`, branche `test`.
3. Titre : `0.1.0-test.1 (version de test)`. Texte : copier la section correspondante de
   `docs/VERSIONS.md`.
4. Joindre les fichiers de l'étape 3.
5. Cocher **« Set as a pre-release »** pour une version de test (pas pour `main`).
6. Publier.

## 5. Valider puis publier sur `main`

Après essai par le client et son accord explicite :

```powershell
git switch main
git merge --ff-only test
git tag -a v0.1.0 -m "Version 0.1.0"
git push origin main --follow-tags
git switch dev
```

La release est créée automatiquement par le workflow à l'étiquette vX.Y.Z (release normale,
pas *pre-release* : section 3 bis).

## En cas de problème sur une version de test

Ne jamais corriger sur `test` : corriger sur `dev`, puis publier une nouvelle version de test
(`0.1.0-test.2`) en suivant à nouveau cette procédure.
