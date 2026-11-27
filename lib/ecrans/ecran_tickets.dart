/// Écran « Mes tickets » (version 0.4.0) : tickets GitHub créés depuis
/// l'application, leur avancée et leurs commentaires.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_tickets.dart';
import '../modeles/ticket.dart';
import '../services/service_tickets.dart' show CommentaireTicketGithub;
import '../widgets/constantes_interface.dart';
import '../widgets/dialogues_tickets.dart';
import '../widgets/messages.dart';
import '../widgets/textes.dart';
import '../widgets/vues_etat.dart';

/// Liste des tickets suivis, avec « Actualiser » et « Nouveau ticket ».
///
/// À l'ouverture, la liste est lue en base puis actualisée sur GitHub (le
/// service ignore une actualisation trop rapprochée de la précédente).
class EcranTickets extends StatefulWidget {
  /// Crée l'écran. [ouvrirLien] remplace le navigateur dans les tests.
  const EcranTickets({super.key, this.ouvrirLien = ouvrirDansNavigateur});

  /// Ouverture des pages GitHub.
  final OuvreurLien ouvrirLien;

  @override
  State<EcranTickets> createState() => _EtatEcranTickets();
}

class _EtatEcranTickets extends State<EcranTickets> {
  @override
  void initState() {
    super.initState();
    // Après la première image : l'état notifie pendant le chargement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<EtatTickets>().ouvrir();
    });
  }

  Future<void> _creer(BuildContext context) async {
    final etat = context.read<EtatTickets>();
    final saisie = await showDialog<SaisieTicket>(
      context: context,
      builder: (_) => const DialogueNouveauTicket(),
    );
    if (saisie == null || !context.mounted) return;
    final resultat = await etat.preparerTicket(
      type: saisie.type,
      titre: saisie.titre,
      description: saisie.description,
    );
    if (!context.mounted) return;
    final prepare = resultat.donnee;
    if (prepare == null) {
      afficherResultat(context, resultat);
      return;
    }
    final ouvert = await ouvrirPageGithub(
      context,
      prepare.urlCreation,
      ouvrir: widget.ouvrirLien,
    );
    if (ouvert && context.mounted) {
      afficherMessage(context, Textes.ticketPrepare);
    }
  }

  void _ouvrirDetail(BuildContext context, Ticket ticket) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EcranDetailTicket(ticket: ticket, ouvrirLien: widget.ouvrirLien),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatTickets>();
    final erreur = etat.erreur;
    final Widget contenu;
    if (erreur != null && etat.tickets.isEmpty) {
      contenu = VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: etat.ouvrir,
      );
    } else if (!etat.estCharge) {
      contenu = const VueChargement();
    } else if (etat.tickets.isEmpty) {
      contenu = const VueVide(
        message: Textes.aucunTicket,
        icone: Icons.forum_outlined,
      );
    } else {
      contenu = ListView.separated(
        // Marge basse : le dernier ticket n'est pas caché par le bouton
        // flottant.
        padding: const EdgeInsets.only(
          top: espacementPetit,
          bottom: margeBasBoutonFlottant,
        ),
        itemCount: etat.tickets.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final ticket = etat.tickets[index];
          return _LigneTicket(
            ticket: ticket,
            surAppui: () => _ouvrirDetail(context, ticket),
          );
        },
      );
    }
    final message = etat.messageActualisation;
    return Scaffold(
      appBar: AppBar(
        title: const Text(Textes.mesTickets),
        actions: <Widget>[
          IconButton(
            tooltip: Textes.actualiser,
            onPressed: etat.estEnActualisation
                ? null
                : () => etat.actualiser(demandeParUtilisateur: true),
            icon: etat.estEnActualisation
                ? SizedBox.square(
                    dimension: IconTheme.of(context).size,
                    child: const CircularProgressIndicator(
                      strokeWidth: epaisseurIndicateurBouton,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _creer(context),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text(Textes.nouveauTicket),
      ),
      // Colonne centrée de largeur plafonnée : sur ordinateur, des lignes
      // étalées sur toute la fenêtre seraient difficiles à suivre ; sur
      // téléphone, la liste prend toute la largeur.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxLecture),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Erreur d'actualisation au-dessus de la liste, sans la
              // masquer : les derniers relevés restent consultables.
              if (message != null) _BandeauActualisation(message: message),
              Expanded(child: contenu),
            ],
          ),
        ),
      ),
    );
  }
}

