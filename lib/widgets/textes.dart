/// Tous les textes affichés par l'interface, en français (PLAYBOOK.md
/// section 8). Les regrouper ici facilitera une traduction future.
library;

import '../etat/description_erreur.dart';
import '../modeles/source.dart';
import '../modeles/titre.dart';

/// Textes de l'interface. Les textes qui dépendent d'une valeur sont des
/// méthodes.
abstract final class Textes {
  // ------------------------------------------------------------- Application

  /// Nom de l'application.
  static const String titreApplication = 'Bibliothèque perso';

  /// Onglet de la bibliothèque.
  static const String ongletBibliotheque = 'Bibliothèque';

  /// Onglet des sites configurés.
  static const String ongletSources = 'Sources';

  // ---------------------------------------------------------------- Communs

  /// Bouton pour relancer une action échouée.
  static const String reessayer = 'Réessayer';

  /// Bouton d'annulation.
  static const String annuler = 'Annuler';

  /// Bouton de validation d'un ajout.
  static const String ajouter = 'Ajouter';

  /// Bouton de suppression.
  static const String supprimer = 'Supprimer';

  /// Bouton ou info-bulle d'actualisation.
  static const String actualiser = 'Actualiser';

  /// Message d'un champ obligatoire laissé vide.
  static const String champObligatoire = 'Ce champ est obligatoire.';

  /// Lien externe qui n'a pas pu être ouvert.
  static const String lienImpossible =
      'Impossible d\'ouvrir le lien dans le navigateur.';

  // ---------------------------------------------------------------- Erreurs

  /// Début du message quand un site n'a pas pu être lu.
  static const String erreurSite = 'Le site n\'a pas pu être lu.';

  /// Début du message quand la base locale refuse une opération.
  static const String erreurBaseDeDonnees =
      'La base de données locale a rencontré un problème.';

  /// Adresse non saisie.
  static const String erreurAdresseVide =
      'Collez d\'abord une adresse commençant par http:// ou https://.';

  /// Titre supprimé entre-temps.
  static const String erreurIntrouvable =
      'Ce titre n\'existe plus dans la bibliothèque.';

  /// Début du message d'une erreur imprévue.
  static const String erreurInattendue =
      'Une erreur inattendue s\'est produite.';

  /// Message affichable pour une [erreur] classée par un état.
  static String messageErreur(DescriptionErreur erreur) {
    final detail = erreur.detail.trim();
    String avecDetail(String debut) =>
        detail.isEmpty ? debut : '$debut\n$detail';
    switch (erreur.nature) {
      case NatureErreur.site:
        return avecDetail(erreurSite);
      case NatureErreur.baseDeDonnees:
        return avecDetail(erreurBaseDeDonnees);
      case NatureErreur.refus:
        // Le service fournit déjà une phrase complète destinée au client.
        return detail.isEmpty ? erreurInattendue : detail;
      case NatureErreur.adresseVide:
        return erreurAdresseVide;
      case NatureErreur.introuvable:
        return erreurIntrouvable;
      case NatureErreur.inattendue:
        return avecDetail(erreurInattendue);
    }
  }

  // ------------------------------------------------------------- Démarrage

  /// Titre de l'écran affiché si la base ne s'ouvre pas.
  static const String erreurDemarrageTitre =
      'Impossible d\'ouvrir la bibliothèque';

  /// Explication de l'écran d'erreur de démarrage.
  static const String erreurDemarrageExplication =
      'La base de données locale n\'a pas pu être ouverte. Vérifiez que '
      'l\'application peut écrire dans son dossier de données, puis '
      'réessayez.';

  /// Détail technique de l'erreur de démarrage.
  static String detailTechnique(String detail) => 'Détail technique : $detail';

  // ---------------------------------------------------------- Bibliothèque

  /// Champ de recherche de la bibliothèque.
  static const String champRecherche = 'Rechercher un titre';

