# Journal des erreurs

Erreurs et échecs de commandes rencontrés pendant le développement, avec leur cause racine et
la façon de les éviter. Tenu par l'agent `analyste-erreurs` ; à lire avant de déboguer une
erreur qui semble déjà vue.

### E1 — Apostrophes perdues dans les scripts Python d'édition
- **Date(s)** : 2026-11-15 (4 occurrences)
- **Symptôme** : `dart format` / `flutter analyze` : « Expected to find ',' » sur
  `test('… l'application', …)` ; ou `AssertionError` d'un script Python qui ne trouve pas un
  texte contenant `n\'a`.
- **Cause racine** : double échappement. Dans une commande `python - <<'EOF'`, `\\'` devient
  `\'` au décodage JSON du paramètre de l'outil, puis `'` dans la chaîne Python. La chaîne Dart
  `'l\'anglais'` est écrite `'l'anglais'`.
- **Solution appliquée** : remplacement par des chaînes Dart entre guillemets doubles.
- **Prévention** : écrire les textes français avec apostrophe entre guillemets doubles en Dart
  (`"l'anglais"`) ; préférer les outils d'édition directe aux scripts ; si un script est
  nécessaire, l'écrire dans un fichier et utiliser des chaînes brutes Python `r"""…"""`.
- **Statut** : résolu.

### E2 — `flutter` introuvable dans les terminaux des agents
- **Date(s)** : 2026-11-15
- **Symptôme** : `flutter : Le terme «flutter» n'est pas reconnu…` dans PowerShell.
- **Cause racine** : les sessions PowerShell des agents ne rechargent pas toujours le PATH
  utilisateur qui contient `D:\dev\flutter\bin`.
- **Solution appliquée** : préfixer la commande par
  `$env:Path = "D:\dev\flutter\bin;" + $env:Path;`.
- **Prévention** : consigne présente dans `CLAUDE.md` (« Pièges connus ») et dans chaque
  demande aux agents.
- **Statut** : contourné.

### E3 — Build Android : cache Kotlin incrémental entre deux disques
- **Date(s)** : 2026-11-15
- **Symptôme** : `:workmanager_android:compileDebugKotlin` échoue avec « this and base files
  have different roots: C:\…\Pub\Cache\… and D:\Projet\Bibliotheque perso\android ».
