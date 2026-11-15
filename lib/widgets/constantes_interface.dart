/// Constantes de mise en page de l'interface (PLAYBOOK.md section 9 : pas de
/// valeur magique).
library;

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

/// Taille des icônes des vues vide et erreur.
const double tailleIconeEtat = 64;

/// Nombre maximal de lignes du nom sur une carte de titre.
const int lignesMaxNomCarte = 2;

/// Nombre de caractères d'un code de langue ISO 639-1.
const int longueurCodeLangue = 2;
