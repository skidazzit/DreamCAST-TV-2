## Apple TV free-account build (Sideload)

This build mode is for local testing on Apple TV with a free Apple Personal Team.
The Xcode project references three Swift packages stored next to the app repo.

From the DreamCAST TV 2 folder on your Mac:

```bash
git switch feature/dreamcast-tvOS
git pull --ff-only origin feature/dreamcast-tvOS
bash Scripts/prepare-free-tvos.sh
```

The script clones missing public package checkouts, without replacing existing folders:
- `../LumeEngine` — package: LumeEngine
- `../LumeRecorder/Kit` — package: LumeRecorderKit
- `../LumeCloud/LumeCloudKit` — package: LumeCloudKit

It also removes the Top Shelf embed and target dependency only in your local
Xcode project. The extension source and target remain in GitHub. Because
the app target then has no extension dependency, Xcode should stop trying
to sign `com.skidazzit.dreamcasttv2.topshelf` during local testing.

In Xcode:
1. Open `DreamCAST-tvOS.xcodeproj`.
2. Go to **Xcode > Settings > Accounts** and sign in to your Apple account.
3. Choose the **Lume** app target, then **Signing & Capabilities**.
4. Select **your Personal Team** and **Automatically manage signing**.
   The checked-in ID `CHG45F8MCL` belongs to another team.
   If Xcode reports a bundle ID conflict, choose a unique local bundle ID.
5. Select the **DreamCAST-tvOS** scheme and set **Run > Build Configuration**
   to **Sideload**.
6. Choose **File > Packages > Reset Package Caches**, then
   **Resolve Package Versions**. The binary media engine packages may also
   need to download on the first build.
7. Select your connected Apple TV and try **Build/Run** again.

To restore Top Shelf embedding when you have the right signing entitlements:

```bash
bash Scripts/prepare-free-tvos.sh --restore-top-shelf
```

The script changes the local `project.pbxproj` until you restore it.
Keep local signing IDs and build edits out of commits. If Git reports a project
conflict on a later pull, restore the links before merging new project changes.
