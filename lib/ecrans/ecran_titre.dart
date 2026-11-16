/// Écran Titre : fiche complète d'un titre et liste de ses chapitres.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_bibliotheque.dart';
import '../etat/etat_parametres.dart';
import '../etat/etat_titre.dart';
import '../etat/outils_chapitres.dart';
import '../modeles/chapitre.dart';
import '../modeles/titre.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/editeur_langues.dart';
import '../widgets/image_couverture.dart';
import '../widgets/indicateur_hors_ligne.dart';
import '../widgets/messages.dart';
import '../widgets/pastille_categorie.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';
import 'ecran_lecteur.dart';

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
        final groupes = etat.groupes;
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
                  Textes.enTeteNumeros(
                    etat.nombreNumeros,
                    etat.nombreNumerosNonLus,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            if (groupes.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(espacementGrand),
                  child: Text(
                    Textes.aucunChapitre,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...<Widget>[
              // La légende reste en haut de la liste pendant le défilement :
              // le client garde le sens des colonnes sous les yeux.
              SliverToBoxAdapter(child: _LegendeChapitres(etat: etat)),
              SliverList.builder(
                itemCount: groupes.length,
                itemBuilder: (context, index) => _LigneGroupe(
                  // Clé par identifiant et non par numéro : plusieurs
                  // oneshots partagent le numéro 0 mais sont des lignes
                  // distinctes.
                  key: ValueKey<int?>(groupes[index].retenu.id),
                  etat: etat,
                  groupe: groupes[index],
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: espacementGrand)),
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
          const SizedBox(height: espacementGrand),
          _SectionLanguesTitre(etat: etat),
        ],
      ),
    );
  }
}

/// Langues appliquées à ce titre (réglage général, du site ou
/// personnalisées) et boutons pour les changer.
class _SectionLanguesTitre extends StatelessWidget {
  const _SectionLanguesTitre({required this.etat});

  final EtatTitre etat;

  Future<void> _modifier(BuildContext context) async {
    final choix = await showDialog<_ChoixLangues>(
      context: context,
      builder: (_) => _DialogueLanguesTitre(
        languesActuelles: etat.langues,
        languesGenerales: etat.languesGenerales,
        aLanguesPropres: etat.aLanguesPropres,
      ),
    );
    if (choix == null || !context.mounted) return;
    await _enregistrer(context, choix.langues);
  }

  Future<void> _enregistrer(BuildContext context, List<String>? langues) async {
    final resultat = await etat.modifierLangues(langues);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.languesTitreEnregistrees(resultat.donnee),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final langues = etat.langues;
    final String description;
    if (etat.aLanguesPropres) {
      description = Textes.languesTitrePropres(langues);
    } else if (listEquals(langues, etat.languesGenerales)) {
      description = Textes.languesTitreGenerales(langues);
    } else {
      // Titre d'un site qui garde l'ancien réglage de langues par site.
      description = Textes.languesTitreSite(langues);
    }
    final occupe = etat.estEnActualisation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(Textes.languesDuTitre, style: theme.textTheme.titleMedium),
        const SizedBox(height: espacementPetit),
        Text(description),
        const SizedBox(height: espacementPetit),
        // Boutons qui passent à la ligne sur un écran étroit.
        Wrap(
          spacing: espacementPetit,
          runSpacing: espacementPetit,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: occupe ? null : () => _modifier(context),
              icon: const Icon(Icons.translate),
              label: const Text(Textes.modifierLangues),
            ),
            if (etat.aLanguesPropres)
              TextButton(
                onPressed: occupe ? null : () => _enregistrer(context, null),
                child: const Text(Textes.revenirAuReglageGeneral),
              ),
          ],
        ),
      ],
    );
  }
}

/// Choix fait dans le dialogue des langues d'un titre : `null` = suivre le
/// réglage général.
class _ChoixLangues {
  const _ChoixLangues(this.langues);

  final List<String>? langues;
}

/// Dialogue des langues d'un titre : suivre « Mes langues », ou choisir des
/// langues propres à ce titre (brouillon local, enregistré à la validation).
class _DialogueLanguesTitre extends StatefulWidget {
  const _DialogueLanguesTitre({
    required this.languesActuelles,
    required this.languesGenerales,
    required this.aLanguesPropres,
  });

  final List<String> languesActuelles;
  final List<String> languesGenerales;
  final bool aLanguesPropres;

