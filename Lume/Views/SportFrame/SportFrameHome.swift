#if os(tvOS)
import SwiftData
import SwiftUI

/// Connection result for the currently selected TheSportsDB tier.
/// A stored key means Premium is configured, not that the key is valid.
private enum SportsZoneAPIConnectionStatus: Equatable {
    case unchecked
    case checking
    case connected
    case invalidKey
    case rateLimited
    case unavailable
    case unexpectedResponse

    var title: String {
        switch self {
        case .unchecked: "Not checked"
        case .checking: "Checking connection…"
        case .connected: "Connected"
        case .invalidKey: "Premium key rejected"
        case .rateLimited: "Rate limit reached"
        case .unavailable: "Connection failed"
        case .unexpectedResponse: "Unexpected API response"
        }
    }

    var detail: String {
        switch self {
        case .unchecked: "Test access to TheSportsDB."
        case .checking: "Contacting TheSportsDB…"
        case .connected: "The selected API returned valid sports data."
        case .invalidKey: "Check your key or remove it to switch to Free."
        case .rateLimited: "Too many requests. Try again shortly."
        case .unavailable: "Check your connection and try again."
        case .unexpectedResponse: "The server returned data we could not verify."
        }
    }

    var symbol: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .checking: "arrow.clockwise"
        case .unchecked: "questionmark.circle"
        case .invalidKey, .rateLimited, .unexpectedResponse: "exclamationmark.triangle.fill"
        case .unavailable: "wifi.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .checking, .unchecked: .secondary
        case .invalidKey, .rateLimited, .unexpectedResponse, .unavailable: .orange
        }
    }
}

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
    @State private var sportsFollowExpanded = false
    @State private var selectedEvent: SportEvent?
    @State private var openedLeague: SportFrameLeagueRoute?
    @State private var playingMedia: PlayableMedia?
    @State private var premiumKeyInput = ""
    @State private var keyMessage: String?
    @State private var apiConnectionStatus: SportsZoneAPIConnectionStatus = .unchecked
    @State private var apiLastChecked: Date?
    /// A new ID cancels the previous test when changing or checking the key.
    @State private var apiCheckID = 0
    @FocusState private var focusedControl: FocusControl?

    private enum FocusControl: Hashable {
        case tab(Int)
        case date
        case refresh
        case sport(String)
        case leagueMenu
        case fixture(String)
        case selectAll
        case selectNone
        case sportSetting(String)
    }

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

    // Honor saved sports even if TheSportsDB has not loaded their catalog data.
    private var followedSportsForLeagueEditor: [String] {
        Array(Set(followedValue.split(separator: "|").map(String.init)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
                    case 1: settingsPage
                    default: matchesPage
                    }
                }
                .padding(.horizontal, 55)
                .padding(.vertical, 36)
            }
        }
        .fullScreenCover(item: $openedLeague) { league in
            SportFrameLeagueDetailTV(league: league)
        }
        .fullScreenCover(item: $selectedEvent) { event in
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
        .onChange(of: page) { _, newPage in
            // Keep the new tab focused until the viewer presses Down.
            focusedControl = .tab(newPage)
        }
        // tvOS handles directional moves through the focus sections below.
        // No programmatic Up/Down moves compete with the system focus engine.
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Spacer()
                HStack(spacing: 24) {
                    pageButton("Sports", index: 0)
                    pageButton("Settings", index: 1)
                }
                Spacer()
            }
            .padding(.bottom, 10)
            .focusSection()

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
                    .focused($focusedControl, equals: .date)
                }
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh sports")
                    .buttonStyle(SportsZonePillStyle())
                    .focused($focusedControl, equals: .refresh)
            }
            .focusSection()
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
                    .buttonStyle(SportsZonePillStyle())
                    .focused($focusedControl, equals: .leagueMenu)
                }
                .focusSection()
            }
        }
    }

    private func pageButton(_ name: String, index: Int) -> some View {
        Button(name) { page = index }
            .buttonStyle(SportsZonePillStyle(isSelected: page == index))
            .focused($focusedControl, equals: .tab(index))
    }

    private func sportButton(_ sport: String) -> some View {
        let selected = selectedSport == sport
        return Button(sport) {
            selectedSport = sport
            selectedLeague = "All Leagues"
        }
        .buttonStyle(SportsZonePillStyle(isSelected: selected))
        .focused($focusedControl, equals: .sport(sport))
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
                        let first = events[0]
                        let sport = fixtures.eventSports[first.idEvent] ?? first.strSport ?? ""
                        let leagueID = first.idLeague ?? catalog.leagueID(for: league, sport: sport)
                        let logoURL = first.leagueBadge ?? catalog.badgeURL(
                            for: league, sport: sport, idLeague: leagueID
                        )
                        Button {
                            openedLeague = SportFrameLeagueRoute(
                                leagueID: leagueID, leagueName: league,
                                sport: sport, badgeURL: logoURL
                            )
                        } label: {
                            HStack(spacing: 17) {
                                AsyncImage(url: logoURL) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "shield.lefthalf.filled")
                                }
                                .frame(width: 62, height: 62)
                                Text(league).font(.system(size: 30, weight: .bold)).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.title3)
                            }
                            .padding(.horizontal, 22)
                            .frame(height: 92)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [accent.opacity(0.67), .blue.opacity(0.16)],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                        }
                        .buttonStyle(TVCardButtonStyle(focusScale: 1.02))
                        .accessibilityLabel("Open \(league) league page")
                        .task(id: leagueID ?? league) {
                            if first.leagueBadge == nil {
                                await catalog.loadBadge(for: league, sport: sport, idLeague: leagueID)
                            }
                        }

                        ForEach(events) { event in
                            Button { selectedEvent = event } label: { SportFrameFixtureCard(event: event) }
                                .buttonStyle(TVCardButtonStyle(focusScale: 1.03))
                                .focused($focusedControl, equals: .fixture(event.idEvent))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .focusSection()
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            sportsDBAPISettings
            Divider()

            Button {
                sportsFollowExpanded.toggle()
                // When collapsing, remove focus from any child now hidden.
                if !sportsFollowExpanded { focusedControl = nil }
            } label: {
                HStack(spacing: 18) {
                    Text("Which sports you follow").font(.largeTitle.bold())
                    Spacer()
                    Text("\(followedSports.count) selected")
                        .font(.title3).foregroundStyle(.secondary)
                    Image(systemName: sportsFollowExpanded ? "chevron.up" : "chevron.down")
                        .font(.title2)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SportsZonePillStyle())
            .focusSection()

            if sportsFollowExpanded {
                HStack {
                    Button("Select All") { followedValue = sportOrder.joined(separator: "|") }
                        .buttonStyle(SportsZonePillStyle())
                        .focused($focusedControl, equals: .selectAll)
                    Button("Select None") { followedValue = "" }
                        .buttonStyle(SportsZonePillStyle())
                        .focused($focusedControl, equals: .selectNone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
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
                        .buttonStyle(SportsZonePillStyle())
                        .focused($focusedControl, equals: .sportSetting(sport))
                    }
                }
                .focusSection()
            }
            Text("Which leagues you follow").font(.largeTitle.bold()).padding(.top, 22)
            Text("Choose a sport to pick its leagues. All leagues are followed until you change them.")
                .foregroundStyle(.secondary)
            if let message = catalog.message {
                Text(message).foregroundStyle(.orange)
            }
            ForEach(followedSportsForLeagueEditor, id: \.self) { sport in
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
                    .buttonStyle(SportsZonePillStyle())

                    if expandedLeagueSport == sport {
                        if leagues.isEmpty {
                            Text("No leagues are listed for this sport yet.").foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Button("Select All") { saveLeagueChoices(nil, for: sport) }
                                    .buttonStyle(SportsZonePillStyle())
                                Button("Select None") { saveLeagueChoices([], for: sport) }
                                    .buttonStyle(SportsZonePillStyle())
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
                                    .buttonStyle(SportsZonePillStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// First section of the tvOS SportsZone settings page. It tests the
    /// selected tier rather than treating a saved key as proof of access.
    private var sportsDBAPISettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                Label("TheSportsDB API", systemImage: "network")
                    .font(.largeTitle.bold())
                Spacer()
                Text(SportsDBAccess.hasPremiumKey ? "Premium" : "Free")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.18), in: Capsule())
            }

            HStack(alignment: .center, spacing: 16) {
                Image(systemName: apiConnectionStatus.symbol)
                    .font(.title2)
                    .foregroundStyle(apiConnectionStatus.tint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(apiConnectionStatus.title)
                        .font(.title3.weight(.semibold))
                    Text(apiConnectionStatus.detail)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if apiConnectionStatus == .checking { ProgressView() }
            }

            if let apiLastChecked {
                Text("Last checked: \(apiLastChecked.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(SportsDBAccess.hasPremiumKey
                 ? "A Premium key is saved. The status above checks whether v2 access works."
                 : "Using the public Free API. Save a Premium key to test v2 access.")
                .foregroundStyle(.secondary)

            SecureField("Premium API key", text: $premiumKeyInput)
                .textContentType(.password)

            HStack(spacing: 16) {
                Button("Save Key") {
                    if SportsDBAccess.save(premiumKeyInput) {
                        premiumKeyInput = ""
                        keyMessage = "Premium key saved."
                        apiCheckID += 1
                    } else {
                        keyMessage = "Enter a valid Premium API key."
                    }
                }
                Button("Remove Key") {
                    SportsDBAccess.remove()
                    premiumKeyInput = ""
                    keyMessage = "Premium key removed. Using Free API."
                    apiCheckID += 1
                }
                Button("Test Connection") {
                    apiCheckID += 1
                }
                .disabled(apiConnectionStatus == .checking)
            }
            .buttonStyle(SportsZonePillStyle())
            .focusSection()

            if let keyMessage {
                Text(keyMessage).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        // The panel is mounted only on the Settings page. Re-test on entry,
        // and after Save, Remove, or an explicit Test Connection action.
        .task(id: apiCheckID) {
            await checkSportsDBConnection()
        }
    }

    @MainActor
    private func checkSportsDBConnection() async {
        apiConnectionStatus = .checking
        apiLastChecked = nil

        // The public v1 API uses key 123. Premium v2 requires a private key
        // in the X-API-KEY header. Never show or log the saved key.
        let isPremium = SportsDBAccess.hasPremiumKey
        let endpoint = isPremium
            ? "https://www.thesportsdb.com/api/v2/json/all/sports"
            : "https://www.thesportsdb.com/api/v1/json/123/all_sports.php"
        guard let url = URL(string: endpoint) else {
            apiConnectionStatus = .unavailable
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if isPremium {
            request.setValue(SportsDBAccess.apiKey, forHTTPHeaderField: "X-API-KEY")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            guard let response = response as? HTTPURLResponse else {
                apiConnectionStatus = .unexpectedResponse
                apiLastChecked = .now
                return
            }

            switch response.statusCode {
            case 200:
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                // Reject error messages and empty payloads even if the server
                // replied 200. Both tiers return a list of sports.
                let hasSports = payload?.values.contains {
                    ($0 as? [[String: Any]])?.isEmpty == false
                } == true
                apiConnectionStatus = hasSports ? .connected : .unexpectedResponse
            case 401, 403:
                apiConnectionStatus = isPremium ? .invalidKey : .unavailable
            case 429:
                apiConnectionStatus = .rateLimited
            default:
                apiConnectionStatus = .unavailable
            }
            apiLastChecked = .now
        } catch {
            guard !Task.isCancelled else { return }
            apiConnectionStatus = .unavailable
            apiLastChecked = .now
        }
    }

    private func refresh() async {
        let selectedDay = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
        await fixtures.fetch(sports: followedSports, date: selectedDay)
    }
}

/// Matches the main Lume tab bar: dark at rest, white with dark text on focus.
private struct SportsZonePillStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        FocusedPill(configuration: configuration, isSelected: isSelected)
    }

    private struct FocusedPill: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(isFocused || isSelected ? Color.black : Color.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(isFocused ? Color.white : (isSelected ? Color.cyan : Color.white.opacity(0.10)),
                            in: Capsule())
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.16), value: isFocused)
                .contentShape(Capsule())
        }
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

/// Search the actual IPTV channel list, excluding unrelated sister networks.
/// Match only the selected network plus safe region/quality feed labels.
nonisolated private enum SportsZoneBroadcasterSearch {
    static func find(name: String, container: ModelContainer, restriction: ContentRestriction) async -> [ResolvedChannel] {
        guard let lookup = SportsZoneBroadcasterMatcher.Lookup(broadcaster: name) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = SportsChannelResolver.candidateStreamDescriptor(restriction: restriction)
            let streams = (try? context.fetch(descriptor)) ?? []
            var results: [(channel: ResolvedChannel, match: SportsZoneBroadcasterMatcher.Match)] = []
            for stream in streams {
                if Task.isCancelled { return [ResolvedChannel]() }
                guard let match = lookup.match(channelName: stream.name),
                      let playlistID = UUID(uuidString: String(stream.id.prefix(36))) else { continue }
                results.append((
                    ResolvedChannel(
                        stream: ResolvedStreamSummary(id: stream.id, name: stream.name,
                                                      streamIcon: stream.streamIcon, epgChannelId: stream.epgChannelId),
                        playlistID: playlistID,
                        matchedTitle: nil,
                        matchedStart: nil,
                        score: match.score,
                        source: .channelName,
                        isConfident: false
                    ), match
                ))
            }
            return results.sorted {
                if $0.match.score != $1.match.score { return $0.match.score > $1.match.score }
                return $0.channel.stream.name.localizedStandardCompare($1.channel.stream.name) == .orderedAscending
            }.map(\.channel)
        }.value
    }
}

/// Broadcaster-first lookup from DreamCAST, with Lume's indexed EPG search below it.
struct SportFrameMatchSheet: View {
    let event: SportEvent
    let onPlay: (ResolvedChannel) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Environment(\.dismiss) private var dismiss
    @State private var broadcasters: [SportFrameBroadcaster] = []
    @State private var selectedBroadcaster: String?
    @State private var foundChannels: [ResolvedChannel] = []
    @State private var broadcasterChannels: [ResolvedChannel] = []
    @State private var searchingBroadcaster = false
    @State private var loading = true

    private var broadcasterMatches: [ResolvedChannel] {
        broadcasterChannels
    }

    private var epgMatches: [ResolvedChannel] {
        let used = Set(broadcasterMatches.map(\.id))
        return foundChannels.filter { !used.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.055, blue: 0.11).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Match channels").font(.system(size: 29, weight: .semibold)).foregroundStyle(.secondary)
                        Text("\(event.strHomeTeam ?? "Home") vs \(event.strAwayTeam ?? "Away")")
                            .font(.system(size: 39, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 16)
                    Button("Back") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }

                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Broadcasters").font(.system(size: 28, weight: .bold))
                        Text("Choose a network to search your IPTV channels.")
                            .font(.system(size: 18)).foregroundStyle(.secondary)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                if loading { ProgressView("Loading broadcasters…") }
                                else if broadcasters.isEmpty {
                                    Text("No broadcasters listed.").foregroundStyle(.secondary)
                                }
                                ForEach(broadcasters, id: \.stableID) { broadcaster in
                                    Button {
                                        selectedBroadcaster = broadcaster.name
                                    } label: {
                                        HStack(spacing: 15) {
                                            AsyncImage(url: broadcaster.logoURL) { image in image.resizable().scaledToFit() }
                                                placeholder: { Image(systemName: "tv") }
                                                .frame(width: 52, height: 36)
                                            Text(broadcaster.name).font(.system(size: 21)).lineLimit(2)
                                            Spacer(minLength: 0)
                                            if selectedBroadcaster == broadcaster.name {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan)
                                            }
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .frame(width: 440)

                    VStack(alignment: .leading, spacing: 15) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 15) {
                                if let selectedBroadcaster {
                                    Text("Channels matching \(selectedBroadcaster)")
                                        .font(.system(size: 27, weight: .bold)).lineLimit(2)
                                    if searchingBroadcaster { ProgressView("Searching IPTV channels…") }
                                    else if broadcasterMatches.isEmpty {
                                        Text("No matching network found. Check the other game matches below.").foregroundStyle(.secondary)
                                    }
                                    ForEach(broadcasterMatches) { channel in channelRow(channel) }
                                } else {
                                    Text("Select a broadcaster on the left")
                                        .font(.title3).foregroundStyle(.secondary)
                                }
                                Divider().padding(.vertical, 10)
                                Text("More matches from your IPTV guide")
                                    .font(.system(size: 27, weight: .bold)).lineLimit(2)
                                if epgMatches.isEmpty && !loading {
                                    Text("No other match-name results found.").foregroundStyle(.secondary)
                                }
                                ForEach(epgMatches) { channel in channelRow(channel) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 75)
            .padding(.vertical, 55)
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
        .task(id: selectedBroadcaster) {
            broadcasterChannels = []
            guard let selectedBroadcaster else { return }
            searchingBroadcaster = true
            let channels = await SportsZoneBroadcasterSearch.find(
                name: selectedBroadcaster, container: modelContext.container, restriction: restriction
            )
            guard !Task.isCancelled else { return }
            broadcasterChannels = channels
            searchingBroadcaster = false
        }
    }

    private func channelRow(_ channel: ResolvedChannel) -> some View {
        Button { onPlay(channel) } label: {
            HStack {
                AsyncImage(url: channel.stream.streamIcon.flatMap(URL.init(string:))) { image in image.resizable().scaledToFit() }
                    placeholder: { Image(systemName: "play.tv") }.frame(width: 60, height: 40)
                Text(channel.stream.name).font(.system(size: 21)).lineLimit(2)
                Spacer()
                Image(systemName: "play.fill")
            }
            .padding(.vertical, 7)
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
