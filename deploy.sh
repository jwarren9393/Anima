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
  echo -e "\n🔍 [1/7] Checks skipped (--skip-checks)."
else
  echo -e "\n🔍 [1/7] Running flutter analyze + flutter test..."
  flutter analyze || { echo "❌ flutter analyze failed — fix the issues, or re-run with --skip-checks."; exit 1; }
  flutter test    || { echo "❌ Tests failed — fix them, or re-run with --skip-checks."; exit 1; }
  echo "   ✅ Checks passed."
fi

# ==============================================================================
# 2. GIT COMMIT & PUSH
# ==============================================================================
echo -e "\n📦 [2/7] Syncing source code to GitHub..."
git add .
if git diff --staged --quiet; then
  echo "No uncommitted code changes."
else
  git commit -m "Build ${BUILD_NUM}: ${CHANGELOG}"
fi
git push origin main

# ==============================================================================
# 3. BUILD ANDROID APK & INSTALL TO PHONE
# ==============================================================================
echo -e "\n📱 [3/7] Compiling Android Release APK..."
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
# 4. BUILD + INSTALL LINUX DESKTOP (bundle, icon and menu entry) — one code path
# ==============================================================================
echo -e "\n💻 [4/7] Building and installing the Linux desktop app..."
./scripts/update_linux.sh
echo "✅ Desktop app updated in-place!"

# ==============================================================================
# 5. PACKAGE DESKTOP ZIP FOR GITHUB RELEASE
# ==============================================================================
echo -e "\n🗜️  [5/7] Packaging Linux Release Zip..."
(cd build/linux/x64/release/bundle && zip -rq "${PROJECT_ROOT}/Anima-${VERSION}-linux-x64.zip" .)

# ==============================================================================
# 6. PUBLISH / UPDATE GITHUB RELEASE (IN-PLACE ON v1.0.0)
# ==============================================================================
echo -e "\n🌐 [6/7] Updating GitHub Release (v${VERSION})..."
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

# ==============================================================================
# 7. WINDOWS APP — built by GitHub Actions (Flutter cannot cross-compile it here)
# ==============================================================================
echo -e "\n🪟 [7/7] Asking GitHub Actions to build the Windows app..."
WINDOWS_CI="https://github.com/jwarren9393/Anima/actions/workflows/windows-release.yml"
if command -v gh &> /dev/null; then
  WINDOWS_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if gh workflow run windows-release.yml --ref main -f "tag=$TAG" > /dev/null 2>&1; then
    echo "   Dispatched — waiting for the Windows zip (usually 4–8 minutes)..."
    WINDOWS_READY=0
    GH_FAILS=0
    for _ in $(seq 1 45); do
      sleep 20

      # The release keeps the same file name, so compare upload timestamps to
      # tell a fresh zip from the one that was already there.
      if ASSET_AT=$(gh release view "$TAG" --json assets \
          -q '[.assets[] | select(.name | test("windows-x64\\.zip$"))][0].createdAt' 2>/dev/null); then
        GH_FAILS=0
      else
        ASSET_AT=""
        GH_FAILS=$((GH_FAILS + 1))
        if [ "$GH_FAILS" -ge 4 ]; then
          echo "   ⚠️ Cannot reach GitHub to check the Windows build (4 tries)."
          echo "      It keeps building in the background: $WINDOWS_CI"
          break
        fi
        continue
      fi

      if [ -n "$ASSET_AT" ] && [ "$ASSET_AT" != "null" ] && [ "$ASSET_AT" \> "$WINDOWS_STARTED_AT" ]; then
        WINDOWS_READY=1
        break
      fi

      # Report a failed build straight away instead of waiting out the full loop.
      if RUN_LINE=$(gh run list --workflow windows-release.yml --branch main --limit 1 \
          --json createdAt,status,conclusion \
          -q '.[0] | .createdAt + "|" + .status + "|" + (.conclusion // "")' 2>/dev/null); then
        RUN_CREATED="${RUN_LINE%%|*}"
        RUN_REST="${RUN_LINE#*|}"
        RUN_STATUS="${RUN_REST%%|*}"
        RUN_CONCLUSION="${RUN_REST#*|}"
        if [ -n "$RUN_CREATED" ] && [ "$RUN_CREATED" \> "$WINDOWS_STARTED_AT" ] &&
            [ "$RUN_STATUS" = "completed" ] && [ "$RUN_CONCLUSION" != "success" ]; then
          echo "   ⚠️ The Windows build finished as: $RUN_CONCLUSION"
          echo "      Log: $WINDOWS_CI"
          break
        fi
      fi
    done

    if [ "$WINDOWS_READY" = "1" ]; then
      echo "   ✅ Fresh Windows zip is on the release — grab it on the PC any time."
    else
      echo "   ⚠️ Windows zip not confirmed yet — watch it here:"
      echo "      $WINDOWS_CI"
    fi
  else
    echo "   ⚠️ Could not start the Windows workflow. Run it from the Actions tab:"
    echo "      $WINDOWS_CI"
  fi
else
  echo "   ⚠️ GitHub CLI (gh) not found — start the Windows build from the Actions tab:"
  echo "      $WINDOWS_CI"
fi

echo -e "\n🎉 ALL DONE! App built, phone updated, desktop updated, Windows building on GitHub!"