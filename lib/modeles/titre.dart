/// Modèle `Titre` : une œuvre (manga, manhwa, roman…) suivie sur une source.
library;

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
  }) : titresAlternatifs = List<TitreAlternatif>.unmodifiable(
         titresAlternatifs,
       );

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
    };
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
    );
  }

  /// Renvoie une copie avec les champs donnés remplacés.
  ///
  /// LIMITE : un champ nullable ne peut pas être remis à `null` par cette
  /// méthode (un argument `null` signifie « inchangé »).
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
            other.nombreChapitresNonLus == nombreChapitresNonLus;
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
  );

  @override
  String toString() =>
      'Titre(id: $id, idSource: $idSource, nom: $nom, '
      'typeTitre: ${typeTitre.name}, urlTitre: $urlTitre, '
      'titresAlternatifs: ${titresAlternatifs.length}, '
      'nombreChapitresNonLus: $nombreChapitresNonLus)';
}
