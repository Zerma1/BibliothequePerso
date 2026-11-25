/// Section « Pourquoi ce site n'est pas lisible ? » (tâche T3), affichée
/// sous un refus d'ajout de site.
library;

import 'package:material_ui/material_ui.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_sources.dart' show DiagnosticLisibilite;
import 'constantes_interface.dart';
import 'textes.dart';

/// Bouton « Pourquoi ce site n'est pas lisible ? » qui, à l'appui, lance
/// [diagnostiquer] puis affiche les raisons et les remarques du diagnostic.
///
/// Le diagnostic n'est lancé qu'à la demande du client : il coûte une
/// requête au site (règle de charge des sites). [diagnostiquer] est une
/// méthode d'un état (`EtatTitre.diagnostiquerSite`,
/// `EtatSources.diagnostiquerSite`) ; ce widget ne fait que l'afficher.
class SectionDiagnosticSite extends StatefulWidget {
  /// Crée la section.
  const SectionDiagnosticSite({super.key, required this.diagnostiquer});

  /// Lance le diagnostic de l'adresse refusée.
  final Future<ResultatAction<DiagnosticLisibilite>> Function() diagnostiquer;

  @override
  State<SectionDiagnosticSite> createState() => _EtatSectionDiagnosticSite();
}

class _EtatSectionDiagnosticSite extends State<SectionDiagnosticSite> {
  bool _enCours = false;
  ResultatAction<DiagnosticLisibilite>? _resultat;

  Future<void> _lancer() async {
    setState(() {
      _enCours = true;
      _resultat = null;
    });
    final resultat = await widget.diagnostiquer();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _resultat = resultat;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultat = _resultat;
    final diagnostic = resultat?.donnee;
    final erreur = resultat?.erreur;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Aligné à gauche, comme les autres actions secondaires du dialogue.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _enCours ? null : _lancer,
            icon: const Icon(Icons.help_outline),
            label: const Text(Textes.pourquoiIllisible),
          ),
        ),
        if (_enCours) ...<Widget>[
          const LinearProgressIndicator(),
          const SizedBox(height: espacementPetit),
          const Text(Textes.diagnosticEnCours),
        ],
        if (erreur != null)
          Text(Textes.diagnosticImpossible(Textes.messageErreur(erreur))),
        if (diagnostic != null)
          // Encadré : le diagnostic se distingue du message d'erreur
          // au-dessus, qu'il explique.
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(espacementPetit),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (diagnostic.protectionAntiRobot) ...<Widget>[
                    Text(
                      Textes.explicationProtectionAntiRobot,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: espacementPetit),
                  ],
                  if (diagnostic.estLisible)
                    const Text(Textes.diagnosticLisible)
                  else ...<Widget>[
                    Text(
                      Textes.raisonsIllisible,
                      style: theme.textTheme.titleSmall,
                    ),
                    for (final raison in diagnostic.raisons) Text('• $raison'),
                  ],
                  if (diagnostic.remarques.isNotEmpty) ...<Widget>[
                    const SizedBox(height: espacementPetit),
                    Text(
                      Textes.remarquesDiagnostic,
                      style: theme.textTheme.titleSmall,
                    ),
                    for (final remarque in diagnostic.remarques)
                      Text('• $remarque', style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
