# Copia los avances del proyecto principal (H2Control) a este repositorio.
#
# El proyecto principal NO se modifica: solo se lee. Se copia el codigo de la
# app Flutter a /app y el firmware del ESP32 a /firmware, sin artefactos de
# compilacion ni archivos locales/sensibles (build, .dart_tool, local.properties,
# google-services.json, etc.).
#
# No borra nada en el repo: archivos que solo existen aqui (ej. lib/utils,
# lib/config, test/irrigation_validator_test.dart) se conservan.
#
# Uso (desde la raiz del repo):
#   powershell -ExecutionPolicy Bypass -File scripts\sync-from-h2control.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\sync-from-h2control.ps1 -Source "D:\otra\ruta\H2Control"

param(
    [string]$Source = "$env:USERPROFILE\OneDrive\Documentos\Proyectos\H2Control"
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

$appSrc = Join-Path $Source 'irrigation_app'
$fwSrc  = Join-Path $Source 'AquaControl_v3_secure'

if (-not (Test-Path (Join-Path $appSrc 'pubspec.yaml'))) {
    throw "No se encontro la app Flutter en '$appSrc'. Usa -Source para indicar la ruta de H2Control."
}

# Carpetas y archivos que nunca deben entrar al repo.
$excludeDirs = @('build', '.dart_tool', '.idea', '.gradle', 'ephemeral', 'Pods', '.symlinks', '.vscode')
$excludeFiles = @('*.iml', 'local.properties', 'google-services.json', 'GoogleService-Info.plist',
                  'firebase_options.dart', '.flutter-plugins', '.flutter-plugins-dependencies',
                  'widget_test.dart', '*.jks', '*.keystore', 'key.properties')

function Invoke-Copy($from, $to) {
    Write-Host "-> $from  =>  $to"
    robocopy $from $to /E /NFL /NDL /NJH /NP /XD $excludeDirs /XF $excludeFiles | Out-Host
    # robocopy: codigos 0-7 = exito, 8+ = error
    if ($LASTEXITCODE -ge 8) { throw "robocopy fallo con codigo $LASTEXITCODE" }
    $global:LASTEXITCODE = 0
}

Invoke-Copy $appSrc (Join-Path $repo 'app')
if (Test-Path $fwSrc) {
    Invoke-Copy $fwSrc (Join-Path $repo 'firmware\AquaControl_v3_secure')
}

Write-Host ""
Write-Host "Listo. Revisa los cambios con 'git status' y 'git diff' antes de hacer commit."
