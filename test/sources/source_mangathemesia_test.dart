import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/erreur_source.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:bibliotheque_perso/sources/source_mangathemesia.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'outils_tests_sources.dart';

/// Pages réelles du site de démonstration du thème MangaThemesia
/// (mangareader.themesia.com), enregistrées le 2026-11-17 et allégées.
/// Aucun appel réseau dans les tests.
const String urlBase = 'https://mangareader.themesia.com';
const String urlTitre =
    'https://mangareader.themesia.com/manga/kaze-no-doragon-raida/';
const String urlChapitre1 =
    'https://mangareader.themesia.com/kaze-no-doragon-raida-chapter-1/';
const String urlImage =
    'https://i3.wp.com/mangastream.themesia.com/wp-content/uploads/2019/04/'
    'sampel-compressed.jpg';

final String htmlAccueil = lireExemple(
  'exemples_html/mangathemesia_accueil.html',
);
final String htmlFiche = lireExemple('exemples_html/mangathemesia_fiche.html');
final String htmlChapitre = lireExemple(
  'exemples_html/mangathemesia_chapitre.html',
);
final String htmlRecherche = lireExemple(
  'exemples_html/mangathemesia_recherche.html',
);

/// Réponse HTML UTF-8. Le site de démonstration n'envoie pas de charset :
/// ClientHttpPoli décode alors en UTF-8, comme ici.
http.Response reponseHtml(String corps, {int statut = 200}) {
  return http.Response(
    corps,
    statut,
    headers: <String, String>{'content-type': 'text/html; charset=UTF-8'},
  );
}

/// Adaptateur branché sur [gestionnaire] (aucun réseau).
SourceMangaThemesia creerSource(
  Future<http.Response> Function(http.Request requete) gestionnaire, {
  String languesPreferees = '',
}) {
  final horloge = HorlogeFactice();
  return SourceMangaThemesia(
    creerClientTest(gestionnaire, horloge),
    urlBase: urlBase,
    languesPreferees: languesPreferees,
    maintenant: horloge.lire,
  );
}

