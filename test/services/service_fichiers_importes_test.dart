// Import de fichiers (CBZ, PDF, EPUB sans DRM), lecture et suppression.
// Base en mémoire ; les fichiers d'essai sont générés dans un dossier
// temporaire (aucun réseau).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliotheque_perso/donnees/depot_categories.dart';
import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_fichiers_importes.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_positions_lecture.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/fichier_importe.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/analyse_fichiers_importes.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_export.dart';
import 'package:bibliotheque_perso/services/service_fichiers_importes.dart';
import 'package:bibliotheque_perso/services/service_import.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

/// Petite image PNG (en-tête seulement : suffit pour une page).
final List<int> _png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

List<int> _zip(Map<String, List<int>> entrees) {
  final archive = Archive();
  entrees.forEach((nom, octets) => archive.add(ArchiveFile.bytes(nom, octets)));
  return ZipEncoder().encode(archive);
}

const String _container =
    '<?xml version="1.0"?><container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
    '<rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

const String _opf =
    '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
    'version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    "<dc:title>L'Île &amp; la mer</dc:title><dc:creator>Jeanne Auteur"
    '</dc:creator><dc:language>fr-FR</dc:language></metadata><manifest>'
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
    'properties="nav"/><item id="c1" href="texte/chap%201.xhtml" '
    'media-type="application/xhtml+xml"/><item id="c2" href="texte/c2.xhtml" '
    'media-type="application/xhtml+xml"/><item id="img" '
    'href="images/a.png" media-type="image/png"/></manifest><spine>'
    '<itemref idref="c1"/><itemref idref="c2" linear="no"/></spine></package>';

const String _nav =
    '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
    '<nav epub:type="toc"><ol><li><a href="texte/chap%201.xhtml#debut">'
    'Chapitre <b>un</b></a></li></ol></nav></body></html>';

const String _chapitre1 =
    '<html><head><script>alert(1)</script></head><body><p>Bonjour</p>'
    '<img src="../images/a.png" alt=""/></body></html>';

Map<String, List<int>> _entreesEpub({String? encryption, bool rights = false}) {
  return <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(_container),
    if (encryption != null) 'META-INF/encryption.xml': utf8.encode(encryption),
    if (rights) 'META-INF/rights.xml': utf8.encode('<rights/>'),
    'OEBPS/content.opf': utf8.encode(_opf),
    'OEBPS/nav.xhtml': utf8.encode(_nav),
    'OEBPS/texte/chap 1.xhtml': utf8.encode(_chapitre1),
    'OEBPS/texte/c2.xhtml': utf8.encode('<html><body>Annexe</body></html>'),
    'OEBPS/images/a.png': _png,
  };
}

String _encryption(String algorithme) =>
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>'
    '<enc:EncryptionMethod Algorithm="$algorithme"/><enc:CipherData>'
    '<enc:CipherReference URI="OEBPS/texte/c2.xhtml"/></enc:CipherData>'
    '</enc:EncryptedData></encryption>';

const String _pdf =
    '%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
    '2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj\n'
    'trailer << /Root 1 0 R /Size 3 >>\n%%EOF\n';

const String _pdfChiffre =
    '%PDF-1.6\n1 0 obj << /Type /Catalog >> endobj\n'
    '5 0 obj << /Filter /Standard /V 4 /R 4 >> endobj\n'
    'trailer << /Root 1 0 R /Encrypt 5 0 R /Size 6 >>\n%%EOF\n';