  /// Puce « toutes les listes ».
  static const String toutesLesListes = 'Tous les titres';

  /// Puce « toutes les catégories ».
  static const String toutesLesCategories = 'Toutes les catégories';

  /// Bouton d'ajout d'un titre.
  static const String boutonAjouterTitre = 'Ajouter un titre';

  /// Bibliothèque vide (aide au premier lancement).
  static const String bibliothequeVide =
      'Votre bibliothèque est vide.\n'
      'Collez l\'adresse d\'un manga MangaDex pour commencer.';

  /// Aucun titre pour les filtres choisis.
  static const String aucunResultat =
      'Aucun titre ne correspond à ces filtres ou à cette recherche.';

  /// Libellé accessible du badge des chapitres non lus.
  static String chapitresNonLus(int nombre) =>
      nombre <= 1 ? '$nombre chapitre non lu' : '$nombre chapitres non lus';

  // ---------------------------------------------------------- Mises à jour

  /// Bouton de recherche des nouveaux chapitres des titres suivis.
  static const String rechercherNouveauxChapitres =
      'Rechercher les nouveaux chapitres';

  /// Info-bulle du bouton pendant la recherche.
  static const String rechercheNouveauxChapitresEnCours =
      'Recherche des nouveaux chapitres…';

  /// Bilan d'une recherche de nouveaux chapitres : « 3 nouveaux chapitres
  /// pour 2 titres. 1 site n'a pas répondu. » ou « Aucun nouveau chapitre. ».
  static String bilanMisesAJour({
    required int nombreChapitres,
    required int nombreTitres,
    required int nombreSitesEnEchec,
    int nombreAutresEchecs = 0,
  }) {
    final chapitres = nombreChapitres == 0
        ? 'Aucun nouveau chapitre'
        : '${nouveauxChapitres(nombreChapitres)} pour $nombreTitres '
              '${nombreTitres <= 1 ? 'titre' : 'titres'}';
    final phrases = <String>['$chapitres.'];
    if (nombreSitesEnEchec > 0) {
      phrases.add(
        nombreSitesEnEchec == 1
            ? "1 site n'a pas répondu."
            : "$nombreSitesEnEchec sites n'ont pas répondu.",
      );
    }
    if (nombreAutresEchecs > 0) {
      phrases.add(
        nombreAutresEchecs == 1
            ? "1 titre n'a pas pu être vérifié."
            : "$nombreAutresEchecs titres n'ont pas pu être vérifiés.",
      );
    }
    return phrases.join(' ');
  }

  // ------------------------------------------------- Dialogue ajout de titre

  /// Champ de l'adresse d'un titre.
  static const String champUrlTitre = 'Adresse du titre';

  /// Exemple d'adresse de titre.
  static const String aideUrlTitre = 'Exemple : https://mangadex.org/title/…';

  /// Intitulé des cases à cocher des listes.
  static const String rangerDans = 'Ranger dans :';

  /// Lecture du site pendant l'ajout d'un titre.
  static const String ajoutTitreEnCours =
      'Lecture du site en cours (quelques secondes)…';

  /// Nombre de chapitres découverts (« aucun nouveau chapitre »…).
  static String nouveauxChapitres(int nombre) {
    if (nombre == 0) {
      return 'aucun nouveau chapitre';
    }
    return nombre == 1 ? '1 nouveau chapitre' : '$nombre nouveaux chapitres';
  }

  /// Confirmation de l'ajout d'un titre.
  static String titreAjoute(String nom, int nombreNouveaux) =>
      '« $nom » ajouté : ${nouveauxChapitres(nombreNouveaux)}.';

  // ---------------------------------------------------------------- Sources

  /// Bouton d'ajout d'un site.
  static const String boutonAjouterSite = 'Ajouter un site';

  /// Aucun site configuré.
  static const String sourcesVide =
      'Aucun site configuré.\n'
      'Ajoutez un site à partir de son adresse. MangaDex est ajouté '
      'automatiquement quand vous ajoutez l\'un de ses titres.';

