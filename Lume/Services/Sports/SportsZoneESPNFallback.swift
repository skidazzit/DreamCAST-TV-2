import Foundation

/// Read-only ESPN fallback for leagues whose names are known and unambiguous.
/// ESPN's site JSON endpoints are public but unofficial, so every call must
/// fail safely without interrupting TheSportsDB or the IPTV player.
nonisolated struct SportsZoneESPNLeague: Sendable {
    let sport: String
    let league: String

    static func map(name: String, sport: String) -> Self? {
        let key = ChannelMatcher.normalize(name)
        let requestedSport = ChannelMatcher.normalize(sport)
        let mappings: [String: (String, String)] = [
            "nba": ("basketball", "nba"),
            "national basketball association": ("basketball", "nba"),
            "wnba": ("basketball", "wnba"),
            "w nba": ("basketball", "wnba"),
            "nfl": ("football", "nfl"),
            "national football league": ("football", "nfl"),
            "nhl": ("hockey", "nhl"),
            "national hockey league": ("hockey", "nhl"),
            "mlb": ("baseball", "mlb"),
            "major league baseball": ("baseball", "mlb"),
            "english premier league": ("soccer", "eng.1"),
            "premier league": ("soccer", "eng.1"),
            "spanish la liga": ("soccer", "esp.1"),
            "la liga": ("soccer", "esp.1"),
            "german bundesliga": ("soccer", "ger.1"),
            "bundesliga": ("soccer", "ger.1"),
            "italian serie a": ("soccer", "ita.1"),
            "serie a": ("soccer", "ita.1"),
            "french ligue 1": ("soccer", "fra.1"),
            "ligue 1": ("soccer", "fra.1"),
            "major league soccer": ("soccer", "usa.1"),
            "mls": ("soccer", "usa.1"),
            "uefa champions league": ("soccer", "uefa.champions"),
            "uefa europa league": ("soccer", "uefa.europa")
        ]
        guard let entry = mappings[key] else { return nil }
        // A named league must belong to the same sport. A mixed/unknown sport
        // label can still be used when TheSportsDB omits strSport.
        let accepted: [String: Set<String>] = [
            "basketball": ["basketball"],
            "football": ["american football", "football", "nfl"],
            "hockey": ["ice hockey", "hockey"],
            "baseball": ["baseball"],
            "soccer": ["soccer", "association football"]
        ]
        if !requestedSport.isEmpty,
           !(accepted[entry.0]?.contains(requestedSport) ?? false) {
            return nil
        }
        return Self(sport: entry.0, league: entry.1)
    }
}

nonisolated struct SportsZoneESPNStanding: Sendable, Identifiable {
    let id: String
    let group: String
    let name: String
    let logo: URL?
    let rank: String
    let played: String
    let wins: String
    let draws: String
    let losses: String
    let difference: String
    let points: String
}

nonisolated struct SportsZoneESPNMatch: Sendable, Identifiable {
    let id: String
    let home: String
    let away: String
    let homeLogo: URL?
    let awayLogo: URL?
    let homeScore: String?
    let awayScore: String?
    let start: Date
    let state: String
    let status: String

    var isLive: Bool { state == "in" }
    var isUpcoming: Bool { state == "pre" }
    var isFinal: Bool { state == "post" }
}

