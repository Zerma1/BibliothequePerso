/// Boîte de dialogue « Ajouter un titre » : adresse et listes.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_bibliotheque.dart';
import '../etat/etat_sources.dart';
import 'constantes_interface.dart';
import 'textes.dart';

/// Ouvre la boîte de dialogue d'ajout d'un titre.
///
/// Renvoie le message de confirmation à afficher, ou `null` si le client a
/// annulé.
Future<String?> afficherDialogueAjoutTitre(BuildContext context) {
  return showDialog<String>(
    context: context,
    // Pendant la lecture du site, un appui à côté ne doit pas fermer la
    // boîte : le client perdrait le résultat de l'ajout.
    barrierDismissible: false,
    builder: (_) => const DialogueAjoutTitre(),
  );
}

/// Formulaire d'ajout d'un titre par son adresse, avec le choix des listes
/// (Favoris et Suivis cochées par défaut).
class DialogueAjoutTitre extends StatefulWidget {
  /// Crée le dialogue.
  const DialogueAjoutTitre({super.key});

  @override
  State<DialogueAjoutTitre> createState() => _EtatDialogueAjoutTitre();
}

class _EtatDialogueAjoutTitre extends State<DialogueAjoutTitre> {
  final TextEditingController _url = TextEditingController();

  /// Listes choisies par le client ; `null` tant qu'il n'a rien touché : on
  /// suit alors les listes par défaut, même si elles arrivent après
  /// l'ouverture du dialogue.
  Set<int>? _idsListesChoisies;
  String? _messageErreur;

  @override
  void initState() {
    super.initState();
    final etat = context.read<EtatBibliotheque>();
    if (!etat.estCharge && !etat.estEnChargement) {
      // Listes jamais chargées (chargement initial en erreur…) : on les
      // demande, sans notifier pendant la construction du dialogue.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          etat.charger();
        }
      });
    }
  }

  Set<int> _idsListes(EtatBibliotheque etat) =>
      _idsListesChoisies ?? etat.idsListesParDefaut;

  void _cocher(EtatBibliotheque etat, int idListe, bool coche) {
    setState(() {
      final choisies = _idsListesChoisies ??= <int>{
        ...etat.idsListesParDefaut,
      };
      if (coche) {
        choisies.add(idListe);
      } else {
        choisies.remove(idListe);
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _ajouter() async {
    final etat = context.read<EtatBibliotheque>();
    final etatSources = context.read<EtatSources>();
    setState(() => _messageErreur = null);
    final resultat = await etat.ajouterTitre(_url.text, _idsListes(etat));
    // MangaDex est ajouté automatiquement à la première adresse collée, même
    // si la lecture du titre échoue ensuite : l'onglet Sources doit le
    // montrer.
    if (resultat.erreur?.nature != NatureErreur.adresseVide) {
      unawaited(etatSources.charger());
    }
    if (!mounted) {
      return;
    }
    final erreur = resultat.erreur;
    final ajout = resultat.donnee;
    if (erreur != null || ajout == null) {
      // L'erreur reste dans la boîte : le client peut corriger l'adresse sans
      // tout ressaisir.
      setState(
        () => _messageErreur = erreur == null
            ? Textes.erreurInattendue
            : Textes.messageErreur(erreur),
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(Textes.titreAjoute(ajout.titre.nom, ajout.nombreNouveauxChapitres));
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatBibliotheque>();
    final enCours = etat.estEnAjout;
    final messageErreur = _messageErreur;
    return AlertDialog(
      title: const Text(Textes.boutonAjouterTitre),
      // Largeur bornée : sur grand écran, un champ d'URL immense est
      // difficile à lire ; sur téléphone, le dialogue prend la place
      // disponible.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _url,
                enabled: !enCours,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: Textes.champUrlTitre,
                  hintText: Textes.aideUrlTitre,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: enCours ? null : (_) => _ajouter(),
              ),
              const SizedBox(height: espacementMoyen),
              const Text(Textes.rangerDans),
              if (etat.listes.isEmpty && etat.estEnChargement)
                const LinearProgressIndicator(),
              for (final liste in etat.listes)
                if (liste.id != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(liste.nom),
                    value: _idsListes(etat).contains(liste.id),
                    onChanged: enCours
                        ? null
                        : (coche) => _cocher(etat, liste.id!, coche ?? false),
                  ),
              if (enCours) ...<Widget>[
                const SizedBox(height: espacementPetit),
                const LinearProgressIndicator(),
                const SizedBox(height: espacementPetit),
                const Text(Textes.ajoutTitreEnCours),
              ],
              if (messageErreur != null) ...<Widget>[
                const SizedBox(height: espacementPetit),
                Text(
                  messageErreur,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: enCours ? null : () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: enCours ? null : _ajouter,
          child: const Text(Textes.ajouter),
        ),
      ],
    );
  }
}
