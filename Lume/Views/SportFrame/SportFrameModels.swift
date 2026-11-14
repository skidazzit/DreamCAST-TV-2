import Foundation

struct SportEvent: Decodable, Identifiable {
    let idEvent: String
    let strEvent: String?
    let strHomeTeam: String?
    let strAwayTeam: String?
    let strLeague: String?
    let idLeague: String?
    let strLeagueBadge: String?
    let strSport: String?
    let strHomeTeamBadge: String?
    let strAwayTeamBadge: String?
    let dateEvent: String?
    let strTime: String?
    let strTimestamp: String?
    let strStatus: String?
    let strProgress: String?
    let intHomeScore: String?
    let intAwayScore: String?

    var id: String { idEvent }

    /// Sort full kickoff timestamps, newest first. Unknown dates go last.
    /// The event ID keeps the order stable when kickoffs are equal.
    static func newestFirst(_ lhs: SportEvent, _ rhs: SportEvent) -> Bool {
        let left = lhs.startDate ?? .distantPast
        let right = rhs.startDate ?? .distantPast
        if left != right { return left > right }
        return lhs.idEvent < rhs.idEvent
    }
    var name: String { strEvent ?? "Upcoming event" }
    var league: String { strLeague ?? "Other league" }
    var leagueBadge: URL? { strLeagueBadge.flatMap(URL.init(string:)) }
    var homeBadge: URL? { strHomeTeamBadge.flatMap(URL.init(string:)) }
    var awayBadge: URL? { strAwayTeamBadge.flatMap(URL.init(string:)) }
    var kickoff: String { [dateEvent, strTime].compactMap { $0 }.joined(separator: "  ") }

    var startDate: Date? {
        if let strTimestamp, let date = ISO8601DateFormatter().date(from: strTimestamp) { return date }
        guard let dateEvent, let strTime else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "\(dateEvent) \(strTime)")
    }

    var isLive: Bool {
        if let startDate, startDate > Date() { return false }
        let status = (strStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Use the provider's explicit match period. Do not guess from the score.
        let livePeriods: Set<String> = ["1H", "2H", "HT", "ET", "Q1", "Q2", "Q3", "Q4", "OT", "P1", "P2", "P3"]
        return status == "LIVE" || status == "IN PLAY" || status.hasPrefix("LIVE ") || livePeriods.contains(status)
    }

    var isUpcoming: Bool { !isLive && (startDate.map { $0 > Date() } ?? false) }
    var timeLabel: String {
        guard let startDate else { return strTime ?? "Time TBA" }
        return startDate.formatted(date: .omitted, time: .shortened)
    }
}

struct DayResponse: Decodable { let events: [SportEvent]? }

enum ChannelMatcher {
    static func normalize(_ text: String) -> String {
        let normalized = text.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : " "
        }
        return normalized.joined().split(separator: " ").joined(separator: " ")
    }

}
