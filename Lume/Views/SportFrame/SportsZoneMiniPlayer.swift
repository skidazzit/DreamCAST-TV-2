#if os(iOS) || os(tvOS)
import SwiftUI

/// SportsZone uses the same decoder handoff as the Live TV guide.
/// Only choosing a channel changes playback; scrolling and changing leagues
/// do not affect the running stream.
@MainActor @Observable
final class SportsZonePlaybackSession {
    #if os(tvOS)
    /// The exact controller Live TV uses for preview ownership, cooldown
    /// and the return from full-screen. Never create a second handoff path.
    let guidePreview = GuidePreviewController()
    var handle: PreviewPlayerHandle { guidePreview.handle }
    #else
    let handle = PreviewPlayerHandle()
    #endif
    var miniMedia: PlayableMedia?
    var fullScreenMedia: PlayableMedia?
    /// The exact channel list shown in the last SportsZone match picker.
    var matchedChannels: [ResolvedChannel] = []
    var failedMediaID: String?
    /// An explicit Stop must not be undone by a tab's autoplay restore.
    var userStopped = false
    var reloadToken = 0
    // Prevent repeated dismissal callbacks from restarting a live stream.
    private var isAwaitingFullScreenDismissal = false
    private var pendingReturnMedia: PlayableMedia?
    private(set) var pendingFullScreenRequest = false
    #if os(tvOS)
    @ObservationIgnored private var fullScreenGraceTask: Task<Void, Never>?
    #endif

    private func cancelPendingFullScreen() {
        pendingFullScreenRequest = false
        #if os(tvOS)
        fullScreenGraceTask?.cancel()
        fullScreenGraceTask = nil
        #endif
    }

    func tune(_ media: PlayableMedia, previewMode: GuidePreviewMode = .small) {
        userStopped = false
        guard miniMedia?.id != media.id else {
            // Off has no mini-player control to reopen the same channel.
            if previewMode == .off { openFullScreen() }
            return
        }
        cancelPendingFullScreen()
        handle.stopPreview()
        failedMediaID = nil
        reloadToken += 1
        miniMedia = media
        #if os(tvOS)
        guidePreview.preferredStreamID = media.id
        #endif
        // The next cold start must know whether Live TV or VOD played last.
        // LiveChannelHistory keeps its channel recall unchanged for VOD.
        LiveChannelHistory.record(media)

        // Match the Live TV setting: "Off" means no inline preview.
        // Open the stream full screen rather than playing it off-screen.
        if previewMode == .off {
            // No embedded decoder exists to hand over.
            presentFullScreenWithoutPreview()
        }
    }

    /// Retain the match order; never re-run broadcaster/EPG searches in the player.
    func rememberMatches(_ matches: [ResolvedChannel], selected: ResolvedChannel) {
        var seen = Set<String>()
        matchedChannels = (matches + [selected]).filter { seen.insert($0.id).inserted }
    }

    /// Keep the SportsZone preview aimed at the channel last picked in full screen.
    /// Do not update fullScreenMedia: that value owns the current cover's identity.
    func didSwitchFullScreen(to media: PlayableMedia) {
        guard fullScreenMedia != nil else { return }
        pendingReturnMedia = media
        failedMediaID = nil
        #if os(tvOS)
        guidePreview.preferredStreamID = media.id
        #endif
    }

