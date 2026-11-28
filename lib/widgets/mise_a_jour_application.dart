/// Mise à jour de l'application (version 0.4.0) : bandeau de l'accueil,
/// dialogue des notes de version et section des Paramètres.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_mise_a_jour_application.dart';
import 'bandeaux_dossier_chapitres.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'section_pliable.dart';
import 'textes.dart';
import 'vues_etat.dart';

/// « Mettre à jour » : confirmation (sous Windows, l'application va se
/// fermer), téléchargement suivi dans le bandeau, puis lancement de
/// l'installateur ; hors Windows, ouverture de la page de la version.
Future<void> lancerMiseAJour(
  BuildContext context,
  EtatMiseAJourApplication etat,
) async {
  final nouvelle = etat.nouvelleVersion;
  if (nouvelle == null) return;
  if (etat.installationAutomatiquePossible) {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: Text(
          Textes.titreConfirmationMiseAJour('${nouvelle.release.version}'),
        ),
        content: const Text(Textes.confirmationMiseAJour),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.mettreAJour),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
  }
  final resultat = await etat.mettreAJour();
  if (!context.mounted) return;
  final page = resultat.urlPage;
  final erreur = resultat.erreur;
  if (page != null) {
    await ouvrirLienExterne(context, page.toString());
  } else if (erreur != null) {
    afficherMessage(context, Textes.messageErreur(erreur), estErreur: true);
  }
}

/// Dialogue des notes de version de [nouvelle] : texte sélectionnable, lien
/// vers la page de la version et, si l'installateur est joint, bouton
/// « Mettre à jour ».
Future<void> afficherNotesVersion(
  BuildContext context,
  EtatMiseAJourApplication etat,
  NouvelleVersionDisponible nouvelle,
) async {
  final release = nouvelle.release;
  final notes = release.notes.trim();
  final mettreAJour = await showDialog<bool>(
    context: context,
    builder: (contexteDialogue) => AlertDialog(
      title: Text(Textes.titreNotesDeVersion('${release.version}')),
      // Largeur bornée : des notes longues restent lisibles sur grand écran ;
      // elles défilent si elles dépassent la hauteur.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (nouvelle.estIgnoree) ...<Widget>[
                const Text(Textes.versionIgnoreeMention),
                const SizedBox(height: espacementPetit),
              ],
              if (!nouvelle.estTelechargeable) ...<Widget>[
                const Text(Textes.versionSansInstallateur),
                const SizedBox(height: espacementPetit),
              ],
              // Texte sélectionnable : le client peut copier une ligne des
              // notes (Markdown brut, affiché tel quel).
              SelectableText(
                notes.isEmpty ? Textes.aucuneNoteDeVersion : notes,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => ouvrirLienExterne(contexteDialogue, release.urlPage),
          child: const Text(Textes.ouvrirPageVersion),
        ),
        TextButton(
          onPressed: () => Navigator.of(contexteDialogue).pop(false),
          child: const Text(Textes.fermer),
        ),
        if (nouvelle.estTelechargeable)
          FilledButton(
            onPressed: etat.estEnTelechargement
                ? null
                : () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.mettreAJour),
          ),
      ],
    ),
  );
  if (mettreAJour == true && context.mounted) {
    await lancerMiseAJour(context, etat);
  }
}

/// Zone qui affiche, au-dessus de [child], le bandeau « Version X.Y.Z
/// disponible » et la progression du téléchargement.
///
/// Sans [EtatMiseAJourApplication] (tests), [child] est affiché seul.
class ZoneBandeauMiseAJour extends StatelessWidget {
  /// Crée la zone autour de [child].
  const ZoneBandeauMiseAJour({super.key, required this.child});

  /// Contenu affiché sous le bandeau.
  final Widget child;

