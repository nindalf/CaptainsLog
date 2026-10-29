app_name := "captainslog"
xcode_project := "captainslog/captainslog.xcodeproj"
data_dir := env("HOME") / "Library/Application Support/CaptainsLog"
db_path := data_dir / "CaptainsLog.store"
cli_binary := ".build/release/captains-log"
test_destination := "platform=macOS,arch=arm64"
# Apple team whose Developer ID certificate signs release builds
release_team := env("CAPTAINSLOG_TEAM_ID", "78T545JWUD")

# List available recipes
default:
    @just --list

# Build the CLI in release mode and link it into /opt/homebrew/bin. Rerun after CLI changes
install-cli:
    swift build -c release
    ln -sf "$(pwd)/{{cli_binary}}" /opt/homebrew/bin/captains-log
    @echo "Installed captains-log to /opt/homebrew/bin/captains-log"

# Link the Claude Code skills in skills/ into ~/.claude/skills, so they work in every project
install-skills:
    mkdir -p ~/.claude/skills
    for dir in skills/*/; do name=$(basename "$dir"); ln -sfn "$(pwd)/skills/$name" ~/.claude/skills/"$name"; echo "Linked ~/.claude/skills/$name"; done

# Open the GUI project in Xcode
gui:
    open {{xcode_project}}

# Build a Release copy and install it to /Applications
install-app:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building Release..."
    xcodebuild -quiet -project {{xcode_project}} -scheme {{app_name}} -configuration Release \
        -destination '{{test_destination}}' -derivedDataPath .build/xcode build
    # Only the copy needs admin rights; the build stays user-owned
    app="/Applications/Captain's Log.app"
    sudo=""
    if [ ! -w /Applications ] || { [ -e "$app" ] && [ ! -w "$app" ]; }; then
        echo "Writing to /Applications needs admin rights (grant them with the Privileges app)"
        sudo="sudo"
    fi
    pkill -x "Captain's Log" || true
    $sudo rm -rf "$app"
    $sudo ditto ".build/xcode/Build/Products/Release/Captain's Log.app" "$app"
    echo "Installed Captain's Log to /Applications"

# Build the app and CLI at the version in Sources/captains-log/Version.swift, sign with Developer ID and notarize, and copy the committed skills and getting-started guide, into .build/dist. Needs the notarytool profile `captainslog`
release-build:
    #!/usr/bin/env bash
    set -euo pipefail
    xcrun notarytool history --keychain-profile captainslog >/dev/null
    version=$(sed -n -E 's/^let cliVersion = "(.*)"$/\1/p' Sources/captains-log/Version.swift)
    identity="Developer ID Application"
    dist=.build/dist
    rm -rf "$dist" && mkdir -p "$dist/stage"
    echo "Building the app..."
    xcodebuild -quiet -project {{xcode_project}} -scheme {{app_name}} -configuration Release \
        -destination '{{test_destination}}' -derivedDataPath .build/xcode-dist build \
        DEVELOPMENT_TEAM={{release_team}} CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" \
        ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp
    ditto ".build/xcode-dist/Build/Products/Release/Captain's Log.app" "$dist/stage/Captain's Log.app"
    app_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$dist/stage/Captain's Log.app/Contents/Info.plist")
    [ "$app_version" = "$version" ] || { echo "The app is $app_version (MARKETING_VERSION) but the CLI is $version (Version.swift)"; exit 1; }
    echo "Building the CLI..."
    swift build -c release
    cp {{cli_binary}} "$dist/stage/captains-log"
    codesign --force --options runtime --timestamp --sign "$identity" --identifier captains-log "$dist/stage/captains-log"
    echo "Notarizing (takes a few minutes)..."
    ditto -c -k "$dist/stage" "$dist/notarize.zip"
    xcrun notarytool submit "$dist/notarize.zip" --keychain-profile captainslog --wait
    xcrun stapler staple "$dist/stage/Captain's Log.app"
    ditto -c -k --keepParent "$dist/stage/Captain's Log.app" "$dist/CaptainsLog-$version.zip"
    ditto -c -k "$dist/stage/captains-log" "$dist/captains-log-$version.zip"
    git archive --format=zip -o "$dist/captains-log-skills-$version.zip" HEAD:skills
    git show HEAD:docs/getting-started.md > "$dist/getting-started.md"
    rm "$dist/notarize.zip"
    ls -1 "$dist"/*.zip "$dist/getting-started.md"

# Set the app and CLI to <version>, release-build, then commit, tag and push it and publish GitHub release v<version>. Needs a clean main level with origin
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    version="{{version}}"
    tag="v$version"
    files=(captainslog/captainslog.xcodeproj/project.pbxproj Sources/captains-log/Version.swift)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version should look like 1.2.3"; exit 1; }
    [ "$(git branch --show-current)" = main ] || { echo "Release from main"; exit 1; }
    # Untracked files count: the app target picks up anything in its folder
    [ -z "$(git status --porcelain)" ] || { echo "Commit or stash everything first, so the build matches the commit"; exit 1; }
    git fetch --quiet --tags origin main
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main isn't level with origin/main"; exit 1; }
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then echo "$tag already exists"; exit 1; fi
    # Until the commit, a failure puts the version files back
    trap 'git checkout -- "${files[@]}"' EXIT
    sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/" "${files[0]}"
    sed -i '' -E "s/^let cliVersion = \".*\"$/let cliVersion = \"$version\"/" "${files[1]}"
    {{just_executable()}} release-build
    git commit --quiet -m "Release $tag" -- "${files[@]}"
    trap - EXIT
    git tag "$tag"
    git push --quiet origin main "$tag"
    gh release create "$tag" --verify-tag --title "$tag" --generate-notes \
        .build/dist/CaptainsLog-$version.zip .build/dist/captains-log-$version.zip \
        .build/dist/captains-log-skills-$version.zip .build/dist/getting-started.md

# Run the fast unit tests (Swift Testing, in the app host)
test:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v xcbeautify >/dev/null || { echo "xcbeautify not found — run: brew install xcbeautify"; exit 1; }
    set -o pipefail
    NSUnbufferedIO=YES xcodebuild test \
        -project {{xcode_project}} -scheme {{app_name}} \
        -destination '{{test_destination}}' \
        -testLanguage en -testRegion GB \
        -only-testing:captainslogTests \
        2>&1 | xcbeautify

# Run a subset by name, e.g. `just test-only PersonMergeTests`
test-only PATTERN:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v xcbeautify >/dev/null || { echo "xcbeautify not found — run: brew install xcbeautify"; exit 1; }
    set -o pipefail
    NSUnbufferedIO=YES xcodebuild test \
        -project {{xcode_project}} -scheme {{app_name}} \
        -destination '{{test_destination}}' \
        -testLanguage en -testRegion GB \
        -only-testing:captainslogTests/{{PATTERN}} \
        2>&1 | xcbeautify

# Open the local SQLite database in sqlite3
db:
    sqlite3 "{{db_path}}"

# Clear local SwiftData store (asks for confirmation)
clear-local-state:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "{{data_dir}}" ]; then
        echo "No data directory found at {{data_dir}}"
        exit 0
    fi
    echo "This will delete all local data at:"
    echo "  {{data_dir}}"
    echo ""
    ls -lh "{{data_dir}}/"
    echo ""
    read -p "Are you sure? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "{{data_dir}}"
        echo "Deleted."
    else
        echo "Cancelled."
    fi

# Encrypt a snapshot of the real store (safe while the app is running) into Google Drive. Run backup-setup once first
backup:
    bash Sources/CaptainsLogKit/Backup/backup.sh

# Create the backup key in Google Drive, protected by a passphrase. Once per person; refuses if the key exists
backup-setup:
    bash Sources/CaptainsLogKit/Backup/backup-setup.sh

# Replace the real store with a backup from Google Drive. Asks for the passphrase; moves the current data aside
restore:
    bash scripts/restore.sh

# Show local data store info
data-info:
    @echo "Data directory: {{data_dir}}"
    @if [ -d "{{data_dir}}" ]; then ls -lh "{{data_dir}}/"; else echo "No data directory found."; fi

# Check that required external tools are available
check-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    ok=true
    for tool in gh gws age claude swift xcodebuild xcbeautify; do
        if command -v "$tool" &>/dev/null; then
            printf "%-12s %s\n" "$tool" "$(command -v $tool)"
        else
            printf "%-12s MISSING\n" "$tool"
            ok=false
        fi
    done
    $ok || { echo ""; echo "Some tools are missing."; exit 1; }

# Build a Debug app into .build/xcode for `just ui` to drive
ui-build:
    xcodebuild -quiet -project {{xcode_project}} -scheme {{app_name}} -configuration Debug \
        -destination '{{test_destination}}' -derivedDataPath .build/xcode build

# Wipe the UI sandbox store and reseed it with demo data (the real store is untouched)
ui-seed:
    rm -rf .build/ui/store
    CAPTAINSLOG_STORE_DIR="$(pwd)/.build/ui/store" bash scripts/seed-data.sh

# Drive the sandboxed app: launch, quit, shot, tree, click, dclick, rclick, drag, press, key, type
ui *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .build/ui
    if [ ! -x .build/ui/ui ] || [ scripts/ui.swift -nt .build/ui/ui ]; then
        swiftc -O scripts/ui.swift -o .build/ui/ui
    fi
    .build/ui/ui {{ARGS}}

# Claude's own copy of the sandbox (app + store in .build/ui-claude), so it doesn't collide with the user's. Run ui-build first.
ui-private-seed:
    rm -rf .build/ui-claude
    mkdir -p .build/ui-claude
    ditto ".build/xcode/Build/Products/Debug/Captain's Log.app" ".build/ui-claude/Captain's Log.app"
    CAPTAINSLOG_STORE_DIR="$(pwd)/.build/ui-claude/store" bash scripts/seed-data.sh

# Drive Claude's private copy; same commands as `just ui`
ui-private *ARGS:
    UI_APP="$(pwd)/.build/ui-claude/Captain's Log.app" CAPTAINSLOG_STORE_DIR="$(pwd)/.build/ui-claude/store" just ui {{ARGS}}

# Build, reseed the UI sandbox with demo data, launch it, and start Claude Code on its store. Args go to claude, e.g. just demo /weekly-review
demo *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    store="$(pwd)/.build/ui/store"
    just ui quit || true
    just ui-build
    just ui-seed
    just ui launch
    # Outside the repo, so Claude doesn't load this project's CLAUDE.md or memory. The skills are global.
    dir="${TMPDIR:-/tmp}/captains-log-demo"
    mkdir -p "$dir"
    cd "$dir"
    CAPTAINSLOG_STORE_DIR="$store" claude {{ARGS}}

# Dump every flavour on the clipboard to /tmp/pbdump (check what a Copy actually wrote)
pbdump:
    swift scripts/pbdump.swift

# Clean Swift build artifacts
clean:
    swift package clean
    @echo "Cleaned .build/"

# Resolve Swift package dependencies
resolve:
    swift package resolve

# Show package dependency graph
deps:
    swift package show-dependencies --format text
