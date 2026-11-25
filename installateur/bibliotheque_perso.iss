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
;   le dossier de installation.json : les sous-dossiers des types de titres
;   (TypeTitre de lib/modeles/titre.dart) et le fichier repère
;   .bibliotheque_perso (lib/donnees/constantes_donnees.dart), puis le dossier
;   s'il est vide. Journaux, rapports et exports de ce dossier sont gardés,
;   sauf confirmation (Non par défaut, jamais en silencieux).
;   LIMITE : un dossier des chapitres changé dans l'application (réglage en
;   base) n'est pas connu de l'installateur : ces chapitres ne sont pas
;   supprimés.
;
; Paramètres de la ligne de commande (en plus de ceux d'Inno Setup) :
;   /BIBLIOTHEQUE="D:\Mes chapitres"   dossier de la bibliothèque (installation
;                                      silencieuse ou valeur proposée) ;
;                                      ignoré lors d'une mise à jour.
;   /GARDERCHAPITRES                   désinstallation : garde les chapitres
;                                      téléchargés (pas de question).
; Mise à jour silencieuse avec l'application ouverte : ajouter /CLOSEAPPLICATIONS.
; Essais seulement : /DIdApplication="{{…}" donne un autre AppId, pour ne pas
; toucher à l'installation réelle du client.

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
const
  NomFichierInstallation = 'installation.json';
  CleDossierBibliotheque = 'dossierBibliotheque';
  // Mémorisé aussi dans les données d'Inno Setup (registre de l'utilisateur),
  // au cas où installation.json aurait disparu.
  ClePreviousData = 'DossierBibliotheque';

var
  PageBibliotheque: TInputDirWizardPage;
  PageConservation: TOutputMsgWizardPage;
  // Figé dans PrepareToInstall (avant la copie des fichiers).
  MiseAJourEnCours: Boolean;
  // Désinstallation : décidés à l'étape usUninstall (installation.json encore
  // présent), appliqués à l'étape usPostUninstall.
  DossierChapitresDesinstallation: String;
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

// Lit la valeur de "dossierBibliotheque" dans un installation.json existant
// (UTF-8, avec ou sans BOM). Renvoie '' si le fichier est absent ou illisible.
function LireDossierInstallationJson(const Fichier: String): String;
var
  Brut: AnsiString;
  Texte, Cle, Valeur: String;
  P, I, Code: Integer;
  C: Char;
begin
  Result := '';
  if not FileExists(Fichier) then
    Exit;
  if not LoadStringFromFile(Fichier, Brut) then
    Exit;
  Texte := UTF8Decode(Brut);
  Cle := '"' + CleDossierBibliotheque + '"';
  P := Pos(Cle, Texte);
  if P = 0 then
    Exit;
  I := P + Length(Cle);
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
      'fichiers sont gardés. Les chapitres déplacés ailleurs depuis ' +
      'l''application ne sont pas supprimés.' + #13#10#13#10 +
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

// Toujours appelé, y compris en mode silencieux : dernière vérification avant
// de copier quoi que ce soit (une chaîne non vide annule l'installation).
// Le type d'installation est figé ici, avant la copie des fichiers.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
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

// Sous-dossiers propres à l'application dans le dossier des chapitres : un
// par valeur de TypeTitre (lib/modeles/titre.dart, `type.name`). À tenir à
// jour si un type est ajouté.
procedure RemplirDossiersChapitres(var Noms: TArrayOfString);
begin
  SetArrayLength(Noms, 6);
  Noms[0] := 'manga';
  Noms[1] := 'manhwa';
  Noms[2] := 'manhua';
  Noms[3] := 'roman';
  Noms[4] := 'livre';
  Noms[5] := 'autre';
end;

// Données de l'application qui peuvent se trouver dans le même dossier quand
// c'est le dossier par défaut (Documents\bibliotheque_perso) : journaux
// (lib/donnees/journal_fichier.dart), rapports et exports
// (lib/services/constantes_services.dart). Gardées par défaut.
procedure RemplirDossiersDonneesApplication(var Noms: TArrayOfString);
begin
  SetArrayLength(Noms, 3);
  Noms[0] := 'journaux';
  Noms[1] := 'rapports';
  Noms[2] := 'exports';
end;

// Fichier repère du dossier des chapitres (nomFichierMarqueurRacine,
// lib/donnees/constantes_donnees.dart).
function NomFichierRepere: String;
begin
  Result := '.bibliotheque_perso';
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

// Liste, séparée par des virgules, des noms de Noms présents dans Dossier.
function SousDossiersPresents(const Dossier: String; const Noms: TArrayOfString): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(Noms) - 1 do
    if DirExists(AddBackslash(Dossier) + Noms[I]) then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Noms[I];
    end;
end;

// Étape usUninstall : lit le dossier et pose les questions (pas en silencieux).
procedure DeciderSuppressionChapitres;
var
  Dossier, Chapitres, Donnees: String;
  Noms: TArrayOfString;
begin
  SupprimerChapitres := False;
  SupprimerDonneesApplication := False;
  Dossier := DossierChapitresInstalle;
  DossierChapitresDesinstallation := Dossier;
  if ParametrePresent('GARDERCHAPITRES') then
  begin
    Log('Désinstallation : /GARDERCHAPITRES, chapitres gardés.');
    Exit;
  end;
  // Même contrôle qu'à l'installation : chemin complet seulement.
  if (Dossier = '') or (VerifierDossierBibliotheque(Dossier,
    ExpandConstant('{app}')) <> '') then
  begin
    Log('Désinstallation : dossier des chapitres inconnu ou refusé (' +
      Dossier + '), rien à supprimer.');
    Exit;
  end;
  if not DirExists(Dossier) then
  begin
    Log('Désinstallation : dossier des chapitres absent ou injoignable (' +
      Dossier + '), rien à supprimer.');
    Exit;
  end;
  RemplirDossiersChapitres(Noms);
  Chapitres := SousDossiersPresents(Dossier, Noms);
  if (Chapitres = '') and not FileExists(AddBackslash(Dossier) + NomFichierRepere) then
  begin
    Log('Désinstallation : aucun chapitre dans ' + Dossier + '.');
    Exit;
  end;
  RemplirDossiersDonneesApplication(Noms);
  Donnees := SousDossiersPresents(Dossier, Noms);

  if UninstallSilent then
  begin
    // Silencieux : chapitres supprimés, journaux, rapports et exports gardés.
    SupprimerChapitres := True;
    Exit;
  end;

  SupprimerChapitres := MsgBox(
    'Supprimer aussi vos chapitres téléchargés (dossier ' + Dossier + ') ?' + #13#10#13#10 +
    'Oui : seuls les dossiers des chapitres de l''application (manga, manhwa, ' +
    'manhua, roman, livre, autre) et le fichier repère ' + NomFichierRepere +
    ' sont supprimés, puis le dossier s''il est vide. Vos autres fichiers de ce ' +
    'dossier sont gardés.' + #13#10 +
    'Non : vos chapitres sont gardés ; une nouvelle installation les retrouvera.' + #13#10#13#10 +
    'Les chapitres déplacés ailleurs depuis l''application (Paramètres > ' +
    'Dossier des chapitres) ne sont pas supprimés. Votre base (titres, ' +
    'sources, listes, réglages) est toujours conservée.',
    mbConfirmation, MB_YESNO) = IDYES;

  if SupprimerChapitres and (Donnees <> '') then
    SupprimerDonneesApplication := MsgBox(
      'Ce dossier contient aussi des données de l''application : ' + Donnees +
      ' (journaux, rapports d''erreur, exports de la bibliothèque).' + #13#10#13#10 +
      'Les supprimer aussi ?' + #13#10#13#10 +
      'Non (par défaut) : ils sont gardés.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

// Supprime Dossier\Nom (dossier) pour chaque nom présent ; journalise.
procedure SupprimerSousDossiers(const Dossier: String; const Noms: TArrayOfString);
var
  I: Integer;
  Chemin: String;
begin
  for I := 0 to GetArrayLength(Noms) - 1 do
  begin
    Chemin := AddBackslash(Dossier) + Noms[I];
    if DirExists(Chemin) then
    begin
      if DelTree(Chemin, True, True, True) then
        Log('Désinstallation : supprimé ' + Chemin)
      else
        Log('Désinstallation : suppression incomplète de ' + Chemin);
    end;
  end;
end;

// Étape usPostUninstall : applique la décision.
procedure AppliquerSuppressionChapitres;
var
  Dossier: String;
  Noms: TArrayOfString;
begin
  Dossier := DossierChapitresDesinstallation;
  if not SupprimerChapitres or (Dossier = '') then
    Exit;
  RemplirDossiersChapitres(Noms);
  SupprimerSousDossiers(Dossier, Noms);
  if SupprimerDonneesApplication then
  begin
    RemplirDossiersDonneesApplication(Noms);
    SupprimerSousDossiers(Dossier, Noms);
  end;
  if FileExists(AddBackslash(Dossier) + NomFichierRepere) then
    DeleteFile(AddBackslash(Dossier) + NomFichierRepere);
  // RemoveDir échoue sans rien supprimer si le dossier n'est pas vide.
  if RemoveDir(Dossier) then
    Log('Désinstallation : dossier vide supprimé ' + Dossier)
  else
    Log('Désinstallation : dossier gardé (non vide) ' + Dossier);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    DeciderSuppressionChapitres
  else if CurUninstallStep = usPostUninstall then
    AppliquerSuppressionChapitres;
end;
