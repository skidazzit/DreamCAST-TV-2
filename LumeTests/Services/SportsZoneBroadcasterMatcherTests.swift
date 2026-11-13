import Testing
@testable import Lume

struct SportsZoneBroadcasterMatcherTests {
    @Test func espnExactAndFeedVariants() {
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN", channelName: "ESPN") == .exact)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN", channelName: "US: ESPN HD") == .feedVariant)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN", channelName: "CA | ESPN FHD 1080p") == .feedVariant)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN", channelName: "ESPN UHD 4K") == .feedVariant)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN", channelName: "ESPN HD [Backup]") == .feedVariant)
    }

    @Test func espnDoesNotShowOtherNetworks() {
        for name in [
            "ESPN2", "ESPN 2", "ESPN 2 HD", "ESPN3", "ESPN Deportes",
            "ESPN+", "ESPN Plus HD", "ESPN News", "ESPNU", "ESPN HD 2", "Fox Sports 1"
        ] {
            #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN", channelName: name) == nil)
        }
    }

    @Test func espnTwoRemainsItsOwnNetwork() {
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN2", channelName: "ESPN 2") == .exact)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN 2", channelName: "ESPN2 HD") == .feedVariant)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN 2", channelName: "ESPN") == nil)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN 2", channelName: "ESPN3 HD") == nil)
    }

    @Test func espnPlusIsDistinctFromEspn() {
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN+", channelName: "ESPN+") == .exact)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN+", channelName: "ESPN Plus HD") == .feedVariant)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN+", channelName: "ESPN") == nil)
    }

    @Test func fullNetworkNameRequired() {
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "Sky Sports Main Event", channelName: "UK: Sky Sports Main Event HD") == .feedVariant)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "Sky Sports Main Event", channelName: "Sky Sports Football") == nil)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "Fox Sports 1", channelName: "FOX SPORTS1") == .exact)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "Fox Sports 1", channelName: "Fox Sports 2") == nil)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "BBC", channelName: "BBC News HD") == nil)
    }

    @Test func emptyBroadcasterCannotMatchEverything() {
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "", channelName: "ESPN") == nil)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "  ", channelName: "ESPN") == nil)
        #expect(SportsZoneBroadcasterMatcher.match(broadcaster: "ESPN", channelName: "") == nil)
    }

    @Test func exactResultsSortBeforeFeedVariants() {
        #expect(SportsZoneBroadcasterMatcher.Match.exact.score > SportsZoneBroadcasterMatcher.Match.feedVariant.score)
    }
}
