; Installateur Windows de « Bibliothèque perso » (Inno Setup 6.7).
;
; Construit par outils\construire_installateur.ps1, qui passe la version lue
; dans pubspec.yaml : ISCC /DVersion=X.Y.Z /DBuild=N bibliotheque_perso.iss
;
; - Installation par utilisateur, sans droits administrateur : par défaut dans
;   %LOCALAPPDATA%\Programs\Bibliotheque perso (dossier modifiable).
; - Page « Dossier de votre bibliothèque » : dossier des chapitres téléchargés
;   (local, disque réseau ou NAS), écrit dans {app}\installation.json, que
;   l'application lit au premier démarrage (lib/main.dart,
;   chargerDossierBibliothequeInstallation).
; - Mise à jour (installation.json déjà présent dans le dossier d'installation) :
;   cette page est sautée et installation.json n'est pas modifié ; le dossier de
;   la bibliothèque se change dans l'application (Paramètres > Dossier des
;   chapitres).
; - Désinstallation (décision du client, 2026-11-25) : la base (%APPDATA%) est
;   toujours conservée. Les chapitres téléchargés sont supprimés si le client
;   répond Oui (réponse par défaut ; en silencieux : supprimés sauf
;   /GARDERCHAPITRES). Seul le contenu propre à l'application est supprimé dans
;   le dossier de installation.json : dans les sous-dossiers des types de
;   titres (TypeTitre de lib/modeles/titre.dart), seulement les archives et
;   couvertures écrites par l'application, puis le fichier repère
;   .bibliotheque_perso et les dossiers devenus vides. Règles de sécurité
;   (repère obligatoire hors de Documents\bibliotheque_perso, ni racine ni
;   dossier connu, liens jamais suivis) : suppression_commune.iss.
;   Journaux, rapports et exports (dans Documents\bibliotheque_perso
;   seulement) sont gardés, sauf confirmation (Non par défaut, jamais en
;   silencieux).
;   Le dossier des chapitres choisi dans l'application (Paramètres > Dossier
;   des chapitres) est lu dans emplacements.json (clé "dossierChapitres"),
;   écrit par l'application dans le dossier de sa base :
;   %APPDATA%\io.github.zerma1\bibliotheque_perso (getApplicationSupportDirectory,
;   CompanyName et ProductName de windows\runner\Runner.rc). Il est traité de
;   la même façon, en plus de celui de installation.json s'il est différent.
;   Désinstallation complète (base comprise) : desinstallateur.iss.
;
; Paramètres de la ligne de commande (en plus de ceux d'Inno Setup) :
;   /BIBLIOTHEQUE="D:\Mes chapitres"   dossier de la bibliothèque (installation
;                                      silencieuse ou valeur proposée) ;
;                                      ignoré lors d'une mise à jour.
;   /GARDERCHAPITRES                   désinstallation : garde les chapitres
;                                      téléchargés (pas de question).
;
; Application ouverte (2026-11-25) : elle se cache dans la zone de notification
; au lieu de se fermer et refuse donc WM_CLOSE ; le Restart Manager
; (CloseApplications) ne parvient pas à l'arrêter (essai : abandon après 30 s).
; L'installation, la mise à jour et la désinstallation arrêtent donc elles-mêmes
; le processus bibliotheque_perso.exe lancé depuis le dossier d'installation,
; et lui seul (chemin complet comparé : une autre copie, par exemple une
; version de développement, n'est jamais touchée). Avec l'interface, le client
; est d'abord prévenu (Non = annuler, pour quitter lui-même par l'icône) ; en
; silencieux, l'arrêt est fait sans question.
; - Désinstallation : la valeur « Bibliotheque perso » du démarrage avec Windows
;   (HKCU\...\CurrentVersion\Run, écrite par lib/main.dart,
;   appliquerDemarrageAvecWindows) est supprimée si elle lance l'exécutable de
;   ce dossier d'installation, ainsi que celle de
;   ...\Explorer\StartupApproved\Run (si aucune valeur Run ne reste).
; Essais seulement : /DIdApplication="{{…}" donne un autre AppId, pour ne pas
; toucher à l'installation réelle du client ; /DDossierBase="C:\essai\base"
; donne un autre dossier de la base (où emplacements.json est lu) ;
; /DNomEntreeDemarrage="Essai…" un autre nom de valeur Run ;
; /DDossierDocuments="C:\essai\doc" un autre dossier Documents.

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
; Dossier de la base de l'application (emplacements.json).
#ifndef DossierBase
  #define DossierBase "{userappdata}\io.github.zerma1\bibliotheque_perso"
#endif
#ifndef NomEntreeDemarrage
  #define NomEntreeDemarrage "Bibliotheque perso"
#endif
; Dossier Documents (dossier des chapitres par défaut ; suppression_commune.iss).
#ifndef DossierDocuments
  #define DossierDocuments "{userdocs}"
#endif

#define NomApplication "Bibliothèque perso"
#define NomExecutable "bibliotheque_perso.exe"

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
VersionInfoDescription=Installation de {#NomApplication}
; Par utilisateur, sans droits administrateur.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Bibliotheque perso
; Page de choix du dossier d'installation toujours affichée (même lors d'une
; mise à jour, où elle propose le dossier précédent).
DisableDirPage=no
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Mise à jour : ferme l'application si elle utilise les fichiers à remplacer.
; L'application elle-même est d'abord arrêtée dans PrepareToInstall (section
; [Code], FermerApplication) : cachée dans la zone de notification, elle ne
; répond pas au Restart Manager. Celui-ci reste pour les autres programmes.
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
; La désinstallation conserve toujours la base ; les chapitres téléchargés font
; l'objet d'une question (section [Code], CurUninstallStepChanged).
ConfirmUninstall=Voulez-vous désinstaller %1 ?%n%nVotre base (titres, sources, listes, réglages) est conservée. Une question vous permettra ensuite de supprimer aussi vos chapitres téléchargés, ou de les garder.
UninstalledAll=%1 a été désinstallé.%n%nVotre base (titres, sources, listes, réglages) a été conservée : une nouvelle installation la retrouvera.

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: unchecked

[Files]
Source: "{#DossierRelease}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#NomApplication}"; Filename: "{app}\{#NomExecutable}"; WorkingDir: "{app}"; IconFilename: "{app}\{#NomExecutable}"
Name: "{autodesktop}\{#NomApplication}"; Filename: "{app}\{#NomExecutable}"; WorkingDir: "{app}"; IconFilename: "{app}\{#NomExecutable}"; Tasks: bureau

[Run]
Filename: "{app}\{#NomExecutable}"; Description: "Lancer {#NomApplication}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Écrit par l'installateur (section [Code]) : à retirer avec le programme.
; Jamais la base. Les chapitres téléchargés sont traités dans la section [Code]
; (CurUninstallStepChanged), selon la réponse du client.
Type: files; Name: "{app}\installation.json"

[Code]
#include "suppression_commune.iss"

const
  NomFichierInstallation = 'installation.json';
  CleDossierBibliotheque = 'dossierBibliotheque';
  // Mémorisé aussi dans les données d'Inno Setup (registre de l'utilisateur),
  // au cas où installation.json aurait disparu.
  ClePreviousData = 'DossierBibliotheque';
  // Écrit par l'application dans le dossier de sa base : dossier des
  // chapitres choisi dans Paramètres.
  NomFichierEmplacements = 'emplacements.json';
  CleDossierChapitres = 'dossierChapitres';
  // Démarrage avec Windows (nomEntreeDemarrageWindows, lib/main.dart ; paquet
  // launch_at_startup).
  NomEntreeDemarrage = '{#NomEntreeDemarrage}';
  CleDemarrageRun = 'Software\Microsoft\Windows\CurrentVersion\Run';
  CleDemarrageApprouve =
    'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  // Attente de la fin des processus arrêtés (pas de 250 ms).
  AttenteArretMaxMs = 15000;

var
  PageBibliotheque: TInputDirWizardPage;
  PageConservation: TOutputMsgWizardPage;
  // Figé dans PrepareToInstall (avant la copie des fichiers).
  MiseAJourEnCours: Boolean;
  // Désinstallation : décidés à l'étape usUninstall (installation.json encore
  // présent), appliqués à l'étape usPostUninstall. Un ou deux dossiers :
  // installation.json et emplacements.json.
  DossiersChapitresDesinstallation: TArrayOfString;
  SupprimerChapitres: Boolean;
  SupprimerDonneesApplication: Boolean;

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

// Lit la valeur de "dossierBibliotheque" dans un installation.json existant.
function LireDossierInstallationJson(const Fichier: String): String;
begin
  Result := LireValeurJson(Fichier, CleDossierBibliotheque);
end;

// Dossier de la bibliothèque proposé : paramètre /BIBLIOTHEQUE=, sinon
// installation.json de l'installation précédente, sinon valeur mémorisée par
// Inno Setup, sinon Documents\bibliotheque_perso (dossier par défaut de
// l'application).
function DossierBibliothequePropose(const DossierApplication: String): String;
begin
  Result := Trim(ExpandConstant('{param:BIBLIOTHEQUE|}'));
  if Result = '' then
    Result := Trim(LireDossierInstallationJson(
      AddBackslash(DossierApplication) + NomFichierInstallation));
  if Result = '' then
    Result := Trim(GetPreviousData(ClePreviousData, ''));
  if Result = '' then
    Result := ExpandConstant('{userdocs}\bibliotheque_perso');
end;

// Message d'erreur si le dossier de la bibliothèque est refusé, sinon ''.
function VerifierDossierBibliotheque(const Dossier, DossierApplication: String): String;
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
  if not (((Length(Bibliotheque) >= 3) and (Bibliotheque[2] = ':') and
    (Bibliotheque[3] = '\')) or (Copy(Bibliotheque, 1, 2) = '\\')) then
  begin
    Result := 'Indiquez un chemin complet (par exemple D:\Bibliothèque ou ' +
      '\\nas\partage\Bibliothèque).';
    Exit;
  end;
  // Les chapitres ne vont pas dans le dossier du programme : il est remplacé
  // à chaque mise à jour.
  Bibliotheque := Lowercase(AddBackslash(Bibliotheque));
  Application := Lowercase(AddBackslash(Trim(DossierApplication)));
  if Copy(Bibliotheque, 1, Length(Application)) = Application then
    Result := 'Le dossier de la bibliothèque ne peut pas se trouver dans le ' +
      'dossier d''installation du programme. Choisissez un autre dossier.';
end;

// Mise à jour : installation.json est déjà présent dans le dossier
// d'installation choisi. Le dossier de la bibliothèque n'est alors plus
// demandé (il se change dans l'application) et installation.json est gardé tel
// quel.
function EstMiseAJour: Boolean;
begin
  Result := FileExists(AddBackslash(WizardDirValue) + NomFichierInstallation);
end;

// Texte de la page « Vos données sont conservées » (nouvelle installation ou
// mise à jour).
function TexteConservation(const MiseAJour: Boolean): String;
begin
  if MiseAJour then
    Result := 'Mise à jour de {#NomApplication} : seuls les fichiers du ' +
      'programme sont remplacés. Votre bibliothèque et ses réglages ne sont ' +
      'pas touchés :' + #13#10#13#10 +
      '  - la base (titres, sources, listes, réglages) ;' + #13#10 +
      '  - le dossier de votre bibliothèque (chapitres téléchargés).' + #13#10#13#10 +
      'Le dossier de la bibliothèque ne se choisit pas ici : pour le changer, ' +
      'ouvrez l''application, Paramètres > Dossier des chapitres.' + #13#10#13#10 +
      'L''installateur ferme l''application si elle est ouverte.'
  else
    Result := 'La désinstallation de {#NomApplication} conserve toujours la base ' +
      '(titres, sources, listes, réglages).' + #13#10#13#10 +
      'Elle vous demande si vos chapitres téléchargés doivent être supprimés ' +
      '(Oui par défaut). Dans le dossier de la bibliothèque, seuls les dossiers ' +
      'des chapitres de l''application sont alors supprimés ; vos autres ' +
      'fichiers sont gardés. Le dossier des chapitres choisi depuis ' +
      'l''application est traité de la même façon.' + #13#10#13#10 +
      'Pour mettre à jour, il suffit ' +
      'de relancer un installateur plus récent : il remplace seulement les ' +
      'fichiers du programme, sans toucher à votre bibliothèque ni à ses ' +
      'réglages, et ferme l''application si elle est ouverte.';
end;

procedure InitializeWizard;
begin
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

  // Texte définitif choisi à l'affichage (CurPageChanged) : le dossier
  // d'installation, donc le type d'installation, peut encore changer.
  PageConservation := CreateOutputMsgPage(PageBibliotheque.ID,
    'Vos données',
    'Désinstallation et mises à jour',
    TexteConservation(False));
end;

// Mise à jour : la page du dossier de la bibliothèque est sautée.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = PageBibliotheque.ID) and EstMiseAJour;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = PageConservation.ID then
  begin
    if EstMiseAJour then
      PageConservation.Description := 'Mise à jour'
    else
      PageConservation.Description := 'Désinstallation et mises à jour';
    PageConservation.MsgLabel.Caption := TexteConservation(EstMiseAJour);
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Erreur: String;
begin
  Result := True;
  if CurPageID = PageBibliotheque.ID then
  begin
    Erreur := VerifierDossierBibliotheque(PageBibliotheque.Values[0], WizardDirValue);
    if Erreur <> '' then
    begin
      // Aussi appelé en mode silencieux : SuppressibleMsgBox ne bloque pas
      // avec /SUPPRESSMSGBOXES (l'installation s'arrête alors avec une erreur).
      SuppressibleMsgBox(Erreur, mbError, MB_OK, IDOK);
      Result := False;
    end;
  end;
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
// Action : « l'installation » ou « la désinstallation ».
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
      Action + '.'
  else
  begin
    Log('Application arrêtée : ' + Exe);
    // Le temps que Windows libère les fichiers (vues web comprises).
    Sleep(1000);
  end;
end;

// Toujours appelé, y compris en mode silencieux : dernière vérification avant
// de copier quoi que ce soit (une chaîne non vide annule l'installation).
// Le type d'installation est figé ici, avant la copie des fichiers.
// Appelé avant la recherche des fichiers utilisés (Restart Manager).
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := FermerApplication(AddBackslash(WizardDirValue) + '{#NomExecutable}',
    'l''installation', not WizardSilent);
  if Result <> '' then
    Exit;
  MiseAJourEnCours := EstMiseAJour;
  if MiseAJourEnCours then
  begin
    // installation.json gardé tel quel (paramètre /BIBLIOTHEQUE= ignoré).
    Log('Mise à jour : ' + NomFichierInstallation + ' conservé, dossier de ' +
      'la bibliothèque inchangé.');
    Result := '';
  end
  else
    Result := VerifierDossierBibliotheque(PageBibliotheque.Values[0], WizardDirValue);
end;

// Écrit {app}\installation.json : {"dossierBibliotheque": "<chemin>"}, en
// UTF-8 sans BOM (lu par jsonDecode côté Dart).
procedure EcrireInstallationJson;
var
  Lignes: TArrayOfString;
  Dossier: String;
begin
  Dossier := RemoveBackslashUnlessRoot(Trim(PageBibliotheque.Values[0]));
  SetArrayLength(Lignes, 1);
  Lignes[0] := '{"' + CleDossierBibliotheque + '": "' + EchapperJson(Dossier) + '"}';
  if not SaveStringsToUTF8FileWithoutBOM(
    ExpandConstant('{app}\' + NomFichierInstallation), Lignes, False) then
    Log('Impossible d''écrire ' + NomFichierInstallation);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // Mise à jour : installation.json n'est jamais réécrit.
  if (CurStep = ssPostInstall) and not MiseAJourEnCours then
    EcrireInstallationJson;
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
var
  Dossier: String;
begin
  // Mise à jour : la valeur mémorisée suit installation.json, inchangé.
  if MiseAJourEnCours then
    Dossier := Trim(LireDossierInstallationJson(
      ExpandConstant('{app}\' + NomFichierInstallation)))
  else
    Dossier := Trim(PageBibliotheque.Values[0]);
  if Dossier <> '' then
    SetPreviousData(PreviousDataKey, ClePreviousData,
      RemoveBackslashUnlessRoot(Dossier));
end;

// ---------------------------------------------------------------------------
// Désinstallation : suppression des chapitres téléchargés.
// ---------------------------------------------------------------------------

// Listes des dossiers de l'application, repère et règles de sécurité :
// suppression_commune.iss (inclus au début de la section [Code]).

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

// Dossier des chapitres choisi à l'installation : installation.json, sinon la
// valeur mémorisée par Inno Setup dans la clé de désinstallation.
function DossierChapitresInstalle: String;
var
  Valeur: String;
begin
  Result := Trim(LireDossierInstallationJson(
    ExpandConstant('{app}\' + NomFichierInstallation)));
  if (Result = '') and RegQueryStringValue(HKCU,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
    ExpandConstant('{#IdApplication}') + '_is1',
    'Inno Setup CodeFile: ' + ClePreviousData, Valeur) then
    Result := Trim(Valeur);
  if Result <> '' then
    Result := RemoveBackslashUnlessRoot(Result);
end;

// Dossier des chapitres choisi dans l'application : emplacements.json du
// dossier de la base, '' si absent.
function DossierChapitresApplication: String;
begin
  Result := Trim(LireValeurJson(AddBackslash(ExpandConstant('{#DossierBase}')) +
    NomFichierEmplacements, CleDossierChapitres));
  if Result <> '' then
    Result := RemoveBackslashUnlessRoot(Result);
end;

// Garde Dossier dans DossiersChapitresDesinstallation s'il est valable (même
// contrôle qu'à l'installation, puis règles de suppression_commune.iss :
// repère obligatoire hors du dossier par défaut, ni racine ni dossier connu),
// joignable, contient des chapitres de l'application et n'y est pas déjà.
// Complète Chapitres et Donnees (« dossier : noms » pour les questions).
procedure RetenirDossierChapitres(const Dossier: String;
  var Chapitres, Donnees: String);
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
    if CompareText(AddBackslash(DossiersChapitresDesinstallation[I]),
      AddBackslash(Dossier)) = 0 then
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
  Chapitres := Chapitres + '  - ' + Dossier + #13#10;
  // Journaux, rapports, exports : seulement dans le dossier par défaut.
  if EstDossierParDefaut(Dossier) then
  begin
    RemplirDossiersDonneesApplication(Noms);
    Presents := SousDossiersPresents(Dossier, Noms);
    if Presents <> '' then
      Donnees := Donnees + '  - ' + Dossier + ' : ' + Presents + #13#10;
  end;
end;

// Étape usUninstall : lit les dossiers (installation.json, puis
// emplacements.json) et pose les questions (pas en silencieux).
procedure DeciderSuppressionChapitres;
var
  Chapitres, Donnees: String;
begin
  SupprimerChapitres := False;
  SupprimerDonneesApplication := False;
  SetArrayLength(DossiersChapitresDesinstallation, 0);
  if ParametrePresent('GARDERCHAPITRES') then
  begin
    Log('Désinstallation : /GARDERCHAPITRES, chapitres gardés.');
    Exit;
  end;
  Chapitres := '';
  Donnees := '';
  RetenirDossierChapitres(DossierChapitresInstalle, Chapitres, Donnees);
  RetenirDossierChapitres(DossierChapitresApplication, Chapitres, Donnees);
  if GetArrayLength(DossiersChapitresDesinstallation) = 0 then
    Exit;

  if UninstallSilent then
  begin
    // Silencieux : chapitres supprimés, journaux, rapports et exports gardés.
    SupprimerChapitres := True;
    Exit;
  end;

  SupprimerChapitres := MsgBox(
    'Supprimer aussi vos chapitres téléchargés ?' + #13#10 + Chapitres + #13#10 +
    'Oui : seuls les chapitres et couvertures enregistrés par l''application ' +
    '(dans manga, manhwa, manhua, roman, livre, autre) et le fichier repère ' +
    NomFichierRepere + ' sont supprimés, puis les dossiers devenus vides. Vos ' +
    'autres fichiers sont gardés.' + #13#10 +
    'Non : vos chapitres sont gardés ; une nouvelle installation les retrouvera.' + #13#10#13#10 +
    'Votre base (titres, sources, listes, réglages) est toujours conservée.',
    mbConfirmation, MB_YESNO) = IDYES;

  if SupprimerChapitres and (Donnees <> '') then
    SupprimerDonneesApplication := MsgBox(
      'Ces dossiers contiennent aussi des données de l''application (journaux, ' +
      'rapports d''erreur, exports de la bibliothèque) :' + #13#10 + Donnees + #13#10 +
      'Les supprimer aussi ?' + #13#10#13#10 +
      'Non (par défaut) : ils sont gardés.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

// Étape usPostUninstall : applique la décision à un dossier (règles de
// suppression_commune.iss, vérifiées de nouveau).
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
  SupprimerChapitresDossier(Dossier, SupprimerDonneesApplication, Supprimes,
    Restes);
  Log('Désinstallation : ' + IntToStr(Supprimes) + ' élément(s) supprimé(s), ' +
    IntToStr(Restes) + ' gardé(s) dans ' + Dossier);
  if DirExists(Dossier) then
    Log('Désinstallation : dossier gardé (non vide ou lien) ' + Dossier)
  else
    Log('Désinstallation : dossier vide supprimé ' + Dossier);
end;

// Étape usPostUninstall : applique la décision à chaque dossier retenu.
procedure AppliquerSuppressionChapitres;
var
  I: Integer;
begin
  if not SupprimerChapitres then
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

// Avant la confirmation : si l'application est ouverte, le client accepte
// qu'elle soit fermée (arrêt à l'étape usUninstall, après la confirmation) ou
// annule. En silencieux : pas de question.
function InitializeUninstall: Boolean;
begin
  Result := True;
  if UninstallSilent then
    Exit;
  if ProcessusApplication(ExpandConstant('{app}\{#NomExecutable}'), False) <= 0 then
    Exit;
  if SuppressibleMsgBox(
    '{#NomApplication} est ouverte, peut-être seulement dans la zone de ' +
    'notification (icône près de l''horloge). Elle sera fermée pendant la ' +
    'désinstallation.' + #13#10#13#10 +
    'Oui : continuer. Un téléchargement en cours sera interrompu.' + #13#10 +
    'Non : annuler. Vous pouvez la quitter vous-même (clic droit sur son ' +
    'icône > Quitter), puis relancer la désinstallation.',
    mbConfirmation, MB_YESNO, IDYES) <> IDYES then
    Result := False;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Erreur: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Accord déjà donné (InitializeUninstall) ou désinstallation silencieuse.
    Erreur := FermerApplication(ExpandConstant('{app}\{#NomExecutable}'),
      'la désinstallation', False);
    if Erreur <> '' then
      Log('Désinstallation : ' + Erreur);
    DeciderSuppressionChapitres;
  end
  else if CurUninstallStep = usPostUninstall then
  begin
    SupprimerDemarrageAvecWindows;
    AppliquerSuppressionChapitres;
  end;
end;
