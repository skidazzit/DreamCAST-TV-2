//
//  MainTabView.swift
//  Lume
//
//  Main tab-based navigation for the app
//

import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    // Optional so previews (which don't inject it) don't crash.
    @Environment(PlaylistSwitchModel.self) private var playlistSwitch: PlaylistSwitchModel?
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Query private var playlists: [Playlist]
    /// Categories marked restricted, and categories hidden in Content
    /// Management. Fetched once here so a single source feeds the restriction
    /// context every content surface reads from the environment.
    @Query(filter: #Predicate<Category> { $0.isRestricted }) private var restrictedCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isHidden }) private var hiddenCategories: [Category]

    @AppStorage(SyncFrequency.storageKey) private var syncFrequencyRaw: String = SyncFrequency.defaultValue.rawValue
    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""
    /// Whether the Sports tab appears in the tab bar (Settings toggle). When off,
    /// the hub is still reachable from the Home rail header.
    @AppStorage(SportsSyncService.tabEnabledKey) private var sportsTabEnabled = SportsSyncService.tabEnabledDefault

    /// Selected tab and the Movies/Series navigation stacks, shared so an
    /// `onOpenURL` deep link can switch tabs and push a detail screen.
    @State private var router = DeepLinkRouter()
    #if os(tvOS)
    /// This session belongs to the app root, not a tab. No tab switch unmounts it.
    @State private var sharedLivePlayback = SportsZonePlaybackSession()
    @State private var restoredLastLiveOnLaunch = false
    @State private var backFocus = TVBackFocusCoordinator()
    @State private var ambientTheme = TVAmbientThemeSession()
    @State private var livePlayerSlotFrame: CGRect?
    @FocusState private var focusedTVTab: AppTab?
    @State private var lastTopMenuBackPress: Date?
    @State private var showingExitConfirmation = false
    @State private var startupTabApplied = false
    @AppStorage("dreamcast.tv.startupTab") private var startupTabRaw = "liveTV"
    @AppStorage("dreamcast.tv.autoResumeLastChannel") private var autoResumeLastChannel = true
    @AppStorage("dreamcast.tv.confirmExit") private var confirmExit = true
    // Observing all visual options at app root refreshes shared chrome
    // without replacing the persistent video player or changing tabs.
    @AppStorage(DreamCASTAccentTheme.storageKey)
    private var visualThemeRaw = DreamCASTAccentTheme.defaultValue.rawValue
    @AppStorage(DreamCASTVisualSettings.transparencyKey)
    private var visualTransparency = DreamCASTVisualSettings.defaultTransparency
    @AppStorage(DreamCASTVisualSettings.liquidGlassKey)
    private var visualGlass = DreamCASTVisualSettings.defaultLiquidGlass
    @AppStorage(LiveTVLayoutMode.storageKey) private var tvLiveLayoutRaw = LiveTVLayoutMode.defaultMode.rawValue
    private var usesLiveList: Bool { LiveTVLayoutMode(storedValue: tvLiveLayoutRaw) == .list }
    #endif

    /// The stream a `lume://resume` or `lume://play/...` (widget, Top Shelf)
    /// deep link asked to open. Presented directly here — the link can arrive
    /// on any tab — independent of any tab's own player cover.
    @State private var linkedMedia: PlayableMedia?

    /// Whether a `lume://downloads` deep link (a download Live Activity tap)
    /// asked for the downloads list. Presented as a sheet from here rather than
    /// pushed into Settings, so the link doesn't disturb whatever the user had
    /// open.
    @State private var showsDownloads = false
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    @State private var autoSyncQueue = AutoSyncQueue()
    @State private var premium = PremiumManager.shared

    /// Memo behind `contentRestriction` — see `ContentRestrictionMemo`.
    @State private var restrictionMemo = ContentRestrictionMemo()

    private var syncFrequency: SyncFrequency {
        SyncFrequency.resolve(syncFrequencyRaw)
    }

    /// The playlists the content tabs are showing, resolved rather than read
    /// raw: the stored id can name a deleted playlist, or Combined can fall back
    /// to its priority-1 member, and auto-sync has to follow every surface there.
    private var catalogScope: CatalogScope {
        playlists.scope(for: selectedPlaylistID, isPremium: premium.isPremium)
    }

    /// The content tabs in the tab bar: an isolated playlist's own choice
    /// (Settings › Library › Tabs), or in Combined every type a member
    /// contributes.
    private func visibleTabs(in scope: CatalogScope) -> Set<PlaylistTab> {
        scope.visibleTabs(isolatedHidden: playlists.primaryMember(of: scope)?.hiddenTabs ?? [])
    }

    private func showsTab(_ tab: AppTab) -> Bool {
        visibleTabs(in: catalogScope).showsTab(tab)
    }

    /// Whether the browse UI is covered: the sync cover, downloads, the add-device sheet (not a link
    /// still waiting for it), or a playlist / profile switch. Players, paywalls and Settings (a toolbar sheet this root can't see) report themselves.
    private var hasBlockingPresentation: Bool {
        hasOwnPresentation || router.presentedCloudPairing != nil
    }

    /// All of the above but the add-device sheet, which waits for these to clear.
    private var hasOwnPresentation: Bool {
        autoSyncQueue.coverPlaylist != nil
            || showsDownloads
            || playlistSwitch?.isSwitching == true
            || profileManager?.isSwitching == true
    }

    /// Hides categories (and their content) from every browse, Home and Search
    /// surface: the ones hidden in Content Management always, the restricted
    /// ones while a child profile is active.
    ///
    /// Routed through a memo: this root's body re-evaluates whenever any catalog
    /// write moves one of its `@Query`s, and constructing a `ContentRestriction`
    /// digests every excluded id — 433 of them on a real hidden-category set.
    /// The two id sets are cheap to rebuild and compare; the digest is not.
    private var contentRestriction: ContentRestriction {
        restrictionMemo.restriction(
            isActive: profileManager?.activeProfileIsChild ?? false,
            restricted: Set(restrictedCategories.map(\.id)),
            hidden: Set(hiddenCategories.map(\.id))
        )
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var autoSyncQueue = autoSyncQueue
        let scope = catalogScope
        let tabs = visibleTabs(in: scope)
        return persistentTabHost(selection: $router.selectedTab, tabs: tabs)
        #if os(tvOS)
            .task {
                // Apply the saved startup tab once. Never override user tab
                // changes later in the same app session.
                guard !startupTabApplied else { return }
                startupTabApplied = true
                let requested: AppTab
                switch startupTabRaw {
                case "sports": requested = .sports
                case "movies": requested = .movies
                case "series": requested = .series
                case "search": requested = .search
                case "settings": requested = .settings
                default: requested = .liveTV
                }
                // A cold launch with Live TV as the last played media
                // returns to its guide. VOD history never triggers playback.
                let resumeLive = autoResumeLastChannel
                    && LiveChannelHistory.shouldResumeLiveOnLaunch()
                    && LiveChannelHistory.currentChannelId() != nil
                    && isVisibleTVTab(.liveTV, tabs: tabs)
                if resumeLive {
                    router.selectedTab = .liveTV
                } else if isVisibleTVTab(requested, tabs: tabs) {
                    router.selectedTab = requested
                }
            }
            .disabled(blockingOverlayOwnsScreen || router.isQuickSwitchPresented)
            .onExitCommand {
                handleTVBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dreamCASTReturnToTopMenu)) { _ in
                // Legacy screen notifications now follow the shared three-step
                // Back route instead of jumping past the player and sidebar.
                handleTVBack()
            }
            .alert("Exit DreamCAST TV?", isPresented: $showingExitConfirmation) {
                Button("No", role: .cancel) {
                    lastTopMenuBackPress = nil
                }
                Button("Yes", role: .destructive) {
                    sharedLivePlayback.close()
                    // Only explicitly confirmed exits terminate the tvOS process.
                    exit(0)
                }
            } message: {
                Text("Close DreamCAST TV and return to Apple TV Home?")
            }
            // Attached OUTSIDE `.disabled` so the same button closes the modal it
            // opened, and above the tabs but below every player: the engines are
            // presented as `fullScreenCover`s from inside a tab, so their own
            // `onPlayPauseCommand` sits above this one in the focused chain and is
            // never shadowed. The guard covers the plain overlays instead, which
            // tvOS focus reaches straight through.
            .onPlayPauseCommand {
                guard playPauseTogglesQuickSwitch else { return }
                router.isQuickSwitchPresented.toggle()
            }
        #endif
            .environment(router)
            .environment(autoSyncQueue)
            .environment(\.contentRestriction, contentRestriction)
            .catalogScope(scope, playlists: playlists)
            // A tab switch is the one browse interaction that has no scroll
            // view of its own to stamp from, and it is the moment a merge is
            // most expensive — the incoming tab is re-running its queries.
            .onChange(of: router.selectedTab) {
                ContentIndexingService.shared.noteUserInteraction()
            }
            // Hiding the tab on screen, or switching to a playlist (or a
            // Combined set) without it, would leave the selection pointing at
            // nothing.
            .onChange(of: PlaylistTab.encode(tabs), initial: true) {
                #if os(tvOS)
                    // Home is removed from the Apple TV tab bar.
                    if !isVisibleTVTab(router.selectedTab, tabs: tabs) {
                        router.selectedTab = [AppTab.liveTV, .sports, .movies, .series, .search, .settings]
                            .first { isVisibleTVTab($0, tabs: tabs) } ?? .settings
                    }
                #else
                    if !showsTab(router.selectedTab) {
                        router.selectedTab = .home
                    }
                #endif
            }
        #if os(iOS)
            .tabBarMinimizeOnScrollDownIfAvailable()
            .castMiniController { linkedMedia = $0 }
        #endif
            .onOpenURL { url in
                handleDeepLink(url)
            }
        #if !os(macOS)
            .fullScreenCover(item: $linkedMedia) { media in
                FullScreenPlayerView(media: media)
            }
        #endif
            .task {
                // First-run restores may happen before the IPTV catalogs exist.
                // Apply matching favorites and watch progress once rows appear.
                try? DreamCASTLocalSettingsBackup.applyPendingViewingState(in: modelContext)
            }
            .onChange(of: playlists.map { "\($0.id)|\($0.syncStatusRaw)" }) { _, _ in
                try? DreamCASTLocalSettingsBackup.applyPendingViewingState(in: modelContext)
            }
            #if os(iOS) || os(tvOS)
            .task(id: "\(scope.token)|\(playlists.map { "\($0.id)|\($0.syncStatusRaw)" }.joined(separator: ";"))") {
                // Run at launch, and retry after a catalog import finishes.
                // Do not replay an old live channel when VOD played last.
                restoreLastLiveChannelOnLaunch()
            }
            #endif
            .task(id: playlists.count) {
                // On launch (and whenever a playlist is added) sync the active
                // playlist if it is due, plus any playlist that has never synced.
                enqueueDueSyncs(playlists)
            }
            .onChange(of: scope.token) {
                // On playlist switch, sync the newly selected one — or every due
                // Combined member — unless the switch asked to land in the
                // cached catalog instead. This is also where a playlist deferred
                // at launch for not being on screen gets its turn. Keyed on the
                // resolved scope rather than the stored selection, so a member
                // joining Combined, or Pro unlocking it, counts as a switch too.
                let deferred = playlistSwitch?.consumeDeferredDueSync() == true
                enqueueDueSyncs(deferred ? [] : playlists.members(of: catalogScope))
                #if os(tvOS)
                    // The initial library can appear after startup playback.
                    // Do not stop a permitted channel simply because its
                    // catalog scope finished loading. A real switch to a
                    // library without that channel still ends its session.
                    if let playing = sharedLivePlayback.miniMedia {
                        let stillVisible: Bool = {
                            guard case let .live(id) = playing.contentRef,
                                  let stream = PlayerContentLookup.liveStream(id, in: modelContext),
                                  !stream.isHidden,
                                  !contentRestriction.hides(categoryID: stream.categoryId),
                                  let owner = playlists.owner(ofContentID: stream.id)
                            else { return false }
                            return catalogScope.members(for: .liveTV).contains(owner.id)
                        }()
                        if !stillVisible { sharedLivePlayback.close() }
                    }
                #endif
            }
            .onChange(of: profileManager?.activeProfileIsChild) { _, _ in
                #if os(tvOS)
                    // Only terminate an actual session when profile access
                    // changes. Closing an empty player would set userStopped
                    // during initial profile loading and block auto-resume.
                    if sharedLivePlayback.miniMedia != nil {
                        sharedLivePlayback.close()
                    }
                #endif
            }
            .onChange(of: contentRestriction.visibilityToken) {
                #if os(tvOS)
                    // Hiding or restricting a playing channel must revoke it
                    // from the always-mounted player as well as the browse list.
                    if let media = sharedLivePlayback.miniMedia,
                       case let .live(id) = media.contentRef {
                        let stream = PlayerContentLookup.liveStream(id, in: modelContext)
                        if stream == nil || contentRestriction.hides(categoryID: stream?.categoryId) {
                            sharedLivePlayback.close()
                        }
                    }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                // Returning to the foreground re-checks staleness — for a long-lived
                // app this is the practical equivalent of "on launch".
                if phase == .active {
                    enqueueDueSyncs(playlists)
                }
                // Coming back to `.active` also refreshes stale sports data.
                SportsSyncService.shared.isForeground = phase == .active
            }
            .syncCover(item: $autoSyncQueue.coverPlaylist) {
                autoSyncQueue.promoteNextIfIdle(scope: catalogScope, context: modelContext)
            }
            .onChange(of: autoSyncQueue.isBusy, initial: true) { _, busy in
                EPGSyncService.shared.setAutoSyncQueued(busy)
                if !busy {
                    try? DreamCASTLocalSettingsBackup.applyPendingViewingState(in: modelContext)
                    // The channel may not exist until the first sync completes.
                    restoreLastLiveChannelOnLaunch()
                }
            }
            .onDisappear {
                // The queue goes with this view (deleting the last playlist
                // swaps the root back to onboarding); don't leave the guide
                // waiting on it.
                EPGSyncService.shared.setAutoSyncQueued(false)
            }
            .downloadsSheet(isPresented: $showsDownloads)
            .lumeCloudPairingSheet(router: router, rootIsCovered: hasOwnPresentation)
            .switchProgressOverlay(playlist: playlistSwitch, profile: profileManager)
            // The one fire point for the rating sheet. Here rather than at the
            // eleven player presentation sites: this view is the browse root,
            // so reaching it *is* the "player gone, nothing over it" condition.
            .appStoreReviewPrompt(isBlocked: hasBlockingPresentation)
            .reportsBrowseRootCovered(hasBlockingPresentation)
        #if os(tvOS)
            .overlay { tvOverlays }
        #endif
    }

    /// Keep the single live decoder outside tvOS's active-only tab content.
    @ViewBuilder
    private func persistentTabHost(selection: Binding<AppTab>, tabs: Set<PlaylistTab>) -> some View {
        #if os(tvOS)
            // Anchor the single decoder to the guide's actual hero bounds.
            // Resolving the anchor inside this TabView overlay avoids counting
            // the tvOS safe-area offsets a second time (80pt / 64pt).
            tabView(selection: selection, tabs: tabs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlayPreferenceValue(TVPlayerSlotAnchorKey.self) { anchor in
                    GeometryReader { geometry in
                        let measured = anchor.map { geometry[$0] }
                        let slot = measured ?? livePlayerSlotFrame
                        // The Live TV guide reports the picture-only frame.
                        // Its controls sit below that frame; the other tabs
                        // include their footer in the measured player slot.
                        let guideFooter: CGFloat =
                            selection.wrappedValue == .liveTV && !usesLiveList
                            ? TVPersistentMiniPlayer.controlsHeight : 0
                        ZStack(alignment: .topLeading) {
                            if sharedLivePlayback.miniMedia != nil,
                               let slot, slot.width > 0, slot.height > 0 {
                                TVPersistentMiniPlayer(session: sharedLivePlayback)
                                    .frame(width: slot.width, height: slot.height + guideFooter)
                                    .position(x: slot.midX, y: slot.midY + guideFooter / 2)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: measured, initial: true) { _, next in
                            // Retain the last slot during a tab transition so
                            // the player/decoder is never unmounted for one frame.
                            guard let next, next.width > 0, next.height > 0 else { return }
                            if livePlayerSlotFrame != next { livePlayerSlotFrame = next }
                        }
                    }
                }
            .environment(sharedLivePlayback)
            .environment(backFocus)
            .environment(ambientTheme)
            .guidePreviewSuspension(
                sharedLivePlayback.guidePreview,
                playingMedia: Binding(
                    get: { sharedLivePlayback.fullScreenMedia },
                    set: { sharedLivePlayback.fullScreenMedia = $0 }
                )
            )
            .fullScreenCover(item: Binding(
                get: { sharedLivePlayback.fullScreenMedia },
                set: { sharedLivePlayback.fullScreenMedia = $0 }
            ), onDismiss: {
                sharedLivePlayback.returnedFromFullScreen()
            }) { media in
                FullScreenPlayerView(media: media, adopting: sharedLivePlayback.handle)
                    .environment(sharedLivePlayback)
            }
        #else
            tabView(selection: selection, tabs: tabs)
        #endif
    }

    #if os(tvOS)
        /// The plain overlays layered over the tabs. One always-mounted container,
        /// so the fade is a transaction over this layer instead of over every
        /// animatable attribute in every live tab.
        private var tvOverlays: some View {
            ZStack {
                if let launch = router.multiViewLaunch {
                    MultiViewScreen(
                        seed: launch.seed,
                        onClose: { router.multiViewLaunch = nil }
                    )
                    // A launch's own id, so a grid started from a channel is a
                    // new view rather than the previous one re-rendered — which
                    // would keep the earlier session and drop the seed.
                    .id(launch.id)
                    .transition(.opacity)
                }

                if router.isQuickSwitchPresented {
                    // Built only while presented: a permanently mounted list of
                    // focusable rows would regrow the focus/AX responder walk
                    // that `activeOnly(_:selection:)` exists to contain.
                    TVQuickSwitchOverlay(router: router, playlists: playlists, scope: catalogScope)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: router.isQuickSwitchPresented)
        }

        /// Checks tab visibility for Apple TV's compact top bar.
        private func isVisibleTVTab(_ tab: AppTab, tabs: Set<PlaylistTab>) -> Bool {
            switch tab {
            case .home: false
            case .liveTV, .movies, .series: tabs.showsTab(tab)
            case .sports: sportsTabEnabled
            case .search, .settings: true
            @unknown default: false
            }
        }

        /// Focus changes highlight a destination, but never select it.
        /// Native tvOS TabView changes tabs on focus and also lets Search
        /// replace the top bar with its system keyboard.
        private func tabView(selection: Binding<AppTab>, tabs: Set<PlaylistTab>) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 24) {
                    tvBrand
                        .frame(width: 250, alignment: .leading)

                    HStack(spacing: 5) {
                        if tabs.showsTab(.liveTV) {
                            tvTabButton("Live TV", .liveTV, symbol: "tv", selection: selection)
                        }
                        if sportsTabEnabled {
                            tvTabButton("SportsZone", .sports, symbol: "trophy", selection: selection)
                        }
                        if tabs.showsTab(.movies) {
                            tvTabButton("Movies", .movies, symbol: "film", selection: selection)
                        }
                        if tabs.showsTab(.series) {
                            tvTabButton("Series", .series, symbol: "square.stack.3d.up", selection: selection)
                        }
                        tvTabButton("Search", .search, symbol: "magnifyingglass", selection: selection)
                        tvTabButton("Settings", .settings, symbol: "gearshape", selection: selection)
                    }
                    .padding(6)
                    .background {
                        if visualGlass {
                            Color.clear
                                .glassEffectCompat(.regular, in: Capsule())
                                .opacity(0.82)
                        }
                    }
                    .background(TVNeonTheme.glass, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(TVNeonTheme.iceBlue.opacity(0.34), lineWidth: 1)
                    }
                    .shadow(color: TVNeonTheme.electricBlue.opacity(0.12), radius: 14)
                    // Prevent the tvOS system focus plate over the custom bar.
                    .focusEffectDisabled()
                    .focusSection()
                    .onChange(of: focusedTVTab) { _, newValue in
                        if newValue != nil {
                            backFocus.markFocused(.topMenu)
                        } else if backFocus.zone == .topMenu {
                            backFocus.markFocused(.content)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 35)
                .padding(.top, 8)
                .padding(.bottom, 15)
                .zIndex(2)

                tvCurrentPage(selection: selection.wrappedValue, tabs: tabs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(DreamCASTAccentTheme.resolve(visualThemeRaw).selectionAccent)
            // Exactly one backdrop behind the app chrome and active tab.
            // It follows Live TV's settled channel tint across tab switches.
            .background {
                TVAmbientBackground(hero: ambientTheme.liveHero)
                    .ignoresSafeArea()
            }
        }

        private func focusTopTVMenu() {
            lastTopMenuBackPress = nil
            backFocus.markFocused(.topMenu)
            // A focus update during a Menu callback can be dropped by tvOS.
            Task { @MainActor in
                focusedTVTab = router.selectedTab
            }
        }

        private func handleTVBack() {
            // Full-screen playback and blocking dialogs own their own Back
            // behavior; do not shift focus behind an active modal.
            guard !blockingOverlayOwnsScreen,
                  !router.isQuickSwitchPresented,
                  sharedLivePlayback.fullScreenMedia == nil
            else { return }

            // Never leave the current tab or rebuild the stream while moving
            // Back. Only change which existing focus section owns the remote.
            if focusedTVTab != nil {
                // Preserve the confirmed double-Back exit when the top menu
                // *already* has remote focus.
                let now = Date()
                if let previous = lastTopMenuBackPress,
                   now.timeIntervalSince(previous) <= 0.85 {
                    lastTopMenuBackPress = nil
                    if confirmExit {
                        showingExitConfirmation = true
                    } else {
                        sharedLivePlayback.close()
                        exit(0)
                    }
                } else {
                    lastTopMenuBackPress = now
                }
                return
            }

            lastTopMenuBackPress = nil
            switch backFocus.zone {
            case .content, .topMenu:
                if sharedLivePlayback.miniMedia != nil {
                    backFocus.requestPlayerFocus()
                } else {
                    // When no channel is playing there is no mini-player.
                    backFocus.requestSidebarFocus()
                }
            case .miniPlayer:
                backFocus.requestSidebarFocus()
            case .sidebar:
                focusTopTVMenu()
            }
        }

        @ViewBuilder
        private func tvCurrentPage(selection: AppTab, tabs: Set<PlaylistTab>) -> some View {
            switch selection {
            case .liveTV:
                if tabs.showsTab(.liveTV) { activeOnly(.liveTV, selection: selection) { LiveTVView() } }
            case .sports:
                if sportsTabEnabled { activeOnly(.sports, selection: selection) { SportFrameHome() } }
            case .movies:
                if tabs.showsTab(.movies) { activeOnly(.movies, selection: selection) { MoviesView() } }
            case .series:
                if tabs.showsTab(.series) { activeOnly(.series, selection: selection) { SeriesView() } }
            case .search:
                activeOnly(.search, selection: selection) { SearchView() }
            case .settings:
                activeOnly(.settings, selection: selection) { SettingsView() }
            case .home:
                Color.clear
            @unknown default:
                Color.clear
            }
        }

        private var tvBrand: some View {
            Image("DreamCASTHeaderLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 210, height: 108, alignment: .leading)
                .accessibilityLabel("DreamCAST TV")
        }

        private func tvTabButton(
            _ title: String,
            _ tab: AppTab,
            symbol: String? = nil,
            selection: Binding<AppTab>
        ) -> some View {
            let selected = selection.wrappedValue == tab
            let focused = focusedTVTab == tab
            return Button {
                // A remote click, not moving focus, changes the active page.
                selection.wrappedValue = tab
            } label: {
                HStack(spacing: 10) {
                    if let symbol {
                        // tvOS borderless buttons automatically enlarge the
                        // first Image in their label on focus. Rendering the
                        // SF Symbol inside Text keeps its size fixed.
                        Text(Image(systemName: symbol))
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 32, height: 34, alignment: .center)
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                    if tab != .search && tab != .settings {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, tab == .search || tab == .settings ? 17 : 22)
                .frame(height: 55)
                .contentShape(Capsule())
                .focusEffectDisabled()
                .background {
                    if selected || focused {
                        Capsule().fill(TVNeonTheme.selection)
                    }
                }
                .overlay {
                    Capsule().strokeBorder(
                        focused ? TVNeonTheme.iceBlue :
                            (selected ? TVNeonTheme.electricBlue.opacity(0.9) : .clear),
                        lineWidth: focused ? 2.5 : 1
                    )
                }
                .shadow(color: focused ? TVNeonTheme.electricBlue.opacity(0.75) : .clear,
                        radius: focused ? 14 : 0)
            }
            // .plain can still show the system's white tvOS focus platter.
            // .borderless keeps Select and @FocusState without that plate.
            .buttonStyle(.borderless)
            .focusEffectDisabled()
            .focused($focusedTVTab, equals: tab)
            .onExitCommand { handleTVBack() }
            .accessibilityLabel(title)
        }

        /// Whether something layered over the tabs owns the screen: tvOS focus is
        /// not clipped by z-order, so the tab bar and the cards behind a plain
        /// overlay would still take presses. The playlist switch is deliberately
        /// absent — it settles in under half a second, and disabling the tabs for
        /// it would move focus and hand it back somewhere else.
        private var blockingOverlayOwnsScreen: Bool {
            router.isMultiViewPresented
                || autoSyncQueue.coverPlaylist != nil
                || profileManager?.isSwitching == true
        }

        /// Whether Play/Pause may toggle the quick-switch modal right now. Off
        /// while a blocking overlay owns the screen, and off when neither column
        /// would have a focusable row — an empty modal over a disabled tab bar has
        /// nothing to hand focus to, and so nothing to deliver Menu either.
        private var playPauseTogglesQuickSwitch: Bool {
            if router.isQuickSwitchPresented {
                return true
            }
            guard !blockingOverlayOwnsScreen else { return false }
            return !playlists.isEmpty || profileManager?.isReady == true
        }

        /// tvOS `TabView` keeps every *visited* tab's view hierarchy alive, and
        /// each remote press triggers a focus/accessibility responder walk over
        /// the whole window — a device trace showed those walks dominating the
        /// EPG guide's scroll time once Home (hero + card rails) had been
        /// visited. Rendering only the selected tab keeps the walked hierarchy
        /// small; tab-local view state resets on switch, which is the usual
        /// tvOS behaviour anyway (navigation paths live in `DeepLinkRouter`
        /// and survive).
        @ViewBuilder
        private func activeOnly(_ tab: AppTab, selection: AppTab, @ViewBuilder content: () -> some View) -> some View {
            if selection == tab {
                // Keep each tab's content in the same VStack when playback
                // starts or stops; only the header enters or leaves.
                VStack(spacing: 0) {
                    // SportsZone has its own featured-game header with a
                    // measured video slot. Never stack the generic page hero
                    // above it; that duplicates the player and clips fixtures.
                    if let media = sharedLivePlayback.miniMedia,
                       tab != .sports,
                       tab != .settings,
                       (tab != .liveTV || usesLiveList) {
                        TVEmbeddedPageHeader(tab: tab, media: media)
                    }
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Color.clear
            }
        }
    #else
        /// Search stays mounted: it holds only the query the viewer typed and a
        /// playlist lookup. The content tabs unmount after sitting unshown — see
        /// `IdleUnmountingTab`.
        private func tabView(selection: Binding<AppTab>, tabs: Set<PlaylistTab>) -> some View {
            TabView(selection: selection) {
                Tab("Home", systemImage: "house", value: AppTab.home) {
                    IdleUnmountingTab(isSelected: selection.wrappedValue == .home) { HomeView() }
                }

                if tabs.showsTab(.movies) {
                    Tab("Movies", systemImage: "film", value: AppTab.movies) {
                        IdleUnmountingTab(isSelected: selection.wrappedValue == .movies) { MoviesView() }
                    }
                }

                if tabs.showsTab(.series) {
                    Tab("Series", systemImage: "tv", value: AppTab.series) {
                        IdleUnmountingTab(isSelected: selection.wrappedValue == .series) { SeriesView() }
                    }
                }

                if tabs.showsTab(.liveTV) {
                    Tab("Live TV", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.liveTV) {
                        IdleUnmountingTab(isSelected: selection.wrappedValue == .liveTV) { LiveTVView() }
                    }
                }

                if sportsTabEnabled {
                    Tab("Sports", systemImage: "sportscourt", value: AppTab.sports) {
                        IdleUnmountingTab(isSelected: selection.wrappedValue == .sports) { SportsHubView() }
                    }
                }

                // macOS 15's tab bar drops a `role: .search` tab entirely — even
                // with an explicit label (the previous workaround), the search tab
                // never renders, leaving no way to reach Search there. macOS 26
                // renders the role correctly, as do iOS/visionOS 18+, so only
                // macOS 15 falls back to a plain tab and every other system keeps
                // the dedicated search treatment.
                if #unavailable(macOS 26) {
                    Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                        SearchView()
                    }
                } else {
                    Tab(value: AppTab.search, role: .search) {
                        SearchView().castMiniControllerInset()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
            }
        }
    #endif

    // MARK: - Deep links

    /// Resolves a `lume://movie/{tmdbId}` / `lume://series/{tmdbId}` link to a
    /// catalog item, switches to the matching tab and pushes its detail screen.
    /// `play`/`open` links (from widgets and the Top Shelf) launch playback or
    /// a detail screen by catalog id. Silently ignores unknown links and titles
    /// not present in the catalog (e.g. a tmdbId that was never synced or
    /// enriched).
    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case let .movie(tmdbId):
            guard let movie = resolveMovie(tmdbId: tmdbId) else { return }
            openMovieDetail(movie)
        case let .series(tmdbId):
            guard let series = resolveSeries(tmdbId: tmdbId) else { return }
            openSeriesDetail(series)
        case .playMovie, .playEpisode, .playLive, .openSeries, .openMovie:
            handleWidgetLink(link)
        case .resume:
            // When a player session is already up, foregrounding the app is
            // all that's needed; otherwise reopen the last played stream where
            // it left off.
            guard NowPlayingService.shared.currentMedia == nil,
                  let media = PlaybackResumeStore.load() else { return }
            #if os(macOS)
                MacPlayerWindowRouter.shared.play(media, using: openWindow)
            #else
                linkedMedia = media
            #endif
        case .downloads:
            // The download Live Activity was tapped.
            showsDownloads = true
        case let .cloudPair(code):
            // Ignored on tvOS: no camera to scan a pairing QR with.
            #if !os(tvOS)
                showsDownloads = false
                router.requestCloudPairing(code: code)
            #endif
        }
    }

    /// Handles a widget / Top Shelf link: `play` launches playback, `open`
    /// pushes a movie or series detail screen — both by catalog id.
    private func handleWidgetLink(_ link: DeepLink) {
        switch WidgetLinkResolver.resolve(link, in: modelContext, restriction: contentRestriction) {
        case let .play(media):
            // Mirrors the in-app play paths: external player hand-off first,
            // then a player window (macOS) or a full-screen cover.
            if ExternalPlayback.open(media) { return }
            #if os(macOS)
                MacPlayerWindowRouter.shared.play(media, using: openWindow)
            #else
                linkedMedia = media
            #endif
        case let .openSeries(series):
            openSeriesDetail(series)
        case let .openMovie(movie):
            openMovieDetail(movie)
        case nil:
            break
        }
    }

    /// Pushes a movie detail screen on the Movies tab — a no-op when the
    /// profile hides that tab.
    private func openMovieDetail(_ movie: Movie) {
        guard showsTab(.movies) else { return }
        router.selectedTab = .movies
        router.moviesPath = NavigationPath()
        router.moviesPath.append(movie)
    }

    /// Pushes a series detail screen on the Series tab — a no-op when the
    /// profile hides that tab.
    private func openSeriesDetail(_ series: Series) {
        guard showsTab(.series) else { return }
        router.selectedTab = .series
        router.seriesPath = NavigationPath()
        router.seriesPath.append(series)
    }

    /// Finds a movie by `tmdbId`, preferring a copy from the playlists on
    /// screen but falling back to any other playlist's copy the plan unlocks.
    /// Restricted categories stay hidden for a child profile.
    private func resolveMovie(tmdbId: Int) -> Movie? {
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
        let restriction = contentRestriction
        let matcher = CatalogScope.Matcher(catalogScope)
        let matches = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { !restriction.hides(categoryID: $0.categoryId) && !playlists.isLocked(contentID: $0.id) }
        return matches.first { matcher.contains($0.id, .movies) } ?? matches.first
    }

    private func resolveSeries(tmdbId: Int) -> Series? {
        let descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.tmdbId == tmdbId })
        let restriction = contentRestriction
        let matcher = CatalogScope.Matcher(catalogScope)
        let matches = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { !restriction.hides(categoryID: $0.categoryId) && !playlists.isLocked(contentID: $0.id) }
        return matches.first { matcher.contains($0.id, .series) } ?? matches.first
    }

    // MARK: - Cold launch Live TV restore

    #if os(iOS) || os(tvOS)
    /// The app-root player is mounted across every tab. Restore at most once,
    /// after cached or freshly synced rows are available, without opening
    /// full screen or replacing any playback the viewer already started.
    private func restoreLastLiveChannelOnLaunch() {
        #if os(tvOS)
        // Honor the existing Live TV auto-resume preference.
        guard autoResumeLastChannel else { return }
        #endif
        guard !restoredLastLiveOnLaunch,
              LiveChannelHistory.shouldResumeLiveOnLaunch(),
              sharedLivePlayback.miniMedia == nil,
              sharedLivePlayback.fullScreenMedia == nil,
              !sharedLivePlayback.userStopped,
              visibleTabs(in: catalogScope).showsTab(.liveTV),
              let lastID = LiveChannelHistory.currentChannelId(),
              let stream = PlayerContentLookup.liveStream(lastID, in: modelContext),
              !stream.isHidden,
              !contentRestriction.hides(categoryID: stream.categoryId),
              let owner = playlists.owner(ofContentID: stream.id),
              catalogScope.members(for: .liveTV).contains(owner.id),
              let media = PlayableMedia.from(
                  stream: stream,
                  ownedByOneOf: playlists,
                  surfScope: LiveSurfScope(catalogScope)
              ) else { return }
        restoredLastLiveOnLaunch = true
        sharedLivePlayback.tune(media, previewMode: .small)
    }
    #endif

    // MARK: - Automatic sync

    /// A playlist the free plan locks never syncs.
    private func enqueueDueSyncs(_ candidates: [Playlist]) {
        autoSyncQueue.enqueueDue(
            candidates.filter { !playlists.isLocked($0) },
            scope: catalogScope,
            frequency: syncFrequency,
            context: modelContext
        )
    }
}

// MARK: - Downloads sheet presentation

private extension View {
    /// Presents the downloads list as a sheet, in the same navigation + dismiss
    /// chrome Settings gives it. The download Live Activity's tap target, so it
    /// is reachable without disturbing whatever tab the user had open.
    @ViewBuilder
    func downloadsSheet(isPresented: Binding<Bool>) -> some View {
        #if os(tvOS)
            // tvOS has no downloads feature to show.
            self
        #else
            sheet(isPresented: isPresented) {
                NavigationStack {
                    DownloadsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isPresented.wrappedValue = false }
                            }
                        }
                }
                #if os(macOS)
                // A `List` in a frameless macOS sheet collapses to zero
                // height, leaving the sheet rendering as a bare toolbar.
                .frame(minWidth: 480, minHeight: 440)
                #endif
            }
        #endif
    }
}

