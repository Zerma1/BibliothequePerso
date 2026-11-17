/// Section « Dossier des chapitres » des paramètres : dossier actuel,
/// changement de dossier (local, lecteur réseau, NAS) avec déplacement des
/// archives, reprise ou abandon d'un déplacement inachevé.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_dossier_chapitres.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'section_pliable.dart';
import 'textes.dart';
import 'vues_etat.dart';

/// Section des paramètres consacrée au dossier des chapitres téléchargés.
/// Absente si l'application n'a pas d'[EtatDossierChapitres] (tests).
class SectionDossierChapitres extends StatelessWidget {
  /// Crée la section.
  const SectionDossierChapitres({super.key});

  Future<void> _abandonner(
    BuildContext context,
    EtatDossierChapitres etat,
  ) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.abandonnerDeplacement),
        content: const Text(Textes.confirmationAbandonDeplacement),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.abandonner),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.abandonnerDeplacementInacheve();
    if (context.mounted) {
      afficherResultat(context, resultat, succes: Textes.deplacementAbandonne);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatDossierChapitres?>();
    if (etat == null) return const SizedBox.shrink();
    return SectionPliable(
      identifiant: 'parametres.dossierChapitres',
      titre: Textes.sectionDossierChapitres,
      icone: Icons.folder_outlined,
      // Le chemin reste lisible section repliée : le client voit d'un coup
      // d'œil où sont ses chapitres.
      resume: etat.dossierActuel,
      enfants: <Widget>[_contenu(context, etat)],
    );
  }

  Widget _contenu(BuildContext context, EtatDossierChapitres etat) {
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
    final inacheve = etat.deplacementInacheve;
    final prochain = etat.dossierAuProchainDemarrage;
    final occupe = etat.estEnChangement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          Textes.explicationDossierChapitres,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: espacementMoyen),
        Text(Textes.dossierActuel, style: theme.textTheme.titleSmall),
        // Chemin sélectionnable : le client peut le copier pour ouvrir le
        // dossier dans l'explorateur.
        SelectableText(etat.dossierActuel),
        Text(
          etat.estDossierPersonnalise
              ? Textes.dossierChoisiParVous
              : Textes.dossierParDefautApplication,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        if (prochain != null) ...<Widget>[
          const SizedBox(height: espacementPetit),
          Text(
            Textes.dossierAuProchainDemarrage(prochain),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const Text(Textes.redemarrerPourNouveauDossier),
        ],
        if (inacheve != null) ...<Widget>[
          const SizedBox(height: espacementMoyen),
          // Carte colorée : un déplacement inachevé demande une décision du
          // client, elle doit se distinguer du reste de la section.
          Card.filled(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(espacementMoyen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    Textes.deplacementInacheve(inacheve),
                    style: TextStyle(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: espacementPetit),
                  // Boutons qui passent à la ligne sur un écran étroit.
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: espacementPetit,
                    runSpacing: espacementPetit,
                    children: <Widget>[
                      TextButton(
                        onPressed: occupe
                            ? null
                            : () => _abandonner(context, etat),
                        child: const Text(Textes.abandonner),
                      ),
                      FilledButton(
                        onPressed: occupe || etat.redemarrageNecessaire
                            ? null
                            : () => ouvrirChangementDossier(
                                context,
                                etat,
                                cheminImpose: inacheve,
                              ),
                        child: const Text(Textes.terminerDeplacement),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        if (etat.peutReprendreFile && !occupe) ...<Widget>[
          const SizedBox(height: espacementMoyen),
          const Text(Textes.filePauseeParChangement),
          const SizedBox(height: espacementPetit),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: etat.reprendreFile,
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text(Textes.reprendreTelechargements),
            ),
          ),
        ],
        const SizedBox(height: espacementMoyen),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            // Un seul changement par session. Pendant un déplacement
            // inachevé, le bouton reste actif : le client peut choisir un
            // autre dossier, après l'avertissement du service.
            onPressed: occupe || etat.redemarrageNecessaire
                ? null
                : () => ouvrirChangementDossier(context, etat),
            icon: const Icon(Icons.drive_file_move_outlined),
            label: const Text(Textes.changerDeDossier),
          ),
        ),
      ],
    );
  }
}

/// Ouvre le dialogue de changement de dossier. Avec [cheminImpose]
/// (déplacement inachevé à terminer), le chemin n'est pas modifiable et le
/// déplacement commence aussitôt.
///
/// Si le client ferme le dialogue alors qu'un refus « chapitre en cours » a
/// mis la file en pause, les téléchargements reprennent.
Future<void> ouvrirChangementDossier(
  BuildContext context,
  EtatDossierChapitres etat, {
  String? cheminImpose,
}) async {
  final resultat = await showDialog<ResultatChangementDossier>(
    context: context,
    // Un appui à côté ne ferme pas la boîte : pendant le déplacement, le
    // client perdrait la progression ; avant, il perdrait sa saisie.
    barrierDismissible: false,
    builder: (_) =>
        DialogueChangementDossier(etat: etat, cheminImpose: cheminImpose),
  );
  if (resultat == null && etat.peutReprendreFile) {
    etat.reprendreFile();
  }
}

