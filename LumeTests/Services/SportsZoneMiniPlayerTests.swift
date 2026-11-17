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
