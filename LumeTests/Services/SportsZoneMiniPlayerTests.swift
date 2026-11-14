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
