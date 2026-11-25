/// Extension de fichier d'une image téléchargée (page d'un chapitre,
/// couverture), d'après ses octets d'abord.
library;

import '../donnees/stockage_telechargements.dart';
import '../sources/detection_image.dart';
import 'constantes_services.dart';

/// Extension (sans point) sous laquelle enregistrer l'image [octets] venue
/// de [adresse] (URL, ou `file:` pour une image de l'appareil).
///
/// Ordre retenu (retour X1 de la 0.2.1-test : une page WEBP servie sans
/// `Content-Type` était mal nommée) :
/// 1. le format reconnu par les octets (`detecterFormatImage`) : c'est le
///    seul qui ne ment jamais (un `.jpg` servi en WEBP existe) ;
/// 2. sinon l'extension de l'adresse (`StockageTelechargements.extensionDepuisUrl`) ;
/// 3. sinon [extensionImageParDefaut].
///
/// Fonction pure (aucun disque, aucun réseau).
String extensionImage(List<int> octets, String? adresse) =>
    detecterFormatImage(octets)?.extension ??
    (adresse == null
        ? null
        : StockageTelechargements.extensionDepuisUrl(adresse)) ??
    extensionImageParDefaut;
