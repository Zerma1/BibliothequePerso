# Conception : le NAS, nœud actif (tâche D2)

> Document **à valider par le client** avant tout code. Rédigé le 2026-11-25.
> Rien ici ne modifie le PLAYBOOK : les changements de règles proposés (§1.4) demandent
> l'accord du client.

Besoin : un programme tourne sur le NAS ; il partage titres, sites, listes et catégories
entre les appareils ; il télécharge lui-même ce qu'il peut ; il reçoit les chapitres
enregistrés sur un appareil ; il est la source prioritaire des chapitres ; plus tard, il
synchronise les lectures. Le client n'a pas encore de NAS : tout doit pouvoir tourner sur le PC.

---

## 1. Architecture

### 1.1 Un programme serveur en Dart, sans interface

- Point d'entrée `bin/serveur_nas.dart`, dans **le même dépôt et le même `pubspec.yaml`**,
  compilé avec `dart compile exe` (pas de Flutter à l'exécution). Le serveur réutilise
  `lib/modeles`, `lib/donnees`, `lib/sources` et les services sans interface
  (`ServiceMisesAJour`, `ServiceTelechargement`, `PolitiqueTelechargement`…).
  *Pourquoi* : une seule copie des adaptateurs de sites et des règles ; une correction
  d'adaptateur profite aux appareils et au NAS.
- Nouveau dossier `lib/serveur/` (API HTTP, appairage, synchronisation, audit). Sens des
  dépendances : `serveur → services → donnees, sources → modeles` ; l'application
  n'importe jamais `lib/serveur/`.
- Serveur HTTP : `HttpServer` de `dart:io` (TLS par `SecurityContext`). **Aucun nouveau
  paquet** ; `crypto` (empreintes SHA-256) et `meta` sont déjà présents en dépendances
  transitives et passeraient en dépendances directes (accord du client, §7).

### 1.2 Préparatifs obligatoires (code actuel)

`dart compile exe` refuse tout fichier qui importe Flutter, même indirectement. Aujourd'hui :

| Fichier | Import gênant | Correction proposée |
|---------|---------------|---------------------|
| `lib/donnees/base_de_donnees.dart` | `sqflite`, `path_provider` | Dépôts typés avec `package:sqflite_common` (`DatabaseExecutor` y est défini) ; ouverture `sqflite` (Android) / `sqflite_common_ffi` (PC, NAS) injectée par `main.dart` ou `bin/` |
| les 13 dépôts | `package:sqflite/sqflite.dart` | même chose : `package:sqflite_common/sqlite_api.dart` |
| `lib/donnees/stockage_telechargements.dart` | `path_provider` | dossier par défaut fourni par l'appelant |
| `service_telechargement.dart`, `service_bibliotheque.dart` | `flutter/foundation.dart` | `package:meta` (`visibleForTesting`) ; `compute` éventuel remplacé par `Isolate.run` |

Ces changements ne modifient aucun comportement : ils sont testés par la suite actuelle.
`// LIMITE :` l'équivalence exacte des API `sqflite` / `sqflite_common` sera vérifiée par
`developpeur-donnees` sur la documentation pub.dev avant de toucher aux dépôts.

### 1.3 Déploiement : image Docker

- Synology (Container Manager), QNAP (Container Station), TrueNAS SCALE et Unraid lancent
  tous des conteneurs Docker : c'est le seul format commun. Image **multi-architecture**
  (`linux/amd64` et `linux/arm64`, beaucoup de NAS d'entrée de gamme sont en ARM).
- Construction en deux étapes : image Flutter/Dart pour `pub get` + `dart compile exe`,
  puis image finale minimale (`debian:stable-slim` + `libsqlite3` + `openssl`), sans
  compilateur, sans shell de connexion, **sans serveur SSH**.
- Construite par GitHub Actions à chaque version (comme les builds actuels), publiée sur
  le registre GitHub du dépôt (privé). Fichier `docker-compose.yml` fourni, prêt à coller
  dans l'interface du NAS : aucune ligne de commande nécessaire sur le NAS.

### 1.4 Règles réseau et usage responsable (§6 et §10 du PLAYBOOK)

- Le NAS utilise **le même `ClientHttpPoli`** : User-Agent honnête, 1 s entre deux
  requêtes par domaine, 20 s de délai, 2 nouvelles tentatives. Jamais de connexion à un
  compte, de contournement de protection anti-robot ni de déchiffrement (MANGA Plus).
- Le NAS et les appareils partagent la même adresse IP publique : pour ne pas doubler la
  charge sur un site, **quand le NAS est joignable, c'est lui seul qui interroge les sites**
  (mises à jour et téléchargements) ; les appareils ne le font qu'en secours (NAS éteint).
- Exception à demander au client : `ClientNas` (appareil → NAS) devient la **deuxième**
  classe autorisée à importer `package:http` (dans `lib/sources/`), sans délai de 1 s
  (le NAS est à nous) mais avec épinglage du certificat (§2.3).

---

## 2. Protocole appareil ↔ NAS et sécurité

Contexte : un accès SSH du client a été piraté récemment. Principe : **défense en
profondeur**, chaque couche suffit seule à bloquer une partie des attaques.

### 2.1 API HTTPS JSON (version `v1`)

| Méthode et chemin | Rôle |
|-------------------|------|
| `POST /api/v1/appairage` | code à usage unique → jeton de l'appareil |
| `GET /api/v1/etat` | version du serveur, version du protocole, révision courante, espace libre |
| `GET /api/v1/synchro?depuis=N` | changements depuis la révision `N` (par paquets de 500) |
| `POST /api/v1/synchro` | changements de l'appareil |
| `GET /api/v1/titres/{uuid}/chapitres` | chapitres d'un titre et leur présence sur le NAS |
| `GET /api/v1/chapitres/{id}/archive` | télécharger l'archive `.zip` (en-tête SHA-256, reprise `Range`) |
| `PUT /api/v1/chapitres/{id}/archive` | envoyer une archive enregistrée sur l'appareil |
| `POST /api/v1/telechargements` | demander au NAS de télécharger en priorité |
| `GET /api/v1/titres/{uuid}/couverture` | couverture enregistrée |
| `GET` / `DELETE /api/v1/appareils[/{id}]` | lister / révoquer les appareils |

- Jeton dans l'en-tête `Authorization: Bearer …`, **jamais dans l'adresse**.
- Le serveur et l'application comparent la version du protocole : en cas d'écart, la
  synchronisation s'arrête avec un message clair (« mettez à jour le NAS ») au lieu
  d'écrire des données mal comprises.

### 2.2 Appairage et jetons

1. Le client ouvre une fenêtre d'appairage depuis l'interface Docker du NAS (bouton
   « Redémarrer » avec la variable `APPAIRAGE=1`, ou depuis un appareil déjà appairé).
   Le NAS affiche dans son journal (visible dans l'interface du NAS) un **code de 8
   caractères** + l'**empreinte de son certificat**. Valable 10 minutes, usage unique.
2. L'appareil saisit l'adresse du NAS et le code ; il vérifie que l'empreinte reçue est
   celle affichée (le code est lié à l'empreinte : un intermédiaire ne peut pas s'insérer).
3. Le NAS renvoie un **jeton de 256 bits** (`Random.secure`), propre à l'appareil. Le NAS
   n'en garde que l'empreinte SHA-256 (une copie volée de sa base ne permet pas de se
   connecter).
4. Chaque appareil est **révocable** (Paramètres → NAS → Appareils). Un appareil perdu se
   révoque depuis un autre.

5 essais de code faux → fenêtre d'appairage fermée. Aucun mot de passe n'existe, donc
aucun mot de passe à deviner ni à réutiliser ailleurs.

### 2.3 Chiffrement TLS

- **Par défaut** : certificat autosigné (ECDSA P-256) généré par `openssl` au premier
  démarrage, dans le volume de données. L'appareil **épingle son empreinte** à
  l'appairage (`HttpClient.badCertificateCallback` n'accepte que cette empreinte) ;
  un changement de certificat impose un nouvel appairage.
- **Option** : le NAS a déjà un reverse proxy avec un vrai certificat (Synology, Let's
  Encrypt) → validation normale du certificat, épinglage désactivé.
- Jamais de HTTP en clair, même en réseau local.

### 2.4 Exposition réseau

- Un seul port (proposé : `8743`). **Jamais exposé à Internet par défaut** : aucune
  redirection de port sur la box, pas d'UPnP.
- Le serveur refuse lui-même les adresses non privées (accepte `127.0.0.0/8`, `10/8`,
  `172.16/12`, `192.168/16`, liens locaux IPv6, et `100.64/10` si le client active un VPN
  type Tailscale). Deuxième barrière si un port est ouvert par erreur.
- Accès hors de chez soi : **uniquement par VPN** (WireGuard de la box ou du NAS,
  Tailscale) : question 2.

### 2.5 Autres protections

- **Limitation de débit** : appairage 5 essais / 10 min par adresse ; API 20 requêtes/s
  par jeton ; envoi d'archive 1 à la fois par appareil, 500 Mo au plus.
- **Contrôle des archives reçues** : uniquement `imgN.<ext>` et `contenu.html`, aucun
  chemin (`../`), taille décompressée bornée (bombe zip), type d'image vérifié par ses
  octets (`detection_image.dart`), SHA-256 comparé à celui annoncé. Écriture
  `.zip.part` → `.zip` par `StockageTelechargements`, comme aujourd'hui.
- **SQL toujours paramétré**, JSON validé champ par champ (types, longueurs), erreurs
  sans détail interne.
- **Journal d'audit** séparé (`audit-AAAA-MM-JJ.log`, 90 jours) : appairages, refus
  d'authentification, révocations, envois et suppressions d'archives, suppressions de
  titres. Jamais de jeton ni de code. Plusieurs refus successifs → alerte affichée sur
  les appareils.
- **Moindre privilège du conteneur** : utilisateur non root (`PUID`/`PGID`), système de
  fichiers en lecture seule (`read_only: true`), `cap_drop: ALL`,
  `no-new-privileges`, limites mémoire et CPU, deux volumes seulement (`/donnees` : base,
  certificat, journaux ; `/chapitres` : archives), jamais le socket Docker.
- **Mises à jour** : image reconstruite à chaque version et au moins chaque mois (image de
  base corrigée) ; l'application signale un NAS en retard de version.
- Côté appareil : le jeton est stocké en base locale (simple) ou dans le coffre du système
  (paquet `flutter_secure_storage`, nouveau) : question 9.

---

## 3. Synchronisation

### 3.1 Identifiants globaux

Les `id` SQLite diffèrent d'un appareil à l'autre : il faut une clé commune.

| Table | Clé commune | Changement |
|-------|-------------|------------|
| `sources` | `url_base` (déjà UNIQUE) + `uuid` | colonne `uuid` |
| `titres` | `uuid` (un titre peut avoir plusieurs sites) | colonne `uuid` |
| `titres_sources` | (`uuid` du titre, `url_titre`) | aucune |
| `listes` | `uuid` ; listes système : identifiant fixe (`systeme:favoris`…) | colonne `uuid` |
| `categories` | `nom` normalisé (déjà UNIQUE) | aucune |
| `chapitres` (0.5) | `url_chapitre` (déjà UNIQUE) | aucune |

UUID v4 tirés avec `Random.secure` (pas de nouveau paquet). Toutes les tables synchronisées
reçoivent `date_modification` (millisecondes UTC), écrite **par les dépôts** (pas par un
déclencheur, sinon appliquer un changement reçu écraserait sa date d'origine).

### 3.2 Suppressions

Les suppressions restent physiques (cascades actuelles intactes) ; une table
`suppressions(table_cible, uuid, date)` garde une trace 90 jours pour la transmettre aux
autres appareils. *Pourquoi* plutôt qu'une colonne « supprimé » partout : aucune requête
existante à modifier. Une archive d'un titre supprimé est gardée 30 jours sur le NAS
(corbeille) avant effacement : question 8.

### 3.3 Échanges incrémentaux

- Le NAS numérote chaque changement reçu (**révision** croissante). Un appareil garde la
  dernière révision reçue et ne demande que la suite ; il envoie ses changements locaux
  depuis son dernier envoi.
- Déclenchement : au démarrage, toutes les 5 minutes, et juste après une modification
  (titre ajouté, liste changée…). Hors ligne, les changements attendent.
- **Conflits** : la dernière modification gagne, par entité. Dates d'appareil plus de
  5 minutes dans le futur ramenées à l'heure du NAS (horloges décalées). Exceptions :
  - appartenance à une liste ou une catégorie : par couple (titre, liste), donc ajouter
    un titre aux Favoris sur le PC et à « Planifié » sur le téléphone garde les deux ;
  - lectures (0.7) : « lu » gagne sur « non lu », sauf « marquer non lu » plus récent ;
  - la description personnelle perdante est conservée dans le journal (rien de perdu).

### 3.4 Ce qui est synchronisé

| Maintenant (0.4) | Plus tard | Jamais (propre à l'appareil) |
|------------------|-----------|------------------------------|
| sources (et `lien_seul`), titres, sites d'un titre, titres alternatifs, listes et leur contenu, catégories et équivalences, description perso, langues d'un titre, couverture choisie | 0.5 : catalogue des chapitres ; 0.7 : lu / non lu, position dans le chapitre | file de téléchargement, archives locales, suppressions prévues, dossier des chapitres, démarrage Windows, journal |

Réglages généraux (langues, archive complète…) : question 12.

---

## 4. Chapitres

- **Format identique** : même arborescence `<type>/<titre>/ch<numero>.<langue>.zip`, mêmes
  noms de doublons, écrite par `StockageTelechargements` du NAS. Le dossier reste lisible
  à la main (partage réseau du NAS).
- **Ordre d'obtention sur un appareil** : archive locale → **archive du NAS** → site
  (seulement si le NAS est injoignable ou ne peut pas l'obtenir). Une archive venue du NAS
  est copiée en local et suit les règles de conservation de l'appareil ; le NAS la garde.
- **Le NAS télécharge** tous les chapitres de tous les titres (archive complète,
  décision du client, tâche X7), dans les langues choisies (question 6), et ne
  supprime jamais automatiquement.
- **Le NAS ne télécharge jamais** : chapitres externes (`url_externe`, MANGA Plus, VIZ…),
  sites en lien seul, sites protégés (page anti-robot, contenu chiffré). Pour eux, seule
  la voie « appareil » existe.
- **Envoi depuis un appareil** : un chapitre enregistré dans le navigateur intégré
  (`origine = 'web'`) ou téléchargé par l'appareil en secours est envoyé au NAS dès qu'il
  est joignable (file d'envoi persistante, reprise après coupure). Le NAS garde
  l'origine `web`.
- Le mode actuel « dossier des chapitres sur un partage du NAS »
  (`ServiceDossierChapitres`) reste pour qui n'a pas de serveur, mais **ne doit pas viser
  le même dossier que le NAS actif** (deux écrivains sur les mêmes fichiers) : refus
  affiché dans les paramètres.

---

## 5. Mode « NAS simulé » sur le PC

- Le **même programme** : `dart run bin/serveur_nas.dart --dossier D:\dev\nas-simule
  --port 8743`. Il écoute seulement sur `127.0.0.1` (et l'adresse locale du PC si on veut
  tester depuis le téléphone ou l'émulateur Android, qui voit le PC en `10.0.2.2`).
- Même TLS, même appairage, même base : ce qui marche simulé marche sur le NAS ; seul
  l'emballage Docker change (testable aussi avec Docker Desktop si installé : question 5).
- Deux « appareils » sur un seul PC : lancement de l'application avec un profil de données
  distinct (`--dart-define=PROFIL=appareil2`, dossier de base séparé) ; impact limité à
  `main.dart`.
- Options de test : `--latence 2s`, `--hors-ligne-apres 60s` (simuler un NAS qui s'éteint),
  `--sans-reseau` (sources factices, aucun site réel interrogé).
- Tests automatisés : serveur lancé dans le processus de test sur un port libre, avec des
  sources factices : **aucun appel réseau réel**, comme pour les adaptateurs.

---

## 6. Étapes proposées

| Version | Contenu | Le client valide |
|---------|---------|------------------|
| 0.4.0 | Préparatifs §1.2 (aucun changement visible) ; **migration 14** : `uuid` + `date_modification` sur `sources`, `titres`, `titres_sources`, `listes`, `titres_listes`, `titres_categories`, table `suppressions` ; remplissage des UUID des lignes existantes | rien à l'écran : non-régression de la 0.3.x |
| 0.4.1 → 0.4.x | Serveur (NAS simulé) : appairage, TLS épinglé, audit, synchro titres / sites / listes / catégories ; écran Paramètres → NAS (adresse, code, appareils, état) | appairer le PC, synchro entre deux profils, révocation |
| 0.5.0 | Chapitres : catalogue tenu par le NAS, téléchargements par le NAS, lecture depuis le NAS en priorité, envoi des chapitres `web` ; **migration 15** (`chapitres.date_modification`, file d'envoi) | lecture NAS d'abord, envoi depuis le navigateur intégré, NAS coupé = secours |
| 0.6.0 | Image Docker multi-architecture, `docker-compose.yml`, guide d'installation pas à pas pour le modèle du client | installation sur le vrai NAS (quand il l'aura) |
| 0.7.0 | Lectures synchronisées (lu / non lu, position) | lire sur le PC, reprendre sur le téléphone |

Chaque version suit le cycle habituel (`X.Y.Z-test` + plan de tests). Windows d'abord ;
le serveur tourne sous Linux (Docker) mais le NAS simulé tourne sous Windows.

**Impacts sur l'application actuelle** : migrations 14 et 15 (jamais de modification des
13 premières) ; dépôts qui écrivent `date_modification` et la trace des suppressions ;
`ServiceTelechargement` qui consulte le NAS avant le site ; mises à jour confiées au NAS
quand il répond ; nouvel écran de paramètres ; mise à jour du PLAYBOOK (couche
`serveur`, exception `ClientNas`, section NAS) ; un nouvel agent `developpeur-serveur`
(scope `bin/`, `lib/serveur/`, `test/serveur/`, `docker/`) à créer avec l'accord du client.

---

## 7. Questions ouvertes au client

1. **Modèle de NAS** envisagé (Synology, QNAP, TrueNAS, Unraid, Raspberry Pi…) ?
   Processeur ARM ou Intel/AMD ? Peut-il lancer des conteneurs Docker ?
2. **Accès hors de chez vous** : nécessaire ? Si oui, par quel VPN (box, WireGuard du NAS,
   Tailscale) ? Sinon : réseau local seulement.
3. **Plusieurs utilisateurs** (famille) avec des bibliothèques séparées, ou une seule
   bibliothèque partagée par tous vos appareils ?
4. **TLS** : certificat autosigné épinglé (proposé, rien à configurer) ou reverse proxy
   du NAS avec un vrai certificat ?
5. **Docker Desktop** sur le PC pour tester l'image, ou NAS simulé en `dart run` seulement ?
6. **Langues sur le NAS** : archive complète dans vos langues choisies, ou toutes les
   langues disponibles (beaucoup plus de place et de requêtes) ?
7. Quand le NAS répond, **lui seul interroge les sites** (moins de charge, §1.4) : d'accord ?
8. **Suppression d'un titre** sur un appareil : supprimée partout, archives du NAS gardées
   30 jours en corbeille ?
9. **Jeton de l'appareil** : en base locale (simple) ou dans le coffre du système
   (nouveau paquet `flutter_secure_storage`) ?
10. Accord pour : le nouvel agent `developpeur-serveur`, les dépendances directes `crypto`,
    `meta`, `sqflite_common` (déjà présentes indirectement), et la modification du
    PLAYBOOK (§1.1, §1.4) ?
11. **Administration du NAS** uniquement depuis l'application (pas d'interface web sur le
    NAS, moins de surface d'attaque) : d'accord ?
12. **Réglages partagés** : langues générales, archive complète, règles de conservation…
    lesquels doivent être identiques sur tous les appareils ?
13. **Espace disque** : alerte à partir de quel seuil libre restant sur le NAS ?
