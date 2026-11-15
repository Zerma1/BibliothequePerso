/// Écran Titre : fiche complète d'un titre et liste de ses chapitres.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_bibliotheque.dart';
import '../etat/etat_titre.dart';
import '../modeles/chapitre.dart';
import '../modeles/titre.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/image_couverture.dart';
import '../widgets/messages.dart';
import '../widgets/pastille_categorie.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';

/// Actions du menu de la fiche.
enum _ActionTitre { toutLu, toutNonLu, supprimer }

/// Fiche d'un titre : couverture, informations, catégories, listes et
/// chapitres (du plus récent au plus ancien).
///
/// Lit un [EtatTitre] fourni au-dessus de lui : utiliser [EcranTitre.ouvrir].
class EcranTitre extends StatelessWidget {
  /// Crée l'écran.
  const EcranTitre({super.key});

  /// Ouvre la fiche du titre [idTitre] avec son propre état.
  ///
  /// L'état est créé par `EtatBibliotheque` : l'écran n'a pas accès aux
  /// services (PLAYBOOK.md section 4). Il est libéré à la fermeture.
  static Future<void> ouvrir(BuildContext context, int idTitre) {
    final etatBibliotheque = context.read<EtatBibliotheque>();
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<EtatTitre>(
          create: (_) => etatBibliotheque.creerEtatTitre(idTitre)..charger(),
          child: const EcranTitre(),
        ),
      ),
    );
  }

  Future<void> _actualiser(BuildContext context, EtatTitre etat) async {
    final resultat = await etat.actualiser();
    if (!context.mounted) {
      return;
    }
    afficherResultat(
      context,
      resultat,
      succes: Textes.actualisationTerminee(resultat.donnee ?? 0),
    );
  }

  Future<void> _executer(
    BuildContext context,
    EtatTitre etat,
    _ActionTitre action,
  ) async {
    if (action == _ActionTitre.supprimer) {
      await _supprimer(context, etat);
      return;
    }
    final resultat = await etat.marquerTousLus(
      estLu: action == _ActionTitre.toutLu,
    );
    if (context.mounted) {
      afficherResultat(context, resultat);
    }
  }

  Future<void> _supprimer(BuildContext context, EtatTitre etat) async {
    final titre = etat.titre;
    if (titre == null) {
      return;
    }
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.supprimerTitre),
        content: Text(Textes.confirmationSuppression(titre.nom)),
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
    if (confirme != true || !context.mounted) {
      return;
    }
    final resultat = await context.read<EtatBibliotheque>().supprimerTitre(
      etat.idTitre,
    );
    if (!context.mounted) {
      return;
    }
    if (resultat.estReussi) {
      // Le message est affiché par le ScaffoldMessenger de l'application :
      // il reste visible sur la bibliothèque après la fermeture de la fiche.
      afficherMessage(context, Textes.titreSupprime(titre.nom));
      Navigator.of(context).pop();
    } else {
      afficherResultat(context, resultat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatTitre>();
    final titre = etat.titre;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titre?.nom ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (titre != null) ...<Widget>[
            if (etat.estEnActualisation)
              const Padding(
                padding: EdgeInsets.all(espacementMoyen),
                child: SizedBox.square(
                  dimension: espacementGrand,
                  child: CircularProgressIndicator(),
                ),
              )
            else
              IconButton(
                tooltip: Textes.actualiser,
                icon: const Icon(Icons.refresh),
                onPressed: () => _actualiser(context, etat),
              ),
            PopupMenuButton<_ActionTitre>(
              onSelected: (action) => _executer(context, etat, action),
              itemBuilder: (_) => const <PopupMenuEntry<_ActionTitre>>[
                PopupMenuItem<_ActionTitre>(
                  value: _ActionTitre.toutLu,
                  child: Text(Textes.toutMarquerLu),
                ),
                PopupMenuItem<_ActionTitre>(
                  value: _ActionTitre.toutNonLu,
                  child: Text(Textes.toutMarquerNonLu),
                ),
                PopupMenuDivider(),
                PopupMenuItem<_ActionTitre>(
                  value: _ActionTitre.supprimer,
                  child: Text(Textes.supprimerTitre),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _contenu(context, etat),
    );
  }

  Widget _contenu(BuildContext context, EtatTitre etat) {
    final erreur = etat.erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.charger,
      );
    }
    final titre = etat.titre;
    if (titre == null) {
      return const VueChargement();
    }
    return LayoutBuilder(
      builder: (context, contraintes) {
        final estLarge = contraintes.maxWidth >= largeurMinNavigationLaterale;
        final chapitres = etat.chapitres;
        // CustomScrollView : la fiche et les chapitres défilent ensemble, et
        // seuls les chapitres visibles sont construits (titres très longs).
        return CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: _EnTete(
                etat: etat,
                titre: titre,
                estLarge: estLarge,
                largeurDisponible: contraintes.maxWidth,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  espacementMoyen,
                  espacementGrand,
                  espacementMoyen,
                  espacementPetit,
                ),
                child: Text(
                  Textes.enTeteChapitres(chapitres.length, etat.nombreNonLus),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            if (chapitres.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(espacementGrand),
                  child: Text(Textes.aucunChapitre, textAlign: TextAlign.center),
                ),
              )
            else
              SliverList.builder(
                itemCount: chapitres.length,
                itemBuilder: (context, index) =>
                    _TuileChapitre(etat: etat, chapitre: chapitres[index]),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: espacementGrand),
            ),
          ],
        );
      },
    );
  }
}

