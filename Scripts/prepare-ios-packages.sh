#!/usr/bin/env bash
# Repair the local Swift package layout for DreamCAST TV's iOS Xcode project.
# Safe to repeat: never replaces a package checkout, resets branches, or edits signing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/DreamCAST-iOS.xcodeproj"
if [[ ! -d "$PROJECT" ]]; then
  echo "ERROR: DreamCAST-iOS.xcodeproj not found at $PROJECT" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: Git is required." >&2
  exit 1
fi

# Local Xcode package references are relative to this repo, not to the
# project file's current working directory.
ensure_package() {
  local repo_name="$1"
  local manifest="$2"
  local dest="$(dirname "$ROOT")/$repo_name"

  if [[ ! -e "$dest" ]]; then
    echo "Downloading missing $repo_name checkout..."
    git clone --depth 1 "https://github.com/bilipp/${repo_name}.git" "$dest"
  else
    echo "Reusing $dest"
  fi
  if [[ ! -f "$dest/$manifest" ]]; then
    echo "ERROR: Expected $dest/$manifest" >&2
    echo "A folder exists but the Swift package is missing. Check its contents; the script will not delete it." >&2
    exit 1
  fi
  echo "OK: $dest/$manifest"
}

ensure_package "LumeEngine" "Package.swift"
ensure_package "LumeRecorder" "Kit/Package.swift"
ensure_package "LumeCloud" "LumeCloudKit/Package.swift"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

echo ""
echo "Checking Swift package manifests..."
for package in \
  "$(dirname "$ROOT")/LumeEngine" \
  "$(dirname "$ROOT")/LumeRecorder/Kit" \
  "$(dirname "$ROOT")/LumeCloud/LumeCloudKit"; do
  xcrun swift package dump-package --package-path "$package" >/dev/null
  echo "OK: $package"
done

echo ""
echo "Resolving Swift packages for DreamCAST-iOS..."
xcodebuild -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme DreamCAST-iOS

echo ""
echo "Package resolution finished. Open DreamCAST-iOS.xcodeproj in Xcode."
echo "If old package errors remain, use File > Packages > Reset Package Caches,"
echo "then File > Packages > Resolve Package Versions and rebuild."
echo "Your signing configuration and package checkouts were not changed."
