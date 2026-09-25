#!/usr/bin/env bash
#
# Anima — one-command Linux dev environment setup (Linux Mint / Ubuntu / Debian).
#
# Installs the bare minimum needed to build and run Anima on Linux:
#   - apt build deps (clang, cmake, ninja, GTK 3, libsecret, libjsoncpp, …)
#   - JDK 17 (Temurin; falls back to Ubuntu's OpenJDK 17)
#   - Flutter stable  ->  ~/development/flutter
#   - Android SDK     ->  ~/Android/Sdk  (cmdline-tools, platform-tools,
#                          platform 36, build-tools 36.0.0, licenses accepted)
#   - GitHub CLI (gh) + optional GitHub sign-in so git push/pull just works
#   - PATH / JAVA_HOME / ANDROID_HOME exports + Cursor's Dart SDK path
#   - a build-capable working copy of the project on a Linux (ext4) drive, at
#     ~/Documents/App-Builds/Anima, when this folder sits on an exFAT drive that
#     cannot store the symlinks Flutter needs (see scripts/dev_copy_linux.sh)
#
# Usage:
#   bash scripts/setup_linux_dev.sh              install everything
#   bash scripts/setup_linux_dev.sh --github     …then sign in to GitHub (device code)
#   bash scripts/setup_linux_dev.sh --help
#
# Safe to re-run: every step is skipped when it is already done.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_ROOT="$HOME/development"
FLUTTER_DIR="$DEV_ROOT/flutter"
SDK_ROOT="$HOME/Android/Sdk"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-16111833_latest.zip"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP"
ANDROID_PLATFORM="platforms;android-36"
ANDROID_BUILD_TOOLS="build-tools;36.0.0"
RUN_GITHUB=0
WORK_COPY="$HOME/Documents/App-Builds/Anima"

step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()    { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '    \033[1;33m!\033[0m %s\n' "$*"; }
fail()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

case "${1:-}" in
  "")        ;;
  --github)  RUN_GITHUB=1 ;;
  -h|--help)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
    exit 0 ;;
  *) fail "Unknown option: $1  (try --help)" ;;
esac

[[ "$(uname -s)" == "Linux" ]] || fail "This installer only runs on Linux."
[[ -f /etc/os-release ]] || fail "Cannot read /etc/os-release — is this a Debian-based distro?"
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID_LIKE:-} ${ID:-} " in
  *debian*) ;;
  *) fail "This script expects a Debian/Ubuntu-based distro (found: ${PRETTY_NAME:-unknown})." ;;
esac

step "Checking your password (needed to install system packages)"
sudo -v || fail "Administrator access is required to install system packages."
ok "Password accepted — it is cached for the rest of this script."

step "Repairing third-party apt repositories (Spotify / Cursor)"
# Installing Spotify or Cursor adds their apt source files, but a reinstall can leave
# their signing keys behind. A keyless source makes 'apt-get update' fail, which then
# breaks every apt command on the machine (including this script). Re-import the
# official keys, best effort.
if [[ -f /etc/apt/sources.list.d/spotify.list && ! -e /etc/apt/trusted.gpg.d/spotify.gpg ]]; then
  if curl -fsSL https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc |
       sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg 2>/dev/null; then
    ok "Re-imported Spotify's signing key."
  else
    warn "Could not fetch Spotify's key — its repo will keep warning until it is fixed."
  fi
fi
if [[ -f /etc/apt/sources.list.d/cursor.list && ! -e /etc/apt/trusted.gpg.d/cursor.asc ]]; then
  if curl -fsSL https://downloads.cursor.com/keys/anysphere.asc |
       sudo tee /etc/apt/trusted.gpg.d/cursor.asc >/dev/null; then
    ok "Re-imported Cursor's signing key."
  else
    warn "Could not fetch Cursor's key — its repo will keep warning until it is fixed."
  fi
fi

step "Installing system build packages"
APT_PACKAGES=(
  git curl wget unzip zip xz-utils rsync file
  build-essential clang cmake ninja-build pkg-config
  libgtk-3-dev liblzma-dev libsecret-1-dev libjsoncpp-dev
  android-sdk-platform-tools-common gh
)
# Never let one broken third-party repository abort the whole install.
sudo apt-get update -qq || warn "Some apt repositories failed to update (usually third-party ones) — carrying on."
sudo apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}" \
  || fail "apt could not install the build packages. Fix the repository named in the apt output above, then re-run this script."
ok "Build tools, GTK 3, libsecret, GitHub CLI and phone USB rules are in place."

