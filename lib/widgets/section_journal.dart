/// Section « Journal » des paramètres : dossier et fichiers du journal de
/// l'application, export pour les retours de test, journal détaillé.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_journal.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'section_pliable.dart';
import 'textes.dart';
import 'vues_etat.dart';

/// Section des paramètres consacrée au journal de l'application.
/// Absente si l'application n'a pas d'[EtatJournal] (tests).
class SectionJournal extends StatelessWidget {
  /// Crée la section.
  const SectionJournal({super.key});

  Future<void> _exporter(
    BuildContext context,
    EtatJournal etat,
    int jours,
  ) async {
    final resultat = await etat.exporter(jours: jours);
    if (!context.mounted) return;
    final chemin = resultat.donnee;
    if (chemin == null) {
      afficherResultat(context, resultat);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.journalExporte),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(Textes.explicationJournalExporte),
                const SizedBox(height: espacementPetit),
                // Sélectionnable : le client copie le chemin pour joindre le
                // fichier à ses retours.
                SelectableText(chemin),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          // Même bouton que l'export des titres et le rapport d'erreur :
          // le dossier s'ouvre dans l'explorateur du système.
          TextButton(
            onPressed: () => ouvrirLienExterne(
              contexteDialogue,
              Uri.directory(etat.dossierExports).toString(),
            ),
            child: const Text(Textes.ouvrirDossier),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(),
            child: const Text(Textes.fermer),
          ),
        ],
      ),
    );
  }

  Future<void> _basculerDetaille(
    BuildContext context,
    EtatJournal etat,
    bool actif,
  ) async {
    final resultat = await etat.modifierJournalDetaille(actif);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.journalDetailleModifie(actif),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatJournal?>();
    if (etat == null) return const SizedBox.shrink();
    return SectionPliable(
      identifiant: 'parametres.journal',
      titre: Textes.sectionJournal,
      icone: Icons.receipt_long_outlined,
      // Section repliée : un journal détaillé resté actif se voit tout de
      // suite (il grossit vite).
      resume: Textes.resumeJournal(detaille: etat.journalDetaille),
      enfants: <Widget>[_contenu(context, etat)],
    );
  }

  Widget _contenu(BuildContext context, EtatJournal etat) {
    final erreur = etat.erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    }
    if (!etat.estCharge) {
      return const Padding(
        padding: EdgeInsets.all(espacementGrand),
        child: VueChargement(),
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(Textes.explicationJournal, style: theme.textTheme.bodyMedium),
        const SizedBox(height: espacementMoyen),
        Text(Textes.dossierJournaux, style: theme.textTheme.titleSmall),
        // Sélectionnable : le client peut copier le chemin même si
        // « Ouvrir le dossier » n'est pas possible (Android).
        SelectableText(etat.dossierJournaux, style: theme.textTheme.bodySmall),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => ouvrirLienExterne(
              context,
              Uri.directory(etat.dossierJournaux).toString(),
            ),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text(Textes.ouvrirDossier),
          ),
        ),
        const SizedBox(height: espacementPetit),
        _ListeFichiers(etat: etat),
        const SizedBox(height: espacementMoyen),
        // Les deux exports côte à côte, l'un sous l'autre sur écran étroit.
        Wrap(
          spacing: espacementPetit,
          runSpacing: espacementPetit,
          children: <Widget>[
            _BoutonExport(
              etat: etat,
              jours: EtatJournal.joursExportJour,
              libelle: Textes.exporterJournalDuJour,
              estPrincipal: true,
              surAppui: () =>
                  _exporter(context, etat, EtatJournal.joursExportJour),
            ),
            _BoutonExport(
              etat: etat,
              jours: EtatJournal.joursExportSemaine,
              libelle: Textes.exporterJournalSemaine,
              estPrincipal: false,
              surAppui: () =>
                  _exporter(context, etat, EtatJournal.joursExportSemaine),
            ),
          ],
        ),
        const Divider(height: espacementGrand),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.manage_search_outlined),
          title: const Text(Textes.journalDetaille),
          subtitle: const Text(Textes.explicationJournalDetaille),
          value: etat.journalDetaille,
          onChanged: etat.estEnEnregistrementReglage
              ? null
              : (actif) => _basculerDetaille(context, etat, actif),
        ),
      ],
    );
  }
}

/// Liste des fichiers de journal (jour, partie, taille), le plus récent en
/// haut, avec un bouton pour la relire.
class _ListeFichiers extends StatelessWidget {
  const _ListeFichiers({required this.etat});

  final EtatJournal etat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                Textes.fichiersJournal,
                style: theme.textTheme.titleSmall,
              ),
            ),
            // Le fichier du jour grossit pendant que la section est
            // ouverte : le client peut relire les tailles.
            IconButton(
              tooltip: Textes.actualiser,
              icon: const Icon(Icons.refresh),
              onPressed: etat.estEnChargement ? null : etat.charger,
            ),
          ],
        ),
        if (etat.fichiers.isEmpty)
          Text(Textes.aucunFichierJournal, style: theme.textTheme.bodySmall)
        else
          for (final ligne in etat.fichiers)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(
                Textes.ligneFichierJournal(
                  ligne.jour,
                  ligne.numero,
                  ligne.taille,
                ),
              ),
              subtitle: Text(ligne.nom),
            ),
      ],
    );
  }
}

/// Bouton d'export du journal ; l'indicateur de progression s'affiche sur
/// le bouton de l'export en cours seulement.
class _BoutonExport extends StatelessWidget {
  const _BoutonExport({
    required this.etat,
    required this.jours,
    required this.libelle,
    required this.estPrincipal,
    required this.surAppui,
  });

  final EtatJournal etat;
  final int jours;
  final String libelle;
  final bool estPrincipal;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final icone = etat.joursEnExport == jours
        ? SizedBox.square(
            dimension: IconTheme.of(context).size,
            child: const CircularProgressIndicator(
              strokeWidth: epaisseurIndicateurBouton,
            ),
          )
        : const Icon(Icons.ios_share_outlined);
    final surAppuiActif = etat.estEnExport ? null : surAppui;
    // Le journal du jour est le plus demandé : bouton plein ; la semaine,
    // bouton en contour.
    return estPrincipal
        ? FilledButton.tonalIcon(
            onPressed: surAppuiActif,
            icon: icone,
            label: Text(libelle),
          )
        : OutlinedButton.icon(
            onPressed: surAppuiActif,
            icon: icone,
            label: Text(libelle),
          );
  }
}
