#!/usr/bin/env bash
#
# Anima — create (or refresh) a build-capable copy of the project on your internal
# Linux drive.
#
# Why this exists: the Anima folder on the Jay-Storage drive is exFAT. Flutter
# stores its plugin links as symlinks and exFAT cannot store symlinks, so
# 'flutter pub get' and every build fail inside that folder. A copy on the
# internal (ext4) drive builds normally.
#
# Usage:
#   bash scripts/dev_copy_linux.sh                   copy into ~/Documents/App-Builds/Anima
#   bash scripts/dev_copy_linux.sh ~/Projects/Anima  use another folder
#
# GitHub stays the shared source of truth. The copy is a normal git checkout of
# the same repository, so commit + push there and pull on your Windows PC.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$HOME/Documents/App-Builds/Anima}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[1;33m!\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || fail "This script only runs on Linux."
command -v git >/dev/null 2>&1 || fail "Git is not installed yet — run scripts/setup_linux_dev.sh first."
[[ -d "$ROOT_DIR/.git" ]] || fail "This folder is not a git checkout: $ROOT_DIR"

step "Preparing the working copy at $TARGET"
PROBE_DIR="$(dirname "$TARGET")"
[[ -d "$PROBE_DIR" ]] || PROBE_DIR="$HOME"
if ! ln -s /tmp "$PROBE_DIR/.anima-symlink-probe" 2>/dev/null; then
  rm -f "$PROBE_DIR/.anima-symlink-probe" 2>/dev/null || true
  fail "That folder is also on a drive without symlink support. Pick a folder on your internal disk, e.g. ~/Documents/App-Builds/Anima"
fi
rm -f "$PROBE_DIR/.anima-symlink-probe"
ok "$PROBE_DIR can store symlinks, so Flutter builds will work there."

if [[ -d "$TARGET/.git" ]]; then
  ok "Working copy already exists — bringing it up to date."
  git -C "$TARGET" fetch --prune origin
  if git -C "$TARGET" rev-parse --verify origin/main >/dev/null 2>&1; then
    git -C "$TARGET" merge --ff-only origin/main || warn "The copy has local commits of its own; leaving it as it is."
  fi
else
  # Never copy a half-finished edit out of sight: require a clean source tree.
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    echo
    echo "These files in $ROOT_DIR are not committed yet:"
    git -C "$ROOT_DIR" status --short
    fail "Commit or stash them first so the copy includes your work, then run this script again."
  fi
  step "Copying the project to the internal drive"
  git clone --no-hardlinks "$ROOT_DIR" "$TARGET" \
    || fail "Could not create the copy."
  # Cloning from a local folder points 'origin' at that folder; aim it back at GitHub.
  git -C "$TARGET" remote set-url origin https://github.com/jwarren9393/Anima.git
  ok "Copied the whole git history to $TARGET"
fi

step "Downloading packages in the new copy"
if command -v flutter >/dev/null 2>&1; then
  ( cd "$TARGET" && flutter pub get ) || warn "'flutter pub get' failed — check the output above."
  ok "Done."
else
  warn "Flutter is not on your PATH in this shell yet (open a new terminal, or run scripts/setup_linux_dev.sh)."
fi

printf '\n\033[1;32mWorking copy ready: %s\033[0m\n\n' "$TARGET"
echo "Do your coding here:"
echo "    cd \"$TARGET\""
echo "    flutter run -d linux      # desktop"
echo "    flutter run               # Android phone over USB"
echo "    flutter test              # the test suite"
echo
echo "Open THIS folder in Cursor: $TARGET"
echo "The exFAT copy at $ROOT_DIR stays as your portable/Windows copy — update it with:"
echo "    git -C \"$ROOT_DIR\" pull"
