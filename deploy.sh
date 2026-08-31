#!/usr/bin/env bash
set -e

# ==============================================================================
# AUTOMATIC VALUE EXTRACTION (NO HARDCODING REQUIRED)
# ==============================================================================

# 1. Extract version and build number from pubspec.yaml
if [ ! -f "pubspec.yaml" ]; then
  echo "❌ Error: pubspec.yaml not found in current directory."
  exit 1
fi

FULL_VERSION=$(grep "^version:" pubspec.yaml | head -n1 | awk '{print $2}')
VERSION=$(echo "$FULL_VERSION" | cut -d'+' -f1)
BUILD_NUM=$(echo "$FULL_VERSION" | cut -d'+' -f2)

if [ -z "$BUILD_NUM" ]; then
  echo "❌ Error: Could not parse build number from pubspec.yaml (Expected format: 1.0.0+65)"
  exit 1
fi

# 2. Automatically find connected ADB device (phone)
DEVICE_ID=$(adb devices | grep -w "device" | awk '{print $1}' | head -n1)

# 3. Desktop install directory on Linux Mint
DESKTOP_DIR="$HOME/.local/share/anima"

# 4. Commit message & Release notes from terminal argument (or fallback default)
CHANGELOG="${1:-Build ${BUILD_NUM} release update and improvements}"

echo "=================================================="
echo "🚀 Deploying Anima ${VERSION} (Build ${BUILD_NUM})"
echo "📱 Connected Device: ${DEVICE_ID:-None (Skipping phone install)}"
echo "💻 Desktop Target:   ${DESKTOP_DIR}"
echo "📝 Notes:            ${CHANGELOG}"
echo "=================================================="

# ==============================================================================
# 1. GIT COMMIT & PUSH
# ==============================================================================
echo -e "\n📦 [1/5] Syncing source code to GitHub..."
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
echo -e "\n📱 [2/5] Compiling Android Release APK..."
flutter build apk --release --build-name="$VERSION" --build-number="$BUILD_NUM"
cp build/app/outputs/flutter-apk/app-release.apk "Anima-${VERSION}.apk"

if [ -n "$DEVICE_ID" ]; then
  echo "Installing in-place onto device ($DEVICE_ID)..."
  adb -s "$DEVICE_ID" install -r "Anima-${VERSION}.apk"
  echo "✅ Phone updated successfully!"
else
  echo "⚠️ No ADB device found. Skipping physical phone install."
fi

# ==============================================================================
# 3. BUILD LINUX DESKTOP & UPDATE IN-PLACE
# ==============================================================================
echo -e "\n💻 [3/5] Compiling Linux Desktop Release..."
flutter build linux --release --build-name="$VERSION" --build-number="$BUILD_NUM"

echo "Updating desktop application in-place..."
mkdir -p "$DESKTOP_DIR"
rsync -av --delete build/linux/x64/release/bundle/ "$DESKTOP_DIR/"
echo "✅ Desktop app updated in-place!"

# ==============================================================================
# 4. PACKAGE DESKTOP ZIP FOR GITHUB RELEASE
# ==============================================================================
echo -e "\n🗜️  [4/5] Packaging Linux Release Zip..."
(cd build/linux/x64/release/bundle && zip -rq "../../../../Anima-${VERSION}-linux-x64.zip" .)

# ==============================================================================
# 5. PUBLISH GITHUB RELEASE
# ==============================================================================
echo -e "\n🌐 [5/5] Publishing GitHub Release..."
TAG="v${VERSION}-b${BUILD_NUM}"
RELEASE_TITLE="Anima ${VERSION} (build ${BUILD_NUM})"
RELEASE_BODY="Install the new APK over the existing app (do not uninstall first).

### What's new in build ${BUILD_NUM}
- ${CHANGELOG}"

if command -v gh &> /dev/null; then
  gh release create "$TAG" "Anima-${VERSION}.apk" "Anima-${VERSION}-linux-x64.zip" \
    --title "$RELEASE_TITLE" \
    --notes "$RELEASE_BODY" || {
      echo "⚠️ Release create warning (release may already exist). Uploading assets..."
      gh release upload "$TAG" "Anima-${VERSION}.apk" "Anima-${VERSION}-linux-x64.zip" --clobber
    }
  echo "✅ GitHub Release published: https://github.com/jwarren9393/Anima/releases/tag/${TAG}"
else
  echo "⚠️ GitHub CLI (gh) not installed. Binaries saved locally. Install 'gh' or upload via Web UI."
fi

echo -e "\n🎉 ALL DONE! App built, phone updated, desktop updated, and GitHub release published!"