; Désinstalleur complet de « Bibliothèque perso » (Inno Setup 6.7).
;
; Demande du client (2026-11-25) : un .exe à côté de l'installateur qui
; supprime TOUT ce que l'application a créé. C'est un « setup » qui n'installe
; rien (CreateAppDir=no, Uninstallable=no) : il ne laisse aucune trace.
;
; Construit par outils\construire_installateur.ps1, avec l'installateur :
;   ISCC /DVersion=X.Y.Z /DBuild=N desinstallateur.iss
;   -> livraisons\X.Y.Z\bibliotheque_perso-X.Y.Z-desinstallation.exe
;
; Ce qui est supprimé (après une seule confirmation, Non par défaut) :
; 1. L'application installée est arrêtée si elle est ouverte (même méthode
;    WMI que bibliotheque_perso.iss : seul le bibliotheque_perso.exe du
;    dossier d'installation, chemin complet comparé ; une copie de
;    développement n'est jamais touchée).
; 2. Le programme : désinstallateur Inno de l'application (clé
;    HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{AppId}_is1)
;    lancé en silencieux (/VERYSILENT /SUPPRESSMSGBOXES /NORESTART), fin
;    attendue. Il retire les fichiers du programme, les raccourcis et la clé
;    de désinstallation. Sans installation, on continue avec les données.
; 3. Les restes du dossier d'installation : données du navigateur intégré
;    (WebView2 : sans userDataFolder, flutter_inappwebview_windows 0.7.0-beta.3
;    crée l'environnement avec CreateCoreWebView2EnvironmentWithOptions(nullptr,
;    nullptr, …) ; WebView2 range alors ses données dans
;    <dossier de l'exe>\bibliotheque_perso.exe.WebView2), installation.json et,
;    si le désinstallateur Inno manquait, a échoué ou n'a pas fini, les
;    fichiers du programme (liste RÉCURSIVE des fichiers du dossier Release
;    relevée à la compilation ; seulement ces fichiers, puis les dossiers
;    devenus vides). Puis le dossier
;    d'installation s'il est vide. Si ce dossier est une racine ou un dossier
;    connu (Documents, Bureau, Program Files…), rien n'y est supprimé
;    directement (seul le désinstallateur du programme y retire ses fichiers).
; 4. Dans chaque dossier des chapitres connu (installation.json, valeur Inno
;    « DossierBibliotheque », emplacements.json de l'application, dossier par
;    défaut Documents\bibliotheque_perso), selon les règles de
;    suppression_commune.iss : repère .bibliotheque_perso obligatoire (sauf
;    dans le dossier par défaut), ni racine ni dossier connu ; dans les
;    dossiers de type (manga, manhwa, manhua, roman, livre, autre), seulement
;    les archives ch….zip et couvertures écrites par l'application (et leurs
;    .part, .deplacement) ; journaux, rapports et exports seulement dans le
;    dossier par défaut ; le repère ; puis les dossiers devenus vides. Jamais
;    le dossier choisi par le client en entier : ses autres fichiers restent.
;    La décision est prise au démarrage (avant que le désinstallateur du
;    programme ne supprime le repère).
; 5. Le dossier de la base, en entier (il appartient à l'application) :
;    getApplicationSupportDirectory() de path_provider_windows 2.3.0 =
;    %APPDATA%\<CompanyName>\<ProductName> (windows\runner\Runner.rc), soit
;    %APPDATA%\io.github.zerma1\bibliotheque_perso : base SQLite (et ses
;    fichiers -wal, -shm, -journal) et emplacements.json. Le dossier
;    io.github.zerma1 est supprimé s'il est vide.
; 6. Le dossier de cache %LOCALAPPDATA%\io.github.zerma1\bibliotheque_perso
;    (getApplicationCacheDirectory) s'il existe : l'application ne l'utilise
;    pas aujourd'hui, mais il lui appartiendrait.
; 7. Le démarrage avec Windows : valeur « Bibliotheque perso » de
;    HKCU\...\CurrentVersion\Run (lib/main.dart, launch_at_startup) si elle
;    lance le bibliotheque_perso.exe de l'installation (sans installation
;    trouvée : si elle contient bibliotheque_perso.exe), puis celle de
;    ...\Explorer\StartupApproved\Run (si aucune valeur Run ne reste).
; Rien d'autre n'est écrit par l'application : pas de fichier dans %TEMP%
; (les fichiers temporaires « .part » sont dans les dossiers ci-dessus), pas
; d'autre clé de registre.
;
; Le dossier d'installation et les dossiers des chapitres sont lus AVANT tout
; (au démarrage) : le désinstallateur Inno supprime installation.json.
;
; En silencieux (/VERYSILENT ou /SILENT) : aucune question, tout est supprimé.
; Journal : toujours écrit (SetupLogging), chemin affiché à la fin ; /LOG="…"
; pour choisir le fichier.
;
; Liens (jonctions, liens symboliques) : jamais suivis par ce programme
; (voir suppression_commune.iss ; un dossier entier qui est un lien est
; gardé).
;
; Seulement si le désinstallateur Inno de l'application est absent, a échoué
; (code non nul) ou n'a pas fini, on retire aussi : la clé « Applications
; installées » restante, les fichiers du désinstallateur Inno dont le nom de
; base est celui de UninstallString (.exe, .dat, .msg ; nom inconnu : rien),
; et les raccourcis « Bibliothèque perso » du menu Démarrer et du Bureau
; seulement s'ils lancent le bibliotheque_perso.exe de l'installation (cible
; lue par WScript.Shell).
;
; Essais seulement (pour ne jamais toucher aux données réelles du client) :
;   /DIdApplication="{{…}"            AppId de l'application visée
;   /DDossierBase="C:\essai\base"     dossier de la base
;   /DDossierCache="C:\essai\cache"   dossier de cache local
;   /DDossierDocuments="C:\essai\doc" dossier Documents
;   /DNomEntreeDemarrage="Essai…"     nom de la valeur Run

