#!/usr/bin/env bash
# Encrypts a consistent snapshot of the store into the Google Drive backup folder, then prunes old backups.
# Run by `just backup` and daily by the app. Needs `just backup-setup` once first.
# CAPTAINSLOG_BACKUP_KEEP sets how many backups to keep (default 30).
# CAPTAINSLOG_STORE_DIR, CAPTAINSLOG_DRIVE_DIR and CAPTAINSLOG_BACKUP_DIR override the store, Drive and backup folders, for testing.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

store_dir="${CAPTAINSLOG_STORE_DIR:-$HOME/Library/Application Support/CaptainsLog}"
drive="${CAPTAINSLOG_DRIVE_DIR:-$HOME/Google Drive}"
backup_dir="${CAPTAINSLOG_BACKUP_DIR:-$drive/My Drive/CaptainsLog backups}"
keep="${CAPTAINSLOG_BACKUP_KEEP:-30}"

fail() { echo "$*" >&2; exit 1; }

[[ "$keep" =~ ^[1-9][0-9]*$ ]] || fail "CAPTAINSLOG_BACKUP_KEEP must be a positive number, not '$keep'"

if [ -z "${CAPTAINSLOG_BACKUP_DIR:-}" ] && [ ! -d "$drive" ]; then
    fail "No Google Drive at $drive. Install Google Drive for desktop and sign in with your work account (SSO)."
fi
# Never encrypt to a key nobody can decrypt with.
[ -f "$backup_dir/identity.age" ] && [ -f "$backup_dir/recipient.txt" ] || fail "No backup key in $backup_dir. Run: just backup-setup"
command -v age >/dev/null || fail "age not found. Run: brew install age"
[ -f "$store_dir/CaptainsLog.store" ] || fail "No store at $store_dir"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/CaptainsLog"

# .backup copies a consistent snapshot even while the app is writing; zipping the live store and WAL wouldn't.
sqlite3 "$store_dir/CaptainsLog.store" ".backup '$tmp/CaptainsLog/CaptainsLog.store'"
sqlite3 "$tmp/CaptainsLog/CaptainsLog.store" 'PRAGMA journal_mode=DELETE;' >/dev/null
check=$(sqlite3 "$tmp/CaptainsLog/CaptainsLog.store" 'PRAGMA integrity_check;')
[ "$check" = "ok" ] || fail "Snapshot failed integrity_check: $check"
rm -f "$tmp/CaptainsLog/CaptainsLog.store-shm" "$tmp/CaptainsLog/CaptainsLog.store-wal"
[ -f "$store_dir/sync-history.json" ] && cp "$store_dir/sync-history.json" "$tmp/CaptainsLog/"

# Written under .partial and renamed, so Drive never uploads half a backup.
name="CaptainsLog-$(date +%Y-%m-%dT%H%M%S).tar.xz.age"
tar -cJf - -C "$tmp" CaptainsLog | age -R "$backup_dir/recipient.txt" -o "$backup_dir/$name.partial"
mv "$backup_dir/$name.partial" "$backup_dir/$name"
echo "Backed up to $backup_dir/$name ($(du -h "$backup_dir/$name" | cut -f1 | tr -d ' '))"

# Keep the newest $keep. Names sort chronologically, so Drive touching mtimes doesn't matter.
find "$backup_dir" -maxdepth 1 -name 'CaptainsLog-*.partial' -mtime +1 -delete
shopt -s nullglob
backups=("$backup_dir"/CaptainsLog-*.tar.xz.age)
for ((i = 0; i < ${#backups[@]} - keep; i++)); do
    rm -f "${backups[i]}"
    echo "Pruned $(basename "${backups[i]}")"
done
