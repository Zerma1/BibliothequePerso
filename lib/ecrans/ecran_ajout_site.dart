/// Écran d'ajout d'un site : adresse, nom, langue et type.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/description_erreur.dart';
import '../etat/etat_sources.dart';
import '../modeles/source.dart';
import '../widgets/bouton_rapport_erreur.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/section_diagnostic_site.dart';
import '../widgets/textes.dart';

/// Formulaire d'ajout d'un site par son adresse.
///
/// Le type est détecté automatiquement ; le client peut le corriger si la
/// détection se trompe (PLAYBOOK.md section 6, étape 2 bis). En cas de
/// réussite, l'écran se ferme et renvoie le message de confirmation.
///
/// Tâche T3 : aide « Critères de lecture », réglages avancés (sélecteurs
/// CSS) pour un site générique, et diagnostic « Pourquoi ce site n'est pas
/// lisible ? » après un refus.
class EcranAjoutSite extends StatefulWidget {
  /// Crée l'écran.
  const EcranAjoutSite({super.key});

  @override
  State<EcranAjoutSite> createState() => _EtatEcranAjoutSite();
}

class _EtatEcranAjoutSite extends State<EcranAjoutSite> {
  final GlobalKey<FormState> _cleFormulaire = GlobalKey<FormState>();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _langue = TextEditingController();

  /// Un champ par réglage avancé d'un site générique (sélecteurs CSS).
  final Map<String, TextEditingController> _reglages =
      <String, TextEditingController>{
        for (final cle in EtatSources.clesReglagesGeneriques)
          cle: TextEditingController(),
      };
  TypeSource? _typeForce;
  String _nomPropose = '';
  String? _messageErreur;

  /// Erreur du dernier essai, gardée pour le rapport d'erreur exportable.
  DescriptionErreur? _erreur;

  /// Adresse refusée par le dernier essai (objet du diagnostic).
  String _urlRefusee = '';

  @override
  void dispose() {
    _url.dispose();
    _nom.dispose();
    _langue.dispose();
    for (final controleur in _reglages.values) {
      controleur.dispose();
    }
    super.dispose();
  }

  /// `true` si les réglages avancés peuvent servir : type générique choisi,
  /// ou détection automatique (qui peut conclure à un site générique).
  bool get _reglagesUtiles =>
      _typeForce == null || _typeForce == TypeSource.generique;