- **Cause racine** : le cache pub est sur C: (`C:\Users\bapti\AppData\Local\Pub\Cache`, et non
  `D:\dev\pub-cache` comme l'indique le README) alors que le projet est sur D: ; le compilateur
  Kotlin incrémental ne gère pas des chemins relatifs entre deux disques.
- **Solution appliquée** : `kotlin.incremental=false` dans `android/gradle.properties`.
- **Prévention** : ne pas retirer ce réglage ; alternative propre : déplacer le cache pub sur D:
  (variable `PUB_CACHE`), réglage global à décider par le client.
- **Statut** : contourné.

### E4 — `flutter build windows` : liens symboliques refusés
- **Date(s)** : 2026-11-15
- **Symptôme** : « Building with plugins requires symlink support. Please enable Developer
  Mode ».
- **Cause racine** : les plugins Flutter sont liés par liens symboliques, que Windows n'autorise
  qu'en mode développeur.
- **Solution appliquée** : mode développeur activé par le client.
- **Prévention** : noté dans `CLAUDE.md` (« Pièges connus »).
- **Statut** : résolu.

### E5 — Analyse ou tests lancés pendant qu'un agent écrit
- **Date(s)** : 2026-11-15
- **Symptôme** : « 1 issue found » ou test qui ne compile pas, puis tout redevient vert sans
  modification.
- **Cause racine** : vérification faite pendant qu'un autre agent était en train d'écrire ses
  fichiers (état intermédiaire).
- **Solution appliquée** : relancer la vérification une fois l'agent terminé.
- **Prévention** : vérifier l'ensemble seulement quand aucun agent n'écrit ; ne jamais faire
  `git commit -a` pendant qu'un agent travaille (ajouter les fichiers un par un).
- **Statut** : résolu.

### E6 — Agent interrompu par la limite d'utilisation
- **Date(s)** : 2026-11-15
- **Symptôme** : « Agent terminated early due to an API error: You've hit your 5-hour limit ».
- **Cause racine** : quota d'utilisation du compte atteint pendant une longue tâche d'agent.
- **Solution appliquée** : nouvel agent relancé avec la consigne complète (l'ancien ne pouvait
  pas être repris ; il n'avait écrit aucun fichier).
- **Prévention** : demander aux agents d'écrire leurs fichiers au fur et à mesure ; découper les
  grosses tâches ; garder la consigne complète pour pouvoir relancer.
- **Statut** : contourné.

### E7 — Titre de la fenêtre Windows mal encodé (« BibliothÃ¨que »)
- **Date(s)** : 2026-11-16 (2 occurrences : la première « correction » n'a rien changé)
- **Symptôme** : la barre de titre affiche « BibliothÃ¨que perso », même après avoir
  « remplacé » le « è » de `windows/runner/main.cpp` par un échappement Unicode et recompilé.
- **Cause racine** (prouvée) : deux causes combinées.
  1. MSVC compile `windows/runner/main.cpp` sans `/utf-8` (`windows/CMakeLists.txt`,
     `APPLY_STANDARD_SETTINGS` : `/W4 /WX /wd4100 /EHsc` seulement) : il lit le fichier UTF-8
     en Windows-1252, et les octets `C3 A8` de « è » deviennent « Ã¨ ». Preuve : l'exécutable
     Debug contient le texte UTF-16 « BibliothÃ¨que » ; un `t.cpp` minimal compilé avec
     `cl` 14.44 donne « Ã¨ » sans `/utf-8` et « è » avec.
  2. L'échappement n'a jamais été écrit : dans les paramètres des outils (Edit/Write, décodés
     comme du JSON), la séquence antislash-u-00e8 est convertie en « è » avant l'écriture.
     Le fichier contient toujours les octets `C3 A8` (vérifié en hexadécimal, ainsi que dans
     `HEAD`). Les outils conservent en revanche `\x`. Même famille que E1.
  - Fausse piste écartée : `MaterialApp(title: …)` → `SystemChrome.setApplicationSwitcherDescription`
    n'est pas traité par le moteur Windows (`flutter_windows.dll` ne contient ni ce nom ni
    `SetWindowTextW`) ; le titre vient seulement de `window.Create(…)` du runner.
- **Solution appliquée** : à faire par `integrateur-plateformes` : ajouter `/utf-8` dans
  `windows/CMakeLists.txt` (`target_compile_options(${TARGET} PRIVATE /W4 /WX /wd4100 /utf-8)`),
  puis `flutter clean` et recompiler. En complément possible : écrire le littéral
  `L"Biblioth\x00E8que perso"` (le `\x` survit aux outils).
- **Prévention** : compiler le C++ Windows avec `/utf-8` ; ne pas écrire d'échappement
  antislash-u dans un paramètre d'outil (utiliser `\x`) ; après toute édition d'un caractère
  spécial, vérifier les octets du fichier (`[IO.File]::ReadAllBytes`) et non l'affichage ;
  vérifier la correction dans l'exécutable ou par capture, pas seulement la compilation.
- **Statut** : résolu le 2026-11-16 (option `/utf-8` ajoutée dans `windows/CMakeLists.txt`, vérifié dans l'exécutable : « Bibliothèque perso »).

### E8 — L'application lancée depuis la session Claude ne voit pas les données du client
- **Date(s)** : 2026-11-16
- **Symptôme** : bibliothèque vide alors que le client avait ajouté des titres.
- **Cause racine** : les processus lancés depuis l'application Claude (paquet Windows) voient un
  dossier `AppData\Roaming` virtualisé (`AppData\Local\Packages\Claude_…\LocalCache\Roaming`) :
  la base `io.github.zerma1\bibliotheque_perso\bibliotheque_perso.db` y est une copie à part. Le
  dossier `Documents` (archives) n'est pas virtualisé.
- **Solution appliquée** : aucune nécessaire (pas de perte de données).
- **Prévention** : pour tester avec les données réelles du client, le client lance lui-même
  l'application ; les essais de l'orchestrateur se font sur une base de test séparée.
- **Statut** : connu, sans conséquence.