  @override
  State<_DialogueLanguesTitre> createState() => _EtatDialogueLanguesTitre();
}

class _EtatDialogueLanguesTitre extends State<_DialogueLanguesTitre> {
  late bool _personnalisees = widget.aLanguesPropres;

  // Brouillon de départ : les langues appliquées aujourd'hui, que le client
  // n'a plus qu'à ajuster.
  late List<String> _brouillon = List<String>.of(
    widget.languesActuelles.isEmpty
        ? widget.languesGenerales
        : widget.languesActuelles,
  );

  void _deplacer(String code, int decalage) {
    final index = _brouillon.indexOf(code);
    final cible = index + decalage;
    if (index < 0 || cible < 0 || cible >= _brouillon.length) return;
    setState(() {
      _brouillon = List<String>.of(_brouillon)
        ..removeAt(index)
        ..insert(cible, code);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(Textes.languesDuTitre),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(Textes.explicationLanguesTitre),
              const SizedBox(height: espacementMoyen),
              RadioGroup<bool>(
                groupValue: _personnalisees,
                onChanged: (valeur) =>
                    setState(() => _personnalisees = valeur ?? false),
                child: Column(
                  children: <Widget>[
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      value: false,
                      title: const Text(Textes.suivreReglageGeneral),
                      subtitle: Text(
                        Textes.listeLangues(widget.languesGenerales),
                      ),
                    ),
                    const RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      value: true,
                      title: Text(Textes.languesPersonnalisees),
                    ),
                  ],
                ),
              ),
              if (_personnalisees)
                EditeurLangues(
                  langues: _brouillon,
                  nombreMaximal: EtatParametres.nombreMaximalLangues,
                  surAjouter: (code) => setState(
                    () => _brouillon = <String>[..._brouillon, code],
                  ),
                  surRetirer: (code) => setState(
                    () => _brouillon = <String>[
                      for (final langue in _brouillon)
                        if (langue != code) langue,
                    ],
                  ),
                  surDeplacer: _deplacer,
                  surChoisirFavorite: (code) =>
                      _deplacer(code, -_brouillon.indexOf(code)),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(_ChoixLangues(_personnalisees ? _brouillon : null)),
          child: const Text(Textes.enregistrer),
        ),
      ],
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

/// Légende de la liste des chapitres : intitulés des colonnes, alignés sur
/// les lignes, puis sens des icônes hors-ligne.
class _LegendeChapitres extends StatelessWidget {
  const _LegendeChapitres({required this.etat});

  final EtatTitre etat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        espacementMoyen,
        0,
        espacementMoyen,
        espacementPetit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (etat.gereTelechargements) ...<Widget>[
            Text(Textes.aideAppuiChapitre, style: theme.textTheme.bodySmall),
            const SizedBox(height: espacementPetit),
            const LegendeHorsLigne(),
            const SizedBox(height: espacementPetit),
          ],
          // Mêmes proportions que les lignes (_ColonnesChapitre) : chaque
          // intitulé tombe au-dessus de sa colonne, quelle que soit la
          // largeur de l'écran.
          _ColonnesChapitre(
            avecHorsLigne: etat.gereTelechargements,
            nom: Text(Textes.colonneChapitre, style: style),
            langue: Text(Textes.colonneLangue, style: style),
            date: Text(Textes.colonneDate, style: style),
            horsLigne: Text(
              Textes.colonneHorsLigne,
              style: style,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            lu: Text(
              Textes.colonneLu,
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: espacementPetit),
        ],
      ),
    );
  }
}

/// Disposition commune à la légende et aux lignes : cinq colonnes en
/// proportions de la largeur (pas de largeur fixe en pixels).
class _ColonnesChapitre extends StatelessWidget {
  const _ColonnesChapitre({
    required this.avecHorsLigne,
    required this.nom,
    required this.langue,
    required this.date,
    required this.horsLigne,
    required this.lu,
  });

  final bool avecHorsLigne;
  final Widget nom;
  final Widget langue;
  final Widget date;
  final Widget horsLigne;
  final Widget lu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(flex: flexColonneNom, child: nom),
        Expanded(flex: flexColonneLangue, child: langue),
        Expanded(flex: flexColonneDate, child: date),
        if (avecHorsLigne)
          Expanded(
            flex: flexColonneHorsLigne,
            child: Center(child: horsLigne),
          ),
        Expanded(
          flex: flexColonneLu,
          child: Center(child: lu),
        ),
      ],
    );
  }
}

