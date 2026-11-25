// ServiceImport (tâche R8) : réimport d'un export JSON par fusion.
// Bases en mémoire et dossier temporaire ; aucun appel réseau.
import 'dart:convert';
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/depot_titres_sources.dart';
import 'package:bibliotheque_perso/donnees/gestionnaire_transactions.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/modeles/titre_alternatif.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_export.dart';
import 'package:bibliotheque_perso/services/service_import.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as chemins;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';

/// Une base en mémoire avec ses dépôts et les deux services.
class _Bibliotheque {
  _Bibliotheque(this.base)
    : sources = DepotSources(base),
      titres = DepotTitres(base),
      liens = DepotTitresSources(base),
      listes = DepotListes(base),
      parametres = ServiceParametres(DepotParametres(base));

  final Database base;
  final DepotSources sources;
  final DepotTitres titres;
  final DepotTitresSources liens;
  final DepotListes listes;
  final ServiceParametres parametres;

  ServiceExport get export => ServiceExport(
    depotSources: sources,
    depotTitres: titres,
    depotChapitres: DepotChapitres(base),
    depotListes: listes,
    depotCategories: DepotCategories(base),
    dossierExports: Directory.systemTemp.path,
    serviceParametres: parametres,
    versionApplication: '0.2.0',
    horloge: () => DateTime.utc(2026, 11, 17, 10),
    depotTitresSources: liens,
  );

  /// Import « tout ou rien » (V2), assemblé comme dans l'application.
  ServiceImport get import => ServiceImport(
    depotSources: sources,
    depotTitres: titres,
    depotTitresSources: liens,
    depotListes: listes,
    depotCategories: DepotCategories(base),
    serviceParametres: parametres,
    depotParametres: DepotParametres(base),
    gestionnaireTransactions: GestionnaireTransactions(base),
  );

  /// Import sans transaction commune (ancien assemblage).
  ServiceImport get importSansTransaction => ServiceImport(
    depotSources: sources,
    depotTitres: titres,
    depotTitresSources: liens,
    depotListes: listes,
    depotCategories: DepotCategories(base),
    serviceParametres: parametres,
  );

  /// JSON de l'export de cette base (date fixe).
  Future<String> json() async =>
      ServiceExport.produireJson(await export.chargerContenu());

  Future<int> ajouterALaListe(String nom, int idTitre) async {
    final liste =
        await listes.chargerListeParNom(nom) ?? await listes.creerListe(nom);
    await listes.ajouterTitre(liste.id!, idTitre);
    return liste.id!;
  }
}

/// Dépôt des titres qui refuse toute écriture par une [ArgumentError]
/// (valeur refusée par un dépôt, cas rare mais possible).
class _DepotTitresPiege extends DepotTitres {
  const _DepotTitresPiege(super.base);

  @override
  Future<Titre> enregistrerTitre(
    Titre titre, {
    List<String>? categories,
    DatabaseExecutor? executeur,
  }) => throw ArgumentError.value(titre.nom, 'titre', 'refusé par le test');
}

