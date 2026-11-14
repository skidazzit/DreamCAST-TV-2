#if os(iOS)
import Combine
import Foundation
import SwiftUI

// MARK: - TheSportsDB league detail data

struct SportFrameLeagueStanding: Decodable, Identifiable {
    let idStanding: String?
    let idTeam: String?
    let strTeam: String
    let strBadge: String?
    let strGroup: String?
    let strSeason: String?
    let intRank: String?
    let intPlayed: String?
    let intWin: String?
    let intDraw: String?
    let intLoss: String?
    let intGoalDifference: String?
    let intPoints: String?

    var id: String { idStanding ?? "\(strGroup ?? "")-\(idTeam ?? strTeam)" }
    var badgeURL: URL? { strBadge.flatMap(URL.init(string:)) }
    var rank: Int { Int(intRank ?? "") ?? 9999 }
}

private struct SportFrameLeagueTableResponse: Decodable {
    let table: [SportFrameLeagueStanding]?
}

private struct SportFrameLeagueLookupResponse: Decodable {
    let leagues: [SportFrameLeagueSummary]?
}

private struct SportFrameLeagueSummary: Decodable {
    let strCurrentSeason: String?
    let strBadge: String?
    let strLogo: String?
}

struct SportFrameLeagueTableGroup: Identifiable {
    let name: String
    let standings: [SportFrameLeagueStanding]
    var id: String { name }
}

struct SportFrameLeagueHighlight: Identifiable {
    let id: String
    let title: String
    let dateLabel: String
    let eventID: String?
    let videoURL: URL
    let thumbnailURL: URL?

    /// The v1 highlights endpoint returns video rows under tvhighlights.
    /// Accept the other common response keys without failing the whole page.
    static func decode(_ data: Data, fallbackDate: String) -> [Self] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let records = ["tvhighlights", "highlights", "events", "videos", "event_highlights", "lookup"]
            .compactMap { root[$0] as? [[String: Any]] }
            .first ?? []
        return records.compactMap { item -> Self? in
            let rawURL = ["strVideo", "strYoutube", "strURL"]
                .compactMap { item[$0] as? String }
                .first { !$0.isEmpty }
            guard let rawURL, let url = URL(string: rawURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            let title = [item["strEvent"] as? String, item["strTitle"] as? String,
                         item["strHomeTeam"] as? String]
                .compactMap { $0 }
                .first { !$0.isEmpty } ?? "Match highlights"
            let thumb = [item["strThumb"] as? String, item["strPoster"] as? String]
                .compactMap { $0 }
                .first { !$0.isEmpty }
                .flatMap(URL.init(string:))
            let date = (item["dateEvent"] as? String) ?? fallbackDate
            let id = (item["idVideo"] as? String) ?? rawURL
            return Self(id: id, title: title, dateLabel: date,
                        eventID: item["idEvent"] as? String,
                        videoURL: url, thumbnailURL: thumb)
        }
    }
    /// Only launch a confirmed YouTube URL, never an unrelated host.
    static func isYouTubeVideo(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    /// Match a clip to the selected game. IDs beat titles; a title match must
    /// contain both teams and match the date to avoid opening another game.
    static func videoURL(for event: SportEvent, in clips: [Self]) -> URL? {
        let videos = clips.filter { isYouTubeVideo($0.videoURL) }
        if let exact = videos.first(where: { $0.eventID == event.idEvent }) {
            return exact.videoURL
        }
        guard let date = event.dateEvent,
              let home = event.strHomeTeam, !home.isEmpty,
              let away = event.strAwayTeam, !away.isEmpty else { return nil }
        let homeKey = ChannelMatcher.normalize(home)
        let awayKey = ChannelMatcher.normalize(away)
        guard !homeKey.isEmpty, !awayKey.isEmpty else { return nil }
        return videos.first {
            $0.eventID == nil && $0.dateLabel == date &&
                ChannelMatcher.normalize($0.title).contains(homeKey) &&
                ChannelMatcher.normalize($0.title).contains(awayKey)
        }?.videoURL
    }

    /// A search is the fallback, not a made-up video URL.
    static func searchURL(for event: SportEvent) -> URL {
        let teams: String
        if let home = event.strHomeTeam, let away = event.strAwayTeam {
            teams = "\(home) vs \(away)"
        } else {
            teams = event.name
        }
        let search = [teams, event.dateEvent ?? "", "match highlights"]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var url = URLComponents()
        url.scheme = "https"
        url.host = "www.youtube.com"
        url.path = "/results"
        url.queryItems = [URLQueryItem(name: "search_query", value: search)]
        return url.url ?? URL(string: "https://www.youtube.com/results")!
    }
}

/// One kickoff in the combined TheSportsDB and ESPN league schedule.
enum SportFrameLeagueMatch: Identifiable {
    case sportsDB(SportEvent)
    case espn(SportsZoneESPNMatch)