    /// Reuse a started, compatible decoder without reloading the stream.
    /// A brief bounded wait lets an almost-ready decoder finish loading;
    /// failure or timeout falls back instead of leaving Full Screen inert.
    func openFullScreen() {
        guard let media = miniMedia, fullScreenMedia == nil else { return }
        #if os(tvOS)
        // Give a buffering, compatible preview a brief chance to produce its
        // first frame. The button shows "Opening…" during this bounded wait.
        // On timeout, open full screen using the Guide's safe fallback.
        if !CastService.shared.isAirPlayActive, failedMediaID != media.id,
           !handle.hasStarted, handle.owner == .preview,
           !guidePreview.isSuspended {
            guard !pendingFullScreenRequest else { return }
            pendingFullScreenRequest = true
            let requestedID = media.id
            fullScreenGraceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self,
                      self.pendingFullScreenRequest,
                      self.miniMedia?.id == requestedID else { return }
                self.presentFullScreenWithoutPreview()
            }
            return
        }
        #else
        // iOS waits for its fixed preview to produce a usable decoder.
        guard failedMediaID != media.id else { return }
        if !CastService.shared.isAirPlayActive && !handle.hasStarted {
            pendingFullScreenRequest = true
            return
        }
        #endif
        cancelPendingFullScreen()
        pendingReturnMedia = nil
        #if os(tvOS)
        guidePreview.prepareToPresent(media)
        #else
        if handle.canAdopt(media, airPlayActive: CastService.shared.isAirPlayActive) {
            handle.handOffToFullScreen()
        } else {
            handle.stopPreview()
        }
        #endif
        isAwaitingFullScreenDismissal = true
        fullScreenMedia = media
    }

    func previewDidStart() {
        guard pendingFullScreenRequest, handle.hasStarted else { return }
        openFullScreen()
    }

    func previewFailed(_ mediaID: String) {
        guard miniMedia?.id == mediaID, handle.owner == .preview else { return }
        let wasOpening = pendingFullScreenRequest
        cancelPendingFullScreen()
        failedMediaID = mediaID
        #if os(tvOS)
        // A pending Full Screen request must still finish when preview fails.
        if wasOpening { presentFullScreenWithoutPreview() }
        #endif
    }

    private func presentFullScreenWithoutPreview() {
        guard let media = miniMedia, fullScreenMedia == nil else { return }
        cancelPendingFullScreen()
        pendingReturnMedia = nil
        #if os(tvOS)
        guidePreview.prepareToPresent(media)
        #endif
        isAwaitingFullScreenDismissal = true
        fullScreenMedia = media
    }

    func returnedFromFullScreen() {
        guard isAwaitingFullScreenDismissal, fullScreenMedia == nil else { return }
        isAwaitingFullScreenDismissal = false
        cancelPendingFullScreen()
        #if os(tvOS)
        guidePreview.fullScreenDidClose()
        #else
        if handle.owner == .fullScreen, let media = miniMedia,
           handle.media?.id == media.id {
            _ = handle.returnToPreview(mediaID: media.id)
        }
        let returned = handle.finishReturnToPreview()
        if !returned { handle.release() }
        #endif
        if let switchedMedia = pendingReturnMedia {
            pendingReturnMedia = nil
            // Only a real channel switch needs a new decoder after dismissal.
            if switchedMedia.id != miniMedia?.id {
                miniMedia = switchedMedia
                handle.release()
                reloadToken += 1
            }
        }
        failedMediaID = nil
        #if !os(tvOS)
        if handle.owner == .released { reloadToken += 1 }
        #endif
    }

    /// An explicit restart replaces only the current mini-player decoder.
    /// Keep automatic full-screen return and tab navigation untouched.
    func restartCurrentChannel() {
        guard miniMedia != nil, fullScreenMedia == nil,
              !isAwaitingFullScreenDismissal,
              !guidePreview.isSuspended,
              handle.owner == .preview || handle.owner == .released else { return }
        cancelPendingFullScreen()
        pendingReturnMedia = nil
        handle.stopPreview()
        failedMediaID = nil
        userStopped = false
        reloadToken += 1
    }

    func close() {
        guard fullScreenMedia == nil else { return }
        userStopped = true
        cancelPendingFullScreen()
        pendingReturnMedia = nil
        handle.stopPreview()
        miniMedia = nil
        failedMediaID = nil
        #if os(tvOS)
        guidePreview.preferredStreamID = nil
        #endif
        reloadToken += 1
    }
}

/// An in-flow, fixed-position SportsZone player. Its parent keeps the view
/// OUTSIDE the fixtures ScrollView, so it never overlays match rows or moves
/// when a viewer scrolls. It reads the actual Live TV guide display settings.
struct SportsZoneMiniPlayer: View {
    let session: SportsZonePlaybackSession

    @AppStorage(PlayerSettings.tvGuidePreviewModeKey)
    private var modeRaw = PlayerSettings.tvGuidePreviewModeDefault.rawValue

    private var mode: GuidePreviewMode {
        GuidePreviewMode(storedValue: modeRaw)
    }

    /// Live TV leaves the preview tile mounted during an adopted handoff.
    /// Other suspensions remove playback but preserve the preview layout.
    private var canShowVideoTile: Bool {
        #if os(tvOS)
        guard session.guidePreview.isSuspended else { return true }
        return session.handle.owner == .fullScreen
            || session.handle.owner == .returning
        #else
        return true
        #endif
    }

    private func tileIdentity(for media: PlayableMedia) -> String {
        #if os(tvOS)
        // The Guide increments this only after a failed handoff's cooldown.
        // Adopted decoders keep the exact same tile identity.
        return "\(media.id)-\(session.reloadToken)-\(session.guidePreview.restartToken)"
        #else
        return "\(media.id)-\(session.reloadToken)"
        #endif
    }

    #if os(tvOS)
    @AppStorage(TVGuideDesign.storageKey)
    private var guideDesignRaw = TVGuideDesign.classic.rawValue

    private var guideDesign: TVGuideDesign {
        TVGuideDesign(storedValue: guideDesignRaw)
    }
    #endif

