/// Écran « Mises à jour » (tâche IN1 de l'étape 6) : titres suivis, favoris
/// et en attente, du plus récemment paru au plus ancien.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_mises_a_jour.dart';
import '../etat/etat_parutions.dart';
import '../widgets/bouton_recherche_mises_a_jour.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/image_couverture.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';
import 'ecran_titre.dart';

/// Liste des dernières parutions dans les langues de chaque titre, avec un
/// badge « Nouveau » quand le dernier chapitre paru n'est pas lu et date de
/// moins de 30 jours (`dureeNouveaute`, `EtatParutions.estNouveaute`).
///
/// Les titres sans aucun chapitre dans leurs langues (liste « En attente »)
/// sont regroupés à la fin sous un intertitre.
class EcranMisesAJour extends StatefulWidget {
  /// Crée l'écran.
  const EcranMisesAJour({super.key});

  @override
  State<EcranMisesAJour> createState() => _EtatEcranMisesAJour();
}

class _EtatEcranMisesAJour extends State<EcranMisesAJour> {
  /// Gardé pour se désabonner dans [dispose], où `context.read` n'est plus
  /// sûr.
  late final EtatMisesAJour _misesAJour;

  @override
  void initState() {
    super.initState();
    // L'écran reste monté (IndexedStack) : chaque recherche de nouveaux
    // chapitres, automatique ou manuelle, met la liste à jour.
    _misesAJour = context.read<EtatMisesAJour>();
    _misesAJour.finVerification.addListener(_surFinVerification);
  }

  @override
  void dispose() {
    _misesAJour.finVerification.removeListener(_surFinVerification);
    super.dispose();
  }

  void _surFinVerification() {
    if (!mounted || _misesAJour.finVerification.value == null) return;
    context.read<EtatParutions>().charger();
  }

  Future<void> _ouvrir(ParutionTitre ligne) async {
    final idTitre = ligne.titre.id;
    if (idTitre == null) return;
    final etat = context.read<EtatParutions>();
    await EcranTitre.ouvrir(context, idTitre);
    // Au retour, des chapitres ont pu être lus (badge « Nouveau »).
    await etat.charger();
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatParutions>();
    return Scaffold(
      appBar: AppBar(
        title: const Text(Textes.ongletMisesAJour),
        actions: <Widget>[
          const BoutonRechercheMisesAJour(),
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

  Widget _contenu(EtatParutions etat) {
    final erreur = etat.erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    }
    if (!etat.estCharge) {
      return const VueChargement();
    }
    if (etat.parutions.isEmpty) {
      return const VueVide(
        message: Textes.misesAJourVide,
        icone: Icons.new_releases_outlined,
      );
    }
    final avec = etat.avecParution;
    final sans = etat.sansParution;
    final theme = Theme.of(context);
    // Une seule liste construite à la demande : explication, titres avec
    // parution, intertitre, titres sans parution.
    final elements = <Widget Function()>[
      () => Padding(
        padding: const EdgeInsets.fromLTRB(
          espacementMoyen,
          espacementPetit,
          espacementMoyen,
          espacementPetit,
        ),
        child: Text(
          Textes.explicationMisesAJour,
          style: theme.textTheme.bodySmall,
        ),
      ),
      for (final ligne in avec)
        () => _LigneParution(
          key: ValueKey<int?>(ligne.titre.id),
          ligne: ligne,
          maintenant: etat.maintenant,
          estNouveau: etat.estNouveau(ligne),
          surAppui: () => _ouvrir(ligne),
        ),
      if (sans.isNotEmpty)
        () => Padding(
          padding: const EdgeInsets.fromLTRB(
            espacementMoyen,
            espacementGrand,
            espacementMoyen,
            espacementPetit,
          ),
          child: Text(
            Textes.sectionSansParution,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      for (final ligne in sans)
        () => _LigneParution(
          key: ValueKey<int?>(ligne.titre.id),
          ligne: ligne,
          maintenant: etat.maintenant,
          estNouveau: etat.estNouveau(ligne),
          surAppui: () => _ouvrir(ligne),
        ),
    ];
    return RefreshIndicator(
      onRefresh: etat.charger,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: espacementGrand),
        itemCount: elements.length,
        itemBuilder: (context, index) => elements[index](),
      ),
    );
  }
}

/// Une ligne : petite couverture, nom, dernier chapitre paru (ou langues
/// attendues) et badge « Nouveau ».
class _LigneParution extends StatelessWidget {
  const _LigneParution({
    super.key,
    required this.ligne,
    required this.maintenant,
    required this.estNouveau,
    required this.surAppui,
  });

  final ParutionTitre ligne;
  final DateTime maintenant;

  /// Badge « Nouveau » (critère de `EtatParutions.estNouveaute`).
  final bool estNouveau;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    final chapitre = ligne.dernierChapitre;
    final date = ligne.derniereParution;
    final detail = chapitre != null && date != null
        ? Textes.dernierChapitreParu(
            Textes.nomChapitre(chapitre.nom, chapitre.numero),
            chapitre.langue,
            date,
            maintenant,
          )
        : Textes.aucuneParution(ligne.langues);
    return ListTile(
      onTap: surAppui,
      // Vignette au format d'un tome : on reconnaît le titre d'un coup d'œil.
      leading: SizedBox(
        width: largeurCouvertureLigne,
        child: AspectRatio(
          aspectRatio: rapportCouverture,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(espacementPetit / 2),
            child: ImageCouverture(titre: ligne.titre),
          ),
        ),
      ),
      title: Text(
        ligne.titre.nom,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: estNouveau ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: Text(
        ligne.estEnAttente ? '$detail\n${Textes.enAttente}' : detail,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: ligne.estEnAttente,
      trailing: estNouveau
          ? Badge(
              label: const Text(Textes.nouveau),
              backgroundColor: couleurs.primary,
              textColor: couleurs.onPrimary,
            )
          : null,
    );
  }
}
