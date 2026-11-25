/// Remplaçant vide de `flutter_inappwebview_linux` : volontairement sans implémentation.
///
/// Sous Linux, l'application n'ouvre jamais de vue web et passe par le navigateur externe
/// (voir le pubspec.yaml de ce paquet).
library;

/// Classe appelée par le registre des plugins Dart de Flutter au démarrage sous Linux.
class LinuxInAppWebViewPlatform {
  LinuxInAppWebViewPlatform._();

  /// N'enregistre rien : `InAppWebViewPlatform.instance` reste nul sous Linux.
  static void registerWith() {}
}
