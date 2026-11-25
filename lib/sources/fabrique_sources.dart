/// Fabrique des adaptateurs de sites (PLAYBOOK.md section 6).
library;

import '../modeles/source.dart';
import 'client_http_poli.dart';
import 'erreur_source.dart';
import 'source_generique.dart';
import 'source_madara.dart';
import 'source_mangadex.dart';
import 'source_mangathemesia.dart';
import 'source_scan_manga.dart';
import 'source_site.dart';
import 'source_webtoons.dart';

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
  /// Lève une [ErreurSource] si les réglages d'un site générique
  /// (`Source.configurationSelecteurs`) sont illisibles.
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
      case TypeSource.webtoons:
        // Langue des épisodes lue dans l'adresse du titre (/fr/, /en/…) :
        // aucun filtre de langue ni de niveau de contenu.
        return SourceWebtoons(_client);
      case TypeSource.madara:
        // Langue des chapitres lue dans la page (`<html lang>`) ; les langues
        // de la source ne servent que de repli.
        return SourceMadara(
          _client,
          urlBase: source.urlBase,
          languesPreferees: source.langueParDefaut,
        );
      case TypeSource.mangaThemesia:
        return SourceMangaThemesia(
          _client,
          urlBase: source.urlBase,
          languesPreferees: source.langueParDefaut,
        );
      case TypeSource.generique:
        // Sélecteurs CSS réglés par le client (JSON), sinon heuristiques
        // des sites à liens explicites. Des réglages illisibles lèvent une
        // ErreurSource dès maintenant, avant toute requête.
        return SourceGenerique(
          _client,
          urlBase: source.urlBase,
          configuration: ConfigurationGenerique.depuisJson(
            source.configurationSelecteurs,
            url: source.urlBase,
          ),
          languesPreferees: source.langueParDefaut,
        );
    }
  }
}
