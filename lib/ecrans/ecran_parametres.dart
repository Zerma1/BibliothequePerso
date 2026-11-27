/// Écran Paramètres : règles de téléchargement (jauges), sites, apparence,
/// journal et « À propos ».
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_export.dart';
import '../etat/etat_mises_a_jour.dart';
import '../etat/etat_parametres.dart';
import '../etat/etat_sources.dart';
import '../etat/etat_theme.dart';
import '../modeles/source.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/dialogue_import.dart';
import '../widgets/dialogue_site.dart';
import '../widgets/editeur_langues.dart';
import '../widgets/jauge_reglage.dart';
import '../widgets/messages.dart';
import '../widgets/section_categories_regroupees.dart';
import '../widgets/section_dossier_chapitres.dart';
import '../widgets/section_journal.dart';
import '../widgets/section_pliable.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';

/// Réglages de l'application : langues, mises à jour, téléchargements,
/// sites, sauvegarde et export, apparence, puis « À propos ».
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
            // Une carte repliable par thème (retour du client sur la
            // 0.2.0-test) : l'écran tient sur une page, le client déplie ce
            // qu'il veut régler. Seule la première section est dépliée au
            // départ ; le pliage est ensuite mémorisé pendant la session.
            children: const <Widget>[
              // Les langues d'abord : c'est le réglage qui décide de ce qui
              // est téléchargé, avant les limites de nombre.
              _SectionLangues(),
              _SectionMisesAJour(),
              _SectionTelechargements(),
              // Juste après les règles de téléchargement : il s'agit de
              // l'endroit où ces chapitres sont rangés.
              SectionDossierChapitres(),
              _SectionSites(),
              // Après les sites : les catégories viennent d'eux.
              SectionCategoriesRegroupees(),
              _SectionExport(),
              // Réglage rare, en bas avec les sections générales plutôt
              // qu'entre les réglages de lecture.
              _SectionApparence(),
              // Autre réglage général et rare, à côté de l'apparence ; absent
              // hors de Windows.
              _SectionDemarrage(),
              // Juste avant « À propos » : on vient y chercher le journal à
              // joindre à un retour de test, comme la version.
              SectionJournal(),
              _SectionAPropos(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenu d'une section qui lit les réglages ([EtatParametres]) :
/// erreur avec « Réessayer », chargement, puis [contenu] une fois les
/// réglages lus. Chaque section gère ces cas elle-même, puisqu'elle peut
/// être la seule dépliée.
class _ContenuReglages extends StatelessWidget {
  const _ContenuReglages({required this.etat, required this.contenu});

  final EtatParametres etat;
  final Widget Function() contenu;

  @override
  Widget build(BuildContext context) {
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
    return contenu();
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
    return SectionPliable(
      identifiant: 'parametres.langues',
      titre: Textes.sectionLangues,
      icone: Icons.translate,
      resume: etat.estCharge ? Textes.listeLangues(etat.langues) : null,
      // Première section, dépliée au départ : c'est le réglage le plus
      // structurant.
      estDeplieeAuDepart: true,
      enfants: <Widget>[
        _ContenuReglages(
          etat: etat,
          contenu: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                Textes.explicationMesLangues,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: espacementPetit),
              EditeurLangues(
                langues: etat.langues,
                nombreMaximal: EtatParametres.nombreMaximalLangues,
                estOccupe: etat.estEnEnregistrementLangues,
                surAjouter: (code) =>
                    _executer(context, etat.ajouterLangue(code)),
                surRetirer: (code) =>
                    _executer(context, etat.retirerLangue(code)),
                surDeplacer: (code, decalage) =>
                    _executer(context, etat.deplacerLangue(code, decalage)),
                surChoisirFavorite: (code) =>
                    _executer(context, etat.choisirFavorite(code)),
              ),
            ],
          ),
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
    return SectionPliable(
      identifiant: 'parametres.recherches',
      titre: Textes.sectionMisesAJour,
      icone: Icons.update,
      resume: etat.estCharge ? Textes.resumeRecherches(nombre) : null,
      enfants: <Widget>[
        _ContenuReglages(
          etat: etat,
          contenu: () =>
              _contenu(context, etat, nombre, occupe, derniere, prochaine),
        ),
      ],
    );
  }

  Widget _contenu(
    BuildContext context,
    EtatParametres etat,
    int nombre,
    bool occupe,
    DateTime? derniere,
    DateTime? prochaine,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          Textes.explicationVerificationsParJour,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: espacementMoyen),
        // Jauge de 1 à 24 : les horaires en dessous suivent le curseur
        // pendant le glissement ; l'enregistrement se fait au lâcher.
        JaugeReglage(
          key: const ValueKey<String>('jauge.recherchesParJour'),
          libelle: Textes.verificationsParJour,
          valeur: nombre,
          crans: cransReguliers(
            EtatParametres.minimumParJour,
            EtatParametres.maximumParJour,
          ),
          formater: (valeur) => '$valeur',
          estActive: !occupe,
          surApercu: etat.previsualiserVerificationsParJour,
          surChoix: (valeur) => _modifier(context, etat, valeur),
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
        const SizedBox(height: espacementMoyen),
        // Surveillance accrue des titres « En attente » (étape 6) : même
        // présentation que le nombre de recherches, juste en dessous. Le
        // maximum suit l'intervalle normal (24 recherches par jour : une
        // seule valeur, 1 h, et pas de curseur).
        JaugeReglage(
          key: const ValueKey<String>('jauge.heuresEnAttente'),
          libelle: Textes.heuresEnAttente,
          valeur: etat.heuresEnAttente,
          crans: cransReguliers(
            EtatParametres.minimumHeuresEnAttente,
            etat.maximumHeuresEnAttente,
          ),
          formater: Textes.valeurHeures,
          estActive: !etat.estEnEnregistrementEnAttente,
          surApercu: etat.previsualiserHeuresEnAttente,
          surChoix: (valeur) => _modifierEnAttente(context, etat, valeur),
          explication: Textes.explicationHeuresEnAttente,
        ),
      ],
    );
  }

  Future<void> _modifierEnAttente(
    BuildContext context,
    EtatParametres etat,
    int heures,
  ) async {
    final misesAJour = context.read<EtatMisesAJour>();
    final resultat = await etat.modifierHeuresEnAttente(heures);
    if (resultat.estReussi) {
      // Minuteur (ordinateur) ou tâche de fond (Android) recalés.
      await misesAJour.replanifier();
    }
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.surveillanceEnregistree,
      );
    }
  }
}