#ifndef Version
  #error Version absente : lancer outils\construire_installateur.ps1, ou ISCC /DVersion=X.Y.Z
#endif
#ifndef Build
  #define Build "0"
#endif
#ifndef DossierRelease
  #define DossierRelease "..\build\windows\x64\runner\Release"
#endif

; AppId de l'APPLICATION (bibliotheque_perso.iss), pas celui de ce
; désinstalleur.
#ifndef IdApplication
  #define IdApplication "{{827D980C-013C-4734-94F1-BB09CBAA7712}"
#endif
#ifndef DossierBase
  #define DossierBase "{userappdata}\io.github.zerma1\bibliotheque_perso"
#endif
#ifndef DossierCache
  #define DossierCache "{localappdata}\io.github.zerma1\bibliotheque_perso"
#endif
#ifndef DossierDocuments
  #define DossierDocuments "{userdocs}"
#endif
#ifndef NomEntreeDemarrage
  #define NomEntreeDemarrage "Bibliotheque perso"
#endif

#define NomApplication "Bibliothèque perso"
#define NomExecutable "bibliotheque_perso.exe"

; Fichiers et dossiers du programme, relevés RÉCURSIVEMENT dans le dossier
; Release à la compilation (parcours en largeur), pour le cas où le
; désinstallateur Inno de l'application manque ou échoue. Chemins relatifs
; séparés par « | » : FichiersProgramme (fichiers seuls), DossiersProgramme
; (dossiers, parents avant enfants). Seuls ces fichiers sont supprimés, puis
; ces dossiers s'ils sont devenus vides (du plus profond au moins profond) :
; un fichier ajouté par le client (data\client.txt) reste.
#define BaseRelease AddBackslash(SourcePath) + DossierRelease + "\"
#define FichiersProgramme ""
#define DossiersProgramme ""
#define FileAttente "|"
#define DossierCourant ""
#define RechercheRelease
#define TrouveRelease
#define Bidon 0
#sub AjouterElementProgramme
  #define NomElement FindGetFileName(RechercheRelease)
  #if NomElement != "." && NomElement != ".."
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
  #pragma warning "Dossier Release introuvable : sans désinstallateur Inno, les fichiers du programme ne seront pas supprimés."
#endif

