#if os(iOS) || os(tvOS)
import SwiftUI

/// SportsZone uses the same decoder handoff as the Live TV guide.
/// Only choosing a channel changes playback; scrolling and changing leagues
/// do not affect the running stream.
@MainActor @Observable
final class SportsZonePlaybackSession {
    let handle = PreviewPlayerHandle()
    var miniMedia: PlayableMedia?
    var fullScreenMedia: PlayableMedia?
    var failedMediaID: String?
    var reloadToken = 0
    /// Stop is intentional: opening Live TV must not restart an old stream.
    var userStopped = false
    private var isAwaitingFullScreenDismissal = false
    /// Store channel changes made inside full screen without spawning a
    /// second decoder in the embedded video host behind that cover.
    private var pendingReturnMedia: PlayableMedia?
    /// A full-screen request made before the preview rendered a frame waits
    /// for the same decoder. Never start a parallel stream just for the cover.
    private(set) var pendingFullScreenRequest = false

    func tune(_ media: PlayableMedia, previewMode: GuidePreviewMode = .small) {
        userStopped = false
        guard miniMedia?.id != media.id else {
            // Off has no mini-player control to reopen the same channel.
            if previewMode == .off { openFullScreen() }
            return
        }
        pendingFullScreenRequest = false
        handle.stopPreview()
        failedMediaID = nil
        reloadToken += 1
        miniMedia = media
        // The next cold start must know whether Live TV or VOD played last.
        // LiveChannelHistory keeps its channel recall unchanged for VOD.
        LiveChannelHistory.record(media)

        // Match the Live TV setting: "Off" means no inline preview.
        // Open the stream full screen rather than playing it off-screen.
        if previewMode == .off {
            // An explicitly disabled preview has no decoder to borrow.
            // This is the initial playback, not a handoff/restart.
            presentFullScreenWithoutPreview()
        }
    }

    /// Keep the root mini-player on the channel picked while full-screen.
    /// That player may switch channels without replacing its cover identity.
    func didSwitchFullScreen(to media: PlayableMedia) {
        guard fullScreenMedia != nil else { return }
        pendingReturnMedia = media
        failedMediaID = nil
    }

    /// Switching pages never touches the media or decoder.
    /// Only an explicit tune, Stop or full-screen action changes ownership.
    func openFullScreen() {
        guard let media = miniMedia, fullScreenMedia == nil,
              failedMediaID != media.id else { return }
        // AirPlay sends full-screen video through a different route. That
        // cannot adopt the local decoder, so keep the prior explicit fallback
        // instead of leaving a pending request that could never complete.
        if CastService.shared.isAirPlayActive {
            handle.stopPreview()
            presentFullScreenWithoutPreview()
            return
        }
        // A tap while the first frame is still buffering must not destroy the
        // preview and create a second provider request. Wait for the preview's
        // KSPlayer/AVPlayer decoder, then borrow that exact session.
        guard handle.canAdopt(media, airPlayActive: CastService.shared.isAirPlayActive) else {
            pendingFullScreenRequest = true
            return
        }
        pendingFullScreenRequest = false
        handle.handOffToFullScreen()
        pendingReturnMedia = nil
        isAwaitingFullScreenDismissal = true
        fullScreenMedia = media
    }

    /// Called when the preview coordinator starts producing frames. One pending
    /// full-screen request can now take ownership without reloading the URL.
    func previewDidStart() {
        guard pendingFullScreenRequest, handle.hasStarted else { return }
        openFullScreen()
    }

    /// A failed preview must cancel a pending full-screen request. Otherwise
    /// tapping Full Screen would wait forever for a frame that cannot arrive.
    func previewFailed(_ mediaID: String) {
        guard miniMedia?.id == mediaID, handle.owner == .preview else { return }
        pendingFullScreenRequest = false
        failedMediaID = mediaID
    }

    /// Used only when preview was explicitly disabled, so no decoder exists.
    private func presentFullScreenWithoutPreview() {
        guard let media = miniMedia, fullScreenMedia == nil else { return }
        pendingFullScreenRequest = false
        pendingReturnMedia = nil
        isAwaitingFullScreenDismissal = true
        fullScreenMedia = media
    }

    func returnedFromFullScreen() {
        guard isAwaitingFullScreenDismissal, fullScreenMedia == nil else { return }
        isAwaitingFullScreenDismissal = false
        pendingFullScreenRequest = false
        if let switchedMedia = pendingReturnMedia {
            // A different channel was selected in full screen, so the old
            // preview decoder cannot be adopted. Rebuild only after UIKit
            // removes the full-screen video host; never while it is playing.
            pendingReturnMedia = nil
            handle.release()
            miniMedia = switchedMedia
            failedMediaID = nil
            reloadToken += 1
            return
        }
        if handle.owner == .fullScreen, let media = miniMedia,
           handle.media?.id == media.id {
            _ = handle.returnToPreview(mediaID: media.id)
        }
        if handle.finishReturnToPreview() {
            failedMediaID = nil
            return
        }
        // Unsupported decoders reopen only after the full-screen host ends.
        handle.release()
        failedMediaID = nil
        reloadToken += 1
    }

