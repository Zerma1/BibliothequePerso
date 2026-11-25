/// Import d'un export de la bibliothèque (U1) : choix du fichier, import,
/// bilan, puis relecture des écrans concernés.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_bibliotheque.dart';
import '../etat/etat_export.dart';
import '../etat/etat_parametres.dart';
import '../etat/etat_parutions.dart';
import '../etat/etat_sources.dart';
import 'constantes_interface.dart';
import 'textes.dart';

/// Ouvre le dialogue d'import ; après un import réussi, affiche le bilan
/// (résumé et lignes non importées) et relit la bibliothèque, les sites,
/// les mises à jour et les réglages (langues reprises du fichier).
Future<void> ouvrirImport(BuildContext context, EtatExport etat) async {
  final resultat = await showDialog<ResultatImport>(
    context: context,
    // Pendant l'import, un appui à côté ne doit pas fermer la boîte : le
    // client perdrait le bilan.
    barrierDismissible: false,
    builder: (_) => DialogueImport(etat: etat),
  );
  if (resultat == null || !context.mounted) return;
  _relireEcrans(context);
  await showDialog<void>(
    context: context,
    builder: (_) => DialogueBilanImport(resultat: resultat),
  );
}

/// Relit les états dont les données ont pu changer. Un état absent (tests
/// d'un seul écran) est ignoré.
void _relireEcrans(BuildContext context) {
  void relire<T>(Future<void> Function(T etat) action) {
    try {
      action(context.read<T>());
    } on ProviderNotFoundException {
      // Écran non fourni : rien à relire.
    }
  }

  relire<EtatBibliotheque>((etat) => etat.charger());
  relire<EtatSources>((etat) => etat.charger());
  relire<EtatParutions>((etat) => etat.charger());
  relire<EtatParametres>((etat) async {
    await etat.charger();
    // Titres ajoutés à Favoris/Suivis, archive complète activée par le
    // fichier : leurs téléchargements partent tout de suite.
    await etat.appliquerReglesATous();
  });
}

/// Dialogue « Importer un export » : liste des exports trouvés (un appui
/// remplit le champ) et champ pour coller le chemin d'un autre fichier.
/// Renvoie le [ResultatImport] d'un import réussi, ou `null` si le client
/// annule. Un fichier refusé laisse la boîte ouverte avec le message.
///
/// Reçoit l'[EtatExport] directement : le dialogue est construit au-dessus
/// de la route courante.
class DialogueImport extends StatefulWidget {
  /// Crée le dialogue pour [etat].
  const DialogueImport({super.key, required this.etat});

  /// État de l'export et de l'import.
  final EtatExport etat;

  @override
  State<DialogueImport> createState() => _EtatDialogueImport();
}

class _EtatDialogueImport extends State<DialogueImport> {
  final TextEditingController _chemin = TextEditingController();
  late final Future<List<String>> _exports = widget.etat
      .chargerExportsDisponibles();
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    // Le bouton « Importer » suit le contenu du champ.
    _chemin.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _chemin.dispose();
    super.dispose();
  }

  Future<void> _importer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.etat.importer(_chemin.text);
    if (!mounted) return;
    final import = resultat.donnee;
    if (import != null) {
      Navigator.of(context).pop(import);
      return;
    }
    final erreur = resultat.erreur;
    setState(() {
      _enCours = false;
      _erreur = erreur == null ? null : Textes.messageErreur(erreur);
    });
  }

  /// Nom du fichier seul (la liste reste lisible) ; le chemin complet est
  /// en sous-titre.
  static String _nomFichier(String chemin) =>
      chemin.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ??
      chemin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final erreur = _erreur;
    final peutImporter = !_enCours && _chemin.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text(Textes.importerUnExport),
      // Largeur bornée : sur grand écran, des chemins sur toute la largeur
      // se lisent mal ; sur téléphone, la boîte prend la place disponible.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(Textes.explicationImport),
              const SizedBox(height: espacementMoyen),
              Text(Textes.exportsTrouves, style: theme.textTheme.titleSmall),
              FutureBuilder<List<String>>(
                future: _exports,
                builder: (context, instantane) {
                  final exports = instantane.data;
                  if (exports == null) {
                    return const Padding(
                      padding: EdgeInsets.all(espacementPetit),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (exports.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: espacementPetit),
                      child: Text(Textes.aucunExportTrouve),
                    );
                  }
                  return Column(
                    children: <Widget>[
                      for (final chemin in exports)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _chemin.text == chemin
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(_nomFichier(chemin)),
                          subtitle: Text(
                            chemin,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          enabled: !_enCours,
                          onTap: () => _chemin.text = chemin,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: espacementMoyen),
              TextField(
                controller: _chemin,
                enabled: !_enCours,
                decoration: const InputDecoration(
                  labelText: Textes.champCheminImport,
                  hintText: Textes.aideCheminImport,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: peutImporter ? (_) => _importer() : null,
              ),
              if (_enCours) ...<Widget>[
                const SizedBox(height: espacementPetit),
                const LinearProgressIndicator(),
                const SizedBox(height: espacementPetit),
                const Text(Textes.importEnCours),
              ],
              if (erreur != null) ...<Widget>[
                const SizedBox(height: espacementPetit),
                Text(erreur, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: peutImporter ? _importer : null,
          child: const Text(Textes.importer),
        ),
      ],
    );
  }
}

/// Bilan d'un import : résumé du service, puis lignes non importées.
class DialogueBilanImport extends StatelessWidget {
  /// Crée le bilan de [resultat].
  const DialogueBilanImport({super.key, required this.resultat});

  /// Résultat de l'import.
  final ResultatImport resultat;

  @override
  Widget build(BuildContext context) {
    final erreurs = resultat.erreurs;
    return AlertDialog(
      title: const Text(Textes.importTermine),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(resultat.resume),
              if (erreurs.isNotEmpty) ...<Widget>[
                const SizedBox(height: espacementMoyen),
                Text(
                  Textes.erreursImport(erreurs.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: espacementPetit),
                // Lignes sélectionnables : le client peut les copier dans
                // son retour.
                for (final erreur in erreurs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: espacementPetit),
                    child: SelectableText('• ${erreur.description}'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Textes.fermer),
        ),
      ],
    );
  }
}
