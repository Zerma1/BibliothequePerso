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
| `integrateur-plateformes` | `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `android/`, `windows/`, `linux/`, `assets/` |
| `developpeur-donnees` | `lib/modeles/`, `lib/donnees/` (+ tests) |
| `developpeur-sources` | `lib/sources/` (+ tests, HTML enregistrés) |
| `developpeur-interface` | `lib/ecrans/`, `lib/widgets/`, `lib/etat/` (+ tests) |
| `testeur-qualite` | `test/` uniquement |
| `relecteur-code` | lecture seule |

- `lib/services/` et `test/services/` : écrits directement par l'orchestrateur.
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

## Environnement

- Windows 11, PowerShell, IntelliJ (plugins Dart + Flutter). Flutter SDK dans `D:\dev\flutter`,
  Android SDK dans `D:\dev\android-sdk` ; caches pub et Gradle sur `D:\dev\`.
- La version Linux ne se compile que sous Linux ou WSL2.
- Commandes : `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d windows`,
  `flutter build windows`, `flutter build apk --release`.

## État actuel (2026-11-15)

Cadrage terminé, **aucun code encore** : prochaine étape = étape 0 de la feuille de route
(`flutter create` par `integrateur-plateformes`). Le dossier n'est pas encore un dépôt Git.
