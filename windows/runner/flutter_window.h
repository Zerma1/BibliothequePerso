#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Demande a Dart (canal "bibliotheque_perso/fenetre") s'il accepte la
  // fermeture de la fenetre, puis ferme selon sa reponse.
  void DemanderFermeture(HWND hwnd);

  // Ferme la fenetre sans redemander a Dart (WM_CLOSE reposte).
  void FermerMaintenant(HWND hwnd);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Canal de la demande de fermeture (voir flutter_window.cpp).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      canal_fenetre_;

  // Une demande de fermeture attend la reponse de Dart.
  bool fermeture_en_cours_ = false;

  // Fermeture acceptee : le prochain WM_CLOSE detruit la fenetre.
  bool fermeture_confirmee_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
