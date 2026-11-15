/// Écran d'ajout d'un site : adresse, nom, langue et type.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../etat/etat_sources.dart';
import '../modeles/source.dart';
import '../widgets/constantes_interface.dart';
import '../widgets/textes.dart';

/// Formulaire d'ajout d'un site par son adresse.
///
/// Le type est détecté automatiquement ; le client peut le corriger si la
/// détection se trompe (PLAYBOOK.md section 6, étape 2 bis). En cas de
/// réussite, l'écran se ferme et renvoie le message de confirmation.
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
  TypeSource? _typeForce;
  String _nomPropose = '';
  String? _messageErreur;

  @override
  void dispose() {
    _url.dispose();
    _nom.dispose();
    _langue.dispose();
    super.dispose();
  }

  String? _validerUrl(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return Textes.champObligatoire;
    }
    // La validation complète (schéma, domaine) est faite par le service, qui
    // renvoie un message précis affiché sous le formulaire.
    return null;
  }

  String? _validerLangue(String? valeur) {
    final langue = valeur?.trim() ?? '';
    if (langue.isEmpty) {
      return null;
    }
    final estCode =
        langue.length == longueurCodeLangue &&
        RegExp(r'^[a-zA-Z]+$').hasMatch(langue);
    return estCode ? null : Textes.erreurLangue;
  }

  Future<void> _ajouter() async {
    final formulaire = _cleFormulaire.currentState;
    if (formulaire == null || !formulaire.validate()) {
      return;
    }
    setState(() => _messageErreur = null);
    final resultat = await context.read<EtatSources>().ajouterSite(
      _url.text,
      nom: _nom.text,
      langueParDefaut: _langue.text,
      typeForce: _typeForce,
    );
    if (!mounted) {
      return;
    }
    final erreur = resultat.erreur;
    final ajout = resultat.donnee;
    if (erreur != null || ajout == null) {
      setState(
        () => _messageErreur = erreur == null
            ? Textes.erreurInattendue
            : Textes.messageErreur(erreur),
      );
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
                    onChanged: (valeur) => setState(
                      () => _nomPropose = etat.proposerNom(valeur),
                    ),
                  ),
                  const SizedBox(height: espacementMoyen),
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
                    maxLength: longueurCodeLangue,
                    decoration: const InputDecoration(
                      labelText: Textes.champLangue,
                      helperText: Textes.aideLangue,
                      border: OutlineInputBorder(),
                    ),
                    validator: _validerLangue,
                  ),
                  const SizedBox(height: espacementPetit),
                  DropdownButtonFormField<TypeSource?>(
                    initialValue: _typeForce,
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
                          child: Text(Textes.libelleTypeSource(type)),
                        ),
                    ],
                    onChanged: enCours
                        ? null
                        : (type) => setState(() => _typeForce = type),
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