/// Étapes du dialogue de changement de dossier.
enum _Etape { saisie, enCours, termine }

/// Dialogue « Changer de dossier » : chemin, case « Déplacer les chapitres
/// déjà téléchargés », retour au dossier par défaut ; puis progression du
/// déplacement (boîte non fermable) et message du résultat.
///
/// Renvoie le [ResultatChangementDossier] d'un changement réussi, ou `null`
/// si le client annule. Reçoit l'[EtatDossierChapitres] directement : le
/// dialogue est construit au-dessus de la route courante.
class DialogueChangementDossier extends StatefulWidget {
  /// Crée le dialogue pour [etat].
  const DialogueChangementDossier({
    super.key,
    required this.etat,
    this.cheminImpose,
  });

  /// État du dossier des chapitres.
  final EtatDossierChapitres etat;

  /// Chemin imposé (déplacement inachevé à terminer), ou `null`.
  final String? cheminImpose;

  @override
  State<DialogueChangementDossier> createState() =>
      _EtatDialogueChangementDossier();
}

class _EtatDialogueChangementDossier extends State<DialogueChangementDossier> {
  late final TextEditingController _chemin = TextEditingController(
    text: widget.cheminImpose ?? '',
  );
  bool _deplacer = true;
  _Etape _etape = _Etape.saisie;
  String? _erreur;
  ResultatChangementDossier? _resultat;

  /// `true` pendant la lecture de l'avertissement avant changement.
  bool _verificationEnCours = false;

  bool get _estImpose => widget.cheminImpose != null;

