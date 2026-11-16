/// Écran Téléchargements : file de téléchargement hors-ligne et sa
/// progression.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_telechargements.dart';
import '../etat/outils_chapitres.dart';
import '../modeles/telechargement.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/indicateur_hors_ligne.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';

/// File de téléchargement : chaque chapitre avec son titre, son statut et
/// une barre de progression ; actions réessayer, supprimer, vider les
/// terminés.
class EcranTelechargements extends StatelessWidget {
  /// Crée l'écran.
  const EcranTelechargements({super.key});

  Future<void> _viderTermines(
    BuildContext context,
    EtatTelechargements etat,
  ) async {
    final resultat = await etat.viderTermines();
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.terminesRetires(resultat.donnee ?? 0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatTelechargements>();
    return Scaffold(
      appBar: AppBar(
        title: const Text(Textes.ongletTelechargements),
        actions: <Widget>[
          if (etat.nombreEchecs > 0)
            IconButton(
              tooltip: Textes.reessayerEchecs,
              icon: const Icon(Icons.replay),
              onPressed: () async {
                final resultat = await etat.reessayerEchecs();
                if (context.mounted) afficherResultat(context, resultat);
              },
            ),
          IconButton(
            tooltip: Textes.viderTermines,
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: etat.nombreTermines == 0
                ? null
                : () => _viderTermines(context, etat),
          ),
          IconButton(
            tooltip: Textes.actualiser,
            icon: const Icon(Icons.refresh),
            onPressed: etat.estEnChargement ? null : etat.charger,
          ),
        ],
      ),
      body: _contenu(etat),
    );
  }

  Widget _contenu(EtatTelechargements etat) {
    final erreur = etat.erreur;
    if (erreur != null && !etat.estCharge) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    }
    if (!etat.estCharge) {
      return const VueChargement();
    }
    if (etat.estVide) {
      return const VueVide(
        message: Textes.telechargementsVide,
        icone: Icons.download_for_offline_outlined,
      );
    }
    final suppressions = etat.suppressionsPrevues;
    // Une seule liste construite à la demande : les suppressions prévues
    // d'abord (elles attendent une décision du client avant l'échéance),
    // puis la file.
    final elements = <Widget Function(BuildContext)>[
      if (suppressions.isNotEmpty) ...<Widget Function(BuildContext)>[
        (context) => const _IntertitreSuppressions(),
        for (final suppression in suppressions)
          (context) => _LigneSuppressionPrevue(
            key: ValueKey<String>('suppression-${suppression.idChapitre}'),
            etat: etat,
            element: suppression,
          ),
        (context) => const _Intertitre(texte: Textes.sectionFile),
        if (etat.elements.isEmpty)
          (context) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: espacementMoyen),
            child: Text(Textes.fileVide),
          ),
      ],
      for (final element in etat.elements)
        (context) => Column(
          key: ValueKey<int>(element.idChapitre),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _LigneTelechargement(etat: etat, element: element),
            const Divider(height: 1),
          ],
        ),
    ];
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: espacementGrand),
      itemCount: elements.length,
      itemBuilder: (context, index) => elements[index](context),
    );
  }
}

/// Intertitre d'une section de l'écran.
class _Intertitre extends StatelessWidget {
  const _Intertitre({required this.texte, this.couleur});

