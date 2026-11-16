# DreamCAST TV 2 — Android TV

A native Android TV / Google TV project inside the DreamCAST-TV-2 repository.

## Status
Phase 1 starter only: launchable TV activity, D-pad focusable top navigation,
and placeholder Live TV, SportsZone, Movies, Series and Settings screens.

The source review used the feature/dreamcast-tvOS branch, whose Xcode project
uses SwiftUI and Apple player libraries (including KSPlayer, VLCKit and LumeEngine).
The Android port must reimplement the UI and platform services; this is not
an automatic Swift-to-Kotlin conversion.

## Open
Open the **AndroidTV** folder in Android Studio (not the repository root).
Use JDK 17 and Android SDK 36. Sync Gradle and run the app on an Android TV
emulator or device. The Gradle wrapper JAR/scripts are not yet committed;
use an installed Gradle 8.13 to build, or generate the wrapper with
`gradle wrapper --gradle-version 8.13`.

## Next
1. Add playlist source screens and M3U / Xtream parsing.
2. Add persistent data, EPG timeline, favorites, and last-played channel.
3. Add Media3 playback and a shared player instance across mini/full-screen.
4. Port SportsZone APIs, live fixtures and broadcaster matching.
5. Port media library, settings and local backup/restore.
6. Replace temporary launcher art with approved DreamCAST TV assets.
7. Verify Gradle sync, build and D-pad traversal on hardware and emulator.

No playlists, credentials, or third-party API keys are included.
Check AGPL-3.0 obligations for code reused from the upstream Lume project.
