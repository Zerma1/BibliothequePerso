// Règles de suppression de bibliotheque_perso.iss (désinstallation et « Tout
// supprimer », un seul script depuis 0.3.3), incluses dans sa section [Code]
// (#include). Requiert le define DossierDocuments (dossier Documents, redirigé
// seulement pour les essais).
//
// Sécurité (relecture du 2026-11-25) :
// 1. Un dossier des chapitres n'est traité que s'il contient le repère
//    .bibliotheque_perso, sauf le dossier par défaut Documents\bibliotheque_perso.
//    Garanti par l'application (lib/donnees/stockage_telechargements.dart) :
//    un dossier choisi (StockageTelechargements.personnalise) reçoit le repère
//    à sa validation (validerDossier) et toute écriture y est refusée sans
//    repère (verifierDossierRacine dans ouvrirEcriture,
//    enregistrerCouverture…). Seul le dossier par défaut peut ne pas l'avoir.
// 2. journaux, rapports et exports : seulement dans le dossier par défaut
//    (dossier de l'application, lib/main.dart racineApplication).
// 3. Jamais une racine (C:\, \\serveur\partage) ni un dossier connu du système
//    ou de l'utilisateur (ou un dossier qui en contient un).
// 4. Dans les dossiers de type (<racine>\<type>\<titre>\…), seuls les fichiers
//    créés par l'application sont supprimés : archives ch….zip, couvertures
//    couverture.<ext>, et leurs fichiers temporaires .part et .deplacement
//    (motifs de stockage_telechargements.dart). Livres importés
//    (import[.<n>].<cbz|pdf|epub>) : seulement avec « Tout supprimer »,
//    jamais avec « Désinstaller ». Puis les dossiers devenus vides. Jamais
//    DelTree d'un dossier de type.
// Liens (jonctions, liens symboliques : attribut « reparse point ») : jamais
// suivis ni supprimés par ce parcours ; un dossier des chapitres qui est
// lui-même un lien est refusé (rien n'y est supprimé).
// Chemins suspects (\\?\, « . », « .. », noms courts « ~ », « / ») : refusés
// avant toute comparaison aux dossiers connus.

const
  AttributDossier = $10;
  AttributPointAnalyse = $400;
  // Dossier par défaut des chapitres, dans Documents
  // (nomDossierRacineTelechargements, lib/modeles/constantes.dart).
  NomDossierChapitresParDefaut = 'bibliotheque_perso';
  // Fichier repère (nomFichierMarqueurRacine, lib/donnees/constantes_donnees.dart).
  NomFichierRepere = '.bibliotheque_perso';
  // Fichier d'essai d'écriture (prefixeFichierEssaiEcriture).
  PrefixeEssaiEcriture = '.essai_ecriture_';

// Dossiers de type : un par valeur de TypeTitre (lib/modeles/titre.dart,
// `type.name`). À tenir à jour si un type est ajouté.
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

// Données de l'application dans le dossier par défaut : journaux
// (lib/donnees/journal_fichier.dart), rapports et exports
// (lib/services/constantes_services.dart).
procedure RemplirDossiersDonneesApplication(var Noms: TArrayOfString);
begin
  SetArrayLength(Noms, 3);
  Noms[0] := 'journaux';
  Noms[1] := 'rapports';
  Noms[2] := 'exports';
end;

function DossierChapitresParDefaut: String;
begin
  Result := AddBackslash(ExpandConstant('{#DossierDocuments}')) +
    NomDossierChapitresParDefaut;
end;

