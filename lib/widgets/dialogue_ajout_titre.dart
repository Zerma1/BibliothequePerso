/// Boîte de dialogue « Ajouter un titre » : adresse et listes.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_bibliotheque.dart';
import '../etat/etat_sources.dart';
import '../modeles/titre.dart';
import 'bouton_rapport_erreur.dart';
import 'constantes_interface.dart';
import 'textes.dart';

/// Issue du dialogue d'ajout d'un titre.
class IssueAjoutTitre {
  /// Crée l'issue.
  const IssueAjoutTitre(this.message, {this.idTitreAOuvrir});

  /// Message de confirmation à afficher.
  final String message;

  /// Titre dont la fiche est à ouvrir : titre déjà présent dans la
  /// bibliothèque (adresse d'un de ses sites, étape 8), sinon `null`.
  final int? idTitreAOuvrir;
}

/// Ouvre la boîte de dialogue d'ajout d'un titre.
///
/// Renvoie le message de confirmation à afficher (et le titre à ouvrir s'il
/// était déjà présent), ou `null` si le client a annulé.
Future<IssueAjoutTitre?> afficherDialogueAjoutTitre(BuildContext context) {
  return showDialog<IssueAjoutTitre>(
    context: context,
    // Pendant la lecture du site, un appui à côté ne doit pas fermer la
    // boîte : le client perdrait le résultat de l'ajout.
    barrierDismissible: false,
    builder: (_) => const DialogueAjoutTitre(),
  );
}

/// Formulaire d'ajout d'un titre par son adresse, ou par une recherche sur
/// MangaDex, avec le choix des listes (Suivis cochée par défaut, Favoris
/// proposée mais décochée : retour X3 du client).
class DialogueAjoutTitre extends StatefulWidget {
  /// Crée le dialogue.
  const DialogueAjoutTitre({super.key});

  @override
  State<DialogueAjoutTitre> createState() => _EtatDialogueAjoutTitre();
}

