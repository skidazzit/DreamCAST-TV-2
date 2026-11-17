//
//  SettingsPages.swift
//  Lume
//
//  The smaller iOS / macOS / visionOS pages behind root Settings rows:
//  Appearance, Downloads and Connected Services (Trakt, Simkl). tvOS has no Appearance or
//  Downloads, and shows Connected Services in its own pane.
//

#if !os(tvOS)

    import SwiftUI

    /// The app-wide appearance override (System / Dark / Light), applied at the
    /// scene root in `LumeApp`.
    struct AppearanceSettingsView: View {
        @AppStorage(AppAppearance.storageKey)
        private var appearanceRaw = AppAppearance.defaultValue.rawValue
        @AppStorage(DreamCASTAccentTheme.storageKey)
        private var accentRaw = DreamCASTAccentTheme.defaultValue.rawValue

        var body: some View {
            List {
                Section {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Display Mode")
                } footer: {
                    Text("Follow your device, or use Dark or Light Mode.")
                }

                Section {
                    ForEach(DreamCASTAccentTheme.allCases) { theme in
                        Button {
                            accentRaw = theme.rawValue
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                                Text(theme.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if accentRaw == theme.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.color)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(accentRaw == theme.rawValue ? [.isSelected] : [])
                    }
                } header: {
                    Text("Color Theme")
                } footer: {
                    Text("Choose an accent for buttons and controls. Changes save right away.")
                }
            }
            .tint(DreamCASTAccentTheme.resolve(accentRaw).color)
            .platformNavigationTitle("Appearance")
        }
    }

    struct DownloadsSettingsView: View {
        @AppStorage(DownloadManager.maxConcurrentKey) private var maxConcurrent = 1
        @AppStorage(DownloadManager.autoDeleteKey) private var autoDeleteAfterWatching = false

        var body: some View {
            List {
                Section {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("Manage Downloads", systemImage: "arrow.down.circle")
                    }
                }

                Section {
                    Stepper(
                        "Max Simultaneous Downloads: \(maxConcurrent)",
                        value: $maxConcurrent,
                        in: 1 ... 5
                    )

                    Toggle("Auto-Delete After Watching", isOn: $autoDeleteAfterWatching)
                } footer: {
                    Text("Download movies and episodes for offline playback. Auto-delete removes the file once you've finished watching.")
                }
            }
            .platformNavigationTitle("Downloads")
        }
    }

    /// Trakt, Simkl and MDBList — whichever this build has credentials for. OpenSubtitles
    /// lives under Player.
    struct ConnectedServicesView: View {
        @State private var trakt = TraktService.shared
        @State private var simkl = SimklService.shared
        @State private var mdblist = MDBListService.shared

        var body: some View {
            List {
                Section {
                    if trakt.isConfigured {
                        NavigationLink {
                            TraktIntegrationView()
                        } label: {
                            serviceLabel(
                                "Trakt",
                                systemImage: "arrow.trianglehead.2.clockwise.rotate.90.circle",
                                status: trakt.isConnected ? trakt.username.map { "@\($0)" } ?? String(localized: "Connected") : nil
                            )
                        }
                    }

                    if simkl.isConfigured {
                        NavigationLink {
                            SimklIntegrationView()
                        } label: {
                            serviceLabel(
                                "Simkl",
                                systemImage: "arrow.trianglehead.2.clockwise.rotate.90.circle",
                                status: simkl.isConnected ? simkl.username.map { "@\($0)" } ?? String(localized: "Connected") : nil
                            )
                        }
                    }

                    if mdblist.isConfigured {
                        NavigationLink {
                            MDBListIntegrationView()
                        } label: {
                            serviceLabel(
                                "MDBList",
                                systemImage: "arrow.trianglehead.2.clockwise.rotate.90.circle",
                                status: mdblist.isConnected ? mdblist.username.map { "@\($0)" } ?? String(localized: "Connected") : nil
                            )
                        }
                    }

                } footer: {
                    Text("Sync watched movies and episodes and show your Trakt, Simkl or MDBList watchlist on Home.")
                }
            }
            .platformNavigationTitle("Connected Services")
        }

        private func serviceLabel(_ title: LocalizedStringKey, systemImage: String, status: String?) -> some View {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if let status {
                    Text(verbatim: status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

#endif
