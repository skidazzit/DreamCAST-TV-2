#!/bin/bash
# Restore the three local Swift packages required by DreamCAST-iOS.xcodeproj.
# Run: bash Scripts/prepare-ios-local-packages.sh
#
# Xcode resolves ../LumeEngine, ../LumeRecorder/Kit, and
# ../LumeCloud/LumeCloudKit relative to this repository. These live outside
# the fork and cannot be fetched by git pull of DreamCAST TV 2.
# This script does not edit Xcode, delete folders, or overwrite local work.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PARENT="$(dirname "$ROOT")"

if [[ ! -f "$ROOT/DreamCAST-iOS.xcodeproj/project.pbxproj" ]]; then
    echo "ERROR: Expected DreamCAST-iOS.xcodeproj in $ROOT" >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is required to fetch the local packages." >&2
    exit 1
fi

ensure_package() {
    local label="$1"
    local directory="$2"
    local manifest="$3"
    local source="$4"
    local destination="$PARENT/$directory"

    if [[ -f "$destination/$manifest" ]]; then
        echo "[OK] $label: $destination/$manifest"
        return
    fi

    if [[ -e "$destination" || -L "$destination" ]]; then
        echo "ERROR: $destination exists but $manifest is missing." >&2
        echo "Keep your existing files. Move or repair this folder yourself, then rerun." >&2
        exit 1
    fi

    echo "[CLONE] $label -> $destination"
    git clone --depth 1 "$source" "$destination"
    if [[ ! -f "$destination/$manifest" ]]; then
        echo "ERROR: Clone finished without the required $manifest" >&2
        exit 1
    fi
}

ensure_package "LumeEngine" "LumeEngine" "Package.swift" "https://github.com/bilipp/LumeEngine.git"
ensure_package "LumeRecorderKit" "LumeRecorder" "Kit/Package.swift" "https://github.com/bilipp/LumeRecorder.git"
ensure_package "LumeCloudKit" "LumeCloud" "LumeCloudKit/Package.swift" "https://github.com/bilipp/LumeCloud.git"

if xcrun --find swift >/dev/null 2>&1; then
    for path in "$PARENT/LumeEngine" "$PARENT/LumeRecorder/Kit" "$PARENT/LumeCloud/LumeCloudKit"; do
        echo "[CHECK] $path"
        xcrun swift package dump-package --package-path "$path" >/dev/null
    done
else
    echo "Swift toolchain not selected. The package manifests are present."
    echo "Select Xcode in xcode-select or set DEVELOPER_DIR before resolving packages."
fi

echo
echo "[READY] All three local package manifests exist beside $ROOT."
echo "Open DreamCAST-iOS.xcodeproj, then use File > Packages > Resolve Package Versions."
echo "The first resolve can download the pinned FFmpeg binary for LumeEngine."
