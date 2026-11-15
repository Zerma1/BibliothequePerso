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

/// Taille du tampon d'écriture d'une archive (256 Kio).
///
/// Le tampon par défaut d'`OutputFileStream` fait 1 Mio ; on le réduit car
/// chaque page est de toute façon vidée sur le disque dès qu'elle est ajoutée.
const int tailleTamponEcritureArchive = 256 * 1024;
