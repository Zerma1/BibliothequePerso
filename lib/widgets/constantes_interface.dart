/// Constantes de mise en page de l'interface (PLAYBOOK.md section 9 : pas de
/// valeur magique).
library;

/// Numéro de version affiché (« À propos », sous la navigation).
///
/// Suit la version de `pubspec.yaml` sans le numéro de build (`X.Y.Z` de
/// `version: X.Y.Z+N`). Elle peut la précéder entre deux publications :
/// `pubspec.yaml` n'est mis à jour qu'à la publication (tâche T7). Un test
/// vérifie qu'elle est égale ou supérieure. Recopiée ici car lire la version
/// à l'exécution demanderait un paquet supplémentaire.
const String versionApplication = '0.3.1';

// ---------------------------------------------------------------- Chapitres

/// Parts de largeur des colonnes de la liste des chapitres (nom, langue,
/// date, hors-ligne, lu) : proportions plutôt que pixels, pour suivre la
/// largeur de l'écran.
const int flexColonneNom = 6;

/// Part de largeur de la colonne de la langue.
const int flexColonneLangue = 2;

/// Part de largeur de la colonne de la date.
const int flexColonneDate = 3;

/// Part de largeur de la colonne de l'état hors-ligne.
const int flexColonneHorsLigne = 2;

/// Part de largeur de la colonne « lu ».
const int flexColonneLu = 2;

// ------------------------------------------------------------------ Lecteur

/// Agrandissement maximal du lecteur.
const double zoomMaxLecteur = 4;

/// Pas des boutons de zoom du lecteur.
const double pasZoomLecteur = 0.5;

/// Largeur maximale des pages et du texte dans le lecteur : sur un grand
/// écran, une page de webtoon étirée sur toute la largeur serait illisible.
const double largeurMaxLecture = 900;

/// Hauteur provisoire d'une page pas encore lue, en part de la hauteur de
/// l'écran : la liste garde une taille plausible pendant le chargement.
const double fractionHauteurPageProvisoire = 1.2;

/// Interligne du texte d'un roman dans le lecteur (plus aéré que le texte
/// de l'interface, pour une lecture longue).
const double interligneLecture = 1.6;

/// Largeur (en pixels logiques) à partir de laquelle la navigation passe de
/// la barre du bas au `NavigationRail` latéral (PLAYBOOK.md section 8).
const double largeurMinNavigationLaterale = 600;

/// Largeur maximale d'une carte de la grille : le nombre de colonnes s'adapte
/// à la largeur disponible au lieu d'être fixé.
const double largeurMaxCarteTitre = 180;

/// Rapport largeur / hauteur d'une carte de titre (couverture + nom).
const double rapportCarteTitre = 0.62;

/// Rapport largeur / hauteur d'une couverture (format courant d'un tome).
const double rapportCouverture = 0.7;

/// Part de la largeur de l'écran occupée par la couverture sur la fiche d'un
/// titre en disposition large.
const double fractionCouvertureFiche = 0.28;

/// Part de la largeur occupée par la couverture en disposition étroite.
const double fractionCouvertureFicheEtroite = 0.45;

/// Largeur maximale de la couverture sur la fiche d'un titre.
const double largeurMaxCouvertureFiche = 300;

/// Largeur maximale des formulaires et dialogues : au-delà, les champs
/// deviendraient pénibles à lire sur un grand écran.
const double largeurMaxFormulaire = 560;

/// Hauteur maximale d'un dialogue qui contient une longue liste (choix d'une
/// langue), en part de la hauteur de l'écran.
const double fractionHauteurDialogueListe = 0.6;

/// Opacité du fond rouge d'un chapitre dont la suppression est prévue : une
/// teinte légère qui attire l'œil sans gêner la lecture du texte.
const double opaciteFondSuppressionPrevue = 0.35;

/// Crans de la jauge des limites de téléchargement (0 à 500) : serrés au
/// début, où se font la plupart des réglages (de 1 en 1 jusqu'à 10), puis de
/// plus en plus espacés. Une jauge linéaire de 500 crans rendrait « 3 » ou
/// « 12 » impossibles à viser ; les boutons − / + à côté de la jauge
/// donnent ensuite la valeur exacte, de 1 en 1.
const List<int> cransLimitesTelechargement = <int>[
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 30, 40, 50, 75, //
  100, 150, 200, 300, 400, 500,
];

/// Couleur principale du logo (indigo), source de toute la palette de
/// l'interface en clair comme en sombre.
const int couleurLogoIndigo = 0xFF3F51B5;

/// Petit espacement entre éléments.
const double espacementPetit = 8;

/// Espacement standard (marges des écrans).
const double espacementMoyen = 16;

/// Grand espacement (séparation des sections).
const double espacementGrand = 24;

/// Marge laissée sous les listes pour que le bouton flottant ne cache pas le
/// dernier élément (hauteur du bouton étendu + ses marges Material).
const double margeBasBoutonFlottant = 88;

/// Hauteur réservée à la barre de progression linéaire (sa hauteur par défaut
/// en Material 3) : le contenu ne saute pas quand elle apparaît.
const double hauteurBarreProgression = 4;

/// Épaisseur du petit indicateur de progression qui remplace une icône de
/// bouton : plus fin que celui par défaut pour rester lisible à cette taille.
const double epaisseurIndicateurBouton = 2;

/// Taille des icônes des vues vide et erreur.
const double tailleIconeEtat = 64;

/// Nombre maximal de lignes du nom sur une carte de titre.
const int lignesMaxNomCarte = 2;

/// Largeur maximale d'une miniature dans le choix de la couverture : la
/// grille compte autant de colonnes que la largeur du dialogue le permet.
const double largeurMaxMiniatureCouverture = 120;

/// Largeur de la petite couverture d'une ligne de l'onglet Mises à jour
/// (vignette de liste, pas la mise en page principale) : assez grande pour
/// reconnaître le titre, assez petite pour garder la ligne compacte.
const double largeurCouvertureLigne = 48;

/// Part de la largeur de l'écran occupée au plus par le contenu d'un
/// dialogue de largeur fixe (choix de la couverture) : laisse les marges
/// Material visibles sur téléphone.
const double fractionLargeurDialogue = 0.8;

/// Part de la hauteur de l'écran occupée au plus par le texte d'un bandeau
/// global (dossier des chapitres inaccessible, redémarrage) : au-delà, le
/// texte défile, et l'onglet garde la place de s'afficher sur un téléphone.
const double fractionHauteurMaxBandeau = 0.15;

/// Part de la hauteur de l'écran occupée au plus par le panneau des
/// catégories (feuille du bas sur téléphone).
const double fractionHauteurPanneau = 0.85;
