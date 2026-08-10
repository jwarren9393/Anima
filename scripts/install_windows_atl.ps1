# Installs "C++ ATL" for Visual Studio Build Tools 2022 (required for Windows desktop builds).
# Right-click -> Run with PowerShell AS ADMINISTRATOR, or from an elevated terminal:
#   powershell -ExecutionPolicy Bypass -File .\scripts\install_windows_atl.ps1

$ErrorActionPreference = 'Stop'
$installPath = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools'
$setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"

if (-not (Test-Path $setup)) {
    Write-Error "Visual Studio Installer not found at $setup"
}

$existing = Get-ChildItem $installPath -Recurse -Filter 'atlstr.h' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    Write-Host "ATL already installed: $($existing.FullName)"
    exit 0
}

Write-Host 'Installing C++ ATL for Build Tools 2022 (may download ~100 MB)...'
& $setup modify `
    --installPath $installPath `
    --add Microsoft.VisualStudio.Component.VC.ATLMFC `
    --passive `
    --norestart

if ($LASTEXITCODE -ne 0) {
    Write-Error "Installer exited with code $LASTEXITCODE. Try Visual Studio Installer -> Modify -> Individual components -> C++ ATL for latest v143 build tools."
}

$installed = Get-ChildItem $installPath -Recurse -Filter 'atlstr.h' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $installed) {
    Write-Error 'Install finished but atlstr.h was not found. Open Visual Studio Installer and add ATL manually.'
}

Write-Host "Success: $($installed.FullName)"
Write-Host 'Now run:  cd D:\AI\Anima  then  flutter run -d windows'