  String? _validerUrl(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return Textes.champObligatoire;
    }
    // La validation complète (schéma, domaine) est faite par le service, qui
    // renvoie un message précis affiché sous le formulaire.
    return null;
  }

  String? _validerLangue(String? valeur) {
    // Variantes régionales acceptées (« pt-br ») : même règle que le service.
    return EtatSources.languesValides(valeur ?? '')
        ? null
        : Textes.erreurLangue;
  }

  Future<void> _ajouter() async {
    final formulaire = _cleFormulaire.currentState;
    if (formulaire == null || !formulaire.validate()) {
      return;
    }
    setState(() {
      _messageErreur = null;
      _erreur = null;
    });
    final url = _url.text.trim();
    final resultat = await context.read<EtatSources>().ajouterSite(
      _url.text,
      nom: _nom.text,
      langueParDefaut: _langue.text,
      typeForce: _typeForce,
      reglagesGeneriques: _reglagesUtiles
          ? <String, String>{
              for (final entree in _reglages.entries)
                entree.key: entree.value.text,
            }
          : const <String, String>{},
    );
    if (!mounted) {
      return;
    }
    final erreur = resultat.erreur;
    final ajout = resultat.donnee;
    if (erreur != null || ajout == null) {
      setState(() {
        _erreur = erreur;
        _urlRefusee = url;
        _messageErreur = erreur == null
            ? Textes.erreurInattendue
            : Textes.messageErreur(erreur);
      });
      return;
    }
    Navigator.of(context).pop(
      ajout.etaitDejaConfigure
          ? Textes.siteDejaConfigure(ajout.source.nom)
          : Textes.siteAjoute(ajout.source.nom),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<EtatSources>();
    final enCours = etat.estEnAjout;
    final messageErreur = _messageErreur;
    return Scaffold(
      appBar: AppBar(title: const Text(Textes.boutonAjouterSite)),
      // Formulaire centré et de largeur bornée : lisible sur un écran large,
      // pleine largeur sur un téléphone.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(espacementMoyen),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: largeurMaxFormulaire),
            child: Form(
              key: _cleFormulaire,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    controller: _url,
                    enabled: !enCours,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: Textes.champUrlSite,
                      helperText: Textes.aideUrlSite,
                      border: OutlineInputBorder(),
                    ),
                    validator: _validerUrl,
                    onChanged: (valeur) =>
                        setState(() => _nomPropose = etat.proposerNom(valeur)),
                  ),
                  // Aide repliée par défaut, juste sous l'adresse : le client
                  // la trouve au moment où il se demande quoi coller, sans
                  // qu'elle allonge le formulaire.
                  const ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_outline),
                    title: Text(Textes.criteresLecture),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: EdgeInsets.only(bottom: espacementPetit),
                    children: <Widget>[Text(Textes.aideCriteresLecture)],
                  ),
                  const SizedBox(height: espacementPetit),
                  TextFormField(
                    controller: _nom,
                    enabled: !enCours,
                    decoration: InputDecoration(
                      labelText: Textes.champNomSite,
                      helperText: _nomPropose.isEmpty
                          ? Textes.aideNomSite
                          : Textes.nomPropose(_nomPropose),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: espacementMoyen),
                  TextFormField(
                    controller: _langue,
                    enabled: !enCours,
                    decoration: const InputDecoration(
                      labelText: Textes.champLangue,
                      helperText: Textes.aideLangue,
                      border: OutlineInputBorder(),
                    ),
                    validator: _validerLangue,
                  ),
                  const SizedBox(height: espacementPetit),
                  // isExpanded : le menu prend la largeur du formulaire au lieu
                  // de celle du libellé le plus long (ex. « Scan-Manga (lecture
                  // sur le site) »), qui débordait sur un écran étroit ; les
                  // libellés trop longs sont alors tronqués avec des points.
                  DropdownButtonFormField<TypeSource?>(
                    initialValue: _typeForce,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: Textes.champTypeSite,
                      helperText: Textes.aideTypeSite,
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<TypeSource?>>[
                      const DropdownMenuItem<TypeSource?>(
                        child: Text(Textes.typeAutomatique),
                      ),
                      for (final type in TypeSource.values)
                        DropdownMenuItem<TypeSource?>(
                          value: type,
                          child: Text(
                            Textes.libelleTypeSource(type),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: enCours
                        ? null
                        : (type) => setState(() => _typeForce = type),
                  ),
                  // Réglages repliés : la plupart des sites se lisent sans
                  // eux (heuristiques) ; masqués pour un type qui ne s'en
                  // sert pas.
                  if (_reglagesUtiles)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tune),
                      // Champs gardés même repliés : leur validation (motif
                      // invalide) s'applique toujours à l'envoi.
                      maintainState: true,
                      title: const Text(Textes.reglagesAvancesSelecteurs),
                      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(Textes.explicationReglagesSelecteurs),
                        for (final cle in EtatSources.clesReglagesGeneriques)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: espacementPetit,
                            ),
                            child: TextFormField(
                              key: ValueKey<String>('reglage_$cle'),
                              controller: _reglages[cle],
                              enabled: !enCours,
                              decoration: InputDecoration(
                                labelText: Textes.libelleReglageSelecteur(cle),
                                helperText: cle,
                                border: const OutlineInputBorder(),
                              ),
                              validator: cle == EtatSources.cleMotifNumero
                                  ? (valeur) =>
                                        EtatSources.motifValide(valeur ?? '')
                                        ? null
                                        : Textes.erreurMotifInvalide
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: espacementGrand),
                  if (enCours) ...<Widget>[
                    const LinearProgressIndicator(),
                    const SizedBox(height: espacementPetit),
                    const Text(
                      Textes.detectionEnCours,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: espacementMoyen),
                  ],
                  if (messageErreur != null) ...<Widget>[
                    Text(
                      messageErreur,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    // Le rapport aide à faire diagnostiquer un site que la
                    // détection ne sait pas lire (étape 6).
                    if (_erreur != null && !enCours) ...<Widget>[
                      const SizedBox(height: espacementPetit),
                      BoutonRapportErreur(
                        erreur: _erreur!,
                        action: Textes.actionRapportAjoutSite,
                      ),
                      // Seulement quand le site est en cause : une adresse
                      // vide n'a rien à analyser.
                      if (_erreur!.nature == NatureErreur.site ||
                          _erreur!.nature == NatureErreur.refus) ...<Widget>[
                        const SizedBox(height: espacementPetit),
                        SectionDiagnosticSite(
                          key: ValueKey<String>(_urlRefusee),
                          diagnostiquer: () =>
                              etat.diagnostiquerSite(_urlRefusee),
                        ),
                      ],
                    ],
                    const SizedBox(height: espacementMoyen),
                  ],
                  FilledButton.icon(
                    onPressed: enCours ? null : _ajouter,
                    icon: const Icon(Icons.add_link),
                    label: const Text(Textes.ajouter),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
