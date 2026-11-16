/// Sources proposées dès le premier lancement (tâche R9 : MangaDex et
/// Scan-Manga), ajoutées sans requête réseau et sans jamais toucher aux
/// réglages du client.
library;

import '../donnees/depot_sources.dart';
import '../modeles/source.dart';
import 'service_ajout_site.dart';
import 'service_parametres.dart';

/// Description d'une source livrée avec l'application.
class SourceParDefaut {
  /// Crée la description.
  const SourceParDefaut({
    required this.identifiant,
    required this.nom,
    required this.urlBase,
    required this.typeSource,
    this.langues = '',
  });

  /// Identifiant stable mémorisé dans les réglages (ne jamais le renommer :
  /// la source serait reproposée au client qui l'a supprimée).
  final String identifiant;

  /// Nom affiché.
  final String nom;

  /// URL de base (`schéma://hôte`, comme `ServiceAjoutSite.calculerUrlBase`).
  final String urlBase;

  /// Famille technique du site (connue d'avance : pas de détection réseau).
  final TypeSource typeSource;

  /// Langues par défaut (codes séparés par des virgules, peut être vide).
  final String langues;

  /// Hôte sans `www.`, pour reconnaître une source déjà configurée.
  String get hote => ServiceAjoutSite.proposerNom(Uri.parse(urlBase));

  /// Source à enregistrer (sans identifiant SQLite).
  Source versSource() => Source(
    nom: nom,
    urlBase: urlBase,
    typeSource: typeSource,
    langueParDefaut: langues,
  );
}

/// Nom de MangaDex.
const String nomMangaDex = 'MangaDex';

/// URL de base de MangaDex.
const String urlBaseMangaDex = 'https://mangadex.org';

/// Nom de Scan-Manga.
const String nomScanManga = 'Scan-Manga';

/// URL de base de Scan-Manga.
const String urlBaseScanManga = 'https://www.scan-manga.com';

/// Sources par défaut, dans l'ordre d'ajout.
const List<SourceParDefaut> sourcesParDefaut = <SourceParDefaut>[
  // MangaDex : langues laissées vides, ce sont alors les langues générales du
  // client qui s'appliquent.
  SourceParDefaut(
    identifiant: 'mangadex',
    nom: nomMangaDex,
    urlBase: urlBaseMangaDex,
    typeSource: TypeSource.mangaDex,
  ),
  // Scan-Manga ne publie qu'en français.
  SourceParDefaut(
    identifiant: 'scan-manga',
    nom: nomScanManga,
    urlBase: urlBaseScanManga,
    typeSource: TypeSource.scanManga,
    langues: 'fr',
  ),
];

/// Décision pure : quelles sources par défaut ajouter et lesquelles marquer
/// comme proposées.
class PlanSourcesParDefaut {
  /// Crée le plan.
  const PlanSourcesParDefaut({
    required this.aAjouter,
    required this.dejaPresentes,
  });

  /// Sources à créer en base.
  final List<SourceParDefaut> aAjouter;

  /// Sources déjà configurées par le client (même hôte, avec ou sans
  /// `www.`) : laissées telles quelles, seulement marquées comme proposées.
  final List<SourceParDefaut> dejaPresentes;

  /// Calcule le plan sans base ni réseau.
  ///
  /// Une source déjà proposée ([dejaProposees]) est ignorée même si elle
  /// n'existe plus : le client l'a supprimée volontairement.
  static PlanSourcesParDefaut calculer({
    required List<SourceParDefaut> defauts,
    required List<Source> existantes,
    required Set<String> dejaProposees,
  }) {
    final hotesExistants = <String>{
      for (final source in existantes) ?_hote(source.urlBase),
    };
    final aAjouter = <SourceParDefaut>[];
    final dejaPresentes = <SourceParDefaut>[];
    for (final defaut in defauts) {
      if (dejaProposees.contains(defaut.identifiant)) continue;
      if (hotesExistants.contains(defaut.hote)) {
        dejaPresentes.add(defaut);
      } else {
        aAjouter.add(defaut);
      }
    }
    return PlanSourcesParDefaut(
      aAjouter: aAjouter,
      dejaPresentes: dejaPresentes,
    );
  }

  static String? _hote(String urlBase) {
    final uri = Uri.tryParse(urlBase);
    if (uri == null || uri.host.isEmpty) return null;
    return ServiceAjoutSite.proposerNom(uri);
  }
}

/// Résultat de [ServiceSourcesParDefaut.assurerSourcesParDefaut].
class ResultatSourcesParDefaut {
  /// Crée le résultat.
  const ResultatSourcesParDefaut({
    this.ajoutees = const <Source>[],
    this.erreurs = const <Object>[],
  });

  /// Sources créées pendant cet appel.
  final List<Source> ajoutees;

  /// Erreurs rencontrées (base) : gardées ici plutôt que levées, pour ne
  /// jamais empêcher le démarrage.
  final List<Object> erreurs;
}

/// Ajoute au démarrage les sources par défaut qui manquent.
class ServiceSourcesParDefaut {
  /// Crée le service.
  const ServiceSourcesParDefaut({
    required DepotSources depotSources,
    required ServiceParametres serviceParametres,
    List<SourceParDefaut> defauts = sourcesParDefaut,
  }) : _depot = depotSources,
       _parametres = serviceParametres,
       _sourcesProposees = defauts;

  final DepotSources _depot;
  final ServiceParametres _parametres;
  final List<SourceParDefaut> _sourcesProposees;

  /// Ajoute les sources par défaut jamais proposées et absentes de la base.
  ///
  /// Aucune requête réseau ; une source existante (même hôte, avec ou sans
  /// `www.`) n'est jamais modifiée ; une source déjà proposée puis supprimée
  /// par le client n'est pas recréée. Ne lève jamais : les erreurs sont
  /// rendues dans le résultat.
  Future<ResultatSourcesParDefaut> assurerSourcesParDefaut() async {
    final erreurs = <Object>[];
    final ajoutees = <Source>[];
    try {
      final proposees = await _parametres.chargerSourcesParDefautProposees();
      final plan = PlanSourcesParDefaut.calculer(
        defauts: _sourcesProposees,
        existantes: await _depot.chargerSources(),
        dejaProposees: proposees,
      );
      final marquees = <String>{
        ...proposees,
        for (final defaut in plan.dejaPresentes) defaut.identifiant,
      };
      for (final defaut in plan.aAjouter) {
        try {
          ajoutees.add(
            await _depot.enregistrerSource(defaut.versSource()),
          );
          marquees.add(defaut.identifiant);
        } catch (erreur) {
          // Non marquée : on réessaiera au prochain démarrage. Une autre
          // source par défaut peut quand même être ajoutée.
          erreurs.add(erreur);
        }
      }
      // LIMITE : l'insertion et la mémorisation ne sont pas atomiques. Si
      // l'écriture du réglage échoue, la source sera reconnue par son hôte
      // au prochain démarrage et seulement marquée : aucun doublon possible.
      if (marquees.length != proposees.length) {
        await _parametres.enregistrerSourcesParDefautProposees(marquees);
      }
    } catch (erreur) {
      erreurs.add(erreur);
    }
    return ResultatSourcesParDefaut(ajoutees: ajoutees, erreurs: erreurs);
  }
}
