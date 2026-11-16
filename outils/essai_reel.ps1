# Essai réel de l'application avec la base du client (hors de l'environnement isolé de Claude).
# 1. Sauvegarde la base actuelle dans Documents\bibliotheque_perso\sauvegardes\<date>.
# 2. Lance la version Windows compilée (build\windows\x64\runner\Release).
$ErrorActionPreference = 'Stop'
$base = Join-Path $env:APPDATA 'io.github.zerma1\bibliotheque_perso'
$horodatage = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$sauvegarde = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "bibliotheque_perso\sauvegardes\$horodatage"
if (Test-Path $base) {
    New-Item -ItemType Directory -Force $sauvegarde | Out-Null
    Copy-Item (Join-Path $base '*') $sauvegarde -Recurse -Force
    Write-Host "Base sauvegardée dans : $sauvegarde"
    Get-ChildItem $sauvegarde | Format-Table Name, Length
} else {
    Write-Host "Aucune base existante dans $base (premier lancement)."
}
$exe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\bibliotheque_perso.exe'
Write-Host "Lancement de $exe"
Start-Process (Resolve-Path $exe)