// Vrai si Chemin est un chemin complet : lecteur (C:\…) ou réseau (\\nas\…).
function EstCheminComplet(const Chemin: String): Boolean;
begin
  Result := ((Length(Chemin) >= 3) and (Chemin[2] = ':') and (Chemin[3] = '\'))
    or (Copy(Chemin, 1, 2) = '\\');
end;

// Vrai si Chemin est Dossier ou se trouve dedans (casse ignorée).
function EstDansDossier(const Chemin, Dossier: String): Boolean;
var
  A, B: String;
begin
  A := Lowercase(AddBackslash(Trim(Chemin)));
  B := Lowercase(AddBackslash(Trim(Dossier)));
  Result := Copy(A, 1, Length(B)) = B;
end;

function EstDossierParDefaut(const Dossier: String): Boolean;
begin
  Result := CompareText(AddBackslash(Trim(Dossier)),
    AddBackslash(DossierChapitresParDefaut)) = 0;
end;

// Racine d'un disque (C:\) ou d'un partage réseau (\\serveur\partage).
function EstRacine(const Chemin: String): Boolean;
var
  I, N: Integer;
  DansSegment: Boolean;
begin
  if Copy(Chemin, 1, 2) = '\\' then
  begin
    N := 0;
    DansSegment := False;
    for I := 3 to Length(Chemin) do
      if Chemin[I] = '\' then
        DansSegment := False
      else if not DansSegment then
      begin
        DansSegment := True;
        N := N + 1;
      end;
    Result := N <= 2;
  end
  else
    Result := Length(RemoveBackslash(Trim(Chemin))) <= 2;
end;

procedure AjouterDossierConnu(var Liste: TArrayOfString; const Constante: String);
var
  Chemin: String;
  N: Integer;
begin
  try
    Chemin := Trim(ExpandConstant(Constante));
  except
    Chemin := '';
  end;
  if (Chemin = '') or not EstCheminComplet(Chemin) then
    Exit;
  N := GetArrayLength(Liste);
  SetArrayLength(Liste, N + 1);
  Liste[N] := RemoveBackslashUnlessRoot(Chemin);
end;

// Dossiers du système et de l'utilisateur : jamais supprimés, ni vidés.
procedure RemplirDossiersConnus(var Liste: TArrayOfString);
begin
  SetArrayLength(Liste, 0);
  AjouterDossierConnu(Liste, '{%USERPROFILE}');
  AjouterDossierConnu(Liste, '{userdocs}');
  AjouterDossierConnu(Liste, '{userdesktop}');
  AjouterDossierConnu(Liste, '{%USERPROFILE}\Downloads');
  AjouterDossierConnu(Liste, '{%USERPROFILE}\Pictures');
  AjouterDossierConnu(Liste, '{%USERPROFILE}\Music');
  AjouterDossierConnu(Liste, '{%USERPROFILE}\Videos');
  AjouterDossierConnu(Liste, '{%OneDrive}');
  AjouterDossierConnu(Liste, '{userappdata}');
  AjouterDossierConnu(Liste, '{localappdata}');
  AjouterDossierConnu(Liste, '{localappdata}\Programs');
  AjouterDossierConnu(Liste, '{userprograms}');
  AjouterDossierConnu(Liste, '{userstartmenu}');
  AjouterDossierConnu(Liste, '{userstartup}');
  AjouterDossierConnu(Liste, '{%TEMP}');
  AjouterDossierConnu(Liste, '{%PUBLIC}');
  AjouterDossierConnu(Liste, '{commonappdata}');
  AjouterDossierConnu(Liste, '{commondocs}');
  AjouterDossierConnu(Liste, '{commondesktop}');
  AjouterDossierConnu(Liste, '{commonpf32}');
  if IsWin64 then
    AjouterDossierConnu(Liste, '{commonpf64}');
  AjouterDossierConnu(Liste, '{win}');
  AjouterDossierConnu(Liste, '{sys}');
  // Documents redirigé pour les essais.
  AjouterDossierConnu(Liste, '{#DossierDocuments}');
end;

// Vrai si Chemin ne peut pas être comparé de façon sûre aux dossiers connus :
// préfixe \\?\ ou \\.\, élément « . » ou « .. », nom court 8.3 (« ~ »), « / ».
// Ces chemins sont refusés plutôt que normalisés (ExpandFileName ne traduit
// pas les noms courts).
function EstCheminSuspect(const Chemin: String): Boolean;
var
  C: String;
begin
  C := AddBackslash(Trim(Chemin));
  Result := (Copy(C, 1, 4) = '\\?\') or (Copy(C, 1, 4) = '\\.\') or
    (Pos('\..\', C) > 0) or (Pos('\.\', C) > 0) or (Pos('~', C) > 0) or
    (Pos('/', C) > 0);
end;

// Vrai si Dossier est suspect, une racine, un dossier connu, ou en contient
// un.
function EstDossierProtege(const Dossier: String): Boolean;
var
  Connus: TArrayOfString;
  I: Integer;
begin
  Result := EstCheminSuspect(Dossier) or EstRacine(Dossier);
  if Result then
    Exit;
  RemplirDossiersConnus(Connus);
  for I := 0 to GetArrayLength(Connus) - 1 do
    if EstDansDossier(Connus[I], Dossier) then
    begin
      Result := True;
      Exit;
    end;
end;

// Vrai si Chemin est un lien (jonction, lien symbolique).
function EstPointDAnalyse(const Chemin: String): Boolean;
var
  Trouve: TFindRec;
begin
  Result := False;
  if FindFirst(RemoveBackslashUnlessRoot(Chemin), Trouve) then
  try
    Result := (Trouve.Attributes and AttributPointAnalyse) <> 0;
  finally
    FindClose(Trouve);
  end;
end;

function FinitPar(const Texte, Fin: String): Boolean;
begin
  Result := (Length(Texte) >= Length(Fin)) and
    (Copy(Texte, Length(Texte) - Length(Fin) + 1, Length(Fin)) = Fin);
end;

function EstChiffre(const C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

// Fichier créé par l'application dans un dossier de titre :
// ch<numero>[.<langue>][.<n>|_<n>].zip (nomFichierChapitre et
// nomFichierNumerote de stockage_telechargements.dart ; formaterNumero donne
// des chiffres, un « - » en tête possible et un « . ») : « ch » suivi d'un
// chiffre, ou de « - » et d'un chiffre ; ou couverture.<ext> (1 à 5 lettres
// minuscules ou chiffres). Éventuellement suivis de .part (écriture en
// cours) ou .deplacement (déplacement interrompu). « chateau.zip » n'en est
// pas un.
function EstFichierChapitre(const Nom: String): Boolean;
var
  N, Extension: String;
  I: Integer;
begin
  Result := False;
  N := Nom;
  if FinitPar(N, '.part') then
    N := Copy(N, 1, Length(N) - Length('.part'))
  else if FinitPar(N, '.deplacement') then
    N := Copy(N, 1, Length(N) - Length('.deplacement'));
  if (Copy(N, 1, 2) = 'ch') and FinitPar(N, '.zip') and (Length(N) > 6) then
  begin
    Result := EstChiffre(N[3]) or ((N[3] = '-') and (Length(N) > 7) and
      EstChiffre(N[4]));
    Exit;
  end;
  if Copy(N, 1, 11) <> 'couverture.' then
    Exit;
  Extension := Copy(N, 12, Length(N));
  if (Length(Extension) < 1) or (Length(Extension) > 5) then
    Exit;
  for I := 1 to Length(Extension) do
    if not (((Extension[I] >= 'a') and (Extension[I] <= 'z')) or
      ((Extension[I] >= '0') and (Extension[I] <= '9'))) then
      Exit;
  Result := True;
end;

// Livre importé par le client et copié par l'application (0.4.0,
// prefixeFichierImporte de constantes_donnees.dart) :
// ^import(\.([2-9]|[1-9][0-9]+))?\.(cbz|pdf|epub)$, éventuellement suivi de
// .part ou .deplacement. « importer.pdf », « mon.import.pdf », « import.1.pdf »
// et « import.02.pdf » n'en sont pas.
function EstFichierImporte(const Nom: String): Boolean;
var
  N, Milieu: String;
  I: Integer;
begin
  Result := False;
  N := Nom;
  if FinitPar(N, '.part') then
    N := Copy(N, 1, Length(N) - Length('.part'))
  else if FinitPar(N, '.deplacement') then
    N := Copy(N, 1, Length(N) - Length('.deplacement'));
  if FinitPar(N, '.cbz') or FinitPar(N, '.pdf') then
    N := Copy(N, 1, Length(N) - 4)
  else if FinitPar(N, '.epub') then
    N := Copy(N, 1, Length(N) - 5)
  else
    Exit;
  if N = 'import' then
  begin
    Result := True;
    Exit;
  end;
  if Copy(N, 1, 7) <> 'import.' then
    Exit;
  Milieu := Copy(N, 8, Length(N));
  if (Milieu = '') or (Milieu[1] = '0') or (Milieu = '1') then
    Exit;
  for I := 1 to Length(Milieu) do
    if not EstChiffre(Milieu[I]) then
      Exit;
  Result := True;
end;

// Vrai si un dossier de titre de Dossier (<Dossier>\<type>\<titre>\)
// contient un livre importé (liens non suivis).
function ContientLivresImportes(const Dossier: String): Boolean;
var
  Noms: TArrayOfString;
  I: Integer;
  DossierType: String;
  TrouveTitre, TrouveFichier: TFindRec;
begin
  Result := False;
  RemplirDossiersChapitres(Noms);
  for I := 0 to GetArrayLength(Noms) - 1 do
  begin
    DossierType := AddBackslash(Dossier) + Noms[I];
    if DirExists(DossierType) and not EstPointDAnalyse(DossierType) then
      if FindFirst(AddBackslash(DossierType) + '*', TrouveTitre) then
      try
        repeat
          if (TrouveTitre.Name <> '.') and (TrouveTitre.Name <> '..') and
            ((TrouveTitre.Attributes and AttributDossier) <> 0) and
            ((TrouveTitre.Attributes and AttributPointAnalyse) = 0) then
            if FindFirst(AddBackslash(DossierType) + TrouveTitre.Name + '\import*',
              TrouveFichier) then
            try
              repeat
                if ((TrouveFichier.Attributes and
                  (AttributDossier or AttributPointAnalyse)) = 0) and
                  EstFichierImporte(TrouveFichier.Name) then
                  Result := True;
              until Result or not FindNext(TrouveFichier);
            finally
              FindClose(TrouveFichier);
            end;
        until Result or not FindNext(TrouveTitre);
      finally
        FindClose(TrouveTitre);
      end;
    if Result then
      Exit;
  end;
end;

// Vide un dossier de type : dans chaque dossier de titre, seulement les
// fichiers de l'application (et les livres importés si AvecImportes, « Tout
// supprimer » ; ImportesGardes compte ceux gardés sinon) ; puis les dossiers
// devenus vides. Tout le reste (fichiers du client, sous-dossiers, liens) est
// gardé et compté dans Restes.
procedure ViderDossierType(const DossierType: String; const AvecImportes: Boolean;
  var Supprimes, Restes, ImportesGardes: Integer);
var
  TrouveTitre, TrouveFichier: TFindRec;
  Titre, Fichier: String;
begin
  if not DirExists(DossierType) then
    Exit;
  if EstPointDAnalyse(DossierType) then
  begin
    Log('Gardé (lien) : ' + DossierType);
    Restes := Restes + 1;
    Exit;
  end;
  if FindFirst(AddBackslash(DossierType) + '*', TrouveTitre) then
  try
    repeat
      if (TrouveTitre.Name <> '.') and (TrouveTitre.Name <> '..') then
      begin
        Titre := AddBackslash(DossierType) + TrouveTitre.Name;
        if ((TrouveTitre.Attributes and AttributDossier) = 0) or
          ((TrouveTitre.Attributes and AttributPointAnalyse) <> 0) then
        begin
          Log('Gardé (pas un dossier de titre) : ' + Titre);
          Restes := Restes + 1;
        end
        else
        begin
          if FindFirst(AddBackslash(Titre) + '*', TrouveFichier) then
          try
            repeat
              if (TrouveFichier.Name <> '.') and (TrouveFichier.Name <> '..') then
              begin
                Fichier := AddBackslash(Titre) + TrouveFichier.Name;
                if ((TrouveFichier.Attributes and
                  (AttributDossier or AttributPointAnalyse)) = 0) and
                  (EstFichierChapitre(TrouveFichier.Name) or
                  (AvecImportes and EstFichierImporte(TrouveFichier.Name))) then
                begin
                  if DeleteFile(Fichier) then
                    Supprimes := Supprimes + 1
                  else
                  begin
                    Log('Suppression impossible : ' + Fichier);
                    Restes := Restes + 1;
                  end;
                end
                else
                begin
                  if ((TrouveFichier.Attributes and
                    (AttributDossier or AttributPointAnalyse)) = 0) and
                    EstFichierImporte(TrouveFichier.Name) then
                  begin
                    Log('Gardé (livre importé) : ' + Fichier);
                    ImportesGardes := ImportesGardes + 1;
                  end
                  else
                    Log('Gardé (pas un fichier de l''application) : ' + Fichier);
                  Restes := Restes + 1;
                end;
              end;
            until not FindNext(TrouveFichier);
          finally
            FindClose(TrouveFichier);
          end;
          RemoveDir(Titre);
        end;
      end;
    until not FindNext(TrouveTitre);
  finally
    FindClose(TrouveTitre);
  end;
  RemoveDir(DossierType);
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

// Contenu de l'application présent dans Dossier (« manga, roman,
// .bibliotheque_perso ») ; journaux, rapports et exports seulement dans le
// dossier par défaut. '' si rien.
function ContenuApplication(const Dossier: String): String;
var
  Noms: TArrayOfString;
  Donnees: String;
begin
  RemplirDossiersChapitres(Noms);
  Result := SousDossiersPresents(Dossier, Noms);
  if EstDossierParDefaut(Dossier) then
  begin
    RemplirDossiersDonneesApplication(Noms);
    Donnees := SousDossiersPresents(Dossier, Noms);
    if (Result <> '') and (Donnees <> '') then
      Result := Result + ', ';
    Result := Result + Donnees;
  end;
  if ContientLivresImportes(Dossier) then
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + 'livres importés';
  end;
  if FileExists(AddBackslash(Dossier) + NomFichierRepere) then
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + NomFichierRepere;
  end;
end;

// Raison de ne rien toucher dans Dossier, '' s'il peut être traité.
// DossierApplication : dossier d'installation ('' si inconnu).
function MotifRefusChapitres(const Dossier, DossierApplication: String): String;
begin
  Result := '';
  if not EstCheminComplet(Dossier) then
    Result := 'chemin incomplet'
  else if EstCheminSuspect(Dossier) then
    Result := 'chemin non pris en charge (\\?\, « . », « .. », « ~ » ou « / »)'
  else if EstRacine(Dossier) then
    Result := 'racine d''un disque ou d''un partage'
  else if EstDossierProtege(Dossier) then
    Result := 'dossier du système ou de l''utilisateur'
  else if (DossierApplication <> '') and EstDansDossier(Dossier, DossierApplication) then
    Result := 'dans le dossier d''installation'
  else if not DirExists(Dossier) then
    Result := 'introuvable ou injoignable'
  else if EstPointDAnalyse(Dossier) then
    Result := 'lien (jonction ou lien symbolique)'
  else if not EstDossierParDefaut(Dossier) and
    not FileExists(AddBackslash(Dossier) + NomFichierRepere) then
    Result := 'pas de repère ' + NomFichierRepere;
end;

// Supprime le contenu de l'application dans Dossier (déjà accepté par
// MotifRefusChapitres) : fichiers des dossiers de type, livres importés,
// journaux, rapports et exports si AvecDonnees (« Tout supprimer » ; données
// dans le dossier par défaut seulement), fichiers d'essai d'écriture, repère
// (gardé si des livres importés restent, pour qu'un « Tout supprimer »
// ultérieur puisse encore les retirer), puis le dossier s'il est vide
// (jamais s'il est un lien). Supprimes : fichiers et dossiers supprimés ;
// Restes : éléments gardés.
procedure SupprimerChapitresDossier(const Dossier: String; const AvecDonnees: Boolean;
  var Supprimes, Restes: Integer);
var
  Noms: TArrayOfString;
  I, ImportesGardes: Integer;
  Chemin: String;
  Trouve: TFindRec;
begin
  ImportesGardes := 0;
  RemplirDossiersChapitres(Noms);
  for I := 0 to GetArrayLength(Noms) - 1 do
    ViderDossierType(AddBackslash(Dossier) + Noms[I], AvecDonnees, Supprimes,
      Restes, ImportesGardes);
  if AvecDonnees and EstDossierParDefaut(Dossier) then
  begin
    RemplirDossiersDonneesApplication(Noms);
    for I := 0 to GetArrayLength(Noms) - 1 do
    begin
      Chemin := AddBackslash(Dossier) + Noms[I];
      if DirExists(Chemin) then
      begin
        if EstPointDAnalyse(Chemin) then
        begin
          Log('Gardé (lien) : ' + Chemin);
          Restes := Restes + 1;
        end
        else
        begin
          // DelTree d'Inno ne suit pas les jonctions qu'il rencontre dans
          // le dossier : il les retire sans toucher à leur cible (vérifié
          // par essai le 2026-11-25 : jonction vers un fichier externe
          // placée dans journaux, fichier externe intact).
          DelTree(Chemin, True, True, True);
          if DirExists(Chemin) then
          begin
            Log('Suppression incomplète : ' + Chemin);
            Restes := Restes + 1;
          end
          else
            Supprimes := Supprimes + 1;
        end;
      end;
    end;
  end;
  // Fichiers d'essai d'écriture laissés par un arrêt brutal.
  if FindFirst(AddBackslash(Dossier) + PrefixeEssaiEcriture + '*', Trouve) then
  try
    repeat
      if (Trouve.Attributes and (AttributDossier or AttributPointAnalyse)) = 0 then
        DeleteFile(AddBackslash(Dossier) + Trouve.Name);
    until not FindNext(Trouve);
  finally
    FindClose(Trouve);
  end;
  if ImportesGardes > 0 then
    Log('Repère gardé (' + IntToStr(ImportesGardes) + ' livre(s) importé(s)) : ' +
      Dossier)
  else if FileExists(AddBackslash(Dossier) + NomFichierRepere) then
    if DeleteFile(AddBackslash(Dossier) + NomFichierRepere) then
      Supprimes := Supprimes + 1;
  if not EstPointDAnalyse(Dossier) then
    RemoveDir(Dossier);
end;