// ------------------------------------------------------------ Téléchargements

/// « Archive complète », téléchargements simultanés, durée de conservation
/// avant suppression, puis les quatre limites des règles de conservation
/// (jauges avec − / +).
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
    return SectionPliable(
      identifiant: 'parametres.telechargements',
      titre: Textes.sectionTelechargements,
      icone: Icons.download_for_offline_outlined,
      // Un brouillon non enregistré reste visible section repliée : le
      // client ne l'oublie pas.
      resume: etat.estCharge && etat.estModifie
          ? Textes.modificationsNonEnregistrees
          : Textes.resumeTelechargements,
      enfants: <Widget>[
        _ContenuReglages(
          etat: etat,
          contenu: () => _contenu(context, theme, etat),
        ),
      ],
    );
  }

  /// Interrupteur « Archive complète » : l'activation est confirmée (elle
  /// peut lancer des milliers de téléchargements), la désactivation non.
  Future<void> _basculerArchive(
    BuildContext context,
    EtatParametres etat,
    bool active,
  ) async {
    if (active) {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (contexteDialogue) => AlertDialog(
          title: const Text(Textes.activerArchiveComplete),
          content: const Text(Textes.confirmationArchiveComplete),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(false),
              child: const Text(Textes.annuler),
            ),
            FilledButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(true),
              child: const Text(Textes.activer),
            ),
          ],
        ),
      );
      if (confirme != true || !context.mounted) return;
    }
    final resultat = await etat.modifierArchiveComplete(active);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.archiveCompleteModifiee(resultat.donnee ?? active),
      );
    }
  }

  /// Enregistre la jauge au lâcher ; seule une erreur est signalée (un
  /// message à chaque réglage serait du bruit).
  Future<void> _modifierSimultanes(
    BuildContext context,
    EtatParametres etat,
    int nombre,
  ) async {
    final resultat = await etat.modifierTelechargementsSimultanes(nombre);
    if (context.mounted) afficherResultat(context, resultat);
  }

  /// Enregistre la durée de conservation ; le message rappelle la durée
  /// en toutes lettres (« 2 jours »), plus parlante que la jauge.
  Future<void> _modifierDelai(
    BuildContext context,
    EtatParametres etat,
    Duration delai,
  ) async {
    final resultat = await etat.modifierDelaiSuppression(delai);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.delaiSuppressionEnregistre(resultat.donnee ?? delai),
      );
    }
  }

  Widget _contenu(BuildContext context, ThemeData theme, EtatParametres etat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // En tête de section : quand elle est active, les limites qui
        // suivent ne s'appliquent plus (tout est gardé).
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.inventory_2_outlined),
          title: const Text(Textes.archiveComplete),
          subtitle: const Text(Textes.explicationArchiveComplete),
          value: etat.archiveComplete,
          onChanged: etat.estEnEnregistrementArchive
              ? null
              : (active) => _basculerArchive(context, etat, active),
        ),
        const Divider(),
        // Jauges enregistrées aussitôt (au lâcher) en haut, puis les limites
        // en brouillon avec leur bouton « Enregistrer » : les deux modes de
        // réglage ne se mélangent pas.
        // De 1 à 32, le client choisit d'un geste.
        JaugeReglage(
          key: const ValueKey<String>('jauge.simultanes'),
          libelle: Textes.libelleTelechargementsSimultanes,
          valeur: etat.telechargementsSimultanes,
          crans: cransReguliers(
            EtatParametres.minimumTelechargementsSimultanes,
            EtatParametres.maximumTelechargementsSimultanes,
          ),
          formater: (valeur) => '$valeur',
          estActive: !etat.estEnEnregistrementSimultanes,
          surApercu: etat.previsualiserTelechargementsSimultanes,
          surChoix: (valeur) => _modifierSimultanes(context, etat, valeur),
          explication: Textes.explicationTelechargementsSimultanes,
        ),
        const SizedBox(height: espacementMoyen),
        // Durée de conservation : crans proposés par le service (1 h à
        // 30 jours), en heures pour la jauge ; − / + passent d'un cran à
        // l'autre (une heure de plus sur 30 jours n'aurait pas de sens).
        JaugeReglage(
          key: const ValueKey<String>('jauge.delaiSuppression'),
          libelle: Textes.libelleDelaiSuppression,
          valeur: etat.delaiSuppression.inHours,
          crans: <int>[
            for (final delai in EtatParametres.delaisSuppressionProposes)
              delai.inHours,
          ],
          formater: (heures) => Textes.dureeCourte(Duration(hours: heures)),
          pasBoutons: null,
          estActive: !etat.estEnEnregistrementDelai,
          surApercu: (heures) =>
              etat.previsualiserDelaiSuppression(Duration(hours: heures)),
          surChoix: (heures) =>
              _modifierDelai(context, etat, Duration(hours: heures)),
          explication: Textes.explicationDelaiSuppression,
        ),
        const Divider(),
        // Durée enregistrée, pas l'aperçu de la jauge : ce texte décrit ce
        // que l'application fait réellement.
        Text(
          Textes.introReglesTelechargement(etat.delaiSuppressionEnregistre),
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
}

