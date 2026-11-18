/// Modèle `Titre` : une œuvre (manga, manhwa, roman…) suivie sur une source.
library;

import 'dart:convert';

import 'erreur_base_de_donnees.dart';
import 'outils_modeles.dart';
import 'titre_alternatif.dart';

/// Nature d'un titre. Sert aussi de premier dossier des fichiers hors-ligne
/// (`<type>/<nom du titre>/…`, PLAYBOOK.md section 5).
///
/// La valeur est stockée en base sous son nom (`Enum.name`) : ne jamais
/// renommer une valeur existante sans migration.
enum TypeTitre {
  /// Bande dessinée japonaise.
  manga,

  /// Bande dessinée coréenne.
  manhwa,

  /// Bande dessinée chinoise.
  manhua,

  /// Roman (light novel, web novel…), lu sous forme de texte.
  roman,

  /// Livre.
  livre,

  /// Tout autre type.
  autre,
}

/// Champ d'un titre que le client peut modifier à la main (migration 10).
///
/// Un champ modifié à la main est « verrouillé » : l'actualisation depuis le
/// site (`DepotTitres.enregistrerTitre`) ne l'écrase plus, jusqu'à ce que le
/// client le rende au site (`DepotTitres.rendreChampsAuSite`).
///
/// Stocké en base sous son nom (`Enum.name`, colonne `titres.champs_manuels`) :
/// ne jamais renommer une valeur existante sans migration. Un nom inconnu lu
/// en base est ignoré.
enum ChampTitre {
  /// Nom principal ([Titre.nom]).
  nom,

  /// Autres noms ([Titre.titresAlternatifs], table `titres_alternatifs`).
  titresAlternatifs,

  /// Résumé ([Titre.resume]).
  resume,

  /// Auteur ([Titre.auteur]).
  auteur,

  /// Statut affiché par le site ([Titre.statut]).
  statut,

  /// Catégories du titre (table `titres_categories`).
  categories,

  /// Niveau de contenu ([Titre.niveauContenu]).
  niveauContenu,
}

/// Une œuvre enregistrée dans la bibliothèque.
///
/// [titresAlternatifs] et [nombreChapitresNonLus] ne sont pas des colonnes de la
/// table `titres` : ils sont remplis par `DepotTitres` lors du chargement.
class Titre {
  /// Crée un titre. [id] vaut `null` tant qu'il n'est pas enregistré.
  ///
  /// La liste [titresAlternatifs] est copiée dans une liste non modifiable pour
  /// garantir l'immuabilité de l'objet.
  Titre({
    this.id,
    this.idSource,
    required this.urlTitre,
    required this.nom,
    this.typeTitre = TypeTitre.autre,
    this.urlCouverture,
    this.resume,
    this.auteur,
    this.statut,
    List<TitreAlternatif> titresAlternatifs = const <TitreAlternatif>[],
    this.dateDerniereVerification,
    this.nombreChapitresNonLus = 0,
    this.languesPreferees,
    this.niveauContenu,
    this.couvertureChoisie,
    Set<ChampTitre> champsManuels = const <ChampTitre>{},
  }) : titresAlternatifs = List<TitreAlternatif>.unmodifiable(
         titresAlternatifs,
       ),
       champsManuels = Set<ChampTitre>.unmodifiable(champsManuels);

  static const String _entite = 'Titre';

  /// Identifiant SQLite, `null` avant le premier enregistrement.
  final int? id;

  /// Identifiant de la source d'où vient le titre.
  ///
  /// `null` tant que le titre n'est connu que de l'adaptateur de site (étape
  /// de lecture réseau) ; `DepotTitres` exige une valeur pour l'enregistrer.
  final int? idSource;

  /// URL de la fiche du titre sur le site (unique en base).
  final String urlTitre;

  /// Nom principal du titre.
  final String nom;

  /// Nature du titre.
  final TypeTitre typeTitre;

