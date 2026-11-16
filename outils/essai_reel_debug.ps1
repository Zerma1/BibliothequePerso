# Relance la version Release depuis le dossier Debug (seul emplacement autorisé pour le contrôle d'écran).
Get-Process bibliotheque_perso -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
$racine = Join-Path $PSScriptRoot '..\build\windows\x64\runner'
$debug = Join-Path $racine 'Debug'
Remove-Item $debug -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $racine 'Release') $debug -Recurse
Start-Process (Join-Path $debug 'bibliotheque_perso.exe')
Write-Host 'Application relancee.'
