# DreamCAST TV 2 — StreamVault-based Android development

This migration is separate from the earlier Kotlin prototype in `AndroidTV/app/`.
**The current Android base is `AndroidTV/StreamVault`, pinned as a Git submodule.**
Do not open `AndroidTV/` in Android Studio for the StreamVault-based build.
Open the generated `AndroidTV/DreamCAST-StreamVault/` instead.

## Prepare the new Android source on macOS

From a fresh clone:

```bash
git clone --recurse-submodules \
  --branch feature/dreamcast-streamvault-migration \
  https://github.com/skidazzit/DreamCAST-TV-2.git \
  DreamCAST-TV-2-Android
cd DreamCAST-TV-2-Android
bash AndroidTV/scripts/prepare-streamvault-worktree.sh
open -a "Android Studio" AndroidTV/DreamCAST-StreamVault
```

From an existing DreamCAST-TV-2 checkout:

```bash
git fetch origin
git switch feature/dreamcast-streamvault-migration
git pull --ff-only origin feature/dreamcast-streamvault-migration
git submodule update --init --recursive
bash AndroidTV/scripts/prepare-streamvault-worktree.sh
```

**Do not run the bootstrap script over a workspace containing local edits.**
The script stops if the generated workspace already exists. It copies the pinned
source without .git history, build files, or local secrets and changes the
Android app display name to `DreamCAST TV 2`. It retains StreamVault's license
and writes a derivative notice. The scripts are early migration tools, not
a finished APK.

### Build
Open `AndroidTV/DreamCAST-StreamVault` with Android Studio, using JDK 17
and installed Android SDK. Sync Gradle. Then use the project's Gradle wrapper:

```bash
cd AndroidTV/DreamCAST-StreamVault
./gradlew :app:assembleDebug
./gradlew testDebugUnitTest
```

Check `app/build/outputs/apk/debug/` for generated debug output.
**No successful Android build, emulator run, or device test is claimed here.**

## StreamVault source reference

- Upstream: https://github.com/Davidona/StreamVault-IPTV
- Pinned upstream revision: `bc32f389b37969e387df83df032d2a8235024222`
- Core modules: `app`, `core:ui`, `core:navigation`, `data`,
  `domain`, `player`, `feature:live`, `feature:provider`,
  `feature:settings`, `feature:catalog`.
- Source license: `AndroidTV/StreamVault/LICENSE`.

## Roadmap based on tvOS changes

1. **First source build / provenance**: Verify default StreamVault builds unchanged,
   then build the generated DreamCAST launcher-name variant.
2. **Full branding / legal credits**: Update theme assets, logo and icon while
   preserving the required visible StreamVault attribution, original GitHub
   and donation links, and `Based on StreamVault` notice.
3. **Xtream provider list**: Set up an authenticated provider URL registry and
   dropdown choices in this order: DreamCAST TV, Klepto TV, Strong, IPTVeditor.
   Keep user credentials separate from the remote public configuration.
4. **Live TV guide**: Fixed current-time EPG, navigate through channel-name
   column only, first/second/third OK channel behavior, guide alignment.
5. **Shared player**: Keep the player/decoder alive across mini/full-screen
   and tab transitions; restart channel control and audible preview;
   last watched Live TV channel on launch.
6. **SportsZone**: TheSportsDB setup/status, followed league filters,
   in-progress versus upcoming match sorting, broadcaster-to-IPTV lookup,
   cache/EPG fallback, league detail and channel popup.
7. **Movies and series**: Use same player and progress store; match poster
   sizes, season names, and release dates from tvOS.
8. **Settings and QA**: Local backup/restore, nav rules, performance and
   extended streaming tests.

## Distribution restrictions

StreamVault is source-available under a non-commercial license.
Keep copyright and credit obligations, the original source and donation
links, and the full source-publication conditions. A commercial DreamCAST TV
service requires prior written permission from the StreamVault copyright owner.
Do not treat this prototype as ready for public distribution.

The older Android prototype remains in the repository for reference. No
Lume APK-derived executable code has been copied into StreamVault.
