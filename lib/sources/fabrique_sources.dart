/// Fabrique des adaptateurs de sites (PLAYBOOK.md section 6).
library;

import '../modeles/source.dart';
import 'client_http_poli.dart';
import 'erreur_source.dart';
import 'source_mangadex.dart';
import 'source_site.dart';

/// Crée l'adaptateur [SourceSite] qui correspond au type d'une [Source].
///
/// Pour ajouter un thème, on crée une nouvelle classe qui implémente
/// [SourceSite] et on l'ajoute ici, sans modifier les adaptateurs existants.
class FabriqueSources {
  /// Crée la fabrique ; tous les adaptateurs partagent [_client], donc ses
  /// délais par domaine.
  const FabriqueSources(this._client);

  final ClientHttpPoli _client;

  /// Renvoie l'adaptateur de [source].
  ///
  /// Lève une [ErreurSource] si le type n'a pas encore d'adaptateur (Madara,
  /// MangaThemesia et générique arrivent à l'étape 6 de la feuille de route).
  SourceSite creer(Source source) {
    switch (source.typeSource) {
      case TypeSource.mangaDex:
        // La langue par défaut de la source filtre les chapitres demandés à
        // l'API : sans filtre, un titre très traduit peut dépasser le plafond
        // de 10 000 résultats de MangaDex. Les variantes régionales (pt-br,
        // es-la, zh-hk) sont incluses : un client qui lit en « pt » veut aussi
        // les traductions brésiliennes.
        return SourceMangaDex(
          _client,
          languesChapitres: SourceMangaDex.languesApiDepuisIso(
            source.langueParDefaut,
          ),
        );
      case TypeSource.madara:
      case TypeSource.mangaThemesia:
      case TypeSource.generique:
        throw ErreurSource(
          source.urlBase,
          'Aucun adaptateur disponible pour le type '
          '« ${source.typeSource.name} » (prévu à l\'étape 6)',
        );
    }
  }
}