/// Une limite : libellé, valeur, jauge à crans (0 à 500, serrés au début)
/// avec − / + de 1 en 1, et explication avec la valeur. Tout reste dans le
/// brouillon jusqu'à « Enregistrer ».
class _LigneLimite extends StatelessWidget {
  const _LigneLimite({required this.etat, required this.limite});

  final EtatParametres etat;
  final LimiteTelechargement limite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: espacementMoyen),
      child: JaugeReglage(
        key: ValueKey<String>('jauge.limite.${limite.name}'),
        libelle: Textes.libelleLimite(limite),
        valeur: etat.valeur(limite),
        crans: cransLimite(
          EtatParametres.minimumLimite(limite),
          EtatParametres.limiteMaximale,
        ),
        formater: (valeur) => '$valeur',
        // Brouillon : glisser ou lâcher modifie la même valeur, rien n'est
        // écrit avant « Enregistrer ».
        surApercu: (valeur) => etat.modifier(limite, valeur),
        surChoix: (valeur) => etat.modifier(limite, valeur),
        explication: Textes.explicationLimite(limite, etat.valeur(limite)),
      ),
    );
  }
}

// ---------------------------------------------------------------------- Sites

/// Sites configurés : modification (nom, langues, activation) et
/// suppression.
class _SectionSites extends StatelessWidget {
  const _SectionSites();

