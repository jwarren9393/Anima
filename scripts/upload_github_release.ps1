# Upload Android APK + Windows zip to an existing GitHub release.
# Removes stale .apk assets first so Releases never shows duplicate APKs.
#
# Usage (from repo root):
#   .\scripts\upload_github_release.ps1
#   .\scripts\upload_github_release.ps1 -Tag v1.0.0

param(
    [string]$Tag = "",
    [string]$Repo = "jwarren9393/Anima"
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is required. Install it, then run: gh auth login"
}

$version = (Select-String -Path "$RootDir\pubspec.yaml" -Pattern '^version:\s*(\S+)' |
    ForEach-Object { $_.Matches[0].Groups[1].Value })
if (-not $version) { $version = "1.0.0+1" }
$versionName = $version.Split('+')[0]
if (-not $Tag) { $Tag = "v$versionName" }

$apkBuilt = Join-Path $RootDir "build\app\outputs\flutter-apk\app-release.apk"
$apkName = "Anima-$versionName.apk"
$apkUpload = Join-Path $RootDir "build\$apkName"
$zipName = "Anima-$versionName-windows-x64.zip"
$zipPath = Join-Path $RootDir "build\$zipName"

if (-not (Test-Path $apkBuilt)) {
    Write-Error "APK not found. Run: flutter build apk --release"
}
if (-not (Test-Path $zipPath)) {
    Write-Error "Windows zip not found at $zipPath. Run: .\scripts\update_windows.ps1 -Zip"
}

Copy-Item $apkBuilt $apkUpload -Force
Write-Host "Staged APK as $apkName"

gh release view $Tag --repo $Repo 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Release $Tag not found on $Repo. Create it first or pass -Tag."
}

$assetsJson = gh release view $Tag --repo $Repo --json assets | ConvertFrom-Json
foreach ($asset in $assetsJson.assets) {
    if ($asset.name -match '\.apk$') {
        Write-Host "Removing stale release asset: $($asset.name)"
        gh release delete-asset $Tag $asset.name --repo $Repo --yes
    }
}

gh release upload $Tag $apkUpload $zipPath --clobber --repo $Repo
Write-Host "Uploaded $apkName and $zipName to $Tag on $Repo"
