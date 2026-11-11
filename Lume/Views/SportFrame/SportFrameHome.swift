#if os(tvOS)
import SwiftData
import SwiftUI

/// DreamCAST's SportsFrame presentation, using Lume's own playback and EPG index.
struct SportFrameHome: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @StateObject private var fixtures = FixtureStore()
    @StateObject private var catalog = SportFrameCatalog()
    @AppStorage("sportFrameFollowedSportsV2") private var followedValue = "Soccer|Basketball|American Football"
    @AppStorage("sportFrameSportOrderV2") private var orderValue = "Soccer|Basketball|American Football|Tennis|Motorsport|Ice Hockey|Cricket"
    @AppStorage("sportFrameLeagueSelectionsV2") private var leagueValue = "{}"
    @State private var page = 0
    @State private var dayOffset = 0
    @State private var selectedSport = "All Sports"
    @State private var selectedLeague = "All Leagues"
    @State private var expandedLeagueSport: String?
    @State private var selectedEvent: SportEvent?
    @State private var playingMedia: PlayableMedia?
    @State private var premiumKeyInput = ""
    @State private var keyMessage: String?

    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)
    private let fallbackSports = ["Soccer", "Basketball", "American Football", "Tennis", "Motorsport", "Ice Hockey", "Cricket", "Baseball", "Rugby", "Golf"]

    private var sportOrder: [String] {
        var seen = Set<String>()
        return (orderValue.split(separator: "|").map(String.init) + catalog.sports + fallbackSports)
            .filter { seen.insert($0).inserted }
    }

    private var followedSports: [String] {
        let saved = Set(followedValue.split(separator: "|").map(String.init))
        return sportOrder.filter { saved.contains($0) }
    }

    private var leagueSelections: [String: [String]] {
        guard let data = leagueValue.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func selectedLeagueNames(for sport: String, available: [SportsCatalogLeague]) -> Set<String> {
        if let saved = leagueSelections[sport] { return Set(saved) }
        return Set(available.map(\.strLeague))
    }

    private func saveLeagueChoices(_ names: Set<String>?, for sport: String) {
        var choices = leagueSelections
        if let names { choices[sport] = names.sorted() }
        else { choices.removeValue(forKey: sport) }
        guard let data = try? JSONEncoder().encode(choices),
              let value = String(data: data, encoding: .utf8) else { return }
        leagueValue = value
    }

    private var visibleEvents: [SportEvent] {
        fixtures.events.filter { event in
            guard let sport = fixtures.eventSports[event.idEvent], followedSports.contains(sport) else { return false }
            guard selectedSport == "All Sports" || selectedSport == sport else { return false }
            guard selectedLeague == "All Leagues" || selectedLeague == event.league else { return false }
            return leagueSelections[sport].map { $0.contains(event.league) } ?? true
        }
        .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var visibleLeagues: [(String, [SportEvent])] {
        let grouped = Dictionary(grouping: visibleEvents, by: \.league)
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    private var availableLeagues: [String] {
        let sports = selectedSport == "All Sports" ? followedSports : [selectedSport]
        let names = sports.flatMap { sport -> [String] in
            // Explicit picks are shown even when a league has no match today.
            if let saved = leagueSelections[sport] { return saved }
            return fixtures.events.filter { fixtures.eventSports[$0.idEvent] == sport }.map(\.league)
        }
        return Array(Set(names)).sorted()
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.1, blue: 0.19), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    switch page {
                    case 1: channelPage
                    case 2: settingsPage
                    default: matchesPage
                    }
                }
                .padding(.horizontal, 55)
                .padding(.vertical, 36)
            }
        }
        .sheet(item: $selectedEvent) { event in
            SportFrameMatchSheet(event: event, onPlay: { channel in
                guard let media = SportsPlayback.media(for: channel, in: modelContext) else { return }
                selectedEvent = nil
                // Present after the previous sheet has finished dismissing.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    playingMedia = media
                }
            })
        }
        .fullScreenCover(item: $playingMedia) { FullScreenPlayerView(media: $0) }
        .task { await catalog.refresh() }
        .task(id: "\(dayOffset)|\(followedValue)|\(SportsDBAccess.apiKey)") {
            let selectedDay = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
            await fixtures.fetch(sports: followedSports, date: selectedDay)
        }
        .onChange(of: followedValue) { _, _ in
            if selectedSport != "All Sports" && !followedSports.contains(selectedSport) {
                selectedSport = "All Sports"
            }
            if selectedLeague != "All Leagues" && !availableLeagues.contains(selectedLeague) {
                selectedLeague = "All Leagues"
            }
        }
        .onChange(of: leagueValue) { _, _ in
            if selectedLeague != "All Leagues" && !availableLeagues.contains(selectedLeague) {
                selectedLeague = "All Leagues"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Spacer()
                HStack(spacing: 24) {
                    pageButton("Sports", index: 0)
                    pageButton("Channels", index: 1)
                    pageButton("Settings", index: 2)
                }
                Spacer()
            }
            .padding(.bottom, 10)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SportsZone").font(.system(size: 53, weight: .bold, design: .rounded))
                    Text("Happening now & coming up").font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                if page == 0 {
                    Picker("Day", selection: $dayOffset) {
                        Text("Yesterday").tag(-1)
                        Text("Today").tag(0)
                        Text("Tomorrow").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 650)
                }
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh sports")
            }
            if page == 0 {
                HStack(spacing: 20) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            sportButton("All Sports")
                            ForEach(followedSports, id: \.self) { sport in sportButton(sport) }
                        }
                    }
                    .scrollIndicators(.hidden)

                    Menu {
                        Button("All Leagues") { selectedLeague = "All Leagues" }
                        ForEach(availableLeagues, id: \.self) { league in
                            Button(league) { selectedLeague = league }
                        }
                    } label: {
                        HStack(spacing: 18) {
                            Text(selectedLeague)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                        }
                        .frame(maxWidth: 275)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func pageButton(_ name: String, index: Int) -> some View {
        Button(name) { page = index }
            .buttonStyle(.borderedProminent)
            .tint(page == index ? accent : .gray.opacity(0.12))
    }

    private func sportButton(_ sport: String) -> some View {
        let selected = selectedSport == sport
        return Button(sport) {
            selectedSport = sport
            selectedLeague = "All Leagues"
        }
        .buttonStyle(.borderedProminent)
        .tint(selected ? accent : .gray.opacity(0.25))
    }

    private var matchesPage: some View {
        VStack(alignment: .leading, spacing: 25) {
            if fixtures.loading { ProgressView("Loading matches…") }
            if let error = fixtures.error { Text(error).foregroundStyle(.orange) }
            if visibleEvents.isEmpty && !fixtures.loading {
                Text("No fixtures available. Choose more sports in Settings.")
                    .foregroundStyle(.secondary).padding(30)
            }

            // Two league tables per row, each anchored to the top of its grid cell.
            LazyVGrid(columns: [.init(.flexible(), alignment: .top), .init(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 24) {
                ForEach(visibleLeagues, id: \.0) { league, events in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 17) {
                            AsyncImage(url: catalog.badgeURL(for: league,
                                                              sport: fixtures.eventSports[events[0].idEvent] ?? "")) {
                                image in image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "shield.lefthalf.filled")
                            }
                            .frame(width: 62, height: 62)
                            Text(league).font(.system(size: 30, weight: .bold)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 22)
                        .frame(height: 92)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [accent.opacity(0.67), .blue.opacity(0.16)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 18))

                        ForEach(events) { event in
                            Button { selectedEvent = event } label: { SportFrameFixtureCard(event: event) }
                                .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var channelPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Match channels").font(.largeTitle.bold())
            Text("Open a fixture in Sports to see TheSportsDB broadcasters first, followed by IPTV guide matches.")
                .foregroundStyle(.secondary)
            Text("Your Live TV channels remain managed by Lume.").foregroundStyle(.secondary)
        }
        .padding(26)
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Which sports you follow").font(.largeTitle.bold())
            HStack {
                Button("Select All") { followedValue = sportOrder.joined(separator: "|") }
                Button("Select None") { followedValue = "" }
            }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(sportOrder, id: \.self) { sport in
                    let selected = followedSports.contains(sport)
                    Button {
                        var saved = Set(followedValue.split(separator: "|").map(String.init))
                        if selected { saved.remove(sport) } else { saved.insert(sport) }
                        followedValue = sportOrder.filter { saved.contains($0) }.joined(separator: "|")
                    } label: {
                        Label(sport, systemImage: selected ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("Which leagues you follow").font(.largeTitle.bold()).padding(.top, 22)
            Text("Choose a sport to pick its leagues. All leagues are followed until you change them.")
                .foregroundStyle(.secondary)
            if let message = catalog.message {
                Text(message).foregroundStyle(.orange)
            }
            ForEach(followedSports, id: \.self) { sport in
                let leagues = catalog.leagues(for: sport)
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        expandedLeagueSport = expandedLeagueSport == sport ? nil : sport
                    } label: {
                        HStack(spacing: 16) {
                            Text(sport).font(.title2.bold())
                            Spacer()
                            let selectedCount = selectedLeagueNames(for: sport, available: leagues).count
                            Text(leagues.isEmpty ? "No leagues found" : "\(selectedCount) of \(leagues.count) leagues")
                                .foregroundStyle(.secondary)
                            Image(systemName: expandedLeagueSport == sport ? "chevron.up" : "chevron.down")
                        }
                        .padding(14)
                    }
                    .buttonStyle(.bordered)

                    if expandedLeagueSport == sport {
                        if leagues.isEmpty {
                            Text("No leagues are listed for this sport yet.").foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Button("Select All") { saveLeagueChoices(nil, for: sport) }
                                Button("Select None") { saveLeagueChoices([], for: sport) }
                            }
                            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 10) {
                                ForEach(leagues) { league in
                                    let selected = selectedLeagueNames(for: sport, available: leagues)
                                        .contains(league.strLeague)
                                    Button {
                                        var names = selectedLeagueNames(for: sport, available: leagues)
                                        if selected { names.remove(league.strLeague) }
                                        else { names.insert(league.strLeague) }
                                        saveLeagueChoices(names.count == leagues.count ? nil : names, for: sport)
                                    } label: {
                                        Label(league.strLeague,
                                              systemImage: selected ? "checkmark.circle.fill" : "circle")
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
            Text("TheSportsDB Premium API key (optional)").font(.title2.bold())
            SecureField("API key", text: $premiumKeyInput)
            HStack {
                Button("Save Key") {
                    keyMessage = SportsDBAccess.save(premiumKeyInput) ? "Key saved securely." : "Could not save the key."
                    premiumKeyInput = ""
                }
                Button("Remove Key") { SportsDBAccess.remove(); keyMessage = "Key removed." }
            }
            if let keyMessage { Text(keyMessage).foregroundStyle(.secondary) }
        }
    }

    private func refresh() async {
        let selectedDay = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
        await fixtures.fetch(sports: followedSports, date: selectedDay)
    }
}

private struct SportFrameFixtureCard: View {
    let event: SportEvent
    @Environment(\.isFocused) private var focused
    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 16) {
                    team(event.strHomeTeam ?? "Home", badge: event.homeBadge)
                    team(event.strAwayTeam ?? "Away", badge: event.awayBadge)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 9) {
                    if event.intHomeScore != nil && event.intAwayScore != nil {
                        Text(score).font(.system(size: 29, weight: .bold))
                    } else {
                        Text(event.timeLabel).font(.system(size: 23, weight: .bold))
                    }
                    Text(event.isLive ? "LIVE" : (event.strStatus ?? "Scheduled"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(event.isLive ? .green : .secondary)
                    if event.intHomeScore != nil && event.intAwayScore != nil {
                        Text(event.timeLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 115, alignment: .trailing)
            }
            Divider().overlay(.white.opacity(0.15))
            SportFrameFixtureBroadcasters(eventID: event.idEvent)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(.white.opacity(focused ? 0.17 : 0.07), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(focused ? accent : .clear, lineWidth: 3))
    }

    private var score: String {
        if let home = event.intHomeScore, let away = event.intAwayScore { return "\(home) : \(away)" }
        return "vs"
    }

    private func team(_ name: String, badge: URL?) -> some View {
        HStack(spacing: 13) {
            AsyncImage(url: badge) { image in image.resizable().scaledToFit() }
                placeholder: { Image(systemName: "shield").resizable().scaledToFit().foregroundStyle(.secondary) }
                .frame(width: 47, height: 47)
            Text(name).font(.system(size: 21, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SportFrameBroadcaster: Decodable, Identifiable {
    let id: String?
    let strChannel: String?
    let strLogo: String?
    var name: String { strChannel ?? "TV Channel" }
    var logoURL: URL? { strLogo.flatMap(URL.init(string:)) }
    var stableID: String { id ?? name }
}

private struct SportFrameBroadcastResponse: Decodable { let tvevent: [SportFrameBroadcaster]? }

@MainActor
private enum SportFrameBroadcasts {
    static func fetch(eventID: String) async -> [SportFrameBroadcaster] {
        guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookuptv.php?id=\(eventID)") else { return [] }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let records = try JSONDecoder().decode(SportFrameBroadcastResponse.self, from: data).tvevent ?? []
            var seen = Set<String>()
            return records.filter { seen.insert(ChannelMatcher.normalize($0.name)).inserted }
        } catch { return [] }
    }
}

private struct SportFrameFixtureBroadcasters: View {
    let eventID: String
    @State private var listings: [SportFrameBroadcaster] = []
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 12) {
            if !loaded { ProgressView().controlSize(.small) }
            else if listings.isEmpty { Text("No broadcasters listed").foregroundStyle(.secondary) }
            ForEach(listings.prefix(3), id: \.stableID) { listing in
                HStack(spacing: 6) {
                    AsyncImage(url: listing.logoURL) { image in image.resizable().scaledToFit() }
                        placeholder: { Image(systemName: "tv") }
                        .frame(width: 35, height: 25)
                    Text(listing.name).font(.system(size: 15)).lineLimit(1)
                }
            }
            if listings.count > 3 { Text("+\(listings.count - 3)").foregroundStyle(.secondary) }
        }
        .task(id: eventID) {
            loaded = false
            listings = await SportFrameBroadcasts.fetch(eventID: eventID)
            loaded = true
        }
    }
}

/// Broadcaster-first lookup from DreamCAST, with Lume's indexed EPG search below it.
private struct SportFrameMatchSheet: View {
    let event: SportEvent
    let onPlay: (ResolvedChannel) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Environment(\.dismiss) private var dismiss
    @State private var broadcasters: [SportFrameBroadcaster] = []
    @State private var selectedBroadcaster: String?
    @State private var foundChannels: [ResolvedChannel] = []
    @State private var loading = true

    private var broadcasterMatches: [ResolvedChannel] {
        guard let selectedBroadcaster else { return [] }
        let broadcaster = ChannelMatcher.normalize(selectedBroadcaster)
        return foundChannels.filter {
            let name = " " + ChannelMatcher.normalize($0.stream.name) + " "
            return name.contains(" " + broadcaster + " ")
        }
    }

    private var epgMatches: [ResolvedChannel] {
        let used = Set(broadcasterMatches.map(\.id))
        return foundChannels.filter { !used.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(event.strHomeTeam ?? "Home") vs \(event.strAwayTeam ?? "Away")")
                        .font(.largeTitle.bold())
                    Text("TheSportsDB broadcasters").font(.title2.bold())
                    if loading { ProgressView("Finding IPTV matches…") }
                    else if broadcasters.isEmpty { Text("No broadcaster names listed.").foregroundStyle(.secondary) }
                    ForEach(broadcasters, id: \.stableID) { broadcaster in
                        Button {
                            selectedBroadcaster = broadcaster.name
                        } label: {
                            HStack {
                                AsyncImage(url: broadcaster.logoURL) { image in image.resizable().scaledToFit() }
                                    placeholder: { Image(systemName: "tv") }.frame(width: 65, height: 42)
                                Text(broadcaster.name)
                                Spacer()
                                if selectedBroadcaster == broadcaster.name { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if let selectedBroadcaster {
                        Text("Channels matching \(selectedBroadcaster)").font(.title2.bold())
                        if broadcasterMatches.isEmpty { Text("No matching channel in your playlist.").foregroundStyle(.secondary) }
                        ForEach(broadcasterMatches) { channel in channelRow(channel) }
                    }
                    Text("More matches from your IPTV guide").font(.title2.bold())
                    if epgMatches.isEmpty && !loading { Text("No other match-name results found.").foregroundStyle(.secondary) }
                    ForEach(epgMatches) { channel in channelRow(channel) }
                }
                .padding(50)
            }
            .navigationTitle("Match channels")
            .toolbar { Button("Back") { dismiss() } }
        }
        .task(id: event.idEvent) {
            loading = true
            broadcasters = await SportFrameBroadcasts.fetch(eventID: event.idEvent)
            guard !Task.isCancelled else { return }
            let fixture = makeFixture()
            let matches = await SportsChannelResolver.resolve(
                container: modelContext.container, fixtures: [fixture], now: Date(), restriction: restriction
            )
            guard !Task.isCancelled else { return }
            foundChannels = matches[fixture.id] ?? []
            loading = false
        }
    }

    private func channelRow(_ channel: ResolvedChannel) -> some View {
        Button { onPlay(channel) } label: {
            HStack {
                AsyncImage(url: channel.stream.streamIcon.flatMap(URL.init(string:))) { image in image.resizable().scaledToFit() }
                    placeholder: { Image(systemName: "play.tv") }.frame(width: 60, height: 40)
                Text(channel.stream.name).font(.headline)
                Spacer()
                Image(systemName: "play.fill")
            }
        }
        .buttonStyle(.bordered)
    }

    private func makeFixture() -> SportsFixture {
        let leagueID = "sportsdb:\(event.idLeague ?? "unknown")"
        func competitor(_ name: String?, badge: URL?, score: String?) -> SportsCompetitor? {
            guard let name else { return nil }
            let team = SportsTeam(leagueId: leagueID, teamId: ChannelMatcher.normalize(name),
                                  name: name, shortName: name, abbreviation: String(name.prefix(3)), logoURL: badge)
            return SportsCompetitor(team: team, score: score.flatMap(Int.init))
        }
        let state: SportsFixtureState = event.isLive ? .inProgress : .scheduled
        return SportsFixture(id: "sportsdb:\(event.idEvent)", leagueId: leagueID,
                             leagueName: event.league, leagueAbbreviation: event.league,
                             startDate: event.startDate ?? Date(),
                             status: SportsFixtureStatus(state: state, detail: event.strStatus ?? ""),
                             home: competitor(event.strHomeTeam, badge: event.homeBadge, score: event.intHomeScore),
                             away: competitor(event.strAwayTeam, badge: event.awayBadge, score: event.intAwayScore),
                             broadcasters: broadcasters.map(\.name), name: event.name)
    }
}
#endif