/// Un numéro de chapitre : la version retenue, et les autres versions
/// (autres langues) repliées dessous.
class _LigneGroupe extends StatefulWidget {
  const _LigneGroupe({super.key, required this.etat, required this.groupe});

  final EtatTitre etat;
  final GroupeChapitres groupe;

  @override
  State<_LigneGroupe> createState() => _EtatLigneGroupe();
}

class _EtatLigneGroupe extends State<_LigneGroupe> {
  // Déplié d'office si une version cachée demande une décision du client
  // (suppression prévue, doublon) : sinon il ne la verrait pas.
  late bool _estDeplie = _autresDemandentAction;

  bool get _autresDemandentAction => widget.groupe.autres.any((chapitre) {
    final horsLigne = widget.etat.etatHorsLigne(chapitre);
    return horsLigne.aSuppressionPrevue ||
        (horsLigne.estDoublon &&
            horsLigne.statut == StatutHorsLigne.telecharge);
  });

  @override
  Widget build(BuildContext context) {
    final groupe = widget.groupe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LigneChapitre(
          etat: widget.etat,
          chapitre: groupe.retenu,
          estLu: groupe.estLu,
          surBasculerLu: () =>
              widget.etat.marquerGroupeLu(groupe, estLu: !groupe.estLu),
          autresVersions: groupe.autres.length,
          autresATrier: _autresDemandentAction,
          estDeplie: _estDeplie,
          surDeplier: () => setState(() => _estDeplie = !_estDeplie),
        ),
        if (_estDeplie)
          for (final autre in groupe.autres)
            _LigneChapitre(
              etat: widget.etat,
              chapitre: autre,
              estLu: autre.estLu,
              surBasculerLu: () =>
                  widget.etat.marquerLu(autre, estLu: !autre.estLu),
              estSecondaire: true,
            ),
      ],
    );
  }
}

/// Ligne d'un chapitre : nom, langue, date, état hors-ligne, lu.
///
/// Un appui n'ouvre jamais le site directement : chapitre téléchargé →
/// lecteur ; sinon, un menu propose de le télécharger ou de l'ouvrir sur le
/// site.
class _LigneChapitre extends StatelessWidget {
  const _LigneChapitre({
    required this.etat,
    required this.chapitre,
    required this.estLu,
    required this.surBasculerLu,
    this.autresVersions = 0,
    this.autresATrier = false,
    this.estDeplie = false,
    this.surDeplier,
    this.estSecondaire = false,
  });

  final EtatTitre etat;
  final Chapitre chapitre;
  final bool estLu;
  final Future<ResultatAction<bool>> Function() surBasculerLu;
  final int autresVersions;

  /// Une des autres versions attend une décision (suppression prévue ou
  /// doublon) : mention orange sur la ligne repliée.
  final bool autresATrier;
  final bool estDeplie;
  final VoidCallback? surDeplier;
  final bool estSecondaire;

  Future<void> _surAppui(BuildContext context) async {
    final horsLigne = etat.etatHorsLigne(chapitre);
    if (horsLigne.statut == StatutHorsLigne.telecharge) {
      await _lire(context);
      return;
    }
    await _afficherMenu(context, horsLigne);
  }

  Future<void> _lire(BuildContext context) async {
    final etatLecteur = etat.creerEtatLecteur(chapitre);
    if (etatLecteur == null) return;
    await EcranLecteur.ouvrir(context, etatLecteur);
    // Au retour, des chapitres ont pu être lus et la file a pu avancer.
    await etat.charger();
  }

