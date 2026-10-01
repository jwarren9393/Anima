#!/usr/bin/env bash
#
# Anima — mount Google Drive as a normal folder on Linux (for Sync / backup).
#
# Why this exists: Anima's "Choose sync file" picker needs a *real* filesystem path.
# GNOME's "Files → Google Drive" needs GNOME Online Accounts, which is unreliable on
# KDE (Kubuntu), and KDE's kio-gdrive is not a POSIX path either — so the picker sees
# nothing. rclone mounts Drive as an ordinary folder that any app can browse.
#
# What this does:
#   1. makes sure the rclone binary exists (downloads it into ~/.local/bin — no sudo)
#   2. checks you have a Google Drive remote in ~/.config/rclone/rclone.conf
#   3. creates ~/GoogleDrive plus a systemd user service that keeps Drive mounted
#   4. starts it now and prints what came back
#
# Usage:
#   bash scripts/setup_gdrive_mount.sh                 # remote "gdrive" → ~/GoogleDrive
#   bash scripts/setup_gdrive_mount.sh --remote mydr   # use another remote name
#   bash scripts/setup_gdrive_mount.sh --dir ~/Drive   # mount somewhere else
#   bash scripts/setup_gdrive_mount.sh --uninstall
#   bash scripts/setup_gdrive_mount.sh -h
#
# Safe to re-run: it rewrites the service file and restarts the mount.
set -Eeuo pipefail

REMOTE="gdrive"
MOUNT_DIR="$HOME/GoogleDrive"
RCLONE="$HOME/.local/bin/rclone"
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
UNIT_NAME="anima-gdrive"
UNIT_FILE="$HOME/.config/systemd/user/$UNIT_NAME.service"
UNINSTALL=0

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[1;33m! %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE="${2:-}"; shift 2 ;;
    --dir)    MOUNT_DIR="${2:-}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) fail "Unknown option: $1  (try --help)" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || fail "This script only runs on Linux."

if [[ "$UNINSTALL" == "1" ]]; then
  step "Removing the Google Drive mount"
  systemctl --user disable --now "$UNIT_NAME.service" 2>/dev/null || true
  fusermount3 -u "$MOUNT_DIR" 2>/dev/null || fusermount -u "$MOUNT_DIR" 2>/dev/null || true
  rm -f "$UNIT_FILE" "$HOME/.config/autostart/$UNIT_NAME.desktop"
  systemctl --user daemon-reload 2>/dev/null || true
  ok "Removed. Your Drive files are untouched; only the local mount is gone."
  exit 0
fi

command -v curl >/dev/null || command -v rclone >/dev/null || fail "curl is required to download rclone."
command -v fusermount3 >/dev/null || command -v fusermount >/dev/null \
  || fail "FUSE is missing — install it with:  sudo apt-get install -y fuse3"

step "Making sure rclone is available"
if command -v rclone >/dev/null 2>&1; then
  RCLONE="$(command -v rclone)"
  ok "Using the system rclone at $RCLONE"
elif [[ -x "$RCLONE" ]]; then
  ok "Using the existing rclone at $RCLONE"
else
  echo "    Downloading rclone into ~/.local/bin (no administrator password needed)…"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/rclone.zip" https://downloads.rclone.org/rclone-current-linux-amd64.zip \
    || fail "Could not download rclone. Check your internet connection."
  unzip -q -o "$tmp/rclone.zip" -d "$tmp"
  mkdir -p "$(dirname "$RCLONE")"
  cp -f "$tmp"/rclone-*/rclone "$RCLONE"
  chmod +x "$RCLONE"
  rm -rf "$tmp"
  ok "rclone installed at $RCLONE"
fi
"$RCLONE" version | head -1 | sed 's/^/    /'

step "Checking the Google Drive remote in rclone.conf"
if [[ ! -f "$RCLONE_CONF" ]]; then
  warn "No $RCLONE_CONF yet — create one first (it opens your browser once):"
  echo "      rclone config        # n → name: $REMOTE → type: drive → scope: drive → auto config: y"
  fail "Then run this script again."
fi
if ! grep -qE "^\[$REMOTE\]" "$RCLONE_CONF"; then
  warn "Remote \"$REMOTE\" was not found in $RCLONE_CONF. Remotes present:"
  grep -oE '^\[[^]]+\]' "$RCLONE_CONF" | sed 's/^/      /' || true
  fail "Create it with:  rclone config   (or pass --remote <name>)"
