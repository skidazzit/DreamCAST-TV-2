#!/bin/sh
#
# inject-env.sh
#
# Reads key/value pairs from the repo-root .env file and injects the ones the
# app needs into the built product's Info.plist. This keeps secrets (like the
# TMDB token) out of source control while still making them available at
# runtime via Bundle.main.object(forInfoDictionaryKey:).
#
# Runs as the final build phase, after Info.plist processing and before
# codesigning. If .env is absent or a key is missing, the build continues —
# the dependent feature simply degrades (e.g. the Trending row hides).

set -eu

ENV_FILE="${SRCROOT}/.env"
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

# Finder may hide the extension on a TextEdit document named ".env.txt".
# Prefer the exact .env file and only accept .env.txt if that file is absent.
# Never show the contents of either file in build logs.
if [ ! -f "$ENV_FILE" ] && [ -f "${SRCROOT}/.env.txt" ]; then
    ENV_FILE="${SRCROOT}/.env.txt"
    echo "warning: using .env.txt (Finder may have hidden .txt); rename it to .env for standard builds"
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "warning: .env not found at ${SRCROOT}/.env — secrets not injected"
    echo "warning: In Terminal run: ls -la \"${SRCROOT}\"/.env*"
    ENV_FILE="/dev/null"
fi

if [ ! -r "$ENV_FILE" ]; then
    echo "warning: cannot read $ENV_FILE — check file permissions"
    ENV_FILE="/dev/null"
fi

# TextEdit can save Rich Text even when the name looks like .env. The loader
# requires KEY=value lines, not an RTF document.
if LC_ALL=C head -c 5 "$ENV_FILE" | grep -qF '{\rtf'; then
    echo "warning: $ENV_FILE is Rich Text (RTF); save as plain text .env"
    ENV_FILE="/dev/null"
fi

if [ ! -f "$PLIST" ]; then
    echo "warning: Info.plist not found at $PLIST — secrets not injected"
    exit 0
fi

# Reads a value from .env: ignores comments/blank lines, trims whitespace and
# optional surrounding quotes, and strips stray carriage returns.
read_env() {
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$ENV_FILE" | head -n1 \
        | sed -E "s/^[^=]*=[[:space:]]*//" \
        | sed -E "s/^\"(.*)\"$/\1/" \
        | sed -E "s/^'(.*)'$/\1/" \
        | tr -d '\r'
}

# Sets (or adds) a string key in the built Info.plist.
set_plist() {
    key="$1"
    value="$2"
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST"
}

TMDB_ACCESS_TOKEN="$(read_env TMDB_ACCESS_TOKEN)"
if [ -n "$TMDB_ACCESS_TOKEN" ]; then
    set_plist TMDBAccessToken "$TMDB_ACCESS_TOKEN"
    echo "Injected TMDB_ACCESS_TOKEN into Info.plist"
else
    echo "warning: TMDB_ACCESS_TOKEN not set in .env — Trending will be hidden"
fi

# TheSportsDB Premium API key for SportsZone. The app uses its existing
# Keychain key first, then this build-time default, then demo/free key 123.
THESPORTSDB_API_KEY="$(read_env THESPORTSDB_API_KEY)"
if [ -n "$THESPORTSDB_API_KEY" ]; then
    set_plist TheSportsDBAPIKey "$THESPORTSDB_API_KEY"
    echo "Injected TheSportsDB API key into Info.plist"
fi

MDBLIST_API_KEY="$(read_env MDBLIST_API_KEY)"
if [ -n "$MDBLIST_API_KEY" ]; then
    set_plist MDBListAPIKey "$MDBLIST_API_KEY"
    echo "Injected MDBLIST_API_KEY into Info.plist"
else
    echo "warning: MDBLIST_API_KEY not set in .env — extra ratings will be hidden"
fi