/// Haut de la fiche : couverture, informations, résumé, catégories, listes.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.etat,
    required this.titre,
    required this.estLarge,
    required this.largeurDisponible,
  });

  final EtatTitre etat;
  final Titre titre;
  final bool estLarge;
  final double largeurDisponible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Couverture proportionnelle à la largeur : à côté des informations sur
    // grand écran, centrée au-dessus sur téléphone.
    final largeurCouverture = math.min(
      largeurDisponible *
          (estLarge ? fractionCouvertureFiche : fractionCouvertureFicheEtroite),
      largeurMaxCouvertureFiche,
    );
    final couverture = SizedBox(
      width: largeurCouverture,
      child: AspectRatio(
        aspectRatio: rapportCouverture,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(espacementPetit),
          child: ImageCouverture(
            urlCouverture: titre.urlCouverture,
            referer: etat.source?.urlBase,
          ),
        ),
      ),
    );
    final informations = _Informations(etat: etat, titre: titre);

    return Padding(
      padding: const EdgeInsets.all(espacementMoyen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (estLarge)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                couverture,
                const SizedBox(width: espacementGrand),
                Expanded(child: informations),
              ],
            )
          else ...<Widget>[
            Center(child: couverture),
            const SizedBox(height: espacementMoyen),
            informations,
          ],
          const SizedBox(height: espacementGrand),
          Text(Textes.resume, style: theme.textTheme.titleMedium),
          const SizedBox(height: espacementPetit),
          SelectableText(
            (titre.resume ?? '').trim().isEmpty
                ? Textes.aucunResume
                : titre.resume!.trim(),
          ),
          const SizedBox(height: espacementGrand),
          Text(Textes.categories, style: theme.textTheme.titleMedium),
          const SizedBox(height: espacementPetit),
          if (etat.categories.isEmpty)
            const Text(Textes.aucuneCategorie)
          else
            Wrap(
              spacing: espacementPetit,
              runSpacing: espacementPetit,
              children: <Widget>[
                for (final categorie in etat.categories)
                  PastilleCategorie(nom: categorie.nom),
              ],
            ),
          const SizedBox(height: espacementGrand),
          Text(Textes.listes, style: theme.textTheme.titleMedium),
          const SizedBox(height: espacementPetit),
          Wrap(
            spacing: espacementPetit,
            runSpacing: espacementPetit,
            children: <Widget>[
              for (final liste in etat.listes)
                if (liste.id != null)
                  FilterChip(
                    label: Text(liste.nom),
                    selected: etat.idsListesDuTitre.contains(liste.id),
                    onSelected: (coche) async {
                      final resultat = coche
                          ? await etat.ajouterALaListe(liste.id!)
                          : await etat.retirerDeLaListe(liste.id!);
                      if (context.mounted) {
                        afficherResultat(context, resultat);
                      }
                    },
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nom, informations, titres alternatifs, lien vers le site et crédit.
class _Informations extends StatelessWidget {
  const _Informations({required this.etat, required this.titre});

  final EtatTitre etat;
  final Titre titre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alternatifs = titre.titresAlternatifs;
    final source = etat.source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SelectableText(titre.nom, style: theme.textTheme.headlineSmall),
        const SizedBox(height: espacementPetit),
        _LigneInfo(Textes.auteur, titre.auteur ?? Textes.inconnu),
        _LigneInfo(Textes.statut, titre.statut ?? Textes.inconnu),
        _LigneInfo(Textes.typeTitre, Textes.libelleTypeTitre(titre.typeTitre)),
        if (source != null) _LigneInfo(Textes.site, source.nom),
        Text(
          Textes.derniereVerification(titre.dateDerniereVerification),
          style: theme.textTheme.bodySmall,
        ),
        if (alternatifs.isNotEmpty)
          // Repliés par défaut : un titre MangaDex en a souvent une dizaine,
          // qui repousseraient le résumé et les chapitres hors de l'écran.
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(Textes.titresAlternatifs(alternatifs.length)),
            children: <Widget>[
              for (final alternatif in alternatifs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: SelectableText(alternatif.nom),
                  trailing: alternatif.langue.isEmpty
                      ? null
                      : Text(alternatif.langue.toUpperCase()),
                ),
            ],
          ),
        const SizedBox(height: espacementPetit),
        OutlinedButton.icon(
          onPressed: () => ouvrirLienExterne(context, titre.urlTitre),
          icon: const Icon(Icons.open_in_new),
          label: const Text(Textes.ouvrirSurLeSite),
        ),
        if (etat.estMangaDex) ...<Widget>[
          const SizedBox(height: espacementPetit),
          // Crédit exigé par les règles d'usage de MangaDex
          // (PLAYBOOK.md section 6).
          Text(Textes.creditMangaDex, style: theme.textTheme.labelSmall),
        ],
      ],
    );
  }
}