  final String texte;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        espacementMoyen,
        espacementMoyen,
        espacementMoyen,
        espacementPetit,
      ),
      child: Text(
        texte,
        style: theme.textTheme.titleSmall?.copyWith(
          color: couleur ?? theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Intertitre rouge des suppressions prévues, avec son explication.
class _IntertitreSuppressions extends StatelessWidget {
  const _IntertitreSuppressions();

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatTelechargements>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Intertitre(
          texte: Textes.sectionSuppressionsPrevues(
            etat.suppressionsPrevues.length,
          ),
          couleur: couleurSuppressionPrevue(theme.colorScheme),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            espacementMoyen,
            0,
            espacementMoyen,
            espacementPetit,
          ),
          child: Text(
            Textes.explicationSuppressionsPrevues,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Un chapitre dont la suppression est prévue : en rouge, avec le compte à
/// rebours et les boutons « Garder » / « Supprimer maintenant » (mêmes
/// couleurs et mêmes mots que la fiche du titre).
class _LigneSuppressionPrevue extends StatelessWidget {
  const _LigneSuppressionPrevue({
    super.key,
    required this.etat,
    required this.element,
  });

  final EtatTelechargements etat;
  final ElementSuppressionPrevue element;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    final rouge = couleurSuppressionPrevue(couleurs);
    final chapitre = element.chapitre;
    final nomChapitre = Textes.nomChapitre(chapitre.nom, chapitre.numero);
    return Ink(
      // Même fond rouge léger que sur la fiche : la ligne se repère d'un
      // coup d'œil.
      color: couleurs.errorContainer.withValues(
        alpha: opaciteFondSuppressionPrevue,
      ),
      child: ListTile(
        leading: Icon(Icons.auto_delete_outlined, color: rouge),
        title: Text(
          element.titre?.nom ?? Textes.titreInconnu,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              chapitre.langue.isEmpty
                  ? nomChapitre
                  : '$nomChapitre · ${chapitre.langue.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              Textes.suppressionDans(element.tempsRestant(etat.maintenant)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: rouge,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Boutons sous le texte (et non à droite) : ils restent lisibles
            // sur un téléphone étroit et passent à la ligne si besoin.
            Wrap(
              spacing: espacementPetit,
              children: <Widget>[
                TextButton(
                  onPressed: () async {
                    final resultat = await etat.garder(element.idChapitre);
                    if (context.mounted) {
                      afficherResultat(
                        context,
                        resultat,
                        succes: Textes.chapitreGarde,
                      );
                    }
                  },
                  child: const Text(Textes.garder),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: rouge),
                  onPressed: () async {
                    final resultat = await etat.supprimerMaintenant(
                      element.idChapitre,
                    );
                    if (context.mounted) {
                      afficherResultat(
                        context,
                        resultat,
                        succes: Textes.telechargementSupprime,
                      );
                    }
                  },
                  child: const Text(Textes.supprimerMaintenant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne de la file.
class _LigneTelechargement extends StatelessWidget {
  const _LigneTelechargement({required this.etat, required this.element});

  final EtatTelechargements etat;
  final ElementTelechargement element;

  /// Statut affiché avec les mêmes icônes et couleurs que la fiche du titre.
  StatutHorsLigne get _statutHorsLigne {
    switch (element.statut) {
      case StatutTelechargement.enAttente:
        return StatutHorsLigne.enFile;
      case StatutTelechargement.enCours:
        return StatutHorsLigne.enCours;
      case StatutTelechargement.termine:
        return StatutHorsLigne.telecharge;
      case StatutTelechargement.echec:
        return StatutHorsLigne.echec;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final telechargement = element.telechargement;
    final chapitre = element.chapitre;
    final statut = _statutHorsLigne;
    final nomChapitre = chapitre == null
        ? Textes.chapitreIntrouvable(element.idChapitre)
        : Textes.nomChapitre(chapitre.nom, chapitre.numero);
    final estEnCours = element.statut == StatutTelechargement.enCours;
    return ListTile(
      leading: IndicateurHorsLigne(
        etat: EtatHorsLigne(
          statut,
          progression: telechargement.progression,
          messageErreur: telechargement.messageErreur,
        ),
      ),
      title: Text(
        element.titre?.nom ?? Textes.titreInconnu,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(nomChapitre, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            Textes.statutTelechargement(telechargement),
            style: theme.textTheme.bodySmall?.copyWith(
              color: statut == StatutHorsLigne.echec
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
          // Repère « gardé » : le client sait que ce chapitre échappe aux
          // règles de suppression.
          if (etat.estGarde(element.idChapitre))
            Tooltip(
              message: Textes.infoGarde,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.push_pin,
                    size: theme.textTheme.bodySmall?.fontSize,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: espacementPetit / 2),
                  Text(
                    Textes.garde,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          // Barre de progression seulement pendant le téléchargement : sans
          // nombre de pages connu, elle reste indéterminée.
          if (estEnCours) ...<Widget>[
            const SizedBox(height: espacementPetit / 2),
            LinearProgressIndicator(value: telechargement.progression),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (element.statut == StatutTelechargement.echec)
            IconButton(
              tooltip: Textes.reessayer,
              icon: const Icon(Icons.replay),
              onPressed: () async {
                final resultat = await etat.reessayer(element.idChapitre);
                if (context.mounted) afficherResultat(context, resultat);
              },
            ),
          IconButton(
            tooltip: element.statut == StatutTelechargement.termine
                ? Textes.supprimerTelechargement
                : Textes.retirerDeLaFile,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              // Même règle que la fiche du titre : une archive terminée se
              // supprime après confirmation (elle a demandé un long
              // téléchargement) ; une ligne en file se retire directement.
              if (element.statut == StatutTelechargement.termine) {
                final confirme = await confirmerSuppressionTelechargement(
                  context,
                  element.titre == null
                      ? nomChapitre
                      : Textes.chapitreDuTitre(element.titre!.nom, nomChapitre),
                );
                if (!confirme || !context.mounted) return;
              }
              final resultat = await etat.supprimer(element.idChapitre);
              if (context.mounted) {
                afficherResultat(
                  context,
                  resultat,
                  succes: element.statut == StatutTelechargement.termine
                      ? Textes.telechargementSupprime
                      : null,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
