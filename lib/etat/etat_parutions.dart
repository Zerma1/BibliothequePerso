/// État de l'onglet « Mises à jour » (tâche IN1 de l'étape 6) : titres
/// suivis, favoris et en attente triés par dernière parution dans leurs
/// langues.
library;

import '../services/service_bibliotheque.dart';
import 'description_erreur.dart';

// Les écrans n'importent que les états (PLAYBOOK.md section 4) : la ligne
// affichée leur est fournie par cet état.
export '../services/service_bibliotheque.dart' show ParutionTitre;

/// Dernières parutions des titres suivis, favoris et en attente.
///
/// Lecture de la base seulement (aucun réseau) : l'écran la relance après
/// chaque recherche de nouveaux chapitres et au retour d'une fiche.
class EtatParutions extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire la base.
  ///
  /// [maintenant] permet aux tests de fixer l'heure des dates relatives.
  EtatParutions(this._service, {DateTime Function()? maintenant})
    : _maintenant = maintenant ?? DateTime.now;

  final ServiceBibliotheque _service;
  final DateTime Function() _maintenant;

  List<ParutionTitre> _parutions = const <ParutionTitre>[];
  bool _estEnChargement = false;
  bool _estCharge = false;
  DescriptionErreur? _erreur;

  /// Numéro du dernier chargement : une réponse plus ancienne est ignorée.
  int _numeroChargement = 0;

  /// Lignes, la parution la plus récente d'abord ; les titres sans aucun
  /// chapitre dans leurs langues à la fin.
  List<ParutionTitre> get parutions => _parutions;

  /// Lignes qui ont au moins une parution dans leurs langues.
  List<ParutionTitre> get avecParution =>
      _parutions.where((ligne) => ligne.derniereParution != null).toList();

  /// Lignes sans aucun chapitre dans leurs langues (en général « En
  /// attente »).
  List<ParutionTitre> get sansParution =>
      _parutions.where((ligne) => ligne.derniereParution == null).toList();

  /// Nombre de titres dont le dernier chapitre paru n'est pas lu (badge de
  /// l'onglet).
  int get nombreNouveautes =>
      _parutions.where((ligne) => ligne.aNouveaute).length;

  /// Heure actuelle (dates relatives « aujourd'hui », « hier »…).
  DateTime get maintenant => _maintenant();

  /// `true` pendant un chargement.
  bool get estEnChargement => _estEnChargement;

  /// `true` une fois qu'un chargement a abouti.
  bool get estCharge => _estCharge;

  /// Erreur du dernier chargement, ou `null`.
  DescriptionErreur? get erreur => _erreur;

  /// `true` si le chargement a abouti sans aucune ligne.
  bool get estVide => _estCharge && _erreur == null && _parutions.isEmpty;

  /// Lit les dernières parutions.
  Future<void> charger() async {
    final numero = ++_numeroChargement;
    _estEnChargement = true;
    _erreur = null;
    notifier();
    try {
      final parutions = await _service.chargerDernieresParutions();
      if (numero != _numeroChargement) return;
      _parutions = parutions;
      _estCharge = true;
    } catch (erreur, pile) {
      if (numero != _numeroChargement) return;
      _erreur = DescriptionErreur.depuis(erreur, pile);
    }
    _estEnChargement = false;
    notifier();
  }
}
