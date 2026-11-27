#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// Argument de ligne de commande du demarrage avec Windows en mode « icone
// masquee » : la fenetre n'est pas affichee, l'application reste dans la zone
// de notification (meme valeur que argumentDemarrageMasque dans lib/main.dart).
constexpr wchar_t kArgumentDemarrageMasque[] = L"--demarrage-masque";

// Argument de ligne de commande de la desinstallation : lance par
// l'installateur (installateur\bibliotheque_perso.iss,
// AppelerApplicationDesinstallation) apres l'arret de l'application, pour
// modifier la base (sources, titres, etat des chapitres) avant le retrait du
// programme. La fenetre n'est jamais affichee et le controle d'instance unique
// est ignore (voir main.cpp). Meme valeur que cote Dart (lib/main.dart).
constexpr wchar_t kArgumentDesinstallation[] = L"--desinstallation";

// Message enregistre (RegisterWindowMessage) envoye par une deuxieme instance
// du meme executable a la fenetre de la premiere : « affiche-toi », puis la
// deuxieme instance se termine (voir main.cpp).
constexpr wchar_t kMessageAfficherFenetre[] =
    L"BibliothequePerso.AfficherFenetre";

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |demarrage_masque| : la fenetre reste cachee apres la premiere image
  // (demarrage avec Windows en mode « icone masquee »).
  // |jamais_afficher| : la fenetre n'est jamais affichee, meme si Dart le
  // demande (« afficher ») ou si un autre lancement le demande
  // (desinstallation, kArgumentDesinstallation).
  FlutterWindow(const flutter::DartProject& project, bool demarrage_masque,
                bool jamais_afficher = false);
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

  // Affiche la fenetre (meme cachee ou reduite) et la met au premier plan.
  void AfficherFenetre(HWND hwnd);

  // Repond aux appels de Dart sur le canal (cacher, afficher, quitter,
  // terminer).
  void TraiterAppelDart(
      const flutter::MethodCall<flutter::EncodableValue>& appel,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> resultat);

  // Fenetre gardee cachee au demarrage (voir le constructeur).
  bool demarrage_masque_ = false;

  // Fenetre jamais affichee (voir le constructeur).
  bool jamais_afficher_ = false;

  // Identifiant du message kMessageAfficherFenetre (0 si non enregistre).
  UINT message_afficher_ = 0;

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