  /// URL de l'image de couverture, si connue.
  final String? urlCouverture;

  /// Résumé, si connu.
  final String? resume;

  /// Auteur, si connu.
  final String? auteur;

  /// Statut affiché par le site (« En cours », « Terminé »…), tel quel.
  final String? statut;

  /// Autres noms du titre (liste non modifiable).
  final List<TitreAlternatif> titresAlternatifs;

  /// Date (UTC) de la dernière recherche de nouveaux chapitres.
  final DateTime? dateDerniereVerification;

  /// Nombre de chapitres non lus, calculé par la requête de chargement.
  final int nombreChapitresNonLus;

  /// Langues favorites propres à ce titre : codes ISO 639-1 (ou variantes
  /// comme `pt-br`) séparés par des virgules, par ordre de préférence
  /// (`fr,en`), ou `null` pour utiliser le réglage général.
  ///
  /// Choix du client : jamais écrasé par une ré-actualisation du titre
  /// depuis le site (voir `DepotTitres.enregistrerLanguesPreferees`).
  final String? languesPreferees;

  /// Niveau de contenu indiqué par le site, tel que MangaDex le nomme
  /// (`safe`, `suggestive`, `erotica`, `pornographic` : voir
  /// `niveauxContenu` dans `constantes.dart`), ou `null` si le site ne le
  /// donne pas.
  ///
  /// Texte libre plutôt qu'énumération : une valeur inconnue ajoutée un jour
  /// par MangaDex ne doit pas rendre la ligne illisible.
  final String? niveauContenu;

  /// Couverture choisie par le client : URL d'une autre couverture du site
  /// (MangaDex : une par volume) ou chemin d'une image de l'appareil, ou
  /// `null` pour la couverture du site ([urlCouverture]).
  ///
  /// Choix du client : jamais écrasé par une ré-actualisation du titre
  /// depuis le site (voir `DepotTitres.enregistrerCouvertureChoisie`).
  final String? couvertureChoisie;

  /// Champs modifiés à la main par le client (ensemble non modifiable) :
  /// l'actualisation depuis le site ne les écrase pas (migration 10).
  ///
  /// Écrits seulement par `DepotTitres.enregistrerModificationManuelle` et
  /// `DepotTitres.rendreChampsAuSite` (et à l'insertion d'un titre) : une
  /// mise à jour par `enregistrerTitre` ne les modifie jamais.
  final Set<ChampTitre> champsManuels;

  /// Indique si [champ] a été modifié à la main (verrouillé contre
  /// l'actualisation depuis le site).
  bool estManuel(ChampTitre champ) => champsManuels.contains(champ);

  /// Couverture à afficher : [couvertureChoisie] si le client en a choisi
  /// une, sinon [urlCouverture].
  String? get couvertureAffichee => couvertureChoisie ?? urlCouverture;

  /// [languesPreferees] découpées en liste (`fr,en` → `['fr', 'en']`), vide
  /// si aucune langue n'est choisie pour ce titre.
  List<String> get listeLanguesPreferees {
    final valeur = languesPreferees;
    if (valeur == null) {
      return const <String>[];
    }
    return <String>[
      for (final langue in valeur.split(','))
        if (langue.trim().isNotEmpty) langue.trim(),
    ];
  }

