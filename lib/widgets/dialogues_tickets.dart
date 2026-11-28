/// Dialogues des tickets GitHub : saisie d'un nouveau ticket et ouverture
/// d'une page GitHub (avec l'adresse à copier si le navigateur ne s'ouvre
/// pas).
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../etat/journal_interface.dart';
import '../modeles/ticket.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'textes.dart';

/// Ouvre une adresse dans le navigateur du système ; renvoie `true` si le
/// système l'a acceptée. Remplaçable dans les tests.
typedef OuvreurLien = Future<bool> Function(Uri adresse);

/// Ouvreur par défaut : navigateur externe via `url_launcher`.
Future<bool> ouvrirDansNavigateur(Uri adresse) async {
  try {
    return await launchUrl(adresse, mode: LaunchMode.externalApplication);
  } catch (erreur) {
    noterProblemeInterface(
      'Ouverture de la page GitHub impossible',
      erreur: erreur,
    );
    return false;
  }
}

/// Ouvre la page GitHub [adresse] ; si le navigateur ne s'ouvre pas,
/// affiche l'adresse (sélectionnable) avec un bouton « Copier l'adresse ».
/// Renvoie `true` si la page s'est ouverte.
Future<bool> ouvrirPageGithub(
  BuildContext context,
  Uri adresse, {
  OuvreurLien ouvrir = ouvrirDansNavigateur,
}) async {
  if (await ouvrir(adresse)) return true;
  if (!context.mounted) return false;
  final texte = adresse.toString();
  await showDialog<void>(
    context: context,
    builder: (contexteDialogue) => AlertDialog(
      title: const Text(Textes.ouvertureImpossible),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(Textes.explicationOuvertureImpossible),
              const SizedBox(height: espacementPetit),
              // L'adresse pré-remplie est longue : sélectionnable et
              // défilante plutôt que coupée.
              SelectableText(texte),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: texte));
            if (contexteDialogue.mounted) {
              afficherMessage(contexteDialogue, Textes.adresseCopiee);
            }
          },
          child: const Text(Textes.copierAdresse),
        ),
        FilledButton(
          onPressed: () => Navigator.of(contexteDialogue).pop(),
          child: const Text(Textes.fermer),
        ),
      ],
    ),
  );
  return false;
}

/// Saisie du dialogue « Nouveau ticket ».
class SaisieTicket {
  /// Crée la saisie.
  const SaisieTicket({
    required this.type,
    required this.titre,
    required this.description,
  });

  /// Nature du ticket.
  final TypeTicket type;

  /// Titre (non vide).
  final String titre;

  /// Description (peut être vide).
  final String description;
}

/// Dialogue de création d'un ticket : type, titre obligatoire,
/// description et avertissement « public ». Renvoie la [SaisieTicket], ou
/// `null` si le client annule.
class DialogueNouveauTicket extends StatefulWidget {
  /// Crée le dialogue.
  const DialogueNouveauTicket({super.key});

  @override
  State<DialogueNouveauTicket> createState() => _EtatDialogueNouveauTicket();
}

class _EtatDialogueNouveauTicket extends State<DialogueNouveauTicket> {
  final GlobalKey<FormState> _cleFormulaire = GlobalKey<FormState>();
  final TextEditingController _titre = TextEditingController();
  final TextEditingController _description = TextEditingController();
  TypeTicket _type = TypeTicket.bug;

  @override
  void dispose() {
    _titre.dispose();
    _description.dispose();
    super.dispose();
  }

  void _valider() {
    if (!(_cleFormulaire.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      SaisieTicket(
        type: _type,
        titre: _titre.text.trim(),
        description: _description.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text(Textes.titreDialogueNouveauTicket),
      // Largeur plafonnée sur ordinateur ; sur téléphone, le dialogue prend
      // la largeur disponible et le contenu défile au-dessus du clavier.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Form(
            key: _cleFormulaire,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  Textes.libelleTypeTicket,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: espacementPetit),
                // Trois choix courts : un bouton segmenté tient sur un
                // téléphone et montre le choix actif d'un coup d'œil.
                SegmentedButton<TypeTicket>(
                  segments: <ButtonSegment<TypeTicket>>[
                    for (final type in TypeTicket.values)
                      ButtonSegment<TypeTicket>(
                        value: type,
                        label: Text(Textes.nomTypeTicket(type)),
                      ),
                  ],
                  selected: <TypeTicket>{_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (choix) =>
                      setState(() => _type = choix.first),
                ),
                const SizedBox(height: espacementMoyen),
                TextFormField(
                  controller: _titre,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: Textes.libelleTitreTicket,
                    border: OutlineInputBorder(),
                  ),
                  validator: (valeur) => (valeur ?? '').trim().isEmpty
                      ? Textes.champObligatoire
                      : null,
                ),
                const SizedBox(height: espacementMoyen),
                TextFormField(
                  controller: _description,
                  minLines: 4,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: Textes.libelleDescriptionTicket,
                    hintText: Textes.aideDescriptionTicket,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: espacementMoyen),
                // Avertissement juste au-dessus des boutons : le client le
                // lit au moment de valider.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.public, color: theme.colorScheme.tertiary),
                    const SizedBox(width: espacementPetit),
                    Expanded(
                      child: Text(
                        Textes.avertissementTicketPublic,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton.icon(
          onPressed: _valider,
          icon: const Icon(Icons.open_in_new),
          label: const Text(Textes.continuerSurGithub),
        ),
      ],
    );
  }
}
