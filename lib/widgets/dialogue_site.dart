/// Dialogue « Modifier le site » (nom, type, activation, langues, réglages
/// avancés, suppression), commun à l'onglet Sources et aux Paramètres
/// (tâche X5).
library;

import 'package:material_ui/material_ui.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_sources.dart';
import '../modeles/source.dart';
import 'champs_reglages_generiques.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'textes.dart';

/// Valeurs saisies dans le dialogue d'un site.
class SaisieSite {
  /// Crée la saisie.
  const SaisieSite({
    required this.nom,
    required this.langues,
    required this.estActive,
    required this.typeSource,
    this.reglagesGeneriques,
  });

  /// Nom du site.
  final String nom;

  /// Langues propres au site (« fr,en »), vide pour le réglage général.
  final String langues;

  /// `true` si le site est actif.
  final bool estActive;

  /// Type choisi (le type actuel si le client ne l'a pas changé).
  final TypeSource typeSource;

  /// Réglages avancés saisis (site générique seulement), sinon `null`.
  final Map<String, String>? reglagesGeneriques;
}

/// Issue du dialogue : une modification à enregistrer, ou une demande de
/// suppression (confirmée ensuite).
class IssueDialogueSite {
  /// Modification à enregistrer.
  const IssueDialogueSite.modification(SaisieSite this.saisie)
    : estSuppression = false;

  /// Demande de suppression.
  const IssueDialogueSite.suppression() : saisie = null, estSuppression = true;

  /// Valeurs saisies, ou `null` pour une suppression.
  final SaisieSite? saisie;

  /// `true` si le client a demandé la suppression du site.
  final bool estSuppression;
}

/// Ouvre le dialogue de modification de [source], puis enregistre la
/// modification ou supprime le site (après confirmation), et affiche le
/// résultat.
Future<void> modifierSiteAvecDialogue(
  BuildContext context,
  EtatSources etat,
  Source source,
) async {
  final issue = await showDialog<IssueDialogueSite>(
    context: context,
    builder: (_) => DialogueSite(source: source),
  );
  if (issue == null || !context.mounted) return;
  if (issue.estSuppression) {
    await supprimerSiteAvecConfirmation(context, etat, source);
    return;
  }
  final saisie = issue.saisie!;
  final resultat = await etat.modifierSource(
    source,
    nom: saisie.nom,
    langues: saisie.langues,
    estActive: saisie.estActive,
    typeSource: saisie.typeSource,
    reglagesGeneriques: saisie.reglagesGeneriques,
  );
  if (context.mounted) {
    afficherResultat(
      context,
      resultat,
      succes: Textes.siteModifie(resultat.donnee?.nom ?? saisie.nom),
    );
  }
}

/// Demande confirmation puis supprime [source]. Le refus du service (des
/// titres dépendent encore du site) est affiché tel quel.
Future<void> supprimerSiteAvecConfirmation(
  BuildContext context,
  EtatSources etat,
  Source source,
) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (contexteDialogue) => AlertDialog(
      title: const Text(Textes.supprimerSite),
      content: Text(Textes.confirmationSuppressionSite(source.nom)),
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
  final ResultatAction<bool> resultat = await etat.supprimerSource(source);
  if (context.mounted) {
    afficherResultat(
      context,
      resultat,
      succes: Textes.siteSupprime(source.nom),
    );
  }
}

/// Dialogue de modification d'un site : nom, type (les types qui ne
/// conviennent pas au site sont grisés), activation, langues propres,
/// réglages avancés d'un site générique, et bouton « Supprimer ».
class DialogueSite extends StatefulWidget {
  /// Crée le dialogue pour [source].
  const DialogueSite({super.key, required this.source});

  /// Site modifié.
  final Source source;

  @override
  State<DialogueSite> createState() => _EtatDialogueSite();
}