  /// Convertit le titre en ligne de la table `titres`.
  ///
  /// [titresAlternatifs] et [nombreChapitresNonLus] sont exclus : ils vivent
  /// dans d'autres tables ou sont calculés.
  Map<String, Object?> versMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'id_source': idSource,
      'url_titre': urlTitre,
      'nom': nom,
      'type_titre': typeTitre.name,
      'url_couverture': urlCouverture,
      'resume': resume,
      'auteur': auteur,
      'statut': statut,
      'date_derniere_verification': dateVersMillisecondes(
        dateDerniereVerification,
      ),
      'langues_preferees': languesPreferees,
      'niveau_contenu': niveauContenu,
      'couverture_choisie': couvertureChoisie,
      'champs_manuels': encoderChampsManuels(champsManuels),
    };
  }

  /// Convertit des champs manuels en texte JSON pour la colonne
  /// `titres.champs_manuels` : tableau des noms, dans l'ordre de
  /// [ChampTitre.values] (texte identique pour un même ensemble).
  static String encoderChampsManuels(Set<ChampTitre> champs) {
    return jsonEncode(<String>[
      for (final champ in ChampTitre.values)
        if (champs.contains(champ)) champ.name,
    ]);
  }

  /// Lit le texte JSON de la colonne `titres.champs_manuels`.
  ///
  /// `null` ou un texte vide donne un ensemble vide ; un nom inconnu est
  /// ignoré. Lève une `ErreurBaseDeDonnees` si le texte n'est pas un tableau
  /// JSON de textes.
  static Set<ChampTitre> decoderChampsManuels(String? texte) {
    if (texte == null || texte.trim().isEmpty) {
      return const <ChampTitre>{};
    }
    final Object? decode;
    try {
      decode = jsonDecode(texte);
    } on FormatException catch (erreur) {
      throw ErreurBaseDeDonnees(
        'Donnée invalide pour $_entite : la colonne « champs_manuels » '
        'n\'est pas du JSON valide ($texte).',
        cause: erreur,
      );
    }
    if (decode is! List<Object?>) {
      throw ErreurBaseDeDonnees(
        'Donnée invalide pour $_entite : la colonne « champs_manuels » doit '
        'être un tableau JSON, reçu « $texte ».',
      );
    }
    final champs = <ChampTitre>{};
    for (final element in decode) {
      if (element is! String) {
        throw ErreurBaseDeDonnees(
          'Donnée invalide pour $_entite : la colonne « champs_manuels » ne '
          'doit contenir que des textes, reçu « $texte ».',
        );
      }
      for (final champ in ChampTitre.values) {
        if (champ.name == element) {
          champs.add(champ);
        }
      }
    }
    return champs;
  }

  /// Construit un titre depuis une ligne SQLite.
  ///
  /// La colonne calculée `nombre_chapitres_non_lus` est lue si elle est
  /// présente (0 sinon). Les [titresAlternatifs] viennent d'une autre requête.
  /// Lève une `ErreurBaseDeDonnees` si une colonne a un type inattendu.
  factory Titre.depuisMap(
    Map<String, Object?> map, {
    List<TitreAlternatif> titresAlternatifs = const <TitreAlternatif>[],
  }) {
    return Titre(
      id: map.lireEntierOptionnel('id', _entite),
      idSource: map.lireEntierOptionnel('id_source', _entite),
      urlTitre: map.lireTexte('url_titre', _entite),
      nom: map.lireTexte('nom', _entite),
      typeTitre: map.lireEnum('type_titre', _entite, TypeTitre.values),
      urlCouverture: map.lireTexteOptionnel('url_couverture', _entite),
      resume: map.lireTexteOptionnel('resume', _entite),
      auteur: map.lireTexteOptionnel('auteur', _entite),
      statut: map.lireTexteOptionnel('statut', _entite),
      titresAlternatifs: titresAlternatifs,
      dateDerniereVerification: map.lireDateOptionnelle(
        'date_derniere_verification',
        _entite,
      ),
      nombreChapitresNonLus:
          map.lireEntierOptionnel('nombre_chapitres_non_lus', _entite) ?? 0,
      languesPreferees: map.lireTexteOptionnel('langues_preferees', _entite),
      niveauContenu: map.lireTexteOptionnel('niveau_contenu', _entite),
      couvertureChoisie: map.lireTexteOptionnel('couverture_choisie', _entite),
      champsManuels: decoderChampsManuels(
        map.lireTexteOptionnel('champs_manuels', _entite),
      ),
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode (un argument `null` signifie « inchangé »), sauf :
  /// - [languesPreferees] : `effacerLanguesPreferees: true` le remet à
  ///   `null` (retour au réglage général) ;
  /// - [couvertureChoisie] : `effacerCouvertureChoisie: true` le remet à
  ///   `null` (retour à la couverture du site) ;
  /// - [niveauContenu] : `effacerNiveauContenu: true` le remet à `null`.
  ///
  /// Un indicateur `effacer…` l'emporte sur la valeur donnée pour le même
  /// champ.
  Titre copierAvec({
    int? id,
    int? idSource,
    String? urlTitre,
    String? nom,
    TypeTitre? typeTitre,
    String? urlCouverture,
    String? resume,
    String? auteur,
    String? statut,
    List<TitreAlternatif>? titresAlternatifs,
    DateTime? dateDerniereVerification,
    int? nombreChapitresNonLus,
    String? languesPreferees,
    bool effacerLanguesPreferees = false,
    String? niveauContenu,
    bool effacerNiveauContenu = false,
    String? couvertureChoisie,
    bool effacerCouvertureChoisie = false,
    Set<ChampTitre>? champsManuels,
  }) {
    return Titre(
      id: id ?? this.id,
      idSource: idSource ?? this.idSource,
      urlTitre: urlTitre ?? this.urlTitre,
      nom: nom ?? this.nom,
      typeTitre: typeTitre ?? this.typeTitre,
      urlCouverture: urlCouverture ?? this.urlCouverture,
      resume: resume ?? this.resume,
      auteur: auteur ?? this.auteur,
      statut: statut ?? this.statut,
      titresAlternatifs: titresAlternatifs ?? this.titresAlternatifs,
      dateDerniereVerification:
          dateDerniereVerification ?? this.dateDerniereVerification,
      nombreChapitresNonLus:
          nombreChapitresNonLus ?? this.nombreChapitresNonLus,
      languesPreferees: effacerLanguesPreferees
          ? null
          : languesPreferees ?? this.languesPreferees,
      niveauContenu: effacerNiveauContenu
          ? null
          : niveauContenu ?? this.niveauContenu,
      couvertureChoisie: effacerCouvertureChoisie
          ? null
          : couvertureChoisie ?? this.couvertureChoisie,
      champsManuels: champsManuels ?? this.champsManuels,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Titre &&
            other.id == id &&
            other.idSource == idSource &&
            other.urlTitre == urlTitre &&
            other.nom == nom &&
            other.typeTitre == typeTitre &&
            other.urlCouverture == urlCouverture &&
            other.resume == resume &&
            other.auteur == auteur &&
            other.statut == statut &&
            listesEgales(other.titresAlternatifs, titresAlternatifs) &&
            other.dateDerniereVerification == dateDerniereVerification &&
            other.nombreChapitresNonLus == nombreChapitresNonLus &&
            other.languesPreferees == languesPreferees &&
            other.niveauContenu == niveauContenu &&
            other.couvertureChoisie == couvertureChoisie &&
            other.champsManuels.length == champsManuels.length &&
            other.champsManuels.containsAll(champsManuels);
  }

  @override
  int get hashCode => Object.hash(
    id,
    idSource,
    urlTitre,
    nom,
    typeTitre,
    urlCouverture,
    resume,
    auteur,
    statut,
    Object.hashAll(titresAlternatifs),
    dateDerniereVerification,
    nombreChapitresNonLus,
    languesPreferees,
    niveauContenu,
    couvertureChoisie,
    Object.hashAllUnordered(champsManuels),
  );

  @override
  String toString() =>
      'Titre(id: $id, idSource: $idSource, nom: $nom, '
      'typeTitre: ${typeTitre.name}, urlTitre: $urlTitre, '
      'titresAlternatifs: ${titresAlternatifs.length}, '
      'nombreChapitresNonLus: $nombreChapitresNonLus)';
}
