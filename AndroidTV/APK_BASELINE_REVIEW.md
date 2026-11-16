# Android Lume APK baseline review — 2026-11-16

## Supplied inputs
- `lume-arm64-v8a.apk` — 65 MB, ARM64 Android package
- `lume-armeabi-v7a.apk` — 51 MB, 32-bit ARM Android package

## Verified from the APK files
- Android application ID: `com.bilipp.lume`.
- Version string embedded in AndroidManifest.xml string pool: `3.2.0`; version-code string: `17`.
- Android TV launcher category: `android.intent.category.LEANBACK_LAUNCHER`.
- TV feature string: `android.software.leanback`.
- Entry activity: `com.bilipp.lume.MainActivity`.
- The packages each contain two DEX files and 2,091 ZIP entries.
- Both DEX files and `resources.arsc` are byte-identical across the two APK variants.
- The common Android manifests are not byte-identical.
- Each build provides native FFmpeg and VLC libraries along with SQLite and other support libraries, compiled for its matching ARM CPU architecture.
- AndroidX Media3 session service and Room database service appear in the manifest strings.

## Rebranding goal
- App display name: `DreamCAST TV 2`.
- Product/UI branding: `DreamCAST TV`.
- New Android application ID: `tv.dreamcast.android` (proposed; align with existing native starter).
- New app icon, Android TV launcher banner, splash, settings/about content, and deep links.
- Preserve core IPTV use cases, focus navigation and player fallback where practical.
- Bring tvOS custom SportsZone and TheSportsDB broadcaster matching into the Android app.

## Important distinction
These uploads are **compiled APK files**, not editable Android source projects.
They can serve as behavior/resource references, but do not provide a reliable, rebuildable upstream source tree.
To adopt the existing Android application directly, obtain the matching Android Studio source repository or a permitted source archive. Rebuilding or repackaging binaries would also require editing resources, revising app ID/manifest references, and signing replacement packages; signed APKs cannot be patched in place while retaining their original signatures.

The public `bilipp/Lume` repository is a Swift/Apple project; do not assume its source compiles to the supplied Android APK. Confirm ownership and license terms for the Android source and any bundled native libraries before distributing a modified Android app.

## Project direction
Use the supplied APK behavior and dependency list as the Android baseline. Keep the independent AndroidTV source project on `feature/dreamcast-android-tv`, and replace its initial placeholders with real feature modules once the matching source tree is available or through a new Kotlin implementation.

Do not commit the APK binaries to the repository without a clear need and license review.