step "Installing JDK 17"
JDK_HOME=""
for candidate in /usr/lib/jvm/temurin-17-jdk-amd64 /usr/lib/jvm/java-17-openjdk-amd64; do
  [[ -x "$candidate/bin/javac" ]] && JDK_HOME="$candidate" && break
done
if [[ -z "$JDK_HOME" ]]; then
  # Try Eclipse Temurin (same as the Windows dev PC), else Ubuntu's OpenJDK 17.
  if sudo install -d -m 0755 /etc/apt/keyrings >/dev/null 2>&1 &&
     curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public |
       sudo tee /etc/apt/keyrings/adoptium.asc >/dev/null 2>&1; then
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb ${UBUNTU_CODENAME:-noble} main" |
      sudo tee /etc/apt/sources.list.d/adoptium.list >/dev/null
    if sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends temurin-17-jdk; then
      JDK_HOME=/usr/lib/jvm/temurin-17-jdk-amd64
    else
      warn "Temurin repository unavailable — using Ubuntu's OpenJDK 17 instead."
    fi
  else
    warn "Could not reach the Temurin repository — using Ubuntu's OpenJDK 17 instead."
  fi
fi
if [[ -z "$JDK_HOME" ]]; then
  sudo apt-get install -y --no-install-recommends openjdk-17-jdk
  JDK_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi
[[ -x "$JDK_HOME/bin/javac" ]] || fail "JDK 17 was not installed correctly ($JDK_HOME)."
export JAVA_HOME="$JDK_HOME"
export PATH="$JDK_HOME/bin:$PATH"
ok "JDK 17 at $JDK_HOME"

step "Installing the Flutter SDK (stable)"
if [[ -x "$FLUTTER_DIR/bin/flutter" ]]; then
  ok "Flutter already present at $FLUTTER_DIR"
else
  mkdir -p "$DEV_ROOT"
  echo "    Downloading the Flutter stable channel (~1.5 GB) — this takes a while…"
  git clone --branch stable --single-branch https://github.com/flutter/flutter.git "$FLUTTER_DIR" \
    || fail "Could not download Flutter. Check your internet connection and re-run."
  ok "Flutter downloaded to $FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

step "Installing the Android SDK (command line tools, platform 36, build tools 36)"
export JAVA_HOME="$JDK_HOME"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"

