/// Écran Paramètres : règles de téléchargement, sites et « À propos ».
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_mises_a_jour.dart';
import '../etat/etat_parametres.dart';
import '../etat/etat_sources.dart';
import '../modeles/source.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/editeur_langues.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';

/// Réglages de l'application, en trois sections : « Téléchargements »,
/// « Sites » et « À propos ».
class EcranParametres extends StatelessWidget {
  /// Crée l'écran.
  const EcranParametres({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(Textes.ongletParametres)),
      // Colonne centrée de largeur plafonnée : sur grand écran, des réglages
      // étalés sur toute la largeur seraient difficiles à suivre.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: ListView(
            padding: const EdgeInsets.all(espacementMoyen),
            children: const <Widget>[
              // Les langues d'abord : c'est le réglage qui décide de ce qui
              // est téléchargé, avant les limites de nombre.
              _SectionLangues(),
              SizedBox(height: espacementGrand),
              _SectionMisesAJour(),
              SizedBox(height: espacementGrand),
              _SectionTelechargements(),
              SizedBox(height: espacementGrand),
              _SectionSites(),
              SizedBox(height: espacementGrand),
              _SectionAPropos(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Titre d'une section.
class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: espacementPetit),
      child: Text(texte, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

// ---------------------------------------------------------------- Mes langues

/// Langues de lecture du client (réglage général) : ajout depuis une liste
/// en français, retrait, ordre, favorite. Chaque changement est enregistré
/// aussitôt.
class _SectionLangues extends StatelessWidget {
  const _SectionLangues();

  Future<void> _executer(
    BuildContext context,
    Future<ResultatAction<bool>> action,
  ) async {
    final resultat = await action;
    if (context.mounted) {
      afficherResultat(context, resultat, succes: Textes.languesEnregistrees);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatParametres>();
    if (!etat.estCharge) {
      // Chargement et erreur sont affichés par la section Téléchargements
      // (même lecture des réglages).
      return const _TitreSection(Textes.sectionLangues);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitreSection(Textes.sectionLangues),
        Text(
          Textes.explicationMesLangues,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: espacementPetit),
        EditeurLangues(
          langues: etat.langues,
          nombreMaximal: EtatParametres.nombreMaximalLangues,
          estOccupe: etat.estEnEnregistrementLangues,
          surAjouter: (code) => _executer(context, etat.ajouterLangue(code)),
          surRetirer: (code) => _executer(context, etat.retirerLangue(code)),
          surDeplacer: (code, decalage) =>
              _executer(context, etat.deplacerLangue(code, decalage)),
          surChoisirFavorite: (code) =>
              _executer(context, etat.choisirFavorite(code)),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- Mises à jour

/// Nombre de recherches de nouveaux chapitres par jour (1 à 24), horaires
/// correspondants et date de la dernière recherche.
class _SectionMisesAJour extends StatelessWidget {
  const _SectionMisesAJour();

  Future<void> _modifier(
    BuildContext context,
    EtatParametres etat,
    int nombre,
  ) async {
    // Lu avant l'attente : le contexte peut ne plus être monté ensuite.
    final misesAJour = context.read<EtatMisesAJour>();
    final resultat = await etat.modifierVerificationsParJour(nombre);
    if (resultat.estReussi) {
      // Minuteur (ordinateur) ou tâche de fond (Android) recalés sur les
      // nouveaux horaires.
      await misesAJour.replanifier();
    }
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.planificationEnregistree,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatParametres>();
    final misesAJour = context.watch<EtatMisesAJour>();
    final theme = Theme.of(context);
    final nombre = etat.verificationsParJour;
    final occupe = etat.estEnEnregistrementPlanification;
    // La date en base est relue au chargement ; une recherche faite depuis
    // par l'application est plus récente : on garde la plus récente des deux.
    final enBase = etat.derniereVerification;
    final enMemoire = misesAJour.dateDerniereVerification;
    final derniere = enBase == null
        ? enMemoire
        : (enMemoire != null && enMemoire.isAfter(enBase) ? enMemoire : enBase);
    final prochaine = misesAJour.prochaineEcheance;
    if (!etat.estCharge) {
      // Chargement et erreur sont affichés par la section Téléchargements
      // (même lecture des réglages).
      return const _TitreSection(Textes.sectionMisesAJour);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitreSection(Textes.sectionMisesAJour),
        Text(
          Textes.explicationVerificationsParJour,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: espacementMoyen),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                Textes.verificationsParJour,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: Textes.diminuer,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: occupe || nombre <= EtatParametres.minimumParJour
                  ? null
                  : () => _modifier(context, etat, nombre - 1),
            ),
            Text('$nombre', style: theme.textTheme.titleMedium),
            IconButton(
              tooltip: Textes.augmenter,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: occupe || nombre >= EtatParametres.maximumParJour
                  ? null
                  : () => _modifier(context, etat, nombre + 1),
            ),
          ],
        ),
        Text(
          Textes.horairesVerifications(
            etat.planification.horairesDuJour(),
            DateTime.now().toUtc(),
          ),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: espacementPetit),
        Text(
          Textes.derniereRecherche(derniere),
          style: theme.textTheme.bodySmall,
        ),
        if (prochaine != null)
          Text(
            Textes.prochaineRecherche(prochaine),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

// ------------------------------------------------------------ Téléchargements

/// Les quatre limites des règles de conservation, avec + / −.
class _SectionTelechargements extends StatelessWidget {
  const _SectionTelechargements();

  Future<void> _enregistrer(BuildContext context, EtatParametres etat) async {
    final resultat = await etat.enregistrer();
    if (context.mounted) {
      afficherResultat(context, resultat, succes: Textes.reglagesEnregistres);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatParametres>();
    final theme = Theme.of(context);
    final erreur = etat.erreur;
    Widget contenu;
    if (erreur != null) {
      contenu = VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    } else if (!etat.estCharge) {
      contenu = const Padding(
        padding: EdgeInsets.all(espacementGrand),
        child: VueChargement(),
      );
    } else {
      contenu = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            Textes.introReglesTelechargement,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: espacementMoyen),
          for (final limite in LimiteTelechargement.values)
            _LigneLimite(etat: etat, limite: limite),
          const SizedBox(height: espacementPetit),
          // Boutons qui passent à la ligne sur un écran étroit.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: espacementPetit,
            runSpacing: espacementPetit,
            children: <Widget>[
              TextButton(
                onPressed: etat.estParDefaut ? null : etat.remettreParDefaut,
                child: const Text(Textes.valeursParDefaut),
              ),
              TextButton(
                onPressed: etat.estModifie ? etat.annulerModifications : null,
                child: const Text(Textes.annulerModifications),
              ),
              FilledButton.icon(
                onPressed: etat.estModifie && !etat.estEnEnregistrement
                    ? () => _enregistrer(context, etat)
                    : null,
                icon: etat.estEnEnregistrement
                    ? SizedBox.square(
                        dimension: IconTheme.of(context).size,
                        child: const CircularProgressIndicator(
                          strokeWidth: epaisseurIndicateurBouton,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text(Textes.enregistrer),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitreSection(Textes.sectionTelechargements),
        contenu,
      ],
    );
  }
}

/// Une limite : libellé, explication avec la valeur, boutons + / −.
class _LigneLimite extends StatelessWidget {
  const _LigneLimite({required this.etat, required this.limite});

  final EtatParametres etat;
  final LimiteTelechargement limite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valeur = etat.valeur(limite);
    return Padding(
      padding: const EdgeInsets.only(bottom: espacementMoyen),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Textes.libelleLimite(limite),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  Textes.explicationLimite(limite, valeur),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: Textes.diminuer,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: valeur <= 0 ? null : () => etat.ajouter(limite, -1),
          ),
          Text('$valeur', style: theme.textTheme.titleMedium),
          IconButton(
            tooltip: Textes.augmenter,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: valeur >= EtatParametres.limiteMaximale
                ? null
                : () => etat.ajouter(limite, 1),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- Sites

/// Sites configurés : modification (nom, langues, activation) et
/// suppression.
class _SectionSites extends StatelessWidget {
  const _SectionSites();

  Future<void> _modifier(
    BuildContext context,
    EtatSources etat,
    Source source,
  ) async {
    final saisie = await showDialog<_SaisieSite>(
      context: context,
      builder: (_) => _DialogueSite(source: source),
    );
    if (saisie == null || !context.mounted) return;
    final resultat = await etat.modifierSource(
      source,
      nom: saisie.nom,
      langues: saisie.langues,
      estActive: saisie.estActive,
    );
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.siteModifie(resultat.donnee?.nom ?? saisie.nom),
      );
    }
  }

  Future<void> _supprimer(
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
    final resultat = await etat.supprimerSource(source);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.siteSupprime(source.nom),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatSources>();
    final erreur = etat.erreur;
    Widget contenu;
    if (erreur != null) {
      contenu = VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    } else if (!etat.estCharge) {
      contenu = const Padding(
        padding: EdgeInsets.all(espacementGrand),
        child: VueChargement(),
      );
    } else if (etat.sources.isEmpty) {
      contenu = const Text(Textes.aucunSiteParametres);
    } else {
      contenu = Column(
        children: <Widget>[
          for (final source in etat.sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                source.estActive
                    ? source.nom
                    : Textes.nomSourceInactive(source.nom),
              ),
              subtitle: Text(
                '${source.urlBase}\n'
                '${Textes.languesSite(source.langueParDefaut)}',
              ),
              isThreeLine: true,
              onTap: () => _modifier(context, etat, source),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: Textes.modifierSite,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _modifier(context, etat, source),
                  ),
                  IconButton(
                    tooltip: Textes.supprimerSite,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _supprimer(context, etat, source),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[const _TitreSection(Textes.sectionSites), contenu],
    );
  }
}

/// Valeurs saisies dans le dialogue d'un site.
class _SaisieSite {
  const _SaisieSite({
    required this.nom,
    required this.langues,
    required this.estActive,
  });

  final String nom;
  final String langues;
  final bool estActive;
}

/// Dialogue de modification d'un site.
class _DialogueSite extends StatefulWidget {
  const _DialogueSite({required this.source});

  final Source source;

  @override
  State<_DialogueSite> createState() => _EtatDialogueSite();
}

class _EtatDialogueSite extends State<_DialogueSite> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  late final TextEditingController _nom = TextEditingController(
    text: widget.source.nom,
  );
  late final TextEditingController _langues = TextEditingController(
    text: widget.source.langueParDefaut,
  );
  late bool _estActive = widget.source.estActive;

  /// Codes de deux lettres séparés par des virgules (espaces tolérés).
  static final RegExp _formatLangues = RegExp(
    '^[a-z]{$longueurCodeLangue}(,[a-z]{$longueurCodeLangue})*\$',
  );

  @override
  void dispose() {
    _nom.dispose();
    _langues.dispose();
    super.dispose();
  }

  String? _validerLangues(String? valeur) {
    final langues = (valeur ?? '').replaceAll(' ', '').toLowerCase();
    if (langues.isEmpty || _formatLangues.hasMatch(langues)) return null;
    return Textes.erreurLangues;
  }

  void _valider() {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _SaisieSite(
        nom: _nom.text,
        langues: _langues.text,
        estActive: _estActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        FilledButton(
          onPressed: _valider,
          child: const Text(Textes.enregistrer),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- À propos

/// Nom, version et crédits.
class _SectionAPropos extends StatelessWidget {
  const _SectionAPropos();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitreSection(Textes.sectionAPropos),
        Text(Textes.titreApplication, style: theme.textTheme.titleMedium),
        Text(Textes.versionComplete(versionApplication)),
        const SizedBox(height: espacementPetit),
        const Text(Textes.descriptionApplication),
        const SizedBox(height: espacementPetit),
        // Crédit exigé par les règles d'usage de MangaDex (PLAYBOOK.md
        // section 6).
        Text(Textes.creditMangaDexComplet, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
