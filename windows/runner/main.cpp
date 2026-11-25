#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <functional>
#include <iterator>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Chemin complet de l'executable en minuscules ("" en cas d'echec).
std::wstring CheminExecutable(HANDLE processus) {
  wchar_t tampon[32768];
  DWORD taille = static_cast<DWORD>(std::size(tampon));
  if (!::QueryFullProcessImageNameW(processus, 0, tampon, &taille)) {
    return L"";
  }
  std::wstring chemin(tampon, taille);
  std::transform(chemin.begin(), chemin.end(), chemin.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return chemin;
}

// Recherche de la fenetre principale d'une autre instance du meme executable.
struct RechercheFenetre {
  std::wstring chemin;
  DWORD processus_courant;
  HWND trouvee;
  DWORD processus_trouve;
};

BOOL CALLBACK ExaminerFenetre(HWND hwnd, LPARAM parametre) {
  auto* recherche = reinterpret_cast<RechercheFenetre*>(parametre);
  wchar_t classe[64];
  if (!::GetClassNameW(hwnd, classe, static_cast<int>(std::size(classe))) ||
      std::wstring(classe) != L"FLUTTER_RUNNER_WIN32_WINDOW") {
    return TRUE;
  }
  DWORD processus = 0;
  ::GetWindowThreadProcessId(hwnd, &processus);
  if (processus == 0 || processus == recherche->processus_courant) {
    return TRUE;
  }
  HANDLE handle =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processus);
  if (!handle) {
    return TRUE;
  }
  const bool meme_executable = CheminExecutable(handle) == recherche->chemin;
  ::CloseHandle(handle);
  if (!meme_executable) {
    return TRUE;
  }
  recherche->trouvee = hwnd;
  recherche->processus_trouve = processus;
  return FALSE;
}

// Instance unique par executable : avec la fermeture dans la zone de
// notification, un nouveau lancement (raccourci, menu Demarrer) alors que
// l'application tourne cachee ouvrirait sinon une deuxieme application sur la
// meme base et la meme file de telechargement. Renvoie true si une autre
// instance du meme executable tourne deja : elle est alors priee de
// s'afficher (sauf demarrage masque) et celle-ci doit se terminer.
// Le nom du verrou depend du chemin de l'executable : une version de
// developpement (build\...) et la version installee ne se bloquent pas.
// Le verrou est garde jusqu'a la fin du processus (liberation par Windows).
bool AutreInstanceActive(bool demarrage_masque) {
  const std::wstring chemin = CheminExecutable(::GetCurrentProcess());
  if (chemin.empty()) {
    return false;
  }
  const std::wstring nom_verrou =
      L"Local\\BibliothequePerso." +
      std::to_wstring(std::hash<std::wstring>{}(chemin));
  ::CreateMutexW(nullptr, FALSE, nom_verrou.c_str());
  if (::GetLastError() != ERROR_ALREADY_EXISTS) {
    return false;
  }
  if (!demarrage_masque) {
    RechercheFenetre recherche{chemin, ::GetCurrentProcessId(), nullptr, 0};
    ::EnumWindows(ExaminerFenetre, reinterpret_cast<LPARAM>(&recherche));
    if (recherche.trouvee) {
      // Ce processus vient d'etre lance par le client : il peut ceder le
      // premier plan a l'instance deja ouverte.
      ::AllowSetForegroundWindow(recherche.processus_trouve);
      ::PostMessageW(recherche.trouvee,
                     ::RegisterWindowMessageW(kMessageAfficherFenetre), 0, 0);
    }
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Demarrage avec Windows en mode « icone masquee » (cle Run ecrite par
  // lib/main.dart, appliquerDemarrageAvecWindows).
  const bool demarrage_masque =
      command_line != nullptr &&
      std::wstring(command_line).find(kArgumentDemarrageMasque) !=
          std::wstring::npos;
  if (AutreInstanceActive(demarrage_masque)) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, demarrage_masque);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // Titre de la fenetre. Le fichier est en UTF-8 et compile avec /utf-8
  // (windows/CMakeLists.txt) : sans cette option, l'accent serait abime
  // (voir E7 dans docs/JOURNAL_ERREURS.md).
  if (!window.Create(L"Bibliothèque perso", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  // Fin immediate du processus (retour 0.3.1-test, Z6 : apres « Quitter », le
  // processus restait dans le gestionnaire des taches). La fenetre et le
  // moteur sont deja detruits et le journal vide ; un retour normal passerait
  // par la liberation des bibliotheques (DllMain, destructeurs statiques), ou
  // une bibliotheque native (cnativeapi.dll, icone de la zone de notification)
  // peut bloquer indefiniment.
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