void main() {
  test("la page d'accueil réelle est détectée comme MangaThemesia", () {
    expect(
      DetecteurTypeSite.detecterDepuisHtml(htmlAccueil),
      TypeSource.mangaThemesia,
    );
    expect(
      DetecteurTypeSite.detecterDepuisHtml(htmlFiche),
      TypeSource.mangaThemesia,
    );
  });

  test('la fabrique crée un SourceMangaThemesia', () {
    final fabrique = FabriqueSources(
      creerClientTest((r) async => reponseHtml(''), HorlogeFactice()),
    );
    final adaptateur = fabrique.creer(
      const Source(
        nom: 'Démo',
        urlBase: urlBase,
        typeSource: TypeSource.mangaThemesia,
        langueParDefaut: 'fr',
      ),
    );
    expect(adaptateur, isA<SourceMangaThemesia>());
    expect((adaptateur as SourceMangaThemesia).urlBase, urlBase);
    expect(adaptateur.languesPreferees, 'fr');
  });

  group('fiche (page réelle)', () {
    final fiche = SourceMangaThemesia.analyserFiche(
      htmlFiche,
      Uri.parse(urlTitre),
    );

    test('nom, titres alternatifs (japonais compris), couverture', () {
      expect(fiche.titre.nom, 'Kaze no Doragon Raida');
      expect(fiche.titre.titresAlternatifs.map((a) => a.nom), <String>[
        'Wind Dragon Rider',
        '風のドラゴンライダー',
      ]);
      expect(
        fiche.titre.urlCouverture,
        'https://i2.wp.com/mangareader.themesia.com/wp-content/uploads/'
        '2019/04/cover-23-compressed.jpg',
      );
    });

    test('résumé en paragraphes', () {
      final lignes = fiche.titre.resume!.split('\n');
      expect(lignes, hasLength(3));
      expect(lignes.first, startsWith('Lorem ipsum dolor sit amet'));
      expect(lignes.last, 'Credit: Freepik');
    });

    test('auteur, statut, type et genres', () {
      expect(fiche.titre.auteur, 'Garou');
      expect(fiche.titre.statut, 'Ongoing');
      expect(fiche.titre.typeTitre, TypeTitre.manga);
      expect(fiche.categories, <String>['Shounen']);
    });

    test('variante .infotable et .fmed (gabarits plus anciens)', () {
      const html = '''
<html><body><div class="bigcontent"><h1 class="entry-title">Ancien</h1>
<table class="infotable"><tr><td>Status</td><td>Completed</td></tr>
<tr><td>Type</td><td>Manhua</td></tr></table>
<div class="fmed"><b>Artist</b><span>Dessinateur</span></div>
<div class="fmed"><b>Author</b><span>Auteur A, Auteur B</span></div>
</div></body></html>''';
      final variante = SourceMangaThemesia.analyserFiche(
        html,
        Uri.parse(urlTitre),
      );
      expect(variante.titre.statut, 'Completed');
      expect(variante.titre.typeTitre, TypeTitre.manhua);
      expect(variante.titre.auteur, 'Auteur A, Auteur B, Dessinateur');
    });

    test("page qui n'est pas une fiche : ErreurSource", () {
      expect(
        () => SourceMangaThemesia.analyserFiche(
          '<html><body>Just a moment...</body></html>',
          Uri.parse(urlTitre),
        ),
        throwsA(isA<ErreurSource>()),
      );
    });
  });

  group('chapitres', () {
    test('page réelle : 6 chapitres, numéros data-num, dates', () {
      final chapitres = SourceMangaThemesia.analyserChapitres(
        htmlFiche,
        Uri.parse(urlTitre),
        languesPreferees: 'fr,en',
      );
      expect(chapitres.map((c) => c.numero), <double>[5, 4.5, 3.5, 3, 2, 1]);
      expect(chapitres.first.nom, 'Chapter 5');
      expect(chapitres.first.datePublication, DateTime.utc(2020, 7, 12));
      expect(chapitres.last.urlChapitre, urlChapitre1);
      expect(chapitres.last.datePublication, DateTime.utc(2019, 4, 6));
      // <html lang="en-US"> l'emporte sur les langues du client.
      expect(chapitres.every((c) => c.langue == 'en'), isTrue);
      // Les liens .dload (téléchargement externe) ne sont pas des chapitres.
      expect(
        chapitres.any((c) => c.urlChapitre.contains('mangaupdates')),
        isFalse,
      );
    });

    test(
      'recupererFiche puis recupererChapitres : une seule requête',
      () async {
        var requetes = 0;
        final source = creerSource((requete) async {
          requetes++;
          return reponseHtml(htmlFiche);
        });
        final fiche = await source.recupererFiche(urlTitre);
        final chapitres = await source.recupererChapitres(urlTitre);
        expect(requetes, 1);
        expect(fiche.titre.nom, 'Kaze no Doragon Raida');
        // Du plus ancien au plus récent.
        expect(chapitres.first.numero, 1);
        expect(chapitres.last.numero, 5);
      },
    );

    test('page sans lang : première langue du client', () {
      const html =
          '<html><body><div id="chapterlist"><ul><li data-num="1">'
          '<div class="eph-num"><a href="/x-chapter-1/">'
          '<span class="chapternum">Chapitre 1</span></a></div></li></ul>'
          '</div></body></html>';
      final chapitres = SourceMangaThemesia.analyserChapitres(
        html,
        Uri.parse(urlTitre),
        languesPreferees: 'fr,en',
      );
      expect(chapitres.single.langue, 'fr');
      expect(chapitres.single.urlChapitre, '$urlBase/x-chapter-1/');
    });
  });

  group('contenu', () {
    test('page réelle : images de ts_reader.run, Referer du site', () {
      final contenu = SourceMangaThemesia.analyserContenu(
        htmlChapitre,
        Uri.parse(urlChapitre1),
      );
      expect(contenu.urlsImages, hasLength(15));
      expect(contenu.urlsImages.every((u) => u == urlImage), isTrue);
      expect(contenu.urlReferer, 'https://mangareader.themesia.com/');
    });

    test('sans script lisible : repli sur les images de #readerarea', () {
      final sansScript = htmlChapitre.replaceAll('ts_reader.run(', 'autre(');
      final contenu = SourceMangaThemesia.analyserContenu(
        sansScript,
        Uri.parse(urlChapitre1),
      );
      expect(contenu.urlsImages, hasLength(15));
      expect(contenu.urlsImages.first, urlImage);
    });

    test('serveur par défaut choisi parmi plusieurs', () {
      const html =
          '<div id="readerarea"></div><script>ts_reader.run({"sources":['
          '{"source":"Server 1","images":["/a1.jpg"]},'
          '{"source":"Server 2","images":["/b1.jpg","/b2.jpg"]}],'
          '"defaultSource":"Server 2","protected":false});</script>';
      final contenu = SourceMangaThemesia.analyserContenu(
        html,
        Uri.parse(urlChapitre1),
      );
      expect(contenu.urlsImages, <String>[
        '$urlBase/b1.jpg',
        '$urlBase/b2.jpg',
      ]);
    });

    test('chapitre protégé ou sans image en clair : ErreurSource', () {
      for (final html in <String>[
        '<div id="readerarea"></div><script>ts_reader.run({"sources":[{'
            '"source":"S","images":["/a.jpg"]}],"protected":true});</script>',
        '<div id="readerarea"></div>'
            '<script src="data:text/javascript;base64,dHNfcmVhZGVy"></script>',
        '<html><body>Just a moment...</body></html>',
      ]) {
        expect(
          () => SourceMangaThemesia.analyserContenu(
            html,
            Uri.parse(urlChapitre1),
          ),
          throwsA(isA<ErreurSource>()),
        );
      }
    });

    test(
      'protégé dans un objet JavaScript non strict : ErreurSource « à lire sur '
      'le site », sans repli sur #readerarea ni <noscript>',
      () {
        // Clés sans guillemets, chaînes entre apostrophes, virgule finale :
        // jsonDecode échoue, et #readerarea / <noscript> ont des images.
        const debut =
            '<div id="readerarea"><img src="/visible.jpg">'
            '<noscript><img src="/cache.jpg"></noscript></div>'
            "<script>ts_reader.run({sources:[{source:'S',images:['/a.jpg']}],";
        for (final marque in <String>[
          'protected:true',
          "'protected' : 1",
          'protected: "1"',
          'protected:!0',
          '"protected":1',
        ]) {
          expect(
            () => SourceMangaThemesia.analyserContenu(
              '$debut$marque,});</script>',
              Uri.parse(urlChapitre1),
            ),
            throwsA(
              isA<ErreurSource>().having(
                (e) => e.message,
                'message',
                contains('à lire sur le site'),
              ),
            ),
            reason: marque,
          );
        }
      },
    );

    test('protected à 1 ou "1" en JSON strict : ErreurSource', () {
      for (final valeur in <String>['1', '"1"']) {
        final html =
            '<div id="readerarea"></div><script>ts_reader.run({"sources":[{'
            '"source":"S","images":["/a.jpg"]}],"protected":$valeur});'
            '</script>';
        expect(
          () => SourceMangaThemesia.analyserContenu(
            html,
            Uri.parse(urlChapitre1),
          ),
          throwsA(isA<ErreurSource>()),
          reason: valeur,
        );
      }
    });

    test('non protégé (false, 0, unprotected:true) : images lues', () {
      for (final marque in <String>[
        'protected:false',
        'protected:0',
        'protected:10',
        'unprotected:true',
      ]) {
        final html =
            '<div id="readerarea"><img src="/visible.jpg"></div>'
            "<script>ts_reader.run({sources:[],$marque});</script>";
        expect(
          SourceMangaThemesia.analyserContenu(
            html,
            Uri.parse(urlChapitre1),
          ).urlsImages,
          <String>['$urlBase/visible.jpg'],
          reason: marque,
        );
      }
    });

    test('recupererContenu : une requête sur la page du chapitre', () async {
      final urls = <String>[];
      final source = creerSource((requete) async {
        urls.add(requete.url.toString());
        return reponseHtml(htmlChapitre);
      });
      final contenu = await source.recupererContenu(urlChapitre1);
      expect(urls, <String>[urlChapitre1]);
      expect(contenu.urlsImages, hasLength(15));
    });
  });

  group('recherche', () {
    test('page réelle : nom, adresse, couverture et type', () {
      final titres = SourceMangaThemesia.analyserRecherche(
        htmlRecherche,
        Uri.parse('$urlBase/?s=kaze'),
      );
      expect(titres, hasLength(1));
      expect(titres.single.nom, 'Kaze no Doragon Raida');
      expect(titres.single.urlTitre, urlTitre);
      expect(titres.single.typeTitre, TypeTitre.manga);
      expect(
        titres.single.urlCouverture,
        'https://i2.wp.com/mangareader.themesia.com/wp-content/uploads/'
        '2019/04/cover-23-compressed.jpg?resize=285,425',
      );
    });

    test('« Not Found » : liste vide ; autre page : ErreurSource', () {
      const vide =
          '<div class="listupd"><center><h3>Not Found</h3></center></div>';
      expect(
        SourceMangaThemesia.analyserRecherche(vide, Uri.parse(urlBase)),
        isEmpty,
      );
      expect(
        () => SourceMangaThemesia.analyserRecherche(
          '<html><body>Erreur</body></html>',
          Uri.parse(urlBase),
        ),
        throwsA(isA<ErreurSource>()),
      );
    });

    test('rechercher : /?s=<texte>, erreur typée MangaThemesia', () async {
      final urls = <String>[];
      final source = creerSource((requete) async {
        urls.add(requete.url.toString());
        return reponseHtml('', statut: 503);
      });
      await expectLater(
        source.rechercher('kaze'),
        throwsA(
          isA<ErreurSource>().having(
            (e) => e.typeDetecte,
            'typeDetecte',
            TypeSource.mangaThemesia,
          ),
        ),
      );
      expect(urls.first, '$urlBase/?s=kaze');
    });
  });
}
