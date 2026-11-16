//
//  PlaylistDetailView+TV.swift
//  Lume
//
//  The tvOS layout for a playlist's detail pane: the connection fields, account
//  info, stream-format and sync sections, and the edit/delete actions. Split out
//  of PlaylistDetailView to keep that file within the project's line-count cap.
//

import SwiftUI

#if os(tvOS)

    extension PlaylistDetailView {
        /// Rendered *inline* inside the Settings detail pane (next to the sidebar),
        /// not pushed full-screen. A push hides the TabView's header tab bar and
        /// strands focus once the content scrolls — keeping it in the pane means
        /// the sidebar and tab bar stay one "Left"/"Up" away at all times. The
        /// enclosing pane supplies the ScrollView, background, and width framing.
        var tvBody: some View {
            VStack(alignment: .leading, spacing: 32) {
                Text(playlist.name)
                    .font(.system(size: 34, weight: .bold))
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                tvServerSection
                tvAccountSection
                tvStreamFormatSection
                tvSyncSection
                tvActionsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Menu while editing discards the edits, like Cancel; otherwise
            // Settings backs out to the playlist list.
            .onExitCommand(perform: isEditing ? { cancelEditing() } : nil)
            .alert("Delete Playlist", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deletePlaylist() }
            } message: {
                Text("All synced content for this playlist will also be removed.")
            }
            .fullScreenCover(isPresented: $showSync) {
                SyncProgressView(playlist: playlist)
            }
            .fullScreenCover(isPresented: $showFullSync) {
                SyncProgressView(playlist: playlist, full: true)
            }
            .paywall(isPresented: $showPaywall, highlight: .multiplePlaylists)
        }

        var tvServerSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel(connectionSectionTitle)

                if isEditing {
                    VStack(spacing: 18) {
                        TVSettingsField(title: "Name", placeholder: "Name", text: $editName, contentType: .name)
                        TVSettingsField(title: serverURLFieldTitle, placeholder: serverURLFieldTitle, text: $editServerURL, contentType: .URL)
                        if isM3U {
                            TVSettingsField(title: "EPG URL (optional)", placeholder: "EPG URL", text: $editEPGURL, contentType: .URL)
                        } else if isStalker {
                            TVSettingsField(title: "MAC Address", placeholder: "00:1A:79:xx:xx:xx", text: $editMacAddress, contentType: nil)
                            TVSettingsField(title: "Username (optional)", placeholder: "Username", text: $editUsername, contentType: .username)
                            TVSettingsField(title: "Password (optional)", placeholder: "Password", text: $editPassword, isSecure: true, contentType: .password)
                        } else if isWebDAV {
                            TVSettingsField(title: "Username (optional)", placeholder: "Username", text: $editUsername, contentType: .username)
                            TVSettingsField(title: "Password (optional)", placeholder: "Password", text: $editPassword, isSecure: true, contentType: .password)
                        } else if isMediaServer {
                            TVSettingsField(title: "Username", placeholder: "Username", text: $editUsername, contentType: .username)
                            TVSettingsField(title: "Password", placeholder: "Password", text: $editPassword, isSecure: true, contentType: .password)
                        } else if isPlex {
                            // A Plex playlist can be credential-free, so both
                            // rows stay optional here too.
                            TVSettingsField(title: "Username (optional)", placeholder: "Username", text: $editUsername, contentType: .username)
                            TVSettingsField(title: "Password or token (optional)", placeholder: "Password", text: $editPassword, isSecure: true, contentType: .password)
                        } else {
                            TVSettingsField(title: "Username", placeholder: "Username", text: $editUsername, contentType: .username)
                            TVSettingsField(title: "Password", placeholder: "Password", text: $editPassword, isSecure: true, contentType: .password)
                        }
                    }
                } else {
                    VStack(spacing: 2) {
                        TVSettingsValueRow("Name", value: playlist.name)
                        TVSettingsValueRow(serverURLFieldTitle) {
                            Text(playlist.displayURL)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if isM3U {
                            TVSettingsValueRow("EPG URL") {
                                Text(playlist.epgURL ?? String(localized: "None"))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } else if isStalker {
                            TVSettingsValueRow("MAC Address", value: playlist.macAddress ?? "")
                            if !playlist.username.isEmpty {
                                TVSettingsValueRow("Username", value: playlist.username)
                            }
                        } else if isWebDAV {
                            // A WebDAV share can be anonymous, so each credential
                            // row only appears when there is something to show.
                            if !playlist.username.isEmpty {
                                TVSettingsValueRow("Username", value: playlist.username)
                            }
                            if !playlist.password.isEmpty {
                                TVSettingsValueRow("Password") { Text("••••••••") }
                            }
                        } else if isMediaServer {
                            TVSettingsValueRow("Username", value: playlist.username)
                            TVSettingsValueRow("Password") { Text("••••••••") }
                        } else if isPlex {
                            if !playlist.username.isEmpty {
                                TVSettingsValueRow("Username", value: playlist.username)
                            }
                            if playlist.plexAccessToken?.isEmpty == false {
                                TVSettingsValueRow("Token") { Text("••••••••") }
                            }
                        } else {
                            TVSettingsValueRow("Username", value: playlist.username)
                            TVSettingsValueRow("Password") { Text("••••••••") }
                        }
                        TVSettingsValueRow("Added") { Text(playlist.addedAt, style: .date) }
                    }
                }
            }
        }

        @ViewBuilder
        var tvAccountSection: some View {
            if let status = playlist.userStatus {
                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Account")

                    VStack(spacing: 2) {
                        TVSettingsValueRow("Status", value: status)
                        TVSettingsValueRow("Expires") {
                            if let expDate = playlist.expDate {
                                Text(formattedExpiry(expDate))
                                    .foregroundStyle(isExpired(expDate) ? .red : .secondary)
                            } else {
                                Text("Not reported by provider")
                            }
                        }
                        if let maxConn = playlist.maxConnections {
                            TVSettingsValueRow("Max Connections", value: maxConn)
                        }
                        if let activeConn = playlist.activeConnections {
                            TVSettingsValueRow("Active Connections", value: activeConn)
                        }
                    }

                    Text("Status and expiry come from your Xtream provider's account response (player_api.php). They may be out of date until refreshed.")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                    if let checked = lastAccountCheck {
                        Text("Last checked: \(checked.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    } else if let lastSync = playlist.lastSyncDate {
                        Text("Last playlist sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    }

                    Button {
                        refreshXtreamAccount()
                    } label: {
                        HStack(spacing: 13) {
                            Text(Image(systemName: "arrow.clockwise"))
                                .font(.system(size: 22))
                                .frame(width: 27, height: 30)
                            Text("Refresh Account Details")
                            Spacer()
                            if refreshingAccount {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                    .disabled(refreshingAccount)
                    if let accountRefreshMessage {
                        Text(accountRefreshMessage)
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    }
                }
            }
        }

        /// Only refresh the small provider account record. Never run a full
        /// catalog sync just to check status or the expiry timestamp.
        private func refreshXtreamAccount() {
            guard playlist.sourceType == .xtream, !refreshingAccount else { return }
            refreshingAccount = true
            accountRefreshMessage = nil
            Task { @MainActor in
                do {
                    let response = try await XtreamClient().getInfo(playlist: playlist)
                    playlist.userStatus = response.userInfo.status
                    playlist.expDate = response.userInfo.expDate
                    playlist.maxConnections = response.userInfo.maxConnections
                    playlist.activeConnections = response.userInfo.activeCons
                    playlist.allowedOutputFormats = response.userInfo.allowedOutputFormats
                    playlist.serverTimezone = response.serverInfo.timezone
                    playlist.lastUpdated = Date()
                    try modelContext.save()
                    lastAccountCheck = Date()
                    accountRefreshMessage = "Account details updated from the provider."
                } catch {
                    accountRefreshMessage = "Could not refresh account details: \(error.localizedDescription)"
                }
                refreshingAccount = false
            }
        }

        @ViewBuilder
        var tvStreamFormatSection: some View {
            if playlist.supportsStreamFormatChoice {
                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Playback")

                    TVOptionCycleRow(
                        title: "Live Stream Format",
                        valueLabel: playlist.streamFormat.displayName
                    ) {
                        playlist.streamFormat = playlist.streamFormat.next
                    }

                    Text(streamFormatFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                        .padding(.top, 4)
                }
            }
        }

        var tvSyncSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("Sync")

                VStack(spacing: 2) {
                    Button {
                        playlist.syncEnabled.toggle()
                    } label: {
                        HStack(spacing: 16) {
                            Text("Sync Enabled")
                            Spacer(minLength: 0)
                            Text(playlist.syncEnabled ? "On" : "Off")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())

                    // Unconditional — see the iOS pane: the states worth
                    // reading were the ones that used to render as no row.
                    TVSettingsValueRow("Status") {
                        HStack(spacing: 8) {
                            if syncState == .syncing {
                                ProgressView()
                            }
                            Text(statusLabel)
                                .foregroundStyle(syncState.tint)
                        }
                    }

                    if let lastSync = syncState.lastSyncDate {
                        TVSettingsValueRow("Last Synced") {
                            Text(lastSync, style: .relative)
                        }
                    }

                    Button("Sync Now") { requestSync() }
                        .buttonStyle(TVSettingsRowButtonStyle())
                        .disabled(playlist.syncStatus == .syncing)

                    if isStalker {
                        Button("Download Full Catalog") { requestSync(full: true) }
                            .buttonStyle(TVSettingsRowButtonStyle())
                            .disabled(playlist.syncStatus == .syncing)
                    }
                }

                if isStalker {
                    Text("""
                    Movies and series load as you browse — nothing is prefetched. \
                    Download the full catalog to make everything available offline and \
                    searchable at once; this can take a while on large portals.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    .padding(.top, 4)
                }
            }
        }

        var tvActionsSection: some View {
            VStack(spacing: 2) {
                if isEditing {
                    Button("Done") { saveChanges() }
                        .buttonStyle(TVSettingsRowButtonStyle())
                    Button("Cancel") { cancelEditing() }
                        .buttonStyle(TVSettingsRowButtonStyle())
                } else {
                    Button("Edit Playlist") { startEditing() }
                        .buttonStyle(TVSettingsRowButtonStyle())
                    Button("Delete Playlist") { showDeleteConfirmation = true }
                        .buttonStyle(TVSettingsRowButtonStyle(isDestructive: true))
                }
            }
            .padding(.top, 12)
        }
    }

#endif
