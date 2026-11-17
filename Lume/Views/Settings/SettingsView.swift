import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) private var dismiss
    /// Not `private`: read by the SettingsView+Library extension (separate file).
    @Environment(CloudSyncCoordinator.self) var cloudSync: CloudSyncCoordinator?
    /// Not `private`: read by the SettingsView+Playlists / +Library extensions (separate files).
    @Query var playlists: [Playlist]
    /// Premium entitlement + paywall presentation. Not `private`: read by the
    /// SettingsView+Premium / +Playlists / +TVPlayer extensions (separate files).
    @State var premium = PremiumManager.shared
    @State var showPaywall = false
    @State var paywallHighlight: PremiumFeature?
    /// The globally-selected playlist, shared with the content tabs. Library's
    /// tab switches apply to it, and on tvOS (no toolbar switcher) the Playlists
    /// pane is also where it is chosen, the Play/Pause quick-switch overlay the
    /// fast path. The raw value can be `PlaylistSelectionStore.combined`, so it
    /// is only ever read through `catalogScope`. Not `private`: written by the
    /// SettingsView+Playlists extension (separate file).
    @AppStorage(PlaylistSelectionStore.key) var selectedPlaylistID: String = ""
    /// The scope the content tabs show, published by `MainTabView`, which hosts
    /// Settings as a tab or as a sheet on the library toolbar. Not `private`:
    /// read by the SettingsView+Playlists / +Library extensions (separate files).
    @Environment(\.catalogScope) var catalogScope
    /// Badges the Sync row while Lume Cloud's recovery key is unseen.
    @AppStorage(LumeCloudSettings.Key.recoveryKeyViewed) private var lumeCloudRecoveryKeyViewed = false
    #if !os(tvOS)
        /// The app-wide appearance override (System / Dark / Light), shown as the
        /// Appearance row's value. Not offered on tvOS — the TV UI is designed
        /// dark and a per-app light mode makes no sense there.
        @AppStorage(AppAppearance.storageKey)
        private var appearanceRaw = AppAppearance.defaultValue.rawValue
    #endif

    #if os(tvOS)
        @AppStorage(DreamCASTAccentTheme.storageKey) private var accentThemeRaw = DreamCASTAccentTheme.defaultValue.rawValue
        @AppStorage(DreamCASTVisualSettings.liquidGlassKey)
        private var dashboardLiquidGlass = DreamCASTVisualSettings.defaultLiquidGlass
        @AppStorage(DreamCASTVisualSettings.transparencyKey)
        private var dashboardTransparency = DreamCASTVisualSettings.defaultTransparency

        /// Legacy single-engine key, kept in sync with the primary engine so a
        /// downgrade still finds the user's preferred engine, and read as the
        /// migration seed for the priority list. See `PlayerEnginePriority`.
        /// Not `private`: engine / playback preferences are read by the
        /// SettingsView+TVPlayer extension (separate file, tvOS player pane).
        @AppStorage(PlayerSettings.engineKey) var engineRaw: String = PlayerEngineKind.defaultValue.rawValue
        @AppStorage(PlayerSettings.enginePriorityKey) var enginePriorityRaw: String = ""
        @AppStorage(PlayerSettings.externalPlayerKey) var externalPlayerRaw: String = ""
        @AppStorage(PlayerSettings.externalPlayerScopeKey)
        var externalPlayerScopeRaw: String = ExternalPlayerScope.default.rawValue
        @AppStorage(PlayerSettings.liveSurfModeKey)
        var liveSurfModeRaw: String = LiveSurfMode.default.rawValue
        @AppStorage(PlayerSettings.tvRemoteSwipesKey)
        var tvRemoteSwipes = PlayerSettings.tvRemoteSwipesDefault
        @AppStorage(PlayerSettings.Playback.autoPlayNextKey)
        var autoPlayNext = PlayerSettings.Playback.autoPlayNextDefault
        /// tvOS only: off tvOS the transport row carries an always-available
        /// Next Episode button, so `PlayerNextUpOverlay`'s outro-armed one —
        /// and with it this switch — has nothing left to control.
        @AppStorage(PlayerSettings.Playback.showNextEpisodeButtonKey)
        var showNextEpisodeButton = PlayerSettings.Playback.showNextEpisodeButtonDefault
        @AppStorage(PlayerSettings.Playback.showSkipIntroButtonKey)
        var showSkipIntroButton = PlayerSettings.Playback.showSkipIntroButtonDefault
        /// Comma-separated preferred languages, empty meaning no preference (see `PreferredLanguageList`).
        @AppStorage(PlayerSettings.Language.preferredAudioLanguagesKey)
        var preferredAudioLanguagesRaw = PlayerSettings.Language.preferredAudioLanguagesDefault
        @AppStorage(PlayerSettings.StreamInfo.detailLevelKey)
        var streamInfoDetailLevelRaw = PlayerSettings.StreamInfo.detailLevelDefault.rawValue
        /// Not `private`: read by the SettingsView+Library extension (separate file).
        @AppStorage(SearchSettings.searchAllPlaylistsKey)
        var searchAllPlaylists = SearchSettings.searchAllPlaylistsDefault
        @AppStorage(SportsSyncService.tabEnabledKey) var sportsTabEnabled = SportsSyncService.tabEnabledDefault
        /// Not `private`: read by the SettingsView+AutoSync extension (separate file).
        @AppStorage(SyncFrequency.storageKey) var syncFrequencyRaw: String = SyncFrequency.defaultValue.rawValue

        /// Routes the switch through the blocking overlay (see PlaylistSwitchModel).
        /// Not `private`: read by the SettingsView+Playlists extension.
        @Environment(PlaylistSwitchModel.self) var playlistSwitch: PlaylistSwitchModel?
        /// Carries the page another surface (the quick-switch overlay) asked
        /// Settings to open on.
        @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?
        /// Not `private`: the Add Playlist row (SettingsView+Playlists) presents it.
        @State var showingAddPlaylist = false
        /// The category whose content is shown in the right pane. Changes only
        /// when a rail row is activated (Live TV's model): moving focus through
        /// the rail just highlights.
        @State private var selectedCategory: SettingsCategory = .profiles
        @State private var dashboardSection: TVDashboardSection = .general
        @State private var dashboardStatus: String?
        @State private var showingStartupChoices = false
        @State private var showingEPGRefreshChoices = false
        @AppStorage("dreamcast.tv.startupTab") private var startupTabRaw = "liveTV"
        @AppStorage("dreamcast.tv.autoResumeLastChannel") private var autoResumeLastChannel = true
        @AppStorage("dreamcast.tv.confirmExit") private var confirmExit = true
        @AppStorage(SyncFrequency.epgStorageKey) private var dashboardEPGFrequency = SyncFrequency.epgDefaultValue.rawValue
        @Environment(SportsZonePlaybackSession.self) private var dashboardPlayback: SportsZonePlaybackSession?
        @Environment(AutoSyncQueue.self) private var dashboardSyncQueue: AutoSyncQueue?
        /// Bumped to hand focus to the rail's selected category — Menu from a
        /// pane's top level, or the tab-bar entry catcher.
        @State private var railFocusRequest = 0
        /// Bumped as activating a category sends focus into its pane, so the
        /// rail keeps it should the pane have nothing to focus (About).
        @State private var paneFocusRequest = 0
        /// Whether focus is settled in the rail, for the tab-bar entry catcher.
        @State private var railFocused = false
        /// The playlist drilled into within the Playlists category. When set, its
        /// settings replace the playlist list *in the detail pane* rather than
        /// pushing a full-screen view — a push hides the header tab bar and
        /// strands remote focus once the content scrolls. Not `private`: read by
        /// the SettingsView+Playlists extension (separate file).
        @State var selectedPlaylist: Playlist?
        /// Whether Library's Categories & Channels is drilled into, replacing the
        /// whole detail pane (same reasoning as `selectedPlaylist`). Not
        /// `private`: set by the SettingsView+Library extension (separate file).
        @State var showingContentManagement = false
        /// Combined View drilled into, like `showingContentManagement`. Not
        /// `private`: set by the SettingsView+Playlists extension.
        @State var showingCombinedView = false
        /// Focus handle on the Content Management pane, written once the pane
        /// has replaced the Library detail (see `beginContentManagementHandoff`).
        @FocusState private var contentManagementFocused: Bool
        /// Where focus belongs while Content Management swaps the whole pane
        /// in or out — the drill-in, the PIN pad giving way to it, or Menu
        /// closing it. See `beginPaneHandoff`.
        @State private var paneHandoff: TVSettingsPaneHandoff?
        @State private var paneHandoffTimeout: Task<Void, Never>?
        /// Whether focus is anywhere in the detail pane. Together with
        /// `railFocused` it tells whether focus is outside Settings — up in
        /// the tab bar — which is when `tvTabBarEntryCatcher` takes it.
        @FocusState private var detailFocused: Bool
        /// The rows that open a sub-page, so Menu can put focus back on the
        /// one it leaves. Not `private`: the panes' extensions tag their rows.
        @FocusState var drillInFocus: TVSettingsDrillIn?
        /// Whether the Player category is drilled into Engines — the priority
        /// list and the per-engine option rows — in place. Not `private`: read
        /// by the SettingsView+TVPlayer extension (separate file).
        @State var showingEngines = false
        /// Whether the Player category is drilled into OpenSubtitles in place.
        /// Not `private`: set by the SettingsView+TVPlayer extension (separate file).
        @State var showingOpenSubtitles = false
        /// Whether the Player category is drilled into Subtitle Style in place.
        /// Not `private`: set by the SettingsView+TVPlayer extension (separate file).
        @State var showingSubtitleStyle = false
        /// Whether the Player category is drilled into Philips Hue in place.
        @State var showingHue = false
        /// Whether the Live TV category is drilled into the Recording Server
        /// pane, in place (same reasoning as `selectedPlaylist`).
        @State private var showingRecordingServer = false
        /// How far the Recording Server pane is drilled in, in place. `nil` is
        /// its top level.
        @State private var recordingServerRoute: TVRecordingServerRoute?
        /// The Sync pane's Lume Cloud drill-in, in place; `nil` is its top level.
        @State private var syncRoute: TVLumeCloudRoute?
        /// Bumped by a pane to scroll the detail back to its top.
        @State private var tvDetailScrollToTopRequest = 0
        @State private var tvDetailScrollToCacheRequest = 0
        /// The engine whose options are drilled into from Engines, replacing it
        /// in place (same reasoning as `selectedPlaylist`). Not `private`: read by
        /// the SettingsView+TVPlayer extension (separate file).
        @State var selectedEngineOptions: PlayerEngineKind?
        /// Which preferred-language pane is drilled into within the Player
        /// category — the ordered list, or its add picker one level deeper —
        /// replacing the player detail in place (same reasoning as
        /// `selectedEngineOptions`). Not `private`: read by the
        /// SettingsView+TVPlayer extension (separate file).
        @State var preferredLanguagePane: PreferredLanguagePane?

        enum PreferredLanguagePane {
            case list, add
        }

        /// Home layout preferences, shown in the Home category. Not `private`: read
        /// by the SettingsView+TVHome extension (separate file). The iOS/macOS build
        /// has its own `HomeLayoutSettingsView`, so these live in the tvOS block.
        @AppStorage(RecommendationSettings.enabledKey) var recommendationsEnabled = RecommendationSettings.enabledDefault
        @AppStorage(HomeLayoutSettings.sectionOrderKey) var homeSectionOrderRaw = ""
        @AppStorage(HomeLayoutSettings.disabledSectionsKey) var homeDisabledSectionsRaw = ""
        @AppStorage(HomeLayoutSettings.enabledSectionsKey) var homeEnabledSectionsRaw = ""
        @AppStorage(HomeLayoutSettings.recentlyWatchedIncludesLiveTVKey)
        var homeRecentlyWatchedIncludesLiveTV = HomeLayoutSettings.recentlyWatchedIncludesLiveTVDefault

        /// The user's ordered engine fallback list (migrates the legacy single-engine
        /// key on first read). The first entry is the primary engine. Not `private`:
        /// read by the SettingsView+TVPlayer extension (separate file).
        var enginePriority: [PlayerEngineKind] {
            PlayerEnginePriority.resolve(priorityRaw: enginePriorityRaw, legacyEngineRaw: engineRaw)
        }
    #endif

    #if !os(tvOS)
        /// Pages pushed above the root, seeded when Settings opens on a route.
        @State private var path: [SettingsRoute]
    #endif

    /// - Parameter route: The page to open on instead of the root. tvOS's
    ///   two-pane layout has no push stack to seed, so it ignores it.
    init(opening route: SettingsRoute? = nil) {
        #if !os(tvOS)
            _path = State(initialValue: route?.stack ?? [])
        #endif
    }

    /// Whether this build has credentials for any Connected Services entry.
    private var hasConnectedServices: Bool {
        TraktService.shared.isConfigured || SimklService.shared.isConfigured || MDBListService.shared.isConfigured
    }

    private func showsBadge(for category: SettingsCategory) -> Bool {
        category == .iCloud && LumeCloudSettings.showsRecoveryKeyBadge(backend: cloudSync?.status.backend, viewed: lumeCloudRecoveryKeyViewed)
    }

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            standardBody
        #endif
    }

    // MARK: - iOS / macOS (grouped list)

    #if !os(tvOS)
        private var standardBody: some View {
            NavigationStack(path: $path) {
                List {
                    ForEach(SettingsCategory.grouped(hasConnectedServices: hasConnectedServices), id: \.group) { entry in
                        Section {
                            ForEach(entry.categories) { category in
                                row(for: category)
                            }
                        } header: {
                            if let title = entry.group.title {
                                Text(title)
                            }
                        }
                    }
                    HelpFeedbackSection()
                    AboutSection()
                }
                #if os(macOS)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                #endif
                .platformNavigationTitle("Settings")
                .navigationDestination(for: SettingsRoute.self) { SettingsRouteDestination(route: $0) }
                .paywall(isPresented: $showPaywall, highlight: paywallHighlight)
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 540, minHeight: 480, idealHeight: 600)
            #endif
        }

        @ViewBuilder
        private func row(for category: SettingsCategory) -> some View {
            if category == .premium, !premium.isPremium {
                // The free plan's row opens the paywall itself rather than a
                // page that would only repeat it.
                Button {
                    presentPaywall(nil)
                } label: {
                    HStack(spacing: 8) {
                        SettingsCategoryRowLabel(category: category, value: Text("Free"))
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    SettingsCategoryDestination(category: category)
                } label: {
                    SettingsCategoryRowLabel(category: category, value: value(for: category), showsBadge: showsBadge(for: category))
                }
            }
        }

        /// The trailing value: only for single-choice pages, plus the Lume Pro
        /// and Sync status.
        private func value(for category: SettingsCategory) -> Text? {
            switch category {
            case .premium:
                Text(premium.isPremium ? "Pro" : "Free")
            case .appearance:
                Text((AppAppearance(rawValue: appearanceRaw) ?? .defaultValue).title)
            case .iCloud:
                cloudSync.map { Text(CloudSyncStatusText.summary($0.status)) }
            default:
                nil
            }
        }
    #endif
}

