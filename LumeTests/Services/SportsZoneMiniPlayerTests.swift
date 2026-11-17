import Foundation
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

    private func movieMedia(_ id: String) -> PlayableMedia {
        PlayableMedia(
            id: id,
            url: URL(string: "https://example.org/vod/\(id).mp4")!,
            title: "Movie \(id)",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 120,
            contentRef: .movie(id)
        )
    }

    @Test func reselectingMoviePreservesSharedPlayerSession() {
        let session = SportsZonePlaybackSession()
        session.tune(movieMedia("m"), previewMode: .small)
        let originalToken = session.reloadToken
        session.tune(movieMedia("m"), previewMode: .small)

        #expect(session.miniMedia?.kind == .vod)
        #expect(session.miniMedia?.id == "m")
        #expect(session.miniMedia?.startTime == 120)
        #expect(session.reloadToken == originalToken)
        #expect(session.fullScreenMedia == nil)
    }

    @Test func selectingEpisodeUsesSameSessionRatherThanIndependentPlayer() {
        let session = SportsZonePlaybackSession()
        session.tune(media("live"))
        let originalToken = session.reloadToken
        session.tune(movieMedia("episode-1"), previewMode: .small)

        #expect(session.miniMedia?.id == "episode-1")
        #expect(session.reloadToken == originalToken + 1)
        #expect(session.fullScreenMedia == nil)
    }

    @Test func fullScreenRequestWaitsForMiniPlayerDecoderRatherThanReloading() {
        let session = SportsZonePlaybackSession()
        session.tune(media("a"), previewMode: .small)
        let originalToken = session.reloadToken

        // No running preview has been registered yet. Full screen must not
        // open its own second stream while the existing preview is buffering.
        session.openFullScreen()
        #expect(session.fullScreenMedia == nil)
        #expect(session.pendingFullScreenRequest)
        #expect(session.reloadToken == originalToken)

        // Navigating away from Live TV does not affect the pending session.
        session.tune(media("a"), previewMode: .small)
        #expect(session.pendingFullScreenRequest)
        #expect(session.reloadToken == originalToken)

        // An explicit Stop cancels the pending handoff.
        session.close()
        #expect(!session.pendingFullScreenRequest)
        #expect(session.fullScreenMedia == nil)
    }

    @Test func startedDecoderIsBorrowedAndReturnedWithoutReload() {
        let session = SportsZonePlaybackSession()
        let selected = media("same")
        session.tune(selected, previewMode: .small)
        let tokenBeforeHandoff = session.reloadToken

        let coordinator = AVPlayerCoordinator(isEmbedded: true)
        session.handle.register(
            media: selected, resolved: selected, coordinator: .av(coordinator)
        )
        session.handle.markStarted()
        let generationBeforeReturn = session.handle.returnGeneration

        session.openFullScreen()
        #expect(session.fullScreenMedia?.id == selected.id)
        #expect(session.handle.owner == .fullScreen)
        #expect(session.handle.coordinator?.avCoordinator === coordinator)
        #expect(session.reloadToken == tokenBeforeHandoff)

        // Full-screen closes first; the owner then returns to the embedded
        // host without starting another decoder or changing the player ID.
        #expect(session.handle.returnToPreview(mediaID: selected.id))
        session.fullScreenMedia = nil
        session.returnedFromFullScreen()

        #expect(session.handle.owner == .preview)
        #expect(session.handle.coordinator?.avCoordinator === coordinator)
        #expect(session.handle.returnGeneration == generationBeforeReturn + 1)
        #expect(session.reloadToken == tokenBeforeHandoff)
    }

    @Test func waitingFullScreenRequestBorrowsDecoderOnceStarted() {
        let session = SportsZonePlaybackSession()
        let selected = media("wait")
        session.tune(selected, previewMode: .small)
        session.openFullScreen()
        #expect(session.pendingFullScreenRequest)
        #expect(session.fullScreenMedia == nil)

        let coordinator = AVPlayerCoordinator(isEmbedded: true)
        session.handle.register(
            media: selected, resolved: selected, coordinator: .av(coordinator)
        )
        session.handle.markStarted()
        session.previewDidStart()

        #expect(!session.pendingFullScreenRequest)
        #expect(session.fullScreenMedia?.id == selected.id)
        #expect(session.handle.owner == .fullScreen)
        #expect(session.handle.coordinator?.avCoordinator === coordinator)
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
