; Installateur Windows de « Bibliothèque perso » (Inno Setup 6.7) : un seul
; .exe pour installer, mettre à jour, désinstaller et tout supprimer (retour
; du client sur 0.3.2-test ; remplace l'ancien desinstallateur.iss).
;
; Construit par outils\construire_installateur.ps1, qui passe la version lue
; dans pubspec.yaml : ISCC /DVersion=X.Y.Z /DBuild=N bibliotheque_perso.iss
;   -> livraisons\X.Y.Z\bibliotheque_perso-X.Y.Z-installation.exe
;
; Première page « Que voulez-vous faire ? » :
; - Application non installée : « Installer » ou « Tout supprimer » (restes
;   d'une ancienne installation : base, chapitres).
; - Application installée (clé « Applications installées » de cet AppId et
;   son désinstallateur présents) : « Mettre à jour » (ou « Réinstaller » si
;   la version est la même), « Désinstaller » ou « Tout supprimer ».
;   « Installer » n'est pas proposé : pour changer de dossier, désinstaller
;   d'abord.
;
; Installer : dossier du programme (par défaut %LOCALAPPDATA%\Programs\
;   Bibliotheque perso), dossier des chapitres téléchargés (local, disque
;   réseau ou NAS) et dossier de la base (de préférence un disque local ; par
;   défaut %APPDATA%\bibliotheque_perso). Les deux derniers sont écrits dans
;   {app}\installation.json (clés "dossierBibliotheque" et "dossierBase"),
;   lu par l'application (lib/main.dart). Si une base existe déjà dans le
;   dossier par défaut ou dans l'ancien dossier, ce dossier est proposé et le
;   texte précise qu'elle sera reprise (déplacée par l'application si le
;   client en choisit un autre).
; Mettre à jour : rien n'est redemandé ; installation.json est gardé tel
;   quel ; une page récapitule les trois emplacements.
; Désinstaller : trois cases, « Chapitres téléchargés » (cochée), « Sources »
;   et « Titres » (non cochées). Un titre ne peut pas exister sans sa source :
;   « Sources » coche et grise « Titres » (questions : pas de question sur les
;   titres si Sources = Oui ; silencieux : /SUPPRIMERSOURCES implique
;   /SUPPRIMERTITRES ; l'appel reçoit alors aussi --supprimer-titres).
;   L'application est d'abord arrêtée (dès le début ; si elle ne peut pas
;   l'être, la désinstallation est annulée sans rien modifier). Les chapitres
;   à supprimer sont décidés AVANT l'appel. Si Sources, Titres ou la
;   suppression des chapitres est demandé (un seul appel, fait par
;   unins000.exe, y compris pour « Désinstaller » depuis l'installateur qui
;   lui transmet les choix), l'application
;   est d'abord lancée (application arrêtée avant) :
;     "{app}\bibliotheque_perso.exe" --desinstallation [--supprimer-sources]
;       [--supprimer-titres] [--chapitres-supprimes]
;   et attendue (au plus DelaiAppelApplicationMs, puis arrêtée). Code 0 =
;   réussi (base absente comprise) ; sinon le client est prévenu (journal en
;   silencieux) et la désinstallation continue sans autre modification de la
;   base. Les étapes de l'application étant des transactions séparées, un
;   échec (code 1, délai dépassé) peut laisser la base modifiée en partie :
;   le message le dit et renvoie au journal de l'application ; seul un
;   lancement impossible garantit une base intacte. Même si Sources ET
;   Titres sont cochés, la base n'est jamais supprimée en entier (les
;   réglages et emplacements restent) : c'est le rôle de « Tout supprimer ».
;   Puis le désinstallateur Inno (unins000.exe) est lancé en silencieux
;   (/GARDERCHAPITRES si la case n'est pas cochée).
;   Depuis « Applications installées » de Windows (unins000.exe), les mêmes
;   trois cases sont proposées dans une petite fenêtre (questions Oui/Non si
;   elle ne peut pas être créée), avec les mêmes valeurs par défaut.
;   Chapitres : seuls les fichiers créés par l'application, selon les règles
;   de suppression_commune.iss (repère obligatoire hors du dossier par défaut,
;   dossiers protégés, chemins suspects refusés, liens non suivis). Journaux,
;   rapports, exports et livres importés (import[.<n>].<cbz|pdf|epub>) sont
;   gardés (seul « Tout supprimer » les retire).
; Tout supprimer : liste des chemins, confirmation (Non par défaut), page
;   « Résultat » : programme, base (dossier de installation.json, défaut et
;   ancien dossier), chapitres (mêmes règles), démarrage avec Windows.
;
; Dossier de la base, cherché dans cet ordre (et emplacements.json dedans) :
;   "dossierBase" de installation.json, {userappdata}\bibliotheque_perso,
;   ancien {userappdata}\io.github.zerma1\bibliotheque_perso (l'application
;   déplace elle-même l'ancien au démarrage). « Tout supprimer » supprime en
;   entier le dossier par défaut et l'ancien (ils appartiennent à
;   l'application ; io.github.zerma1 aussi s'il est vide) ; un dossier choisi
;   par le client n'est jamais supprimé en entier : seuls les fichiers de
;   l'application (bibliotheque_perso.db et ses -wal, -shm, -journal,
;   emplacements.json), puis le dossier s'il est vide.
;
; Paramètres de la ligne de commande (en plus de ceux d'Inno Setup) :
;   /ACTION=INSTALLER|METTREAJOUR|DESINSTALLER|TOUTSUPPRIMER
;       action en silencieux (présélection sinon) ; par défaut METTREAJOUR si
;       l'application est installée, sinon INSTALLER.
;   /BIBLIOTHEQUE="D:\Mes chapitres"   installation : dossier des chapitres.
;   /BASE="D:\Base"                    installation : dossier de la base.
;   /SUPPRIMERSOURCES /SUPPRIMERTITRES /GARDERCHAPITRES
;       désinstallation silencieuse (installateur ou unins000.exe).
;   /RELANCER   installation ou mise à jour (silencieuse ou non) : relance
;       l'application à la fin si elle a réussi (sans la case « Lancer »).
;       Utilisé par la mise à jour automatique :
;       /ACTION=METTREAJOUR /SILENT /NORESTART /RELANCER
;
; Application ouverte : elle se cache dans la zone de notification et refuse
; WM_CLOSE ; le Restart Manager ne l'arrête pas. Le processus
; bibliotheque_perso.exe lancé depuis le dossier d'installation, et lui seul
; (chemin complet comparé), est arrêté (après accord du client avec
; l'interface ; sans question en silencieux et pour « Tout supprimer », dont
; la liste le signale).
;
; Essais seulement (pour ne jamais toucher aux données réelles du client) :
;   /DIdApplication="{{…}"              autre AppId
;   /DDossierBase="C:\essai\base"       dossier de la base par défaut
;   /DAncienDossierBase="C:\essai\anc"  ancien dossier de la base
;   /DDossierCache="C:\essai\cache"     dossier de cache local
;   /DDossierDocuments="C:\essai\doc"   dossier Documents
;   /DNomEntreeDemarrage="Essai…"       nom de la valeur Run
;   /DNomRaccourci="Essai…"             nom des raccourcis
;   /DDossierProgrammeParDefaut="C:\essai\prog"  dossier du programme proposé
;   /DDelaiAppelApplicationMs=3000      délai de l'appel --desinstallation
;   /DDossierRelease="C:\essai\release" fichiers du programme

#ifndef Version
  #error Version absente : lancer outils\construire_installateur.ps1, ou ISCC /DVersion=X.Y.Z
#endif
#ifndef Build
  #define Build "0"
#endif
#ifndef DossierRelease
  #define DossierRelease "..\build\windows\x64\runner\Release"
#endif

#ifndef IdApplication
  #define IdApplication "{{827D980C-013C-4734-94F1-BB09CBAA7712}"
#endif
; Dossier de la base par défaut (et où emplacements.json est cherché).
#ifndef DossierBase
  #define DossierBase "{userappdata}\bibliotheque_perso"
#endif
; Ancien dossier de la base (jusqu'à 0.3.2) : getApplicationSupportDirectory
; de path_provider_windows = %APPDATA%\<CompanyName>\<ProductName>
; (windows\runner\Runner.rc).
#ifndef AncienDossierBase
  #define AncienDossierBase "{userappdata}\io.github.zerma1\bibliotheque_perso"
#endif
; Cache local (getApplicationCacheDirectory) : inutilisé aujourd'hui, mais il
; appartiendrait à l'application.
#ifndef DossierCache
  #define DossierCache "{localappdata}\io.github.zerma1\bibliotheque_perso"
#endif
#ifndef NomEntreeDemarrage
  #define NomEntreeDemarrage "Bibliotheque perso"
#endif
; Dossier Documents (dossier des chapitres par défaut ; suppression_commune.iss).
#ifndef DossierDocuments
  #define DossierDocuments "{userdocs}"
#endif
#ifndef DossierProgrammeParDefaut
  #define DossierProgrammeParDefaut "{localappdata}\Programs\Bibliotheque perso"
#endif
; Délai maximal de l'appel « --desinstallation » (2 minutes).
#ifndef DelaiAppelApplicationMs
  #define DelaiAppelApplicationMs "120000"
#endif
; Pointeur vers les emplacements choisis (HKCU), hors du programme : il
; survit à « Désinstaller » (une réinstallation retrouve la base et les
; chapitres) ; seul « Tout supprimer » le retire. Valeurs DossierBase et
; DossierBibliotheque.
#ifndef ClePointeur
  #define ClePointeur "Software\Bibliotheque perso"
#endif

#define NomApplication "Bibliothèque perso"
#define NomExecutable "bibliotheque_perso.exe"
#ifndef NomRaccourci
  #define NomRaccourci NomApplication
#endif

; Fichiers et dossiers du programme, relevés RÉCURSIVEMENT dans le dossier
; Release à la compilation (parcours en largeur), pour « Tout supprimer » si
; le désinstallateur Inno manque ou échoue. Chemins relatifs séparés par
; « | » : FichiersProgramme (fichiers seuls), DossiersProgramme (dossiers,
; parents avant enfants). Seuls ces fichiers sont supprimés, puis ces dossiers
; s'ils sont devenus vides : un fichier ajouté par le client reste. Mêmes
; exclusions que [Files] (installation.json, *.WebView2 : jamais livrés).
#define BaseRelease AddBackslash(SourcePath) + DossierRelease + "\"
#if Copy(DossierRelease, 2, 1) == ":"
  #undef BaseRelease
  #define BaseRelease DossierRelease + "\"
#endif
#define FichiersProgramme ""
#define DossiersProgramme ""
#define FileAttente "|"
#define DossierCourant ""
#define RechercheRelease
#define TrouveRelease
#define Bidon 0
#sub AjouterElementProgramme
  #define NomElement FindGetFileName(RechercheRelease)
  #if NomElement != "." && NomElement != ".." && NomElement != "installation.json" && Pos(".WebView2", NomElement) == 0
    #if Pos("'", NomElement) > 0 || Pos("|", NomElement) > 0
      #error Nom de fichier non pris en charge (apostrophe ou barre verticale) dans le dossier Release.
    #endif
    #if DirExists(BaseRelease + DossierCourant + NomElement)
      #expr FileAttente = FileAttente + DossierCourant + NomElement + "\|"
      #expr DossiersProgramme = DossiersProgramme + DossierCourant + NomElement + "|"
    #else
      #expr FichiersProgramme = FichiersProgramme + DossierCourant + NomElement + "|"
    #endif
  #endif
#endsub
#sub ParcourirDossierRelease
  #expr DossierCourant = Copy(FileAttente, 1, Pos("|", FileAttente) - 1)
  #expr FileAttente = Copy(FileAttente, Pos("|", FileAttente) + 1, Len(FileAttente))
  #for {RechercheRelease = TrouveRelease = FindFirst(BaseRelease + DossierCourant + "*", faAnyFile); TrouveRelease; TrouveRelease = FindNext(RechercheRelease)} AjouterElementProgramme
  #if RechercheRelease
    #expr FindClose(RechercheRelease)
  #endif
#endsub
#if DirExists(BaseRelease)
  #for {Bidon = 0; FileAttente != ""; Bidon = 0} ParcourirDossierRelease
#endif
#if FichiersProgramme == ""
  #error Dossier Release introuvable ou vide : compiler l'application (flutter build windows --release).
#endif

[Setup]
; Identifiant fixe : il permet de reconnaître une installation précédente
; (mise à jour par-dessus, même dossier) ; ne jamais le changer.
AppId={#IdApplication}
AppName={#NomApplication}
AppVersion={#Version}
AppVerName={#NomApplication} {#Version}
AppPublisher=Bibliothèque perso
VersionInfoVersion={#Version}.{#Build}
VersionInfoProductVersion={#Version}
VersionInfoDescription=Installation et désinstallation de {#NomApplication}
; Par utilisateur, sans droits administrateur.
PrivilegesRequired=lowest
DefaultDirName={#DossierProgrammeParDefaut}
; La page du dossier n'est affichée que pour « Installer » (ShouldSkipPage).
DisableDirPage=no
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
; La première page est le choix de l'action.
DisableWelcomePage=yes
; Rien n'est installé (ni désinstallateur enregistré) pour « Désinstaller » et
; « Tout supprimer ».
Uninstallable=EstModeInstallation
CreateUninstallRegKey=EstModeInstallation
UsedUserAreasWarning=no
; Journal toujours écrit (%TEMP%), chemin affiché pour Désinstaller et Tout
; supprimer ; /LOG="…" pour choisir le fichier.
SetupLogging=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; L'application elle-même est d'abord arrêtée dans PrepareToInstall
; (FermerApplication) : cachée dans la zone de notification, elle ne répond
; pas au Restart Manager. Celui-ci reste pour les autres programmes.
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no
SetupIconFile=..\assets\logo\logo.ico
UninstallDisplayIcon={app}\{#NomExecutable}
UninstallDisplayName={#NomApplication}
WizardStyle=modern
ShowLanguageDialog=no
OutputDir=..\livraisons\{#Version}
OutputBaseFilename=bibliotheque_perso-{#Version}-installation
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Messages]
SetupAppTitle={#NomApplication}
SetupWindowTitle=%1 {#Version}
ExitSetupMessage=Rien n'a encore été modifié.%n%nQuitter ?
; Désinstallation depuis « Applications installées » : les cases sont
; proposées juste avant (InitializeUninstall).
ConfirmUninstall=Désinstaller %1 avec les choix indiqués ?%n%nCe que vous n'avez pas coché est conservé : une nouvelle installation le retrouvera.
UninstalledAll=%1 a été désinstallé.%n%nCe que vous n'avez pas demandé de supprimer est conservé (réglages compris) : une nouvelle installation le retrouvera.

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: unchecked

[Files]
Source: "{#DossierRelease}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: EstModeInstallation; Excludes: "installation.json,*.WebView2"
; installation.json et *.WebView2 (données du navigateur intégré) peuvent se
; trouver dans le dossier Release si l'application y a été lancée : ils ne
; doivent jamais être livrés (ils écraseraient ceux du client).

[Icons]
Name: "{autoprograms}\{#NomRaccourci}"; Filename: "{app}\{#NomExecutable}"; WorkingDir: "{app}"; IconFilename: "{app}\{#NomExecutable}"; Check: EstModeInstallation
Name: "{autodesktop}\{#NomRaccourci}"; Filename: "{app}\{#NomExecutable}"; WorkingDir: "{app}"; IconFilename: "{app}\{#NomExecutable}"; Tasks: bureau; Check: EstModeInstallation

[Run]
Filename: "{app}\{#NomExecutable}"; Description: "Lancer {#NomApplication}"; Flags: nowait postinstall skipifsilent; Check: EstModeInstallation and not ParametrePresent('RELANCER')
; /RELANCER (mise à jour automatique) : relance sans case à cocher, même en
; silencieux, seulement après une installation ou mise à jour réussie.
Filename: "{app}\{#NomExecutable}"; Flags: nowait; Check: EstModeInstallation and ParametrePresent('RELANCER')

[UninstallDelete]
; Écrit par l'installateur (section [Code]) : à retirer avec le programme.
; Jamais la base. Les chapitres téléchargés sont traités dans la section [Code]
; (CurUninstallStepChanged), selon les choix du client.
Type: files; Name: "{app}\installation.json"

[Code]
#include "suppression_commune.iss"

const
  ModeInstaller = 0;
  ModeMettreAJour = 1;
  ModeDesinstaller = 2;
  ModeToutSupprimer = 3;

  NomFichierInstallation = 'installation.json';
  CleDossierBibliotheque = 'dossierBibliotheque';
  CleDossierBase = 'dossierBase';
  // Mémorisés aussi dans les données d'Inno Setup (registre de l'utilisateur),
  // au cas où installation.json aurait disparu.
  ClePreviousData = 'DossierBibliotheque';
  ClePreviousDataBase = 'DossierBase';
  // Écrit par l'application dans le dossier de sa base : dossier des
  // chapitres choisi dans Paramètres.
  NomFichierEmplacements = 'emplacements.json';
  CleDossierChapitres = 'dossierChapitres';
  // Fichiers de l'application dans le dossier de la base
  // (nomFichierBaseDeDonnees, lib/modeles/constantes.dart ;
  // nomFichierEmplacements, lib/donnees/constantes_donnees.dart).
  NomFichierBase = 'bibliotheque_perso.db';
  // Dossier de l'éditeur (CompanyName de windows\runner\Runner.rc), parent de
  // l'ancien dossier de la base et du cache : supprimé s'il devient vide.
  NomDossierEditeur = 'io.github.zerma1';
  // Données WebView2 du navigateur intégré, dans le dossier d'installation.
  NomDossierWebView2 = '{#NomExecutable}.WebView2';
  // Démarrage avec Windows (nomEntreeDemarrageWindows, lib/main.dart).
  NomEntreeDemarrage = '{#NomEntreeDemarrage}';
  CleDemarrageRun = 'Software\Microsoft\Windows\CurrentVersion\Run';
  CleDemarrageApprouve =
    'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  // Attente de la fin des processus arrêtés et du désinstallateur Inno.
  AttenteArretMaxMs = 15000;
  AttenteDesinstallationMaxMs = 60000;
  // Appel de l'application pour la désinstallation (windows\runner\main.cpp,
  // kArgumentDesinstallation).
  ArgumentDesinstallation = '--desinstallation';
  ArgumentSupprimerSources = '--supprimer-sources';
  ArgumentSupprimerTitres = '--supprimer-titres';
  ArgumentChapitresSupprimes = '--chapitres-supprimes';
  DelaiAppelApplicationMs = {#DelaiAppelApplicationMs};
  // kernel32 : CreateProcessW, WaitForSingleObject.
  CreationSansFenetre = $08000000;   // CREATE_NO_WINDOW
  DemarrageAvecAffichage = $00000001; // STARTF_USESHOWWINDOW
  AttenteDepassee = 258;             // WAIT_TIMEOUT
  // Textes des trois cases de la désinstallation.
  LibelleCaseChapitres = 'Chapitres téléchargés';
  LibelleCaseSources = 'Sources';
  LibelleCaseTitres = 'Titres';
  // Un titre ne peut pas exister sans sa source (schéma de la base) :
  // « Sources » coche et grise « Titres ».
  LibelleCaseTitresImposee = 'Titres (les titres dépendent de leurs sources)';

type
  // STARTUPINFOW et PROCESS_INFORMATION. Setup et unins000 d'Inno Setup 6.7
  // sont toujours des programmes x86 32 bits (Setup.e32 et unins000.exe :
  // machine 0x014C, vérifié le 2026-11-27 ; ArchitecturesInstallIn64BitMode ne
  // change que le mode d'installation, et même UseSetupLdr=x64 ne rend 64 bits
  // que le chargeur) : pointeurs et descripteurs sur 4 octets, STARTUPINFOW
  // = 68 octets, PROCESS_INFORMATION = 16 octets.
  TInfoDemarrage = record
    cb: DWORD;
    lpReserved: Longint;
    lpDesktop: Longint;
    lpTitle: Longint;
    dwX: DWORD;
    dwY: DWORD;
    dwXSize: DWORD;
    dwYSize: DWORD;
    dwXCountChars: DWORD;
    dwYCountChars: DWORD;
    dwFillAttribute: DWORD;
    dwFlags: DWORD;
    wShowWindow: Word;
    cbReserved2: Word;
    lpReserved2: Longint;
    hStdInput: Longint;
    hStdOutput: Longint;
    hStdError: Longint;
  end;
  TInfoProcessus = record
    hProcess: Longint;
    hThread: Longint;
    dwProcessId: DWORD;
    dwThreadId: DWORD;
  end;

function CreerProcessus(lpApplicationName: String; lpCommandLine: String;
  lpProcessAttributes, lpThreadAttributes: Longint; bInheritHandles: Longint;
  dwCreationFlags: DWORD; lpEnvironment: Longint; lpCurrentDirectory: String;
  var lpStartupInfo: TInfoDemarrage;
  var lpProcessInformation: TInfoProcessus): Longint;
  external 'CreateProcessW@kernel32.dll stdcall';
function AttendreObjet(hHandle: Longint; dwMilliseconds: DWORD): DWORD;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function LireCodeSortie(hProcess: Longint; var lpExitCode: DWORD): Longint;
  external 'GetExitCodeProcess@kernel32.dll stdcall';
function TerminerProcessus(hProcess: Longint; uExitCode: DWORD): Longint;
  external 'TerminateProcess@kernel32.dll stdcall';
function FermerDescripteur(hObject: Longint): Longint;
  external 'CloseHandle@kernel32.dll stdcall';

var
  // Action choisie (première page, ou /ACTION= en silencieux).
  Mode: Integer;
  ModeImpossible: String;

  // Installation existante, relevée au démarrage (InitializeSetup).
  DossierApplication: String;          // '' : aucune installation trouvée
  DesinstallateurApplication: String;  // unins000.exe, '' si absent
  // Chemin du désinstallateur tel que relevé dans UninstallString, même si le
  // fichier manque ('' si la valeur est absente).
  DesinstallateurReleve: String;
  VersionInstallee: String;
  // Dossier d'installation égal à (ou contenant) un dossier connu : son
  // contenu n'est jamais touché directement par « Tout supprimer ».
  ApplicationProtegee: Boolean;

  // Pages.
  PageAction: TInputOptionWizardPage;
  IndexInstaller, IndexMettreAJour, IndexDesinstaller, IndexToutSupprimer: Integer;
  PageBibliotheque: TInputDirWizardPage;
  PageBase: TInputDirWizardPage;
  PageRecapitulatif: TOutputMsgWizardPage;
  PageDesinstallation: TInputOptionWizardPage;
  PageListe: TOutputMsgMemoWizardPage;
  PageResultat: TOutputMsgMemoWizardPage;

  // Le dossier {app} existait avant « Désinstaller » ou « Tout supprimer » :
  // sinon, le dossier vide créé par Inno Setup est retiré à la fin.
  DossierAppExistaitAvant: Boolean;

  // Choix de la désinstallation (cases, questions ou paramètres). Sources
  // implique Titres (un titre ne peut pas exister sans sa source).
  ChoixChapitres, ChoixSources, ChoixTitres: Boolean;
  // Cases de la fenêtre du désinstallateur (CaseSourcesCliquee).
  CaseSourcesFenetre, CaseTitresFenetre: TNewCheckBox;

  // Désinstallateur (unins000.exe) : dossiers des chapitres décidés à
  // l'étape usUninstall (installation.json encore présent), traités à
  // l'étape usPostUninstall.
  DossiersChapitresDesinstallation: TArrayOfString;
  ChapitresASupprimer: Boolean;

  // « Tout supprimer » : relevé fait avant toute suppression.
  ReleveFait: Boolean;
  DesinstallationReussie: Boolean;
  DossiersChapitres: TArrayOfString;
  OriginesChapitres: TArrayOfString;
  MotifsChapitres: TArrayOfString;
  ContenusChapitres: TArrayOfString;
  DossiersBases: TArrayOfString;
  DossierCacheReleve: String;
  CommandeDemarrage: String;           // valeur Run à supprimer, '' sinon
  ApprouveASupprimer: Boolean;

  // Résumé (page « Résultat » et journal).
  Resume: String;
  Echecs: Integer;

// ---------------------------------------------------------------------------
// Outils.
// ---------------------------------------------------------------------------

// Vérification [Files], [Icons], [Run], Uninstallable : seulement pour
// « Installer » et « Mettre à jour ».
function EstModeInstallation: Boolean;
begin
  Result := (Mode = ModeInstaller) or (Mode = ModeMettreAJour);
end;

// Échappe une chaîne pour l'écrire entre guillemets dans du JSON.
function EchapperJson(const Texte: String): String;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(Texte) do
  begin
    C := Texte[I];
    if C = '\' then
      Result := Result + '\\'
    else if C = '"' then
      Result := Result + '\"'
    else if Ord(C) < 32 then
      Result := Result + '\u' + Format('%.4x', [Ord(C)])
    else
      Result := Result + C;
  end;
end;

// Lit la valeur texte de "Cle" dans un fichier JSON simple (UTF-8, avec ou
// sans BOM). Renvoie '' si le fichier est absent ou illisible, ou si la valeur
// n'est pas une chaîne.
function LireValeurJson(const Fichier, Cle: String): String;
var
  Brut: AnsiString;
  Texte, Motif, Valeur: String;
  P, I, Code: Integer;
  C: Char;
begin
  Result := '';
  if not FileExists(Fichier) then
    Exit;
  if not LoadStringFromFile(Fichier, Brut) then
    Exit;
  Texte := UTF8Decode(Brut);
  Motif := '"' + Cle + '"';
  P := Pos(Motif, Texte);
  if P = 0 then
    Exit;
  I := P + Length(Motif);
  while (I <= Length(Texte)) and ((Texte[I] = ' ') or (Texte[I] = #9) or
    (Texte[I] = #10) or (Texte[I] = #13) or (Texte[I] = ':')) do
    I := I + 1;
  if (I > Length(Texte)) or (Texte[I] <> '"') then
    Exit;
  I := I + 1;
  Valeur := '';
  while I <= Length(Texte) do
  begin
    C := Texte[I];
    if C = '"' then
    begin
      // Un caractère de contrôle (< 32) n'a rien à faire dans un chemin :
      // valeur refusée.
      for I := 1 to Length(Valeur) do
        if Ord(Valeur[I]) < 32 then
          Exit;
      Result := Valeur;
      Exit;
    end;
    if C = '\' then
    begin
      I := I + 1;
      if I > Length(Texte) then
        Exit;
      C := Texte[I];
      if (C = '"') or (C = '\') or (C = '/') then
        Valeur := Valeur + C
      else if C = 'n' then
        Valeur := Valeur + #10
      else if C = 'r' then
        Valeur := Valeur + #13
      else if C = 't' then
        Valeur := Valeur + #9
      else if C = 'b' then
        Valeur := Valeur + #8
      else if C = 'f' then
        Valeur := Valeur + #12
      else if C = 'u' then
      begin
        if I + 4 > Length(Texte) then
          Exit;
        Code := StrToIntDef('$' + Copy(Texte, I + 1, 4), -1);
        if Code < 0 then
          Exit;
        Valeur := Valeur + Chr(Code);
        I := I + 4;
      end
      else
        Exit;
    end
    else
      Valeur := Valeur + C;
    I := I + 1;
  end;
end;

// Valeur de "Cle" dans DossierApp\installation.json, sans espace autour ni
// barre finale ('' si absente).
function LireInstallationJson(const DossierApp, Cle: String): String;
begin
  Result := '';
  if DossierApp = '' then
    Exit;
  Result := Trim(LireValeurJson(AddBackslash(DossierApp) +
    NomFichierInstallation, Cle));
  if Result <> '' then
    Result := RemoveBackslashUnlessRoot(Result);
end;

// Vrai si /Nom figure sur la ligne de commande (sans tenir compte de la casse).
function ParametrePresent(const Nom: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/' + Nom) = 0 then
    begin
      Result := True;
      Exit;
    end;
end;

function CleDesinstallationApplication: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
    ExpandConstant('{#IdApplication}') + '_is1';
end;

// Valeur mémorisée par Inno Setup (RegisterPreviousData) dans la clé de
// désinstallation, '' si absente.
function LireDonneeMemorisee(const Cle: String): String;
var
  Valeur: String;
begin
  Result := '';
  if RegQueryStringValue(HKCU, CleDesinstallationApplication,
    'Inno Setup CodeFile: ' + Cle, Valeur) then
    Result := Trim(Valeur);
  if Result <> '' then
    Result := RemoveBackslashUnlessRoot(Result);
end;

// Pointeur HKCU\{#ClePointeur} (voir l'en-tête) : valeur Nom ('' si absente).
// Noms : ClePreviousData (chapitres) et ClePreviousDataBase (base).
function LirePointeur(const Nom: String): String;
var
  Valeur: String;
begin
  Result := '';
  if RegQueryStringValue(HKCU, '{#ClePointeur}', Nom, Valeur) then
    Result := Trim(Valeur);
  if Result <> '' then
    Result := RemoveBackslashUnlessRoot(Result);
end;

procedure EcrirePointeur(const Chapitres, Base: String);
begin
  if Chapitres <> '' then
    RegWriteStringValue(HKCU, '{#ClePointeur}', ClePreviousData, Chapitres);
  if Base <> '' then
    RegWriteStringValue(HKCU, '{#ClePointeur}', ClePreviousDataBase, Base);
  Log('Pointeur des emplacements écrit (HKCU\{#ClePointeur}) : ' + Chapitres +
    ' ; ' + Base);
end;

function MemeDossier(const A, B: String): Boolean;
begin
  Result := CompareText(AddBackslash(Trim(A)), AddBackslash(Trim(B))) = 0;
end;

// Ajoute D à Liste s'il n'est ni vide ni déjà présent.
procedure AjouterSansDoublon(var Liste: TArrayOfString; const D: String);
var
  I, N: Integer;
begin
  if Trim(D) = '' then
    Exit;
  N := GetArrayLength(Liste);
  for I := 0 to N - 1 do
    if MemeDossier(Liste[I], D) then
      Exit;
  SetArrayLength(Liste, N + 1);
  Liste[N] := RemoveBackslashUnlessRoot(Trim(D));
end;

// ---------------------------------------------------------------------------
// Dossier de la base.
// ---------------------------------------------------------------------------

function DossierBaseParDefaut: String;
begin
  Result := RemoveBackslashUnlessRoot(ExpandConstant('{#DossierBase}'));
end;

function AncienDossierBase: String;
begin
  Result := RemoveBackslashUnlessRoot(ExpandConstant('{#AncienDossierBase}'));
end;

// Dossier par défaut ou ancien dossier : ils appartiennent à l'application
// (supprimés en entier par « Tout supprimer »).
function EstDossierBaseApplication(const Dossier: String): Boolean;
begin
  Result := MemeDossier(Dossier, DossierBaseParDefaut) or
    MemeDossier(Dossier, AncienDossierBase);
end;

// Dossiers où la base peut se trouver, dans l'ordre de recherche :
// "dossierBase" de installation.json (ou valeur mémorisée), dossier par
// défaut, ancien dossier.
procedure ListerDossiersBase(const DossierApp: String; var Liste: TArrayOfString);
var
  Choisi: String;
begin
  SetArrayLength(Liste, 0);
  Choisi := LireInstallationJson(DossierApp, CleDossierBase);
  if Choisi = '' then
    Choisi := LireDonneeMemorisee(ClePreviousDataBase);
  if (Choisi <> '') and EstCheminComplet(Choisi) then
    AjouterSansDoublon(Liste, Choisi);
  // Pointeur : il survit à « Désinstaller ».
  Choisi := LirePointeur(ClePreviousDataBase);
  if (Choisi <> '') and EstCheminComplet(Choisi) then
    AjouterSansDoublon(Liste, Choisi);
  AjouterSansDoublon(Liste, DossierBaseParDefaut);
  AjouterSansDoublon(Liste, AncienDossierBase);
end;

// Dossier des chapitres choisi dans l'application : emplacements.json du
// premier dossier de la base qui en contient un, '' sinon.
function DossierChapitresApplication(const DossierApp: String): String;
var
  Bases: TArrayOfString;
  I: Integer;
begin
  Result := '';
  ListerDossiersBase(DossierApp, Bases);
  for I := 0 to GetArrayLength(Bases) - 1 do
  begin
    Result := Trim(LireValeurJson(AddBackslash(Bases[I]) +
      NomFichierEmplacements, CleDossierChapitres));
    if Result <> '' then
    begin
      Result := RemoveBackslashUnlessRoot(Result);
      Exit;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Vérification des dossiers choisis à l'installation.
// ---------------------------------------------------------------------------

// Message d'erreur si le dossier de la bibliothèque est refusé, sinon ''.
function VerifierDossierBibliotheque(const Dossier, DossierApp: String): String;
var
  Bibliotheque, Application: String;
begin
  Result := '';
  Bibliotheque := Trim(Dossier);
  if Bibliotheque = '' then
  begin
    Result := 'Choisissez le dossier de votre bibliothèque.';
    Exit;
  end;
  // Chemin complet : lecteur (C:\…) ou chemin réseau (\\nas\partage\…).
  if not EstCheminComplet(Bibliotheque) then
  begin
    Result := 'Indiquez un chemin complet (par exemple D:\Bibliothèque ou ' +
      '\\nas\partage\Bibliothèque).';
    Exit;
  end;
  // Les chapitres ne vont pas dans le dossier du programme : il est remplacé
  // à chaque mise à jour.
  Bibliotheque := Lowercase(AddBackslash(Bibliotheque));
  Application := Lowercase(AddBackslash(Trim(DossierApp)));
  if Copy(Bibliotheque, 1, Length(Application)) = Application then
    Result := 'Le dossier de la bibliothèque ne peut pas se trouver dans le ' +
      'dossier d''installation du programme. Choisissez un autre dossier.';
end;

// Message d'erreur si le dossier de la base est refusé, sinon ''. Plus strict
// que pour les chapitres : « Tout supprimer » doit pouvoir y retirer la base
// sans jamais toucher à un dossier du système ou de l'utilisateur.
function VerifierDossierBase(const Dossier, DossierApp, Chapitres: String): String;
var
  Base: String;
begin
  Result := '';
  Base := RemoveBackslashUnlessRoot(Trim(Dossier));
  if Base = '' then
    Result := 'Choisissez le dossier de la base.'
  else if not EstCheminComplet(Base) then
    Result := 'Indiquez un chemin complet pour la base (par exemple ' +
      'D:\Bibliotheque\base).'
  else if EstCheminSuspect(Base) then
    Result := 'Ce chemin n''est pas pris en charge pour la base (\\?\, ' +
      '« . », « .. », « ~ » ou « / ») : indiquez le chemin complet habituel.'
  else if EstRacine(Base) then
    Result := 'La base ne peut pas être à la racine d''un disque ou d''un ' +
      'partage : choisissez un sous-dossier (par exemple D:\Bibliotheque\base).'
  else if EstDossierProtege(Base) then
    Result := 'Ce dossier est un dossier du système ou de l''utilisateur ' +
      '(Documents, Bureau, AppData…) : choisissez un sous-dossier qui sera ' +
      'réservé à la base (par exemple ' + DossierBaseParDefaut + ').'
  // Dans (ou autour de) un dossier réservé à l'application : « Tout
  // supprimer » supprime ceux-ci en entier. Seuls le dossier par défaut et
  // l'ancien dossier eux-mêmes sont acceptés.
  else if not MemeDossier(Base, DossierBaseParDefaut) and
    not MemeDossier(Base, AncienDossierBase) and
    (EstDansDossier(Base, DossierBaseParDefaut) or
    EstDansDossier(DossierBaseParDefaut, Base) or
    EstDansDossier(Base, ExtractFileDir(AncienDossierBase)) or
    EstDansDossier(ExtractFileDir(AncienDossierBase), Base)) then
    Result := 'Ce dossier est dans (ou contient) un dossier réservé à ' +
      'l''application (' + DossierBaseParDefaut + ' ou ' +
      ExtractFileDir(AncienDossierBase) + '). Choisissez le dossier proposé, ' +
      'ou un dossier séparé.'
  else if EstDansDossier(Base, DossierApp) then
    Result := 'La base ne peut pas se trouver dans le dossier d''installation ' +
      'du programme. Choisissez un autre dossier.'
  else if (Trim(Chapitres) <> '') and MemeDossier(Base, Chapitres) then
    Result := 'La base et les chapitres téléchargés doivent être dans deux ' +
      'dossiers différents.';
end;

// Vrai si Dossier ne contient rien (ni fichier ni dossier).
function DossierVide(const Dossier: String): Boolean;
var
  Trouve: TFindRec;
begin
  Result := True;
  if FindFirst(AddBackslash(Dossier) + '*', Trouve) then
  try
    repeat
      if (Trouve.Name <> '.') and (Trouve.Name <> '..') then
        Result := False;
    until (not Result) or not FindNext(Trouve);
  finally
    FindClose(Trouve);
  end;
end;

// « Installer » : message d'erreur si le dossier du programme est refusé,
// sinon ''. Accepté : dossier nouveau ou vide, ou ancienne installation de
// l'application (bibliotheque_perso.exe présent), jamais un dossier de projet
// (pubspec.yaml, .git) ni un dossier du système ou de l'utilisateur.
function VerifierDossierProgramme(const Dossier: String): String;
var
  D: String;
begin
  Result := '';
  D := RemoveBackslashUnlessRoot(Trim(Dossier));
  if not DirExists(D) then
    Exit;
  if EstDossierProtege(D) then
    Result := 'Ce dossier est un dossier du système ou de l''utilisateur. ' +
      'Choisissez un dossier vide ou nouveau, réservé au programme (par ' +
      'exemple ' + ExpandConstant('{#DossierProgrammeParDefaut}') + ').'
  else if FileExists(AddBackslash(D) + 'pubspec.yaml') or
    DirExists(AddBackslash(D) + '.git') or FileExists(AddBackslash(D) + '.git') then
    Result := 'Ce dossier contient un projet (pubspec.yaml ou .git) : le ' +
      'programme ne doit pas y être installé. Choisissez un dossier vide ou ' +
      'nouveau (par exemple ' + ExpandConstant('{#DossierProgrammeParDefaut}') + ').'
  else if not DossierVide(D) and
    not FileExists(AddBackslash(D) + '{#NomExecutable}') then
    Result := 'Ce dossier n''est pas vide et ne contient pas d''installation ' +
      'de {#NomApplication}. Choisissez un dossier vide ou nouveau (par exemple ' +
      ExpandConstant('{#DossierProgrammeParDefaut}') + ').';
end;

// ---------------------------------------------------------------------------
// Application ouverte : arrêt avant installation, mise à jour ou
// désinstallation (voir l'en-tête).
// ---------------------------------------------------------------------------

// Nombre de processus {#NomExecutable} dont le chemin complet est Exe (casse
// ignorée) ; si Arreter, chacun est arrêté (Win32_Process.Terminate). Les
// processus d'un autre chemin ne sont jamais touchés. -1 si WMI est
// indisponible (le Restart Manager reste alors seul).
function ProcessusApplication(const Exe: String; const Arreter: Boolean): Integer;
var
  Localisateur, Service, Liste, Element: Variant;
  I, Total: Integer;
  Chemin: String;
begin
  Result := 0;
  try
    Localisateur := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Localisateur.ConnectServer('.', 'root\CIMV2');
    Liste := Service.ExecQuery(
      'SELECT * FROM Win32_Process WHERE Name = ''{#NomExecutable}''');
    Total := Liste.Count;
    for I := 0 to Total - 1 do
    begin
      Element := Liste.ItemIndex(I);
      // Chemin illisible (processus d'un autre utilisateur) : pas le nôtre.
      if not VarIsNull(Element.ExecutablePath) then
      begin
        Chemin := Element.ExecutablePath;
        if CompareText(Chemin, Exe) = 0 then
        begin
          Result := Result + 1;
          if Arreter then
          begin
            Log('Arrêt du processus ' + IntToStr(Element.ProcessId) + ' (' +
              Chemin + ').');
            Element.Terminate();
          end;
        end;
      end;
    end;
  except
    Log('Recherche des processus impossible (WMI) : ' + GetExceptionMessage);
    Result := -1;
  end;
end;

// Arrête l'application lancée depuis Exe, après accord du client si Demander
// (Oui par défaut avec /SUPPRESSMSGBOXES). Renvoie '' si elle n'est pas (ou
// plus) ouverte, sinon le message d'erreur (refus du client ou échec).
// Action : « l'installation », « la désinstallation »…
function FermerApplication(const Exe, Action: String; const Demander: Boolean): String;
var
  Attente: Integer;
begin
  Result := '';
  if ProcessusApplication(Exe, False) <= 0 then
    Exit;
  if Demander and (SuppressibleMsgBox(
    '{#NomApplication} est ouverte, peut-être seulement dans la zone de ' +
    'notification (icône près de l''horloge). Elle doit être fermée pour ' +
    'continuer ' + Action + '.' + #13#10#13#10 +
    'Oui : la fermer maintenant. Un téléchargement en cours sera interrompu.' + #13#10 +
    'Non : annuler. Vous pouvez la quitter vous-même (clic droit sur son ' +
    'icône > Quitter), puis relancer ' + Action + '.',
    mbConfirmation, MB_YESNO, IDYES) <> IDYES) then
  begin
    Result := '{#NomApplication} est encore ouverte : quittez-la (clic droit ' +
      'sur son icône dans la zone de notification > Quitter), puis relancez ' +
      Action + '.';
    Exit;
  end;
  ProcessusApplication(Exe, True);
  Attente := 0;
  while (ProcessusApplication(Exe, False) > 0) and (Attente < AttenteArretMaxMs) do
  begin
    Sleep(250);
    Attente := Attente + 250;
  end;
  if ProcessusApplication(Exe, False) > 0 then
    Result := 'Impossible de fermer {#NomApplication}. Quittez-la (clic droit ' +
      'sur son icône dans la zone de notification > Quitter), puis relancez ' +
      Action + '. Rien n''a été modifié.'
  else
  begin
    Log('Application arrêtée : ' + Exe);
    // Le temps que Windows libère les fichiers (base, vues web).
    Sleep(1000);
  end;
end;

// ---------------------------------------------------------------------------
// Désinstallation : appel de l'application pour modifier la base.
// ---------------------------------------------------------------------------

// Résumé des choix pour la base (« sources et titres supprimés »).
function TexteChoixBase(const Sources, Titres: Boolean): String;
begin
  if Sources and Titres then
    Result := 'sources et titres supprimés'
  else if Sources then
    Result := 'sources supprimées'
  else if Titres then
    Result := 'titres supprimés'
  else
    Result := 'rien à modifier';
end;

// Lance DossierApp\{#NomExecutable} --desinstallation … (fenêtre jamais
// affichée : windows\runner\main.cpp) et attend sa fin, au plus
// DelaiAppelApplicationMs (le processus, lancé ici, est alors arrêté).
// Renvoie '' si le code de sortie est 0, sinon le motif de l'échec.
// L'application doit déjà être arrêtée (FermerApplication).
function AppelerApplicationDesinstallation(const DossierApp: String;
  const Sources, Titres, Chapitres: Boolean): String;
var
  Exe, Commande: String;
  Demarrage: TInfoDemarrage;
  Processus: TInfoProcessus;
  Etat, Code: DWORD;
  Attente: Integer;
begin
  Result := '';
  Exe := AddBackslash(DossierApp) + '{#NomExecutable}';
  if (DossierApp = '') or not FileExists(Exe) then
  begin
    Result := 'programme introuvable : ' + Exe;
    Log('Appel de l''application impossible : ' + Result);
    Exit;
  end;
  Commande := '"' + Exe + '" ' + ArgumentDesinstallation;
  if Sources then
    Commande := Commande + ' ' + ArgumentSupprimerSources;
  // Sources implique Titres (un titre ne peut pas exister sans sa source).
  if Titres or Sources then
    Commande := Commande + ' ' + ArgumentSupprimerTitres;
  if Chapitres then
    Commande := Commande + ' ' + ArgumentChapitresSupprimes;
  Log('Appel de l''application : ' + Commande);

  Demarrage.cb := 68;
  Demarrage.lpReserved := 0;
  Demarrage.lpDesktop := 0;
  Demarrage.lpTitle := 0;
  Demarrage.dwX := 0;
  Demarrage.dwY := 0;
  Demarrage.dwXSize := 0;
  Demarrage.dwYSize := 0;
  Demarrage.dwXCountChars := 0;
  Demarrage.dwYCountChars := 0;
  Demarrage.dwFillAttribute := 0;
  Demarrage.dwFlags := DemarrageAvecAffichage;
  Demarrage.wShowWindow := SW_HIDE;
  Demarrage.cbReserved2 := 0;
  Demarrage.lpReserved2 := 0;
  Demarrage.hStdInput := 0;
  Demarrage.hStdOutput := 0;
  Demarrage.hStdError := 0;
  Processus.hProcess := 0;
  Processus.hThread := 0;
  Processus.dwProcessId := 0;
  Processus.dwThreadId := 0;

  if CreerProcessus(Exe, Commande, 0, 0, 0, CreationSansFenetre, 0, DossierApp,
    Demarrage, Processus) = 0 then
  begin
    Result := 'lancement impossible (' + SysErrorMessage(DLLGetLastError) + ')';
    Log('Appel de l''application : ' + Result);
    Exit;
  end;
  try
    Attente := 0;
    Etat := AttendreObjet(Processus.hProcess, 0);
    while (Etat = AttenteDepassee) and (Attente < DelaiAppelApplicationMs) do
    begin
      Etat := AttendreObjet(Processus.hProcess, 250);
      Attente := Attente + 250;
    end;
    if Etat = AttenteDepassee then
    begin
      // Processus lancé ici (handle) : seul lui est arrêté.
      TerminerProcessus(Processus.hProcess, 1);
      AttendreObjet(Processus.hProcess, 5000);
      Result := 'pas de fin après ' + IntToStr(DelaiAppelApplicationMs div 1000) +
        ' s, application arrêtée';
    end
    else
    begin
      Code := 0;
      if LireCodeSortie(Processus.hProcess, Code) = 0 then
        Result := 'code de sortie illisible'
      else if Code <> 0 then
        Result := 'code de sortie ' + IntToStr(Code);
    end;
  finally
    FermerDescripteur(Processus.hThread);
    FermerDescripteur(Processus.hProcess);
  end;
  if Result = '' then
    Log('Appel de l''application réussi (code 0).')
  else
    Log('Appel de l''application en échec : ' + Result);
end;

// Prévient le client de l'échec de l'appel (journal seul en silencieux).
// Vrai si l'application n'a pas pu être lancée : la base n'a pas été touchée.
// Sinon (code non nul, délai dépassé), elle a pu être modifiée en partie :
// l'application traite chapitres, titres et sources dans des transactions
// séparées.
function EchecAvantLancement(const Motif: String): Boolean;
begin
  Result := (Pos('programme introuvable', Motif) = 1) or
    (Pos('lancement impossible', Motif) = 1);
end;

procedure SignalerEchecBase(const Motif: String; const Silencieux: Boolean);
var
  Texte: String;
begin
  if EchecAvantLancement(Motif) then
  begin
    Texte := 'La base de {#NomApplication} n''a pas pu être modifiée (' + Motif +
      ').' + #13#10#13#10 + 'La désinstallation continue sans toucher à la ' +
      'base : vos sources et vos titres y sont conservés. Vous pourrez les ' +
      'retirer depuis l''application après une nouvelle installation, ou tout ' +
      'effacer avec « Tout supprimer ».';
    Log('Base non modifiée : ' + Motif);
  end
  else
  begin
    Texte := 'La base de {#NomApplication} n''a pas pu être entièrement ' +
      'nettoyée (' + Motif + ') : certaines données ont peut-être déjà été ' +
      'supprimées. Détails dans le journal de l''application ' +
      '(Documents\bibliotheque_perso\journaux).' + #13#10#13#10 +
      'La désinstallation continue. Pour tout effacer, utilisez « Tout ' +
      'supprimer ».';
    Log('Base pas entièrement nettoyée (modification partielle possible) : ' +
      Motif);
  end;
  if not Silencieux then
    MsgBox(Texte, mbError, MB_OK);
end;

// ---------------------------------------------------------------------------
// Installation existante.
// ---------------------------------------------------------------------------

procedure ReleverInstallation;
var
  Valeur: String;
begin
  DossierApplication := '';
  DesinstallateurApplication := '';
  DesinstallateurReleve := '';
  VersionInstallee := '';
  ApplicationProtegee := False;
  if RegQueryStringValue(HKCU, CleDesinstallationApplication, 'InstallLocation',
    Valeur) then
    DossierApplication := Trim(Valeur);
  if RegQueryStringValue(HKCU, CleDesinstallationApplication, 'DisplayVersion',
    Valeur) then
    VersionInstallee := Trim(Valeur);
  if RegQueryStringValue(HKCU, CleDesinstallationApplication, 'UninstallString',
    Valeur) then
  begin
    Valeur := Trim(RemoveQuotes(Trim(Valeur)));
    DesinstallateurReleve := Valeur;
    if FileExists(Valeur) then
      DesinstallateurApplication := Valeur;
    if (DossierApplication = '') and (Valeur <> '') then
      DossierApplication := ExtractFileDir(Valeur);
  end;
  if DossierApplication <> '' then
  begin
    DossierApplication := RemoveBackslashUnlessRoot(DossierApplication);
    // Garde-fou : jamais un chemin incomplet.
    if not EstCheminComplet(DossierApplication) then
    begin
      Log('Dossier d''installation refusé : ' + DossierApplication);
      DossierApplication := '';
      DesinstallateurApplication := '';
    end
    // Racine ou dossier connu (Documents, Bureau, Program Files…) : le
    // désinstallateur du programme (qui ne retire que ses propres fichiers)
    // est lancé, mais rien d'autre n'y est supprimé directement.
    else if EstDossierProtege(DossierApplication) then
    begin
      Log('Dossier d''installation protégé (racine ou dossier connu), son ' +
        'contenu ne sera pas touché directement : ' + DossierApplication);
      ApplicationProtegee := True;
    end;
  end;
  if DossierApplication <> '' then
    Log('Installation trouvée : ' + DossierApplication + ' (version ' +
      VersionInstallee + ', désinstallateur : ' + DesinstallateurApplication + ')')
  else
    Log('Aucune installation trouvée (clé ' + CleDesinstallationApplication + ').');
end;

// Installée = « Mettre à jour » et « Désinstaller » possibles : clé de
// désinstallation et désinstallateur présents.
function ApplicationInstallee: Boolean;
begin
  Result := (DossierApplication <> '') and (DesinstallateurApplication <> '');
end;

function ExeInstalle: String;
begin
  Result := AddBackslash(DossierApplication) + '{#NomExecutable}';
end;

// ---------------------------------------------------------------------------
// « Tout supprimer » : relevé (avant toute suppression) et liste.
// ---------------------------------------------------------------------------

// Ajoute un dossier des chapitres connu (sans doublon). Origine : d'où vient
// le chemin, pour la liste affichée.
procedure AjouterDossierChapitres(const Dossier, Origine: String);
var
  D: String;
  I, N: Integer;
begin
  D := Trim(Dossier);
  if D = '' then
    Exit;
  D := RemoveBackslashUnlessRoot(D);
  // Les refus (racine, dossier connu, pas de repère…) sont décidés plus tard
  // (MotifRefusChapitres), pour être affichés dans la liste.
  N := GetArrayLength(DossiersChapitres);
  for I := 0 to N - 1 do
    if MemeDossier(DossiersChapitres[I], D) then
      Exit;
  SetArrayLength(DossiersChapitres, N + 1);
  SetArrayLength(OriginesChapitres, N + 1);
  DossiersChapitres[N] := D;
  OriginesChapitres[N] := Origine;
  Log('Dossier des chapitres connu (' + Origine + ') : ' + D);
end;

procedure ReleverDemarrage;
var
  Commande, Exe: String;
  Lance: Boolean;
begin
  CommandeDemarrage := '';
  ApprouveASupprimer := False;
  if RegQueryStringValue(HKCU, CleDemarrageRun, NomEntreeDemarrage, Commande) then
  begin
    if DossierApplication <> '' then
    begin
      Exe := ExeInstalle;
      Lance := Pos(Lowercase(Exe), Lowercase(Commande)) > 0;
    end
    else
      Lance := Pos(Lowercase('{#NomExecutable}'), Lowercase(Commande)) > 0;
    if Lance then
    begin
      CommandeDemarrage := Commande;
      ApprouveASupprimer := RegValueExists(HKCU, CleDemarrageApprouve,
        NomEntreeDemarrage);
    end
    else
      Log('Démarrage avec Windows d''une autre copie, gardé : ' + Commande);
  end
  else
    // Valeur orpheline (sans valeur Run) : elle ne sert plus à rien.
    ApprouveASupprimer := RegValueExists(HKCU, CleDemarrageApprouve,
      NomEntreeDemarrage);
end;

// Relevé complet. La décision pour les chapitres est prise ici, avant que le
// désinstallateur du programme ne supprime le repère.
// LIMITE : un dossier sur un NAS éteint ou un lecteur réseau déconnecté peut
// faire attendre quelques dizaines de secondes (délai réseau de Windows dans
// DirExists) ; il est alors noté « introuvable ou injoignable » et rien n'y
// est supprimé.
procedure ReleverToutSupprimer;
var
  I, N: Integer;
begin
  SetArrayLength(DossiersChapitres, 0);
  SetArrayLength(OriginesChapitres, 0);
  DossierCacheReleve := RemoveBackslashUnlessRoot(ExpandConstant('{#DossierCache}'));
  ListerDossiersBase(DossierApplication, DossiersBases);
  for I := 0 to GetArrayLength(DossiersBases) - 1 do
    Log('Dossier de la base possible : ' + DossiersBases[I]);
  AjouterDossierChapitres(LireInstallationJson(DossierApplication,
    CleDossierBibliotheque), 'choisi à l''installation');
  AjouterDossierChapitres(LireDonneeMemorisee(ClePreviousData),
    'choisi à l''installation');
  AjouterDossierChapitres(LirePointeur(ClePreviousData),
    'choisi à l''installation');
  for I := 0 to GetArrayLength(DossiersBases) - 1 do
    AjouterDossierChapitres(LireValeurJson(AddBackslash(DossiersBases[I]) +
      NomFichierEmplacements, CleDossierChapitres), 'choisi dans l''application');
  AjouterDossierChapitres(DossierChapitresParDefaut, 'dossier par défaut');
  ReleverDemarrage;

  N := GetArrayLength(DossiersChapitres);
  SetArrayLength(MotifsChapitres, N);
  SetArrayLength(ContenusChapitres, N);
  for I := 0 to N - 1 do
  begin
    MotifsChapitres[I] := MotifRefusChapitres(DossiersChapitres[I],
      DossierApplication);
    if MotifsChapitres[I] = '' then
      ContenusChapitres[I] := ContenuApplication(DossiersChapitres[I])
    else
    begin
      ContenusChapitres[I] := '';
      Log('Dossier des chapitres gardé (' + MotifsChapitres[I] + ') : ' +
        DossiersChapitres[I]);
    end;
  end;
  ReleveFait := True;
end;

function TexteListe: String;
var
  I: Integer;
  Contenu, Ligne, Fin: String;
  BaseTrouvee: Boolean;
begin
  Fin := #13#10;
  Result := 'Les éléments suivants vont être supprimés DÉFINITIVEMENT (ils ne ' +
    'passent pas par la Corbeille) :' + Fin + Fin;

  Result := Result + '1. Le programme' + Fin;
  if DossierApplication <> '' then
  begin
    Result := Result + '   ' + DossierApplication + Fin +
      '   (fichiers du programme, raccourcis, données du navigateur intégré)' + Fin;
    if ApplicationProtegee then
      Result := Result + '   Ce dossier est un dossier du système ou de ' +
        'l''utilisateur : seul le désinstallateur du programme y retire ses ' +
        'fichiers ; rien d''autre n''y est supprimé.' + Fin;
    if ProcessusApplication(ExeInstalle, False) > 0 then
      Result := Result + '   L''application est ouverte : elle sera fermée ' +
        '(un téléchargement en cours sera interrompu).' + Fin;
  end
  else
    Result := Result + '   Aucune installation trouvée.' + Fin;
  Result := Result + Fin;

  Result := Result + '2. Votre base (titres, sources, listes, réglages)' + Fin;
  BaseTrouvee := False;
  for I := 0 to GetArrayLength(DossiersBases) - 1 do
    if DirExists(DossiersBases[I]) then
    begin
      BaseTrouvee := True;
      if EstDossierBaseApplication(DossiersBases[I]) then
        Result := Result + '   ' + DossiersBases[I] + ' (dossier entier)' + Fin
      else
        Result := Result + '   ' + DossiersBases[I] + ' (dossier choisi : ' +
          'seulement ' + NomFichierBase + ' et ses fichiers -wal, -shm, ' +
          '-journal, et ' + NomFichierEmplacements + ' ; le dossier est ' +
          'supprimé s''il devient vide)' + Fin;
    end;
  if not BaseTrouvee then
    Result := Result + '   Aucune base trouvée.' + Fin;
  if DirExists(DossierCacheReleve) then
    Result := Result + '   ' + DossierCacheReleve + ' (cache, dossier entier)' + Fin;
  Result := Result + Fin;

  Result := Result + '3. Vos chapitres téléchargés' + Fin;
  Ligne := '';
  for I := 0 to GetArrayLength(DossiersChapitres) - 1 do
  begin
    Contenu := ContenusChapitres[I];
    if (MotifsChapitres[I] <> '') or (Contenu = '') then
      Continue;
    Ligne := Ligne + '   ' + DossiersChapitres[I] + ' (' + OriginesChapitres[I] +
      ')' + Fin + '      dans : ' + Contenu + Fin;
  end;
  if Ligne = '' then
    Result := Result + '   Aucun chapitre trouvé.' + Fin
  else
    Result := Result + Ligne +
      '   Seuls les chapitres et couvertures enregistrés par l''application (et ' +
      'ses journaux, rapports et exports dans Documents\bibliotheque_perso) ' +
      'sont supprimés : vos autres fichiers sont gardés, et chaque dossier ' +
      'n''est supprimé que s''il devient vide.' + Fin;
  for I := 0 to GetArrayLength(DossiersChapitres) - 1 do
    if (MotifsChapitres[I] <> '') and not ((OriginesChapitres[I] =
      'dossier par défaut') and not DirExists(DossiersChapitres[I])) then
      Result := Result + '   Rien ne sera supprimé (' + MotifsChapitres[I] +
        ') : ' + DossiersChapitres[I] + Fin;
  Result := Result + Fin;

  Result := Result + '4. Le démarrage avec Windows' + Fin;
  if CommandeDemarrage <> '' then
    Result := Result + '   ' + CommandeDemarrage + Fin
  else if ApprouveASupprimer then
    Result := Result + '   Réglage restant du démarrage avec Windows.' + Fin
  else
    Result := Result + '   Non activé.' + Fin;
end;

// ---------------------------------------------------------------------------
// Suppressions (« Tout supprimer » et résumé de « Désinstaller »).
// ---------------------------------------------------------------------------

procedure Noter(const Texte: String);
begin
  Log(Texte);
  Resume := Resume + Texte + #13#10;
end;

// Supprime un dossier entier de l'application ; note le résultat. Jamais une
// racine, un dossier connu ou un lien (jonction, lien symbolique).
procedure SupprimerDossierEntier(const Dossier, Libelle: String);
begin
  if not DirExists(Dossier) then
    Exit;
  if EstDossierProtege(Dossier) or EstPointDAnalyse(Dossier) then
  begin
    Noter('Gardé : ' + Libelle + ' (racine, dossier connu ou lien) : ' + Dossier);
    Exit;
  end;
  // DelTree d'Inno ne suit pas les jonctions rencontrées dans le dossier : il
  // les retire sans toucher à leur cible (vérifié par essai le 2026-11-25).
  DelTree(Dossier, True, True, True);
  if DirExists(Dossier) then
  begin
    Noter('ÉCHEC : ' + Libelle + ' non supprimé(e) entièrement : ' + Dossier);
    Echecs := Echecs + 1;
  end
  else
    Noter('Supprimé : ' + Libelle + ' (' + Dossier + ')');
end;

// Supprime Dossier s'il est vide ; Libelle '' : rien noté.
procedure SupprimerSiVide(const Dossier, Libelle: String);
begin
  if not DirExists(Dossier) then
    Exit;
  if RemoveDir(Dossier) then
  begin
    if Libelle <> '' then
      Noter('Supprimé : ' + Libelle + ' devenu vide (' + Dossier + ')');
  end
  else if Libelle <> '' then
    Noter('Gardé : ' + Libelle + ', qui contient d''autres fichiers (' +
      Dossier + ')');
end;

// Supprime le parent de Dossier (dossier de l'éditeur) s'il est vide.
procedure SupprimerDossierEditeurSiVide(const Dossier: String);
var
  Parent: String;
begin
  Parent := ExtractFileDir(Dossier);
  if CompareText(ExtractFileName(Parent), NomDossierEditeur) = 0 then
    SupprimerSiVide(Parent, '');
end;

// Supprime un FICHIER (jamais un dossier ni un lien) ; note un échec.
procedure SupprimerFichierProgramme(const Chemin: String);
begin
  if not FileExists(Chemin) or DirExists(Chemin) then
    Exit;
  if EstPointDAnalyse(Chemin) then
  begin
    Noter('Gardé (lien) : ' + Chemin);
    Exit;
  end;
  if not DeleteFile(Chemin) then
  begin
    Noter('ÉCHEC : non supprimé : ' + Chemin);
    Echecs := Echecs + 1;
  end;
end;

// Dossier de la base choisi par le client : seulement les fichiers de
// l'application, puis le dossier s'il est vide (jamais en entier).
procedure SupprimerFichiersBase(const Dossier: String);
var
  Restes: Boolean;
  Trouve: TFindRec;
begin
  if not DirExists(Dossier) then
    Exit;
  if EstCheminSuspect(Dossier) or EstRacine(Dossier) or
    EstDossierProtege(Dossier) or EstPointDAnalyse(Dossier) then
  begin
    Noter('Gardé : base (racine, dossier connu, lien ou chemin suspect) : ' +
      Dossier);
    Exit;
  end;
  SupprimerFichierProgramme(AddBackslash(Dossier) + NomFichierBase);
  SupprimerFichierProgramme(AddBackslash(Dossier) + NomFichierBase + '-wal');
  SupprimerFichierProgramme(AddBackslash(Dossier) + NomFichierBase + '-shm');
  SupprimerFichierProgramme(AddBackslash(Dossier) + NomFichierBase + '-journal');
  SupprimerFichierProgramme(AddBackslash(Dossier) + NomFichierEmplacements);
  SupprimerFichierProgramme(AddBackslash(Dossier) + NomFichierEmplacements + '.tmp');
  // Restes d'une migration de la base par l'application (déplacement
  // interrompu) : *.migration et bibliotheque_perso.db.verification.
  SupprimerFichierProgramme(AddBackslash(Dossier) + NomFichierBase + '.verification');
  if FindFirst(AddBackslash(Dossier) + '*.migration', Trouve) then
  try
    repeat
      if (Trouve.Attributes and (AttributDossier or AttributPointAnalyse)) = 0 then
        SupprimerFichierProgramme(AddBackslash(Dossier) + Trouve.Name);
    until not FindNext(Trouve);
  finally
    FindClose(Trouve);
  end;
  Restes := not RemoveDir(Dossier);
  if Restes then
    Noter('Supprimé : base (' + NomFichierBase + ', ' + NomFichierEmplacements +
      ') ; dossier gardé, il contient d''autres fichiers (' + Dossier + ')')
  else
    Noter('Supprimé : base et son dossier devenu vide (' + Dossier + ')');
end;

// Lance le désinstallateur Inno de l'application en silencieux, avec
// Parametres, et attend sa fin. Inno recopie le désinstallateur dans %TEMP% et
// le relance : on attend en plus que unins000.exe ait disparu. Vrai si code 0
// et fin constatée.
function LancerDesinstallateur(const Parametres: String; var Code: Integer): Boolean;
var
  Attente: Integer;
begin
  Result := False;
  Code := -1;
  Log('Lancement : ' + DesinstallateurApplication + ' ' + Parametres);
  if not Exec(DesinstallateurApplication, Parametres, '', SW_HIDE,
    ewWaitUntilTerminated, Code) then
  begin
    Log('Désinstallateur du programme non lancé : ' + SysErrorMessage(Code));
    Exit;
  end;
  Log('Désinstallateur du programme terminé (code ' + IntToStr(Code) + ').');
  Attente := 0;
  while FileExists(DesinstallateurApplication) and
    (Attente < AttenteDesinstallationMaxMs) do
  begin
    Sleep(250);
    Attente := Attente + 250;
  end;
  // Laisse au désinstallateur le temps de retirer la clé de registre.
  Sleep(500);
  Result := (Code = 0) and not FileExists(DesinstallateurApplication);
end;

procedure DesinstallerProgramme;
var
  Code: Integer;
begin
  DesinstallationReussie := False;
  if DesinstallateurApplication = '' then
  begin
    if DossierApplication <> '' then
      Noter('Désinstallateur du programme absent : fichiers du programme ' +
        'supprimés directement.');
    Exit;
  end;
  DesinstallationReussie := LancerDesinstallateur(
    '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', Code);
  if DesinstallationReussie then
    Noter('Supprimé : programme, raccourcis et entrée « Applications ' +
      'installées » (désinstallateur du programme).')
  else
    Noter('Désinstallateur du programme en échec ou fin non constatée (code ' +
      IntToStr(Code) + ') : restes supprimés directement.');
end;

// Raccourci laissé par une installation sans désinstallateur : supprimé
// seulement s'il lance le {#NomExecutable} de cette installation.
procedure SupprimerRaccourci(const Raccourci: String);
var
  Shell, Lien: Variant;
  Cible: String;
begin
  if not FileExists(Raccourci) then
    Exit;
  try
    Shell := CreateOleObject('WScript.Shell');
    Lien := Shell.CreateShortcut(Raccourci);
    Cible := Lien.TargetPath;
  except
    Log('Cible du raccourci illisible, gardé : ' + Raccourci + ' (' +
      GetExceptionMessage + ')');
    Exit;
  end;
  if CompareText(Cible, ExeInstalle) <> 0 then
  begin
    Log('Raccourci vers une autre copie, gardé : ' + Raccourci + ' -> ' + Cible);
    Exit;
  end;
  if DeleteFile(Raccourci) then
    Noter('Supprimé : raccourci ' + Raccourci)
  else
  begin
    Noter('ÉCHEC : raccourci non supprimé : ' + Raccourci);
    Echecs := Echecs + 1;
  end;
end;

// Restes du dossier d'installation, puis le dossier s'il est vide.
procedure SupprimerRestesInstallation;
var
  Liste, Nom: String;
  P, I: Integer;
  Dossiers: TArrayOfString;
begin
  if DossierApplication = '' then
    Exit;
  if ApplicationProtegee then
  begin
    Noter('Gardé : contenu du dossier d''installation, dossier du système ou ' +
      'de l''utilisateur (' + DossierApplication + ')');
    Exit;
  end;
  if DirExists(AddBackslash(DossierApplication) + NomDossierWebView2) then
    SupprimerDossierEntier(AddBackslash(DossierApplication) + NomDossierWebView2,
      'données du navigateur intégré');
  SupprimerFichierProgramme(AddBackslash(DossierApplication) + NomFichierInstallation);
  if DesinstallationReussie then
  begin
    if DirExists(DossierApplication) then
      SupprimerSiVide(DossierApplication, 'dossier d''installation')
    else
      Noter('Supprimé : dossier d''installation (' + DossierApplication + ')');
    Exit;
  end;
  // Repli, seulement si le désinstallateur du programme manque, a échoué ou
  // n'a pas fini : les FICHIERS de la liste récursive du dossier Release
  // (jamais un dossier entier), puis ses dossiers devenus vides, du plus
  // profond au moins profond.
  Liste := '{#FichiersProgramme}';
  while Liste <> '' do
  begin
    P := Pos('|', Liste);
    if P = 0 then
      P := Length(Liste) + 1;
    Nom := Copy(Liste, 1, P - 1);
    Delete(Liste, 1, P);
    if Nom <> '' then
      SupprimerFichierProgramme(AddBackslash(DossierApplication) + Nom);
  end;
  SetArrayLength(Dossiers, 0);
  Liste := '{#DossiersProgramme}';
  while Liste <> '' do
  begin
    P := Pos('|', Liste);
    if P = 0 then
      P := Length(Liste) + 1;
    Nom := Copy(Liste, 1, P - 1);
    Delete(Liste, 1, P);
    if Nom <> '' then
    begin
      SetArrayLength(Dossiers, GetArrayLength(Dossiers) + 1);
      Dossiers[GetArrayLength(Dossiers) - 1] := Nom;
    end;
  end;
  for I := GetArrayLength(Dossiers) - 1 downto 0 do
  begin
    Nom := AddBackslash(DossierApplication) + Dossiers[I];
    if DirExists(Nom) and not EstPointDAnalyse(Nom) then
      SupprimerSiVide(Nom, '');
    if DirExists(Nom) then
      Noter('Gardé : ' + Nom + ' (contient des fichiers qui ne viennent pas ' +
        'du programme, ou est un lien)');
  end;
  // Fichiers du désinstallateur Inno : seulement ceux dont le nom de base est
  // celui relevé dans UninstallString, et seulement dans le dossier
  // d'installation, jamais pendant qu'il tourne encore.
  if (DesinstallateurReleve <> '') and
    MemeDossier(ExtractFileDir(DesinstallateurReleve), DossierApplication) and
    ((DesinstallateurApplication = '') or
    not FileExists(DesinstallateurApplication)) then
  begin
    Nom := ChangeFileExt(DesinstallateurReleve, '');
    SupprimerFichierProgramme(Nom + '.exe');
    SupprimerFichierProgramme(Nom + '.dat');
    SupprimerFichierProgramme(Nom + '.msg');
  end
  else
    Log('Fichiers du désinstallateur Inno : nom inconnu ou hors du dossier ' +
      'd''installation, rien supprimé (' + DesinstallateurReleve + ').');
  SupprimerRaccourci(ExpandConstant('{userprograms}\{#NomRaccourci}.lnk'));
  SupprimerRaccourci(ExpandConstant('{userdesktop}\{#NomRaccourci}.lnk'));
  if DirExists(DossierApplication) then
    SupprimerSiVide(DossierApplication, 'dossier d''installation')
  else
    Noter('Supprimé : dossier d''installation (' + DossierApplication + ')');
  // Désinstallateur absent ou en échec : l'entrée « Applications installées »
  // ne mènerait plus à rien.
  if RegKeyExists(HKCU, CleDesinstallationApplication) then
  begin
    if RegDeleteKeyIncludingSubkeys(HKCU, CleDesinstallationApplication) then
      Noter('Supprimé : entrée « Applications installées » restante.')
    else
    begin
      Noter('ÉCHEC : entrée « Applications installées » non supprimée.');
      Echecs := Echecs + 1;
    end;
  end;
end;

// Dans un dossier des chapitres : seulement le contenu de l'application.
// La décision (MotifsChapitres) a été prise au relevé, repère encore présent :
// le désinstallateur du programme l'a peut-être supprimé depuis, après avoir
// traité ce dossier avec les mêmes règles.
procedure SupprimerChapitresReleves(const Indice: Integer);
var
  Dossier, Origine, Contenu, Motif: String;
  Supprimes, Restes: Integer;
begin
  Dossier := DossiersChapitres[Indice];
  Origine := OriginesChapitres[Indice];
  Contenu := ContenusChapitres[Indice];
  if MotifsChapitres[Indice] <> '' then
  begin
    if not ((Origine = 'dossier par défaut') and
      (MotifsChapitres[Indice] = 'introuvable ou injoignable')) then
      Noter('Gardé : ' + Dossier + ' (' + Origine + ') : ' +
        MotifsChapitres[Indice] + '.');
    Exit;
  end;
  if Contenu = '' then
  begin
    Log('Rien de l''application dans ' + Dossier);
    Exit;
  end;
  Supprimes := 0;
  Restes := 0;
  if DirExists(Dossier) then
  begin
    Motif := MotifRefusChapitres(Dossier, DossierApplication);
    if Motif = '' then
      SupprimerChapitresDossier(Dossier, True, Supprimes, Restes)
    else if Pos('pas de repère', Motif) = 1 then
      Log('Repère déjà retiré par le désinstallateur du programme, dossier ' +
        'déjà traité : ' + Dossier)
    else
    begin
      Noter('Gardé : ' + Dossier + ' (' + Origine + ') : ' + Motif + '.');
      Exit;
    end;
  end;
  Noter('Supprimé : contenu de l''application (' + Contenu + ') dans ' + Dossier +
    ' (' + Origine + ')');
  if Restes > 0 then
    Noter('Gardé : ' + IntToStr(Restes) + ' fichier(s) ou dossier(s) qui ne ' +
      'viennent pas de l''application (ou verrouillés), dans ' + Dossier +
      ' : détail dans le journal.');
  if DirExists(Dossier) then
    Noter('Gardé : dossier des chapitres, qui contient d''autres fichiers (' +
      Dossier + ')')
  else
    Noter('Supprimé : dossier des chapitres devenu vide (' + Dossier + ')');
end;

// Le désinstallateur du programme a pu retirer ces valeurs avant nous : une
// valeur déjà absente compte comme supprimée.
procedure SupprimerDemarrageReleve;
begin
  if CommandeDemarrage <> '' then
  begin
    if not RegValueExists(HKCU, CleDemarrageRun, NomEntreeDemarrage) or
      RegDeleteValue(HKCU, CleDemarrageRun, NomEntreeDemarrage) then
      Noter('Supprimé : démarrage avec Windows (' + CommandeDemarrage + ')')
    else
    begin
      Noter('ÉCHEC : démarrage avec Windows non supprimé (valeur Run).');
      Echecs := Echecs + 1;
    end;
  end;
  if ApprouveASupprimer and
    not RegValueExists(HKCU, CleDemarrageRun, NomEntreeDemarrage) then
  begin
    if not RegValueExists(HKCU, CleDemarrageApprouve, NomEntreeDemarrage) or
      RegDeleteValue(HKCU, CleDemarrageApprouve, NomEntreeDemarrage) then
      Log('Supprimé : valeur StartupApproved du démarrage avec Windows.')
    else
    begin
      Noter('ÉCHEC : valeur StartupApproved du démarrage avec Windows non supprimée.');
      Echecs := Echecs + 1;
    end;
  end;
end;

// Vrai si Dossier contient (sans l'être) un dossier choisi par le client :
// base hors des dossiers de l'application, ou dossier des chapitres.
function ContientDossierChoisi(const Dossier: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to GetArrayLength(DossiersBases) - 1 do
    if not EstDossierBaseApplication(DossiersBases[I]) and
      EstDansDossier(DossiersBases[I], Dossier) then
      Result := True;
  for I := 0 to GetArrayLength(DossiersChapitres) - 1 do
    if EstDansDossier(DossiersChapitres[I], Dossier) then
      Result := True;
end;

procedure ToutSupprimer;
var
  I: Integer;
begin
  Resume := '';
  Echecs := 0;
  if not ReleveFait then
    ReleverToutSupprimer;
  DesinstallerProgramme;
  SupprimerRestesInstallation;
  for I := 0 to GetArrayLength(DossiersChapitres) - 1 do
    SupprimerChapitresReleves(I);
  for I := 0 to GetArrayLength(DossiersBases) - 1 do
  begin
    // Garde-fou : jamais DelTree d'un dossier de l'application qui contient
    // un dossier choisi par le client (base ou chapitres).
    if EstDossierBaseApplication(DossiersBases[I]) and
      ContientDossierChoisi(DossiersBases[I]) then
    begin
      Noter('Dossier de l''application gardé (il contient un dossier choisi ' +
        'par vous) : seuls les fichiers de la base y sont supprimés.');
      SupprimerFichiersBase(DossiersBases[I]);
    end
    else if EstDossierBaseApplication(DossiersBases[I]) then
    begin
      SupprimerDossierEntier(DossiersBases[I], 'base et réglages');
      SupprimerDossierEditeurSiVide(DossiersBases[I]);
    end
    else
      SupprimerFichiersBase(DossiersBases[I]);
  end;
  SupprimerDossierEntier(DossierCacheReleve, 'cache');
  SupprimerDossierEditeurSiVide(DossierCacheReleve);
  SupprimerDemarrageReleve;
  if RegKeyExists(HKCU, '{#ClePointeur}') then
  begin
    if RegDeleteKeyIncludingSubkeys(HKCU, '{#ClePointeur}') then
      Noter('Supprimé : emplacements mémorisés (HKCU\{#ClePointeur}).')
    else
    begin
      Noter('ÉCHEC : emplacements mémorisés non supprimés (HKCU\{#ClePointeur}).');
      Echecs := Echecs + 1;
    end;
  end;
  if Resume = '' then
    Noter('Rien à supprimer : aucune trace de {#NomApplication} trouvée.');
  if Echecs > 0 then
    Noter(#13#10 + IntToStr(Echecs) + ' élément(s) non supprimé(s) : fichier ' +
      'peut-être ouvert par un autre programme. Relancez « Tout supprimer » ' +
      'après avoir redémarré l''ordinateur.')
  else
    Noter(#13#10 + 'Suppression complète réussie.');
end;

// ---------------------------------------------------------------------------
// « Désinstaller » depuis l'installateur.
// ---------------------------------------------------------------------------

// Journal du désinstallateur Inno, à côté de celui de l'installateur ('' si
// pas de journal).
function JournalDesinstallation: String;
begin
  Result := ExpandConstant('{log}');
  if Result <> '' then
    Result := ChangeFileExt(Result, '') + ' - desinstallation.txt';
end;

// Texte qui suit Repere dans le journal Journal, jusqu'à la fin de la ligne
// ('' si absent).
function LireApresRepere(const Journal, Repere: String): String;
var
  Brut: AnsiString;
  Texte: String;
  P, Fin: Integer;
begin
  Result := '';
  if (Journal = '') or not LoadStringFromFile(Journal, Brut) then
    Exit;
  Texte := UTF8Decode(Brut);
  P := Pos(Repere, Texte);
  if P = 0 then
    Exit;
  Texte := Copy(Texte, P + Length(Repere), Length(Texte));
  Fin := Pos(#13, Texte);
  if Fin = 0 then
    Fin := Pos(#10, Texte);
  if Fin = 0 then
    Fin := Length(Texte) + 1;
  Result := Trim(Copy(Texte, 1, Fin - 1));
  if Result = '' then
    Result := '?';
end;

// Le désinstallateur Inno fait tout, y compris l'unique appel de
// l'application (--desinstallation) : les choix lui sont transmis. Le
// résultat de l'appel est relu dans son journal.
procedure DesinstallerDepuisInstallateur;
var
  Motif, Parametres, Journal: String;
  Code: Integer;
begin
  Resume := '';
  Echecs := 0;
  WizardForm.StatusLabel.Caption := 'Désinstallation…';
  Parametres := '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART';
  if not ChoixChapitres then
    Parametres := Parametres + ' /GARDERCHAPITRES';
  if ChoixSources then
    Parametres := Parametres + ' /SUPPRIMERSOURCES';
  if ChoixTitres then
    Parametres := Parametres + ' /SUPPRIMERTITRES';
  Journal := JournalDesinstallation;
  if Journal <> '' then
    Parametres := Parametres + ' /LOG="' + Journal + '"';
  if LancerDesinstallateur(Parametres, Code) then
    Noter('Supprimé : programme, raccourcis et entrée « Applications ' +
      'installées ».')
  else
  begin
    Noter('ÉCHEC : désinstallation non faite ou incomplète (code ' +
      IntToStr(Code) + ') : application impossible à fermer, ou ' +
      'désinstallateur en échec. Détail dans le journal ci-dessous.');
    Echecs := Echecs + 1;
  end;

  // Résultat de l'appel de l'application (journal du désinstallateur).
  Motif := LireApresRepere(Journal, 'Base non modifiée : ');
  if Motif = '' then
    Motif := LireApresRepere(Journal,
      'Base pas entièrement nettoyée (modification partielle possible) : ');
  if Motif <> '' then
  begin
    if EchecAvantLancement(Motif) then
      Noter('ÉCHEC : base non modifiée (' + Motif + ') : vos sources et vos ' +
        'titres y sont conservés.')
    else
      Noter('ÉCHEC : base pas entièrement nettoyée (' + Motif + ') : ' +
        'certaines données ont peut-être déjà été supprimées (journal de ' +
        'l''application : Documents\bibliotheque_perso\journaux).');
    Echecs := Echecs + 1;
    SignalerEchecBase(Motif, WizardSilent);
  end
  else if LireApresRepere(Journal, 'Appel de l''application réussi') <> '' then
  begin
    if ChoixSources or ChoixTitres then
      Noter('Base modifiée par l''application : ' +
        TexteChoixBase(ChoixSources, ChoixTitres) + '.')
    else
      Noter('Base : chapitres marqués comme non téléchargés ; sources, ' +
        'titres, listes et réglages conservés.');
  end
  else if not (ChoixSources or ChoixTitres) then
    Noter('Conservé : base (sources, titres, listes, réglages).');

  if ChoixChapitres then
    Noter('Chapitres téléchargés : seuls les chapitres et couvertures ' +
      'enregistrés par l''application ont été supprimés (vos autres fichiers, ' +
      'livres importés, journaux, rapports et exports sont gardés).')
  else
    Noter('Conservé : chapitres téléchargés.');
  if DirExists(DossierApplication) then
    Noter('Gardé : dossier d''installation, qui contient encore des fichiers ' +
      '(par exemple les données du navigateur intégré) : ' + DossierApplication);
  if Journal <> '' then
    Noter('Détail : ' + Journal);
  if Echecs > 0 then
    Noter(#13#10 + 'Désinstallation terminée avec ' + IntToStr(Echecs) +
      ' erreur(s).')
  else
    Noter(#13#10 + 'Désinstallation réussie.');
end;

// ---------------------------------------------------------------------------
// Assistant (installateur).
// ---------------------------------------------------------------------------

// Mode demandé par /ACTION= (-1 si absent) ; ModeImpossible reçoit le motif
// d'une valeur refusée.
function ModeDemande: Integer;
var
  Action: String;
begin
  Result := -1;
  ModeImpossible := '';
  Action := Uppercase(Trim(ExpandConstant('{param:ACTION|}')));
  if Action = '' then
    Exit;
  if Action = 'INSTALLER' then
  begin
    Result := ModeInstaller;
    if ApplicationInstallee then
    begin
      Log('/ACTION=INSTALLER : application déjà installée, mise à jour.');
      Result := ModeMettreAJour;
    end;
  end
  else if Action = 'METTREAJOUR' then
    Result := ModeMettreAJour
  else if Action = 'DESINSTALLER' then
    Result := ModeDesinstaller
  else if Action = 'TOUTSUPPRIMER' then
    Result := ModeToutSupprimer
  else
    ModeImpossible := 'Action inconnue : /ACTION=' + Action + ' (attendu : ' +
      'INSTALLER, METTREAJOUR, DESINSTALLER ou TOUTSUPPRIMER).';
  if ((Result = ModeMettreAJour) or (Result = ModeDesinstaller)) and
    not ApplicationInstallee then
  begin
    ModeImpossible := '{#NomApplication} n''est pas installée : /ACTION=' +
      Action + ' impossible.';
    Result := -1;
  end;
end;

function InitializeSetup: Boolean;
var
  Demande: Integer;
begin
  Result := True;
  ReleverInstallation;
  if ApplicationInstallee then
    Mode := ModeMettreAJour
  else
    Mode := ModeInstaller;
  Demande := ModeDemande;
  if ModeImpossible <> '' then
  begin
    Log(ModeImpossible);
    SuppressibleMsgBox(ModeImpossible, mbError, MB_OK, IDOK);
    Result := False;
    Exit;
  end;
  if Demande >= 0 then
    Mode := Demande;
  // Choix de la désinstallation : valeurs par défaut, ou paramètres.
  ChoixChapitres := not ParametrePresent('GARDERCHAPITRES');
  ChoixSources := ParametrePresent('SUPPRIMERSOURCES');
  // /SUPPRIMERSOURCES implique /SUPPRIMERTITRES.
  ChoixTitres := ParametrePresent('SUPPRIMERTITRES') or ChoixSources;
  Log('Action : ' + IntToStr(Mode) + ' (0 installer, 1 mettre à jour, ' +
    '2 désinstaller, 3 tout supprimer).');
end;

// Dossier de la bibliothèque proposé : /BIBLIOTHEQUE=, sinon installation.json
// du dossier proposé, sinon valeur mémorisée, sinon Documents\bibliotheque_perso.
function DossierBibliothequePropose(const DossierApp: String): String;
begin
  Result := Trim(ExpandConstant('{param:BIBLIOTHEQUE|}'));
  if Result = '' then
    Result := LireInstallationJson(DossierApp, CleDossierBibliotheque);
  if Result = '' then
    Result := LirePointeur(ClePreviousData);
  if Result = '' then
    Result := LireDonneeMemorisee(ClePreviousData);
  if Result = '' then
    Result := DossierChapitresParDefaut;
end;

// Dossier par défaut ou ancien dossier qui contient déjà une base ('' si
// aucun) : à l'installation, il est proposé et la base y est reprise.
function BaseExistante: String;
var
  Pointee: String;
begin
  Result := '';
  // Dossier choisi lors d'une installation précédente (pointeur).
  Pointee := LirePointeur(ClePreviousDataBase);
  if (Pointee <> '') and EstCheminComplet(Pointee) and
    FileExists(AddBackslash(Pointee) + NomFichierBase) then
    Result := Pointee
  else if FileExists(AddBackslash(DossierBaseParDefaut) + NomFichierBase) then
    Result := DossierBaseParDefaut
  else if FileExists(AddBackslash(AncienDossierBase) + NomFichierBase) then
    Result := AncienDossierBase;
end;

// Dossier de la base proposé : /BASE=, sinon installation.json, sinon valeur
// mémorisée, sinon le dossier qui contient déjà une base (par défaut ou
// ancien), sinon %APPDATA%\bibliotheque_perso.
function DossierBasePropose(const DossierApp: String): String;
begin
  Result := Trim(ExpandConstant('{param:BASE|}'));
  if Result = '' then
    Result := LireInstallationJson(DossierApp, CleDossierBase);
  if Result = '' then
    Result := LirePointeur(ClePreviousDataBase);
  if Result = '' then
    Result := LireDonneeMemorisee(ClePreviousDataBase);
  if Result = '' then
    Result := BaseExistante;
  if Result = '' then
    Result := DossierBaseParDefaut;
end;

// Texte de la page du dossier de la base.
function TexteDossierBase: String;
var
  Existante: String;
begin
  Result := 'La base contient vos titres, sources, listes et réglages. ' +
    'Choisissez de préférence un dossier sur un disque local de cet ' +
    'ordinateur : une base sur un disque réseau ou un NAS peut être abîmée si ' +
    'la connexion est coupée.';
  Existante := BaseExistante;
  if Existante <> '' then
    Result := Result + #13#10#13#10 + 'Une base existe déjà dans ' + Existante +
      ' : elle sera reprise. Si vous choisissez un autre dossier, l''application ' +
      'l''y déplacera à son premier démarrage.'
  else
    Result := Result + #13#10#13#10 + 'Le dossier proposé convient dans la ' +
      'plupart des cas. Si vous en choisissez un autre, prenez un dossier ' +
      'réservé à la base.';
end;

// Texte de la page d'action.
function TexteAction: String;
begin
  if ApplicationInstallee then
    Result := '{#NomApplication} ' + VersionInstallee + ' est installée dans ' +
      DossierApplication + '.' + #13#10#13#10 +
      'Mettre à jour : remplace seulement le programme ; vos emplacements, ' +
      'votre base et vos chapitres sont gardés.' + #13#10 +
      'Désinstaller : retire le programme ; vous choisissez ensuite ce qui est ' +
      'supprimé avec lui (chapitres téléchargés, sources, titres).' + #13#10 +
      'Tout supprimer : retire le programme, la base et les chapitres ' +
      'téléchargés ; la liste est affichée avant, avec une confirmation.'
  else
    Result := 'Installer : vous choisissez le dossier du programme, celui des ' +
      'chapitres téléchargés et celui de la base.' + #13#10 +
      'Tout supprimer : efface ce qui reste d''une ancienne installation ' +
      '(base, chapitres téléchargés) ; la liste est affichée avant, avec une ' +
      'confirmation.';
end;

// Page « Désinstaller » : « Sources » coché coche et grise « Titres » ;
// décoché, « Titres » redevient libre.
procedure AppliquerSourcesSurTitres;
var
  Liste: TNewCheckListBox;
begin
  Liste := PageDesinstallation.CheckListBox;
  if PageDesinstallation.Values[1] then
  begin
    PageDesinstallation.Values[2] := True;
    Liste.ItemEnabled[2] := False;
    Liste.ItemCaption[2] := LibelleCaseTitresImposee;
  end
  else
  begin
    Liste.ItemEnabled[2] := True;
    Liste.ItemCaption[2] := LibelleCaseTitres;
  end;
end;

procedure CasesDesinstallationCliquees(Sender: TObject);
begin
  AppliquerSourcesSurTitres;
end;

procedure InitializeWizard;
begin
  IndexInstaller := -1;
  IndexMettreAJour := -1;
  IndexDesinstaller := -1;
  IndexToutSupprimer := -1;
  PageAction := CreateInputOptionPage(wpWelcome,
    'Que voulez-vous faire ?',
    '{#NomApplication} {#Version}',
    TexteAction, True, False);
  if ApplicationInstallee then
  begin
    if CompareText(VersionInstallee, '{#Version}') = 0 then
      IndexMettreAJour := PageAction.Add('Réinstaller la version {#Version} ' +
        '(déjà installée ; vos données sont gardées)')
    else
      IndexMettreAJour := PageAction.Add('Mettre à jour : version ' +
        VersionInstallee + ' -> {#Version}');
    IndexDesinstaller := PageAction.Add('Désinstaller');
  end
  else
    IndexInstaller := PageAction.Add('Installer {#NomApplication} {#Version}');
  IndexToutSupprimer := PageAction.Add('Tout supprimer (programme, base et ' +
    'chapitres téléchargés)');
  if Mode = ModeInstaller then
    PageAction.SelectedValueIndex := IndexInstaller
  else if Mode = ModeMettreAJour then
    PageAction.SelectedValueIndex := IndexMettreAJour
  else if Mode = ModeDesinstaller then
    PageAction.SelectedValueIndex := IndexDesinstaller
  else
    PageAction.SelectedValueIndex := IndexToutSupprimer;

  PageBibliotheque := CreateInputDirPage(wpSelectDir,
    'Dossier de votre bibliothèque',
    'Où ranger les chapitres téléchargés ?',
    'Les chapitres téléchargés pour la lecture hors-ligne (et les couvertures) ' +
    'seront enregistrés dans ce dossier. Il peut se trouver sur un autre disque, ' +
    'un disque réseau ou un NAS (par exemple \\nas\partage\Bibliothèque).' + #13#10#13#10 +
    'Vous pourrez le changer plus tard dans l''application : Paramètres > ' +
    'Dossier des chapitres.',
    False, '');
  PageBibliotheque.Add('');
  // Le dossier d'installation proposé est déjà celui de l'installation
  // précédente (UsePreviousAppDir) : on y relit installation.json.
  PageBibliotheque.Values[0] := DossierBibliothequePropose(WizardForm.DirEdit.Text);

  PageBase := CreateInputDirPage(PageBibliotheque.ID,
    'Dossier de la base',
    'Où ranger la base de l''application ?',
    TexteDossierBase,
    False, '');
  PageBase.Add('');
  PageBase.Values[0] := DossierBasePropose(WizardForm.DirEdit.Text);

  // Mise à jour : texte écrit à l'affichage (CurPageChanged).
  PageRecapitulatif := CreateOutputMsgPage(PageBase.ID,
    'Mise à jour', 'Vos emplacements sont gardés', '');

  PageDesinstallation := CreateInputOptionPage(PageRecapitulatif.ID,
    'Désinstaller',
    'Que faut-il supprimer avec le programme ?',
    'Cochez ce qui doit être supprimé :' + #13#10 +
    '- Chapitres téléchargés : seuls les chapitres et couvertures enregistrés ' +
    'par l''application ; vos autres fichiers et les livres importés sont ' +
    'gardés (« Tout supprimer » retire les livres importés).' + #13#10 +
    '- Sources : les sites de lecture ajoutés sont retirés de la base.' + #13#10 +
    '- Titres : les titres suivis sont retirés de la base (cochés avec les ' +
    'sources : les titres dépendent de leurs sources).' + #13#10#13#10 +
    'Ce qui n''est pas coché est conservé, ainsi que vos réglages : une ' +
    'nouvelle installation le retrouvera.',
    False, False);
  PageDesinstallation.Add(LibelleCaseChapitres);
  PageDesinstallation.Add(LibelleCaseSources);
  PageDesinstallation.Add(LibelleCaseTitres);
  PageDesinstallation.Values[0] := ChoixChapitres;
  PageDesinstallation.Values[1] := ChoixSources;
  PageDesinstallation.Values[2] := ChoixTitres;
  AppliquerSourcesSurTitres;
  PageDesinstallation.CheckListBox.OnClickCheck := @CasesDesinstallationCliquees;

  PageListe := CreateOutputMsgMemoPage(PageDesinstallation.ID,
    'Tout supprimer',
    'Tout ce que {#NomApplication} a créé sur cet ordinateur',
    'Vérifiez la liste, puis cliquez sur « Tout supprimer ». Une confirmation ' +
    'vous sera demandée.',
    '');

  PageResultat := CreateOutputMsgMemoPage(wpInstalling,
    'Résultat', 'Ce qui a été fait', 'Résumé :', '');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = wpSelectDir) or (PageID = PageBibliotheque.ID) or
    (PageID = PageBase.ID) or (PageID = wpSelectTasks) then
    Result := Mode <> ModeInstaller
  else if PageID = PageRecapitulatif.ID then
    Result := Mode <> ModeMettreAJour
  else if PageID = PageDesinstallation.ID then
    Result := Mode <> ModeDesinstaller
  else if PageID = PageListe.ID then
    Result := Mode <> ModeToutSupprimer
  else if PageID = wpReady then
    Result := Mode <> ModeInstaller
  else if PageID = PageResultat.ID then
    Result := EstModeInstallation;
end;

// Récapitulatif de la mise à jour : programme, base, chapitres.
function TexteRecapitulatif: String;
var
  Base, Chapitres, Fin: String;
begin
  Fin := #13#10;
  Base := LireInstallationJson(DossierApplication, CleDossierBase);
  if Base = '' then
    Base := DossierBaseParDefaut + ' (dossier par défaut)';
  if not DirExists(LireInstallationJson(DossierApplication, CleDossierBase)) and
    not DirExists(DossierBaseParDefaut) and DirExists(AncienDossierBase) then
    Base := Base + Fin + '    (au premier démarrage, l''application y déplacera ' +
      'votre base actuelle, ' + AncienDossierBase + ')';
  Chapitres := DossierChapitresApplication(DossierApplication);
  if Chapitres <> '' then
    Chapitres := Chapitres + ' (choisi dans l''application)'
  else
  begin
    Chapitres := LireInstallationJson(DossierApplication, CleDossierBibliotheque);
    if Chapitres = '' then
      Chapitres := DossierChapitresParDefaut + ' (dossier par défaut)';
  end;
  if CompareText(VersionInstallee, '{#Version}') = 0 then
    Result := 'Réinstallation de la version {#Version}.'
  else
    Result := 'Mise à jour de la version ' + VersionInstallee +
      ' vers la version {#Version}.';
  Result := Result + ' Seuls les fichiers du programme sont remplacés ; rien ' +
    'n''est redemandé et rien d''autre n''est modifié.' + Fin + Fin +
    'Programme :' + Fin + '    ' + DossierApplication + Fin + Fin +
    'Base (titres, sources, listes, réglages) :' + Fin + '    ' + Base + Fin + Fin +
    'Chapitres téléchargés :' + Fin + '    ' + Chapitres + Fin + Fin +
    'Le dossier des chapitres se change dans l''application (Paramètres > ' +
    'Dossier des chapitres). L''installateur ferme l''application si elle est ' +
    'ouverte.';
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = PageRecapitulatif.ID then
  begin
    PageRecapitulatif.MsgLabel.Caption := TexteRecapitulatif;
    if CompareText(VersionInstallee, '{#Version}') = 0 then
      WizardForm.NextButton.Caption := '&Réinstaller'
    else
      WizardForm.NextButton.Caption := '&Mettre à jour';
  end
  else if CurPageID = PageDesinstallation.ID then
    WizardForm.NextButton.Caption := '&Désinstaller'
  else if CurPageID = PageListe.ID then
  begin
    PageListe.RichEditViewer.Text := TexteListe;
    WizardForm.NextButton.Caption := '&Tout supprimer';
  end
  else if (CurPageID = wpInstalling) and not EstModeInstallation then
  begin
    if Mode = ModeDesinstaller then
    begin
      WizardForm.PageNameLabel.Caption := 'Désinstallation';
      WizardForm.PageDescriptionLabel.Caption :=
        'Désinstallation de {#NomApplication} en cours…';
    end
    else
    begin
      WizardForm.PageNameLabel.Caption := 'Suppression';
      WizardForm.PageDescriptionLabel.Caption :=
        'Suppression de {#NomApplication} et de ses données en cours…';
    end;
  end
  else if CurPageID = PageResultat.ID then
    PageResultat.RichEditViewer.Text := Resume + #13#10 + 'Journal : ' +
      ExpandConstant('{log}')
  else if (CurPageID = wpFinished) and not EstModeInstallation then
  begin
    if Mode = ModeDesinstaller then
      WizardForm.FinishedHeadingLabel.Caption := 'Désinstallation terminée'
    else
      WizardForm.FinishedHeadingLabel.Caption := 'Suppression terminée';
    WizardForm.FinishedLabel.Caption := 'Le résumé figure à la page ' +
      'précédente et dans le journal.';
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Erreur: String;
begin
  Result := True;
  if CurPageID = PageAction.ID then
  begin
    if PageAction.SelectedValueIndex = IndexInstaller then
      Mode := ModeInstaller
    else if PageAction.SelectedValueIndex = IndexMettreAJour then
      Mode := ModeMettreAJour
    else if PageAction.SelectedValueIndex = IndexDesinstaller then
      Mode := ModeDesinstaller
    else
      Mode := ModeToutSupprimer;
    Log('Action choisie : ' + IntToStr(Mode));
    if Mode = ModeToutSupprimer then
      ReleverToutSupprimer;
  end
  else if (CurPageID = wpSelectDir) and (Mode = ModeInstaller) then
  begin
    Erreur := VerifierDossierProgramme(WizardDirValue);
    if Erreur <> '' then
    begin
      SuppressibleMsgBox(Erreur, mbError, MB_OK, IDOK);
      Result := False;
    end;
  end
  else if CurPageID = PageBibliotheque.ID then
  begin
    Erreur := VerifierDossierBibliotheque(PageBibliotheque.Values[0], WizardDirValue);
    if Erreur <> '' then
    begin
      SuppressibleMsgBox(Erreur, mbError, MB_OK, IDOK);
      Result := False;
    end;
  end
  else if CurPageID = PageBase.ID then
  begin
    Erreur := VerifierDossierBase(PageBase.Values[0], WizardDirValue,
      PageBibliotheque.Values[0]);
    if Erreur <> '' then
    begin
      SuppressibleMsgBox(Erreur, mbError, MB_OK, IDOK);
      Result := False;
    end
    else if (Copy(Trim(PageBase.Values[0]), 1, 2) = '\\') and not WizardSilent then
      Result := SuppressibleMsgBox('Ce dossier est sur le réseau. Une base sur ' +
        'un disque réseau ou un NAS peut être abîmée si la connexion est ' +
        'coupée ; un disque local est conseillé.' + #13#10#13#10 +
        'Garder ce dossier quand même ?', mbConfirmation,
        MB_YESNO or MB_DEFBUTTON2, IDYES) = IDYES;
  end
  else if CurPageID = PageDesinstallation.ID then
  begin
    ChoixChapitres := PageDesinstallation.Values[0];
    ChoixSources := PageDesinstallation.Values[1];
    ChoixTitres := PageDesinstallation.Values[2] or ChoixSources;
    Erreur := 'Supprimé : le programme';
    if ChoixChapitres then
      Erreur := Erreur + ', les chapitres téléchargés';
    if ChoixSources then
      Erreur := Erreur + ', les sources';
    if ChoixTitres then
      Erreur := Erreur + ', les titres';
    // En silencieux, Inno Setup appelle aussi NextButtonClick : pas de
    // question (le choix vient de /ACTION= et des paramètres).
    if not WizardSilent then
      Result := MsgBox('Désinstaller {#NomApplication} ?' + #13#10#13#10 +
      Erreur + '.' + #13#10 + 'Tout le reste est conservé.',
      mbConfirmation, MB_YESNO) = IDYES;
  end
  else if (CurPageID = PageListe.ID) and not WizardSilent then
    Result := MsgBox('Supprimer définitivement {#NomApplication}, votre base et ' +
      'vos chapitres téléchargés ?' + #13#10#13#10 +
      'Cette opération est irréversible.' + #13#10#13#10 +
      'Oui : tout supprimer.' + #13#10 +
      'Non (par défaut) : ne rien supprimer.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

// Pour « Installer » : dossiers et emplacements choisis.
function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := MemoDirInfo + NewLine + NewLine +
    'Chapitres téléchargés :' + NewLine + Space +
    RemoveBackslashUnlessRoot(Trim(PageBibliotheque.Values[0])) + NewLine + NewLine +
    'Base (titres, sources, listes, réglages) :' + NewLine + Space +
    RemoveBackslashUnlessRoot(Trim(PageBase.Values[0]));
  if MemoTasksInfo <> '' then
    Result := Result + NewLine + NewLine + MemoTasksInfo;
end;

// Toujours appelé, y compris en mode silencieux : dernière vérification avant
// de modifier quoi que ce soit (une chaîne non vide annule tout).
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if Mode = ModeInstaller then
  begin
    Result := VerifierDossierProgramme(WizardDirValue);
    if Result = '' then
      Result := FermerApplication(AddBackslash(WizardDirValue) + '{#NomExecutable}',
        'l''installation', not WizardSilent);
    if Result = '' then
      Result := VerifierDossierBibliotheque(PageBibliotheque.Values[0],
        WizardDirValue);
    if Result = '' then
      Result := VerifierDossierBase(PageBase.Values[0], WizardDirValue,
        PageBibliotheque.Values[0]);
  end
  else if Mode = ModeMettreAJour then
  begin
    Result := FermerApplication(AddBackslash(WizardDirValue) + '{#NomExecutable}',
      'la mise à jour', not WizardSilent);
    if Result = '' then
      Log('Mise à jour : ' + NomFichierInstallation + ' conservé, emplacements ' +
        'inchangés.');
  end
  else
  begin
    DossierAppExistaitAvant := DirExists(WizardDirValue);
    if Mode = ModeDesinstaller then
      Result := FermerApplication(ExeInstalle, 'la désinstallation',
        not WizardSilent)
    else
    begin
      // La liste a prévenu le client : pas de nouvelle question.
      if DossierApplication <> '' then
        Result := FermerApplication(ExeInstalle, '« Tout supprimer »', False);
      if (Result = '') and not ReleveFait then
        ReleverToutSupprimer;
    end;
  end;
end;

// Écrit {app}\installation.json : dossier des chapitres et dossier de la base,
// en UTF-8 sans BOM (lu par jsonDecode côté Dart).
procedure EcrireInstallationJson;
var
  Lignes: TArrayOfString;
begin
  SetArrayLength(Lignes, 4);
  Lignes[0] := '{';
  Lignes[1] := '  "' + CleDossierBibliotheque + '": "' + EchapperJson(
    RemoveBackslashUnlessRoot(Trim(PageBibliotheque.Values[0]))) + '",';
  Lignes[2] := '  "' + CleDossierBase + '": "' + EchapperJson(
    RemoveBackslashUnlessRoot(Trim(PageBase.Values[0]))) + '"';
  Lignes[3] := '}';
  if not SaveStringsToUTF8FileWithoutBOM(
    ExpandConstant('{app}\' + NomFichierInstallation), Lignes, False) then
    Log('Impossible d''écrire ' + NomFichierInstallation);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if Mode = ModeDesinstaller then
      DesinstallerDepuisInstallateur
    else if Mode = ModeToutSupprimer then
      ToutSupprimer;
    // Dossier retiré par l'action : s'il est recréé (vide) par Inno Setup, il
    // sera retiré à la fin.
    if not EstModeInstallation and not DirExists(WizardDirValue) then
      DossierAppExistaitAvant := False;
  end
  else if CurStep = ssPostInstall then
  begin
    // Mise à jour : installation.json n'est jamais réécrit.
    if Mode = ModeInstaller then
    begin
      EcrireInstallationJson;
      EcrirePointeur(RemoveBackslashUnlessRoot(Trim(PageBibliotheque.Values[0])),
        RemoveBackslashUnlessRoot(Trim(PageBase.Values[0])));
    end
    else if Mode = ModeMettreAJour then
      // Pointeur tenu à jour depuis installation.json (inchangé).
      EcrirePointeur(LireInstallationJson(ExpandConstant('{app}'),
        CleDossierBibliotheque), LireInstallationJson(ExpandConstant('{app}'),
        CleDossierBase))
    else if not EstModeInstallation and not DossierAppExistaitAvant then
      // Dossier vide créé par Inno Setup (rien n'y est installé).
      RemoveDir(WizardDirValue);
  end;
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
var
  Chapitres, Base: String;
begin
  // Mise à jour : les valeurs mémorisées suivent installation.json, inchangé.
  if Mode = ModeMettreAJour then
  begin
    Chapitres := LireInstallationJson(ExpandConstant('{app}'),
      CleDossierBibliotheque);
    Base := LireInstallationJson(ExpandConstant('{app}'), CleDossierBase);
  end
  else
  begin
    Chapitres := RemoveBackslashUnlessRoot(Trim(PageBibliotheque.Values[0]));
    Base := RemoveBackslashUnlessRoot(Trim(PageBase.Values[0]));
  end;
  if Chapitres <> '' then
    SetPreviousData(PreviousDataKey, ClePreviousData, Chapitres);
  if Base <> '' then
    SetPreviousData(PreviousDataKey, ClePreviousDataBase, Base);
end;

// ---------------------------------------------------------------------------
// Désinstallateur (unins000.exe) : depuis « Applications installées », ou
// lancé en silencieux par l'installateur (« Désinstaller », « Tout
// supprimer »).
// ---------------------------------------------------------------------------

// Dossier des chapitres choisi à l'installation : installation.json, sinon la
// valeur mémorisée par Inno Setup.
function DossierChapitresInstalle: String;
begin
  Result := LireInstallationJson(ExpandConstant('{app}'), CleDossierBibliotheque);
  if Result = '' then
    Result := LireDonneeMemorisee(ClePreviousData);
  if Result = '' then
    Result := LirePointeur(ClePreviousData);
end;

// Garde Dossier dans DossiersChapitresDesinstallation s'il est valable (même
// contrôle qu'à l'installation, puis règles de suppression_commune.iss :
// repère obligatoire hors du dossier par défaut, ni racine ni dossier connu),
// joignable, contient des chapitres de l'application et n'y est pas déjà.
procedure RetenirDossierChapitres(const Dossier: String);
var
  Presents, Motif: String;
  Noms: TArrayOfString;
  I, N: Integer;
begin
  if (Dossier = '') or (VerifierDossierBibliotheque(Dossier,
    ExpandConstant('{app}')) <> '') then
  begin
    Log('Désinstallation : dossier des chapitres inconnu ou refusé (' +
      Dossier + '), rien à supprimer.');
    Exit;
  end;
  N := GetArrayLength(DossiersChapitresDesinstallation);
  for I := 0 to N - 1 do
    if MemeDossier(DossiersChapitresDesinstallation[I], Dossier) then
      Exit;
  Motif := MotifRefusChapitres(Dossier, ExpandConstant('{app}'));
  if Motif <> '' then
  begin
    Log('Désinstallation : dossier des chapitres gardé (' + Motif + ') : ' +
      Dossier);
    Exit;
  end;
  RemplirDossiersChapitres(Noms);
  Presents := SousDossiersPresents(Dossier, Noms);
  if (Presents = '') and not FileExists(AddBackslash(Dossier) + NomFichierRepere) then
  begin
    Log('Désinstallation : aucun chapitre dans ' + Dossier + '.');
    Exit;
  end;
  SetArrayLength(DossiersChapitresDesinstallation, N + 1);
  DossiersChapitresDesinstallation[N] := Dossier;
end;

// Étape usUninstall : relève les dossiers des chapitres (installation.json,
// puis emplacements.json) si la case est cochée.
procedure DeciderSuppressionChapitres;
begin
  ChapitresASupprimer := False;
  SetArrayLength(DossiersChapitresDesinstallation, 0);
  if not ChoixChapitres then
  begin
    Log('Désinstallation : chapitres gardés (case non cochée ou /GARDERCHAPITRES).');
    Exit;
  end;
  RetenirDossierChapitres(DossierChapitresInstalle);
  RetenirDossierChapitres(DossierChapitresApplication(ExpandConstant('{app}')));
  ChapitresASupprimer := GetArrayLength(DossiersChapitresDesinstallation) > 0;
end;

// Étape usPostUninstall : supprime les chapitres d'un dossier (règles de
// suppression_commune.iss, vérifiées de nouveau). Journaux, rapports et
// exports sont toujours gardés ici.
procedure AppliquerSuppressionChapitresDossier(const Dossier: String);
var
  Supprimes, Restes: Integer;
  Motif: String;
begin
  Motif := MotifRefusChapitres(Dossier, ExpandConstant('{app}'));
  if Motif <> '' then
  begin
    Log('Désinstallation : dossier des chapitres gardé (' + Motif + ') : ' +
      Dossier);
    Exit;
  end;
  Supprimes := 0;
  Restes := 0;
  SupprimerChapitresDossier(Dossier, False, Supprimes, Restes);
  Log('Désinstallation : ' + IntToStr(Supprimes) + ' élément(s) supprimé(s), ' +
    IntToStr(Restes) + ' gardé(s) dans ' + Dossier);
  if DirExists(Dossier) then
    Log('Désinstallation : dossier gardé (non vide ou lien) ' + Dossier)
  else
    Log('Désinstallation : dossier vide supprimé ' + Dossier);
end;

procedure AppliquerSuppressionChapitres;
var
  I: Integer;
begin
  if not ChapitresASupprimer then
    Exit;
  for I := 0 to GetArrayLength(DossiersChapitresDesinstallation) - 1 do
    AppliquerSuppressionChapitresDossier(DossiersChapitresDesinstallation[I]);
end;

// Supprime le démarrage avec Windows de cette installation : la valeur Run
// seulement si elle lance l'exécutable de {app} (une autre copie garde la
// sienne), puis la valeur StartupApproved\Run si aucune valeur Run ne reste.
procedure SupprimerDemarrageAvecWindows;
var
  Commande, Exe: String;
begin
  Exe := ExpandConstant('{app}\{#NomExecutable}');
  if RegQueryStringValue(HKCU, CleDemarrageRun, NomEntreeDemarrage, Commande) then
  begin
    if Pos(Lowercase(Exe), Lowercase(Commande)) = 0 then
    begin
      Log('Désinstallation : démarrage avec Windows d''une autre copie, gardé (' +
        Commande + ').');
      Exit;
    end;
    if RegDeleteValue(HKCU, CleDemarrageRun, NomEntreeDemarrage) then
      Log('Désinstallation : démarrage avec Windows supprimé (Run).')
    else
      Log('Désinstallation : suppression impossible de la valeur Run.');
  end;
  if not RegValueExists(HKCU, CleDemarrageRun, NomEntreeDemarrage) and
    RegValueExists(HKCU, CleDemarrageApprouve, NomEntreeDemarrage) then
  begin
    if RegDeleteValue(HKCU, CleDemarrageApprouve, NomEntreeDemarrage) then
      Log('Désinstallation : démarrage avec Windows supprimé (StartupApproved).')
    else
      Log('Désinstallation : suppression impossible de la valeur StartupApproved.');
  end;
end;

// Questions Oui/Non (si la fenêtre des cases ne peut pas être créée).
procedure DemanderChoixParQuestions;
begin
  ChoixChapitres := MsgBox('Supprimer aussi vos chapitres téléchargés ?' +
    Chr(13) + Chr(10) + Chr(13) + Chr(10) + 'Seuls les chapitres et ' +
    'couvertures enregistrés par l''application sont supprimés ; vos autres ' +
    'fichiers sont gardés.' + Chr(13) + Chr(10) + Chr(13) + Chr(10) +
    'Oui (par défaut) : les supprimer.' + Chr(13) + Chr(10) +
    'Non : les garder.', mbConfirmation, MB_YESNO) = IDYES;
  ChoixSources := MsgBox('Retirer aussi vos sources (sites de lecture ajoutés) ' +
    'de la base ?' + #13#10#13#10 + 'Oui : les retirer.' + #13#10 +
    'Non (par défaut) : les garder.', mbConfirmation,
    MB_YESNO or MB_DEFBUTTON2) = IDYES;
  // Les titres dépendent de leurs sources : pas de question si les sources
  // sont retirées.
  if ChoixSources then
    ChoixTitres := True
  else
    ChoixTitres := MsgBox('Retirer aussi vos titres suivis de la base ?' +
      Chr(13) + Chr(10) + Chr(13) + Chr(10) + 'Oui : les retirer.' + #13#10 +
      'Non (par défaut) : les garder.', mbConfirmation,
      MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

// Fenêtre du désinstallateur : « Sources » coché coche et grise « Titres ».
procedure CaseSourcesCliquee(Sender: TObject);
begin
  if CaseSourcesFenetre.Checked then
  begin
    CaseTitresFenetre.Checked := True;
    CaseTitresFenetre.Enabled := False;
    CaseTitresFenetre.Caption := LibelleCaseTitresImposee;
  end
  else
  begin
    CaseTitresFenetre.Enabled := True;
    CaseTitresFenetre.Caption := LibelleCaseTitres;
  end;
end;

// Fenêtre des trois cases. Faux si le client annule.
function DemanderChoixParCases: Boolean;
var
  Formulaire: TSetupForm;
  Texte, Note: TNewStaticText;
  CaseChapitres, CaseSources, CaseTitres: TNewCheckBox;
  BoutonOk, BoutonAnnuler: TNewButton;
  Marge, Largeur, Haut: Integer;
begin
  Formulaire := CreateCustomForm(ScaleX(460), ScaleY(320), False, False);
  try
    Formulaire.Caption := 'Désinstallation de {#NomApplication}';
    Marge := ScaleX(16);
    Largeur := Formulaire.ClientWidth - 2 * Marge;

    Texte := TNewStaticText.Create(Formulaire);
    Texte.Parent := Formulaire;
    Texte.Left := Marge;
    Texte.Top := ScaleY(14);
    Texte.Width := Largeur;
    Texte.AutoSize := False;
    Texte.WordWrap := True;
    Texte.Height := ScaleY(30);
    Texte.Caption := 'Que faut-il supprimer avec le programme ? Ce qui n''est ' +
      'pas coché est conservé.';
    Haut := Texte.Top + Texte.Height + ScaleY(8);

    CaseChapitres := TNewCheckBox.Create(Formulaire);
    CaseChapitres.Parent := Formulaire;
    CaseChapitres.Left := Marge;
    CaseChapitres.Top := Haut;
    CaseChapitres.Width := Largeur;
    CaseChapitres.Caption := LibelleCaseChapitres;
    CaseChapitres.Checked := True;
    Haut := Haut + ScaleY(22);

    CaseSources := TNewCheckBox.Create(Formulaire);
    CaseSources.Parent := Formulaire;
    CaseSources.Left := Marge;
    CaseSources.Top := Haut;
    CaseSources.Width := Largeur;
    CaseSources.Caption := LibelleCaseSources;
    CaseSources.Checked := False;
    Haut := Haut + ScaleY(22);

    CaseTitres := TNewCheckBox.Create(Formulaire);
    CaseTitres.Parent := Formulaire;
    CaseTitres.Left := Marge;
    CaseTitres.Top := Haut;
    CaseTitres.Width := Largeur;
    CaseTitres.Caption := LibelleCaseTitres;
    CaseTitres.Checked := False;
    Haut := Haut + ScaleY(30);
    CaseSourcesFenetre := CaseSources;
    CaseTitresFenetre := CaseTitres;
    CaseSources.OnClick := @CaseSourcesCliquee;

    Note := TNewStaticText.Create(Formulaire);
    Note.Parent := Formulaire;
    Note.Left := Marge;
    Note.Top := Haut;
    Note.Width := Largeur;
    Note.AutoSize := False;
    Note.WordWrap := True;
    Note.Height := ScaleY(130);
    Note.Caption := 'Chapitres téléchargés : seuls les chapitres et couvertures ' +
      'enregistrés par l''application ; vos autres fichiers et les livres ' +
      'importés sont gardés (« Tout supprimer » les retire).' + #13#10 +
      'Sources : les sites de lecture ajoutés sont retirés de la base.' + #13#10 +
      'Titres : les titres suivis sont retirés de la base (toujours ' +
      'avec les sources : les titres dépendent de leurs sources).' + #13#10 +
      'Vos réglages sont toujours conservés : une nouvelle installation les ' +
      'retrouvera.';

    BoutonAnnuler := TNewButton.Create(Formulaire);
    BoutonAnnuler.Parent := Formulaire;
    BoutonAnnuler.Width := ScaleX(90);
    BoutonAnnuler.Height := ScaleY(25);
    BoutonAnnuler.Left := Formulaire.ClientWidth - Marge - BoutonAnnuler.Width;
    BoutonAnnuler.Top := Formulaire.ClientHeight - ScaleY(12) - BoutonAnnuler.Height;
    BoutonAnnuler.Caption := 'Annuler';
    BoutonAnnuler.ModalResult := mrCancel;
    BoutonAnnuler.Cancel := True;

    BoutonOk := TNewButton.Create(Formulaire);
    BoutonOk.Parent := Formulaire;
    BoutonOk.Width := ScaleX(110);
    BoutonOk.Height := ScaleY(25);
    BoutonOk.Left := BoutonAnnuler.Left - ScaleX(8) - BoutonOk.Width;
    BoutonOk.Top := BoutonAnnuler.Top;
    BoutonOk.Caption := 'Continuer';
    BoutonOk.ModalResult := mrOk;
    BoutonOk.Default := True;

    Formulaire.ActiveControl := BoutonOk;
    Result := Formulaire.ShowModal = mrOk;
    if Result then
    begin
      ChoixChapitres := CaseChapitres.Checked;
      ChoixSources := CaseSources.Checked;
      ChoixTitres := CaseTitres.Checked or ChoixSources;
    end;
  finally
    Formulaire.Free;
  end;
end;

// Arrête l'application dès le début de la désinstallation. Échec : la
// désinstallation est annulée (rien n'est modifié : ni programme, ni base, ni
// chapitres) ; prévenu en interactif, journal en silencieux.
function ArreterAvantDesinstallation: Boolean;
var
  Erreur: String;
begin
  Erreur := FermerApplication(ExpandConstant('{app}\{#NomExecutable}'),
    'la désinstallation', False);
  Result := Erreur = '';
  if not Result then
  begin
    Log('Désinstallation annulée : ' + Erreur);
    if not UninstallSilent then
      MsgBox(Erreur, mbError, MB_OK);
  end;
end;

// Avant la confirmation d'Inno Setup : choix des trois cases, puis accord pour
// fermer l'application si elle est ouverte. En silencieux : paramètres.
function InitializeUninstall: Boolean;
begin
  Result := True;
  ChoixChapitres := not ParametrePresent('GARDERCHAPITRES');
  ChoixSources := ParametrePresent('SUPPRIMERSOURCES');
  // /SUPPRIMERSOURCES implique /SUPPRIMERTITRES.
  ChoixTitres := ParametrePresent('SUPPRIMERTITRES') or ChoixSources;
  if UninstallSilent then
  begin
    Log('Désinstallation silencieuse : chapitres ' +
      IntToStr(Ord(ChoixChapitres)) + ', sources ' + IntToStr(Ord(ChoixSources)) +
      ', titres ' + IntToStr(Ord(ChoixTitres)) + '.');
    Result := ArreterAvantDesinstallation;
    Exit;
  end;
  try
    Result := DemanderChoixParCases;
  except
    Log('Fenêtre des choix impossible (' + GetExceptionMessage +
      ') : questions Oui/Non.');
    DemanderChoixParQuestions;
    Result := True;
  end;
  if not Result then
    Exit;
  Log('Choix : chapitres ' + IntToStr(Ord(ChoixChapitres)) + ', sources ' +
    IntToStr(Ord(ChoixSources)) + ', titres ' + IntToStr(Ord(ChoixTitres)) + '.');
  if ProcessusApplication(ExpandConstant('{app}\{#NomExecutable}'), False) <= 0 then
    Exit;
  if SuppressibleMsgBox(
    '{#NomApplication} est ouverte, peut-être seulement dans la zone de ' +
    'notification (icône près de l''horloge). Elle va être fermée pour la ' +
    'désinstallation.' + #13#10#13#10 +
    'Oui : continuer. Un téléchargement en cours sera interrompu.' + #13#10 +
    'Non : annuler. Vous pouvez la quitter vous-même (clic droit sur son ' +
    'icône > Quitter), puis relancer la désinstallation.',
    mbConfirmation, MB_YESNO, IDYES) <> IDYES then
    Result := False
  else
    Result := ArreterAvantDesinstallation;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Erreur: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    ChapitresASupprimer := False;
    // Déjà arrêtée dans InitializeUninstall ; revérifié ici. Si elle tourne
    // encore, ni la base ni les chapitres ne sont touchés.
    Erreur := FermerApplication(ExpandConstant('{app}\{#NomExecutable}'),
      'la désinstallation', False);
    if Erreur <> '' then
    begin
      Log('Désinstallation : ' + Erreur + ' Base et chapitres non modifiés.');
      Exit;
    end;
    // Chapitres décidés AVANT l'appel : l'application remet alors à zéro
    // l'état « téléchargé » (--chapitres-supprimes), même sans Sources ni
    // Titres (sinon la base garderait des chapitres marqués téléchargés dont
    // les archives et le repère ont disparu).
    DeciderSuppressionChapitres;
    // La base, avant de retirer le programme : un seul appel.
    if ChoixSources or ChoixTitres or ChapitresASupprimer then
    begin
      Erreur := AppelerApplicationDesinstallation(ExpandConstant('{app}'),
        ChoixSources, ChoixTitres, ChapitresASupprimer);
      if Erreur <> '' then
        SignalerEchecBase(Erreur, UninstallSilent);
    end;
  end
  else if CurUninstallStep = usPostUninstall then
  begin
    SupprimerDemarrageAvecWindows;
    AppliquerSuppressionChapitres;
  end;
end;