    var id: String {
        switch self {
        case .sportsDB(let event): "sportsdb:\(event.idEvent)"
        case .espn(let match): "espn:\(match.id)"
        }
    }

    var startDate: Date? {
        switch self {
        case .sportsDB(let event): event.startDate
        case .espn(let match): match.start
        }
    }
}

@MainActor
final class SportFrameLeagueDetailStore: ObservableObject {
    @Published private(set) var liveUpcoming: [SportEvent] = []
    @Published private(set) var recentResults: [SportEvent] = []
    @Published private(set) var standings: [SportFrameLeagueStanding] = []
    @Published private(set) var standingsSource = "TheSportsDB"
    @Published private(set) var espnMatches: [SportsZoneESPNMatch] = []
    @Published private(set) var highlights: [SportFrameLeagueHighlight] = []
    @Published private(set) var season: String?
    @Published private(set) var badgeURL: URL?
    @Published private(set) var loadingMatches = false
    @Published private(set) var loadingStandings = false
    @Published private(set) var loadingHighlights = false
    @Published private(set) var matchError: String?
    @Published private(set) var tableError: String?
    @Published private(set) var highlightError: String?

    /// Combine both providers before sorting, so ESPN matches do not
    /// appear after older TheSportsDB fixtures just because of their source.
    var upcomingMatches: [SportFrameLeagueMatch] {
        (liveUpcoming.map(SportFrameLeagueMatch.sportsDB)
         + espnMatches.map(SportFrameLeagueMatch.espn))
            .sorted { left, right in
                let lhs = left.startDate ?? .distantFuture
                let rhs = right.startDate ?? .distantFuture
                if lhs != rhs { return lhs < rhs }
                return left.id < right.id
            }
    }

    var tableGroups: [SportFrameLeagueTableGroup] {
        let groups = Dictionary(grouping: standings) { row -> String in
            let label = row.strGroup?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return label.isEmpty ? "League table" : label
        }
        return groups.keys.sorted().map { name in
            SportFrameLeagueTableGroup(name: name, standings: (groups[name] ?? []).sorted { $0.rank < $1.rank })
        }
    }

    func refresh(leagueID: String?, leagueName: String, sport: String) async {
        guard let leagueID, !leagueID.isEmpty else {
            matchError = "TheSportsDB has no league ID for this competition."
            tableError = "No league standings available."
            highlightError = "No league highlights available."
            return
        }
        let espn = SportsZoneESPNLeague.map(name: leagueName, sport: sport)
        async let schedule: Void = loadMatches(leagueID: leagueID, espn: espn)
        async let table: Void = loadStandings(leagueID: leagueID, espn: espn)
        async let video: Void = loadHighlights(leagueID: leagueID)
        _ = await (schedule, table, video)
    }

