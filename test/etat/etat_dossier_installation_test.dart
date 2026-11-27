// Tests de EtatDossierChapitres avec le **vrai** ServiceDossierChapitres
// (base en mémoire, dossier temporaire) : l'extension
// `DossierInstallationEnAttente` lit le dépôt privé du service, elle ne peut
// pas être simulée par le faux service. Vérifie le branchement par défaut de
// l'état (celui de l'application). Aucun appel réseau.
import 'dart:io';

import 'package:bibliotheque_perso/donnees/depot_chapitres.dart';
import 'package:bibliotheque_perso/donnees/depot_listes.dart';
import 'package:bibliotheque_perso/donnees/depot_parametres.dart';
import 'package:bibliotheque_perso/donnees/depot_sources.dart';
import 'package:bibliotheque_perso/donnees/depot_telechargements.dart';
import 'package:bibliotheque_perso/donnees/depot_titres.dart';
import 'package:bibliotheque_perso/donnees/stockage_telechargements.dart';
import 'package:bibliotheque_perso/etat/etat_dossier_chapitres.dart';
import 'package:bibliotheque_perso/services/service_parametres.dart';
import 'package:bibliotheque_perso/services/service_telechargement.dart';
import 'package:bibliotheque_perso/sources/fabrique_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../donnees/outils_tests_donnees.dart';
import '../sources/outils_tests_sources.dart';

void main() {
  late Database base;
  late Directory temporaire;
  late DepotParametres depotParametres;
  late ServiceDossierChapitres dossiers;
  late EtatDossierChapitres etat;
  late String nas;

  setUp(() async {
    base = await ouvrirBaseDeTest();
    temporaire = await Directory.systemTemp.createTemp('etat_installation');
    final dossierParDefaut = p.join(temporaire.path, 'defaut');
    nas = p.join(temporaire.path, 'nas');
    depotParametres = DepotParametres(base);
    // Aucune requête attendue : toute tentative échoue.
    final client = creerClientTest(
      (_) async => throw StateError('aucun appel réseau dans ce test'),
      HorlogeFactice(),
    );
    final telechargement = ServiceTelechargement(
      depotTelechargements: DepotTelechargements(base),
      depotChapitres: DepotChapitres(base),
      depotTitres: DepotTitres(base),
      depotListes: DepotListes(base),
      depotSources: DepotSources(base),
      stockage: StockageTelechargements(dossierParDefaut),
      fabriqueSources: FabriqueSources(client),
      client: client,
      serviceParametres: ServiceParametres(depotParametres),
      depotParametres: depotParametres,
    );
    addTearDown(telechargement.fermer);
    dossiers = ServiceDossierChapitres(
      serviceTelechargement: telechargement,
      depotParametres: depotParametres,
      cheminDossierParDefaut: () async => dossierParDefaut,
      // Jamais le vrai `emplacements.json` du poste (path_provider).
      cheminFichierEmplacements: () async =>
          p.join(temporaire.path, 'emplacements.json'),
    );
    etat = EtatDossierChapitres(dossiers);
  });

  tearDown(() async {
    etat.dispose();
    await base.close();
    try {
      await temporaire.delete(recursive: true);
    } on FileSystemException {
      // Fichier encore ouvert : nettoyé plus tard, sans conséquence.
    }
  });

  /// Proposition posée comme au démarrage (des chapitres étaient déjà
  /// téléchargés : sans dépôt de chapitres, le service reste prudent).
  Future<void> proposer() =>
      ServiceDossierChapitres.appliquerDossierInstallation(
        depotParametres,
        nas,
        cheminDossierParDefaut: () async => p.join(temporaire.path, 'defaut'),
      );

  test('sans proposition, rien à afficher', () async {
    await etat.charger();

    expect(etat.erreur, isNull);
    expect(etat.dossierInstallationEnAttente, isNull);
  });

  test('charger lit la proposition du vrai service', () async {
    await proposer();
    await etat.charger();

    expect(etat.erreur, isNull);
    expect(etat.dossierInstallationEnAttente, p.normalize(nas));
  });

  test('ignorer la clôt définitivement', () async {
    await proposer();
    await etat.charger();

    final resultat = await etat.ignorerDossierInstallation();
    expect(resultat.estReussi, isTrue);
    expect(etat.dossierInstallationEnAttente, isNull);

    // Relue depuis la base : plus rien à proposer.
    await etat.charger();
    expect(etat.dossierInstallationEnAttente, isNull);
    expect(await dossiers.chargerDossierInstallationEnAttente(), isNull);
  });
}
