import Foundation
import Testing
@testable import Lume

@MainActor
struct SportsZoneScoreRefreshTests {
    @Test func liveAndPremiumScoresRefreshEveryMinute() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let early = start.addingTimeInterval(59)
        let due = start.addingTimeInterval(60)
        #expect(SportsZoneScoreRefreshPolicy.liveInterval == 60)
        #expect(SportsZoneScoreRefreshPolicy.premiumInterval == 60)
        #expect(!SportsZoneScoreRefreshPolicy.isDue(
            since: start, interval: SportsZoneScoreRefreshPolicy.liveInterval, now: early
        ))
        #expect(SportsZoneScoreRefreshPolicy.isDue(
            since: start, interval: SportsZoneScoreRefreshPolicy.liveInterval, now: due
        ))
    }

    @Test func upcomingFixturesRefreshEveryFiveMinutes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SportsZoneScoreRefreshPolicy.upcomingInterval == 300)
        #expect(!SportsZoneScoreRefreshPolicy.isDue(
            since: start, interval: SportsZoneScoreRefreshPolicy.upcomingInterval,
            now: start.addingTimeInterval(299)
        ))
        #expect(SportsZoneScoreRefreshPolicy.isDue(
            since: start, interval: SportsZoneScoreRefreshPolicy.upcomingInterval,
            now: start.addingTimeInterval(300)
        ))
    }

    @Test func finalScoreChecksRequireAConfirmedFinalStatus() {
        for status in ["FT", "Final", "Match Finished", "AET", "PEN", "Final/OT"] {
            #expect(SportsZoneScoreRefreshPolicy.isFinal(status))
        }
        for status in ["LIVE", "1H", "HT", "2H", "Q4", "Scheduled", "Postponed", ""] {
            #expect(!SportsZoneScoreRefreshPolicy.isFinal(status))
        }
        #expect(!SportsZoneScoreRefreshPolicy.isFinal(nil))
    }
}
