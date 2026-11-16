/// Écran Sources : liste des sites configurés.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_sources.dart';
import '../modeles/source.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';
import 'ecran_ajout_site.dart';

/// Liste des sites configurés, avec un bouton pour en ajouter.
class EcranSources extends StatelessWidget {
  /// Crée l'écran.
  const EcranSources({super.key});

  Future<void> _ajouterSite(BuildContext context) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const EcranAjoutSite()),
    );
    if (message != null && context.mounted) {
      afficherMessage(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatSources>();
    return Scaffold(
      appBar: AppBar(
        title: const Text(Textes.ongletSources),
        actions: <Widget>[
          IconButton(
            tooltip: Textes.actualiser,
            icon: const Icon(Icons.refresh),
            onPressed: etat.estEnChargement ? null : etat.charger,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ajouterSite(context),
        icon: const Icon(Icons.add_link),
        label: const Text(Textes.boutonAjouterSite),
      ),
      body: _contenu(context, etat),
    );
  }

  Widget _contenu(BuildContext context, EtatSources etat) {
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
    if (etat.sources.isEmpty) {
      return VueVide(
        message: Textes.sourcesVide,
        icone: Icons.public_off_outlined,
        action: FilledButton.icon(
          onPressed: () => _ajouterSite(context),
          icon: const Icon(Icons.add_link),
          label: const Text(Textes.boutonAjouterSite),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: margeBasBoutonFlottant),
      itemCount: etat.sources.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _TuileSource(source: etat.sources[index]),
    );
  }
}

/// Ligne d'un site : nom, adresse, type et langue.
class _TuileSource extends StatelessWidget {
  const _TuileSource({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        source.typeSource == TypeSource.mangaDex
            ? Icons.auto_stories_outlined
            : Icons.language,
      ),
      title: Text(
        source.estActive ? source.nom : Textes.nomSourceInactive(source.nom),
      ),
      subtitle: Text(Textes.descriptionSource(source)),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: Textes.ouvrirSurLeSite,
        icon: const Icon(Icons.open_in_new),
        onPressed: () => ouvrirLienExterne(context, source.urlBase),
      ),
    );
  }
}