void main() {
  late Database base;
  late Directory dossier;
  late StockageTelechargements stockage;
  late DepotTitres depotTitres;
  late DepotChapitres depotChapitres;
  late DepotSources depotSources;
  late ServiceFichiersImportes service;

  String ecrire(String nom, List<int> octets) {
    final chemin = p.join(dossier.path, 'origine', nom);
    File(chemin)
      ..createSync(recursive: true)
      ..writeAsBytesSync(octets);
    return chemin;
  }

  setUp(() async {
    base = await ouvrirBaseDeTest();
    dossier = await Directory.systemTemp.createTemp('fichiers_importes_');
    stockage = StockageTelechargements(p.join(dossier.path, 'bibliotheque'));
    depotTitres = DepotTitres(base);
    depotChapitres = DepotChapitres(base);
    depotSources = DepotSources(base);
    service = ServiceFichiersImportes(
      depotFichiersImportes: DepotFichiersImportes(base),
      depotPositions: DepotPositionsLecture(base),
      depotTitres: depotTitres,
      depotChapitres: depotChapitres,
      stockage: stockage,
      horloge: () => DateTime.utc(2026, 11, 28, 12),
    );
  });

  tearDown(() async {
    await base.close();
    await dossier.delete(recursive: true);
  });

  group('import', () {
    test('un CBZ valide est copié et devient un titre manga', () async {
      final chemin = ecrire('Mon tome 1.cbz', _zip({'p1.png': _png}));
      final resultats = await service.importer(<String>[chemin]);
      expect(resultats.single.statut, StatutImportFichier.importe);
      final titre = resultats.single.titre!;
      expect(titre.nom, 'Mon tome 1');
      expect(titre.typeTitre, TypeTitre.manga);
      final chapitre = resultats.single.chapitre!;
      expect(
        ServiceFichiersImportes.formatDuChapitre(chapitre),
        FormatFichierLocal.cbz,
      );
      expect(await service.nombrePagesCbz(chapitre), 1);
      expect(await service.pageCbz(chapitre, 0), _png);
      // Le fichier d'origine n'est pas touché.
      expect(File(chemin).existsSync(), isTrue);
    });

    test(
      'les résultats suivent l’ordre des fichiers et chaque refus a son motif',
      () async {
        final chemins = <String>[
          ecrire('notes.txt', utf8.encode('texte')),
          ecrire('faux.cbz', utf8.encode('pas une archive')),
          ecrire('vide.cbz', _zip({'info.txt': utf8.encode('x')})),
          ecrire(
            'protege.epub',
            _zip(
              _entreesEpub(
                encryption: _encryption(
                  'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
                ),
              ),
            ),
          ),
          ecrire('adobe.epub', _zip(_entreesEpub(rights: true))),
          ecrire('chiffre.pdf', utf8.encode(_pdfChiffre)),
          ecrire('vide.pdf', <int>[]),
          p.join(dossier.path, 'absent.pdf'),
        ];
        final statuts = (await service.importer(chemins))
            .map((r) => r.statut)
            .toList();
        expect(statuts, <StatutImportFichier>[
          StatutImportFichier.formatNonPrisEnCharge,
          StatutImportFichier.illisible,
          StatutImportFichier.illisible,
          StatutImportFichier.protegeParDrm,
          StatutImportFichier.protegeParDrm,
          StatutImportFichier.protegeParDrm,
          StatutImportFichier.illisible,
          StatutImportFichier.erreur,
        ]);
        // Aucun titre ni aucune copie pour un fichier refusé.
        expect(await depotTitres.chargerTitres(), isEmpty);
        expect(Directory(stockage.dossierRacine).existsSync(), isFalse);
      },
    );

    test(
      'un EPUB valide prend le titre, l’auteur et la langue de ses métadonnées',
      () async {
        final chemin = ecrire('livre.epub', _zip(_entreesEpub()));
        final resultat = (await service.importer(<String>[chemin])).single;
        expect(resultat.statut, StatutImportFichier.importe);
        expect(resultat.titre!.nom, "L'Île & la mer");
        expect(resultat.titre!.auteur, 'Jeanne Auteur');
        expect(resultat.titre!.typeTitre, TypeTitre.livre);
        expect(resultat.chapitre!.langue, 'fr');
      },
    );

    test(
      'un EPUB dont seules les polices sont obfusquées est accepté',
      () async {
        final chemin = ecrire(
          'polices.epub',
          _zip(
            _entreesEpub(
              encryption: _encryption('http://www.idpf.org/2008/embedding'),
            ),
          ),
        );
        final resultat = (await service.importer(<String>[chemin])).single;
        expect(resultat.statut, StatutImportFichier.importe);
      },
    );

    test('un PDF minimal est importé et son chemin est lisible', () async {
      final chemin = ecrire('Rapport.pdf', utf8.encode(_pdf));
      final resultat = (await service.importer(<String>[chemin])).single;
      expect(resultat.statut, StatutImportFichier.importe);
      expect(resultat.titre!.nom, 'Rapport');
      final copie = await service.cheminPdf(resultat.chapitre!);
      expect(File(copie).readAsStringSync(), _pdf);
      expect(copie, isNot(chemin));
    });

    test('le même contenu renommé est refusé comme doublon', () async {
      final octets = _zip({'p1.png': _png});
      final resultats = await service.importer(<String>[
        ecrire('a.cbz', octets),
        ecrire('b.cbz', octets),
      ]);
      expect(resultats[0].statut, StatutImportFichier.importe);
      expect(resultats[1].statut, StatutImportFichier.doublon);
      expect(resultats[1].titre?.id, resultats[0].titre!.id);
      expect(await depotTitres.chargerTitres(), hasLength(1));
    });

    test(
      'deux imports lancés ensemble sont traités l’un après l’autre',
      () async {
        final octets = _zip({'p1.png': _png});
        final premier = service.importer(<String>[ecrire('a.cbz', octets)]);
        final second = service.importer(<String>[ecrire('b.cbz', octets)]);
        final resultats = await Future.wait(
          <Future<List<ResultatImportFichier>>>[premier, second],
        );
        expect(resultats[0].single.statut, StatutImportFichier.importe);
        expect(resultats[1].single.statut, StatutImportFichier.doublon);
      },
    );
  });

  group('lecture', () {
    test('la structure EPUB suit le spine avec les titres de la table des matières', () async {
      final chemin = ecrire('livre.epub', _zip(_entreesEpub()));
      final chapitre = (await service.importer(<String>[chemin]))
          .single
          .chapitre!;
      final contenu = await service.contenuEpub(chapitre);
      expect(contenu.sections, hasLength(2));
      expect(contenu.sections[0].chemin, 'OEBPS/texte/chap 1.xhtml');
      expect(contenu.sections[0].titre, 'Chapitre un');
      expect(contenu.sections[1].titre, isNull);
      expect(contenu.sections[1].estLineaire, isFalse);
    });

    test(
      'une section EPUB intègre ses images en data URI et perd ses scripts',
      () async {
        final chemin = ecrire('livre.epub', _zip(_entreesEpub()));
        final chapitre = (await service.importer(<String>[chemin]))
            .single
            .chapitre!;
        final html = await service.sectionEpub(chapitre, 0);
        expect(
          html,
          contains('src="data:image/png;base64,${base64Encode(_png)}"'),
        );
        expect(html, isNot(contains('<script')));
        expect(html, contains('Bonjour'));
        expect(
          () => service.sectionEpub(chapitre, 5),
          throwsA(isA<ErreurService>()),
        );
      },
    );

    test('un chapitre d’un autre format est refusé par le lecteur', () async {
      final chemin = ecrire('a.cbz', _zip({'p1.png': _png}));
      final chapitre = (await service.importer(<String>[chemin]))
          .single
          .chapitre!;
      expect(() => service.cheminPdf(chapitre), throwsA(isA<ErreurService>()));
      expect(
        () => service.contenuEpub(chapitre),
        throwsA(isA<ErreurService>()),
      );
    });

    test('la position de lecture est enregistrée puis relue', () async {
      final chemin = ecrire('livre.epub', _zip(_entreesEpub()));
      final chapitre = (await service.importer(<String>[chemin]))
          .single
          .chapitre!;
      await service.enregistrerSection(chapitre.id!, 1, fraction: 1.7);
      final position = await service.chargerPosition(chapitre.id!);
      expect(position?.section, 1);
      expect(position?.fraction, 1.0);
      await service.enregistrerPage(chapitre.id!, 3, nombrePages: 10);
      expect((await service.chargerPosition(chapitre.id!))?.page, 3);
    });
  });

  group('suppression', () {
    test('supprimer un import efface le titre puis le fichier copié', () async {
      final chemin = ecrire('a.cbz', _zip({'p1.png': _png}));
      final resultat = (await service.importer(<String>[chemin])).single;
      final copie = stockage.cheminFichierImporte(
        resultat.chapitre!.nomArchive!,
      );
      expect(File(copie).existsSync(), isTrue);
      expect(await service.supprimerImport(resultat.titre!), isTrue);
      expect(await depotTitres.chargerTitres(), isEmpty);
      expect(File(copie).existsSync(), isFalse);
      expect(File(chemin).existsSync(), isTrue);
    });

    test('un titre d’un site ne se supprime pas comme un import', () async {
      final source = await depotSources.enregistrerSource(sourceMangaDex);
      final titre = await depotTitres.enregistrerTitre(
        Titre(
          idSource: source.id,
          urlTitre: 'https://mangadex.org/title/x',
          nom: 'X',
        ),
      );
      expect(
        () => service.supprimerImport(titre),
        throwsA(isA<ErreurService>()),
      );
    });
  });

  group('règles pures', () {
    test('les signatures distinguent zip et PDF', () {
      expect(
        AnalyseFichiersImportes.aSignatureAttendue(
          FormatFichierLocal.epub,
          _zip({
            'a': <int>[1],
          }),
        ),
        isTrue,
      );
      expect(
        AnalyseFichiersImportes.aSignatureAttendue(
          FormatFichierLocal.pdf,
          utf8.encode('xx%PDF-1.7'),
        ),
        isTrue,
      );
      expect(
        AnalyseFichiersImportes.aSignatureAttendue(
          FormatFichierLocal.cbz,
          utf8.encode('%PDF-1.7'),
        ),
        isFalse,
      );
    });

    test('la clé /EncryptMetadata seule ne compte pas, /Encrypt oui', () {
      expect(
        AnalyseFichiersImportes.contientChiffrementPdf(
          utf8.encode('/EncryptMetadata false'),
        ),
        isFalse,
      );
      expect(
        AnalyseFichiersImportes.contientChiffrementPdf(
          utf8.encode('<</Encrypt 5 0 R>>'),
        ),
        isTrue,
      );
    });

    test(
      'un chiffrement sans algorithme lisible est considéré comme un DRM',
      () {
        expect(
          AnalyseFichiersImportes.chiffreDesContenus(
            '<EncryptedData><CipherData/></EncryptedData>',
          ),
          isTrue,
        );
        expect(
          AnalyseFichiersImportes.chiffreDesContenus(
            _encryption('http://ns.adobe.com/pdf/enc#RC'),
          ),
          isFalse,
        );
      },
    );
  });

  group('autres services', () {
    test(
      'l’export JSON écarte la source « Fichiers locaux » et ses titres',
      () async {
        await depotSources.enregistrerSource(sourceMangaDex);
        await service.importer(<String>[
          ecrire('a.cbz', _zip({'p1.png': _png})),
        ]);
        final export = ServiceExport(
          depotSources: depotSources,
          depotTitres: depotTitres,
          depotChapitres: depotChapitres,
          depotListes: DepotListes(base),
          depotCategories: DepotCategories(base),
          dossierExports: ServiceExport.cheminDossierExports(dossier.path),
          serviceParametres: ServiceParametres(DepotParametres(base)),
          versionApplication: '0.4.0',
        );
        final contenu = await export.chargerContenu();
        expect(contenu.sources.map((s) => s.urlBase), <String>[
          'https://mangadex.org',
        ]);
        expect(contenu.titres, isEmpty);
      },
    );

    test('l’import JSON reconnaît les lignes de fichiers locaux à ignorer', () {
      expect(
        ServiceImport.estLigneFichiersLocaux(<String, Object?>{
          'urlBase': 'local://fichiers-locaux',
        }),
        isTrue,
      );
      expect(
        ServiceImport.estLigneFichiersLocaux(<String, Object?>{
          'nom': 'Livre',
          'sites': <Object?>[
            <String, Object?>{'url': 'local://fichiers-locaux/abc'},
          ],
        }),
        isTrue,
      );
      expect(
        ServiceImport.estLigneFichiersLocaux(<String, Object?>{
          'url': 'https://mangadex.org/title/x',
        }),
        isFalse,
      );
    });

    test(
      'la file de téléchargement ne touche jamais un fichier importé',
      () async {
        final client = creerClientTest(
          (requete) async => http.Response('introuvable', 404),
          HorlogeFactice(),
        );
        final depotParametres = DepotParametres(base);
        final telechargement = ServiceTelechargement(
          depotTelechargements: DepotTelechargements(base),
          depotChapitres: depotChapitres,
          depotTitres: depotTitres,
          depotListes: DepotListes(base),
          depotSources: depotSources,
          stockage: stockage,
          fabriqueSources: FabriqueSources(client),
          client: client,
          serviceParametres: ServiceParametres(depotParametres),
          depotParametres: depotParametres,
        );
        final resultat = (await service.importer(<String>[
          ecrire('a.cbz', _zip({'p1.png': _png})),
        ])).single;
        final id = resultat.chapitre!.id!;
        await expectLater(
          telechargement.telechargerChapitre(id),
          throwsA(isA<ErreurService>()),
        );
        await expectLater(
          telechargement.supprimerTelechargement(id),
          throwsA(isA<ErreurService>()),
        );
        await telechargement.retirerGarde(id);
        expect((await depotChapitres.chargerChapitre(id))!.estGarde, isTrue);
        expect(
          (await telechargement.appliquerRegles(resultat.titre!.id!)).idsVoulus,
          isEmpty,
        );
        // Fichier disparu du disque : il n'est pas « à retélécharger ».
        File(stockage.cheminFichierImporte(resultat.chapitre!.nomArchive!))
            .deleteSync();
        await telechargement.reparerArchivesManquantes();
        final relu = await depotChapitres.chargerChapitre(id);
        expect(relu!.estTelecharge, isTrue);
        expect(relu.nomArchive, resultat.chapitre!.nomArchive);
        await telechargement.fermer();
      },
    );

    test(
      'supprimer le titre depuis la file efface aussi le fichier importé',
      () async {
        final client = creerClientTest(
          (requete) async => http.Response('introuvable', 404),
          HorlogeFactice(),
        );
        final depotParametres = DepotParametres(base);
        final telechargement = ServiceTelechargement(
          depotTelechargements: DepotTelechargements(base),
          depotChapitres: depotChapitres,
          depotTitres: depotTitres,
          depotListes: DepotListes(base),
          depotSources: depotSources,
          stockage: stockage,
          fabriqueSources: FabriqueSources(client),
          client: client,
          serviceParametres: ServiceParametres(depotParametres),
          depotParametres: depotParametres,
        );
        final resultat = (await service.importer(<String>[
          ecrire('a.cbz', _zip({'p1.png': _png})),
        ])).single;
        final copie = stockage.cheminFichierImporte(
          resultat.chapitre!.nomArchive!,
        );
        await telechargement.supprimerTitre(resultat.titre!.id!);
        expect(File(copie).existsSync(), isFalse);
        expect(await depotTitres.chargerTitres(), isEmpty);
        await telechargement.fermer();
      },
    );
  });

  test('un chapitre sans fichier importé n’a pas de format', () {
    final chapitre = Chapitre(
      idTitre: 1,
      idSource: 1,
      urlChapitre: 'https://exemple.fr/c1',
      nom: 'C1',
      numero: 1,
      dateDetection: DateTime.utc(2026),
      nomArchive: 'manga/X/ch1.fr.zip',
    );
    expect(ServiceFichiersImportes.formatDuChapitre(chapitre), isNull);
    expect(
      const Source(
        nom: 'x',
        urlBase: 'local://fichiers-locaux',
        typeSource: TypeSource.generique,
      ).estFichiersLocaux,
      isTrue,
    );
  });
}