if [[ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  mkdir -p "$SDK_ROOT/cmdline-tools" "$SDK_ROOT/.download"
  echo "    Downloading Android command line tools…"
  curl -fL "$CMDLINE_TOOLS_URL" -o "$SDK_ROOT/.download/$CMDLINE_TOOLS_ZIP" \
    || fail "Could not download the Android command line tools."
  rm -rf "$SDK_ROOT/cmdline-tools/latest" "$SDK_ROOT/.download/unzipped"
  unzip -q "$SDK_ROOT/.download/$CMDLINE_TOOLS_ZIP" -d "$SDK_ROOT/.download/unzipped"
  mv "$SDK_ROOT/.download/unzipped/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
  rm -rf "$SDK_ROOT/.download"
  ok "Command line tools installed."
else
  ok "Command line tools already present."
fi

SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
export PATH="$SDK_ROOT/cmdline-tools/latest/bin:$SDK_ROOT/platform-tools:$PATH"

echo "    Accepting Android SDK licences…"
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
echo "    Installing platform-tools, $ANDROID_PLATFORM and $ANDROID_BUILD_TOOLS…"
"$SDKMANAGER" --install "platform-tools" "$ANDROID_PLATFORM" "$ANDROID_BUILD_TOOLS" >/dev/null \
  || warn "Some Android packages could not be installed — re-run this script after checking your connection."
[[ -x "$SDK_ROOT/platform-tools/adb" ]] && ok "adb installed at $SDK_ROOT/platform-tools/adb"
ok "Android SDK ready at $SDK_ROOT"


step "Saving environment variables"
BASHRC="$HOME/.bashrc"
BLOCK_START="# >>> Anima dev environment >>>"
BLOCK_END="# <<< Anima dev environment <<<"
if grep -qF "$BLOCK_START" "$BASHRC" 2>/dev/null; then
  # Remove the previous block so paths stay correct when this script is re-run.
  python3 - "$BASHRC" "$BLOCK_START" "$BLOCK_END" <<'PY'
import sys
path, start, end = sys.argv[1], sys.argv[2], sys.argv[3]
keep, skipping = [], False
for line in open(path).read().splitlines():
    if line.strip() == start:
        skipping = True
        continue
    if line.strip() == end:
        skipping = False
        continue
    if not skipping:
        keep.append(line)
while keep and not keep[-1].strip():
    keep.pop()
open(path, 'w').write("\n".join(keep) + "\n")
PY
fi
{
  echo "$BLOCK_START"
  echo "export JAVA_HOME=\"$JDK_HOME\""
  echo "export ANDROID_HOME=\"$SDK_ROOT\""
  echo "export ANDROID_SDK_ROOT=\"$SDK_ROOT\""
  echo "export PATH=\"$FLUTTER_DIR/bin:\$JAVA_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$HOME/.local/bin:\$PATH\""
  echo "$BLOCK_END"
} >> "$BASHRC"
ok "Added PATH, JAVA_HOME and ANDROID_HOME to ~/.bashrc"

# Apps started from the application menu (Cursor, the Anima launcher) never read
# ~/.bashrc, so mirror the same values for the login session too.
ENV_DIR="$HOME/.config/environment.d"
mkdir -p "$ENV_DIR"
cat > "$ENV_DIR/50-anima-dev.conf" <<EOF
# Written by Anima's scripts/setup_linux_dev.sh — safe to delete.
JAVA_HOME=$JDK_HOME
ANDROID_HOME=$SDK_ROOT
ANDROID_SDK_ROOT=$SDK_ROOT
PATH=$FLUTTER_DIR/bin:$JDK_HOME/bin:$SDK_ROOT/cmdline-tools/latest/bin:$SDK_ROOT/platform-tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
EOF
ok "Desktop apps will see the new tools after you sign out and back in."

step "Pointing Cursor at the Flutter SDK"
python3 - "$HOME/.config/Cursor/User/settings.json" "$FLUTTER_DIR" <<'PY'
import json, pathlib, sys
path, flutter = pathlib.Path(sys.argv[1]), sys.argv[2]
data = {}
if path.exists() and path.read_text().strip():
    try:
        data = json.loads(path.read_text())
    except Exception:
        path.with_suffix('.json.bak').write_text(path.read_text())
        print("    (existing settings.json was unreadable — backed it up and started fresh)")
data['dart.flutterSdkPath'] = flutter
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=4) + "\n")
PY
ok "Cursor setting dart.flutterSdkPath = $FLUTTER_DIR"

step "Enabling the Flutter desktop and Android targets"
"$FLUTTER_DIR/bin/flutter" config --no-analytics --enable-linux-desktop --enable-android >/dev/null 2>&1 \
  || fail "Flutter could not start (its first run downloads the Dart SDK). Check your internet connection and re-run."
ok "Linux desktop and Android enabled."

step "GitHub sign-in (optional)"
if ! command -v gh >/dev/null 2>&1; then
  warn "GitHub CLI is missing — re-run this script to install it."
elif gh auth status >/dev/null 2>&1; then
  ok "Already signed in to GitHub as $(gh api user --jq .login 2>/dev/null || echo 'unknown')."
elif [[ "$RUN_GITHUB" -eq 1 ]]; then
  echo "    Follow the prompts: choose GitHub.com → HTTPS → 'Login with a web browser'."
  gh auth login --hostname github.com --git-protocol https --web
else
  warn "Not signed in to GitHub yet. Run this later:"
  echo "        gh auth login --hostname github.com --git-protocol https --web"
fi

if gh auth status >/dev/null 2>&1; then
  # Let git use your GitHub login for push/pull (no password prompts in Cursor).
  gh auth setup-git >/dev/null 2>&1 && ok "git is connected to GitHub through gh."
  GH_LOGIN="$(gh api user --jq .login 2>/dev/null || echo '')"
  GH_NAME="$(gh api user --jq '.name // .login' 2>/dev/null || echo "${GH_LOGIN:-}")"
  GH_EMAIL="$(gh api user --jq ".id|tostring" 2>/dev/null || echo '')"
  if [[ -n "$GH_LOGIN" ]]; then
    git config --global user.name "$GH_NAME"
    git config --global user.email "${GH_EMAIL}+${GH_LOGIN}@users.noreply.github.com"
    git config --global init.defaultBranch main
    git config --global --add safe.directory "$ROOT_DIR"
    ok "Git commits will be signed as $GH_NAME <${GH_EMAIL}+${GH_LOGIN}@users.noreply.github.com>"
  fi
fi


