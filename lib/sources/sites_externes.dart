/// Noms lisibles des sites où se lisent les chapitres externes (bouton
/// « Lire sur `site` », PLAYBOOK.md section 10).
///
/// Partagé par tous les adaptateurs : un chapitre externe peut venir de
/// MangaDex (lien vers l'éditeur) ou d'un site dont les pages de chapitre ne
/// sont jamais lues par l'application (Scan-Manga).
library;

/// Noms commerciaux des sites externes connus (domaine sans `www.`).
const Map<String, String> nomsSitesExternes = <String, String>{
  'mangaplus.shueisha.co.jp': 'MANGA Plus',
  'viz.com': 'VIZ',
  'scan-manga.com': 'Scan-Manga',
};

/// Nom lisible du site de [urlExterne] pour le bouton « Lire sur `site` » :
/// le nom commercial s'il est connu ([nomsSitesExternes] : « MANGA Plus »,
/// « VIZ », « Scan-Manga »), sinon le nom de domaine en minuscules sans
/// `www.`. Renvoie le texte reçu tel quel s'il ne contient pas d'hôte.
String nomSiteExterne(String urlExterne) {
  final hote = Uri.tryParse(urlExterne.trim())?.host.toLowerCase() ?? '';
  if (hote.isEmpty) {
    return urlExterne.trim();
  }
  final domaine = hote.startsWith('www.') ? hote.substring(4) : hote;
  return nomsSitesExternes[domaine] ?? domaine;
}
