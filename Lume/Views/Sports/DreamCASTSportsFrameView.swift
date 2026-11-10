#if os(tvOS)
import SwiftUI

// The DreamCAST SportsFrame tab stays independent from Lume's ESPN Sports Hub.
// TheSportsDB schedules, match broadcasts and the DreamCAST table layout live here.
struct DreamCASTSportsFrameView: View {
    @State private var selectedDay = 1
    @State private var selectedSport = "Soccer"
    @State private var events: [DreamCASTSportEvent] = []
    @State private var loading = false
    @State private var message: String?
    @State private var selectedEvent: DreamCASTSportEvent?

    private let sports = ["Soccer", "American Football", "Basketball", "Baseball", "Ice Hockey", "Motorsport", "Tennis", "Cricket", "Rugby"]
    private let days = ["Yesterday", "Today", "Tomorrow"]

    private var day: Date {
        Calendar.current.date(byAdding: .day, value: selectedDay - 1, to: .now) ?? .now
    }

    private var leagues: [(String, [DreamCASTSportEvent])] {
        let groups = Dictionary(grouping: events, by: { $0.league })
        return groups.keys.sorted().map { ($0, (groups[$0] ?? []).sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }) }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.12, blue: 0.22), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SPORTSFRAME").font(.system(size: 48, weight: .bold))
                            Text("DreamCAST TV 2 • Scores, fixtures and broadcasts")
                                .font(.system(size: 24)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(sports, id: \.self) { sport in
                                Button(sport) { selectedSport = sport }
                                    .buttonStyle(.borderedProminent)
                                    .tint(selectedSport == sport ? .cyan : .gray.opacity(0.35))
                            }
                        }
                    }
                    Picker("Day", selection: $selectedDay) {
                        ForEach(0..<3, id: \.self) { index in Text(days[index]).tag(index) }
                    }
                    .pickerStyle(.segmented)
                    if loading { ProgressView("Loading fixtures…") }
                    if let message { Text(message).foregroundStyle(.secondary) }
                    ForEach(leagues, id: \.0) { league, games in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(league).font(.system(size: 30, weight: .semibold))
                                Spacer()
                                Text("\(games.count) matches").foregroundStyle(.secondary)
                            }
                            .padding(20)
                            .background(LinearGradient(colors: [.cyan.opacity(0.38), .blue.opacity(0.16)], startPoint: .leading, endPoint: .trailing))
                            ForEach(games) { game in
                                Button { selectedEvent = game } label: {
                                    HStack(spacing: 18) {
                                        Text(game.timeLabel).frame(width: 135, alignment: .leading)
                                        Text(game.home).frame(maxWidth: .infinity, alignment: .trailing)
                                        Text(game.score).fontWeight(.bold).frame(width: 110)
                                        Text(game.away).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(game.isLive ? "LIVE" : game.status).foregroundStyle(game.isLive ? .green : .secondary)
                                            .frame(width: 155)
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.system(size: 24))
                                    .padding(.horizontal, 24).frame(height: 84)
                                }
                                .buttonStyle(.plain)
                                Divider().opacity(0.25)
                            }
                        }
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(50)
            }
        }
        .sheet(item: $selectedEvent) { event in DreamCASTBroadcastSheet(event: event) }
        .task(id: "\(selectedSport)-\(selectedDay)") { await refresh() }
    }

    private func refresh() async {
        loading = true
        message = nil
        defer { loading = false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let requestedDay = day
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: requestedDay) ?? requestedDay
        var found: [DreamCASTSportEvent] = []
        var successes = 0
        for candidate in [requestedDay, nextDay] {
            var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/123/eventsday.php")!
            parts.queryItems = [.init(name: "d", value: formatter.string(from: candidate)), .init(name: "s", value: selectedSport)]
            guard let url = parts.url else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                let payload = try JSONDecoder().decode(DreamCASTSportResponse.self, from: data)
                found += (payload.events ?? []).filter { game in
                    guard let start = game.start else { return candidate == requestedDay }
                    return Calendar.current.isDate(start, inSameDayAs: requestedDay)
                }
                successes += 1
            } catch { /* Show a clear offline state after both requests. */ }
        }
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        events = found.filter { seen.insert($0.id).inserted }
        if successes == 0 { message = "Could not load TheSportsDB fixtures." }
        else if events.isEmpty { message = "No matches found for this sport and day." }
    }
}

private struct DreamCASTSportResponse: Decodable { let events: [DreamCASTSportEvent]? }

private struct DreamCASTSportEvent: Decodable, Identifiable {
    let idEvent: String
    let strHomeTeam: String?
    let strAwayTeam: String?
    let strLeague: String?
    let strTimestamp: String?
    let strStatus: String?
    let intHomeScore: String?
    let intAwayScore: String?

    var id: String { idEvent }
    var home: String { strHomeTeam ?? "Home" }
    var away: String { strAwayTeam ?? "Away" }
    var league: String { strLeague ?? "Other league" }
    var start: Date? {
        guard let strTimestamp else { return nil }
        return ISO8601DateFormatter().date(from: strTimestamp)
    }
    var timeLabel: String { start?.formatted(date: .omitted, time: .shortened) ?? "TBA" }
    var score: String { if let intHomeScore, let intAwayScore { return "\(intHomeScore) – \(intAwayScore)" }; return "vs" }
    var status: String { strStatus ?? "Scheduled" }
    var isLive: Bool {
        guard start.map({ $0 <= .now }) ?? false else { return false }
        let value = status.uppercased()
        return value == "LIVE" || value == "IN PLAY" || ["1H", "2H", "HT", "ET", "Q1", "Q2", "Q3", "Q4", "OT", "P1", "P2", "P3"].contains(value)
    }
}

private struct DreamCASTBroadcasterResponse: Decodable { let tvevent: [DreamCASTBroadcaster]? }
private struct DreamCASTBroadcaster: Decodable {
    let strChannel: String?
}

private struct DreamCASTBroadcastSheet: View {
    let event: DreamCASTSportEvent
    @Environment(\.dismiss) private var dismiss
    @State private var channels: [String] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                Section("\(event.home) vs \(event.away)") {
                    if loading { ProgressView() }
                    else if channels.isEmpty { Text("No broadcaster names listed by TheSportsDB.") }
                    ForEach(channels, id: \.self) { channel in
                        Label(channel, systemImage: "tv")
                    }
                }
            }
            .navigationTitle("Broadcasters")
            .toolbar { Button("Done") { dismiss() } }
        }
        .task {
            defer { loading = false }
            guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/123/lookuptv.php?id=\(event.id)") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(DreamCASTBroadcasterResponse.self, from: data)
                channels = Array(Set((response.tvevent ?? []).compactMap(\.strChannel).filter { !$0.isEmpty })).sorted()
            } catch { /* An empty list is shown when the lookup fails. */ }
        }
    }
}
#endif
