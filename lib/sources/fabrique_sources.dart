/// Fabrique des adaptateurs de sites (PLAYBOOK.md section 6).
library;

import '../modeles/source.dart';
import 'client_http_poli.dart';
import 'erreur_source.dart';
import 'source_mangadex.dart';
import 'source_scan_manga.dart';
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
  /// [niveauxContenuRecherche] : niveaux de contenu acceptés par la recherche
  /// (valeurs de `niveauxContenu`, lib/modeles/constantes.dart) ; `null`
  /// garde le défaut du site (MangaDex : tout sauf `pornographic`). Ignoré
  /// par les sites qui n'ont pas cette notion.
  ///
  /// Lève une [ErreurSource] si le type n'a pas encore d'adaptateur (Madara,
  /// MangaThemesia et générique arrivent à l'étape 6 de la feuille de route).
  SourceSite creer(Source source, {List<String>? niveauxContenuRecherche}) {
    switch (source.typeSource) {
      case TypeSource.mangaDex:
        // Les langues de la source (« fr,en », par ordre de préférence)
        // filtrent les chapitres demandés à l'API : sans filtre, un titre très
        // traduit peut dépasser le plafond de 10 000 résultats de MangaDex.
        // Les variantes régionales (pt-br, es-la, zh-hk) sont incluses : un
        // client qui lit en « pt » veut aussi les traductions brésiliennes.
        // Valeur vide = toutes les langues.
        final preferees = SourceMangaDex.languesIsoDepuisPreference(
          source.langueParDefaut,
        );
        return SourceMangaDex(
          _client,
          languesChapitres: SourceMangaDex.languesDepuisPreference(
            source.langueParDefaut,
          ),
          // Le même ordre choisit la langue du résumé ; sans préférence, on
          // garde le défaut de l'adaptateur (fr puis en).
          languesPreferees: preferees.isEmpty
              ? const <String>['fr', 'en']
              : preferees,
          niveauxContenuRecherche: niveauxContenuRecherche,
        );
      case TypeSource.scanManga:
        // Site francophone : chapitres en « fr » sauf suffixe contraire dans
        // leur adresse ; pas de filtre de langue ni de niveau de contenu.
        return SourceScanManga(_client);
      case TypeSource.madara:
      case TypeSource.mangaThemesia:
      case TypeSource.generique:
        throw ErreurSource(
          source.urlBase,
          'Aucun adaptateur disponible pour le type '
          "« ${source.typeSource.name} » (prévu à l'étape 6)",
          typeDetecte: source.typeSource,
        );
    }
  }
}
