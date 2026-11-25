<#
.SYNOPSIS
  Construit l'installateur Windows de « Bibliothèque perso ».

.DESCRIPTION
  1. Lit la version dans pubspec.yaml (version: X.Y.Z+N).
  2. Compile l'application : flutter build windows --release.
  3. Lance Inno Setup (installateur\bibliotheque_perso.iss).
  Résultat : livraisons\<X.Y.Z>\bibliotheque_perso-<X.Y.Z>-installation.exe

  Prérequis : mode développeur de Windows (liens symboliques des plugins),
  nuget.exe (winget), Flutter dans D:\dev\flutter, Inno Setup 6.

.PARAMETER SansCompilation
  Réutilise build\windows\x64\runner\Release sans relancer flutter build.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File outils\construire_installateur.ps1
#>
[CmdletBinding()]
param(
    [switch]$SansCompilation
)

$ErrorActionPreference = 'Stop'

$racine = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $racine 'pubspec.yaml'
$script = Join-Path $racine 'installateur\bibliotheque_perso.iss'
$release = Join-Path $racine 'build\windows\x64\runner\Release'
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'

# nuget.exe (navigateur intégré) et flutter doivent être dans le PATH.
$env:Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links') + ';D:\dev\flutter\bin;' + $env:Path

# Version : « version: X.Y.Z+N » dans pubspec.yaml.
$ligne = Get-Content -Path $pubspec -Encoding UTF8 | Where-Object { $_ -match '^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$' } | Select-Object -First 1
if (-not $ligne) {
    throw "Version introuvable dans $pubspec (attendu : version: X.Y.Z+N)."
}
$version = $Matches[1]
$build = if ($Matches[2]) { $Matches[2] } else { '0' }
Write-Host "Version $version (build $build)"

if (-not (Test-Path $iscc)) {
    throw "Inno Setup 6 introuvable : $iscc"
}

if (-not $SansCompilation) {
    Write-Host 'Compilation : flutter build windows --release'
    Push-Location $racine
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build windows a échoué (code $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $release 'bibliotheque_perso.exe'))) {
    throw "Application compilée introuvable : $release"
}

$sortie = Join-Path $racine "livraisons\$version"
New-Item -ItemType Directory -Force -Path $sortie | Out-Null

Write-Host 'Installateur : Inno Setup'
& $iscc /Qp "/DVersion=$version" "/DBuild=$build" "/O$sortie" $script
if ($LASTEXITCODE -ne 0) {
    throw "ISCC a échoué (code $LASTEXITCODE)."
}

$installateur = Join-Path $sortie "bibliotheque_perso-$version-installation.exe"
Write-Host "Installateur prêt : $installateur"