// MARK: - Sync cover presentation

private extension View {
    /// Presents the auto-sync progress UI as a blocking cover: a full-screen
    /// cover on iOS/tvOS (no swipe-to-dismiss), a sheet on macOS where
    /// `fullScreenCover` is unavailable.
    @ViewBuilder
    func syncCover(item: Binding<Playlist?>, onDismiss: @escaping () -> Void) -> some View {
        #if os(macOS)
            sheet(item: item, onDismiss: onDismiss) { playlist in
                SyncProgressView(playlist: playlist, autoStart: true)
                    .frame(minWidth: 420, minHeight: 480)
            }
        #else
            fullScreenCover(item: item, onDismiss: onDismiss) { playlist in
                SyncProgressView(playlist: playlist, autoStart: true)
            }
        #endif
    }
}

#if os(tvOS)
/// Single source of truth for Back navigation across the six tvOS pages.
/// Each focus zone owns its @FocusState; the root only issues focus requests.
@MainActor @Observable
final class TVBackFocusCoordinator {
    enum Zone: Equatable {
        case content, miniPlayer, sidebar, topMenu
    }

    private(set) var zone: Zone = .content
    private(set) var playerFocusRequest = 0
    private(set) var sidebarFocusRequest = 0

    func markFocused(_ newZone: Zone) {
        zone = newZone
    }

