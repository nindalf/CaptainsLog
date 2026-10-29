#!/usr/bin/env bash
# Replaces the store with a backup from the Google Drive backup folder. Interactive: asks for the passphrase.
# The current data folder is moved aside, never deleted.
# CAPTAINSLOG_STORE_DIR and CAPTAINSLOG_BACKUP_DIR override the store and backup folder, for testing.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

store_dir="${CAPTAINSLOG_STORE_DIR:-$HOME/Library/Application Support/CaptainsLog}"
drive="$HOME/Google Drive"
backup_dir="${CAPTAINSLOG_BACKUP_DIR:-$drive/My Drive/CaptainsLog backups}"

fail() { echo "$*" >&2; exit 1; }

[ -t 0 ] || fail "Restore is interactive; run just restore in a terminal."
if [ -z "${CAPTAINSLOG_BACKUP_DIR:-}" ] && [ ! -d "$drive" ]; then
    fail "No Google Drive at ~/Google Drive. Install Google Drive for desktop and sign in with your work account (SSO)."
fi
[ -f "$backup_dir/identity.age" ] || fail "No backup key in $backup_dir, so there's nothing to restore from."
command -v age >/dev/null || fail "age not found. Run: brew install age"

# The app holds the store open; replacing it underneath would corrupt it. Scratch stores belong to sandboxes.
if [ -z "${CAPTAINSLOG_STORE_DIR:-}" ]; then
    while pgrep -x "Captain's Log" >/dev/null; do
        read -r -p "Quit Captain's Log (every copy), then press Return. "
    done
fi

shopt -s nullglob
backups=("$backup_dir"/CaptainsLog-*.tar.xz.age)
[ ${#backups[@]} -gt 0 ] || fail "No backups in $backup_dir"

# Newest first; names sort chronologically.
labels=()
for ((i = ${#backups[@]} - 1; i >= 0; i--)); do
    name=$(basename "${backups[i]}")
    stamp=${name#CaptainsLog-}
    stamp=${stamp%.tar.xz.age}
    labels+=("${stamp:0:10} ${stamp:11:2}:${stamp:13:2}:${stamp:15:2}  ($(( $(stat -f %z "${backups[i]}") / 1024 )) KB)")
done

echo "Backups in $backup_dir, newest first:"
PS3="Restore which? "
select label in "${labels[@]}"; do
    [ -n "${label:-}" ] && break
    echo "Pick a number from the list."
done
backup="${backups[${#backups[@]} - REPLY]}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Decrypting $(basename "$backup"). Older backups may download from Drive first."
age -d -i "$backup_dir/identity.age" "$backup" | tar -xJf - -C "$tmp"
restored="$tmp/CaptainsLog"
[ -f "$restored/CaptainsLog.store" ] || fail "The backup has no CaptainsLog.store; nothing changed."
check=$(sqlite3 "$restored/CaptainsLog.store" 'PRAGMA integrity_check;' 2>&1) || true
[ "$check" = "ok" ] || fail "The backup failed integrity_check, so nothing changed: $check"

aside="$store_dir-before-restore-$(date +%Y-%m-%dT%H%M%S)"
echo
echo "This replaces your data with the backup from ${label%%  (*}."
[ -d "$store_dir" ] && echo "Your current data folder moves to: $aside"
read -r -p "Restore? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || fail "Cancelled; nothing changed."

[ -d "$store_dir" ] && mv "$store_dir" "$aside"
mkdir -p "$(dirname "$store_dir")"
mv "$restored" "$store_dir"

echo "Restored. Open Captain's Log; it syncs GitHub and the calendar again on launch."
[ -d "$aside" ] && echo "Your previous data is in $aside. Delete it once you're happy with the restore."
true
