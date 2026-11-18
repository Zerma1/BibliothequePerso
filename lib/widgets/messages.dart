/// Petits messages temporaires et ouverture de liens externes.
library;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../etat/description_erreur.dart';
import 'textes.dart';

/// Durée d'affichage d'un message d'erreur : plus longue que les 4 s par
/// défaut, car un refus du service est souvent une phrase complète avec une
/// consigne (par exemple « chapitres en cours de déplacement… »).
const Duration dureeMessageErreur = Duration(seconds: 10);

/// Affiche [texte] dans une barre temporaire en bas de l'écran. Avec
/// [estErreur], la barre reste plus longtemps et peut être fermée.
void afficherMessage(
  BuildContext context,
  String texte, {
  bool estErreur = false,
}) {
  final messager = ScaffoldMessenger.of(context);
  // Un message plus ancien encore visible est remplacé : le client voit
  // toujours le résultat de sa dernière action.
  messager
    ..hideCurrentSnackBar()
    ..showSnackBar(
      estErreur
          ? SnackBar(
              content: Text(texte),
              duration: dureeMessageErreur,
              // Le client peut fermer un long message une fois lu.
              showCloseIcon: true,
            )
          : SnackBar(content: Text(texte)),
    );
}

/// Affiche l'erreur d'une action échouée, ou [succes] si elle a réussi.
void afficherResultat<T>(
  BuildContext context,
  ResultatAction<T> resultat, {
  String? succes,
}) {
  final erreur = resultat.erreur;
  if (erreur != null) {
    afficherMessage(context, Textes.messageErreur(erreur), estErreur: true);
  } else if (succes != null) {
    afficherMessage(context, succes);
  }
}

/// Demande au client de confirmer la suppression de l'archive du chapitre
/// [nomChapitre] ; renvoie `true` s'il confirme. Partagé par la fiche du
/// titre et l'écran Téléchargements pour que la question soit la même.
Future<bool> confirmerSuppressionTelechargement(
  BuildContext context,
  String nomChapitre,
) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (contexteDialogue) => AlertDialog(
      title: const Text(Textes.supprimerTelechargement),
      content: Text(Textes.confirmationSuppressionTelechargement(nomChapitre)),
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
  return confirme ?? false;
}

/// Ouvre [url] dans le navigateur du système.
///
/// Ce n'est pas une requête HTTP de l'application : c'est le navigateur qui
/// charge la page. Un échec est signalé par un message, jamais par un
/// plantage.
Future<void> ouvrirLienExterne(BuildContext context, String url) async {
  final messager = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  var estOuvert = false;
  if (uri != null) {
    try {
      estOuvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (erreur) {
      debugPrint('Ouverture du lien impossible ($url) : $erreur');
    }
  }
  if (!estOuvert) {
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(Textes.lienImpossible)));
  }
}
