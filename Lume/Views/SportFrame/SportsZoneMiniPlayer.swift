#if os(iOS) || os(tvOS)
import SwiftUI

/// One SportsZone live playback session, shared by its guide and mini-player.
/// The same PreviewPlayerHandle transfers a running decoder to full screen
/// and restores it when the viewer backs out, as Live TV does.
@MainActor @Observable
final class SportsZonePlaybackSession {
    let handle = PreviewPlayerHandle()
    var miniMedia: PlayableMedia?
    var fullScreenMedia: PlayableMedia?
    var failedMediaID: String?
    var reloadToken = 0

    func tune(_ media: PlayableMedia) {
        // Reselecting the same channel must not restart its decoder.
        guard miniMedia?.id != media.id else { return }
        handle.stopPreview()
        failedMediaID = nil
        reloadToken += 1
        miniMedia = media
        LiveChannelHistory.record(media)
    }

    func openFullScreen() {
        guard let media = miniMedia, fullScreenMedia == nil else { return }
        if handle.canAdopt(media, airPlayActive: CastService.shared.isAirPlayActive) {
            handle.handOffToFullScreen()
        } else {
            // When the engine cannot hand off, release the preview connection
            // before full screen opens a new one.
            handle.stopPreview()
        }
        fullScreenMedia = media
    }

    func returnedFromFullScreen() {
        // Called after the full-screen UIKit surface has been dismissed.
        if handle.owner == .fullScreen, let id = handle.media?.id {
            _ = handle.returnToPreview(mediaID: id)
        }
        if !handle.finishReturnToPreview() {
            // Engines without handoff start a fresh mini-player on return.
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

/// The mini-player is always audible and never changes streams on a focus
/// move, event refresh or league switch. Only selecting a channel calls tune.
struct SportsZoneMiniPlayer: View {
    let session: SportsZonePlaybackSession

    var body: some View {
        if let media = session.miniMedia {
            #if os(tvOS)
                HStack(alignment: .center, spacing: 26) {
                    surface(media)
                        .frame(width: 405, height: 228)
                    VStack(alignment: .leading, spacing: 18) {
                        Text("NOW PLAYING")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(media.title)
                            .font(.title2.bold())
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
                    Spacer(minLength: 0)
                }
                .padding(22)
                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24))
                .focusSection()
            #else
                HStack(spacing: 12) {
                    surface(media)
                        .frame(width: 142, height: 80)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NOW PLAYING")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(media.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        session.openFullScreen()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.headline)
                    }
                    .accessibilityLabel("Open SportsZone full screen")
                    Button {
                        session.close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Stop SportsZone playback")
                }
                .padding(10)
                .background(Color(red: 0.09, green: 0.13, blue: 0.2),
                            in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 10)
            #endif
        }
    }

    private func surface(_ media: PlayableMedia) -> some View {
        ZStack {
            Color.black
            if session.failedMediaID == media.id {
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
                // Retain the actual player across full-screen handoff. A new
                // identity is needed only for a different stream or fallback.
                .id("\(media.id)-\(session.reloadToken)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("SportsZone playing \(media.title)")
    }
}
#endif
