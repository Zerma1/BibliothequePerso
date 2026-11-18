import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => Journal.actuel = const JournalSilencieux());

  group('NiveauJournal', () {
    test('ordre de gravité', () {
      expect(NiveauJournal.erreur.estAuMoins(NiveauJournal.info), isTrue);
      expect(NiveauJournal.info.estAuMoins(NiveauJournal.info), isTrue);
      expect(NiveauJournal.debogage.estAuMoins(NiveauJournal.info), isFalse);
    });

    test("depuisTexte accepte le nom et l'étiquette", () {
      expect(NiveauJournal.depuisTexte('debogage'), NiveauJournal.debogage);
      expect(NiveauJournal.depuisTexte(' AVERT '), NiveauJournal.avertissement);
      expect(NiveauJournal.depuisTexte('inconnu'), isNull);
      expect(NiveauJournal.depuisTexte(null), isNull);
    });
  });

  group('Journal.actuel', () {
    test('silencieux par défaut, sans exception', () {
      expect(Journal.actuel, isA<JournalSilencieux>());
      expect(Journal.actuel.estActif(NiveauJournal.erreur), isFalse);
      Journal.actuel.erreur(CategorieJournal.base, 'rien', erreur: 'x');
    });

    test('remplaçable par un journal en mémoire', () {
      final memoire = JournalMemoire(niveauMinimal: NiveauJournal.info);
      Journal.actuel = memoire;
      Journal.actuel.debogage(CategorieJournal.reseau, 'ignoré');
      Journal.actuel.info(CategorieJournal.reseau, 'GET');
      final erreur = StateError('boum');
      Journal.actuel.erreur(
        CategorieJournal.telechargement,
        'échec',
        erreur: erreur,
      );
      expect(memoire.entrees, [
        const EntreeJournal(
          niveau: NiveauJournal.info,
          categorie: CategorieJournal.reseau,
          message: 'GET',
        ),
        EntreeJournal(
          niveau: NiveauJournal.erreur,
          categorie: CategorieJournal.telechargement,
          message: 'échec',
          erreur: erreur,
        ),
      ]);
    });
  });

  group('masquerDonneesSensibles', () {
    test('paramètres de requête sensibles', () {
      expect(
        masquerDonneesSensibles(
          'https://site.org/api?q=one+piece&token=abc123&page=2'
          '&api_key=XYZ&password=secret&PHPSESSID=99',
        ),
        'https://site.org/api?q=one+piece&token=***&page=2'
        '&api_key=***&password=***&PHPSESSID=***',
      );
    });

    test('garde les paramètres ordinaires (author, includes)', () {
      const url =
          'https://api.mangadex.org/manga?authors[]=12&includes[]=author'
          '&limit=10';
      expect(masquerDonneesSensibles(url), url);
    });

    test('en-têtes Authorization et Cookie', () {
      expect(
        masquerDonneesSensibles('Authorization: Bearer eyJhbGci.abc.def'),
        'Authorization: ***',
      );
      expect(
        masquerDonneesSensibles(
          '{User-Agent: BibliothequePerso, Cookie: a=1; sid=2, Accept: */*}',
        ),
        '{User-Agent: BibliothequePerso, Cookie: ***, Accept: */*}',
      );
      expect(
        masquerDonneesSensibles('set-cookie=cf_clearance=zzz\nsuite'),
        'set-cookie=***\nsuite',
      );
    });

    test('jeton Bearer isolé et champ JSON', () {
      expect(
        masquerDonneesSensibles('envoi de Bearer eyJhbGciOiJIUzI1.abc-def='),
        'envoi de Bearer ***',
      );
      expect(
        masquerDonneesSensibles('Basic dXRpbGlzYXRldXI6bW90ZGVwYXNzZQ=='),
        'Basic ***',
      );
      expect(
        masquerDonneesSensibles('{"username":"moi","password":"p\\"a"}'),
        '{"username":"moi","password":"***"}',
      );
    });

    test('jeton de session MangaDex dans le chemin des images', () {
      expect(
        masquerDonneesSensibles(
          'https://abc.xyz.mangadex.network/JETON123/data/hash/1.png',
        ),
        'https://abc.xyz.mangadex.network/***/data/hash/1.png',
      );
      expect(
        masquerDonneesSensibles(
          'GET https://x.mangadex.network:44300/JETON/data-saver/h/2.jpg : 200',
        ),
        'GET https://x.mangadex.network:44300/***/data-saver/h/2.jpg : 200',
      );
    });

    test("Bearer ou Basic court hors en-tête : texte ordinaire gardé", () {
      const texte = 'Recherche « Basic Instinct » puis « Bearer of bad news »';
      expect(masquerDonneesSensibles(texte), texte);
      // Dans un en-tête, la valeur est masquée quelle que soit sa longueur.
      expect(
        masquerDonneesSensibles('Authorization: Basic abc'),
        'Authorization: ***',
      );
      expect(
        masquerDonneesSensibles('{Authorization: Bearer xyz, Accept: */*}'),
        '{Authorization: ***, Accept: */*}',
      );
    });

    test("identifiants dans l'URL", () {
      expect(
        masquerDonneesSensibles('https://moi:secret@nas.local:5005/livres'),
        'https://***@nas.local:5005/livres',
      );
      expect(
        masquerDonneesSensibles('ftp://moi:@hote/x et http://hote:8080/a@b'),
        'ftp://***@hote/x et http://hote:8080/a@b',
      );
    });

    test('sid : nom exact ou séparé seulement', () {
      expect(
        masquerDonneesSensibles(
          'https://site.org/a?sid=ABC&connect.sid=DEF&user_sid=GHI&page=1',
        ),
        'https://site.org/a?sid=***&connect.sid=***&user_sid=***&page=1',
      );
      const ordinaire =
          'https://site.org/a?side=left&inside=1&consider=2&sidebar=0';
      expect(masquerDonneesSensibles(ordinaire), ordinaire);
      expect(
        masquerDonneesSensibles('{"sid":"ABC","side":"gauche"}'),
        '{"sid":"***","side":"gauche"}',
      );
    });

    test('texte sans donnée sensible inchangé', () {
      const texte = 'Chapitre 12 téléchargé (34 pages) en 2,1 s';
      expect(masquerDonneesSensibles(texte), texte);
      expect(masquerDonneesSensibles(''), '');
    });
  });
}
