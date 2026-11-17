// ServiceAjoutSite (V2) : réglages d'un site générique — clés exposées,
// vérification avant enregistrement, effacement. Base en mémoire, aucun
// appel réseau (le détecteur n'est jamais appelé).
import 'dart:convert';

import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/modeles/source.dart';
import 'package:bibliotheque_perso/services/erreur_service.dart';
import 'package:bibliotheque_perso/services/service_ajout_site.dart';
import 'package:bibliotheque_perso/sources/detecteur_type_site.dart';
import 'package:bibliotheque_perso/sources/source_generique.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

void main() {
  late Database base;
  late DepotSources depot;
  late ServiceAjoutSite service;
  late Source generique;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    depot = DepotSources(base);
    final client = creerClientTest(
      (http.Request requete) async => http.Response('introuvable', 404),
      HorlogeFactice(),
    );
    service = ServiceAjoutSite(depot, DetecteurTypeSite(client));
    generique = await depot.enregistrerSource(
      const Source(
        nom: 'Générique',
        urlBase: 'https://generique.example',
        typeSource: TypeSource.generique,
        configurationSelecteurs: '{"selecteurTitre":"h1"}',
      ),
    );
  });

  tearDown(() => base.close());

  Matcher erreurNommant(String extrait) => throwsA(
    isA<ErreurService>().having((e) => e.message, 'message', contains(extrait)),
  );

  group('clés et libellés exposés', () {
    test("les clés sont celles de l'adaptateur générique, chacune avec un "
        'libellé français', () {
      expect(
        ServiceAjoutSite.clesReglagesGeneriques,
        ConfigurationGenerique.cles,
      );
      for (final cle in ServiceAjoutSite.clesReglagesGeneriques) {
        expect(ServiceAjoutSite.libellesReglagesGeneriques[cle], isNotNull);
      }
      expect(
        ServiceAjoutSite.clesReglagesGeneriques,
        contains(ServiceAjoutSite.cleMotifNumeroChapitre),
      );
      expect(ServiceAjoutSite.libelleReglageGenerique('inconnue'), 'inconnue');
    });

    test('formulaire ↔ JSON : valeurs vides retirées, aller-retour fidèle', () {
      final json = ServiceAjoutSite.reglagesGeneriquesVersJson(<String, String>{
        'selecteurTitre': '  h1.titre ',
        'selecteurResume': '   ',
        'cleInconnue': 'x',
      });
      expect(jsonDecode(json!), <String, Object?>{
        'selecteurTitre': 'h1.titre',
      });
      expect(
        ServiceAjoutSite.reglagesGeneriquesDepuisJson(json),
        <String, String>{'selecteurTitre': 'h1.titre'},
      );
      expect(
        ServiceAjoutSite.reglagesGeneriquesVersJson(const <String, String>{}),
        isNull,
      );
      expect(
        ServiceAjoutSite.reglagesGeneriquesDepuisJson('pas du json'),
        isEmpty,
      );
    });
  });

  group('normaliserReglagesGeneriques', () {
    test('des réglages vides donnent null', () {
      for (final vide in <String?>[
        null,
        '',
        '  ',
        '{}',
        '{"selecteurTitre":" "}',
      ]) {
        expect(ServiceAjoutSite.normaliserReglagesGeneriques(vide), isNull);
      }
    });

    test('nettoie : espaces, clés inconnues, ordre du formulaire', () {
      final json = ServiceAjoutSite.normaliserReglagesGeneriques(
        '{"motifNumeroChapitre":" chapitre-(\\\\d+) ","inconnue":"x",'
        '"selecteurTitre":"h1"}',
      );
      expect(
        json,
        '{"selecteurTitre":"h1","motifNumeroChapitre":"chapitre-(\\\\d+)"}',
      );
    });

    test('un JSON illisible est refusé clairement', () {
      expect(
        () => ServiceAjoutSite.normaliserReglagesGeneriques('{selecteurTitre'),
        erreurNommant('illisibles'),
      );
    });

    test('une valeur qui n\'est pas un texte nomme le champ fautif', () {
      expect(
        () => ServiceAjoutSite.normaliserReglagesGeneriques(
          '{"selecteurLiensChapitres": 3}',
        ),
        erreurNommant('Liens des chapitres'),
      );
    });

    test('un motif invalide nomme le champ fautif', () {
      expect(
        () => ServiceAjoutSite.normaliserReglagesGeneriques(
          '{"motifNumeroChapitre":"chapitre-(\\\\d+"}',
        ),
        erreurNommant('Numéro de chapitre (expression régulière)'),
      );
    });
  });

  group('modifierSource', () {
    test('des réglages invalides ne sont pas enregistrés', () async {
      await expectLater(
        service.modifierSource(
          generique.copierAvec(
            nom: 'Nouveau nom',
            configurationSelecteurs: '{"motifNumeroChapitre":"("}',
          ),
        ),
        erreurNommant('Numéro de chapitre'),
      );
      final relue = await depot.chargerSource(generique.id!);
      expect(relue!.nom, 'Générique');
      expect(relue.configurationSelecteurs, '{"selecteurTitre":"h1"}');
    });

    test('des réglages vides effacent ceux du site', () async {
      final modifiee = await service.modifierSource(
        generique.copierAvec(configurationSelecteurs: '{"selecteurTitre":""}'),
      );
      expect(modifiee.configurationSelecteurs, isNull);
      expect(
        (await depot.chargerSource(generique.id!))!.configurationSelecteurs,
        isNull,
      );
      // Même chose avec un texte vide.
      final avecReglages = await service.modifierSource(
        generique.copierAvec(
          configurationSelecteurs: '{"selecteurTitre":"h2"}',
        ),
      );
      expect(avecReglages.configurationSelecteurs, '{"selecteurTitre":"h2"}');
      final videe = await service.modifierSource(
        avecReglages.copierAvec(configurationSelecteurs: '  '),
      );
      expect(videe.configurationSelecteurs, isNull);
    });

    test('des réglages valides sont enregistrés nettoyés', () async {
      final modifiee = await service.modifierSource(
        generique.copierAvec(
          configurationSelecteurs:
              '{"selecteurLiensChapitres":" .liste a ","selecteurTitre":""}',
        ),
      );
      expect(
        modifiee.configurationSelecteurs,
        '{"selecteurLiensChapitres":".liste a"}',
      );
    });

    test(
      'des réglages anciens inchangés ne bloquent pas un renommage',
      () async {
        // Enregistré avant la vérification : motif invalide déjà en base.
        final ancienne = await depot.enregistrerSource(
          generique.copierAvec(
            configurationSelecteurs: '{"motifNumeroChapitre":"("}',
          ),
        );
        final renommee = await service.modifierSource(
          ancienne.copierAvec(nom: 'Renommé'),
        );
        expect(renommee.nom, 'Renommé');
        expect(renommee.configurationSelecteurs, '{"motifNumeroChapitre":"("}');
      },
    );
  });
}