/// Ligne « Libellé : valeur ».
class _LigneInfo extends StatelessWidget {
  const _LigneInfo(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: espacementPetit / 2),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: Textes.libelleInfo(libelle),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: valeur),
          ],
        ),
      ),
    );
  }
}

/// Ligne d'un chapitre : nom, langue, date, état de lecture.
class _TuileChapitre extends StatelessWidget {
  const _TuileChapitre({required this.etat, required this.chapitre});

  final EtatTitre etat;
  final Chapitre chapitre;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final estLu = chapitre.estLu;
    return ListTile(
      leading: Icon(
        estLu ? Icons.check_circle : Icons.circle_outlined,
        color: estLu ? couleurs.outline : couleurs.primary,
      ),
      title: Text(
        Textes.nomChapitre(chapitre.nom, chapitre.numero),
        // Les chapitres lus sont atténués : les nouveautés ressortent.
        style: TextStyle(
          color: estLu ? couleurs.outline : null,
          fontWeight: estLu ? null : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        Textes.detailsChapitre(chapitre.langue, chapitre.datePublication),
      ),
      // LIMITE : le lecteur intégré arrive à l'étape 5 ; d'ici là, l'appui
      // ouvre le chapitre sur le site.
      onTap: () => ouvrirLienExterne(context, chapitre.urlChapitre),
      trailing: IconButton(
        tooltip: estLu ? Textes.marquerNonLu : Textes.marquerLu,
        icon: Icon(estLu ? Icons.remove_done : Icons.done),
        onPressed: () async {
          final resultat = await etat.marquerLu(chapitre, estLu: !estLu);
          if (context.mounted) {
            afficherResultat(context, resultat);
          }
        },
      ),
    );
  }
}