    var body: some View {
        if let media = session.miniMedia, mode.showsHero {
            #if os(tvOS)
            tvPlayer(media)
            #else
            phonePlayer(media)
            #endif
        }
    }

    #if os(tvOS)
    /// The same hero dimensions and left/right order as the tvOS Live TV guide.
    /// The fixtures and league table scroll in the space BELOW this hero.
    private func tvPlayer(_ media: PlayableMedia) -> some View {
        let layout = EPGHeroLayout(mode)
        return HStack(alignment: .bottom, spacing: 48) {
            if guideDesign == .dreamcast {
                surface(media)
                    .frame(width: layout.videoWidth, height: layout.height)
                tvInfo(media)
            } else {
                tvInfo(media)
                surface(media)
                    .frame(width: layout.videoWidth, height: layout.height)
            }
        }
        .frame(height: layout.height)
        .padding(.bottom, layout.bottomPadding)
        .focusSection()
        .accessibilityElement(children: .contain)
    }

    private func tvInfo(_ media: PlayableMedia) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("NOW PLAYING")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(media.title)
                .font(.system(size: 35, weight: .bold))
                .lineLimit(2)
            HStack(spacing: 18) {
                Button {
                    session.openFullScreen()
                } label: {
                    TVFixedButtonLabel(title: "Full Screen", systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    session.restartCurrentChannel()
                } label: {
                    TVFixedButtonLabel(title: "Restart", systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(session.guidePreview.isSuspended)
                .accessibilityLabel("Restart channel")
                Button {
                    session.close()
                } label: {
                    TVFixedButtonLabel(title: "Stop", systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
    #else
    /// Match iOS Live TV: title/controls above a wide, non-floating preview.
    private func phonePlayer(_ media: PlayableMedia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("NOW PLAYING")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(media.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    session.openFullScreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Open SportsZone full screen")
                Button {
                    session.close()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .accessibilityLabel("Stop SportsZone playback")
            }
            surface(media)
                .frame(height: mode == .large || mode == .infoOnly ? 210 : 124)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
    #endif

    /// The tile remains mounted behind full screen to retain its player state.
    /// Only .small and .large render video, matching GuidePreviewMode.
    private func surface(_ media: PlayableMedia) -> some View {
        ZStack {
            Color.black
            if !mode.playsVideo {
                if let artwork = media.posterURL {
                    AsyncImage(url: artwork) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "tv").font(.largeTitle)
                    }
                } else {
                    Image(systemName: "tv").font(.largeTitle)
                }
            } else if !canShowVideoTile {
                // Do not open a second provider connection behind full screen
                // when the selected engine did not support decoder adoption.
                Color.black
            } else if session.failedMediaID == media.id {
                Label("Stream unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.white)
            } else {
                MultiViewTilePlayer(
                    media: media,
                    isMuted: false,
                    role: .guidePreview(handle: session.handle),
                    onFailure: {
                        // A stale preview watchdog cannot replace the active
                        // video with a failure badge during full-screen handoff.
                        guard session.miniMedia?.id == media.id,
                              session.fullScreenMedia == nil,
                              session.handle.owner == .preview,
                              canShowVideoTile else { return }
                        session.previewFailed(media.id)
                    }
                )
                .id(tileIdentity(for: media))
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityLabel("SportsZone channel: \(media.title)")
    }
}

#if os(tvOS)
/// One always-mounted mini-player, owned by MainTabView rather than its tabs.
/// This keeps the same live decoder and audio running as viewers browse.
struct TVPersistentMiniPlayer: View {
    let session: SportsZonePlaybackSession
    @Environment(TVBackFocusCoordinator.self) private var backFocus: TVBackFocusCoordinator?
    @FocusState private var focusedAction: MiniPlayerAction?

    private enum MiniPlayerAction: Hashable {
        case fullScreen, restart, stop
    }

    private var canShowVideo: Bool {
        guard session.guidePreview.isSuspended else { return true }
        return session.handle.owner == .fullScreen || session.handle.owner == .returning
    }

    private func tileID(_ media: PlayableMedia) -> String {
        "\(media.id)-\(session.reloadToken)-\(session.guidePreview.restartToken)"
    }

    /// Space reserved by every page for controls below its video.
    static let controlsHeight: CGFloat = 66

    var body: some View {
        if let media = session.miniMedia {
            // The stream view itself stays mounted on every tab. The footer is
            // below the video, so buttons never cover the broadcast picture.
            GeometryReader { geometry in
                let pictureHeight = max(0, geometry.size.height - Self.controlsHeight)

                VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        videoSurface(for: media)
                            .frame(width: geometry.size.width, height: pictureHeight)

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.72)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: min(68, pictureHeight))
                        .allowsHitTesting(false)

                        HStack(spacing: 10) {
                            Text(media.isLive ? "LIVE" : "PLAYING")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(media.isLive ? Color.red.opacity(0.88) : TVNeonTheme.electricBlue.opacity(0.88), in: Capsule())

                            Text(media.title)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 13)
                        .padding(.bottom, 10)
                    }
                    .frame(width: geometry.size.width, height: pictureHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(TVNeonTheme.iceBlue.opacity(0.85), lineWidth: 2)
                            .allowsHitTesting(false)
                    }

                    HStack(spacing: 12) {
                        Spacer(minLength: 0)

                        Button {
                            session.openFullScreen()
                        } label: {
                            miniPlayerActionLabel(
                                session.pendingFullScreenRequest ? "Opening…" : "Full Screen",
                                symbol: "arrow.up.left.and.arrow.down.right",
                                focused: focusedAction == .fullScreen
                            )
                        }
                        .buttonStyle(.borderless)
                        .focusEffectDisabled()
                        .accessibilityLabel("Open live channel full screen")
                        .focused($focusedAction, equals: .fullScreen)

                        Button {
                            session.restartCurrentChannel()
                        } label: {
                            miniPlayerActionLabel(
                                "Restart",
                                symbol: "arrow.clockwise",
                                focused: focusedAction == .restart
                            )
                        }
                        .buttonStyle(.borderless)
                        .focusEffectDisabled()
                        .disabled(session.guidePreview.isSuspended)
                        .accessibilityLabel("Restart channel")
                        .focused($focusedAction, equals: .restart)

                        Button {
                            session.close()
                        } label: {
                            miniPlayerActionLabel(
                                "Stop",
                                symbol: "stop.fill",
                                focused: focusedAction == .stop
                            )
                        }
                        .buttonStyle(.borderless)
                        .focusEffectDisabled()
                        .accessibilityLabel("Stop live channel")
                        .focused($focusedAction, equals: .stop)
                    }
                    .padding(.horizontal, 13)
                    .frame(width: geometry.size.width, height: Self.controlsHeight)
                    .background(TVNeonTheme.glass)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: TVNeonTheme.electricBlue.opacity(0.26), radius: 10)
            }
            .focusSection()
            .onChange(of: session.handle.hasStarted, initial: true) { _, started in
                if started { session.previewDidStart() }
            }
            .onChange(of: backFocus?.playerFocusRequest) { _, _ in
                // Keep the video running. Only the footer's first button
                // receives focus, without activating Full Screen.
                Task { @MainActor in
                    // Let the current content's Menu event finish before
                    // asking the focus engine to move into this overlay.
                    await Task.yield()
                    focusedAction = .fullScreen
                }
            }
            .onChange(of: focusedAction) { _, next in
                if next != nil {
                    backFocus?.markFocused(.miniPlayer)
                } else if backFocus?.zone == .miniPlayer {
                    backFocus?.markFocused(.content)
                }
            }
            .onExitCommand {
                NotificationCenter.default.post(
                    name: .dreamCASTReturnToTopMenu,
                    object: nil
                )
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// A visible focused state is required when tvOS's white focus plate is
    /// disabled. Keep a fixed-size symbol and highlight the full button only.
    private func miniPlayerActionLabel(
        _ title: LocalizedStringKey,
        symbol: String,
        focused: Bool
    ) -> some View {
        TVFixedButtonLabel(title: title, systemName: symbol, iconSize: 20)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background {
                RoundedRectangle(cornerRadius: 13)
                    .fill(focused ? TVNeonTheme.selection : TVNeonTheme.glass)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        focused ? TVNeonTheme.iceBlue : .white.opacity(0.14),
                        lineWidth: focused ? 2.5 : 1
                    )
            }
            .shadow(
                color: focused ? TVNeonTheme.electricBlue.opacity(0.65) : .clear,
                radius: focused ? 10 : 0
            )
            .contentShape(RoundedRectangle(cornerRadius: 13))
    }

    /// Mounted once in MainTabView; moving among tabs never recreates this tile.
    @ViewBuilder
    private func videoSurface(for media: PlayableMedia) -> some View {
        ZStack {
            Color.black
            if !canShowVideo {
                Color.black
            } else if session.failedMediaID == media.id {
                Label("Stream unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.white)
            } else {
                MultiViewTilePlayer(
                    media: media,
                    isMuted: false,
                    role: .guidePreview(handle: session.handle),
                    onFailure: {
                        guard session.miniMedia?.id == media.id,
                              session.fullScreenMedia == nil,
                              session.handle.owner == .preview,
                              canShowVideo else { return }
                        session.previewFailed(media.id)
                    }
                )
                .id(tileID(media))
            }
        }
    }
}
#endif
#endif