  /// Langue par défaut absente.
  static const String langueNonPrecisee = 'langue non précisée';

  /// Nom affiché d'un type de site.
  static String libelleTypeSource(TypeSource type) {
    switch (type) {
      case TypeSource.mangaDex:
        return 'MangaDex (API officielle)';
      case TypeSource.madara:
        return 'WordPress Madara';
      case TypeSource.mangaThemesia:
        return 'WordPress MangaThemesia';
      case TypeSource.generique:
        return 'Générique (sélecteurs CSS)';
    }
  }

  /// Ligne de description d'un site dans la liste des sources.
  static String descriptionSource(Source source) {
    final langue = source.langueParDefaut.isEmpty
        ? langueNonPrecisee
        : 'langue : ${source.langueParDefaut.toUpperCase()}';
    return '${source.urlBase}\n${libelleTypeSource(source.typeSource)} · '
        '$langue';
  }

  /// Nom d'un site désactivé, suivi de la mention « désactivé ».
  static String nomSourceInactive(String nom) => '$nom (désactivé)';

  // ---------------------------------------------------------- Ajout de site

  /// Champ de l'adresse d'un site.
  static const String champUrlSite = 'Adresse du site';

  /// Aide du champ d'adresse d'un site.
  static const String aideUrlSite =
      'L\'accueil ou n\'importe quelle page du site';

  /// Champ du nom d'un site.
  static const String champNomSite = 'Nom (facultatif)';

  /// Aide du champ de nom quand aucun nom n'est proposé.
  static const String aideNomSite = 'Par défaut : le nom de domaine';

  /// Nom proposé à partir de l'adresse.
  static String nomPropose(String nom) => 'Par défaut : $nom';

  /// Champ de la langue par défaut.
  static const String champLangue = 'Langue par défaut (facultatif)';

  /// Aide du champ de langue.
  static const String aideLangue = 'Code à deux lettres : fr, en, ja…';

  /// Langue mal saisie.
  static const String erreurLangue = 'Deux lettres attendues (par ex. fr).';

  /// Champ du type de site.
  static const String champTypeSite = 'Type de site';

  /// Choix « détection automatique » du type.
  static const String typeAutomatique = 'Détection automatique';

  /// Aide du champ de type.
  static const String aideTypeSite =
      'À corriger seulement si la détection se trompe.';

  /// Détection du site pendant l'ajout.
  static const String detectionEnCours = 'Analyse du site en cours…';

  /// Confirmation de l'ajout d'un site.
  static String siteAjoute(String nom) => 'Site « $nom » ajouté.';

  /// Site déjà présent.
  static String siteDejaConfigure(String nom) =>
      'Le site « $nom » est déjà configuré.';

  // ------------------------------------------------------------------ Titre

  /// Libellé de l'auteur.
  static const String auteur = 'Auteur';

  /// Libellé d'une ligne d'information, suivi des deux-points français.
  static String libelleInfo(String libelle) => '$libelle : ';

  /// Libellé du statut.
  static const String statut = 'Statut';

  /// Libellé du type de titre.
  static const String typeTitre = 'Type';

  /// Libellé du site d'origine.
  static const String site = 'Site';

  /// Valeur inconnue.
  static const String inconnu = 'inconnu';

  /// Titre de la section résumé.
  static const String resume = 'Résumé';

  /// Résumé absent.
  static const String aucunResume = 'Aucun résumé.';

  /// Titre de la section des catégories.
  static const String categories = 'Catégories';

  /// Aucune catégorie.
  static const String aucuneCategorie = 'Aucune catégorie.';

  /// Titre de la section des listes.
  static const String listes = 'Listes';

  /// En-tête repliable des titres alternatifs.
  static String titresAlternatifs(int nombre) => 'Titres alternatifs ($nombre)';

