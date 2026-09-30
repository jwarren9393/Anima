#!/usr/bin/env bash
#
# Anima — Linux dev environment setup that needs NO administrator password.
#
# Use this when you cannot (or would rather not) type a sudo password. Everything
# is installed inside your home folder:
#   - Flutter stable        ->  ~/development/flutter
#   - Temurin JDK 17        ->  ~/development/jdk-17
#   - Android SDK           ->  ~/Android/Sdk  (cmdline-tools, platform-tools,
#                              platforms 36/35/34, build-tools 36.0.0, licences)
#   - PATH / JAVA_HOME / ANDROID_HOME exports for shells + desktop apps
#   - Cursor's Dart SDK path
#   - the git identity a fresh Linux install forgets
#   - the project's Dart packages (`flutter pub get`)
#
# The only things this cannot install without sudo are the Linux *desktop* build
# libraries (clang, cmake, ninja, pkg-config, GTK 3, libsecret, libjsoncpp), the
# GitHub CLI, and the phone udev rules. It prints the one apt command for those.
#
# Usage:
#   bash scripts/setup_linux_dev_noroot.sh
#   bash scripts/setup_linux_dev_noroot.sh -h
#
# Safe to re-run: every step is skipped when it is already done.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_ROOT="$HOME/development"
FLUTTER_DIR="$DEV_ROOT/flutter"
JDK_HOME="$DEV_ROOT/jdk-17"
SDK_ROOT="$HOME/Android/Sdk"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-16111833_latest.zip"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP"
JDK_URL="https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
ANDROID_PACKAGES=(platform-tools "platforms;android-36" "platforms;android-35"
                  "platforms;android-34" "build-tools;36.0.0")
APT_PACKAGES="clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev gh android-sdk-platform-tools-common"

step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()    { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '    \033[1;33m! %s\033[0m\n' "$*"; }
fail()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

case "${1:-}" in
  "")     ;;
  -h|--help)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
    exit 0 ;;
  *) fail "Unknown option: $1  (try --help)" ;;
esac

[[ "$(uname -s)" == "Linux" ]] || fail "This installer only runs on Linux."
command -v curl >/dev/null || fail "curl is required (sudo apt install curl)."
command -v unzip >/dev/null || fail "unzip is required (sudo apt install unzip)."

if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO_OK=1
else
  SUDO_OK=0
fi

step "System build libraries (Linux desktop + Android USB)"
# The apt packages Anima needs: the desktop build toolchain, gh for the release
# script, and the phone udev rules. None of them can be installed without an
# administrator password, so when sudo is unavailable we just report them.
if [[ "$SUDO_OK" == "1" ]]; then
  if dpkg -s clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev >/dev/null 2>&1; then
    ok "Already installed."
  else
    echo "    Installing: $APT_PACKAGES"
    # shellcheck disable=SC2086
    sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends $APT_PACKAGES \
      || warn "Some packages could not be installed — the Linux desktop build may not work."
  fi
  ok "Desktop build libraries ready."
else
  warn "No password-free sudo — skipping the apt packages."
  warn "Run this yourself once (needs your password):"
  echo
  echo "    sudo apt-get update && sudo apt-get install -y $APT_PACKAGES"
  echo
  warn "Android builds work without them; only 'flutter run -d linux' needs the desktop libs, and only deploy.sh needs gh."
fi

step "Installing JDK 17 (Temurin, inside your home folder)"
mkdir -p "$DEV_ROOT"
if [[ -x "$JDK_HOME/bin/javac" ]]; then
  ok "Already present at $JDK_HOME"
else
  echo "    Downloading Temurin JDK 17 (~185 MB)…"
  curl -fL --retry 3 -o "$DEV_ROOT/jdk-17.tar.gz" "$JDK_URL" \
    || fail "Could not download the JDK. Check your internet connection."
  rm -rf "$DEV_ROOT/jdk-17-extract"
  mkdir -p "$DEV_ROOT/jdk-17-extract"
  tar -xzf "$DEV_ROOT/jdk-17.tar.gz" -C "$DEV_ROOT/jdk-17-extract" --strip-components=1
  rm -rf "$JDK_HOME"
  mv "$DEV_ROOT/jdk-17-extract" "$JDK_HOME"
  rm -f "$DEV_ROOT/jdk-17.tar.gz"
  ok "JDK 17 installed at $JDK_HOME"
fi
export JAVA_HOME="$JDK_HOME"
export PATH="$JDK_HOME/bin:$PATH"
ok "$("$JDK_HOME/bin/java" -version 2>&1 | head -1)"

step "Installing the Flutter SDK (stable)"
if [[ -x "$FLUTTER_DIR/bin/flutter" ]]; then
  ok "Already present at $FLUTTER_DIR"
