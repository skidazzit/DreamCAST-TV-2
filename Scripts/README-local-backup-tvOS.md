# DreamCAST TV — Apple TV local backup and restore

Use the new **Settings → Backup & Storage → Local Backup & Restore** section.

1. On Apple TV, select **Start Local Backup & Restore**.
2. Keep the Settings screen open. On a phone or Mac connected to the same
   private network, scan the QR code or enter the address shown on the TV.
3. To back up settings, select **Download Settings** and save the JSON file.
4. To restore, choose a DreamCAST TV settings JSON file, then select
   **Send to Apple TV**.
5. **Approve Restore on the Apple TV**. The upload alone never changes
   your settings.
6. Restart DreamCAST TV after a restore.

Apple TV has no normal Files picker. The temporary local web page is the
transfer method. The link contains a random session token, is visible only
while the transfer is enabled, and expires after 10 minutes or when the
Settings pane closes. This is a plain HTTP transfer on your LAN: use only a
trusted private network and stop the transfer when finished.

The file follows the iOS version-1 JSON settings format. It carries safe
preferences only; it is **not** a copy of your media library, playlists,
account passwords, Keychain entries, or watch-history database.
The maximum upload is 8 MB.

**Cloud sync:** The Apple TV Sync category is hidden and tvOS's active
backend uses local-only mode. Existing remote cloud account data is not
deleted by this change. The iOS branch already provides local JSON backups
through the Files app; its workflow is unchanged.

The code and archive tests were pushed to GitHub. Build, QR connection,
browser upload, and device restore still require an Apple TV test.