  /// En-tête de la liste des chapitres.
  static String enTeteChapitres(int nombre, int nonLus) =>
      'Chapitres : $nombre (${chapitresNonLus(nonLus)})';

  /// Aucun chapitre connu.
  static const String aucunChapitre =
      'Aucun chapitre pour l\'instant.\n'
      'Utilisez « Actualiser » pour relire le site.';

  /// Bouton d'ouverture du titre dans le navigateur.
  static const String ouvrirSurLeSite = 'Ouvrir sur le site';

  /// Action : marquer un chapitre lu.
  static const String marquerLu = 'Marquer comme lu';

  /// Action : marquer un chapitre non lu.
  static const String marquerNonLu = 'Marquer comme non lu';

  /// Action : marquer tous les chapitres lus.
  static const String toutMarquerLu = 'Tout marquer comme lu';

  /// Action : marquer tous les chapitres non lus.
  static const String toutMarquerNonLu = 'Tout marquer comme non lu';

  /// Action : supprimer le titre.
  static const String supprimerTitre = 'Supprimer de la bibliothèque';

  /// Question de confirmation de la suppression.
  static String confirmationSuppression(String nom) =>
      'Supprimer « $nom » et ses chapitres de la bibliothèque ?\n'
      'Le titre pourra être ajouté de nouveau plus tard.';

  /// Titre supprimé.
  static String titreSupprime(String nom) => '« $nom » supprimé.';

  /// Crédit obligatoire des données MangaDex (PLAYBOOK.md section 6).
  static const String creditMangaDex = 'Données fournies par MangaDex';

  /// Résultat d'une actualisation.
  static String actualisationTerminee(int nombreNouveaux) {
    final texte = nouveauxChapitres(nombreNouveaux);
    return '${texte[0].toUpperCase()}${texte.substring(1)}.';
  }

  /// Date de la dernière vérification du site.
  static String derniereVerification(DateTime? date) => date == null
      ? 'Jamais vérifié'
      : 'Dernière vérification : ${formaterDate(date)}';

  /// Nom d'un chapitre, ou « Chapitre » suivi du numéro si le site n'en donne
  /// pas.
  static String nomChapitre(String nom, double numero) =>
      nom.trim().isEmpty ? 'Chapitre ${formaterNumero(numero)}' : nom;

  /// Détails d'un chapitre : langue et date de publication.
  static String detailsChapitre(String langue, DateTime? datePublication) {
    final morceaux = <String>[
      if (langue.isNotEmpty) langue.toUpperCase(),
      if (datePublication != null) formaterDate(datePublication),
    ];
    return morceaux.isEmpty ? 'Langue et date inconnues' : morceaux.join(' · ');
  }

  /// Nom affiché d'un type de titre.
  static String libelleTypeTitre(TypeTitre type) {
    switch (type) {
      case TypeTitre.manga:
        return 'Manga';
      case TypeTitre.manhwa:
        return 'Manhwa';
      case TypeTitre.manhua:
        return 'Manhua';
      case TypeTitre.roman:
        return 'Roman';
      case TypeTitre.livre:
        return 'Livre';
      case TypeTitre.autre:
        return 'Autre';
    }
  }

  // ------------------------------------------------------------- Formatage

  /// Date au format français `jj/mm/aaaa`, en heure locale.
  ///
  /// Écrit à la main : le paquet `intl` ne fait pas partie de la pile
  /// autorisée (PLAYBOOK.md section 3).
  static String formaterDate(DateTime date) {
    final locale = date.toLocal();
    final jour = locale.day.toString().padLeft(2, '0');
    final mois = locale.month.toString().padLeft(2, '0');
    return '$jour/$mois/${locale.year}';
  }

  /// Numéro de chapitre sans zéros inutiles (`1`, `10.5`).
  static String formaterNumero(double numero) {
    if (numero.isFinite && numero == numero.truncateToDouble()) {
      return numero.toInt().toString();
    }
    return numero.toString();
  }
}
