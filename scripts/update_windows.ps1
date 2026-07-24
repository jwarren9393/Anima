# Build and optionally package Anima for Windows.
# Usage:
#   .\scripts\update_windows.ps1
#   .\scripts\update_windows.ps1 -Zip
#   .\scripts\update_windows.ps1 -Zip -Release   # also upload to GitHub Releases (needs gh auth)

param(
    [switch]$Zip,
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter was not found on PATH. Install Flutter and reopen the terminal."
}

$version = (Select-String -Path "$RootDir\pubspec.yaml" -Pattern '^version:\s*(\S+)' |
    ForEach-Object { $_.Matches[0].Groups[1].Value })
if (-not $version) { $version = "1.0.0+7" }
$versionName = $version.Split('+')[0]

Write-Host "Building Anima $versionName for Windows..."
flutter pub get
flutter build windows --release

$releaseDir = Join-Path $RootDir "build\windows\x64\runner\Release"
$exePath = Join-Path $releaseDir "anima.exe"
if (-not (Test-Path $exePath)) {
    Write-Error "Build finished but anima.exe was not found at $exePath"
}

Write-Host ""
Write-Host "Built: $exePath"
Write-Host "Run the app from that folder (keep all DLLs and data beside anima.exe)."

if ($Zip -or $Release) {
    $zipName = "Anima-$versionName-windows-x64.zip"
    $zipPath = Join-Path $RootDir "build\$zipName"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -Force
    Write-Host "Packaged: $zipPath"
}

if ($Release) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) is required for -Release. Install it, then run: gh auth login"
    }
    $tag = "v$versionName"
    $zipName = "Anima-$versionName-windows-x64.zip"
    $zipPath = Join-Path $RootDir "build\$zipName"
    gh release view $tag 2>$null
    if ($LASTEXITCODE -ne 0) {
        gh release create $tag $zipPath --title "Anima $versionName" --notes "Windows x64 build. Unzip and run anima.exe."
    } else {
        gh release upload $tag $zipPath --clobber
    }
    Write-Host "Uploaded to GitHub release $tag"
}