fi
ok "Remote \"$REMOTE\" found."
# A drive remote created without your own client_id uses rclone's shared one, which
# Google is retiring during 2026 — mention it so it is not a surprise later.
if ! grep -A6 "^\[$REMOTE\]" "$RCLONE_CONF" | grep -q '^client_id'; then
  warn "This remote uses rclone's shared Google client_id, which Google is retiring"
  warn "during 2026. When it stops working, make your own ID (rclone.org/drive) then:"
  warn "  rclone config update $REMOTE client_id <id> client_secret <secret>"
fi

echo "    Testing the remote (this talks to Google)…"
if ! timeout 90 "$RCLONE" lsd "$REMOTE:" >/dev/null 2>&1; then
  fail "Could not list $REMOTE: — you probably need to sign in again:  rclone config reconnect $REMOTE:"
fi
ok "Google Drive answers."

step "Mounting Drive at $MOUNT_DIR"
mkdir -p "$MOUNT_DIR" "$HOME/.config/systemd/user"

# --dir-cache-time / --poll-interval keep the folder listing fresh, which matters
# because the phone pushes the sync file from another device; --vfs-cache-mode writes
# lets Anima overwrite the file in place and have it uploaded promptly.
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Google Drive mount for Anima sync (rclone)
Documentation=https://rclone.org/commands/rclone_mount/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/bin/mkdir -p $MOUNT_DIR
ExecStart=$RCLONE mount $REMOTE: $MOUNT_DIR --config $RCLONE_CONF --vfs-cache-mode writes --vfs-write-back 2s --dir-cache-time 15s --poll-interval 15s --log-level INFO
ExecStopPost=-/usr/bin/fusermount3 -u $MOUNT_DIR
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=default.target
EOF
ok "Wrote $UNIT_FILE"

if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user enable --now "$UNIT_NAME.service" >/dev/null 2>&1 || true
  sleep 5
  if mountpoint -q "$MOUNT_DIR"; then
    ok "Drive is mounted and comes back automatically at every login."
  else
    warn "The service did not mount in time — check:  journalctl --user -u $UNIT_NAME -n 40"
  fi
else
  # No user systemd — fall back to a desktop autostart entry.
  mkdir -p "$HOME/.config/autostart"
  cat > "$HOME/.config/autostart/$UNIT_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Google Drive mount (Anima)
Comment=Mounts Google Drive at $MOUNT_DIR with rclone
Exec=$RCLONE mount $REMOTE: $MOUNT_DIR --config $RCLONE_CONF --vfs-cache-mode writes --vfs-write-back 2s --dir-cache-time 15s --poll-interval 15s
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  nohup "$RCLONE" mount "$REMOTE:" "$MOUNT_DIR" --config "$RCLONE_CONF" \
    --vfs-cache-mode writes --vfs-write-back 2s --dir-cache-time 15s --poll-interval 15s \
    >/dev/null 2>&1 &
  sleep 5
  ok "No user systemd here — added an autostart entry and started the mount."
fi

step "What is in Drive now"
if mountpoint -q "$MOUNT_DIR"; then
  ls -la "$MOUNT_DIR" | sed 's/^/    /'
else
  warn "Not mounted yet; try:  $RCLONE lsf $REMOTE:"
fi

printf '\n\033[1;32m========================================\033[0m\n'
printf '\033[1;32m Google Drive is available to Anima\033[0m\n'
printf '\033[1;32m========================================\033[0m\n'
echo
echo "In Anima:  Settings → Backup, restore & sync → Choose sync file"
echo "           browse to  $MOUNT_DIR/Anima Backup/anima-sync.anima-backup"
echo
echo "Push to cloud overwrites that file and Pull from cloud restores from it —"
echo "the phone uses the same file, so phone ↔ PC handoff works normally."
echo
echo "Handy commands:"
echo "  rclone lsf $REMOTE:Anima\\ Backup        # list the folder"
echo "  systemctl --user status $UNIT_NAME       # is the mount healthy?"
echo "  journalctl --user -u $UNIT_NAME -n 50    # mount logs"
echo "  bash scripts/setup_gdrive_mount.sh --uninstall"

