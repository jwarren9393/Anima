#!/usr/bin/env bash
#
# Anima — move your library between the phone and this PC with NO cloud at all.
#
# Why this exists: if your phone is always with you, Google Drive is an unnecessary
# middleman (and Google rate-limits rclone's shared client_id, which made it slow).
# This uses the USB / Wi-Fi link you already have — adb — to copy Anima's own backup
# file, or the whole library folder, in whichever direction you ask for. No account,
# no consent screen, no tokens that expire.
#
# One-time setup on the phone, so the app and this script agree on a folder:
#   Anima → Settings → Backup, restore & sync → choose sync folder → Documents/Anima
# After that, "Push to cloud" on the phone writes anima-sync.anima-backup into that
# folder, which is exactly the file this script copies.
#
# Usage:
#   bash scripts/sync_phone_anima.sh                   # status only — changes nothing
#   bash scripts/sync_phone_anima.sh --push            # this PC  → phone
#   bash scripts/sync_phone_anima.sh --pull            # phone → this PC
#   bash scripts/sync_phone_anima.sh --auto            # copy whichever side is newer
#   bash scripts/sync_phone_anima.sh --library --push  # whole library folder, not just the backup
#   bash scripts/sync_phone_anima.sh --auto --dry-run  # show what would happen
#   bash scripts/sync_phone_anima.sh --library --pull --yes   # skip the confirmation
#
# Then apply it in the app on the receiving device:
#   Anima → Settings → Backup, restore & sync → Pull from cloud
# (On the PC it reads a local file, so it is instant.)
#
# Notes:
#   * --library copies the live library folder. Close Anima on the phone first and
#     re-open it afterwards, and each device keeps its own settings + API key
#     (anima_settings.json and api_key.txt are never copied).
#   * --dry-run prints the exact adb commands instead of running them.
set -Eeuo pipefail

ADB=""
for candidate in "$HOME/Android/Sdk/platform-tools/adb" "$(command -v adb 2>/dev/null || true)"; do
  [[ -n "$candidate" && -x "$candidate" ]] && ADB="$candidate" && break
done

PHONE_LIB="/storage/emulated/0/Documents/Anima"
PHONE_FILE="$PHONE_LIB/anima-sync.anima-backup"
LOCAL_LIB="$HOME/Documents/Anima"
LOCAL_FILE="$HOME/AnimaCloud/anima-sync.anima-backup"
# Per-device files: never copied, or the two devices would fight over them.
SKIP_FILES=(api_key.txt anima_settings.json)

DIRECTION=""
MODE="file"          # file | library
DRY_RUN=0
ASSUME_YES=0
SERIAL=""

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[1;33m! %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)    DIRECTION="push"; shift ;;
    --pull)    DIRECTION="pull"; shift ;;
    --auto)    DIRECTION="auto"; shift ;;
    --library) MODE="library"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -s|--serial) SERIAL="${2:-}"; shift 2 ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) fail "Unknown option: $1  (try --help)" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || fail "This script only runs on Linux."
[[ -n "$ADB" ]] || fail "adb was not found. It ships with the Android SDK (see scripts/setup_linux_dev_noroot.sh)."

run() { # run <command...>  — honours --dry-run
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '    would run: %s\n' "$*"
  else
    "$@"
  fi
}

step "Finding your phone"
if [[ -z "$SERIAL" ]]; then
  SERIAL="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi
[[ -n "$SERIAL" ]] || fail "No phone found. Plug it in over USB, or turn on Developer options → Wireless debugging, then try again.
    adb devices      # a line saying 'unauthorized' means accept the prompt on the phone"
ok "Using $SERIAL"

phone_stat() { # bytes + mtime, e.g. "8120140 1790833428"
  # NB: the format must stay quoted *through* adb, otherwise the phone's shell
  # splits it and stat treats "%Y" as a second filename (returning just the size).
  "$ADB" -s "$SERIAL" shell "stat -c '%s %Y' '$1'" 2>/dev/null | tr -d '\r' || true
}
local_stat() { [[ -e "$1" ]] && stat -c '%s %Y' "$1" || true; }

step "What each side has"
PHONE_COUNT="$("$ADB" -s "$SERIAL" shell "ls $PHONE_LIB 2>/dev/null | wc -l" 2>/dev/null | tr -d '\r' || echo 0)"
info "phone library  : $PHONE_LIB ($PHONE_COUNT entries)"
info "this PC library: $LOCAL_LIB ($(ls "$LOCAL_LIB" 2>/dev/null | wc -l) entries)"

