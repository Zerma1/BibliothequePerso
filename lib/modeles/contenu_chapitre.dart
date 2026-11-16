/// Modèle `ContenuChapitre` : ce qu'il faut lire ou télécharger pour un
/// chapitre (PLAYBOOK.md section 6, `SourceSite.recupererContenu`).
library;

import 'outils_modeles.dart';

/// Contenu d'un chapitre : soit une liste ordonnée d'URLs d'images (manga,
/// manhwa…), soit un texte HTML (roman).
///
/// Les deux formes sont exclusives : on passe par [ContenuChapitre.images] ou
/// [ContenuChapitre.texte].
class ContenuChapitre {
  /// Contenu sous forme d'images, dans l'ordre de lecture.
  ///
  /// [urlReferer] est l'URL à envoyer dans l'en-tête `Referer` lors du
  /// téléchargement des images, quand le site l'exige (`null` sinon).
  ContenuChapitre.images(List<String> urlsImages, {this.urlReferer})
    : urlsImages = List<String>.unmodifiable(urlsImages),
      texteHtml = null;

  /// Contenu sous forme de texte HTML (chapitre de roman).
  ContenuChapitre.texte(String this.texteHtml)
    : urlsImages = const <String>[],
      urlReferer = null;

  /// URLs absolues des images, dans l'ordre de lecture (vide pour un texte).
  final List<String> urlsImages;

  /// Texte HTML du chapitre, `null` pour un chapitre en images.
  final String? texteHtml;

  /// En-tête `Referer` à envoyer pour télécharger les images, si nécessaire.
  final String? urlReferer;

  /// `true` si le chapitre est un texte (roman) plutôt que des images.
  bool get estTexte => texteHtml != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ContenuChapitre &&
            listesEgales(other.urlsImages, urlsImages) &&
            other.texteHtml == texteHtml &&
            other.urlReferer == urlReferer;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(urlsImages), texteHtml, urlReferer);

  @override
  String toString() => estTexte
      ? 'ContenuChapitre(texte : ${texteHtml!.length} caractères)'
      : 'ContenuChapitre(images : ${urlsImages.length}, '
            'urlReferer: $urlReferer)';
}
