/// Constantes propres à la couche `donnees` (PLAYBOOK.md section 9 : pas de
/// valeur magique dans le code).
library;

/// Extension d'une archive de chapitre complète.
const String extensionArchiveChapitre = '.zip';

/// Suffixe ajouté à une archive en cours d'écriture (`ch1.en.zip.part`).
///
/// Une archive n'est renommée en `.zip` qu'une fois complète : un fichier qui
/// porte ce suffixe n'est donc jamais pris pour un chapitre téléchargé.
const String suffixeArchivePartielle = '.part';

/// Suffixe de la copie temporaire d'un fichier pendant un déplacement des
/// archives vers un autre dossier (`ch1.en.zip.deplacement`,
/// `couverture.png.deplacement`).
///
/// Distinct de [suffixeArchivePartielle] : dans un dossier partagé (NAS), un
/// déplacement ne doit jamais écraser ni supprimer le `.part` d'un
/// téléchargement en cours d'une autre bibliothèque. Comme il ne finit pas
/// par `.zip`, un tel fichier n'est jamais pris pour une archive.
const String suffixeCopieDeplacement = '.deplacement';

/// Préfixe du nom de fichier d'un chapitre (`ch<numero>.<langue>.zip`).
const String prefixeFichierChapitre = 'ch';

/// Séparateur des dossiers dans un `nomArchive` enregistré en base
/// (`manga/One Punch Man/ch1.en.zip`).
///
/// Toujours `/`, quelle que soit la plateforme : la valeur en base reste
/// identique sur Windows, Linux et Android (une bibliothèque copiée d'un
/// système à l'autre reste lisible). Elle est convertie en chemin du système
/// au moment de l'accès au fichier.
const String separateurNomArchive = '/';

/// Séparateur placé devant le numéro d'une archive homonyme quand le
/// chapitre n'a pas de langue (`ch1_2.zip`).
///
/// Avec une langue, le numéro suit la langue après un point
/// (`ch1.fr.2.zip`). Sans langue, un point serait ambigu : `ch1.2.zip` est
/// aussi le nom du chapitre 1.2. Un numéro de chapitre ne contient jamais de
/// `_`, donc `ch1_2.zip` ne peut désigner que la 2e archive du chapitre 1.
const String separateurNumeroArchiveSansLangue = '_';

/// Nombre maximal de noms essayés pour trouver un nom d'archive libre
/// (`ch1.fr.zip`, `ch1.fr.2.zip`… `ch1.fr.<max>.zip`).
///
/// Garde-fou contre une boucle sans fin si le disque refuse toute création ;
/// en pratique, deux ou trois homonymes au plus.
const int nombreMaxArchivesHomonymes = 1000;

/// Nom (sans extension) d'un fichier importé par le client, copié dans le
/// dossier de son titre : `<type>/<nom du titre>/import.<cbz|pdf|epub>`,
/// puis `import.2.pdf`, `import.3.pdf`… si le nom est déjà pris
/// (migration 15).
///
/// NE PAS RENOMMER : ce motif est reconnu par le désinstalleur Windows
/// (`installateur/*.iss`) et par les fichiers déjà importés. Il ne peut pas
/// être confondu avec une archive (`ch….zip`) ni une couverture.
const String prefixeFichierImporte = 'import';

/// Préfixe des images dans une archive (`img1.jpg`, `img2.webp`…).
const String prefixePageArchive = 'img';

/// Nom de l'entrée qui contient le texte d'un chapitre (romans).
const String nomEntreeContenuTexte = 'contenu.html';

/// Nom de dossier utilisé quand le nom d'un titre est vide après nettoyage
/// (par exemple un nom fait uniquement de `?` ou de points).
const String nomDossierDeRepli = 'sans nom';

/// Longueur maximale (en unités UTF-16) du nom nettoyé d'un titre.
///
/// Windows limite un chemin complet à 260 caractères par défaut : on garde de
/// la marge pour le dossier racine, le type, le suffixe de source et le nom du
/// fichier.
const int longueurMaxNomDossierTitre = 100;

/// Longueur maximale d'une extension d'image (`jpg`, `jpeg`, `webp`, `avif`…).
const int longueurMaxExtensionPage = 5;

/// Nom (sans extension) du fichier de couverture d'un titre, enregistré dans
/// le dossier du titre : `<type>/<nom du titre>/couverture.<ext>`.
///
/// Ne peut pas être confondu avec une archive de chapitre, qui commence par
/// [prefixeFichierChapitre] et finit par `.zip`.
const String nomFichierCouverture = 'couverture';

/// Taille maximale d'une image de couverture enregistrée (20 Mio).
///
/// Une couverture MangaDex pèse quelques centaines de Kio ; la limite évite
/// qu'une image locale énorme, choisie par erreur, soit copiée en entier.
const int tailleMaxCouverture = 20 * 1024 * 1024;

/// Taille du tampon d'écriture d'une archive (256 Kio).
///
/// Le tampon par défaut d'`OutputFileStream` fait 1 Mio ; on le réduit car
/// chaque page est de toute façon vidée sur le disque dès qu'elle est ajoutée.
const int tailleTamponEcritureArchive = 256 * 1024;