INTRO_DB_API_KEY="$(read_env INTRO_DB_API_KEY)"
if [ -n "$INTRO_DB_API_KEY" ]; then
    set_plist IntroDBAPIKey "$INTRO_DB_API_KEY"
    echo "Injected INTRO_DB_API_KEY into Info.plist"
else
    echo "warning: INTRO_DB_API_KEY not set in .env — IntroDB reads still work unauthenticated"
fi

OPENSUBTITLES_API_KEY="$(read_env OPENSUBTITLES_API_KEY)"
if [ -n "$OPENSUBTITLES_API_KEY" ]; then
    set_plist OpenSubtitlesAPIKey "$OPENSUBTITLES_API_KEY"
    echo "Injected OPENSUBTITLES_API_KEY into Info.plist"
else
    echo "warning: OPENSUBTITLES_API_KEY not set in .env — subtitle search will be hidden"
fi

TRAKT_CLIENT_ID="$(read_env TRAKT_CLIENT_ID)"
TRAKT_CLIENT_SECRET="$(read_env TRAKT_CLIENT_SECRET)"
if [ -n "$TRAKT_CLIENT_ID" ] && [ -n "$TRAKT_CLIENT_SECRET" ]; then
    set_plist TraktClientID "$TRAKT_CLIENT_ID"
    set_plist TraktClientSecret "$TRAKT_CLIENT_SECRET"
    echo "Injected Trakt credentials into Info.plist"
else
    echo "warning: TRAKT_CLIENT_ID/SECRET not set in .env — Trakt integration will be hidden"
fi

SIMKL_CLIENT_ID="$(read_env SIMKL_CLIENT_ID)"
if [ -n "$SIMKL_CLIENT_ID" ]; then
    set_plist SimklClientID "$SIMKL_CLIENT_ID"
    # Simkl's TV/device OAuth registrations carry no secret; one present for a
    # server-app registration is forwarded when set.
    SIMKL_CLIENT_SECRET="$(read_env SIMKL_CLIENT_SECRET)"
    if [ -n "$SIMKL_CLIENT_SECRET" ]; then
        set_plist SimklClientSecret "$SIMKL_CLIENT_SECRET"
    fi
    echo "Injected Simkl credentials into Info.plist"
else
    echo "warning: SIMKL_CLIENT_ID not set in .env — Simkl integration will be hidden"
fi

# MDBList account sync uses a "Device Code App" OAuth registration, which has no
# secret. Separate from MDBLIST_API_KEY, the app's own key for ratings lookups.
MDBLIST_CLIENT_ID="$(read_env MDBLIST_CLIENT_ID)"
if [ -n "$MDBLIST_CLIENT_ID" ]; then
    set_plist MDBListClientID "$MDBLIST_CLIENT_ID"
    echo "Injected MDBLIST_CLIENT_ID into Info.plist"
else
    echo "warning: MDBLIST_CLIENT_ID not set in .env — MDBList account sync will be hidden"
fi

# Optional: without it the per-configuration LUME_CLOUD_URL build setting
# stays (production in every configuration).
LUME_CLOUD_URL="$(read_env LUME_CLOUD_URL)"
if [ -n "$LUME_CLOUD_URL" ]; then
    set_plist LumeCloudServerURL "$LUME_CLOUD_URL"
    echo "Injected LUME_CLOUD_URL into Info.plist"
fi

# Provider mappings use the checked-in template only when a key is absent.
# An explicitly blank override hides a provider. Always write the key so an
# incremental build cannot retain an address removed from the configuration.
for provider in IPTVEDITOR DREAMCAST KLEPTO STRONG; do
    env_key="XTREAM_PROVIDER_${provider}_URL"
    if grep -qE "^[[:space:]]*${env_key}[[:space:]]*=" "$ENV_FILE"; then
        address="$(read_env "$env_key")"
    else
        original_env_file="$ENV_FILE"
        ENV_FILE="${SRCROOT}/.env.example"
        address="$(read_env "$env_key")"
        ENV_FILE="$original_env_file"
    fi
    set_plist "XtreamProvider${provider}URL" "$address"
done
