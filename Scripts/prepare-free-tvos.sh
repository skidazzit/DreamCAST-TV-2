#!/usr/bin/env bash
# Free Apple Personal Team setup for DreamCAST TV 2.
# Changes only this checkout's Xcode project, never a GitHub or device setting.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/DreamCAST-tvOS.xcodeproj/project.pbxproj"
ACTION="${1:---prepare}"

if [[ ! -f "$PROJECT" ]]; then
  echo "ERROR: DreamCAST-tvOS.xcodeproj was not found beside Scripts/." >&2
  exit 1
fi

modify_top_shelf() {
  python3 - "$PROJECT" "$ACTION" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
action = sys.argv[2]
src = path.read_text()
# Only change the app's two references. Do not remove the extension target.
extension_embed = '\t\t\t\tC6BD5701000000000000F003 /* LumeTopShelf.appex in Embed Foundation Extensions */,\n'
extension_dependency = '\t\t\t\tC6BD5701000000000000F007 /* PBXTargetDependency */,\n'
widget_embed = '\t\t\t\tC6AA310B2FDD00020000AB0B /* LumeWidgets.appex in Embed Foundation Extensions */,\n'
widget_dependency = '\t\t\t\tC6AA310E2FDD00020000AB0E /* PBXTargetDependency */,\n'

if action == '--prepare':
    for needle, label in [
        (extension_embed, "Top Shelf embed"),
        (extension_dependency, "Top Shelf target dependency")
    ]:
        if src.count(needle) > 1:
            sys.exit(f"ERROR: Multiple {label} references; project not changed.")
    for needle in [extension_embed, extension_dependency]:
        src = src.replace(needle, '')
    result = "Top Shelf removed from the local app build."
elif action == '--restore-top-shelf':
    if extension_embed not in src:
        if src.count(widget_embed) != 1:
            sys.exit("ERROR: Cannot locate embed anchor; project not changed.")
        src = src.replace(widget_embed, widget_embed + extension_embed, 1)
    if extension_dependency not in src:
        if src.count(widget_dependency) != 1:
            sys.exit("ERROR: Cannot locate dependency anchor; project not changed.")
        src = src.replace(widget_dependency, widget_dependency + extension_dependency, 1)
    result = "Top Shelf dependency and extension embedding restored."
else:
    sys.exit(f"Unknown option: {action}. Use --prepare or --restore-top-shelf.")

if src != path.read_text():
    path.write_text(src)
print(result)
PY
}

if [[ "$ACTION" == "--restore-top-shelf" ]]; then
  modify_top_shelf
  echo "Your local signing choices were not changed."
  exit 0
fi
if [[ "$ACTION" != "--prepare" ]]; then
  echo "Usage: bash Scripts/prepare-free-tvos.sh [--prepare|--restore-top-shelf]" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: Git is required to retrieve local Swift packages." >&2
  exit 1
fi

# Xcode references these Swift packages as siblings of the app checkout.
# Never replace an existing clone or reset its branch.
ensure_package() {
  local name="$1" manifest="$2"
  local destination="$(dirname "$ROOT")/$name"
  if [[ ! -d "$destination" ]]; then
    echo "Cloning $name next to $(basename "$ROOT")..."
    git clone --depth 1 "https://github.com/bilipp/${name}.git" "$destination"
  else
    echo "Keeping existing $name at $destination"
  fi
  if [[ ! -f "$destination/$manifest" ]]; then
    echo "ERROR: Missing $destination/$manifest" >&2
    echo "Move the incomplete folder aside, then run this script again." >&2
    exit 1
  fi
}
ensure_package "LumeEngine" "Package.swift"
ensure_package "LumeRecorder" "Kit/Package.swift"
ensure_package "LumeCloud" "LumeCloudKit/Package.swift"

modify_top_shelf

cat <<'MESSAGE'

Local package paths prepared:
  ../LumeEngine
  ../LumeRecorder/Kit
  ../LumeCloud/LumeCloudKit

IN XCODE:
  1. Select the Lume app target > Signing & Capabilities.
  2. Select your own Personal Team; turn on Automatically manage signing.
     Change the app bundle identifier only if Xcode reports a conflict.
  3. Product > Scheme > Edit Scheme > Run > Build Configuration: Sideload.
  4. File > Packages > Reset Package Caches, then Resolve Package Versions.
  5. Select your Apple TV and run the build again.

The Top Shelf target and all source files remain in GitHub.
To restore Top Shelf embedding for a paid-team build:
  bash Scripts/prepare-free-tvos.sh --restore-top-shelf

Keep your local signing changes and Team ID out of Git commits.
MESSAGE
