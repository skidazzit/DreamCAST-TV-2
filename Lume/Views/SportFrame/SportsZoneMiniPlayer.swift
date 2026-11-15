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

    func tune(_ media: PlayableMedia, previewMode: GuidePreviewMode = .small) {
        userStopped = false
        guard miniMedia?.id != media.id else {
            // Off has no mini-player control to reopen the same channel.
            if previewMode == .off { openFullScreen() }
            return
        }
        handle.stopPreview()
        failedMediaID = nil
        reloadToken += 1
        miniMedia = media
        #if os(tvOS)
        guidePreview.preferredStreamID = media.id
        #endif
        LiveChannelHistory.record(media)

        // Match the Live TV setting: "Off" means no inline preview.
        // Open the stream full screen rather than playing it off-screen.
        if previewMode == .off {
            openFullScreen()
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
        miniMedia = media
        failedMediaID = nil
        #if os(tvOS)
        guidePreview.preferredStreamID = media.id
        #endif
    }

    func openFullScreen() {
        guard let media = miniMedia, fullScreenMedia == nil else { return }
        #if os(tvOS)
        // Use Live TV's exact preparation, including owner transition
        // and suspend/cooldown state for a non-adoptable decoder.
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

    func returnedFromFullScreen() {
        // A single dismissal may be reported twice by SwiftUI. Live TV
        // must receive just one matching return for each presentation.
        guard isAwaitingFullScreenDismissal, fullScreenMedia == nil else { return }
        isAwaitingFullScreenDismissal = false

        #if os(tvOS)
        // Let the working Guide code return the same decoder, or cool down
        // a failed handoff before opening another provider connection.
        guidePreview.fullScreenDidClose()
        // An unsupported engine restarts after the Guide's cooldown. Never
        // leave a stale failure badge hiding that next preview attempt.
        failedMediaID = nil
        #else
        if handle.owner == .preview,
           handle.media?.id == miniMedia?.id,
           handle.coordinator != nil { return }
        if handle.owner == .fullScreen, let media = miniMedia,
           handle.media?.id == media.id {
            _ = handle.returnToPreview(mediaID: media.id)
        }
        if handle.finishReturnToPreview() {
            failedMediaID = nil
            return
        }
        handle.release()
        failedMediaID = nil
        reloadToken += 1
        #endif
    }

    func close() {
        guard fullScreenMedia == nil else { return }
        userStopped = true
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
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    session.close()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
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
                        session.failedMediaID = media.id
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

    private var canShowVideo: Bool {
        guard session.guidePreview.isSuspended else { return true }
        return session.handle.owner == .fullScreen || session.handle.owner == .returning
    }

    private func tileID(_ media: PlayableMedia) -> String {
        "\(media.id)-\(session.reloadToken)-\(session.guidePreview.restartToken)"
    }

    var body: some View {
        if let media = session.miniMedia {
            VStack(alignment: .leading, spacing: 12) {
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
                                session.failedMediaID = media.id
                            }
                        )
                        .id(tileID(media))
                    }
                }
                .frame(width: 352, height: 198)
                .clipShape(RoundedRectangle(cornerRadius: 13))

                HStack(spacing: 10) {
                    Text(media.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        session.openFullScreen()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel("Open live channel full screen")

                    Button {
                        session.close()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .accessibilityLabel("Stop live channel")
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(width: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 16, y: 7)
            .focusSection()
            .accessibilityElement(children: .contain)
        }
    }
}
#endif
#endif
