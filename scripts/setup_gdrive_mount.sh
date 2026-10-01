#!/usr/bin/env bash
#
# Anima — Google Drive on Linux: a browsable mount + a local sync file for Anima.
#
# Why this exists: Anima's "Choose sync file" picker needs a *real* filesystem path.
# GNOME's "Files → Google Drive" needs GNOME Online Accounts, which is unreliable on
# KDE (Kubuntu), and KDE's kio-gdrive is not a POSIX path either — so the picker sees
# nothing. rclone mounts Drive as an ordinary folder that any app can browse.
#
# What this does:
#   1. makes sure the rclone binary exists (downloads it into ~/.local/bin — no sudo)
#   2. checks you have a Google Drive remote in ~/.config/rclone/rclone.conf
#   3. creates ~/GoogleDrive plus a systemd user service that keeps Drive mounted,
#      tuned for browsing (long directory cache + local read cache) so a file manager
#      does not re-ask Google for every folder and picture
#   4. keeps a LOCAL copy of Anima's sync file at
#      ~/AnimaCloud/anima-sync.anima-backup in step with Drive — a background timer
#      checks every 45 s and a change to the local file uploads it straight away, so
#      Pull works without waiting on the network and Push goes out in seconds
#   5. starts everything now and prints what came back
#
# Usage:
#   bash scripts/setup_gdrive_mount.sh                 # remote "gdrive" → ~/GoogleDrive
#   bash scripts/setup_gdrive_mount.sh --remote mydr   # use another remote name
#   bash scripts/setup_gdrive_mount.sh --dir ~/Drive   # mount somewhere else
#   bash scripts/setup_gdrive_mount.sh --sync          # sync the sync file right now
#   bash scripts/setup_gdrive_mount.sh --uninstall     # remove mount + background sync
#   bash scripts/setup_gdrive_mount.sh -h
#
# Safe to re-run: it rewrites the service files and restarts the mount.
set -Eeuo pipefail

REMOTE="gdrive"
MOUNT_DIR="$HOME/GoogleDrive"
RCLONE="$HOME/.local/bin/rclone"
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
UNIT_NAME="anima-gdrive"
UNIT_FILE="$HOME/.config/systemd/user/$UNIT_NAME.service"
# Anima's own sync file, kept as a plain local file (never read through FUSE).
CLOUD_DIR="$HOME/AnimaCloud"
MIRROR_FILE="$CLOUD_DIR/anima-sync.anima-backup"
SYNC_HELPER="$HOME/.local/bin/anima-drive-sync"
SYNC_UNIT="anima-cloud-sync"
UNINSTALL=0
SYNC_ONLY=0

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[1;33m! %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE="${2:-}"; shift 2 ;;
    --dir)    MOUNT_DIR="${2:-}"; shift 2 ;;
    --sync)   SYNC_ONLY=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) fail "Unknown option: $1  (try --help)" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || fail "This script only runs on Linux."

if [[ "$SYNC_ONLY" == "1" ]]; then
  command -v "$SYNC_HELPER" >/dev/null 2>&1 || [[ -x "$SYNC_HELPER" ]] \
    || fail "Background sync is not set up yet — run this script without --sync first."
  exec "$SYNC_HELPER"
fi

if [[ "$UNINSTALL" == "1" ]]; then
  step "Removing the Google Drive mount and the background sync"
  systemctl --user disable --now "$UNIT_NAME.service" 2>/dev/null || true
  systemctl --user disable --now "$SYNC_UNIT.timer" "$SYNC_UNIT.path" 2>/dev/null || true
  fusermount3 -u "$MOUNT_DIR" 2>/dev/null || fusermount -u "$MOUNT_DIR" 2>/dev/null || true
  rm -f "$UNIT_FILE" "$HOME/.config/autostart/$UNIT_NAME.desktop" \
        "$HOME/.config/systemd/user/$SYNC_UNIT.service" \
        "$HOME/.config/systemd/user/$SYNC_UNIT.timer" \
        "$HOME/.config/systemd/user/$SYNC_UNIT.path" \
        "$SYNC_HELPER"
  systemctl --user daemon-reload 2>/dev/null || true
  ok "Removed. Your Drive files and the ~/AnimaCloud copy are untouched — only the automation is gone."
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
# Browsing-friendly tuning. Anima itself does NOT read through this mount (it uses the
# local copy in ~/AnimaCloud), so keeping a local read cache here is safe and makes a
# file manager behave like a normal disk instead of re-asking Google for everything.
ExecStart=$RCLONE mount $REMOTE: $MOUNT_DIR \\
  --config $RCLONE_CONF \\
  --vfs-cache-mode full \\
  --vfs-cache-max-size 20G \\
  --vfs-cache-max-age 72h \\
  --vfs-fast-fingerprint \\
  --dir-cache-time 4h \\
  --poll-interval 3m \\
  --checkers 2 --transfers 2 \\
  --buffer-size 16M \\
  --vfs-read-chunk-size 16M --vfs-read-chunk-size-limit 1G \\
  --log-level INFO
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

step "Keeping Anima's sync file as a local file"
# Pull/Push should never wait on (or be confused by) a network mount. The sync file is
# mirrored to ~/AnimaCloud: a change here uploads at once, and a timer pulls remote
# changes down (including ones the phone pushed).
mkdir -p "$CLOUD_DIR" "$HOME/.local/bin"