  Future<void> _ignorer(
    BuildContext context,
    EtatMiseAJourApplication etat,
    String version,
  ) async {
    final resultat = await etat.ignorerVersion();
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.versionIgnoree(version),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatMiseAJourApplication?>();
    final nouvelle = etat?.nouvelleVersion;
    final visible = etat != null && nouvelle != null && etat.bandeauVisible;
    // Même structure avec ou sans bandeau (Column > Expanded > MediaQuery),
    // comme les bandeaux du dossier des chapitres : le contenu garde son
    // état quand le bandeau apparaît ou disparaît.
    return Column(
      children: <Widget>[
        if (visible)
          SafeArea(
            bottom: false,
            child: BandeauGlobal(
              icone: Icons.system_update_outlined,
              texte: Textes.versionDisponible('${nouvelle.release.version}'),
              // Simple proposition : teinte secondaire, pas d'alerte.
              estAlerte: false,
              action: etat.estEnTelechargement
                  // Pendant le téléchargement, la barre remplace les
                  // boutons, sur toute la largeur du bandeau.
                  ? SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: espacementPetit),
                          LinearProgressIndicator(value: etat.progression),
                          const SizedBox(height: espacementPetit),
                          Text(
                            Textes.telechargementMiseAJour(
                              '${nouvelle.release.version}',
                              etat.progression,
                            ),
                          ),
                        ],
                      ),
                    )
                  // Boutons qui passent à la ligne sur un écran étroit.
                  : Wrap(
                      alignment: WrapAlignment.end,
                      spacing: espacementPetit,
                      runSpacing: espacementPetit,
                      children: <Widget>[
                        TextButton(
                          onPressed: etat.masquerBandeau,
                          child: const Text(Textes.plusTard),
                        ),
                        TextButton(
                          onPressed: () => _ignorer(
                            context,
                            etat,
                            '${nouvelle.release.version}',
                          ),
                          child: const Text(Textes.ignorerCetteVersion),
                        ),
                        TextButton(
                          onPressed: () =>
                              afficherNotesVersion(context, etat, nouvelle),
                          child: const Text(Textes.notesDeVersion),
                        ),
                        FilledButton.tonal(
                          onPressed: () => lancerMiseAJour(context, etat),
                          child: const Text(Textes.mettreAJour),
                        ),
                      ],
                    ),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: visible,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Section « Mise à jour de l'application » des Paramètres : vérification
/// quotidienne, « Vérifier maintenant » et son résultat, version actuelle.
///
/// Absente sans [EtatMiseAJourApplication] (tests).
class SectionMiseAJourApplication extends StatelessWidget {
  /// Crée la section.
  const SectionMiseAJourApplication({super.key});

  Future<void> _verifier(
    BuildContext context,
    EtatMiseAJourApplication etat,
  ) async {
    final resultat = await etat.verifierMaintenant();
    if (!context.mounted) return;
    switch (resultat) {
      case NouvelleVersionDisponible():
        // Même dialogue que le bandeau : notes, page et « Mettre à jour ».
        await afficherNotesVersion(context, etat, resultat);
      case ApplicationAJour():
        afficherMessage(context, Textes.applicationAJour);
      case EchecVerificationMiseAJour():
        afficherMessage(context, resultat.message, estErreur: true);
      case VerificationNonFaite():
        break;
    }
  }

  Future<void> _modifier(
    BuildContext context,
    EtatMiseAJourApplication etat,
    bool active,
  ) async {
    final resultat = await etat.modifierVerificationActivee(active);
    // Une réussite se voit sur l'interrupteur : seule une erreur est
    // signalée.
    if (context.mounted) afficherResultat(context, resultat);
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatMiseAJourApplication?>();
    if (etat == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SectionPliable(
      identifiant: 'parametres.miseAJourApplication',
      titre: Textes.sectionMiseAJourApplication,
      icone: Icons.system_update_outlined,
      resume: Textes.resumeMiseAJourApplication(
        versionApplication,
        etat.verificationActivee,
      ),
      enfants: <Widget>[
        if (!etat.estCharge)
          const Padding(
            padding: EdgeInsets.all(espacementGrand),
            child: VueChargement(),
          )
        else ...<Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(Textes.verifierChaqueJour),
            subtitle: const Text(Textes.explicationVerificationQuotidienne),
            value: etat.verificationActivee,
            onChanged: (active) => _modifier(context, etat, active),
          ),
          const SizedBox(height: espacementPetit),
          Text(Textes.versionComplete(versionApplication)),
          Text(
            Textes.derniereVerificationApplication(
              etat.derniereVerification,
              DateTime.now(),
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: espacementPetit),
          _ResultatVerification(etat: etat),
          const SizedBox(height: espacementPetit),
          // Bouton aligné à droite, comme les actions des autres sections.
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: etat.estEnVerification || etat.estEnTelechargement
                  ? null
                  : () => _verifier(context, etat),
              icon: etat.estEnVerification
                  ? SizedBox.square(
                      dimension: IconTheme.of(context).size,
                      child: const CircularProgressIndicator(
                        strokeWidth: epaisseurIndicateurBouton,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: const Text(Textes.verifierMaintenant),
            ),
          ),
        ],
      ],
    );
  }
}

/// Résultat de la dernière vérification, affiché sous la date.
class _ResultatVerification extends StatelessWidget {
  const _ResultatVerification({required this.etat});

  final EtatMiseAJourApplication etat;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final resultat = etat.dernierResultat;
    switch (resultat) {
      case null:
      case VerificationNonFaite():
        return const SizedBox.shrink();
      case ApplicationAJour():
        return const Text(Textes.applicationAJour);
      case NouvelleVersionDisponible():
        // Texte et lien vers les notes sur une ou deux lignes selon la
        // largeur.
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: espacementPetit,
          children: <Widget>[
            Text(Textes.nouvelleVersionTrouvee('${resultat.release.version}')),
            TextButton(
              onPressed: () => afficherNotesVersion(context, etat, resultat),
              child: const Text(Textes.notesDeVersion),
            ),
          ],
        );
      case EchecVerificationMiseAJour():
        final reprise = resultat.heureReprise;
        return Text(
          reprise == null
              ? resultat.message
              : '${resultat.message} ${Textes.heureRepriseGithub(reprise)}',
          style: TextStyle(color: couleurs.error),
        );
    }
  }
}
