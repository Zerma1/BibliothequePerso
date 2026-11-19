// Tests de EtatNavigateur (navigateur intégré, tâche N3) avec un faux
// service et une fausse page : aucun réseau, aucune vraie vue web.
import 'dart:async';

import 'package:bibliotheque_perso/etat/constantes_etat.dart';
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_navigateur.dart';
import 'package:bibliotheque_perso/services/service_lecture_web.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';
import 'outils_tests_navigateur.dart';

void main() {
  late FauxServiceLectureWeb service;
  late FauxServiceBibliotheque bibliotheque;
  late List<Duration> attentes;
  late DateTime horloge;

  const adresse1 = 'https://site.test/manga/titre/chapitre-1';
  const adresse2 = 'https://site.test/manga/titre/chapitre-2';
  const adresse3 = 'https://site.test/manga/titre/chapitre-3';

  setUp(() {
    service = FauxServiceLectureWeb();
    bibliotheque = FauxServiceBibliotheque()..ajouterTitreDeTest('Mon titre');
    service.chapitresParAdresse[adresse1] = chapitreDeTest(1, 1);
    service.chapitresParAdresse[adresse2] = chapitreDeTest(2, 2);
    service.chapitresParAdresse[adresse3] = chapitreDeTest(3, 3);
    attentes = <Duration>[];
    horloge = DateTime.utc(2026, 11, 19, 12);
  });

  EtatNavigateur creer({Future<void> Function(Duration)? attendre}) =>
      EtatNavigateur(
        service,
        adresseInitiale: adresse1,
        idTitre: 1,
        serviceBibliotheque: bibliotheque,
        attendre:
            attendre ??
            (duree) async {
              attentes.add(duree);
            },
        maintenant: () => horloge,
      );

  group('adresse et chapitre affiché', () {
    test('reconnaît le chapitre, le note et affiche le nom du titre', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);

      expect(etat.chapitre?.id, 1);
      expect(etat.nomTitreChapitre, 'Mon titre');
      expect(etat.peutEnregistrer, isTrue);
      expect(service.journal, <String>[
        'reconnaitre:$adresse1',
        'noter:$adresse1',
      ]);
    });

    test('la même adresse signalée deux fois (historique puis fin de '
        'chargement, fragment) n\'est examinée qu\'une fois', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      await etat.signalerAdresse(adresse1);
      await etat.signalerAdresse('$adresse1#page-3');

      expect(
        service.journal.where((ligne) => ligne.startsWith('reconnaitre')),
        hasLength(1),
      );
    });

    test('passer au chapitre suivant quitte le précédent, même après une '
        'page qui n\'est pas un chapitre', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      await etat.signalerAdresse(adresse2);
      await etat.signalerAdresse('https://site.test/accueil');
      expect(etat.chapitre, isNull);
      expect(etat.peutEnregistrer, isFalse);
      await etat.signalerAdresse(adresse3);

      expect(service.sorties, <String>['1->2', '2->3']);
      expect(etat.chapitre?.id, 3);
    });

    test('suivi par titre : A ch. 1 → B ch. 10 → A ch. 2 marque A ch. 1 lu, '
        'B ch. 10 n\'est pas quitté pour un autre titre', () async {
      const adresseB = 'https://autre.test/manga/b/chapitre-10';
      service.chapitresParAdresse[adresseB] = chapitreDeTest(
        10,
        10,
        idTitre: 2,
      );
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      await etat.signalerAdresse(adresseB);
      await etat.signalerAdresse(adresse2);

      expect(service.sorties, <String>['1->2']);

      // Retour au titre B : son dernier chapitre vu reste le 10.
      const adresseB11 = 'https://autre.test/manga/b/chapitre-11';
      service.chapitresParAdresse[adresseB11] = chapitreDeTest(
        11,
        11,
        idTitre: 2,
      );
      await etat.signalerAdresse(adresseB11);
      expect(service.sorties, <String>['1->2', '10->11']);
    });

    test('nouvelle adresse : l\'ancien chapitre est oublié avant la fin de '
        'la reconnaissance, « Enregistrer » est inactif', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      expect(etat.peutEnregistrer, isTrue);
      final retenue = Completer<void>();
      service.reconnaissancesRetenues[adresse2] = retenue;

      final examen = etat.signalerAdresse(adresse2);
      // Aussitôt (avant toute réponse du service).
      expect(etat.chapitre, isNull);
      expect(etat.chapitreReconnu, isNull);
      expect(etat.peutEnregistrer, isFalse);
      final page = FaussePage()..images['https://img.test/4.png'] = octetsPng;
      final refus = await etat.enregistrerChapitre(page);
      expect(refus.refus, RefusEnregistrementWeb.pageNonReconnue);
      expect(service.nombreEnregistrements, 0);
      expect(page.lues, isEmpty);

      retenue.complete();
      await examen;
      expect(etat.chapitre?.id, 2);
      expect(etat.peutEnregistrer, isTrue);
    });

    test('début de chargement d\'une autre page : l\'ancien chapitre est '
        'oublié ; un simple fragment le garde', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);

      etat.signalerDebutChargement('$adresse1#page-2');
      expect(etat.chapitre?.id, 1);
      expect(etat.peutEnregistrer, isTrue);

      etat.signalerDebutChargement(adresse2);
      expect(etat.chapitre, isNull);
      expect(etat.peutEnregistrer, isFalse);
      final resultat = await etat.enregistrerChapitre(FaussePage());
      expect(resultat.refus, RefusEnregistrementWeb.pageNonReconnue);

      // La nouvelle page est bien examinée ensuite.
      await etat.signalerAdresse(adresse2);
      expect(etat.chapitre?.id, 2);
    });

    test('un examen de l\'ancienne page qui finit après le début de la '
        'nouvelle est ignoré', () async {
      final etat = creer();
      final retenue = Completer<void>();
      service.reconnaissancesRetenues[adresse1] = retenue;
      final examen = etat.signalerAdresse(adresse1);
      etat.signalerDebutChargement(adresse2);
      retenue.complete();
      await examen;

      expect(etat.chapitre, isNull);
      expect(etat.peutEnregistrer, isFalse);
    });

    test('adresse saisie : https ajouté, adresse invalide refusée', () {
      expect(
        EtatNavigateur.adresseDepuisSaisie('  exemple.com/page '),
        'https://exemple.com/page',
      );
      expect(
        EtatNavigateur.adresseDepuisSaisie('http://exemple.com'),
        'http://exemple.com',
      );
      expect(EtatNavigateur.adresseDepuisSaisie(''), isNull);
      expect(EtatNavigateur.adresseDepuisSaisie('ftp://exemple.com'), isNull);
      expect(EtatNavigateur.adresseDepuisSaisie('deux mots'), isNull);
    });

    test('chargement, historique et erreur de la page', () {
      final etat = creer();
      etat.signalerDebutChargement(adresse2);
      expect(etat.estEnChargement, isTrue);
      expect(etat.adresse, adresse2);
      etat.signalerProgression(100);
      expect(etat.estEnChargement, isFalse);
      etat.signalerHistorique(peutReculer: true, peutAvancer: false);
      expect(etat.peutReculer, isTrue);
      etat.signalerErreurChargement('Hôte introuvable');
      expect(etat.erreurChargement, 'Hôte introuvable');
      etat.signalerDebutChargement(adresse2);
      expect(etat.erreurChargement, isNull);
    });
  });

  group('Enregistrer ce chapitre', () {
    test('page non reconnue : refus, le service n\'est pas appelé', () async {
      final etat = creer();
      final resultat = await etat.enregistrerChapitre(FaussePage());
      expect(resultat.refus, RefusEnregistrementWeb.pageNonReconnue);
      expect(service.nombreEnregistrements, 0);
    });

    test('images lues dans l\'ordre du document puis confiées au service ; '
        'le repère passe à « déjà enregistré »', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..images['https://img.test/1.png'] = <int>[...octetsPng, 1]
        ..images['https://img.test/2.png'] = <int>[...octetsPng, 2];

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.estReussi, isTrue);
      expect(service.pagesProtegeesRecues, isFalse);
      expect(service.imagesRecues!.map((i) => i.octets.last), <int>[1, 2]);
      expect(service.imagesRecues!.first.adresse, 'https://img.test/1.png');
      expect(etat.chapitre!.estTelecharge, isTrue);
      expect(etat.estEnEnregistrement, isFalse);
      expect(etat.pagesFaites, 2);
      expect(etat.pagesTotal, 2);
      // Copies base64 libérées dans la page.
      expect(page.copiesRestantes, 0);
    });

    test('une grande image est rapatriée en plusieurs blocs', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final grande = <int>[
        ...octetsPng,
        ...List<int>.generate(tailleBlocBase64Navigateur, (i) => i % 256),
      ];
      final page = FaussePage()..images['https://img.test/1.png'] = grande;

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.estReussi, isTrue);
      expect(service.imagesRecues!.single.octets, grande);
    });

    test('pages en canvas : le service refuse (images protégées), aucune '
        'image n\'est lue', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..canvas = 3
        ..images['https://img.test/1.png'] = octetsPng;

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.erreur?.nature, NatureErreur.refus);
      expect(resultat.erreur?.detail, messageImagesProtegees);
      expect(service.pagesProtegeesRecues, isTrue);
      expect(page.lues, isEmpty);
    });

    test('images blob: ou data: : marquées protégées, jamais lues, refus '
        'du service (images protégées)', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..images['https://img.test/1.png'] = octetsPng
        ..images['blob:https://site.test/0b1c'] = octetsPng
        ..images['data:image/png;base64,iVBORw0KGgo='] = octetsPng;

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.erreur?.nature, NatureErreur.refus);
      expect(resultat.erreur?.detail, messageImagesProtegees);
      expect(page.lues, isEmpty);
      expect(service.imagesRecues!.map((i) => i.estProtegee), <bool>[
        false,
        true,
        true,
      ]);
      expect(etat.chapitre!.estTelecharge, isFalse);
    });

    test('page quittée puis revenue pendant la lecture (reconnaissance pas '
        'finie) : rien n\'est confié au service', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      service.reconnaissancesRetenues[adresse1] = Completer<void>();
      final page = FaussePage()
        ..images['https://img.test/1.png'] = octetsPng
        ..images['https://img.test/2.png'] = octetsPng;
      page.avantLecture = (adresse) {
        if (adresse.endsWith('2.png')) {
          etat.signalerDebutChargement(adresse2);
          etat.signalerDebutChargement(adresse1);
          unawaited(etat.signalerAdresse(adresse1));
        }
      };

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.refus, RefusEnregistrementWeb.pageChangee);
      expect(service.nombreEnregistrements, 0);
    });

    test('pages pas encore chargées : refus, rien d\'enregistré', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..nonChargees = 2
        ..images['https://img.test/1.png'] = octetsPng;

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.refus, RefusEnregistrementWeb.pagesNonChargees);
      expect(service.nombreEnregistrements, 0);
    });

    test('aucune image : refus', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final resultat = await etat.enregistrerChapitre(FaussePage());
      expect(resultat.refus, RefusEnregistrementWeb.aucuneImage);
    });

    test('image refusée par le site : refus, rien d\'enregistré', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..images['https://img.test/1.png'] = octetsPng
        ..images['https://img.test/2.png'] = octetsPng
        ..refusees.add('https://img.test/2.png');

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.refus, RefusEnregistrementWeb.imagesInaccessibles);
      expect(service.nombreEnregistrements, 0);
      expect(page.copiesRestantes, 0);
    });

    test('erreur du service : transmise, état remis à zéro', () async {
      service.erreurEnregistrement = Exception('disque plein');
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()..images['https://img.test/1.png'] = octetsPng;

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.erreur?.nature, NatureErreur.inattendue);
      expect(etat.estEnEnregistrement, isFalse);
      expect(etat.chapitre!.estTelecharge, isFalse);
    });

    test('changement de page pendant l\'enregistrement : refus', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..images['https://img.test/1.png'] = octetsPng
        ..images['https://img.test/2.png'] = octetsPng;
      page.avantLecture = (adresse) {
        if (adresse.endsWith('1.png')) {
          etat.signalerDebutChargement(adresse2);
        }
      };

      final resultat = await etat.enregistrerChapitre(page);

      expect(resultat.refus, RefusEnregistrementWeb.pageChangee);
      expect(service.nombreEnregistrements, 0);
    });

    test('délai d\'une seconde entre deux requêtes vers un même domaine, '
        'sauf images servies par le cache ou d\'un autre domaine', () async {
      final etat = creer();
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..images['https://img.test/1.png'] = octetsPng
        ..images['https://img.test/2.png'] = octetsPng
        ..images['https://autre.test/3.png'] = octetsPng
        ..images['https://img.test/4.png'] = octetsPng
        ..enCache.add('https://img.test/4.png');

      await etat.enregistrerChapitre(page);

      // 1 : première requête ; 2 : attente ; 3 : autre domaine ; 4 : attente
      // (la 2 est allée sur le réseau), puis venue du cache.
      expect(attentes, <Duration>[
        delaiRequetesImagesNavigateur,
        delaiRequetesImagesNavigateur,
      ]);

      // Second enregistrement : la dernière requête réseau vers img.test
      // reste celle de l'image 2 (l'image 4 venait du cache).
      attentes.clear();
      horloge = horloge.add(const Duration(milliseconds: 400));
      page.images
        ..clear()
        ..['https://img.test/5.png'] = octetsPng;
      await etat.enregistrerChapitre(page);
      expect(attentes, <Duration>[const Duration(milliseconds: 600)]);
    });

    test('annuler pendant l\'attente : rien d\'enregistré', () async {
      final bloque = Completer<void>();
      final etat = creer(attendre: (_) => bloque.future);
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..images['https://img.test/1.png'] = octetsPng
        ..images['https://img.test/2.png'] = octetsPng;

      final enCours = etat.enregistrerChapitre(page);
      await pumpEventQueue();
      expect(etat.estEnEnregistrement, isTrue);
      expect(etat.pagesFaites, 1);
      etat.annulerEnregistrement();
      final resultat = await enCours;

      expect(resultat.refus, RefusEnregistrementWeb.annule);
      expect(service.nombreEnregistrements, 0);
      expect(page.lues, <String>['https://img.test/1.png']);
    });

    test('un second appel pendant l\'enregistrement est refusé', () async {
      final bloque = Completer<void>();
      final etat = creer(attendre: (_) => bloque.future);
      await etat.signalerAdresse(adresse1);
      final page = FaussePage()
        ..images['https://img.test/1.png'] = octetsPng
        ..images['https://img.test/2.png'] = octetsPng;

      final premier = etat.enregistrerChapitre(page);
      await pumpEventQueue();
      final second = await etat.enregistrerChapitre(page);
      expect(second.refus, RefusEnregistrementWeb.dejaEnCours);
      expect(etat.peutEnregistrer, isFalse);
      etat.annulerEnregistrement();
      await premier;
    });
  });
}
