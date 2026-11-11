import Foundation
import Combine
import Security

struct SportFrameScore: Equatable {
    let home: String?
    let away: String?
    let status: String?
}

enum SportsDBAccess {
    private static let keychainAccount = "sportFrameSportsDBPremiumKey"

    static var hasPremiumKey: Bool { loadKey() != nil }
    static var apiKey: String { loadKey() ?? "123" }

    private static var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.skidazzit.dreamcasttv2.sportsdb",
         kSecAttrAccount as String: keychainAccount]
    }

    private static func loadKey() -> String? {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").contains($0)
        }) else { return false }
        let values: [String: Any] = [kSecValueData as String: Data(cleaned.utf8),
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(keyQuery as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var query = keyQuery
        query.merge(values) { _, new in new }
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func remove() { SecItemDelete(keyQuery as CFDictionary) }
}

@MainActor
final class FixtureStore: ObservableObject {
    @Published private(set) var events: [SportEvent] = []
    @Published private(set) var eventSports: [String: String] = [:]
    @Published private(set) var nextDayEvents: [SportEvent] = []
    @Published private(set) var nextDaySports: [String: String] = [:]
    @Published private(set) var scoreUpdates: [String: SportFrameScore] = [:]
    @Published private(set) var liveScores: [String: SportFrameScore] = [:]
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    func fetch(sports: [String], date: Date, quietly: Bool = false) async {
        if !quietly { loading = true; error = nil }
        defer { if !quietly { loading = false } }
        guard !sports.isEmpty else { events = []; eventSports = [:]; nextDayEvents = []; nextDaySports = [:]; return }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = .current
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        var results: [SportEvent] = []
        var sportMap: [String: String] = [:]
        var upcoming: [SportEvent] = []
        var upcomingSports: [String: String] = [:]
        var failures = 0
        for sport in sports {
            if Task.isCancelled { return }
            // UTC kickoff times can land on the following calendar day.
            // Fetch both API dates and sort them into the viewer's local day.
            for requestDate in [date, tomorrow] {
                if Task.isCancelled { return }
                var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/eventsday.php")!
                parts.queryItems = [URLQueryItem(name: "d", value: day.string(from: requestDate)),
                                    URLQueryItem(name: "s", value: sport)]
                guard let url = parts.url else { failures += 1; continue }
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let dayEvents = try JSONDecoder().decode(DayResponse.self, from: data).events ?? []
                    for event in dayEvents {
                        if isOnLocalDay(event, date: date, calendar: calendar) {
                            sportMap[event.idEvent] = sport
                            results.append(event)
                        } else if calendar.isDateInToday(date) && isOnLocalDay(event, date: tomorrow, calendar: calendar) {
                            upcomingSports[event.idEvent] = sport
                            upcoming.append(event)
                        }
                    }
                } catch {
                    failures += 1
                }
            }
        }
        if Task.isCancelled { return }
        // One event may appear under multiple sport labels. Keep its first copy.
        var ids = Set<String>()
        let fetched = results.filter { ids.insert($0.idEvent).inserted }
        if quietly && failures == sports.count * 2 { return }
        if eventFingerprint(events) != eventFingerprint(fetched) { events = fetched }
        if eventSports != sportMap { eventSports = sportMap }
        if !quietly && failures > 0 { error = failures == sports.count * 2 ? "Could not load sports schedules." : nil }
        var upcomingIDs = Set<String>()
        let nextEvents = calendar.isDateInToday(date) ? upcoming.filter { upcomingIDs.insert($0.idEvent).inserted } : []
        let nextSports = calendar.isDateInToday(date) ? upcomingSports : [:]
        if eventFingerprint(nextDayEvents) != eventFingerprint(nextEvents) { nextDayEvents = nextEvents }
        if nextDaySports != nextSports { nextDaySports = nextSports }
    }

    func score(for event: SportEvent) -> SportFrameScore {
        let schedule = scoreUpdates[event.idEvent]
        let live = liveScores[event.idEvent]
        return SportFrameScore(home: live?.home ?? schedule?.home ?? event.intHomeScore,
                               away: live?.away ?? schedule?.away ?? event.intAwayScore,
                               status: live?.status ?? schedule?.status ?? event.strStatus)
    }

    func isLive(_ event: SportEvent) -> Bool {
        // The live-score endpoint also returns scheduled fixtures. Require a
        // real in-play status and never label a future kickoff as live.
        if let startDate = event.startDate, startDate > Date() { return false }
        let status = (score(for: event).status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let livePeriods: Set<String> = ["1H", "2H", "HT", "ET", "Q1", "Q2", "Q3", "Q4", "OT", "P1", "P2", "P3"]
        return status == "LIVE" || status == "IN PLAY" || status.hasPrefix("LIVE ") || livePeriods.contains(status)
    }

    // Refresh scores without changing the event list, card IDs, or loading state.
    func refreshScores(sports: [String], date: Date) async {
        guard !sports.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        var updates: [String: SportFrameScore] = [:]
        for sport in sports {
            for requestDate in [date, tomorrow] {
                if Task.isCancelled { return }
                var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/eventsday.php")!
                parts.queryItems = [URLQueryItem(name: "d", value: formatter.string(from: requestDate)),
                                    URLQueryItem(name: "s", value: sport)]
                guard let url = parts.url else { continue }
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                    for event in try JSONDecoder().decode(DayResponse.self, from: data).events ?? [] {
                        updates[event.idEvent] = SportFrameScore(home: event.intHomeScore, away: event.intAwayScore, status: event.strStatus)
                    }
                } catch { continue }
            }
        }
        if !Task.isCancelled && !updates.isEmpty && updates != scoreUpdates { scoreUpdates = updates }
    }

    // Premium V2 is polled on its own two-minute schedule.
    func refreshLiveScores() async {
        guard SportsDBAccess.hasPremiumKey,
              let url = URL(string: "https://www.thesportsdb.com/api/v2/json/livescore/all") else { return }
        var request = URLRequest(url: url)
        request.setValue(SportsDBAccess.apiKey, forHTTPHeaderField: "X_API_KEY")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let rows = payload.values.compactMap { $0 as? [[String: Any]] }.first ?? []
            var scores: [String: SportFrameScore] = [:]
            for row in rows {
                let eventID = (row["idEvent"] as? String) ?? (row["idEvent"] as? Int).map { String($0) }
                guard let eventID else { continue }
                func field(_ key: String) -> String? {
                    if let value = row[key] as? String { return value }
                    if let value = row[key] as? NSNumber { return value.stringValue }
                    return nil
                }
                scores[eventID] = SportFrameScore(home: field("intHomeScore"), away: field("intAwayScore"), status: field("strStatus"))
            }
            guard !Task.isCancelled else { return }
            if scores != liveScores { liveScores = scores }
        } catch {
            // Keep the last known values during a temporary network failure.
        }
    }

    private func isOnLocalDay(_ event: SportEvent, date: Date, calendar: Calendar) -> Bool {
        if let kickoff = event.startDate { return calendar.isDate(kickoff, inSameDayAs: date) }
        // Older fixtures have no timestamp. Use their supplied date as a fallback.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        guard let rawDate = event.dateEvent, let fallback = formatter.date(from: rawDate) else { return false }
        return calendar.isDate(fallback, inSameDayAs: date)
    }

    private func eventFingerprint(_ events: [SportEvent]) -> [String] {
        events.map {
            "\($0.idEvent)|\($0.strStatus ?? "")|\($0.intHomeScore ?? "")|\($0.intAwayScore ?? "")|\($0.strTimestamp ?? "")"
        }
    }
}