    /// Explicitly restart the selected stream in the embedded player.
    /// Ordinary tab changes and full-screen handoffs never call this.
    func restartCurrentChannel() {
        guard miniMedia != nil, fullScreenMedia == nil,
              !isAwaitingFullScreenDismissal,
              handle.owner == .preview || handle.owner == .released else { return }
        pendingFullScreenRequest = false
        pendingReturnMedia = nil
        handle.stopPreview()
        failedMediaID = nil
        userStopped = false
        reloadToken += 1
    }

    func close() {
        guard fullScreenMedia == nil else { return }
        userStopped = true
        pendingFullScreenRequest = false
        pendingReturnMedia = nil
        handle.stopPreview()
        miniMedia = nil
        failedMediaID = nil
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

    /// A manual iPhone channel tap always plays in the fixed embedded
    /// player, even when automatic guide preview is set to Off or Info Only.
    /// That preference still controls automatic guide restore behavior.
    private var embeddedMode: GuidePreviewMode {
        #if os(iOS)
        if mode == .off || mode == .infoOnly { return .small }
        #endif
        if session.miniMedia?.isLive == false { return .small }
        return mode
    }

    #if os(tvOS)
    @AppStorage(TVGuideDesign.storageKey)
    private var guideDesignRaw = TVGuideDesign.classic.rawValue

    private var guideDesign: TVGuideDesign {
        TVGuideDesign(storedValue: guideDesignRaw)
    }
    #endif

    var body: some View {
        Group {
            if let media = session.miniMedia, embeddedMode.showsHero {
                #if os(tvOS)
                tvPlayer(media)
                #else
                phonePlayer(media)
                #endif
            }
        }
        .onChange(of: session.handle.hasStarted) { _, started in
            if started { session.previewDidStart() }
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
    /// Fixed embedded player: tvOS neon-glass treatment with native iPhone
    /// controls. Only the decoration changes; the video decoder keeps its
    /// existing stable position and full-screen handoff lifecycle.
    private func phonePlayer(_ media: PlayableMedia) -> some View {
        VStack(spacing: 0) {
            surface(media)
                .frame(height: embeddedMode == .large ? 192 : (embeddedMode == .infoOnly ? 98 : 152))
                .overlay(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(media.isLive ? "LIVE" : "PLAYING")
                            .font(.caption2.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                media.isLive ? Color.red.opacity(0.9)
                                    : DreamCASTMobileTheme.electricBlue.opacity(0.9),
                                in: Capsule()
                            )
                        Text(media.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer(minLength: 4)
                        Button { session.openFullScreen() } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 35, height: 35)
                        }
                        .accessibilityLabel("Open video full screen")
                        .dreamCASTGlass(radius: 11)
                        Button { session.restartCurrentChannel() } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 35, height: 35)
                        }
                        .accessibilityLabel(media.isLive ? "Restart channel" : "Restart stream")
                        .dreamCASTGlass(radius: 11)
                        Button { session.close() } label: {
                            Image(systemName: "stop.fill")
                                .frame(width: 35, height: 35)
                        }
                        .accessibilityLabel("Stop playback")
                        .dreamCASTGlass(radius: 11)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.86)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 21))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(DreamCASTMobileTheme.iceBlue.opacity(0.94), lineWidth: 1.6)
                }
                .shadow(color: DreamCASTMobileTheme.electricBlue.opacity(0.32), radius: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
    #endif

    /// The tile remains mounted behind full screen to retain its player state.
    /// Only .small and .large render video, matching GuidePreviewMode.
    private func surface(_ media: PlayableMedia) -> some View {
        ZStack {
            Color.black
            if !embeddedMode.playsVideo {
                if let artwork = media.posterURL {
                    AsyncImage(url: artwork) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "tv").font(.largeTitle)
                    }
                } else {
                    Image(systemName: "tv").font(.largeTitle)
                }
            } else if session.failedMediaID == media.id {
                Label("Stream unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.white)
            } else if session.fullScreenMedia == nil ||
                        session.handle.owner != .released {
                // The root keeps this video surface mounted behind full screen.
                // Retaining the tile preserves an adopted decoder and its audio.
                MultiViewTilePlayer(
                    media: media,
                    isMuted: false,
                    role: .guidePreview(handle: session.handle),
                    onFailure: { session.previewFailed(media.id) }
                )
                .id("\(media.id)-\(session.reloadToken)")
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityLabel("Now playing: \(media.title)")
    }
}
#endif