cat > "$SYNC_HELPER" <<'HELPER'
#!/usr/bin/env bash
# Keeps ~/AnimaCloud/anima-sync.anima-backup in step with Google Drive.
# Newest write wins; nothing is ever deleted. Generated by Anima's
# scripts/setup_gdrive_mount.sh — remove it with that script's --uninstall.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

REMOTE="${ANIMA_DRIVE_REMOTE:-gdrive:Anima Backup/anima-sync.anima-backup}"
LOCAL="${ANIMA_DRIVE_LOCAL:-$HOME/AnimaCloud/anima-sync.anima-backup}"
NAME="$(basename "$LOCAL")"

mkdir -p "$(dirname "$LOCAL")" "$HOME/.cache"
exec 9>"$HOME/.cache/anima-drive-sync.lock"
flock -n 9 || { echo "already running — skipping"; exit 0; }

# Never upload a half-written file: wait until size+mtime hold still.
for _ in 1 2 3 4 5; do
  a="$(stat -c '%s %Y' "$LOCAL" 2>/dev/null || echo none)"
  sleep 2
  b="$(stat -c '%s %Y' "$LOCAL" 2>/dev/null || echo none)"
  [[ "$a" == "$b" ]] && break
done

remote_line="$(timeout 180 rclone lsl "$REMOTE" 2>/dev/null | head -1)"
if [[ -z "$remote_line" ]]; then
  echo "Drive not reachable (or $NAME is missing there) — leaving the local copy alone."
  exit 0
fi
remote_stamp="$(awk '{print $2" "$3}' <<<"$remote_line" | cut -d. -f1)"
remote_epoch="$(date -d "$remote_stamp" +%s 2>/dev/null || echo 0)"
local_epoch=0
[[ -f "$LOCAL" ]] && local_epoch="$(stat -c %Y "$LOCAL")"

if (( local_epoch == 0 )); then
  echo "Creating the local copy from Drive…"
  rclone copyto "$REMOTE" "$LOCAL"
elif (( local_epoch > remote_epoch + 1 )); then
  echo "Uploading the local copy (newer by $((local_epoch - remote_epoch))s)…"
  rclone copyto "$LOCAL" "$REMOTE"
elif (( remote_epoch > local_epoch + 1 )); then
  echo "Downloading the Drive copy (newer by $((remote_epoch - local_epoch))s)…"
  rclone copyto "$REMOTE" "$LOCAL"
else
  echo "In step (local=$local_epoch remote=$remote_epoch)."
fi
HELPER
chmod +x "$SYNC_HELPER"
ok "Wrote $SYNC_HELPER"

cat > "$HOME/.config/systemd/user/$SYNC_UNIT.service" <<EOF
[Unit]
Description=Keep Anima's sync file in step with Google Drive
After=network-online.target

[Service]
Type=oneshot
Environment="ANIMA_DRIVE_REMOTE=$REMOTE:Anima Backup/anima-sync.anima-backup"
ExecStart=$SYNC_HELPER
EOF

cat > "$HOME/.config/systemd/user/$SYNC_UNIT.timer" <<EOF
[Unit]
Description=Check Anima's Google Drive sync file regularly

[Timer]
OnBootSec=45s
OnUnitActiveSec=45s
AccuracySec=5s
Unit=$SYNC_UNIT.service

[Install]
WantedBy=timers.target
EOF

cat > "$HOME/.config/systemd/user/$SYNC_UNIT.path" <<EOF
[Unit]
Description=Upload Anima's sync file as soon as it changes

[Path]
PathModified=$MIRROR_FILE
Unit=$SYNC_UNIT.service

[Install]
WantedBy=paths.target
EOF

if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user enable --now "$SYNC_UNIT.timer" "$SYNC_UNIT.path" >/dev/null 2>&1 || true
  ok "Background sync running: every 45 s, plus instantly whenever the file changes."
else
  warn "No user systemd here — run '$SYNC_HELPER' yourself (or add it to autostart)."
fi

echo "    First sync:"
"$SYNC_HELPER" 2>&1 | sed 's/^/      /'
[[ -f "$MIRROR_FILE" ]] && ok "Local sync file ready: $MIRROR_FILE ($(wc -c < "$MIRROR_FILE") bytes)"

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
echo "           pick  $MIRROR_FILE"
echo
echo "That path is an ordinary local file — instant to read, and never a half-downloaded"
echo "copy. It is kept in step with Drive: editing it uploads within seconds, and changes"
echo "the phone pushes arrive within about 45 s."
echo
echo "Your Drive is also browsable at $MOUNT_DIR (Dolphin / any file dialog)."
echo
echo "Handy commands:"
echo "  bash scripts/setup_gdrive_mount.sh --sync     # sync the sync file right now"
echo "  $SYNC_HELPER                                    # same thing, directly"
echo "  systemctl --user status $UNIT_NAME            # is the Drive mount healthy?"
echo "  systemctl --user list-timers $SYNC_UNIT       # is the background sync alive?"
echo "  journalctl --user -u $UNIT_NAME -n 50         # mount logs"
echo "  bash scripts/setup_gdrive_mount.sh --uninstall"

