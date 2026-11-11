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

# Link the Claude Code skills in skills/ into ~/.claude/skills, so they work in every project
install-skills:
    mkdir -p ~/.claude/skills
    for dir in skills/*/; do name=$(basename "$dir"); ln -sfn "$(pwd)/skills/$name" ~/.claude/skills/"$name"; echo "Linked ~/.claude/skills/$name"; done

# Open the GUI project in Xcode
gui:
    open {{xcode_project}}

# Build the working tree as a release does (app, CLI in Contents/Helpers, skills), sign it with Developer ID if this Mac has one, and install it to /Applications, and link the CLI and skills as Homebrew does. No notarization: a local build isn't quarantined
install-app:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building the app..."
    xcodebuild -quiet -project {{xcode_project}} -scheme {{app_name}} -configuration Release \
        -destination '{{test_destination}}' -derivedDataPath .build/xcode \
        -onlyUsePackageVersionsFromResolvedFile build
    echo "Building the CLI..."
    swift build -c release --only-use-versions-from-resolved-file
    local=.build/local
    built="$local/Captain's Log.app"
    rm -rf "$local" && mkdir -p "$local"
    ditto ".build/xcode/Build/Products/Release/Captain's Log.app" "$built"
    mkdir -p "$built/Contents/Helpers"
    cp {{cli_binary}} "$built/Contents/Helpers/captains-log"
    ditto skills "$built/Contents/Resources/skills"
    # A stable identity keeps Keychain and privacy grants across rebuilds; ad hoc changes with every build
    identity=$(security find-identity -v -p codesigning | sed -n -E 's/.*"(Developer ID Application: .*\({{release_team}}\))"$/\1/p' | head -1)
    if [ -z "$identity" ]; then
        echo "No Developer ID for team {{release_team}}: signing ad hoc"
        identity=-
    fi
    sign() { codesign --force --options runtime --timestamp=none --sign "$identity" "$@"; }
    sign --identifier captains-log "$built/Contents/Helpers/captains-log"
    sign "$built"
    codesign --verify --strict --deep "$built"
    # Only the copy needs admin rights; the build stays user-owned
    app="/Applications/Captain's Log.app"
    sudo=""
    if [ ! -w /Applications ] || { [ -e "$app" ] && [ ! -w "$app" ]; }; then
        echo "Writing to /Applications needs admin rights (grant them with the Privileges app)"
        sudo="sudo"
    fi
    running=false
    pkill -x "Captain's Log" && running=true || true
    $sudo rm -rf "$app"
    $sudo ditto "$built" "$app"
    # The same links Homebrew makes, so a source install needs nothing else
    ln -sf "$app/Contents/Helpers/captains-log" /opt/homebrew/bin/captains-log
    "$app/Contents/Helpers/captains-log" skills install >/dev/null
    echo "Installed Captain's Log $(git describe --tags --always --dirty) to /Applications, with the CLI and skills"
    if $running; then open "$app"; fi

# Build <treeish> unsigned into <dir>/Captain's Log.app, with the CLI in Contents/Helpers and the skills in Contents/Resources/skills. It always builds at the same path, which the linker hashes into each binary's UUID, so a release can be rebuilt byte for byte from its tag
_release-assemble treeish dir:
    #!/usr/bin/env bash
    set -euo pipefail
    build=/tmp/captainslog-release
    src="$build/CaptainsLog"
    mkdir -p "{{dir}}" && out=$(cd "{{dir}}" && pwd)
    app="$out/Captain's Log.app"
    rm -rf "$build" "$app" && mkdir -p "$src"
    git archive "{{treeish}}" | tar -x -C "$src"
    cd "$src"
    echo "Building the app..."
    xcodebuild -quiet -project {{xcode_project}} -scheme {{app_name}} -configuration Release \
        -destination '{{test_destination}}' -derivedDataPath .build/xcode-dist \
        -onlyUsePackageVersionsFromResolvedFile build CODE_SIGNING_ALLOWED=NO
    echo "Building the CLI..."
    swift build -c release --scratch-path .build/cli-dist --only-use-versions-from-resolved-file
    ditto ".build/xcode-dist/Build/Products/Release/Captain's Log.app" "$app"
    mkdir -p "$app/Contents/Helpers"
    cp .build/cli-dist/release/captains-log "$app/Contents/Helpers/captains-log"
    ditto skills "$app/Contents/Resources/skills"
    cd / && rm -rf "$build"

# Assemble the app at the version in Sources/captains-log/Version.swift from the tracked files, uncommitted changes included, sign it with Developer ID and notarize it, into .build/dist. Needs the notarytool profile `captainslog`
release-build:
    #!/usr/bin/env bash
    set -euo pipefail
    xcrun notarytool history --keychain-profile captainslog >/dev/null
    version=$(sed -n -E 's/^let cliVersion = "(.*)"$/\1/p' Sources/captains-log/Version.swift)
    identity="Developer ID Application"
    dist=.build/dist
    app="$dist/Captain's Log.app"
    rm -rf "$dist"
    # A commit of the working tree that touches nothing, so `release` builds the version bump it's about to commit
    tree=$(git stash create)
    {{just_executable()}} _release-assemble "${tree:-HEAD}" "$dist"
    app_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
    [ "$app_version" = "$version" ] || { echo "The app is $app_version (MARKETING_VERSION) but the CLI is $version (Version.swift)"; exit 1; }
    # Inside out: nested code first, the app last
    sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
    sign --identifier captains-log "$app/Contents/Helpers/captains-log"
    sign "$app"
    codesign --verify --strict --deep "$app"
    echo "Notarizing (takes a few minutes)..."
    ditto -c -k --keepParent "$app" "$dist/notarize.zip"
    xcrun notarytool submit "$dist/notarize.zip" --keychain-profile captainslog --wait
    rm "$dist/notarize.zip"
    xcrun stapler staple "$app"
    spctl --assess --type execute "$app"
    ditto -c -k --keepParent "$app" "$dist/CaptainsLog-$version.zip"
    ls -1 "$dist/CaptainsLog-$version.zip"

# Rebuild release v<version> from its tag, with the tag's own build step, and compare it with the published zip. Signatures are normalised, and BuildMachineOSBuild ignored. Needs the tag locally and the Xcode the release was built with
verify-release version:
    #!/usr/bin/env bash
    set -euo pipefail
    tag="v{{version}}"
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "No tag $tag here: run git fetch --tags"; exit 1; }
    git show "$tag:justfile" | grep -q '^_release-assemble' || { echo "$tag predates reproducible releases"; exit 1; }
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    gh release download "$tag" --pattern "CaptainsLog-{{version}}.zip" --dir "$work"
    mkdir "$work/published" && ditto -x -k "$work/CaptainsLog-{{version}}.zip" "$work/published"
    built_with=$(/usr/libexec/PlistBuddy -c "Print DTXcodeBuild" "$work/published/Captain's Log.app/Contents/Info.plist")
    have=$(xcodebuild -version | sed -n 's/^Build version //p')
    [ "$built_with" = "$have" ] || { echo "$tag was built with Xcode build $built_with, but this Mac has $have"; exit 1; }
    git show "$tag:justfile" > "$work/justfile"
    {{just_executable()}} --justfile "$work/justfile" --working-directory "$PWD" _release-assemble "$tag" "$work/rebuilt"
    for app in "$work/published/Captain's Log.app" "$work/rebuilt/Captain's Log.app"; do
        # Removing a signature leaves sizes that depend on it, so give every binary the same ad hoc one
        find "$app" -type f -print0 | while IFS= read -r -d '' f; do
            file -b "$f" | grep -q Mach-O || continue
            cp "$f" "$work/macho"
            codesign --remove-signature "$work/macho"
            codesign --sign - --identifier normalised "$work/macho"
            mv "$work/macho" "$f"
        done
        find "$app" -name _CodeSignature -type d -prune -exec rm -rf {} +
        rm -f "$app/Contents/CodeResources"
        find "$app" -name Info.plist -exec plutil -remove BuildMachineOSBuild {} \; 2>/dev/null || true
    done
    diff -r "$work/published" "$work/rebuilt"
    echo "$tag matches its tag's source"

# Set the app and CLI to <version>, release-build, point the cask at it, then commit, tag and push it, publish GitHub release v<version> and the cask. Needs a clean main level with origin
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    version="{{version}}"
    tag="v$version"
    files=(captainslog/captainslog.xcodeproj/project.pbxproj Sources/captains-log/Version.swift homebrew/captains-log.rb)
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
    sha=$(shasum -a 256 ".build/dist/CaptainsLog-$version.zip" | cut -d' ' -f1)
    sed -i '' -E -e "s/^  version \".*\"$/  version \"$version\"/" -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" "${files[2]}"
    git commit --quiet -m "Release $tag" -- "${files[@]}"
    trap - EXIT
    git tag "$tag"
    git push --quiet origin main "$tag"
    gh release create "$tag" --verify-tag --title "$tag" --generate-notes \
        .build/dist/CaptainsLog-$version.zip
    {{just_executable()}} publish-cask

# Copy homebrew/captains-log.rb into github.com/nindalf/homebrew-tap and push it. `release` runs it; rerun it if that step failed
publish-cask:
    #!/usr/bin/env bash
    set -euo pipefail
    version=$(sed -n -E 's/^  version "(.*)"$/\1/p' homebrew/captains-log.rb)
    gh release view "v$version" >/dev/null || { echo "There's no GitHub release v$version for the cask to point at"; exit 1; }
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    gh repo clone nindalf/homebrew-tap "$work/tap" -- --quiet
    mkdir -p "$work/tap/Casks"
    cp homebrew/captains-log.rb "$work/tap/Casks/captains-log.rb"
    cd "$work/tap"
    [ -n "$(git status --porcelain)" ] || { echo "The tap already has captains-log $version"; exit 0; }
    git add Casks/captains-log.rb
    git commit --quiet -m "captains-log $version"
    git push --quiet
    echo "Published captains-log $version to nindalf/homebrew-tap"

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

# Encrypt a snapshot of the real store (safe while the app is running) into Google Drive. Run backup-setup once first
backup:
    swift build -q --product captains-log
    .build/debug/captains-log backup --pretty

# Create the backup key in Google Drive, protected by a passphrase. Once per person; refuses if the key exists
backup-setup:
    swift build -q --product captains-log
    .build/debug/captains-log backup-setup

# Replace the real store with a backup from Google Drive (captains-log restore). Asks for the passphrase; moves the current data aside
restore:
    swift build -q --product captains-log
    .build/debug/captains-log restore

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