/// Message d'une actualisation échouée (limite GitHub, réseau).
class _BandeauActualisation extends StatelessWidget {
  const _BandeauActualisation({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return Card(
      color: couleurs.errorContainer,
      margin: const EdgeInsets.all(espacementPetit),
      child: Padding(
        padding: const EdgeInsets.all(espacementMoyen),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, color: couleurs.onErrorContainer),
            const SizedBox(width: espacementMoyen),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: couleurs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne de la liste : titre, type, état, commentaires, étiquettes et
/// marque « Nouveau ».
class _LigneTicket extends StatelessWidget {
  const _LigneTicket({required this.ticket, required this.surAppui});

  final Ticket ticket;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nombre = ticket.nombreCommentaires;
    final details = <String>[
      Textes.nomTypeTicket(ticket.type),
      Textes.etatTicket(ticket),
      if (nombre != null) Textes.nombreCommentaires(nombre),
    ].join(' · ');
    return ListTile(
      onTap: surAppui,
      leading: Icon(_iconeEtat(ticket), color: _couleurEtat(ticket, theme)),
      title: Text(ticket.titre, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(details),
          if (ticket.etiquettes.isNotEmpty) ...<Widget>[
            const SizedBox(height: espacementPetit / 2),
            _Etiquettes(etiquettes: ticket.etiquettes),
          ],
        ],
      ),
      // Marque « Nouveau » à droite, comme les badges des Mises à jour.
      trailing: ticket.aDesNouveautes
          ? Badge(
              label: const Text(Textes.ticketNouveau),
              backgroundColor: theme.colorScheme.primary,
              textColor: theme.colorScheme.onPrimary,
            )
          : null,
    );
  }
}

IconData _iconeEtat(Ticket ticket) {
  if (!ticket.estRetrouve) return Icons.hourglass_top_outlined;
  return switch (ticket.etat) {
    EtatTicket.ferme => switch (ticket.raisonFermeture) {
      RaisonFermetureTicket.nonRetenu => Icons.do_not_disturb_on_outlined,
      _ => Icons.check_circle_outline,
    },
    _ => Icons.radio_button_unchecked,
  };
}

Color _couleurEtat(Ticket ticket, ThemeData theme) {
  if (!ticket.estRetrouve) return theme.colorScheme.outline;
  return ticket.etat == EtatTicket.ferme
      ? theme.colorScheme.tertiary
      : theme.colorScheme.primary;
}

/// Étiquettes GitHub d'un ticket, en petites puces qui passent à la ligne.
class _Etiquettes extends StatelessWidget {
  const _Etiquettes({required this.etiquettes});

  final List<String> etiquettes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: espacementPetit / 2,
      runSpacing: espacementPetit / 2,
      children: <Widget>[
        for (final etiquette in etiquettes)
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(espacementPetit),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: espacementPetit,
                vertical: espacementPetit / 4,
              ),
              child: Text(
                etiquette,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Détail d'un ticket : informations, actions (GitHub, retrait) et
/// commentaires.
class EcranDetailTicket extends StatefulWidget {
  /// Crée l'écran du [ticket]. [ouvrirLien] remplace le navigateur dans les
  /// tests.
  const EcranDetailTicket({
    super.key,
    required this.ticket,
    this.ouvrirLien = ouvrirDansNavigateur,
  });

  /// Ticket ouvert (sa version à jour est relue dans [EtatTickets]).
  final Ticket ticket;

  /// Ouverture des pages GitHub.
  final OuvreurLien ouvrirLien;

  @override
  State<EcranDetailTicket> createState() => _EtatEcranDetailTicket();
}

class _EtatEcranDetailTicket extends State<EcranDetailTicket> {
  List<CommentaireTicketGithub>? _commentaires;
  DescriptionErreur? _erreur;
  bool _estEnChargement = false;

  @override
  void initState() {
    super.initState();
    if (widget.ticket.estRetrouve) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chargerCommentaires();
      });
    }
  }

  Future<void> _chargerCommentaires() async {
    setState(() {
      _estEnChargement = true;
      _erreur = null;
    });
    final resultat = await context.read<EtatTickets>().chargerCommentaires(
      _ticketAJour(context.read<EtatTickets>()),
    );
    if (!mounted) return;
    setState(() {
      _estEnChargement = false;
      _commentaires = resultat.donnee;
      _erreur = resultat.erreur;
    });
  }

  /// Version la plus récente du ticket dans la liste de l'état.
  Ticket _ticketAJour(EtatTickets etat) {
    for (final ticket in etat.tickets) {
      if (ticket.id == widget.ticket.id) return ticket;
    }
    return widget.ticket;
  }

  Future<void> _retirer(BuildContext context, Ticket ticket) async {
    final etat = context.read<EtatTickets>();
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text(Textes.retirerDeMaListe),
        content: const Text(Textes.confirmationRetraitTicket),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text(Textes.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text(Textes.retirer),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final resultat = await etat.retirerTicket(ticket);
    if (!context.mounted) return;
    if (resultat.estReussi) {
      // Le message est affiché par l'écran de la liste, qui reste visible.
      final messager = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(Textes.ticketRetire)));
    } else {
      afficherResultat(context, resultat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatTickets>();
    final ticket = _ticketAJour(etat);
    final theme = Theme.of(context);
    final urlPage = etat.urlPage(ticket);
    final urlCreation = etat.urlCreation(ticket);
    final numero = ticket.numero;
    final nombre = ticket.nombreCommentaires;
    return Scaffold(
      appBar: AppBar(title: const Text(Textes.mesTickets)),
      // Même colonne centrée que la liste ; tout défile ensemble pour
      // qu'un long commentaire reste lisible sur téléphone.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: largeurMaxLecture),
          child: ListView(
            padding: const EdgeInsets.all(espacementMoyen),
            children: <Widget>[
              SelectableText(ticket.titre, style: theme.textTheme.titleLarge),
              const SizedBox(height: espacementPetit),
              Text(
                <String>[
                  Textes.nomTypeTicket(ticket.type),
                  Textes.etatTicket(ticket),
                  if (numero != null) Textes.numeroTicket(numero),
                  Textes.ticketCreeLe(ticket.dateCreation),
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              if (ticket.etiquettes.isNotEmpty) ...<Widget>[
                const SizedBox(height: espacementPetit),
                _Etiquettes(etiquettes: ticket.etiquettes),
              ],
              if (!ticket.estRetrouve) ...<Widget>[
                const SizedBox(height: espacementMoyen),
                Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.all(espacementMoyen),
                    child: Text(
                      urlCreation != null
                          ? Textes.ticketEnAttente
                          : '${Textes.ticketEnAttente}\n'
                                '${Textes.ticketEnAttenteSansPage}',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: espacementMoyen),
              // Boutons côte à côte sur ordinateur, les uns sous les autres
              // sur un téléphone étroit.
              Wrap(
                spacing: espacementPetit,
                runSpacing: espacementPetit,
                children: <Widget>[
                  if (urlPage != null)
                    FilledButton.tonalIcon(
                      onPressed: () => ouvrirPageGithub(
                        context,
                        urlPage,
                        ouvrir: widget.ouvrirLien,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(Textes.voirSurGithub),
                    ),
                  // LIMITE : la page de création n'est connue que pour un
                  // ticket préparé pendant cette session (voir EtatTickets).
                  if (urlPage == null && urlCreation != null)
                    FilledButton.tonalIcon(
                      onPressed: () => ouvrirPageGithub(
                        context,
                        urlCreation,
                        ouvrir: widget.ouvrirLien,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(Textes.rouvrirPageCreation),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _retirer(context, ticket),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text(Textes.retirerDeMaListe),
                  ),
                ],
              ),
              if (ticket.estRetrouve) ...<Widget>[
                const SizedBox(height: espacementGrand),
                Text(
                  nombre == null
                      ? Textes.commentaires
                      : '${Textes.commentaires} ($nombre)',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: espacementPetit),
                _contenuCommentaires(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _contenuCommentaires() {
    final erreur = _erreur;
    if (erreur != null) {
      return VueErreur(
        message: Textes.messageErreur(erreur),
        surReessayer: _chargerCommentaires,
      );
    }
    final commentaires = _commentaires;
    if (_estEnChargement || commentaires == null) {
      return const Padding(
        padding: EdgeInsets.all(espacementGrand),
        child: VueChargement(),
      );
    }
    if (commentaires.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: espacementMoyen),
        child: Text(Textes.aucunCommentaire),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final commentaire in commentaires)
          _CarteCommentaire(commentaire: commentaire),
      ],
    );
  }
}

/// Un commentaire GitHub : auteur, date et texte brut sélectionnable.
class _CarteCommentaire extends StatelessWidget {
  const _CarteCommentaire({required this.commentaire});

  final CommentaireTicketGithub commentaire;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: espacementPetit),
      child: Padding(
        padding: const EdgeInsets.all(espacementMoyen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              Textes.enteteCommentaire(commentaire.auteur, commentaire.date),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: espacementPetit),
            // Texte brut (Markdown non interprété) : rien n'est chargé
            // depuis le contenu d'un commentaire, et le client peut copier.
            SelectableText(commentaire.corps),
          ],
        ),
      ),
    );
  }
}
