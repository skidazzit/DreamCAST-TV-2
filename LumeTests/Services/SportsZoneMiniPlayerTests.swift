import Foundation
import KSPlayer
import Testing
@testable import Lume

#if os(iOS) || os(tvOS)
@MainActor
struct SportsZoneMiniPlayerTests {
    private func media(_ id: String) -> PlayableMedia {
        PlayableMedia(
            id: id,
            url: URL(string: "https://example.org/live/\(id).m3u8")!,
            title: "Channel \(id)",
            subtitle: nil,
            posterURL: nil,
            kind: .live,
            startTime: 0,
            contentRef: .live(id)
        )
    }

    @Test func selectingTheSameSportsChannelDoesNotRetune() {
        let session = SportsZonePlaybackSession()
        session.tune(media("a"))
        let originalToken = session.reloadToken
        session.tune(media("a"))
        #expect(session.miniMedia?.id == "a")
        #expect(session.reloadToken == originalToken)
    }

    @Test func selectingAnotherChannelUpdatesTheMiniPlayer() {
        let session = SportsZonePlaybackSession()
        session.tune(media("a"))
        let originalToken = session.reloadToken
        session.tune(media("b"))
        #expect(session.miniMedia?.id == "b")
        #expect(session.reloadToken > originalToken)
    }

    @Test func previewOffOpensFullScreenInsteadOfPlayingBehindThePage() {
        let session = SportsZonePlaybackSession()
        session.tune(media("a"), previewMode: .off)
        #expect(session.miniMedia?.id == "a")
        #expect(session.fullScreenMedia?.id == "a")
    }

    @Test func infoOnlyDoesNotForceFullScreen() {
        let session = SportsZonePlaybackSession()
        session.tune(media("a"), previewMode: .infoOnly)
        #expect(session.miniMedia?.id == "a")
        #expect(session.fullScreenMedia == nil)
    }

    @Test func repeatedFullScreenReturnKeepsAnAdoptedDecoder() {
        let session = SportsZonePlaybackSession()
        let channel = media("a")
        session.tune(channel)
        let decoder = KSVideoPlayer.Coordinator()
        session.handle.register(media: channel, resolved: nil, coordinator: .ks(decoder))
        session.handle.markStarted()

        let initialReloads = session.reloadToken
        session.openFullScreen()
        #expect(session.handle.owner == .fullScreen)
        session.fullScreenMedia = nil
        session.returnedFromFullScreen()

        #expect(session.handle.owner == .preview)
        #expect(session.handle.coordinator?.ksCoordinator === decoder)
        #expect(session.reloadToken == initialReloads)

        // SwiftUI sometimes sends another dismissal after view updates.
        session.returnedFromFullScreen()
        #expect(session.handle.owner == .preview)
        #expect(session.handle.coordinator?.ksCoordinator === decoder)
        #expect(session.reloadToken == initialReloads)
    }

    @Test func duplicateFallbackDismissalDoesNotRestartTwice() {
        let session = SportsZonePlaybackSession()
        session.tune(media("a"))
        session.openFullScreen() // No decoder available for adoption yet.
        let before = session.reloadToken
        session.fullScreenMedia = nil
        session.returnedFromFullScreen()
        #expect(session.reloadToken == before + 1)
        session.returnedFromFullScreen()
        #expect(session.reloadToken == before + 1)
    }

    @Test func stoppingMiniPlayerClearsOnlyTheSportsSession() {
        let session = SportsZonePlaybackSession()
        session.tune(media("a"))
        session.close()
        #expect(session.miniMedia == nil)
        #expect(session.fullScreenMedia == nil)
        #expect(session.handle.owner == .released)
    }
}
#endif