  // Dialogue commun avec l'onglet Sources (tâche X5) : même formulaire,
  // type modifiable et suppression aux deux endroits.
  Future<void> _modifier(
    BuildContext context,
    EtatSources etat,
    Source source,
  ) => modifierSiteAvecDialogue(context, etat, source);

  Future<void> _supprimer(
    BuildContext context,
    EtatSources etat,
    Source source,
  ) => supprimerSiteAvecConfirmation(context, etat, source);

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
    return SectionPliable(
      identifiant: 'parametres.sites',
      titre: Textes.sectionSites,
      icone: Icons.public_outlined,
      resume: etat.estCharge && erreur == null
          ? Textes.nombreSites(etat.sources.length)
          : null,
      enfants: <Widget>[contenu],
    );
  }
}

// --------------------------------------------------------- Sauvegarde, export

/// Export des titres et des sites (JSON complet et Markdown lisible).
/// Absente si l'application n'a pas de service d'export (tests).
class _SectionExport extends StatelessWidget {
  const _SectionExport();

  Future<void> _exporter(BuildContext context, EtatExport etat) async {
    final resultat = await etat.exporter();
    if (!context.mounted) return;
    final export = resultat.donnee;
    if (export == null) {
      afficherResultat(context, resultat);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.exportEnregistre),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  Textes.resumeExport(export.nombreTitres, export.nombreSites),
                ),
                const SizedBox(height: espacementPetit),
                // Chemins sélectionnables : le client peut les copier pour
                // retrouver ou envoyer les fichiers.
                const Text(Textes.fichierJson),
                SelectableText(export.cheminJson),
                const SizedBox(height: espacementPetit),
                const Text(Textes.fichierMarkdown),
                SelectableText(export.cheminMarkdown),
              ],
            ),
          ),
        ),
        actions: <Widget>[
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

  @override
  Widget build(BuildContext context) {
    final EtatExport etat;
    try {
      etat = context.watch<EtatExport>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return SectionPliable(
      identifiant: 'parametres.export',
      titre: Textes.sectionSauvegardeExport,
      icone: Icons.save_alt_outlined,
      resume: Textes.resumeSauvegardeExport,
      enfants: <Widget>[
        const Text(Textes.explicationExport),
        const SizedBox(height: espacementPetit),
        // Les deux boutons côte à côte, et l'un sous l'autre sur un écran
        // étroit.
        Wrap(
          spacing: espacementPetit,
          runSpacing: espacementPetit,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: etat.estEnCours || etat.estEnImport
                  ? null
                  : () => _exporter(context, etat),
              icon: etat.estEnCours
                  ? SizedBox.square(
                      dimension: IconTheme.of(context).size,
                      child: const CircularProgressIndicator(
                        strokeWidth: epaisseurIndicateurBouton,
                      ),
                    )
                  : const Icon(Icons.save_alt_outlined),
              label: const Text(Textes.exporterTitresEtSites),
            ),
            if (etat.peutImporter)
              OutlinedButton.icon(
                onPressed: etat.estEnCours || etat.estEnImport
                    ? null
                    : () => ouvrirImport(context, etat),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text(Textes.importerUnExport),
              ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Apparence

/// Thème de l'interface : Système, Clair ou Sombre, appliqué aussitôt.
/// Absente si l'application ne fournit pas d'[EtatTheme] (tests).
class _SectionApparence extends StatelessWidget {
  const _SectionApparence();

  Future<void> _choisir(
    BuildContext context,
    EtatTheme etat,
    ModeTheme mode,
  ) async {
    final resultat = await etat.modifier(mode);
    // Seule une erreur est signalée : le changement de thème se voit.
    if (context.mounted) afficherResultat(context, resultat);
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatTheme?>();
    if (etat == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SectionPliable(
      identifiant: 'parametres.apparence',
      titre: Textes.sectionApparence,
      icone: Icons.palette_outlined,
      resume: Textes.resumeApparence(etat.mode),
      enfants: <Widget>[
        Text(Textes.libelleTheme, style: theme.textTheme.titleSmall),
        const SizedBox(height: espacementPetit),
        // Trois boutons côte à côte, sur toute la largeur : ils tiennent sur
        // un téléphone (libellés courts) et le choix actif se voit d'un coup
        // d'œil.
        SegmentedButton<ModeTheme>(
          segments: <ButtonSegment<ModeTheme>>[
            for (final mode in ModeTheme.values)
              ButtonSegment<ModeTheme>(
                value: mode,
                label: Text(Textes.nomModeTheme(mode)),
                icon: Icon(switch (mode) {
                  ModeTheme.systeme => Icons.brightness_auto_outlined,
                  ModeTheme.clair => Icons.light_mode_outlined,
                  ModeTheme.sombre => Icons.dark_mode_outlined,
                }),
              ),
          ],
          selected: <ModeTheme>{etat.mode},
          showSelectedIcon: false,
          onSelectionChanged: etat.estEnEnregistrement
              ? null
              : (choix) => _choisir(context, etat, choix.first),
        ),
        const SizedBox(height: espacementPetit),
        Text(Textes.explicationTheme, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// ------------------------------------------------------------------ Démarrage

/// « Démarrer avec Windows » : Désactivé, Pleine fenêtre ou Icône masquée,
/// enregistré et appliqué aussitôt. Absente hors de Windows.
class _SectionDemarrage extends StatelessWidget {
  const _SectionDemarrage();

  Future<void> _choisir(
    BuildContext context,
    EtatParametres etat,
    ModeDemarrage mode,
  ) async {
    final resultat = await etat.modifierModeDemarrage(mode);
    if (!context.mounted) return;
    if (resultat.donnee == false) {
      afficherMessage(
        context,
        Textes.demarrageRefuseParWindows,
        estErreur: true,
      );
      return;
    }
    // Une réussite se voit sur le bouton : seule une erreur est signalée.
    afficherResultat(context, resultat);
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatParametres>();
    if (!etat.demarrageAvecWindowsDisponible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SectionPliable(
      identifiant: 'parametres.demarrage',
      titre: Textes.sectionDemarrage,
      icone: Icons.power_settings_new_outlined,
      resume: etat.estCharge
          ? Textes.resumeDemarrage(etat.modeDemarrage)
          : null,
      enfants: <Widget>[
        _ContenuReglages(
          etat: etat,
          contenu: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                Textes.libelleDemarrerAvecWindows,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: espacementPetit),
              // Même présentation que le choix du thème : trois boutons
              // côte à côte, le choix actif visible d'un coup d'œil.
              SegmentedButton<ModeDemarrage>(
                segments: <ButtonSegment<ModeDemarrage>>[
                  for (final mode in ModeDemarrage.values)
                    ButtonSegment<ModeDemarrage>(
                      value: mode,
                      label: Text(Textes.nomModeDemarrage(mode)),
                      icon: Icon(switch (mode) {
                        ModeDemarrage.desactive => Icons.block_outlined,
                        ModeDemarrage.pleineFenetre =>
                          Icons.open_in_full_outlined,
                        ModeDemarrage.iconeMasquee =>
                          Icons.visibility_off_outlined,
                      }),
                    ),
                ],
                selected: <ModeDemarrage>{etat.modeDemarrage},
                showSelectedIcon: false,
                onSelectionChanged: etat.estEnEnregistrementDemarrage
                    ? null
                    : (choix) => _choisir(context, etat, choix.first),
              ),
              const SizedBox(height: espacementPetit),
              // L'explication suit le choix actif : le client sait ce qui se
              // passera à la prochaine ouverture de session.
              Text(
                Textes.explicationModeDemarrage(etat.modeDemarrage),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
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
    return SectionPliable(
      identifiant: 'parametres.aPropos',
      titre: Textes.sectionAPropos,
      icone: Icons.info_outline,
      // Le numéro de version reste lisible section repliée.
      resume: Textes.versionComplete(versionApplication),
      enfants: <Widget>[
        // Version déjà dans l'en-tête : pas de doublon ici.
        Text(Textes.titreApplication, style: theme.textTheme.titleMedium),
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