// MARK: - tvOS DreamCAST Settings Dashboard

#if os(tvOS)

    /// Display groups from the approved Settings dashboard mockup.
    /// They route into the existing Settings panes, preserving their tools.
    private enum TVDashboardSection: String, CaseIterable {
        case general, playback, liveGuide, sports, backup, appearance, dataSources, about
        case advanced // Opens existing account options without adding a rail row.

        static let sidebar: [Self] = [
            .general, .playback, .liveGuide, .sports,
            .backup, .appearance, .dataSources, .about
        ]

        var title: String {
            switch self {
            case .general: "General"
            case .playback: "Playback"
            case .liveGuide: "Live TV & Guide"
            case .sports: "SportsZone"
            case .backup: "Backup & Restore"
            case .appearance: "Appearance"
            case .dataSources: "Data Sources"
            case .about: "About"
            case .advanced: "More Settings"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .playback: "play.rectangle"
            case .liveGuide: "list.bullet.rectangle"
            case .sports: "trophy"
            case .backup: "icloud.and.arrow.up"
            case .appearance: "tv"
            case .dataSources: "globe"
            case .about: "info.circle"
            case .advanced: "slider.horizontal.3"
            }
        }

        var legacyCategory: SettingsCategory? {
            switch self {
            case .general: nil
            // Appearance owns the former Library controls and Content Management editor.
            case .appearance: .library
            case .playback: .player
            case .liveGuide: .liveTV
            case .sports: .sports
            case .backup: .storage
            case .dataSources: .playlists
            case .about: .about
            case .advanced: .profiles
            }
        }
    }

    extension SettingsView {
        private var tvBody: some View {
            NavigationStack {
                HStack(alignment: .top, spacing: TVSidebarRail.paneSpacing) {
                    TVSidebarRail(
                        items: dashboardRailItems,
                        selectedID: dashboardSection == .advanced
                            ? TVDashboardSection.general.rawValue
                            : dashboardSection.rawValue,
                        focusRequest: railFocusRequest,
                        focusHandOffRequest: paneFocusRequest,
                        masksFocus: paneHandoff != nil,
                        onFocusChange: railFocusDidChange
                    )

                    GeometryReader { geometry in
                        let rightWidth = min(620, max(440, geometry.size.width * 0.46))
                        HStack(alignment: .top, spacing: 28) {
                            tvDashboardDetail
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .topLeading)
                                .focused($detailFocused)
                            tvDashboardRightColumn(width: rightWidth)
                                .frame(width: rightWidth)
                        }
                        .frame(width: geometry.size.width,
                               height: geometry.size.height, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 35)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onExitCommand {
                    NotificationCenter.default.post(
                        name: .dreamCASTReturnToTopMenu, object: nil
                    )
                }
                .overlay(alignment: .top) { tvTabBarEntryCatcher }
                .paywall(isPresented: $showPaywall, highlight: paywallHighlight)
                .fullScreenCover(isPresented: $showingAddPlaylist) {
                    LoginView(isModal: true)
                }
                .onChange(of: router?.pendingSettingsRoute, initial: true) { _, route in
                    guard let route else { return }
                    open(route)
                }
            }
        }

        private var dashboardRailItems: [TVSidebarRailItem] {
            TVDashboardSection.sidebar.map { section in
                TVSidebarRailItem(
                    id: section.rawValue, title: Text(section.title),
                    icon: section.icon
                ) {
                    openDashboard(section)
                }
            }
        }

        private func openDashboard(_ section: TVDashboardSection) {
            dashboardSection = section
            if let category = section.legacyCategory {
                selectedCategory = category
            }
            closeDrillIns()
            paneFocusRequest += 1
            Task { @MainActor in detailFocused = true }
        }

        private func dashboardOpenLegacy(_ category: SettingsCategory) {
            dashboardSection = category == .library ? .appearance : .advanced
            selectedCategory = category
            closeDrillIns()
            paneFocusRequest += 1
            Task { @MainActor in detailFocused = true }
        }

        @ViewBuilder
        private var tvDashboardDetail: some View {
            if dashboardSection == .general {
                ScrollView(.vertical) {
                    tvDashboardGeneral
                        .padding(.bottom, 90)
                }
                .scrollIndicators(.visible)
                .focusSection()
            } else if dashboardSection == .appearance {
                if showingContentManagement {
                    // Keep the existing PIN gate and editor. The editor must
                    // replace the scroll pane rather than nest inside one.
                    tvDetailContainer
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                        .onExitCommand(perform: handleDetailMenu)
                } else {
                    ScrollView(.vertical) {
                        tvDashboardAppearance
                            .padding(.bottom, 100)
                    }
                    .scrollIndicators(.visible)
                    .focusSection()
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text(dashboardSection == .advanced
                         ? "More Settings" : dashboardSection.title)
                        .font(.system(size: 43, weight: .bold, design: .rounded))
                    tvDetailContainer
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                }
            }
        }

        private func tvDashboardRightColumn(width: CGFloat) -> some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 25) {
                    if dashboardPlayback?.miniMedia != nil {
                        // App root owns the only decoder. This is its actual
                        // measured slot, not a second or floating player.
                        TVEmbeddedPlayerSlot(
                            width: width,
                            height: width * 9 / 16 + TVPersistentMiniPlayer.controlsHeight
                        )
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "play.tv")
                                .font(.system(size: 54))
                                .foregroundStyle(TVNeonTheme.iceBlue)
                            Text("Your live channel will appear here")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .frame(width: width,
                               height: width * 9 / 16 + TVPersistentMiniPlayer.controlsHeight)
                        .background(TVNeonTheme.glass,
                                    in: RoundedRectangle(cornerRadius: 22))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(TVNeonTheme.iceBlue.opacity(0.4), lineWidth: 1)
                        }
                    }

                    Text("Quick Actions")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(TVNeonTheme.iceBlue)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 13),
                        GridItem(.flexible(), spacing: 13)
                    ], spacing: 13) {
                        tvDashboardQuickAction("Backup Settings",
                                               detail: "Save settings to a file",
                                               symbol: "externaldrive") {
                            openDashboard(.backup)
                        }
                        tvDashboardQuickAction("Restore Settings",
                                               detail: "Load settings from a file",
                                               symbol: "square.and.arrow.up") {
                            openDashboard(.backup)
                        }
                        tvDashboardQuickAction("Refresh All Data",
                                               detail: "EPG · Sports · Playlists",
                                               symbol: "arrow.clockwise") {
                            dashboardSyncQueue?.enqueueManualMembers(
                                scope: catalogScope, playlists: playlists,
                                frequency: SyncFrequency.resolve(syncFrequencyRaw),
                                context: modelContext
                            )
                            EPGSyncService.shared.syncNow()
                            SportsSyncService.shared.syncNow()
                            dashboardStatus = "Refreshing guide, sports and playlists."
                        }
                        tvDashboardQuickAction("Clear Cache",
                                               detail: "Manage cached storage",
                                               symbol: "paintbrush") {
                            openDashboard(.backup)
                            dashboardStatus = "Choose image, metadata or other caches to clear."
                            Task { @MainActor in
                                // Wait until the storage pane is in the tree.
                                await Task.yield()
                                tvDetailScrollToCacheRequest += 1
                            }
                        }
                    }
                    if let dashboardStatus {
                        Text(dashboardStatus)
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 90)
            }
            .scrollIndicators(.visible)
            .focusSection()
        }

        private func tvDashboardQuickAction(
            _ title: String,
            detail: String,
            symbol: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: 15) {
                    Text(Image(systemName: symbol))
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(TVNeonTheme.iceBlue)
                        .frame(width: 44, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(detail)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 17)
                .frame(height: 102)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TVDashboardCardStyle())
        }

        private var tvDashboardGeneral: some View {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.system(size: 45, weight: .bold, design: .rounded))
                Text("Customize your DreamCAST TV 2 experience")
                    .font(.system(size: 21))
                    .foregroundStyle(.white.opacity(0.75))

                Text("General")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(TVNeonTheme.iceBlue)
                    .padding(.top, 13)

                VStack(spacing: 0) {
                    // Use the same ButtonStyle as the other General rows.
                    // tvOS Menu applies its own large gray focus plate even
                    // when the label disables the system focus effect.
                    Button {
                        showingStartupChoices = true
                    } label: {
                        dashboardGeneralRow(
                            title: "Startup Screen", icon: "play.tv",
                            value: dashboardStartupLabel, showsArrow: true
                        )
                    }
                    .buttonStyle(TVDashboardCardStyle())
                    .confirmationDialog(
                        "Startup Screen",
                        isPresented: $showingStartupChoices,
                        titleVisibility: .visible
                    ) {
                        Button("Live TV") { startupTabRaw = "liveTV" }
                        Button("SportsZone") { startupTabRaw = "sports" }
                        Button("Movies") { startupTabRaw = "movies" }
                        Button("Series") { startupTabRaw = "series" }
                        Button("Search") { startupTabRaw = "search" }
                        Button("Settings") { startupTabRaw = "settings" }
                        Button("Cancel", role: .cancel) {}
                    }

                    dashboardGeneralDivider()
                    dashboardGeneralToggle(
                        "Auto Resume Last Channel",
                        icon: "clock.arrow.circlepath",
                        isOn: $autoResumeLastChannel
                    )
                    dashboardGeneralDivider()
                    dashboardGeneralToggle(
                        "Confirm Exit", icon: "power", isOn: $confirmExit
                    )
                    dashboardGeneralDivider()

                    Button {
                        showingEPGRefreshChoices = true
                    } label: {
                        dashboardGeneralRow(
                            title: "Auto Refresh (EPG)",
                            icon: "arrow.triangle.2.circlepath",
                            value: dashboardRefreshLabel, showsArrow: true
                        )
                    }
                    .buttonStyle(TVDashboardCardStyle())
                    .confirmationDialog(
                        "Auto Refresh (EPG)",
                        isPresented: $showingEPGRefreshChoices,
                        titleVisibility: .visible
                    ) {
                        ForEach(SyncFrequency.allCases) { frequency in
                            Button(frequency.label) {
                                dashboardEPGFrequency = frequency.rawValue
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }

                    dashboardGeneralDivider()
                    Button {
                        openDashboard(.playback)
                        selectedCategory = .player
                        showingSubtitleStyle = true
                    } label: {
                        dashboardGeneralRow(
                            title: "Default Subtitles", icon: "captions.bubble",
                            value: "Style", showsArrow: true
                        )
                    }
                    .buttonStyle(TVDashboardCardStyle())

                    dashboardGeneralDivider()
                    Button {
                        openDashboard(.playback)
                        selectedCategory = .player
                        preferredLanguagePane = .list
                    } label: {
                        dashboardGeneralRow(
                            title: "Preferred Audio Language",
                            icon: "globe", value: "Choose", showsArrow: true
                        )
                    }
                    .buttonStyle(TVDashboardCardStyle())
                }
                .padding(10)
                .background(TVNeonTheme.glass,
                            in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.19), lineWidth: 1)
                }

                Text("More Settings")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(TVNeonTheme.iceBlue)
                    .padding(.top, 12)

                VStack(spacing: 9) {
                    dashboardMoreRow("Profiles", icon: "person.crop.circle") {
                        dashboardOpenLegacy(.profiles)
                    }
                    dashboardMoreRow("Home Layout", icon: "house") {
                        dashboardOpenLegacy(.home)
                    }
                    dashboardMoreRow("TV Guide Sources", icon: "calendar") {
                        dashboardOpenLegacy(.epg)
                    }
                    if hasConnectedServices {
                        dashboardMoreRow("Connected Services", icon: "link") {
                            dashboardOpenLegacy(.connectedServices)
                        }
                    }
                    dashboardMoreRow("Help & Feedback", icon: "questionmark.circle") {
                        dashboardOpenLegacy(.help)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        private var dashboardStartupLabel: String {
            switch startupTabRaw {
            case "sports": "SportsZone"
            case "movies": "Movies"
            case "series": "Series"
            case "search": "Search"
            case "settings": "Settings"
            default: "Live TV"
            }
        }

        private var dashboardRefreshLabel: String {
            switch SyncFrequency.resolveEPG(dashboardEPGFrequency) {
            case .sixHours: "Every 6 Hours"
            case .daily: "Every Day"
            case .everyThreeDays: "Every 3 Days"
            case .weekly: "Every Week"
            }
        }

        private func dashboardGeneralRow(
            title: String, icon: String, value: String,
            showsArrow: Bool = false
        ) -> some View {
            HStack(spacing: 15) {
                Text(Image(systemName: icon))
                    .font(.system(size: 23))
                    .frame(width: 33, height: 36)
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 10)
                Text(value)
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                if showsArrow {
                    Text(Image(systemName: "chevron.right"))
                        .font(.system(size: 18))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 65)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }

        private func dashboardGeneralToggle(
            _ title: String, icon: String, isOn: Binding<Bool>
        ) -> some View {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                HStack(spacing: 15) {
                    Text(Image(systemName: icon))
                        .font(.system(size: 23))
                        .frame(width: 33, height: 36)
                    Text(title)
                        .font(.system(size: 20, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 10)
                    Capsule()
                        .fill(isOn.wrappedValue
                              ? TVNeonTheme.electricBlue : .white.opacity(0.24))
                        .frame(width: 61, height: 32)
                        .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                            Circle()
                                .fill(.white)
                                .frame(width: 27, height: 27)
                                .padding(3)
                        }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .frame(height: 65)
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(TVDashboardCardStyle())
            .accessibilityLabel(Text(title))
            .accessibilityValue(isOn.wrappedValue ? Text("On") : Text("Off"))
        }

        private func dashboardGeneralDivider() -> some View {
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
                .padding(.horizontal, 18)
        }

        private func dashboardMoreRow(
            _ title: String, icon: String, action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack(spacing: 13) {
                    Text(Image(systemName: icon))
                        .font(.system(size: 23))
                        .frame(width: 30, height: 34)
                    Text(title)
                        .font(.system(size: 19, weight: .medium))
                    Spacer(minLength: 0)
                    Text(Image(systemName: "chevron.right"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .frame(height: 57)
            }
            .buttonStyle(TVDashboardCardStyle())
        }

        private var tvDashboardAppearance: some View {
            VStack(alignment: .leading, spacing: 26) {
                Text("Appearance")
                    .font(.system(size: 43, weight: .bold, design: .rounded))
                Text("Choose visible tabs, organize categories and channels, and set search scope.")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.73))

                // Reuse the existing playlist-aware bindings and PIN-gated
                // Content Management action. Do not create duplicate settings.
                tvLibraryDetail

                Text("Color Theme")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    ForEach(DreamCASTAccentTheme.allCases) { theme in
                        Button {
                            accentThemeRaw = theme.rawValue
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(theme.gradient)
                                    .frame(height: 42)
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color.opacity(0.5)))
                                HStack {
                                    Text(theme.title)
                                        .font(.system(size: 18, weight: .medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 4)
                                    if accentThemeRaw == theme.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(theme.selectionAccent)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TVDashboardCardStyle())
                        .accessibilityAddTraits(accentThemeRaw == theme.rawValue ? [.isSelected] : [])
                    }
                }
                Text("Choose matching accent colors and gradient backgrounds. Changes save automatically.")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.65))

                Text("Surface Style")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(TVNeonTheme.iceBlue)
                TVOptionToggleRow(title: "Liquid Glass", isOn: $dashboardLiquidGlass)
                HStack(spacing: 20) {
                    Text("Transparency")
                        .font(.system(size: 22))
                    Slider(value: $dashboardTransparency, in: 0 ... 0.85, step: 0.05)
                    Text("\(Int(dashboardTransparency * 100))%")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Text("Adjust dock cards, menu surfaces, and selected controls.")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.65))

                Text("Display & Layout")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(TVNeonTheme.iceBlue)
                    .padding(.top, 10)

                dashboardMoreRow("Live TV Guide Design", icon: "tv") {
                    dashboardOpenLegacy(.liveTV)
                }
                dashboardMoreRow("Subtitle Appearance", icon: "captions.bubble") {
                    dashboardOpenLegacy(.player)
                    showingSubtitleStyle = true
                }
                dashboardMoreRow("Home Sections & Top Shelf", icon: "square.grid.2x2") {
                    dashboardOpenLegacy(.home)
                }
                Text("DreamCAST TV uses a dark interface on Apple TV.")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        /// Opens Playlists the way activating its rail row does, then drills
        /// into Combined View when the route asks for it.
        private func open(_ route: SettingsRoute) {
            router?.pendingSettingsRoute = nil
            activate(.playlists)
            guard route == .combinedView else { return }
            beginContentManagementHandoff()
            showingCombinedView = true
            // Deferred: the pane only exists a render later.
            Task { @MainActor in contentManagementFocused = true }
        }

        /// Match the leading symbols and glass rail in the Live TV mockup.
        private var railItems: [TVSidebarRailItem] {
            SettingsCategory.visible(hasConnectedServices: hasConnectedServices).map { category in
                let badge = showsBadge(for: category)
                return TVSidebarRailItem(
                    id: category.id, title: Text(category.title),
                    icon: badge ? "exclamationmark.circle" : tvRailIcon(for: category),
                    iconAccessibilityLabel: badge ? Text("Recovery key not viewed") : nil
                ) {
                    activate(category)
                }
            }
        }

        private func tvRailIcon(for category: SettingsCategory) -> String {
            switch category {
            case .premium: "crown"
            case .profiles: "person.crop.circle"
            case .playlists: "rectangle.stack"
            case .epg: "calendar"
            case .library: "square.stack.3d.up"
            case .home: "house"
            case .liveTV: "tv"
            case .sports: "trophy"
            case .appearance: "paintbrush"
            case .player: "play.rectangle"
            case .downloads: "arrow.down.circle"
            case .iCloud: "cloud"
            case .connectedServices: "link"
            case .storage: "externaldrive"
            case .help: "questionmark.circle"
            case .about: "info.circle"
            case .developer: "hammer"
            }
        }

        /// Opens `category` at its top level — also the open one, which backs
        /// out of any sub-page — and moves focus into its pane.
        private func activate(_ category: SettingsCategory) {
            // Pending deep links still reach their real settings pane.
            dashboardSection = category == .playlists ? .dataSources :
                (category == .library ? .appearance : .advanced)
            selectedCategory = category
            closeDrillIns()
            paneFocusRequest += 1
            // Deferred: the pane only holds the new category's rows a render
            // later.
            Task { @MainActor in detailFocused = true }
        }

        private func closeDrillIns() {
            selectedPlaylist = nil
            showingContentManagement = false
            showingCombinedView = false
            showingEngines = false
            showingOpenSubtitles = false
            showingSubtitleStyle = false
            showingHue = false
            showingRecordingServer = false
            recordingServerRoute = nil
            syncRoute = nil
            selectedEngineOptions = nil
            preferredLanguagePane = nil
        }

        /// Menu in the pane backs out of the innermost sub-page onto the row
        /// that opened it, and from a pane's top level returns to the rail.
        private func handleDetailMenu() {
            guard let opener = closeInnermostDrillIn() else {
                // A top-level pane returns directly to the app's tab bar.
                NotificationCenter.default.post(
                    name: .dreamCASTReturnToTopMenu,
                    object: nil
                )
                return
            }
            // Deferred: the row only exists again a render later, and a
            // same-frame write from a Menu callback is dropped anyway.
            Task { @MainActor in drillInFocus = opener }
        }

        /// Closes the sub-page on top and returns the row that opened it; nil
        /// at the pane's top level. Checked in the order `tvDetail` draws
        /// them, so the visible one closes.
        private func closeInnermostDrillIn() -> TVSettingsDrillIn? {
            switch selectedCategory {
            case .playlists:
                return closeInnermostPlaylistsDrillIn()
            case .library:
                guard showingContentManagement else { return nil }
                beginPaneHandoff(.drillIn(.contentManagement))
                showingContentManagement = false
                return .contentManagement
            case .liveTV:
                // The pairing step backs out to the pane's top level itself.
                guard showingRecordingServer else { return nil }
                showingRecordingServer = false
                recordingServerRoute = nil
                return .recordingServer
            case .player:
                return closeInnermostPlayerDrillIn()
            case .iCloud:
                guard let route = syncRoute else { return nil }
                syncRoute = nil
                return route.opener
            default:
                return nil
            }
        }

        private func closeInnermostPlaylistsDrillIn() -> TVSettingsDrillIn? {
            if showingCombinedView {
                beginPaneHandoff(.drillIn(.combinedView))
                showingCombinedView = false
                return .combinedView
            }
            guard let playlist = selectedPlaylist else { return nil }
            selectedPlaylist = nil
            return .playlist(playlist.id)
        }

        private func railFocusDidChange(_ isFocused: Bool) {
            railFocused = isFocused
            guard let paneHandoff else { return }
            if isFocused {
                // Deferred: a same-frame write from a focus callback is dropped.
                Task { @MainActor in
                    switch paneHandoff {
                    case .contentManagement: contentManagementFocused = true
                    case let .drillIn(row): drillInFocus = row
                    }
                }
            } else {
                endPaneHandoff()
            }
        }

        /// Replacing the pane wholesale removes the focused view with the
        /// scroll view around it — the Categories & Channels row, the PIN pad
        /// once it unlocks, or Content Management itself on Menu — and the
        /// engine then drops focus on the rail's selected row. The handoff
        /// passes that focus on to `target` and, until focus has left the rail
        /// again, draws the rail unfocused so Library never flashes. A timeout
        /// closes it should focus never pass through the rail, so it can't
        /// swallow the user's own later move there.
        private func beginPaneHandoff(_ target: TVSettingsPaneHandoff) {
            paneHandoff = target
            paneHandoffTimeout?.cancel()
            paneHandoffTimeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                endPaneHandoff()
            }
        }

        /// Not `private`: the Library pane's row calls it
        /// (SettingsView+Library).
        func beginContentManagementHandoff() {
            beginPaneHandoff(.contentManagement)
        }

        private func endPaneHandoff() {
            paneHandoffTimeout?.cancel()
            paneHandoffTimeout = nil
            paneHandoff = nil
        }

        /// Pressing down from the tab bar lands on whatever sits under the
        /// Settings tab — the detail pane's top row, never the rail, which is
        /// far off to the left. This invisible full-width strip across the top
        /// is nearer than any of them, so it catches that move and hands it to
        /// the rail's selected category. It's focusable only while focus is
        /// outside Settings, so moving up from the panes still reaches the tab
        /// bar.
        private var tvTabBarEntryCatcher: some View {
            TVTabBarEntryCatcher(isEnabled: !railFocused && !detailFocused) {
                railFocusRequest += 1
            }
            .accessibilityHidden(true)
            // Raised into the gap between the tab bar and the screen's top,
            // as Live TV's is: the tab bar ends at y ≈ 114 and the screen
            // starts at 158 (tvOS 26.5), so the band sits at y ≈ 130.
            .alignmentGuide(.top) { $0[.top] + 28 }
        }

        /// Content Management and Combined View bring their own scroll view
        /// (both host a `TVReorderableContentList`), so they replace the detail
        /// pane wholesale rather than nesting inside the scrolling detail.
        @ViewBuilder
        private var tvDetailContainer: some View {
            if selectedCategory == .library, showingContentManagement {
                ParentalGateView {
                    ContentManagementView()
                        .onAppear(perform: beginContentManagementHandoff)
                }
                .focusSection()
                .focused($contentManagementFocused)
            } else if selectedCategory == .playlists, showingCombinedView {
                TVCombinedViewSettingsPane(beginHandoff: beginContentManagementHandoff)
                    .focusSection()
                    .focused($contentManagementFocused)
            } else {
                tvDetail
            }
        }

        private var tvDetail: some View {
            ScrollViewReader { proxy in
                tvDetailScrollView
                    .onChange(of: tvDetailScrollToTopRequest) {
                        withAnimation { proxy.scrollTo(Self.tvDetailTopID, anchor: .top) }
                    }
                    .onChange(of: tvDetailScrollToCacheRequest) {
                        withAnimation { proxy.scrollTo("settings.storage.cache", anchor: .top) }
                    }
            }
        }

        private static let tvDetailTopID = "settings.detail.top"

        private var tvDetailScrollView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    switch selectedCategory {
                    case .premium:
                        tvPremiumDetail
                    case .profiles:
                        TVProfilesSettingsView()
                    case .playlists:
                        if let selectedPlaylist {
                            PlaylistDetailView(playlist: selectedPlaylist) {
                                self.selectedPlaylist = nil
                            }
                        } else {
                            tvPlaylistsDetail
                        }
                    case .epg:
                        EPGSettingsView()
                    case .library:
                        tvLibraryDetail
                    case .home:
                        tvHomeLayoutDetail
                    case .liveTV:
                        if showingRecordingServer {
                            TVRecordingServerSettingsView(route: $recordingServerRoute)
                        } else {
                            TVLiveTVSettingsPane(
                                showingRecordingServer: $showingRecordingServer,
                                drillInFocus: $drillInFocus
                            ) { presentPaywall($0) }
                        }
                    case .sports:
                        TVSportsSettingsPane()
                    case .player:
                        if showingHue {
                            TVHueSettingsPane { presentPaywall($0) }
                        } else if showingOpenSubtitles {
                            TVOpenSubtitlesIntegrationView()
                        } else if showingSubtitleStyle {
                            TVSubtitleStyleSettingsView()
                        } else if let selectedEngineOptions {
                            tvEngineOptionsDetail(for: selectedEngineOptions)
                        } else if showingEngines {
                            tvEnginesDetail
                        } else if let preferredLanguagePane {
                            tvPreferredLanguageDetail(preferredLanguagePane)
                        } else {
                            tvPlayerDetail
                        }
                    case .iCloud:
                        TVSyncSettingsPane(route: $syncRoute, drillInFocus: $drillInFocus) { tvDetailScrollToTopRequest += 1 }
                    case .connectedServices:
                        TVConnectedServicesView()
                    case .storage:
                        TVLocalBackupSettingsPane()
                        StorageManagementView()
                            .id("settings.storage.cache")
                    case .help:
                        tvHelpDetail
                    case .about:
                        tvAboutDetail
                    case .appearance, .downloads, .developer:
                        EmptyView() // not offered on tvOS
                    }
                }
                // Lume Pro lays its benefits out in two columns across the
                // whole pane.
                .tvSettingsPaneContent(maxWidth: selectedCategory == .premium ? .infinity : TVSettingsMetrics.detailMaxWidth)
                // Give the final row space to scroll fully above the TV edge.
                .padding(.bottom, 100)
                .id(Self.tvDetailTopID)
            }
            // A fresh scroll position per category; sub-pages keep theirs.
            .id(selectedCategory)
            .scrollIndicators(.visible)
            .focusSection()
        }
    }

#endif
