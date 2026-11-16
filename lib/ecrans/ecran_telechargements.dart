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
    if (etat.elements.isEmpty) {
      return const VueVide(
        message: Textes.telechargementsVide,
        icone: Icons.download_for_offline_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: espacementGrand),
      itemCount: etat.elements.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final element = etat.elements[index];
        return _LigneTelechargement(
          key: ValueKey<int>(element.idChapitre),
          etat: etat,
          element: element,
        );
      },
    );
  }
}

/// Une ligne de la file.
class _LigneTelechargement extends StatelessWidget {
  const _LigneTelechargement({
    super.key,
    required this.etat,
    required this.element,
  });

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