    private static func request(_ endpoint: String, query: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(string:
            "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/\(endpoint)"
        ) else { throw URLError(.badURL) }
        components.queryItems = query
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func loadMatches(leagueID: String, espn: SportsZoneESPNLeague?) async {
        loadingMatches = true
        matchError = nil
        defer { loadingMatches = false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let utcToday = formatter.string(from: .now)
        async let todayData: Data? = try? Self.request("eventsday.php",
            query: [URLQueryItem(name: "d", value: utcToday), URLQueryItem(name: "l", value: leagueID)])
        async let nextData: Data? = try? Self.request("eventsnextleague.php",
            query: [URLQueryItem(name: "id", value: leagueID)])
        async let pastData: Data? = try? Self.request("eventspastleague.php",
            query: [URLQueryItem(name: "id", value: leagueID)])
        let (today, next, past) = await (todayData, nextData, pastData)
        guard !Task.isCancelled else { return }

        func events(from data: Data?) -> [SportEvent] {
            guard let data else { return [] }
            return (try? JSONDecoder().decode(DayResponse.self, from: data).events) ?? []
        }
        let current = events(from: today)
        let future = events(from: next)
        let pastEvents = events(from: past)
        var seen = Set<String>()
        liveUpcoming = (current + future)
            .filter { seen.insert($0.idEvent).inserted && ($0.isLive || $0.isUpcoming) }
            .sorted(by: SportEvent.oldestFirst)
            .prefix(10).map { $0 }

        recentResults = Array(pastEvents
            .filter { !$0.isLive && !$0.isUpcoming }
            .sorted(by: SportEvent.newestFirst)
            .prefix(4))
            .sorted(by: SportEvent.oldestFirst)
        espnMatches = []
        // The Free API may return one next match. Fill sparse fixtures from
        // ESPN without changing TheSportsDB IDs used for broadcaster lookups.
        if liveUpcoming.count < 4, let espn {
            let other = await SportsZoneESPNFallback.shared.matches(for: espn)
            guard !Task.isCancelled else { return }
            espnMatches = other.filter { $0.isLive || $0.isUpcoming }
                .filter { match in
                    !liveUpcoming.contains { event in
                        let home = ChannelMatcher.normalize(event.strHomeTeam ?? "")
                        let away = ChannelMatcher.normalize(event.strAwayTeam ?? "")
                        let sameTeams = home == ChannelMatcher.normalize(match.home)
                            && away == ChannelMatcher.normalize(match.away)
                        let sameKickoff = abs((event.startDate ?? .distantPast).timeIntervalSince(match.start)) < 4 * 3600
                        return sameTeams && sameKickoff
                    }
                }
                .sorted { left, right in
                    if left.start != right.start { return left.start < right.start }
                    return left.id < right.id
                }
                .prefix(10).map { $0 }
        }
        if today == nil && next == nil && past == nil && espnMatches.isEmpty {
            matchError = "Could not load league matches. Pull down to retry."
        }
    }

    private func loadStandings(leagueID: String, espn: SportsZoneESPNLeague?) async {
        loadingStandings = true
        tableError = nil
        defer { loadingStandings = false }
        async let tableData: Data? = try? Self.request("lookuptable.php",
            query: [URLQueryItem(name: "l", value: leagueID)])
        async let lookupData: Data? = try? Self.request("lookupleague.php",
            query: [URLQueryItem(name: "id", value: leagueID)])
        let (table, lookup) = await (tableData, lookupData)
        guard !Task.isCancelled else { return }
        if let table {
            standings = (try? JSONDecoder().decode(SportFrameLeagueTableResponse.self, from: table).table) ?? []
        } else {
            standings = []
            tableError = "Could not load standings. Try refreshing."
        }
        if let lookup, let info = (try? JSONDecoder().decode(
            SportFrameLeagueLookupResponse.self, from: lookup
        ).leagues)?.first {
            season = info.strCurrentSeason
            badgeURL = [info.strBadge, info.strLogo].compactMap { $0 }
                .first { !$0.isEmpty }.flatMap(URL.init(string:))
        }
        standingsSource = "TheSportsDB"
        // Free API tables can stop at five entries. ESPN fills known leagues
        // only when it returns a more complete set of teams.
        if standings.count < 8, let espn {
            let replacement = await SportsZoneESPNFallback.shared.standings(for: espn)
            guard !Task.isCancelled else { return }
            if replacement.count > standings.count {
                let recordTable = ["basketball", "baseball", "football"].contains(espn.sport)
                standings = replacement.map { row in
                    SportFrameLeagueStanding(
                        idStanding: row.id, idTeam: nil, strTeam: row.name,
                        strBadge: row.logo?.absoluteString, strGroup: row.group,
                        strSeason: nil, intRank: row.rank, intPlayed: row.played,
                        intWin: row.wins, intDraw: row.draws, intLoss: row.losses,
                        intGoalDifference: recordTable ? row.winPercent : row.difference,
                        intPoints: recordTable ? row.gamesBehind : row.points
                    )
                }
                standingsSource = "ESPN"
                tableError = nil
            }
        }
        if season == nil { season = standings.first?.strSeason }
    }

    /// Resolve the selected finished game to a real YouTube clip, or search
    /// YouTube with its team names and date if no matching clip exists.
    func highlightDestination(for event: SportEvent) async -> URL {
        if let url = SportFrameLeagueHighlight.videoURL(for: event, in: highlights) {
            return url
        }

        // Premium supports an exact event-ID highlight lookup.
        if SportsDBAccess.hasPremiumKey, Int(event.idEvent) != nil,
           let url = URL(string:
                "https://www.thesportsdb.com/api/v2/json/lookup/event_highlights/\(event.idEvent)") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(SportsDBAccess.apiKey, forHTTPHeaderField: "X-API-KEY")
            if let response = try? await URLSession.shared.data(for: request),
               (response.1 as? HTTPURLResponse)?.statusCode == 200 {
                let clips = SportFrameLeagueHighlight.decode(
                    response.0, fallbackDate: event.dateEvent ?? ""
                )
                if let video = clips.first(where: { SportFrameLeagueHighlight.isYouTubeVideo($0.videoURL) }) {
                    return video.videoURL
                }
            }
        }

        // The public v1 API lists highlights by match day, not event ID.
        if let date = event.dateEvent {
            var query = [URLQueryItem(name: "d", value: date)]
            if let leagueID = event.idLeague, !leagueID.isEmpty {
                query.append(URLQueryItem(name: "l", value: leagueID))
            }
            if let data = try? await Self.request("eventshighlights.php", query: query) {
                let clips = SportFrameLeagueHighlight.decode(data, fallbackDate: date)
                if let video = SportFrameLeagueHighlight.videoURL(for: event, in: clips) {
                    return video
                }
            }
        }

        return SportFrameLeagueHighlight.searchURL(for: event)
    }

    private func loadHighlights(leagueID: String) async {
        loadingHighlights = true
        highlightError = nil
        highlights = []
        defer { loadingHighlights = false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar(identifier: .gregorian)
        let days = (0..<7).compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            return formatter.string(from: date)
        }
        var found: [SportFrameLeagueHighlight] = []
        var seen = Set<String>()
        var successfulResponses = 0
        // Two requests at a time limits traffic, while showing fetched clips as
        // soon as a pair finishes. The Free API may have just two clips per day.
        for offset in stride(from: 0, to: days.count, by: 2) {
            guard !Task.isCancelled else { return }
            let firstDate = days[offset]
            let secondDate = offset + 1 < days.count ? days[offset + 1] : nil
            async let first: Data? = try? Self.request("eventshighlights.php", query: [
                URLQueryItem(name: "d", value: firstDate), URLQueryItem(name: "l", value: leagueID)
            ])
            async let second: Data? = {
                guard let secondDate else { return nil }
                return try? await Self.request("eventshighlights.php", query: [
                    URLQueryItem(name: "d", value: secondDate), URLQueryItem(name: "l", value: leagueID)
                ])
            }()
            let (one, two) = await (first, second)
            guard !Task.isCancelled else { return }
            for (data, date) in [(one, firstDate), (two, secondDate ?? "")] {
                guard let data else { continue }
                successfulResponses += 1
                for clip in SportFrameLeagueHighlight.decode(data, fallbackDate: date) {
                    if seen.insert(clip.videoURL.absoluteString).inserted {
                        found.append(clip)
                    }
                }
            }
            highlights = found.sorted { $0.dateLabel > $1.dateLabel }.prefix(10).map { $0 }
            if highlights.count >= 10 { break }
        }
        if successfulResponses == 0 {
            highlightError = "Could not load match highlights. Try refreshing."
        }
    }
}

// MARK: - iPhone league page

struct SportFrameLeagueDetail: View {
    let leagueID: String?
    let leagueName: String
    let sport: String
    let initialBadge: URL?
    let onSelectEvent: (SportEvent) -> Void

