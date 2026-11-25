/// Bloc « Ma description » de la fiche d'un titre, et son dialogue de saisie.
///
/// Décision du client : la fiche venant du site n'est pas modifiable ; seule
/// une description personnelle, distincte du résumé du site, peut être
/// ajoutée.
library;

import 'package:material_ui/material_ui.dart';

import '../etat/etat_titre.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'textes.dart';

/// Description personnelle du titre de [etat], affichée sous le résumé du
/// site : « Ajouter une description » quand elle est vide, sinon le texte
/// avec « Modifier » et « Effacer ».
class BlocDescriptionPerso extends StatelessWidget {
  /// Crée le bloc pour le titre de [etat].
  const BlocDescriptionPerso({super.key, required this.etat});

  /// État de la fiche du titre.
  final EtatTitre etat;

  Future<void> _modifier(BuildContext context) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => DialogueDescriptionPerso(etat: etat),
    );
    if (message != null && context.mounted) {
      afficherMessage(context, message);
    }
  }

  Future<void> _effacer(BuildContext context) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.titreEffacerDescription),
        content: const Text(Textes.confirmationEffacerDescription),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.effacerDescription),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.enregistrerDescriptionPerso(null);
    if (!context.mounted) return;
    afficherResultat(context, resultat, succes: Textes.descriptionEffacee);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = etat.descriptionPerso;
    final aDescription = description != null && description.trim().isNotEmpty;
    final occupe = etat.estEnEnregistrementDescription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(Textes.maDescription, style: theme.textTheme.titleMedium),
        Text(
          Textes.aideMaDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: espacementPetit),
        if (aDescription) ...<Widget>[
          // Fond teinté : le texte du client se distingue du résumé du site
          // juste au-dessus, sans titre supplémentaire.
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(espacementPetit),
            ),
            child: Padding(
              padding: const EdgeInsets.all(espacementMoyen),
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(description.trim()),
              ),
            ),
          ),
          // Wrap : les deux boutons passent l'un sous l'autre sur un écran
          // très étroit au lieu de déborder.
          Wrap(
            spacing: espacementPetit,
            children: <Widget>[
              TextButton.icon(
                onPressed: occupe ? null : () => _modifier(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text(Textes.modifierDescription),
              ),
              TextButton.icon(
                onPressed: occupe ? null : () => _effacer(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text(Textes.effacerDescription),
              ),
            ],
          ),
        ] else
          OutlinedButton.icon(
            onPressed: occupe ? null : () => _modifier(context),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text(Textes.ajouterDescription),
          ),
      ],
    );
  }
}

/// Saisie multi-lignes de la description personnelle, avec compteur de
/// caractères ([EtatTitre.longueurMaxDescription] au plus).
///
/// L'enregistrement se fait depuis le dialogue : en cas d'erreur, le message
/// s'affiche sous le champ et le texte saisi est gardé. Le dialogue renvoie
/// le message de réussite, ou `null` s'il est fermé sans enregistrer.
class DialogueDescriptionPerso extends StatefulWidget {
  /// Crée le dialogue pour le titre de [etat].
  const DialogueDescriptionPerso({super.key, required this.etat});

  /// État de la fiche du titre (le dialogue est une autre route, hors du
  /// fournisseur de la fiche).
  final EtatTitre etat;

  @override
  State<DialogueDescriptionPerso> createState() =>
      _EtatDialogueDescriptionPerso();
}

class _EtatDialogueDescriptionPerso extends State<DialogueDescriptionPerso> {
  late final TextEditingController _texte = TextEditingController(
    text: widget.etat.descriptionPerso ?? '',
  );

  bool _enCours = false;
  String? _messageErreur;

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final texte = _texte.text;
    const maximum = EtatTitre.longueurMaxDescription;
    // Garde-fou : le champ limite déjà la saisie, mais un collage peut
    // dépasser selon la plateforme ; le service refuserait de toute façon.
    if (texte.trim().length > maximum) {
      setState(() => _messageErreur = Textes.descriptionTropLongue(maximum));
      return;
    }
    final avait = (widget.etat.descriptionPerso ?? '').trim().isNotEmpty;
    setState(() {
      _enCours = true;
      _messageErreur = null;
    });
    final resultat = await widget.etat.enregistrerDescriptionPerso(texte);
    if (!mounted) return;
    final erreur = resultat.erreur;
    if (erreur != null) {
      setState(() {
        _enCours = false;
        _messageErreur = Textes.messageErreur(erreur);
      });
      return;
    }
    final estVide = texte.trim().isEmpty;
    Navigator.of(context).pop(
      estVide
          ? (avait ? Textes.descriptionEffacee : null)
          : Textes.descriptionEnregistree,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(Textes.maDescription),
      content: ConstrainedBox(
        // Largeur bornée (lisibilité) ; la hauteur suit le nombre de lignes
        // et le dialogue défile si le clavier réduit l'écran.
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _texte,
                autofocus: true,
                enabled: !_enCours,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                minLines: 5,
                maxLines: 12,
                // maxLength affiche le compteur « n/5000 » sous le champ.
                maxLength: EtatTitre.longueurMaxDescription,
                decoration: InputDecoration(
                  labelText: Textes.champDescription,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  errorText: _messageErreur,
                  errorMaxLines: 4,
                ),
              ),
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
          onPressed: _enCours ? null : _enregistrer,
          child: const Text(Textes.enregistrer),
        ),
      ],
    );
  }
}
