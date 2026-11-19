# Bibliothèque perso

Application personnelle pour **Windows, Linux et Android** qui regroupe, dans une seule
interface, les mangas et livres suivis sur plusieurs sites de lecture.

## Fonctionnalités prévues

- **Plusieurs sites** : on ajoute un site à partir de son URL (`http://` ou `https://`). Les
  thèmes courants (Madara, MangaThemesia) sont détectés automatiquement ; pour les autres
  sites, on configure des sélecteurs CSS.
- **Bibliothèque** : ajout de titres avec couverture, résumé, auteur, statut et catégories.
- **Listes** : « Favoris » et « Suivis » existent par défaut, et on peut créer ses propres listes.
- **Catégories** : tri et filtre par genre, en reprenant les genres des sites.
- **Mises à jour** : recherche périodique des nouveaux chapitres de chaque titre.
- **Hors-ligne** : téléchargement des chapitres pour les lire dans l'application.

## État du projet

🚧 **Cadrage terminé, développement pas encore commencé.** Voir la feuille de route dans
[PLAYBOOK.md](PLAYBOOK.md#11-feuille-de-route).

## Prérequis (Windows 11)

Installation actuelle sur le poste de développement (vérifiée avec `flutter doctor` le
2026-11-15, aucun problème) :

| Outil | Emplacement | Rôle |
|-------|-------------|------|
| Flutter 3.50.0 (Dart 3.14) | `D:\dev\flutter` | SDK de l'application |
| Android SDK 35 et 36, build-tools 28.0.3, 35 et 36 | `D:\dev\android-sdk` | Compilation de l'APK (sans Android Studio) |
| Microsoft OpenJDK 17 | `C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot` | Gradle (Android) |
| Visual Studio Build Tools 2022 (C++) | `C:\Program Files (x86)\…` | Compilateur de la version Windows `.exe` (aucune interface à utiliser) |
| NuGet 8 (`winget install Microsoft.NuGet`) | `C:\Users\<utilisateur>\AppData\Local\Microsoft\WinGet\Links\nuget.exe` (dans le `PATH`) | Exigé par `flutter build windows` : télécharge les dépendances WebView2 du navigateur intégré (`flutter_inappwebview`) |
| Cache des paquets Dart | `D:\dev\pub-cache` (variable `PUB_CACHE`, chemin confirmé par `.dart_tool/package_config.json`) | Évite de remplir C: |
| Cache Gradle | `D:\dev\gradle` (variable `GRADLE_USER_HOME`) | Évite de remplir C: |

Variables d'environnement utilisateur : `JAVA_HOME`, `ANDROID_HOME`, `PUB_CACHE`,
`GRADLE_USER_HOME`. Le `PATH` contient `D:\dev\flutter\bin`,
`D:\dev\android-sdk\platform-tools` et `D:\dev\android-sdk\cmdline-tools\latest\bin`.

Pour IntelliJ : installer les plugins **Dart** et **Flutter** (`File > Settings > Plugins`),
puis indiquer `D:\dev\flutter` comme « Flutter SDK path ».

Pour vérifier l'installation :
```powershell
flutter doctor
```

La version Linux se compile **sur une machine Linux** (ou sous WSL2), avec les paquets
`clang cmake ninja-build pkg-config libgtk-3-dev`. WPE WebKit n'est pas nécessaire : la
partie Linux de `flutter_inappwebview` est remplacée par un paquet vide
(`paquets/flutter_inappwebview_linux_vide/`), il n'y a pas de navigateur intégré sous Linux.

`flutter build windows` exige aussi le **mode développeur** de Windows (liens symboliques
des plugins) et `nuget.exe` dans le `PATH` (après l'installation par winget, rouvrir le
terminal et IntelliJ).

## Commandes utiles

```powershell
flutter pub get                 # installer les dépendances
flutter run -d windows          # lancer sur Windows
flutter run -d <id_android>     # lancer sur un téléphone (voir : flutter devices)
flutter analyze                 # analyse statique (doit renvoyer 0 problème)
flutter test                    # tests
flutter build windows           # build/windows/x64/runner/Release/
flutter build apk --release     # build/app/outputs/flutter-apk/app-release.apk
flutter build linux             # sous Linux uniquement
```

## Organisation du projet

| Élément | Rôle |
|---------|------|
| [PLAYBOOK.md](PLAYBOOK.md) | Architecture, règles de code, feuille de route : **à lire en premier** |
| [CONVENTIONS_NOMMAGE.md](CONVENTIONS_NOMMAGE.md) | Nommage en français et conventions Dart |
| `.claude/agents/` | Agents IA spécialisés (but et scope de chacun) |
| `lib/` | Code source (structure décrite dans le playbook) |
| `test/` | Tests unitaires et tests des adaptateurs de sites |

## Méthode de travail

Le projet est piloté par un **orchestrateur IA** (Claude Code), avec l'utilisateur dans le rôle
de **client**. L'orchestrateur répartit le travail entre des agents spécialisés :

| Agent | But | Scope |
|-------|-----|-------|
| `developpeur-sources` | Adaptateurs de sites, analyse HTML, détection des thèmes | `lib/sources/`, `test/sources/` |
| `developpeur-donnees` | Modèles, SQLite, dépôts, stockage hors-ligne | `lib/modeles/`, `lib/donnees/`, `test/modeles/`, `test/donnees/` |
| `developpeur-interface` | Écrans, widgets, état de l'interface | `lib/ecrans/`, `lib/widgets/`, `lib/etat/`, `test/ecrans/`, `test/widgets/`, `test/etat/` |
| `integrateur-plateformes` | Configuration Windows, Linux et Android, dépendances, compilation | `android/`, `windows/`, `linux/`, `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart` |
| `testeur-qualite` | Tests, `flutter analyze`, `flutter test` | Écrit uniquement dans `test/` |
| `relecteur-code` | Conformité au playbook et aux conventions | Lecture seule |

## Usage

Ce projet est destiné à un usage personnel. L'application respecte la charge des sites
(délai entre les requêtes) et ne contourne aucune protection d'accès.

## Licence

Copyright (c) 2026 Zerma1. Tous droits réservés : voir [LICENSE](LICENSE).
