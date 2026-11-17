/// Section « Sites » de la fiche d'un titre (étape 8 : plusieurs sites pour
/// un même titre) et ses dialogues.
library;

import 'package:material_ui/material_ui.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_titre.dart';
import 'bouton_rapport_erreur.dart';
import 'constantes_interface.dart';
import 'messages.dart';
import 'section_diagnostic_site.dart';
import 'textes.dart';

/// Sites du titre : le principal (marqué) puis les secondaires, avec pour
/// chacun son nom, son nombre de chapitres et ses actions (ouvrir, définir
/// comme principal, garder comme simple lien, retirer), puis le bouton
/// « Ajouter un autre site ». Un lien seul (T4) est marqué comme tel et
/// propose « Ouvrir dans le navigateur » et « Essayer de le lire ».
///
/// Lit l'[EtatTitre] reçu (déjà surveillé par la fiche) et appelle ses
/// méthodes ; aucune logique métier ici.
class SectionSitesTitre extends StatelessWidget {
  /// Crée la section pour [etat].
  const SectionSitesTitre({super.key, required this.etat});

  /// État de la fiche affichée.
  final EtatTitre etat;

  Future<void> _ajouter(BuildContext context) async {
    // Le dialogue renvoie directement le message de confirmation : il est
    // différent pour un site lu et pour un simple lien.
    final message = await showDialog<String>(
      context: context,
      // Pendant la lecture du site, un appui à côté ne doit pas fermer la
      // boîte : le client perdrait le résultat de l'ajout.
      barrierDismissible: false,
      builder: (_) => DialogueAjoutSite(etat: etat),
    );
    if (message != null && context.mounted) {
      afficherMessage(context, message);
    }
  }

  Future<void> _passerEnLienSeul(BuildContext context, SiteDuTitre site) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: Text(Textes.titrePassageLienSeul(site.nomSite)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: Text(
            Textes.confirmationPassageLienSeul(
              nombreNonLusRetires: etat.nombreChapitresRetiresAvecSite(
                site.idSource,
              ),
              nombreTelecharges: etat.nombreTelechargesDuSite(site.idSource),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.passerEnLienSeul),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.passerEnLienSeul(site.idSource);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.sitePasseEnLienSeul(resultat.donnee ?? 0),
      );
    }
  }

  Future<void> _essayerDeLire(BuildContext context, SiteDuTitre site) async {
    final resultat = await etat.essayerDeLire(site.idSource);
    if (!context.mounted) return;
    final erreur = resultat.erreur;
    afficherMessage(
      context,
      erreur == null
          ? Textes.lienSeulLu(resultat.donnee ?? 0)
          : Textes.lienSeulToujoursIllisible(Textes.messageErreur(erreur)),
    );
  }

  Future<void> _retirer(BuildContext context, SiteDuTitre site) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: Text(Textes.titreRetraitSite(site.nomSite)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: Text(
            Textes.confirmationRetraitSite(
              nombreNonLusRetires: etat.nombreChapitresRetiresAvecSite(
                site.idSource,
              ),
              nombreTelecharges: etat.nombreTelechargesDuSite(site.idSource),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.retirerSite),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.retirerSite(site.idSource);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.siteRetire(resultat.donnee ?? 0),
      );
    }
  }

  Future<void> _definirPrincipal(BuildContext context, SiteDuTitre site) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: Text(Textes.titreChangementPrincipal(site.nomSite)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
          child: const Text(Textes.explicationChangementPrincipal),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.confirmerPrincipal),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.definirSitePrincipal(site.idSource);
    if (context.mounted) {
      afficherResultat(
        context,
        resultat,
        succes: Textes.sitePrincipalChange(site.nomSite),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occupe = etat.estEnModificationSites || etat.estEnActualisation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(Textes.sitesDuTitre, style: theme.textTheme.titleMedium),
        const SizedBox(height: espacementPetit),
        Text(Textes.explicationSitesDuTitre, style: theme.textTheme.bodySmall),
        const SizedBox(height: espacementPetit),
        for (final site in etat.sites)
          _LigneSite(
            site: site,
            occupe: occupe,
            surOuvrir: () => ouvrirLienExterne(context, site.urlTitre),
            surDefinirPrincipal: () => _definirPrincipal(context, site),
            surRetirer: () => _retirer(context, site),
            surPasserEnLienSeul: () => _passerEnLienSeul(context, site),
            surEssayerDeLire: () => _essayerDeLire(context, site),
          ),
        if (etat.estEnModificationSites) ...<Widget>[
          const LinearProgressIndicator(),
          const SizedBox(height: espacementPetit),
        ],
        // Aligné à gauche : un bouton étiré sur toute la largeur d'un grand
        // écran se lit mal.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: occupe ? null : () => _ajouter(context),
            icon: const Icon(Icons.add_link),
            label: const Text(Textes.ajouterAutreSite),
          ),
        ),
      ],
    );
  }
}

