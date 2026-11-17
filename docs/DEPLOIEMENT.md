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
git merge --no-ff -X theirs dev -m "Version de test 0.1.0-test.N"
git diff --quiet dev -- lib test pubspec.yaml docs   # doit être vrai : code identique à dev
git tag -a v0.1.0-test.N -m "Version de test 0.1.0-test.N"
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

Limites actuelles (à lever à l'étape 9 de la feuille de route) :
- l'APK est signé avec la **clé de développement** de Flutter : il s'installe, mais une future
  version signée avec une vraie clé demandera de désinstaller l'ancienne ;
- la version Linux n'est pas construite automatiquement ; l'intégration continue (GitHub
  Actions) construira les trois plateformes en même temps.

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
« Code » → « Download ZIP », et ouvrir `livraisons/<version>/`.

### Pour une version publiée (`main`) : « release » GitHub

Les fichiers ne vont pas dans Git sur `main`. On les dépose dans une **« release » GitHub** :

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

Puis refaire les étapes 3 et 4 depuis `main`, sans cocher « pre-release ».

## En cas de problème sur une version de test

Ne jamais corriger sur `test` : corriger sur `dev`, puis publier une nouvelle version de test
(`0.1.0-test.2`) en suivant à nouveau cette procédure.
