/// Tous les textes affichés par l'interface, en français (PLAYBOOK.md
/// section 8). Les regrouper ici facilitera une traduction future.
library;

import '../etat/description_erreur.dart';
import '../etat/etat_parametres.dart';
import '../etat/outils_chapitres.dart';
import '../modeles/source.dart';
import '../modeles/telechargement.dart';
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

  /// Onglet de la file de téléchargement.
  static const String ongletTelechargements = 'Téléchargements';

  /// Onglet des paramètres.
  static const String ongletParametres = 'Paramètres';

  /// Numéro de version court, affiché sous la navigation.
  static String versionCourte(String version) => 'v$version';

  /// Numéro de version complet (« À propos »).
  static String versionComplete(String version) => 'Version $version';

  /// Libellé accessible du badge des téléchargements actifs.
  static String telechargementsActifs(int nombre) => nombre <= 1
      ? '$nombre téléchargement en cours'
      : '$nombre téléchargements en cours';

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

  /// Nom de site laissé vide.
  static const String erreurNomVide = 'Donnez un nom au site.';

  /// Suppression d'un site refusée : des titres en viennent encore.
  static String erreurSiteAvecTitres(int nombre) {
    final titres = nombre <= 1
        ? 'un titre de votre bibliothèque vient'
        : '$nombre titres de votre bibliothèque viennent';
    return 'Impossible de supprimer ce site : $titres encore de lui. '
        'Supprimez d\'abord ces titres, ou désactivez simplement le site.';
  }

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
      case NatureErreur.nomVide:
        return erreurNomVide;
      case NatureErreur.siteAvecTitres:
        return erreurSiteAvecTitres(int.tryParse(detail) ?? 0);
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

  // ------------------------------------------- Titre : chapitres hors-ligne

  /// En-tête de la liste des chapitres regroupés par numéro.
  static String enTeteNumeros(int nombre, int nonLus) =>
      'Chapitres : $nombre (${chapitresNonLus(nonLus)})';

  /// Légende de la colonne du numéro et du nom.
  static const String colonneChapitre = 'N° / nom';

  /// Légende de la colonne de la langue.
  static const String colonneLangue = 'Langue';

  /// Légende de la colonne de la date.
  static const String colonneDate = 'Date';

  /// Légende de la colonne de l'état hors-ligne.
  static const String colonneHorsLigne = 'Hors-ligne';

  /// Légende de la colonne de lecture.
  static const String colonneLu = 'Lu';

  /// Titre de la légende des icônes.
  static const String legende = 'Légende';

  /// Explication des appuis sur une ligne de chapitre.
  static const String aideAppuiChapitre =
      'Touchez un chapitre téléchargé pour le lire. Un chapitre non '
      'téléchargé propose de le télécharger ou de l\'ouvrir sur le site.';

  /// Nom d'un état hors-ligne (légende, info-bulle).
  static String libelleStatutHorsLigne(StatutHorsLigne statut) {
    switch (statut) {
      case StatutHorsLigne.telecharge:
        return 'Téléchargé';
      case StatutHorsLigne.enFile:
        return 'En file d\'attente';
      case StatutHorsLigne.enCours:
        return 'Téléchargement en cours';
      case StatutHorsLigne.echec:
        return 'Échec du téléchargement';
      case StatutHorsLigne.nonTelecharge:
        return 'Non téléchargé (en ligne seulement)';
    }
  }

  /// Info-bulle de l'état hors-ligne d'un chapitre, avec l'action proposée.
  static String infoBulleHorsLigne(EtatHorsLigne etat) {
    switch (etat.statut) {
      case StatutHorsLigne.telecharge:
        if (etat.aSuppressionPrevue) {
          return 'Suppression prévue — appuyer pour supprimer maintenant';
        }
        if (etat.estDoublon) {
          return 'Doublon — appuyer pour supprimer cette version';
        }
        return 'Téléchargé — appuyer pour supprimer le téléchargement';
      case StatutHorsLigne.enFile:
        return 'En file d\'attente — appuyer pour retirer de la file';
      case StatutHorsLigne.enCours:
        return 'Téléchargement en cours (${pourcentage(etat.progression)}) '
            '— appuyer pour annuler';
      case StatutHorsLigne.echec:
        final message = etat.messageErreur;
        return 'Échec${message == null ? '' : ' : $message'} '
            '— appuyer pour réessayer';
      case StatutHorsLigne.nonTelecharge:
        return 'Non téléchargé — appuyer pour télécharger';
    }
  }

  /// Progression en pourcentage (« 45 % », « … » si inconnue).
  static String pourcentage(double? progression) =>
      progression == null ? '…' : '${(progression * 100).round()} %';

  /// Nombre d'autres versions d'un même numéro.
  static String autresVersions(int nombre) =>
      nombre <= 1 ? '1 autre version' : '$nombre autres versions';

  /// Action : lire un chapitre.
  static const String lire = 'Lire';

  /// Action : télécharger un chapitre.
  static const String telecharger = 'Télécharger';

  /// Action : supprimer l'archive d'un chapitre.
  static const String supprimerTelechargement = 'Supprimer le téléchargement';

  /// Action : retirer un chapitre de la file.
  static const String retirerDeLaFile = 'Retirer de la file';

  /// Action : relancer un téléchargement en échec.
  static const String reessayerTelechargement = 'Réessayer le téléchargement';

  /// Question avant la suppression d'une archive.
  static String confirmationSuppressionTelechargement(String nomChapitre) =>
      'Supprimer le fichier hors-ligne de « $nomChapitre » ?\n'
      'Le chapitre reste dans la liste. Pour un titre favori ou suivi, il '
      'pourra être téléchargé de nouveau automatiquement.';

  /// Chapitre désigné avec son titre (écran Téléchargements, qui mélange les
  /// titres).
  static String chapitreDuTitre(String nomTitre, String nomChapitre) =>
      '$nomTitre – $nomChapitre';

  // --------------------------- Titre : suppressions prévues et doublons

  /// Légende : archive dont la suppression automatique est prévue.
  static const String legendeSuppressionPrevue = 'Suppression prévue (24 h)';

  /// Légende : archive en double.
  static const String legendeDoublon = 'Doublon (à vous de choisir)';

  /// Compte à rebours d'une suppression prévue.
  static String suppressionDans(Duration reste) {
    if (reste.inMinutes < 1) return 'Suppression imminente';
    final heures = reste.inHours;
    final minutes = reste.inMinutes % 60;
    if (heures == 0) return 'Supprimé dans $minutes min';
    return 'Supprimé dans $heures h ${minutes.toString().padLeft(2, '0')}';
  }

  /// Explication d'une suppression prévue (sous le compte à rebours).
  static const String explicationSuppressionPrevue =
      'Ce chapitre ne fait plus partie de vos règles de téléchargement.';

  /// Bouton : garder une archive dont la suppression est prévue.
  static const String garder = 'Garder';

  /// Bouton : supprimer tout de suite une archive.
  static const String supprimerMaintenant = 'Supprimer maintenant';

  /// Archive gardée.
  static const String chapitreGarde =
      'Chapitre gardé : il ne sera plus supprimé automatiquement.';

  /// Explication d'un doublon.
  static const String explicationDoublon =
      "Doublon : même numéro et même langue qu'une autre version "
      'téléchargée. Supprimez celle que vous ne voulez pas.';

  /// Bouton : supprimer un doublon.
  static const String supprimerCeDoublon = 'Supprimer ce doublon';

  /// Mention sur un numéro dont une version cachée demande une action.
  static const String versionsATrier = 'Versions à trier';

  // ------------------------------------------------------ Titre : langues

  /// Titre de la section des langues d'un titre.
  static const String languesDuTitre = 'Langues de ce titre';

  /// Langues d'un titre qui suit le réglage général.
  static String languesTitreGenerales(List<String> langues) =>
      'Réglage général (« Mes langues ») : ${listeLangues(langues)}';

  /// Langues d'un titre choisies pour lui.
  static String languesTitrePropres(List<String> langues) =>
      'Personnalisées : ${listeLangues(langues)}';

  /// Langues d'un titre qui suit l'ancien réglage de son site.
  static String languesTitreSite(List<String> langues) =>
      'Réglage du site : ${listeLangues(langues)}';

  /// Bouton : modifier les langues d'un titre.
  static const String modifierLangues = 'Modifier';

  /// Bouton : revenir au réglage général.
  static const String revenirAuReglageGeneral = 'Revenir au réglage général';

  /// Choix du dialogue : suivre le réglage général.
  static const String suivreReglageGeneral = 'Suivre « Mes langues »';

  /// Choix du dialogue : langues propres au titre.
  static const String languesPersonnalisees = 'Langues personnalisées';

  /// Explication du dialogue des langues d'un titre.
  static const String explicationLanguesTitre =
      "Seuls les chapitres dans ces langues sont téléchargés pour ce titre. "
      "Une langue retirée : ses chapitres téléchargés seront supprimés dans "
      "24 heures (vous pourrez les garder). Une langue ajoutée : le site est "
      "relu pour trouver ses chapitres.";

  /// Langues d'un titre enregistrées.
  static String languesTitreEnregistrees(int? nombreNouveaux) {
    if (nombreNouveaux == null) {
      return "Langues enregistrées. Le site n'a pas pu être relu : les "
          "chapitres des nouvelles langues apparaîtront à la prochaine "
          "actualisation.";
    }
    if (nombreNouveaux == 0) return 'Langues enregistrées.';
    return 'Langues enregistrées : ${nouveauxChapitres(nombreNouveaux)}.';
  }

  // -------------------------------------------------------- Mes langues

  /// Section des langues de lecture.
  static const String sectionLangues = 'Mes langues';

  /// Explication de la section des langues.
  static const String explicationMesLangues =
      "Langues dans lesquelles vous lisez, par ordre de préférence. Pour "
      "chaque chapitre, une seule version est téléchargée : dans la langue "
      "favorite si elle existe, sinon dans la suivante. Les chapitres dans "
      "d'autres langues ne sont jamais téléchargés automatiquement. Chaque "
      "titre peut avoir ses propres langues (sur sa fiche).";

  /// Bouton : ajouter une langue.
  static const String ajouterLangue = 'Ajouter une langue';

  /// Titre du dialogue de choix d'une langue.
  static const String choisirUneLangue = 'Choisir une langue';

  /// Champ de recherche d'une langue.
  static const String rechercherLangue = 'Rechercher une langue';

  /// Aucune langue ne correspond à la recherche.
  static const String aucuneLangueTrouvee = 'Aucune langue trouvée.';

  /// Action : la langue devient la favorite.
  static const String choisirCommeFavorite = 'Choisir comme favorite';

  /// Mention de la langue favorite.
  static const String favorite = 'favorite';

  /// Action : monter une langue.
  static const String monterLangue = 'Préférer (monter)';

  /// Action : descendre une langue.
  static const String descendreLangue = 'Moins préférer (descendre)';

  /// Action : retirer une langue.
  static const String retirerLangue = 'Retirer';

  /// Nombre maximal de langues atteint.
  static String maximumLangues(int nombre) =>
      'Vous avez atteint le maximum de $nombre langues.';

  /// Langues enregistrées (réglage général).
  static const String languesEnregistrees =
      'Langues enregistrées : les téléchargements sont mis à jour.';

  /// Nom français d'une langue (code ISO 639-1, variante régionale
  /// éventuelle), ou le code en majuscules s'il est inconnu.
  static String nomLangue(String code) =>
      nomsLangues[code.toLowerCase()] ?? code.toUpperCase();

  /// Liste lisible de langues : « Français (favorite), Anglais ».
  static String listeLangues(List<String> codes) {
    if (codes.isEmpty) return '—';
    return <String>[
      for (var i = 0; i < codes.length; i++)
        i == 0 ? '${nomLangue(codes[i])} ($favorite)' : nomLangue(codes[i]),
    ].join(', ');
  }

  /// Langues proposées à l'ajout, avec leur nom en français (codes ISO
  /// 639-1, et variantes régionales utilisées par MangaDex). Triées par nom
  /// à l'affichage.
  static const Map<String, String> nomsLangues = <String, String>{
    'fr': 'Français',
    'en': 'Anglais',
    'es': 'Espagnol',
    'es-la': 'Espagnol (Amérique latine)',
    'pt': 'Portugais',
    'pt-br': 'Portugais (Brésil)',
    'it': 'Italien',
    'de': 'Allemand',
    'nl': 'Néerlandais',
    'pl': 'Polonais',
    'ru': 'Russe',
    'uk': 'Ukrainien',
    'cs': 'Tchèque',
    'sk': 'Slovaque',
    'hu': 'Hongrois',
    'ro': 'Roumain',
    'bg': 'Bulgare',
    'sr': 'Serbe',
    'hr': 'Croate',
    'lt': 'Lituanien',
    'el': 'Grec',
    'tr': 'Turc',
    'sv': 'Suédois',
    'no': 'Norvégien',
    'da': 'Danois',
    'fi': 'Finnois',
    'ca': 'Catalan',
    'ar': 'Arabe',
    'he': 'Hébreu',
    'fa': 'Persan',
    'hi': 'Hindi',
    'bn': 'Bengali',
    'ta': 'Tamoul',
    'th': 'Thaï',
    'vi': 'Vietnamien',
    'id': 'Indonésien',
    'ms': 'Malais',
    'tl': 'Tagalog',
    'my': 'Birman',
    'mn': 'Mongol',
    'kk': 'Kazakh',
    'ja': 'Japonais',
    'ja-ro': 'Japonais (romanisé)',
    'ko': 'Coréen',
    'ko-ro': 'Coréen (romanisé)',
    'zh': 'Chinois (simplifié)',
    'zh-hk': 'Chinois (traditionnel)',
    'zh-ro': 'Chinois (romanisé)',
    'eo': 'Espéranto',
    'la': 'Latin',
  };

  /// Chapitre ajouté à la file.
  static const String telechargementAjoute =
      'Chapitre ajouté à la file de téléchargement.';

  /// Archive supprimée.
  static const String telechargementSupprime = 'Téléchargement supprimé.';

  // ---------------------------------------------------------------- Lecteur

  /// Position dans le chapitre.
  static String pageSurTotal(int page, int total) => 'Page $page / $total';

  /// Bouton du chapitre précédent.
  static const String chapitrePrecedent = 'Chapitre précédent';

  /// Bouton du chapitre suivant.
  static const String chapitreSuivant = 'Chapitre suivant';

  /// Fin du chapitre.
  static const String finDuChapitre = 'Fin du chapitre';

  /// Dernier chapitre connu atteint.
  static const String dernierChapitre =
      'C\'est le dernier chapitre connu de ce titre.';

  /// Bouton de zoom avant.
  static const String agrandir = 'Agrandir';

  /// Bouton de zoom arrière.
  static const String reduire = 'Réduire';

  /// Retour à la taille normale.
  static const String tailleNormale = 'Taille normale';

  /// Page illisible dans l'archive.
  static const String pageIllisible = 'Cette page n\'a pas pu être lue.';

  /// Chapitre pas encore sur l'appareil.
  static const String lecteurNonTelecharge =
      'Ce chapitre n\'est pas encore sur l\'appareil.\n'
      'Téléchargez-le pour le lire ici, ou ouvrez-le sur le site.';

  /// Chapitre en attente ou en cours de téléchargement.
  static String lecteurEnTelechargement(EtatHorsLigne etat) =>
      etat.statut == StatutHorsLigne.enCours
      ? 'Téléchargement en cours (${pourcentage(etat.progression)}) : la '
            'lecture commencera dès qu\'il sera terminé.'
      : 'Chapitre en file d\'attente : la lecture commencera dès qu\'il '
            'sera téléchargé.';

  /// Chapitre texte vide.
  static const String texteVide = 'Ce chapitre ne contient pas de texte.';

  // -------------------------------------------------------- Téléchargements

  /// File vide (aide).
  static const String telechargementsVide =
      'Aucun téléchargement.\n'
      'Les chapitres des titres Favoris et Suivis sont téléchargés '
      'automatiquement (voir Paramètres). Vous pouvez aussi télécharger un '
      'chapitre depuis la fiche d\'un titre.';

  /// Bouton : retirer les terminés de la liste.
  static const String viderTermines = 'Vider les terminés';

  /// Bouton : relancer tous les échecs.
  static const String reessayerEchecs = 'Réessayer les échecs';

  /// Terminés retirés de la liste.
  static String terminesRetires(int nombre) => nombre <= 1
      ? '$nombre téléchargement terminé retiré de la liste.'
      : '$nombre téléchargements terminés retirés de la liste.';

  /// Ligne d'état d'un téléchargement de la file.
  static String statutTelechargement(Telechargement telechargement) {
    switch (telechargement.statut) {
      case StatutTelechargement.enAttente:
        return 'En attente';
      case StatutTelechargement.enCours:
        final total = telechargement.nombrePagesTotal;
        return total <= 0
            ? 'En cours…'
            : 'En cours : ${telechargement.nombrePagesFaites} / $total pages';
      case StatutTelechargement.termine:
        return 'Terminé';
      case StatutTelechargement.echec:
        final message = telechargement.messageErreur;
        return message == null || message.isEmpty
            ? 'Échec'
            : 'Échec : $message';
    }
  }

  /// Chapitre de la file qui n'existe plus.
  static String chapitreIntrouvable(int idChapitre) =>
      'Chapitre n°$idChapitre (introuvable)';

  /// Titre inconnu.
  static const String titreInconnu = 'Titre inconnu';

  // ------------------------------------------------------------- Paramètres

  /// Section des réglages de téléchargement.
  static const String sectionTelechargements = 'Téléchargements';

  /// Section des sites.
  static const String sectionSites = 'Sites';

  /// Section « À propos ».
  static const String sectionAPropos = 'À propos';

  /// Introduction des règles de téléchargement.
  static const String introReglesTelechargement =
      'Les chapitres sont téléchargés automatiquement pour la lecture '
      'hors-ligne selon les listes du titre. Un titre ni favori ni suivi '
      'n\'est jamais téléchargé automatiquement. Une seule version est '
      'gardée par numéro de chapitre, selon « Mes langues ». Un chapitre '
      'qui sort des règles est supprimé 24 heures plus tard (il est affiché '
      'en rouge d\'ici là, et vous pouvez le garder).';

  /// Nom d'une limite de téléchargement.
  static String libelleLimite(LimiteTelechargement limite) {
    switch (limite) {
      case LimiteTelechargement.favorisLusConserves:
        return 'Favoris : chapitres lus gardés';
      case LimiteTelechargement.suivisInitial:
        return 'Suivis : chapitres téléchargés au départ';
      case LimiteTelechargement.suivisAvant:
        return 'Suivis : chapitres gardés jusqu\'au dernier lu';
      case LimiteTelechargement.suivisApres:
        return 'Suivis : chapitres téléchargés après le dernier lu';
    }
  }

  /// Phrase qui explique une limite avec sa [valeur] actuelle.
  static String explicationLimite(LimiteTelechargement limite, int valeur) {
    final chapitres = valeur <= 1 ? '$valeur chapitre' : '$valeur chapitres';
    switch (limite) {
      case LimiteTelechargement.favorisLusConserves:
        return 'Pour un favori, tous les chapitres non lus sont téléchargés, '
            'et on garde aussi les $chapitres lus les plus récents.';
      case LimiteTelechargement.suivisInitial:
        return 'Pour un titre suivi dont la lecture n\'a pas commencé, les '
            'premiers chapitres sont téléchargés : $chapitres.';
      case LimiteTelechargement.suivisAvant:
        return 'Quand la lecture avance, on garde $chapitres jusqu\'au '
            'dernier lu (inclus) ; les plus anciens sont supprimés.';
      case LimiteTelechargement.suivisApres:
        return 'Quand la lecture avance, on télécharge les $chapitres qui '
            'suivent le dernier lu.';
    }
  }

  /// Info-bulle du bouton « + ».
  static const String augmenter = 'Augmenter';

  /// Info-bulle du bouton « − ».
  static const String diminuer = 'Diminuer';

  /// Remise aux valeurs par défaut.
  static const String valeursParDefaut = 'Valeurs par défaut';

  /// Bouton d'enregistrement.
  static const String enregistrer = 'Enregistrer';

  /// Annulation des modifications non enregistrées.
  static const String annulerModifications = 'Annuler les modifications';

  /// Réglages enregistrés.
  static const String reglagesEnregistres =
      'Réglages enregistrés : les téléchargements sont mis à jour.';

  /// Section des recherches de mises à jour.
  static const String sectionMisesAJour = 'Mises à jour';

  /// Libellé du nombre de recherches par jour.
  static const String verificationsParJour =
      'Recherches de nouveaux chapitres par jour';

  /// Explication du réglage.
  static const String explicationVerificationsParJour =
      'Les titres suivis sont vérifiés à heures fixes, réparties dans la '
      'journée à partir de minuit UTC. Moins de recherches ménage la batterie '
      'et les sites.';

  /// Heure « HH:MM ».
  static String formaterHeure(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  /// Énumération française : « a », « a et b », « a, b et c ».
  static String enumerer(List<String> elements) {
    if (elements.length <= 1) return elements.join();
    return '${elements.sublist(0, elements.length - 1).join(', ')} et '
        '${elements.last}';
  }

  /// Horaires des recherches en UTC et en heure locale : « 00:00 et 12:00
  /// UTC, soit 01:00 et 13:00 chez vous ». [jour] (UTC) sert au calcul de
  /// l'heure locale (heure d'été ou d'hiver du jour affiché).
  static String horairesVerifications(List<Duration> horaires, DateTime jour) {
    final minuit = DateTime.utc(jour.year, jour.month, jour.day);
    final utc = <String>[
      for (final horaire in horaires) formaterHeure(minuit.add(horaire)),
    ];
    final locales = <String>[
      for (final horaire in horaires)
        formaterHeure(minuit.add(horaire).toLocal()),
    ];
    final enUtc = '${enumerer(utc)} UTC';
    // Sur un appareil réglé en UTC, inutile de répéter les mêmes heures.
    if (minuit.toLocal().timeZoneOffset == Duration.zero) return enUtc;
    return '$enUtc, soit ${enumerer(locales)} chez vous';
  }

  /// Date et heure locales « jj/mm/aaaa à HH:MM ».
  static String formaterDateHeure(DateTime date) =>
      '${formaterDate(date)} à ${formaterHeure(date.toLocal())}';

  /// Dernière recherche de mises à jour.
  static String derniereRecherche(DateTime? date) => date == null
      ? 'Aucune recherche pour l\'instant.'
      : 'Dernière recherche : ${formaterDateHeure(date)}';

  /// Prochaine recherche programmée (ordinateur).
  static String prochaineRecherche(DateTime date) =>
      'Prochaine recherche : ${formaterDateHeure(date)}';

  /// Réglage des recherches enregistré.
  static const String planificationEnregistree =
      'Horaires des recherches enregistrés.';

  /// Aucun site configuré (section Sites).
  static const String aucunSiteParametres =
      'Aucun site configuré. Ajoutez-en un depuis l\'onglet « Sources ».';

  /// Action : modifier un site.
  static const String modifierSite = 'Modifier le site';

  /// Action : supprimer un site.
  static const String supprimerSite = 'Supprimer le site';

  /// Champ du nom d'un site (obligatoire).
  static const String champNomSiteObligatoire = 'Nom';

  /// Champ des langues d'un site.
  static const String champLangues = 'Langues propres à ce site';

  /// Aide du champ des langues.
  static const String aideLangues =
      "Laissez vide pour suivre « Mes langues » (conseillé). Sinon, codes "
      "par ordre de préférence : « fr,en » = français en priorité ; si un "
      "chapitre sort d'abord en anglais, il est téléchargé puis remplacé par "
      "la version française à sa sortie.";

  /// Titre repliable du réglage avancé des langues d'un site.
  static const String reglageAvanceLangues = 'Réglage avancé : langues du site';

  /// Langues mal saisies.
  static const String erreurLangues =
      'Codes à deux lettres séparés par des virgules (par ex. fr,en).';

  /// Interrupteur d'activation d'un site.
  static const String siteActif = 'Rechercher les nouveaux chapitres';

  /// Aide de l'interrupteur d'activation.
  static const String aideSiteActif =
      'Désactivé : les titres de ce site restent dans la bibliothèque mais '
      'ne sont plus vérifiés.';

  /// Langues d'un site dans la liste.
  static String languesSite(String langues) => langues.isEmpty
      ? 'Langues : celles de « Mes langues »'
      : 'Langues propres au site : '
            '${langues.toUpperCase().replaceAll(',', ', ')}';

  /// Site modifié.
  static String siteModifie(String nom) => 'Site « $nom » modifié.';

  /// Site supprimé.
  static String siteSupprime(String nom) => 'Site « $nom » supprimé.';

  /// Question avant la suppression d'un site.
  static String confirmationSuppressionSite(String nom) =>
      'Supprimer le site « $nom » ?\n'
      'Ses réglages seront perdus ; il pourra être ajouté de nouveau.';

  /// Crédit complet de MangaDex (PLAYBOOK.md section 6).
  static const String creditMangaDexComplet =
      'Données et images fournies par MangaDex et ses groupes de traduction.';

  /// Présentation de l'application.
  static const String descriptionApplication =
      'Application personnelle, sans publicité, qui regroupe les titres '
      'suivis sur plusieurs sites de lecture.';

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