  @override
  void initState() {
    super.initState();
    // Le bouton « Changer » suit le contenu du champ.
    _chemin.addListener(() => setState(() {}));
    if (_estImpose) {
      // Terminer un déplacement inachevé : rien à saisir, il reprend tout
      // de suite (après la première image, le dialogue étant affiché).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _changer(widget.cheminImpose);
      });
    }
  }

  @override
  void dispose() {
    _chemin.dispose();
    super.dispose();
  }

  Future<void> _changer(String? chemin) async {
    if (_verificationEnCours) return;
    // Le déplacement est toujours demandé pour terminer un déplacement
    // inachevé.
    final deplacer = _estImpose || _deplacer;
    if (!_estImpose && !await _confirmerAvertissement(chemin, deplacer)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _etape = _Etape.enCours;
      _erreur = null;
    });
    final resultat = await widget.etat.changerDossier(
      chemin,
      deplacerArchives: deplacer,
    );
    if (!mounted) return;
    final changement = resultat.donnee;
    final erreur = resultat.erreur;
    setState(() {
      if (changement != null) {
        _resultat = changement;
        _etape = _Etape.termine;
      } else {
        _etape = _Etape.saisie;
        _erreur = erreur == null ? null : Textes.messageErreur(erreur);
      }
    });
  }

  /// Demande l'avertissement du service avant le changement ; s'il y en a
  /// un, le client doit confirmer. Renvoie `true` si le changement peut
  /// commencer. Une erreur de lecture reste affichée dans la saisie.
  Future<bool> _confirmerAvertissement(String? chemin, bool deplacer) async {
    // Boutons désactivés pendant la lecture : un double appui ne pose pas
    // deux fois la question.
    setState(() {
      _verificationEnCours = true;
      _erreur = null;
    });
    final resultat = await widget.etat.avertissementAvantChangement(
      chemin,
      deplacerArchives: deplacer,
    );
    if (!mounted) return false;
    setState(() => _verificationEnCours = false);
    final erreur = resultat.erreur;
    if (erreur != null) {
      setState(() => _erreur = Textes.messageErreur(erreur));
      return false;
    }
    final avertissement = resultat.donnee;
    if (avertissement == null) return true;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.avantChangementDossier),
        // Même largeur bornée que le dialogue principal : le texte cite un
        // chemin, il reste lisible sur grand écran.
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: SingleChildScrollView(child: Text(avertissement)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.changerQuandMeme),
          ),
        ],
      ),
    );
    return confirme == true;
  }

  @override
  Widget build(BuildContext context) {
    // Pendant le déplacement, ni le bouton retour (Android) ni Échap ne
    // ferment la boîte.
    return PopScope(
      canPop: _etape != _Etape.enCours,
      child: ListenableBuilder(
        listenable: widget.etat,
        builder: (context, _) => switch (_etape) {
          _Etape.saisie => _saisie(context),
          _Etape.enCours => _enCours(context),
          _Etape.termine => _termine(context),
        },
      ),
    );
  }

  /// Contenu borné en largeur : sur grand écran, des chemins sur toute la
  /// largeur se lisent mal ; sur téléphone, la boîte prend la place
  /// disponible.
  Widget _cadre(List<Widget> enfants) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: enfants,
      ),
    ),
  );

  Widget _saisie(BuildContext context) {
    final theme = Theme.of(context);
    final etat = widget.etat;
    final erreur = _erreur;
    final parDefaut = etat.cheminParDefaut;
    final peutChanger = _chemin.text.trim().isNotEmpty && !_verificationEnCours;
    return AlertDialog(
      title: Text(
        _estImpose ? Textes.terminerDeplacement : Textes.changerDeDossier,
      ),
      content: _cadre(<Widget>[
        if (!_estImpose) ...<Widget>[
          const Text(Textes.explicationChangementDossier),
          const SizedBox(height: espacementMoyen),
        ],
        TextField(
          controller: _chemin,
          readOnly: _estImpose,
          autofocus: !_estImpose,
          decoration: const InputDecoration(
            labelText: Textes.champNouveauDossier,
            hintText: Textes.aideNouveauDossier,
            border: OutlineInputBorder(),
          ),
          onSubmitted: peutChanger ? (texte) => _changer(texte) : null,
        ),
        if (!_estImpose) ...<Widget>[
          const SizedBox(height: espacementPetit),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _deplacer,
            onChanged: (valeur) => setState(() => _deplacer = valeur ?? true),
            title: const Text(Textes.deplacerChapitresTelecharges),
            // L'explication suit la case : le client voit ce qu'implique
            // chaque choix avant de valider.
            subtitle: Text(
              _deplacer
                  ? Textes.explicationDeplacerCoche
                  : Textes.explicationDeplacerDecoche,
            ),
          ),
          const SizedBox(height: espacementPetit),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: etat.estDossierPersonnalise && !_verificationEnCours
                  ? () => _changer(null)
                  : null,
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text(Textes.revenirDossierParDefaut),
            ),
          ),
          if (parDefaut != null)
            Text(
              Textes.cheminDossierParDefaut(parDefaut),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
        if (erreur != null) ...<Widget>[
          const SizedBox(height: espacementMoyen),
          Text(erreur, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (etat.peutReprendreFile) ...<Widget>[
          const SizedBox(height: espacementPetit),
          const Text(Textes.filePauseeParChangement),
        ],
      ]),
      actions: <Widget>[
        // « Annuler » ferme la boîte ; si la file a été mise en pause par un
        // refus, ouvrirChangementDossier la fait reprendre.
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: peutChanger ? () => _changer(_chemin.text) : null,
          child: Text(
            _estImpose
                ? Textes.terminerDeplacement
                : (erreur == null ? Textes.changer : Textes.reessayer),
          ),
        ),
      ],
    );
  }

  Widget _enCours(BuildContext context) {
    final etat = widget.etat;
    final deplacement = _estImpose || _deplacer;
    return AlertDialog(
      title: Text(
        _estImpose ? Textes.terminerDeplacement : Textes.changerDeDossier,
      ),
      // Aucun bouton : la boîte ne se ferme qu'à la fin du changement.
      content: _cadre(<Widget>[
        Text(
          deplacement ? Textes.deplacementEnCours : Textes.changementEnCours,
        ),
        const SizedBox(height: espacementMoyen),
        LinearProgressIndicator(value: deplacement ? etat.progression : null),
        if (deplacement) ...<Widget>[
          const SizedBox(height: espacementPetit),
          Text(
            Textes.progressionDeplacement(etat.faits, etat.total),
            textAlign: TextAlign.end,
          ),
        ],
      ]),
    );
  }

  /// Liste courte des fichiers restés dans l'ancien dossier (conflits),
  /// vide s'il n'y en a pas. Un chemin par ligne : plus facile à retrouver
  /// dans l'explorateur que la phrase du message.
  List<Widget> _conflits(ThemeData theme, List<String> chemins) {
    if (chemins.isEmpty) return const <Widget>[];
    const maximum = ResultatChangementDossier.nombreMaximalConflitsCites;
    final reste = chemins.length - maximum;
    return <Widget>[
      const SizedBox(height: espacementMoyen),
      Text(
        Textes.fichiersEnConflit(chemins.length),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      const SizedBox(height: espacementPetit),
      for (final chemin in chemins.take(maximum))
        SelectableText(
          Textes.fichierEnConflit(chemin),
          style: theme.textTheme.bodySmall,
        ),
      if (reste > 0)
        Text(
          Textes.autresFichiersEnConflit(reste),
          style: theme.textTheme.bodySmall,
        ),
    ];
  }

  Widget _termine(BuildContext context) {
    final theme = Theme.of(context);
    final resultat = _resultat!;
    return AlertDialog(
      title: const Text(Textes.dossierChange),
      content: _cadre(<Widget>[
        // Message du service sélectionnable : il contient le chemin.
        SelectableText(resultat.message),
        ..._conflits(theme, resultat.cheminsEnConflit),
        const SizedBox(height: espacementMoyen),
        // Consigne mise en avant : sans redémarrage, le nouveau dossier
        // n'est pas utilisé et les téléchargements restent en pause.
        Row(
          children: <Widget>[
            Icon(Icons.restart_alt, color: theme.colorScheme.primary),
            const SizedBox(width: espacementPetit),
            Expanded(
              child: Text(
                Textes.redemarrerPourNouveauDossier,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ]),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(resultat),
          child: const Text(Textes.fermer),
        ),
      ],
    );
  }
}