void main() {
  late _Bibliotheque origine;
  late _Bibliotheque cible;

  setUp(() async {
    origine = _Bibliotheque(await ouvrirBaseDeTest());
    cible = _Bibliotheque(await ouvrirBaseDeTest());
  });

  tearDown(() async {
    await origine.base.close();
    await cible.base.close();
  });

  /// Remplit la base d'origine : quatre sites (dont un générique avec ses
  /// sélecteurs et un désactivé), trois titres (sites secondaires, lien
  /// seul, listes système et du client, catégories, réglages du client).
  Future<void> remplirOrigine() async {
    final mangaDex = await origine.sources.enregistrerSource(
      const Source(
        nom: 'MangaDex',
        urlBase: 'https://mangadex.org',
        typeSource: TypeSource.mangaDex,
        langueParDefaut: 'fr,en',
      ),
    );
    final etagere = await origine.sources.enregistrerSource(
      const Source(
        nom: "L'Étagère",
        urlBase: 'https://etagere.example',
        typeSource: TypeSource.madara,
        estActive: false,
      ),
    );
    final generique = await origine.sources.enregistrerSource(
      const Source(
        nom: 'Générique',
        urlBase: 'https://generique.example',
        typeSource: TypeSource.generique,
        configurationSelecteurs:
            '{"selecteurTitre":"h1","selecteurLiensChapitres":"ul.ch a"}',
      ),
    );
    final protege = await origine.sources.enregistrerSource(
      const Source(
        nom: 'Protégé',
        urlBase: 'https://protege.example',
        typeSource: TypeSource.generique,
      ),
    );

    final premier = await origine.titres.enregistrerTitre(
      Titre(
        idSource: mangaDex.id,
        urlTitre: urlTitreReference,
        nom: "Death's Daughter — l'épée d'ébène",
        typeTitre: TypeTitre.manga,
        urlCouverture: 'https://uploads.mangadex.org/covers/exemple.jpg',
        resume: 'Une jeune fille élevée par la Mort.',
        auteur: 'Exemple',
        statut: 'En cours',
        niveauContenu: niveauContenuSuggestif,
        titresAlternatifs: const <TitreAlternatif>[
          TitreAlternatif(nom: '死神に育てられた少女', langue: 'ja'),
          TitreAlternatif(nom: 'La fille de la Mort', langue: 'fr'),
        ],
      ),
      categories: <String>['Action', 'Comédie'],
    );
    await origine.titres.enregistrerLanguesPreferees(premier.id!, 'fr,en');
    await origine.titres.enregistrerCouvertureChoisie(
      premier.id!,
      'https://uploads.mangadex.org/covers/tome2.jpg',
    );
    await origine.liens.ajouterSourceSecondaire(
      premier.id!,
      etagere.id!,
      'https://etagere.example/manga/death',
    );
    await origine.liens.ajouterSourceSecondaire(
      premier.id!,
      protege.id!,
      'https://protege.example/oeuvre/death',
      lienSeul: true,
    );
    await origine.ajouterALaListe(nomListeFavoris, premier.id!);
    await origine.ajouterALaListe('À relire [été]', premier.id!);

    final second = await origine.titres.enregistrerTitre(
      Titre(
        idSource: generique.id,
        urlTitre: 'https://generique.example/oeuvre/un-livre',
        nom: 'Un *livre*',
        typeTitre: TypeTitre.livre,
      ),
    );
    await origine.ajouterALaListe(nomListeSuivis, second.id!);
    await origine.ajouterALaListe(nomListeEnAttente, second.id!);
    await origine.ajouterALaListe('Lectures du soir', second.id!);

    await origine.titres.enregistrerTitre(
      Titre(
        idSource: etagere.id,
        urlTitre: 'https://etagere.example/manga/sans-liste',
        nom: 'Sans liste',
      ),
    );
    await origine.parametres.enregistrerLangues(<String>['fr', 'ja']);
    await origine.parametres.enregistrerNiveauxContenu(<String>['safe']);
  }

  group('aller-retour export puis import', () {
    test('une base vide retrouve les mêmes titres, sites, listes et '
        'réglages', () async {
      await remplirOrigine();
      final json = await origine.json();

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.erreurs, isEmpty);
      expect(resultat.titresAjoutes, 3);
      expect(resultat.titresCompletes, 0);
      expect(resultat.titresIgnores, 0);
      expect(resultat.sitesAjoutes, 4);
      expect(resultat.listesAjoutees, 2);
      expect(resultat.reglagesGenerauxAppliques, isTrue);
      expect(resultat.chapitresALaProchaineVerification, isTrue);
      expect(resultat.resume, contains('prochaine vérification'));
      // L'export de la base importée est identique à celui d'origine : même
      // contenu, même ordre (sites, titres, sites des titres, listes).
      expect(await cible.json(), json);
    });

    test('le site générique garde ses sélecteurs et la fiche son '
        'résumé', () async {
      await remplirOrigine();
      await cible.import.importerTexte(await origine.json());

      final generique = await cible.sources.chargerSourceParUrl(
        'https://generique.example',
      );
      expect(
        generique!.configurationSelecteurs,
        '{"selecteurTitre":"h1","selecteurLiensChapitres":"ul.ch a"}',
      );
      final titre = await cible.titres.chargerTitreParUrl(urlTitreReference);
      expect(titre!.resume, 'Une jeune fille élevée par la Mort.');
      expect(titre.languesPreferees, 'fr,en');
      expect(
        titre.couvertureChoisie,
        'https://uploads.mangadex.org/covers/tome2.jpg',
      );
      // Jamais vérifié : la prochaine vérification récupère les chapitres.
      expect(titre.dateDerniereVerification, isNull);
      final liens = await cible.liens.chargerLiensTitre(titre.id!);
      expect(liens.map((l) => l.estLienSeul), <bool>[false, false, true]);
    });

    test('réimporter dans la même base n\'ajoute rien', () async {
      await remplirOrigine();
      final json = await origine.json();
      await cible.import.importerTexte(json);
      final avant = await cible.json();

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.erreurs, isEmpty);
      expect(resultat.titresAjoutes, 0);
      expect(resultat.titresCompletes, 0);
      expect(resultat.titresIgnores, 3);
      expect(resultat.sitesAjoutes, 0);
      expect(resultat.listesAjoutees, 0);
      expect(resultat.chapitresALaProchaineVerification, isFalse);
      expect(await cible.json(), avant);
    });

    test(
      "importer son propre export ne change rien à la base d'origine",
      () async {
        await remplirOrigine();
        final json = await origine.json();
        final resultat = await origine.import.importerTexte(json);
        expect(resultat.titresIgnores, 3);
        expect(resultat.erreurs, isEmpty);
        expect(await origine.json(), json);
      },
    );
  });

  group('fusion avec une base existante', () {
    test('un titre présent est complété sans être dupliqué ni '
        'appauvri', () async {
      await remplirOrigine();
      final json = await origine.json();
      // La cible connaît déjà le premier titre, autrement : autre liste,
      // une autre catégorie, d'autres langues, sans site secondaire.
      final mangaDex = await cible.sources.enregistrerSource(
        const Source(
          nom: 'MangaDex (perso)',
          urlBase: 'https://www.mangadex.org',
          typeSource: TypeSource.mangaDex,
        ),
      );
      final existant = await cible.titres.enregistrerTitre(
        Titre(
          idSource: mangaDex.id,
          urlTitre: urlTitreReference,
          nom: 'Nom choisi sur cet appareil',
        ),
        categories: <String>['Drame'],
      );
      await cible.titres.enregistrerLanguesPreferees(existant.id!, 'es');
      await cible.ajouterALaListe(nomListePlanifie, existant.id!);
      await cible.parametres.enregistrerLangues(<String>['de']);

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.erreurs, isEmpty);
      expect(resultat.titresAjoutes, 2);
      expect(resultat.titresCompletes, 1);
      // MangaDex reconnu par son hôte (www.) : pas de second MangaDex.
      expect(resultat.sitesAjoutes, 3);
      final sources = await cible.sources.chargerSources();
      expect(sources.where((s) => s.typeSource == TypeSource.mangaDex), [
        mangaDex,
      ]);
      // Réglages généraux gardés : la bibliothèque n'était pas vide.
      expect(resultat.reglagesGenerauxAppliques, isFalse);
      expect(await cible.parametres.chargerLangues(), <String>['de']);

      final titres = await cible.titres.chargerTitres();
      expect(titres, hasLength(3));
      final complete = (await cible.titres.chargerTitre(existant.id!))!;
      expect(complete.nom, 'Nom choisi sur cet appareil');
      expect(complete.languesPreferees, 'es');
      expect(complete.niveauContenu, niveauContenuSuggestif);
      expect(
        complete.couvertureChoisie,
        'https://uploads.mangadex.org/covers/tome2.jpg',
      );
      expect(
        complete.titresAlternatifs.map((a) => a.nom),
        containsAll(<String>['死神に育てられた少女', 'La fille de la Mort']),
      );
      final listes = await cible.listes.chargerListesDuTitre(existant.id!);
      expect(listes.map((l) => l.nom), <String>[
        nomListeFavoris,
        nomListePlanifie,
        'À relire [été]',
      ]);
      final categories = await DepotCategories(cible.base)
          .chargerCategoriesDuTitre(existant.id!);
      expect(categories.map((c) => c.nom), <String>[
        'action',
        'comédie',
        'drame',
      ]);
      final liens = await cible.liens.chargerLiensTitre(existant.id!);
      expect(liens, hasLength(3));
      expect(liens.first.idSource, mangaDex.id);
      expect(liens.first.estPrincipale, isTrue);
    });

    test('un titre déjà lié comme site secondaire est reconnu', () async {
      await remplirOrigine();
      final json = await origine.json();
      // Dans la cible, le titre a pour principal L'Étagère, et MangaDex
      // (l'adresse principale du fichier) comme site secondaire.
      final etagere = await cible.sources.enregistrerSource(
        const Source(
          nom: 'Étagère',
          urlBase: 'https://etagere.example',
          typeSource: TypeSource.madara,
        ),
      );
      final mangaDex = await cible.sources.enregistrerSource(
        const Source(
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
        ),
      );
      final existant = await cible.titres.enregistrerTitre(
        Titre(
          idSource: etagere.id,
          urlTitre: 'https://etagere.example/manga/death',
          nom: 'Death',
        ),
      );
      await cible.liens.ajouterSourceSecondaire(
        existant.id!,
        mangaDex.id!,
        urlTitreReference,
      );

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.erreurs, isEmpty);
      expect(resultat.titresAjoutes, 2);
      expect(resultat.titresCompletes, 1);
      final liens = await cible.liens.chargerLiensTitre(existant.id!);
      // Le site principal n'est pas changé ; le lien seul est ajouté.
      expect(liens.first.urlTitre, 'https://etagere.example/manga/death');
      expect(liens.map((l) => l.urlTitre), <String>[
        'https://etagere.example/manga/death',
        urlTitreReference,
        'https://protege.example/oeuvre/death',
      ]);
      expect(liens.last.estLienSeul, isTrue);
    });

    test("l'adresse exacte du site l'emporte sur un autre site du même "
        'domaine', () async {
      // Deux sites sur le même domaine : « A » (sans www) vient en premier
      // par ordre alphabétique, mais le titre est sur « B » (www).
      await cible.sources.enregistrerSource(
        const Source(
          nom: 'A',
          urlBase: 'https://exemple.org',
          typeSource: TypeSource.madara,
        ),
      );
      final b = await cible.sources.enregistrerSource(
        const Source(
          nom: 'B',
          urlBase: 'https://www.exemple.org',
          typeSource: TypeSource.madara,
        ),
      );
      final json = jsonEncode(<String, Object?>{
        'format': 'bibliotheque_perso-export',
        'version': 1,
        'titres': <Object?>[
          // urlSource connue et exacte.
          <String, Object?>{
            'nom': 'Avec site',
            'url': 'https://www.exemple.org/manga/un',
            'urlSource': 'https://www.exemple.org',
          },
          // Sans urlSource : la racine exacte de l'adresse du titre.
          <String, Object?>{
            'nom': 'Sans site',
            'url': 'https://www.exemple.org/manga/deux',
          },
        ],
      });

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.erreurs, isEmpty);
      for (final url in <String>[
        'https://www.exemple.org/manga/un',
        'https://www.exemple.org/manga/deux',
      ]) {
        expect((await cible.titres.chargerTitreParUrl(url))!.idSource, b.id);
      }
    });

    test('les réglages généraux sont appliqués sur demande', () async {
      await remplirOrigine();
      await cible.parametres.enregistrerLangues(<String>['de']);
      final mangaDex = await cible.sources.enregistrerSource(sourceMangaDex);
      await cible.titres.enregistrerTitre(titreReference(mangaDex.id!));

      final resultat = await cible.import.importerTexte(
        await origine.json(),
        appliquerReglagesGeneraux: true,
      );

      expect(resultat.reglagesGenerauxAppliques, isTrue);
      expect(await cible.parametres.chargerLangues(), <String>['fr', 'ja']);
      expect(await cible.parametres.chargerNiveauxContenu(), <String>['safe']);
    });
  });

  group('erreurs par ligne', () {
    Map<String, Object?> exportMinimal(List<Object?> titres) =>
        <String, Object?>{
          'format': 'bibliotheque_perso-export',
          'version': 2,
          'sources': <Object?>[
            <String, Object?>{
              'nom': 'MangaDex',
              'urlBase': 'https://mangadex.org',
              'type': 'mangaDex',
              'langues': <String>[],
              'active': true,
            },
            <String, Object?>{
              'nom': 'Futur',
              'urlBase': 'https://futur.example',
              'type': 'typeDuFutur',
            },
          ],
          'titres': titres,
        };

    test('une ligne fautive est signalée sans arrêter les autres', () async {
      final json = jsonEncode(
        exportMinimal(<Object?>[
          <String, Object?>{'url': 'https://mangadex.org/title/sans-nom'},
          'pas un objet',
          <String, Object?>{
            'nom': 'Site inconnu',
            'url': 'https://inconnu.example/titre/1',
            'source': 'Inconnu',
            'urlSource': 'https://inconnu.example',
          },
          <String, Object?>{
            'nom': 'Bon titre',
            'url': 'https://mangadex.org/title/bon',
            'urlSource': 'https://mangadex.org',
            'listes': <String>[nomListeSuivis],
          },
        ]),
      );

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.titresAjoutes, 1);
      expect(resultat.sitesAjoutes, 1);
      expect(resultat.erreurs, hasLength(4));
      final descriptions = resultat.erreurs.map((e) => e.description).toList();
      expect(descriptions, contains(startsWith('Site n°2 « Futur »')));
      expect(descriptions, contains('Titre n°1 : titre sans nom.'));
      expect(descriptions, contains('Titre n°2 : ligne illisible.'));
      expect(
        descriptions,
        contains(startsWith('Titre n°3 « Site inconnu » : site « Inconnu »')),
      );
      final bon = await cible.titres.chargerTitreParUrl(
        'https://mangadex.org/title/bon',
      );
      final listes = await cible.listes.chargerListesDuTitre(bon!.id!);
      expect(listes.single.nom, nomListeSuivis);
    });

    test(
      "un export du format 1 (sans « sites » ni sélecteurs) se lit",
      () async {
        final json = jsonEncode(<String, Object?>{
          'format': 'bibliotheque_perso-export',
          'version': 1,
          'reglages': <String, Object?>{
            'langues': <String>['fr'],
            'niveauxContenu': <String>['safe', 'suggestive'],
          },
          'listes': <Object?>[
            <String, Object?>{'nom': nomListeFavoris, 'systeme': true},
          ],
          'sources': <Object?>[
            <String, Object?>{
              'nom': 'MangaDex',
              'urlBase': 'https://mangadex.org',
              'type': 'mangaDex',
              'langues': <String>['fr'],
              'active': true,
            },
          ],
          'titres': <Object?>[
            <String, Object?>{
              'nom': 'Ancien',
              'type': 'manhwa',
              'url': 'https://mangadex.org/title/ancien',
              'source': 'MangaDex',
              'urlSource': 'https://mangadex.org',
              'listes': <String>[nomListeFavoris],
              'categories': <String>['Action'],
              'couvertureChoisie': 'ma couverture.png',
            },
          ],
        });

        final resultat = await cible.import.importerTexte(json);

        expect(resultat.versionFormat, 1);
        expect(resultat.erreurs, isEmpty);
        expect(resultat.titresAjoutes, 1);
        final titre = await cible.titres.chargerTitreParUrl(
          'https://mangadex.org/title/ancien',
        );
        expect(titre!.typeTitre, TypeTitre.manhwa);
        // Une image de l'appareil exportée par son seul nom est ignorée.
        expect(titre.couvertureChoisie, isNull);
        expect(await cible.parametres.chargerNiveauxContenu(), <String>[
          'safe',
          'suggestive',
        ]);
      },
    );
  });

  group('fichier refusé', () {
    Future<void> attendreRefus(String texte, String extrait) async {
      await expectLater(
        cible.import.importerTexte(texte),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains(extrait),
          ),
        ),
      );
      // Rien n'a été écrit.
      expect(await cible.sources.chargerSources(), isEmpty);
      expect(await cible.titres.chargerTitres(), isEmpty);
    }

    test('un JSON invalide donne une ErreurService claire', () async {
      await attendreRefus('{"format": "bibliotheque_perso-export", ', 'JSON');
    });

    test("un JSON d'un autre format est refusé", () async {
      await attendreRefus(
        '{"format": "autre-application", "version": 1, "titres": []}',
        "n'est pas un export de Bibliothèque perso",
      );
      await attendreRefus('[1, 2, 3]', "n'est pas un export");
    });

    test(
      "un format plus récent demande une mise à jour de l'application",
      () async {
        await attendreRefus(
          '{"format": "bibliotheque_perso-export", "version": 99, '
              '"titres": []}',
          'version plus récente',
        );
      },
    );

    test('un export sans liste de titres est refusé avant toute '
        'écriture', () async {
      await attendreRefus(
        '{"format": "bibliotheque_perso-export", "version": 2, '
            '"sources": [{"nom": "A", "urlBase": "https://a.example", '
            '"type": "madara"}], "titres": "abîmé"}',
        'incomplet',
      );
    });
  });

  group('importerFichier', () {
    late Directory dossier;

    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('bibliotheque_import');
    });

    tearDown(() async {
      if (await dossier.exists()) await dossier.delete(recursive: true);
    });

    test("lit un fichier UTF-8, même précédé d'une marque d'ordre des "
        'octets', () async {
      await remplirOrigine();
      final fichier = File(chemins.join(dossier.path, 'export.json'));
      await fichier.writeAsString(
        '${String.fromCharCode(0xFEFF)}${await origine.json()}',
        encoding: utf8,
      );
      final resultat = await cible.import.importerFichier(fichier.path);
      expect(resultat.titresAjoutes, 3);
    });

    test('un fichier introuvable donne une ErreurService', () async {
      await expectLater(
        cible.import.importerFichier(chemins.join(dossier.path, 'absent.json')),
        throwsA(isA<ErreurService>()),
      );
    });

    test('un fichier qui n\'est pas du texte UTF-8 est refusé', () async {
      final fichier = File(chemins.join(dossier.path, 'image.json'));
      await fichier.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0xC3, 0x28]);
      await expectLater(
        cible.import.importerFichier(fichier.path),
        throwsA(isA<ErreurService>()),
      );
    });
  });

  test('un double appel simultané partage le même import', () async {
    await remplirOrigine();
    final json = await origine.json();
    final service = cible.import;
    final a = service.importerTexte(json);
    final b = service.importerTexte(json);
    expect(identical(a, b), isTrue);
    expect((await a).titresAjoutes, 3);
    expect(await cible.titres.chargerTitres(), hasLength(3));
  });

  group('tout ou rien (V2)', () {
    /// Fait refuser par SQLite l'insertion du titre nommé « Un *livre* »
    /// (deuxième titre du fichier, par ordre alphabétique) : erreur de base
    /// inattendue au milieu de l'import.
    Future<void> pieger() => cible.base.execute(
      'CREATE TRIGGER piege BEFORE INSERT ON titres '
      "WHEN NEW.nom = 'Un *livre*' "
      "BEGIN SELECT RAISE(ABORT, 'disque plein simulé'); END",
    );

    test('une erreur de base au milieu annule tout : sites, listes, titres '
        'et réglages', () async {
      await remplirOrigine();
      final json = await origine.json();
      await pieger();

      await expectLater(
        cible.import.importerTexte(json),
        throwsA(
          isA<ErreurService>().having(
            (e) => e.message,
            'message',
            contains('entièrement annulé'),
          ),
        ),
      );

      expect(await cible.sources.chargerSources(), isEmpty);
      expect(await cible.titres.chargerTitres(), isEmpty);
      expect(
        (await cible.listes.chargerListes()).where((l) => !l.estSysteme),
        isEmpty,
      );
      expect(
        await cible.parametres.chargerLangues(),
        ServiceParametres.languesParDefaut,
      );
      // Le service reste utilisable : le piège retiré, l'import réussit.
      await cible.base.execute('DROP TRIGGER piege');
      expect((await cible.import.importerTexte(json)).titresAjoutes, 3);
    });

    test('sans gestionnaire de transactions, la même erreur reste notée sur '
        'sa ligne (ancien comportement)', () async {
      await remplirOrigine();
      final json = await origine.json();
      await pieger();

      final resultat = await cible.importSansTransaction.importerTexte(json);

      expect(resultat.titresAjoutes, 2);
      expect(resultat.erreurs.single.nom, 'Un *livre*');
    });

    test('les refus par ligne (site non configuré) n\'annulent rien', () async {
      final json = jsonEncode(<String, Object?>{
        'format': 'bibliotheque_perso-export',
        'version': 2,
        'sources': <Object?>[
          <String, Object?>{
            'nom': 'MangaDex',
            'urlBase': 'https://mangadex.org',
            'type': 'mangaDex',
          },
        ],
        'titres': <Object?>[
          <String, Object?>{
            'nom': 'Inconnu',
            'url': 'https://inconnu.example/t/1',
          },
          <String, Object?>{
            'nom': 'Connu',
            'url': 'https://mangadex.org/title/connu',
          },
        ],
      });

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.titresAjoutes, 1);
      expect(resultat.erreurs.single.nom, 'Inconnu');
      expect(await cible.titres.chargerTitres(), hasLength(1));
    });

    test('des réglages de site générique refusés : site importé sans '
        'réglages, erreur notée ; un site non générique n\'en garde '
        'aucun', () async {
      final json = jsonEncode(<String, Object?>{
        'format': 'bibliotheque_perso-export',
        'version': 2,
        'sources': <Object?>[
          <String, Object?>{
            'nom': 'Générique',
            'urlBase': 'https://generique.example',
            'type': 'generique',
            'configurationSelecteurs':
                '{"selecteurLiensChapitres":"a[href","selecteurTitre":"h1"}',
          },
          <String, Object?>{
            'nom': 'Madara',
            'urlBase': 'https://madara.example',
            'type': 'madara',
            'configurationSelecteurs': '{"selecteurTitre":"h1"}',
          },
          <String, Object?>{
            'nom': 'Propre',
            'urlBase': 'https://propre.example',
            'type': 'generique',
            'configurationSelecteurs':
                '{"selecteurTitre":" h1 ","inconnue":"x"}',
          },
        ],
        'titres': <Object?>[],
      });

      final resultat = await cible.import.importerTexte(json);

      expect(resultat.sitesAjoutes, 3);
      final erreur = resultat.erreurs.single;
      expect(erreur.partie, PartieImport.site);
      expect(erreur.nom, 'Générique');
      expect(erreur.message, contains('Liens des chapitres'));
      Future<String?> reglagesDe(String url) async =>
          (await cible.sources.chargerSourceParUrl(url))!
              .configurationSelecteurs;
      expect(await reglagesDe('https://generique.example'), isNull);
      expect(await reglagesDe('https://madara.example'), isNull);
      expect(
        await reglagesDe('https://propre.example'),
        '{"selecteurTitre":"h1"}',
      );
    });

    test('une ArgumentError pendant un import tout ou rien devient une '
        'ErreurService « annulé »', () async {
      await remplirOrigine();
      final json = await origine.json();
      final service = ServiceImport(
        depotSources: cible.sources,
        depotTitres: _DepotTitresPiege(cible.base),
        depotTitresSources: cible.liens,
        depotListes: cible.listes,
        depotCategories: DepotCategories(cible.base),
        gestionnaireTransactions: GestionnaireTransactions(cible.base),
      );

      await expectLater(
        service.importerTexte(json),
        throwsA(
          isA<ErreurService>()
              .having((e) => e.message, 'message', contains('annulé'))
              .having((e) => e.cause, 'cause', isA<ArgumentError>()),
        ),
      );
      expect(await cible.sources.chargerSources(), isEmpty);
    });

    test('un import transactionnel avec ServiceParametres mais sans '
        'DepotParametres est refusé à la construction', () {
      expect(
        () => ServiceImport(
          depotSources: cible.sources,
          depotTitres: cible.titres,
          depotTitresSources: cible.liens,
          depotListes: cible.listes,
          depotCategories: DepotCategories(cible.base),
          serviceParametres: cible.parametres,
          gestionnaireTransactions: GestionnaireTransactions(cible.base),
        ),
        throwsArgumentError,
      );
    });
  });
}
