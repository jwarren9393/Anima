#!/usr/bin/env bash
set -e

# ==============================================================================
# Anima — One-Command Deploy
# ==============================================================================
# Runs checks, pushes source, builds the Android APK + installs it on the phone,
# builds + installs the Linux desktop app, packages the release zip, and updates
# the GitHub Release.
#
# Usage:
#   ./deploy.sh "optional changelog message"
#   ./deploy.sh --skip-checks "message"    # skip flutter analyze + flutter test
# ==============================================================================

# ==============================================================================
# AUTOMATIC VALUE EXTRACTION
# ==============================================================================

if [ ! -f "pubspec.yaml" ]; then
  echo "❌ Error: pubspec.yaml not found in current directory."
  exit 1
fi

FULL_VERSION=$(grep "^version:" pubspec.yaml | head -n1 | awk '{print $2}' | tr -d '\r')
VERSION=$(echo "$FULL_VERSION" | cut -d'+' -f1 | tr -d '\r')
BUILD_NUM=$(echo "$FULL_VERSION" | cut -d'+' -f2 | tr -d '\r')

if [ -z "$BUILD_NUM" ]; then
  echo "❌ Error: Could not parse build number from pubspec.yaml"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
DEVICE_ID=$(adb devices | grep -w "device" | awk '{print $1}' | head -n1 | tr -d '\r')
DESKTOP_DIR="$HOME/.local/share/anima"
CHANGELOG=""
SKIP_CHECKS=0
for _arg in "$@"; do
  case "$_arg" in
    --skip-checks) SKIP_CHECKS=1 ;;
    *) [ -z "$CHANGELOG" ] && CHANGELOG="$_arg" ;;
  esac
done
CHANGELOG="${CHANGELOG:-Build ${BUILD_NUM} release update and improvements}"

echo "=================================================="
echo "🚀 Deploying Anima ${VERSION} (Build ${BUILD_NUM})"
echo "📱 Connected Device: ${DEVICE_ID:-None (Skipping phone install)}"
echo "💻 Desktop Target:   ${DESKTOP_DIR}"
echo "📝 Notes:            ${CHANGELOG}"
echo "=================================================="

# ==============================================================================
# 1. SANITY CHECKS — type-check + tests before anything ships
# ==============================================================================
if [ "$SKIP_CHECKS" = "1" ]; then
  echo -e "\n🔍 [1/6] Checks skipped (--skip-checks)."
else
  echo -e "\n🔍 [1/6] Running flutter analyze + flutter test..."
  flutter analyze || { echo "❌ flutter analyze failed — fix the issues, or re-run with --skip-checks."; exit 1; }
  flutter test    || { echo "❌ Tests failed — fix them, or re-run with --skip-checks."; exit 1; }
  echo "   ✅ Checks passed."
fi

# ==============================================================================
# 2. GIT COMMIT & PUSH
# ==============================================================================
echo -e "\n📦 [2/6] Syncing source code to GitHub..."
git add .
if git diff --staged --quiet; then
  echo "No uncommitted code changes."
else
  git commit -m "Build ${BUILD_NUM}: ${CHANGELOG}"
fi
git push origin main

# ==============================================================================
# 2. BUILD ANDROID APK & INSTALL TO PHONE
# ==============================================================================
echo -e "\n📱 [3/6] Compiling Android Release APK..."
flutter build apk --release --build-name="$VERSION" --build-number="$BUILD_NUM"
cp build/app/outputs/flutter-apk/app-release.apk "Anima-${VERSION}.apk"

if [ -n "$DEVICE_ID" ]; then
  echo "   Installing in-place onto device ($DEVICE_ID)..."
  if INSTALL_OUT=$(adb -s "$DEVICE_ID" install -r "Anima-${VERSION}.apk" 2>&1); then
    echo "$INSTALL_OUT"
    echo "   ✅ Phone updated successfully!"
  else
    echo "$INSTALL_OUT"
    if echo "$INSTALL_OUT" | grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE'; then
      echo "   ⚠️ The app on the phone was signed with a different key."
      echo "      The Anima library lives in Documents/Anima, so this one-time fix is safe:"
      echo "        adb -s $DEVICE_ID uninstall com.anima.anima"
      echo "      then re-run ./deploy.sh — every later update installs in place."
    fi
    echo "   ⚠️ Phone install failed — continuing with the rest of the deploy."
  fi
else
  echo "   ⚠️ No ADB device found. Skipping physical phone install."
fi

# ==============================================================================
# 3. BUILD LINUX DESKTOP & UPDATE IN-PLACE
# ==============================================================================
echo -e "\n💻 [4/6] Compiling Linux Desktop Release..."
flutter build linux --release --build-name="$VERSION" --build-number="$BUILD_NUM"

echo "Updating desktop application in-place..."
mkdir -p "$DESKTOP_DIR"
rsync -av --delete build/linux/x64/release/bundle/ "$DESKTOP_DIR/"
echo "✅ Desktop app updated in-place!"

# ==============================================================================
# 4. PACKAGE DESKTOP ZIP FOR GITHUB RELEASE
# ==============================================================================
echo -e "\n🗜️  [5/6] Packaging Linux Release Zip..."
(cd build/linux/x64/release/bundle && zip -rq "${PROJECT_ROOT}/Anima-${VERSION}-linux-x64.zip" .)

# ==============================================================================
# 5. PUBLISH / UPDATE GITHUB RELEASE (IN-PLACE ON v1.0.0)
# ==============================================================================
echo -e "\n🌐 [6/6] Updating GitHub Release (v${VERSION})..."
TAG="v${VERSION}"
RELEASE_TITLE="Anima ${VERSION} (build ${BUILD_NUM})"
RELEASE_BODY="Install the new APK over the existing app (do not uninstall first).

### What's new in build ${BUILD_NUM}
- ${CHANGELOG}"

if command -v gh &> /dev/null; then
  # If release exists, update title/notes and upload fresh assets with --clobber
  gh release edit "$TAG" --title "$RELEASE_TITLE" --notes "$RELEASE_BODY" || \
  gh release create "$TAG" --title "$RELEASE_TITLE" --notes "$RELEASE_BODY"

  gh release upload "$TAG" "Anima-${VERSION}.apk" "Anima-${VERSION}-linux-x64.zip" --clobber
  echo "✅ GitHub Release updated: https://github.com/jwarren9393/Anima/releases/tag/${TAG}"
else
  echo "⚠️ GitHub CLI (gh) not found. Upload binaries manually if needed."
fi

echo -e "\n🎉 ALL DONE! App built, phone updated, desktop updated, and GitHub release published!"