# DreamCAST TV server manager

Dashboard: https://dreamcast-server-manager.inquisitivemagpie.chatgpt.site

Sign in with the owner ChatGPT account. Change an address and select **Publish changes**. The public `/api/providers` feed contains provider addresses only. Usernames and passwords stay in the Apple apps.

Updated apps check on launch, foreground, and before Xtream catalog sync; checks are limited to one per minute. A valid directory is cached on the device. Network errors, invalid data, and older revisions keep the last good copy. `.env` addresses remain offline defaults for a fresh installation.

Provider IDs and names remain fixed. New playlists save the stable ID. Existing playlists match their original address against current, bundled and historical addresses. Disabling a provider hides it from the add-playlist list; existing playlists still resolve its current address.

API, live, movie, episode, catch-up and saved XMLTV URLs use the current provider base. Direct links on external CDN hosts stay unchanged. A stream already playing is not interrupted; the next request uses the new address.

Local encrypted playlist backups preserve the provider ID and current base. Older backups still work through address matching. Manual server edits to an unrelated custom address unlink that playlist from the directory.

One app rebuild/install is required to ship this feature. Future address changes only require publishing in the dashboard.

Validation: server tests cover provider order, validation, alias ownership and conflicts. Apple tests cover address validation, directory shape and playback URL rewriting. Run `XtreamProviderDirectoryTests` with Xcode's iOS test scheme.
