/// État du thème de l'interface (Paramètres → Apparence) : Système, Clair
/// ou Sombre.
library;

import '../modeles/journal.dart';
import '../services/service_parametres.dart';
import 'description_erreur.dart';

// L'interface n'importe pas les services : le choix du thème lui parvient
// par cet état.
export '../services/service_parametres.dart' show ModeTheme;

/// Thème choisi par le client, lu au démarrage et modifiable dans les
/// Paramètres. La racine de l'application le surveille pour passer du clair
/// au sombre sans redémarrage.
class EtatTheme extends EtatNotifiant {
  /// Crée l'état ; appeler [charger] pour lire le choix enregistré.
  ///
  /// [modeInitial] : choix déjà lu avant l'affichage (évite un éclair du
  /// thème du système au démarrage) ; par défaut, celui du service.
  EtatTheme(this._serviceParametres, {ModeTheme? modeInitial})
    : _mode = modeInitial ?? ServiceParametres.modeThemeParDefaut;

  final ServiceParametres _serviceParametres;

  ModeTheme _mode;
  bool _estEnEnregistrement = false;

  /// Thème choisi.
  ModeTheme get mode => _mode;

  /// `true` pendant l'enregistrement d'un nouveau choix.
  bool get estEnEnregistrement => _estEnEnregistrement;

  /// Lit le choix enregistré. Une erreur est seulement journalisée : le
  /// thème ne doit jamais empêcher l'application de s'afficher (on garde
  /// alors le thème du système).
  Future<void> charger() async {
    try {
      final mode = await _serviceParametres.chargerModeTheme();
      if (mode != _mode) {
        _mode = mode;
        notifier();
      }
    } catch (erreur, pile) {
      Journal.actuel.avertissement(
        CategorieJournal.parametres,
        'Thème enregistré illisible : thème du système',
        erreur: erreur,
        pile: pile,
      );
    }
  }

  /// Applique [mode] tout de suite (le client voit l'effet de son choix
  /// sans attendre la base), puis l'enregistre ; en cas d'échec, l'ancien
  /// thème revient.
  Future<ResultatAction<ModeTheme>> modifier(ModeTheme mode) async {
    final precedent = _mode;
    _mode = mode;
    _estEnEnregistrement = true;
    notifier();
    try {
      await _serviceParametres.enregistrerModeTheme(mode);
      return ResultatAction<ModeTheme>.reussite(mode);
    } catch (erreur, pile) {
      _mode = precedent;
      return ResultatAction<ModeTheme>.echec(
        DescriptionErreur.depuis(erreur, pile),
      );
    } finally {
      _estEnEnregistrement = false;
      notifier();
    }
  }
}