else
  echo "    Downloading Flutter stable (~240 MB) — this takes a little while…"
  rm -rf "$FLUTTER_DIR"
  git clone -b stable --depth 1 https://github.com/flutter/flutter.git "$FLUTTER_DIR" \
    || fail "Could not download Flutter. Check your internet connection and re-run."
  ok "Flutter downloaded to $FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

step "Installing the Android SDK (command line tools, platform 36, build tools 36)"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
if [[ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  mkdir -p "$SDK_ROOT/cmdline-tools" "$SDK_ROOT/.download"
  echo "    Downloading Android command line tools (~175 MB)…"
  curl -fL --retry 3 "$CMDLINE_TOOLS_URL" -o "$SDK_ROOT/.download/$CMDLINE_TOOLS_ZIP" \
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
echo "    Installing platform-tools, platform 36 and build-tools 36…"
"$SDKMANAGER" --install "${ANDROID_PACKAGES[@]}" >/dev/null \
  || warn "Some Android packages could not be installed — re-run after checking your connection."
[[ -x "$SDK_ROOT/platform-tools/adb" ]] && ok "adb at $SDK_ROOT/platform-tools/adb"
ok "Android SDK ready at $SDK_ROOT"

step "Saving environment variables"
BASHRC="$HOME/.bashrc"
BLOCK_START="# >>> Anima/Journey dev environment >>>"
BLOCK_END="# <<< Anima/Journey dev environment <<<"
# Strip any previous block (either project's older marker) so running both setup
# scripts can never leave duplicate PATH/JAVA_HOME entries in ~/.bashrc.
if grep -qE '# >>> .*dev environment >>>' "$BASHRC" 2>/dev/null; then
  python3 - "$BASHRC" <<'PY'
import re, sys
path = sys.argv[1]
start = re.compile(r'^# >>> .*dev environment >>>$')
end = re.compile(r'^# <<< .*dev environment <<<$')
keep, skipping = [], False
for line in open(path).read().splitlines():
    stripped = line.strip()
    if start.match(stripped):
        skipping = True
        continue
    if end.match(stripped):
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

# Apps started from the application menu (Cursor, the menu launcher) never read
# ~/.bashrc, so mirror the same values for the login session too.
ENV_DIR="$HOME/.config/environment.d"
mkdir -p "$ENV_DIR"
rm -f "$ENV_DIR/50-anima-dev.conf" "$ENV_DIR/50-journey-dev.conf" 2>/dev/null || true
cat > "$ENV_DIR/50-flutter-dev.conf" <<EOF
# Written by Anima/Journey scripts/setup_linux_dev_noroot.sh — safe to delete.
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
print(f"    ✓ Cursor setting dart.flutterSdkPath = {flutter}")
PY

step "Restoring the global git identity"
if git config --global --get user.email >/dev/null 2>&1; then
  ok "Already set ($(git config --global --get user.email))"
else
  git config --global user.name "jwarren9393"
  git config --global user.email "196878293+jwarren9393@users.noreply.github.com"
  git config --global init.defaultBranch main
  ok "Set to jwarren9393 — change it with: git config --global user.email \"you@example.com\""
fi

step "Enabling the Flutter desktop and Android targets"
"$FLUTTER_DIR/bin/flutter" config --no-analytics --enable-linux-desktop --enable-android \
  --jdk-dir="$JDK_HOME" --android-sdk="$SDK_ROOT" >/dev/null \
  || fail "Flutter could not start (its first run downloads the Dart SDK). Check your internet connection and re-run."
ok "Linux desktop and Android enabled, pointed at $JDK_HOME and $SDK_ROOT"

step "Downloading the project's Dart packages"
cd "$ROOT_DIR"
"$FLUTTER_DIR/bin/flutter" pub get || warn "'flutter pub get' failed — fix the notes above and re-run."

step "Checking your installation (flutter doctor)"
"$FLUTTER_DIR/bin/flutter" doctor || true

printf '\n\033[1;32m========================================\033[0m\n'
printf '\033[1;32m Anima dev environment is ready\033[0m\n'
printf '\033[1;32m========================================\033[0m\n'
echo
echo "Project        : $ROOT_DIR"
echo "Flutter        : $FLUTTER_DIR"
echo "JDK 17         : $JDK_HOME"
echo "Android SDK    : $SDK_ROOT"
echo
echo "Next steps:"
echo "  1. Close and reopen your terminal (and restart Cursor) so PATH applies."
echo "  2. Sign in to GitHub once (needs a browser):"
echo "       gh auth login --hostname github.com --git-protocol https --web"
echo "       gh auth setup-git"
if [[ "$SUDO_OK" != "1" ]]; then
  echo "  3. For the *Linux desktop* build only, run this once (your password):"
  echo "       sudo apt-get update && sudo apt-get install -y $APT_PACKAGES"
fi
echo "  4. Build / run the app:"
echo "       cd \"$ROOT_DIR\""
echo "       flutter run               # Android phone over USB"
echo "       flutter run -d linux      # desktop (needs step 3 above)"
echo "  5. Run the test suite:  flutter test"
echo


