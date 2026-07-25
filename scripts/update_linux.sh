#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA_HOME/anima"
APPLICATIONS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons"
BUILD_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
STAGING_DIR="$DATA_HOME/.anima-installing"

case "${1:-}" in
  "")
    ;;
  --pull)
    if ! command -v git >/dev/null 2>&1; then
      echo "Git was not found, so the latest source cannot be downloaded."
      exit 1
    fi
    echo "Downloading the latest Anima source..."
    git -C "$ROOT_DIR" pull --ff-only
    ;;
  -h|--help)
    echo "Usage: ./scripts/update_linux.sh [--pull]"
    echo "  --pull  Download the latest GitHub changes before building."
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: ./scripts/update_linux.sh [--pull]"
    exit 2
    ;;
esac

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This installer only runs on Linux."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter was not found."
  echo "Install Flutter, reopen the terminal, and run this script again."
  echo "Guide: https://docs.flutter.dev/get-started/install/linux"
  exit 1
fi

echo "Building the latest Anima Linux release..."
cd "$ROOT_DIR"
flutter pub get
flutter build linux --release

echo "Installing Anima for the current user..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$APPLICATIONS_DIR" "$ICON_DIR"
cp -a "$BUILD_DIR/." "$STAGING_DIR/"

rm -rf "$INSTALL_DIR"
mv "$STAGING_DIR" "$INSTALL_DIR"
cp "$ROOT_DIR/assets/branding/anima_icon.png" "$ICON_DIR/anima.png"

cat >"$APPLICATIONS_DIR/anima.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Anima
Comment=Private AI character chat
Exec=$INSTALL_DIR/anima
Icon=$ICON_DIR/anima.png
Terminal=false
Categories=Network;Chat;
StartupNotify=true
StartupWMClass=anima
EOF

chmod +x "$INSTALL_DIR/anima"
chmod +x "$APPLICATIONS_DIR/anima.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

echo
echo "Anima is installed and up to date."
echo "Open it from your application menu, or run:"
echo "  $INSTALL_DIR/anima"