class _EtatDialogueAjoutTitre extends State<DialogueAjoutTitre> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _requete = TextEditingController();

  /// `true` pour le mode « Rechercher » (sur MangaDex), `false` pour
  /// « Adresse ».
  bool _modeRecherche = false;

  /// Résultats de la dernière recherche, `null` avant toute recherche.
  List<Titre>? _resultats;
  bool _rechercheEnCours = false;

  /// Adresse du résultat choisi, ajoutée par « Ajouter ».
  String? _urlChoisie;

  /// Listes choisies par le client ; `null` tant qu'il n'a rien touché : on
  /// suit alors les listes par défaut, même si elles arrivent après
  /// l'ouverture du dialogue.
  Set<int>? _idsListesChoisies;
  String? _messageErreur;

  /// Erreur du dernier essai, gardée pour le rapport d'erreur exportable.
  DescriptionErreur? _erreur;

  @override
  void initState() {
    super.initState();
    final etat = context.read<EtatBibliotheque>();
    if (!etat.estCharge && !etat.estEnChargement) {
      // Listes jamais chargées (chargement initial en erreur…) : on les
      // demande, sans notifier pendant la construction du dialogue.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          etat.charger();
        }
      });
    }
  }

  Set<int> _idsListes(EtatBibliotheque etat) =>
      _idsListesChoisies ?? etat.idsListesParDefaut;

  void _cocher(EtatBibliotheque etat, int idListe, bool coche) {
    setState(() {
      final choisies = _idsListesChoisies ??= <int>{...etat.idsListesParDefaut};
      if (coche) {
        choisies.add(idListe);
      } else {
        choisies.remove(idListe);
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _requete.dispose();
    super.dispose();
  }

  /// Lance la recherche sur MangaDex (une requête au site).
  Future<void> _rechercher() async {
    final etat = context.read<EtatBibliotheque>();
    setState(() {
      _rechercheEnCours = true;
      _messageErreur = null;
      _erreur = null;
      _urlChoisie = null;
    });
    final resultat = await etat.rechercherSurMangaDex(_requete.text);
    if (!mounted) return;
    setState(() {
      _rechercheEnCours = false;
      _resultats = resultat.donnee;
      final erreur = resultat.erreur;
      if (erreur != null) {
        _erreur = erreur;
        _messageErreur = Textes.messageErreur(erreur);
      }
    });
  }

  Future<void> _ajouter() async {
    final etat = context.read<EtatBibliotheque>();
    final etatSources = context.read<EtatSources>();
    setState(() {
      _messageErreur = null;
      _erreur = null;
    });
    final url = _modeRecherche ? (_urlChoisie ?? '') : _url.text;
    final resultat = await etat.ajouterTitre(url, _idsListes(etat));
    // MangaDex est ajouté automatiquement à la première adresse collée, même
    // si la lecture du titre échoue ensuite : l'onglet Sources doit le
    // montrer.
    if (resultat.erreur?.nature != NatureErreur.adresseVide) {
      unawaited(etatSources.charger());
    }
    if (!mounted) {
      return;
    }
    final erreur = resultat.erreur;
    final ajout = resultat.donnee;
    if (erreur != null || ajout == null) {
      // L'erreur reste dans la boîte : le client peut corriger l'adresse sans
      // tout ressaisir.
      setState(() {
        _erreur = erreur;
        _messageErreur = erreur == null
            ? Textes.erreurInattendue
            : Textes.messageErreur(erreur);
      });
      return;
    }
    if (ajout.estDejaPresent) {
      // Adresse d'un site secondaire d'un titre existant : rien n'a été
      // créé, on emmène le client sur la fiche de ce titre.
      Navigator.of(context).pop(
        IssueAjoutTitre(
          Textes.titreDejaPresent,
          idTitreAOuvrir: ajout.titre.id,
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      IssueAjoutTitre(
        ajout.estEnAttente
            ? Textes.titreAjouteEnAttente(ajout.titre.nom)
            : Textes.titreAjoute(
                ajout.titre.nom,
                ajout.nombreNouveauxChapitres,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatBibliotheque>();
    final enCours = etat.estEnAjout;
    final messageErreur = _messageErreur;
    return AlertDialog(
      title: const Text(Textes.boutonAjouterTitre),
      // Largeur bornée : sur grand écran, un champ d'URL immense est
      // difficile à lire ; sur téléphone, le dialogue prend la place
      // disponible.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Deux façons d'ajouter : coller une adresse (tous les sites
              // configurés) ou chercher par nom sur MangaDex.
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.link),
                    label: Text(Textes.modeAdresse),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.search),
                    label: Text(Textes.modeRechercher),
                  ),
                ],
                selected: <bool>{_modeRecherche},
                onSelectionChanged: enCours
                    ? null
                    : (choix) => setState(() {
                        _modeRecherche = choix.first;
                        _messageErreur = null;
                        _erreur = null;
                      }),
              ),
              const SizedBox(height: espacementMoyen),
              if (_modeRecherche)
                ..._recherche(enCours)
              else
                TextField(
                  controller: _url,
                  enabled: !enCours,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: Textes.champUrlTitre,
                    hintText: Textes.aideUrlTitre,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: enCours ? null : (_) => _ajouter(),
                ),
              const SizedBox(height: espacementMoyen),
              const Text(Textes.rangerDans),
              if (etat.listes.isEmpty && etat.estEnChargement)
                const LinearProgressIndicator(),
              // « En attente » n'est pas proposée : l'application la tient
              // seule (un titre sans chapitre dans vos langues y entre).
              for (final liste in etat.listes)
                if (liste.id != null && !etat.estListeAutomatique(liste))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(liste.nom),
                    value: _idsListes(etat).contains(liste.id),
                    onChanged: enCours
                        ? null
                        : (coche) => _cocher(etat, liste.id!, coche ?? false),
                  ),
              if (enCours) ...<Widget>[
                const SizedBox(height: espacementPetit),
                const LinearProgressIndicator(),
                const SizedBox(height: espacementPetit),
                const Text(Textes.ajoutTitreEnCours),
              ],
              if (messageErreur != null) ...<Widget>[
                const SizedBox(height: espacementPetit),
                Text(
                  messageErreur,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (_erreur != null && !enCours) ...<Widget>[
                  const SizedBox(height: espacementPetit),
                  BoutonRapportErreur(
                    erreur: _erreur!,
                    action: Textes.actionRapportAjoutTitre,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: enCours ? null : () => Navigator.of(context).pop(),
          child: const Text(Textes.annuler),
        ),
        FilledButton(
          // En mode recherche, il faut d'abord choisir un résultat.
          onPressed: enCours || (_modeRecherche && _urlChoisie == null)
              ? null
              : _ajouter,
          child: const Text(Textes.ajouter),
        ),
      ],
    );
  }

  /// Champ de recherche sur MangaDex et résultats à choisir.
  List<Widget> _recherche(bool enCours) {
    final resultats = _resultats;
    final occupe = enCours || _rechercheEnCours;
    return <Widget>[
      TextField(
        controller: _requete,
        enabled: !occupe,
        autofocus: true,
        decoration: InputDecoration(
          labelText: Textes.champRechercheMangaDex,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: Textes.rechercher,
            icon: const Icon(Icons.search),
            onPressed: occupe ? null : _rechercher,
          ),
        ),
        onSubmitted: occupe ? null : (_) => _rechercher(),
      ),
      if (_rechercheEnCours) ...<Widget>[
        const SizedBox(height: espacementPetit),
        const LinearProgressIndicator(),
      ],
      if (resultats != null && !_rechercheEnCours) ...<Widget>[
        const SizedBox(height: espacementPetit),
        if (resultats.isEmpty)
          const Text(Textes.aucunResultatMangaDex)
        else ...<Widget>[
          Text(
            Textes.aideRechercheMangaDex,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // Résultats dans le défilement du dialogue (une vingtaine au
          // plus) : pas de liste imbriquée à hauteur fixe.
          for (final titre in resultats)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              selected: _urlChoisie == titre.urlTitre,
              leading: Icon(
                _urlChoisie == titre.urlTitre
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(titre.nom),
              subtitle: titre.auteur == null ? null : Text(titre.auteur!),
              onTap: enCours
                  ? null
                  : () => setState(() => _urlChoisie = titre.urlTitre),
            ),
        ],
      ],
    ];
  }
}
