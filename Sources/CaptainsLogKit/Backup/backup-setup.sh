#!/usr/bin/env bash
# Creates the backup key in the Google Drive backup folder: identity.age, the private key encrypted with a
# passphrase, and recipient.txt, the public key the daily backup encrypts to. Run once, by `just backup-setup`
# (asks for the passphrase) or by the app's Settings with --passphrase-stdin (reads one line from stdin).
# CAPTAINSLOG_DRIVE_DIR and CAPTAINSLOG_BACKUP_DIR override the Drive and backup folders, for testing.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

drive="${CAPTAINSLOG_DRIVE_DIR:-$HOME/Google Drive}"
backup_dir="${CAPTAINSLOG_BACKUP_DIR:-$drive/My Drive/CaptainsLog backups}"

fail() { echo "$*" >&2; exit 1; }

passphrase=""
interactive=1
if [ "${1:-}" = "--passphrase-stdin" ]; then
    interactive=""
    IFS= read -r passphrase || true
    # age generates and prints a passphrase when given an empty one.
    [ -n "$passphrase" ] || fail "Empty passphrase."
fi

if [ -z "${CAPTAINSLOG_BACKUP_DIR:-}" ] && [ ! -d "$drive" ]; then
    fail "No Google Drive at $drive. Install Google Drive for desktop and sign in with your work account (SSO)."
fi
# A new key would make every existing backup unreadable.
[ -e "$backup_dir/identity.age" ] && fail "$backup_dir/identity.age already exists. Backups are set up; not replacing the key."
command -v age >/dev/null && command -v age-keygen >/dev/null || fail "age not found. Run: brew install age"

if [ -n "$interactive" ]; then
    echo "Backups are encrypted with a key that is itself protected by a passphrase."
    echo "If you forget the passphrase, every backup is unreadable. Nobody can recover it."
    echo
fi

mkdir -p "$backup_dir"
# The private key only ever exists in memory unencrypted.
identity=$(age-keygen 2>/dev/null)
recipient=$(printf '%s\n' "$identity" | age-keygen -y)

if [ -n "$interactive" ]; then
    printf '%s\n' "$identity" | age -p -o "$backup_dir/identity.age"
else
    # age reads passphrases only from a terminal, so script(1) gives it one. The key reaches age through a
    # fifo, so it never touches the disk; stdin is the terminal.
    tmp=$(mktemp -d)
    writer=""
    trap '[ -n "$writer" ] && kill "$writer" 2>/dev/null; rm -rf "$tmp"' EXIT
    mkfifo -m 600 "$tmp/identity"
    printf '%s\n' "$identity" > "$tmp/identity" &
    writer=$!
    if ! printf '%s\n%s\n' "$passphrase" "$passphrase" | script -q /dev/null age -p -o "$backup_dir/identity.age" "$tmp/identity" >/dev/null; then
        rm -f "$backup_dir/identity.age"
        fail "age failed to encrypt the key."
    fi
    writer=""
    # Decrypt it straight back, so a key that doesn't open with this passphrase is never left in place.
    check=$(printf '%s\n' "$passphrase" | script -q /dev/null sh -c 'age -d "$1" | age-keygen -y' _ "$backup_dir/identity.age" 2>/dev/null | grep -o 'age1[0-9a-z]*' || true)
    if [ "$check" != "$recipient" ]; then
        rm -f "$backup_dir/identity.age"
        fail "The new key didn't decrypt with the passphrase. Nothing was saved; try again."
    fi
fi
unset identity passphrase
printf '%s\n' "$recipient" > "$backup_dir/recipient.txt"
chmod 444 "$backup_dir/identity.age" "$backup_dir/recipient.txt"

echo "Backup key created in $backup_dir"
[ -n "$interactive" ] && echo "Run: just backup"
exit 0
