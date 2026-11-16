/// Éditeur d'une liste de langues de lecture (« Mes langues » dans les
/// Paramètres, langues propres à un titre sur sa fiche) et dialogue de choix
/// d'une langue.
library;

import 'package:material_ui/material_ui.dart';

import 'constantes_interface.dart';
import 'textes.dart';

/// Liste ordonnée de langues : la première est la favorite (étoile), les
/// autres peuvent la remplacer, monter, descendre ou être retirées ; un
/// bouton ajoute une langue choisie dans une liste en français.
///
/// Le widget ne garde aucun état : chaque action est transmise à
/// l'appelant, qui enregistre (état des Paramètres) ou modifie un brouillon
/// (dialogue des langues d'un titre).
class EditeurLangues extends StatelessWidget {
  /// Crée l'éditeur.
  const EditeurLangues({
    super.key,
    required this.langues,
    required this.surAjouter,
    required this.surRetirer,
    required this.surDeplacer,
    required this.surChoisirFavorite,
    this.nombreMaximal,
    this.estOccupe = false,
  });

  /// Langues affichées (codes), la favorite d'abord.
  final List<String> langues;

  /// Ajout d'une langue (code choisi dans le dialogue).
  final ValueChanged<String> surAjouter;

  /// Retrait d'une langue.
  final ValueChanged<String> surRetirer;

  /// Déplacement d'une langue de −1 (plus préférée) ou +1 (moins).
  final void Function(String code, int decalage) surDeplacer;

  /// « Choisir comme favorite ».
  final ValueChanged<String> surChoisirFavorite;

  /// Nombre maximal de langues (bouton d'ajout désactivé au-delà), ou
  /// `null` sans limite.
  final int? nombreMaximal;

  /// `true` pendant un enregistrement : boutons désactivés.
  final bool estOccupe;

  Future<void> _ajouter(BuildContext context) async {
    final code = await choisirLangue(context, exclues: langues.toSet());
    if (code != null) surAjouter(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximal = nombreMaximal;
    final peutAjouter = maximal == null || langues.length < maximal;
    // Il faut toujours au moins une langue : le retrait de la dernière est
    // désactivé plutôt que refusé après coup.
    final peutRetirer = langues.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < langues.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: index == 0
                ? Icon(
                    Icons.star,
                    color: theme.colorScheme.primary,
                    semanticLabel: Textes.favorite,
                  )
                : IconButton(
                    tooltip: Textes.choisirCommeFavorite,
                    icon: const Icon(Icons.star_border),
                    onPressed: estOccupe
                        ? null
                        : () => surChoisirFavorite(langues[index]),
                  ),
            title: Text(Textes.nomLangue(langues[index])),
            subtitle: Text(
              index == 0
                  ? '${langues[index]} · ${Textes.favorite}'
                  : langues[index],
            ),
            // Flèches plutôt qu'un glisser-déposer : utilisables au doigt
            // comme à la souris, et dans une page qui défile déjà.
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: Textes.monterLangue,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: estOccupe || index == 0
                      ? null
                      : () => surDeplacer(langues[index], -1),
                ),
                IconButton(
                  tooltip: Textes.descendreLangue,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: estOccupe || index == langues.length - 1
                      ? null
                      : () => surDeplacer(langues[index], 1),
                ),
                IconButton(
                  tooltip: Textes.retirerLangue,
                  icon: const Icon(Icons.close),
                  onPressed: estOccupe || !peutRetirer
                      ? null
                      : () => surRetirer(langues[index]),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: estOccupe || !peutAjouter
                ? null
                : () => _ajouter(context),
            icon: const Icon(Icons.add),
            label: const Text(Textes.ajouterLangue),
          ),
        ),
        if (!peutAjouter)
          Text(
            Textes.maximumLangues(maximal),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// Ouvre la liste des langues (noms en français, avec recherche) et renvoie
/// le code choisi, ou `null` si le client annule. Les langues [exclues]
/// (déjà choisies) ne sont pas proposées.
Future<String?> choisirLangue(
  BuildContext context, {
  Set<String> exclues = const <String>{},
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogueChoixLangue(exclues: exclues),
  );
}

/// Dialogue de choix d'une langue, avec un champ de recherche.
class _DialogueChoixLangue extends StatefulWidget {
  const _DialogueChoixLangue({required this.exclues});

  final Set<String> exclues;

  @override
  State<_DialogueChoixLangue> createState() => _EtatDialogueChoixLangue();
}

class _EtatDialogueChoixLangue extends State<_DialogueChoixLangue> {
  String _recherche = '';

  /// Recherche insensible à la casse et aux accents simples (« francais »
  /// trouve « Français »), sur le nom comme sur le code.
  static String _normaliser(String texte) {
    const avecAccents = 'àâäçéèêëîïôöùûüÿ';
    const sansAccents = 'aaaceeeeiioouuuy';
    final minuscules = texte.toLowerCase();
    final tampon = StringBuffer();
    for (final caractere in minuscules.split('')) {
      final index = avecAccents.indexOf(caractere);
      tampon.write(index < 0 ? caractere : sansAccents[index]);
    }
    return tampon.toString();
  }

  @override
  Widget build(BuildContext context) {
    final recherche = _normaliser(_recherche.trim());
    final proposees =
        Textes.nomsLangues.entries
            .where((entree) => !widget.exclues.contains(entree.key))
            .where(
              (entree) =>
                  recherche.isEmpty ||
                  _normaliser(entree.value).contains(recherche) ||
                  entree.key.contains(recherche),
            )
            .toList()
          ..sort(
            (a, b) => _normaliser(a.value).compareTo(_normaliser(b.value)),
          );
    final hauteur = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      title: const Text(Textes.choisirUneLangue),
      content: ConstrainedBox(
        // Largeur plafonnée comme les formulaires ; hauteur en part de
        // l'écran : la liste défile au lieu de dépasser.
        constraints: BoxConstraints(
          maxWidth: largeurMaxFormulaire,
          maxHeight: hauteur * fractionHauteurDialogueListe,
        ),
        // Largeur explicite (ramenée au plafond ci-dessus) : AlertDialog
        // mesure la largeur « naturelle » de son contenu, ce qu'une liste
        // qui défile ne sait pas faire.
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: Textes.rechercherLangue,
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (valeur) => setState(() => _recherche = valeur),
              ),
              const SizedBox(height: espacementPetit),
              Flexible(
                child: proposees.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(espacementMoyen),
                        child: Text(Textes.aucuneLangueTrouvee),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: proposees.length,
                        itemBuilder: (context, index) {
                          final entree = proposees[index];
                          return ListTile(
                            title: Text(entree.value),
                            subtitle: Text(entree.key),
                            onTap: () => Navigator.of(context).pop(entree.key),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
      ],
    );
  }
}