if [[ "$MODE" == "file" ]]; then
  echo
  P_SYNC="$(phone_stat "$PHONE_FILE")"
  L_SYNC="$(local_stat "$LOCAL_FILE")"
  if [[ -n "$P_SYNC" ]]; then
    info "phone backup : ${P_SYNC%% *} bytes, written $(date -d "@${P_SYNC##* }" '+%Y-%m-%d %H:%M')"
  else
    warn "phone backup : not there yet (on the phone: Push to cloud)"
  fi
  if [[ -n "$L_SYNC" ]]; then
    info "PC backup    : ${L_SYNC%% *} bytes, written $(date -d "@${L_SYNC##* }" '+%Y-%m-%d %H:%M')"
  else
    warn "PC backup    : not there yet"
  fi
fi

# --auto: work out which side holds the newest data.
if [[ "$DIRECTION" == "auto" && "$MODE" == "file" ]]; then
  P_SYNC="$(phone_stat "$PHONE_FILE")"; L_SYNC="$(local_stat "$LOCAL_FILE")"
  if   [[ -z "$P_SYNC" && -z "$L_SYNC" ]]; then fail "Neither side has a backup file yet."
  elif [[ -z "$P_SYNC" ]]; then DIRECTION="push"
  elif [[ -z "$L_SYNC" ]]; then DIRECTION="pull"
  elif (( ${P_SYNC##* } > ${L_SYNC##* } + 1 )); then DIRECTION="pull"
  elif (( ${L_SYNC##* } > ${P_SYNC##* } + 1 )); then DIRECTION="push"
  else
    ok "Already in step — nothing to copy."
    echo
    info "Apply it in the app if you have not: Settings → Backup, restore & sync → Pull from cloud"
    exit 0
  fi
  ok "The phone has the newest data" 2>/dev/null || true
fi

[[ -n "$DIRECTION" ]] || {
  echo
  info "Status check only — nothing was changed. Add --push, --pull or --auto to copy."
  exit 0
}

# A real run overwrites files on the receiving device: confirm first.
if [[ "$ASSUME_YES" != "1" && "$DRY_RUN" != "1" ]]; then
  FROM="$([[ "$DIRECTION" == "pull" ]] && echo phone || echo 'this PC')"
  TO="$([[ "$DIRECTION" == "pull" ]] && echo 'this PC' || echo phone)"
  if [[ -t 0 ]]; then
    printf '    Copy %s from %s to %s (overwrites it there)? [y/N] ' "$MODE" "$FROM" "$TO"
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || { warn "Cancelled — nothing changed."; exit 0; }
  else
    fail "Refusing to overwrite without confirmation — add --yes, or use --dry-run first."
  fi
fi

step "Copying ($DIRECTION, $MODE mode, ${DRY_RUN:+dry run})"

if [[ "$MODE" == "file" ]]; then
  mkdir -p "$(dirname "$LOCAL_FILE")"
  if [[ "$DIRECTION" == "push" ]]; then
    [[ -f "$LOCAL_FILE" ]] || fail "There is no PC backup file at $LOCAL_FILE yet. In Anima: Backup, restore & sync → Push to cloud."
    run "$ADB" -s "$SERIAL" push "$LOCAL_FILE" "$PHONE_FILE"
    [[ "$DRY_RUN" == "1" ]] || ok "Sent $(wc -c < "$LOCAL_FILE") bytes to the phone"
  else
    [[ -n "$(phone_stat "$PHONE_FILE")" ]] || fail "The phone has no $PHONE_FILE yet. On the phone: Settings → Backup, restore & sync → Push to cloud (with the sync folder set to Documents/Anima)."
    run "$ADB" -s "$SERIAL" pull "$PHONE_FILE" "$LOCAL_FILE"
    [[ "$DRY_RUN" == "1" ]] || ok "Saved $(wc -c < "$LOCAL_FILE") bytes to $LOCAL_FILE"
  fi
else
  TMP="$(mktemp -d)"
  if [[ "$DIRECTION" == "pull" ]]; then
    run "$ADB" -s "$SERIAL" pull "$PHONE_LIB" "$TMP"
    if [[ "$DRY_RUN" == "1" ]]; then
      info "would copy every file from the phone's library into $LOCAL_LIB"
      info "(skipping ${SKIP_FILES[*]} — each device keeps its own)"
    else
      SRC="$TMP/Anima"
      [[ -d "$SRC" ]] || fail "adb did not produce $SRC"
      mkdir -p "$LOCAL_LIB"
      (cd "$SRC" && tar -cf - --exclude=api_key.txt --exclude=anima_settings.json .) \
        | (cd "$LOCAL_LIB" && tar -xf -)
      ok "Copied $(find "$SRC" -type f | wc -l) files into $LOCAL_LIB"
      warn "Skipped ${SKIP_FILES[*]} — your API key and settings stayed put."
    fi
  else
    if [[ "$DRY_RUN" == "1" ]]; then
      info "would copy every file from $LOCAL_LIB to the phone's library"
      info "(skipping ${SKIP_FILES[*]} — each device keeps its own)"
    else
      SRC="$TMP/lib"; mkdir -p "$SRC"
      (cd "$LOCAL_LIB" && tar -cf - --exclude=api_key.txt --exclude=anima_settings.json .) \
        | (cd "$SRC" && tar -xf -)
      run "$ADB" -s "$SERIAL" push "$SRC/." "$PHONE_LIB/"
      ok "Copied $(find "$SRC" -type f | wc -l) files to the phone"
      warn "Skipped ${SKIP_FILES[*]} — the phone keeps its own API key and settings."
      warn "Re-open Anima on the phone so it reads the new files."
    fi
  fi
  rm -rf "$TMP" 2>/dev/null || true
fi

printf '\n\033[1;32m========================================\033[0m\n'
printf '\033[1;32m Transfer done\033[0m\n'
printf '\033[1;32m========================================\033[0m\n'
echo
echo "Apply it on the device that received the files:"
echo "  Anima → Settings → Backup, restore & sync → Pull from cloud"
echo
if [[ "$MODE" == "library" ]]; then
  echo "(--library copies the live library folder, so just restart Anima there.)"
  echo
fi
echo "Handy:"
echo "  bash scripts/sync_phone_anima.sh --auto     # whoever is newer wins"
echo "  bash scripts/sync_phone_anima.sh            # look, do not touch"
echo "  bash scripts/sync_phone_anima.sh --help"
echo
echo "No cloud involved: this is a direct copy over USB or Wi-Fi to your own phone."
