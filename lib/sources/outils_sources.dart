/// Outils d'analyse communs à plusieurs adaptateurs de `lib/sources/` :
/// numéros de chapitre et dates affichées par les sites.
///
/// Ils vivaient dans `SourceMangaDex` et `SourceWebtoons` ; les rassembler
/// ici évite qu'un adaptateur (ou `OutilsWordPress`) dépende d'un autre
/// adaptateur. Le comportement est inchangé, sauf le refus des jours qui
/// n'existent pas dans le mois (31/02), qui débordaient sur le mois suivant.
library;

/// Fonctions d'analyse partagées par les adaptateurs de sites.
abstract final class OutilsSources {
  /// Mois abrégés ou complets (français et anglais, sans le point final) des
  /// dates affichées : « 13 nov. 2026 », « Dec 22, 2024 ».
  static const Map<String, int> _mois = <String, int>{
    'janv': 1,
    'janvier': 1,
    'jan': 1,
    'january': 1,
    'févr': 2,
    'fevr': 2,
    'février': 2,
    'feb': 2,
    'february': 2,
    'mars': 3,
    'mar': 3,
    'march': 3,
    'avr': 4,
    'avril': 4,
    'apr': 4,
    'april': 4,
    'mai': 5,
    'may': 5,
    'juin': 6,
    'jun': 6,
    'june': 6,
    'juil': 7,
    'juillet': 7,
    'jul': 7,
    'july': 7,
    'août': 8,
    'aout': 8,
    'aug': 8,
    'august': 8,
    'sept': 9,
    'septembre': 9,
    'sep': 9,
    'september': 9,
    'oct': 10,
    'octobre': 10,
    'october': 10,
    'nov': 11,
    'novembre': 11,
    'november': 11,
    'déc': 12,
    'dec': 12,
    'décembre': 12,
    'december': 12,
  };

  /// Convertit un numéro de chapitre écrit en texte en double.
  ///
  /// `null` ou vide (oneshot) → 0. On lit le premier nombre trouvé
  /// (« 10.5 », « 12a » → 12, « 10,5 » → 10.5) et 0 si aucun.
  ///
  /// `double.tryParse` accepte aussi « NaN », « Infinity » et « 1e3 », qui ne
  /// sont pas des numéros de chapitre : seule la forme décimale simple
  /// (chiffres, éventuellement « . » ou « , » puis chiffres) est lue. Un texte
  /// en notation scientifique ou non fini donne 0.
  static double convertirNumero(String? texte) {
    if (texte == null) {
      return 0;
    }
    final t = texte.trim();
    // Notation scientifique (« 1e3 », « 2.5E-1 ») : refusée plutôt que lue
    // comme « 1 » ou « 1000 ».
    if (RegExp(r'\d[eE][+-]?\d').hasMatch(t)) {
      return 0;
    }
    final correspondance = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(t);
    if (correspondance == null) {
      return 0;
    }
    final valeur = double.parse(correspondance.group(0)!.replaceAll(',', '.'));
    return valeur.isFinite ? valeur : 0;
  }

  /// Date affichée avec un nom de mois (« 13 nov. 2026 », « Dec 22, 2024 »),
  /// en UTC à minuit ; `null` si le format est inconnu ou si la date n'existe
  /// pas (« 31 févr. 2025 »).
  ///
  /// LIMITE : seuls les noms de mois français et anglais sont reconnus.
  static DateTime? convertirDateAvecMois(String texte) {
    final propre = texte.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    // « 13 nov. 2026 » (jour, mois, année : français)
    final francais = RegExp(r'^(\d{1,2})\s+([^\s\d]+?)\.?\s+(\d{4})$')
        .firstMatch(propre);
    // « Dec 22, 2024 » (mois, jour, année : anglais)
    final anglais = RegExp(r'^([^\s\d]+?)\.?\s+(\d{1,2}),\s*(\d{4})$')
        .firstMatch(propre);
    final int jour;
    final int? mois;
    final int annee;
    if (francais != null) {
      jour = int.parse(francais.group(1)!);
      mois = _mois[francais.group(2)!];
      annee = int.parse(francais.group(3)!);
    } else if (anglais != null) {
      jour = int.parse(anglais.group(2)!);
      mois = _mois[anglais.group(1)!];
      annee = int.parse(anglais.group(3)!);
    } else {
      return null;
    }
    if (mois == null) {
      return null;
    }
    return dateValide(annee, mois, jour);
  }

  /// Date UTC à minuit si elle existe dans le calendrier, sinon `null`.
  ///
  /// `DateTime.utc` ne refuse rien : le 31/02 y devient le 3 mars (ou le
  /// 2 mars d'une année bissextile). On vérifie donc que le jour et le mois
  /// obtenus sont ceux demandés.
  static DateTime? dateValide(int annee, int mois, int jour) {
    if (mois < 1 || mois > 12 || jour < 1 || jour > 31) {
      return null;
    }
    final date = DateTime.utc(annee, mois, jour);
    if (date.year != annee || date.month != mois || date.day != jour) {
      return null;
    }
    return date;
  }
}
