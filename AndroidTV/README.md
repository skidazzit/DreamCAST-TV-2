# DreamCAST TV 2 — Android TV

Native Android TV / Google TV app in the DreamCAST-TV-2 repository.
Branch: `feature/dreamcast-android-tv`.

## Implemented in source
- DreamCAST TV branding and TV launcher activity.
- Top-level remote-focusable navigation.
- Import M3U / M3U8 playlists by HTTP(S) URL or local file picker.
- Parse `#EXTINF` attributes including channel name, `tvg-id`, `tvg-logo`, and `group-title`.
- Browse channel groups and channel names with remote D-pad.
- Media3 / ExoPlayer playback, one player shared between preview and full-screen layouts.
- Last-selected playback channel ID saved in app preferences.
- Restore saved remote URL or last imported local playlist after app restart.
- M3U parser unit tests.
- XMLTV EPG URL setting, parser, timezone handling, and program lookup by tvg-id.
- Fixed-to-current-time guide grid with half-hour slots; channel names are the only guide row focus targets.
- Guide preview stays on one ExoPlayer instance when opening and leaving full-screen.

## Still missing
- EPG logos, time-range scrolling, background refresh, and alternate program matching.
- Xtream Codes login, movie and series catalogs.
- SportsZone, TheSportsDB match data and broadcaster matching.
- Advanced channel sorting, search, favorites, settings, backup/restore.
- Playback error/retry UI, decoder fallback, artwork and branding assets.
- Focus testing and performance fixes for large playlists.

## Build and install
1. Open `AndroidTV` in Android Studio.
2. Select JDK 17 and install Android SDK Platform 36.
3. Gradle configuration uses Android Gradle Plugin 8.13.2 and Gradle 8.13.
4. The Gradle wrapper JAR and scripts are **not** included yet. Use installed Gradle 8.13 and generate them with `gradle wrapper --gradle-version 8.13`.
5. Sync, select an Android TV emulator or connected TV, and Run `app`.
6. Open Settings, import an M3U URL or local M3U file, and enter an XMLTV EPG URL.
7. Open Live TV and use the channel-name column for selection and playback.

Remote actions: first OK selects a channel; next OK starts the preview; another OK on the playing channel opens full-screen. Back returns to guide without stopping the player. The "Play selected" and "Full screen" buttons also provide direct actions.

## Validation status
The source changes were committed and re-fetched from GitHub. Build, unit tests,
EPG parsing, playlist imports on real providers and device playback have **not** been run
in this environment. Do not treat this as a tested APK or production release.

## Source and licensing
The supplied Lume Android APKs were reviewed as compiled behavior references.
Their compiled code was **not** copied into this source project.
The original Apple SwiftUI source is also a reference, not buildable Android code.
No playlists, stream links or API keys are bundled. Only use media you have
rights to access. Review applicable project and third-party licenses before release.
