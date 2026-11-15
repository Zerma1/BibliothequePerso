/// Outils partagés par les tests de `donnees/` : base en mémoire et données de
/// référence (titre MangaDex du PLAYBOOK, section 6).
library;

import 'package:bibliotheque_perso/donnees/base_de_donnees.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ouvre une base SQLite neuve, en mémoire, avec toutes les migrations.
///
/// La fabrique FFI est passée explicitement pour ne pas modifier la fabrique
/// globale de sqflite pendant les tests.
Future<Database> ouvrirBaseDeTest() {
  sqfliteFfiInit();
  return ouvrirBaseDeDonnees(
    chemin: inMemoryDatabasePath,
    fabrique: databaseFactoryFfi,
  );
}

/// Source MangaDex de référence (non enregistrée).
const Source sourceMangaDex = Source(
  nom: 'MangaDex',
  urlBase: 'https://mangadex.org',
  typeSource: TypeSource.mangaDex,
  langueParDefaut: 'en',
);

/// URL du titre de référence du PLAYBOOK.
const String urlTitreReference =
    'https://mangadex.org/title/12e28a8a-cbfe-4e12-bab8-b6fb0b9a59b4';

/// Nom principal du titre de référence.
const String nomTitreReference =
    'Shinigami ni Sodaterareta Shoujo wa Shikkoku no Tsurugi wo Mune ni Idaku';

/// Les 6 titres alternatifs du titre de référence.
const List<TitreAlternatif> titresAlternatifsReference = <TitreAlternatif>[
  TitreAlternatif(nom: "Death's Daughter and the Ebony Blade", langue: 'en'),
  TitreAlternatif(
    nom: 'The Little Girl Raised by Death Holds the Sword of Death Tight',
    langue: 'en',
  ),
  TitreAlternatif(nom: '死神に育てられた少女は漆黒の剣を胸に抱く', langue: 'ja'),
  TitreAlternatif(
    nom:
        'Shinigami ni Sodaterareta Shoujo wa Shikkoku no Tsurugi o Mune ni '
        'Idaku',
    // Romanisation : pas de code ISO 639-1 propre, la langue reste vide.
  ),
  TitreAlternatif(nom: '사신에게 길러진 소녀는 칠흑의 검을 가슴에 품는다', langue: 'ko'),
  TitreAlternatif(nom: '被死神抚养的少女怀抱漆黑之剑', langue: 'zh'),
];

/// Les 9 tags MangaDex du titre de référence, tels qu'affichés par le site.
const List<String> categoriesReference = <String>[
  'Gore',
  'Action',
  'Comedy',
  'Survival',
  'Magic',
  'Military',
  'Fantasy',
  'Supernatural',
  'Adaptation',
];

/// Construit le titre de référence pour une source enregistrée.
Titre titreReference(int idSource) => Titre(
  idSource: idSource,
  urlTitre: urlTitreReference,
  nom: nomTitreReference,
  typeTitre: TypeTitre.manga,
  urlCouverture: 'https://uploads.mangadex.org/covers/exemple.jpg',
  resume: 'Une jeune fille élevée par la Mort.',
  auteur: 'Exemple',
  statut: 'En cours',
  titresAlternatifs: titresAlternatifsReference,
);
