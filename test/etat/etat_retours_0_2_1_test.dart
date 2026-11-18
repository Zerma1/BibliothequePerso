// Tests des états pour les retours du client sur la 0.2.1-test (X3 à X10),
// avec de faux services (aucune base, aucun réseau).
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_bibliotheque.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/constantes.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/modeles/titre.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

/// Chapitres 1 à [nombre] en anglais, plus une version française du 2.
List<Chapitre> _chapitres(int nombre) => <Chapitre>[
  for (var i = 1; i <= nombre; i++)
    Chapitre(
      id: i,
      urlChapitre: 'https://mangadex.org/chapter/$i',
      nom: '',
      numero: i.toDouble(),
      langue: 'en',
    ),
  const Chapitre(
    id: 100,
    urlChapitre: 'https://mangadex.org/chapter/2-fr',
    nom: '',
    numero: 2,
    langue: 'fr',
  ),
];

void main() {
  late FauxServiceBibliotheque service;

  setUp(() => service = FauxServiceBibliotheque());

  group('X3 et X4 : listes', () {
    late EtatBibliotheque etat;

    setUp(() async {
      etat = EtatBibliotheque(service);
      await etat.charger();
    });

    tearDown(() => etat.dispose());

    test('seule Suivis est cochée par défaut', () {
      expect(etat.idsListesParDefaut, <int>{2});
    });

    test('les listes système ne sont pas modifiables, les personnelles le '
        'sont', () {
      final parNom = <String, bool>{
        for (final liste in etat.listes)
          liste.nom: etat.estListeModifiable(liste),
      };
      expect(parNom[nomListeFavoris], isFalse);
      expect(parNom[nomListeTermines], isFalse);
      expect(parNom['À lire plus tard'], isTrue);
    });

    test('crée, renomme puis supprime une liste ; la bibliothèque est '
        'relue', () async {
      final creee = await etat.creerListe('  Mes   préférés ');
      expect(creee.estReussi, isTrue);
      expect(creee.donnee!.nom, 'Mes préférés');
      expect(etat.listes.map((l) => l.nom), contains('Mes préférés'));

      final id = creee.donnee!.id!;
      final renommee = await etat.renommerListe(id, 'Coups de cœur');
      expect(renommee.donnee!.nom, 'Coups de cœur');
      expect(etat.listes.map((l) => l.nom), contains('Coups de cœur'));

      await etat.choisirListe(id);
      final supprimee = await etat.supprimerListe(id);
      expect(supprimee.estReussi, isTrue);
      expect(etat.listes.any((l) => l.id == id), isFalse);
      // Le filtre posé sur la liste supprimée est abandonné.
      expect(etat.idListeChoisie, isNull);
    });

    test('un refus du service est rendu sans exception', () async {
      service.erreurListes = const ErreurService(
        'Une liste nommée « X » '
        'existe déjà.',
      );
      final resultat = await etat.creerListe('X');
      expect(resultat.erreur!.nature, NatureErreur.refus);
      expect(resultat.erreur!.detail, contains('existe déjà'));
    });

    test('réordonne tout de suite, puis enregistre l\'ordre', () async {
      final ids = <int>[for (final liste in etat.listes) liste.id!];
      final inverse = ids.reversed.toList();
      final resultat = await etat.reordonnerListes(inverse);
      expect(resultat.estReussi, isTrue);
      expect(<int>[for (final liste in etat.listes) liste.id!], inverse);
      expect(<int>[for (final liste in service.listes) liste.id!], inverse);
    });

    test('un échec du réordonnancement remet l\'ordre enregistré', () async {
      final avant = <int>[for (final liste in etat.listes) liste.id!];
      service.erreurListes = const ErreurService('Liste disparue.');
      final resultat = await etat.reordonnerListes(avant.reversed.toList());
      expect(resultat.estReussi, isFalse);
      expect(<int>[for (final liste in etat.listes) liste.id!], avant);
    });

    test('recherche sur MangaDex : source par défaut si aucun site '
        'MangaDex n\'est configuré', () async {
      service.resultatsRecherche = <Titre>[
        Titre(
          urlTitre: 'https://mangadex.org/title/abc',
          nom: 'Trouvé',
          typeTitre: TypeTitre.manga,
        ),
      ];
      final resultat = await etat.rechercherSurMangaDex('  trouvé ');
      expect(resultat.donnee!.single.nom, 'Trouvé');
      expect(service.recherches.single.requete, 'trouvé');
      expect(service.recherches.single.source.typeSource, TypeSource.mangaDex);

      // Requête vide : aucune requête au site.
      final vide = await etat.rechercherSurMangaDex('   ');
      expect(vide.donnee, isEmpty);
      expect(service.recherches, hasLength(1));
    });
  });

  group('X5 : sites', () {
    late FauxServiceAjoutSite ajoutSite;
    late EtatSources etat;

    setUp(() async {
      ajoutSite = FauxServiceAjoutSite(service);
      etat = EtatSources(service, ajoutSite);
      service.sources.add(
        const Source(
          id: 1,
          nom: 'Site générique',
          urlBase: 'https://scans.test',
          typeSource: TypeSource.generique,
          configurationSelecteurs: '{"selecteurTitre":"h1"}',
        ),
      );
      await etat.charger();
    });

    tearDown(() => etat.dispose());

    test('l\'ajout transmet les sélecteurs au service (vérification de la '
        'page générique)', () async {
      await etat.ajouterSite(
        'https://autre.test/manga/x',
        reglagesGeneriques: <String, String>{'selecteurTitre': 'h1.titre'},
      );
      expect(ajoutSite.dernierAppel!.selecteurs, contains('h1.titre'));
    });

    test('le type se change ; quitter le générique efface les réglages', () {
      final source = etat.sources.single;
      expect(
        EtatSources.changementTypeEffaceReglages(source, TypeSource.madara),
        isTrue,
      );
      expect(
        EtatSources.changementTypeEffaceReglages(source, TypeSource.generique),
        isFalse,
      );
      expect(
        EtatSources.erreurTypeSite(source.urlBase, TypeSource.mangaDex),
        isNotNull,
      );
      expect(
        EtatSources.erreurTypeSite(source.urlBase, TypeSource.madara),
        isNull,
      );
    });

    test('modifierSource envoie le nouveau type', () async {
      final resultat = await etat.modifierSource(
        etat.sources.single,
        nom: 'Site Madara',
        langues: '',
        estActive: true,
        typeSource: TypeSource.madara,
      );
      expect(resultat.estReussi, isTrue);
      expect(ajoutSite.sourcesModifiees.single.typeSource, TypeSource.madara);
    });
  });

  group('X7 : archive complète', () {
    test('active, enregistre puis applique les règles à tous', () async {
      final parametres = FauxServiceParametres();
      final telechargement = FauxServiceTelechargement(service);
      final etat = EtatParametres(parametres, telechargement);
      addTearDown(etat.dispose);
      await etat.charger();
      expect(etat.archiveComplete, isFalse);

      final resultat = await etat.modifierArchiveComplete(true);

      expect(resultat.donnee, isTrue);
      expect(parametres.archiveComplete, isTrue);
      expect(etat.archiveComplete, isTrue);
      expect(telechargement.nombreAppelsReglesATous, 1);
    });
  });

  group('X6 et X10 : fiche', () {
    late FauxServiceTelechargement telechargement;
    late EtatTitre etat;

    setUp(() async {
      service.ajouterTitreDeTest(
        'Titre',
        idSource: 1,
        chapitres: _chapitres(5),
      );
      telechargement = FauxServiceTelechargement(service);
      etat = EtatTitre(service, 1, serviceTelechargement: telechargement);
      await etat.charger();
    });

    tearDown(() => etat.dispose());

    test('description personnelle : enregistrée puis effacée, la fiche '
        'est relue', () async {
      expect(etat.descriptionPerso, isNull);

      final resultat = await etat.enregistrerDescriptionPerso(
        '  Mes notes\n\nsur deux paragraphes  ',
      );
      expect(resultat.estReussi, isTrue);
      expect(etat.descriptionPerso, 'Mes notes\n\nsur deux paragraphes');
      expect(etat.estEnEnregistrementDescription, isFalse);

      await etat.enregistrerDescriptionPerso(null);
      expect(etat.descriptionPerso, isNull);
    });

    test('description personnelle refusée : erreur lisible, rien ne '
        'change', () async {
      service.erreurDescription = const ErreurService(
        'La description est trop longue (5000 caractères au plus).',
      );

      final resultat = await etat.enregistrerDescriptionPerso('Texte');

      expect(resultat.estReussi, isFalse);
      expect(resultat.erreur!.nature, NatureErreur.refus);
      expect(resultat.erreur!.detail, contains('trop longue'));
      expect(etat.descriptionPerso, isNull);
      expect(etat.estEnEnregistrementDescription, isFalse);
    });

    test(
      'glisser sélectionne la plage, puis « marquer lus » en une fois',
      () async {
        final groupes = etat.groupes; // 5, 4, 3, 2, 1
        etat.commencerGlisser(groupes[1]);
        etat.etendreGlisser(groupes[3]);
        etat.terminerGlisser();
        expect(etat.estEnSelection, isTrue);
        expect(etat.nombreSelectionnes, 3);

        // Un appui en mode sélection retire une ligne.
        etat.basculerSelection(groupes[2]);
        expect(etat.nombreSelectionnes, 2);

        final resultat = await etat.marquerSelection();

        // Numéros 4 et 2 : 2 en anglais et en français.
        expect(resultat.donnee, 3);
        expect(service.nombreMarquagesEnLot, 1);
        expect(etat.estEnSelection, isFalse);
        final lus = <int>{
          for (final chapitre in etat.chapitres)
            if (chapitre.estLu) chapitre.id!,
        };
        expect(lus, <int>{4, 2, 100});
        expect(telechargement.reglesAppliquees, contains(1));
      },
    );

    test('tout sélectionner puis annuler ne change rien', () async {
      etat.toutSelectionner();
      expect(etat.toutEstSelectionne, isTrue);
      etat.annulerSelection();
      expect(etat.estEnSelection, isFalse);
      expect(etat.nombreSelectionnes, 0);
      expect(service.nombreMarquagesEnLot, 0);
    });

    test('« marquer lus jusqu\'ici » marque tous les numéros inférieurs, '
        'toutes langues', () async {
      final resultat = await etat.marquerLusJusqua(3);
      expect(resultat.donnee, 4);
      expect(etat.nombreNumerosNonLus, 2);
      expect(telechargement.reglesAppliquees, contains(1));
    });
  });
}
