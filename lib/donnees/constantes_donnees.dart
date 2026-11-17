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
