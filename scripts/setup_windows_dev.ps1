# One-time Windows dev environment setup for Anima (Flutter + Android + desktop).
# Run from an elevated PowerShell if VS Build Tools or Developer Mode fail:
#   powershell -ExecutionPolicy Bypass -File .\scripts\setup_windows_dev.ps1
#
# Safe to re-run — skips components that are already installed.

param(
    [switch]$SkipVsBuildTools,
    [switch]$SkipFlutterClone
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $PSScriptRoot

# --- Paths (match AGENTS.md) ---
$FlutterRoot = 'C:\src\flutter'
$AndroidSdk  = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$JavaHome    = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot'

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Add-UserPathEntry([string]$entry) {
    if (-not $entry -or -not (Test-Path $entry)) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -split ';' | Where-Object { $_ -eq $entry }) { return }
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$entry", 'User')
    $env:Path = "$env:Path;$entry"
}

function Ensure-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error 'winget is required. Install App Installer from the Microsoft Store, then re-run.'
    }
}

function Install-WingetPackage([string]$id, [string]$label, [string[]]$ExtraArgs = @()) {
    $installed = winget list --id $id --accept-source-agreements 2>$null | Select-String $id
    if ($installed) {
        Write-Host "  Already installed: $label"
        return
    }
    Write-Host "  Installing $label ..."
    $args = @('install', '--id', $id, '-e', '--accept-package-agreements', '--accept-source-agreements') + $ExtraArgs
    & winget @args
    if ($LASTEXITCODE -gt 1) {
        Write-Warning "winget install $id exited with $LASTEXITCODE (may already be installed)."
    }
}

Write-Step 'Git safe.directory for Anima (post laptop reset / ownership change)'
git config --global --add safe.directory 'D:/AI/Anima' 2>$null
git config --global --add safe.directory 'D:\AI\Anima' 2>$null

Write-Step 'Package manager checks'
Ensure-Winget

Write-Step 'Core tools via winget'
Install-WingetPackage 'EclipseAdoptium.Temurin.17.JDK' 'Eclipse Temurin JDK 17'
Install-WingetPackage 'GitHub.cli' 'GitHub CLI'
Install-WingetPackage 'Google.PlatformTools' 'Android Platform Tools (adb)'

if (-not $SkipVsBuildTools) {
    $vsSetup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
    if (-not (Test-Path $vsSetup)) {
        Write-Host '  Installing Visual Studio Build Tools 2022 (C++ + ATL) — this can take 15–30 min ...'
        Install-WingetPackage 'Microsoft.VisualStudio.2022.BuildTools' 'VS Build Tools 2022' @(
            '--override',
            '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.ATLMFC'
        )
    } else {
        Write-Host '  VS Installer present — ensuring ATL component ...'
        & (Join-Path $PSScriptRoot 'install_windows_atl.ps1')
    }
}

Write-Step 'Flutter SDK at C:\src\flutter'
if (-not $SkipFlutterClone) {
    New-Item -ItemType Directory -Force -Path (Split-Path $FlutterRoot) | Out-Null
    if (-not (Test-Path (Join-Path $FlutterRoot 'bin\flutter.bat'))) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Error 'git is required to clone Flutter.'
        }
        Write-Host '  Cloning Flutter stable (may take a few minutes) ...'
        git clone https://github.com/flutter/flutter.git -b stable --depth 1 $FlutterRoot
    } else {
        Write-Host '  Flutter already present.'
    }
}

Write-Step 'Android SDK command-line tools'
New-Item -ItemType Directory -Force -Path $AndroidSdk | Out-Null
$cmdlineLatest = Join-Path $AndroidSdk 'cmdline-tools\latest'
if (-not (Test-Path (Join-Path $cmdlineLatest 'bin\sdkmanager.bat'))) {
    $zipUrl  = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
    $zipPath = Join-Path $env:TEMP 'commandlinetools-win.zip'
    Write-Host '  Downloading Android cmdline-tools ...'
    curl.exe -L -o $zipPath $zipUrl
    if (-not (Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 1MB) {
        Write-Error "Failed to download cmdline-tools from $zipUrl"
    }
    $extractRoot = Join-Path $env:TEMP 'android-cmdline-tools'
    if (Test-Path $extractRoot) { Remove-Item $extractRoot -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
    New-Item -ItemType Directory -Force -Path (Split-Path $cmdlineLatest) | Out-Null
    Move-Item -Path (Join-Path $extractRoot 'cmdline-tools') -Destination $cmdlineLatest -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
} else {
    Write-Host '  cmdline-tools already present.'
}

Write-Step 'Environment variables (User scope)'
if (-not (Test-Path $JavaHome)) {
    $found = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Filter 'jdk-17*' -Directory -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { $JavaHome = $found.FullName }
}
[Environment]::SetEnvironmentVariable('JAVA_HOME', $JavaHome, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $AndroidSdk, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $AndroidSdk, 'User')
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk

Add-UserPathEntry (Join-Path $FlutterRoot 'bin')
Add-UserPathEntry (Join-Path $JavaHome 'bin')
Add-UserPathEntry (Join-Path $AndroidSdk 'platform-tools')
Add-UserPathEntry (Join-Path $cmdlineLatest 'bin')
Add-UserPathEntry 'C:\Program Files\GitHub CLI'
Add-UserPathEntry 'C:\Program Files\Git\cmd'

Write-Step 'Developer Mode (required for Flutter Windows symlinks)'
try {
    $devKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    if (-not (Test-Path $devKey)) { New-Item -Path $devKey -Force | Out-Null }
    Set-ItemProperty -Path $devKey -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord -Force
    Write-Host '  Developer Mode registry flag set.'
} catch {
    Write-Warning "Could not set Developer Mode (run this script as Administrator): $_"
    Write-Host '  Or enable manually: Settings -> Privacy & security -> For developers -> Developer Mode ON'
}

Write-Step 'Android SDK licenses + packages (platform 36, build-tools 36.0.0)'
$sdkmanager = Join-Path $cmdlineLatest 'bin\sdkmanager.bat'
if (Test-Path $sdkmanager) {
    Write-Host '  Accepting Android licenses ...'
    1..120 | ForEach-Object { 'y' } | & $sdkmanager --sdk_root=$AndroidSdk --licenses 2>&1 | Out-Null
    Write-Host '  Installing SDK packages ...'
    & $sdkmanager --sdk_root=$AndroidSdk 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 2>&1
}

Write-Step 'Flutter config + project deps'
& (Join-Path $FlutterRoot 'bin\flutter.bat') config --enable-windows-desktop
& (Join-Path $FlutterRoot 'bin\flutter.bat') precache --windows
Set-Location $RootDir
& (Join-Path $FlutterRoot 'bin\flutter.bat') pub get

Write-Step 'flutter doctor'
& (Join-Path $FlutterRoot 'bin\flutter.bat') doctor -v

Write-Step 'Smoke tests'
& (Join-Path $FlutterRoot 'bin\flutter.bat') analyze
& (Join-Path $FlutterRoot 'bin\flutter.bat') test

Write-Host ""
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host "  Project: $RootDir"
Write-Host "  Run app:  cd $RootDir  then  flutter run -d windows"
Write-Host "  GitHub:   gh auth login   (once, for releases)"
Write-Host ""
Write-Host 'Restart Cursor / open a new terminal so PATH updates apply everywhere.' -ForegroundColor Yellow