    func requestPlayerFocus() {
        zone = .miniPlayer
        playerFocusRequest &+= 1
    }

    func requestSidebarFocus() {
        zone = .sidebar
        sidebarFocusRequest &+= 1
    }
}

extension Notification.Name {
    static let dreamCASTReturnToTopMenu =
        Notification.Name("dreamcast.tv.returnToTopMenu")
}

/// The guide and other tabs publish their real layout bounds. This is only
/// an anchor, not a player; the app-root surface is mounted once above TabView.
struct TVEmbeddedPlayerSlot: View {
    var width: CGFloat = 640
    var height: CGFloat = 360

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .anchorPreference(key: TVPlayerSlotAnchorKey.self, value: .bounds) { $0 }
            .accessibilityHidden(true)
    }
}

struct TVPlayerSlotAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

/// Unified header for the five non-guide tabs and the Live TV list layout.
/// It replaces the old empty top inset with useful content and a real slot.
private struct TVEmbeddedPageHeader: View {
    let tab: AppTab
    let media: PlayableMedia

    // Search and Settings reserve more space below for keys, results and lists.
    private var compact: Bool { tab == .search || tab == .settings }
    private var videoWidth: CGFloat { compact ? 386 : 640 }
    private var videoHeight: CGFloat { compact ? 217 : 360 }

