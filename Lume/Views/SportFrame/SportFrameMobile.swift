#if os(iOS)
import SwiftData
import SwiftUI

/// Health of the API tier currently used by SportsZone. A saved premium key
/// chooses the tier, but a real API response is required to show Connected.
private enum SportsDBConnectionStatus: Equatable {
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
        case .connected: "The selected API responded with valid sports data."
        case .invalidKey: "Check your Premium key or remove it to use Free."
        case .rateLimited: "Too many requests. Try again in a minute."
        case .unavailable: "Check your internet connection and try again."
        case .unexpectedResponse: "The server responded, but the data was not valid."
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

/// Touch-first SportsZone. Reuses the exact fixture, league and IPTV search
/// services from the Apple TV SportsFrame without bringing over tvOS focus.
struct SportFrameMobile: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @StateObject private var fixtures = FixtureStore()
    @StateObject private var catalog = SportFrameCatalog()
    @AppStorage("sportFrameFollowedSportsV2") private var followedValue = "Soccer|Basketball|American Football"
    @AppStorage("sportFrameLeagueSelectionsV2") private var leaguesValue = "{}"
    @State private var page = 0
    @State private var dayOffset = 0
    @State private var selectedSport = "All Sports"
    @State private var selectedLeague = "All Leagues"
    @State private var expandedSport: String?
    @State private var selectedEvent: SportEvent?
    /// Hold the tapped channel until the match sheet has fully dismissed.
    /// This replaces a fixed delay before full-screen playback.
    @State private var pendingPlaybackMedia: PlayableMedia?
    @State private var playingMedia: PlayableMedia?
    @State private var premiumKey = ""
    @State private var keyStatus: String?
    @State private var apiConnectionStatus: SportsDBConnectionStatus = .unchecked
    @State private var apiLastChecked: Date?
    /// Incremented after Save/Remove or a manual test to cancel stale checks.
    @State private var apiCheckID = 0

    private let defaultSports = ["Soccer", "Basketball", "American Football", "Tennis",
                                 "Motorsport", "Ice Hockey", "Cricket", "Baseball", "Rugby", "Golf"]

    private var sports: [String] {
        Array(Set(defaultSports + catalog.sports)).sorted()
    }

    private var followed: [String] {
        let chosen = Set(followedValue.split(separator: "|").map(String.init))
        return sports.filter { chosen.contains($0) }
    }

