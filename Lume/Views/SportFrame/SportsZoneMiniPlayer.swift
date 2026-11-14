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

    func tune(_ media: PlayableMedia, previewMode: GuidePreviewMode = .small) {
        guard miniMedia?.id != media.id else { return }
        handle.stopPreview()
        failedMediaID = nil
        reloadToken += 1
        miniMedia = media
        LiveChannelHistory.record(media)

        // Match the Live TV setting: "Off" means no inline preview.
        // Open the stream full screen rather than playing it off-screen.
        if previewMode == .off {
            openFullScreen()
        }
    }

    func openFullScreen() {
        guard let media = miniMedia, fullScreenMedia == nil else { return }
        if handle.canAdopt(media, airPlayActive: CastService.shared.isAirPlayActive) {
            handle.handOffToFullScreen()
        } else {
            // The selected engine cannot hand over its decoder. Release the
            // preview connection first, then let full screen start normally.
            handle.stopPreview()
        }
        fullScreenMedia = media
    }

    func returnedFromFullScreen() {
        if handle.owner == .fullScreen, let id = handle.media?.id {
            _ = handle.returnToPreview(mediaID: id)
        }
        if !handle.finishReturnToPreview() {
            handle.release()
            reloadToken += 1
        }
    }

    func close() {
        guard fullScreenMedia == nil else { return }
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
                        guard session.miniMedia?.id == media.id else { return }
                        session.failedMediaID = media.id
                    }
                )
                .id("\(media.id)-\(session.reloadToken)")
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityLabel("SportsZone channel: \(media.title)")
    }
}
#endif
