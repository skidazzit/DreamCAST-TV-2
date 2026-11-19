import Foundation
import Combine

struct SportCategory: Decodable {
    let strSport: String
}

struct SportsCatalogLeague: Decodable, Identifiable {
    let idLeague: String
    let strLeague: String
    let strSport: String
    let strBadge: String?
    let strLogo: String?
    var id: String { idLeague }
}

private struct SportsListResponse: Decodable { let sports: [SportCategory]? }
private struct SportsLeaguesResponse: Decodable { let leagues: [SportsCatalogLeague]? }

@MainActor
final class SportFrameCatalog: ObservableObject {
    private static let sportsCacheKey = "dreamcast.sportszone.thesportsdb.categories.v1"
    @Published private(set) var sports: [String] = []
    @Published private(set) var leagues: [SportsCatalogLeague] = []
    @Published private(set) var message: String?
    @Published private(set) var badgeURLs: [String: URL] = [:]
    private var requestedBadges = Set<String>()

    init() {
        // Restore TheSportsDB categories before the first network response.
        // The sidebar remains useful after an offline app relaunch.
        sports = UserDefaults.standard.stringArray(forKey: Self.sportsCacheKey) ?? []
    }

    func refresh() async {
        let base = "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/"
        do {
            async let sportsRequest = URLSession.shared.data(from: URL(string: base + "all_sports.php")!)
            async let leaguesRequest = URLSession.shared.data(from: URL(string: base + "all_leagues.php")!)
            let (sportData, sportResponse) = try await sportsRequest
            guard (sportResponse as? HTTPURLResponse)?.statusCode == 200
            else { throw URLError(.badServerResponse) }
            let fetchedSports = Array(Set(
                (try JSONDecoder().decode(SportsListResponse.self, from: sportData).sports ?? [])
                    .map { $0.strSport.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if !fetchedSports.isEmpty {
                sports = fetchedSports
                UserDefaults.standard.set(fetchedSports, forKey: Self.sportsCacheKey)
            }
            // A failing league endpoint must not hide valid TheSportsDB
            // sport categories from the left menu.
            do {
                let (leagueData, leagueResponse) = try await leaguesRequest
                guard (leagueResponse as? HTTPURLResponse)?.statusCode == 200
                else { throw URLError(.badServerResponse) }
                leagues = try JSONDecoder().decode(SportsLeaguesResponse.self, from: leagueData).leagues ?? []
                message = nil
            } catch {
                message = "Sport categories loaded, but league details could not refresh."
            }
        } catch {
            message = "Could not load the sport catalog. Existing choices are still available."
        }
    }

    func leagues(for sport: String) -> [SportsCatalogLeague] {
        leagues.filter { $0.strSport.caseInsensitiveCompare(sport) == .orderedSame }
            .sorted { $0.strLeague.localizedStandardCompare($1.strLeague) == .orderedAscending }
    }

    func leagueID(for leagueName: String, sport: String) -> String? {
        matchingLeague(leagueName, sport: sport)?.idLeague
    }

    func badgeURL(for leagueName: String, sport: String, idLeague: String? = nil) -> URL? {
        if let idLeague, let cached = badgeURLs[idLeague] { return cached }
        guard let league = matchingLeague(leagueName, sport: sport, idLeague: idLeague) else { return nil }
        if let cached = badgeURLs[league.idLeague] { return cached }
        return [league.strBadge, league.strLogo]
            .compactMap { $0 }
            .first { !$0.isEmpty }
            .flatMap(URL.init(string:))
    }

    func loadBadge(for leagueName: String, sport: String, idLeague: String? = nil) async {
        guard let resolvedID = idLeague ?? matchingLeague(leagueName, sport: sport)?.idLeague,
              badgeURL(for: leagueName, sport: sport, idLeague: resolvedID) == nil,
              requestedBadges.insert(resolvedID).inserted else { return }
        guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookupleague.php?id=\(resolvedID)") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let detail = (payload["leagues"] as? [[String: Any]])?.first,
                  let badge = [detail["strBadge"] as? String, detail["strLogo"] as? String]
                    .compactMap({ $0 }).first(where: { !$0.isEmpty }),
                  let badgeURL = URL(string: badge), !Task.isCancelled else { return }
            badgeURLs[resolvedID] = badgeURL
        } catch {
            // Keep the sport icon when the league has no available artwork.
        }
    }

    private func matchingLeague(_ name: String, sport: String, idLeague: String? = nil) -> SportsCatalogLeague? {
        if let idLeague, let league = leagues.first(where: { $0.idLeague == idLeague }) { return league }
        return leagues.first {
            $0.strSport.caseInsensitiveCompare(sport) == .orderedSame &&
            $0.strLeague.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
