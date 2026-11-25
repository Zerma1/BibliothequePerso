#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Canal partage avec lib/main.dart (canalFenetre).
constexpr char kNomCanalFenetre[] = "bibliotheque_perso/fenetre";

// Methode appelee sur Dart a la fermeture de la fenetre ; Dart repond
// "exit" (fermer) ou "cancel" (garder la fenetre ouverte).
constexpr char kMethodeDemanderFermeture[] = "demanderFermeture";

// Minuteur de securite : sans reponse de Dart dans ce delai, la fenetre se
// ferme quand meme (Dart attend lui-meme au plus 2 s l'ecriture du journal).
constexpr UINT_PTR kMinuteurFermeture = 0xB1B1;
constexpr UINT kDelaiMaxFermetureMs = 5000;

// Methodes appelees par Dart (zone de notification, lib/main.dart) :
// cacher la fenetre (croix), l'afficher (clic sur l'icone, menu « Ouvrir ») et
// demander la vraie fermeture (menu « Quitter », qui repasse par
// kMethodeDemanderFermeture pour vider le journal).
constexpr char kMethodeCacher[] = "cacher";
constexpr char kMethodeAfficher[] = "afficher";
constexpr char kMethodeQuitter[] = "quitter";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool demarrage_masque)
    : project_(project), demarrage_masque_(demarrage_masque) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Demande de fermeture geree ici plutot que par le moteur : le moteur ne
  // previent Dart (System.requestAppExit) que si la fenetre est la derniere
  // fenetre de premier niveau du processus (WindowsLifecycleManager::
  // IsLastWindowOfProcess). Or flutter_inappwebview_windows cree des fenetres
  // cachees de premier niveau (WebViewEnvironmentManager, une par navigateur
  // ouvert) : le moteur laissait donc passer WM_CLOSE sans rien dire a Dart,
  // et AppLifecycleListener.onExitRequested n'etait jamais appele (journal
  // non vide a la fermeture).
  canal_fenetre_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kNomCanalFenetre,
          &flutter::StandardMethodCodec::GetInstance());
  canal_fenetre_->SetMethodCallHandler(
      [this](const auto& appel, auto resultat) {
        TraiterAppelDart(appel, std::move(resultat));
      });

  message_afficher_ = ::RegisterWindowMessage(kMessageAfficherFenetre);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Demarrage avec Windows en mode « icone masquee » : la fenetre reste
    // cachee, Dart installe l'icone de la zone de notification (et rappelle
    // « afficher » s'il n'y parvient pas).
    if (!demarrage_masque_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  canal_fenetre_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::DemanderFermeture(HWND hwnd) {
  if (fermeture_en_cours_) {
    // Deuxieme clic sur la croix pendant l'attente : on ferme sans attendre.
    FermerMaintenant(hwnd);
    return;
  }
  if (!canal_fenetre_) {
    FermerMaintenant(hwnd);
    return;
  }
  fermeture_en_cours_ = true;
  ::SetTimer(hwnd, kMinuteurFermeture, kDelaiMaxFermetureMs, nullptr);
  // Les rappels sont executes sur le fil de la fenetre ; ils ne ferment
  // jamais directement (FermerMaintenant reposte WM_CLOSE), pour ne pas
  // detruire le moteur pendant qu'il traite la reponse.
  auto resultat =
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [this, hwnd](const flutter::EncodableValue* reponse) {
            if (!fermeture_en_cours_) {
              return;
            }
            const auto* texte =
                reponse ? std::get_if<std::string>(reponse) : nullptr;
            if (texte && *texte == "cancel") {
              // Fermeture refusee par l'application : la fenetre reste.
              fermeture_en_cours_ = false;
              ::KillTimer(hwnd, kMinuteurFermeture);
              return;
            }
            FermerMaintenant(hwnd);
          },
          [this, hwnd](const std::string&, const std::string&,
                       const flutter::EncodableValue*) {
            // Erreur cote Dart : on ferme quand meme.
            if (fermeture_en_cours_) {
              FermerMaintenant(hwnd);
            }
          },
          [this, hwnd]() {
            // Gestionnaire Dart pas encore installe (demarrage) : on ferme.
            if (fermeture_en_cours_) {
              FermerMaintenant(hwnd);
            }
          });
  canal_fenetre_->InvokeMethod(kMethodeDemanderFermeture, nullptr,
                               std::move(resultat));
}

void FlutterWindow::AfficherFenetre(HWND hwnd) {
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  } else {
    ::ShowWindow(hwnd, SW_SHOW);
  }
  // Le clic sur l'icone de la zone de notification (ou la deuxieme instance,
  // via AllowSetForegroundWindow) donne a ce processus le droit de passer au
  // premier plan.
  ::SetForegroundWindow(hwnd);
  if (flutter_controller_) {
    // Fenetre jamais affichee (demarrage masque) : une image est redemandee
    // pour ne pas montrer une surface vide.
    flutter_controller_->ForceRedraw();
  }
}

void FlutterWindow::TraiterAppelDart(
    const flutter::MethodCall<flutter::EncodableValue>& appel,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> resultat) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    resultat->Error("fenetre_absente", "Fenetre deja detruite");
    return;
  }
  const std::string& methode = appel.method_name();
  if (methode == kMethodeCacher) {
    ::ShowWindow(hwnd, SW_HIDE);
    resultat->Success();
  } else if (methode == kMethodeAfficher) {
    AfficherFenetre(hwnd);
    resultat->Success();
  } else if (methode == kMethodeQuitter) {
    // Meme chemin que la croix : WM_CLOSE -> DemanderFermeture -> Dart
    // (qui sait que l'on quitte vraiment et vide le journal).
    ::PostMessage(hwnd, WM_CLOSE, 0, 0);
    resultat->Success();
  } else {
    resultat->NotImplemented();
  }
}

void FlutterWindow::FermerMaintenant(HWND hwnd) {
  fermeture_en_cours_ = false;
  fermeture_confirmee_ = true;
  ::KillTimer(hwnd, kMinuteurFermeture);
  ::PostMessage(hwnd, WM_CLOSE, 0, 0);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Fermeture (croix, Alt+F4, CloseMainWindow) : on demande d'abord a Dart,
  // puis le WM_CLOSE reposte va directement a Win32Window (DestroyWindow),
  // sans repasser par le moteur pour ne pas declencher une deuxieme demande.
  if (message == WM_CLOSE) {
    if (fermeture_confirmee_ || !flutter_controller_) {
      return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    }
    DemanderFermeture(hwnd);
    return 0;
  }
  if (message == WM_TIMER && wparam == kMinuteurFermeture) {
    // Pas de reponse de Dart a temps : on ferme quand meme.
    FermerMaintenant(hwnd);
    return 0;
  }
  if (message_afficher_ != 0 && message == message_afficher_) {
    // Deuxieme lancement du meme executable (raccourci, menu Demarrer)
    // pendant que l'application tourne dans la zone de notification.
    AfficherFenetre(hwnd);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
