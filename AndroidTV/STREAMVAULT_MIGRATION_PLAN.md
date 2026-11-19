# DreamCAST TV Android — StreamVault migration assessment
Date: 2026-11-19
Target branch: `feature/dreamcast-streamvault-migration`
Candidate upstream: https://github.com/Davidona/StreamVault-IPTV (master)
Existing DreamCAST Android prototype: `feature/dreamcast-android-tv`
tvOS feature reference: `feature/dreamcast-tvOS` (review source before porting individual features)

## Decision gate — source license
StreamVault is **source-available**, not standard OSI open source. Its `LICENSE` is the StreamVault Source-Available License (Non-Commercial).
- Retain attribution to David Nashash/Davidona in About/Credits and all distributed docs.
- Retain visible links to the original repository and https://ko-fi.com/davidona.
- Identify the derivative as "Based on StreamVault" in the app and distribution description.
- Non-commercial use only without explicit written permission from the copyright holder.
- Distributing modifications requires publishing the full corresponding source under this exact license.
- Any code previously derived from Lume requires independent AGPL-3.0 compatibility review; do not combine license-covered source without resolving conflicts.
- **Do not copy StreamVault source, rename its package, or publish the fork yet until use case and license compatibility are settled.**

## Verified architecture
The upstream repo is a rebuildable multi-module Android app, unlike the supplied Lume APK files:
- `app`: Compose TV UI and Android platform integrations
- `core:navigation`, `core:ui`: screen navigation, design/focus
- `domain`, `data`: provider models, Room persistence and repositories
- `player`, `feature:playback`: Media3 playback
- `feature:provider`, `feature:settings`: login/playlist and preferences
- `feature:live`: channel guide and live browsing
- `feature:catalog`: VOD
- `docs/sports`: existing sports provider docs
Its README lists Xtream Codes, M3U, XMLTV, full guide, live preview, movies/series, DVR, and backups.

## tvOS to Android feature parity targets
### 1. Identity and settings
- App display and navigation branding "DreamCAST TV 2"; use DreamCAST TV art, icons, TV banner and splash.
- Preserve StreamVault attribution and links where license requires.
- Top tabs: Live TV, SportsZone, Movies, Series, Settings; remove Home from main nav.
- Move sports/playlist configuration to matching DreamCAST Settings categories.
- Keep local file Backup/Restore; do not require cloud service.
- Xtream provider choice list (in order): DreamCAST TV, Klepto TV, Strong, IPTVeditor; user enters username, password, playlist name.
- Provider server URLs come from an authenticated, remotely maintained provider config; never store passwords in a public config. Validate expiry/version and use HTTPS. Actual URLs/secrets must not be committed.

### 2. Live TV
- Select a channel with first OK, play it in mini-player on second OK, open full-screen on third OK.
- One persistent player session for mini and full view; back returns to guide while stream keeps playing.
- Reuse session as user switches tabs; do not start playback anew merely because a view changed.
- Play last Live TV channel when app starts, highlight it in guide; do not auto-play a saved VOD title.
- EPG timeline anchored to current time; only channel-name column accepts channel selection focus.
- Stream stays audible in preview; channel refresh/restart button available.
- Guide column/channel programs stay aligned on row selection, and channel names scroll when focused.
- Player fallback and error handling must be tested for stream types and decoders.
- Background EPG scan can supplement channel matching.

### 3. SportsZone
- TheSportsDB Premium/free key and connection status in Settings.
- Followed sports/leagues filter, Select All/None, and smooth focus for all-sports mode.
- Happening Now uses true in-progress matches; Coming Up is sorted by start time.
- Broadcaster list from TheSportsDB; exact IPTV channel matches before partial name variants; exclude unrelated.
- Cache broadcaster-to-channel mapping independently from match event ID. EPG as second matching source.
- Fixtures, standings, scores and league details, channel popup and live playback through shared player.
- League logos, team logos, team color backgrounds, full team names and guide-friendly focus styles.
- Limit visible league match rows to 5 with scroll when more.

### 4. Movies and series
- Match DreamCAST poster sizes, full season labels, release/air dates, and category browsing.
- Open VOD with shared player service (do not start separate video engine), while preserving progress tracking.
- Keep player ready across navigation, without unnecessary decoder rebuild.

## Proposed implementation sequence once license is cleared
1. Vendor or fork StreamVault source into an isolated `AndroidTV/` subtree on a new integration branch; keep copyright/LICENSE intact.
2. Establish clean Gradle assembleDebug and Android TV emulator launch **before** edits.
3. Rebrand app strings, assets, app ID where safe, and navigation without disrupting provider/database namespaces.
4. Implement provider dropdown/remote config, test Xtream/M3U login without embedding credentials.
5. Bring live-guide interaction and persistent player handoff to parity with tvOS.
6. Port SportsZone with TheSportsDB matching and detail screens.
7. Match VOD/shared player flow, settings/local backup and launch behavior.
8. Run unit/instrumented tests, remote focus, reboot/persistence, player handoff, and extended stream health tests.
9. Verify attribution/license obligations and publish compliant source prior to distribution.

## Safe migration posture
The current homegrown Android prototype remains untouched on `feature/dreamcast-android-tv`.
This branch currently contains only the plan, not copied upstream code.
A StreamVault-based derivative cannot safely inherit the prototype's Lume-derived code or ship commercially without a license review.
