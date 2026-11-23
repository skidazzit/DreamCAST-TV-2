# DreamCAST TV — StreamVault-based Android development

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
Android app display name to `DreamCAST TV`. It retains StreamVault's license
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

## Official DreamCAST Android logo assets

Use the transparent artwork supplied for this rebrand. Extract the `branding/` directory from the DreamCAST Android branding ZIP into `AndroidTV/` so the following files exist:

- `AndroidTV/branding/dreamcast-icon.png` — 1024 × 1024 square transparent logo.
- `AndroidTV/branding/dreamcast-tv-banner.png` — 320 × 180 transparent TV banner.

Then run `bash AndroidTV/scripts/apply-dreamcast-branding.sh` from the repository root. The script updates the generated local `AndroidTV/DreamCAST-StreamVault` workspace, not the upstream StreamVault submodule. It creates density-specific launcher assets and copies the supplied TV banner. The ZIP must be placed on the Mac first; image files are not embedded in this Git commit. This is a development rebrand; distribution still requires in-app attribution and matching public source under the upstream license.

## Rebrand an existing built Android workspace

Do not rerun the `prepare-streamvault-worktree.sh` script or clone again.
From the existing DreamCAST checkout:

```bash
cd ~/Desktop/DreamCAST-TV-2-Android
git pull --ff-only origin feature/dreamcast-streamvault-migration
bash AndroidTV/scripts/apply-dreamcast-branding.sh
cd AndroidTV/DreamCAST-StreamVault
./gradlew :app:assembleDebug
```

Reinstall the new APK rather than relaunching the old installed app.
This script replaces launcher labels and StreamVault-branded values in
`app/src/main/res/values*/strings.xml`, plus launcher icons and TV banner
from the current DreamCAST tvOS assets.
It does not rename Kotlin packages, internal API names or third-party credits.
Other hard-coded product strings/graphics, About/Credits UI and all tvOS feature
ports remain pending. It can be run again without erasing your working directory.

### Xtream provider chooser — first integration
The branding script now also applies a source patch to the Xtream setup form.
It shows the four choices in this order: **DreamCAST TV, Klepto TV, Strong,
IPTVeditor**. The existing provider-name, username and password fields remain.

No provider addresses are committed. Until a URL is configured for a choice,
the server URL text field remains available so login does not break.

For local testing only, you may pass a separate JSON mapping to the tracked
overlay. The file must have exactly four keys:

```json
{
  "DreamCAST TV": "",
  "Klepto TV": "",
  "Strong": "",
  "IPTVeditor": ""
}
```

Save it outside GitHub, for example `~/private-dreamcast-provider-map.json`,
and run:

```bash
python3 AndroidTV/scripts/apply-provider-chooser.py \
  AndroidTV/DreamCAST-StreamVault \
  --map ~/private-dreamcast-provider-map.json
```

A populated local mapping is bundled into the APK, **so its server URLs are
not secret from someone who inspects the APK**. This is only a short-term
development aid, not the planned authenticated provider management service.
The cloud config website and authenticated endpoint are not built yet.

The chooser is not yet compiled or tested against the modified app.


## Gradle catalog repair (only if `libs` stays unresolved)

If Gradle reports `Unresolved reference: libs` even though
`gradle/libs.versions.toml` exists, use the isolated workaround:

```bash
cd ~/Desktop/DreamCAST-TV-2-Android
git pull --ff-only origin feature/dreamcast-streamvault-migration
python3 AndroidTV/scripts/repair-gradle-catalog.py AndroidTV/DreamCAST-StreamVault
cd AndroidTV/DreamCAST-StreamVault
./gradlew --stop
./gradlew help --no-configuration-cache
./gradlew :app:assembleDebug --no-configuration-cache
```

The script backs up `settings.gradle.kts` and the original catalog.
It gives the TOML file a new name and imports it directly through Gradle
settings, avoiding a clash with Gradle's default catalog auto-import.
It does not change Android app files, branding, credentials, or player logic.
This is a diagnostic workaround rather than a confirmed fix for every setup.
Do not rerun the script if it reports a backup conflict.

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
