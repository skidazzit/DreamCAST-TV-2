import Foundation
import Testing
@testable import Lume

#if os(iOS)
struct SportFrameLeagueDetailTests {
    @Test func leagueTableRowsReadTheSportsDBFields() throws {
        let json = """
        [
          {"idStanding":"101","strTeam":"Arsenal","intRank":"1",
           "strGroup":"Premier League","strSeason":"2026-2027",
           "intPlayed":"10","intWin":"9","intDraw":"0","intLoss":"1",
           "intGoalDifference":"10","intPoints":"27"},
          {"idStanding":"102","strTeam":"Chelsea","intRank":"5",
           "strGroup":"Premier League","intPlayed":"10","intPoints":"16"}
        ]
        """
        let rows = try JSONDecoder().decode([SportFrameLeagueStanding].self, from: Data(json.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].rank == 1)
        #expect(rows[0].intPoints == "27")
        #expect(rows[0].strSeason == "2026-2027")
        #expect(rows[1].strTeam == "Chelsea")
    }

    @Test func sportsZoneOrdersMatchesByDateThenTimeDescending() throws {
        let json = """
        [
          {"idEvent":"late","dateEvent":"2026-11-13","strTime":"21:30:00"},
          {"idEvent":"early","dateEvent":"2026-11-13","strTime":"18:00:00"},
          {"idEvent":"prior","dateEvent":"2026-11-12","strTime":"23:00:00"},
          {"idEvent":"unknown"}
        ]
        """
        let matches = try JSONDecoder().decode([SportEvent].self, from: Data(json.utf8))
            .sorted(by: SportEvent.newestFirst)
        #expect(matches.map(\.idEvent) == ["late", "early", "prior", "unknown"])
    }

    @Test func highlightsDecodeYouTubeVideoAndDate() {
        let json = """
        {"tvhighlights":[
          {"idVideo":"500","idEvent":"2494105","strEvent":"Arsenal vs Chelsea",
           "strVideo":"https://www.youtube.com/watch?v=abc123",
           "strThumb":"https://example.org/thumb.jpg"}
        ]}
        """
        let results = SportFrameLeagueHighlight.decode(Data(json.utf8), fallbackDate: "2026-11-12")
        #expect(results.count == 1)
        #expect(results[0].title == "Arsenal vs Chelsea")
        #expect(results[0].id == "500")
        #expect(results[0].dateLabel == "2026-11-12")
        #expect(results[0].videoURL.host == "www.youtube.com")
    }

    @Test func matchResultOpensTheRightYouTubeVideo() throws {
        let match = try JSONDecoder().decode(SportEvent.self, from: Data("""
        {"idEvent":"981","strHomeTeam":"Houston Rockets",
         "strAwayTeam":"Utah Jazz","dateEvent":"2026-11-13","strTime":"20:30:00"}
        """.utf8))
        let clips = SportFrameLeagueHighlight.decode(Data("""
        {"tvhighlights":[
          {"idEvent":"999","strEvent":"Other game","dateEvent":"2026-11-13",
           "strVideo":"https://www.youtube.com/watch?v=other"},
          {"idEvent":"981","strEvent":"Houston Rockets vs Utah Jazz",
           "dateEvent":"2026-11-13","strVideo":"https://youtu.be/correct"}
        ]}
        """.utf8), fallbackDate: "2026-11-13")
        #expect(SportFrameLeagueHighlight.videoURL(for: match, in: clips)?.absoluteString
                == "https://youtu.be/correct")
    }

    @Test func unknownHighlightsSearchByMatchAndDate() throws {
        let match = try JSONDecoder().decode(SportEvent.self, from: Data("""
        {"idEvent":"981","strHomeTeam":"Houston Rockets",
         "strAwayTeam":"Utah Jazz","dateEvent":"2026-11-13","strTime":"20:30:00"}
        """.utf8))
        let clips = SportFrameLeagueHighlight.decode(Data("""
        {"tvhighlights":[
          {"idEvent":"999","strEvent":"Other game","dateEvent":"2026-11-13",
           "strVideo":"https://www.youtube.com/watch?v=other"}
        ]}
        """.utf8), fallbackDate: "2026-11-13")
        #expect(SportFrameLeagueHighlight.videoURL(for: match, in: clips) == nil)
        let searchURL = SportFrameLeagueHighlight.searchURL(for: match)
        #expect(searchURL.host == "www.youtube.com")
        #expect(searchURL.path == "/results")
        let term = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "search_query" })?.value
        #expect(term == "Houston Rockets vs Utah Jazz 2026-11-13 match highlights")
    }

    @Test func highlightsHandlesEmptyAndMissingVideo() {
        let empty = Data(#"{"tvhighlights":null}"#.utf8)
        let missing = Data(#"{"tvhighlights":[{"strEvent":"No video"}]}"#.utf8)
        #expect(SportFrameLeagueHighlight.decode(empty, fallbackDate: "2026-11-12").isEmpty)
        #expect(SportFrameLeagueHighlight.decode(missing, fallbackDate: "2026-11-12").isEmpty)
    }

    @Test func highlightsCanReadOtherResponseKeys() {
        let json = Data(#"{"highlights":[{"strTitle":"Game recap","strYoutube":"https://youtu.be/abc"}]}"#.utf8)
        let results = SportFrameLeagueHighlight.decode(json, fallbackDate: "2026-11-11")
        #expect(results.count == 1)
        #expect(results[0].title == "Game recap")
    }
}
#endif