  Future<void> _afficherMenu(
    BuildContext context,
    EtatHorsLigne horsLigne,
  ) async {
    final action = await showModalBottomSheet<_ActionChapitre>(
      context: context,
      showDragHandle: true,
      builder: (contexteMenu) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                Textes.nomChapitre(chapitre.nom, chapitre.numero),
                style: Theme.of(contexteMenu).textTheme.titleMedium,
              ),
              subtitle: Text(Textes.libelleStatutHorsLigne(horsLigne.statut)),
            ),
            if (etat.gereTelechargements &&
                (horsLigne.statut == StatutHorsLigne.nonTelecharge ||
                    horsLigne.statut == StatutHorsLigne.echec))
              ListTile(
                leading: const Icon(Icons.download),
                title: Text(
                  horsLigne.statut == StatutHorsLigne.echec
                      ? Textes.reessayerTelechargement
                      : Textes.telecharger,
                ),
                onTap: () =>
                    Navigator.of(contexteMenu).pop(_ActionChapitre.telecharger),
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text(Textes.ouvrirSurLeSite),
              onTap: () =>
                  Navigator.of(contexteMenu).pop(_ActionChapitre.ouvrirSite),
            ),
            ListTile(
              leading: Icon(estLu ? Icons.remove_done : Icons.done),
              title: Text(estLu ? Textes.marquerNonLu : Textes.marquerLu),
              onTap: () =>
                  Navigator.of(contexteMenu).pop(_ActionChapitre.basculerLu),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _ActionChapitre.telecharger:
        final resultat = await etat.telecharger(chapitre);
        if (context.mounted) {
          afficherResultat(
            context,
            resultat,
            succes: Textes.telechargementAjoute,
          );
        }
      case _ActionChapitre.ouvrirSite:
        await ouvrirLienExterne(context, chapitre.urlChapitre);
      case _ActionChapitre.basculerLu:
        final resultat = await surBasculerLu();
        if (context.mounted) afficherResultat(context, resultat);
    }
  }

  /// Bouton de la colonne hors-ligne : l'action dépend de l'état.
  Future<void> _surAppuiHorsLigne(
    BuildContext context,
    EtatHorsLigne horsLigne,
  ) async {
    switch (horsLigne.statut) {
      case StatutHorsLigne.telecharge:
        final nom = Textes.nomChapitre(chapitre.nom, chapitre.numero);
        final confirme = await confirmerSuppressionTelechargement(context, nom);
        if (!confirme || !context.mounted) return;
        final resultat = await etat.supprimerTelechargement(chapitre);
        if (context.mounted) {
          afficherResultat(
            context,
            resultat,
            succes: Textes.telechargementSupprime,
          );
        }
      case StatutHorsLigne.enFile:
      case StatutHorsLigne.enCours:
        final resultat = await etat.supprimerTelechargement(chapitre);
        if (context.mounted) afficherResultat(context, resultat);
      case StatutHorsLigne.echec:
      case StatutHorsLigne.nonTelecharge:
        final resultat = await etat.telecharger(chapitre);
        if (context.mounted) {
          afficherResultat(
            context,
            resultat,
            succes: Textes.telechargementAjoute,
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    final horsLigne = etat.etatHorsLigne(chapitre);
    final aSuppression = horsLigne.aSuppressionPrevue;
    final estDoublon =
        !aSuppression &&
        horsLigne.estDoublon &&
        horsLigne.statut == StatutHorsLigne.telecharge;
    // Décisions du client : rouge pour une suppression prévue, orange pour
    // un doublon ; sinon les chapitres lus sont atténués (les nouveautés
    // ressortent).
    final Color? couleurAlerte = aSuppression
        ? couleurSuppressionPrevue(couleurs)
        : (estDoublon ? couleurDoublon(couleurs) : null);
    final couleurTexte = couleurAlerte ?? (estLu ? couleurs.outline : null);
    final styleDetail = theme.textTheme.bodySmall?.copyWith(
      color: couleurTexte,
    );
    final reste = horsLigne.tempsAvantSuppression(etat.maintenant);
    return InkWell(
      onTap: () => _surAppui(context),
      child: Ink(
        // Fond rouge léger : la ligne se repère en faisant défiler une longue
        // liste, même avant d'en lire le texte.
        color: aSuppression
            ? couleurs.errorContainer.withValues(
                alpha: opaciteFondSuppressionPrevue,
              )
            : null,
        child: Padding(
          // Les autres versions sont décalées : on voit qu'elles appartiennent
          // au numéro du dessus.
          padding: EdgeInsets.fromLTRB(
            estSecondaire ? espacementGrand + espacementMoyen : espacementMoyen,
            espacementPetit / 2,
            espacementMoyen,
            espacementPetit / 2,
          ),
          child: _ColonnesChapitre(
            avecHorsLigne: etat.gereTelechargements,
            nom: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Textes.nomChapitre(chapitre.nom, chapitre.numero),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: couleurTexte,
                    fontWeight: estLu || estSecondaire ? null : FontWeight.w600,
                  ),
                ),
                if (autresVersions > 0)
                  InkWell(
                    onTap: surDeplier,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            autresATrier
                                ? '${Textes.autresVersions(autresVersions)} · '
                                      '${Textes.versionsATrier}'
                                : Textes.autresVersions(autresVersions),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: autresATrier
                                  ? couleurDoublon(couleurs)
                                  : couleurs.primary,
                            ),
                          ),
                        ),
                        Icon(
                          estDeplie ? Icons.expand_less : Icons.expand_more,
                          size: theme.textTheme.bodySmall?.fontSize,
                          color: couleurs.primary,
                        ),
                      ],
                    ),
                  ),
                if (aSuppression && reste != null) ...<Widget>[
                  Text(
                    Textes.suppressionDans(reste),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: couleurAlerte,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    Textes.explicationSuppressionPrevue,
                    style: theme.textTheme.bodySmall,
                  ),
                  _ActionsArchive(
                    enfants: <Widget>[
                      TextButton(
                        onPressed: () => _garder(context),
                        child: const Text(Textes.garder),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: couleurAlerte,
                        ),
                        onPressed: () => _supprimerMaintenant(context),
                        child: const Text(Textes.supprimerMaintenant),
                      ),
                    ],
                  ),
                ],
                if (estDoublon) ...<Widget>[
                  Text(
                    Textes.explicationDoublon,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: couleurAlerte,
                    ),
                  ),
                  _ActionsArchive(
                    enfants: <Widget>[
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: couleurAlerte,
                        ),
                        onPressed: () => _supprimerDoublon(context),
                        child: const Text(Textes.supprimerCeDoublon),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            langue: Text(
              chapitre.langue.isEmpty ? '—' : chapitre.langue.toUpperCase(),
              style: styleDetail,
            ),
            date: Text(
              chapitre.datePublication == null
                  ? '—'
                  : Textes.formaterDate(chapitre.datePublication!),
              style: styleDetail,
            ),
            horsLigne: IconButton(
              tooltip: Textes.infoBulleHorsLigne(horsLigne),
              onPressed: () => _surAppuiHorsLigne(context, horsLigne),
              icon: IndicateurHorsLigne(etat: horsLigne),
            ),
            lu: IconButton(
              tooltip: estLu ? Textes.marquerNonLu : Textes.marquerLu,
              icon: Icon(
                estLu ? Icons.check_circle : Icons.circle_outlined,
                color: estLu ? couleurs.outline : couleurs.primary,
              ),
              onPressed: () async {
                final resultat = await surBasculerLu();
                if (context.mounted) afficherResultat(context, resultat);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// « Garder » : la suppression prévue est annulée pour de bon.
  Future<void> _garder(BuildContext context) async {
    final resultat = await etat.garder(chapitre);
    if (context.mounted) {
      afficherResultat(context, resultat, succes: Textes.chapitreGarde);
    }
  }

  /// « Supprimer maintenant » : sans confirmation, le client vient de
  /// choisir entre deux boutons explicites et l'archive allait de toute
  /// façon être supprimée.
  Future<void> _supprimerMaintenant(BuildContext context) async {
    final resultat = await etat.supprimerMaintenant(chapitre);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.telechargementSupprime,
      );
    }
  }

  /// Suppression d'un doublon : confirmée, car rien ne l'aurait supprimé
  /// sans l'action du client.
  Future<void> _supprimerDoublon(BuildContext context) async {
    final confirme = await confirmerSuppressionTelechargement(
      context,
      Textes.nomChapitre(chapitre.nom, chapitre.numero),
    );
    if (!confirme || !context.mounted) return;
    final resultat = await etat.supprimerMaintenant(chapitre);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.telechargementSupprime,
      );
    }
  }
}

/// Boutons d'action sous le nom d'un chapitre (suppression prévue,
/// doublon) : compacts, et passent à la ligne si la colonne est étroite.
class _ActionsArchive extends StatelessWidget {
  const _ActionsArchive({required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return TextButtonTheme(
      data: TextButtonThemeData(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: espacementPetit),
        ),
      ),
      child: Wrap(spacing: espacementPetit / 2, children: enfants),
    );
  }
}

/// Actions du menu d'un chapitre non téléchargé.
enum _ActionChapitre { telecharger, ouvrirSite, basculerLu }

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
