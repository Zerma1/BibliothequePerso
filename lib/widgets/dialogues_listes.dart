/// Dialogues des listes personnelles (tâche X4) : créer, renommer et
/// supprimer une liste. Partagés par la bibliothèque et l'écran « Gérer les
/// listes ».
library;

import 'package:material_ui/material_ui.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_bibliotheque.dart';
import '../modeles/liste_lecture.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'textes.dart';

/// Crée une liste : demande son nom, puis affiche le résultat.
Future<void> creerListeAvecDialogue(
  BuildContext context,
  EtatBibliotheque etat,
) async {
  final nom = await showDialog<String>(
    context: context,
    builder: (_) => DialogueNomListe(
      titre: Textes.nouvelleListe,
      libelleValider: Textes.creer,
      surValider: etat.creerListe,
    ),
  );
  if (nom != null && context.mounted) {
    afficherMessage(context, Textes.listeCreee(nom));
  }
}

/// Renomme [liste] : demande le nouveau nom, puis affiche le résultat.
Future<void> renommerListeAvecDialogue(
  BuildContext context,
  EtatBibliotheque etat,
  ListeLecture liste,
) async {
  final idListe = liste.id;
  if (idListe == null) return;
  final nom = await showDialog<String>(
    context: context,
    builder: (_) => DialogueNomListe(
      titre: Textes.titreRenommerListe,
      libelleValider: Textes.renommer,
      nomInitial: liste.nom,
      surValider: (nom) => etat.renommerListe(idListe, nom),
    ),
  );
  if (nom != null && context.mounted) {
    afficherMessage(context, Textes.listeRenommee(nom));
  }
}

/// Supprime [liste] après confirmation (ses titres restent dans la
/// bibliothèque), puis affiche le résultat.
Future<void> supprimerListeAvecConfirmation(
  BuildContext context,
  EtatBibliotheque etat,
  ListeLecture liste,
) async {
  final idListe = liste.id;
  if (idListe == null) return;
  final confirme = await showDialog<bool>(
    context: context,
    builder: (contexteDialogue) => AlertDialog(
      title: const Text(Textes.supprimerListe),
      content: Text(Textes.confirmationSuppressionListe(liste.nom)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(contexteDialogue).pop(false),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: () => Navigator.of(contexteDialogue).pop(true),
          child: const Text(Textes.supprimer),
        ),
      ],
    ),
  );
  if (confirme != true || !context.mounted) return;
  final resultat = await etat.supprimerListe(idListe);
  if (context.mounted) {
    afficherResultat(
      context,
      resultat,
      succes: Textes.listeSupprimee(liste.nom),
    );
  }
}

/// Dialogue de saisie du nom d'une liste. Le nom est validé par
/// [surValider] (le service) : un refus (nom vide, déjà pris…) s'affiche
/// sous le champ et le dialogue reste ouvert ; une réussite le ferme en
/// renvoyant le nom enregistré.
class DialogueNomListe extends StatefulWidget {
  /// Crée le dialogue.
  const DialogueNomListe({
    super.key,
    required this.titre,
    required this.libelleValider,
    required this.surValider,
    this.nomInitial = '',
  });

  /// Titre du dialogue.
  final String titre;

  /// Libellé du bouton de validation.
  final String libelleValider;

  /// Nom prérempli (renommage).
  final String nomInitial;

  /// Enregistre le nom ; renvoie la liste enregistrée, ou l'erreur à
  /// afficher.
  final Future<ResultatAction<ListeLecture>> Function(String nom) surValider;

  @override
  State<DialogueNomListe> createState() => _EtatDialogueNomListe();
}

class _EtatDialogueNomListe extends State<DialogueNomListe> {
  late final TextEditingController _nom = TextEditingController(
    text: widget.nomInitial,
  );
  String? _messageErreur;
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _messageErreur = null;
    });
    final resultat = await widget.surValider(_nom.text);
    if (!mounted) return;
    final erreur = resultat.erreur;
    if (erreur != null) {
      setState(() {
        _enCours = false;
        _messageErreur = Textes.messageErreur(erreur);
      });
      return;
    }
    // Nom tel qu'enregistré (espaces superflus retirés par le service).
    Navigator.of(context).pop(resultat.donnee?.nom ?? _nom.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      // Largeur bornée : un nom de liste est court, un champ immense sur
      // grand écran serait difficile à lire.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: TextField(
          controller: _nom,
          autofocus: true,
          enabled: !_enCours,
          decoration: InputDecoration(
            labelText: Textes.champNomListe,
            border: const OutlineInputBorder(),
            errorText: _messageErreur,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _valider(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: _enCours ? null : _valider,
          child: Text(widget.libelleValider),
        ),
      ],
    );
  }
}
