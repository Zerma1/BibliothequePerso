// Tests de EtatParametres (réglages de téléchargement et de mises à jour) et
// de la modification / suppression des sites dans EtatSources, avec de faux
// services.
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_parametres.dart';
import 'package:bibliotheque_perso/etat/etat_sources.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/politique_telechargement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  group('EtatParametres', () {
    late FauxServiceParametres parametres;
    late FauxServiceTelechargement telechargement;
    late EtatParametres etat;

    setUp(() async {
      parametres = FauxServiceParametres()
        ..reglages = const ReglagesTelechargement(favorisLusConserves: 3);
      telechargement = FauxServiceTelechargement(FauxServiceBibliotheque());
      etat = EtatParametres(parametres, telechargement);
      addTearDown(etat.dispose);
      await etat.charger();
    });

    group('Mes langues', () {
      test('charge les langues, la première est la favorite', () {
        expect(etat.langues, <String>['fr', 'en']);
        expect(etat.langueFavorite, 'fr');
        expect(etat.peutRetirerLangue, isTrue);
      });

      test('ajoute, déplace, choisit la favorite et retire, en '
          'enregistrant et appliquant les règles à chaque fois', () async {
        expect((await etat.ajouterLangue('ja')).estReussi, isTrue);
        expect(parametres.langues, <String>['fr', 'en', 'ja']);

        await etat.deplacerLangue('ja', -1);
        expect(etat.langues, <String>['fr', 'ja', 'en']);

        await etat.choisirFavorite('en');
        expect(etat.langues, <String>['en', 'fr', 'ja']);
        expect(etat.langueFavorite, 'en');

        await etat.retirerLangue('fr');
        expect(parametres.langues, <String>['en', 'ja']);
        expect(telechargement.nombreAppelsReglesATous, 4);
        expect(etat.estEnEnregistrementLangues, isFalse);
      });

      test('une langue déjà choisie ou un déplacement hors limites ne '
          'change rien', () async {
        await etat.ajouterLangue('fr');
        await etat.deplacerLangue('fr', -1);
        await etat.deplacerLangue('en', 1);
        expect(etat.langues, <String>['fr', 'en']);
        expect(telechargement.nombreAppelsReglesATous, 0);
      });

      test('la dernière langue ne peut pas être retirée', () async {
        await etat.retirerLangue('en');
        expect(etat.peutRetirerLangue, isFalse);

        final resultat = await etat.retirerLangue('fr');

        expect(resultat.estReussi, isFalse);
        expect(resultat.erreur!.nature, NatureErreur.refus);
        expect(etat.langues, <String>['fr']);
      });
    });

    test('charge les réglages enregistrés', () {
      expect(etat.estCharge, isTrue);
      expect(etat.valeur(LimiteTelechargement.favorisLusConserves), 3);
      expect(etat.valeur(LimiteTelechargement.suivisInitial), 10);
      expect(etat.estModifie, isFalse);
      expect(etat.estParDefaut, isFalse);
    });

    test('+ / − modifient le brouillon, bornés entre le minimum de la '
        'limite et le maximum', () {
      etat.ajouter(LimiteTelechargement.suivisApres, 1);
      expect(etat.valeur(LimiteTelechargement.suivisApres), 6);
      expect(etat.estModifie, isTrue);
      // Rien n'est écrit avant « Enregistrer ».
      expect(parametres.nombreEnregistrements, 0);

      // « avant » des suivis : 1 au moins, comme dans le service.
      etat.modifier(LimiteTelechargement.suivisAvant, -4);
      expect(etat.valeur(LimiteTelechargement.suivisAvant), 1);
      etat.modifier(LimiteTelechargement.favorisLusConserves, -4);
      expect(etat.valeur(LimiteTelechargement.favorisLusConserves), 0);
      etat.modifier(LimiteTelechargement.suivisAvant, 100000);
      expect(
        etat.valeur(LimiteTelechargement.suivisAvant),
        EtatParametres.limiteMaximale,
      );

      etat.annulerModifications();
      expect(etat.estModifie, isFalse);
    });

    test(
      'enregistrer écrit les réglages puis applique les règles à tous',
      () async {
        etat.remettreParDefaut();
        expect(etat.estParDefaut, isTrue);
        final resultat = await etat.enregistrer();

        expect(resultat.estReussi, isTrue);
        expect(parametres.reglages, const ReglagesTelechargement());
        expect(telechargement.nombreAppelsReglesATous, 1);
        expect(etat.estModifie, isFalse);
      },
    );

    test(
      'nombre de vérifications par jour : borné et enregistré aussitôt',
      () async {
        expect(etat.verificationsParJour, 2);
        final resultat = await etat.modifierVerificationsParJour(30);
        expect(resultat.estReussi, isTrue);
        expect(etat.verificationsParJour, 24);
        expect(parametres.verificationsParJour, 24);

        await etat.modifierVerificationsParJour(0);
        expect(etat.verificationsParJour, 1);
        expect(etat.planification.horairesDuJour(), <Duration>[Duration.zero]);
      },
    );

    test('date de la dernière vérification', () async {
      expect(etat.derniereVerification, isNull);
      parametres.derniereVerification = DateTime.utc(2026, 11, 15, 12);
      await etat.rechargerDerniereVerification();
      expect(etat.derniereVerification, DateTime.utc(2026, 11, 15, 12));
    });

    test('erreur de lecture exposée', () async {
      parametres.erreurLecture = const ErreurService('Réglages illisibles.');
      await etat.charger();
      expect(etat.erreur!.nature, NatureErreur.refus);
    });
  });

  group('EtatSources : modifier et supprimer un site', () {
    late FauxServiceBibliotheque bibliotheque;
    late FauxServiceAjoutSite ajoutSite;
    late FauxServiceTelechargement telechargement;
    late EtatSources etat;

    setUp(() async {
      bibliotheque = FauxServiceBibliotheque();
      bibliotheque.sources.addAll(const <Source>[
        Source(
          id: 1,
          nom: 'MangaDex',
          urlBase: 'https://mangadex.org',
          typeSource: TypeSource.mangaDex,
          langueParDefaut: 'fr,en',
        ),
        Source(
          id: 2,
          nom: 'Autre',
          urlBase: 'https://autre.test',
          typeSource: TypeSource.madara,
        ),
      ]);
      bibliotheque.ajouterTitreDeTest('Titre', idSource: 1);
      ajoutSite = FauxServiceAjoutSite(bibliotheque);
      telechargement = FauxServiceTelechargement(bibliotheque);
      etat = EtatSources(
        bibliotheque,
        ajoutSite,
        serviceTelechargement: telechargement,
      );
      addTearDown(etat.dispose);
      await etat.charger();
    });

    test('changer les langues réapplique les règles', () async {
      final resultat = await etat.modifierSource(
        etat.sources.first,
        nom: ' MangaDex FR ',
        langues: 'EN, fr',
        estActive: true,
      );

      expect(resultat.estReussi, isTrue);
      expect(resultat.donnee!.nom, 'MangaDex FR');
      expect(resultat.donnee!.langueParDefaut, 'en,fr');
      expect(etat.sources.first.langueParDefaut, 'en,fr');
      expect(telechargement.nombreAppelsReglesATous, 1);
    });

    test(
      'changer seulement le nom ou l\'activation ne relance pas les règles',
      () async {
        await etat.modifierSource(
          etat.sources.first,
          nom: 'MD',
          langues: 'fr,en',
          estActive: false,
        );
        expect(etat.sources.first.estActive, isFalse);
        expect(telechargement.nombreAppelsReglesATous, 0);
      },
    );

    test('un nom vide est refusé', () async {
      final resultat = await etat.modifierSource(
        etat.sources.first,
        nom: '  ',
        langues: 'fr',
        estActive: true,
      );
      expect(resultat.erreur!.nature, NatureErreur.nomVide);
      expect(ajoutSite.sourcesModifiees, isEmpty);
    });

    test('supprimer un site qui a des titres est refusé clairement', () async {
      final resultat = await etat.supprimerSource(etat.sources.first);
      expect(resultat.erreur!.nature, NatureErreur.siteAvecTitres);
      expect(resultat.erreur!.detail, '1');
      expect(bibliotheque.sources, hasLength(2));
    });

    test('supprimer un site sans titre', () async {
      final resultat = await etat.supprimerSource(etat.sources[1]);
      expect(resultat.estReussi, isTrue);
      expect(etat.sources.map((s) => s.nom), <String>['MangaDex']);
    });
  });
}