    private var page: (title: String, description: String, symbol: String) {
        switch tab {
        case .liveTV:
            ("Live TV", "Browse channels while the live stream keeps playing.", "tv")
        case .sports:
            ("SportsZone", "Live scores, leagues and upcoming fixtures.", "sportscourt")
        case .movies:
            ("Movies", "Keep watching and discover more from your library.", "film.stack")
        case .series:
            ("Series", "Your shows, new episodes and what to watch next.", "play.tv")
        case .search:
            ("Search", "Find live channels, movies and series in one place.", "magnifyingglass")
        case .settings:
            ("Settings", "Make DreamCAST TV work the way you want.", "gearshape")
        case .home:
            ("Home", "Your media, all in one place.", "house")
        @unknown default:
            ("DreamCAST TV", "Continue browsing your library.", "tv")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 50) {
            VStack(alignment: .leading, spacing: 16) {
                Label(page.title, systemImage: page.symbol)
                    .font(.system(size: compact ? 35 : 47, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(page.description)
                    .font(.system(size: compact ? 20 : 24))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("LIVE")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(media.title)
                        .font(.system(size: compact ? 18 : 22))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }
                .padding(.top, compact ? 7 : 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 7)

            // This slot is never a second player.
            TVEmbeddedPlayerSlot(
                width: videoWidth,
                height: videoHeight + TVPersistentMiniPlayer.controlsHeight
            )
        }
        .padding(.horizontal, 64)
        .padding(.top, compact ? 8 : 20)
        .padding(.bottom, compact ? 10 : 28)
        .frame(maxWidth: .infinity)
    }
}
#endif

#Preview("No Playlists") {
    MainTabView()
}

#Preview("With Playlists") {
    MainTabView()
        .modelContainer(for: Playlist.self, inMemory: true) { result in
            if case let .success(container) = result {
                let playlist = Playlist(name: "My IPTV", serverURL: "http://example.com:8080", username: "user", password: "pass")
                container.mainContext.insert(playlist)
            }
        }
}