class _EtatDialogueSite extends State<DialogueSite> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  late final TextEditingController _nom = TextEditingController(
    text: widget.source.nom,
  );
  late final TextEditingController _langues = TextEditingController(
    text: widget.source.langueParDefaut,
  );
  late bool _estActive = widget.source.estActive;
  late TypeSource _type = widget.source.typeSource;

  /// `true` pour un site générique (type choisi) : seul type qui lit les
  /// réglages avancés.
  bool get _estGenerique => _type == TypeSource.generique;

  /// Réglages enregistrés du site, par clé (préremplissage) ; vides si le
  /// site n'est pas générique aujourd'hui.
  late final Map<String, String> _reglagesInitiaux =
      widget.source.typeSource == TypeSource.generique
      ? EtatSources.reglagesGeneriquesDepuisJson(
          widget.source.configurationSelecteurs,
        )
      : const <String, String>{};

  /// Un champ par réglage avancé, prérempli.
  late final Map<String, TextEditingController> _reglages =
      <String, TextEditingController>{
        for (final cle in EtatSources.clesReglagesGeneriques)
          cle: TextEditingController(text: _reglagesInitiaux[cle] ?? ''),
      };

  @override
  void dispose() {
    _nom.dispose();
    _langues.dispose();
    for (final controleur in _reglages.values) {
      controleur.dispose();
    }
    super.dispose();
  }

  /// Codes séparés par des virgules, variantes régionales acceptées
  /// (« fr,pt-br ») : même règle que le service.
  String? _validerLangues(String? valeur) =>
      EtatSources.languesValides(valeur ?? '') ? null : Textes.erreurLangues;

  /// `true` si [type] peut être choisi pour ce site : le type actuel
  /// toujours (un ancien site reste modifiable), sinon selon le service.
  bool _typePossible(TypeSource type) =>
      type == widget.source.typeSource ||
      EtatSources.erreurTypeSite(widget.source.urlBase, type) == null;

  void _valider() {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      IssueDialogueSite.modification(
        SaisieSite(
          nom: _nom.text,
          langues: _langues.text,
          estActive: _estActive,
          typeSource: _type,
          reglagesGeneriques: _estGenerique
              ? <String, String>{
                  for (final entree in _reglages.entries)
                    entree.key: entree.value.text,
                }
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    // L'aide n'apparaît que si des types sont grisés : le client comprend
    // pourquoi il ne peut pas les choisir.
    final refusAutres = TypeSource.values
        .where((type) => type != _type && !_typePossible(type))
        .isNotEmpty;
    return AlertDialog(
      title: const Text(Textes.modifierSite),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: Form(
          key: _formulaire,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(widget.source.urlBase),
                const SizedBox(height: espacementMoyen),
                TextFormField(
                  controller: _nom,
                  decoration: const InputDecoration(
                    labelText: Textes.champNomSiteObligatoire,
                    border: OutlineInputBorder(),
                  ),
                  validator: (valeur) => (valeur ?? '').trim().isEmpty
                      ? Textes.erreurNomVide
                      : null,
                ),
                const SizedBox(height: espacementMoyen),
                // Type modifiable (X5) : les types incohérents avec le site
                // restent visibles mais grisés, pour que le client voie
                // qu'ils existent sans pouvoir les choisir.
                DropdownButtonFormField<TypeSource>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: Textes.champTypeSite,
                    helperText: refusAutres
                        ? Textes.aideTypeSiteModification
                        : null,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<TypeSource>>[
                    for (final type in TypeSource.values)
                      DropdownMenuItem<TypeSource>(
                        value: type,
                        enabled: _typePossible(type),
                        child: Text(
                          Textes.libelleTypeSource(type),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (type) {
                    if (type != null) setState(() => _type = type);
                  },
                ),
                if (EtatSources.changementTypeEffaceReglages(
                  widget.source,
                  _type,
                )) ...<Widget>[
                  const SizedBox(height: espacementPetit),
                  Text(
                    Textes.avertissementEffacementReglages,
                    style: TextStyle(color: couleurs.error),
                  ),
                ],
                const SizedBox(height: espacementMoyen),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(Textes.siteActif),
                  subtitle: const Text(Textes.aideSiteActif),
                  value: _estActive,
                  onChanged: (valeur) => setState(() => _estActive = valeur),
                ),
                // Réglage avancé, replié : « Mes langues » (Paramètres) et
                // les langues de chaque titre suffisent dans presque tous
                // les cas. Déplié d'office si le site a déjà des langues
                // propres, pour que le client voie ce qui s'applique.
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: widget.source.langueParDefaut.isNotEmpty,
                  title: const Text(Textes.reglageAvanceLangues),
                  childrenPadding: const EdgeInsets.only(
                    bottom: espacementPetit,
                  ),
                  children: <Widget>[
                    TextFormField(
                      controller: _langues,
                      decoration: const InputDecoration(
                        labelText: Textes.champLangues,
                        helperText: Textes.aideLangues,
                        helperMaxLines: 5,
                        border: OutlineInputBorder(),
                      ),
                      validator: _validerLangues,
                    ),
                  ],
                ),
                // Sélecteurs CSS : seulement pour le type générique (les
                // autres types ne les lisent pas). Dépliés d'office si le
                // site en a déjà, comme les langues ci-dessus.
                if (_estGenerique)
                  ChampsReglagesGeneriques(
                    controleurs: _reglages,
                    valeursInitiales: _reglagesInitiaux,
                    estDeplieeAuDepart: _reglagesInitiaux.isNotEmpty,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        // Suppression en premier, en rouge, loin de « Enregistrer » ; elle
        // est de plus confirmée par une seconde question.
        TextButton(
          style: TextButton.styleFrom(foregroundColor: couleurs.error),
          onPressed: () =>
              Navigator.of(context).pop(const IssueDialogueSite.suppression()),
          child: const Text(Textes.supprimer),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: _valider,
          child: const Text(Textes.enregistrer),
        ),
      ],
    );
  }
}