step "Cleaning generated files left over from the previous computer"
# These are all re-created automatically by Flutter. The old copies still point at
# the previous PC's SDK/pub-cache paths and would break the first build.
[[ -f "$ROOT_DIR/android/local.properties" ]] && rm -f "$ROOT_DIR/android/local.properties" \
  && ok "Removed android/local.properties (it pointed at the old SDK path)."
[[ -d "$ROOT_DIR/linux/flutter/ephemeral" ]] && rm -rf "$ROOT_DIR/linux/flutter/ephemeral" \
  && ok "Removed regenerated linux/flutter/ephemeral plugin links."
if [[ -d "$ROOT_DIR/.dart_tool" ]] && grep -q "/home/" "$ROOT_DIR/.dart_tool/package_config.json" 2>/dev/null \
   && ! grep -q "$HOME/.pub-cache" "$ROOT_DIR/.dart_tool/package_config.json" 2>/dev/null; then
  rm -rf "$ROOT_DIR/.dart_tool"
  ok "Removed .dart_tool (it still pointed at the old machine's package cache)."
fi

step "Checking where Flutter is able to build from"
# Flutter stores its plugin links as symlinks (packages/flutter_tools/lib/src/
# flutter_plugins.dart -> link.createSync, and on failure it rethrows). exFAT/FAT
# drives cannot store symlinks, so builds must run from a real Linux drive.
BUILD_DIR="$ROOT_DIR"
PROBE="$ROOT_DIR/.anima-symlink-probe"
if ln -s /tmp "$PROBE" 2>/dev/null; then
  rm -f "$PROBE"
  ok "This folder supports symlinks — builds work here."
else
  rm -f "$PROBE" 2>/dev/null || true
  warn "This folder is on an exFAT/FAT drive, which cannot store symlinks."
  warn "Flutter needs symlinks for plugin links, so 'flutter pub get' AND every"
  warn "build will fail here. This is a limitation of the drive, not your setup."
  if [[ -d "$WORK_COPY/.git" ]]; then
    BUILD_DIR="$WORK_COPY"
    ok "Using your working copy on the Linux drive instead: $BUILD_DIR"
  else
    echo "    Creating a working copy on the Linux drive ($WORK_COPY)…"
    if bash "$ROOT_DIR/scripts/dev_copy_linux.sh" && [[ -d "$WORK_COPY/.git" ]]; then
      BUILD_DIR="$WORK_COPY"
      ok "Working copy ready — builds will run from $BUILD_DIR."
    else
      warn "Could not create $WORK_COPY automatically (uncommitted changes or git missing)."
      warn "Run 'bash scripts/dev_copy_linux.sh', then re-run this script."
    fi
  fi
fi

step "Downloading the project's Dart packages"
cd "$BUILD_DIR"
"$FLUTTER_DIR/bin/flutter" pub get || warn "'flutter pub get' failed — see the notes above and re-run after fixing them."
ok "Package downloads finished in $BUILD_DIR"

step "Checking your installation (flutter doctor)"
"$FLUTTER_DIR/bin/flutter" doctor || warn "flutter doctor found issues — read the notes above. They are often harmless."

printf '\n\033[1;32m========================================\033[0m\n'
printf '\033[1;32m Anima dev environment is ready\033[0m\n'
printf '\033[1;32m========================================\033[0m\n'
echo
echo "Source folder  : $ROOT_DIR"
echo "Build folder   : $BUILD_DIR"
echo "Flutter        : $FLUTTER_DIR"
echo "JDK 17         : $JDK_HOME"
echo "Android SDK    : $SDK_ROOT"
echo
echo "Next steps:"
echo "  1. Close and reopen your terminal (and restart Cursor) so PATH updates apply."
if ! gh auth status >/dev/null 2>&1; then
  echo "  2. Connect GitHub (opens your browser once):"
  echo "       gh auth login --hostname github.com --git-protocol https --web"
  echo "     then re-run this script so git signing/push settings are applied."
else
  echo "  2. GitHub is connected — nothing else to do."
fi
echo "  3. Open this folder in Cursor (File > Open Folder):"
echo "       $BUILD_DIR"
echo "  4. Build / run the app:"
echo "       cd \"$BUILD_DIR\""
echo "       flutter run -d linux      # desktop"
echo "       flutter run               # Android phone over USB"
echo "  5. Run the test suite:  flutter test"
echo
echo "The Anima library folder (characters, chats, API key) is created on first"
echo "launch — pick ~/Documents/Anima, or restore your backup file from"
echo "Settings > Backup, restore & sync."