    /// Read the stored choices directly. The settings editor must not lose a
    /// followed sport when the online catalog refreshes its sport list.
    private var followedSportsForLeagueEditor: [String] {
        Array(Set(followedValue.split(separator: "|").map(String.init)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var leagueChoices: [String: [String]] {
        guard let data = leaguesValue.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private var shownEvents: [SportEvent] {
        fixtures.events.filter { event in
            guard let sport = fixtures.eventSports[event.idEvent],
                  followed.contains(sport) else { return false }
            return (selectedSport == "All Sports" || selectedSport == sport)
                && (selectedLeague == "All Leagues" || selectedLeague == event.league)
                && (leagueChoices[sport]?.contains(event.league) ?? true)
        }.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var availableLeagues: [String] {
        Array(Set(fixtures.events.filter {
            selectedSport == "All Sports" || fixtures.eventSports[$0.idEvent] == selectedSport
        }.map(\.league))).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    switch page {
                    case 1: channelsPage
                    case 2: settingsPage
                    default: matchesPage
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(red: 0.025, green: 0.055, blue: 0.11).ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("SportsZone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh SportsZone")
                }
            }
            .sheet(item: $selectedEvent, onDismiss: {
                // Start playback at the earliest safe point, when the sheet
                // has finished closing. No arbitrary 350 ms timer is needed.
                guard let media = pendingPlaybackMedia else { return }
                pendingPlaybackMedia = nil
                playingMedia = media
            }) { event in
                SportFrameMobileMatchSheet(event: event, restriction: restriction) { channel in
                    guard let media = SportsPlayback.media(for: channel, in: modelContext) else { return }
                    pendingPlaybackMedia = media
                    selectedEvent = nil
                }
            }
            .fullScreenCover(item: $playingMedia) { FullScreenPlayerView(media: $0) }
        }
        .task { await catalog.refresh() }
        .task(id: "\(dayOffset)|\(followedValue)|\(SportsDBAccess.apiKey)") { await refresh() }
        .onChange(of: followedValue) { _, _ in
            if selectedSport != "All Sports" && !followed.contains(selectedSport) {
                selectedSport = "All Sports"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("SportsZone section", selection: $page) {
                Text("Sports").tag(0)
                Text("Channels").tag(1)
                Text("Settings").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("SportsZone section")
            if page == 0 {
                Picker("Day", selection: $dayOffset) {
                    Text("Yesterday").tag(-1)
                    Text("Today").tag(0)
                    Text("Tomorrow").tag(1)
                }
                .pickerStyle(.segmented)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        sportChip("All Sports")
                        ForEach(followed, id: \.self) { sport in sportChip(sport) }
                    }
                }
                .scrollIndicators(.hidden)

                Menu {
                    Button("All Leagues") { selectedLeague = "All Leagues" }
                    ForEach(availableLeagues, id: \.self) { name in
                        Button(name) { selectedLeague = name }
                    }
                } label: {
                    Label(selectedLeague, systemImage: "line.3.horizontal.decrease.circle")
                        .lineLimit(1)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private func sportChip(_ sport: String) -> some View {
        Button(sport) {
            selectedSport = sport
            selectedLeague = "All Leagues"
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(selectedSport == sport ? Color.cyan : Color.white.opacity(0.12), in: Capsule())
        .foregroundStyle(selectedSport == sport ? .black : .white)
    }

    private var matchesPage: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text("Happening now & coming up")
                .font(.headline)
                .foregroundStyle(.secondary)
            if fixtures.loading { ProgressView("Loading matches…") }
            if let error = fixtures.error { Text(error).foregroundStyle(.orange) }
            if shownEvents.isEmpty && !fixtures.loading {
                ContentUnavailableView("No Matches", systemImage: "sportscourt",
                                       description: Text("Choose more sports or another date."))
            }
            let groups = Dictionary(grouping: shownEvents, by: \.league)
            ForEach(groups.keys.sorted(), id: \.self) { league in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if let first = groups[league]?.first {
                            AsyncImage(url: catalog.badgeURL(for: league,
                                      sport: fixtures.eventSports[first.idEvent] ?? "")) {
                                $0.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "shield").foregroundStyle(.secondary)
                            }
                            .frame(width: 32, height: 32)
                        }
                        Text(league).font(.headline).lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.cyan.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))

                    ForEach(Array((groups[league] ?? []).prefix(5))) { event in
                        Button { selectedEvent = event } label: {
                            mobileFixture(event)
                        }
                        .buttonStyle(.plain)
                    }
                    if (groups[league]?.count ?? 0) > 5 {
                        Text("Showing first 5 matches")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func mobileFixture(_ event: SportEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                mobileTeam(event.strHomeTeam ?? "Home", icon: event.homeBadge)
                mobileTeam(event.strAwayTeam ?? "Away", icon: event.awayBadge)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                if let home = event.intHomeScore, let away = event.intAwayScore {
                    Text("\(home) : \(away)").font(.headline.monospacedDigit())
                } else {
                    Text(event.timeLabel).font(.subheadline.weight(.semibold))
                }
                Text(event.isLive ? "LIVE" : (event.strStatus ?? "Scheduled"))
                    .font(.caption2)
                    .foregroundStyle(event.isLive ? .green : .secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func mobileTeam(_ name: String, icon: URL?) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: icon) { $0.resizable().scaledToFit() } placeholder: {
                Image(systemName: "shield").foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)
            Text(name).font(.subheadline.weight(.medium)).lineLimit(2)
        }
    }

    private var channelsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Match channels").font(.title2.bold())
            Text("Select a match in Sports. Pick a broadcaster to search your IPTV channels. EPG match results appear below.")
                .foregroundStyle(.secondary)
            Button("Browse matches") { page = 0 }
                .buttonStyle(.borderedProminent)
        }
    }

    private var settingsPage: some View {
        // An eager outer stack keeps the sports editor and its league headers
        // in sync. Only the expanded sport creates its lazy list of leagues.
        VStack(alignment: .leading, spacing: 16) {
            sportsDBAPISettings
            Divider()

            Text("Which sports you follow").font(.title2.bold())
            HStack {
                Button("Select All") { followedValue = sports.joined(separator: "|") }
                Button("Select None") { followedValue = "" }
            }
            .buttonStyle(.bordered)

            ForEach(sports, id: \.self) { sport in
                Toggle(sport, isOn: Binding(
                    get: { followed.contains(sport) },
                    set: { enabled in
                        var selected = Set(followed)
                        if enabled { selected.insert(sport) } else { selected.remove(sport) }
                        followedValue = sports.filter { selected.contains($0) }.joined(separator: "|")
                    }
                ))
                .tint(.cyan)
            }

            Divider()
            Text("Which leagues you follow").font(.title2.bold())
            Text("Tap a followed sport to choose its leagues.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let message = catalog.message { Text(message).foregroundStyle(.orange) }

            // Use the saved set as the source of truth, not a catalog-filtered
            // array. Every checked sport, including Soccer, gets a header.
            ForEach(followedSportsForLeagueEditor, id: \.self) { sport in
                leagueEditor(for: sport)
            }

        }
    }

    private var sportsDBAPISettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("TheSportsDB API", systemImage: "network")
                    .font(.title3.weight(.bold))
                Spacer(minLength: 8)
                Text(SportsDBAccess.hasPremiumKey ? "Premium" : "Free")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.cyan.opacity(0.13), in: Capsule())
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: apiConnectionStatus.symbol)
                    .foregroundStyle(apiConnectionStatus.tint)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(apiConnectionStatus.title)
                        .font(.subheadline.weight(.semibold))
                    Text(apiConnectionStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if apiConnectionStatus == .checking {
                    ProgressView()
                }
            }

            if let apiLastChecked {
                Text("Last checked: \(apiLastChecked.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(SportsDBAccess.hasPremiumKey
                 ? "Using your saved Premium key. Live scores use the Premium API."
                 : "Using the public Free API. Add a Premium key to unlock Premium access.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("Enter Premium API key", text: $premiumKey)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Button("Save Key") {
                    if SportsDBAccess.save(premiumKey) {
                        premiumKey = ""
                        keyStatus = "Key saved. Checking Premium access."
                        apiCheckID += 1
                    } else {
                        keyStatus = "Enter a valid Premium API key."
                    }
                }
                Button("Remove Key") {
                    SportsDBAccess.remove()
                    premiumKey = ""
                    keyStatus = "Premium key removed. Using Free API."
                    apiCheckID += 1
                }
                Button("Test Connection") {
                    apiCheckID += 1
                }
                .disabled(apiConnectionStatus == .checking)
            }
            .font(.subheadline)
            .buttonStyle(.bordered)

            if let keyStatus {
                Text(keyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        // Runs when Settings opens and after changing the saved API tier.
        // Leaving this page cancels the check; no continuous polling.
        .task(id: apiCheckID) {
            await checkSportsDBConnection()
        }
    }

    @MainActor
    private func checkSportsDBConnection() async {
        apiConnectionStatus = .checking
        apiLastChecked = nil

        // v1 uses the shared Free key 123. Premium v2 accepts the private
        // API key in a header. Never place that private key in UI or logs.
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
                // Both endpoints return a list of sport records, though their
                // root keys differ. Error JSON must never count as connected.
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

    @ViewBuilder
    private func leagueEditor(for sport: String) -> some View {
        let available = catalog.leagues(for: sport)
        VStack(alignment: .leading, spacing: 12) {
            Button {
                expandedSport = expandedSport == sport ? nil : sport
            } label: {
                HStack(spacing: 12) {
                    Text(sport)
                        .font(.headline)
                    Spacer(minLength: 6)
                    if available.isEmpty {
                        Text("No leagues")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: expandedSport == sport ? "chevron.up" : "chevron.down")
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(sport) leagues")
            .accessibilityAddTraits(.isButton)

            if expandedSport == sport {
                if available.isEmpty {
                    Text("No leagues available for this sport yet. Try Refresh.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Select All") { saveLeagues(nil, for: sport) }
                        Button("Select None") { saveLeagues([], for: sport) }
                    }
                    .buttonStyle(.bordered)

                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(available) { league in
                            Toggle(league.strLeague, isOn: Binding(
                                get: { leagueChoices[sport]?.contains(league.strLeague) ?? true },
                                set: { enabled in
                                    var chosen = Set(leagueChoices[sport] ?? available.map(\.strLeague))
                                    if enabled { chosen.insert(league.strLeague) }
                                    else { chosen.remove(league.strLeague) }
                                    saveLeagues(chosen.count == available.count ? nil : chosen.sorted(), for: sport)
                                }
                            ))
                            .tint(.cyan)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func saveLeagues(_ leagues: [String]?, for sport: String) {
        var values = leagueChoices
        values[sport] = leagues
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return }
        leaguesValue = string
    }

    private func refresh() async {
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
        await fixtures.fetch(sports: followed, date: date)
    }
}

/// Broadcaster-first channel selection, followed by matches from the EPG.
/// Kept in the iOS app target so free device signing never needs a widget.
private struct SportFrameMobileBroadcaster: Decodable, Identifiable {
    let id: String?
    let strChannel: String?
    var name: String { strChannel ?? "TV Channel" }
    var stableID: String { id ?? name }
}
private struct SportFrameMobileBroadcastResponse: Decodable {
    let tvevent: [SportFrameMobileBroadcaster]?
}

private struct SportFrameMobileMatchSheet: View {
    let event: SportEvent
    let restriction: ContentRestriction
    let onPlay: (ResolvedChannel) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var broadcasters: [SportFrameMobileBroadcaster] = []
    @State private var selectedBroadcaster: String?
    @State private var matchingBroadcasterChannels: [ResolvedChannel] = []
    @State private var epgChannels: [ResolvedChannel] = []
    @State private var loading = true
    @State private var searching = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("\(event.strHomeTeam ?? "Home") vs \(event.strAwayTeam ?? "Away")")
                        .font(.title3.bold())
                    Text("Broadcasters").font(.headline)
                    Text("Choose a listed network to search your IPTV channels.")
                        .font(.caption).foregroundStyle(.secondary)
                    if loading { ProgressView("Finding matches…") }
                    if broadcasters.isEmpty && !loading {
                        Text("No broadcasters listed.").foregroundStyle(.secondary)
                    }
                    ForEach(broadcasters, id: \.stableID) { broadcaster in
                        Button {
                            selectedBroadcaster = broadcaster.name
                        } label: {
                            HStack {
                                Image(systemName: "tv")
                                Text(broadcaster.name)
                                Spacer()
                                if selectedBroadcaster == broadcaster.name {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    if let selectedBroadcaster {
                        Text("Channels matching \(selectedBroadcaster)").font(.headline)
                        if searching { ProgressView("Searching IPTV channels…") }
                        if matchingBroadcasterChannels.isEmpty && !searching {
                            Text("No matching IPTV channel.").foregroundStyle(.secondary)
                        }
                        ForEach(matchingBroadcasterChannels) { channel in channelRow(channel) }
                    }
                    Divider()
                    Text("More matches from your IPTV guide").font(.headline)
                    let used = Set(matchingBroadcasterChannels.map(\.id))
                    ForEach(epgChannels.filter { !used.contains($0.id) }) { channel in
                        channelRow(channel)
                    }
                }
                .padding()
            }
            .navigationTitle("Match channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: event.idEvent) {
            loading = true
            if let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookuptv.php?id=\(event.idEvent)"),
               let (data, _) = try? await URLSession.shared.data(from: url) {
                broadcasters = (try? JSONDecoder().decode(
                    SportFrameMobileBroadcastResponse.self, from: data).tvevent) ?? []
            }
            let fixture = makeFixture()
            let matches = await SportsChannelResolver.resolve(
                container: modelContext.container,
                fixtures: [fixture], now: .now, restriction: restriction
            )
            if Task.isCancelled { return }
            epgChannels = matches[fixture.id] ?? []
            loading = false
        }
        .task(id: selectedBroadcaster) {
            matchingBroadcasterChannels = []
            guard let selectedBroadcaster else { return }
            searching = true
            let container = modelContext.container
            let restriction = restriction
            let needle = SportsMatcher.normalize(selectedBroadcaster)
            let channels = await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                let descriptor = SportsChannelResolver.candidateStreamDescriptor(restriction: restriction)
                let streams = (try? context.fetch(descriptor)) ?? []
                return streams.compactMap { stream -> ResolvedChannel? in
                    let name = SportsMatcher.normalize(stream.name)
                    guard !needle.isEmpty, name.contains(needle),
                          let playlistID = UUID(uuidString: String(stream.id.prefix(36))) else { return nil }
                    return ResolvedChannel(
                        stream: ResolvedStreamSummary(id: stream.id, name: stream.name,
                            streamIcon: stream.streamIcon, epgChannelId: stream.epgChannelId),
                        playlistID: playlistID,
                        matchedTitle: nil, matchedStart: nil,
                        score: name == needle ? 100 : 50,
                        source: .channelName, isConfident: false
                    )
                }
                .sorted { $0.score > $1.score }
            }.value
            if Task.isCancelled { return }
            matchingBroadcasterChannels = channels
            searching = false
        }
    }

    private func channelRow(_ channel: ResolvedChannel) -> some View {
        Button { onPlay(channel) } label: {
            HStack(spacing: 10) {
                AsyncImage(url: channel.stream.streamIcon.flatMap(URL.init(string:))) {
                    $0.resizable().scaledToFit()
                } placeholder: { Image(systemName: "tv") }
                .frame(width: 42, height: 32)
                Text(channel.stream.name).font(.subheadline).lineLimit(2)
                Spacer()
                Image(systemName: "play.fill")
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
    }

    private func makeFixture() -> SportsFixture {
        let leagueID = "sportsdb:\(event.idLeague ?? "unknown")"
        func competitor(_ name: String?, badge: URL?, score: String?) -> SportsCompetitor? {
            guard let name else { return nil }
            let team = SportsTeam(leagueId: leagueID,
                                 teamId: ChannelMatcher.normalize(name),
                                 name: name, shortName: name,
                                 abbreviation: String(name.prefix(3)), logoURL: badge)
            return SportsCompetitor(team: team, score: score.flatMap(Int.init))
        }
        return SportsFixture(
            id: "sportsdb:\(event.idEvent)", leagueId: leagueID,
            leagueName: event.league, leagueAbbreviation: event.league,
            startDate: event.startDate ?? .now,
            status: SportsFixtureStatus(state: event.isLive ? .inProgress : .scheduled,
                                        detail: event.strStatus ?? ""),
            home: competitor(event.strHomeTeam, badge: event.homeBadge, score: event.intHomeScore),
            away: competitor(event.strAwayTeam, badge: event.awayBadge, score: event.intAwayScore),
            broadcasters: broadcasters.map(\.name), name: event.name
        )
    }
}
#endif