/// Un site du titre : nom, rôle, nombre de chapitres et actions.
class _LigneSite extends StatelessWidget {
  const _LigneSite({
    required this.site,
    required this.occupe,
    required this.surOuvrir,
    required this.surDefinirPrincipal,
    required this.surRetirer,
    required this.surPasserEnLienSeul,
    required this.surEssayerDeLire,
  });

  final SiteDuTitre site;
  final bool occupe;
  final VoidCallback surOuvrir;
  final VoidCallback surDefinirPrincipal;
  final VoidCallback surRetirer;
  final VoidCallback surPasserEnLienSeul;
  final VoidCallback surEssayerDeLire;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    final lienSeul = site.estLienSeul;
    final role = site.estPrincipal
        ? Textes.sitePrincipal
        : Textes.siteSecondaire;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: espacementPetit),
      child: Padding(
        padding: const EdgeInsets.all(espacementPetit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              // Étoile pleine pour le principal : repérable d'un coup d'œil,
              // même sans lire la pastille. Un lien seul a l'icône du
              // navigateur : c'est là qu'il s'ouvre.
              leading: Icon(
                site.estPrincipal
                    ? Icons.star
                    : (lienSeul ? Icons.open_in_browser : Icons.link),
                color: site.estPrincipal ? couleurs.primary : null,
              ),
              title: Text(site.nomSite),
              subtitle: Text(
                lienSeul
                    ? '$role · ${Textes.lienSeul}\n'
                          '${Textes.explicationLigneLienSeul}'
                    : '$role · ${Textes.chapitresDuSite(site.nombreChapitres)}',
              ),
            ),
            // Boutons dans un Wrap : ils passent à la ligne sur téléphone au
            // lieu de déborder.
            Wrap(
              spacing: espacementPetit,
              runSpacing: espacementPetit / 2,
              children: <Widget>[
                TextButton.icon(
                  onPressed: surOuvrir,
                  icon: Icon(
                    lienSeul ? Icons.open_in_browser : Icons.open_in_new,
                  ),
                  label: Text(
                    lienSeul
                        ? Textes.ouvrirDansNavigateur
                        : Textes.ouvrirCeSite,
                  ),
                ),
                if (lienSeul)
                  // Pas de « Définir comme site principal » : l'application
                  // ne sait pas lire ce site, il ne peut pas fournir la fiche.
                  TextButton.icon(
                    onPressed: occupe ? null : surEssayerDeLire,
                    icon: const Icon(Icons.refresh),
                    label: const Text(Textes.essayerDeLire),
                  )
                else if (!site.estPrincipal) ...<Widget>[
                  TextButton.icon(
                    onPressed: occupe ? null : surDefinirPrincipal,
                    icon: const Icon(Icons.star_outline),
                    label: const Text(Textes.definirSitePrincipal),
                  ),
                  TextButton.icon(
                    onPressed: occupe ? null : surPasserEnLienSeul,
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text(Textes.passerEnLienSeul),
                  ),
                ],
                if (!site.estPrincipal) ...<Widget>[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: couleurs.error,
                    ),
                    onPressed: occupe ? null : surRetirer,
                    icon: const Icon(Icons.link_off),
                    label: const Text(Textes.retirerSite),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialogue « Ajouter un autre site » : adresse du même titre sur l'autre
/// site. Renvoie le message de confirmation à afficher, ou `null` si le
/// client annule. Un refus (site non configuré, illisible, adresse déjà
/// liée) reste affiché dans la boîte, avec le bouton d'export du rapport
/// d'erreur quand le site est en cause ; si le site lui-même est en cause,
/// la boîte propose aussi « Pourquoi ce site n'est pas lisible ? » (T3) et
/// « Ajouter quand même comme simple lien » (T4).
///
/// Reçoit l'[EtatTitre] directement : le dialogue est construit au-dessus
/// de la route de la fiche, hors de portée de son fournisseur.
class DialogueAjoutSite extends StatefulWidget {
  /// Crée le dialogue pour [etat].
  const DialogueAjoutSite({super.key, required this.etat});

  /// État de la fiche affichée.
  final EtatTitre etat;

  @override
  State<DialogueAjoutSite> createState() => _EtatDialogueAjoutSite();
}

class _EtatDialogueAjoutSite extends State<DialogueAjoutSite> {
  final TextEditingController _url = TextEditingController();
  bool _enCours = false;
  DescriptionErreur? _erreur;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Adresse refusée par le dernier essai : le diagnostic et le lien seul
  /// portent sur elle, même si le client a modifié le champ depuis.
  String _urlRefusee = '';

  Future<void> _ajouter() async {
    await _executer(
      () => widget.etat.ajouterSite(_url.text),
      (nombre) => Textes.siteAjouteAuTitre(nombre),
    );
  }

  Future<void> _ajouterCommeLienSeul() async {
    await _executer(
      () => widget.etat.ajouterLienSeul(_urlRefusee),
      (_) => Textes.lienSeulAjoute,
    );
  }

  /// Lance [action] ; en cas de réussite, ferme la boîte avec le message
  /// produit par [message], sinon garde l'erreur affichée.
  Future<void> _executer(
    Future<ResultatAction<int>> Function() action,
    String Function(int nombre) message,
  ) async {
    final url = _url.text.trim();
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await action();
    if (!mounted) return;
    final erreur = resultat.erreur;
    if (erreur == null) {
      Navigator.of(context).pop(message(resultat.donnee ?? 0));
      return;
    }
    // L'erreur reste dans la boîte : le client peut corriger l'adresse sans
    // tout ressaisir.
    setState(() {
      _enCours = false;
      _erreur = erreur;
      _urlRefusee = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final erreur = _erreur;
    // Propositions réservées aux refus dus au site lui-même (illisible,
    // injoignable, non configuré) : une adresse invalide ou déjà liée ne
    // deviendrait pas meilleure en simple lien.
    final siteEnCause =
        erreur != null && EtatTitre.peutAjouterCommeLienSeul(erreur);
    return AlertDialog(
      title: const Text(Textes.ajouterAutreSite),
      // Largeur bornée : un champ d'adresse immense se lit mal sur grand
      // écran ; sur téléphone, le dialogue prend la place disponible.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(Textes.explicationAjoutSite(widget.etat.titre?.nom ?? '')),
              const SizedBox(height: espacementMoyen),
              TextField(
                controller: _url,
                enabled: !_enCours,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: Textes.champUrlAutreSite,
                  hintText: Textes.aideUrlTitre,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _enCours ? null : (_) => _ajouter(),
              ),
              if (_enCours) ...<Widget>[
                const SizedBox(height: espacementPetit),
                const LinearProgressIndicator(),
                const SizedBox(height: espacementPetit),
                const Text(Textes.ajoutSiteEnCours),
              ],
              if (erreur != null) ...<Widget>[
                const SizedBox(height: espacementPetit),
                Text(
                  Textes.messageErreur(erreur),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: espacementPetit),
                BoutonRapportErreur(
                  erreur: erreur,
                  action: Textes.actionRapportAjoutSiteAuTitre,
                ),
                if (siteEnCause && !_enCours) ...<Widget>[
                  const SizedBox(height: espacementPetit),
                  SectionDiagnosticSite(
                    // La clé change avec l'adresse : un nouveau refus
                    // efface le diagnostic de l'adresse précédente.
                    key: ValueKey<String>(_urlRefusee),
                    diagnostiquer: () =>
                        widget.etat.diagnostiquerSite(_urlRefusee),
                  ),
                  const Divider(height: espacementMoyen),
                  const Text(Textes.explicationAjoutLienSeul),
                  const SizedBox(height: espacementPetit),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: _ajouterCommeLienSeul,
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text(Textes.ajouterCommeLienSeul),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          onPressed: _enCours ? null : _ajouter,
          child: const Text(Textes.ajouter),
        ),
      ],
    );
  }
}