    @Environment(\.openURL) private var openURL
    @StateObject private var store = SportFrameLeagueDetailStore()
    @State private var openingHighlightsFor: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    AsyncImage(url: store.badgeURL ?? initialBadge) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "sportscourt")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(leagueName)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text([sport, store.season].compactMap { $0 }.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                matchesSection
                standingsSection
                highlightsSection
            }
            .padding(16)
        }
        .background(Color(red: 0.025, green: 0.055, blue: 0.11).ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle(leagueName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refresh(leagueID: leagueID, leagueName: leagueName, sport: sport) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh league")
            }
        }
        .task(id: leagueID) { await store.refresh(leagueID: leagueID, leagueName: leagueName, sport: sport) }
        .refreshable { await store.refresh(leagueID: leagueID, leagueName: leagueName, sport: sport) }
    }

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Live & upcoming matches", symbol: "play.circle")
            if store.loadingMatches { ProgressView("Loading league matches…") }
            if let error = store.matchError { Text(error).font(.subheadline).foregroundStyle(.orange) }
            if !store.loadingMatches && store.liveUpcoming.isEmpty && store.espnMatches.isEmpty && store.matchError == nil {
                emptyMessage("No live or upcoming matches returned for this league.")
            }
            ForEach(store.upcomingMatches) { match in
                switch match {
                case .sportsDB(let event):
                    Button { onSelectEvent(event) } label: { fixtureRow(event) }
                        .buttonStyle(.plain)
                case .espn(let event):
                    espnFixtureRow(event)
                }
            }
            if !store.recentResults.isEmpty {
                Text("Recent results").font(.subheadline.bold()).foregroundStyle(.secondary)
                recentResultsTable
            }
        }
    }

    /// Compact results table with matchups, actual scores and full kickoff date/time.
    private var recentResultsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Matchup").frame(maxWidth: .infinity, alignment: .leading)
                Text("Score").frame(width: 64)
                Text("Date").frame(width: 78, alignment: .leading)
            }
            .font(.caption.bold()).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 10)

            ForEach(store.recentResults) { event in
                Button { openHighlights(for: event) } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 7) {
                            teamRow(event.strHomeTeam ?? "Home", image: event.homeBadge)
                            teamRow(event.strAwayTeam ?? "Away", image: event.awayBadge)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Group {
                            if let home = event.intHomeScore, let away = event.intAwayScore {
                                Text("\(home) – \(away)")
                            } else {
                                Text("Result")
                            }
                        }
                        .font(.subheadline.bold().monospacedDigit())
                        .frame(width: 64)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.startDate?.formatted(.dateTime.month(.abbreviated).day())
                                 ?? event.dateEvent ?? "Date TBA")
                            if openingHighlightsFor == event.idEvent {
                                ProgressView().controlSize(.small).tint(.cyan)
                            } else {
                                Text(event.timeLabel).foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                        .frame(width: 78, alignment: .leading)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(.white.opacity(0.12))
            }
        }
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Results open the correct highlight video, not the live-channel picker.
    private func openHighlights(for event: SportEvent) {
        guard openingHighlightsFor == nil else { return }
        openingHighlightsFor = event.idEvent
        Task {
            let destination = await store.highlightDestination(for: event)
            openingHighlightsFor = nil
            openURL(destination)
        }
    }

    private func fixtureRow(_ event: SportEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                teamRow(event.strHomeTeam ?? "Home", image: event.homeBadge)
                teamRow(event.strAwayTeam ?? "Away", image: event.awayBadge)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                if let home = event.intHomeScore, let away = event.intAwayScore {
                    Text("\(home) - \(away)").font(.headline.monospacedDigit())
                } else {
                    Text(event.timeLabel).font(.subheadline.weight(.semibold))
                }
                Text(event.isLive ? "LIVE" : event.isUpcoming ? "UPCOMING" : "RESULT")
                    .font(.caption2.bold())
                    .foregroundStyle(event.isLive ? .green : .secondary)
                Text(event.startDate?.formatted(date: .abbreviated, time: .omitted)
                     ?? event.dateEvent ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func espnFixtureRow(_ match: SportsZoneESPNMatch) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                teamRow(match.home, image: match.homeLogo)
                teamRow(match.away, image: match.awayLogo)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                if match.isLive || match.isFinal {
                    Text("\(match.homeScore ?? "-") : \(match.awayScore ?? "-")")
                        .font(.headline.monospacedDigit())
                } else {
                    Text(match.start.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                }
                Text(match.isLive ? "LIVE" : match.status)
                    .font(.caption).foregroundStyle(match.isLive ? .green : .secondary)
                Text("ESPN • \(match.start.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func teamRow(_ name: String, image: URL?) -> some View {
        HStack(spacing: 9) {
            AsyncImage(url: image) { $0.resizable().scaledToFit() }
                placeholder: { Image(systemName: "shield").foregroundStyle(.secondary) }
                .frame(width: 27, height: 27)
            Text(name).font(.subheadline.weight(.medium)).lineLimit(2)
        }
    }

    private var standingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("League standings", symbol: "list.number")
                Spacer()
                if !store.standings.isEmpty {
                    Text(store.standingsSource).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.loadingStandings { ProgressView("Loading standings…") }
            if let error = store.tableError { Text(error).font(.subheadline).foregroundStyle(.orange) }
            if !store.loadingStandings && store.standings.isEmpty && store.tableError == nil {
                emptyMessage("No standings available from TheSportsDB or ESPN for this league.")
            }
            ForEach(store.tableGroups) { group in
                VStack(alignment: .leading, spacing: 9) {
                    Text(group.name).font(.subheadline.bold()).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            tableHeading
                            ForEach(group.standings) { team in standingRow(team) }
                        }
                        .frame(minWidth: 400)
                    }
                    .scrollIndicators(.hidden)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if !store.standings.isEmpty && store.standingsSource == "TheSportsDB" && !SportsDBAccess.hasPremiumKey {
                Text("The Free API may show only the first five table rows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var usesRecordColumns: Bool {
        store.standingsSource == "ESPN" &&
            ["Basketball", "Baseball", "American Football"].contains(sport)
    }

    private var tableHeading: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: 24)
            Text("Club").frame(maxWidth: .infinity, alignment: .leading)
            Text("P").frame(width: 26)
            Text("W").frame(width: 26)
            Text("D").frame(width: 26)
            Text("L").frame(width: 26)
            Text(usesRecordColumns ? "PCT" : "GD").frame(width: 30)
            Text(usesRecordColumns ? "GB" : "Pts").frame(width: 34)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(9)
    }

    private func standingRow(_ team: SportFrameLeagueStanding) -> some View {
        HStack(spacing: 6) {
            Text(team.intRank ?? "-").frame(width: 24)
            HStack(spacing: 7) {
                AsyncImage(url: team.badgeURL) { $0.resizable().scaledToFit() }
                    placeholder: { Image(systemName: "shield").foregroundStyle(.secondary) }
                    .frame(width: 21, height: 21)
                Text(team.strTeam).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(team.intPlayed ?? "-").frame(width: 26)
            Text(team.intWin ?? "-").frame(width: 26)
            Text(team.intDraw ?? "-").frame(width: 26)
            Text(team.intLoss ?? "-").frame(width: 26)
            Text(team.intGoalDifference ?? "-").frame(width: 30)
            Text(team.intPoints ?? "-").fontWeight(.bold).frame(width: 34)
        }
        .font(.caption)
        .padding(9)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recent match highlights", symbol: "play.rectangle")
            if store.loadingHighlights { ProgressView("Finding recent highlights…") }
            if let error = store.highlightError { Text(error).font(.subheadline).foregroundStyle(.orange) }
            if !store.loadingHighlights && store.highlights.isEmpty && store.highlightError == nil {
                emptyMessage("No recent video highlights are listed for this league.")
            }
            ForEach(store.highlights) { clip in
                Button { openURL(clip.videoURL) } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: clip.thumbnailURL) { $0.resizable().scaledToFill() }
                            placeholder: {
                                Image(systemName: "play.rectangle.fill")
                                    .resizable().scaledToFit().foregroundStyle(.secondary)
                            }
                            .frame(width: 100, height: 66)
                            .clipped()
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(clip.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(clip.dateLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "play.circle.fill")
                            .font(.title2).foregroundStyle(.cyan)
                    }
                    .padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch \(clip.title) highlights")
            }
            if !store.highlights.isEmpty {
                Text("Videos open in your browser or YouTube. Some clips may be region restricted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.title3.bold())
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