/// Nom du fichier repère écrit à la racine d'un dossier de téléchargements
/// choisi par le client (`StockageTelechargements.personnalise`).
///
/// Sa présence prouve que le dossier joint est bien le bon : sous Linux ou
/// Android, un point de montage dont le partage est démonté reste un dossier
/// vide qui existe ; sans ce repère, les archives seraient recréées en
/// silence sur le disque local.
const String nomFichierMarqueurRacine = '.bibliotheque_perso';

/// Contenu du fichier repère ([nomFichierMarqueurRacine]), lisible par le
/// client s'il ouvre le dossier.
const String contenuMarqueurRacine =
    'Dossier des téléchargements de Bibliothèque perso. '
    'Ne pas supprimer ce fichier.\n';

/// Préfixe du fichier d'essai écrit puis supprimé pour vérifier qu'un dossier
/// candidat accepte l'écriture (`.essai_ecriture_<horodatage>`).
const String prefixeFichierEssaiEcriture = '.essai_ecriture_';

/// Nom du fichier qui indique au désinstalleur Windows où sont les chapitres
/// téléchargés, écrit dans le dossier de la base de données
/// (`fichier_emplacements.dart`).
///
/// NE PAS RENOMMER : le désinstalleur (`installateur/*.iss`) lit ce nom tel
/// quel, et il ne sait pas lire la base SQLite où le réglage est enregistré.
const String nomFichierEmplacements = 'emplacements.json';

/// Clé du chemin absolu du dossier des chapitres dans
/// [nomFichierEmplacements] : `{"dossierChapitres": "<chemin>"}`.
///
/// NE PAS RENOMMER : lue telle quelle par `installateur/*.iss`.
const String cleDossierChapitresEmplacements = 'dossierChapitres';

/// Suffixe du fichier temporaire écrit avant d'être renommé en
/// [nomFichierEmplacements] (`emplacements.json.tmp`).
const String suffixeFichierTemporaireEmplacements = '.tmp';

/// Nom du dossier de la base de données sous Windows, directement dans
/// `%APPDATA%` (`%APPDATA%\bibliotheque_perso`), depuis la version 0.3.3.
const String nomDossierBaseWindows = 'bibliotheque_perso';

/// Dossier de l'éditeur dans `%APPDATA%` utilisé jusqu'à la version 0.3.2
/// (`getApplicationSupportDirectory()` : nom de société de
/// `windows/runner/Runner.rc`).
///
/// NE PAS MODIFIER : sert seulement à retrouver la base des anciennes
/// versions (`%APPDATA%\io.github.zerma1\bibliotheque_perso`), même si le nom
/// de société change un jour.
const String nomAncienDossierEditeurWindows = 'io.github.zerma1';

/// Dossier de la base dans [nomAncienDossierEditeurWindows] jusqu'à la
/// version 0.3.2. NE PAS MODIFIER (même raison).
const String nomAncienDossierBaseWindows = 'bibliotheque_perso';

/// Fichier écrit par l'installateur Windows à côté de l'exécutable
/// (`installation.json`), lu ici pour la clé [cleDossierBaseInstallation].
///
/// NE PAS RENOMMER : écrit tel quel par `installateur/*.iss` (et lu aussi
/// par `lib/main.dart` pour le dossier des chapitres).
const String nomFichierInstallationWindows = 'installation.json';

/// Clé du dossier de la base de données choisi dans l'installateur Windows,
/// dans [nomFichierInstallationWindows] : `{"dossierBase": "<chemin>"}`.
///
/// NE PAS RENOMMER : écrite telle quelle par `installateur/*.iss`.
const String cleDossierBaseInstallation = 'dossierBase';

/// Suffixe de la copie d'un fichier pendant le déplacement de l'ancien
/// dossier de la base (`bibliotheque_perso.db.migration`).
///
/// La copie n'est renommée sous son vrai nom qu'une fois vérifiée : une
/// copie interrompue n'est donc jamais prise pour la base.
const String suffixeCopieMigrationBase = '.migration';

/// Suffixe sous lequel l'ancienne base est brièvement renommée pour vérifier
/// qu'aucun autre processus ne l'a ouverte (`….db.verification`), puis
/// remise sous son nom.
const String suffixeVerificationBaseLibre = '.verification';

/// Nombre d'essais pour rendre son nom à la base après le test
/// d'occupation ([suffixeVerificationBaseLibre]) ; un antivirus ou
/// l'indexeur de Windows peut bloquer brièvement le fichier.
const int nombreEssaisRestaurationBase = 5;

/// Attente entre deux essais de [nombreEssaisRestaurationBase].
const Duration delaiEntreEssaisRestaurationBase = Duration(milliseconds: 100);

/// Fichiers annexes de SQLite, accolés au nom de la base
/// (`bibliotheque_perso.db-wal`…).
///
/// Ceux qui traînent dans le dossier cible sans correspondre à la base
/// déplacée sont supprimés avant de la mettre en place : SQLite pourrait
/// sinon tenter de les rejouer sur une autre base.
const List<String> suffixesFichiersAnnexesSqlite = <String>[
  '-wal',
  '-shm',
  '-journal',
];

/// Taille des blocs lus pour comparer une copie à l'original (1 Mio).
const int tailleBlocComparaisonFichiers = 1024 * 1024;