nonisolated enum SportsZoneESPNDecoder {
    static func standings(_ data: Data) -> [SportsZoneESPNStanding] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var result: [SportsZoneESPNStanding] = []
        func parse(_ group: [String: Any], path: String) {
            let groupName = group["name"] as? String ?? group["abbreviation"] as? String ?? path
            let name = groupName.isEmpty ? path : groupName
            if let standings = group["standings"] as? [String: Any],
               let entries = standings["entries"] as? [[String: Any]] {
                for (position, entry) in entries.enumerated() {
                    guard let team = entry["team"] as? [String: Any],
                          let title = team["displayName"] as? String ?? team["name"] as? String,
                          !title.isEmpty else { continue }
                    let stats = entry["stats"] as? [[String: Any]] ?? []
                    func stat(_ names: [String]) -> String {
                        for stat in stats {
                            let id = (stat["name"] as? String ?? "").lowercased()
                            let abbr = (stat["abbreviation"] as? String ?? "").lowercased()
                            if names.contains(id) || names.contains(abbr) {
                                return stat["displayValue"] as? String
                                    ?? (stat["value"] as? NSNumber)?.stringValue ?? "-"
                            }
                        }
                        return "-"
                    }
                    let logoText = ((team["logos"] as? [[String: Any]])?.first?["href"] as? String)
                        ?? team["logo"] as? String
                    let teamID = team["id"] as? String ?? title
                    let rank = stat(["rank", "playoffseed", "seed"])
                    result.append(.init(
                        id: "\(name)|\(teamID)",
                        group: name,
                        name: title,
                        logo: logoText.flatMap(URL.init(string:)),
                        rank: rank == "-" ? String(position + 1) : rank,
                        played: stat(["gamesplayed", "gp", "played"]),
                        wins: stat(["wins", "w"]),
                        draws: stat(["ties", "draws", "d", "t"]),
                        losses: stat(["losses", "l"]),
                        difference: stat(["pointdifferential", "goaldifference", "gd", "diff"]),
                        points: stat(["points", "pts", "p"])
                    ))
                }
            }
            for child in group["children"] as? [[String: Any]] ?? [] {
                parse(child, path: name)
            }
        }
        parse(root, path: "League table")
        return result
    }

    static func matches(_ data: Data) -> [SportsZoneESPNMatch] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.timeZone = TimeZone(secondsFromGMT: 0)
        short.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return events.compactMap { item -> SportsZoneESPNMatch? in
            guard let id = item["id"] as? String,
                  let dateText = item["date"] as? String,
                  let date = iso.date(from: dateText) ?? short.date(from: dateText),
                  let competition = (item["competitions"] as? [[String: Any]])?.first,
                  let competitors = competition["competitors"] as? [[String: Any]] else { return nil }
            func find(_ side: String) -> [String: Any]? {
                competitors.first { ($0["homeAway"] as? String) == side }
            }
            guard let home = find("home"), let away = find("away"),
                  let homeTeam = home["team"] as? [String: Any],
                  let awayTeam = away["team"] as? [String: Any] else { return nil }
            func name(_ team: [String: Any]) -> String {
                team["displayName"] as? String ?? team["shortDisplayName"] as? String ?? "Team"
            }
            func logo(_ team: [String: Any]) -> URL? {
                let value = team["logo"] as? String
                    ?? ((team["logos"] as? [[String: Any]])?.first?["href"] as? String)
                return value.flatMap(URL.init(string:))
            }
            let statusObject = item["status"] as? [String: Any]
                ?? competition["status"] as? [String: Any]
                ?? [:]
            let type = statusObject["type"] as? [String: Any] ?? [:]
            let state = type["state"] as? String ?? "pre"
            return .init(
                id: id,
                home: name(homeTeam), away: name(awayTeam),
                homeLogo: logo(homeTeam), awayLogo: logo(awayTeam),
                homeScore: home["score"] as? String,
                awayScore: away["score"] as? String,
                start: date,
                state: state,
                status: type["shortDetail"] as? String
                    ?? type["description"] as? String
                    ?? (state == "in" ? "LIVE" : state == "post" ? "Final" : "Scheduled")
            )
        }
    }
}

/// Memory-only cache reduces requests to ESPN's undocumented website API.
/// Network failures return nil; callers retain TheSportsDB data when possible.
actor SportsZoneESPNFallback {
    static let shared = SportsZoneESPNFallback()
    private struct Cached {
        let date: Date
        let data: Data
    }
    private var cache: [String: Cached] = [:]

    private func get(_ url: URL, ttl: TimeInterval) async -> Data? {
        let key = url.absoluteString
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < ttl {
            return cached.data
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        cache[key] = .init(date: .now, data: data)
        return data
    }

    func standings(for league: SportsZoneESPNLeague) async -> [SportsZoneESPNStanding] {
        guard let url = URL(string:
            "https://site.api.espn.com/apis/v2/sports/\(league.sport)/\(league.league)/standings"
        ), let data = await get(url, ttl: 30 * 60) else { return [] }
        return SportsZoneESPNDecoder.standings(data)
    }

    func matches(for league: SportsZoneESPNLeague) async -> [SportsZoneESPNMatch] {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(secondsFromGMT: 0)
        date.dateFormat = "yyyyMMdd"
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: .now) ?? .now
        let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 7, to: .now) ?? .now
        guard var url = URLComponents(string:
            "https://site.api.espn.com/apis/site/v2/sports/\(league.sport)/\(league.league)/scoreboard"
        ) else { return [] }
        url.queryItems = [
            URLQueryItem(name: "dates", value: "\(date.string(from: start))-\(date.string(from: end))"),
            URLQueryItem(name: "limit", value: "250")
        ]
        guard let endpoint = url.url,
              let data = await get(endpoint, ttl: 5 * 60) else { return [] }
        let matches = SportsZoneESPNDecoder.matches(data)
        return matches.sorted {
            if $0.isLive != $1.isLive { return $0.isLive }
            return $0.start < $1.start
        }
    }
}
