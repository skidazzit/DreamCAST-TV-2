#!/usr/bin/env bash
set -euo pipefail

# Produce a local editable DreamCAST-branded worktree from the pinned upstream.
# Never edit the upstream submodule or commit bundled provider credentials.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$ANDROID_DIR/StreamVault"
TARGET="$ANDROID_DIR/DreamCAST-StreamVault"
PIN="bc32f389b37969e387df83df032d2a8235024222"

if [[ ! -f "$SOURCE/settings.gradle.kts" ]]; then
  echo "Missing upstream submodule. Run: git submodule update --init --recursive" >&2
  exit 1
fi
CURRENT="$(git -C "$SOURCE" rev-parse HEAD)"
if [[ "$CURRENT" != "$PIN" ]]; then
  echo "Unexpected StreamVault version: $CURRENT; expected $PIN" >&2
  exit 1
fi
if [[ -e "$TARGET" ]]; then
  echo "Target already exists: $TARGET. Keep local changes safe; move or remove it manually." >&2
  exit 1
fi

mkdir -p "$TARGET"
# Copy the full source tree but not its Git admin folder or prior build outputs.
rsync -a --exclude='.git' --exclude='.gradle' --exclude='build' --exclude='local.properties' \
  --exclude='keystore.properties' "$SOURCE/" "$TARGET/"

# Change the Android launcher title in all existing string translations.
# Other upstream naming and code references are intentionally left in place
# until the related feature can be tested.
python3 - "$TARGET" <<'PY'
from pathlib import Path
import re
import sys
root = Path(sys.argv[1])
changed = 0
for file in (root / 'app/src/main/res').glob('values*/strings.xml'):
    data = file.read_text(encoding='utf-8')
    new_data, n = re.subn(
        r'(<string\s+name="app_name"[^>]*>).*?(</string>)',
        r'\g<1>DreamCAST TV 2\g<2>',
        data,
        count=1,
        flags=re.DOTALL
    )
    if n:
        file.write_text(new_data, encoding='utf-8')
        changed += 1
if changed == 0:
    raise SystemExit('Could not find app_name string; upstream resource layout changed.')
print(f'Updated app title in {changed} resource file(s).')
PY

cat > "$TARGET/DREAMCAST_DERIVATIVE_NOTICE.md" <<'EOF'
# DreamCAST TV 2 (Android) — development copy

Based on StreamVault by David Nashash (Davidona).
Original source: https://github.com/Davidona/StreamVault-IPTV
Support: https://ko-fi.com/davidona

The upstream StreamVault Source-Available License (Non-Commercial) remains
in LICENSE. Commercial uses require prior written permission. If modified
software is distributed, publish the complete matching source under the exact
license and show this credit and both links inside the app's About/Credits UI
as well as in public distribution pages.

This generated workspace is not a finished, licensed-to-distribute
DreamCAST Android release. Its About/Credits screen and all remaining user
visible branding must be completed before distribution.
EOF

echo "Prepared source at: $TARGET"
echo "Open $TARGET in Android Studio, then sync and build."
echo "The Gradle project is StreamVault-based; only the launcher app_name is rebranded so far."
