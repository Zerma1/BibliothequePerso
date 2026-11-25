// Tests des notes de l'interface dans le journal de l'application : erreurs
// inattendues, ouverture d'une fiche, lecture d'un chapitre ouverte et
// fermée, aides `noterActionInterface` / `noterProblemeInterface`.
import 'package:bibliotheque_perso/etat/description_erreur.dart';
import 'package:bibliotheque_perso/etat/etat_lecteur.dart';
import 'package:bibliotheque_perso/etat/etat_titre.dart';
import 'package:bibliotheque_perso/etat/journal_interface.dart';
import 'package:bibliotheque_perso/modeles/chapitre.dart';
import 'package:bibliotheque_perso/modeles/journal.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils_tests_etat.dart';

void main() {
  late JournalMemoire journal;

  setUp(() {
    journal = JournalMemoire();
    Journal.actuel = journal;
  });

  tearDown(() {
    Journal.actuel = const JournalSilencieux();
  });

  Iterable<EntreeJournal> entreesInterface() =>
      journal.entrees.where((e) => e.categorie == CategorieJournal.interface);

  group('DescriptionErreur.depuis', () {
    test('une erreur inattendue est notée en erreur avec sa pile', () {
      final pile = StackTrace.current;
      final description = DescriptionErreur.depuis(StateError('bogue'), pile);

      expect(description.nature, NatureErreur.inattendue);
      final entree = entreesInterface().single;
      expect(entree.niveau, NiveauJournal.erreur);
      expect(entree.erreur, isA<StateError>());
      expect(entree.pile, same(pile));
    });

    test('une erreur déjà journalisée par un service n\'est pas recopiée', () {
      DescriptionErreur.depuis(const ErreurService('Refus du service.'));
      expect(journal.entrees, isEmpty);
    });
  });

  group('aides de l\'interface', () {
    test('noterActionInterface écrit une information', () {
      noterActionInterface('Onglet « Paramètres » ouvert');
      final entree = entreesInterface().single;
      expect(entree.niveau, NiveauJournal.info);
      expect(entree.message, 'Onglet « Paramètres » ouvert');
    });

    test('noterProblemeInterface écrit un avertissement avec l\'erreur', () {
      final erreur = Exception('refus');
      noterProblemeInterface('Ouverture du lien impossible', erreur: erreur);
      final entree = entreesInterface().single;
      expect(entree.niveau, NiveauJournal.avertissement);
      expect(entree.erreur, same(erreur));
    });
  });

  group('fiche et lecteur', () {
    late FauxServiceBibliotheque bibliotheque;
    late FauxServiceTelechargement telechargement;

    setUp(() {
      bibliotheque = FauxServiceBibliotheque();
      telechargement = FauxServiceTelechargement(bibliotheque);
      bibliotheque.ajouterTitreDeTest(
        'Titre',
        chapitres: const <Chapitre>[
          Chapitre(id: 1, urlChapitre: 'u1', nom: 'Un', numero: 1),
          Chapitre(id: 2, urlChapitre: 'u2', nom: 'Deux', numero: 2),
        ],
      );
      telechargement.ajouterChapitreTelecharge(1, nombrePages: 2);
    });

    test('l\'ouverture d\'une fiche est notée une seule fois', () async {
      final etat = EtatTitre(bibliotheque, 1);
      await etat.charger();
      // « Réessayer » ou relecture : pas de seconde ligne.
      await etat.charger();

      final ouvertures = entreesInterface()
          .where((e) => e.message.startsWith('Fiche ouverte'))
          .toList();
      expect(ouvertures, hasLength(1));
      expect(ouvertures.single.message, contains('« Titre »'));
      expect(ouvertures.single.niveau, NiveauJournal.info);

      etat.dispose();
      expect(entreesInterface().last.message, 'Fiche du titre n°1 fermée');
    });

    test('la lecture d\'un chapitre téléchargé est notée à l\'ouverture, à '
        'la fin et à la fermeture', () async {
      final etat = EtatLecteur(
        serviceBibliotheque: bibliotheque,
        serviceTelechargement: telechargement,
        idTitre: 1,
        idChapitre: 1,
      );
      await etat.charger();

      expect(
        entreesInterface().map((e) => e.message),
        contains(
          'Lecteur : chapitre n°1 (numéro 1) du titre n°1 ouvert : '
          '2 page(s) depuis le disque',
        ),
      );

      etat.signalerPageVisible(1);
      await etat.marquerFinLecture();
      expect(
        entreesInterface().map((e) => e.message),
        contains('Lecteur : chapitre n°1 marqué lu (fin de lecture)'),
      );

      etat.dispose();
      expect(
        entreesInterface().last.message,
        'Lecteur fermé : chapitre n°1 du titre n°1, page 2/2',
      );
    });

    test('un chapitre non téléchargé est noté comme tel', () async {
      final etat = EtatLecteur(
        serviceBibliotheque: bibliotheque,
        serviceTelechargement: telechargement,
        idTitre: 1,
        idChapitre: 2,
      );
      addTearDown(etat.dispose);
      await etat.charger();

      expect(
        entreesInterface().map((e) => e.message),
        contains(
          'Lecteur : chapitre n°2 (numéro 2) du titre n°1 ouvert : '
          'non téléchargé (hors file)',
        ),
      );
    });
  });
}
