#!/usr/bin/env bash
set -euo pipefail

# Apply app-facing DreamCAST branding to an existing generated Android workspace.
# Repeatable: does not delete the workspace, alter package namespaces, or erase builds.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
TARGET="${1:-$ROOT/AndroidTV/DreamCAST-StreamVault}"
SOURCE_RES="$TARGET/app/src/main/res"
BRAND_RES="$ROOT/Lume/Assets.xcassets"
ICON="$BRAND_RES/AppIcon.appiconset/icon-mac-512x512@2x.png"
LOGO="$BRAND_RES/DreamCASTHeaderLogo.imageset/DreamCASTHeaderLogo.png"

if [[ ! -f "$TARGET/settings.gradle.kts" || ! -f "$SOURCE_RES/values/strings.xml" ]]; then
  echo "Missing generated Android app: $TARGET" >&2
  echo "First run bash AndroidTV/scripts/prepare-streamvault-worktree.sh" >&2
  exit 1
fi
if [[ ! -f "$ICON" || ! -f "$LOGO" ]]; then
  echo "DreamCAST tvOS artwork not found in $BRAND_RES" >&2
  exit 1
fi
if ! command -v sips >/dev/null; then
  echo "Mac 'sips' image utility is required for launcher art." >&2
  exit 1
fi

# Replace display-facing brand text in Android string resource values, not
# resource names, Kotlin packages, URL schemes, legal copyright notices, or API keys.
python3 - "$SOURCE_RES" <<'PY'
import pathlib, re, sys
base = pathlib.Path(sys.argv[1])
count = 0
files = 0
for file in base.glob('values*/strings.xml'):
    text = file.read_text(encoding='utf-8')
    # Preserve translator formatting and XML entities.
    def replace(m):
        global count
        head, body, tail = m.groups()
        if 'streamvault' not in body.lower():
            return m.group(0)
        # Never hide attribution or source/donation links.
        if any(s in body.lower() for s in (
            'davidona', 'david nashash', 'github.com/', 'ko-fi.com/', 'based on streamvault'
        )):
            return m.group(0)
        count += 1
        return head + re.sub('StreamVault', 'DreamCAST TV', body, flags=re.I) + tail
    new = re.sub(
        r'(<string\b[^>]*>)(.*?)(</string>)',
        replace,
        text,
        flags=re.DOTALL
    )
    if new != text:
        file.write_text(new, encoding='utf-8')
        files += 1
print(f'Updated {count} user-facing string entries across {files} locale files.')
PY

# Build launcher images from the approved DreamCAST assets already tracked
# in this repository. The app's existing XML/manifest resources keep their
# names, so no package or manifest migration is needed.
for density in ldpi mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  dir="$SOURCE_RES/mipmap-$density"
  [[ -d "$dir" ]] || continue
  case "$density" in
    ldpi) px=36;;
    mdpi) px=48;;
    hdpi) px=72;;
    xhdpi) px=96;;
    xxhdpi) px=144;;
    xxxhdpi) px=192;;
  esac
  for name in ic_launcher.png ic_launcher_round.png ic_launcher_foreground.png; do
    [[ -f "$dir/$name" ]] || continue
    sips -s format png -z "$px" "$px" "$ICON" --out "$dir/$name" >/dev/null
  done
done
# Use the TV logo as the leanback banner. Keep the exact resource name.
sips -s format png -z 180 320 "$LOGO" --out "$SOURCE_RES/drawable/app_banner.png" >/dev/null
# Also replace web/store preview art if present.
for file in "$SOURCE_RES/ic_launcher-web.png" "$SOURCE_RES/playstore-icon.png"; do
  [[ -f "$file" ]] && sips -s format png -z 512 512 "$ICON" --out "$file" >/dev/null
done

cat > "$TARGET/DREAMCAST_DERIVATIVE_NOTICE.md" <<'EOF'
# DreamCAST TV — Android development copy

Based on StreamVault by David Nashash (Davidona).
Original code: https://github.com/Davidona/StreamVault-IPTV
Support: https://ko-fi.com/davidona

The upstream StreamVault Source-Available License (Non-Commercial) in LICENSE
still governs this derivative. Any distributed copy must visibly credit
David Nashash / Davidona in an About/Credits screen, retain the original
GitHub and support links, identify itself as Based on StreamVault, and
publish its corresponding source under that license. Commercial use needs
prior written permission.

This development workspace is not yet suitable for public distribution:
in-app About/Credits, other hard-coded brand assets and end-to-end QA still
need review.
EOF

echo "Updated Android app-facing strings, launcher icon and TV banner in $TARGET"
echo "Next: ./gradlew :app:assembleDebug"
echo "Note: Existing installed apps need a rebuilt and reinstalled APK to show changes."
