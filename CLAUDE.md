# CLAUDE.md

Application Flutter personnelle (Windows, Linux, Android) qui regroupe les mangas et livres
suivis sur plusieurs sites de lecture. Tout le projet est en **français** : réponses, code
métier, commentaires, noms de tests.

## Documents de référence (font autorité)

- [PLAYBOOK.md](PLAYBOOK.md) : architecture, modèle de données, règles réseau, feuille de
  route. **À lire avant d'écrire du code.** En cas de conflit, le playbook gagne ; le
  modifier demande la validation du client.
- [CONVENTIONS_NOMMAGE.md](CONVENTIONS_NOMMAGE.md) : nommage français sans accents,
  préfixes (`Ecran`, `Etat`, `Service`, `Depot`, `Source`, `Erreur`), verbes
  (`recuperer` = réseau, `charger` = base/disque, `enregistrer` = écriture en base).
- [README.md](README.md) : installation et commandes.

Ne pas recopier ces documents ici : les lire au besoin.

## Rôle de la session principale : orchestrateur

L'utilisateur est le **client** (il valide les livrables et arbitre les choix produit).
La session principale découpe le travail et délègue aux agents de `.claude/agents/`, chacun
limité à son scope :

| Agent | Scope en écriture |
|-------|-------------------|
| `integrateur-plateformes` | `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `android/`, `windows/`, `linux/`, `assets/`, `.github/` (compilation automatique) |
| `developpeur-donnees` | `lib/modeles/`, `lib/donnees/` (+ tests) |
| `developpeur-sources` | `lib/sources/` (+ tests, HTML enregistrés) |
| `developpeur-services` | `lib/services/` (+ tests) |
| `developpeur-interface` | `lib/ecrans/`, `lib/widgets/`, `lib/etat/` (+ tests) |
| `testeur-qualite` | `test/` uniquement |
| `relecteur-code` | lecture seule |
| `analyste-erreurs` | `docs/JOURNAL_ERREURS.md` (diagnostic d'erreurs, lecture du reste) |

- `lib/services/` et `test/services/` : écrits par `developpeur-services` (créé le 2026-11-15
  à la demande du client, pour que l'orchestrateur reste disponible). L'orchestrateur garde
  l'assemblage et les décisions, et délègue le travail lourd.
- Cycle : agent spécialiste → `testeur-qualite` → `relecteur-code` → présentation au client.
- Un nouvel agent ou un nouveau paquet pub.dev : proposer au client avant de l'ajouter.
- Économie de tokens : pour une petite modification évidente, l'orchestrateur peut la faire
  lui-même plutôt que lancer toute la chaîne d'agents ; le dire au client.

## Règles qui reviennent souvent

- Dépendances : `ecrans/widgets → etat → services → donnees, sources → modeles`, jamais
  dans l'autre sens.
- Seul `ClientHttpPoli` importe `package:http` (1 s entre requêtes par domaine).
- Aucun appel réseau réel dans les tests ; SQL toujours paramétré ; migrations jamais
  modifiées après livraison.
- Ne jamais inventer d'API : en cas de doute, commentaire `// LIMITE :`.
- `flutter analyze` doit donner 0 problème avant toute livraison.

## Branches et versions (détail : PLAYBOOK.md section 12)

- **On code uniquement sur `dev`**, et on y teste en local. `test` reçoit les versions de
  test (`X.Y.Z-test`) à essayer par le client ; `main` sert seulement à publier les versions
  validées par le client. Ne jamais commiter sur `test` ni sur `main` : procédure dans
  `docs/DEPLOIEMENT.md`.
- Versions de test : **`X.Y.Z-test`** sur `test` (Z+1 à chaque itération de corrections),
  toujours accompagnées de `testUtilisateur/plan_de_tests_vX.Y.Z-test.md` ; le client est
  prévenu quand une version de test est prête.
- Versions au format `X.Y.Z` : X = rupture, Y = nouvelle fonctionnalité, Z = correction.
  Dans `pubspec.yaml` : `version: X.Y.Z+N`. Étiquette `vX.Y.Z` sur `main` à chaque version.

## Environnement

- Windows 11, PowerShell, IntelliJ (plugins Dart + Flutter). Flutter SDK dans `D:\dev\flutter`,
  Android SDK dans `D:\dev\android-sdk` ; caches pub et Gradle sur `D:\dev\`.
- La version Linux ne se compile que sous Linux ou WSL2.
- Commandes : `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d windows`,
  `flutter build windows`, `flutter build apk --release`.

## État actuel (2026-11-17)

- `main` : version **0.3.3** (validée par le client, 2026-11-27 ; étiquette v0.3.3).
- `test` : **0.3.3-test**, publiée sur `main` en 0.3.3. Prochaine version de test : 0.4.0-test
  (nouvelle fonctionnalité) ou 0.3.4-test (corrections).
- Plateformes : Windows d'abord ; Android puis Linux seulement après validation.
- Suivi des tâches dans `docs/TACHES_EN_COURS.md`.

## Pièges connus

Avant de déboguer une erreur, lire `docs/JOURNAL_ERREURS.md` (erreurs déjà rencontrées,
cause et solution). Toute erreur inattendue ou récurrente est confiée à `analyste-erreurs`.


- Flutter 3.50 : les widgets Material s'importent avec `package:material_ui/material_ui.dart`
  (et non `package:flutter/material.dart`).
- `flutter build windows` exige le **mode développeur** de Windows (liens symboliques des
  plugins).
- Les sous-agents ne voient pas toujours `D:\dev\flutter\bin` dans leur PATH : l'ajouter en
  tête de commande si `flutter` est introuvable.
- Les chaînes Dart contenant une apostrophe s'écrivent entre guillemets doubles
  (`"l'anglais"`) : voir E1 du journal des erreurs.
- Dans les paramètres des outils Edit/Write (décodés comme du JSON), un échappement
  Unicode antislash-u est transformé en caractère avant l'écriture : pour garder un
  échappement dans un fichier, utiliser `\x..` et vérifier les octets (voir E7).
- Le C++ Windows est compilé avec `/utf-8` (`windows/CMakeLists.txt`) : ne pas retirer
  cette option, sinon les accents des textes natifs sont abîmés.
- Toute requête vers un serveur MangaDex (`mangadex.org`, `*.mangadex.org`,
  `*.mangadex.network`) envoie le User-Agent de l'application : avec un User-Agent de
  navigateur, MangaDex renvoie une page anti-robot HTML (code 200) au lieu de l'image (E10).
  Un essai réel d'image vérifie le type des octets, pas seulement leur présence.
- `dart format` seulement sur les fichiers qu'on a modifiés, jamais sur un dossier entier
  (sinon des fichiers d'autres agents sont reformatés : E12).
- Le cache pub utilisé est `D:\dev\pub-cache` (vérifié dans `.dart_tool/package_config.json`
  le 2026-11-19). Le cache Kotlin incrémental plantait entre deux disques : d'où
  `kotlin.incremental=false` dans `android/gradle.properties` (à garder).
- `flutter build windows` exige `nuget.exe` dans le PATH depuis le navigateur intégré
  (installé par winget : `C:\Users\bapti\AppData\Local\Microsoft\WinGet\Links`).
- Navigateur intégré (`flutter_inappwebview`, bêta épinglée) : jamais de vue web sous Linux
  (paquet local vide `paquets/flutter_inappwebview_linux_vide` via `dependency_overrides`) ;
  tester `Platform.isAndroid || Platform.isWindows` avant de créer `InAppWebView`.
