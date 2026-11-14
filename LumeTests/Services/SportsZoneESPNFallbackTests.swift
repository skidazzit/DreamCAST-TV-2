import Foundation
import Testing
@testable import Lume

struct SportsZoneESPNFallbackTests {
    @Test func onlyKnownLeaguesAreMapped() {
        #expect(SportsZoneESPNLeague.map(name: "NBA", sport: "Basketball")?.league == "nba")
        #expect(SportsZoneESPNLeague.map(name: "English Premier League", sport: "Soccer")?.league == "eng.1")
        #expect(SportsZoneESPNLeague.map(name: "NFL", sport: "American Football")?.sport == "football")
        #expect(SportsZoneESPNLeague.map(name: "NBA", sport: "Soccer") == nil)
        #expect(SportsZoneESPNLeague.map(name: "Premier League of Canada", sport: "Soccer") == nil)
    }

    @Test func groupedNBAStandingsDecode() {
        let json = """
        {"children":[
          {"name":"Eastern Conference","standings":{"entries":[
            {"team":{"id":"2","displayName":"Boston Celtics",
                     "logo":"https://a.espncdn.com/abc.png"},
             "stats":[{"name":"wins","displayValue":"8"},
                      {"name":"losses","displayValue":"4"},
                      {"name":"winPercent","displayValue":".667"},
                      {"name":"gamesBehind","displayValue":"-"}]},
            {"team":{"id":"3","displayName":"New York Knicks"},
             "stats":[{"name":"wins","displayValue":"7"},
                      {"name":"losses","displayValue":"5"}]}
          ]}},
          {"name":"Western Conference","standings":{"entries":[
            {"team":{"id":"4","displayName":"Golden State Warriors"},
             "stats":[{"name":"wins","displayValue":"9"},
                      {"name":"losses","displayValue":"3"}]}
          ]}}
        ]}
        """
        let rows = SportsZoneESPNDecoder.standings(Data(json.utf8))
        #expect(rows.count == 3)
        #expect(rows[0].group == "Eastern Conference")
        #expect(rows[0].rank == "1")
        #expect(rows[0].played == "12")
        #expect(rows[0].winPercent == ".667")
        #expect(rows[0].gamesBehind == "-")
        #expect(rows[2].group == "Western Conference")
        #expect(rows[2].name == "Golden State Warriors")
    }

    @Test func scoreboardMatchesKeepStateAndLogos() {
        let json = """
        {"events":[
          {"id":"100","date":"2026-11-13T00:00Z","status":{"type":{"state":"in","description":"In Progress"}},
           "competitions":[{"competitors":[
             {"homeAway":"home","team":{"displayName":"Boston Celtics","logo":"https://example.com/a.png"},"score":"97"},
             {"homeAway":"away","team":{"displayName":"New York Knicks"},"score":"90"}
           ]}]},
          {"id":"101","date":"2026-11-14T00:00:00Z","status":{"type":{"state":"pre","description":"Scheduled"}},
           "competitions":[{"competitors":[
             {"homeAway":"home","team":{"displayName":"Pacers"}},
             {"homeAway":"away","team":{"displayName":"Bucks"}}
           ]}]}
        ]}
        """
        let matches = SportsZoneESPNDecoder.matches(Data(json.utf8))
        #expect(matches.count == 2)
        #expect(matches[0].isLive)
        #expect(matches[0].homeScore == "97")
        #expect(matches[0].homeLogo != nil)
        #expect(matches[1].isUpcoming)
        #expect(matches[1].home == "Pacers")
    }

    @Test func sportEventsSortEarliestDateAndKickoffTimeFirst() throws {
        let data = Data("""
        [
          {"idEvent":"late","dateEvent":"2026-11-15","strTime":"22:00:00"},
          {"idEvent":"early","dateEvent":"2026-11-15","strTime":"18:00:00"},
          {"idEvent":"yesterday","dateEvent":"2026-11-14","strTime":"20:00:00"},
          {"idEvent":"unknown"}
        ]
        """.utf8)
        let events = try JSONDecoder().decode([SportEvent].self, from: data)
            .sorted(by: SportEvent.oldestFirst)
        #expect(events.map(\.idEvent) == ["yesterday", "early", "late", "unknown"])
    }

    @Test func decoderHandlesMissingData() {
        #expect(SportsZoneESPNDecoder.matches(Data("{}".utf8)).isEmpty)
        #expect(SportsZoneESPNDecoder.standings(Data(#"{"children":[]}"#.utf8)).isEmpty)
    }
}
