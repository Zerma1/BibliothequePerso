/// Tous les textes affichés par l'interface, en français (PLAYBOOK.md
/// section 8). Les regrouper ici facilitera une traduction future.
library;

import '../etat/description_erreur.dart';
import '../etat/etat_bibliotheque.dart' show EtatFiltreCategorie;
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
      'Appuyez sur « Ajouter un titre » et collez l\'adresse d\'un manga '
      'MangaDex pour commencer.';

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
      case TypeSource.scanManga:
        return 'Scan-Manga (lecture sur le site)';
      case TypeSource.webtoons:
        return 'WEBTOON (lecture sur le site)';
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
  static const String aideLangue = 'Code de langue : fr, en, ja, pt-br…';

  /// Langue mal saisie.
  static const String erreurLangue =
      'Code de langue attendu (par ex. fr ou pt-br).';

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
      'téléchargé propose de le télécharger ou de l\'ouvrir sur le site. '
      'Un chapitre publié sur un site externe se lit sur ce site.';

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
      case StatutHorsLigne.externe:
        return 'Sur un site externe (à lire sur ce site)';
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
      case StatutHorsLigne.externe:
        return "Sur un site externe — appuyer pour l'ouvrir sur ce site";
    }
  }

  // ------------------------------------- Chapitres sur un site externe (R4)

  /// Action : lire un chapitre externe sur le site de l'éditeur.
  static String lireSur(String site) => 'Lire sur $site';

  /// Mention sous le nom d'un chapitre externe.
  static String publieSur(String site) =>
      'Publié sur $site (non téléchargeable)';

  /// Lecteur ouvert sur un chapitre externe.
  static String lecteurChapitreExterne(String site) =>
      "Ce chapitre est publié sur $site : il se lit uniquement sur ce site, "
      "il n'est jamais téléchargé.";

  /// Fin d'un chapitre : le ou les chapitres suivants sont sur un site
  /// externe (le bouton « Chapitre suivant » les saute).
  static String chapitresExternesSuivants(int nombre, String site) =>
      nombre <= 1
      ? 'Le chapitre suivant est publié sur $site.'
      : 'Les $nombre chapitres suivants sont publiés sur $site.';

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
  static const String sectionTelechargements =
      'Téléchargements et conservation';

  /// Résumé de la section des téléchargements quand des valeurs ont été
  /// changées sans être enregistrées.
  static const String modificationsNonEnregistrees =
      'Modifications non enregistrées';

  /// Résumé de la section des téléchargements, visible section repliée.
  static const String resumeTelechargements =
      "Chapitres téléchargés d'avance et chapitres gardés après lecture";

  /// Section des sites.
  static const String sectionSites = 'Sites';

  /// Nombre de sites configurés (résumé de la section Sites).
  static String nombreSites(int nombre) => switch (nombre) {
    0 => 'Aucun site configuré',
    1 => '1 site configuré',
    _ => '$nombre sites configurés',
  };

  /// Section « À propos ».
  static const String sectionAPropos = 'À propos';

  /// Section « Sauvegarde et export ».
  static const String sectionSauvegardeExport = 'Sauvegarde et export';

  /// Résumé de la section « Sauvegarde et export ».
  static const String resumeSauvegardeExport =
      'Exporter ou réimporter vos titres et vos sites';

  /// Explication de l'export.
  static const String explicationExport =
      "Enregistre la liste de vos titres et de vos sites dans deux fichiers : "
      "un fichier JSON complet (que « Importer un export » sait relire, par "
      "exemple sur un autre appareil) et un fichier Markdown lisible, avec "
      "des liens cliquables.";

  /// Bouton de l'export.
  static const String exporterTitresEtSites =
      'Exporter mes titres et mes sites';

  /// Titre de la boîte affichée après un export réussi.
  static const String exportEnregistre = 'Export enregistré';

  /// Bouton et titre du dialogue d'import d'un export.
  static const String importerUnExport = 'Importer un export';

  /// Explication en tête du dialogue d'import.
  static const String explicationImport =
      "Choisissez un export (fichier JSON) : ses titres, sites et listes sont "
      "ajoutés à votre bibliothèque. Rien n'est supprimé ni remplacé, et un "
      "titre déjà présent n'est pas ajouté deux fois.";

  /// Intertitre de la liste des exports trouvés.
  static const String exportsTrouves = 'Exports trouvés';

  /// Aucun export trouvé dans le dossier des exports.
  static const String aucunExportTrouve =
      "Aucun export trouvé dans le dossier des exports. Collez le chemin "
      "d'un fichier ci-dessous.";

  /// Champ du chemin d'un fichier à importer.
  static const String champCheminImport = 'Chemin du fichier JSON';

  /// Aide du champ du chemin.
  static const String aideCheminImport =
      r'Par exemple : C:\Users\moi\Documents\export.json';

  /// Bouton qui lance l'import.
  static const String importer = 'Importer';

  /// Message pendant l'import.
  static const String importEnCours = 'Import en cours…';

  /// Titre de la boîte affichée après un import.
  static const String importTermine = 'Import terminé';

  /// Intertitre des lignes non importées.
  static String erreursImport(int nombre) => nombre <= 1
      ? '$nombre ligne non importée :'
      : '$nombre lignes non importées :';

  /// Contenu d'un export réussi.
  static String resumeExport(int titres, int sites) =>
      "${titres <= 1 ? '$titres titre' : '$titres titres'} et "
      "${sites <= 1 ? '$sites site' : '$sites sites'} exportés.";

  /// Libellé du chemin du fichier JSON.
  static const String fichierJson = 'Fichier JSON (complet) :';

  /// Libellé du chemin du fichier Markdown.
  static const String fichierMarkdown = 'Fichier Markdown (lisible) :';

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

  /// Section des recherches de mises à jour (Paramètres).
  static const String sectionMisesAJour = 'Recherche des nouveaux chapitres';

  /// Résumé de la section des recherches, visible section repliée.
  static String resumeRecherches(int nombre) => nombre <= 1
      ? '$nombre recherche par jour'
      : '$nombre recherches par jour';

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
      'Codes de langue séparés par des virgules (par ex. fr,en ou pt-br).';

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

  // ------------------------------------------------- Étape 6 : Mises à jour

  /// Onglet des dernières parutions.
  static const String ongletMisesAJour = 'Mises à jour';

  /// Libellé accessible du badge de l'onglet Mises à jour.
  static String titresAvecNouveaute(int nombre) => nombre <= 1
      ? '$nombre titre avec un chapitre non lu'
      : '$nombre titres avec un chapitre non lu';

  /// Explication en haut de l'onglet Mises à jour.
  static const String explicationMisesAJour =
      'Titres favoris, suivis et en attente, du plus récemment paru au plus '
      'ancien, dans les langues de chaque titre. « Nouveau » : dernier '
      'chapitre non lu, paru depuis moins de 30 jours.';

  /// Onglet Mises à jour vide.
  static const String misesAJourVide =
      'Aucun titre favori ou suivi pour l\'instant.\n'
      'Rangez des titres dans « Favoris » ou « Suivis » pour voir ici leurs '
      'dernières parutions.';

  /// Intertitre des titres sans aucun chapitre dans leurs langues.
  static const String sectionSansParution = 'Aucun chapitre dans vos langues';

  /// Badge d'un dernier chapitre paru et pas encore lu.
  static const String nouveau = 'Nouveau';

  /// Mention d'un titre de la liste « En attente ».
  static const String enAttente = 'En attente';

  /// Dernier chapitre paru : « Chapitre 12 · FR · aujourd'hui ».
  static String dernierChapitreParu(
    String nomChapitre,
    String langue,
    DateTime date,
    DateTime maintenant,
  ) {
    final morceaux = <String>[
      nomChapitre,
      if (langue.isNotEmpty) langue.toUpperCase(),
      dateRelative(date, maintenant),
    ];
    return morceaux.join(' · ');
  }

  /// Titre sans chapitre dans ses langues.
  static String aucuneParution(List<String> langues) {
    final noms = <String>[
      for (final code in langues) nomLangue(code).toLowerCase(),
    ];
    if (noms.isEmpty) return 'Pas encore de chapitre dans vos langues';
    final liste = noms.length == 1
        ? noms.single
        : '${noms.sublist(0, noms.length - 1).join(', ')} ou ${noms.last}';
    return 'Pas encore de chapitre en $liste';
  }

  /// Date relative : « aujourd'hui », « hier », « il y a 3 jours », puis la
  /// date au-delà d'une semaine (jours comptés en heure locale).
  static String dateRelative(DateTime date, DateTime maintenant) {
    final locale = date.toLocal();
    final aujourdhui = maintenant.toLocal();
    final jourDate = DateTime(locale.year, locale.month, locale.day);
    final jourActuel = DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day,
    );
    final ecart = jourActuel.difference(jourDate).inDays;
    if (ecart <= 0) return "aujourd'hui";
    if (ecart == 1) return 'hier';
    if (ecart < 7) return 'il y a $ecart jours';
    return formaterDate(date);
  }

  // ------------------------------------------ Étape 6 : filtres et listes

  /// Titre du panneau des catégories et info-bulle de l'entonnoir.
  static const String filtrerParCategories = 'Filtrer par catégories';

  /// Libellé accessible de l'entonnoir avec des catégories filtrées.
  static String filtreCategoriesActif(int nombre) => nombre <= 1
      ? 'Filtrer par catégories ($nombre catégorie filtrée)'
      : 'Filtrer par catégories ($nombre catégories filtrées)';

  /// Mode d'emploi des puces à trois états.
  static const String aideTroisEtats =
      'Touchez une catégorie pour l\'inclure (+), touchez-la encore pour '
      'l\'exclure (−), une troisième fois pour l\'ignorer. Sont affichés les '
      'titres qui ont toutes les catégories incluses et aucune des '
      'catégories exclues.';

  /// État d'une catégorie (info-bulle de sa puce).
  static String etatFiltreCategorie(EtatFiltreCategorie etat) {
    switch (etat) {
      case EtatFiltreCategorie.neutre:
        return 'Ignorée — toucher pour l\'inclure';
      case EtatFiltreCategorie.incluse:
        return 'Incluse — toucher pour l\'exclure';
      case EtatFiltreCategorie.exclue:
        return 'Exclue — toucher pour l\'ignorer';
    }
  }

  /// Résumé du brouillon du panneau.
  static String resumeFiltreCategories(int incluses, int exclues) {
    if (incluses == 0 && exclues == 0) return 'Aucun filtre de catégorie.';
    String compte(int nombre, String singulier, String pluriel) =>
        nombre <= 1 ? '$nombre $singulier' : '$nombre $pluriel';
    return '${compte(incluses, 'incluse', 'incluses')}, '
        '${compte(exclues, 'exclue', 'exclues')}.';
  }

  /// Bouton : appliquer le filtre du panneau.
  static const String appliquer = 'Appliquer';

  /// Champ de recherche du panneau des catégories.
  static const String rechercherCategorie = 'Rechercher une catégorie';

  /// Bouton : remettre toutes les catégories à « ignorée ».
  static const String effacerCategories = 'Tout effacer';

  /// Aucune catégorie ne correspond à la recherche.
  static const String aucuneCategorieTrouvee = 'Aucune catégorie trouvée.';

  /// Aucune catégorie connue.
  static const String aucuneCategorieConnue =
      'Aucune catégorie pour l\'instant : elles viennent des sites quand '
      'vous ajoutez des titres.';

  /// Bouton de fermeture du panneau, avec le nombre de titres affichés.
  static String afficherTitres(int nombre) =>
      nombre <= 1 ? 'Afficher $nombre titre' : 'Afficher $nombre titres';

  /// Bouton du filtre de niveau de contenu.
  static const String boutonContenu = 'Contenu';

  /// Titre du réglage des niveaux de contenu.
  static const String niveauxContenu = 'Niveau de contenu';

  /// Explication des niveaux de contenu.
  static const String explicationNiveauxContenu =
      'Niveaux affichés dans la bibliothèque et demandés à MangaDex lors '
      'd\'une recherche. Les titres des sites qui n\'indiquent pas de niveau '
      'restent toujours affichés.';

  /// Bouton : niveaux de contenu par défaut.
  static const String niveauxParDefaut =
      'Par défaut (tout sauf pornographique)';

  /// Nom affiché d'un niveau de contenu MangaDex.
  static String libelleNiveauContenu(String niveau) {
    switch (niveau) {
      case 'safe':
        return 'Tous publics';
      case 'suggestive':
        return 'Suggestif';
      case 'erotica':
        return 'Érotique';
      case 'pornographic':
        return 'Pornographique';
      default:
        return niveau;
    }
  }

  /// Info-bulle d'une liste tenue automatiquement (« En attente »).
  static const String listeAutomatique =
      'Liste automatique : un titre y entre quand il n\'a aucun chapitre '
      'dans vos langues, et en sort dès qu\'un chapitre paraît.';

  /// Confirmation de l'ajout d'un titre placé dans « En attente ».
  static String titreAjouteEnAttente(String nom) =>
      '« $nom » ajouté. Aucun chapitre dans vos langues pour l\'instant : '
      'il est placé dans « En attente » et vérifié plus souvent.';

  // ------------------------------------------------- Étape 6 : couvertures

  /// Bouton : changer la couverture d'un titre.
  static const String changerCouverture = 'Changer la couverture';

  /// Titre du dialogue de choix de la couverture.
  static const String choisirCouverture = 'Choisir la couverture';

  /// Intertitre des couvertures proposées par le site.
  static const String couverturesDuSite = 'Couvertures proposées par le site';

  /// Le site ne propose qu'une couverture.
  static const String aucuneCouvertureSite =
      'Le site ne propose pas d\'autre couverture pour ce titre.';

  /// Légende d'une couverture du site : « Vol. 3 · JA ».
  static String legendeCouverture(String? volume, String? langue) {
    final morceaux = <String>[
      volume == null || volume.isEmpty ? 'Sans volume' : 'Vol. $volume',
      if (langue != null && langue.isNotEmpty) langue.toUpperCase(),
    ];
    return morceaux.join(' · ');
  }

  /// Mention de la couverture actuelle dans la liste de choix.
  static const String couvertureActuelle = 'Actuelle';

  /// Intertitre du choix d'une image de l'appareil.
  static const String imageDeLAppareil = 'Image de l\'appareil';

  /// Champ du chemin d'une image de l'appareil.
  static const String champCheminImage = 'Chemin complet de l\'image';

  /// Aide du champ du chemin d'une image.
  static const String aideCheminImage =
      'Fichier JPG, PNG ou WebP. Une copie est gardée avec le titre.';

  /// Bouton : utiliser l'image de l'appareil.
  static const String utiliserImage = 'Utiliser cette image';

  /// Bouton : revenir à la couverture fournie par le site.
  static const String revenirCouvertureSite = 'Revenir à la couverture du site';

  /// Couverture changée.
  static const String couvertureChangee = 'Couverture changée.';

  // ---------------------------------------------- Étape 6 : rapport d'erreur

  /// Bouton : exporter le rapport d'erreur.
  static const String exporterRapport = 'Exporter le rapport d\'erreur';

  /// Titre du dialogue après l'export.
  static const String rapportEnregistre = 'Rapport d\'erreur enregistré';

  /// Explication du rapport exporté.
  static const String explicationRapport =
      'Le rapport est enregistré dans le fichier ci-dessous. Il ne contient '
      'pas de données personnelles (adresses e-mail, jetons et adresses IP '
      'sont masqués) : vous pouvez l\'envoyer pour faire analyser le site.';

  /// Bouton : ouvrir le dossier des rapports.
  static const String ouvrirDossier = 'Ouvrir le dossier';

  /// Bouton de fermeture d'un dialogue.
  static const String fermer = 'Fermer';

  /// Action décrite dans le rapport : ajout d'un site.
  static const String actionRapportAjoutSite = 'Ajout d\'un site';

  /// Action décrite dans le rapport : ajout d'un titre.
  static const String actionRapportAjoutTitre = 'Ajout d\'un titre';

  // ---------------------------------------- Étape 6 : téléchargements

  /// Intertitre des suppressions prévues (onglet Téléchargements).
  static String sectionSuppressionsPrevues(int nombre) =>
      'Suppressions prévues ($nombre)';

  /// Explication des suppressions prévues.
  static const String explicationSuppressionsPrevues =
      'Ces chapitres ne font plus partie de vos règles de téléchargement : '
      'ils seront supprimés à la fin du compte à rebours, sauf si vous les '
      'gardez.';

  /// Intertitre de la file de téléchargement.
  static const String sectionFile = 'File de téléchargement';

  /// File vide alors que des suppressions sont prévues.
  static const String fileVide = 'La file de téléchargement est vide.';

  /// Repère d'un chapitre gardé.
  static const String garde = 'Gardé';

  /// Info-bulle du repère « gardé ».
  static const String infoGarde =
      'Gardé : ce chapitre ne sera jamais supprimé automatiquement.';

  /// Bouton : ne plus garder un chapitre.
  static const String nePlusGarder = 'Ne plus garder';

  /// Garde retirée.
  static const String gardeRetiree =
      'Le chapitre suit de nouveau vos règles de téléchargement.';

  // ------------------------------------- Étape 6 : surveillance « En attente »

  /// Libellé de l'écart des vérifications des titres en attente.
  static const String heuresEnAttente =
      'Titres « En attente » vérifiés toutes les';

  /// Écart en heures.
  static String valeurHeures(int heures) => '$heures h';

  /// Explication de la surveillance des titres en attente.
  static const String explicationHeuresEnAttente =
      'Les titres favoris, suivis ou planifiés qui n\'ont encore aucun '
      'chapitre dans vos langues sont vérifiés plus souvent (à chaque heure '
      'pleine par défaut), pour ne pas rater leur premier chapitre. Les '
      'titres seulement « Planifiés » ne déclenchent jamais de notification.';

  /// Réglage de la surveillance enregistré.
  static const String surveillanceEnregistree =
      'Surveillance des titres en attente enregistrée.';

  // ---------------------------------- Étape 8 : plusieurs sites par titre

  /// Intertitre de la section « Sites » de la fiche.
  static const String sitesDuTitre = 'Sites';

  /// En-tête de la section « Sites » repliable, avec le nombre de sites.
  static String sitesDuTitreAvecNombre(int nombre) => '$sitesDuTitre ($nombre)';

  /// Résumé de la section « Sites » : le site principal.
  static String resumeSitesDuTitre(String sitePrincipal) =>
      'Site principal : $sitePrincipal';

  /// Explication de la section « Sites ».
  static const String explicationSitesDuTitre =
      "Le site principal fournit la fiche (couverture, résumé, catégories). "
      "Les autres sites ajoutent leurs chapitres : pour chaque numéro, "
      "l'application télécharge une seule version (votre langue d'abord, "
      "puis une version lisible dans l'application, puis le site principal).";

  /// Pastille du site principal.
  static const String sitePrincipal = 'Principal';

  /// Pastille d'un site secondaire.
  static const String siteSecondaire = 'Secondaire';

  /// Nombre de chapitres connus d'un site.
  static String chapitresDuSite(int nombre) => switch (nombre) {
    0 => 'aucun chapitre',
    1 => '1 chapitre',
    _ => '$nombre chapitres',
  };

  /// Bouton : ajouter un autre site au titre.
  static const String ajouterAutreSite = 'Ajouter un autre site';

  /// Bouton : ouvrir la page du titre sur ce site.
  static const String ouvrirCeSite = 'Ouvrir ce site';

  /// Bouton : retirer un site secondaire.
  static const String retirerSite = 'Retirer';

  /// Bouton : faire d'un site secondaire le site principal.
  static const String definirSitePrincipal = 'Définir comme site principal';

  /// Explication du dialogue d'ajout d'un site.
  static String explicationAjoutSite(String nomTitre) =>
      "Collez l'adresse de « $nomTitre » sur un autre site (la page du "
      "titre, pas celle d'un chapitre). Le site doit être configuré dans "
      "« Sources », sauf MangaDex et Scan-Manga, reconnus automatiquement.";

  /// Champ de l'adresse du titre sur l'autre site.
  static const String champUrlAutreSite = 'Adresse du titre sur l\'autre site';

  /// Lecture de l'autre site en cours.
  static const String ajoutSiteEnCours =
      'Lecture du site… (une requête par seconde au plus)';

  /// Action décrite dans le rapport d'erreur.
  static const String actionRapportAjoutSiteAuTitre =
      "Ajout d'un autre site à un titre";

  /// Site ajouté au titre.
  static String siteAjouteAuTitre(int nombreChapitres) =>
      'Site ajouté (${chapitresDuSite(nombreChapitres)}).';

  /// Titre de la confirmation du retrait d'un site.
  static String titreRetraitSite(String nomSite) => 'Retirer « $nomSite » ?';

  /// Confirmation du retrait d'un site secondaire.
  static String confirmationRetraitSite({
    required int nombreNonLusRetires,
    required int nombreTelecharges,
  }) {
    final retires = switch (nombreNonLusRetires) {
      0 => 'Aucun chapitre non lu ne sera retiré.',
      1 => '1 chapitre non lu de ce site sera retiré.',
      _ => '$nombreNonLusRetires chapitres non lus de ce site seront retirés.',
    };
    final telecharges = switch (nombreTelecharges) {
      0 => '',
      1 =>
        "\n\nLe chapitre téléchargé depuis ce site passera au rouge : son "
            "archive sera supprimée dans 24 heures, sauf si vous le gardez.",
      _ =>
        "\n\nLes $nombreTelecharges chapitres téléchargés depuis ce site "
            "passeront au rouge : leurs archives seront supprimées dans 24 "
            "heures, sauf si vous les gardez.",
    };
    return '$retires Les chapitres lus restent dans votre historique.'
        '$telecharges';
  }

  /// Site retiré.
  static String siteRetire(int nombreChapitres) => switch (nombreChapitres) {
    0 => 'Site retiré.',
    1 => 'Site retiré (1 chapitre retiré).',
    _ => 'Site retiré ($nombreChapitres chapitres retirés).',
  };

  /// Titre de la confirmation du changement de site principal.
  static String titreChangementPrincipal(String nomSite) =>
      '« $nomSite » comme site principal ?';

  /// Explication du changement de site principal.
  static const String explicationChangementPrincipal =
      "La fiche (nom, couverture, résumé, catégories) sera relue sur ce site. "
      "L'ancien site principal devient secondaire et garde ses chapitres.";

  /// Bouton de confirmation du changement de site principal.
  static const String confirmerPrincipal = 'Changer';

  /// Site principal changé.
  static String sitePrincipalChange(String nomSite) =>
      '« $nomSite » est maintenant le site principal.';

  /// Filtre des chapitres : tous les sites.
  static const String tousLesSites = 'Tous les sites';

  /// Étiquette du filtre des chapitres par site.
  static const String filtreSite = 'Site des chapitres';

  /// Légende : le nom du site sous chaque chapitre.
  static const String legendeSiteChapitre =
      'Sous chaque chapitre : le site d\'où il vient.';

  /// Chapitre venant d'un site (sous son nom).
  static String chapitreDuSite(String nomSite) => 'Site : $nomSite';

  /// Actualisation dont certains sites n'ont pas répondu.
  static String actualisationSitesSansReponse(
    int nombreNouveaux,
    List<String> nomsSites,
  ) {
    final debut = actualisationTerminee(nombreNouveaux);
    final noms = nomsSites.map((nom) => '« $nom »').join(', ');
    return nomsSites.length == 1
        ? "$debut Le site $noms n'a pas répondu ; réessayez plus tard."
        : "$debut Ces sites n'ont pas répondu : $noms ; réessayez plus tard.";
  }

  /// Ajout d'un titre déjà présent par l'adresse d'un de ses sites.
  static const String titreDejaPresent =
      'Ce titre est déjà dans votre bibliothèque.';

  // ------------------------------------------ Liens seuls (tâche T4)

  /// Pastille d'un site gardé comme simple lien.
  static const String lienSeul = 'lien seul';

  /// Sous-titre d'un lien seul dans la section « Sites ».
  static const String explicationLigneLienSeul =
      "Aucun chapitre lu ici : ce site s'ouvre dans votre navigateur.";

  /// Bouton : ouvrir un lien seul dans le navigateur.
  static const String ouvrirDansNavigateur = 'Ouvrir dans le navigateur';

  /// Bouton : essayer de lire un lien seul.
  static const String essayerDeLire = 'Essayer de le lire';

  /// Bouton : passer un site lu en lien seul.
  static const String passerEnLienSeul = 'Garder comme simple lien';

  /// Bouton du dialogue d'ajout : enregistrer l'adresse comme lien seul.
  static const String ajouterCommeLienSeul =
      'Ajouter quand même comme simple lien';

  /// Explication sous le bouton « Ajouter quand même comme simple lien ».
  static const String explicationAjoutLienSeul =
      "L'application ne pourra lire aucun chapitre sur ce site. Il sera "
      "enregistré avec ce titre, et un bouton l'ouvrira dans votre "
      'navigateur.';

  /// Lien seul ajouté.
  static const String lienSeulAjoute =
      'Site ajouté comme simple lien (ouvert dans le navigateur).';

  /// Titre de la confirmation du passage en lien seul.
  static String titrePassageLienSeul(String nomSite) =>
      '« $nomSite » comme simple lien ?';

  /// Confirmation du passage d'un site lu en lien seul.
  static String confirmationPassageLienSeul({
    required int nombreNonLusRetires,
    required int nombreTelecharges,
  }) {
    final debut =
        "L'application ne lira plus ce site : il s'ouvrira seulement dans "
        'votre navigateur. ';
    final chapitres = switch (nombreNonLusRetires) {
      0 => 'Aucun chapitre non lu de ce site ne sera retiré.',
      1 => '1 chapitre non lu de ce site sera retiré.',
      _ => '$nombreNonLusRetires chapitres non lus de ce site seront retirés.',
    };
    final lus = ' Les chapitres lus restent.';
    final telecharges = switch (nombreTelecharges) {
      0 => '',
      1 =>
        "\n\nLe chapitre téléchargé depuis ce site passera au rouge : son "
            'archive sera supprimée dans 24 heures, sauf si vous la gardez.',
      _ =>
        "\n\nLes $nombreTelecharges chapitres téléchargés depuis ce site "
            'passeront au rouge : leurs archives seront supprimées dans 24 '
            'heures, sauf si vous les gardez.',
    };
    return '$debut$chapitres$lus$telecharges';
  }

  /// Site passé en lien seul.
  static String sitePasseEnLienSeul(int nombreChapitres) =>
      switch (nombreChapitres) {
        0 => 'Site gardé comme simple lien.',
        1 => 'Site gardé comme simple lien (1 chapitre retiré).',
        _ =>
          'Site gardé comme simple lien ($nombreChapitres chapitres '
              'retirés).',
      };

  /// Lien seul relu avec succès.
  static String lienSeulLu(int nombreChapitres) =>
      'Le site est maintenant lu (${chapitresDuSite(nombreChapitres)}).';

  /// Lien seul toujours illisible.
  static String lienSeulToujoursIllisible(String message) =>
      "Ce site n'est toujours pas lisible : il reste un simple lien. $message";

  // ------------------------------- Critères de lecture (tâche T3)

  /// Bouton / intertitre du diagnostic d'un site refusé.
  static const String pourquoiIllisible =
      "Pourquoi ce site n'est pas lisible ?";

  /// Diagnostic en cours.
  static const String diagnosticEnCours =
      'Analyse de la page… (une seule requête au site)';

  /// Diagnostic : la page est lisible.
  static const String diagnosticLisible =
      "D'après l'analyse, cette page respecte les critères de lecture. "
      "L'échec vient peut-être d'une autre page (liste des chapitres, "
      "chapitre) ou du site lui-même : exportez le rapport d'erreur.";

  /// Intertitre des raisons du diagnostic.
  static const String raisonsIllisible = 'Raisons :';

  /// Intertitre des remarques du diagnostic.
  static const String remarquesDiagnostic = 'Remarques :';

  /// Explication d'une protection anti-robot.
  static const String explicationProtectionAntiRobot =
      'Protection anti-robot : le site bloque les programmes automatiques ; '
      "l'application ne contourne jamais ces protections. Lisez ce site dans "
      'votre navigateur, ou gardez-le comme simple lien.';

  /// Diagnostic impossible.
  static String diagnosticImpossible(String message) =>
      "L'analyse n'a pas pu être faite. $message";

  /// Intertitre repliable de l'aide « Critères de lecture ».
  static const String criteresLecture = 'Critères de lecture';

  /// Aide « Critères de lecture » de l'écran d'ajout de site.
  static const String aideCriteresLecture =
      "Pour qu'un site soit lu par l'application :\n"
      '• les liens des chapitres sont explicites (« chapter-12 », '
      '« chapitre-3 », « episode-5 » dans leur adresse ou leur texte) ;\n'
      '• les pages des chapitres sont des images en clair (pas dessinées par '
      'un script ni brouillées) ;\n'
      '• pas de protection anti-robot (« Just a moment… ») : '
      "l'application ne la contourne jamais.\n"
      "Collez la page qui liste les chapitres, ou l'adresse d'un chapitre : "
      "l'application remontera à la liste.";

  /// Intertitre repliable des réglages avancés d'un site générique.
  static const String reglagesAvancesSelecteurs =
      'Réglages avancés (sélecteurs CSS)';

  /// Explication des réglages avancés.
  static const String explicationReglagesSelecteurs =
      'Facultatif, pour un site de type générique seulement. Laissez vide '
      "pour que l'application devine. Un sélecteur CSS désigne un élément "
      'de la page (ex. « h1.titre », « .liste-chapitres a »).';

  // Libellés des réglages et messages d'erreur : fournis par le service
  // (`ServiceAjoutSite.libellesReglagesGeneriques`), via `EtatSources`.

  // ------------------------------------------------ Catégories regroupées

  /// Autres noms d'un groupe (info-bulle d'une puce du filtre).
  static String aussiAppelee(String autres) => 'Aussi appelée : $autres';

  /// Titre de la section des Paramètres.
  static const String sectionCategoriesRegroupees = 'Catégories regroupées';

  /// Résumé de la section repliée.
  static String resumeCategoriesRegroupees(int groupes, int suggestions) {
    final debut = groupes == 0
        ? 'Aucun groupe'
        : (groupes == 1 ? '1 groupe' : '$groupes groupes');
    if (suggestions == 0) return debut;
    return suggestions == 1
        ? '$debut, 1 suggestion'
        : '$debut, $suggestions suggestions';
  }

  /// Explication en tête de la section.
  static const String explicationCategoriesRegroupees =
      'Les sites donnent parfois la même catégorie sous plusieurs noms '
      '(« Survival », « Survie »). Regroupées, elles ne forment plus qu\'une '
      'catégorie dans les filtres et sur les fiches, au nom de la référence. '
      'Les catégories données par les sites ne sont pas modifiées.';

  /// Intertitre : groupes existants.
  static const String intertitreGroupes = 'Groupes';

  /// Aucun groupe.
  static const String aucunGroupe = 'Aucun groupe pour l\'instant.';

  /// Libellé de la référence d'un groupe.
  static const String referenceDuGroupe = 'Référence';

  /// Catégories rattachées à la référence.
  static String rattacheesAuGroupe(String noms) => 'Regroupe : $noms';

  /// Info-bulle : retirer une catégorie de son groupe.
  static String detacherCategorie(String nom) => 'Retirer « $nom » du groupe';

  /// Bouton : défaire un groupe.
  static const String defaireGroupe = 'Défaire le groupe';

  /// Confirmation avant de défaire un groupe.
  static String confirmationDefaireGroupe(String reference) =>
      'Les catégories du groupe « $reference » redeviendront séparées dans '
      'les filtres et sur les fiches.';

  /// Bouton de confirmation : défaire.
  static const String defaire = 'Défaire';

  /// Message après le retrait d'une catégorie.
  static String categorieDetachee(String nom) =>
      '« $nom » ne fait plus partie du groupe.';

  /// Message après la dissolution d'un groupe.
  static String groupeDefait(String reference) =>
      'Groupe « $reference » défait.';

  /// Bouton et titre du dialogue de regroupement manuel.
  static const String regrouperDesCategories = 'Regrouper des catégories';

  /// Il faut au moins deux catégories pour regrouper.
  static const String pasAssezDeCategories =
      'Il faut au moins deux catégories pour en regrouper.';

  /// Première étape du dialogue : choix de la référence.
  static const String choisirReference =
      '1. Choisissez la catégorie de référence : son nom représentera le '
      'groupe.';

  /// Deuxième étape du dialogue : catégories à rattacher.
  static String choisirARattacher(String reference) =>
      '2. Cochez les catégories de même sens à rattacher à « $reference ».';

  /// Bouton : revenir au choix de la référence.
  static const String changerReference = 'Changer de référence';

  /// Catégorie déjà dans un autre groupe (elle en changera).
  static String dansLeGroupe(String reference) =>
      'Actuellement dans le groupe « $reference »';

  /// Bouton de validation du regroupement manuel.
  static String regrouperNombre(int nombre) => 'Regrouper ($nombre)';

  /// Message après un regroupement.
  static String categoriesRegroupees(String reference, int nombre) =>
      nombre <= 1
      ? '1 catégorie rattachée à « $reference ».'
      : '$nombre catégories rattachées à « $reference ».';

  /// Intertitre : suggestions.
  static const String intertitreSuggestions = 'Suggestions';

  /// Explication des suggestions.
  static const String explicationSuggestions =
      'Catégories qui semblent avoir le même sens (traduction ou écriture '
      'proche). Rien n\'est regroupé sans votre accord.';

  /// Aucune suggestion.
  static const String aucuneSuggestion = 'Aucune suggestion pour l\'instant.';

  /// Une suggestion : catégories à rattacher à la référence.
  static String suggestion(String reference, String autres) =>
      'Rattacher $autres à « $reference »';

  /// Bouton : appliquer une suggestion.
  static const String regrouper = 'Regrouper';

  /// Bouton : écarter une suggestion pour la session.
  static const String ignorer = 'Ignorer';

  // ------------------------------------------------- Dossier des chapitres

  /// Titre de la section des Paramètres.
  static const String sectionDossierChapitres = 'Dossier des chapitres';

  /// Explication en tête de la section.
  static const String explicationDossierChapitres =
      'Les chapitres téléchargés sont rangés dans ce dossier. Vous pouvez '
      'en choisir un autre : un dossier de cet appareil, un lecteur réseau '
      '(Z:\\Mangas) ou un partage de votre NAS (\\\\nas\\partage\\Mangas). '
      'Les rapports d\'erreur et les exports restent dans le dossier de '
      'l\'application.';

  /// Intitulé du dossier utilisé pendant cette session.
  static const String dossierActuel = 'Dossier actuel';

  /// Précision : dossier par défaut de l'application.
  static const String dossierParDefautApplication =
      'Dossier par défaut de l\'application';

  /// Précision : dossier choisi par le client.
  static const String dossierChoisiParVous = 'Dossier choisi par vous';

  /// Dossier qui sera utilisé au prochain démarrage.
  static String dossierAuProchainDemarrage(String chemin) =>
      'Au prochain démarrage : $chemin';

  /// Bouton et titre du dialogue de changement de dossier.
  static const String changerDeDossier = 'Changer de dossier';

  /// Libellé du champ du chemin.
  static const String champNouveauDossier = 'Nouveau dossier';

  /// Exemple sous le champ du chemin.
  static const String aideNouveauDossier =
      r'D:\Mangas, Z:\Mangas ou \\nas\partage\Mangas';

  /// Explication en tête du dialogue.
  static const String explicationChangementDossier =
      'Collez le chemin complet du dossier. Il est créé s\'il n\'existe pas, '
      'puis l\'application vérifie qu\'elle peut y écrire.';

  /// Case : déplacer les chapitres déjà téléchargés.
  static const String deplacerChapitresTelecharges =
      'Déplacer les chapitres déjà téléchargés';

  /// Explication de la case cochée.
  static const String explicationDeplacerCoche =
      'Les chapitres et les couvertures sont déplacés vers le nouveau '
      'dossier. Cela peut prendre du temps sur un NAS.';

  /// Explication de la case décochée.
  static const String explicationDeplacerDecoche =
      'Les chapitres déjà téléchargés restent dans l\'ancien dossier : ceux '
      'que vos règles demandent seront retéléchargés dans le nouveau.';

  /// Bouton de validation du changement.
  static const String changer = 'Changer';

  /// Bouton : revenir au dossier par défaut.
  static const String revenirDossierParDefaut = 'Revenir au dossier par défaut';

  /// Chemin du dossier par défaut, sous le bouton.
  static String cheminDossierParDefaut(String chemin) =>
      'Dossier par défaut : $chemin';

  /// Pendant le déplacement : boîte non fermable.
  static const String deplacementEnCours =
      'Déplacement des chapitres en cours. Ne fermez pas l\'application.';

  /// Pendant un changement sans déplacement (vérification du dossier).
  static const String changementEnCours = 'Vérification du dossier…';

  /// Progression du déplacement.
  static String progressionDeplacement(int faits, int total) =>
      total <= 0 ? 'Préparation…' : '$faits / $total fichier(s)';

  /// Titre de la boîte après un changement réussi.
  static const String dossierChange = 'Dossier des chapitres changé';

  /// Mention après un changement réussi.
  static const String redemarrerPourNouveauDossier =
      'Redémarrez l\'application pour utiliser le nouveau dossier.';

  /// Titre de la confirmation demandée quand le service signale un risque
  /// avant le changement de dossier.
  static const String avantChangementDossier = 'Changer de dossier ?';

  /// Bouton : changer de dossier malgré l'avertissement.
  static const String changerQuandMeme = 'Changer quand même';

  /// Titre de la liste des fichiers en conflit après un déplacement.
  static String fichiersEnConflit(int nombre) =>
      "Fichiers restés dans l'ancien dossier, à vérifier ($nombre) :";

  /// Ligne de la liste des fichiers en conflit.
  static String fichierEnConflit(String chemin) => '• $chemin';

  /// Fin de la liste des fichiers en conflit quand elle est tronquée.
  static String autresFichiersEnConflit(int nombre) =>
      'et $nombre autre(s) fichier(s)';

  /// Refus « chapitre en cours » : la file attend la décision du client.
  static const String filePauseeParChangement =
      'Les téléchargements sont en pause en attendant le changement de '
      'dossier. Réessayez dans un instant, ou annulez pour les reprendre.';

  /// Bouton : renoncer au changement et reprendre les téléchargements.
  static const String reprendreTelechargements =
      'Reprendre les téléchargements';

  /// Déplacement inachevé détecté.
  static String deplacementInacheve(String chemin) =>
      'Un déplacement des chapitres vers « $chemin » n\'est pas terminé. '
      'Les chapitres déjà déplacés ne sont pas perdus.';

  /// Bouton : terminer le déplacement inachevé.
  static const String terminerDeplacement = 'Terminer le déplacement';

  /// Bouton : abandonner le déplacement inachevé.
  static const String abandonner = 'Abandonner';

  /// Titre de la confirmation d'abandon.
  static const String abandonnerDeplacement = 'Abandonner le déplacement ?';

  /// Confirmation avant d'abandonner un déplacement inachevé.
  static const String confirmationAbandonDeplacement =
      'Les chapitres restés dans l\'autre dossier ne seront plus reconnus : '
      'ceux que vos règles demandent seront retéléchargés. Aucun fichier '
      'n\'est supprimé.';

  /// Message après l'abandon.
  static const String deplacementAbandonne = 'Déplacement abandonné.';

  /// Bandeau : le dossier a été changé pendant la session.
  static const String bandeauRedemarrage =
      'Redémarrez l\'application pour utiliser le nouveau dossier des '
      'chapitres.';

  // ------------------------------------------- Listes personnelles (X4)

  /// Bouton et titre du dialogue de création d'une liste.
  static const String nouvelleListe = 'Nouvelle liste';

  /// Bouton et titre de l'écran de gestion des listes.
  static const String gererListes = 'Gérer les listes';

  /// Action : renommer une liste.
  static const String renommerListe = 'Renommer';

  /// Titre du dialogue de renommage d'une liste.
  static const String titreRenommerListe = 'Renommer la liste';

  /// Action : supprimer une liste.
  static const String supprimerListe = 'Supprimer la liste';

  /// Champ du nom d'une liste.
  static const String champNomListe = 'Nom de la liste';

  /// Bouton de création d'une liste.
  static const String creer = 'Créer';

  /// Bouton de validation d'un renommage.
  static const String renommer = 'Renommer';

  /// Mention d'une liste système (menu grisé, écran de gestion).
  static const String listeSysteme =
      "Liste de l'application : elle ne peut être ni renommée ni supprimée.";

  /// Info-bulle de la poignée de déplacement d'une liste.
  static const String deplacerListe = 'Faire glisser pour déplacer';

  /// Info-bulle du bouton des actions d'une liste.
  static const String actionsListe = 'Actions de la liste';

  /// Explication de l'écran de gestion des listes.
  static const String aideGestionListes =
      "Faites glisser une liste par sa poignée pour changer l'ordre des "
      'puces de la bibliothèque. Les listes de l\'application (Favoris, '
      'Suivis…) se déplacent aussi, mais ne se renomment ni ne se '
      'suppriment.';

  /// Aucune liste à gérer.
  static const String aucuneListe = 'Aucune liste.';

  /// Question avant la suppression d'une liste personnelle.
  static String confirmationSuppressionListe(String nom) =>
      'Supprimer la liste « $nom » ?\n'
      "Les titres qu'elle contient restent dans votre bibliothèque.";

  /// Liste créée.
  static String listeCreee(String nom) => 'Liste « $nom » créée.';

  /// Liste renommée.
  static String listeRenommee(String nom) => 'Liste renommée en « $nom ».';

  /// Liste supprimée.
  static String listeSupprimee(String nom) => 'Liste « $nom » supprimée.';

  // ------------------------------------------------- Type d'un site (X5)

  /// Aide du choix du type dans la modification d'un site.
  static const String aideTypeSiteModification =
      "Le type décide de la façon dont l'application lit le site. Les types "
      'grisés ne conviennent pas à ce site.';

  /// Avertissement : quitter le type générique efface les sélecteurs CSS.
  static const String avertissementEffacementReglages =
      'Changer de type effacera les réglages avancés (sélecteurs CSS) de ce '
      'site : ils ne servent qu\'au type générique.';

  /// Mention sous la liste des sources : toucher une ligne la modifie.
  static const String aideModifierSource =
      'Touchez un site pour le modifier (nom, type, langues) ou le supprimer.';

  // ------------------------------------- Description personnelle (client)

  /// Intitulé du bloc de la description personnelle, sous le résumé.
  static const String maDescription = 'Ma description';

  /// Explication sous l'intitulé : ce texte est au client, pas au site.
  static const String aideMaDescription =
      'Vos notes sur ce titre. Le site ne les remplace jamais.';

  /// Bouton quand la description est vide.
  static const String ajouterDescription = 'Ajouter une description';

  /// Bouton de modification de la description.
  static const String modifierDescription = 'Modifier';

  /// Bouton d'effacement de la description.
  static const String effacerDescription = 'Effacer';

  /// Champ de saisie du dialogue.
  static const String champDescription = 'Description';

  /// Question avant d'effacer la description.
  static const String titreEffacerDescription = 'Effacer la description ?';

  /// Détail de la confirmation d'effacement.
  static const String confirmationEffacerDescription =
      'Votre description de ce titre sera effacée. Le résumé du site ne '
      'change pas.';

  /// Message après l'enregistrement de la description.
  static const String descriptionEnregistree = 'Description enregistrée.';

  /// Message après l'effacement de la description.
  static const String descriptionEffacee = 'Description effacée.';

  /// Erreur de saisie : texte trop long.
  static String descriptionTropLongue(int maximum) =>
      'La description est trop longue ($maximum caractères au plus).';

  /// Choix « Adresse » du dialogue d'ajout d'un titre.
  static const String modeAdresse = 'Adresse';

  /// Choix « Rechercher » du dialogue d'ajout d'un titre.
  static const String modeRechercher = 'Rechercher';

  /// Champ de recherche sur MangaDex.
  static const String champRechercheMangaDex = 'Rechercher sur MangaDex';

  /// Bouton de recherche.
  static const String rechercher = 'Rechercher';

  /// Aucun résultat de recherche sur MangaDex.
  static const String aucunResultatMangaDex =
      'Aucun titre trouvé sur MangaDex.';

  /// Aide de la recherche : choisir un résultat puis « Ajouter ».
  static const String aideRechercheMangaDex =
      'Choisissez un résultat, puis appuyez sur « Ajouter ».';

  // -------------------------------------------- Archive complète (X7)

  /// Interrupteur « Archive complète ».
  static const String archiveComplete = 'Archive complète';

  /// Explication de l'archive complète.
  static const String explicationArchiveComplete =
      'Télécharger tous les chapitres de tous les titres et ne jamais les '
      'supprimer automatiquement (conseillé avec un NAS).';

  /// Titre de la confirmation d'activation.
  static const String activerArchiveComplete = "Activer l'archive complète ?";

  /// Avertissement avant l'activation de l'archive complète.
  static const String confirmationArchiveComplete =
      'Tous les chapitres de tous les titres de la bibliothèque seront '
      "téléchargés : cela peut représenter beaucoup de téléchargements et "
      "d'espace disque. Plus aucun chapitre ne sera supprimé "
      'automatiquement.';

  /// Bouton d'activation.
  static const String activer = 'Activer';

  /// Message après le changement de l'archive complète.
  static String archiveCompleteModifiee(bool active) => active
      ? 'Archive complète activée : tous les chapitres vont être téléchargés.'
      : 'Archive complète désactivée : les règles habituelles '
            "s'appliquent de nouveau.";

  // --------------------------------------- Chapitres lus en lot (X10)

  /// Aide de la sélection de chapitres.
  static const String aideSelectionChapitres =
      'Appui long sur un chapitre (ou clic maintenu et glisser à la souris) '
      'pour en sélectionner plusieurs.';

  /// Titre de la barre de sélection.
  static String chapitresSelectionnes(int nombre) =>
      nombre <= 1 ? '$nombre sélectionné' : '$nombre sélectionnés';

  /// Action : marquer la sélection lue.
  static const String marquerSelectionLus = 'Marquer lus';

  /// Action : marquer la sélection non lue.
  static const String marquerSelectionNonLus = 'Marquer non lus';

  /// Action : tout sélectionner.
  static const String toutSelectionner = 'Tout sélectionner';

  /// Action : quitter la sélection.
  static const String annulerSelection = 'Annuler la sélection';

  /// Action du menu d'un chapitre : marquer lus tous les précédents.
  static const String marquerLusJusquIci = "Marquer lus jusqu'ici";

  /// Action de la barre de sélection (une seule ligne choisie).
  static const String lusJusquIci = "Lus jusqu'ici";

  /// Info-bulle du bouton « ⋮ » d'un chapitre téléchargé.
  static const String ouvrirMenuChapitre = 'Ouvrir le menu';

  /// Message après un marquage en lot.
  static String chapitresMarques(int nombre, {required bool lu}) {
    if (nombre == 0) return 'Aucun chapitre à changer.';
    if (nombre == 1) {
      return lu ? '1 chapitre marqué lu.' : '1 chapitre marqué non lu.';
    }
    return lu
        ? '$nombre chapitres marqués lus.'
        : '$nombre chapitres marqués non lus.';
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