[Setup]
; Identifiant propre au désinstalleur (différent de celui de l'application) ;
; rien n'est enregistré (Uninstallable=no).
AppId={{5E0C3B7A-2F4D-4B8E-9C61-7A2D9F3E8B15}
AppName={#NomApplication}
AppVersion={#Version}
AppVerName=Désinstallation complète de {#NomApplication} {#Version}
AppPublisher=Bibliothèque perso
VersionInfoVersion={#Version}.{#Build}
VersionInfoProductVersion={#Version}
VersionInfoDescription=Désinstallation complète de {#NomApplication}
PrivilegesRequired=lowest
CreateAppDir=no
Uninstallable=no
DisableProgramGroupPage=yes
DisableWelcomePage=yes
; La confirmation est demandée sur la page de la liste (NextButtonClick).
DisableReadyPage=yes
UsedUserAreasWarning=no
SetupLogging=yes
SetupIconFile=..\assets\logo\logo.ico
WizardStyle=modern
ShowLanguageDialog=no
OutputDir=..\livraisons\{#Version}
OutputBaseFilename=bibliotheque_perso-{#Version}-desinstallation
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Messages]
SetupAppTitle=Désinstallation complète
SetupWindowTitle=Désinstallation complète de %1
ButtonInstall=&Tout supprimer
WizardInstalling=Suppression
InstallingLabel=Suppression de %1 et de ses données en cours…
FinishedHeadingLabel=Désinstallation complète terminée
FinishedLabelNoIcons=La suppression est terminée. Le résumé figure à la page précédente et dans le journal.
FinishedLabel=La suppression est terminée. Le résumé figure à la page précédente et dans le journal.
ExitSetupMessage=Rien n'a encore été supprimé.%n%nQuitter ?

[Code]
#include "suppression_commune.iss"

const
  NomFichierInstallation = 'installation.json';
  CleDossierBibliotheque = 'dossierBibliotheque';
  // Écrit par l'application dans le dossier de sa base.
  NomFichierEmplacements = 'emplacements.json';
  CleDossierChapitres = 'dossierChapitres';
  // Valeur mémorisée par bibliotheque_perso.iss (RegisterPreviousData).
  ClePreviousData = 'DossierBibliotheque';
  // Dossier de l'éditeur (CompanyName de windows\runner\Runner.rc), parent
  // des dossiers de la base et du cache : supprimé s'il devient vide.
  NomDossierEditeur = 'io.github.zerma1';
  // Données WebView2 du navigateur intégré, dans le dossier d'installation.
  NomDossierWebView2 = '{#NomExecutable}.WebView2';
  CleDemarrageRun = 'Software\Microsoft\Windows\CurrentVersion\Run';
  CleDemarrageApprouve =
    'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  // Attente de la fin des processus arrêtés et du désinstallateur Inno.
  AttenteArretMaxMs = 15000;
  AttenteDesinstallationMaxMs = 60000;

var
  // Relevés au démarrage (InitializeSetup), avant toute suppression.
  DossierApplication: String;        // '' : aucune installation trouvée
  DesinstallateurApplication: String; // unins000.exe, '' si absent
  // Chemin du désinstallateur tel que relevé dans UninstallString, même si
  // le fichier manque ('' si la valeur est absente) : seuls ses fichiers
  // (même nom de base, .exe, .dat, .msg) sont supprimés par le repli.
  DesinstallateurReleve: String;
  // Dossier d'installation égal à (ou contenant) un dossier connu du système
  // ou de l'utilisateur : son contenu n'est jamais touché par ce programme.
  ApplicationProtegee: Boolean;
  // Désinstallateur du programme lancé, code 0 et fin constatée.
  DesinstallationReussie: Boolean;
  DossiersChapitres: TArrayOfString;
  OriginesChapitres: TArrayOfString;
  // Relevés au démarrage : raison de ne pas toucher au dossier ('' : il est
  // traité) et contenu de l'application qu'il contient.
  MotifsChapitres: TArrayOfString;
  ContenusChapitres: TArrayOfString;
  DossierBase: String;
  DossierCache: String;
  CommandeDemarrage: String;         // valeur Run à supprimer, '' sinon
  ApprouveASupprimer: Boolean;
  PageListe: TOutputMsgMemoWizardPage;
  PageResultat: TOutputMsgMemoWizardPage;
  // Résumé des suppressions (page de résultat et journal).
  Resume: String;
  Echecs: Integer;

// ---------------------------------------------------------------------------
// Lecture des fichiers JSON (installation.json, emplacements.json).
// ---------------------------------------------------------------------------

// Lit la valeur texte de "Cle" dans un fichier JSON simple (UTF-8, avec ou
// sans BOM). Renvoie '' si le fichier est absent, illisible, ou si la valeur
// n'est pas une chaîne (null par exemple).
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

// Listes des dossiers de l'application, repère et règles de sécurité :
// suppression_commune.iss (inclus au début de la section [Code]).

function CleDesinstallationApplication: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
    ExpandConstant('{#IdApplication}') + '_is1';
end;

// ---------------------------------------------------------------------------
// Relevé initial (avant toute suppression).
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
    if CompareText(AddBackslash(DossiersChapitres[I]), AddBackslash(D)) = 0 then
      Exit;
  SetArrayLength(DossiersChapitres, N + 1);
  SetArrayLength(OriginesChapitres, N + 1);
  DossiersChapitres[N] := D;
  OriginesChapitres[N] := Origine;
  Log('Dossier des chapitres connu (' + Origine + ') : ' + D);
end;

procedure ReleverInstallation;
var
  Valeur: String;
begin
  DossierApplication := '';
  DesinstallateurApplication := '';
  DesinstallateurReleve := '';
  ApplicationProtegee := False;
  if RegQueryStringValue(HKCU, CleDesinstallationApplication, 'InstallLocation',
    Valeur) then
    DossierApplication := Trim(Valeur);
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
    // est lancé, mais ce programme n'y supprime rien lui-même.
    else if EstDossierProtege(DossierApplication) then
    begin
      Log('Dossier d''installation protégé (racine ou dossier connu), son ' +
        'contenu ne sera pas touché directement : ' + DossierApplication);
      ApplicationProtegee := True;
    end;
  end;
  if DossierApplication <> '' then
    Log('Installation trouvée : ' + DossierApplication + ' (désinstallateur : ' +
      DesinstallateurApplication + ')')
  else
    Log('Aucune installation trouvée (clé ' + CleDesinstallationApplication + ').');
end;

procedure ReleverDemarrage;
var
  Commande, Exe: String;
  Lance: Boolean;
begin
  CommandeDemarrage := '';
  ApprouveASupprimer := False;
  if RegQueryStringValue(HKCU, CleDemarrageRun, '{#NomEntreeDemarrage}', Commande) then
  begin
    if DossierApplication <> '' then
    begin
      Exe := AddBackslash(DossierApplication) + '{#NomExecutable}';
      Lance := Pos(Lowercase(Exe), Lowercase(Commande)) > 0;
    end
    else
      Lance := Pos(Lowercase('{#NomExecutable}'), Lowercase(Commande)) > 0;
    if Lance then
    begin
      CommandeDemarrage := Commande;
      ApprouveASupprimer := RegValueExists(HKCU, CleDemarrageApprouve,
        '{#NomEntreeDemarrage}');
    end
    else
      Log('Démarrage avec Windows d''une autre copie, gardé : ' + Commande);
  end
  else
    // Valeur orpheline (sans valeur Run) : elle ne sert plus à rien.
    ApprouveASupprimer := RegValueExists(HKCU, CleDemarrageApprouve,
      '{#NomEntreeDemarrage}');
end;

procedure Relever;
var
  Valeur: String;
begin
  SetArrayLength(DossiersChapitres, 0);
  SetArrayLength(OriginesChapitres, 0);
  DossierBase := RemoveBackslashUnlessRoot(ExpandConstant('{#DossierBase}'));
  DossierCache := RemoveBackslashUnlessRoot(ExpandConstant('{#DossierCache}'));
  ReleverInstallation;
  if DossierApplication <> '' then
    AjouterDossierChapitres(LireValeurJson(AddBackslash(DossierApplication) +
      NomFichierInstallation, CleDossierBibliotheque), 'choisi à l''installation');
  if RegQueryStringValue(HKCU, CleDesinstallationApplication,
    'Inno Setup CodeFile: ' + ClePreviousData, Valeur) then
    AjouterDossierChapitres(Valeur, 'choisi à l''installation');
  AjouterDossierChapitres(LireValeurJson(AddBackslash(DossierBase) +
    NomFichierEmplacements, CleDossierChapitres), 'choisi dans l''application');
  AjouterDossierChapitres(DossierChapitresParDefaut, 'dossier par défaut');
  ReleverDemarrage;
end;

// ---------------------------------------------------------------------------
// Application ouverte (même méthode que bibliotheque_perso.iss).
// ---------------------------------------------------------------------------

// Nombre de processus {#NomExecutable} dont le chemin complet est Exe (casse
// ignorée) ; si Arreter, chacun est arrêté. -1 si WMI est indisponible.
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

function ExeInstalle: String;
begin
  Result := AddBackslash(DossierApplication) + '{#NomExecutable}';
end;

// Arrête l'application installée. '' si elle n'est pas (ou plus) ouverte,
// sinon le message d'erreur.
function FermerApplication: String;
var
  Attente: Integer;
begin
  Result := '';
  if DossierApplication = '' then
    Exit;
  if ProcessusApplication(ExeInstalle, False) <= 0 then
    Exit;
  ProcessusApplication(ExeInstalle, True);
  Attente := 0;
  while (ProcessusApplication(ExeInstalle, False) > 0) and
    (Attente < AttenteArretMaxMs) do
  begin
    Sleep(250);
    Attente := Attente + 250;
  end;
  if ProcessusApplication(ExeInstalle, False) > 0 then
    Result := 'Impossible de fermer {#NomApplication}. Quittez-la (clic droit ' +
      'sur son icône dans la zone de notification > Quitter), puis relancez ' +
      'la désinstallation complète. Rien n''a été supprimé.'
  else
  begin
    Log('Application arrêtée : ' + ExeInstalle);
    // Le temps que Windows libère les fichiers (base, vues web).
    Sleep(1000);
  end;
end;

// ---------------------------------------------------------------------------
// Liste de ce qui sera supprimé.
// ---------------------------------------------------------------------------

function TexteListe: String;
var
  I: Integer;
  Contenu, Ligne: String;
  Fin: String;
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
  if DirExists(DossierBase) then
    Result := Result + '   ' + DossierBase + ' (dossier entier)' + Fin
  else
    Result := Result + '   Absente (' + DossierBase + ').' + Fin;
  if DirExists(DossierCache) then
    Result := Result + '   ' + DossierCache + ' (cache, dossier entier)' + Fin;
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

procedure InitializeWizard;
begin
  Log('Liste affichée :' + #13#10 + TexteListe);
  PageListe := CreateOutputMsgMemoPage(wpWelcome,
    'Désinstallation complète',
    'Tout ce que {#NomApplication} a créé sur cet ordinateur',
    'Vérifiez la liste, puis cliquez sur « Tout supprimer ». Une confirmation ' +
    'vous sera demandée.',
    TexteListe);
  PageResultat := CreateOutputMsgMemoPage(wpInstalling,
    'Résultat',
    'Ce qui a été supprimé',
    'Résumé de la désinstallation complète :',
    '');
end;

function InitializeSetup: Boolean;
var
  I, N: Integer;
begin
  Relever;
  // Décision prise ici, avant que le désinstallateur du programme ne
  // supprime le repère : les règles de suppression_commune.iss.
  // LIMITE : un dossier sur un NAS éteint ou un lecteur réseau déconnecté
  // peut faire attendre le démarrage quelques dizaines de secondes (délai
  // réseau de Windows dans DirExists) ; il est alors noté « introuvable ou
  // injoignable » et rien n'y est supprimé.
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
  Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = PageListe.ID) and not WizardSilent then
    Result := MsgBox('Supprimer définitivement {#NomApplication}, votre base et ' +
      'vos chapitres téléchargés ?' + #13#10#13#10 +
      'Cette opération est irréversible.' + #13#10#13#10 +
      'Oui : tout supprimer.' + #13#10 +
      'Non (par défaut) : ne rien supprimer.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

// Dernière étape avant les suppressions : arrêt de l'application (une chaîne
// non vide arrête tout, sans rien supprimer).
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := FermerApplication;
end;

// ---------------------------------------------------------------------------
// Suppressions.
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
  // les retire sans toucher à leur cible (vérifié par essai le 2026-11-25 :
  // jonctions vers un fichier externe placées dans le dossier de la base et
  // dans .WebView2, fichier externe intact).
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

// Supprime Parent (dossier de l'éditeur) s'il est vide.
procedure SupprimerDossierEditeurSiVide(const Dossier: String);
var
  Parent: String;
begin
  Parent := ExtractFileDir(Dossier);
  if CompareText(ExtractFileName(Parent), NomDossierEditeur) = 0 then
    SupprimerSiVide(Parent, '');
end;

// Lance le désinstallateur Inno de l'application et attend sa fin. Inno
// recopie le désinstallateur dans %TEMP% et le relance : on attend en plus
// que unins000.exe ait disparu.
procedure DesinstallerProgramme;
var
  Code, Attente: Integer;
begin
  DesinstallationReussie := False;
  if DesinstallateurApplication = '' then
  begin
    if DossierApplication <> '' then
      Noter('Désinstallateur du programme absent : fichiers du programme ' +
        'supprimés directement.');
    Exit;
  end;
  Log('Lancement : ' + DesinstallateurApplication +
    ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART');
  if not Exec(DesinstallateurApplication, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
    '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Noter('ÉCHEC : désinstallateur du programme non lancé (' +
      SysErrorMessage(Code) + ').');
    Echecs := Echecs + 1;
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
  DesinstallationReussie := (Code = 0) and
    not FileExists(DesinstallateurApplication);
  if DesinstallationReussie then
    Noter('Supprimé : programme, raccourcis et entrée « Applications ' +
      'installées » (désinstallateur du programme).')
  else
    Noter('Désinstallateur du programme en échec ou fin non constatée (code ' +
      IntToStr(Code) + ') : restes supprimés directement.');
end;

// Raccourci laissé par une installation sans désinstallateur : supprimé
// seulement s'il lance le {#NomExecutable} de cette installation (un
// raccourci du même nom vers une autre copie est gardé).
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

// Supprime un FICHIER du programme (jamais un dossier ni un lien) ; note un
// échec.
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
  // profond au moins profond (ordre inverse du parcours en largeur).
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
  // celui relevé dans UninstallString (unins000 → unins000.exe, .dat, .msg),
  // et seulement s'il est dans le dossier d'installation. Inconnu : rien
  // (un unins001 d'une autre application reste). Jamais pendant qu'il tourne
  // encore (fin non constatée).
  if (DesinstallateurReleve <> '') and
    (CompareText(RemoveBackslashUnlessRoot(ExtractFileDir(DesinstallateurReleve)),
    DossierApplication) = 0) and
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
  SupprimerRaccourci(ExpandConstant('{userprograms}\{#NomApplication}.lnk'));
  SupprimerRaccourci(ExpandConstant('{userdesktop}\{#NomApplication}.lnk'));
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
// Le désinstallateur du programme en a peut-être déjà supprimé une partie (et
// le dossier s'il est devenu vide) : le résumé part du contenu relevé au
// démarrage (ContenusChapitres[Indice]).
// La décision (MotifsChapitres) a été prise au démarrage, repère encore
// présent : le désinstallateur du programme l'a peut-être supprimé depuis.
procedure SupprimerChapitres(const Indice: Integer);
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
    // Revérifié juste avant de supprimer (protégé, lien, repère…). Le repère
    // a pu être retiré entre-temps par le désinstallateur du programme, qui
    // a alors déjà traité ce dossier avec les mêmes règles : rien de plus
    // n'est supprimé ici.
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
procedure SupprimerDemarrage;
begin
  if CommandeDemarrage <> '' then
  begin
    if not RegValueExists(HKCU, CleDemarrageRun, '{#NomEntreeDemarrage}') or
      RegDeleteValue(HKCU, CleDemarrageRun, '{#NomEntreeDemarrage}') then
      Noter('Supprimé : démarrage avec Windows (' + CommandeDemarrage + ')')
    else
    begin
      Noter('ÉCHEC : démarrage avec Windows non supprimé (valeur Run).');
      Echecs := Echecs + 1;
    end;
  end;
  if ApprouveASupprimer and
    not RegValueExists(HKCU, CleDemarrageRun, '{#NomEntreeDemarrage}') then
  begin
    if not RegValueExists(HKCU, CleDemarrageApprouve, '{#NomEntreeDemarrage}') or
      RegDeleteValue(HKCU, CleDemarrageApprouve, '{#NomEntreeDemarrage}') then
      Log('Supprimé : valeur StartupApproved du démarrage avec Windows.')
    else
    begin
      Noter('ÉCHEC : valeur StartupApproved du démarrage avec Windows non supprimée.');
      Echecs := Echecs + 1;
    end;
  end;
end;

procedure ToutSupprimer;
var
  I: Integer;
begin
  Resume := '';
  Echecs := 0;
  DesinstallerProgramme;
  SupprimerRestesInstallation;
  for I := 0 to GetArrayLength(DossiersChapitres) - 1 do
    SupprimerChapitres(I);
  SupprimerDossierEntier(DossierBase, 'base et réglages');
  SupprimerDossierEditeurSiVide(DossierBase);
  SupprimerDossierEntier(DossierCache, 'cache');
  SupprimerDossierEditeurSiVide(DossierCache);
  SupprimerDemarrage;
  if Resume = '' then
    Noter('Rien à supprimer : aucune trace de {#NomApplication} trouvée.');
  if Echecs > 0 then
    Noter(#13#10 + IntToStr(Echecs) + ' élément(s) non supprimé(s) : fichier ' +
      'peut-être ouvert par un autre programme. Relancez la désinstallation ' +
      'complète après avoir redémarré l''ordinateur.')
  else
    Noter(#13#10 + 'Désinstallation complète réussie.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    ToutSupprimer;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = PageResultat.ID then
    PageResultat.RichEditViewer.Text := Resume + #13#10 + 'Journal : ' +
      ExpandConstant('{log}');
end;
